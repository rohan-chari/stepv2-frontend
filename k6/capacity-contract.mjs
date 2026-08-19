const PROFILE_DEFINITION = {
  name: 'capacity-benchmark-v1',
  routes: [
    {key: 'race_messages', method: 'GET', path: '/races/:id/messages?limit=50', weight: 26, context: 'activeRace', acceptedStatuses: [200], criticalWrite: false},
    {key: 'challenges_current', method: 'GET', path: '/challenges/current', weight: 9, context: 'workloadUser', acceptedStatuses: [200, 404], criticalWrite: false},
    {key: 'assets_manifest', method: 'GET', path: '/assets/manifest', weight: 9, context: 'none', acceptedStatuses: [200], criticalWrite: false},
    {key: 'race_resolution', method: 'GET', path: '/steps/race-resolution/:jobId?generation=N', weight: 7, context: 'resolutionSeed', acceptedStatuses: [200], criticalWrite: false},
    {key: 'steps_post', method: 'POST', path: '/steps', weight: 7, context: 'writeUser', acceptedStatuses: [200], criticalWrite: true},
    {key: 'races_list', method: 'GET', path: '/races?view=compact-v1', weight: 7, context: 'workloadUser', acceptedStatuses: [200], criticalWrite: false},
    {key: 'steps_samples', method: 'POST', path: '/steps/samples', weight: 6, context: 'writeUser', acceptedStatuses: [200], criticalWrite: true},
    {key: 'race_progress', method: 'GET', path: '/races/:id/progress?view=participants-v1&offset=0&limit=15', weight: 6, context: 'activeRace', acceptedStatuses: [200], criticalWrite: false},
    {key: 'auth_me', method: 'GET', path: '/auth/me', weight: 5, context: 'workloadUser', acceptedStatuses: [200], criticalWrite: false},
    {key: 'steps_sync_v2', method: 'POST', path: '/steps/sync-v2', weight: 5, context: 'writeUser', acceptedStatuses: [202], criticalWrite: true},
    {key: 'home_race_card', method: 'GET', path: '/home/race-card?view=shell-v1&homeActiveRaces=1&localDate=YYYY-MM-DD', weight: 5, context: 'workloadUser', acceptedStatuses: [200], criticalWrite: false},
    {key: 'suggested_races', method: 'GET', path: '/home/suggested-races', weight: 4, context: 'workloadUser', acceptedStatuses: [200], criticalWrite: false},
    {key: 'powerups_inventory', method: 'GET', path: '/powerups/inventory', weight: 4, context: 'workloadUser', acceptedStatuses: [200], criticalWrite: false},
  ],
  timeout: '15s',
  maxRedirects: 0,
  thresholds: {
    capacityFailureRateExclusive: 0.01,
    rateLimitedRateExclusive: 0.01,
    httpP95MsExclusive: 2000,
    httpP99MsExclusive: 5000,
    criticalWriteP95MsExclusive: 2000,
    criticalWriteP99MsExclusive: 5000,
    criticalWriteMaxMsExclusive: 15000,
  },
  comparability: {
    selector: '100-slot weighted route schedule; recorded-seed stable-hash read identity/race; command-wide without-replacement write ordinal',
    headers: {
      authenticated: ['Authorization','X-Timezone','X-Release-Channel','X-App-Version','X-Client-Features','User-Agent','X-Capacity-Run-Id','X-Capacity-Repeat'],
      assetManifest: ['X-Release-Channel'],
      jsonWrite: ['Content-Type: application/json'],
    },
    payloads: {
      steps: 'seeded integer 500..14000 at LOCAL_DATE',
      samples: 'two five-minute UTC buckets ending exactly 12m and 17m before logical epoch',
      syncV2: 'seeded steps plus three five-minute UTC buckets ending 7m/12m/17m before logical epoch and deterministic unique UUID idempotency key',
    },
    phases: {separateWarmupAndMeasurementProcesses: true, constantArrivalDuration: 'nominal duration minus 1 microsecond; scheduler accounting accepts at most one boundary arrival either side', smokeWarmupSeconds: 15, smokeMeasurementMaxSeconds: 300,
      findConfirmWarmupSeconds: 60, findConfirmMeasureSeconds: 300, soakWarmupSeconds: 120, soakMeasureSeconds: 1800, gracefulStopSeconds: 15},
    vuAllocation: {preAllocatedVUs: 'max(50, ceil(RPS * 2.5))', maxVUs: 'max(preAllocatedVUs, ceil(RPS * 6))'},
  },
};

export const PROFILE = deepFreeze(PROFILE_DEFINITION);
export const RESULT_SCHEMA_VERSION = 'simple-capacity-result-v1';
export const FIXTURE_SCHEMA_VERSION = 'simple-capacity-fixture-v1';
export const WRITE_WEIGHT = 18;

function deepFreeze(value) {
  if (!value || typeof value !== 'object' || Object.isFrozen(value)) return value;
  Object.freeze(value);
  for (const child of Object.values(value)) deepFreeze(child);
  return value;
}

function assertInteger(value, label, minimum = 0) {
  if (!Number.isInteger(value) || value < minimum) throw new Error(`${label} must be an integer >= ${minimum}`);
  return value;
}

function nonEmptyString(value, label) {
  if (typeof value !== 'string' || value.trim() === '') throw new Error(`${label} must be a non-empty string`);
  return value;
}

