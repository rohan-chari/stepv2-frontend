/**
 * Staging load test weighted to the ACTUAL prod request mix.
 *
 * Differences from `staging-load-test.js`, and why they matter:
 *
 *  1. Endpoint weights come from 24h of real nginx logs (2026-08-16), not from
 *     guesswork. The old script gave /health an 18% weight (prod: ~0%) and
 *     never touched /races/:id/messages (prod: 28% of all requests) or
 *     /home/race-card (prod: 30% of all server time). Load shaped that wrongly
 *     measures nothing useful.
 *
 *  2. `constant-arrival-rate` instead of `ramping-vus`. With ramping VUs, each
 *     VU waits for its own response, so offered load *falls* as the server
 *     slows — the test politely backs off exactly when you need it to push.
 *     Arrival rate holds the offered rps flat and lets the queue build, which
 *     is what a real user population does.
 *
 *  3. Every iteration picks a different one of N pre-minted user identities
 *     (see mint-staging-users.js) instead of reusing the reviewer account, so
 *     writes hit distinct rows and reads miss the cache realistically.
 *
 * Each scenario is one rung of the DAU ladder, using the measured conversion
 * of 0.0122 peak rps per DAU (467 req/DAU/day x 2.26 peak-to-mean factor).
 *
 *   k6 run k6/prod-mix-load-test.js
 *   TARGET_ONLY=dau_5000 k6 run k6/prod-mix-load-test.js   # single rung
 */

import http from "k6/http";
import { SharedArray } from "k6/data";
import { Rate, Trend } from "k6/metrics";

const BASE_URL = String(
  __ENV.BASE_URL || "https://staging.steptracker-api.org",
).replace(/\/+$/, "");

const CLIENT_FEATURES =
  "characters,ads,jammer,spinpowerups,team_races,tournaments,race_leave," +
  "powerups2,powerups3,powerups4,powerups5,stealth_runner_duration," +
  "hitchhike_effective_steps,remote_assets,remote_asset_preferred," +
  "next_race_cta,discoverable_identity,home_suggested_races," +
  "seeded_race_buckets,home_invite_modal,race_participants_paging," +
  "race_preview,race_payout_double";

const users = new SharedArray("users", () =>
  JSON.parse(open(__ENV.USERS_FILE || "./users.json")),
);

/**
 * Weights are raw 24h request counts from prod nginx logs, so the mix is
 * exactly proportional to reality. `/challenges/current` is entered at its
 * organic 13,400 rather than its logged 17,421 — the difference was a single
 * device stuck retrying a 404, which is a client bug, not user load.
 */
const ENDPOINTS = [
  { key: "race_messages",      w: 39207, m: "GET",  p: (u, r) => `/races/${r}/messages?limit=50` },
  { key: "challenges_current", w: 13400, m: "GET",  p: () => "/challenges/current" },
  { key: "assets_manifest",    w: 12993, m: "GET",  p: () => "/assets/manifest" },
  // Takes a resolution JOB id, not a race id. The app gets one back from
  // /steps/sync-v2 and then polls it, so this pulls from jobs this run created.
  { key: "race_resolution",    w: 10812, m: "GET",  p: () => `/steps/race-resolution/${takeJobId()}`, needsJob: true },
  { key: "steps_post",         w: 10462, m: "POST", p: () => "/steps",           b: stepsBody },
  { key: "races_list",         w:  9937, m: "GET",  p: () => "/races" },
  { key: "steps_samples",      w:  8648, m: "POST", p: () => "/steps/samples",   b: samplesBody },
  { key: "race_progress",      w:  8286, m: "GET",  p: (u, r) => `/races/${r}/progress` },
  { key: "message_streams",    w:  7718, m: "GET",  p: (u, r) => `/races/${r}/message-streams` },
  { key: "auth_me",            w:  7337, m: "GET",  p: () => "/auth/me" },
  { key: "powerups_inventory", w:  7297, m: "GET",  p: () => "/powerups/inventory" },
  { key: "steps_sync_v2",      w:  7294, m: "POST", p: () => "/steps/sync-v2",   b: syncBody, h: idempotencyHeader },
  { key: "home_race_card",     w:  6591, m: "GET",  p: () => "/home/race-card" },
  { key: "version_policy",     w:  6143, m: "GET",  p: () => "/app-version/policy" },
  { key: "powerups_catalog",   w:  5814, m: "GET",  p: () => "/powerups/catalog" },
  { key: "suggested_races",    w:  5778, m: "GET",  p: () => "/home/suggested-races" },
  { key: "friends_steps",      w:  4929, m: "GET",  p: () => "/friends/steps" },
  { key: "invite_preflight",   w:  4720, m: "GET",  p: () => "/races/invite-preflight" },
  { key: "activation_events",  w:  4257, m: "POST", p: () => "/analytics/activation-events", b: activationBody },
  { key: "chat_read",          w:  3467, m: "POST", p: (u, r) => `/races/${r}/chat/read`, b: () => ({}) },
  { key: "discovery_summary",  w:  3444, m: "GET",  p: () => "/races/discovery-summary" },
  { key: "auth_session",       w:  3188, m: "GET",  p: () => "/auth/session" },
  { key: "friends_list",       w:  2139, m: "GET",  p: () => "/friends" },
  { key: "shop_catalog",       w:  2135, m: "GET",  p: () => "/shop/catalog" },
  { key: "race_detail",        w:  1944, m: "GET",  p: (u, r) => `/races/${r}?view=participants-v1` },
  { key: "race_bootstrap",     w:  1517, m: "GET",  p: (u, r) => `/races/${r}/bootstrap` },
];

