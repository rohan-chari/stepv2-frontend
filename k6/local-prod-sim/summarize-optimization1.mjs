import fs from "node:fs";

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`missing ${name}`);
  return process.argv[index + 1];
}

const readJson = (path) => JSON.parse(fs.readFileSync(path, "utf8"));
const readNumber = (path) => {
  const value = Number(fs.readFileSync(path, "utf8").trim());
  if (!Number.isFinite(value)) throw new Error(`invalid numeric artifact: ${path}`);
  return value;
};
const requiredNumber = (value, label) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) throw new Error(`missing or invalid ${label}`);
  return parsed;
};
const durationSeconds = (value) => {
  const match = /^(\d+)s$/.exec(String(value));
  if (!match) throw new Error(`unsupported diagnostic duration: ${value}`);
  return Number(match[1]);
};
const fixed = (value, digits = 1) => requiredNumber(value, "report value").toFixed(digits);
const percentile = (samples, p) => {
  if (!samples.length) throw new Error("steady-state metric has no samples");
  const sorted = samples.slice().sort((left, right) => left - right);
  return sorted[Math.max(0, Math.ceil(p * sorted.length) - 1)];
};

function rawStats(path) {
  const points = [];
  for (const line of fs.readFileSync(path, "utf8").trim().split("\n")) {
    if (!line) continue;
    const point = JSON.parse(line);
    const time = Date.parse(point.data?.time);
    const value = Number(point.data?.value);
    if (Number.isFinite(time) && Number.isFinite(value)) points.push({ ...point, time, value });
  }
  const samples = (metric, endpoint = null) => points
    .filter((point) => point.data?.tags?.traffic_phase === "steady" &&
      point.metric === metric &&
      (endpoint == null || point.data?.tags?.endpoint === endpoint))
    .map((point) => point.value);
  const stat = (metric, endpoint = null) => {
    const values = samples(metric, endpoint);
    return { count: values.length, p95: percentile(values, 0.95), p99: percentile(values, 0.99) };
  };
  return {
    http: stat("http_req_duration"),
    writes: stat("persistence_critical_duration_ms"),
    endpoints: Object.fromEntries(
      ["steps_sync_v2", "steps_post", "steps_samples"].map((endpoint) =>
        [endpoint, stat("endpoint_duration_ms", endpoint)]),
    ),
  };
}

function assertSummary(summary, label) {
  if (summary?.schemaVersion !== "capacity-harness-summary-v1") {
    throw new Error(`${label} summary schema mismatch`);
  }
  for (const path of [
    ["totals", "requests", "count"],
    ["totals", "hardFailures", "count"],
    ["totals", "capacityFailures", "count"],
    ["totals", "droppedArrivals", "count"],
    ["totals", "rateLimited429", "count"],
    ["totals", "contextFallbacks", "count"],
    ["totals", "resolutionLag", "max"],
    ["totals", "finalResolutionOutstanding", "value"],
    ["totals", "resolutionStates", "failed", "count"],
    ["totals", "resolutionStates", "superseded", "count"],
  ]) {
    let value = summary;
    for (const key of path) value = value?.[key];
    requiredNumber(value, `${label}.${path.join(".")}`);
  }
  if (summary.totals.finalResolutionOutstanding.value !== 0) {
    throw new Error(`${label} has outstanding resolution seed work`);
  }
  if (summary.totals.resolutionStates.failed.count !== 0 ||
      summary.totals.resolutionStates.superseded.count !== 0) {
    throw new Error(`${label} has failed or superseded resolution seed work`);
  }
  for (const [endpoint, accounting] of Object.entries(summary.endpointAccounting || {})) {
    const selected = requiredNumber(accounting.selected, `${label}.${endpoint}.selected`);
    const executed = requiredNumber(accounting.executed, `${label}.${endpoint}.executed`);
    const duration = requiredNumber(accounting.durationSamples, `${label}.${endpoint}.durationSamples`);
    const status = requiredNumber(accounting.statusTotal, `${label}.${endpoint}.statusTotal`);
    if (selected !== executed || executed !== duration || duration !== status) {
      throw new Error(`${label} endpoint accounting mismatch for ${endpoint}`);
    }
  }
}

