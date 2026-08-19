"use strict";

// This file is delivered verbatim over SSH stdin and executes only on the
// production host. It emits one redacted JSON line and never prints raw errors.
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { createRequire } = require("node:module");
const originalStdoutWrite = process.stdout.write.bind(process.stdout);
process.stdout.write = () => true;
process.stderr.write = () => true;
console.log = () => {};
console.error = () => {};
console.warn = () => {};

const PERFORMANCE_REGISTRY_V1 = {
  placementDistributedClaimEnabled: { env: "PLACEMENT_DISTRIBUTED_CLAIM_ENABLED", type: "boolean", default: false },
  placementInertPushSuppressionEnabled: { env: "PLACEMENT_INERT_PUSH_SUPPRESSION_ENABLED", type: "boolean", default: false },
  placementLeanBaselineWritesEnabled: { env: "PLACEMENT_LEAN_BASELINE_WRITES_ENABLED", type: "boolean", default: false },
  stepSyncBulkEnabled: { env: "STEP_SYNC_BULK_ENABLED", type: "boolean", default: false },
  apnsSessionReuseEnabled: { env: "APNS_SESSION_REUSE_ENABLED", type: "boolean", default: false },
  placementBaselineWriteConcurrency: { env: "PLACEMENT_BASELINE_WRITE_CONCURRENCY", type: "integer", default: 4, min: 1, max: 8 },
  stepSyncPushConcurrency: { env: "STEP_SYNC_PUSH_CONCURRENCY", type: "integer", default: 8, min: 1, max: 16 },
};
const RUNTIME_PATHS = ["package.json", "package-lock.json", "prisma.config.ts", "src", "prisma"];
// package-lock.json is deployment provenance, but Node does not load it at
// runtime. Deploy tooling may refresh its mtime after PM2 has already started.
const LOADED_CODE_PATHS = ["package.json", "prisma.config.ts", "src", "prisma"];
const backendDir = process.argv[2];
let output;

function fail(code) {
  const error = new Error(code);
  error.safeCode = code;
  throw error;
}

function command(commandName, args, options = {}) {
  return execFileSync(commandName, args, {
    cwd: backendDir,
    encoding: "utf8",
    timeout: 15_000,
    maxBuffer: 1024 * 1024,
    stdio: ["ignore", "pipe", "ignore"],
    ...options,
  }).trim();
}

function envIdentity() {
  const envPath = path.join(backendDir, ".env");
  const stat = fs.lstatSync(envPath);
  if (!stat.isFile() || stat.isSymbolicLink()) fail("ENV_NOT_REGULAR");
  const bytes = fs.readFileSync(envPath);
  return {
    path: envPath,
    bytes,
    hash: crypto.createHash("sha256").update(bytes).digest("hex"),
    mtimeMs: stat.mtimeMs,
    size: stat.size,
  };
}

function gitIdentity() {
  const head = command("git", ["rev-parse", "HEAD^{commit}"]);
  if (!/^[a-f0-9]{40}$/.test(head)) fail("GIT_HEAD_INVALID");
  const trackedChanges = command("git", ["status", "--porcelain=v1", "--untracked-files=no", "--", ...RUNTIME_PATHS]);
  const untrackedFiles = command("git", ["ls-files", "--others", "--", ...RUNTIME_PATHS]);
  if (trackedChanges || untrackedFiles) {
    fail("RUNTIME_TREE_DIRTY");
  }
  const tracked = command("git", ["ls-files", "--", ...RUNTIME_PATHS]).split("\n").filter(Boolean);
  if (!tracked.length) fail("TRACKED_RUNTIME_EMPTY");
  const loadedCode = command("git", ["ls-files", "--", ...LOADED_CODE_PATHS]).split("\n").filter(Boolean);
  if (!loadedCode.length) fail("TRACKED_RUNTIME_EMPTY");
  const newestRuntimeMtimeMs = Math.max(...loadedCode.map((relative) =>
    fs.statSync(path.join(backendDir, relative)).mtimeMs));
  const reflog = path.join(command("git", ["rev-parse", "--git-dir"]), "logs", "HEAD");
  if (!fs.existsSync(reflog)) fail("REFLOG_INDETERMINATE");
  const reflogSha = command("git", ["reflog", "-1", "--format=%H", "HEAD"]);
  if (!/^[a-f0-9]{40}$/.test(reflogSha) || reflogSha !== head) fail("REFLOG_HEAD_MISMATCH");
  return { head, reflogSha, newestRuntimeMtimeMs, reflogMtimeMs: fs.statSync(reflog).mtimeMs };
}

