#!/usr/bin/env node
import fs from "node:fs";
import { ENDPOINTS } from "../harness-contract.mjs";

const argument = (name) => {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`missing ${name}`);
  return process.argv[index + 1];
};
const summary = JSON.parse(fs.readFileSync(argument("--summary"), "utf8"));
if (summary.schemaVersion !== "capacity-harness-summary-v1") throw new Error("summary schema mismatch");
const metricTotals = new Map();
const metricPresence = new Set();
const phaseTotals = { warmup: new Map(), steady: new Map() };
const http = [];
const warmupHttp = [];
const critical = [];
for (const [lineNumber, line] of fs.readFileSync(argument("--raw"), "utf8").split("\n").entries()) {
  if (!line) continue;
  let point;
  try { point = JSON.parse(line); } catch { throw new Error(`malformed raw metric line ${lineNumber + 1}`); }
  if (point.type === "Metric" && typeof point.data?.name === "string") {
    metricPresence.add(point.data.name);
    if (!metricTotals.has(point.data.name)) metricTotals.set(point.data.name, 0);
    continue;
  }
  if (typeof point.metric !== "string" || !Number.isFinite(Number(point.data?.value))) continue;
  const value = Number(point.data.value);
  metricPresence.add(point.metric);
  metricTotals.set(point.metric, (metricTotals.get(point.metric) || 0) + value);
  const phase = point.data?.tags?.traffic_phase;
  if (phase === "warmup" || phase === "steady") {
    phaseTotals[phase].set(point.metric, (phaseTotals[phase].get(point.metric) || 0) + value);
    if (phase === "warmup" && point.metric === "http_req_duration") warmupHttp.push(value);
    if (phase === "steady" && point.metric === "http_req_duration") http.push(value);
    if (phase === "steady" && point.metric === "persistence_critical_duration_ms") critical.push(value);
  }
}
const requiredRaw = [
  "iterations", "executed_endpoint_count", "http_reqs", "http_req_duration", "persistence_critical_duration_ms",
  "capacity_failure_count", "hard_failure_count", "rate_limit_429_count", "context_fallback_count",
];
for (const metric of requiredRaw) if (!metricPresence.has(metric)) throw new Error(`required raw metric absent: ${metric}`);
const reconstructedEndpointZeros = [];
const normalizedEndpointAccounting = {};
const numberAt = (value, label) => {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new Error(`summary metric absent or malformed: ${label}`);
  return value;
};
const countAt = (value, label) => {
  if (!Number.isInteger(value) || value < 0) throw new Error(`counter absent or malformed: ${label}`);
  return value;
};
for (const endpoint of ENDPOINTS) {
  const accounting = summary.endpointAccounting?.[endpoint.key];
  if (!accounting) throw new Error(`summary endpoint absent: ${endpoint.key}`);
  normalizedEndpointAccounting[endpoint.key] = {};
  for (const [field, suffix] of [
    ["selected", "selected_count"], ["executed", "executed_count"],
    ["durationSamples", "duration_sample_count"], ["statusTotal", "status_count"],
  ]) {
    const metric = `summary_endpoint_${endpoint.key}_${suffix}`;
    if (!metricPresence.has(metric)) throw new Error(`raw endpoint metric absent: ${endpoint.key}.${field}`);
    const rawValue = metricTotals.get(metric);
    countAt(rawValue, `raw ${endpoint.key}.${field}`);
    let summaryValue;
    if (typeof accounting[field] === "number" && Number.isFinite(accounting[field])) {
      summaryValue = countAt(accounting[field], `${endpoint.key}.${field}`);
    } else if (rawValue === 0) {
      summaryValue = 0;
      reconstructedEndpointZeros.push(`${endpoint.key}.${field}`);
    } else {
      throw new Error(`summary endpoint metric malformed: ${endpoint.key}.${field}`);
    }
    normalizedEndpointAccounting[endpoint.key][field] = summaryValue;
    if (summaryValue !== rawValue) {
      throw new Error(`raw/summary endpoint cross-check failed: ${endpoint.key}.${field}`);
    }
  }
}
const summaryCrossChecks = [
  ["capacityFailures", "capacity_failure_count"],
  ["hardFailures", "hard_failure_count"],
  ["rateLimited429", "rate_limit_429_count"],
  ["contextFallbacks", "context_fallback_count"],
];
const reconstructedSummaryZeros = [];
for (const [field, metric] of summaryCrossChecks) {
  const rawTotal = metricTotals.get(metric);
  countAt(rawTotal, `raw ${field}`);
  const summaryCount = summary.totals?.[field]?.count;
  if (typeof summaryCount !== "number" && rawTotal === 0 && metricPresence.has(metric)) {
    reconstructedSummaryZeros.push(field);
  } else if (countAt(summaryCount, field) !== rawTotal) {
    throw new Error(`raw/summary counter cross-check failed: ${field}`);
  }
}
const executed = Object.values(normalizedEndpointAccounting).reduce((sum, accounting) => sum + accounting.executed, 0);
countAt(executed, "executed endpoint total");
const summaryRequests = countAt(summary.totals?.requests?.count, "requests.count");
if (metricTotals.get("executed_endpoint_count") !== executed) {
  throw new Error("raw/summary request accounting mismatch");
}
if (summaryRequests !== metricTotals.get("http_reqs")) throw new Error("raw/summary total HTTP request accounting mismatch");
const warmupExecuted = phaseTotals.warmup.get("executed_endpoint_count");
const steadyExecuted = phaseTotals.steady.get("executed_endpoint_count");
if (!Number.isInteger(warmupExecuted) || !Number.isInteger(steadyExecuted) ||
    warmupExecuted < 0 || steadyExecuted < 0 ||
    warmupExecuted !== warmupHttp.length || steadyExecuted !== http.length ||
    warmupExecuted + steadyExecuted !== executed) {
  throw new Error("traffic-only raw HTTP and endpoint accounting mismatch");
}
const rps = numberAt(summary.inputs?.offeredRateRps, "offeredRateRps");
const planned = rps * 35;
const rawIterations = countAt(metricTotals.get("iterations"), "raw iterations");
if (rawIterations !== executed) throw new Error("raw iteration/endpoint accounting mismatch");
const summaryDropped = summary.totals?.droppedArrivals?.count;
const rawDropped = metricPresence.has("dropped_iterations")
  ? countAt(metricTotals.get("dropped_iterations"), "raw dropped iterations")
  : countAt(summaryDropped, "summary dropped iterations");
