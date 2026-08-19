#!/usr/bin/env node

import {performance} from 'node:perf_hooks';
import {createRequire} from 'node:module';
import {chmodSync, existsSync, readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

import {
  PROFILE,
  buildRequest,
  buildResult,
  classifyHttpSummary,
  classifyQueueEvidence,
  commandPlan,
  computeCommandDeadline,
  countWriteSlots,
  expectedSyncReservationsMax,
  measuredWriteStats,
  parseTarget,
  profileHash,
  schedulerAccountingComplete,
  selectWorkload,
  validateAggregateRuns,
  validateFixture,
  validateLogicalEpochMs,
  vuAllocation,
} from './capacity-contract.mjs';

export const SAMPLE_INTERVAL_SECONDS = 10;
export const STATEMENT_TIMEOUT_MS = 2000;

export const SERVICE_QUERY = `SELECT
  COUNT(*) FILTER (WHERE state='queued')::int AS "queued",
  COUNT(*) FILTER (WHERE state='running')::int AS "running",
  COUNT(*) FILTER (WHERE
    (state='queued' AND (retry_at IS NULL OR retry_at <= (to_timestamp($1 / 1000.0) AT TIME ZONE 'UTC'))
      AND (not_before_at IS NULL OR not_before_at <= (to_timestamp($1 / 1000.0) AT TIME ZONE 'UTC')))
    OR (state='running' AND lease_expires_at IS NOT NULL AND lease_expires_at <= (to_timestamp($1 / 1000.0) AT TIME ZONE 'UTC'))
  )::int AS "claimable",
  GREATEST(0, COALESCE(MAX(EXTRACT(EPOCH FROM ((to_timestamp($1 / 1000.0) AT TIME ZONE 'UTC')-requested_at))*1000), 0))::float8 AS "oldestRequestAgeMs",
  GREATEST(0, COALESCE(MAX(EXTRACT(EPOCH FROM ((to_timestamp($1 / 1000.0) AT TIME ZONE 'UTC')-requested_at))*1000) FILTER (WHERE
    (state='queued' AND (retry_at IS NULL OR retry_at <= (to_timestamp($1 / 1000.0) AT TIME ZONE 'UTC'))
      AND (not_before_at IS NULL OR not_before_at <= (to_timestamp($1 / 1000.0) AT TIME ZONE 'UTC')))
    OR (state='running' AND lease_expires_at IS NOT NULL AND lease_expires_at <= (to_timestamp($1 / 1000.0) AT TIME ZONE 'UTC'))
  ), 0))::float8 AS "oldestClaimableAgeMs"
FROM race_resolution_jobs_v2
WHERE state IN ('queued','running')`;

export const BOUNDARY_QUERY = `SELECT
  COUNT(*) FILTER (WHERE state='failed')::int AS "failed",
  COALESCE(SUM(generation), 0)::bigint AS "generationSum",
  COUNT(DISTINCT race_id) FILTER (WHERE requested_at >= (to_timestamp($1 / 1000.0) AT TIME ZONE 'UTC')
    AND requested_at <= (to_timestamp($2 / 1000.0) AT TIME ZONE 'UTC'))::int AS "distinctDirtyRaces",
  COUNT(*) FILTER (WHERE requested_at >= (to_timestamp($1 / 1000.0) AT TIME ZONE 'UTC')
    AND requested_at <= (to_timestamp($2 / 1000.0) AT TIME ZONE 'UTC')
    AND NOT (state='succeeded' AND processing_generation >= generation))::int AS "touchedNotTerminalSuccess"
FROM race_resolution_jobs_v2`;

export const SETUP_STATUS_QUERY = `WITH expected AS (
  SELECT * FROM UNNEST($1::text[], $2::int[]) AS value("jobId", generation)
)
SELECT
  COUNT(j.id)::int AS "matched",
  COUNT(j.id) FILTER (WHERE j.generation = expected.generation AND j.state='succeeded'
    AND j.processing_generation >= expected.generation)::int AS "succeeded",
  COUNT(j.id) FILTER (WHERE j.generation = expected.generation AND j.state='failed')::int AS "failed",
  COUNT(j.id) FILTER (WHERE j.generation > expected.generation)::int AS "superseded"
FROM expected
LEFT JOIN race_resolution_jobs_v2 j ON j.id=expected."jobId"`;

export function parseDatabaseTarget(input) {
  if (typeof input !== 'string' || input.trim() === '') throw new Error('QUEUE_DATABASE_URL is required');
  let parsed;
  try { parsed = new URL(input); } catch { throw new Error('QUEUE_DATABASE_URL is malformed'); }
  if (!['postgres:', 'postgresql:'].includes(parsed.protocol)) throw new Error('QUEUE_DATABASE_URL must use postgres or postgresql');
  const hostname = parsed.hostname.toLowerCase().replace(/\.$/, '');
  const normalizedHost = hostname === '[::1]' ? '::1' : hostname;
  const databaseName = decodeURIComponent(parsed.pathname.replace(/^\//, '')).toLowerCase();
  if (!['localhost','127.0.0.1','::1'].includes(normalizedHost)) throw new Error('queue observation accepts only a loopback database');
  if (normalizedHost === 'steptracker-api.org' || normalizedHost.endsWith('.steptracker-api.org')) throw new Error('production database host is categorically forbidden');
  if (/(^|[_-])(prod|production)([_-]|$)/.test(databaseName) || !/(^|[_-])(test|capacity)([_-]|$)/.test(databaseName)) {
    throw new Error('queue database name must contain test or capacity and must not be production');
  }
  return {hostname, databaseName};
}

export function validateQueueBinding(baseUrl, confirmed) {
  const target = parseTarget(baseUrl);
  if (!target.loopback) throw new Error('verified queue evidence requires a loopback BASE_URL');
  if (confirmed !== '1' && confirmed !== true) throw new Error('QUEUE_TARGET_CONFIRMED=1 is required');
  return target;
}

export async function withReadOnlyTransaction(pool, callback) {
  let client;
  let began = false;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    began = true;
    await client.query('SET TRANSACTION READ ONLY');
    await client.query("SET LOCAL statement_timeout = '2s'");
    return await callback(client);
  } finally {
    if (client && began) {
      try { await client.query('ROLLBACK'); } catch { /* retain original failure */ }
    }
    if (client?.release) client.release();
    if (pool?.end) await pool.end();
  }
}

function numeric(value) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) throw new Error('queue query returned a malformed aggregate');
  return number;
}

