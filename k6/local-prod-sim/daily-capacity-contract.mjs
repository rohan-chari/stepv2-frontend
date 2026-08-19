import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export const PERFORMANCE_REGISTRY_V1 = Object.freeze({
  placementDistributedClaimEnabled: Object.freeze({ env: "PLACEMENT_DISTRIBUTED_CLAIM_ENABLED", type: "boolean", default: false }),
  placementInertPushSuppressionEnabled: Object.freeze({ env: "PLACEMENT_INERT_PUSH_SUPPRESSION_ENABLED", type: "boolean", default: false }),
  placementLeanBaselineWritesEnabled: Object.freeze({ env: "PLACEMENT_LEAN_BASELINE_WRITES_ENABLED", type: "boolean", default: false }),
  stepSyncBulkEnabled: Object.freeze({ env: "STEP_SYNC_BULK_ENABLED", type: "boolean", default: false }),
  apnsSessionReuseEnabled: Object.freeze({ env: "APNS_SESSION_REUSE_ENABLED", type: "boolean", default: false }),
  placementBaselineWriteConcurrency: Object.freeze({ env: "PLACEMENT_BASELINE_WRITE_CONCURRENCY", type: "integer", default: 4, min: 1, max: 8 }),
  stepSyncPushConcurrency: Object.freeze({ env: "STEP_SYNC_PUSH_CONCURRENCY", type: "integer", default: 8, min: 1, max: 16 }),
});

const REQUIRED_ZERO_COUNTERS = [
  "droppedArrivals", "capacityFailures", "hardFailures", "rateLimited429",
  "contextFallbacks",
];
const MAX_RECORD_BYTES = 4096;
const START = "<!-- DAILY_K6_LOG_V1_START -->";
const END = "<!-- DAILY_K6_LOG_V1_END -->";
const LOG_HEADER = "| Day / local date | Backend | Prod flags | Tested RPS | Result | Known floor / ceiling | Rough DAU | Note |";
const LOG_SEPARATOR = "|---|---|---|---:|---|---|---:|---|";

export function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function sha256(value) {
  return `sha256:${crypto.createHash("sha256").update(value, "utf8").digest("hex")}`;
}

function plainObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
  return value;
}

function validateRegistry(registry, label) {
  plainObject(registry, label);
  for (const [semantic, entry] of Object.entries(registry)) {
    if (!/^[A-Za-z][A-Za-z0-9]+$/.test(semantic) ||
        !/^[A-Z][A-Z0-9_]+$/.test(entry?.env || "") ||
        !["boolean", "integer"].includes(entry?.type)) {
      throw new Error(`${label} contains an invalid mapping`);
    }
    if (entry.type === "integer" &&
        (!Number.isInteger(entry.default) || !Number.isInteger(entry.min) ||
         !Number.isInteger(entry.max) || entry.min > entry.max)) {
      throw new Error(`${label} contains invalid integer bounds`);
    }
  }
}

function validatePerformanceValue(value, mapping, semantic) {
  if (mapping.type === "boolean" && typeof value !== "boolean") {
    throw new Error(`${semantic} must be boolean`);
  }
  if (mapping.type === "integer" &&
      (!Number.isInteger(value) || value < mapping.min || value > mapping.max)) {
    throw new Error(`${semantic} is outside its registry bounds`);
  }
}

export function validateProductionSnapshot(snapshot) {
  plainObject(snapshot, "snapshot");
  if (snapshot.schemaVersion !== 1) {
    throw new Error("snapshot schema mismatch");
  }
  plainObject(snapshot.productionDbSettings, "productionDbSettings");
  plainObject(snapshot.productionPerformanceFlags, "productionPerformanceFlags");
  validateRegistry(snapshot.performanceRegistry, "deployed performance registry");
  if (!Array.isArray(snapshot.ignoredProductionOnlyKeys) ||
      snapshot.ignoredProductionOnlyKeys.some((key) => typeof key !== "string") ||
      (snapshot.captureTime != null && !Number.isFinite(Date.parse(snapshot.captureTime)))) {
    throw new Error("snapshot provenance fields are malformed");
  }
  if (snapshot.expectedWorkerCount !== 2 || snapshot.observedWorkerCount !== 2 ||
      !Array.isArray(snapshot.workers) || snapshot.workers.length !== 2) {
    throw new Error("production must have exactly two steps-tracker workers");
  }
  const instances = snapshot.workers.map((worker) => String(worker?.instance)).sort();
  if (instances.join(",") !== "0,1" || snapshot.workers.some((worker) =>
    worker.status !== "online" || worker.identityVerified !== true ||
    worker.loadedRevisionVerified !== true || worker.environmentAgeVerified !== true ||
    !Number.isInteger(worker.pid) || worker.pid < 1 || !Number.isFinite(worker.startedAtMs) ||
    !Number.isInteger(worker.restartCount) || worker.restartCount < 0)) {
    throw new Error("workers must be verified online instances 0 and 1");
  }
  if (!/^[a-f0-9]{40}$/.test(snapshot.deployedLoadedRevision || "")) {
    throw new Error("deployed loaded revision is missing");
  }
  for (const [semantic, mapping] of Object.entries(snapshot.performanceRegistry)) {
    validatePerformanceValue(snapshot.productionPerformanceFlags[semantic], mapping, semantic);
  }
  if (Object.keys(snapshot.productionPerformanceFlags).sort().join(",") !==
      Object.keys(snapshot.performanceRegistry).sort().join(",")) {
    throw new Error("production performance key set differs from its registry");
  }
  return snapshot;
}

