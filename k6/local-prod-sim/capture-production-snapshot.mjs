#!/usr/bin/env node
import fs from "node:fs";
import { spawnSync } from "node:child_process";
import { validateProductionSnapshot } from "./daily-capacity-contract.mjs";

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

const ssh = argument("--ssh", "ssh");
const target = argument("--target");
const backendDir = argument("--backend-dir");
const output = argument("--output");
if (!/^(?:[A-Za-z0-9_.-]+|[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+)$/.test(target || "")) {
  throw new Error("PROD_SSH_TARGET is invalid");
}
if (!/^\/[A-Za-z0-9._/-]+$/.test(backendDir || "") || backendDir.split("/").includes("..")) {
  throw new Error("PROD_BACKEND_DIR is invalid");
}
if (!output) throw new Error("snapshot output is required");
const helper = fs.readFileSync(new URL("remote-production-snapshot.cjs", import.meta.url), "utf8");
const result = spawnSync(ssh, [
  "-o", "BatchMode=yes",
  "-o", "StrictHostKeyChecking=yes",
  "-o", "ConnectTimeout=10",
  "-o", "ServerAliveInterval=5",
  "-o", "ServerAliveCountMax=2",
  target,
  "node", "-", backendDir,
], { input: helper, encoding: "utf8", timeout: 90_000, maxBuffer: 2 * 1024 * 1024 });
const lines = (result.stdout || "").split(/\r?\n/).filter((line) => line.length > 0);
if (result.error?.code === "ETIMEDOUT") throw new Error("production snapshot failed: SSH_TIMEOUT");
let document;
if (lines.length === 1) {
  try { document = JSON.parse(lines[0]); } catch { throw new Error("production snapshot failed: MALFORMED_JSON"); }
}
if (result.status !== 0 || lines.length !== 1) {
  const safeCode = /^[-A-Z0-9_]{1,64}$/.test(document?.errorCode || "") ? document.errorCode : `SSH_${result.status ?? "ERROR"}`;
  throw new Error(`production snapshot failed: ${safeCode}`);
}
validateProductionSnapshot(document);
const temporary = `${output}.tmp.${process.pid}`;
fs.writeFileSync(temporary, `${JSON.stringify(document)}\n`, { mode: 0o600 });
fs.renameSync(temporary, output);