function percentile(values, quantile) {
  if (!values.length) return null;
  const sorted = [...values].sort((a,b) => a-b);
  return sorted[Math.max(0, Math.ceil(sorted.length * quantile) - 1)];
}

export function classifySetupContexts(value) {
  if (!value || !['matched','succeeded','failed','superseded'].every(key => Number.isFinite(Number(value[key])))) {
    return {outcome: 'invalid', reason: 'setup job evidence is missing or malformed'};
  }
  if (Number(value.matched) !== 4 || Number(value.succeeded) !== 4 || Number(value.failed) !== 0 || Number(value.superseded) !== 0) {
    return {outcome: 'invalid', reason: 'all four exact setup job generations must be terminally successful'};
  }
  return {outcome: 'pass', reason: null};
}

export function validateSampleCadence(samples, {startMs, endMs}) {
  if (!Array.isArray(samples) || samples.length === 0 || !Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs < startMs) {
    return {valid: false, reason: 'sample cadence metadata is malformed'};
  }
  const timestamps = samples.map(sample => Number(sample.atMs));
  if (timestamps.some(value => !Number.isFinite(value))) return {valid: false, reason: 'sample timestamp is malformed'};
  const expectedCount = Math.floor((endMs - startMs) / (SAMPLE_INTERVAL_SECONDS * 1000)) + 1;
  const materialLatenessMs = 5000;
  if (timestamps.length < expectedCount || timestamps[0] > startMs + materialLatenessMs || timestamps[timestamps.length - 1] < endMs - materialLatenessMs) {
    return {valid: false, reason: 'sample coverage is incomplete'};
  }
  for (let index = 1; index < timestamps.length; index += 1) {
    const gap = timestamps[index] - timestamps[index - 1];
    if (gap <= 0 || gap > SAMPLE_INTERVAL_SECONDS * 1000 + materialLatenessMs) return {valid: false, reason: 'sample cadence was materially late'};
  }
  return {valid: true, reason: null, expectedCount};
}