export function canonicalSnapshotHash(snapshot) {
  validateProductionSnapshot(snapshot);
  if (new Set(snapshot.ignoredProductionOnlyKeys).size !== snapshot.ignoredProductionOnlyKeys.length ||
      snapshot.ignoredProductionOnlyKeys.some((key) => !/^(?:db|performance):/.test(key))) {
    throw new Error("canonical ignored-key set is malformed");
  }
  return sha256(canonicalJson({
    schemaVersion: snapshot.schemaVersion,
    productionDbSettings: Object.fromEntries(Object.entries(snapshot.productionDbSettings).map(([key, value]) => [`db:${key}`, value])),
    productionPerformanceFlags: Object.fromEntries(Object.entries(snapshot.productionPerformanceFlags).map(([key, value]) => [`performance:${key}`, value])),
    ignoredProductionOnlyKeys: [...(snapshot.ignoredProductionOnlyKeys || [])].sort(),
  }));
}

export function reconcileSnapshot(snapshot, mainRegistry, mainDbDefaults) {
  validateProductionSnapshot(snapshot);
  validateRegistry(mainRegistry, "fetched-main performance registry");
  plainObject(mainDbDefaults, "fetched-main DB defaults");
  const deployedRegistry = snapshot.performanceRegistry;
  for (const semantic of Object.keys(deployedRegistry)) {
    if (semantic in mainRegistry && canonicalJson(deployedRegistry[semantic]) !== canonicalJson(mainRegistry[semantic])) {
      throw new Error(`performance registry mapping drift for ${semantic}`);
    }
  }
  const productionPerformance = {};
  const defaultedNewMainPerformanceKeys = [];
  const ignoredProductionOnlyPerformanceKeys = [];
  for (const [semantic, mapping] of Object.entries(mainRegistry)) {
    const value = semantic in deployedRegistry
      ? snapshot.productionPerformanceFlags[semantic]
      : mapping.default;
    validatePerformanceValue(value, mapping, semantic);
    productionPerformance[semantic] = value;
    if (!(semantic in deployedRegistry)) defaultedNewMainPerformanceKeys.push(semantic);
  }
  for (const semantic of Object.keys(deployedRegistry)) {
    if (!(semantic in mainRegistry)) ignoredProductionOnlyPerformanceKeys.push(semantic);
  }
  const localDbSettings = {};
  const defaultedNewMainKeys = [];
  for (const [key, defaultValue] of Object.entries(mainDbDefaults)) {
    if (key === "capacityPhaseMetricsV1Enabled") continue;
    if (Object.hasOwn(snapshot.productionDbSettings, key)) {
      localDbSettings[key] = snapshot.productionDbSettings[key];
    } else {
      localDbSettings[key] = defaultValue;
      defaultedNewMainKeys.push(key);
    }
  }
  return {
    schemaVersion: "daily-k6-reconciled-settings-v1",
    productionDbSettings: snapshot.productionDbSettings,
    deployedProductionPerformanceFlags: snapshot.productionPerformanceFlags,
    productionPerformanceFlags: productionPerformance,
    canonicalEnvironment: Object.fromEntries(Object.entries(mainRegistry).map(([semantic, mapping]) => [
      mapping.env,
      mapping.type === "boolean" ? String(productionPerformance[semantic]) : String(productionPerformance[semantic]),
    ])),
    localDbSettings,
    localOverride: { key: "capacityPhaseMetricsV1Enabled", value: true },
    defaultedNewMainKeys: defaultedNewMainKeys.sort(),
    defaultedNewMainPerformanceKeys: defaultedNewMainPerformanceKeys.sort(),
    ignoredProductionOnlyKeys: Object.keys(snapshot.productionDbSettings).filter((key) => !(key in mainDbDefaults)).sort(),
    ignoredProductionOnlyPerformanceKeys: ignoredProductionOnlyPerformanceKeys.sort(),
    performanceLifecycle: {
      mirrored: Object.keys(mainRegistry).filter((key) => key in deployedRegistry).sort(),
      defaultedNewMain: defaultedNewMainPerformanceKeys.sort(),
      ignoredDeployedOnly: ignoredProductionOnlyPerformanceKeys.sort(),
    },
  };
}

