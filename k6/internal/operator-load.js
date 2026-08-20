import exec from 'k6/execution';
import http from 'k6/http';
import {SharedArray} from 'k6/data';
import {Counter, Rate, Trend} from 'k6/metrics';

import {buildRegisteredRequest} from './request-builders.js';

function required(value,label){if(value===undefined||value===null||String(value)==='')throw new Error(`${label} is required`);return String(value);}

const phase = String(__ENV.PHASE || 'measure');
const rps = Number(__ENV.RPS || 50);
const duration = String(__ENV.DURATION || '30s');
const baseUrl = String(__ENV.BASE_URL || '');
const seed = Number(__ENV.RUN_SEED || 1) >>> 0;
const vuMultiplier = Number(__ENV.VU_MULTIPLIER || 6);
const maximumVUs = Math.max(50, Math.ceil(rps * vuMultiplier));
const localDate = String(__ENV.LOCAL_DATE || new Date().toISOString().slice(0, 10));
const logicalEpochMs = Number(__ENV.LOGICAL_EPOCH_MS || 0);
const runId = String(__ENV.RUN_ID || 'missing-run-id');
const repeat = Number(__ENV.REPEAT_INDEX || 1);
const logicalBase = Number(__ENV.STEP_LOGICAL_BASE || 0);
const logicalSpan = Number(__ENV.STEP_LOGICAL_SPAN || 0);

const identities = new SharedArray('capacity identities', () => {
  const lines = open(__ENV.IDENTITY_PATH).trim().split('\n').map(line => JSON.parse(line));
  const meta = lines.shift();
  if (meta?.schemaVersion !== 'capacity-identities-v1' || meta?.runId !== runId) throw new Error('identity file does not match this run');
  const identities = lines.filter(row => row.type === 'identity');
  if (identities.length !== 10_000 || identities.some(row => !row.userId || !row.token || !Array.isArray(row.activeRaceIds) || row.activeRaceIds.length < 1 || row.activeRaceIds.length > 5)) {
    throw new Error('identity file contains an invalid identity');
  }
  return identities;
});
const statusContexts = new SharedArray('capacity status contexts', () => {
  const rows=open(__ENV.IDENTITY_PATH).trim().split('\n').map(line => JSON.parse(line)).filter(row => row.type === 'statusContext');
  if(rows.length!==16||rows.some(row=>!row.userId||!row.token||!row.resolutionJobId||!Number.isInteger(Number(row.resolutionGeneration))))throw new Error('identity file contains invalid status contexts');
  return rows;
});
if (!Number.isSafeInteger(logicalBase) || logicalBase < 1 || !Number.isSafeInteger(logicalSpan) || logicalSpan < 1) throw new Error('operator did not provide a valid monotonic logical window');

const mix = JSON.parse(open(__ENV.MIX_PATH));
const registry = JSON.parse(open(__ENV.REGISTRY_PATH));
if (registry.schemaVersion !== 'stepv2-capacity-route-registry-v1') throw new Error('unsupported route registry');
const weighted = Object.entries(mix.weights).filter(([, weight]) => Number(weight) > 0);
const totalWeight = weighted.reduce((sum, [, weight]) => sum + Number(weight), 0);
if (!weighted.length || Math.abs(totalWeight - 1) > 0.001) throw new Error('route weights must sum to one');
const registryByKey = Object.fromEntries(registry.routes.map(route => [route.key, route]));
if (weighted.some(([key]) => !registryByKey[key] || registryByKey[key].requestBuilder !== key || !Array.isArray(registryByKey[key].acceptedStatuses))) throw new Error('route mix contains an invalid registered request builder');

const failures = new Rate('capacity_failures');
const authFailures = new Counter('auth_failures');
const acceptedRequests = new Counter('accepted_requests');
const rejectedRequests = new Counter('rejected_requests');
const timedOutRequests = new Counter('timed_out_requests');
const routeCounts = Object.fromEntries(weighted.map(([key]) => [key, new Counter(`route_count_${key}`)]));
const routeFailures = Object.fromEntries(weighted.map(([key]) => [key, new Rate(`route_failure_${key}`)]));
const routeDurations = Object.fromEntries(weighted.map(([key]) => [key, new Trend(`route_duration_${key}`, true)]));

export const options = {
  scenarios: {
    production_mix: {
      executor: 'constant-arrival-rate', rate: rps, timeUnit: '1s', duration,
      preAllocatedVUs: Math.max(50, Math.ceil(rps * 2.5)),
      maxVUs: maximumVUs,
      gracefulStop: '15s', exec: 'hit', tags: {phase},
    },
  },
  thresholds: phase === 'measure' ? {capacity_failures: ['rate<0.01'], auth_failures: ['count==0'], dropped_iterations: ['count==0']} : {},
  discardResponseBodies: true,
  maxRedirects: 0,
  summaryTrendStats: ['count','avg','p(50)','p(95)','p(99)','max'],
};

function hash(value) {
  let result = (0x811c9dc5 ^ seed) >>> 0;
  for (const character of String(value)) {
    result ^= character.charCodeAt(0);
    result = Math.imul(result, 0x01000193) >>> 0;
  }
  return result >>> 0;
}

function selectedRoute(iteration) {
  let target = (hash(`route:${iteration}`) % 1_000_000) / 1_000_000 * totalWeight;
  for (const [key, weight] of weighted) {
    target -= Number(weight);
    if (target < 0) return registryByKey[key];
  }
  const key=weighted[weighted.length - 1][0];
  return registryByKey[key];
}