// Prefix sums once at init, so endpoint selection is a binary search per
// iteration rather than a linear scan over 26 entries.
const CUMULATIVE = [];
let running = 0;
for (const e of ENDPOINTS) {
  running += e.w;
  CUMULATIVE.push(running);
}
const TOTAL_WEIGHT = running;

const RACELESS_FALLBACK = ENDPOINTS.find((e) => e.key === "races_list");

/**
 * Resolution job ids harvested from this VU's own /steps/sync-v2 responses.
 * Bounded so a long run cannot grow it without limit.
 */
const jobIds = [];
const JOB_POOL_MAX = 200;

function rememberJobId(id) {
  if (!id) return;
  if (jobIds.length >= JOB_POOL_MAX) jobIds.shift();
  jobIds.push(id);
}

function takeJobId() {
  return jobIds[Math.floor(Math.random() * jobIds.length)];
}

const failureRate = new Rate("hard_failure_rate");
const unauthorizedRate = new Rate("unauthorized_rate");
const serverTime = new Trend("server_time_ms", true);

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function isoDate() {
  return new Date().toISOString().split("T")[0];
}

function makeSample(minuteOffset) {
  const end = new Date(Date.now() - minuteOffset * 60 * 1000);
  const start = new Date(end.getTime() - 5 * 60 * 1000);
  return {
    periodStart: start.toISOString(),
    periodEnd: end.toISOString(),
    steps: randomInt(20, 140),
    sourceName: "k6-prod-mix",
  };
}

function stepsBody() {
  return { date: isoDate(), steps: randomInt(500, 14000) };
}

function samplesBody() {
  return { samples: [makeSample(12), makeSample(17)] };
}

function syncBody() {
  return {
    date: isoDate(),
    steps: randomInt(500, 14000),
    samples: [makeSample(7), makeSample(12), makeSample(17)],
  };
}

function activationBody() {
  return { events: [{ name: "app_open", occurredAt: new Date().toISOString() }] };
}

function idempotencyHeader() {
  return { "Idempotency-Key": `k6-${__VU}-${__ITER}-${Math.random().toString(16).slice(2)}` };
}

function pickEndpoint() {
  const roll = Math.random() * TOTAL_WEIGHT;
  let lo = 0;
  let hi = CUMULATIVE.length - 1;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (roll < CUMULATIVE[mid]) hi = mid;
    else lo = mid + 1;
  }
  return ENDPOINTS[lo];
}

const LADDER_RUNGS = [
  { name: "dau_1250", rate: 15,  duration: "3m", start: "0s" },
  { name: "dau_2500", rate: 31,  duration: "3m", start: "3m30s" },
  { name: "dau_5000", rate: 61,  duration: "4m", start: "7m" },
  { name: "dau_10000", rate: 122, duration: "3m", start: "11m30s" },
  { name: "dau_20000", rate: 244, duration: "3m", start: "15m" },
];

/**
 * FAST=1: skip the low rungs entirely and jump straight to the interesting
 * ones, one minute each. The gaps are 20s so that in-flight requests from the
 * previous rung (30s timeout, 30s gracefulStop) drain before the next starts
 * and don't contaminate its numbers. ~3m40s total.
 *
 * The dau_10000 rung carries an ABORTING threshold: if it is drowning in 5xx
 * there is nothing to learn from dau_20000, so the run stops instead.
 */
