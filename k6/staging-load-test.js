import http from 'k6/http';
import { sleep } from 'k6';
import { Rate } from 'k6/metrics';

const BASE_URL = (String(__ENV.BASE_URL || 'https://staging.steptracker-api.org')).replace(/\/+$/, '');
const IDENTITY_TOKEN = String(__ENV.IDENTITY_TOKEN || '').trim();
const WATCHDOG_URL = `${BASE_URL}/app-version/policy`;

function envInt(name, fallback) {
  const value = Number(__ENV[name]);
  return Number.isFinite(value) ? value : fallback;
}

function envFloat(name, fallback) {
  const value = Number(__ENV[name]);
  return Number.isFinite(value) ? value : fallback;
}

const START_VUS = envInt('START_VUS', 2);
const STAGE_1_TARGET = envInt('STAGE_1_TARGET', 12);
const STAGE_2_TARGET = envInt('STAGE_2_TARGET', 40);
const STAGE_3_TARGET = envInt('STAGE_3_TARGET', 150);

const STAGE_1_DURATION = String(__ENV.STAGE_1_DURATION || '30s');
const STAGE_2_DURATION = String(__ENV.STAGE_2_DURATION || '2m');
const STAGE_3_DURATION = String(__ENV.STAGE_3_DURATION || '4m');
const STAGE_4_DURATION = String(__ENV.STAGE_4_DURATION || '2m');
const STAGE_5_DURATION = String(__ENV.STAGE_5_DURATION || '1m');

const THINK_SECONDS = envFloat('THINK_SECONDS', 0.2);
const WATCHDOG_EVERY_ITER = envInt('WATCHDOG_EVERY_ITER', 20);

const BASELINE_POLICY_MS = envInt('WATCHDOG_BASELINE_MS', 0);
const WATCHDOG_P95_BUDGET_MS = envInt(
  'WATCHDOG_P95_BUDGET_MS',
  BASELINE_POLICY_MS > 0 ? BASELINE_POLICY_MS * 8 : 500,
);
const API_P95_BUDGET_MS = envInt('API_P95_BUDGET_MS', 3000);
const HARD_FAILURE_RATE_BUDGET = envFloat('HARD_FAILURE_RATE_BUDGET', 0.02);
const AUTH_UNAUTH_RATE_BUDGET = envFloat('AUTH_UNAUTH_RATE_BUDGET', 0.60);

const hardRequestFailureRate = new Rate('hard_request_failure_rate');
const authUnauthorizedRate = new Rate('auth_unauthorized_rate');

const endpointDefinitions = [
  {
    key: 'health',
    authRequired: false,
    weight: 18,
    method: 'GET',
    path: () => '/health',
  },
  {
    key: 'policy_poll',
    authRequired: false,
    weight: 6,
    method: 'GET',
    path: () => '/app-version/policy',
  },
  {
    key: 'home_race_card',
    authRequired: true,
    weight: 18,
    method: 'GET',
    path: () => '/home/race-card',
  },
  {
    key: 'auth_me',
    authRequired: true,
    weight: 12,
    method: 'GET',
    path: () => '/auth/me',
  },
  {
    key: 'races_list',
    authRequired: true,
    weight: 14,
    method: 'GET',
    path: () => '/races',
  },
  {
    key: 'friends_steps',
    authRequired: true,
    weight: 10,
    method: 'GET',
    path: () => '/friends/steps',
  },
  {
    key: 'races_progress',
    authRequired: true,
    weight: 8,
    method: 'GET',
    path: (seed) => {
      const raceId = pickRaceId(seed.raceIds);
      return raceId ? `/races/${raceId}/progress` : '/races';
    },
  },
  {
    key: 'shop_catalog',
    authRequired: false,
    weight: 8,
    method: 'GET',
    path: () => '/shop/catalog',
  },
  {
    key: 'powerup_catalog',
    authRequired: false,
    weight: 3,
    method: 'GET',
    path: () => '/powerups/catalog',
  },
  {
    key: 'steps_sync_v2',
    authRequired: true,
    weight: 6,
    method: 'POST',
    body: () => ({
      date: isoDate(),
      steps: randomInt(500, 1400),
      samples: [
        makeSample(7),
        makeSample(10),
      ],
    }),
    buildHeaders: () => ({
      'Idempotency-Key': randomIdempotencyKey(),
    }),
    path: () => '/steps/sync-v2',
  },
  {
    key: 'steps_samples',
    authRequired: true,
    weight: 3,
    method: 'POST',
    body: () => ({
      samples: [makeSample(12)],
    }),
    path: () => '/steps/samples',
  },
  {
    key: 'steps',
    authRequired: true,
    weight: 4,
    method: 'POST',
    body: () => ({
      date: isoDate(),
      steps: randomInt(500, 1400),
    }),
    path: () => '/steps',
  },
];

