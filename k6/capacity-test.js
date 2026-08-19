import exec from 'k6/execution';
import http from 'k6/http';
import {SharedArray} from 'k6/data';
import {Counter, Rate, Trend} from 'k6/metrics';

import {
  PROFILE,
  buildIterationContext,
  buildRequest,
  k6ArrivalDuration,
  parseTarget,
  routeForSlot,
  selectWorkload,
  validateFixture,
  vuAllocation,
} from './capacity-contract.mjs';

const phase = String(__ENV.PHASE || 'measure');
const smoke = __ENV.COMMAND === 'smoke';
const baseUrl = parseTarget(__ENV.BASE_URL, {allowNonprod: __ENV.ALLOW_NONPROD_TARGET === '1'}).origin;
const fixturePath = String(__ENV.FIXTURE_PATH || './fixture.json');
const fixtureDocument = JSON.parse(open(fixturePath));
validateFixture(fixtureDocument, {corpusId: __ENV.CORPUS_ID});
const fixtures = new SharedArray('capacity fixture', () => [fixtureDocument]);
const fixture = fixtures[0];
const rps = Number(__ENV.RPS || 1);
const durationSeconds = Number(__ENV.PHASE_DURATION_SECONDS || 1);
const plannedRequests = Number(__ENV.PLANNED_REQUESTS || (smoke && phase === 'measure' ? PROFILE.routes.length : rps * durationSeconds));
const runSeed = Number(__ENV.RUN_SEED || 0);
const writeOrdinalBase = Number(__ENV.WRITE_ORDINAL_BASE || 0);
const allocation = vuAllocation(rps);
const client = {
  appVersion: String(__ENV.APP_VERSION || ''), platform: String(__ENV.PLATFORM || ''),
  clientFeatures: String(__ENV.CLIENT_FEATURES || ''), userAgent: String(__ENV.USER_AGENT || ''),
  timezone: String(__ENV.TIMEZONE || ''), releaseChannel: String(__ENV.RELEASE_CHANNEL || ''),
};
const statusContexts = __ENV.STATUS_CONTEXT_PATH ? new SharedArray('resolution status contexts', () => JSON.parse(open(__ENV.STATUS_CONTEXT_PATH))) : [];
const workload = selectWorkload(fixture, Number(__ENV.WORKLOAD_USER_COUNT), {
  plannedMeasurementWriteSlots: Number(__ENV.PLANNED_MEASURE_WRITE_SLOTS || plannedRequests), seed: runSeed,
  verifiedQueue: __ENV.VERIFIED_QUEUE === '1' && phase === 'measure',
});

const capacityFailures = new Rate('capacity_failures');
const rateLimited = new Rate('rate_limited');
const criticalWriteDuration = new Trend('critical_write_duration', true);
const contextFallback = new Counter('context_fallback');
const authFailures = new Counter('auth_failures');
const runtimeFailures = new Counter('runtime_failures');
const endpointCounters = Object.fromEntries(PROFILE.routes.map(route => [route.key, new Counter(`endpoint_${route.key}`)]));

function thresholds() {
  if (phase !== 'measure') return {};
  const filters = '{phase:measure}';
  const values = {
    [`capacity_failures${filters}`]: ['rate<0.01'],
    [`rate_limited${filters}`]: ['rate<0.01'],
    [`context_fallback${filters}`]: ['count==0'],
    [`auth_failures${filters}`]: ['count==0'],
    [`runtime_failures${filters}`]: ['count==0'],
    dropped_iterations: ['count==0'],
  };
  if (!smoke) {
    values['http_req_duration{phase:measure}'] = ['p(95)<2000', 'p(99)<5000'];
    values['critical_write_duration{phase:measure}'] = ['p(95)<2000', 'p(99)<5000', 'max<15000'];
  }
  for (const route of PROFILE.routes) values[`endpoint_${route.key}${filters}`] = ['count>0'];
  return values;
}

