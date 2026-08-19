import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  ENDPOINTS,
  RELEASED_CLIENT_COHORTS,
  RUNG_DEFINITIONS,
  buildActivationEvent,
  buildFixtureDocument,
  buildThresholds,
  classifyCapacityRun,
  classifyResponse,
  matchedIterationSeed,
  partitionResolutionSeeds,
  resolutionStateDisposition,
  validateFixture,
} from "../harness-contract.mjs";

test("documented inspect command passes its shell environment to k6", () => {
  const readme = readFileSync(new URL("../README.md", import.meta.url), "utf8");
  assert.match(
    readme,
    /k6 inspect --include-system-env-vars k6\/prod-mix-load-test\.js/,
  );
});

test("matched iteration seeds are stable and distinct", () => {
  assert.equal(matchedIterationSeed(0), matchedIterationSeed(0));
  assert.notEqual(matchedIterationSeed(0), matchedIterationSeed(1));
  assert.throws(() => matchedIterationSeed(-1), /iteration/i);
});

const validFixture = {
  schemaVersion: "capacity-fixture-v1",
  metadata: {
    fixtureRevision: "capacity-fixture-v1:test",
    generatedAt: "2026-08-18T00:00:00.000Z",
    corpusWindowDays: 14,
    dauDenominatorWindowHours: 24,
    source: "staging-prod-clone",
    counts: {
      users: 2,
      activeRaceReferences: 2,
      pendingRaceReferences: 1,
      resolutionSeedUsers: 1,
    },
    raceStrata: {
      active: { solo: 1, team: 1, small: 1, medium: 0, large: 1 },
      pending: { solo: 1, team: 0, small: 0, medium: 1, large: 0 },
    },
  },
  users: [
    {
      userId: "user-active",
      token: "test-token-active",
      activeRaces: [
        {
          id: "race-active-solo",
          isTeamRace: false,
          rosterSize: 12,
          rosterSizeStratum: "small",
        },
        {
          id: "race-active-team",
          isTeamRace: true,
          rosterSize: 120,
          rosterSizeStratum: "large",
        },
      ],
      pendingRaces: [],
    },
    {
      userId: "user-pending",
      token: "test-token-pending",
      activeRaces: [],
      pendingRaces: [
        {
          id: "race-pending-solo",
          isTeamRace: false,
          rosterSize: 32,
          rosterSizeStratum: "medium",
        },
      ],
    },
  ],
  resolutionSeeds: [
    {
      userId: "resolution-seed",
      token: "resolution-token",
      raceIds: ["resolution-race"],
    },
  ],
};

test("offered-rate rungs replace stale DAU identities and carry every gate", () => {
  assert.deepEqual(
    Object.keys(RUNG_DEFINITIONS),
    [
      "rate_5rps",
      "rate_15rps",
      "rate_31rps",
      "diagnostic_160rps",
      "diagnostic_260rps",
    ],
  );
  assert.equal(RUNG_DEFINITIONS.rate_15rps.duration, "90s");
  assert.equal(RUNG_DEFINITIONS.rate_31rps.duration, "30s");
  for (const name of [
    "diagnostic_160rps",
    "diagnostic_260rps",
  ]) {
    assert.equal(RUNG_DEFINITIONS[name].diagnosticOnly, true);
    assert.equal(RUNG_DEFINITIONS[name].duration, "30s");
    assert.ok(
      RUNG_DEFINITIONS[name].preAllocatedVUs >=
        Math.ceil(RUNG_DEFINITIONS[name].rate * 2.4),
    );
    assert.ok(
      RUNG_DEFINITIONS[name].maxVUs >=
        RUNG_DEFINITIONS[name].preAllocatedVUs,
    );
    assert.equal(
      RUNG_DEFINITIONS[name].maxVUs,
      name === "diagnostic_260rps" ? 800 : 400,
    );
  }

  const thresholds = buildThresholds(["rate_15rps", "rate_31rps"]);
  for (const rung of ["rate_15rps", "rate_31rps"]) {
    assert.ok(thresholds[`dropped_iterations{rung:${rung}}`]);
    assert.ok(thresholds[`capacity_failure_rate{rung:${rung}}`]);
    assert.ok(thresholds[`http_req_duration{rung:${rung}}`]);
    assert.ok(thresholds[`persistence_critical_duration_ms{rung:${rung}}`]);
    assert.ok(thresholds[`context_fallback_count{rung:${rung}}`]);
    assert.ok(thresholds[`resolution_lag_sample_count{rung:${rung}}`]);
    assert.ok(thresholds[`final_resolution_outstanding{rung:${rung}}`]);
    assert.deepEqual(
      thresholds[`resolution_state_superseded_count{rung:${rung}}`],
      ["count==0"],
    );
    assert.equal(
      thresholds[`endpoint_duration_ms{endpoint:race_detail,rung:${rung}}`],
      undefined,
    );
    assert.equal(
      thresholds[`selected_endpoint_count{endpoint:race_detail,rung:${rung}}`],
      undefined,
    );
  }
  assert.deepEqual(
    thresholds["capacity_failure_rate{rung:rate_15rps}"],
    ["rate==0"],
  );
  assert.deepEqual(
    thresholds["capacity_failure_rate{rung:rate_31rps}"],
    ["rate<0.01"],
  );
  assert.throws(
    () =>
      classifyCapacityRun(
        "60s",
        false,
        "https://staging.steptracker-api.org",
        RUNG_DEFINITIONS.diagnostic_160rps,
      ),
    /ALLOW_DIAGNOSTIC_OVERRIDE=1/,
  );
  assert.deepEqual(
    classifyCapacityRun(
      "60s",
      true,
      "https://staging.steptracker-api.org",
      RUNG_DEFINITIONS.diagnostic_160rps,
    ),
    {
      capacityCandidate: false,
      diagnosticReason: "diagnostic_breakpoint_rung",
    },
  );
});