function exactKeys(value, expected, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${label} must be an object`);
  const actual = Object.keys(value).sort();
  const wanted = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) throw new Error(`${label} keys must be exactly ${wanted.join(', ')}`);
}

function stableHash(value, seed = 0) {
  let hash = (0x811c9dc5 ^ (Number(seed) >>> 0)) >>> 0;
  const input = String(value);
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

function rotr(value, count) {
  return (value >>> count) | (value << (32 - count));
}

// Small dependency-free SHA-256 implementation usable by Node and k6.
export function sha256(input) {
  const constants = [
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
  ];
  const bytes = unescape(encodeURIComponent(String(input))).split('').map(character => character.charCodeAt(0));
  const bitLength = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  const high = Math.floor(bitLength / 0x100000000);
  const low = bitLength >>> 0;
  for (let shift = 24; shift >= 0; shift -= 8) bytes.push((high >>> shift) & 0xff);
  for (let shift = 24; shift >= 0; shift -= 8) bytes.push((low >>> shift) & 0xff);
  const state = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
  for (let offset = 0; offset < bytes.length; offset += 64) {
    const words = new Array(64);
    for (let index = 0; index < 16; index += 1) {
      const at = offset + index * 4;
      words[index] = ((bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]) >>> 0;
    }
    for (let index = 16; index < 64; index += 1) {
      const x = words[index - 15];
      const y = words[index - 2];
      const s0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >>> 3);
      const s1 = rotr(y, 17) ^ rotr(y, 19) ^ (y >>> 10);
      words[index] = (words[index - 16] + s0 + words[index - 7] + s1) >>> 0;
    }
    let [a,b,c,d,e,f,g,h] = state;
    for (let index = 0; index < 64; index += 1) {
      const s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const choice = (e & f) ^ (~e & g);
      const t1 = (h + s1 + choice + constants[index] + words[index]) >>> 0;
      const s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const majority = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (s0 + majority) >>> 0;
      h=g; g=f; f=e; e=(d+t1)>>>0; d=c; c=b; b=a; a=(t1+t2)>>>0;
    }
    state[0]=(state[0]+a)>>>0; state[1]=(state[1]+b)>>>0; state[2]=(state[2]+c)>>>0; state[3]=(state[3]+d)>>>0;
    state[4]=(state[4]+e)>>>0; state[5]=(state[5]+f)>>>0; state[6]=(state[6]+g)>>>0; state[7]=(state[7]+h)>>>0;
  }
  return state.map(value => value.toString(16).padStart(8, '0')).join('');
}

export function profileHash(effectivePhases = null) {
  return sha256(JSON.stringify({profile: PROFILE_DEFINITION, effectivePhases}));
}

export function parseTarget(input, {allowNonprod = false} = {}) {
  nonEmptyString(input, 'BASE_URL');
  const match = /^(https?):\/\/([^/?#]+)\/?$/i.exec(input);
  if (!match) throw new Error('BASE_URL must be an absolute http(s) origin without path, query, or fragment');
  const protocol = `${match[1].toLowerCase()}:`;
  const authority = match[2];
  if (authority.includes('@')) throw new Error('BASE_URL must not contain userinfo');
  let hostname;
  let port = '';
  if (authority.startsWith('[')) {
    const ipv6 = /^\[([^\]]+)\](?::(\d+))?$/.exec(authority);
    if (!ipv6) throw new Error('BASE_URL contains a malformed IPv6 origin');
    hostname = ipv6[1];
    port = ipv6[2] || '';
  } else {
    const host = /^([^:]+)(?::(\d+))?$/.exec(authority);
    if (!host) throw new Error('BASE_URL contains a malformed hostname or port');
    hostname = host[1];
    port = host[2] || '';
  }
  hostname = hostname.toLowerCase().replace(/\.$/, '');
  if (!hostname || (port && (Number(port) < 1 || Number(port) > 65535))) throw new Error('BASE_URL contains an invalid host or port');
  if (hostname === 'steptracker-api.org' || (hostname.endsWith('.steptracker-api.org') && hostname !== 'staging.steptracker-api.org')) {
    throw new Error('production steptracker-api.org targets are categorically forbidden');
  }
  const loopback = hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '::1' || hostname === '[::1]';
  const staging = hostname === 'staging.steptracker-api.org';
  if (!loopback && !staging && !allowNonprod) throw new Error('unknown non-production target requires ALLOW_NONPROD_TARGET=1');
  const portSuffix = port ? `:${port}` : '';
  const canonicalHostname = hostname;
  const hostForUrl = canonicalHostname === '::1' ? '[::1]' : canonicalHostname;
  return {origin: `${protocol}//${hostForUrl}${portSuffix}`, hostname: canonicalHostname, loopback, staging};
}

function decodeBase64Url(input) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const normalized = String(input).replace(/-/g, '+').replace(/_/g, '/');
  let bits = 0;
  let bitCount = 0;
  let output = '';
  for (const character of normalized.replace(/=+$/, '')) {
    const index = alphabet.indexOf(character);
    if (index < 0) throw new Error('JWT payload is not base64url');
    bits = (bits << 6) | index;
    bitCount += 6;
    if (bitCount >= 8) {
      bitCount -= 8;
      output += String.fromCharCode((bits >>> bitCount) & 0xff);
    }
  }
  return decodeURIComponent(output.split('').map(character => `%${character.charCodeAt(0).toString(16).padStart(2, '0')}`).join(''));
}

