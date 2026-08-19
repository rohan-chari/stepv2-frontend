#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import { execFileSync, spawn, spawnSync } from "node:child_process";

const argument = (name) => {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`missing ${name}`);
  return process.argv[index + 1];
};
const separator = process.argv.indexOf("--");
if (separator < 0 || !process.argv[separator + 1]) throw new Error("missing child command");
const output = argument("--output");
const exitFile = argument("--exit-file");
const rawPath = argument("--raw");
const maxVUs = Number(argument("--max-vus"));
const stdoutPath = argument("--stdout");
const stderrPath = argument("--stderr");
const childCommand = process.argv[separator + 1];
const childArguments = process.argv.slice(separator + 2);
const startWall = new Date();
const monotonicStart = process.hrtime.bigint();
const monotonicMs = () => Number(process.hrtime.bigint() - monotonicStart) / 1e6;
const samples = [];
const command = (name, args) => execFileSync(name, args, { encoding: "utf8", timeout: 2000, maxBuffer: 1024 * 1024 }).trim();
const availableMemory = () => {
  const text = command("vm_stat", []);
  const pageSize = Number(/page size of (\d+) bytes/.exec(text)?.[1]);
  let pages = 0;
  for (const label of ["Pages free", "Pages inactive", "Pages speculative"]) {
    const value = new RegExp(`${label}:\\s+(\\d+)`).exec(text)?.[1];
    if (value) pages += Number(value);
  }
  if (!Number.isFinite(pageSize) || pages <= 0) throw new Error("vm_stat parse failed");
  return pages * pageSize;
};
const overallCpu = () => command("ps", ["-A", "-o", "%cpu="]).split("\n").reduce((sum, value) => sum + Number(value.trim() || 0), 0);
const processStartIdentity = (pid) => command("ps", ["-p", String(pid), "-o", "lstart="]).trim();
const processNumber = (pid, field) => Number(command("ps", ["-p", String(pid), "-o", `${field}=`]).trim());
function pressureState() {
  const result = spawnSync("memory_pressure", ["-Q"], { encoding: "utf8", timeout: 2000 });
  if (result.status !== 0) return { parseStatus: "failed", critical: false };
  return { parseStatus: "ok", critical: /critical/i.test(result.stdout) };
}
function swapState() {
  const result = spawnSync("sysctl", ["-n", "vm.swapusage"], { encoding: "utf8", timeout: 2000 });
  if (result.status !== 0) return { parseStatus: "failed", exhausted: false };
  return { parseStatus: "ok", exhausted: /free = 0\.00M/.test(result.stdout) && !/total = 0\.00M/.test(result.stdout) };
}
function hostSample({ pid = null, startIdentity = null, processAlive }) {
  const pressure = pressureState();
  const swap = swapState();
  let cpuPercent = 0;
  let rssBytes = 0;
  let observedStartIdentity = startIdentity;
  if (processAlive && pid != null) {
    cpuPercent = processNumber(pid, "%cpu");
    rssBytes = processNumber(pid, "rss") * 1024;
    observedStartIdentity = processStartIdentity(pid);
  }
  samples.push({
    timestamp: new Date().toISOString(),
    monotonicMs: monotonicMs(),
    pid,
    processAlive,
    processStartIdentity: observedStartIdentity,
    cpuPercent,
    rssBytes,
    overallCpuPercent: overallCpu(),
    availableBytes: availableMemory(),
    memoryPressureParseStatus: pressure.parseStatus,
    memoryPressureCritical: pressure.critical,
    swapParseStatus: swap.parseStatus,
    swapExhausted: swap.exhausted,
  });
}