test("capacity overrides are explicitly diagnostic and non-claimable", () => {
  assert.deepEqual(classifyCapacityRun(undefined, false), {
    capacityCandidate: true,
    diagnosticReason: null,
  });
  assert.deepEqual(
    classifyCapacityRun(undefined, false, "http://localhost:3000"),
    {
      capacityCandidate: false,
      diagnosticReason: "non_staging_base_url",
    },
  );
  assert.deepEqual(classifyCapacityRun("12s", true), {
    capacityCandidate: false,
    diagnosticReason: "duration_override",
  });
  assert.throws(
    () => classifyCapacityRun("12s", false),
    /ALLOW_DIAGNOSTIC_OVERRIDE=1/,
  );
  assert.deepEqual(
    classifyCapacityRun(
      undefined,
      false,
      "https://staging.steptracker-api.org",
      RUNG_DEFINITIONS.diagnostic_160rps,
    ),
    {
      capacityCandidate: false,
      diagnosticReason: "diagnostic_breakpoint_rung",
    },
  );
});

test("status classification permits only 2xx and the organic challenge 404", () => {
  assert.deepEqual(classifyResponse("auth_me", 200), {
    allowed: true,
    capacityFailure: false,
    hardFailure: false,
    rateLimited: false,
  });
  assert.equal(
    classifyResponse("challenges_current", 404).capacityFailure,
    false,
  );
  for (const status of [0, 301, 401, 403, 408, 409, 429, 500, 503]) {
    assert.equal(
      classifyResponse("auth_me", status).capacityFailure,
      true,
      `status ${status}`,
    );
  }
  assert.equal(classifyResponse("auth_me", 429).rateLimited, true);
  assert.equal(classifyResponse("auth_me", 503).hardFailure, true);
});

test("SUPERSEDED resolution state requires immediate run abort", () => {
  assert.equal(resolutionStateDisposition("SUPERSEDED"), "abort");
  assert.equal(resolutionStateDisposition("succeeded"), "continue");
  assert.equal(resolutionStateDisposition("running"), "continue");
});

test("race endpoints use exact paging and endpoint-appropriate contexts", () => {
  const byKey = Object.fromEntries(ENDPOINTS.map((entry) => [entry.key, entry]));
  assert.equal(
    byKey.race_detail.path("race-1"),
    "/races/race-1?view=participants-v1&offset=0&limit=15",
  );
  assert.equal(byKey.race_progress.context, "active_race");
  assert.equal(byKey.race_resolution.context, "seeded_resolution_job");
  assert.equal(byKey.race_bootstrap.context, "active_or_pending_race");
});