export function decodeJwtClaims(token) {
  nonEmptyString(token, 'token');
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('token must be a JWT');
  let claims;
  try { claims = JSON.parse(decodeBase64Url(parts[1])); } catch { throw new Error('token JWT payload is malformed'); }
  if (!Number.isInteger(claims.exp)) throw new Error('token JWT exp must be an integer');
  return claims;
}

export function validateFixture(document, {corpusId, commandDeadlineSeconds = null} = {}) {
  exactKeys(document, ['schemaVersion','issuedAt','expiresAt','corpusId','cohortFingerprint','workloadUsers','resolutionSeeds'], 'fixture');
  if (document.schemaVersion !== FIXTURE_SCHEMA_VERSION) throw new Error(`fixture schemaVersion must be ${FIXTURE_SCHEMA_VERSION}`);
  assertInteger(document.issuedAt, 'fixture.issuedAt');
  assertInteger(document.expiresAt, 'fixture.expiresAt');
  nonEmptyString(document.corpusId, 'fixture.corpusId');
  if (corpusId !== undefined && document.corpusId !== corpusId) throw new Error('CORPUS_ID does not match fixture corpusId');
  if (!/^sha256:[a-f0-9]{64}$/.test(document.cohortFingerprint)) throw new Error('fixture cohortFingerprint must be sha256:<64 lowercase hex>');
  if (!Array.isArray(document.workloadUsers) || document.workloadUsers.length < 200) throw new Error('fixture requires at least 200 workloadUsers');
  if (!Array.isArray(document.resolutionSeeds) || document.resolutionSeeds.length !== 4) throw new Error('fixture requires exactly four resolutionSeeds');
  const identities = new Set();
  const workloadRaces = new Set();
  let earliestExpiry = Number.MAX_SAFE_INTEGER;
  for (const [index, user] of document.workloadUsers.entries()) {
    exactKeys(user, ['userId','token','activeRaceIds','activeRaceSetComplete'], `workloadUsers[${index}]`);
    nonEmptyString(user.userId, `workloadUsers[${index}].userId`);
    nonEmptyString(user.token, `workloadUsers[${index}].token`);
    if (identities.has(user.userId)) throw new Error('fixture identities must be distinct');
    identities.add(user.userId);
    if (user.activeRaceSetComplete !== true) throw new Error('every workload user must declare complete ACTIVE race context');
    if (!Array.isArray(user.activeRaceIds) || user.activeRaceIds.length === 0) throw new Error('every workload user requires at least one ACTIVE race');
    const localRaces = new Set();
    for (const raceId of user.activeRaceIds) {
      nonEmptyString(raceId, 'activeRaceId');
      if (localRaces.has(raceId)) throw new Error('activeRaceIds must be unique within each workload user');
      localRaces.add(raceId); workloadRaces.add(raceId);
    }
    const claims = decodeJwtClaims(user.token);
    if (claims.sub !== user.userId || claims.iss !== 'steps-tracker-api') throw new Error('fixture JWT subject/issuer mismatch');
    earliestExpiry = Math.min(earliestExpiry, claims.exp);
  }
  const seedRaces = new Set();
  for (const [index, seed] of document.resolutionSeeds.entries()) {
    exactKeys(seed, ['userId','token','raceId'], `resolutionSeeds[${index}]`);
    nonEmptyString(seed.userId, `resolutionSeeds[${index}].userId`);
    nonEmptyString(seed.token, `resolutionSeeds[${index}].token`);
    nonEmptyString(seed.raceId, `resolutionSeeds[${index}].raceId`);
    if (identities.has(seed.userId)) throw new Error('seed identities must be distinct from workload identities');
    identities.add(seed.userId);
    if (seedRaces.has(seed.raceId)) throw new Error('resolution seed races must be mutually distinct');
    if (workloadRaces.has(seed.raceId)) throw new Error('resolution seed race cannot occur in workload ACTIVE race sets');
    seedRaces.add(seed.raceId);
    const claims = decodeJwtClaims(seed.token);
    if (claims.sub !== seed.userId || claims.iss !== 'steps-tracker-api') throw new Error('fixture JWT subject/issuer mismatch');
    earliestExpiry = Math.min(earliestExpiry, claims.exp);
  }
  if (document.expiresAt !== earliestExpiry) throw new Error('fixture expiresAt must equal the earliest decoded JWT exp');
  if (commandDeadlineSeconds !== null && earliestExpiry <= commandDeadlineSeconds) throw new Error('fixture tokens expire before the complete command deadline');
  return document;
}

export function routeForSlot(iterationIndex, seed = 0) {
  assertInteger(iterationIndex, 'iterationIndex');
  const slot = (iterationIndex + (Number(seed) >>> 0)) % 100;
  let end = 0;
  for (const route of PROFILE.routes) {
    end += route.weight;
    if (slot < end) return route;
  }
  throw new Error('profile weights do not cover 100 slots');
}

export function countWriteSlots(plannedRequests, seed = 0) {
  assertInteger(plannedRequests, 'plannedRequests');
  const blocks = Math.floor(plannedRequests / 100);
  let count = blocks * WRITE_WEIGHT;
  for (let index = blocks * 100; index < plannedRequests; index += 1) {
    if (routeForSlot(index, seed).method === 'POST') count += 1;
  }
  return count;
}

