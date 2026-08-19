export const HARNESS_SCHEMA_VERSION = "capacity-harness-summary-v1";
export const FIXTURE_SCHEMA_VERSION = "capacity-fixture-v1";

const BASE_FEATURES =
  "characters,jammer,spinpowerups,team_races,tournaments,race_leave," +
  "powerups2,powerups3,powerups4,powerups5,stealth_runner_duration," +
  "hitchhike_effective_steps,remote_assets,remote_asset_preferred," +
  "next_race_cta,discoverable_identity,home_suggested_races," +
  "seeded_race_buckets,home_invite_modal,race_participants_paging," +
  "race_preview";

// These are deliberately frozen cohorts, not a copy of whatever happens to be
// on the current development branch. They match the released 2.3.7 header at
// frontend baseline 17ca1a8. A new released cohort is an explicit code change.
export const RELEASED_CLIENT_COHORTS = Object.freeze({
  ios_bara_2_3_7_ads_payout: Object.freeze({
    appVersion: "2.3.7",
    features: `characters,ads,${BASE_FEATURES.slice("characters,".length)},race_payout_double`,
    userAgent: "Bara/2.3.7 CFNetwork/3860.700.1 Darwin/25.6.0",
    platform: "ios",
    frontendRevision: "17ca1a8",
  }),
});

// Re-seed every arrival from its scenario-global iteration. Matched OFF/ON
// runs then select the same user, endpoint and payload randomness even when k6
// assigns iterations to different VUs.
export function matchedIterationSeed(iterationInTest) {
  if (!Number.isInteger(iterationInTest) || iterationInTest < 0) {
    throw new Error("iterationInTest must be a non-negative integer");
  }
  return (0x51f15e + iterationInTest * 2654435761) >>> 0;
}

export const RUNG_DEFINITIONS = Object.freeze({
  rate_5rps: Object.freeze({ rate: 5, duration: "60s", capacityFailure: "rate==0" }),
  rate_15rps: Object.freeze({ rate: 15, duration: "90s", capacityFailure: "rate==0" }),
  rate_31rps: Object.freeze({ rate: 31, duration: "30s", capacityFailure: "rate<0.01" }),
  diagnostic_160rps: Object.freeze({
    rate: 160,
    duration: "30s",
    capacityFailure: "rate<0.01",
    diagnosticOnly: true,
    preAllocatedVUs: 384,
    maxVUs: 400,
  }),
  diagnostic_260rps: Object.freeze({
    rate: 260,
    duration: "30s",
    capacityFailure: "rate<0.01",
    diagnosticOnly: true,
    preAllocatedVUs: 624,
    maxVUs: 800,
  }),
});

export function rungDefinitionForName(name) {
  if (RUNG_DEFINITIONS[name]) return RUNG_DEFINITIONS[name];
  const match = /^daily_(150|250|350|450|550|650|750|850|950)rps$/.exec(name);
  if (!match) return null;
  const rate = Number(match[1]);
  return Object.freeze({
    rate,
    duration: "35s",
    capacityFailure: "rate<0.01",
    diagnosticOnly: true,
    preAllocatedVUs: Math.ceil(rate * 2.4),
    maxVUs: Math.ceil(rate * 3.2),
  });
}