export function summarizeQueueEvidence({samples, before, after, final = after, measureSeconds, measurementEndMs = null}) {
  if (!Array.isArray(samples) || samples.length === 0 || !before || !after) return {complete: false, observed: true};
  const queryDurations = samples.map(sample => numeric(sample.queryDurationMs));
  const lagValues = samples.map(sample => numeric(sample.oldestClaimableAgeMs));
  const finalSample = samples[samples.length - 1];
  const measureEndMs = measurementEndMs || samples[0].measurementStartMs + measureSeconds * 1000;
  const cadence = validateSampleCadence(samples, {startMs: samples[0].measurementStartMs, endMs: measureEndMs + 120000});
  if (!cadence.valid) return {complete: false, observed: true, cadenceValid: false, cadenceReason: cadence.reason,
    sampleTimestampsMs: samples.map(sample => sample.atMs), observerQueryP95Ms: percentile(queryDurations, 0.95),
    observerQueryMaxMs: Math.max(...queryDurations)};
  const drained = samples.find(sample => sample.atMs >= measureEndMs && numeric(sample.queued) === 0 && numeric(sample.running) === 0);
  return {
    complete: true,
    observed: true,
    sampleIntervalSeconds: SAMPLE_INTERVAL_SECONDS,
    cadenceValid: true,
    sampleTimestampsMs: samples.map(sample => sample.atMs),
    measurementStartMs: samples[0].measurementStartMs,
    measurementEndMs: measureEndMs,
    distinctDirtyRaces: numeric(after.distinctDirtyRaces),
    generationDelta: Math.max(0, numeric(after.generationSum) - numeric(before.generationSum)),
    oldestClaimableAgeP95Ms: percentile(lagValues, 0.95),
    drainSeconds: drained ? Math.max(0, (drained.atMs - measureEndMs) / 1000) : 120,
    newFailedJobs: Math.max(0, numeric(final.failed) - numeric(before.failed)),
    observerQueryP95Ms: percentile(queryDurations, 0.95),
    observerQueryMaxMs: Math.max(...queryDurations),
    boundaryQueryDurationsMs: [before, after, final]
      .map(boundary => numeric(boundary.queryDurationMs || 0)),
    finalQueued: numeric(finalSample.queued),
    finalRunning: numeric(finalSample.running),
    allTouchedTerminalSuccess: final.touchedTerminalSuccess === true || numeric(final.touchedNotTerminalSuccess || 0) === 0,
  };
}

function parseArguments(argv) {
  const [command, ...rest] = argv;
  const values = {};
  for (let index = 0; index < rest.length; index += 2) {
    if (!rest[index]?.startsWith('--') || rest[index + 1] === undefined) throw new Error('observer arguments must be --name value pairs');
    values[rest[index].slice(2)] = rest[index + 1];
  }
  return {command, values};
}

function sleep(milliseconds) {
  return new Promise(resolvePromise => setTimeout(resolvePromise, milliseconds));
}

async function resolutionSeedCommand(action, values) {
  const required = ['BASE_URL','FIXTURE_PATH','CORPUS_ID','APP_VERSION','PLATFORM','CLIENT_FEATURES','USER_AGENT','TIMEZONE','RELEASE_CHANNEL','LOCAL_DATE','LOGICAL_EPOCH_MS','RUN_ID','REPEAT_INDEX'];
  for (const name of required) if (!String(process.env[name] || '').trim()) throw new Error(`${name} is required`);
  const target = parseTarget(process.env.BASE_URL, {allowNonprod: process.env.ALLOW_NONPROD_TARGET === '1'});
  const fixture = validateFixture(JSON.parse(readFileSync(process.env.FIXTURE_PATH, 'utf8')), {corpusId: process.env.CORPUS_ID});
  const client = {appVersion: process.env.APP_VERSION, platform: process.env.PLATFORM, clientFeatures: process.env.CLIENT_FEATURES,
    userAgent: process.env.USER_AGENT, timezone: process.env.TIMEZONE, releaseChannel: process.env.RELEASE_CHANNEL};
  const syncRoute = PROFILE.routes.find(route => route.key === 'steps_sync_v2');
  const statusRoute = PROFILE.routes.find(route => route.key === 'race_resolution');
  const prior = values.previous ? JSON.parse(readFileSync(resolve(values.previous), 'utf8')) : null;
  if (action === 'postcheck' && (!Array.isArray(prior) || prior.length !== 4)) throw new Error('postcheck requires four prior setup status contexts');
  const phaseName = action === 'postcheck' ? 'postcheck' : String(values.phase || 'setup');
  const ordinalBase = Number(values['ordinal-base'] || 0);
  const submissions = await Promise.all(fixture.resolutionSeeds.map(async (seed, seedIndex) => {
    const request = buildRequest(syncRoute, {baseUrl: target.origin, user: seed, localDate: process.env.LOCAL_DATE,
      logicalEpochMs: Number(process.env.LOGICAL_EPOCH_MS), client, runId: process.env.RUN_ID,
      repeat: process.env.REPEAT_INDEX, writeOrdinal: ordinalBase + seedIndex, phase: phaseName});
    const response = await fetch(request.url, {method: 'POST', headers: request.params.headers, body: request.body,
      redirect: 'manual', signal: AbortSignal.timeout(15000)});
    if (response.status !== 202) throw new Error(`resolution seed submission returned unexpected status ${response.status}`);
    let parsed;
    try { parsed = await response.json(); } catch { throw new Error('resolution seed submission returned malformed JSON'); }
    const job = parsed?.raceResolution;
    if (!job || typeof job.jobId !== 'string' || !job.jobId || !Number.isInteger(job.generation) || job.generation < 1) {
      throw new Error('resolution seed submission returned no valid job generation');
    }
    const priorGeneration = prior?.find(item => item.seedIndex === seedIndex)?.generation;
    if (Number.isInteger(priorGeneration) && job.generation <= priorGeneration) throw new Error('resolution seed generation did not increase');
    return {seedIndex, jobId: job.jobId, generation: job.generation};
  }));
  const output = resolve(values.output || 'resolution-context.json');
  if (action === 'seed') {
    writeFileSync(output, `${JSON.stringify(submissions)}\n`, {mode: 0o600});
    chmodSync(output, 0o600);
    return;
  }
  const deadline = Date.now() + (action === 'postcheck' ? 60000 : 120000);
  const remaining = new Map(submissions.map(context => [context.seedIndex, context]));
  while (remaining.size > 0 && Date.now() < deadline) {
    await Promise.all([...remaining.values()].map(async context => {
      const seed = fixture.resolutionSeeds[context.seedIndex];
      const request = buildRequest(statusRoute, {baseUrl: target.origin, user: seed, resolutionJob: context,
        localDate: process.env.LOCAL_DATE, client, runId: process.env.RUN_ID, repeat: process.env.REPEAT_INDEX, phase: phaseName});
      const response = await fetch(request.url, {headers: request.params.headers, redirect: 'manual', signal: AbortSignal.timeout(15000)});
      if (response.status !== 200) throw new Error(`resolution status returned unexpected status ${response.status}`);
      let parsed;
      try { parsed = await response.json(); } catch { throw new Error('resolution status returned malformed JSON'); }
      const status = String(parsed?.raceResolution?.state || '').toLowerCase();
      if (status === 'succeeded') remaining.delete(context.seedIndex);
      else if (status === 'failed' || status === 'superseded') throw new Error(`resolution status reached ${status}`);
      else if (status !== 'queued' && status !== 'running') throw new Error('resolution status returned an unknown state');
    }));
    if (remaining.size > 0) await sleep(250);
  }
  if (remaining.size > 0) throw new Error('resolution status polling timed out');
  writeFileSync(output, `${JSON.stringify({postcheckSuccesses: 4, postcheckFailures: 0})}\n`, {mode: 0o600});
  chmodSync(output, 0o600);
}