export function normalizeSummary(summary, raw) {
  if (summary?.schemaVersion !== "capacity-harness-summary-v1") throw new Error("summary schema mismatch");
  if (raw?.schemaVersion !== "daily-k6-normalized-raw-v1" || raw.rawSummaryCrossChecked !== true ||
      !raw.requiredMetricPresence || Object.values(raw.requiredMetricPresence).some((present) => present !== true)) {
    throw new Error("raw metric presence/cross-check proof is missing");
  }
  const totals = { ...(summary.totals || {}) };
  for (const key of REQUIRED_ZERO_COUNTERS.filter((item) => item !== "droppedArrivals")) {
    if (Number.isInteger(totals[key]?.count) && totals[key].count >= 0) {
      totals[key] = { ...totals[key], count: totals[key].count };
    } else if (raw.reconstructedSummaryZeros?.includes(key) && raw.allCounterTotals?.[key] === 0) {
      totals[key] = { count: 0, normalizedFrom: "raw-explicit-zero" };
    } else {
      throw new Error(`required summary counter absent: ${key}`);
    }
  }
  if (Number.isInteger(totals.droppedArrivals?.count) && totals.droppedArrivals.count >= 0) {
    totals.droppedArrivals = { ...totals.droppedArrivals, count: totals.droppedArrivals.count };
  } else if (raw.droppedSource === "scheduler-reconstruction") {
    totals.droppedArrivals = { count: raw.dropped, normalizedFrom: "scheduler-reconstruction" };
  } else {
    throw new Error("dropped-arrival counter absent without reconstruction proof");
  }
  const endpointAccounting = raw.normalizedEndpointAccounting;
  if (!endpointAccounting || Object.keys(endpointAccounting).length === 0) throw new Error("normalized endpoint accounting missing");
  for (const [endpoint, accounting] of Object.entries(endpointAccounting)) {
    const values = [accounting.selected, accounting.executed, accounting.durationSamples, accounting.statusTotal];
    if (values.some((value) => !Number.isInteger(value) || value < 0) ||
        !values.every((value) => value === values[0])) {
      throw new Error(`endpoint accounting mismatch for ${endpoint}`);
    }
  }
  return { ...summary, totals, endpointAccounting };
}

const percentile = (values, p) => {
  if (!Array.isArray(values) || values.length === 0) return null;
  const sorted = values.map(Number).filter(Number.isFinite).sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(sorted.length * p) - 1)] ?? null;
};

