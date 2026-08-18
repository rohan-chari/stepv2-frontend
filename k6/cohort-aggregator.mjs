const REQUIRED_SETTING_KEYS = Object.freeze([
  "backendRevision",
  "flags",
  "config",
  "workerCount",
  "pgBouncerPool",
  "redisState",
  "cronCohort",
]);

const IDENTITY_REQUIRED_METRICS = new Set([
  "selected_endpoint_count",
  "executed_endpoint_count",
  "endpoint_duration_ms",
  "response_status_count",
  "resolution_state_count",
  "context_fallback_count",
  "successful_response_count",
  "expected_challenge_404_count",
  "capacity_failure_count",
  "hard_failure_count",
  "rate_limit_429_count",
  "capacity_failure_rate",
  "hard_failure_rate",
  "persistence_critical_duration_ms",
  "resolution_lag_ms",
  "resolution_lag_sample_count",
  "final_resolution_outstanding",
]);

function identityRequired(metric) {
  return (
    IDENTITY_REQUIRED_METRICS.has(metric) ||
    metric.startsWith("summary_endpoint_") ||
    metric.startsWith("resolution_state_") ||
    metric.startsWith("response_status_code_")
  );
}

function percentile(values, percentileValue) {
  if (values.length === 0) return null;
  const sorted = values.slice().sort((left, right) => left - right);
  const index = Math.max(0, Math.ceil((percentileValue / 100) * sorted.length) - 1);
  return sorted[index];
}

function allThresholdsPassed(summary) {
  return Object.values(summary.thresholds || {}).every((thresholds) =>
    Object.values(thresholds || {}).every((passed) => passed === true),
  );
}

function recorded(value) {
  return (
    (typeof value === "string" || typeof value === "number") &&
    String(value).trim().length > 0 &&
    String(value).trim().toUpperCase() !== "UNRECORDED"
  );
}

function structurallyValidSettings(inputs = {}) {
  const placeholder = /(replace[-_ ]?me|placeholder|change[-_ ]?me|dummy|example|unknown|unrecorded|tbd|todo)/i;
  const labeled = (value) =>
    recorded(value) &&
    !placeholder.test(String(value)) &&
    /^[A-Za-z0-9][A-Za-z0-9._=,;:+/-]{2,255}$/.test(String(value));
  return (
    /^[0-9a-f]{7,40}$/i.test(String(inputs.backendRevision || "")) &&
    labeled(inputs.flags) &&
    String(inputs.flags).includes("-") &&
    labeled(inputs.config) &&
    String(inputs.config).includes("-") &&
    /^[1-9][0-9]*$/.test(String(inputs.workerCount || "")) &&
    String(inputs.pgBouncerPool) === "3" &&
    [
      "warm-process-warm-redis",
      "cold-process-warm-redis",
      "cold-process-cold-staging-test-namespace",
    ].includes(String(inputs.redisState)) &&
    labeled(inputs.cronCohort) &&
    String(inputs.cronCohort).split("-").length >= 3
  );
}

function settingFromInputs(inputs = {}) {
  return Object.fromEntries(REQUIRED_SETTING_KEYS.map((key) => [key, inputs[key]]));
}

function stableSetting(setting = {}) {
  return JSON.stringify(settingFromInputs(setting));
}

function validateEvidence(evidence, summary, index) {
  const failures = [];
  const inputs = summary.inputs || {};
  const prefix = `repeat ${index + 1} telemetry evidence`;
  if (evidence?.schema !== "capacity-telemetry-evidence-v1") {
    failures.push(`${prefix}: schema must be capacity-telemetry-evidence-v1`);
  }
  if (evidence?.runId !== inputs.runId) {
    failures.push(`${prefix}: runId does not match summary`);
  }
  if (String(evidence?.repeatIndex) !== String(inputs.repeatIndex)) {
    failures.push(`${prefix}: repeatIndex does not match summary`);
  }
  if (evidence?.queryCaptureAvailable !== true) {
    failures.push(`${prefix}: queryCaptureAvailable must be true`);
  }
  if (evidence?.measurementGateEligible !== true) {
    failures.push(`${prefix}: measurementGateEligible must be true`);
  }
  if (stableSetting(evidence?.setting) !== stableSetting(inputs)) {
    failures.push(`${prefix}: operator setting does not match summary`);
  }
  if (
    !evidence?.setting ||
    Object.keys(evidence.setting).sort().join(",") !==
      REQUIRED_SETTING_KEYS.slice().sort().join(",")
  ) {
    failures.push(`${prefix}: operator setting keys are not exact`);
  }

  const server = evidence?.telemetry;
  if (server?.schema !== "capacity-telemetry-server-evidence-v1") {
    failures.push(`${prefix}: server evidence schema is invalid`);
  }
  if (server?.runId !== evidence?.runId || server?.runId !== inputs.runId) {
    failures.push(`${prefix}: nested server runId mismatch`);
  }
  if (
    String(server?.repeat) !== String(evidence?.repeatIndex) ||
    String(server?.repeat) !== String(inputs.repeatIndex)
  ) {
    failures.push(`${prefix}: nested server repeat mismatch`);
  }
  if (server?.event !== "capacity_phase_metrics_v1") {
    failures.push(`${prefix}: server event must be capacity_phase_metrics_v1`);
  }
  if (!Number.isInteger(server?.sampleCount) || server.sampleCount < 1) {
    failures.push(`${prefix}: server sampleCount must be a positive integer`);
  }
  if (
    server?.queryCaptureAvailable !== true ||
    server?.queryCaptureAvailable !== evidence?.queryCaptureAvailable
  ) {
    failures.push(`${prefix}: nested queryCaptureAvailable must match and be true`);
  }
  if (
    server?.measurementGateEligible !== true ||
    server?.measurementGateEligible !== evidence?.measurementGateEligible
  ) {
    failures.push(`${prefix}: nested measurementGateEligible must match and be true`);
  }
  if (server?.queryCaptureSetting !== "PRISMA_QUERY_EVENTS_ENABLED=true") {
    failures.push(`${prefix}: unknown queryCaptureSetting`);
  }
  if (
    !Array.isArray(server?.surfaces) ||
    server.surfaces.length === 0 ||
    server.surfaces.some((surface) => !recorded(surface))
  ) {
    failures.push(`${prefix}: server surfaces must be non-empty`);
  }
  return failures;
}