function context(route, iteration) {
  const userIndex = route.method === 'POST' ? iteration % identities.length : hash(`identity:${route.key}:${iteration}`) % identities.length;
  const workloadUser = identities[userIndex];
  const user = route.key === 'race_resolution' ? statusContexts[hash(`status:${iteration}`) % statusContexts.length] : workloadUser;
  if (!user) throw new Error('route requires an unavailable identity context');
  const raceId = workloadUser.activeRaceIds[hash(`race:${route.key}:${iteration}`) % workloadUser.activeRaceIds.length];
  return {
    baseUrl, user, raceId,
    resolutionJob: route.key === 'race_resolution' ? {
      jobId: user.resolutionJobId || '00000000-0000-4000-8000-000000000000',
      generation: Number(user.resolutionGeneration || 1),
    } : null,
    localDate, logicalEpochMs,
    client: {
      appVersion: required(__ENV.APP_VERSION,'APP_VERSION'), platform: required(__ENV.PLATFORM,'PLATFORM'),
      clientFeatures: required(__ENV.CLIENT_FEATURES,'CLIENT_FEATURES'),
      userAgent: required(__ENV.USER_AGENT,'USER_AGENT'), timezone: required(__ENV.TIMEZONE,'TIMEZONE'),
      releaseChannel: required(__ENV.RELEASE_CHANNEL,'RELEASE_CHANNEL'),
    },
    runId, repeat, phase, iteration,
    writeOrdinal: repeat * 1_000_000_000 + iteration, userIndex,
  };
}

function monotonicBody(route, selected) {
  const cycle = Math.floor(selected.iteration / identities.length);
  if (cycle >= logicalSpan) throw new Error('stage exceeded its preallocated monotonic logical window');
  const logical = logicalBase + cycle;
  const totalSteps = 100_000 + logical * 100;
  const sampleSteps = 20 + logical;
  const sample = minutesBefore => {
    const bucketEnd = logicalEpochMs - minutesBefore * 60_000;
    return {periodStart:new Date(bucketEnd-300_000).toISOString(),periodEnd:new Date(bucketEnd).toISOString(),steps:sampleSteps,sourceName:'k6-capacity-operator'};
  };
  if(route.key==='steps_post')return JSON.stringify({date:localDate,steps:totalSteps});
  if(route.key==='steps_samples')return JSON.stringify({samples:[sample(12),sample(17)]});
  if(route.key==='steps_sync_v2')return JSON.stringify({date:localDate,steps:totalSteps,samples:[sample(7),sample(12),sample(17)]});
  return null;
}

export function hit() {
  const iteration = exec.scenario.iterationInTest;
  const route = selectedRoute(iteration);
  const selected = context(route, iteration);
  const request = buildRegisteredRequest(route, selected);
  if(route.method==='POST')request.body=monotonicBody(route,selected);
  const response = request.method === 'POST'
    ? http.post(request.url, request.body, request.params)
    : http.get(request.url, request.params);
  const accepted = request.acceptedStatuses.includes(response.status);
  routeCounts[route.key].add(1, {phase, endpoint: route.key});
  routeFailures[route.key].add(!accepted, {phase, endpoint: route.key});
  routeDurations[route.key].add(response.timings.duration, {phase, endpoint: route.key});
  failures.add(!accepted, {phase, endpoint: route.key});
  authFailures.add(response.status === 401 || response.status === 403 ? 1 : 0, {phase, endpoint: route.key});
  acceptedRequests.add(accepted ? 1 : 0, {phase, endpoint: route.key});
  rejectedRequests.add(!accepted && response.status !== 0 ? 1 : 0, {phase, endpoint: route.key});
  timedOutRequests.add(response.status === 0 ? 1 : 0, {phase, endpoint: route.key});
}

function metric(data, name) {
  return data.metrics?.[name]?.values || {};
}

function count(data, name) {
  const value = Number(metric(data, name).count || 0);
  return Number.isFinite(value) ? value : 0;
}

export function handleSummary(data) {
  const requests = count(data, 'http_reqs');
  const dropped = count(data, 'dropped_iterations');
  const durationSeconds = Number(__ENV.DURATION_SECONDS || 1);
  const routes = Object.fromEntries(weighted.map(([key]) => [key, {
    count: count(data, `route_count_${key}`),
    failureRate: Number(metric(data, `route_failure_${key}`).rate || 0),
    p50Ms: Number(metric(data, `route_duration_${key}`)['p(50)'] || 0),
    p95Ms: Number(metric(data, `route_duration_${key}`)['p(95)'] || 0),
    p99Ms: Number(metric(data, `route_duration_${key}`)['p(99)'] || 0),
  }]));
  const httpDuration = metric(data, 'http_req_duration');
  const result = {
    schemaVersion: 'stepv2-k6-stage-summary-v1', phase, offeredRps: rps,
    requests, completedIterations: count(data, 'iterations'), dropped,
    accepted: count(data, 'accepted_requests'), rejected: count(data, 'rejected_requests'),
    timedOut: count(data, 'timed_out_requests'),
    achievedRps: requests / durationSeconds,
    failureRate: Number(metric(data, 'capacity_failures').rate || 0),
    peakActiveVUs: Number(metric(data,'vus').max || metric(data,'vus').value || 0), configuredMaxVUs: maximumVUs,
    authFailures: count(data, 'auth_failures'),
    p50Ms: Number(httpDuration['p(50)'] || 0), p95Ms: Number(httpDuration['p(95)'] || 0),
    p99Ms: Number(httpDuration['p(99)'] || 0), maxMs: Number(httpDuration.max || 0), routes,
  };
  return {[__ENV.SUMMARY_PATH]: `${JSON.stringify(result, null, 2)}\n`};
}