export function selectWorkload(document, count, {plannedMeasurementWriteSlots, seed = 0, verifiedQueue = false} = {}) {
  assertInteger(count, 'WORKLOAD_USER_COUNT', 200);
  if (count > document.workloadUsers.length) throw new Error('WORKLOAD_USER_COUNT exceeds fixture cohort size');
  if (verifiedQueue && (!Number.isInteger(plannedMeasurementWriteSlots) || count > plannedMeasurementWriteSlots)) {
    throw new Error('verified queue WORKLOAD_USER_COUNT cannot exceed planned measurement write slots');
  }
  const users = [...document.workloadUsers]
    .sort((left, right) => stableHash(left.userId, seed) - stableHash(right.userId, seed) || left.userId.localeCompare(right.userId))
    .slice(0, count);
  const activeRaces = new Set(users.flatMap(user => user.activeRaceIds));
  const phaseOffsets = {warmup: 0, setup: 1_000_000_000, measure: 2_000_000_000, postcheck: 3_000_000_000};
  return {
    users,
    distinctMeasuredWriteUsers: Math.min(count, Number(plannedMeasurementWriteSlots) || 0),
    distinctActiveRaceCount: activeRaces.size,
    userForWriteOrdinal(ordinal) { assertInteger(ordinal, 'write ordinal'); return users[ordinal % users.length]; },
    payloadOrdinal(phase, ordinal) {
      if (!(phase in phaseOffsets)) throw new Error(`unknown phase ${phase}`);
      assertInteger(ordinal, 'phase write ordinal');
      return phaseOffsets[phase] + ordinal;
    },
  };
}

export function buildIterationContext({route, iteration, runSeed, writeOrdinalBase, workload, fixture,
  statusContexts = [], baseUrl, localDate, logicalEpochMs, client, runId, repeat, phase}) {
  assertInteger(iteration, 'iteration');
  const writeOrdinal = writeOrdinalBase + countWriteSlots(iteration, runSeed);
  const readUserIndex = stableHash(`read-user:${route.key}:${iteration}`, runSeed) % workload.users.length;
  const workloadUser = route.method === 'POST'
    ? workload.userForWriteOrdinal(writeOrdinal)
    : workload.users[readUserIndex];
  const raceIndex = stableHash(`read-race:${route.key}:${iteration}:${workloadUser.userId}`, runSeed)
    % workloadUser.activeRaceIds.length;
  const resolutionStatus = route.context === 'resolutionSeed' && statusContexts.length > 0
    ? statusContexts[stableHash(`resolution-status:${iteration}`, runSeed) % statusContexts.length]
    : null;
  const resolutionSeed = resolutionStatus ? fixture.resolutionSeeds[resolutionStatus.seedIndex] : null;
  return {
    contextFallback: route.context === 'resolutionSeed' && !resolutionStatus,
    context: {
      baseUrl,
      user: route.context === 'resolutionSeed' ? resolutionSeed : workloadUser,
      raceId: workloadUser.activeRaceIds[raceIndex],
      resolutionJob: resolutionStatus ? {jobId: resolutionStatus.jobId, generation: resolutionStatus.generation} : null,
      localDate, logicalEpochMs, client, runId, repeat, iteration, writeOrdinal, phase,
    },
  };
}

function deterministicRange(ordinal, minimum, maximum, salt) {
  return minimum + (stableHash(`${ordinal}:${salt}`) % (maximum - minimum + 1));
}

function uuidFor(scope) {
  const hex = `${sha256(scope)}${sha256(`more:${scope}`)}`.slice(0, 32).split('');
  hex[12] = '4';
  hex[16] = ((parseInt(hex[16], 16) & 3) | 8).toString(16);
  const value = hex.join('');
  return `${value.slice(0,8)}-${value.slice(8,12)}-${value.slice(12,16)}-${value.slice(16,20)}-${value.slice(20)}`;
}

export function validateLogicalEpochMs(logicalEpochMs) {
  if (!Number.isInteger(logicalEpochMs) || logicalEpochMs <= 0 || logicalEpochMs % 300000 !== 120000) {
    throw new Error('LOGICAL_EPOCH_MS must be a positive integer anchored two minutes after a five-minute UTC boundary');
  }
  return logicalEpochMs;
}

function alignedSample(logicalEpochMs, minutesBefore, ordinal) {
  validateLogicalEpochMs(logicalEpochMs);
  const bucketEnd = logicalEpochMs - minutesBefore * 60000;
  return {periodStart: new Date(bucketEnd - 300000).toISOString(), periodEnd: new Date(bucketEnd).toISOString(),
    steps: deterministicRange(ordinal, 20, 140, `sample-${minutesBefore}`), sourceName: 'k6-capacity-benchmark-v1'};
}