function pm2Identity(git, registry, envMtimeMs) {
  const all = JSON.parse(command("pm2", ["jlist"]));
  const workers = all.filter((process) => process.name === "steps-tracker");
  if (workers.length !== 2) fail("WORKER_COUNT");
  const normalized = workers.map((worker) => {
    const pm = worker.pm2_env || {};
    const instance = String(pm.NODE_APP_INSTANCE ?? pm.env?.NODE_APP_INSTANCE ?? "");
    const cwd = path.resolve(pm.pm_cwd || "");
    const execPath = path.resolve(pm.pm_exec_path || "");
    if (pm.status !== "online" || cwd !== backendDir || execPath !== path.join(backendDir, "src/index.js")) {
      fail("WORKER_IDENTITY");
    }
    const revisionCandidates = [pm.versioning?.revision, pm.pm2_git_revision, pm.DEPLOY_REVISION, pm.env?.DEPLOY_REVISION]
      .filter((value) => value != null && String(value) !== "")
      .map(String);
    if (!Number.isFinite(pm.pm_uptime) || pm.pm_uptime <= envMtimeMs) fail("WORKER_PREDATES_ENV");
    if (revisionCandidates.length) {
      if (revisionCandidates.some((revision) => !/^[a-f0-9]{40}$/.test(revision) || revision !== git.head)) {
        fail("WORKER_REVISION_MISMATCH");
      }
    } else if (!Number.isFinite(pm.pm_uptime) || pm.pm_uptime <= git.reflogMtimeMs ||
               pm.pm_uptime <= git.newestRuntimeMtimeMs) {
      fail("WORKER_LOADED_CODE_UNPROVEN");
    }
    return {
      instance,
      status: pm.status,
      cwd,
      execPath,
      pid: Number(worker.pid),
      uptimeMs: Number(pm.pm_uptime),
      restartCount: Number(pm.restart_time || 0),
      revisionMetadataPresent: revisionCandidates.length > 0,
      allowlistedOverrides: Object.fromEntries(Object.values(registry)
        .filter(({ env }) => Object.hasOwn(pm, env) || Object.hasOwn(pm.env || {}, env))
        .map(({ env }) => [env, String(pm[env] ?? pm.env[env])])),
    };
  }).sort((left, right) => left.instance.localeCompare(right.instance));
  if (normalized.map(({ instance }) => instance).join(",") !== "0,1") fail("WORKER_INSTANCES");
  if (normalized[0].revisionMetadataPresent !== normalized[1].revisionMetadataPresent) fail("PARTIAL_WORKER_REVISION_METADATA");
  return normalized;
}

function sameIdentity(before, after) {
  return JSON.stringify(before) === JSON.stringify(after);
}

function inferPerformanceRegistry(readPerformanceFlags) {
  const accessed = new Set();
  const defaults = readPerformanceFlags(new Proxy({}, { get(_target, property) { accessed.add(String(property)); return undefined; } }));
  const registry = {};
  for (const env of accessed) {
    const trueProbe = readPerformanceFlags({ [env]: "true" });
    const highProbe = readPerformanceFlags({ [env]: "999999999" });
    const changed = Object.keys(defaults).filter((semantic) =>
      trueProbe[semantic] !== defaults[semantic] || highProbe[semantic] !== defaults[semantic]);
    if (changed.length !== 1) fail("PERFORMANCE_REGISTRY_UNSUPPORTED");
    const semantic = changed[0];
    if (typeof defaults[semantic] === "boolean" && trueProbe[semantic] === true) {
      registry[semantic] = { env, type: "boolean", default: defaults[semantic] };
    } else if (Number.isInteger(defaults[semantic]) && Number.isInteger(highProbe[semantic])) {
      registry[semantic] = { env, type: "integer", default: defaults[semantic], min: readPerformanceFlags({ [env]: "-999999999" })[semantic], max: highProbe[semantic] };
    } else fail("PERFORMANCE_REGISTRY_UNSUPPORTED");
  }
  for (const [semantic, mapping] of Object.entries(PERFORMANCE_REGISTRY_V1)) {
    if (JSON.stringify(registry[semantic]) !== JSON.stringify(mapping)) fail("PERFORMANCE_REGISTRY_V1_DRIFT");
  }
  return registry;
}

