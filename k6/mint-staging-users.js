#!/usr/bin/env node
/**
 * Mints staging session tokens for N real (prod-cloned) users and captures the
 * race ids each of them actually participates in.
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
  const out = arg("out", "k6/users.json");

  // DO managed Postgres presents a self-signed chain; the CA bundle is not on
  // this machine and the connection is read-only over an already-trusted path.
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

  // Race ids per user. Only races that are still live/pending are worth
  // hitting: a settled race short-circuits most of the expensive read paths
  // and would flatter the results.
  const { rows: parts } = await client.query(
    `SELECT rp.user_id, rp.race_id
       FROM race_participants rp
       JOIN races r ON r.id = rp.race_id
      WHERE rp.user_id = ANY($1::text[])
        AND r.status IN ('active', 'pending')`,
    [users.map((u) => u.id)],
  );

  const racesByUser = new Map();
  for (const row of parts) {
    if (!racesByUser.has(row.user_id)) racesByUser.set(row.user_id, []);
    racesByUser.get(row.user_id).push(row.race_id);
  }

  const minted = users.map((u) => ({
    userId: u.id,
    token: jwt.sign({ appleId: u.apple_id }, secret, {
      subject: u.id,
      issuer: ISSUER,
      expiresIn: "2d",
      algorithm: "HS256",
    }),
    raceIds: (racesByUser.get(u.id) || []).slice(0, 12),
  }));

  const withRaces = minted.filter((u) => u.raceIds.length > 0);

  fs.writeFileSync(out, JSON.stringify(minted, null, 0));
  await client.end();

  console.log(`minted ${minted.length} tokens -> ${out}`);
  console.log(`  ${withRaces.length} have >=1 live/pending race`);
  console.log(
    `  median races/user: ${
      withRaces.length
        ? withRaces.map((u) => u.raceIds.length).sort((a, b) => a - b)[
            Math.floor(withRaces.length / 2)
          ]
        : 0
    }`,
  );
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
