/**
 * Capacity harness for the released client request mix.
 *
 * This script is staging-only. It uses a fixed arrival rate, status-aware
 * fixtures, exact released-client headers, tagged metrics, and executable
 * gates. See k6/README.md before running it.
 */

import exec from "k6/execution";
import { sleep } from "k6";
import http from "k6/http";
import { SharedArray } from "k6/data";
import { Counter, Gauge, Rate, Trend } from "k6/metrics";

import {
  ENDPOINTS,
  HARNESS_SCHEMA_VERSION,
  RELEASED_CLIENT_COHORTS,
  RUNG_DEFINITIONS,
  buildActivationEvent,
  buildThresholds,
  classifyCapacityRun,
  classifyResponse,
  resolutionStateDisposition,
  validateFixture,
} from "./harness-contract.mjs";

const BASE_URL = String(
  __ENV.BASE_URL || "https://staging.steptracker-api.org",
).replace(/\/+$/, "");
const FIXTURE_FILE = __ENV.USERS_FILE || "./users.json";
const CLIENT_COHORT = __ENV.CLIENT_COHORT || "ios_bara_2_3_7_ads_payout";
const MODE = __ENV.MODE || "capacity";
const TARGET_RUNG = __ENV.TARGET_RUNG || "rate_15rps";
const RUN_ID = String(__ENV.RUN_ID || "").trim();
const REPEAT_INDEX = String(__ENV.REPEAT_INDEX || "").trim();
const cohort = RELEASED_CLIENT_COHORTS[CLIENT_COHORT];
const rung = RUNG_DEFINITIONS[TARGET_RUNG];
const capacityRun = MODE === "capacity"
  ? classifyCapacityRun(
      __ENV.DURATION_OVERRIDE,
      __ENV.ALLOW_DIAGNOSTIC_OVERRIDE === "1",
      BASE_URL,
    )
  : { capacityCandidate: false, diagnosticReason: "smoke" };

if (!RUN_ID) throw new Error("RUN_ID is required");
if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(RUN_ID)) {
  throw new Error("RUN_ID must match [A-Za-z0-9][A-Za-z0-9._-]{0,63}");
}
if (!REPEAT_INDEX) throw new Error("REPEAT_INDEX is required");
if (MODE === "capacity" && !["1", "2", "3"].includes(REPEAT_INDEX)) {
  throw new Error("capacity REPEAT_INDEX must be 1, 2, or 3");
}

const requiredCapacityInputs = {
  backendRevision: __ENV.BACKEND_REVISION,
  flags: __ENV.BACKEND_FLAGS,
  config: __ENV.BACKEND_CONFIG,
  workerCount: __ENV.WORKER_COUNT,
  pgBouncerPool: __ENV.PGBOUNCER_POOL,
  redisState: __ENV.REDIS_STATE,
  cronCohort: __ENV.CRON_COHORT,
};
if (MODE === "capacity") {
  for (const [label, value] of Object.entries(requiredCapacityInputs)) {
    if (!String(value || "").trim() || String(value).trim().toUpperCase() === "UNRECORDED") {
      throw new Error(`${label} is required and cannot be UNRECORDED`);
    }
  }
}

const identityTags = Object.freeze({
  run_id: RUN_ID,
  repeat_index: REPEAT_INDEX,
  client_cohort: CLIENT_COHORT,
});

if (!cohort) {
  throw new Error(
    `unknown CLIENT_COHORT=${CLIENT_COHORT}; choose ${Object.keys(RELEASED_CLIENT_COHORTS).join(", ")}`,
  );
}
if (MODE !== "capacity" && MODE !== "smoke") {
  throw new Error("MODE must be capacity or smoke");
}
if (MODE === "capacity" && !rung) {
  throw new Error(
    `unknown TARGET_RUNG=${TARGET_RUNG}; choose ${Object.keys(RUNG_DEFINITIONS).join(", ")}`,
  );
}

const fixtureDocument = JSON.parse(open(FIXTURE_FILE));
const users = new SharedArray("capacity fixture users", () =>
  Array.isArray(fixtureDocument.users) ? fixtureDocument.users : [],
);

