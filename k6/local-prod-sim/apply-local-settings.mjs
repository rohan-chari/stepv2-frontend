#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { canonicalJson, sha256 } from "./daily-capacity-contract.mjs";

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`missing ${name}`);
  return process.argv[index + 1];
}

const settingsPath = argument("--settings");
const artifactDir = path.resolve(argument("--artifact-dir"));
const databaseUrl = argument("--database-url");
const expectedDb = argument("--expected-db");
const expectedMarker = argument("--expected-marker");
const expectedHash = argument("--expected-hash");
if (!/^postgresql:\/\/[^@/]*@(?:127\.0\.0\.1|host\.lima\.internal):(?:55432|56432)\/stepv2_capacity_[A-Za-z0-9_]+(?:\?|$)/.test(databaseUrl)) {
  throw new Error("refusing settings mutation outside the dedicated local capacity database");
}
const document = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
if (document.schemaVersion !== "daily-k6-reconciled-settings-v1" ||
    document.localOverride?.key !== "capacityPhaseMetricsV1Enabled" ||
    document.localOverride?.value !== true) throw new Error("settings document is invalid");
const expectedSettings = { ...document.localDbSettings, capacityPhaseMetricsV1Enabled: true };
if (sha256(canonicalJson(expectedSettings)) !== expectedHash) throw new Error("expected settings hash mismatch");

process.env.DATABASE_URL = databaseUrl;
process.chdir(artifactDir);
const artifactRequire = createRequire(path.join(artifactDir, "package.json"));
const { prisma } = artifactRequire("./src/db.js");
try {
  await prisma.$transaction(async (tx) => {
    const [identity] = await tx.$queryRaw`SELECT current_database() AS database`;
    if (identity?.database !== expectedDb) throw new Error("capacity database identity mismatch");
    const marker = await tx.appSetting.findUnique({ where: { key: "capacityBenchmarkCorpusMarker" } });
    // Older pinned sanitized corpora predate the in-database marker. Their
    // exact dump SHA is verified by the runner before restore. If a marker is
    // present it must still agree, so a conflicting corpus always fails.
    if (marker && marker.value !== expectedMarker) throw new Error("sanitized corpus marker mismatch");
    await tx.appSetting.deleteMany({ where: { key: { not: "capacityBenchmarkCorpusMarker" } } });
    for (const [key, value] of Object.entries(expectedSettings)) {
      if (key === "capacityPhaseMetricsV1Enabled" || key === "capacityBenchmarkCorpusMarker") continue;
      await tx.appSetting.create({ data: { key, value } });
    }
    // The observability override is intentionally separate from mirrored prod.
    await tx.appSetting.create({ data: { key: "capacityPhaseMetricsV1Enabled", value: true } });
    const rows = await tx.appSetting.findMany({ where: { key: { not: "capacityBenchmarkCorpusMarker" } } });
    const actual = Object.fromEntries(rows.map((row) => [row.key, row.value]));
    if (sha256(canonicalJson(actual)) !== expectedHash) throw new Error("resolved local settings hash mismatch");
  });
} finally {
  await prisma.$disconnect();
}