export function validateLoadGeneratorHealth(artifact) {
  const stderrKeys = ["allowedThresholdExitLineCount", "errorLikeLineCount", "lineCount", "unexpectedErrorLineCount"];
  const stderrEvidenceValid = artifact?.stderrEvidence &&
    Object.keys(artifact.stderrEvidence).sort().join(",") === stderrKeys.sort().join(",") &&
    Object.values(artifact.stderrEvidence).every((value) => Number.isInteger(value) && value >= 0) &&
    artifact.stderrEvidence.unexpectedErrorLineCount === 0 &&
    (artifact.k6Exit === 99
      ? artifact.stderrEvidence.allowedThresholdExitLineCount > 0 &&
        artifact.stderrEvidence.allowedThresholdExitLineCount === artifact.stderrEvidence.errorLikeLineCount
      : artifact.stderrEvidence.allowedThresholdExitLineCount === 0 && artifact.stderrEvidence.errorLikeLineCount === 0);
  if (artifact?.schemaVersion !== "load-generator-health-v1" ||
      artifact.beforeSpawnCovered !== true || artifact.processExitObserved !== true ||
      artifact.stderrParseStatus !== "ok" || artifact.hostOomParseStatus !== "ok" ||
      !Number.isInteger(artifact.hostOomEvents) || artifact.hostOomEvents !== 0 ||
      !Number.isInteger(artifact.vuMetricSamples) || artifact.vuMetricSamples < 1 ||
      ![0, 99].includes(artifact.k6Exit) || !Number.isInteger(artifact.logicalCpus) ||
      artifact.logicalCpus < 1 || !Number.isFinite(artifact.totalMemoryBytes) ||
      !Number.isInteger(artifact.maxVUs) || artifact.maxVUs < 1 ||
      !Number.isInteger(artifact.vusMaxObserved) || artifact.vusMaxObserved < 0 ||
      artifact.vusMaxObserved > artifact.maxVUs || !Array.isArray(artifact.samples) ||
      artifact.samples.length < 3 || !artifact.k6ProcessStartIdentity || !stderrEvidenceValid) return { valid: false, reason: "load-generator evidence missing or malformed" };
  if (artifact.samples[0].pid != null || artifact.samples[0].processAlive !== false ||
      artifact.samples.at(-1).processAlive !== false || artifact.samples.at(-1).pid !== artifact.k6Pid) {
    return { valid: false, reason: "load-generator start/exit coverage is invalid" };
  }
  const evidenceStart = Date.parse(artifact.startedAt);
  const evidenceEnd = Date.parse(artifact.endedAt);
  if (![evidenceStart, evidenceEnd].every(Number.isFinite) || evidenceEnd < evidenceStart ||
      Math.abs(artifact.samples.at(-1).monotonicMs - artifact.monotonicDurationMs) > 1 ||
      Date.parse(artifact.samples[0].timestamp) - evidenceStart > 2000 ||
      evidenceEnd - Date.parse(artifact.samples.at(-1).timestamp) > 2000) {
    return { valid: false, reason: "load-generator evidence window is incomplete" };
  }
  let hot = 0;
  for (let index = 0; index < artifact.samples.length; index += 1) {
    const sample = artifact.samples[index];
    const previous = index > 0 ? artifact.samples[index - 1] : null;
    const wallDelta = previous ? Date.parse(sample.timestamp) - Date.parse(previous.timestamp) : 0;
    const monotonicDelta = previous ? sample.monotonicMs - previous.monotonicMs : 0;
    if (!Number.isFinite(Date.parse(sample.timestamp)) || !Number.isFinite(sample.monotonicMs) ||
        !Number.isFinite(sample.cpuPercent) || sample.cpuPercent < 0 ||
        !Number.isFinite(sample.availableBytes) || sample.availableBytes < 0 ||
        !Number.isFinite(sample.rssBytes) || sample.rssBytes < 0 ||
        !Number.isFinite(sample.overallCpuPercent) || sample.overallCpuPercent < 0 ||
        sample.memoryPressureParseStatus !== "ok" || sample.swapParseStatus !== "ok" ||
        (index > 0 && (monotonicDelta <= 0 || monotonicDelta > 2100 || wallDelta <= 0 ||
          wallDelta > 2100 || Math.abs(wallDelta - monotonicDelta) > 500)) ||
        (index > 0 && (sample.pid !== artifact.k6Pid || sample.processStartIdentity !== artifact.k6ProcessStartIdentity))) {
      return { valid: false, reason: "load-generator sampler gap or PID mismatch" };
    }
    hot = sample.cpuPercent >= artifact.logicalCpus * 100 * 0.8 ? hot + 1 : 0;
    if (hot >= 3) return { valid: false, reason: "load-generator CPU exhausted" };
    if (sample.availableBytes < Math.max(2 * 1024 ** 3, artifact.totalMemoryBytes * 0.05) ||
        sample.memoryPressureCritical || sample.oom || sample.swapExhausted) {
      return { valid: false, reason: "load-generator memory exhausted" };
    }
  }
  return { valid: true, reachedMaxVUs: artifact.vusMaxObserved === artifact.maxVUs };
}