function requiredEnvironment(names) {
  for (const name of names) if (!String(process.env[name] || '').trim()) throw new Error(`${name} is required`);
}

function writeJson(path, value, mode = 0o644) {
  writeFileSync(resolve(path), `${JSON.stringify(value, null, 2)}\n`, {mode});
  chmodSync(resolve(path), mode);
}

function preflightCommand(values) {
  requiredEnvironment(['BASE_URL','APP_VERSION','PLATFORM','CLIENT_FEATURES','USER_AGENT','TIMEZONE','RELEASE_CHANNEL','LOCAL_DATE','CORPUS_ID','WORKLOAD_USER_COUNT','FIXTURE_PATH']);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(process.env.LOCAL_DATE)) throw new Error('LOCAL_DATE must use exact YYYY-MM-DD form');
  const command = values.command;
  const target = parseTarget(process.env.BASE_URL, {allowNonprod: process.env.ALLOW_NONPROD_TARGET === '1'});
  const runSeed = Number(process.env.RUN_SEED || Date.now() % 0x7fffffff);
  if (!Number.isInteger(runSeed) || runSeed < 0) throw new Error('RUN_SEED must be a non-negative integer');
  const logicalEpochMs = validateLogicalEpochMs(Number(process.env.LOGICAL_EPOCH_MS));
  const plan = commandPlan(command, {rps: process.env.RPS, startRps: process.env.START_RPS,
    stepRps: process.env.STEP_RPS, maxRps: process.env.MAX_RPS, warmupDuration: process.env.WARMUP_DURATION,
    measureDuration: process.env.MEASURE_DURATION, soakDuration: process.env.SOAK_DURATION});
  const queueVerified = command !== 'smoke';
  if (queueVerified) {
    requiredEnvironment(['QUEUE_DATABASE_URL','BACKEND_REPO']);
    parseDatabaseTarget(process.env.QUEUE_DATABASE_URL);
    validateQueueBinding(process.env.BASE_URL, process.env.QUEUE_TARGET_CONFIRMED);
    if (process.env.RESOLUTION_WORKER_ENABLED !== '1') throw new Error('RESOLUTION_WORKER_ENABLED=1 is required for verified queue runs');
  }
  let ordinalCursor = 0;
  const enrichedPlan = plan.map(run => {
    const plannedWarmup = run.rps * run.warmupSeconds;
    const plannedMeasure = run.smoke ? PROFILE.routes.length : run.rps * run.measureSeconds;
    const warmupWrites = countWriteSlots(plannedWarmup, runSeed);
    const offeredWriteRequests = run.smoke ? PROFILE.routes.filter(route => route.method === 'POST').length : countWriteSlots(plannedMeasure, runSeed);
    const warmupWriteOrdinalBase = ordinalCursor;
    ordinalCursor += warmupWrites;
    const measureWriteOrdinalBase = ordinalCursor;
    ordinalCursor += offeredWriteRequests;
    return {...run, plannedWarmup, plannedMeasure, plannedTotal: plannedWarmup + plannedMeasure,
      warmupWrites, offeredWriteRequests, warmupWriteOrdinalBase, measureWriteOrdinalBase,
      ...vuAllocation(run.rps), expectedSyncReservationsMax: expectedSyncReservationsMax(run.rps, run.warmupSeconds, run.measureSeconds)};
  });
  const commandDeadline = computeCommandDeadline(Math.floor(Date.now() / 1000), enrichedPlan, {smoke: command === 'smoke'});
  const fixture = validateFixture(JSON.parse(readFileSync(resolve(process.env.FIXTURE_PATH), 'utf8')), {corpusId: process.env.CORPUS_ID, commandDeadlineSeconds: commandDeadline});
  const minimumWrites = Math.min(...enrichedPlan.map(run => run.offeredWriteRequests));
  const workload = selectWorkload(fixture, Number(process.env.WORKLOAD_USER_COUNT), {plannedMeasurementWriteSlots: minimumWrites,
    seed: runSeed, verifiedQueue: queueVerified});
  const client = {appVersion: process.env.APP_VERSION, platform: process.env.PLATFORM, clientFeatures: process.env.CLIENT_FEATURES,
    userAgent: process.env.USER_AGENT, timezone: process.env.TIMEZONE, releaseChannel: process.env.RELEASE_CHANNEL, localDate: process.env.LOCAL_DATE};
  const effective = {schemaVersion: 'simple-capacity-effective-config-v1', command, targetHostname: target.hostname,
    queueTargetConfirmed: queueVerified, client, corpusId: process.env.CORPUS_ID, fixtureFingerprint: fixture.cohortFingerprint,
    workloadUserCount: workload.users.length, selectedActiveRaceCount: workload.distinctActiveRaceCount,
    runSeed, logicalEpochMs, commandDeadline, sequenceDependent: true,
    profileSha256: profileHash(enrichedPlan.map(run => ({warmupSeconds: run.warmupSeconds, measureSeconds: run.measureSeconds, smoke: run.smoke}))),
    generatorCapacityVerified: process.env.GENERATOR_CAPACITY_VERIFIED === '1',
    plan: enrichedPlan,
    environment: {
      backendRevision: process.env.BACKEND_REVISION || null, backendFlags: process.env.BACKEND_FLAGS || null,
      cpuMemoryLimits: process.env.CPU_MEMORY_LIMITS || null, nodeWorkerCount: process.env.NODE_WORKER_COUNT || null,
      postgresTopology: process.env.POSTGRES_TOPOLOGY || null, redisTopology: process.env.REDIS_TOPOLOGY || null,
      applicationPoolSize: process.env.APPLICATION_POOL_SIZE || null, pgBouncerPoolSize: process.env.PGBOUNCER_POOL_SIZE || null,
      backgroundWorkers: process.env.BACKGROUND_WORKERS || null, databaseCorpusNotes: process.env.DATABASE_CORPUS_NOTES || null,
      loadGeneratorSeparateHardware: process.env.LOAD_GENERATOR_SEPARATE_HARDWARE || null,
    },
  };
  writeJson(values.output, effective);
}