function thresholdFailures(summary) {
  const failures = [];
  for (const [metric, thresholds] of Object.entries(summary.thresholds || {})) {
    for (const [expression, passed] of Object.entries(thresholds || {})) {
      if (passed !== true) failures.push({ metric, expression });
    }
  }
  return failures;
}

function assertExpectedThresholds(summary, label) {
  const rungTag = `{rung:${summary.inputs.rung}}`;
  const expected = [
    "dropped_iterations",
    "capacity_failure_rate",
    "hard_failure_rate",
    "http_req_duration",
    "persistence_critical_duration_ms",
    "context_fallback_count",
    "resolution_lag_ms",
    "resolution_lag_sample_count",
    "final_resolution_outstanding",
    "resolution_state_failed_count",
    "resolution_state_superseded_count",
  ].map((metric) => `${metric}${rungTag}`);
  for (const metric of expected) {
    if (!summary.thresholds?.[metric] ||
        Object.keys(summary.thresholds[metric]).length === 0) {
      throw new Error(`${label} is missing expected threshold ${metric}`);
    }
  }
}

const off = readJson(argument("--off"));
const on = readJson(argument("--on"));
assertSummary(off, "off");
assertSummary(on, "on");
assertExpectedThresholds(off, "off");
assertExpectedThresholds(on, "on");

const matchedInputKeys = [
  "baseUrl", "offeredRateRps", "rung", "duration", "clientCohort",
  "backendRevision", "config", "workerCount", "pgBouncerPool", "redisState", "cronCohort",
  "matchedPairEpochMs", "warmupIterations",
];
for (const key of matchedInputKeys) {
  if (JSON.stringify(off.inputs?.[key]) !== JSON.stringify(on.inputs?.[key])) {
    throw new Error(`OFF/ON input mismatch: ${key}`);
  }
}
if (off.inputs?.flags !== "queued-generation-merge=false" ||
    on.inputs?.flags !== "queued-generation-merge=true") {
  throw new Error("OFF/ON flag labels are not the optimization-1 pair");
}
for (const endpoint of Object.keys(off.endpointAccounting)) {
  if (off.endpointAccounting[endpoint].executed !== on.endpointAccounting?.[endpoint]?.executed) {
    throw new Error(`OFF/ON endpoint count mismatch: ${endpoint}`);
  }
}

const warmupIterations = requiredNumber(argument("--warmup-iterations"), "warmup iterations");
if (off.inputs.warmupIterations !== warmupIterations) {
  throw new Error("summary warm-up iterations do not match the runner artifact");
}
const offRaw = rawStats(argument("--off-raw"));
const onRaw = rawStats(argument("--on-raw"));
const totalOffered = off.inputs.offeredRateRps * durationSeconds(off.inputs.duration);
const expectedSteady = totalOffered - warmupIterations;
if (!Number.isInteger(expectedSteady) || expectedSteady <= 0) {
  throw new Error("invalid expected steady offered-arrival count");
}
for (const [label, summary, raw] of [["off", off, offRaw], ["on", on, onRaw]]) {
  const accounted = Object.values(summary.endpointAccounting)
    .reduce((sum, endpoint) => sum + endpoint.executed, 0);
  if (accounted !== totalOffered) {
    throw new Error(`${label} endpoint accounting does not equal offered arrivals`);
  }
  if (raw.http.count !== expectedSteady) {
    throw new Error(`${label} steady raw HTTP stream is incomplete`);
  }
}
const artifacts = {
  exit: { off: readNumber(argument("--off-exit")), on: readNumber(argument("--on-exit")) },
  backlog: { off: readNumber(argument("--off-post-k6-backlog")), on: readNumber(argument("--on-post-k6-backlog")) },
  drain: { off: readNumber(argument("--off-post-k6-drain")), on: readNumber(argument("--on-post-k6-drain")) },
};
for (const [label, summary] of [["off", off], ["on", on]]) {
  const failures = thresholdFailures(summary);
  const unexpected = failures.filter(({ metric }) => !metric.startsWith("resolution_lag_ms{"));
  if (unexpected.length) throw new Error(`${label} has unexpected failed thresholds`);
  const exitCode = artifacts.exit[label];
  const expectedExit = failures.length === 0 ? 0 : 99;
  if (exitCode !== expectedExit) {
    throw new Error(`${label} k6 exit does not match its threshold results`);
  }
}
for (const metric of ["http", "writes"]) {
  if (offRaw[metric].count !== onRaw[metric].count) {
    throw new Error(`OFF/ON steady ${metric} sample count mismatch`);
  }
}
for (const endpoint of Object.keys(offRaw.endpoints)) {
  if (offRaw.endpoints[endpoint].count !== onRaw.endpoints[endpoint].count) {
    throw new Error(`OFF/ON steady endpoint count mismatch: ${endpoint}`);
  }
}
const count = (summary, name) => requiredNumber(summary.totals[name].count, name);
const integrity = ["hardFailures", "capacityFailures", "droppedArrivals", "rateLimited429", "contextFallbacks"]
  .every((name) => count(off, name) === 0 && count(on, name) === 0);

