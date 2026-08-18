import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { aggregateCapacityCohort } from "../cohort-aggregator.mjs";
import { ENDPOINTS } from "../harness-contract.mjs";

function runIdentity(repeat) {
  return { runId: `run-${repeat}`, repeatIndex: String(repeat) };
}

function setting() {
  return {
    backendRevision: "abcdef1234567890",
    flags: "all-capacity-flags-off",
    config: "capacity-phase-metrics-v1-query-capture-on",
    workerCount: "1",
    pgBouncerPool: "3",
    redisState: "warm-process-warm-redis",
    cronCohort: "warm-steady-outside-heavy-tick",
  };
}

function summary(repeat, endpointCount = 7, baseUrl = "https://staging.steptracker-api.org") {
  return {
    schemaVersion: "capacity-harness-summary-v1",
    inputs: {
      mode: "capacity",
      claimable: false,
      capacityCandidate: true,
      baseUrl,
      offeredRateRps: 15,
      rung: "rate_15rps",
      duration: "90s",
      clientCohort: "ios_bara_2_3_7_ads_payout",
      fixture: { fixtureRevision: "fixture-1" },
      ...setting(),
      ...runIdentity(repeat),
    },
    thresholds: {
      core: { "rate==0": true },
    },
    endpointAccounting: {
      race_detail: {
        selected: endpointCount,
        executed: endpointCount,
        durationSamples: endpointCount,
        statusTotal: endpointCount,
      },
      auth_me: {
        selected: endpointCount,
        executed: endpointCount,
        durationSamples: endpointCount,
        statusTotal: endpointCount,
      },
    },
  };
}

function evidence(repeat, overrides = {}) {
  const identity = runIdentity(repeat);
  const result = {
    schema: "capacity-telemetry-evidence-v1",
    ...identity,
    queryCaptureAvailable: true,
    measurementGateEligible: true,
    setting: setting(),
    telemetry: {
      schema: "capacity-telemetry-server-evidence-v1",
      runId: identity.runId,
      repeat: identity.repeatIndex,
      event: "capacity_phase_metrics_v1",
      sampleCount: 4,
      queryCaptureAvailable: true,
      measurementGateEligible: true,
      queryCaptureSetting: "PRISMA_QUERY_EVENTS_ENABLED=true",
      surfaces: ["race_progress"],
    },
  };
  return Object.assign(result, overrides);
}

function point(metric, value, repeat, tags = {}) {
  const identity = runIdentity(repeat);
  return {
    type: "Point",
    metric,
    data: {
      value,
      tags: {
        rung: "rate_15rps",
        client_cohort: "ios_bara_2_3_7_ads_payout",
        run_id: identity.runId,
        repeat_index: identity.repeatIndex,
        ...tags,
      },
    },
  };
}

function repeatPoints(repeat, durationCount = 7) {
  const result = [];
  for (const endpoint of ["race_detail", "auth_me"]) {
    result.push(point("selected_endpoint_count", durationCount, repeat, { endpoint }));
    result.push(point("executed_endpoint_count", durationCount, repeat, { endpoint }));
    result.push(point("response_status_count", durationCount, repeat, { endpoint, status: "200" }));
    for (let index = 0; index < durationCount; index += 1) {
      result.push(
        point("endpoint_duration_ms", endpoint === "auth_me" ? 2100 : 100, repeat, {
          endpoint,
          status: "200",
        }),
      );
    }
  }
  result.push(point("resolution_state_count", 1, repeat, { state: "succeeded" }));
  return result;
}

