#!/usr/bin/env node
/**
 * Mints staging session tokens for N real (prod-cloned) users and captures the
 * status/mode/roster context and seeded resolution jobs for races each user
 * actually participates in.
 *
 * Why this exists: the older harness authenticated every VU as the single App
 * Store reviewer account. That serialises all writes onto one user's rows and
 * gives every read the same warm cache line — which is nothing like 5000
 * distinct users. Signing tokens directly with SESSION_TOKEN_SECRET lets the
 * load test drive N genuinely different identities.
 *
 * STAGING ONLY. Refuses to run if the DB url is not the staging database.
 *
 *   SESSION_TOKEN_SECRET=... STAGING_DATABASE_URL=... \
 *     node k6/mint-staging-users.js --count=400 --out=k6/users.json
 */

const fs = require("fs");
const jwt = require("jsonwebtoken");
const { Client } = require("pg");

const ISSUER = "steps-tracker-api";

function arg(name, fallback) {
  const hit = process.argv.find((v) => v.startsWith(`--${name}=`));
  return hit ? hit.split("=").slice(1).join("=") : fallback;
}

async function main() {
  const { buildFixtureDocument, partitionResolutionSeeds, validateFixture } = await import(
    "./harness-contract.mjs"
  );
  const url = process.env.STAGING_DATABASE_URL;
  const secret = process.env.SESSION_TOKEN_SECRET;
  if (!url) throw new Error("STAGING_DATABASE_URL is required");
  if (!secret) throw new Error("SESSION_TOKEN_SECRET is required");
  if (!/step-tracker-staging/.test(url)) {
    throw new Error(
      `refusing to run: DB url does not look like staging (${url.replace(/:[^:@]*@/, ":***@")})`,
    );
  }

  const count = Number(arg("count", 400));
  const resolutionSeedCount = Number(arg("resolution-seeds", 4));
  const out = arg("out", "k6/users.json");

  // DO managed Postgres presents a self-signed chain; the CA bundle is not on
  // this machine and the connection is read-only over an already-trusted path.
  // `sslmode` in the URL wins over the `ssl` option in pg v8+, so strip it.
  const client = new Client({
    connectionString: url.replace(/([?&])sslmode=[^&]*/g, "$1"),
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();

  // Users who were actually active recently — these are the identities whose
  // request mix the nginx log was measured from.
  const { rows: users } = await client.query(
    `SELECT id, apple_id
       FROM users
      WHERE last_seen_at > NOW() - INTERVAL '14 days'
        AND is_review_account IS NOT TRUE
      ORDER BY last_seen_at DESC
      LIMIT $1`,
    [count],
  );

  if (!users.length) throw new Error("no recently-active users found in staging");

  // Keep ACTIVE/PENDING separate and count the complete ACCEPTED roster, not
  // merely the subset of users selected for this fixture. Resolution jobs are
  // seeded globally in the fixture, so every VU can poll them without relying
  // on VU-local history from a prior sync response.
  const { rows: raceRows } = await client.query(
    `WITH selected_races AS (
       SELECT DISTINCT rp.race_id
         FROM race_participants rp
         JOIN races r ON r.id = rp.race_id
        WHERE rp.user_id = ANY($1::text[])
          AND rp.status = 'accepted'
          AND r.status IN ('active', 'pending')
     ), roster_sizes AS (
       SELECT rp.race_id, COUNT(*)::int AS roster_size
         FROM race_participants rp
         JOIN selected_races selected ON selected.race_id = rp.race_id
        WHERE rp.status = 'accepted'
        GROUP BY rp.race_id
     )
     SELECT viewer.user_id,
            viewer.race_id,
            r.status::text AS race_status,
            r.is_team_race,
            roster.roster_size
       FROM race_participants viewer
       JOIN races r ON r.id = viewer.race_id
       JOIN roster_sizes roster ON roster.race_id = viewer.race_id
      WHERE viewer.user_id = ANY($1::text[])
        AND viewer.status = 'accepted'
        AND r.status IN ('active', 'pending')
      ORDER BY viewer.user_id, r.status, viewer.race_id`,
    [users.map((u) => u.id)],
  );

  const signedUsers = users.map((u) => ({
    ...u,
    token: jwt.sign({ appleId: u.apple_id }, secret, {
      subject: u.id,
      issuer: ISSUER,
      expiresIn: "2d",
      algorithm: "HS256",
    }),
  }));
  const partition = partitionResolutionSeeds({
    users: signedUsers,
    raceRows,
    seedCount: resolutionSeedCount,
  });
  const fixture = buildFixtureDocument({
    generatedAt: new Date().toISOString(),
    users: partition.workloadUsers,
    raceRows: partition.workloadRaceRows,
    resolutionSeeds: partition.resolutionSeeds,
  });
  const validation = validateFixture(fixture);
  if (!validation.ok) {
    throw new Error(`fixture validation failed:\n- ${validation.errors.join("\n- ")}`);
  }

  fs.writeFileSync(out, JSON.stringify(fixture));
  await client.end();

  console.log(`minted ${fixture.users.length} tokens -> ${out}`);
  console.log(`  fixture revision: ${fixture.metadata.fixtureRevision}`);
  console.log(`  ACTIVE references: ${fixture.metadata.counts.activeRaceReferences}`);
  console.log(`  PENDING references: ${fixture.metadata.counts.pendingRaceReferences}`);
  console.log(`  dedicated resolution users: ${fixture.metadata.counts.resolutionSeedUsers}`);
  console.log(`  strata: ${JSON.stringify(fixture.metadata.raceStrata)}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
