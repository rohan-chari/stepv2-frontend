import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const read = (relativePath) =>
  readFileSync(new URL(`../${relativePath}`, import.meta.url), "utf8");

test("sanitizer and validator cover linked durable provider hashes", () => {
  const sanitizer = read("local-prod-sim/sanitize.sql");
  const validator = read("local-prod-sim/validate-sanitization.sql");
  for (const table of [
    "race_payout_double_identities",
    "race_payout_double_offers",
    "race_payout_double_velocity_grants",
    "race_payout_double_claim_receipts",
    "referrals",
    "referral_reward_grants",
  ]) {
    assert.match(validator, new RegExp(`FROM ${table}\\b`));
  }
  assert.match(sanitizer, /CREATE TEMP TABLE payout_hash_map/);
  assert.match(sanitizer, /CREATE TEMP TABLE referral_hash_map/);
  assert.match(validator, /payout provider hash linkage failures/);
  assert.match(validator, /referral provider hash linkage failures/);
});

test("one-command runner isolates exactly optimization 1 and always tears down", () => {
  const runner = read("local-prod-sim/run-optimization1-comparison.zsh");
  assert.match(runner, /run_variant off[\s\S]*run_variant on/);
  assert.match(runner, /diagnostic_\$\{rate_rps\}rps/);
  assert.match(runner, /raceResolutionQueuedGenerationMergeV1Enabled/);
  assert.match(runner, /pm2 start src\/capacityLocal\.js/);
  assert.doesNotMatch(runner, /CAPACITY_HTTP_RESOLUTION_ONLY/);
  assert.match(runner, /capacity-http-resolution-only/);
  assert.match(runner, /MATCHED_PAIR_EPOCH_MS/);
  assert.match(runner, /git ls-files -z/);
  assert.match(runner, /source_manifest/);
  assert.match(runner, /refusing sensitive runtime path/);
  assert.match(runner, /pem\|key\|p12\|pfx\|jks\|keystore/);
  assert.ok(
    runner.indexOf("refusing sensitive runtime path") <
      runner.indexOf('tar --no-xattrs --null -T "$source_manifest"'),
    "the selected source manifest must be rejected before it enters the tar",
  );
  assert.doesNotMatch(runner, /cp \/opt\/stepv2-backend\/\.env|git ls-files[^\n]*(CLAUDE\.local|service-account)/);
  assert.match(runner, /host\.lima\.internal:56432\/\$capacity_db/);
  assert.match(runner, /capacityBenchmarkCorpusMarker/);
  assert.match(runner, /remint-local-fixture\.mjs/);
  assert.match(runner, /USERS_FILE="\$local_fixture"/);
  assert.match(runner, /rm -f -- "\$result_dir\/off-fixture\.json"/);
  assert.match(runner, /--output "\$4" --error "\$5"/);
  assert.match(runner, /expected_corpus_sha/);
  assert.match(runner, /expected_fixture_revision/);
  assert.match(runner, /\^stepv2_capacity_\[A-Za-z0-9_\]\+\$/);
  assert.ok(runner.indexOf("SHOW data_directory") < runner.indexOf('"$pg_bin/dropdb"'));
  assert.match(runner, /WARMUP_ITERATIONS="\$warmup_iterations"/);
  assert.doesNotMatch(
    runner,
    /raceProgressLeanProjectionV1Enabled|legacyUploaderStepSamplePrefetchV1Enabled|placementBaselineWorkerBatchV1Enabled/,
  );
  assert.match(runner, /pg_restore[\s\S]*run_variant/);
  assert.match(runner, /pm_cwd|\.pm2_env\.pm_cwd/);
  assert.match(runner, /pm_exec_path/);
  assert.match(runner, /trap 'teardown' EXIT/);
  assert.match(runner, /trap 'exit_code=\$\?; teardown; exit \$exit_code' ZERR/);
  assert.match(runner, /limactl stop/);
  assert.match(runner, /pg_ctl[\s\S]*stop -m fast/);
  assert.match(runner, /stop_owned_pgbouncer/);
  assert.match(runner, /pgbouncer\.owner/);
  assert.match(runner, /ps -p "\$pool_pid" -o lstart=/);
  assert.match(runner, /ps -p "\$pool_pid" -o command=/);
  assert.match(runner, /ps -p "\$pool_pid" -o comm=/);
  assert.ok(
    runner.lastIndexOf('rmdir "$lock_dir"') >
      runner.lastIndexOf('stop -m fast'),
    "the single-run lock must be released only after every shared service is stopped",
  );
  assert.doesNotMatch(runner, /steptracker-api\.org|staging\.steptracker-api\.org/);
  assert.doesNotMatch(runner, /\/Users\/rohan/);
});

test("runbook exposes one normal command and keeps production refresh separate", () => {
  const runbook = read("LOCAL-PROD-SIM-RUNBOOK.md");
  assert.match(runbook, /run-optimization1-comparison\.zsh/);
  assert.match(runbook, /approximately five minutes/i);
  assert.match(runbook, /never connects to production/i);
  assert.match(runbook, /separate, in-the-moment authorization/i);
  assert.match(runbook, /host\.lima\.internal/);
  assert.match(runbook, /STAGING_DATABASE_URL/);
  assert.doesNotMatch(runbook, /EXPERIMENT-[23]|legacy uploader|placement batch/i);
});