hostSample({ processAlive: false });
const stdout = fs.openSync(stdoutPath, "w", 0o600);
const stderr = fs.openSync(stderrPath, "w", 0o600);
const child = spawn(childCommand, childArguments, { stdio: ["ignore", stdout, stderr], env: process.env });
const pid = child.pid;
if (!Number.isInteger(pid)) throw new Error("k6 process did not start");
let interruptedSignal = null;
for (const signal of ["SIGINT", "SIGTERM"]) {
  process.once(signal, () => {
    interruptedSignal = signal;
    child.kill("SIGTERM");
  });
}
const startIdentity = processStartIdentity(pid);
hostSample({ pid, startIdentity, processAlive: true });
const interval = setInterval(() => {
  try { hostSample({ pid, startIdentity, processAlive: true }); } catch { /* artifact records the resulting gap */ }
}, 1000);
const exitCode = await new Promise((resolve) => {
  child.once("error", () => resolve(127));
  child.once("exit", (code, signal) => resolve(signal ? 128 : (code ?? 127)));
});
clearInterval(interval);
fs.closeSync(stdout);
fs.closeSync(stderr);
hostSample({ pid, startIdentity, processAlive: false });
const endWall = new Date();
const exitMonotonicMs = samples.at(-1).monotonicMs;
const logTimestamp = (date) => {
  const pad = (value) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
};
const oom = spawnSync("/usr/bin/log", [
  "show", "--style", "json", "--start", logTimestamp(startWall), "--end", logTimestamp(endWall),
  "--predicate", 'eventMessage CONTAINS[c] "out of memory: killed" OR eventMessage CONTAINS[c] "killed process" OR eventMessage CONTAINS[c] "memorystatus: killing" OR eventMessage CONTAINS[c] "jetsam: killing"',
], { encoding: "utf8", timeout: 10_000, maxBuffer: 2 * 1024 * 1024 });
let hostOomEvents = null;
if (oom.status === 0) {
  try {
    const entries = JSON.parse(oom.stdout);
    if (Array.isArray(entries)) hostOomEvents = entries.filter((entry) => {
      const message = String(entry?.eventMessage || "");
      return !/killing_idle_process|idle-exit/i.test(message) &&
        /out of memory:\s*killed|killed process|memorystatus:\s*killing|jetsam:\s*killing/i.test(message);
    }).length;
  } catch { /* represented by failed parse status below */ }
}
const stderrText = fs.readFileSync(stderrPath, "utf8");
const stderrLines = stderrText.split(/\r?\n/).filter(Boolean);
const thresholdExitLine = (line) =>
  /^(?:time="[^"]+" level=error msg=|ERRO\[\d+\]\s+)"?thresholds on metrics '(?:[^'\r\n]+)' have been crossed"?$/.test(line);
const errorLikeLine = (line) =>
  /(?:\blevel=error\b|^ERRO\[|\b(?:error|fatal)\b|\bpanic:|\bGoError\b|could not initialize|failed to initialize|invalid output)/i.test(line);
const errorLines = stderrLines.filter(errorLikeLine);
const allowedThresholdLines = errorLines.filter(thresholdExitLine);
const unexpectedErrorLines = errorLines.filter((line) => !thresholdExitLine(line));
const stderrParseStatus = unexpectedErrorLines.length === 0 &&
  ((exitCode === 99 && allowedThresholdLines.length > 0 && allowedThresholdLines.length === errorLines.length) ||
   (exitCode !== 99 && allowedThresholdLines.length === 0 && errorLines.length === 0))
  ? "ok"
  : "runtime-error";
let vusMaxObserved = 0;
let vuMetricSamples = 0;
for (const line of fs.existsSync(rawPath) ? fs.readFileSync(rawPath, "utf8").split("\n") : []) {
  if (!line) continue;
  let point;
  try { point = JSON.parse(line); } catch { continue; }
  if (point.metric === "vus" && Number.isFinite(Number(point.data?.value))) {
    vusMaxObserved = Math.max(vusMaxObserved, Number(point.data.value));
    vuMetricSamples += 1;
  }
}
const artifact = {
  schemaVersion: "load-generator-health-v1",
  collectorVersion: 2,
  startedAt: startWall.toISOString(),
  endedAt: endWall.toISOString(),
  monotonicDurationMs: exitMonotonicMs,
  logicalCpus: os.cpus().length,
  totalMemoryBytes: os.totalmem(),
  maxVUs,
  vusMaxObserved,
  vuMetricSamples,
  k6Pid: pid,
  k6ProcessStartIdentity: startIdentity,
  k6Exit: exitCode,
  stderrParseStatus,
  stderrEvidence: {
    lineCount: stderrLines.length,
    errorLikeLineCount: errorLines.length,
    allowedThresholdExitLineCount: allowedThresholdLines.length,
    unexpectedErrorLineCount: unexpectedErrorLines.length,
  },
  beforeSpawnCovered: samples[0]?.pid == null,
  processExitObserved: samples.at(-1)?.processAlive === false,
  hostOomParseStatus: Number.isInteger(hostOomEvents) ? "ok" : "failed",
  hostOomEvents: Number.isInteger(hostOomEvents) ? hostOomEvents : 0,
  samples,
};
const temporary = `${output}.tmp.${process.pid}`;
fs.writeFileSync(temporary, `${JSON.stringify(artifact, null, 2)}\n`, { mode: 0o600 });
fs.renameSync(temporary, output);
const exitTemporary = `${exitFile}.tmp.${process.pid}`;
fs.writeFileSync(exitTemporary, `${exitCode}\n`, { mode: 0o600 });
fs.renameSync(exitTemporary, exitFile);
if (interruptedSignal) process.exitCode = interruptedSignal === "SIGINT" ? 130 : 143;