export function buildRequest(route, context) {
  if (!PROFILE.routes.some(candidate => candidate.key === route.key)) throw new Error('route is not part of the pinned profile');
  const phase = context.phase || 'measure';
  let path = route.path;
  if (path.includes(':id')) path = path.replace(':id', encodeURIComponent(nonEmptyString(context.raceId, 'raceId')));
  if (path.includes(':jobId')) {
    const job = context.resolutionJob;
    if (!job || !Number.isInteger(job.generation)) throw new Error('resolutionJob with integer generation is required');
    path = path.replace(':jobId', encodeURIComponent(nonEmptyString(job.jobId, 'resolutionJob.jobId'))).replace('generation=N', `generation=${job.generation}`);
  }
  path = path.replace('localDate=YYYY-MM-DD', `localDate=${encodeURIComponent(nonEmptyString(context.localDate, 'LOCAL_DATE'))}`);
  const headers = route.key === 'assets_manifest' ? {'X-Release-Channel': context.client.releaseChannel} : {
    Authorization: `Bearer ${nonEmptyString(context.user?.token, 'user token')}`,
    'X-Timezone': context.client.timezone,
    'X-Release-Channel': context.client.releaseChannel,
    'X-App-Version': context.client.appVersion,
    'X-Client-Features': context.client.clientFeatures,
    'User-Agent': context.client.userAgent,
    'X-Capacity-Run-Id': context.runId,
    'X-Capacity-Repeat': String(context.repeat),
  };
  let body = null;
  const ordinal = Number(context.writeOrdinal || 0);
  if (route.method === 'POST') {
    headers['Content-Type'] = 'application/json';
    if (route.key === 'steps_post') body = JSON.stringify({date: context.localDate, steps: deterministicRange(ordinal, 500, 14000, route.key)});
    if (route.key === 'steps_samples') body = JSON.stringify({samples: [alignedSample(context.logicalEpochMs, 12, ordinal), alignedSample(context.logicalEpochMs, 17, ordinal)]});
    if (route.key === 'steps_sync_v2') {
      headers['Idempotency-Key'] = uuidFor(`${context.runId}:${context.repeat}:${phase}:${ordinal}`);
      body = JSON.stringify({date: context.localDate, steps: deterministicRange(ordinal, 500, 14000, route.key),
        samples: [alignedSample(context.logicalEpochMs, 7, ordinal), alignedSample(context.logicalEpochMs, 12, ordinal), alignedSample(context.logicalEpochMs, 17, ordinal)]});
    }
  }
  return {method: route.method, url: `${context.baseUrl}${path}`, body, acceptedStatuses: route.acceptedStatuses,
    params: {headers, timeout: '15s', redirects: 0, tags: {phase, endpoint: route.key, critical_write: route.criticalWrite ? 'true' : 'false'}}};
}

export function classifyStatus(route, status) {
  if (route.acceptedStatuses.includes(status)) return 'accepted';
  if (status === 0 || status === 401 || status === 403) return 'invalid';
  return 'capacity-failure';
}

export function parseDurationSeconds(input) {
  nonEmptyString(input, 'duration');
  const match = /^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/.exec(input);
  if (!match || !match.slice(1).some(Boolean)) throw new Error(`invalid duration: ${input}`);
  const seconds = Number(match[1] || 0) * 3600 + Number(match[2] || 0) * 60 + Number(match[3] || 0);
  if (!Number.isSafeInteger(seconds) || seconds <= 0) throw new Error('duration must be positive');
  return seconds;
}

export function k6ArrivalDuration(durationSeconds) {
  assertInteger(durationSeconds, 'durationSeconds', 1);
  return `${durationSeconds * 1000 - 0.001}ms`;
}

export function schedulerAccountingComplete(planned, completed, dropped) {
  for (const [value, label] of [[planned, 'planned'], [completed, 'completed'], [dropped, 'dropped']]) {
    assertInteger(value, label);
  }
  return Math.abs(completed + dropped - planned) <= 1;
}

export function vuAllocation(rps) {
  if (!Number.isFinite(rps) || rps <= 0) throw new Error('RPS must be positive');
  const preAllocatedVUs = Math.max(50, Math.ceil(rps * 2.5));
  return {preAllocatedVUs, maxVUs: Math.max(preAllocatedVUs, Math.ceil(rps * 6))};
}

export function expectedSyncReservationsMax(rps, warmupSeconds, measureSeconds) {
  return Math.ceil(0.05 * rps * (warmupSeconds + measureSeconds)) + 12;
}

export function operatingLimit(confirmedRps) {
  if (!Number.isFinite(confirmedRps) || confirmedRps < 0) throw new Error('confirmedRps must be non-negative');
  return Math.floor(confirmedRps * 0.70);
}

export function measuredWriteStats({endpointCounts, completedMeasure, workloadUserCount, rps, runSeed = 0, smoke = false}) {
  const completedWriteRequests = PROFILE.routes
    .filter(route => route.method === 'POST')
    .reduce((sum, route) => sum + Number(endpointCounts?.[route.key] || 0), 0);
  if (!Number.isFinite(completedWriteRequests) || completedWriteRequests < 0 || !Number.isFinite(completedMeasure) || completedMeasure < 0) {
    throw new Error('completed write metrics must be finite and non-negative');
  }
  const writePositions = [];
  for (let iteration = 0; iteration < completedMeasure; iteration += 1) {
    const route = smoke ? PROFILE.routes[iteration] : routeForSlot(iteration, runSeed);
    if (route?.method === 'POST') writePositions.push(iteration);
  }
  if (writePositions.length !== completedWriteRequests) throw new Error('completed endpoint counts do not match deterministic write-slot ordinals');
  let minimumReuseIntervalSeconds = 0;
  if (completedWriteRequests > workloadUserCount) {
    let minimumGapIterations = Number.POSITIVE_INFINITY;
    for (let index = workloadUserCount; index < writePositions.length; index += 1) {
      minimumGapIterations = Math.min(minimumGapIterations, writePositions[index] - writePositions[index - workloadUserCount]);
    }
    minimumReuseIntervalSeconds = minimumGapIterations / rps;
  }
  return {
    completedWriteRequests,
    distinctMeasuredWriteUsers: Math.min(workloadUserCount, completedWriteRequests),
    completedWriteCycles: Math.floor(completedWriteRequests / workloadUserCount),
    writesPerSelectedUser: completedWriteRequests / workloadUserCount,
    minimumReuseIntervalSeconds,
  };
}