const allUsers = [];
const activeContexts = [];
const activeOrPendingContexts = [];
for (const user of users) {
  allUsers.push({ user, race: null, raceStatus: "none", job: null });
  for (const race of user.activeRaces || []) {
    const context = { user, race, raceStatus: "active", job: null };
    activeContexts.push(context);
    activeOrPendingContexts.push(context);
  }
  for (const race of user.pendingRaces || []) {
    activeOrPendingContexts.push({
      user,
      race,
      raceStatus: "pending",
      job: null,
    });
  }
}

const totalWeight = ENDPOINTS.reduce((sum, endpoint) => sum + endpoint.w, 0);
const cumulativeWeights = [];
let runningWeight = 0;
for (const endpoint of ENDPOINTS) {
  runningWeight += endpoint.w;
  cumulativeWeights.push(runningWeight);
}

const selectedEndpointCount = new Counter("selected_endpoint_count");
const executedEndpointCount = new Counter("executed_endpoint_count");
const contextFallbackCount = new Counter("context_fallback_count");
const responseStatusCount = new Counter("response_status_count");
const successfulResponseCount = new Counter("successful_response_count");
const expectedChallenge404Count = new Counter("expected_challenge_404_count");
const capacityFailureCount = new Counter("capacity_failure_count");
const hardFailureCount = new Counter("hard_failure_count");
const rateLimitCount = new Counter("rate_limit_429_count");
const capacityFailureRate = new Rate("capacity_failure_rate");
const hardFailureRate = new Rate("hard_failure_rate");
const endpointDuration = new Trend("endpoint_duration_ms", true);
const persistenceCriticalDuration = new Trend(
  "persistence_critical_duration_ms",
  true,
);
const resolutionLag = new Trend("resolution_lag_ms", true);
const resolutionLagSampleCount = new Counter("resolution_lag_sample_count");
const resolutionStateCount = new Counter("resolution_state_count");
const finalResolutionOutstanding = new Gauge("final_resolution_outstanding");
const endpointAccountingCounters = Object.fromEntries(
  ENDPOINTS.map((endpoint) => [
    endpoint.key,
    {
      selected: new Counter(`summary_endpoint_${endpoint.key}_selected_count`),
      executed: new Counter(`summary_endpoint_${endpoint.key}_executed_count`),
      durationSamples: new Counter(
        `summary_endpoint_${endpoint.key}_duration_sample_count`,
      ),
      statusTotal: new Counter(`summary_endpoint_${endpoint.key}_status_count`),
    },
  ]),
);
const resolutionStateSummaryCounters = Object.fromEntries(
  ["queued", "running", "succeeded", "failed", "superseded", "missing", "malformed"].map(
    (state) => [state, new Counter(`resolution_state_${state}_count`)],
  ),
);
const summarizedStatusCodes = [
  "0",
  "200",
  "201",
  "202",
  "204",
  "304",
  "400",
  "401",
  "403",
  "404",
  "408",
  "409",
  "429",
  "500",
  "502",
  "503",
  "504",
];
const statusSummaryCounters = Object.fromEntries(
  [...summarizedStatusCodes, "other"].map((status) => [
    status,
    new Counter(`response_status_code_${status}_count`),
  ]),
);

function smokeThresholds() {
  const thresholds = {
    capacity_failure_rate: ["rate==0"],
    context_fallback_count: ["count==0"],
    resolution_lag_sample_count: ["count>0"],
    final_resolution_outstanding: ["value==0"],
    resolution_state_failed_count: ["count==0"],
    resolution_state_superseded_count: ["count==0"],
  };
  for (const endpoint of ENDPOINTS) {
    thresholds[`selected_endpoint_count{endpoint:${endpoint.key}}`] = ["count>0"];
    thresholds[`executed_endpoint_count{endpoint:${endpoint.key}}`] = ["count>0"];
  }
  return thresholds;
}

