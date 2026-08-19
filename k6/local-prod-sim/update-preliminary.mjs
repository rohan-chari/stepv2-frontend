#!/usr/bin/env node
import fs from "node:fs";

const argument = (name, fallback = null) => {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
};
const file = argument("--file");
if (!file) throw new Error("missing --file");
let document = fs.existsSync(file)
  ? JSON.parse(fs.readFileSync(file, "utf8"))
  : { schemaVersion: "daily-k6-result-v1", runId: argument("--run-id"), createdAt: new Date().toISOString() };
if (!document.runId) throw new Error("preliminary run ID missing");
document = {
  ...document,
  phase: argument("--phase", document.phase || "lock-acquired"),
  status: argument("--status", document.status || "invalid"),
  reason: argument("--reason", document.reason || "setup did not complete"),
  backendSha: argument("--backend-sha", document.backendSha || null),
  snapshotHash: argument("--snapshot-hash", document.snapshotHash || null),
  updatedAt: new Date().toISOString(),
};
const temporary = `${file}.tmp.${process.pid}`;
fs.writeFileSync(temporary, `${JSON.stringify(document, null, 2)}\n`, { mode: 0o600 });
fs.renameSync(temporary, file);