test("released client cohorts are explicit and match the 2.3.7 baseline", () => {
  const ios = RELEASED_CLIENT_COHORTS.ios_bara_2_3_7_ads_payout;
  assert.equal(ios.appVersion, "2.3.7");
  assert.match(ios.userAgent, /^Bara\/2\.3\.7 /);
  assert.equal(
    ios.features,
    "characters,ads,jammer,spinpowerups,team_races,tournaments,race_leave," +
      "powerups2,powerups3,powerups4,powerups5,stealth_runner_duration," +
      "hitchhike_effective_steps,remote_assets,remote_asset_preferred," +
      "next_race_cta,discoverable_identity,home_suggested_races," +
      "seeded_race_buckets,home_invite_modal,race_participants_paging," +
      "race_preview,race_payout_double",
  );
});

test("activation event matches the real released ingestion contract", () => {
  const event = buildActivationEvent({
    id: "k6-event-123",
    now: new Date("2026-08-18T12:00:00.000Z"),
    appVersion: "2.3.7",
    platform: "ios",
  });
  assert.deepEqual(event, {
    id: "k6-event-123",
    name: "daily_opened",
    appVersion: "2.3.7",
    platform: "ios",
    timestamp: "2026-08-18T12:00:00.000Z",
  });
  assert.deepEqual(Object.keys(event).sort(), [
    "appVersion",
    "id",
    "name",
    "platform",
    "timestamp",
  ]);
});

test("fixture validation requires separate status pools, strata, and dedicated seeds", () => {
  assert.equal(validateFixture(validFixture).ok, true);

  const arrayFixture = validFixture.users;
  assert.match(validateFixture(arrayFixture).errors.join("\n"), /schemaVersion/);

  const noPending = structuredClone(validFixture);
  noPending.users[1].pendingRaces = [];
  assert.match(validateFixture(noPending).errors.join("\n"), /PENDING/);

  const noSeeds = structuredClone(validFixture);
  noSeeds.resolutionSeeds = [];
  assert.match(validateFixture(noSeeds).errors.join("\n"), /resolution seed/);

  const multiRaceSeed = structuredClone(validFixture);
  multiRaceSeed.resolutionSeeds[0].raceIds.push("resolution-race-2");
  assert.match(
    validateFixture(multiRaceSeed).errors.join("\n"),
    /exactly one distinct ACTIVE race/,
  );

  const wrongWindow = structuredClone(validFixture);
  wrongWindow.metadata.dauDenominatorWindowHours = 336;
  assert.match(validateFixture(wrongWindow).errors.join("\n"), /24-hour/);
});

test("fixture construction preserves status and computes non-secret strata metadata", () => {
  const fixture = buildFixtureDocument({
    generatedAt: "2026-08-18T00:00:00.000Z",
    users: [
      { id: "u1", apple_id: "apple-1", token: "token-one" },
      { id: "u2", apple_id: "apple-2", token: "token-two" },
    ],
    raceRows: [
      {
        user_id: "u1",
        race_id: "a1",
        race_status: "active",
        is_team_race: false,
        roster_size: 15,
        job_id: "j1",
        generation: 3,
      },
      {
        user_id: "u1",
        race_id: "p1",
        race_status: "pending",
        is_team_race: true,
        roster_size: 16,
        job_id: null,
        generation: null,
      },
      {
        user_id: "u2",
        race_id: "a2",
        race_status: "active",
        is_team_race: false,
        roster_size: 100,
        job_id: null,
        generation: null,
      },
    ],
    resolutionSeeds: [
      {
        userId: "resolution-seed",
        token: "resolution-token",
        raceIds: ["resolution-race"],
      },
    ],
  });

  assert.deepEqual(
    fixture.users[0].activeRaces.map((race) => race.id),
    ["a1"],
  );
  assert.deepEqual(
    fixture.users[0].pendingRaces.map((race) => race.id),
    ["p1"],
  );
  assert.deepEqual(
    fixture.users.map((user) => [
      user.activeRaces.map((race) => race.rosterSizeStratum),
      user.pendingRaces.map((race) => race.rosterSizeStratum),
    ]),
    [[ ["small"], ["medium"] ], [ ["large"], [] ]],
  );
  assert.equal(fixture.metadata.counts.resolutionSeedUsers, 1);
  assert.equal(fixture.metadata.raceStrata.active.solo, 2);
  assert.equal(fixture.metadata.raceStrata.pending.team, 1);
  assert.match(fixture.metadata.fixtureRevision, /^capacity-fixture-v1:/);
  assert.ok(!fixture.metadata.fixtureRevision.includes("token"));
});