function readJsonOrNull(path) {
  if (!path) return null;
  try { return JSON.parse(readFileSync(resolve(path), 'utf8')); } catch { return null; }
}

function finalizeRunCommand(values) {
  const config = readJsonOrNull(values.config);
  if (!config) throw new Error('valid preflight config is required');
  const plan = config.plan[Number(values.index) - 1];
  if (!plan) throw new Error('run index is outside the command plan');
  const warmup = readJsonOrNull(values.warmup);
  const measure = readJsonOrNull(values.measure);
  const postcheck = readJsonOrNull(values.postcheck);
  if (measure && postcheck) Object.assign(measure, postcheck);
  let stderr = '';
  try { stderr = values.stderr ? String(readFileSync(resolve(values.stderr), 'utf8')) : ''; } catch { stderr = ''; }
  if (measure && /insufficient vus|out of memory|generator.*(?:cpu|memory)/i.test(stderr)) measure.generatorWarnings = ['generator resource warning'];
  const warm = classifyHttpSummary(warmup, {generatorCapacityVerified: config.generatorCapacityVerified,
    processExitCode: Number(values['warmup-exit']), phase: 'warmup'});
  let http = classifyHttpSummary(measure, {generatorCapacityVerified: config.generatorCapacityVerified,
    processExitCode: Number(values['measure-exit']), phase: 'measure'});
  if (warm.outcome !== 'pass') http = {outcome: 'invalid', reasons: [...warm.reasons, ...http.reasons]};
  if (Number(values['setup-exit']) !== 0 || Number(values['postcheck-exit']) !== 0) {
    http = {outcome: 'invalid', reasons: [...http.reasons, 'resolution setup or postcheck process failed']};
  }
  let queue;
  if (config.command === 'smoke') queue = {outcome: 'unverified', reasons: ['smoke does not claim combined queue capacity']};
  else if (Number(values['queue-exit']) !== 0) queue = {outcome: 'invalid', reasons: ['queue observer process failed']};
  else queue = classifyQueueEvidence(readJsonOrNull(values.queue));
  const rank = {pass: 0, fail: 1, unverified: 2, invalid: 3};
  const benchmarkOutcome = config.command === 'smoke' ? http.outcome : (rank[http.outcome] >= rank[queue.outcome] ? http.outcome : queue.outcome);
  const writeStats = measuredWriteStats({endpointCounts: measure?.endpointCounts,
    completedMeasure: Number(measure?.completedMeasure || 0), workloadUserCount: config.workloadUserCount,
    rps: plan.rps, runSeed: config.runSeed, smoke: plan.smoke});
  const run = {rps: plan.rps, plannedTotal: plan.plannedTotal, plannedMeasure: plan.plannedMeasure,
    completedMeasure: Number(measure?.completedMeasure || 0), dropped: Number(measure?.dropped || 0),
    expectedSyncReservationsMax: plan.expectedSyncReservationsMax,
    offeredWriteRequests: plan.smoke ? plan.offeredWriteRequests : countWriteSlots(Number(measure?.completedMeasure || 0) + Number(measure?.dropped || 0), config.runSeed),
    ...writeStats,
    ...(config.command === 'smoke' ? {} : {queue: readJsonOrNull(values.queue)}),
    gates: {schedulerComplete: measure ? schedulerAccountingComplete(measure.plannedMeasure, measure.completedMeasure, measure.dropped) : false,
      postcheckComplete: measure ? measure.postcheckSuccesses === 4 && measure.postcheckFailures === 0 : false},
    benchmarkOutcome, httpOutcome: http.outcome, queueOutcome: queue.outcome,
    reasons: [...new Set([...http.reasons, ...queue.reasons])],
  };
  writeJson(values.output, run);
}