function matchedInputs(summaries) {
  const keys = [
    "offeredRateRps",
    "rung",
    "duration",
    "clientCohort",
    "baseUrl",
    ...REQUIRED_SETTING_KEYS,
  ];
  const first = summaries[0].inputs;
  return summaries.every((summary) => {
    if (summary.inputs?.fixture?.fixtureRevision !== first.fixture?.fixtureRevision) {
      return false;
    }
    return keys.every((key) => summary.inputs?.[key] === first[key]);
  });
}

export function aggregateCapacityCohort({
  summaries,
  rawRuns,
  evidences,
  configuredEndpoints,
}) {
  if (summaries.length !== 3 || rawRuns.length !== 3 || evidences?.length !== 3) {
    throw new Error(
      "capacity cohorts require exactly three summaries, three raw outputs, and three telemetry evidence files",
    );
  }
  const endpoints = Object.fromEntries(
    configuredEndpoints.map((endpoint) => [
      endpoint,
      { selected: 0, executed: 0, durations: [], statusCounts: {} },
    ]),
  );
  const perRunEndpoints = summaries.map(() =>
    Object.fromEntries(
      configuredEndpoints.map((endpoint) => [
        endpoint,
        { selected: 0, executed: 0, durationSamples: 0, statusTotal: 0 },
      ]),
    ),
  );
  const failures = [];
  const resolutionStateCounts = {};
  let contextFallbacks = 0;
  let rawIdentityMismatchCount = 0;
  for (let runIndex = 0; runIndex < rawRuns.length; runIndex += 1) {
    const points = rawRuns[runIndex];
    const expectedInputs = summaries[runIndex].inputs || {};
    for (const point of points) {
      if (!point || point.type !== "Point") continue;
      const value = Number(point.data?.value) || 0;
      const tags = point.data?.tags || {};
      if (
        identityRequired(point.metric) &&
        (tags.rung !== expectedInputs.rung ||
          tags.client_cohort !== expectedInputs.clientCohort ||
          tags.run_id !== expectedInputs.runId ||
          String(tags.repeat_index) !== String(expectedInputs.repeatIndex))
      ) {
        rawIdentityMismatchCount += 1;
        continue;
      }
      const endpoint = endpoints[tags.endpoint];
      if (point.metric === "selected_endpoint_count" && endpoint) {
        endpoint.selected += value;
        perRunEndpoints[runIndex][tags.endpoint].selected += value;
      } else if (point.metric === "executed_endpoint_count" && endpoint) {
        endpoint.executed += value;
        perRunEndpoints[runIndex][tags.endpoint].executed += value;
      } else if (point.metric === "endpoint_duration_ms" && endpoint) {
        endpoint.durations.push(value);
        perRunEndpoints[runIndex][tags.endpoint].durationSamples += 1;
      } else if (point.metric === "response_status_count" && endpoint) {
        const status = String(tags.status ?? "missing");
        endpoint.statusCounts[status] = (endpoint.statusCounts[status] || 0) + value;
        perRunEndpoints[runIndex][tags.endpoint].statusTotal += value;
      } else if (point.metric === "resolution_state_count") {
        const state = String(tags.state ?? "missing");
        resolutionStateCounts[state] = (resolutionStateCounts[state] || 0) + value;
      } else if (point.metric === "context_fallback_count") {
        contextFallbacks += value;
      }
    }
  }

  for (let runIndex = 0; runIndex < summaries.length; runIndex += 1) {
    for (const endpoint of configuredEndpoints) {
      const raw = perRunEndpoints[runIndex][endpoint];
      const expected = summaries[runIndex].endpointAccounting?.[endpoint];
      if (
        !expected ||
        raw.selected !== expected.selected ||
        raw.executed !== expected.executed ||
        raw.durationSamples !== expected.durationSamples ||
        raw.statusTotal !== expected.statusTotal
      ) {
        failures.push(
          `repeat ${runIndex + 1} ${endpoint}: raw accounting does not match summary ` +
            `(raw ${JSON.stringify(raw)}, summary ${JSON.stringify(expected ?? null)})`,
        );
      }
    }
  }

  for (const [endpointKey, endpoint] of Object.entries(endpoints)) {
    endpoint.samples = endpoint.durations.length;
    endpoint.statusTotal = Object.values(endpoint.statusCounts).reduce(
      (sum, count) => sum + count,
      0,
    );
    endpoint.p95Ms = percentile(endpoint.durations, 95);
    endpoint.p95GateApplied = endpoint.samples >= 20;
    endpoint.p95GatePassed = !endpoint.p95GateApplied || endpoint.p95Ms < 2000;
    endpoint.accountingGatePassed =
      endpoint.selected > 0 &&
      endpoint.selected === endpoint.executed &&
      endpoint.selected === endpoint.samples &&
      endpoint.selected === endpoint.statusTotal;
    delete endpoint.durations;
    if (!endpoint.accountingGatePassed) {
      failures.push(
        `${endpointKey}: selected ${endpoint.selected}, executed ${endpoint.executed}, duration samples ${endpoint.samples}, exact-status total ${endpoint.statusTotal}`,
      );
    }
    if (!endpoint.p95GatePassed) {
      failures.push(`${endpointKey}: aggregate p95 ${endpoint.p95Ms}ms`);
    }
  }

  const summaryCandidates = summaries.every(
    (summary) =>
      summary.schemaVersion === "capacity-harness-summary-v1" &&
      summary.inputs?.mode === "capacity" &&
      summary.inputs?.capacityCandidate === true &&
      summary.inputs?.claimable === false,
  );
  const repeatThresholdsPassed = summaries.every(allThresholdsPassed);
  const inputsMatch = matchedInputs(summaries);
  const runIds = summaries.map((summary) => String(summary.inputs?.runId));
  const repeatIndices = summaries.map((summary) => String(summary.inputs?.repeatIndex));
  const runIdsUnique = new Set(runIds).size === 3 && runIds.every(recorded);
  const repeatIndicesValid =
    new Set(repeatIndices).size === 3 &&
    repeatIndices.slice().sort().join(",") === "1,2,3";
  const requiredLabelsRecorded = summaries.every((summary) =>
    REQUIRED_SETTING_KEYS.every((key) => recorded(summary.inputs?.[key])),
  );
  const settingsStructurallyValid = summaries.every((summary) =>
    structurallyValidSettings(summary.inputs),
  );
  const approvedBaseUrl = summaries.every(
    (summary) => summary.inputs?.baseUrl === "https://staging.steptracker-api.org",
  );
  const evidenceFailures = evidences.flatMap((evidence, index) =>
    validateEvidence(evidence, summaries[index], index),
  );

  if (!summaryCandidates) failures.push("all summaries must be non-diagnostic capacity candidates awaiting evidence");
  if (!repeatThresholdsPassed) failures.push("one or more repeat thresholds failed");
  if (!inputsMatch) failures.push("repeat inputs do not match");
  if (!runIdsUnique) failures.push("run IDs must be unique and recorded");
  if (!repeatIndicesValid) failures.push("repeat indices must be unique values 1, 2, and 3");
  if (!requiredLabelsRecorded) failures.push("required operator labels cannot be blank or UNRECORDED");
  if (!settingsStructurallyValid) {
    failures.push("required operator labels are structurally invalid or placeholders");
  }
  if (!approvedBaseUrl) {
    failures.push("all repeats must use the approved staging base URL");
  }
  failures.push(...evidenceFailures);
  if (rawIdentityMismatchCount !== 0) {
    failures.push(`raw identity mismatches: ${rawIdentityMismatchCount}`);
  }
  if (contextFallbacks !== 0) failures.push(`context fallbacks: ${contextFallbacks}`);

  return {
    schemaVersion: "capacity-cohort-summary-v1",
    valid: failures.length === 0,
    claimable: failures.length === 0,
    failures,
    inputs: summaries[0].inputs,
    repeatThresholdsPassed,
    inputsMatch,
    runIdsUnique,
    repeatIndicesValid,
    requiredLabelsRecorded,
    settingsStructurallyValid,
    approvedBaseUrl,
    runIds,
    repeatIndices,
    rawIdentityMismatchCount,
    contextFallbacks,
    endpoints,
    resolutionStateCounts,
  };
}