test("summary is strict and never auto-approves a fast diagnostic", () => {
  const directory = mkdtempSync(join(tmpdir(), "opt1-summary-"));
  try {
    const make = (flag) => ({
      schemaVersion: "capacity-harness-summary-v1",
      inputs: {
        baseUrl: "http://127.0.0.1:3302",
        rung: "diagnostic_160rps",
        backendRevision: "abc1234",
        offeredRateRps: 2,
        duration: "2s",
        clientCohort: "ios_bara_2_3_7_ads_payout",
        config: "prod-sim",
        workerCount: "2",
        pgBouncerPool: "25",
        redisState: "empty",
        cronCohort: "capacity-http-resolution-only",
        flags: `queued-generation-merge=${flag}`,
        matchedPairEpochMs: 1787073600000,
        warmupIterations: 1,
      },
      totals: {
        requests: { count: 4800, rate: 158 },
        duration: { "p(95)": 50, "p(99)": 100, max: 500 },
        persistenceCriticalDuration: { "p(95)": 80, "p(99)": 200 },
        hardFailures: { count: 0 },
        capacityFailures: { count: 0 },
        droppedArrivals: { count: 0 },
        rateLimited429: { count: 0 },
        contextFallbacks: { count: 0 },
        resolutionLag: { max: 22000 },
        finalResolutionOutstanding: { value: 0 },
        resolutionStates: {
          failed: { count: 0 },
          superseded: { count: 0 },
        },
      },
      endpointAccounting: Object.fromEntries(
        ["steps_sync_v2", "steps_post", "steps_samples"].map((endpoint, index) => [
          endpoint,
          { selected: index === 0 ? 2 : 1, executed: index === 0 ? 2 : 1,
            durationSamples: index === 0 ? 2 : 1, statusTotal: index === 0 ? 2 : 1 },
        ]),
      ),
      thresholds: Object.fromEntries([
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
      ].map((metric) => [
        `${metric}{rung:diagnostic_160rps}`,
        { gate: metric !== "resolution_lag_ms" },
      ])),
    });
    const off = join(directory, "off.json");
    const on = join(directory, "on.json");
    const output = join(directory, "result.md");
    const offRaw = join(directory, "off.ndjson");
    const onRaw = join(directory, "on.ndjson");
    writeFileSync(off, JSON.stringify(make(false)));
    writeFileSync(on, JSON.stringify(make(true)));
    const artifact = (name, contents) => {
      const path = join(directory, name);
      writeFileSync(path, contents);
      return path;
    };
    const point = (metric, endpoint, value, second) => JSON.stringify({
      metric,
      data: {
        time: new Date(Date.UTC(2026, 7, 18, 12, 0, second)).toISOString(),
        value,
        tags: { endpoint, traffic_phase: second === 0 ? "warmup" : "steady" },
      },
    });
    const lines = [];
    for (const endpoint of ["steps_sync_v2", "steps_post", "steps_samples"]) {
      lines.push(point("endpoint_duration_ms", endpoint, 25, 0));
      lines.push(point("endpoint_duration_ms", endpoint, 25, 6));
    }
    lines.push(point("http_req_duration", "steps_post", 40, 0));
    lines.push(point("http_req_duration", "steps_post", 30, 6));
    lines.push(point("http_req_duration", "steps_sync_v2", 31, 6));
    lines.push(point("http_req_duration", "steps_samples", 32, 6));
    lines.push(point("persistence_critical_duration_ms", "steps_post", 70, 6));
    const raw = lines.join("\n");
    writeFileSync(offRaw, raw);
    writeFileSync(onRaw, raw);
    const script = new URL(
      "../local-prod-sim/summarize-optimization1.mjs",
      import.meta.url,
    );
    const args = [script.pathname, "--off", off, "--on", on,
        "--off-raw", offRaw, "--on-raw", onRaw,
        "--off-exit", artifact("off-exit", "99"),
        "--on-exit", artifact("on-exit", "99"),
        "--off-post-k6-backlog", artifact("off-backlog", "4"),
        "--on-post-k6-backlog", artifact("on-backlog", "4"),
        "--off-post-k6-drain", artifact("off-drain", "12"),
        "--on-post-k6-drain", artifact("on-drain", "12"),
        "--warmup-iterations", "1", "--output", output];
    const runSummary = () => spawnSync(
      process.execPath,
      args,
      { encoding: "utf8" },
    );
    const result = runSummary();
    assert.equal(result.status, 0, result.stderr);
    assert.match(readFileSync(output, "utf8"), /DIAGNOSTIC ONLY/);
    assert.doesNotMatch(readFileSync(output, "utf8"), /ADVANCE_TO_REVIEW/);

    const truncated = lines.filter((line) =>
      !(line.includes('"metric":"http_req_duration"') && line.includes('"endpoint":"steps_samples"')),
    ).join("\n");
    writeFileSync(offRaw, truncated);
    writeFileSync(onRaw, truncated);
    assert.notEqual(runSummary().status, 0);
    writeFileSync(offRaw, raw);
    writeFileSync(onRaw, raw);

    for (const mutate of [
      (summary) => { summary.totals.finalResolutionOutstanding.value = 1; },
      (summary) => { summary.totals.resolutionStates.failed.count = 1; },
      (summary) => {
        summary.thresholds["http_req_duration{rung:diagnostic_160rps}"].gate = false;
      },
      (summary) => { delete summary.thresholds["dropped_iterations{rung:diagnostic_160rps}"]; },
    ]) {
      const invalid = make(false);
      mutate(invalid);
      writeFileSync(off, JSON.stringify(invalid));
      assert.notEqual(runSummary().status, 0);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("harness labels deterministic warm-up and steady arrivals", () => {
  const harness = read("prod-mix-load-test.js");
  assert.match(harness, /WARMUP_ITERATIONS/);
  assert.match(harness, /iteration < WARMUP_ITERATIONS/);
  assert.match(harness, /traffic_phase/);
});

test("findings index retains only the optimization-1 decision", () => {
  const index = read("findings/README.md");
  assert.match(index, /Optimization 1 matched aggressive comparison/);
  assert.doesNotMatch(index, /Experiment 2|Experiment 3|M5\.1/);
});