const totalWeight = Object.freeze({
  auth: endpointDefinitions.filter((entry) => entry.authRequired).reduce((sum, entry) => sum + entry.weight, 0),
  noAuth: endpointDefinitions.filter((entry) => !entry.authRequired).reduce((sum, entry) => sum + entry.weight, 0),
});

function pickRaceId(raceIds) {
  if (!raceIds.length) {
    return '';
  }
  return raceIds[Math.floor(Math.random() * raceIds.length)];
}

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function isoDate() {
  return new Date().toISOString().split('T')[0];
}

function makeSample(minuteOffset) {
  const end = new Date(Date.now() - minuteOffset * 60 * 1000);
  const start = new Date(end.getTime() - 10 * 60 * 1000);
  return {
    periodStart: start.toISOString(),
    periodEnd: end.toISOString(),
    steps: randomInt(20, 140),
    sourceName: 'k6-load',
  };
}

function randomIdempotencyKey() {
  return `${Date.now()}-${Math.random().toString(16).slice(2)}-${__VU}`;
}

function pickEndpoint(hasAuth) {
  const candidates = endpointDefinitions.filter((entry) => !entry.authRequired || hasAuth);
  const maxWeight = candidates.reduce((sum, entry) => sum + entry.weight, 0);
  const roll = Math.random() * maxWeight;
  let cursor = 0;
  for (const entry of candidates) {
    cursor += entry.weight;
    if (roll < cursor) {
      return entry;
    }
  }
  return candidates[candidates.length - 1];
}

function extractRaceIds(rawBody) {
  if (!rawBody) {
    return [];
  }
  let parsed;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return [];
  }

  const races = Array.isArray(parsed)
    ? parsed
    : Array.isArray(parsed?.races)
      ? parsed.races
      : Array.isArray(parsed?.data?.races)
        ? parsed.data.races
        : Array.isArray(parsed?.data)
          ? parsed.data
          : [];

  return races
    .map((entry) => entry?.id || entry?.raceId || entry?.uuid)
    .filter((value) => typeof value === 'string' && value.length > 0)
    .slice(0, 30);
}

function authHeaders() {
  if (!IDENTITY_TOKEN) {
    return {};
  }
  return {
    Authorization: `Bearer ${IDENTITY_TOKEN}`,
  };
}

function baseRequestHeaders() {
  return {
    'Content-Type': 'application/json',
    Accept: 'application/json',
    'User-Agent': 'k6-steps-tracker-arch-load/1.0',
    ...authHeaders(),
  };
}

function buildAndSend(endpoint, state) {
  const headers = { ...baseRequestHeaders(), ...(endpoint.buildHeaders ? endpoint.buildHeaders() : {}) };
  const url = `${BASE_URL}${endpoint.path(state)}`;
  const tags = {
    endpoint: endpoint.key === 'policy_poll' ? 'policy_watchdog' : 'api_workload',
    request: endpoint.key,
  };

  if (endpoint.method === 'POST') {
    const payload = endpoint.body ? JSON.stringify(endpoint.body()) : '{}';
    const response = http.post(url, payload, {
      headers,
      tags,
    });
    recordFailure(response);
    return response;
  }

  const response = http.get(url, {
    headers,
    tags,
  });
  recordFailure(response);
  return response;
}