test("three-repeat aggregate conditionally gates endpoint p95 and emits exact counts", () => {
  const result = aggregateCapacityCohort({
    summaries: [summary(1), summary(2), summary(3)],
    rawRuns: [repeatPoints(1), repeatPoints(2), repeatPoints(3)],
    evidences: [evidence(1), evidence(2), evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.equal(result.valid, false);
  assert.equal(result.endpoints.race_detail.samples, 21);
  assert.equal(result.endpoints.race_detail.p95Ms, 100);
  assert.equal(result.endpoints.race_detail.statusCounts["200"], 21);
  assert.equal(result.endpoints.auth_me.p95GateApplied, true);
  assert.equal(result.endpoints.auth_me.p95GatePassed, false);
  assert.equal(result.resolutionStateCounts.succeeded, 3);
});

test("aggregate requires exactly three matched raw/summary repeats", () => {
  assert.throws(
    () =>
      aggregateCapacityCohort({
        summaries: [summary(1), summary(2)],
        rawRuns: [repeatPoints(1), repeatPoints(2)],
        evidences: [evidence(1), evidence(2)],
        configuredEndpoints: ["race_detail", "auth_me"],
      }),
    /exactly three/,
  );
});

test("aggregate fails selected/executed mismatch even when both are nonzero", () => {
  const points = repeatPoints(1, 2);
  points.push(point("selected_endpoint_count", 1, 1, { endpoint: "race_detail" }));
  const result = aggregateCapacityCohort({
    summaries: [summary(1, 2), summary(2, 2), summary(3, 2)],
    rawRuns: [points, repeatPoints(2, 2), repeatPoints(3, 2)],
    evidences: [evidence(1), evidence(2), evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.equal(result.endpoints.race_detail.selected, 7);
  assert.equal(result.endpoints.race_detail.executed, 6);
  assert.equal(result.endpoints.race_detail.accountingGatePassed, false);
  assert.equal(result.valid, false);
});

test("sparse endpoints below 20 aggregate samples do not receive a p95 gate", () => {
  const result = aggregateCapacityCohort({
    summaries: [summary(1, 2), summary(2, 2), summary(3, 2)],
    rawRuns: [repeatPoints(1, 2), repeatPoints(2, 2), repeatPoints(3, 2)],
    evidences: [evidence(1), evidence(2), evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.equal(result.endpoints.auth_me.samples, 6);
  assert.equal(result.endpoints.auth_me.p95GateApplied, false);
});

test("aggregate rejects reused run IDs, mispaired raw output, and truncated endpoint metrics", () => {
  const duplicateSummaries = [summary(1), summary(1), summary(3)];
  const duplicateResult = aggregateCapacityCohort({
    summaries: duplicateSummaries,
    rawRuns: [repeatPoints(1), repeatPoints(1), repeatPoints(3)],
    evidences: [evidence(1), evidence(1), evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.match(duplicateResult.failures.join("\n"), /run IDs must be unique/);

  const mispairedResult = aggregateCapacityCohort({
    summaries: [summary(1), summary(2), summary(3)],
    rawRuns: [repeatPoints(2), repeatPoints(1), repeatPoints(3)],
    evidences: [evidence(1), evidence(2), evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.match(mispairedResult.failures.join("\n"), /raw identity mismatches/);

  const truncated = repeatPoints(1, 2);
  truncated.splice(
    truncated.findIndex(
      (entry) => entry.metric === "response_status_count" && entry.data.tags.endpoint === "auth_me",
    ),
    1,
  );
  const truncatedResult = aggregateCapacityCohort({
    summaries: [summary(1, 2), summary(2, 2), summary(3, 2)],
    rawRuns: [truncated, repeatPoints(2, 2), repeatPoints(3, 2)],
    evidences: [evidence(1), evidence(2), evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.match(truncatedResult.failures.join("\n"), /selected.*executed.*duration.*status/i);

  const quartetRemoved = repeatPoints(1).filter(
    (entry) => entry.data.tags.endpoint !== "auth_me",
  );
  const quartetResult = aggregateCapacityCohort({
    summaries: [summary(1), summary(2), summary(3)],
    rawRuns: [quartetRemoved, repeatPoints(2), repeatPoints(3)],
    evidences: [evidence(1), evidence(2), evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.match(quartetResult.failures.join("\n"), /repeat 1.*auth_me.*summary/i);
});

test("claimability rejects placeholders and malformed topology labels", () => {
  const placeholder = summary(2);
  placeholder.inputs.backendRevision = "replace-me";
  const malformed = summary(3);
  malformed.inputs.pgBouncerPool = "pool-three";
  const result = aggregateCapacityCohort({
    summaries: [summary(1), placeholder, malformed],
    rawRuns: [repeatPoints(1), repeatPoints(2), repeatPoints(3)],
    evidences: [evidence(1), evidence(2), evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.equal(result.claimable, false);
  assert.match(result.failures.join("\n"), /required operator labels are structurally invalid/);
});

test("claimability requires identical approved staging base URLs", () => {
  const mixed = aggregateCapacityCohort({
    summaries: [summary(1), summary(2, 7, "http://localhost:3000"), summary(3)],
    rawRuns: [repeatPoints(1), repeatPoints(2), repeatPoints(3)],
    evidences: [evidence(1), evidence(2), evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.equal(mixed.claimable, false);
  assert.match(mixed.failures.join("\n"), /base URL|inputs do not match/i);

  const local = aggregateCapacityCohort({
    summaries: [1, 2, 3].map((repeat) => summary(repeat, 7, "http://localhost:3000")),
    rawRuns: [repeatPoints(1), repeatPoints(2), repeatPoints(3)],
    evidences: [evidence(1), evidence(2), evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.equal(local.claimable, false);
  assert.match(local.failures.join("\n"), /approved staging base URL/);
});

test("claimability requires bound server telemetry evidence and fully recorded settings", () => {
  const invalidEvidence = evidence(2);
  invalidEvidence.telemetry.queryCaptureAvailable = false;
  const result = aggregateCapacityCohort({
    summaries: [summary(1), summary(2), summary(3)],
    rawRuns: [repeatPoints(1), repeatPoints(2), repeatPoints(3)],
    evidences: [evidence(1), invalidEvidence, evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.equal(result.claimable, false);
  assert.match(result.failures.join("\n"), /queryCaptureAvailable/);

  const misboundEvidence = evidence(2);
  misboundEvidence.runId = "different-run";
  const misboundResult = aggregateCapacityCohort({
    summaries: [summary(1), summary(2), summary(3)],
    rawRuns: [repeatPoints(1), repeatPoints(2), repeatPoints(3)],
    evidences: [evidence(1), misboundEvidence, evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.match(misboundResult.failures.join("\n"), /runId does not match/);

  const unrecorded = summary(2);
  unrecorded.inputs.config = "UNRECORDED";
  const unrecordedResult = aggregateCapacityCohort({
    summaries: [summary(1), unrecorded, summary(3)],
    rawRuns: [repeatPoints(1), repeatPoints(2), repeatPoints(3)],
    evidences: [evidence(1), evidence(2), evidence(3)],
    configuredEndpoints: ["race_detail", "auth_me"],
  });
  assert.match(unrecordedResult.failures.join("\n"), /UNRECORDED/);
});

test("aggregator CLI requires and combines three summary/raw/evidence triples", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "capacity-cohort-"));
  try {
    const args = [path.resolve("k6/aggregate-capacity-cohort.mjs")];
    for (let repeat = 1; repeat <= 3; repeat += 1) {
      const summaryPath = path.join(directory, `summary-${repeat}.json`);
      const rawPath = path.join(directory, `raw-${repeat}.json`);
      const evidencePath = path.join(directory, `evidence-${repeat}.json`);
      const summaryDocument = summary(repeat);
      summaryDocument.endpointAccounting = Object.fromEntries(
        ENDPOINTS.map(({ key }) => [
          key,
          { selected: 7, executed: 7, durationSamples: 7, statusTotal: 7 },
        ]),
      );
      fs.writeFileSync(summaryPath, JSON.stringify(summaryDocument));
      const points = ENDPOINTS.flatMap(({ key: endpoint }) => [
        point("selected_endpoint_count", 7, repeat, { endpoint }),
        point("executed_endpoint_count", 7, repeat, { endpoint }),
        point("response_status_count", 7, repeat, { endpoint, status: "200" }),
        ...Array.from({ length: 7 }, () =>
          point("endpoint_duration_ms", 100, repeat, { endpoint, status: "200" }),
        ),
      ]);
      fs.writeFileSync(rawPath, `${points.map(JSON.stringify).join("\n")}\n`);
      fs.writeFileSync(evidencePath, JSON.stringify(evidence(repeat)));
      args.push("--summary", summaryPath, "--raw", rawPath, "--evidence", evidencePath);
    }
    const result = spawnSync(process.execPath, args, {
      cwd: path.resolve("."),
      encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const output = JSON.parse(result.stdout);
    assert.equal(output.valid, true);
    assert.equal(output.endpoints.race_detail.samples, 21);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