export function validateServerHealth(artifact) {
  const classifiedLogKeys = ["deadlock", "oom", "p2028", "poolTimeout"];
  const classifiedLogsValid = artifact?.classifiedLogCounts &&
    Object.keys(artifact.classifiedLogCounts).sort().join(",") === classifiedLogKeys.sort().join(",") &&
    Object.values(artifact.classifiedLogCounts).every((value) => Number.isInteger(value) && value >= 0);
  if (artifact?.schemaVersion !== "server-health-v1" || artifact.parseStatus !== "ok" ||
      !artifact.windowComplete || !Array.isArray(artifact.memorySamples) ||
      artifact.memorySamples.length === 0 || !Number.isInteger(artifact.deadlockDelta) || artifact.deadlockDelta < 0 ||
      !classifiedLogsValid || !artifact.pm2?.pre || !artifact.pm2?.post ||
      artifact.pm2.pre.length !== 2 || artifact.pm2.post.length !== 2 ||
      !artifact.resolution || !Number.isFinite(artifact.resolution.samples) ||
      artifact.resolution.samples < 1 || artifact.kernelOomParseStatus !== "ok" ||
      !Number.isInteger(artifact.kernelOomKills) || artifact.kernelOomKills < 0) {
    return { valid: false, reason: "server evidence missing or malformed" };
  }
  if (!Number.isFinite(artifact.resolution.maxLagMs) || artifact.resolution.maxLagMs < 0 ||
      !Number.isInteger(artifact.resolution.samples) || artifact.resolution.samples < 1 ||
      !Number.isInteger(artifact.resolution.failures) || artifact.resolution.failures < 0 ||
      !Number.isFinite(artifact.resolution.dedicatedDrainSeconds) || artifact.resolution.dedicatedDrainSeconds < 0 ||
      !Number.isFinite(artifact.resolution.globalDrainSeconds) || artifact.resolution.globalDrainSeconds < 0 ||
      !Number.isInteger(artifact.resolution.consecutiveZeroSamples) || artifact.resolution.consecutiveZeroSamples < 0 ||
      typeof artifact.resolution.dedicatedDrained !== "boolean" || typeof artifact.resolution.globalDrained !== "boolean" ||
      (artifact.resolution.globalDrained && artifact.resolution.consecutiveZeroSamples < 5) ||
      (!artifact.resolution.globalDrained && artifact.resolution.consecutiveZeroSamples >= 5)) {
    return { valid: false, reason: "resolution evidence is missing or malformed" };
  }
  const memory = artifact.memorySamples.map((sample) => typeof sample === "number"
    ? { timestamp: null, availableBytes: sample }
    : sample);
  if (memory.some((sample) => !Number.isFinite(sample.availableBytes) || sample.availableBytes < 0) ||
      memory.some((sample, index) => index > 0 &&
        (Date.parse(sample.timestamp) <= Date.parse(memory[index - 1].timestamp) ||
         Date.parse(sample.timestamp) - Date.parse(memory[index - 1].timestamp) > 2000))) {
    return { valid: false, reason: "server memory sampler is incomplete" };
  }
  const windowStart = Date.parse(artifact.startedAt);
  const windowEnd = Date.parse(artifact.endedAt);
  const firstSample = Date.parse(memory[0].timestamp);
  const lastSample = Date.parse(memory.at(-1).timestamp);
  if (![windowStart, windowEnd, firstSample, lastSample].every(Number.isFinite) ||
      firstSample - windowStart > 2000 || windowEnd - lastSample > 2000) {
    return { valid: false, reason: "server memory sampler does not cover the evidence window" };
  }
  const pm2InstancesValid = [artifact.pm2.pre, artifact.pm2.post].every((workers) =>
    workers.map((worker) => String(worker.instance)).sort().join(",") === "0,1");
  if (!pm2InstancesValid) return { valid: false, reason: "PM2 identity evidence is malformed" };
  if ([...artifact.pm2.pre, ...artifact.pm2.post].some((worker) =>
    !Number.isInteger(worker.pid) || worker.pid < 1 || !Number.isFinite(worker.startedAtMs) ||
    !Number.isInteger(worker.restarts) || worker.restarts < 0 || !Number.isInteger(worker.exitCode) ||
    !Number.isInteger(worker.unstableRestarts) || worker.unstableRestarts < 0)) {
    return { valid: false, reason: "PM2 required fields are missing" };
  }
  const pm2Breaking = [...artifact.pm2.pre, ...artifact.pm2.post].some((worker) =>
    worker.status !== "online" || worker.restarts !== 0 || worker.unstableRestarts !== 0 ||
    worker.exitCode !== 0 || !worker.cwd || !worker.execPath) ||
    artifact.pm2.pre.some((worker) => {
      const after = artifact.pm2.post.find((candidate) => String(candidate.instance) === String(worker.instance));
      return !after || after.cwd !== worker.cwd || after.execPath !== worker.execPath ||
        after.pid !== worker.pid || after.startedAtMs !== worker.startedAtMs;
    });
  const logBreaking = ["p2028", "poolTimeout", "deadlock", "oom"].some((key) =>
    Number(artifact.classifiedLogCounts[key]) > 0);
  const breaking = Math.min(...memory.map((sample) => sample.availableBytes)) < 300 * 1024 ** 2 ||
    artifact.deadlockDelta > 0 || logBreaking || pm2Breaking ||
    Number(artifact.kernelOomKills) > 0 || artifact.resolution.maxLagMs >= 5000 ||
    artifact.resolution.failures > 0 || artifact.resolution.dedicatedDrainSeconds > 60 ||
    artifact.resolution.globalDrainSeconds > 90 || !artifact.resolution.dedicatedDrained ||
    !artifact.resolution.globalDrained;
  return { valid: true, breaking, reason: breaking ? "server-health breaking gate" : null };
}