function scenario() {
  if (smoke) {
    return {executor: 'shared-iterations', vus: 1, iterations: plannedRequests, maxDuration: '5m', exec: 'hitApi', gracefulStop: '15s', tags: {phase}};
  }
  return {executor: 'constant-arrival-rate', rate: rps, timeUnit: '1s', duration: k6ArrivalDuration(durationSeconds),
    preAllocatedVUs: allocation.preAllocatedVUs, maxVUs: allocation.maxVUs, exec: 'hitApi', gracefulStop: '15s', tags: {phase}};
}

export const options = {
  scenarios: {traffic: scenario()},
  thresholds: thresholds(),
  maxRedirects: 0,
  discardResponseBodies: false,
  summaryTrendStats: ['count','avg','p(50)','p(95)','p(99)','max'],
};

function requestContext(route, iteration) {
  const selected = buildIterationContext({route, iteration, runSeed, writeOrdinalBase, workload, fixture,
    statusContexts, baseUrl, localDate: __ENV.LOCAL_DATE, logicalEpochMs: Number(__ENV.LOGICAL_EPOCH_MS),
    client, runId: __ENV.RUN_ID, repeat: __ENV.REPEAT_INDEX, phase});
  if (selected.contextFallback) contextFallback.add(1, {phase, endpoint: route.key});
  else contextFallback.add(0, {phase, endpoint: route.key});
  return selected.context;
}

export function hitApi() {
  const iteration = exec.scenario.iterationInTest;
  const route = smoke && phase === 'measure' ? PROFILE.routes[iteration] : routeForSlot(iteration, runSeed);
  const request = buildRequest(route, requestContext(route, iteration));
  const response = request.method === 'POST'
    ? http.post(request.url, request.body, request.params)
    : http.get(request.url, request.params);
  endpointCounters[route.key].add(1, {phase, endpoint: route.key});
  const accepted = request.acceptedStatuses.includes(response.status);
  const authFailure = response.status === 401 || response.status === 403;
  const failed = !accepted;
  capacityFailures.add(failed, {phase, endpoint: route.key, status: String(response.status)});
  rateLimited.add(response.status === 429, {phase, endpoint: route.key});
  authFailures.add(authFailure ? 1 : 0, {phase, endpoint: route.key});
  runtimeFailures.add(response.status === 0 ? 1 : 0, {phase, endpoint: route.key});
  if (route.criticalWrite) criticalWriteDuration.add(response.timings.duration, {phase, endpoint: route.key});
}

function values(data, name) {
  return data.metrics?.[name]?.values || {};
}

function count(data, name) {
  const value = Number(values(data, name).count);
  return Number.isFinite(value) ? value : 0;
}

export function handleSummary(data) {
  const completed = count(data, 'iterations');
  const dropped = count(data, 'dropped_iterations');
  const http = values(data, 'http_req_duration');
  const critical = values(data, 'critical_write_duration');
  const summary = {
    complete: true,
    plannedMeasure: plannedRequests,
    completedMeasure: completed,
    dropped,
    failureRate: Number(values(data, 'capacity_failures').rate || 0),
    rateLimitedRate: Number(values(data, 'rate_limited').rate || 0),
    httpP95Ms: Number(http['p(95)'] || 0),
    httpP99Ms: Number(http['p(99)'] || 0),
    httpMaxMs: Number(http.max || 0),
    criticalWriteP95Ms: Number(critical['p(95)'] || 0),
    criticalWriteP99Ms: Number(critical['p(99)'] || 0),
    criticalWriteMaxMs: Number(critical.max || 0),
    contextFallbacks: count(data, 'context_fallback'),
    endpointCounts: Object.fromEntries(PROFILE.routes.map(route => [route.key, count(data, `endpoint_${route.key}`)])),
    postcheckSuccesses: Number(__ENV.POSTCHECK_SUCCESSES || 0),
    postcheckFailures: Number(__ENV.POSTCHECK_FAILURES || 0),
    authFailures: count(data, 'auth_failures'),
    runtimeFailures: count(data, 'runtime_failures'),
    generatorWarnings: [],
  };
  return {[__ENV.SUMMARY_PATH || 'capacity-summary.json']: `${JSON.stringify(summary, null, 2)}\n`};
}