export const ENDPOINTS = Object.freeze([
  { key: "race_messages", w: 39207, method: "GET", context: "active_or_pending_race", path: (id) => `/races/${id}/messages?limit=50` },
  { key: "challenges_current", w: 13400, method: "GET", context: "none", path: () => "/challenges/current" },
  { key: "assets_manifest", w: 12993, method: "GET", context: "none", path: () => "/assets/manifest" },
  { key: "race_resolution", w: 10812, method: "GET", context: "seeded_resolution_job", path: (_id, job) => `/steps/race-resolution/${job.id}?generation=${job.generation}` },
  { key: "steps_post", w: 10462, method: "POST", context: "none", critical: true, path: () => "/steps" },
  { key: "races_list", w: 9937, method: "GET", context: "none", path: () => "/races" },
  { key: "steps_samples", w: 8648, method: "POST", context: "none", critical: true, path: () => "/steps/samples" },
  { key: "race_progress", w: 8286, method: "GET", context: "active_race", path: (id) => `/races/${id}/progress?view=participants-v1&offset=0&limit=15` },
  { key: "message_streams", w: 7718, method: "GET", context: "active_or_pending_race", path: (id) => `/races/${id}/message-streams` },
  { key: "auth_me", w: 7337, method: "GET", context: "none", path: () => "/auth/me" },
  { key: "powerups_inventory", w: 7297, method: "GET", context: "none", path: () => "/powerups/inventory" },
  { key: "steps_sync_v2", w: 7294, method: "POST", context: "none", critical: true, path: () => "/steps/sync-v2" },
  { key: "home_race_card", w: 6591, method: "GET", context: "none", path: () => "/home/race-card" },
  { key: "version_policy", w: 6143, method: "GET", context: "none", path: () => "/app-version/policy" },
  { key: "powerups_catalog", w: 5814, method: "GET", context: "none", path: () => "/powerups/catalog" },
  { key: "suggested_races", w: 5778, method: "GET", context: "none", path: () => "/home/suggested-races" },
  { key: "friends_steps", w: 4929, method: "GET", context: "none", path: () => "/friends/steps" },
  { key: "invite_preflight", w: 4720, method: "GET", context: "none", path: () => "/races/invite-preflight" },
  { key: "activation_events", w: 4257, method: "POST", context: "none", path: () => "/analytics/activation-events" },
  { key: "chat_read", w: 3467, method: "POST", context: "active_or_pending_race", path: (id) => `/races/${id}/chat/read` },
  { key: "discovery_summary", w: 3444, method: "GET", context: "none", path: () => "/races/discovery-summary" },
  { key: "auth_session", w: 3188, method: "GET", context: "none", path: () => "/auth/session" },
  { key: "friends_list", w: 2139, method: "GET", context: "none", path: () => "/friends" },
  { key: "shop_catalog", w: 2135, method: "GET", context: "none", path: () => "/shop/catalog" },
  { key: "race_detail", w: 1944, method: "GET", context: "active_or_pending_race", path: (id) => `/races/${id}?view=participants-v1&offset=0&limit=15` },
  { key: "race_bootstrap", w: 1517, method: "GET", context: "active_or_pending_race", path: (id) => `/races/${id}/bootstrap?view=participants-v1&offset=0&limit=15` },
]);

export function buildThresholds(rungNames) {
  const thresholds = {};
  for (const rungName of rungNames) {
    const rung = rungDefinitionForName(rungName);
    if (!rung) throw new Error(`unknown offered-rate rung: ${rungName}`);
    const tag = `{rung:${rungName}}`;
    thresholds[`dropped_iterations${tag}`] = ["count==0"];
    thresholds[`capacity_failure_rate${tag}`] = [rung.capacityFailure];
    thresholds[`hard_failure_rate${tag}`] = [rung.capacityFailure];
    thresholds[`http_req_duration${tag}`] = ["p(95)<2000", "p(99)<5000"];
    thresholds[`persistence_critical_duration_ms${tag}`] = [
      "p(95)<2000",
      "p(99)<5000",
      "max<15000",
    ];
    thresholds[`context_fallback_count${tag}`] = ["count==0"];
    thresholds[`resolution_lag_ms${tag}`] = ["max<5000"];
    thresholds[`resolution_lag_sample_count${tag}`] = ["count>0"];
    thresholds[`final_resolution_outstanding${tag}`] = ["value==0"];
    thresholds[`resolution_state_failed_count${tag}`] = ["count==0"];
    thresholds[`resolution_state_superseded_count${tag}`] = ["count==0"];
  }
  return thresholds;
}