export function classifyCheckpoint({ summary: input, raw, loadGenerator, server, k6Exit }) {
  const generator = loadGenerator?.valid === true ? loadGenerator : validateLoadGeneratorHealth(loadGenerator);
  const backend = server?.valid === true ? server : validateServerHealth(server);
  if (!generator.valid) return { classification: "invalid", reason: generator.reason || "invalid load-generator evidence" };
  if (!backend.valid) return { classification: "invalid", reason: backend.reason || "invalid server evidence" };
  if (![0, 99].includes(k6Exit)) return { classification: "invalid", reason: "unexpected k6 exit" };
  let summary;
  try { summary = normalizeSummary(input, raw); } catch (error) {
    return { classification: "invalid", reason: error.message };
  }
  const rps = Number(summary.inputs?.offeredRateRps);
  const planned = rps * 35;
  if (summary.inputs?.duration !== "35s" || summary.inputs?.warmupIterations !== rps * 5 ||
      summary.inputs?.preAllocatedVUs !== Math.ceil(rps * 2.4) ||
      summary.inputs?.maxVUs !== Math.ceil(rps * 3.2)) {
    return { classification: "invalid", reason: "checkpoint protocol inputs drifted" };
  }
  const executed = raw?.executed;
  const dropped = raw?.dropped;
  const rawCounters = [executed, dropped, raw?.warmup, raw?.steady, raw?.capacityFailures,
    raw?.hardFailures, raw?.rateLimited429, raw?.contextFallbacks];
  if (!Number.isInteger(planned) || rawCounters.some((value) => !Number.isInteger(value) || value < 0) ||
      Math.abs((executed + dropped) - planned) > 1 || raw?.trafficHttpSamples?.warmup !== raw.warmup ||
      raw?.trafficHttpSamples?.steady !== raw.steady) {
    return { classification: "invalid", reason: "scheduler accounting incomplete" };
  }
  if (dropped > 0) return { classification: "breaking", reason: "dropped arrivals" };
  if (raw.warmup !== rps * 5 || Math.abs(raw.steady - rps * 30) > 1) {
    return { classification: "invalid", reason: "zero-drop phase accounting mismatch" };
  }
  if (raw.http?.length !== raw.steady || Number(raw.contextFallbacks) !== 0) {
    return { classification: "invalid", reason: "steady raw HTTP or endpoint evidence mismatch" };
  }
  const requestCount = raw.steady;
  const failures = Math.max(Number(raw.capacityFailures), Number(raw.hardFailures));
  if (![failures, Number(raw.rateLimited429)].every(Number.isFinite)) {
    return { classification: "invalid", reason: "steady failure counters missing" };
  }
  if (requestCount <= 0 || failures / requestCount >= 0.01 || Number(raw.rateLimited429) / requestCount >= 0.01) {
    return { classification: "breaking", reason: "failure rate" };
  }
  const http95 = percentile(raw.http, 0.95);
  const http99 = percentile(raw.http, 0.99);
  const critical95 = percentile(raw.critical, 0.95);
  const critical99 = percentile(raw.critical, 0.99);
  if ([http95, http99, critical95, critical99].some((value) => value == null)) {
    return { classification: "invalid", reason: "required raw latency samples missing" };
  }
  if (http95 >= 2000 || http99 >= 5000 || critical95 >= 2000 ||
      critical99 >= 5000 || Math.max(...raw.critical) >= 15000 || backend.breaking) {
    return { classification: "breaking", reason: backend.breaking ? backend.reason : "latency gate" };
  }
  return { classification: "pass", reason: "all gates passed" };
}

export function buildCompatibilityFingerprint(inputs) {
  const required = ["corpus", "fixture", "k6", "node", "pm2", "lima", "postgres", "pgbouncer", "hostArch", "guestArch", "limaCpu", "limaMemoryBytes", "portForward", "nginxUpstream", "pgbouncerMapping"];
  for (const key of required) if (!inputs?.[key]) throw new Error(`missing compatibility input ${key}`);
  return sha256(canonicalJson({
    schemaVersion: "daily-k6-compatibility-v1",
    corpus: inputs.corpus,
    fixture: inputs.fixture,
    clientCohort: inputs.clientCohort || "ios_bara_2_3_7_ads_payout",
    topology: {
      workers: 2,
      pgbouncerPool: 25,
      redis: "empty-at-start",
      limaCpu: inputs.limaCpu,
      limaMemoryBytes: inputs.limaMemoryBytes,
      portForward: inputs.portForward,
      nginxUpstream: inputs.nginxUpstream,
      pgbouncerMapping: inputs.pgbouncerMapping,
    },
    durationSeconds: 35,
    warmup: "first-rps-times-5-offered-arrivals",
    classifier: "daily-k6-classifier-v1",
    vuFormula: { preAllocated: "ceil(rps*2.4)", max: "ceil(rps*3.2)" },
    tools: Object.fromEntries(required.slice(2).map((key) => [key, inputs[key]])),
  }));
}