test("resolution seeds reserve users and every shared live race from workload", () => {
  const users = [
    { id: "seed", token: "seed-token" },
    { id: "shared", token: "shared-token" },
    { id: "workload", token: "workload-token" },
  ];
  const raceRows = [
    { user_id: "seed", race_id: "dedicated", race_status: "active" },
    { user_id: "shared", race_id: "dedicated", race_status: "active" },
    { user_id: "shared", race_id: "other", race_status: "pending" },
    { user_id: "workload", race_id: "workload-active", race_status: "active" },
    { user_id: "workload", race_id: "workload-pending", race_status: "pending" },
  ];
  const partition = partitionResolutionSeeds({ users, raceRows, seedCount: 1 });
  assert.deepEqual(partition.resolutionSeeds.map((seed) => seed.userId), ["seed"]);
  assert.deepEqual(partition.resolutionSeeds[0].raceIds, ["dedicated"]);
  assert.deepEqual(partition.workloadUsers.map((user) => user.id), ["workload"]);
  assert.ok(
    partition.workloadRaceRows.every((row) => row.race_id !== "dedicated"),
  );
});

test("resolution partition skips multi-ACTIVE users and fails when eligible seeds are unavailable", () => {
  const users = [
    { id: "multi", token: "multi-token" },
    { id: "eligible", token: "eligible-token" },
    { id: "workload", token: "workload-token" },
  ];
  const raceRows = [
    { user_id: "multi", race_id: "active-1", race_status: "active" },
    { user_id: "multi", race_id: "active-2", race_status: "active" },
    { user_id: "eligible", race_id: "dedicated", race_status: "active" },
    { user_id: "workload", race_id: "workload-active", race_status: "active" },
  ];
  const partition = partitionResolutionSeeds({ users, raceRows, seedCount: 1 });
  assert.deepEqual(partition.resolutionSeeds, [
    {
      userId: "eligible",
      token: "eligible-token",
      raceIds: ["dedicated"],
    },
  ]);
  assert.throws(
    () => partitionResolutionSeeds({ users, raceRows, seedCount: 3 }),
    /requested 3.*found 2/i,
  );
});

test("resolution partition prefers a later small-race user over an earlier large-race user", () => {
  const users = [
    { id: "recent-large", token: "large-token" },
    { id: "later-small", token: "small-token" },
    { id: "workload", token: "workload-token" },
  ];
  const raceRows = [
    {
      user_id: "recent-large",
      race_id: "race-large",
      race_status: "active",
      roster_size: 642,
    },
    {
      user_id: "later-small",
      race_id: "race-small",
      race_status: "active",
      roster_size: 3,
    },
    {
      user_id: "workload",
      race_id: "workload-active",
      race_status: "active",
      roster_size: 14,
    },
  ];

  const partition = partitionResolutionSeeds({ users, raceRows, seedCount: 1 });

  assert.deepEqual(partition.resolutionSeeds, [
    {
      userId: "later-small",
      token: "small-token",
      raceIds: ["race-small"],
    },
  ]);
  assert.deepEqual(
    partition.workloadUsers.map((user) => user.id),
    ["recent-large", "workload"],
  );
});

test("resolution partition selects distinct races when users share the smallest race", () => {
  const users = [
    { id: "small-a", token: "small-a-token" },
    { id: "small-b", token: "small-b-token" },
    { id: "next", token: "next-token" },
    { id: "large", token: "large-token" },
  ];
  const raceRows = [
    {
      user_id: "small-a",
      race_id: "shared-small",
      race_status: "active",
      roster_size: 2,
    },
    {
      user_id: "small-b",
      race_id: "shared-small",
      race_status: "active",
      roster_size: 2,
    },
    {
      user_id: "next",
      race_id: "next-distinct",
      race_status: "active",
      roster_size: 4,
    },
    {
      user_id: "large",
      race_id: "large-distinct",
      race_status: "active",
      roster_size: 100,
    },
  ];

  const partition = partitionResolutionSeeds({ users, raceRows, seedCount: 2 });

  assert.deepEqual(
    partition.resolutionSeeds.map((seed) => [seed.userId, seed.raceIds[0]]),
    [
      ["small-a", "shared-small"],
      ["next", "next-distinct"],
    ],
  );
  assert.throws(
    () => partitionResolutionSeeds({
      users: users.slice(0, 2),
      raceRows: raceRows.slice(0, 2),
      seedCount: 2,
    }),
    /requested 2.*1 distinct eligible ACTIVE races/i,
  );
});
