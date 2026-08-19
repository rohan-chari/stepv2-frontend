import assert from 'node:assert/strict';
import {execFileSync, spawn, spawnSync} from 'node:child_process';
import {existsSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {test} from 'node:test';

import * as contractModule from '../capacity-contract.mjs';
import * as observerModule from '../queue-observer.mjs';

import {
  PROFILE,
  buildRequest,
  buildResult,
  classifyHttpSummary,
  classifyQueueEvidence,
  classifyStatus,
  commandPlan,
  computeCommandDeadline,
  expectedSyncReservationsMax,
  k6ArrivalDuration,
  operatingLimit,
  parseDurationSeconds,
  parseTarget,
  profileHash,
  routeForSlot,
  selectWorkload,
  validateFixture,
  vuAllocation,
} from '../capacity-contract.mjs';
import {
  buildFixtureFromRows,
  parseDatabaseTarget as parseFixtureDatabaseTarget,
  withReadOnlyTransaction as withFixtureReadOnlyTransaction,
} from '../prepare-fixture.mjs';
import {
  BOUNDARY_QUERY,
  SERVICE_QUERY,
  parseDatabaseTarget as parseQueueDatabaseTarget,
  summarizeQueueEvidence,
  withReadOnlyTransaction as withQueueReadOnlyTransaction,
} from '../queue-observer.mjs';

const repoRoot = resolve(import.meta.dirname, '../..');
const runner = join(repoRoot, 'k6/run-capacity.zsh');

function jwt(exp, sub = 'test-user') {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({alg: 'HS256', typ: 'JWT'})}.${encode({exp, iss: 'steps-tracker-api', sub})}.signature`;
}

function fixture(overrides = {}) {
  const exp = Math.floor(Date.now() / 1000) + 100000;
  const workloadUsers = Array.from({length: 205}, (_, index) => ({
    userId: `workload-${index}`,
    token: jwt(exp, `workload-${index}`),
    activeRaceIds: [`race-${index}`, `shared-${index % 7}`],
    activeRaceSetComplete: true,
  }));
  const resolutionSeeds = Array.from({length: 4}, (_, index) => ({
    userId: `seed-${index}`,
    token: jwt(exp, `seed-${index}`),
    raceId: `seed-race-${index}`,
  }));
  return {
    schemaVersion: 'simple-capacity-fixture-v1',
    issuedAt: Math.floor(Date.now() / 1000),
    expiresAt: exp,
    corpusId: 'corpus-a',
    cohortFingerprint: `sha256:${'a'.repeat(64)}`,
    workloadUsers,
    resolutionSeeds,
    ...overrides,
  };
}

const client = {
  appVersion: '9.9.9',
  platform: 'ios',
  clientFeatures: 'compact-v1',
  userAgent: 'Bara/9.9.9',
  timezone: 'America/New_York',
  releaseChannel: 'prod',
};

function completeSummary(overrides = {}) {
  return {
    complete: true,
    plannedMeasure: 1000,
    completedMeasure: 1000,
    dropped: 0,
    failureRate: 0,
    rateLimitedRate: 0,
    httpP95Ms: 100,
    httpP99Ms: 200,
    httpMaxMs: 500,
    criticalWriteP95Ms: 120,
    criticalWriteP99Ms: 240,
    criticalWriteMaxMs: 500,
    contextFallbacks: 0,
    endpointCounts: Object.fromEntries(PROFILE.routes.map(route => [route.key, 1])),
    postcheckSuccesses: 4,
    postcheckFailures: 0,
    authFailures: 0,
    runtimeFailures: 0,
    generatorWarnings: [],
    ...overrides,
  };
}

test('profile pins thirteen unique routes, exact weights, order, and hash', () => {
  assert.equal(PROFILE.name, 'capacity-benchmark-v1');
  assert.equal(PROFILE.routes.reduce((sum, route) => sum + route.weight, 0), 100);
  assert.equal(new Set(PROFILE.routes.map(route => route.key)).size, 13);
  assert.deepEqual(PROFILE.routes.map(route => [route.method, route.path, route.weight]), [
    ['GET', '/races/:id/messages?limit=50', 26],
    ['GET', '/challenges/current', 9],
    ['GET', '/assets/manifest', 9],
    ['GET', '/steps/race-resolution/:jobId?generation=N', 7],
    ['POST', '/steps', 7],
    ['GET', '/races?view=compact-v1', 7],
    ['POST', '/steps/samples', 6],
    ['GET', '/races/:id/progress?view=participants-v1&offset=0&limit=15', 6],
    ['GET', '/auth/me', 5],
    ['POST', '/steps/sync-v2', 5],
    ['GET', '/home/race-card?view=shell-v1&homeActiveRaces=1&localDate=YYYY-MM-DD', 5],
    ['GET', '/home/suggested-races', 4],
    ['GET', '/powerups/inventory', 4],
  ]);
  assert.match(profileHash(), /^[a-f0-9]{64}$/);
  const slots = Array.from({length: 100}, (_, index) => routeForSlot(index, 19).key);
  for (const route of PROFILE.routes) {
    assert.equal(slots.filter(key => key === route.key).length, route.weight);
  }
});

test('request construction pins headers, statuses, timeout, redirects, paths, and bodies', () => {
  const user = fixture().workloadUsers[0];
  const context = {
    baseUrl: 'http://127.0.0.1:3000', user, raceId: user.activeRaceIds[0],
    resolutionJob: {jobId: 'job-placeholder', generation: 7},
    localDate: '2026-08-19', logicalEpochMs: 1_755_600_120_000,
    client, runId: 'run-public', repeat: 2, iteration: 3, writeOrdinal: 210,
  };
  for (const route of PROFILE.routes) {
    const request = buildRequest(route, context);
    assert.equal(request.method, route.method);
    assert.equal(request.params.timeout, '15s');
    assert.equal(request.params.redirects, 0);
    assert.equal(request.params.tags.phase, 'measure');
    assert.deepEqual(request.acceptedStatuses, route.acceptedStatuses);
    assert.ok(!request.url.includes(':id'));
    assert.ok(!request.url.includes('generation=N'));
    if (route.key === 'assets_manifest') {
      assert.deepEqual(request.params.headers, {'X-Release-Channel': 'prod'});
    } else {
      assert.equal(request.params.headers.Authorization, `Bearer ${user.token}`);
      assert.equal(request.params.headers['X-Timezone'], client.timezone);
      assert.equal(request.params.headers['X-Capacity-Run-Id'], 'run-public');
      assert.equal(request.params.headers['X-Capacity-Repeat'], '2');
    }
    if (route.method === 'POST') {
      assert.equal(request.params.headers['Content-Type'], 'application/json');
      assert.doesNotThrow(() => JSON.parse(request.body));
    }
  }
  assert.ok(buildRequest(PROFILE.routes.find(route => route.key === 'home_race_card'), context).url.endsWith('localDate=2026-08-19'));
  assert.equal(classifyStatus(PROFILE.routes.find(route => route.key === 'challenges_current'), 404), 'accepted');
  assert.equal(classifyStatus(PROFILE.routes[0], 404), 'capacity-failure');
  for (const status of [401, 403]) assert.equal(classifyStatus(PROFILE.routes[0], status), 'invalid');
  for (const status of [0]) assert.equal(classifyStatus(PROFILE.routes[0], status), 'invalid');
  for (const status of [301, 408, 409, 429, 500, 503]) assert.equal(classifyStatus(PROFILE.routes[0], status), 'capacity-failure');
});

test('target parsing is canonical and production refusal cannot be overridden', () => {
  assert.equal(parseTarget('HTTP://LOCALHOST.:3000').hostname, 'localhost');
  assert.equal(parseTarget('https://staging.steptracker-api.org/').hostname, 'staging.steptracker-api.org');
  for (const url of [
    'https://steptracker-api.org', 'https://STEPTRACKER-API.ORG.',
    'https://x.steptracker-api.org', 'https://x.STEPTRACKER-API.ORG.',
    'http://user@localhost:3000', 'http://localhost:3000/path',
    'http://localhost:3000/?q=1', 'http://localhost:3000/#fragment', 'ftp://localhost',
  ]) assert.throws(() => parseTarget(url, {allowNonprod: true}));
  assert.throws(() => parseTarget('https://capacity.example.test'));
  assert.equal(parseTarget('https://capacity.example.test', {allowNonprod: true}).hostname, 'capacity.example.test');
});

test('fixture validation rejects unsafe shape, overlaps, stale tokens, and corpus mismatch', () => {
  const valid = fixture();
  assert.equal(validateFixture(valid, {corpusId: 'corpus-a'}).workloadUsers.length, 205);
  assert.throws(() => validateFixture({...valid, workloadUsers: valid.workloadUsers.slice(0, 199)}, {corpusId: 'corpus-a'}));
  assert.throws(() => validateFixture({...valid, resolutionSeeds: valid.resolutionSeeds.slice(0, 3)}, {corpusId: 'corpus-a'}));
  assert.throws(() => validateFixture({...valid, extra: true}, {corpusId: 'corpus-a'}));
  assert.throws(() => validateFixture(valid, {corpusId: 'wrong'}));
  assert.throws(() => validateFixture({...valid, expiresAt: valid.expiresAt + 1}, {corpusId: 'corpus-a'}));
  const incomplete = structuredClone(valid);
  incomplete.workloadUsers[0].activeRaceSetComplete = false;
  assert.throws(() => validateFixture(incomplete, {corpusId: 'corpus-a'}));
  const duplicate = structuredClone(valid);
  duplicate.workloadUsers[1].userId = duplicate.workloadUsers[0].userId;
  assert.throws(() => validateFixture(duplicate, {corpusId: 'corpus-a'}));
  const overlap = structuredClone(valid);
  overlap.resolutionSeeds[0].raceId = overlap.workloadUsers[0].activeRaceIds[0];
  assert.throws(() => validateFixture(overlap, {corpusId: 'corpus-a'}));
  assert.throws(() => validateFixture(valid, {corpusId: 'corpus-a', commandDeadlineSeconds: valid.expiresAt}));
});

test('workload selection is bounded, rotates without replacement, and reports breadth', () => {
  const valid = fixture();
  assert.throws(() => selectWorkload(valid, undefined, {plannedMeasurementWriteSlots: 1000}));
  assert.throws(() => selectWorkload(valid, 199, {plannedMeasurementWriteSlots: 1000}));
  assert.throws(() => selectWorkload(valid, 206, {plannedMeasurementWriteSlots: 1000}));
  assert.throws(() => selectWorkload(valid, 205, {plannedMeasurementWriteSlots: 204, verifiedQueue: true}));
  const selected = selectWorkload(valid, 200, {plannedMeasurementWriteSlots: 600, seed: 41, verifiedQueue: true});
  assert.equal(selected.users.length, 200);
  assert.equal(new Set(Array.from({length: 200}, (_, ordinal) => selected.userForWriteOrdinal(ordinal).userId)).size, 200);
  assert.equal(selected.userForWriteOrdinal(0).userId, selected.userForWriteOrdinal(200).userId);
  assert.equal(selected.distinctMeasuredWriteUsers, 200);
  assert.ok(selected.distinctActiveRaceCount >= 200);
  assert.notEqual(selected.payloadOrdinal('warmup', 0), selected.payloadOrdinal('measure', 0));
});

test('duration, command, reservation, VU, and deadline formulas are exact', () => {
  const workloadSource = readFileSync(join(repoRoot, 'k6/capacity-test.js'), 'utf8');
  assert.match(
    workloadSource,
    /if \(smoke\) \{\s*return \{executor: 'shared-iterations', vus: 1, iterations: plannedRequests,/,
    'smoke warm-up and measurement must use exact shared iterations',
  );
  assert.equal(k6ArrivalDuration(15), '14999.999ms');
  assert.equal(parseDurationSeconds('30m'), 1800);
  assert.equal(parseDurationSeconds('1m30s'), 90);
  assert.throws(() => parseDurationSeconds('')); 
  assert.deepEqual(vuAllocation(250), {preAllocatedVUs: 625, maxVUs: 1500});
  assert.deepEqual(vuAllocation(1), {preAllocatedVUs: 50, maxVUs: 50});
  assert.equal(expectedSyncReservationsMax(250, 60, 300), 4512);
  assert.equal(operatingLimit(251), 175);
  assert.deepEqual(commandPlan('confirm', {rps: 250}).map(run => run.rps), [250, 250, 250]);
  assert.deepEqual(commandPlan('find', {startRps: 100, stepRps: 50, maxRps: 220}).map(run => run.rps), [100, 150, 200]);
  assert.equal(commandPlan('soak', {rps: 25})[0].measureSeconds, 1800);
  const one = computeCommandDeadline(1000, [{warmupSeconds: 60, measureSeconds: 300}], {smoke: false});
  assert.equal(one, 1000 + 30 + 15 + 60 + 15 + 120 + 15 + 120 + 300 + 15 + 120 + 15 + 60 + 300);
  const smoke = computeCommandDeadline(1000, [{warmupSeconds: 15, measureSeconds: 30, smoke: true}], {smoke: true});
  assert.equal(smoke, 1000 + 15 + 15 + 15 + 15 + 300 + 15 + 15 + 60 + 300);
});

test('HTTP classification fails closed at every exact gate boundary', () => {
  assert.equal(classifyHttpSummary(completeSummary(), {generatorCapacityVerified: true, processExitCode: 0}).outcome, 'pass');
  assert.equal(classifyHttpSummary(completeSummary({completedMeasure: 1001}), {generatorCapacityVerified: true, processExitCode: 0}).outcome, 'pass');
  assert.equal(classifyHttpSummary(completeSummary({completedMeasure: 1002}), {generatorCapacityVerified: true, processExitCode: 0}).outcome, 'invalid');
  for (const change of [
    {complete: false}, {completedMeasure: 998}, {failureRate: 0.01}, {rateLimitedRate: 0.01},
    {httpP95Ms: 2000}, {httpP99Ms: 5000}, {criticalWriteP95Ms: 2000},
    {criticalWriteP99Ms: 5000}, {criticalWriteMaxMs: 15000}, {contextFallbacks: 1},
    {postcheckSuccesses: 3}, {postcheckFailures: 1},
  ]) assert.notEqual(classifyHttpSummary(completeSummary(change), {generatorCapacityVerified: true, processExitCode: 0}).outcome, 'pass');
  assert.equal(classifyHttpSummary(completeSummary({dropped: 1, completedMeasure: 999}), {generatorCapacityVerified: true, processExitCode: 99}).outcome, 'fail');
  assert.equal(classifyHttpSummary(completeSummary({dropped: 1, completedMeasure: 999}), {generatorCapacityVerified: false, processExitCode: 99}).outcome, 'invalid');
  assert.equal(classifyHttpSummary(completeSummary({generatorWarnings: ['insufficient VUs']}), {generatorCapacityVerified: true, processExitCode: 0}).outcome, 'invalid');
  assert.equal(classifyHttpSummary(completeSummary(), {generatorCapacityVerified: true, processExitCode: 17}).outcome, 'invalid');
  assert.equal(classifyHttpSummary(completeSummary({failureRate: 0.02}), {generatorCapacityVerified: true, processExitCode: 99}).outcome, 'fail');
});

test('queue classification separates invalid, unverified, fail, and pass boundaries', () => {
  const good = {complete: true, observed: true, cadenceValid: true, distinctDirtyRaces: 1, generationDelta: 1,
    oldestClaimableAgeP95Ms: 30000, newFailedJobs: 0, finalQueued: 0, finalRunning: 0,
    allTouchedTerminalSuccess: true, observerQueryP95Ms: 100, observerQueryMaxMs: 250,
    sampleIntervalSeconds: 10, drainSeconds: 40};
  assert.equal(classifyQueueEvidence(good).outcome, 'pass');
  assert.equal(classifyQueueEvidence({...good, oldestClaimableAgeP95Ms: 30001}).outcome, 'fail');
  assert.equal(classifyQueueEvidence({...good, finalQueued: 1}).outcome, 'fail');
  assert.equal(classifyQueueEvidence({...good, observerQueryP95Ms: 100.01}).outcome, 'unverified');
  assert.equal(classifyQueueEvidence({...good, observerQueryMaxMs: 250.01}).outcome, 'unverified');
  assert.equal(classifyQueueEvidence({...good, complete: false}).outcome, 'invalid');
  assert.equal(classifyQueueEvidence(null).outcome, 'unverified');
});

test('result shape separates outcomes, confirmation, first failure, and redacts secrets', () => {
  const runs = [
    {rps: 100, httpOutcome: 'pass', queueOutcome: 'pass', benchmarkOutcome: 'pass', reasons: []},
    {rps: 150, httpOutcome: 'fail', queueOutcome: 'pass', benchmarkOutcome: 'fail', reasons: ['p95']},
  ];
  const result = buildResult({command: 'find', targetHostname: 'localhost', client,
    corpusId: 'corpus-a', fixtureFingerprint: `sha256:${'b'.repeat(64)}`,
    workloadUserCount: 200, distinctMeasuredWriteUsers: 200, selectedActiveRaceCount: 207,
    generatorCapacityVerified: false, runs});
  assert.equal(result.schemaVersion, 'simple-capacity-result-v1');
  assert.equal(result.firstFailedRung, 150);
  assert.equal(result.systemTelemetryVerified, false);
  assert.equal(result.httpConfirmed, false);
  assert.equal(result.queueConfirmed, false);
  const serialized = JSON.stringify(result);
  for (const forbidden of ['Bearer ', 'Authorization', 'postgres://', 'token', 'workload-0', 'race-0']) {
    assert.ok(!serialized.includes(forbidden));
  }
  const confirm = buildResult({...result, command: 'confirm', runs: Array(3).fill({rps: 100, httpOutcome: 'pass', queueOutcome: 'pass', benchmarkOutcome: 'pass', reasons: []})});
  assert.equal(confirm.httpConfirmed, true);
  assert.equal(confirm.queueConfirmed, true);
  const twoOfThree = buildResult({...result, command: 'confirm', runs: [confirm.runs[0], confirm.runs[0], {...confirm.runs[0], httpOutcome: 'fail', benchmarkOutcome: 'fail'}]});
  assert.equal(twoOfThree.httpConfirmed, false);
  assert.equal(twoOfThree.benchmarkOutcome, 'fail');
});

test('fixture database target and read-only transaction are fail-closed', async () => {
  assert.equal(parseFixtureDatabaseTarget('postgres://u:p@127.0.0.1:5432/app_capacity_test').hostname, '127.0.0.1');
  for (const url of ['postgres://u:p@db.example/app_test', 'postgres://u:p@localhost/app', 'postgres://u:p@localhost/steptracker_prod']) {
    assert.throws(() => parseFixtureDatabaseTarget(url));
  }
  const calls = [];
  const client = {query: async sql => {calls.push(sql); if (sql === 'SELECT boom') throw new Error('boom');}, release: () => calls.push('release')};
  const pool = {connect: async () => client, end: async () => calls.push('end')};
  await assert.rejects(() => withFixtureReadOnlyTransaction(pool, async db => db.query('SELECT boom')));
  assert.deepEqual(calls.slice(0, 2), ['BEGIN', 'SET TRANSACTION READ ONLY']);
  assert.ok(calls.includes('ROLLBACK'));
  assert.deepEqual(calls.slice(-2), ['release', 'end']);
});

test('fixture row builder enforces allowlist, review/device filters, isolated rosters, and JWT metadata', () => {
  const exp = Math.floor(Date.now() / 1000) + 7200;
  const allowlist = Array.from({length: 204}, (_, index) => `u-${index}`);
  const rows = allowlist.map((userId, index) => ({userId, isReviewAccount: false, deviceTokenCount: 0,
    activeRaceIds: index < 200 ? [`r-${index}`] : [`seed-r-${index - 200}`], rostersSafe: true}));
  const output = buildFixtureFromRows(rows, {allowlist, corpusId: 'c', issuedAt: exp - 7200, expiresAt: exp,
    sign: userId => jwt(exp, userId)});
  assert.equal(output.workloadUsers.length, 200);
  assert.equal(output.resolutionSeeds.length, 4);
  assert.equal(output.expiresAt, exp);
  assert.match(output.cohortFingerprint, /^sha256:[a-f0-9]{64}$/);
  assert.throws(() => buildFixtureFromRows([{...rows[0], isReviewAccount: true}, ...rows.slice(1)], {allowlist, corpusId: 'c', issuedAt: exp - 1, expiresAt: exp, sign: id => jwt(exp, id)}));
  assert.throws(() => buildFixtureFromRows([{...rows[0], deviceTokenCount: 1}, ...rows.slice(1)], {allowlist, corpusId: 'c', issuedAt: exp - 1, expiresAt: exp, sign: id => jwt(exp, id)}));
  const inactiveId = 'u-inactive';
  const withInactive = buildFixtureFromRows([
    ...rows,
    {userId: inactiveId, isReviewAccount: false, deviceTokenCount: 0, activeRaceIds: [], rostersSafe: false},
  ], {allowlist: [...allowlist, inactiveId], corpusId: 'c', issuedAt: exp - 7200, expiresAt: exp,
    sign: userId => jwt(exp, userId)});
  assert.equal(withInactive.workloadUsers.length, 200);
  assert.ok(!withInactive.workloadUsers.some(user => user.userId === inactiveId));
});

test('fixture preparer command loads fake backend dependencies and emits a private exact fixture', () => {
  const root = mkdtempSync(join(tmpdir(), 'capacity-fixture-'));
  const backend = join(root, 'backend');
  const pgDirectory = join(backend, 'node_modules', 'pg');
  const jwtDirectory = join(backend, 'node_modules', 'jsonwebtoken');
  mkdirSync(pgDirectory, {recursive: true});
  mkdirSync(jwtDirectory, {recursive: true});
  writeFileSync(join(backend, 'package.json'), '{"private":true}\n');
  writeFileSync(join(pgDirectory, 'index.js'), `
const {appendFileSync} = require('node:fs');
const rows = Array.from({length: 204}, (_, index) => ({
  userId: \`dedicated-\${index}\`, isReviewAccount: false, deviceTokenCount: 0,
  activeRaceIds: [\`isolated-race-\${index}\`], rostersSafe: true,
}));
class Pool {
  async connect() {
    return {
      query: async sql => {
        appendFileSync(process.env.FAKE_DB_LOG, String(sql).trim().split('\\n')[0] + '\\n');
        return {rows: String(sql).includes('FROM users u') ? rows : []};
      },
      release: () => appendFileSync(process.env.FAKE_DB_LOG, 'release\\n'),
    };
  }
  async end() { appendFileSync(process.env.FAKE_DB_LOG, 'end\\n'); }
}
module.exports = {Pool};
`);
  writeFileSync(join(jwtDirectory, 'index.js'), `
function encode(value) { return Buffer.from(JSON.stringify(value)).toString('base64url'); }
exports.sign = (_payload, _secret, options) => {
  const now = Math.floor(Date.now() / 1000);
  return \`\${encode({alg: options.algorithm, typ: 'JWT'})}.\${encode({exp: now + options.expiresIn, iss: options.issuer, sub: options.subject})}.signature\`;
};
`);
  const allowlist = join(root, 'allowlist.json');
  const output = join(root, 'fixture.json');
  const dbLog = join(root, 'db.log');
  writeFileSync(allowlist, `${JSON.stringify(Array.from({length: 204}, (_, index) => `dedicated-${index}`))}\n`);
  const environment = {
    ...process.env,
    DATABASE_URL: 'postgres://fixture:private@127.0.0.1:5432/app_capacity_test',
    BACKEND_REPO: backend,
    SESSION_SECRET: 'private-test-secret',
    TOKEN_TTL_SECONDS: '7200',
    CORPUS_ID: 'hermetic-corpus',
    ALLOWLIST_PATH: allowlist,
    FIXTURE_OUTPUT: output,
    FAKE_DB_LOG: dbLog,
  };
  const execution = spawnSync(process.execPath, [join(repoRoot, 'k6/prepare-fixture.mjs')], {env: environment, encoding: 'utf8'});
  assert.equal(execution.status, 0, execution.stderr);
  assert.ok(!execution.stdout.includes(environment.SESSION_SECRET));
  assert.ok(!execution.stdout.includes(environment.DATABASE_URL));
  assert.ok(!execution.stdout.includes('eyJ'));
  const calls = readFileSync(dbLog, 'utf8').trim().split('\n');
  assert.deepEqual(calls.slice(0, 2), ['BEGIN', 'SET TRANSACTION READ ONLY']);
  assert.deepEqual(calls.slice(-3), ['ROLLBACK', 'release', 'end']);
  const document = JSON.parse(readFileSync(output, 'utf8'));
  assert.equal(document.workloadUsers.length, 200);
  assert.equal(document.resolutionSeeds.length, 4);
  assert.equal(document.expiresAt, Math.min(...[...document.workloadUsers, ...document.resolutionSeeds]
    .map(item => Number(JSON.parse(Buffer.from(item.token.split('.')[1], 'base64url')).exp))));
  assert.equal(JSON.parse(Buffer.from(document.workloadUsers[0].token.split('.')[0], 'base64url')).alg, 'HS256');
  assert.equal(JSON.parse(Buffer.from(document.workloadUsers[0].token.split('.')[1], 'base64url')).iss, 'steps-tracker-api');
  assert.equal((Number((spawnSync('stat', ['-f', '%Lp', output], {encoding: 'utf8'}).stdout.trim()))), 600);

  const refused = spawnSync(process.execPath, [join(repoRoot, 'k6/prepare-fixture.mjs')], {
    env: {...environment, DATABASE_URL: 'postgres://fixture:private@STEPTRACKER-API.ORG./app_capacity_test'},
    encoding: 'utf8',
  });
  assert.equal(refused.status, 2);
  assert.match(refused.stderr, /production database host is categorically forbidden/);
});

test('queue observer pins safe DB, indexed service query, boundary aggregates, and read-only cleanup', async () => {
  assert.equal(parseQueueDatabaseTarget('postgres://u:p@[::1]:5432/queue-test').hostname, '[::1]');
  assert.match(SERVICE_QUERY, /state IN \('queued','running'\)/);
  assert.match(SERVICE_QUERY, /retry_at IS NULL OR retry_at <=/);
  assert.match(SERVICE_QUERY, /not_before_at IS NULL OR not_before_at <=/);
  assert.match(SERVICE_QUERY, /GREATEST\([^;]*oldestRequestAgeMs/s);
  assert.match(SERVICE_QUERY, /GREATEST\([^;]*oldestClaimableAgeMs/s);
  assert.match(SERVICE_QUERY, /to_timestamp\(\$1 \/ 1000\.0\) AT TIME ZONE 'UTC'/);
  assert.doesNotMatch(SERVICE_QUERY, /\$1::timestamp/);
  assert.doesNotMatch(SERVICE_QUERY, /SUM\(generation\)|COUNT\(DISTINCT race_id\)/);
  assert.match(BOUNDARY_QUERY, /SUM\(generation\)/);
  assert.match(BOUNDARY_QUERY, /COUNT\(DISTINCT race_id\)/);
  assert.match(BOUNDARY_QUERY, /to_timestamp\(\$1 \/ 1000\.0\) AT TIME ZONE 'UTC'/);
  assert.match(BOUNDARY_QUERY, /to_timestamp\(\$2 \/ 1000\.0\) AT TIME ZONE 'UTC'/);
  assert.doesNotMatch(observerModule.SETUP_STATUS_QUERY, /state='superseded'/);
  assert.match(observerModule.SETUP_STATUS_QUERY, /j\.generation > expected\.generation/);
  assert.match(observerModule.SETUP_STATUS_QUERY, /j\.generation = expected\.generation AND j\.state='succeeded'/);
  assert.match(observerModule.SETUP_STATUS_QUERY, /j\.generation = expected\.generation AND j\.state='failed'/);
  const calls = [];
  const db = {query: async sql => {calls.push(sql); return {rows: []};}, release: () => calls.push('release')};
  const pool = {connect: async () => db, end: async () => calls.push('end')};
  await withQueueReadOnlyTransaction(pool, async client => client.query('SELECT 1'));
  assert.deepEqual(calls.slice(0, 3), ['BEGIN', 'SET TRANSACTION READ ONLY', "SET LOCAL statement_timeout = '2s'"]);
  assert.ok(calls.includes('ROLLBACK'));
  assert.deepEqual(calls.slice(-2), ['release', 'end']);
});

test('queue aggregation is aggregate-only and enforces clean barriers, lag, failure, drain, and overhead', () => {
  const samples = Array.from({length: 20}, (_, index) => ({atMs: index * 10000, measurementStartMs: 0, queued: index < 2 ? 1 : 0,
    running: 0, claimable: index < 2 ? 1 : 0, oldestRequestAgeMs: 1000,
    oldestClaimableAgeMs: index < 2 ? 30000 : 0, queryDurationMs: index === 0 ? 250 : 20}));
  const summary = summarizeQueueEvidence({samples, before: {failed: 2, generationSum: 10, distinctDirtyRaces: 0},
    after: {failed: 2, generationSum: 11, distinctDirtyRaces: 1, touchedTerminalSuccess: true}, measureSeconds: 20});
  assert.equal(summary.complete, true);
  assert.equal(summary.generationDelta, 1);
  assert.equal(summary.distinctDirtyRaces, 1);
  assert.equal(summary.newFailedJobs, 0);
  assert.equal('raceId' in summary, false);
  assert.equal(classifyQueueEvidence(summary).outcome, 'pass');
});

function runFakeRunner(command, {measureModes = ['pass'], queueModes = ['pass'], extraEnv = {}} = {}) {
  const root = mkdtempSync(join(tmpdir(), 'capacity-runner-'));
  const results = join(root, 'results');
  const fixturePath = join(root, 'fixture.json');
  const log = join(root, 'launch.log');
  const contextLog = join(root, 'context.log');
  const counter = join(root, 'counter');
  writeFileSync(fixturePath, JSON.stringify(fixture()));
  const fakeK6 = join(root, 'fake-k6.mjs');
  writeFileSync(fakeK6, `#!/usr/bin/env node
import {appendFileSync, existsSync, readFileSync, writeFileSync} from 'node:fs';
const phase = process.env.PHASE; appendFileSync(process.env.FAKE_LOG, phase + '\\n');
const contract = await import(process.env.CONTRACT_MODULE);
const fixtureDocument = JSON.parse(readFileSync(process.env.FIXTURE_PATH, 'utf8'));
const selectedWorkload = contract.selectWorkload(fixtureDocument, Number(process.env.WORKLOAD_USER_COUNT), {
  plannedMeasurementWriteSlots: Number(process.env.PLANNED_MEASURE_WRITE_SLOTS), seed: Number(process.env.RUN_SEED),
  verifiedQueue: process.env.VERIFIED_QUEUE === '1' && phase === 'measure',
});
const statusContexts = JSON.parse(readFileSync(process.env.STATUS_CONTEXT_PATH, 'utf8'));
const executedRoutes = process.env.COMMAND === 'smoke' && phase === 'measure'
  ? contract.PROFILE.routes : Array.from({length: Math.min(100, Number(process.env.PLANNED_REQUESTS))}, (_, iteration) => contract.routeForSlot(iteration, Number(process.env.RUN_SEED)));
for (const [iteration, route] of executedRoutes.entries()) {
  const selected = contract.buildIterationContext({route, iteration, runSeed: Number(process.env.RUN_SEED),
    writeOrdinalBase: Number(process.env.WRITE_ORDINAL_BASE), workload: selectedWorkload, fixture: fixtureDocument,
    statusContexts, baseUrl: process.env.BASE_URL, localDate: process.env.LOCAL_DATE,
    logicalEpochMs: Number(process.env.LOGICAL_EPOCH_MS), client: {appVersion:process.env.APP_VERSION,platform:process.env.PLATFORM,
      clientFeatures:process.env.CLIENT_FEATURES,userAgent:process.env.USER_AGENT,timezone:process.env.TIMEZONE,releaseChannel:process.env.RELEASE_CHANNEL},
    runId: process.env.RUN_ID, repeat: process.env.REPEAT_INDEX, phase});
  const request = contract.buildRequest(route, selected.context);
  appendFileSync(process.env.FAKE_CONTEXT_LOG, JSON.stringify({phase,route:route.key,userId:selected.context.user?.userId || null,
    authorization:request.params.headers.Authorization || null}) + '\\n');
}
let index = existsSync(process.env.FAKE_COUNTER) ? Number(readFileSync(process.env.FAKE_COUNTER, 'utf8')) : 0;
if (phase === 'measure') { writeFileSync(process.env.FAKE_COUNTER, String(index + 1)); }
const modes = process.env.FAKE_MODES.split(','); const mode = phase === 'measure' ? (modes[index] || modes.at(-1)) : 'pass';
if (mode === 'crash') process.exit(17); if (mode === 'missing') process.exit(0);
if (mode === 'malformed') { writeFileSync(process.env.SUMMARY_PATH, '{'); process.exit(0); }
if (mode === 'hang') await new Promise(resolve => setTimeout(resolve, 5000));
const routes = ${JSON.stringify(PROFILE.routes.map(route => route.key))};
const planned = Number(process.env.PLANNED_REQUESTS);
const endpointCounts = Object.fromEntries(routes.map(key => [key, 0]));
for (let iteration = 0; iteration < planned; iteration += 1) {
  const scheduled = process.env.COMMAND === 'smoke' && phase === 'measure'
    ? contract.PROFILE.routes[iteration] : contract.routeForSlot(iteration, Number(process.env.RUN_SEED));
  if (scheduled) endpointCounts[scheduled.key] += 1;
}
const summary = {complete:true, plannedMeasure:Number(process.env.PLANNED_REQUESTS), completedMeasure:Number(process.env.PLANNED_REQUESTS), dropped:0,
 failureRate:mode === 'fail' ? 0.02 : 0, rateLimitedRate:0, httpP95Ms:100, httpP99Ms:200, httpMaxMs:mode === 'overrun' ? 139637 : 500,
 criticalWriteP95Ms:120, criticalWriteP99Ms:240, criticalWriteMaxMs:500, contextFallbacks:0,
 endpointCounts, postcheckSuccesses:4, postcheckFailures:0, authFailures:0, runtimeFailures:0, generatorWarnings:[]};
writeFileSync(process.env.SUMMARY_PATH, JSON.stringify(summary)); process.exit(mode === 'fail' ? 99 : 0);`);
  execFileSync('chmod', ['700', fakeK6]);
  const fakeObserver = join(root, 'fake-observer.mjs');
  writeFileSync(fakeObserver, `#!/usr/bin/env node
import {existsSync,readFileSync,writeFileSync} from 'node:fs'; const args=process.argv.slice(2); const output=args[args.indexOf('--output')+1];
if (args[0] === 'barrier') { const contextsIndex=args.indexOf('--contexts'); if(contextsIndex>=0) { const contexts=JSON.parse(readFileSync(args[contextsIndex+1],'utf8')); if(contexts.length!==4) process.exit(2); } writeFileSync(output,JSON.stringify({complete:true,clean:true,setupVerified:true})); }
if (args[0] === 'seed') writeFileSync(output, JSON.stringify(Array.from({length:4},(_,seedIndex)=>({seedIndex,jobId:'fixture-job-'+seedIndex,generation:args.includes('measurement-setup')?2:1}))));
if (args[0] === 'postcheck') writeFileSync(output, JSON.stringify({postcheckSuccesses:4,postcheckFailures:0}));
if (args[0] === 'observe') { const ready=args[args.indexOf('--ready')+1]; const boundary=args[args.indexOf('--boundary-ready')+1]; writeFileSync(ready,'ready'); writeFileSync(boundary,'boundary-ready'); const index=existsSync(process.env.FAKE_COUNTER)?Number(readFileSync(process.env.FAKE_COUNTER,'utf8')):0; const mode=process.env.FAKE_QUEUE_MODES.split(',')[index]||'pass'; const evidence={complete:mode!=='invalid',observed:true,cadenceValid:true,distinctDirtyRaces:1,generationDelta:1,oldestClaimableAgeP95Ms:mode==='fail'?30001:0,newFailedJobs:0,finalQueued:0,finalRunning:0,allTouchedTerminalSuccess:true,observerQueryP95Ms:mode==='unverified'?101:1,observerQueryMaxMs:mode==='unverified'?251:2,sampleIntervalSeconds:10,drainSeconds:1}; writeFileSync(output, JSON.stringify(evidence)); }`);
  execFileSync('chmod', ['700', fakeObserver]);
  const queueRequired = command !== 'smoke';
  const env = {
    ...process.env, BASE_URL: 'http://127.0.0.1:3000', APP_VERSION: '9.9.9', PLATFORM: 'ios',
    CLIENT_FEATURES: 'compact-v1', USER_AGENT: 'Bara/9.9.9', TIMEZONE: 'UTC', RELEASE_CHANNEL: 'test',
    LOCAL_DATE: '2026-08-19', CORPUS_ID: 'corpus-a', WORKLOAD_USER_COUNT: '200', FIXTURE_PATH: fixturePath,
    RESULTS_ROOT: results, K6_BIN: fakeK6, QUEUE_OBSERVER_BIN: fakeObserver, SEED_HELPER_BIN: fakeObserver,
    FAKE_LOG: log, FAKE_CONTEXT_LOG: contextLog, CONTRACT_MODULE: join(repoRoot, 'k6/capacity-contract.mjs'), FAKE_COUNTER: counter,
    FAKE_MODES: measureModes.join(','), FAKE_QUEUE_MODES: queueModes.join(','), GENERATOR_CAPACITY_VERIFIED: '1', RUN_SEED: '7', LOGICAL_EPOCH_MS: '1755600120000',
    RPS: '100', START_RPS: '100', STEP_RPS: '100', MAX_RPS: String(measureModes.length * 100), WARMUP_DURATION: '1s', MEASURE_DURATION: '12s', SOAK_DURATION: '12s',
    ...(queueRequired ? {QUEUE_DATABASE_URL: 'postgres://u:p@127.0.0.1/db_capacity_test', BACKEND_REPO: root,
      QUEUE_TARGET_CONFIRMED: '1', RESOLUTION_WORKER_ENABLED: '1'} : {}), ...extraEnv,
  };
  const result = spawnSync(runner, [command], {cwd: repoRoot, env, encoding: 'utf8'});
  const artifactLine = result.stdout.split('\n').find(line => line.startsWith('artifacts: '));
  const artifact = artifactLine?.slice('artifacts: '.length);
  return {root, result, artifact, launches: existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n') : [],
    contexts: existsSync(contextLog) ? readFileSync(contextLog, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line)) : []};
}

test('runner executes warm-up process fully before measurement and produces secret-free smoke artifacts', () => {
  const run = runFakeRunner('smoke');
  assert.equal(run.result.status, 0, run.result.stderr);
  assert.deepEqual(run.launches, ['warmup', 'measure']);
  const result = JSON.parse(readFileSync(join(run.artifact, 'result.json')));
  assert.equal(result.httpOutcome, 'pass');
  assert.equal(result.queueOutcome, 'unverified');
  assert.equal(result.benchmarkOutcome, 'pass');
  const measuredContexts = run.contexts.filter(value => value.phase === 'measure');
  assert.equal(measuredContexts.length, PROFILE.routes.length);
  for (const value of measuredContexts) {
    if (value.route === 'assets_manifest') assert.equal(value.authorization, null);
    else if (value.route === 'race_resolution') assert.match(value.userId, /^seed-/);
    else assert.match(value.userId, /^workload-/);
  }
  const artifacts = readFileSync(join(run.artifact, 'effective-config.json'), 'utf8') + JSON.stringify(result);
  assert.ok(!artifacts.includes('signature'));
  assert.ok(!artifacts.includes('postgres://'));
});

test('runner maps complete threshold failure to 1 and crash/missing/malformed summaries to 2', () => {
  assert.equal(runFakeRunner('smoke', {measureModes: ['fail']}).result.status, 1);
  for (const mode of ['crash', 'missing', 'malformed']) assert.equal(runFakeRunner('smoke', {measureModes: [mode]}).result.status, 2);
});

test('request timeout overruns and k6 phases exceeding their parent deadline are invalid', () => {
  assert.equal(classifyHttpSummary(completeSummary({httpMaxMs: 16001})).outcome, 'invalid');
  assert.equal(runFakeRunner('smoke', {measureModes: ['overrun']}).result.status, 2);
  const shortGrace = runFakeRunner('smoke', {extraEnv: {K6_PARENT_GRACE_SECONDS: '1'}});
  assert.equal(shortGrace.result.status, 2);
  assert.match(shortGrace.result.stderr, /at least 15 seconds/);
  const startedAt = Date.now();
  const hung = runFakeRunner('find', {measureModes: ['hang'], extraEnv: {
    RPS: '1200', START_RPS: '1200', STEP_RPS: '1200', MAX_RPS: '1200',
    MEASURE_DURATION: '1s', K6_PARENT_GRACE_SECONDS: '1', CAPACITY_INTERNAL_TEST_MODE: '1',
  }});
  assert.equal(hung.result.status, 2);
  assert.deepEqual(hung.launches, ['warmup', 'measure']);
  assert.match(readFileSync(join(hung.artifact, 'run-01-measure.stderr.log'), 'utf8'), /exceeded parent deadline/);
  assert.match(JSON.stringify(JSON.parse(readFileSync(join(hung.artifact, 'result.json')))), /unexpected k6 exit 124/);
  assert.ok(Date.now() - startedAt < 4500, `parent deadline took ${Date.now() - startedAt}ms`);
});

test('find stops at first failed rung and confirmation requires 3/3', () => {
  const find = runFakeRunner('find', {measureModes: ['pass', 'fail', 'pass']});
  assert.equal(find.result.status, 1);
  assert.equal(find.launches.filter(value => value === 'measure').length, 2);
  assert.equal(JSON.parse(readFileSync(join(find.artifact, 'result.json'))).firstFailedRung, 200);
  const confirmed = runFakeRunner('confirm', {measureModes: ['pass', 'pass', 'pass']});
  assert.equal(confirmed.result.status, 0);
  assert.equal(JSON.parse(readFileSync(join(confirmed.artifact, 'result.json'))).httpConfirmed, true);
  const rejected = runFakeRunner('confirm', {measureModes: ['pass', 'pass', 'fail']});
  assert.equal(rejected.result.status, 1);
  assert.equal(JSON.parse(readFileSync(join(rejected.artifact, 'result.json'))).httpConfirmed, false);
});

test('verified commands reject missing queue evidence and soak remains independent', () => {
  const invalid = runFakeRunner('find', {extraEnv: {QUEUE_DATABASE_URL: ''}});
  assert.equal(invalid.result.status, 2);
  assert.equal(JSON.parse(readFileSync(join(invalid.artifact, 'result.json'))).benchmarkOutcome, 'invalid');
  const soak = runFakeRunner('soak');
  assert.equal(soak.result.status, 0);
  assert.equal(JSON.parse(readFileSync(join(soak.artifact, 'result.json'))).command, 'soak');
});

test('runner stops find on queue failure and preserves unverified/invalid precedence', () => {
  const queueFailed = runFakeRunner('find', {measureModes: ['pass', 'pass', 'pass'], queueModes: ['pass', 'fail', 'pass']});
  assert.equal(queueFailed.result.status, 1);
  assert.equal(queueFailed.launches.filter(value => value === 'measure').length, 2);
  const queueResult = JSON.parse(readFileSync(join(queueFailed.artifact, 'result.json')));
  assert.equal(queueResult.firstFailedRung, 200);
  assert.equal(queueResult.httpOutcome, 'pass');
  assert.equal(queueResult.queueOutcome, 'fail');
  const unverified = runFakeRunner('find', {measureModes: ['pass'], queueModes: ['unverified']});
  assert.equal(unverified.result.status, 2);
  assert.equal(JSON.parse(readFileSync(join(unverified.artifact, 'result.json'))).benchmarkOutcome, 'unverified');
  const invalidWins = runFakeRunner('find', {measureModes: ['fail'], queueModes: ['invalid']});
  assert.equal(invalidWins.result.status, 2);
  assert.equal(JSON.parse(readFileSync(join(invalidWins.artifact, 'result.json'))).benchmarkOutcome, 'invalid');
});

test('example and README contain placeholders and runtime paths are ignored', () => {
  const example = readFileSync(join(repoRoot, 'k6/fixture.example.json'), 'utf8');
  const readme = readFileSync(join(repoRoot, 'k6/README.md'), 'utf8');
  assert.ok(example.includes('<workload-test-user-id-001>'));
  assert.ok(readme.includes('<dedicated-test-user-id>'));
  assert.ok(!/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/.test(example + readme));
  const ignored = spawnSync('git', ['check-ignore', 'k6/fixture.json', 'k6/results/probe.json'], {cwd: repoRoot, encoding: 'utf8'});
  assert.equal(ignored.status, 0);
});

test('review regression: only resolution polling authenticates as a resolution seed', () => {
  assert.equal(typeof contractModule.buildIterationContext, 'function');
  const selected = selectWorkload(fixture(), 200, {plannedMeasurementWriteSlots: 200, seed: 17});
  const statusContexts = [{seedIndex: 0, jobId: 'job-0', generation: 3}];
  const common = {iteration: 4, runSeed: 17, writeOrdinalBase: 0, workload: selected,
    fixture: fixture(), statusContexts, baseUrl: 'http://127.0.0.1:3000', localDate: '2026-08-19',
    logicalEpochMs: 1787155320000, client, runId: 'run', repeat: 1, phase: 'measure'};
  const normal = contractModule.buildIterationContext({...common, route: PROFILE.routes.find(route => route.key === 'auth_me')});
  const resolution = contractModule.buildIterationContext({...common, route: PROFILE.routes.find(route => route.key === 'race_resolution')});
  assert.match(normal.context.user.userId, /^workload-/);
  assert.equal(resolution.context.user.userId, 'seed-0');
});

test('review regression: empty or incomplete aggregate run sets are invalid', () => {
  assert.equal(buildResult({command: 'confirm', runs: []}).benchmarkOutcome, 'invalid');
  assert.equal(buildResult({command: 'confirm', runs: [
    {rps: 10, httpOutcome: 'pass', queueOutcome: 'pass', benchmarkOutcome: 'pass', reasons: []},
    {rps: 10, httpOutcome: 'pass', queueOutcome: 'pass', benchmarkOutcome: 'pass', reasons: []},
  ]}).benchmarkOutcome, 'invalid');
  assert.equal(typeof contractModule.validateAggregateRuns, 'function');
  assert.equal(contractModule.validateAggregateRuns({command: 'soak', plan: [{rps: 10}]}, [null]).outcome, 'invalid');
  const passRun = rps => ({rps, httpOutcome:'pass', queueOutcome:'pass', benchmarkOutcome:'pass', reasons:[]});
  const failRun = rps => ({...passRun(rps), benchmarkOutcome:'fail', httpOutcome:'fail'});
  const findConfig = {command:'find', plan:[{rps:100},{rps:200},{rps:300}]};
  assert.equal(contractModule.validateAggregateRuns(findConfig, [passRun(100)]).outcome, 'invalid');
  assert.equal(contractModule.validateAggregateRuns(findConfig, [passRun(200), failRun(300)]).outcome, 'invalid');
  assert.equal(contractModule.validateAggregateRuns(findConfig, [passRun(100), failRun(200)]).outcome, 'pass');
  assert.equal(contractModule.validateAggregateRuns(findConfig, [failRun(100), passRun(200)]).outcome, 'invalid');
});

test('review regression: aggregate CLI writes invalid exit-2 evidence for missing, malformed, and empty run lists', () => {
  const root = mkdtempSync(join(tmpdir(), 'capacity-aggregate-'));
  const configPath = join(root, 'config.json');
  writeFileSync(configPath, JSON.stringify({command: 'confirm', targetHostname: '127.0.0.1', queueTargetConfirmed: true,
    client, corpusId: 'c', fixtureFingerprint: `sha256:${'a'.repeat(64)}`, workloadUserCount: 200,
    selectedActiveRaceCount: 200, generatorCapacityVerified: true, profileSha256: profileHash(),
    plan: [{rps: 10}, {rps: 10}, {rps: 10}]}));
  const malformed = join(root, 'malformed.json');
  writeFileSync(malformed, '{');
  const emptyObject = join(root, 'empty-object.json');
  writeFileSync(emptyObject, '{}');
  for (const [label, runs] of [['empty', ''], ['missing', join(root, 'missing.json')], ['malformed', malformed], ['empty-object', emptyObject]]) {
    const output = join(root, `${label}-result.json`);
    const execution = spawnSync(process.execPath, [join(repoRoot, 'k6/queue-observer.mjs'), 'aggregate',
      '--config', configPath, '--runs', runs, '--output', output], {encoding: 'utf8'});
    assert.equal(execution.status, 2, `${label}: ${execution.stderr}`);
    const result = JSON.parse(readFileSync(output, 'utf8'));
    assert.equal(result.benchmarkOutcome, 'invalid');
    assert.equal(result.httpConfirmed, false);
    assert.match(result.reasons.join(' '), /per-run|no per-run/);
  }
});

test('review regression: setup barriers and observer cadence fail closed', () => {
  assert.equal(typeof observerModule.classifySetupContexts, 'function');
  assert.equal(observerModule.classifySetupContexts({matched: 4, succeeded: 4, failed: 0, superseded: 0}).outcome, 'pass');
  assert.equal(observerModule.classifySetupContexts({matched: 4, succeeded: 3, failed: 1, superseded: 0}).outcome, 'invalid');
  assert.equal(observerModule.classifySetupContexts({matched: 4, succeeded: 3, failed: 0, superseded: 1}).outcome, 'invalid');
  assert.equal(typeof observerModule.validateSampleCadence, 'function');
  const complete = Array.from({length: 15}, (_, index) => ({atMs: index * 10000, queryDurationMs: 1}));
  assert.equal(observerModule.validateSampleCadence(complete, {startMs: 0, endMs: 140000}).valid, true);
  assert.equal(observerModule.validateSampleCadence(complete.filter((_, index) => index !== 5), {startMs: 0, endMs: 140000}).valid, false);
});

test('review regression: real observer CLI enforces exact setup jobs, cadence, drain, failure, and read-only fake-pg queries', async () => {
  const root = mkdtempSync(join(tmpdir(), 'capacity-observer-'));
  const backend = join(root, 'backend');
  const pgDirectory = join(backend, 'node_modules', 'pg');
  mkdirSync(pgDirectory, {recursive: true});
  writeFileSync(join(backend, 'package.json'), '{"private":true}\n');
  writeFileSync(join(pgDirectory, 'index.js'), `
const {appendFileSync} = require('node:fs');
let boundaryCount = 0;
class Pool {
  async connect() {
    return {query: async (sql, params = []) => {
      appendFileSync(process.env.FAKE_PG_LOG, String(sql).trim().split('\\n')[0] + '\\n');
      if (/state='superseded'/.test(String(sql))) throw new Error('unsupported RaceResolutionJobState literal');
      if ((String(sql).includes("state IN ('queued','running')") || String(sql).includes("COUNT(*) FILTER (WHERE state='failed')")) &&
          params.some(value => typeof value !== 'number' || !Number.isFinite(value))) {
        throw new Error('queue time boundaries must be numeric epoch milliseconds');
      }
      if (String(sql).includes("state IN ('queued','running')")) {
        const delay = Number(process.env.FAKE_SERVICE_DELAY_MS || 0);
        if (delay) await new Promise(resolve => setTimeout(resolve, delay));
        return {rows:[{queued:0,running:0,claimable:0,oldestRequestAgeMs:0,oldestClaimableAgeMs:0}]};
      }
      if (String(sql).includes('WITH expected AS')) {
        const mode = process.env.FAKE_SETUP_MODE || 'pass';
        return {rows:[{matched:4,succeeded:mode==='pass'?4:3,failed:mode==='failed'?1:0,superseded:mode==='superseded'?1:0}]};
      }
      if (String(sql).includes("COUNT(*) FILTER (WHERE state='failed')")) {
        boundaryCount += 1;
        return {rows:[{failed:process.env.FAKE_BOUNDARY_MODE==='failed'&&boundaryCount>=3?1:0,
          generationSum:boundaryCount===1?10:11,distinctDirtyRaces:boundaryCount===1?0:1,
          touchedNotTerminalSuccess:process.env.FAKE_BOUNDARY_MODE==='terminal'?1:0}]};
      }
      return {rows:[]};
    }, release: () => appendFileSync(process.env.FAKE_PG_LOG, 'release\\n')};
  }
  async end() { appendFileSync(process.env.FAKE_PG_LOG, 'end\\n'); }
}
module.exports={Pool};
`);
  const contexts = join(root, 'contexts.json');
  writeFileSync(contexts, JSON.stringify(Array.from({length: 4}, (_, index) => ({seedIndex:index,jobId:`job-${index}`,generation:2}))));
  const baseEnv = {...process.env, NODE_ENV:'test', OBSERVER_TEST_TIME_SCALE:'100', BACKEND_REPO:backend,
    QUEUE_DATABASE_URL:'postgres://u:p@127.0.0.1/db_capacity_test', BASE_URL:'http://127.0.0.1:3000',
    QUEUE_TARGET_CONFIRMED:'1', FAKE_PG_LOG:join(root, 'pg.log')};
  for (const [mode, expected] of [['pass', 0], ['failed', 2], ['superseded', 2]]) {
    const output = join(root, `barrier-${mode}.json`);
    const execution = spawnSync(process.execPath, [join(repoRoot, 'k6/queue-observer.mjs'), 'barrier', '--timeout', '30',
      '--contexts', contexts, '--output', output], {env:{...baseEnv,FAKE_SETUP_MODE:mode},encoding:'utf8'});
    assert.equal(execution.status, expected, execution.stderr);
    assert.equal(JSON.parse(readFileSync(output, 'utf8')).setupVerified, mode === 'pass');
  }
  const runObserve = async ({label, extraEnv = {}}) => {
    const ready = join(root, `${label}-ready`), done = join(root, `${label}-done`), boundaryReady = join(root, `${label}-boundary`);
    const output = join(root, `${label}.json`);
    const child = spawn(process.execPath, [join(repoRoot, 'k6/queue-observer.mjs'), 'observe', '--measure-seconds', '1',
      '--drain-seconds', '120', '--ready', ready, '--done', done, '--boundary-ready', boundaryReady, '--output', output],
    {env:{...baseEnv,...extraEnv},stdio:['ignore','pipe','pipe']});
    let stderr = '';
    child.stderr.on('data', chunk => { stderr += chunk; });
    const readyDeadline = Date.now() + 3000;
    while (!existsSync(ready) && Date.now() < readyDeadline) await new Promise(resolvePromise => setTimeout(resolvePromise, 2));
    assert.ok(existsSync(ready), `observer did not become ready: ${stderr}`);
    writeFileSync(done, 'done\n');
    const status = await new Promise(resolvePromise => child.on('close', resolvePromise));
    assert.equal(status, 0, stderr);
    return JSON.parse(readFileSync(output, 'utf8'));
  };
  const pass = await runObserve({label:'pass'});
  assert.equal(pass.complete, true);
  assert.equal(pass.cadenceValid, true);
  assert.equal(pass.finalQueued, 0);
  assert.equal(pass.finalRunning, 0);
  assert.equal(pass.boundaryQueryDurationsMs.length, 3);
  assert.ok(pass.sampleTimestampsMs.length >= 13);
  assert.equal(classifyQueueEvidence(pass).outcome, 'pass');
  const failed = await runObserve({label:'failed',extraEnv:{FAKE_BOUNDARY_MODE:'failed'}});
  assert.equal(classifyQueueEvidence(failed).outcome, 'fail');
  const late = await runObserve({label:'late',extraEnv:{FAKE_SERVICE_DELAY_MS:'180'}});
  assert.equal(late.complete, false);
  assert.equal(classifyQueueEvidence(late).outcome, 'invalid');
  const pgCalls = readFileSync(baseEnv.FAKE_PG_LOG, 'utf8').trim().split('\n');
  for (let index = 0; index < pgCalls.length; index += 1) {
    if (pgCalls[index] === 'BEGIN') assert.equal(pgCalls[index + 1], 'SET TRANSACTION READ ONLY');
  }
  assert.ok(pgCalls.includes("SET LOCAL statement_timeout = '2s'"));
});

test('review regression: five-minute buckets retain exact 12/17-minute offsets', () => {
  const logicalEpochMs = 1787155320000;
  const selected = selectWorkload(fixture(), 200, {plannedMeasurementWriteSlots: 200, seed: 1});
  const route = PROFILE.routes.find(candidate => candidate.key === 'steps_samples');
  const request = buildRequest(route, {baseUrl: 'http://127.0.0.1:3000', user: selected.users[0],
    localDate: '2026-08-19', logicalEpochMs, client, runId: 'run', repeat: 1, writeOrdinal: 0, phase: 'measure'});
  const samples = JSON.parse(request.body).samples;
  assert.equal(Date.parse(samples[0].periodEnd), logicalEpochMs - 12 * 60000);
  assert.equal(Date.parse(samples[1].periodEnd), logicalEpochMs - 17 * 60000);
  assert.ok(samples.every(sample => Date.parse(sample.periodEnd) % 300000 === 0));
});

test('review regression: profile hash definition covers every comparability algorithm', () => {
  assert.deepEqual(Object.keys(PROFILE.comparability).sort(), ['headers','payloads','phases','selector','vuAllocation'].sort());
  assert.match(JSON.stringify(PROFILE.comparability), /stable-hash/);
  assert.match(JSON.stringify(PROFILE.comparability), /five-minute/);
  assert.match(JSON.stringify(PROFILE.comparability), /ceil\(RPS \* 2\.5\)/);
  assert.notEqual(profileHash([{warmupSeconds:60,measureSeconds:300}]), profileHash([{warmupSeconds:120,measureSeconds:300}]));
});

test('review regression: measured write breadth derives from completed endpoint counts', () => {
  assert.equal(typeof contractModule.measuredWriteStats, 'function');
  const endpointCounts = Object.fromEntries(PROFILE.routes.map(route => [route.key, route.weight]));
  const stats = contractModule.measuredWriteStats({endpointCounts, completedMeasure: 100, workloadUserCount: 200, rps: 10});
  assert.equal(stats.completedWriteRequests, 18);
  assert.equal(stats.distinctMeasuredWriteUsers, 18);
  assert.equal(stats.completedWriteCycles, 0);
  assert.equal(stats.writesPerSelectedUser, 0.09);
  assert.equal(stats.minimumReuseIntervalSeconds, 0);
});

test('review regression: minimum reuse is the exact deterministic same-user write-slot gap', () => {
  const completedMeasure = 1400;
  const runSeed = 7;
  const workloadUserCount = 200;
  const rps = 100;
  const endpointCounts = Object.fromEntries(PROFILE.routes.map(route => [route.key, 0]));
  const writePositions = [];
  for (let iteration = 0; iteration < completedMeasure; iteration += 1) {
    const route = routeForSlot(iteration, runSeed);
    endpointCounts[route.key] += 1;
    if (route.method === 'POST') writePositions.push(iteration);
  }
  const expectedMinimum = Math.min(...writePositions.slice(workloadUserCount)
    .map((position, index) => (position - writePositions[index]) / rps));
  const stats = contractModule.measuredWriteStats({endpointCounts, completedMeasure, workloadUserCount, rps, runSeed});
  assert.equal(stats.minimumReuseIntervalSeconds, expectedMinimum);
  assert.notEqual(stats.minimumReuseIntervalSeconds, workloadUserCount / (rps * (writePositions.length / completedMeasure)));
});

test('review regression: README examples use the shipped cohort and exact user agent', () => {
  const readme = readFileSync(join(repoRoot, 'k6/README.md'), 'utf8');
  assert.doesNotMatch(readme, /active_impact_notices_v1/);
  assert.match(readme, /Bara\/2\.3\.8 CFNetwork\/3860\.700\.1 Darwin\/25\.6\.0/);
  assert.match(readme, /Dart\/3\.12 \(dart:io\)/);
});

test('review regression: approved specification records implementation state', () => {
  const specification = readFileSync(join(repoRoot, 'docs/simple-capacity-load-test-requirements.md'), 'utf8');
  assert.match(specification, /\*\*Status:\*\* Approved; implementation in progress\./);
  assert.doesNotMatch(specification, /awaiting owner approval/i);
});