export function commandPlan(command, options = {}) {
  const duration = (value, fallback) => value === undefined ? fallback : (typeof value === 'number' ? value : parseDurationSeconds(value));
  if (command === 'smoke') return [{index: 1, rps: 1, warmupSeconds: duration(options.warmupDuration, 15), measureSeconds: duration(options.measureDuration, 30), smoke: true}];
  if (command === 'find') {
    const start = Number(options.startRps), step = Number(options.stepRps), max = Number(options.maxRps);
    for (const [value, label] of [[start,'START_RPS'],[step,'STEP_RPS'],[max,'MAX_RPS']]) if (!Number.isInteger(value) || value <= 0) throw new Error(`${label} must be a positive integer`);
    if (start > max) throw new Error('START_RPS cannot exceed MAX_RPS');
    const runs = [];
    for (let rps = start; rps <= max; rps += step) runs.push({index: runs.length + 1, rps, warmupSeconds: duration(options.warmupDuration, 60), measureSeconds: duration(options.measureDuration, 300), smoke: false});
    return runs;
  }
  if (command === 'confirm') {
    const rps = Number(options.rps); if (!Number.isInteger(rps) || rps <= 0) throw new Error('RPS must be a positive integer');
    return Array.from({length: 3}, (_, index) => ({index: index + 1, rps, warmupSeconds: duration(options.warmupDuration, 60), measureSeconds: duration(options.measureDuration, 300), smoke: false}));
  }
  if (command === 'soak') {
    const rps = Number(options.rps); if (!Number.isInteger(rps) || rps <= 0) throw new Error('RPS must be a positive integer');
    return [{index: 1, rps, warmupSeconds: duration(options.warmupDuration, 120), measureSeconds: duration(options.soakDuration, 1800), smoke: false}];
  }
  throw new Error('command must be smoke, find, confirm, or soak');
}

export function computeCommandDeadline(nowSeconds, runs, {smoke = false} = {}) {
  assertInteger(Math.floor(nowSeconds), 'nowSeconds');
  let total = 300;
  for (const run of runs) {
    if (smoke || run.smoke) {
      // Smoke has no queue baselines/drains. Its thirteen-request measurement uses
      // the pinned five-minute maxDuration rather than the nominal phase duration.
      total += 15 + run.warmupSeconds + 15 + 15 + 300 + 15 + 15 + 60;
    } else {
      total += 30 + 15 + run.warmupSeconds + 15 + 120 + 15 + 120 + run.measureSeconds + 15 + 120 + 15 + 60;
    }
  }
  return Math.floor(nowSeconds) + total;
}

function finiteMetric(summary, key) {
  return typeof summary?.[key] === 'number' && Number.isFinite(summary[key]);
}

export function classifyHttpSummary(summary, {generatorCapacityVerified = false, processExitCode = 0, phase = 'measure'} = {}) {
  const reasons = [];
  const required = ['plannedMeasure','completedMeasure','dropped','failureRate','rateLimitedRate','httpP95Ms','httpP99Ms','httpMaxMs','criticalWriteP95Ms','criticalWriteP99Ms','criticalWriteMaxMs','contextFallbacks','postcheckSuccesses','postcheckFailures','authFailures','runtimeFailures'];
  if (![0, 99].includes(processExitCode)) return {outcome: 'invalid', reasons: [`unexpected k6 exit ${processExitCode}`]};
  if (!summary || summary.complete !== true || required.some(key => !finiteMetric(summary, key)) || !summary.endpointCounts || !Array.isArray(summary.generatorWarnings)) {
    return {outcome: 'invalid', reasons: ['missing or malformed summary fields']};
  }
  if (summary.generatorWarnings.length > 0) return {outcome: 'invalid', reasons: ['generator warning: ' + summary.generatorWarnings.join('; ')]};
  if (summary.authFailures > 0) return {outcome: 'invalid', reasons: ['authentication or authorization failure']};
  if (summary.runtimeFailures > 0) return {outcome: 'invalid', reasons: ['network/runtime response status 0']};
  if (summary.httpMaxMs > 16000) return {outcome: 'invalid', reasons: ['HTTP request materially exceeded the configured 15s timeout']};
  if (!schedulerAccountingComplete(summary.plannedMeasure, summary.completedMeasure, summary.dropped)) return {outcome: 'invalid', reasons: ['scheduler accounting mismatch']};
  if (summary.dropped > 0 && !generatorCapacityVerified) return {outcome: 'invalid', reasons: ['dropped arrivals without generator capacity attestation']};
  if (summary.dropped > 0) reasons.push('dropped arrivals');
  if (summary.contextFallbacks !== 0) return {outcome: 'invalid', reasons: ['warm-up/measurement context fallback occurred']};
  if (phase !== 'warmup') {
    if (summary.failureRate >= 0.01) reasons.push('capacity failure rate is not below 1%');
    if (summary.rateLimitedRate >= 0.01) reasons.push('rate-limited response rate is not below 1%');
    for (const route of PROFILE.routes) if (!finiteMetric(summary.endpointCounts, route.key) || summary.endpointCounts[route.key] < 1) reasons.push(`endpoint ${route.key} did not execute`);
  }
  if (phase === 'measure') {
    if (summary.httpP95Ms >= 2000) reasons.push('HTTP p95 is not below 2s');
    if (summary.httpP99Ms >= 5000) reasons.push('HTTP p99 is not below 5s');
    if (summary.criticalWriteP95Ms >= 2000) reasons.push('critical-write p95 is not below 2s');
    if (summary.criticalWriteP99Ms >= 5000) reasons.push('critical-write p99 is not below 5s');
    if (summary.criticalWriteMaxMs >= 15000) reasons.push('critical-write maximum is not below 15s');
    if (summary.postcheckSuccesses !== 4 || summary.postcheckFailures !== 0) reasons.push('public resolution postcheck did not succeed for all four seeds');
  }
  if (processExitCode === 99 && reasons.length === 0) return {outcome: 'invalid', reasons: ['threshold exit without a classified gate failure']};
  return {outcome: reasons.length ? 'fail' : 'pass', reasons};
}