let dropped;
let droppedSource;
if (typeof summaryDropped === "number" && Number.isFinite(summaryDropped)) {
  dropped = summaryDropped;
  droppedSource = "summary";
  if (rawDropped !== dropped) {
    throw new Error("raw/summary dropped-iteration mismatch");
  }
} else {
  dropped = planned - executed;
  droppedSource = "scheduler-reconstruction";
}
if (!Number.isInteger(dropped) || dropped < 0 || Math.abs((executed + dropped) - planned) > 1) {
  throw new Error("scheduler accounting is incomplete");
}
const output = {
  schemaVersion: "daily-k6-normalized-raw-v1",
  executed,
  dropped,
  droppedSource,
  warmup: warmupExecuted,
  steady: steadyExecuted,
  trafficHttpSamples: { warmup: warmupHttp.length, steady: http.length },
  http,
  critical,
  capacityFailures: phaseTotals.steady.get("capacity_failure_count") ?? (metricTotals.get("capacity_failure_count") === 0 ? 0 : null),
  hardFailures: phaseTotals.steady.get("hard_failure_count") ?? (metricTotals.get("hard_failure_count") === 0 ? 0 : null),
  rateLimited429: phaseTotals.steady.get("rate_limit_429_count") ?? (metricTotals.get("rate_limit_429_count") === 0 ? 0 : null),
  contextFallbacks: phaseTotals.steady.get("context_fallback_count") ?? (metricTotals.get("context_fallback_count") === 0 ? 0 : null),
  requiredMetricPresence: Object.fromEntries(requiredRaw.map((metric) => [metric, metricPresence.has(metric)])),
  reconstructedEndpointZeros,
  reconstructedSummaryZeros,
  reconstructedPhaseZeros: summaryCrossChecks
    .filter(([, metric]) => !phaseTotals.steady.has(metric) && metricTotals.get(metric) === 0)
    .map(([field]) => field),
  allCounterTotals: Object.fromEntries(summaryCrossChecks.map(([field, metric]) => [field, metricTotals.get(metric)])),
  normalizedEndpointAccounting,
  rawSummaryCrossChecked: true,
};
const outputPath = argument("--output");
const temporary = `${outputPath}.tmp.${process.pid}`;
fs.writeFileSync(temporary, `${JSON.stringify(output)}\n`, { mode: 0o600 });
fs.renameSync(temporary, outputPath);