export function classifyCapacityRun(
  durationOverride,
  allowDiagnosticOverride,
  baseUrl = "https://staging.steptracker-api.org",
  rungDefinition = null,
) {
  if (durationOverride && !allowDiagnosticOverride) {
    throw new Error(
      "DURATION_OVERRIDE in capacity mode requires ALLOW_DIAGNOSTIC_OVERRIDE=1",
    );
  }
  if (rungDefinition?.diagnosticOnly === true) {
    return {
      capacityCandidate: false,
      diagnosticReason: "diagnostic_breakpoint_rung",
    };
  }
  if (baseUrl !== "https://staging.steptracker-api.org") {
    return {
      capacityCandidate: false,
      diagnosticReason: "non_staging_base_url",
    };
  }
  if (!durationOverride) return { capacityCandidate: true, diagnosticReason: null };
  return { capacityCandidate: false, diagnosticReason: "duration_override" };
}

export function buildActivationEvent({ id, now, appVersion, platform }) {
  return {
    id,
    name: "daily_opened",
    appVersion,
    platform,
    timestamp: now.toISOString(),
  };
}

export function classifyResponse(endpointKey, status) {
  const allowed =
    (status >= 200 && status < 300) ||
    (endpointKey === "challenges_current" && status === 404);
  return {
    allowed,
    capacityFailure: !allowed,
    hardFailure: status === 0 || status >= 500,
    rateLimited: status === 429,
  };
}

export function resolutionStateDisposition(state) {
  return String(state).toLowerCase() === "superseded" ? "abort" : "continue";
}

export function rosterSizeStratum(rosterSize) {
  if (rosterSize <= 15) return "small";
  if (rosterSize < 100) return "medium";
  return "large";
}

