#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const argument = (name) => {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`missing ${name}`);
  return process.argv[index + 1];
};
const artifactDir = path.resolve(argument("--artifact-dir"));
const settings = JSON.parse(fs.readFileSync(argument("--settings"), "utf8"));
const runId = argument("--run-id");
const databaseUrl = argument("--database-url");
const output = argument("--stdout");
const error = argument("--stderr");
const resolutionConcurrency = argument("--resolution-concurrency");
if (!/^[123]$/.test(resolutionConcurrency)) throw new Error("invalid resolution concurrency");
if (!databaseUrl.startsWith("postgresql://") || !databaseUrl.includes("host.lima.internal:56432/stepv2_capacity_")) {
  throw new Error("invalid local worker database URL");
}
const launcherEnvironment = Object.fromEntries(
  ["PATH", "HOME", "USER"].filter((key) => process.env[key]).map((key) => [key, process.env[key]]),
);
const env = {
  ...launcherEnvironment,
  ...settings.canonicalEnvironment,
  NODE_ENV: "production",
  PORT: "3002",
  DATABASE_URL: databaseUrl,
  REDIS_URL: "redis://127.0.0.1:6379/0",
  SESSION_TOKEN_SECRET: "capacity-local-only-not-a-secret",
  PRISMA_QUERY_EVENTS_ENABLED: "true",
  CRON_START_DELAY_MS: "0",
  CAPACITY_RUN_ID: runId,
  CAPACITY_REPEAT: "1",
  ASYNC_RACE_RESOLUTION_CONCURRENCY: resolutionConcurrency,
};
const result = spawnSync("pm2", [
  "start", "src/capacityLocal.js",
  "--name", "steps-tracker-prod-sim",
  "-i", "2",
  "--max-memory-restart", "600M",
  "--merge-logs",
  "--output", output,
  "--error", error,
  "--update-env",
], { cwd: artifactDir, env, stdio: "inherit" });
if (result.status !== 0) process.exit(result.status ?? 1);