function aggregateCommand(values) {
  const config = readJsonOrNull(values.config);
  if (!config) throw new Error('valid preflight config is required');
  const runPaths = String(values.runs || '').split(',').filter(Boolean);
  const runs = runPaths.map(readJsonOrNull);
  const aggregateValidation = validateAggregateRuns(config, runs);
  const result = buildResult({command: config.command, targetHostname: config.targetHostname,
    queueTargetConfirmed: config.queueTargetConfirmed, client: config.client, corpusId: config.corpusId,
    fixtureFingerprint: config.fixtureFingerprint, workloadUserCount: config.workloadUserCount,
    distinctMeasuredWriteUsers: Math.max(0, ...runs.map(run => Number(run?.distinctMeasuredWriteUsers || 0))),
    selectedActiveRaceCount: config.selectedActiveRaceCount,
    generatorCapacityVerified: config.generatorCapacityVerified, profileSha256: config.profileSha256,
    plan: config.plan, runs});
  if (aggregateValidation.outcome === 'invalid' && result.benchmarkOutcome !== 'invalid') throw new Error('aggregate validation did not fail closed');
  writeJson(values.output, result);
  process.stdout.write(`HTTP: ${result.httpOutcome}\nqueue: ${result.queueOutcome}\nbenchmark: ${result.benchmarkOutcome}\n`);
  process.exitCode = result.benchmarkOutcome === 'pass' ? 0 : result.benchmarkOutcome === 'fail' ? 1 : 2;
}

