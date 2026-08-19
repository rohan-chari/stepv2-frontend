import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const LOCAL_SESSION_SECRET = "capacity-local-only-not-a-secret";
const ISSUER = "steps-tracker-api";

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`missing ${name}`);
  return process.argv[index + 1];
}

const input = argument("--input");
const output = argument("--output");
const databaseUrl = argument("--database-url");
const backendRepo = argument("--backend-repo");
const epochMs = Number(argument("--epoch-ms"));
if (!/^postgresql:\/\/[^@/]*@127\.0\.0\.1:55432\/stepv2_capacity_/.test(databaseUrl)) {
  throw new Error("refusing token remint outside the dedicated local capacity database");
}
if (!Number.isFinite(epochMs) || epochMs <= 0) throw new Error("invalid epoch");

const backendRequire = createRequire(path.join(backendRepo, "package.json"));
const jwt = backendRequire("jsonwebtoken");
const { Client } = backendRequire("pg");
const fixture = JSON.parse(fs.readFileSync(input, "utf8"));
const ids = [
  ...(fixture.users || []).map((user) => user.userId),
  ...(fixture.resolutionSeeds || []).map((user) => user.userId),
];
const uniqueIds = [...new Set(ids)];
const client = new Client({ connectionString: databaseUrl });
await client.connect();
const { rows } = await client.query(
  "SELECT id FROM users WHERE id = ANY($1::text[])",
  [uniqueIds],
);
await client.end();
const existingIds = new Set(rows.map((row) => row.id));
if (existingIds.size !== uniqueIds.length) {
  throw new Error("sanitized corpus is missing a fixture identity");
}
const issuedAt = Math.floor(epochMs / 1000);
const tokenFor = (userId) => jwt.sign(
  { iat: issuedAt, exp: issuedAt + 2 * 86400 },
  LOCAL_SESSION_SECRET,
  { subject: userId, issuer: ISSUER, algorithm: "HS256", noTimestamp: true },
);
for (const user of fixture.users || []) user.token = tokenFor(user.userId);
for (const user of fixture.resolutionSeeds || []) user.token = tokenFor(user.userId);
fs.writeFileSync(output, `${JSON.stringify(fixture)}\n`, { mode: 0o600 });