function revisionHash(value) {
  // FNV-1a is sufficient here: this is a reproducibility label over a redacted
  // fixture shape, not a security digest. Tokens are never included.
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

export function partitionResolutionSeeds({ users, raceRows, seedCount }) {
  const usersById = new Map(users.map((user) => [user.id, user]));
  if (!Number.isInteger(seedCount) || seedCount < 1) {
    throw new Error("resolution seed count must be a positive integer");
  }
  const activeRacesByUser = new Map();
  for (const row of raceRows) {
    if (
      String(row.race_status).toLowerCase() === "active" &&
      usersById.has(row.user_id)
    ) {
      if (!activeRacesByUser.has(row.user_id)) {
        activeRacesByUser.set(row.user_id, new Map());
      }
      const races = activeRacesByUser.get(row.user_id);
      const rosterSize = Number(row.roster_size);
      const normalizedRosterSize = Number.isFinite(rosterSize) && rosterSize > 0
        ? rosterSize
        : Number.POSITIVE_INFINITY;
      races.set(
        row.race_id,
        Math.min(races.get(row.race_id) ?? Number.POSITIVE_INFINITY, normalizedRosterSize),
      );
    }
  }
  const eligibleSeeds = users
    .map((user) => {
      const races = activeRacesByUser.get(user.id);
      if (races?.size !== 1) return null;
      const [[raceId, rosterSize]] = races.entries();
      return { userId: user.id, raceId, rosterSize };
    })
    .filter(Boolean)
    .sort(
      (left, right) =>
        left.rosterSize - right.rosterSize ||
        String(left.userId).localeCompare(String(right.userId)) ||
        String(left.raceId).localeCompare(String(right.raceId)),
    );
  const selectedSeeds = [];
  const selectedRaceIds = new Set();
  for (const candidate of eligibleSeeds) {
    if (selectedRaceIds.has(candidate.raceId)) continue;
    selectedSeeds.push(candidate);
    selectedRaceIds.add(candidate.raceId);
    if (selectedSeeds.length === seedCount) break;
  }
  if (selectedSeeds.length < seedCount) {
    throw new Error(
      `requested ${seedCount} resolution seeds but found ${selectedRaceIds.size} distinct eligible ACTIVE races`,
    );
  }
  const selectedSeedIds = new Set(
    selectedSeeds.map((seed) => seed.userId),
  );
  const dedicatedRaceIds = new Set(
    raceRows
      .filter(
        (row) =>
          selectedSeedIds.has(row.user_id) &&
          String(row.race_status).toLowerCase() === "active",
      )
      .map((row) => row.race_id),
  );
  const excludedUserIds = new Set(selectedSeedIds);
  for (const row of raceRows) {
    if (dedicatedRaceIds.has(row.race_id)) excludedUserIds.add(row.user_id);
  }
  const resolutionSeeds = [...selectedSeedIds].map((userId) => ({
    userId,
    token: usersById.get(userId).token,
    raceIds: [...activeRacesByUser.get(userId).keys()],
  }));
  return {
    resolutionSeeds,
    workloadUsers: users.filter((user) => !excludedUserIds.has(user.id)),
    workloadRaceRows: raceRows.filter(
      (row) =>
        !excludedUserIds.has(row.user_id) &&
        !dedicatedRaceIds.has(row.race_id),
    ),
  };
}

export function buildFixtureDocument({
  generatedAt,
  users,
  raceRows,
  resolutionSeeds = [],
}) {
  const rowsByUser = new Map();
  for (const row of raceRows) {
    if (!rowsByUser.has(row.user_id)) rowsByUser.set(row.user_id, []);
    rowsByUser.get(row.user_id).push(row);
  }
  const strata = {
    active: { solo: 0, team: 0, small: 0, medium: 0, large: 0 },
    pending: { solo: 0, team: 0, small: 0, medium: 0, large: 0 },
  };
  let activeRaceReferences = 0;
  let pendingRaceReferences = 0;
  const fixtureUsers = users.map((user) => {
    const activeRaces = [];
    const pendingRaces = [];
    const rows = (rowsByUser.get(user.id) || []).slice().sort((left, right) =>
      String(left.race_id).localeCompare(String(right.race_id)),
    );
    for (const row of rows) {
      const rosterSize = Number(row.roster_size);
      const stratum = rosterSizeStratum(rosterSize);
      const status = String(row.race_status).toLowerCase();
      const race = {
        id: row.race_id,
        isTeamRace: row.is_team_race === true,
        rosterSize,
        rosterSizeStratum: stratum,
      };
      if (status === "active") {
        activeRaces.push(race);
        activeRaceReferences += 1;
        strata.active[race.isTeamRace ? "team" : "solo"] += 1;
        strata.active[stratum] += 1;
      } else if (status === "pending") {
        pendingRaces.push(race);
        pendingRaceReferences += 1;
        strata.pending[race.isTeamRace ? "team" : "solo"] += 1;
        strata.pending[stratum] += 1;
      }
    }
    return {
      userId: user.id,
      token: user.token,
      activeRaces,
      pendingRaces,
    };
  });
  const redactedShape = {
    users: fixtureUsers.map((user) => ({
      userId: user.userId,
      activeRaces: user.activeRaces,
      pendingRaces: user.pendingRaces,
    })),
    resolutionSeeds: resolutionSeeds.map((seed) => ({
      userId: seed.userId,
      raceIds: seed.raceIds,
    })),
  };
  return {
    schemaVersion: FIXTURE_SCHEMA_VERSION,
    metadata: {
      fixtureRevision: `${FIXTURE_SCHEMA_VERSION}:${revisionHash(JSON.stringify(redactedShape))}`,
      generatedAt,
      corpusWindowDays: 14,
      dauDenominatorWindowHours: 24,
      source: "staging-prod-clone",
      counts: {
        users: fixtureUsers.length,
        activeRaceReferences,
        pendingRaceReferences,
        resolutionSeedUsers: resolutionSeeds.length,
      },
      raceStrata: strata,
    },
    users: fixtureUsers,
    resolutionSeeds,
  };
}

function validRace(race) {
  return (
    race &&
    typeof race.id === "string" &&
    race.id.length > 0 &&
    typeof race.isTeamRace === "boolean" &&
    Number.isInteger(race.rosterSize) &&
    race.rosterSize > 0 &&
    ["small", "medium", "large"].includes(race.rosterSizeStratum)
  );
}

export function validateFixture(fixture) {
  const errors = [];
  if (!fixture || fixture.schemaVersion !== FIXTURE_SCHEMA_VERSION) {
    errors.push(`fixture schemaVersion must be ${FIXTURE_SCHEMA_VERSION}`);
    return { ok: false, errors };
  }
  const metadata = fixture.metadata;
  if (!metadata || typeof metadata !== "object") {
    errors.push("fixture metadata is required");
  } else {
    if (metadata.corpusWindowDays !== 14) {
      errors.push("fixture corpus must be labeled as a 14-day pool");
    }
    if (metadata.dauDenominatorWindowHours !== 24) {
      errors.push("DAU denominator must be labeled as a separate 24-hour window");
    }
    if (typeof metadata.fixtureRevision !== "string" || !metadata.fixtureRevision) {
      errors.push("fixtureRevision is required");
    }
    if (!metadata.raceStrata || typeof metadata.raceStrata !== "object") {
      errors.push("raceStrata metadata is required");
    }
  }
  if (!Array.isArray(fixture.users) || fixture.users.length === 0) {
    errors.push("fixture users must be a non-empty array");
    return { ok: false, errors };
  }

  let activeCount = 0;
  let pendingCount = 0;
  let activeSoloCount = 0;
  for (const user of fixture.users) {
    if (!user || typeof user.userId !== "string" || !user.userId) {
      errors.push("every fixture user needs a userId");
      continue;
    }
    if (typeof user.token !== "string" || !user.token) {
      errors.push("every fixture user needs a token");
    }
    if (!Array.isArray(user.activeRaces) || !Array.isArray(user.pendingRaces)) {
      errors.push("every fixture user needs separate activeRaces and pendingRaces arrays");
      continue;
    }
    for (const race of user.activeRaces) {
      if (!validRace(race)) {
        errors.push("ACTIVE race fixtures need id, mode, roster size, and stratum");
        continue;
      }
      activeCount += 1;
      if (!race.isTeamRace) activeSoloCount += 1;
    }
    for (const race of user.pendingRaces) {
      if (!validRace(race)) {
        errors.push("PENDING race fixtures need id, mode, roster size, and stratum");
        continue;
      }
      pendingCount += 1;
    }
  }
  if (activeCount === 0) errors.push("fixture must preserve at least one ACTIVE race");
  if (pendingCount === 0) errors.push("fixture must preserve at least one PENDING race");
  if (activeSoloCount === 0) errors.push("fixture needs an ACTIVE solo race for paged progress");
  if (!Array.isArray(fixture.resolutionSeeds) || fixture.resolutionSeeds.length === 0) {
    errors.push("fixture needs at least one dedicated resolution seed user");
  } else {
    const workloadUserIds = new Set(fixture.users.map((user) => user.userId));
    const workloadRaceIds = new Set(
      fixture.users.flatMap((user) => [
        ...user.activeRaces.map((race) => race.id),
        ...user.pendingRaces.map((race) => race.id),
      ]),
    );
    for (const seed of fixture.resolutionSeeds) {
      if (
        !seed ||
        typeof seed.userId !== "string" ||
        typeof seed.token !== "string" ||
        !seed.token ||
        !Array.isArray(seed.raceIds) ||
        new Set(seed.raceIds).size !== 1 ||
        typeof seed.raceIds[0] !== "string" ||
        !seed.raceIds[0]
      ) {
        errors.push(
          "resolution seeds need userId, token, and exactly one distinct ACTIVE race",
        );
        continue;
      }
      if (workloadUserIds.has(seed.userId)) {
        errors.push("resolution seed users must be excluded from workload users");
      }
      if (seed.raceIds.some((raceId) => workloadRaceIds.has(raceId))) {
        errors.push("resolution seed races must be excluded from workload races");
      }
    }
  }
  return { ok: errors.length === 0, errors };
}