function percentile(values, percentileValue) {
  if (!values.length) return null;
  const sorted = [...values].sort((a,b) => a-b);
  return sorted[Math.ceil(percentileValue * sorted.length) - 1];
}

export function classifyQueueEvidence(queue) {
  if (queue === null || queue === undefined) return {outcome: 'unverified', reasons: ['queue observer was not configured']};
  const required = ['distinctDirtyRaces','generationDelta','oldestClaimableAgeP95Ms','newFailedJobs','observerQueryP95Ms','observerQueryMaxMs','finalQueued','finalRunning','drainSeconds','sampleIntervalSeconds'];
  if (queue.complete !== true || queue.observed !== true || queue.cadenceValid !== true || required.some(key => !finiteMetric(queue, key)) || typeof queue.allTouchedTerminalSuccess !== 'boolean') {
    return {outcome: 'invalid', reasons: ['incomplete or malformed queue evidence']};
  }
  if (queue.observerQueryP95Ms > 100 || queue.observerQueryMaxMs > 250) return {outcome: 'unverified', reasons: ['queue observer exceeded its overhead budget']};
  const reasons = [];
  if (queue.distinctDirtyRaces < 1) reasons.push('no measured dirty race observed');
  if (queue.generationDelta < 1) reasons.push('no measured queue generation observed');
  if (queue.newFailedJobs > 0) reasons.push('new failed resolution job observed');
  if (queue.oldestClaimableAgeP95Ms > 30000) reasons.push('claimable queue age p95 exceeded 30s');
  if (queue.finalQueued !== 0 || queue.finalRunning !== 0) reasons.push('queue did not fully drain');
  if (!queue.allTouchedTerminalSuccess) reasons.push('not every measured race row became terminally successful');
  return {outcome: reasons.length ? 'fail' : 'pass', reasons};
}

const precedence = {pass: 0, fail: 1, unverified: 2, invalid: 3};
function worstOutcome(outcomes) {
  return outcomes.reduce((worst, value) => precedence[value] > precedence[worst] ? value : worst, 'pass');
}

export function validateAggregateRuns(config, runs) {
  if (!Array.isArray(runs) || runs.length === 0) return {outcome: 'invalid', reason: 'no per-run result artifacts were supplied'};
  const validOutcomes = new Set(['pass','fail','unverified','invalid']);
  for (const run of runs) {
    if (!run || typeof run !== 'object' || !Number.isFinite(Number(run.rps)) ||
      !validOutcomes.has(run.benchmarkOutcome) || !['pass','fail','invalid'].includes(run.httpOutcome) ||
      !validOutcomes.has(run.queueOutcome) || !Array.isArray(run.reasons)) {
      return {outcome: 'invalid', reason: 'a per-run result artifact is missing or malformed'};
    }
  }
  const command = config?.command;
  const expectedCount = command === 'confirm' ? 3 : (command === 'smoke' || command === 'soak' ? 1 : null);
  if (expectedCount !== null && runs.length !== expectedCount) {
    return {outcome: 'invalid', reason: `${command} requires exactly ${expectedCount} per-run result artifact(s)`};
  }
  const plan = Array.isArray(config?.plan) ? config.plan : [];
  if (plan.length > 0) {
    if (runs.length > plan.length) return {outcome: 'invalid', reason: 'per-run results exceed the configured plan'};
    for (let index = 0; index < runs.length; index += 1) {
      if (Number(runs[index].rps) !== Number(plan[index]?.rps)) return {outcome: 'invalid', reason: 'per-run results do not match the configured rung sequence'};
    }
    if (command !== 'find' && runs.length !== plan.length) return {outcome: 'invalid', reason: 'per-run result count does not match the configured plan'};
    if (command === 'find' && runs.length < plan.length && runs[runs.length - 1].benchmarkOutcome === 'pass') {
      return {outcome: 'invalid', reason: 'find stopped before a non-pass rung'};
    }
    if (command === 'find' && runs.slice(0, -1).some(run => run.benchmarkOutcome !== 'pass')) {
      return {outcome: 'invalid', reason: 'find contains results after its first non-pass rung'};
    }
  }
  return {outcome: 'pass', reason: null};
}