const FAST_RUNGS = [
  { name: "dau_5000",  rate: 61,  duration: "1m", start: "0s" },
  { name: "dau_10000", rate: 122, duration: "1m", start: "1m20s" },
  { name: "dau_20000", rate: 244, duration: "1m", start: "2m40s" },
];

const FAST = __ENV.FAST === "1";
const RUNGS = FAST ? FAST_RUNGS : LADDER_RUNGS;

function buildScenarios() {
  const only = __ENV.TARGET_ONLY;
  const scenarios = {};
  for (const rung of RUNGS) {
    if (only && rung.name !== only) continue;
    scenarios[rung.name] = {
      executor: "constant-arrival-rate",
      rate: rung.rate,
      timeUnit: "1s",
      duration: __ENV.DURATION_OVERRIDE || rung.duration,
      startTime: only ? "0s" : rung.start,
      // Headroom so k6 itself is never the limiter: at 244 rps with a 4s
      // response the run needs ~1000 concurrent VUs.
      preAllocatedVUs: Math.max(50, rung.rate * 4),
      maxVUs: Math.max(200, rung.rate * 20),
      exec: "hitApi",
      tags: { rung: rung.name },
      gracefulStop: "30s",
    };
  }
  return scenarios;
}

export const options = {
  scenarios: buildScenarios(),
  // The ladder observes the whole breakdown, so nothing aborts. FAST mode
  // stops after dau_10000 when that rung is already drowning in 5xx — pushing
  // on to dau_20000 would only re-measure a box that has fallen over.
  thresholds: {
    "hard_failure_rate{rung:dau_5000}": [
      { threshold: "rate<0.01", abortOnFail: false },
    ],
    "http_req_duration{rung:dau_5000}": [
      { threshold: "p(95)<2000", abortOnFail: false },
    ],
    ...(FAST
      ? {
          "hard_failure_rate{rung:dau_10000}": [
            {
              threshold: `rate<${__ENV.ABORT_5XX_RATE || 0.25}`,
              abortOnFail: true,
              // Let the rung accumulate a real sample before judging it;
              // the first seconds are cold-connection noise.
              delayAbortEval: "30s",
            },
          ],
        }
      : {}),
  },
  discardResponseBodies: true,
  noConnectionReuse: false,
};

export function hitApi() {
  const user = users[randomInt(0, users.length - 1)];
  const endpoint = pickEndpoint();

  // Endpoints that need a race id fall back to the races list for users who
  // happen to have none, rather than firing a request at `/races/undefined`.
  const raceId = user.raceIds.length
    ? user.raceIds[randomInt(0, user.raceIds.length - 1)]
    : null;
  // Fall back to the races list rather than firing at `/races/undefined` when
  // the picked endpoint needs context this VU does not have yet.
  const needsRace = endpoint.p.length > 1;
  const missingContext =
    (needsRace && !raceId) || (endpoint.needsJob && jobIds.length === 0);
  const active = missingContext ? RACELESS_FALLBACK : endpoint;

  const headers = {
    "Content-Type": "application/json",
    Accept: "application/json",
    Authorization: `Bearer ${user.token}`,
    "X-App-Version": "2.3.7",
    "X-Client-Features": CLIENT_FEATURES,
    "User-Agent": "Bara/2.3.7 CFNetwork/3860.700.1 Darwin/25.6.0",
    ...(active.h ? active.h() : {}),
  };

  const url = `${BASE_URL}${active.p(user, raceId)}`;
  const params = {
    headers,
    tags: { name: active.key },
    timeout: "30s",
    // The sync response is the only one whose body we need (for the job id it
    // hands back); everything else stays discarded to keep k6 cheap.
    responseType: active.key === "steps_sync_v2" ? "text" : "none",
  };

  const response =
    active.m === "POST"
      ? http.post(url, JSON.stringify(active.b ? active.b() : {}), params)
      : http.get(url, params);

  if (active.key === "steps_sync_v2" && response.status < 300) {
    try {
      const parsed = JSON.parse(response.body);
      rememberJobId(parsed?.raceResolution?.jobId);
    } catch (_) {
      // A malformed body is not what this test is measuring.
    }
  }

  const broken = response.status === 0 || response.status >= 500;
  failureRate.add(broken ? 1 : 0);
  unauthorizedRate.add(
    response.status === 401 || response.status === 403 ? 1 : 0,
  );
  if (!broken) serverTime.add(response.timings.duration);
}