export function selectCheckpoint(records, fingerprint, override = null) {
  if (override != null && (!Number.isInteger(override) || override < 150 || override > 950 || (override - 150) % 100 !== 0)) {
    throw new Error("RPS_OVERRIDE must be a standard ladder value from 150 through 950");
  }
  if (override != null) return { rps: override, standard: false, seriesCompatibility: "nonstandard" };
  const comparable = records.filter((record) => record.schemaVersion === "daily-k6-log-v1" &&
    record.standard === true && record.fingerprint === fingerprint);
  const precedingValid = records.filter((record) =>
    ["pass", "breaking"].includes(record.classification)).at(-1);
  const compatibility = precedingValid?.fingerprint === fingerprint
    ? "comparable"
    : "series reset/non-comparable";
  if (!comparable.length) return { rps: 150, standard: true, floor: null, ceiling: null, seriesCompatibility: compatibility };
  const last = comparable.at(-1);
  if (last.classification === "pass") return { rps: Math.min(950, last.testedRps + 100), standard: true, floor: last.testedRps, ceiling: last.ceiling ?? null, seriesCompatibility: compatibility };
  return { rps: last.testedRps, standard: true, floor: last.floor ?? null, ceiling: last.ceiling ?? null, seriesCompatibility: compatibility };
}

function recordLine(record) {
  validateRecord(record);
  const json = JSON.stringify(record);
  if (Buffer.byteLength(json) > MAX_RECORD_BYTES) throw new Error("daily record exceeds bounded length");
  if (/-->|[\r\n]/.test(json)) throw new Error("daily record contains unsafe text");
  const backend = record.backend ? `\`${String(record.backend).slice(0, 12)}\`` : "—";
  const snapshot = record.snapshotHash ? `\`${record.snapshotHash.slice(0, 19)}…\`` : "—";
  const bound = record.floor == null && record.ceiling != null
    ? `below ${record.ceiling} RPS`
    : `${record.floor == null ? "unknown" : record.floor} / ${record.ceiling == null ? "unknown" : record.ceiling}`;
  const dau = record.roughDau == null ? "—" : `~${Number(record.roughDau).toLocaleString("en-US")} at 0.0259 RPS/DAU`;
  const row = `| Day ${record.day} / ${record.localDate} | ${backend} | ${snapshot} | \`${record.testedRps}\` | \`${record.classification}\` | ${bound} | ${dau} | ${record.note} |`;
  return `<!-- DAILY_K6_LOG_V1 ${json} -->\n${row}`;
}

export function renderDailyRecord(record) {
  return `${recordLine(record)}\n`;
}

const RECORD_KEYS = ["backend", "ceiling", "classification", "day", "fingerprint", "floor", "localDate", "note", "roughDau", "runId", "schemaVersion", "seriesCompatibility", "snapshotHash", "standard", "testedRps"];
const rungValue = (value) => Number.isInteger(value) && value >= 150 && value <= 950 && (value - 150) % 100 === 0;
function validateRecord(record) {
  if (!record || typeof record !== "object" || Array.isArray(record) ||
      Object.keys(record).sort().join(",") !== RECORD_KEYS.slice().sort().join(",") ||
      record.schemaVersion !== "daily-k6-log-v1" || !Number.isInteger(record.day) || record.day < 1 ||
      !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(record.runId || "") ||
      !/^\d{4}-\d{2}-\d{2}$/.test(record.localDate || "") || typeof record.standard !== "boolean" ||
      !["pass", "breaking", "invalid"].includes(record.classification) ||
      !["comparable", "series reset/non-comparable", "nonstandard", "historical-invalid"].includes(record.seriesCompatibility) ||
      !(record.backend == null || /^[a-f0-9]{12,40}$/.test(record.backend)) ||
      !(record.snapshotHash == null || /^sha256:[a-f0-9]{64}$/.test(record.snapshotHash)) ||
      !(record.floor == null || rungValue(record.floor)) || !(record.ceiling == null || rungValue(record.ceiling)) ||
      !(record.roughDau == null || (Number.isInteger(record.roughDau) && record.roughDau >= 0 && record.roughDau % 100 === 0)) ||
      typeof record.note !== "string" || record.note.length < 1 || record.note.length > 180 || /[|\r\n]|-->/.test(record.note)) {
    throw new Error("machine record schema is invalid");
  }
  const historical = record.runId === "historical-aborted-20260818-260rps";
  if (historical) {
    if (record.day !== 1 || record.standard || record.testedRps !== 260 || record.classification !== "invalid" ||
        record.fingerprint !== "historical-invalid" || record.seriesCompatibility !== "historical-invalid" ||
        record.floor != null || record.ceiling != null || record.roughDau != null) throw new Error("historical record is invalid");
  } else if (!rungValue(record.testedRps) || !/^sha256:[a-f0-9]{64}$/.test(record.fingerprint || "") ||
      (record.standard ? !["comparable", "series reset/non-comparable"].includes(record.seriesCompatibility) : record.seriesCompatibility !== "nonstandard") ||
      (!record.standard && (record.floor != null || record.ceiling != null)) ||
      (record.classification === "invalid" && record.roughDau != null) ||
      (record.classification !== "invalid" && (record.backend == null || record.snapshotHash == null || record.roughDau == null))) {
    throw new Error("machine record state is invalid");
  }
}