function recordFailure(response) {
  hardRequestFailureRate.add(response.status === 0 || response.status >= 500 ? 1 : 0);
  if (response.status === 401 || response.status === 403) {
    authUnauthorizedRate.add(1);
  } else {
    authUnauthorizedRate.add(0);
  }
}

function runWatchdog() {
  const response = http.get(WATCHDOG_URL, {
    tags: {
      endpoint: 'policy_watchdog',
      request: 'policy_watchdog',
    },
  });
  recordFailure(response);
}

function sanitizeNumber(value) {
  return Number.isFinite(value) ? value : 0;
}

function printSummaryState(state) {
  if (__ITER === 0 && __VU === 1) {
    console.log(`Load test target: ${state.hasAuth ? 'Authenticated' : 'Public'} path`);
    console.log(`Race ids available: ${state.raceIds.length}`);
    console.log(`Auth-required candidate weight: ${sanitizeNumber(totalWeight.auth)}`);
    console.log(`Public candidate weight: ${sanitizeNumber(totalWeight.noAuth)}`);
    console.log(`Watchdog cadence: every ${WATCHDOG_EVERY_ITER} iterations`);
    console.log(`Watchdog p95 budget: ${WATCHDOG_P95_BUDGET_MS}ms`);
  }
}

export const options = {
  scenarios: {
    architecture_load_ramp: {
      executor: 'ramping-vus',
      startVUs: START_VUS,
      stages: [
        { duration: STAGE_1_DURATION, target: STAGE_1_TARGET },
        { duration: STAGE_2_DURATION, target: STAGE_2_TARGET },
        { duration: STAGE_3_DURATION, target: STAGE_3_TARGET },
        { duration: STAGE_4_DURATION, target: STAGE_3_TARGET },
        { duration: STAGE_5_DURATION, target: 0 },
      ],
      gracefulStop: '30s',
    },
  },
  thresholds: {
    'http_req_duration{endpoint:api_workload}': [`p(95)<${API_P95_BUDGET_MS}`],
    'http_req_duration{endpoint:policy_watchdog}': [`p(95)<${WATCHDOG_P95_BUDGET_MS}`],
    hard_request_failure_rate: [`rate<${HARD_FAILURE_RATE_BUDGET}`],
    auth_unauthorized_rate: [`rate<${AUTH_UNAUTH_RATE_BUDGET}`],
  },
};

export function setup() {
  const state = {
    hasAuth: false,
    raceIds: [],
  };

  if (!IDENTITY_TOKEN) {
    console.log('No IDENTITY_TOKEN set. Running unauthenticated mix only.');
    return state;
  }

  const authCheck = http.get(`${BASE_URL}/auth/me`, { headers: baseRequestHeaders() });
  if (authCheck.status >= 200 && authCheck.status < 300) {
    state.hasAuth = true;
    console.log('AUTH accepted. Authenticated endpoint set enabled for load mix.');
  } else {
    console.log(`AUTH not accepted (status ${authCheck.status}). Running unauthenticated mix only.`);
    return state;
  }

  const raceSeed = http.get(`${BASE_URL}/races`, {
    headers: baseRequestHeaders(),
    tags: { endpoint: 'setup' },
  });
  if (raceSeed.status >= 200 && raceSeed.status < 300) {
    state.raceIds = extractRaceIds(raceSeed.body);
  }

  return state;
}

export default function (state) {
  printSummaryState(state);
  const endpoint = pickEndpoint(state.hasAuth);
  buildAndSend(endpoint, state);

  if (__ITER % WATCHDOG_EVERY_ITER === 0) {
    runWatchdog();
  }

  sleep(Math.max(0.0, THINK_SECONDS));
}
