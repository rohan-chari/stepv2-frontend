#!/usr/bin/env node

import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {chmodSync, readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

import {FIXTURE_SCHEMA_VERSION, decodeJwtClaims} from './capacity-contract.mjs';

const PRODUCTION_DATABASE_NAMES = new Set(['steptracker', 'steptracker_prod', 'steps_tracker', 'steps_tracker_prod', 'production']);

export function parseDatabaseTarget(input) {
  if (typeof input !== 'string' || input.trim() === '') throw new Error('DATABASE_URL is required');
  let parsed;
  try { parsed = new URL(input); } catch { throw new Error('DATABASE_URL is malformed'); }
  if (!['postgres:', 'postgresql:'].includes(parsed.protocol)) throw new Error('DATABASE_URL must use postgres or postgresql');
  const hostname = parsed.hostname.toLowerCase().replace(/\.$/, '');
  const normalizedHost = hostname === '[::1]' ? '::1' : hostname;
  const databaseName = decodeURIComponent(parsed.pathname.replace(/^\//, '')).toLowerCase();
  if (normalizedHost === 'steptracker-api.org' || normalizedHost.endsWith('.steptracker-api.org')) throw new Error('production database host is categorically forbidden');
  if (PRODUCTION_DATABASE_NAMES.has(databaseName) || /(^|[_-])(prod|production)([_-]|$)/.test(databaseName)) throw new Error('production database name is categorically forbidden');
  if (!['localhost', '127.0.0.1', '::1'].includes(normalizedHost)) throw new Error('fixture preparation accepts only a loopback database');
  if (!/(^|[_-])(test|capacity)([_-]|$)/.test(databaseName)) throw new Error('database name must contain a test or capacity token');
  return {hostname, databaseName};
}

export async function withReadOnlyTransaction(pool, callback) {
  let client;
  let began = false;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    began = true;
    await client.query('SET TRANSACTION READ ONLY');
    return await callback(client);
  } finally {
    if (client && began) {
      try { await client.query('ROLLBACK'); } catch { /* original failure remains authoritative */ }
    }
    if (client?.release) client.release();
    if (pool?.end) await pool.end();
  }
}

function fingerprintDocument(workloadUsers, resolutionSeeds, corpusId) {
  const normalized = {
    corpusId,
    workloadUsers: workloadUsers.map(user => ({userId: user.userId, activeRaceIds: [...user.activeRaceIds].sort()})),
    resolutionSeeds: resolutionSeeds.map(seed => ({userId: seed.userId, raceId: seed.raceId})),
  };
  return `sha256:${createHash('sha256').update(JSON.stringify(normalized)).digest('hex')}`;
}

function normalizedRows(rows, allowlist) {
  const allowed = new Set(allowlist);
  const seen = new Set();
  const valid = [];
  for (const row of rows) {
    const userId = String(row.userId || '');
    if (!allowed.has(userId) || seen.has(userId)) continue;
    seen.add(userId);
    if (row.isReviewAccount === true || Number(row.deviceTokenCount || 0) !== 0) {
      throw new Error('allowlisted identities must be non-review and device-token-free');
    }
    const activeRaceIds = [...new Set((row.activeRaceIds || []).map(String).filter(Boolean))].sort();
    if (activeRaceIds.length === 0) continue;
    if (row.rostersSafe !== true) {
      throw new Error('allowlisted identities with active races must have safe complete race rosters');
    }
    valid.push({userId, activeRaceIds});
  }
  return valid;
}

function chooseCohorts(valid) {
  for (let start = 0; start < valid.length; start += 1) {
    const seedUsers = [];
    const seedRaces = new Set();
    for (let offset = 0; offset < valid.length && seedUsers.length < 4; offset += 1) {
      const candidate = valid[(start + offset) % valid.length];
      const raceId = candidate.activeRaceIds.find(id => !seedRaces.has(id));
      if (!raceId) continue;
      seedUsers.push({userId: candidate.userId, raceId});
      seedRaces.add(raceId);
    }
    if (seedUsers.length !== 4) continue;
    const seedIds = new Set(seedUsers.map(seed => seed.userId));
    const workload = valid.filter(user => !seedIds.has(user.userId) && user.activeRaceIds.every(raceId => !seedRaces.has(raceId)));
    if (workload.length >= 200) return {workload, seedUsers};
  }
  throw new Error('could not isolate four seed identities/races from at least 200 workload identities');
}

export function buildFixtureFromRows(rows, {allowlist, corpusId, issuedAt, expiresAt, sign}) {
  if (!Array.isArray(allowlist) || new Set(allowlist).size < 204) throw new Error('allowlist requires at least 204 distinct dedicated test user IDs');
  if (typeof sign !== 'function') throw new Error('JWT signing callback is required');
  const valid = normalizedRows(rows, allowlist);
  const {workload, seedUsers} = chooseCohorts(valid);
  const workloadUsers = workload.map(user => ({userId: user.userId, token: sign(user.userId), activeRaceIds: user.activeRaceIds, activeRaceSetComplete: true}));
  const resolutionSeeds = seedUsers.map(seed => ({userId: seed.userId, token: sign(seed.userId), raceId: seed.raceId}));
  const claims = [...workloadUsers, ...resolutionSeeds].map(item => decodeJwtClaims(item.token));
  for (let index = 0; index < claims.length; index += 1) {
    const item = index < workloadUsers.length ? workloadUsers[index] : resolutionSeeds[index - workloadUsers.length];
    if (claims[index].sub !== item.userId || claims[index].iss !== 'steps-tracker-api') throw new Error('signed JWT does not match required issuer/subject contract');
  }
  const earliestExpiry = Math.min(...claims.map(claim => claim.exp));
  if (earliestExpiry !== expiresAt) throw new Error('expiresAt must equal the earliest signed JWT exp');
  return {
    schemaVersion: FIXTURE_SCHEMA_VERSION,
    issuedAt,
    expiresAt: earliestExpiry,
    corpusId,
    cohortFingerprint: fingerprintDocument(workloadUsers, resolutionSeeds, corpusId),
    workloadUsers,
    resolutionSeeds,
  };
}

const PREPARE_QUERY = `
SELECT
  u.id AS "userId",
  u.is_review_account AS "isReviewAccount",
  COUNT(DISTINCT own_dt.id)::int AS "deviceTokenCount",
  COALESCE(ARRAY_AGG(DISTINCT r.id) FILTER (WHERE r.id IS NOT NULL), ARRAY[]::text[]) AS "activeRaceIds",
  COALESCE(BOOL_AND(
    NOT EXISTS (
      SELECT 1
      FROM race_participants roster
      JOIN users roster_user ON roster_user.id = roster.user_id
      LEFT JOIN device_tokens roster_dt ON roster_dt.user_id = roster.user_id
      WHERE roster.race_id = r.id
        AND (NOT (roster.user_id = ANY($1::text[])) OR roster_user.is_review_account OR roster_dt.id IS NOT NULL)
    )
  ) FILTER (WHERE r.id IS NOT NULL), false) AS "rostersSafe"
FROM users u
LEFT JOIN device_tokens own_dt ON own_dt.user_id = u.id
LEFT JOIN race_participants rp ON rp.user_id = u.id AND rp.status = 'accepted'
LEFT JOIN races r ON r.id = rp.race_id AND r.status = 'active'
WHERE u.id = ANY($1::text[])
GROUP BY u.id, u.is_review_account
ORDER BY u.id`;

async function main() {
  const required = ['DATABASE_URL','BACKEND_REPO','SESSION_SECRET','TOKEN_TTL_SECONDS','CORPUS_ID','ALLOWLIST_PATH'];
  for (const name of required) if (!String(process.env[name] || '').trim()) throw new Error(`${name} is required`);
  parseDatabaseTarget(process.env.DATABASE_URL);
  const ttl = Number(process.env.TOKEN_TTL_SECONDS);
  if (!Number.isInteger(ttl) || ttl <= 0) throw new Error('TOKEN_TTL_SECONDS must be a positive integer');
  const allowlistValue = JSON.parse(readFileSync(resolve(process.env.ALLOWLIST_PATH), 'utf8'));
  if (!Array.isArray(allowlistValue) || allowlistValue.some(value => typeof value !== 'string' || !value.trim())) throw new Error('ALLOWLIST_PATH must contain a JSON array of non-empty user IDs');
  const allowlist = [...new Set(allowlistValue)];
  if (allowlist.length < 204) throw new Error('allowlist requires at least 204 distinct dedicated test user IDs');
  const backendPackage = resolve(process.env.BACKEND_REPO, 'package.json');
  const backendRequire = createRequire(backendPackage);
  const {Pool} = backendRequire('pg');
  const jwtLibrary = backendRequire('jsonwebtoken');
  const pool = new Pool({connectionString: process.env.DATABASE_URL, max: 1});
  const rows = await withReadOnlyTransaction(pool, async client => (await client.query(PREPARE_QUERY, [allowlist])).rows);
  const issuedAt = Math.floor(Date.now() / 1000);
  const expiresAt = issuedAt + ttl;
  const document = buildFixtureFromRows(rows, {
    allowlist,
    corpusId: process.env.CORPUS_ID,
    issuedAt,
    expiresAt,
    sign: userId => jwtLibrary.sign({}, process.env.SESSION_SECRET, {algorithm: 'HS256', issuer: 'steps-tracker-api', subject: userId, expiresIn: ttl}),
  });
  const output = resolve(process.env.FIXTURE_OUTPUT || fileURLToPath(new URL('./fixture.json', import.meta.url)));
  writeFileSync(output, `${JSON.stringify(document, null, 2)}\n`, {mode: 0o600});
  chmodSync(output, 0o600);
  const breadth = [];
  for (const size of [200, 500, 1000, document.workloadUsers.length]) {
    if (size > document.workloadUsers.length || breadth.some(item => item.workloadUserCount === size)) continue;
    breadth.push({workloadUserCount: size, distinctActiveRaceCount: new Set(document.workloadUsers.slice(0, size).flatMap(user => user.activeRaceIds)).size});
  }
  process.stdout.write(`${JSON.stringify({output, schemaVersion: document.schemaVersion, issuedAt, expiresAt, workloadUserCount: document.workloadUsers.length, resolutionSeedCount: 4, cohortFingerprint: document.cohortFingerprint, breadth})}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { process.stderr.write(`fixture preparation failed: ${error.message}\n`); process.exitCode = 2; });
}