export function parseDailyLog(markdown) {
  if (markdown.split(START).length !== 2 || markdown.split(END).length !== 2 || markdown.indexOf(START) > markdown.indexOf(END)) {
    throw new Error("daily log markers are missing or ambiguous");
  }
  const block = markdown.slice(markdown.indexOf(START) + START.length, markdown.indexOf(END));
  if (Buffer.byteLength(block) > 1024 * 1024) throw new Error("daily log block exceeds bounded length");
  const records = [];
  const lines = block.split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const match = /^<!-- DAILY_K6_LOG_V1 (\{.*\}) -->$/.exec(lines[index]);
    if (!match) {
      if (["", LOG_HEADER, LOG_SEPARATOR].includes(lines[index])) continue;
      throw new Error("orphan or malformed daily log row");
    }
    if (Buffer.byteLength(match[1]) > MAX_RECORD_BYTES || !lines[index + 1]?.startsWith("| Day ")) {
      throw new Error("machine record is malformed or not paired with a visible row");
    }
    const record = JSON.parse(match[1]);
    validateRecord(record);
    if (lines[index + 1] !== recordLine(record).split("\n")[1]) throw new Error("visible daily row differs from machine record");
    records.push(record);
    index += 1;
  }
  const ids = new Set();
  const days = new Set();
  for (const record of records) {
    if (ids.has(record.runId) || days.has(record.day)) throw new Error("duplicate daily record");
    ids.add(record.runId); days.add(record.day);
  }
  for (let index = 0; index < records.length; index += 1) {
    if (records[index].day !== index + 1) throw new Error("daily records are out of order");
  }
  const state = new Map();
  let precedingValid = null;
  for (const record of records) {
    if (record.standard) {
      const prior = state.get(record.fingerprint);
      const expectedRps = !prior ? 150 : prior.classification === "pass" ? Math.min(950, prior.testedRps + 100) : prior.testedRps;
      if (record.testedRps !== expectedRps) throw new Error("standard ladder transition is invalid");
      const expectedCompatibility = precedingValid?.fingerprint === record.fingerprint ? "comparable" : "series reset/non-comparable";
      if (record.seriesCompatibility !== expectedCompatibility) throw new Error("series compatibility label is invalid");
      let floor = prior?.floor ?? null;
      let ceiling = prior?.ceiling ?? null;
      if (record.classification === "pass") { floor = record.testedRps; if (ceiling === record.testedRps) ceiling = null; }
      if (record.classification === "breaking") ceiling = ceiling == null ? record.testedRps : Math.min(ceiling, record.testedRps);
      if (record.floor !== floor || record.ceiling !== ceiling) throw new Error("standard floor/ceiling state is invalid");
      state.set(record.fingerprint, record);
    }
    if (["pass", "breaking"].includes(record.classification)) precedingValid = record;
  }
  return records;
}

export function appendDailyRecord(readmePath, expectedHash, record) {
  const markdown = fs.readFileSync(readmePath, "utf8");
  if (sha256(markdown) !== expectedHash) throw new Error("README changed after checkpoint selection");
  const records = parseDailyLog(markdown);
  if (records.some((item) => item.runId === record.runId || item.day === record.day)) throw new Error("duplicate daily record");
  const insertion = `${recordLine(record)}\n`;
  const updated = markdown.replace(END, `${insertion}${END}`);
  parseDailyLog(updated);
  const temporary = path.join(path.dirname(readmePath), `.${path.basename(readmePath)}.${process.pid}.tmp`);
  fs.writeFileSync(temporary, updated, { mode: fs.statSync(readmePath).mode });
  fs.renameSync(temporary, readmePath);
}

export function replaceDailyRecord(readmePath, runId, record) {
  const markdown = fs.readFileSync(readmePath, "utf8");
  const records = parseDailyLog(markdown);
  if (records.filter((item) => item.runId === runId).length !== 1 || record.runId !== runId) {
    throw new Error("cannot safely identify appended daily record");
  }
  const lines = markdown.split("\n");
  const index = lines.findIndex((line) => {
    const match = /^<!-- DAILY_K6_LOG_V1 (\{.*\}) -->$/.exec(line);
    if (!match) return false;
    try { return JSON.parse(match[1]).runId === runId; } catch { return false; }
  });
  if (index < 0 || !lines[index + 1]?.startsWith("| Day ")) throw new Error("daily record pair is missing");
  lines.splice(index, 2, ...recordLine(record).split("\n"));
  parseDailyLog(lines.join("\n"));
  const temporary = path.join(path.dirname(readmePath), `.${path.basename(readmePath)}.${process.pid}.tmp`);
  fs.writeFileSync(temporary, lines.join("\n"), { mode: fs.statSync(readmePath).mode });
  fs.renameSync(temporary, readmePath);
}

export const DAILY_LOG_MARKERS = Object.freeze({ start: START, end: END });