function invalidResultCommand(values) {
  const command = values.command;
  const queueOutcome = command === 'smoke' ? 'unverified' : 'invalid';
  const result = buildResult({command, targetHostname: '', queueTargetConfirmed: false,
    client: {appVersion: process.env.APP_VERSION, platform: process.env.PLATFORM, clientFeatures: process.env.CLIENT_FEATURES,
      userAgent: process.env.USER_AGENT, timezone: process.env.TIMEZONE, releaseChannel: process.env.RELEASE_CHANNEL,
      localDate: process.env.LOCAL_DATE}, corpusId: process.env.CORPUS_ID,
    fixtureFingerprint: '', workloadUserCount: Number(process.env.WORKLOAD_USER_COUNT || 0),
    distinctMeasuredWriteUsers: 0, selectedActiveRaceCount: 0, generatorCapacityVerified: false,
    runs: [{rps: Number(process.env.RPS || process.env.START_RPS || 0), httpOutcome: 'invalid', queueOutcome,
      benchmarkOutcome: 'invalid', reasons: ['preflight failed; see preflight.stderr.log']}],
  });
  writeJson(values.output, result);
}

async function main() {
  const {command, values} = parseArguments(process.argv.slice(2));
  if (!['barrier','observe','seed','postcheck','preflight','finalize-run','aggregate','invalid-result'].includes(command)) throw new Error('unknown queue/capacity helper command');
  if (command === 'invalid-result') { invalidResultCommand(values); return; }
  if (command === 'preflight') { preflightCommand(values); return; }
  if (command === 'finalize-run') { finalizeRunCommand(values); return; }
  if (command === 'aggregate') { aggregateCommand(values); return; }
  if (command === 'seed' || command === 'postcheck') {
    await resolutionSeedCommand(command, values);
    return;
  }
  const databaseUrl = process.env.QUEUE_DATABASE_URL;
  parseDatabaseTarget(databaseUrl);
  validateQueueBinding(process.env.BASE_URL, process.env.QUEUE_TARGET_CONFIRMED);
  if (!String(process.env.BACKEND_REPO || '').trim()) throw new Error('BACKEND_REPO is required');
  const backendRequire = createRequire(resolve(process.env.BACKEND_REPO, 'package.json'));
  const {Pool} = backendRequire('pg');
  const poolFactory = () => new Pool({connectionString: databaseUrl, max: 1});
  const testScale = process.env.NODE_ENV === 'test' ? Number(process.env.OBSERVER_TEST_TIME_SCALE || 1) : 1;
  if (!Number.isFinite(testScale) || testScale < 1 || testScale > 10000) throw new Error('invalid observer test time scale');
  const realClockStartMs = Date.now();
  const logicalClockStartMs = realClockStartMs;
  const nowMs = () => logicalClockStartMs + (Date.now() - realClockStartMs) * testScale;
  const wait = milliseconds => sleep(milliseconds / testScale);
  const serviceSample = async measurementStartMs => {
    const now = nowMs();
    const measured = await withReadOnlyTransaction(poolFactory(), async client => {
      const started = performance.now();
      const result = await client.query(SERVICE_QUERY, [now]);
      return {rows: result.rows, queryDurationMs: performance.now() - started};
    });
    const {rows, queryDurationMs} = measured;
    const row = rows[0] || {};
    return {atMs: nowMs(), measurementStartMs, queued: numeric(row.queued || 0), running: numeric(row.running || 0),
      claimable: numeric(row.claimable || 0), oldestRequestAgeMs: numeric(row.oldestRequestAgeMs || 0),
      oldestClaimableAgeMs: numeric(row.oldestClaimableAgeMs || 0), queryDurationMs};
  };
  const boundary = async (start, end) => {
    const measured = await withReadOnlyTransaction(poolFactory(), async client => {
      const started = performance.now();
      const result = await client.query(BOUNDARY_QUERY, [start, end]);
      return {rows: result.rows, queryDurationMs: performance.now() - started};
    });
    const {rows, queryDurationMs} = measured;
    const row = rows[0] || {};
    return {failed: numeric(row.failed || 0), generationSum: numeric(row.generationSum || 0),
      distinctDirtyRaces: numeric(row.distinctDirtyRaces || 0), touchedNotTerminalSuccess: numeric(row.touchedNotTerminalSuccess || 0),
      queryDurationMs};
  };
  const setupContexts = values.contexts ? JSON.parse(readFileSync(resolve(values.contexts), 'utf8')) : null;
  if (setupContexts && (!Array.isArray(setupContexts) || setupContexts.length !== 4 || setupContexts.some(context =>
    !context || typeof context.jobId !== 'string' || !context.jobId || !Number.isInteger(context.generation) || context.generation < 1))) {
    throw new Error('barrier contexts must contain exactly four valid job/generation pairs');
  }
  const setupStatus = async () => {
    if (!setupContexts) return {matched: 4, succeeded: 4, failed: 0, superseded: 0};
    const rows = await withReadOnlyTransaction(poolFactory(), async client =>
      (await client.query(SETUP_STATUS_QUERY, [setupContexts.map(context => context.jobId), setupContexts.map(context => context.generation)])).rows);
    const row = rows[0] || {};
    return {matched: numeric(row.matched || 0), succeeded: numeric(row.succeeded || 0),
      failed: numeric(row.failed || 0), superseded: numeric(row.superseded || 0)};
  };
  const output = resolve(values.output || 'queue.json');
  if (command === 'barrier') {
    const timeoutSeconds = Number(values.timeout || 120);
    const deadline = nowMs() + timeoutSeconds * 1000;
    const samples = [];
    let consecutiveClean = 0;
    while (nowMs() <= deadline) {
      const sample = await serviceSample(nowMs());
      samples.push(sample);
      consecutiveClean = sample.queued === 0 && sample.running === 0 ? consecutiveClean + 1 : 0;
      if (consecutiveClean >= 3) {
        const setup = await setupStatus();
        const setupClassification = classifySetupContexts(setup);
        if (setupClassification.outcome !== 'pass') {
          writeFileSync(output, `${JSON.stringify({complete: false, clean: true, setupVerified: false, reason: setupClassification.reason})}\n`);
          process.exitCode = 2;
          return;
        }
        writeFileSync(output, `${JSON.stringify({complete: true, clean: true, sampleCount: samples.length,
          sampleTimestampsMs: samples.map(sampleValue => sampleValue.atMs), setupVerified: true,
          sampleIntervalSeconds: SAMPLE_INTERVAL_SECONDS, observerQueryP95Ms: percentile(samples.map(item => item.queryDurationMs), .95),
          observerQueryMaxMs: Math.max(...samples.map(item => item.queryDurationMs))})}\n`);
        return;
      }
      await wait(SAMPLE_INTERVAL_SECONDS * 1000);
    }
    writeFileSync(output, `${JSON.stringify({complete: false, clean: false, reason: 'clean queue barrier timed out'})}\n`);
    process.exitCode = 2;
    return;
  }
  const measureSeconds = Number(values['measure-seconds']);
  const drainSeconds = Number(values['drain-seconds'] || 120);
  if (!Number.isInteger(measureSeconds) || measureSeconds <= 0 || drainSeconds !== 120 || !values.ready || !values.done || !values['boundary-ready']) {
    throw new Error('observe requires positive --measure-seconds, fixed drain, and ready/done boundary signals');
  }
  const measurementStartMs = nowMs();
  const before = await boundary(0, measurementStartMs);
  writeFileSync(resolve(values.ready), 'ready\n', {mode: 0o600});
  const maximumMeasurementEndMs = measurementStartMs + (measureSeconds + 30) * 1000;
  let nextSampleMs = measurementStartMs;
  const samples = [];
  while (!existsSync(resolve(values.done)) && nowMs() <= maximumMeasurementEndMs) {
    if (nowMs() >= nextSampleMs) {
      samples.push(await serviceSample(measurementStartMs));
      nextSampleMs += SAMPLE_INTERVAL_SECONDS * 1000;
    } else {
      await wait(Math.min(100, nextSampleMs - nowMs()));
    }
  }
  if (!existsSync(resolve(values.done))) throw new Error('measurement completion signal timed out');
  const measurementEndMs = nowMs();
  const after = await boundary(measurementStartMs, measurementEndMs);
  writeFileSync(resolve(values['boundary-ready']), 'boundary-ready\n', {mode: 0o600});
  const finalEndMs = measurementEndMs + drainSeconds * 1000;
  while (nowMs() <= finalEndMs) {
    if (nowMs() >= nextSampleMs) {
      samples.push(await serviceSample(measurementStartMs));
      nextSampleMs += SAMPLE_INTERVAL_SECONDS * 1000;
    } else {
      await wait(Math.min(100, nextSampleMs - nowMs(), finalEndMs - nowMs()));
    }
    if (nowMs() >= finalEndMs) break;
  }
  if (samples[samples.length - 1]?.atMs < finalEndMs - 1000) samples.push(await serviceSample(measurementStartMs));
  const final = await boundary(measurementStartMs, measurementEndMs);
  const evidence = summarizeQueueEvidence({samples, before, after, final, measureSeconds, measurementEndMs});
  writeFileSync(output, `${JSON.stringify(evidence)}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { process.stderr.write(`queue observer failed: ${error.message}\n`); process.exitCode = 2; });
}