function safeRun(run) {
  const queue = run.queue && typeof run.queue === 'object' ? {
    observed: Boolean(run.queue.observed), cadenceValid: run.queue.cadenceValid === true, sampleIntervalSeconds: Number(run.queue.sampleIntervalSeconds || 0),
    distinctDirtyRaces: Number(run.queue.distinctDirtyRaces || 0), generationDelta: Number(run.queue.generationDelta || 0),
    oldestClaimableAgeP95Ms: Number(run.queue.oldestClaimableAgeP95Ms || 0), drainSeconds: Number(run.queue.drainSeconds || 0),
    newFailedJobs: Number(run.queue.newFailedJobs || 0), observerQueryP95Ms: Number(run.queue.observerQueryP95Ms || 0),
    observerQueryMaxMs: Number(run.queue.observerQueryMaxMs || 0), finalQueued: Number(run.queue.finalQueued || 0), finalRunning: Number(run.queue.finalRunning || 0),
  } : undefined;
  return {
    rps: Number(run.rps || 0), plannedTotal: Number(run.plannedTotal || run.plannedMeasure || 0), plannedMeasure: Number(run.plannedMeasure || 0),
    completedMeasure: Number(run.completedMeasure || 0), dropped: Number(run.dropped || 0), expectedSyncReservationsMax: Number(run.expectedSyncReservationsMax || 0),
    offeredWriteRequests: Number(run.offeredWriteRequests || 0), completedWriteRequests: Number(run.completedWriteRequests || 0),
    completedWriteCycles: Number(run.completedWriteCycles || 0),
    writesPerSelectedUser: Number(run.writesPerSelectedUser || 0), minimumReuseIntervalSeconds: Number(run.minimumReuseIntervalSeconds || 0),
    ...(queue ? {queue} : {}), gates: run.gates && typeof run.gates === 'object' ? run.gates : {},
    benchmarkOutcome: run.benchmarkOutcome, httpOutcome: run.httpOutcome, queueOutcome: run.queueOutcome,
    reasons: Array.isArray(run.reasons) ? run.reasons.map(String) : [],
  };
}

export function buildResult(input) {
  const rawRuns = Array.isArray(input.runs) ? input.runs : [];
  const aggregateValidation = validateAggregateRuns({command: input.command, plan: input.plan}, rawRuns);
  const runs = rawRuns.filter(run => run && typeof run === 'object').map(safeRun);
  const command = input.command;
  let httpOutcome = worstOutcome(runs.map(run => run.httpOutcome).filter(Boolean));
  let queueOutcome = worstOutcome(runs.map(run => run.queueOutcome).filter(Boolean));
  let benchmarkOutcome = worstOutcome(runs.map(run => run.benchmarkOutcome).filter(Boolean));
  if (aggregateValidation.outcome === 'invalid') {
    benchmarkOutcome = 'invalid';
    httpOutcome = 'invalid';
    queueOutcome = command === 'smoke' ? 'unverified' : 'invalid';
  } else if (command === 'smoke' && httpOutcome === 'pass') benchmarkOutcome = 'pass';
  const result = {
    schemaVersion: RESULT_SCHEMA_VERSION,
    command,
    benchmarkOutcome,
    httpOutcome,
    queueOutcome: command === 'smoke' && runs.every(run => run.queueOutcome === 'unverified') ? 'unverified' : queueOutcome,
    httpConfirmed: command === 'confirm' && runs.length === 3 && runs.every(run => run.httpOutcome === 'pass'),
    queueConfirmed: command === 'confirm' && runs.length === 3 && runs.every(run => run.queueOutcome === 'pass'),
    systemTelemetryVerified: false,
    reasons: [...new Set([...(aggregateValidation.reason ? [aggregateValidation.reason] : []), ...runs.flatMap(run => run.reasons)])],
    profile: {name: PROFILE.name, sha256: input.profileSha256 || profileHash()},
    targetHostname: String(input.targetHostname || ''),
    queueTargetConfirmed: input.queueTargetConfirmed === true,
    client: {
      appVersion: String(input.client?.appVersion || ''), platform: String(input.client?.platform || ''),
      clientFeatures: String(input.client?.clientFeatures || ''), userAgent: String(input.client?.userAgent || ''),
      timezone: String(input.client?.timezone || ''), releaseChannel: String(input.client?.releaseChannel || ''),
      localDate: String(input.client?.localDate || ''),
    },
    corpusId: String(input.corpusId || ''),
    fixtureFingerprint: String(input.fixtureFingerprint || ''),
    workloadUserCount: Number(input.workloadUserCount || 0),
    distinctMeasuredWriteUsers: Number(input.distinctMeasuredWriteUsers || 0),
    selectedActiveRaceCount: Number(input.selectedActiveRaceCount || 0),
    sequenceDependent: true,
    generatorCapacityVerified: input.generatorCapacityVerified === true,
    runs,
  };
  if (command === 'find') {
    const failed = runs.find(run => run.benchmarkOutcome !== 'pass');
    result.firstFailedRung = failed ? failed.rps : null;
    result.expectedSyncReservationsMaxTotal = runs.reduce((sum, run) => sum + run.expectedSyncReservationsMax, 0);
  }
  return result;
}

export function queueP95(samples) {
  return percentile(samples, 0.95);
}