(async () => {
  try {
    if (!backendDir || !path.isAbsolute(backendDir) || backendDir.split("/").includes("..")) fail("BACKEND_DIR_INVALID");
    process.chdir(backendDir);
    const requireFromDeploy = createRequire(path.join(backendDir, "package.json"));
    const envBefore = envIdentity();
    const gitBefore = gitIdentity();
    // Prove the fixed v1 worker identity before any deployed runtime module is loaded.
    pm2Identity(gitBefore, PERFORMANCE_REGISTRY_V1, envBefore.mtimeMs);
    const dotenv = requireFromDeploy("dotenv");
    const deployedEnv = dotenv.parse(envBefore.bytes, { debug: false, quiet: true });
    const { readPerformanceFlags } = requireFromDeploy("./src/shared/config/performanceFlags.js");
    const deployedRegistry = inferPerformanceRegistry(readPerformanceFlags);
    const workersBefore = pm2Identity(gitBefore, deployedRegistry, envBefore.mtimeMs);
    const workerFlags = workersBefore.map((worker) => readPerformanceFlags({ ...deployedEnv, ...worker.allowlistedOverrides }));
    if (!sameIdentity(workerFlags[0], workerFlags[1])) fail("WORKER_FLAGS_MISMATCH");
    for (const [semantic, mapping] of Object.entries(deployedRegistry)) {
      const value = workerFlags[0][semantic];
      if (mapping.type === "boolean" ? typeof value !== "boolean" :
          !Number.isInteger(value) || value < mapping.min || value > mapping.max) fail("PERFORMANCE_VALUE_INVALID");
    }
    const operationalEnv = Object.fromEntries(["PATH", "HOME", "PM2_HOME"]
      .filter((key) => process.env[key] != null)
      .map((key) => [key, process.env[key]]));
    for (const key of Object.keys(process.env)) delete process.env[key];
    Object.assign(process.env, operationalEnv);
    for (const [key, value] of Object.entries(deployedEnv)) process.env[key] = value;
    const { prisma } = requireFromDeploy("./src/db.js");
    const { buildAppSettings } = requireFromDeploy("./src/shared/config/appSettings.js");
    let productionDbSettings;
    try {
      productionDbSettings = await prisma.$transaction(async (tx) => {
        await tx.$executeRawUnsafe("SET TRANSACTION READ ONLY");
        const [readOnly] = await tx.$queryRawUnsafe("SHOW transaction_read_only");
        if (readOnly?.transaction_read_only !== "on") fail("TRANSACTION_NOT_READ_ONLY");
        return buildAppSettings({ prisma: tx }).getAllFlags();
      }, { maxWait: 2000, timeout: 10000 });
    } finally {
      await prisma.$disconnect();
    }
    const envAfter = envIdentity();
    const gitAfter = gitIdentity();
    const workersAfter = pm2Identity(gitAfter, deployedRegistry, envAfter.mtimeMs);
    if (envBefore.hash !== envAfter.hash || envBefore.mtimeMs !== envAfter.mtimeMs || envBefore.size !== envAfter.size) fail("ENV_CHANGED_DURING_CAPTURE");
    if (!sameIdentity(gitBefore, gitAfter)) fail("GIT_CHANGED_DURING_CAPTURE");
    if (!sameIdentity(workersBefore, workersAfter)) fail("PM2_CHANGED_DURING_CAPTURE");
    output = {
      schemaVersion: 1,
      productionDbSettings,
      productionPerformanceFlags: workerFlags[0],
      performanceRegistry: deployedRegistry,
      expectedWorkerCount: 2,
      observedWorkerCount: workersAfter.length,
      workers: workersAfter.map(({ instance, status, pid, uptimeMs, restartCount }) => ({
        instance,
        status,
        pid,
        startedAtMs: uptimeMs,
        restartCount,
        identityVerified: true,
        loadedRevisionVerified: true,
        environmentAgeVerified: true,
      })),
      deployedLoadedRevision: gitAfter.head,
      captureTime: new Date().toISOString(),
      ignoredProductionOnlyKeys: [],
    };
  } catch (error) {
    output = { schemaVersion: 1, ok: false, errorCode: error.safeCode || "REMOTE_HELPER_FAILED" };
    process.exitCode = 20;
  }
})().finally(() => {
  originalStdoutWrite(`${JSON.stringify(output)}\n`);
});