function buildScenarios() {
  if (MODE === "smoke") {
    return {
      deterministic_smoke: {
        executor: "shared-iterations",
        vus: 1,
        iterations: ENDPOINTS.length,
        maxDuration: __ENV.DURATION_OVERRIDE || "5m",
        exec: "hitApi",
        tags: { rung: "smoke", mode: "smoke", ...identityTags },
      },
    };
  }
  return {
    [TARGET_RUNG]: {
      executor: "constant-arrival-rate",
      rate: rung.rate,
      timeUnit: "1s",
      duration: __ENV.DURATION_OVERRIDE || rung.duration,
      preAllocatedVUs: Math.max(50, rung.rate * 4),
      maxVUs: Math.max(200, rung.rate * 20),
      exec: "hitApi",
      tags: { rung: TARGET_RUNG, mode: "capacity", ...identityTags },
      gracefulStop: "30s",
    },
  };
}

export const options = {
  scenarios: buildScenarios(),
  thresholds:
    MODE === "smoke" ? smokeThresholds() : buildThresholds([TARGET_RUNG]),
  discardResponseBodies: true,
  noConnectionReuse: false,
  summaryTrendStats: ["count", "avg", "p(50)", "p(95)", "p(99)", "max"],
};

export function setup() {
  const validation = validateFixture(fixtureDocument);
  if (!validation.ok) {
    throw new Error(`invalid capacity fixture:\n- ${validation.errors.join("\n- ")}`);
  }
  const hostname = BASE_URL
    .replace(/^https?:\/\//, "")
    .split(/[/:]/, 1)[0]
    .toLowerCase();
  const safeHost =
    hostname === "staging.steptracker-api.org" ||
    hostname === "localhost" ||
    hostname === "127.0.0.1";
  if (!safeHost) {
    throw new Error(`refusing capacity traffic to non-staging host: ${hostname}`);
  }
  const resolutionContexts = fixtureDocument.resolutionSeeds.map((seed) => {
    const idempotencyKey = randomUuid();
    const response = http.post(
      `${BASE_URL}/steps/sync-v2`,
      JSON.stringify(bodyFor("steps_sync_v2")),
      {
        headers: requestHeaders(seed.token, idempotencyKey),
        tags: {
          name: "resolution_seed_sync",
          phase: "setup",
          client_cohort: CLIENT_COHORT,
          run_id: RUN_ID,
          repeat_index: REPEAT_INDEX,
        },
        timeout: "30s",
        responseType: "text",
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw new Error(
        `resolution seed sync failed for dedicated user (${response.status})`,
      );
    }
    let parsed;
    try {
      parsed = JSON.parse(response.body || "");
    } catch (_) {
      throw new Error("resolution seed sync returned malformed JSON");
    }
    const job = parsed && parsed.raceResolution;
    if (
      !job ||
      typeof job.jobId !== "string" ||
      !job.jobId ||
      !Number.isInteger(job.generation) ||
      job.generation < 1
    ) {
      throw new Error("resolution seed sync returned no current job generation");
    }
    return {
      user: { userId: seed.userId, token: seed.token },
      race: null,
      raceStatus: "active",
      job: {
        id: job.jobId,
        generation: job.generation,
        requestedAt: job.requestedAt || null,
      },
    };
  });
  return {
    fixtureRevision: fixtureDocument.metadata.fixtureRevision,
    clientCohort: CLIENT_COHORT,
    resolutionContexts,
  };
}

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

function randomUuid() {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (char) => {
    const value = Math.floor(Math.random() * 16);
    return (char === "x" ? value : (value & 0x3) | 0x8).toString(16);
  });
}

function bodyFor(endpointKey) {
  switch (endpointKey) {
    case "steps_post":
      return { date: isoDate(), steps: randomInt(500, 14000) };
    case "steps_samples":
      return { samples: [makeSample(12), makeSample(17)] };
    case "steps_sync_v2":
      return {
        date: isoDate(),
        steps: randomInt(500, 14000),
        samples: [makeSample(7), makeSample(12), makeSample(17)],
      };
    case "activation_events":
      return {
        events: [
          buildActivationEvent({
            id: randomUuid(),
            now: new Date(),
            appVersion: cohort.appVersion,
            platform: cohort.platform,
          }),
        ],
      };
    default:
      return {};
  }
}

function pickEndpoint() {
  if (MODE === "smoke") {
    return ENDPOINTS[exec.scenario.iterationInTest % ENDPOINTS.length];
  }
  const roll = Math.random() * totalWeight;
  let low = 0;
  let high = cumulativeWeights.length - 1;
  while (low < high) {
    const middle = (low + high) >> 1;
    if (roll < cumulativeWeights[middle]) high = middle;
    else low = middle + 1;
  }
  return ENDPOINTS[low];
}

function poolFor(context, setupData) {
  switch (context) {
    case "none":
      return allUsers;
    case "active_race":
      return activeContexts;
    case "active_or_pending_race":
      return activeOrPendingContexts;
    case "seeded_resolution_job":
      return setupData.resolutionContexts;
    default:
      return [];
  }
}

function contextTags(context) {
  const race = context.race;
  return {
    race_status: context.raceStatus,
    race_mode: race ? (race.isTeamRace ? "team" : "solo") : "none",
    roster_size_stratum: race ? race.rosterSizeStratum : "none",
  };
}

function recordResolutionLag(response, extraTags = {}) {
  const resolutionTags = { ...identityTags, ...extraTags };
  let parsed;
  try {
    parsed = JSON.parse(response.body || "");
  } catch (_) {
    resolutionStateCount.add(1, { state: "malformed", ...resolutionTags });
    resolutionStateSummaryCounters.malformed.add(1, resolutionTags);
    return;
  }
  const status = parsed && parsed.raceResolution;
  const state = status && typeof status.state === "string"
    ? status.state.toLowerCase()
    : "missing";
  resolutionStateCount.add(1, { state, ...resolutionTags });
  const stateSummary = resolutionStateSummaryCounters[state] || resolutionStateSummaryCounters.missing;
  stateSummary.add(1, resolutionTags);
  if (state !== "failed") resolutionStateSummaryCounters.failed.add(0, resolutionTags);
  if (state !== "superseded") {
    resolutionStateSummaryCounters.superseded.add(0, resolutionTags);
  }
  if (resolutionStateDisposition(state) === "abort") {
    exec.test.abort(
      `resolution seed ${status?.jobId || "unknown"} became SUPERSEDED; isolated seed stability is invalid`,
    );
  }
  const requestedAt = Date.parse(status && status.requestedAt);
  const completedAt = Date.parse(status && status.completedAt);
  if (!Number.isFinite(requestedAt)) return;
  if (Number.isFinite(completedAt)) {
    resolutionLag.add(Math.max(0, completedAt - requestedAt), resolutionTags);
    resolutionLagSampleCount.add(1, resolutionTags);
  } else if (state === "queued" || state === "running") {
    resolutionLag.add(Math.max(0, Date.now() - requestedAt), resolutionTags);
    resolutionLagSampleCount.add(1, resolutionTags);
  }
}

function requestHeaders(token, idempotencyKey = null) {
  return {
    "Content-Type": "application/json",
    Accept: "application/json",
    Authorization: `Bearer ${token}`,
    "X-App-Version": cohort.appVersion,
    "X-Client-Features": cohort.features,
    "User-Agent": cohort.userAgent,
    "X-Capacity-Run-Id": RUN_ID,
    "X-Capacity-Repeat": REPEAT_INDEX,
    ...(idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {}),
  };
}

export function hitApi(setupData) {
  const selected = pickEndpoint();
  selectedEndpointCount.add(1, {
    endpoint: selected.key,
    ...identityTags,
  });
  endpointAccountingCounters[selected.key].selected.add(1, identityTags);

  const candidates = poolFor(selected.context, setupData);
  let executed = selected;
  let context;
  if (candidates.length === 0) {
    contextFallbackCount.add(1, {
      endpoint: selected.key,
      reason: `missing_${selected.context}`,
      ...identityTags,
    });
    executed = ENDPOINTS.find((endpoint) => endpoint.key === "races_list");
    context = allUsers[randomInt(0, allUsers.length - 1)];
  } else {
    contextFallbackCount.add(0, {
      endpoint: selected.key,
      reason: "none",
      ...identityTags,
    });
    context = candidates[randomInt(0, candidates.length - 1)];
  }
  executedEndpointCount.add(1, {
    endpoint: executed.key,
    ...identityTags,
  });
  endpointAccountingCounters[executed.key].executed.add(1, identityTags);

  const idempotencyKey = randomUuid();
  const tags = {
    name: executed.key,
    endpoint: executed.key,
    selected_endpoint: selected.key,
    executed_endpoint: executed.key,
    ...identityTags,
    ...contextTags(context),
  };
  const headers = requestHeaders(
    context.user.token,
    executed.key === "steps_sync_v2" ? idempotencyKey : null,
  );
  const raceId = context.race ? context.race.id : null;
  const url = `${BASE_URL}${executed.path(raceId, context.job)}`;
  const params = {
    headers,
    tags,
    timeout: "30s",
    responseType: executed.key === "race_resolution" ? "text" : "none",
  };
  const response = executed.method === "POST"
    ? http.post(url, JSON.stringify(bodyFor(executed.key)), params)
    : http.get(url, params);

  const classification = classifyResponse(executed.key, response.status);
  const metricTags = {
    endpoint: executed.key,
    status: String(response.status),
    ...identityTags,
    ...contextTags(context),
  };
  responseStatusCount.add(1, metricTags);
  endpointAccountingCounters[executed.key].statusTotal.add(1, identityTags);
  const statusKey = summarizedStatusCodes.includes(String(response.status))
    ? String(response.status)
    : "other";
  statusSummaryCounters[statusKey].add(1, {
    endpoint: executed.key,
    ...identityTags,
  });
  successfulResponseCount.add(
    response.status >= 200 && response.status < 300 ? 1 : 0,
    metricTags,
  );
  expectedChallenge404Count.add(
    executed.key === "challenges_current" && response.status === 404 ? 1 : 0,
    metricTags,
  );
  capacityFailureCount.add(classification.capacityFailure ? 1 : 0, metricTags);
  hardFailureCount.add(classification.hardFailure ? 1 : 0, metricTags);
  rateLimitCount.add(classification.rateLimited ? 1 : 0, metricTags);
  capacityFailureRate.add(classification.capacityFailure ? 1 : 0, metricTags);
  hardFailureRate.add(classification.hardFailure ? 1 : 0, metricTags);
  endpointDuration.add(response.timings.duration, metricTags);
  endpointAccountingCounters[executed.key].durationSamples.add(1, identityTags);
  if (executed.critical) {
    persistenceCriticalDuration.add(response.timings.duration, metricTags);
  }
  if (executed.key === "race_resolution" && response.status >= 200 && response.status < 300) {
    recordResolutionLag(response);
  }
}

function fetchResolutionStatus(context, phase) {
  const response = http.get(
    `${BASE_URL}/steps/race-resolution/${context.job.id}?generation=${context.job.generation}`,
    {
      headers: requestHeaders(context.user.token),
      tags: {
        name: "race_resolution_drain",
        endpoint: "race_resolution",
        phase,
        ...identityTags,
      },
      timeout: "30s",
      responseType: "text",
    },
  );
  if (response.status < 200 || response.status >= 300) return "http_failure";
  recordResolutionLag(response, {
    rung: MODE === "smoke" ? "smoke" : TARGET_RUNG,
    phase,
    client_cohort: CLIENT_COHORT,
    run_id: RUN_ID,
    repeat_index: REPEAT_INDEX,
  });
  try {
    const parsed = JSON.parse(response.body || "");
    return String(parsed?.raceResolution?.state || "missing").toLowerCase();
  } catch (_) {
    return "malformed";
  }
}

export function teardown(setupData) {
  const deadline = Date.now() + Number(__ENV.RESOLUTION_DRAIN_TIMEOUT_MS || 15000);
  const terminal = new Set(["succeeded", "failed"]);
  const pending = setupData.resolutionContexts.slice();
  while (pending.length > 0 && Date.now() < deadline) {
    for (let index = pending.length - 1; index >= 0; index -= 1) {
      if (terminal.has(fetchResolutionStatus(pending[index], "drain"))) {
        pending.splice(index, 1);
      }
    }
    if (pending.length > 0) sleep(0.25);
  }
  finalResolutionOutstanding.add(pending.length, {
    rung: MODE === "smoke" ? "smoke" : TARGET_RUNG,
    ...identityTags,
  });
}

function metricValues(data, name) {
  return data.metrics[name] ? data.metrics[name].values : null;
}

function metricCount(data, name) {
  const values = metricValues(data, name);
  return values && Number.isFinite(values.count) ? values.count : null;
}

function thresholdResults(data) {
  const results = {};
  for (const [metricName, metric] of Object.entries(data.metrics)) {
    if (!metric.thresholds) continue;
    results[metricName] = Object.fromEntries(
      Object.entries(metric.thresholds).map(([expression, result]) => [
        expression,
        result.ok === true,
      ]),
    );
  }
  return results;
}

export function handleSummary(data) {
  const rungName = MODE === "smoke" ? "smoke" : TARGET_RUNG;
  const summary = {
    schemaVersion: HARNESS_SCHEMA_VERSION,
    generatedAt: new Date().toISOString(),
    inputs: {
      baseUrl: BASE_URL,
      mode: MODE,
      claimable: false,
      capacityCandidate: capacityRun.capacityCandidate,
      claimability: capacityRun.capacityCandidate
        ? "pending_three_repeat_aggregation_and_server_telemetry_evidence"
        : "diagnostic_only",
      diagnosticReason: capacityRun.diagnosticReason,
      offeredRateRps: MODE === "smoke" ? null : rung.rate,
      rung: rungName,
      duration: __ENV.DURATION_OVERRIDE || (MODE === "smoke" ? null : rung.duration),
      clientCohort: CLIENT_COHORT,
      client: cohort,
      fixture: fixtureDocument.metadata,
      ...requiredCapacityInputs,
      runId: RUN_ID,
      repeatIndex: REPEAT_INDEX,
    },
    totals: {
      requests: metricValues(data, "http_reqs"),
      duration: metricValues(data, "http_req_duration"),
      droppedArrivals: metricValues(data, "dropped_iterations"),
      capacityFailureRate: metricValues(data, "capacity_failure_rate"),
      capacityFailures: metricValues(data, "capacity_failure_count"),
      hardFailureRate: metricValues(data, "hard_failure_rate"),
      hardFailures: metricValues(data, "hard_failure_count"),
      rateLimited429: metricValues(data, "rate_limit_429_count"),
      expectedChallenge404: metricValues(data, "expected_challenge_404_count"),
      contextFallbacks: metricValues(data, "context_fallback_count"),
      persistenceCriticalDuration: metricValues(
        data,
        "persistence_critical_duration_ms",
      ),
      resolutionLag: metricValues(data, "resolution_lag_ms"),
      resolutionLagSamples: metricValues(data, "resolution_lag_sample_count"),
      finalResolutionOutstanding: metricValues(
        data,
        "final_resolution_outstanding",
      ),
      resolutionStates: Object.fromEntries(
        Object.keys(resolutionStateSummaryCounters).map((state) => [
          state,
          metricValues(data, `resolution_state_${state}_count`),
        ]),
      ),
      statusCodes: Object.fromEntries(
        [...summarizedStatusCodes, "other"].map((status) => [
          status,
          metricValues(data, `response_status_code_${status}_count`),
        ]),
      ),
    },
    endpointAccounting: Object.fromEntries(
      ENDPOINTS.map((endpoint) => {
        const prefix = `summary_endpoint_${endpoint.key}`;
        return [
          endpoint.key,
          {
            selected: metricCount(data, `${prefix}_selected_count`),
            executed: metricCount(data, `${prefix}_executed_count`),
            durationSamples: metricCount(data, `${prefix}_duration_sample_count`),
            statusTotal: metricCount(data, `${prefix}_status_count`),
          },
        ];
      }),
    ),
    thresholds: thresholdResults(data),
    aggregateRequired: "A claim requires aggregate-capacity-cohort.mjs over exactly three matched summary/raw/server-telemetry evidence triples. Endpoint accounting and conditional p95 are cohort gates.",
    taggedRawOutput: "Use --out json=<path>; relevant samples carry run_id, repeat_index, endpoint, exact status, resolution state, rung, race_status, race_mode, roster_size_stratum, and client_cohort tags.",
  };
  const json = `${JSON.stringify(summary, null, 2)}\n`;
  const destinations = { stdout: json };
  if (__ENV.SUMMARY_JSON) destinations[__ENV.SUMMARY_JSON] = json;
  return destinations;
}