const comparison = (a, b) => a > 0 ? ((a - b) / a) * 100 : 0;
const speedLabel = (a, b) => {
  const delta = comparison(a, b);
  return `${fixed(Math.abs(delta))}% ${delta >= 0 ? "faster" : "slower"}`;
};
const endpointRows = Object.keys(offRaw.endpoints).map((endpoint) => {
  const a = offRaw.endpoints[endpoint];
  const b = onRaw.endpoints[endpoint];
  return `| ${endpoint} | ${a.count} / ${b.count} | ${fixed(a.p95)} / ${fixed(b.p95)} ms | ${fixed(a.p99)} / ${fixed(b.p99)} ms |`;
}).join("\n");

const markdown = `# Optimization 1 matched local diagnostic

- Generated: ${new Date().toISOString()}
- Rung: ${off.inputs.rung} (${off.inputs.offeredRateRps} offered RPS)
- Backend source: ${off.inputs.backendRevision}
- Warm-up excluded deterministically: first ${warmupIterations} offered arrivals
- Integrity checks: **${integrity ? "PASS" : "FAIL"}**
- Decision: **DIAGNOSTIC ONLY — NEVER AUTOMATICALLY APPROVE**

| Steady-state metric | OFF | ON | ON versus OFF |
|---|---:|---:|---:|
| HTTP p95 | ${fixed(offRaw.http.p95)} ms | ${fixed(onRaw.http.p95)} ms | ${speedLabel(offRaw.http.p95, onRaw.http.p95)} |
| HTTP p99 | ${fixed(offRaw.http.p99)} ms | ${fixed(onRaw.http.p99)} ms | ${speedLabel(offRaw.http.p99, onRaw.http.p99)} |
| Critical-write p95 | ${fixed(offRaw.writes.p95)} ms | ${fixed(onRaw.writes.p95)} ms | ${speedLabel(offRaw.writes.p95, onRaw.writes.p95)} |
| Critical-write p99 | ${fixed(offRaw.writes.p99)} ms | ${fixed(onRaw.writes.p99)} ms | ${speedLabel(offRaw.writes.p99, onRaw.writes.p99)} |
| Post-k6 global backlog (after teardown) | ${artifacts.backlog.off} | ${artifacts.backlog.on} | — |
| Post-k6 drain to quiet | ${artifacts.drain.off}s | ${artifacts.drain.on}s | — |
| k6 exit | ${artifacts.exit.off} | ${artifacts.exit.on} | — |

| Target endpoint | OFF / ON steady samples | OFF / ON p95 | OFF / ON p99 |
|---|---:|---:|---:|
${endpointRows}

This fast OFF→ON pair is a local diagnostic, not a production or DAU approval.
The fixed order can still carry thermal/order effects. Review server logs and run
counterbalanced repeats before deciding to enable the flag.
`;

fs.writeFileSync(argument("--output"), markdown, { mode: 0o600 });
process.stdout.write(markdown);
