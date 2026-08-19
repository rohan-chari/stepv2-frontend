# Request-path and payload optimization requirements

**Status:** Specification complete; architect approved; awaiting owner approval. No
measurement or implementation is authorized until the owner explicitly approves the
final document.

**Evidence date:** 2026-08-18
**Frontend baseline inspected:** `6a1e5d4` plus existing uncommitted owner work
**Backend baseline inspected:** `6719393` (clean worktree at refreshed audit)

This document is the follow-on implementation contract for the organic-traffic
review performed after the capacity investigation. It complements, and does not
replace,
[`capacity-bottleneck-optimization-requirements.md`](capacity-bottleneck-optimization-requirements.md).
Where that specification already owns progress/bootstrap projection, legacy step
reconciliation, or lean message access, this specification references that seam
instead of inventing a competing implementation.

The owner has made a task-specific test-policy decision for this work:

- do not add tests;
- do not edit, delete, skip, weaken, regenerate, or mechanically rewrite any
  existing test file or assertion; and
- implementation business logic must pass the existing frontend and backend test
  suites unchanged.

That decision overrides the normal tests-first step of the feature workflow for
this optimization only, including the tests-first language inherited by referenced
capacity milestones 5.1, 5.4, and 5.5b. Test directories are read-only
implementation inputs.

## 1. Summary and user story

As an app user, opening Home, the Races tab, a race, chat/activity, and powerup
targeting should transfer only the data the running app can use and should avoid
database or CPU work that is discarded before rendering. As the operator, step
uploads and other correctness-sensitive paths should retain their current game
semantics while moving set operations to PostgreSQL and keeping canonical game
rules in one JavaScript implementation.

The reviewed 30-minute production window contained 5,013 app requests and about
6.64 MiB of compressed response bodies. The four largest response contributors
were `GET /races`, race message streams, progress, and bootstrap; together they
were about 80% of response bytes. The longest average durations were Home race
card, race list, legacy sample upload, bootstrap, discovery summary, sync-v2,
powerup use, and progress.

This is an optimization and contract-cleanup project, not a scoring or UI feature.
A faster response is insufficient if an old client breaks, a rank changes, a
message stops refreshing, or same-request box state becomes stale.

## 2. Scope and non-goals

### 2.1 In scope

1. Make `GET /races` obtain persisted list summaries through set-based database
   projection instead of loading every participant row into Node, while retaining
   the exact legacy response.
2. Add an opt-in compact `GET /races` response that removes only fields proven
   redundant for the carrying app build.
3. Complete the already-specified two-phase progress/bootstrap projection and add
   an opt-in ACTIVE-solo bootstrap shape that sends the participant page once.
4. Make Home's live calculation path load lean scoring rows, hydrate presentation
   only for the returned top three, and run independent optional branches
   concurrently.
5. Replace discovery's in-memory public-race count with one set-based database
   count using the same visibility rules as the public browser.
6. Reuse/batch immutable step and sample inputs for legacy uploader reconciliation
   exactly as specified by capacity milestone 5.4.
7. Replace full-roster message authorization with lean caller authorization and
   add an exact-output conditional message-stream response to avoid retransmitting
   unchanged snapshots.
8. Replace full progress rows in powerup targeting context with a typed lean
   projection; remove the Pinecone Toss context request entirely.
9. Replace the successful powerup-use race read with a narrower two-level
   projection—complete minimal accepted roster plus caster/branch-specific fields—
   without moving canonical scoring into SQL or weakening Decoy, Mirror, shield,
   notification, or target validation.
10. Add an opt-in compact leaderboard response without duplicated `top10` or a
    duplicated current-user row.
11. Preserve every old-client route, status, envelope, ordering, and semantic
    fallback behind double-gated opt-ins and independently reversible flags.

### 2.2 Explicit non-goals

- No scoring, ranking, tie-break, team, effect, drop-rate, powerup, payout, box,
  notification, or message-visibility rule changes.
- No initial-Home switch from live totals to persisted totals. The existing client
  may continue to opt into `homePersistedTotals=1` only after sync-v2 reports
  uploader reconciliation `CURRENT`.
- No database implementation of timezone slicing, sample proration, effect
  stacking, Hitchhike, Leech, Trail Mine, Stealth, Detour, Imposter, or other
  canonical game rules.
- No database paging of the scoring roster. The complete accepted roster remains
  available to ranking and cross-participant calculations.
- No removal or mutation of legacy API fields for requests that omit the new
  capability/query opt-in.
- No new required request parameter on an existing endpoint.
- No broad race-list or Home response cache and no Redis-as-authority behavior.
- No schema migration unless a representative `EXPLAIN (ANALYZE, BUFFERS)` proves
  an existing index is insufficient. An index is not approved from query shape
  alone.
- No visible widget addition, removal, movement, style change, pagination behavior
  change, or tutorial/demo layout change.
- No test-file changes of any kind and no new tests, per the owner's explicit
  instruction.
- No production deploy, production database write, seed, cache flush, PM2 change,
  or infrastructure resize. Production work always needs separate in-the-moment
  approval.

## 3. Placement of calculations

### 3.0 Current-path evidence

The implementation seams below were inspected at the stated baseline:

- Flutter advertises feature tokens in
  `lib/services/backend_api_service.dart:241-253`, requests a 15-row bootstrap
  page in `lib/screens/race_detail_screen.dart:922-950`, and requests full
  powerup context for every paged targeting flow—including Pinecone—in
  `lib/screens/race_detail_screen.dart:2063-2071`.
- Flutter polls combined message streams every five seconds through
  `lib/services/race_stream_coordinator.dart:18-21,60-61,109-149`.
- The backend race list loads all participant summary rows at
  `src/modules/races/models/race.js:550-610` and repeatedly filters/sorts them at
  `src/modules/races/queries/getRaces.js:138-168,307-455`.
- Progress slices the serialized participant array only after the full leaderboard
  is built at `src/modules/races/queries/getRaceProgress.js:1204-1372`.
- Powerup use-context explicitly forces full progress at
  `src/modules/races/routes.js:1587-1634`.
- Message-stream access loads the complete race participant/name set at
  `src/modules/social/queries/getRaceMessageStreams.js:21-65`.
- Public discovery loads every candidate and counts in memory at
  `src/modules/races/queries/getPublicRaceCount.js:12-28`.
- Home's live path begins at `src/modules/home/getHomeRaceCard.js:455`, and the
  route awaits independent optional branches sequentially at
  `src/modules/home/routes.js:87-294`.
- Legacy sample reconciliation loops uploader races through
  `src/modules/races/services/reconcileUploaderRaces.js:55-220`.
- Leaderboard compatibility duplicates are constructed at
  `src/modules/leaderboard/getLeaderboard.js:190-232,369-400`.
- The refreshed backend adds a caster-wide Signal Jammer/Power Outage guard at
  `src/modules/powerups/commands/usePowerup.js:1042-1094`; every narrowed powerup
  context must retain the caster effect fields that guard reads.
- Single-target offensive powers may redirect through any eligible accepted racer
  via Decoy at `src/modules/powerups/commands/usePowerup.js:2295-2375`, and the
  post-cast multiplier path uses all other live participant recipients at
  `src/modules/powerups/commands/usePowerup.js:3750-3775`. A caster/target-only
  projection is therefore unsafe.
- Home now obtains inbox counts through the public inbox service at
  `src/modules/home/routes.js:258-272`; the Home assembler must inject that public
  seam rather than reintroduce direct inbox-table policy.

### 3.1 PostgreSQL-owned work

PostgreSQL should perform work that is relational, set-based, and based only on
persisted columns:

- membership and authorization existence checks;
- public-race visibility/count predicates;
- accepted participant counts;
- team member counts and persisted team-step sums;
- maximum `totalsUpdatedAt` for a race;
- viewer participant projection;
- persisted viewer rank and leader selection for the race-list surface;
- bounded participant identity projection by known IDs;
- top-100 step aggregation already used by the leaderboard; and
- set-based step/sample reads, deletes, inserts, and conflict updates.

The persisted race-list ordering must be byte/semantic compatible with
`compareParticipantsForPlacement`:

1. finishers before runners;
2. finishers by stored placement, then `finishedAt`;
3. runners by `totalSteps` descending; and
4. ties by `joinedAt`, then `userId`.

The SQL implementation must encode that ordering explicitly and must not substitute
`RANK()` tie semantics for the current one-row-per-position ordering.

The SQL ordering is pinned to the JavaScript defaults as follows:

```sql
ORDER BY
  CASE WHEN finished_at IS NOT NULL THEN 0 ELSE 1 END ASC,
  CASE WHEN finished_at IS NOT NULL
       THEN COALESCE(placement::bigint, 9007199254740991) END ASC,
  CASE WHEN finished_at IS NOT NULL THEN finished_at END ASC,
  CASE WHEN finished_at IS NULL THEN COALESCE(total_steps, 0) END DESC,
  COALESCE(joined_at, TIMESTAMP '1970-01-01 00:00:00') ASC,
  user_id COLLATE "C" ASC
```

`COLLATE "C"` is required because UUID strings are ASCII and must use deterministic
byte ordering compatible with the existing JavaScript `localeCompare` result; the
database default locale is not assumed. Paired flag-off/on fixtures must include a
finisher with null placement, equal finish instants with distinct placements,
zero-step running ties, equal join instants, and UUID-order ties.

One legacy anomaly cannot be represented by a normal SQL total order: when two
finishers have both the same effective placement (including null) and identical
`finishedAt`, `compareParticipantsForPlacement` returns `-1` instead of falling
through, and the schema does not make placement unique. The SQL summary reports an
`ambiguousFinisherOrder` bit when any race contains such a duplicate finish key. If
true for any race in the request, the flagged implementation deliberately discards
the SQL summary and runs the legacy full-roster/Node-sort path for the whole request.
This rare semantic fallback may perform the second read; database errors may not.
The verifier must include identical placement + identical finish-time rows and prove
that flag-off/on output is exact.

### 3.2 Application-memory-owned work

Node remains the only authority for:

- timezone and effective race-window selection;
- step-sample overlap/proration and closed-bucket rules;
- buff/debuff and global-event scoring;
- Hitchhike and Leech dependency resolution;
- Trail Mine's required fresh canonical state;
- full live ranking after game-rule calculations;
- Stealth, Detour, Imposter, capability downcasts, and viewer redaction;
- response serialization and backward-compatible null/default behavior; and
- sorting bounded result sets such as 100 leaderboard rows or 50+50 messages.

### 3.3 Hybrid paths

Home, progress/bootstrap, step reconciliation, and some powerup types are hybrid:
PostgreSQL returns a lean, set-based input; Node applies the canonical rules; then a
bounded database/cache hydration loads presentation only for rows that will be
serialized.

## 4. Compatibility and opt-in protocol

### 4.1 Client capability

The carrying Flutter build adds `api_payload_compact_v1` to both branches of
`BackendApiService.clientFeaturesHeader`. The capability alone changes nothing.
Every compact response is double-gated by both that token and the endpoint-specific
query/header below.

An older build never sends the token and receives the current response byte for
byte except for non-semantic JSON formatting differences already allowed by the
framework. A new build against an older backend receives the legacy response and
parses it through its existing defensive fallback.

### 4.2 Runtime switches

Add these exact backend application-setting keys to `KNOWN_FLAGS`, default `false`:

| Flag | Governs | Flag-off behavior |
|---|---|---|
| `raceListSqlSummaryV1Enabled` | set-based internal race-list summary | current `findSummariesForUser` path |
| `apiRaceListCompactV1Enabled` | compact race-list wire shape | current response |
| `apiRaceBootstrapCompactV1Enabled` | ACTIVE-solo participant dedup | current bootstrap |
| `homeRaceCardLeanLiveV1Enabled` | lean Home live scoring/hydration | current Home calculation |
| `homeRaceCardParallelOptionalV1Enabled` | concurrent independent Home branches | current sequential route order |
| `publicRaceCountSqlV1Enabled` | set-based discovery count | current lean-list/in-memory count |
| `apiRaceMessageConditionalV1Enabled` | conditional message-stream transfer | current full JSON snapshot |
| `apiRacePowerupTargetContextV1Enabled` | typed lean targeting context | current full-progress context |
| `racePowerupLeanUseContextV1Enabled` | minimal-roster plus branch-specific POST-use read | current resolution-roster context |
| `apiLeaderboardCompactV1Enabled` | compact leaderboard wire shape | current response |

The existing flags from the capacity specification continue to own progress lean
projection, legacy step/sample prefetch, and lean message access. No duplicate flag
or alternate implementation is added here.

Flags are read once at the request/operation boundary through the existing settings
cache. No inner participant/message loop may re-read a flag.

## 5. API contracts

### 5.1 `GET /races` internal SQL summary

This optimization is wire-neutral and may run for every request when its flag is
enabled. Add a race-domain model/query method; routes must not contain raw SQL.

The set-based result must provide enough data to build the existing response:

- race scalars and creator/winner projections;
- the caller's participant row;
- accepted count;
- leader identity and viewer position under the exact persisted comparator;
- per-team accepted count, total steps, and maximum totals-update timestamp;
- IDs of relevant ACTIVE races for viewer inventory/effect queries; and
- completed race IDs for the existing bounded podium hydration.

Effects needed for leader masking and `myActiveEffects` are queried by race/viewer,
not by first materializing every accepted participant ID. Slot inventory remains a
single viewer-bound bulk query. Completed podium remains bounded to placements
1–3. Tournament, next-race, payout-double, review-opportunity, and leave-action
top-level behavior is unchanged.

If the SQL path throws, the request fails as it does today; it must not issue the
legacy query as a hidden retry because that doubles load during database distress.
Rollback is the flag, not per-request dual execution.

Raw SQL, if required, uses tagged/parameterized Prisma queries only. No route uses
`$queryRawUnsafe`, string-interpolated identifiers, or unbounded dynamic SQL. The
SQL-summary and legacy-summary flag combinations must all feed the same serializer;
compact output cannot depend on the SQL optimization being enabled.

The SQL public-race count implements this existing visibility truth table rather
than creating a second policy:

| Condition | Counted? |
|---|---|
| tournament matchup | no |
| team race without `team_races` capability | no |
| ACTIVE team race | no |
| caller has any participant row in the race | no |
| finite `maxParticipants` and accepted count is at/above it | no |
| null `maxParticipants` with no other exclusion | yes |
| PENDING seeded race excluded by the existing base predicate | no |
| seed/window appears in caller's hidden-window set | no |
| creator is a review account | no |
| otherwise public PENDING/ACTIVE individual race | yes |

`excludeSeeded` and hidden-window inputs remain parameterized and retain their
current caller-specific behavior.

### 5.2 `GET /races?view=compact-v1`

The compact response is selected only when:

- `X-Client-Features` contains `api_payload_compact_v1`;
- `view=compact-v1`; and
- `apiRaceListCompactV1Enabled` is true.

Otherwise the existing response is returned.

The compact response adds top-level
`"contract":"race-list-compact-v1"`, keeps the same top-level `active`,
`pending`, and `completed` arrays and all optional top-level objects currently
selected by capabilities. Normatively, each race row is the exact legacy row
produced for the same request, minus only these compatibility duplicates:

- `targetSteps` (marked 1.1.4 compatibility server-side and unused by the current
  races/results surfaces);
- `payouts` when `payoutTiers` is present;
- `leader`;
- `mysteryBoxCount` when `slotItems` is present;
- `teamATotalSteps` and `teamBTotalSteps` when `teams` is present;
- `creator.profilePhotoUrl`; and
- `winner.profilePhotoUrl`.

No other top-level or row field is removed in v1. In particular, payout/prize fields, podium,
viewer result fields, invite state, slot items, active effects, team block,
leave-action state, and review/payout-double metadata remain unchanged.

The carrying frontend derives mystery-box count from `slotItems` and reads canonical
team totals from `teams`; when it receives the legacy shape it continues accepting
the duplicate fields. Missing/malformed compact fields retain today's defensive
defaults.

### 5.3 `GET /races/:id/bootstrap?...&shape=compact-v1`

The existing `view=participants-v1&offset=0&limit=15` paging query is retained.
The new `shape=compact-v1` is optional and double-gated by capability and flag.

For an ACTIVE, non-team race, the following example illustrates the transformation:

```json
{
  "contract": "race-bootstrap-compact-v1",
  "race": {
    "...": "all existing non-participant race-detail fields",
    "participantsPagination": {
      "offset": 0,
      "limit": 15,
      "total": 123,
      "hasMore": true,
      "nextOffset": 15
    }
  },
  "progress": {
    "...": "existing race-progress-participants-v1 response",
    "participants": ["the single authoritative visible participant page"]
  },
  "progressError": null,
  "globalPowerupInventory": []
}
```

Normatively, the response equals the same request's `race-bootstrap-v1` response
with only these changes: `contract` becomes `race-bootstrap-compact-v1` and
`race.participants` is omitted. No other field, null, order, pagination value, or
error marker changes. `race.participants` is omitted only in this compact
ACTIVE-solo shape. The carrying
frontend must use existing top-level detail summaries (`participantUserIds`,
`acceptedCount`, viewer/team fields) for membership and invitations, and progress
for standings rows. If any required summary is absent or malformed, it performs the
existing standalone details/progress fallback rather than guessing.

Team, PENDING, COMPLETED, preview, unpaged, tokenless, flag-off, and malformed
requests retain `race-bootstrap-v1` unchanged. Progress-unavailable behavior and
the pre-existing completed-bootstrap issue remain outside this change.

The internal two-phase scoring/presentation work is exactly capacity milestone 5.1:
full lean scoring roster, Node ranking/illusions, visible-ID selection, then bounded
presentation hydration.

### 5.4 `GET /races/:id/message-streams` conditional transfer

The carrying client adds `view=conditional-v1` and, after a successful full
response, sends the returned ETag in `If-None-Match` on the next poll.

When capability/flag/view are absent, the endpoint remains
`race-message-streams-v1` with status 200 and the current body.

When enabled, a changed response returns status 200, the exact existing stream
payload, plus:

```json
{
  "contract": "race-message-streams-conditional-v1",
  "revision": "opaque-version"
}
```

and headers:

```text
ETag: "opaque-version"
Cache-Control: private, no-cache
Vary: Authorization, X-Client-Features
```

The revision is a SHA-256 hash of a deterministic UTF-8 serialization of the exact
`race-message-streams-v1` body that would otherwise be sent, before the v2
`contract` and `revision` fields are added. Object keys are recursively sorted;
array order, JSON nulls, ISO instants, and strings are preserved. The hash input
therefore includes requested/resolved/error state, message rows, names/photos,
stealth-redacted bodies, cursors, and watermark. Hash input is never logged and the
opaque hash contains no personal data. Computing the exact response before hashing
is intentional in v1: it guarantees presentation/effect/redaction parity while
still eliminating repeated response bytes. Lean access and cached message rows
address server work separately.

If `If-None-Match` equals the newly computed ETag, return 304 with no body and the
same private cache headers, the matching `ETag`, and no JSON serialization.
Authorization runs on every poll before 304. A partial
stream failure changes the canonical response and therefore the ETag; it must never
be hidden behind a stale 304.

The Flutter coordinator retains its current in-memory streams on 304. It clears the
stored ETag when user/session/base URL/race/includeUser/limit changes, when polling
restarts after lifecycle pause, or when a non-304 response is malformed. A 404 from
an older backend retains the existing endpoint fallback. A timeout or 5xx does not
discard the last rendered messages or permanently mark support unavailable.

### 5.5 `GET /races/:id/powerups/use-context`

The carrying client calls:

```text
GET /races/:id/powerups/use-context?view=targets-v1&powerupType=BOUNTY
```

Both parameters are optional for compatibility. The typed response is selected only
under capability, flag, and `view=targets-v1`; otherwise the current
`race-powerup-use-context-v1` full-progress behavior remains.

The new response is:

```json
{
  "contract": "race-powerup-target-context-v1",
  "participants": [
    {
      "userId": "uuid",
      "displayName": "Name",
      "profilePhotoUrl": null,
      "team": "TEAM_A",
      "forfeitedAt": null,
      "stealthed": false,
      "totalSteps": 12345
    }
  ],
  "powerupData": {
    "powerupSlots": 3,
    "inventory": [],
    "queuedBoxCount": 0,
    "myPlacement": 4
  }
}
```

Rules:

- only ACCEPTED participants are returned;
- the caller is included because team and Bounty filtering need the caller row;
- `totalSteps` is present only for `BOUNTY`; other types omit it;
- Bounty picker totals inherit the same documented 15–30 second bounded staleness
  as the rebuildable Redis standings display snapshot. With Redis unavailable,
  malformed, unsupported, or `REDIS_URL` unset, the existing Postgres-derived
  progress fallback is used. The picker is advisory only: the POST's fresh
  Postgres/Node validation is the sole authoritative Bounty decision;
- other targeted types load only accepted identity/team/forfeit fields and active
  Stealth state; they do not run scoring, drop-odds, inventory-upgrade, illusion,
  cosmetic-character, or full progress serialization;
- absent/unknown `powerupType` safely falls back to the legacy full context; and
- the POST-use endpoint remains authoritative and may reject a target selected from
  a now-stale picker.

The frontend does not request context for `PINECONE_TOSS`, whose UI asks only for a
direction. If the typed endpoint is missing, malformed, or returns 404, the current
progress-page candidate fallback remains.

### 5.6 `POST /races/:id/powerups/:powerupId/use` lean two-level read

The refreshed audit rejects caster/target-only loading: Decoy can redirect an
offensive cast to an unaddressed racer, and the post-cast multiplier evaluator needs
the other live recipients. The safe v1 optimization therefore preserves a complete
accepted roster but narrows its columns.

For every non-Trail-Mine type, `Race.findPowerupUseContextV1` returns:

- existing race status/end/powerup/team/timezone scalars;
- every accepted participant with only `id`, `userId`, `status`, `totalSteps`,
  `finishedAt`, `forfeitedAt`, `team`, `joinedAt`, and
  `user.displayName`—the common validation, Decoy pool, AOE, rank-gap, direction,
  and alert-recipient projection; and
- the caster row extended with `bonusSteps`, `maxBonusSteps`, `nextBoxAtSteps`,
  `powerupSlots`, `placement`, and `highMultiplierNotifiedAt`.

Branch-specific indexed reads continue to load active effects, inventory, a target
effect, or a fresh target/caster row where the current command already requires
them. If source audit finds another participant field read before mutation, that
field is added to the common projection; behavior is never approximated. No
offensive type drops the complete minimal roster because Decoy must select and
validate its full redirect pool. No successful type drops the recipient roster
unless the high-multiplier evaluator is separately changed to obtain an equivalent
lean recipient projection.

`TRAIL_MINE` remains the only `FULL_SCORING` exception: it runs the complete fresh
canonical computation and reuses the resulting race exactly as today. An unknown
future powerup type defaults to the current `resolutionRaceSelect`, not the narrow
projection. A source-local closed set derived from `POWERUP_COPY_TYPES` must mark
`TRAIL_MINE`, every currently known non-Trail type, and the conservative unknown
fallback; module validation may fail in development/test when a known type is
missing, while production uses the full legacy projection.

Server-side ownership, jam guard, status, race-end, team/friendly-fire, Stealth,
forfeit, Decoy, Mirror, shield, cooldown, inventory, upgrade, notification,
feed-event, and target validation remain unchanged. The resolution enqueue remains
after successful mutation. This milestone optimizes column and relation hydration,
not participant cardinality or business logic.

### 5.7 `GET /leaderboard?view=compact-v1`

Under capability, flag, and query opt-in, return:

```json
{
  "contract": "leaderboard-compact-v1",
  "top100": ["existing top100 row shape"],
  "currentUser": null
}
```

`top10` is omitted. `currentUser` is `null` when the caller is already in `top100`;
otherwise it retains the existing out-of-top-100 row shape. The current Flutter
screen already renders the caller from `top100` and builds the pinned row only when
`currentUser.inTop100 != true`; update parsing to accept the explicit compact
contract and nullable row. The legacy response remains unchanged, including
`top10`, `inTop10`, and its current-user duplication.

The existing database `groupBy`/SUM and bounded in-memory tie-rank/presentation
hydration remain. Moving rank arithmetic for 100 rows into SQL is not part of this
work.

### 5.8 Error and downgrade behavior

- Unknown, absent, duplicated, or malformed compact `view`/`shape` selectors are
  ignored and receive legacy behavior; they do not create a new 400.
- `GET /races` and leaderboard retain their current authentication and 500 error
  behavior. A compact serializer failure is a request failure, not a silent second
  legacy query.
- Bootstrap retains the current 400/403/404/domain errors and 500 fallback. A
  compact shape is never returned when its ACTIVE-solo eligibility predicate is
  false.
- Message streams retain current 403/404/500 and partial-stream semantics. Status
  304 is legal only after authorization and only when the exact would-be successful
  response matches. Errors never become 304.
- Typed powerup context retains the current race-not-found, `RACE_NOT_ACTIVE`,
  not-active-participant/powerups-disabled, and 500 behavior. Missing or unknown
  `powerupType` selects legacy context rather than returning a new error.
- Powerup POST errors, error codes, refund behavior, and `retainHeld` behavior are
  unchanged under both the lean and legacy roster projections.
- A new client receiving any legacy contract parses it normally. A malformed new
  contract follows the existing endpoint-specific fallback/error path and never
  installs a sticky unsupported state except on the endpoint's documented 404.

## 6. Backend implementation plan

Implementation occurs in independently reversible milestones. Do not combine their
first benchmark attribution.

### 6.0 Milestone 0 — inherited capacity prerequisite, before optimization code

This document complements the capacity specification, so its prerequisite remains
binding. After this spec is approved but before any optimization source change:

1. finish/verify capacity milestone 5.0's corrected harness and observability;
2. run the first claimable corrected-harness, one-staging-worker, PgBouncer-pool-3
   baseline under the exact §8 protocol of the capacity spec;
3. retain its structured summaries, server telemetry, topology/config/commit
   manifest, and raw evidence; and
4. present the baseline for owner review.

No Milestone A–E implementation begins until the owner reviews that baseline and
explicitly authorizes optimization work. If the prerequisite is not satisfied,
capacity milestones 5.1, 5.4, and 5.5b remain outside implementation rather than
being silently weakened or bypassed.

### 6.1 Milestone A — database-owned set operations

1. Add a domain-model set-based race-list summary method and wire it behind
   `raceListSqlSummaryV1Enabled` in
   `src/modules/races/queries/getRaces.js`.
2. Preserve serializer logic while replacing full participant arrays with viewer,
   aggregate, leader/rank, and team summary records.
3. Add a raw/query-builder public-race count method in the race model and select it
   behind `publicRaceCountSqlV1Enabled`.
4. Run representative local/test-database EXPLAIN plans using existing tooling. Do
   not add an index unless measured plans require it and a later owner approval
   explicitly extends this spec to a migration.

### 6.2 Milestone B — existing scoring-path optimizations

1. Implement capacity milestone 5.1 for paged progress/bootstrap presentation
   hydration.
2. Implement capacity milestone 5.4 for uploader-only step/sample prefetch with the
   scoring-input version fence.
3. Do not duplicate their flags, queue semantics, or canonical calculation helpers.

### 6.3 Milestone C — Home

1. Add an injected `buildHomeRaceCardResponse` service/assembler. The route parses
   the request, calls the assembler, and serializes its result; it does not acquire
   new orchestration, Prisma, or cache policy.
2. Split active-race loading into a lean scoring projection and bounded
   presentation hydration.
3. Reuse step/sample/global-event inputs across compatible windows while keeping
   effects/Hitchhike just in time under the existing correctness boundary.
4. Rank the complete roster in Node and hydrate only the returned top-three rows
   plus viewer-specific presentation if the response actually needs it.
5. Preserve each optional branch's existing omission/default on failure and use this
   exact maximum-three-DB-branch schedule:
   - wave 1: core race card, shell presentation, friends summary;
   - wave 2: next-race resolution, active global event, step milestones;
   - wave 3: eligible ad-extra-spin status, impact summary, inbox unread count;
   - wave 4: service-banner settings and assembly of already-settled results.
   A branch not requested/capable is a resolved no-op and does not consume a slot.
   `dailyReward` remains an in-memory projection from `req.user`/`localDate`.
6. Inject the public inbox service (`getInboxUnreadCount`), existing next-race,
   event, milestone, ad, settings, cache, presentation, and friends collaborators
   into the assembler. Do not import inbox tables or duplicate their policy.
7. Preserve the existing fallback-card precedence. Candidate queries may run in
   parallel only when doing so cannot select a lower-precedence card or add
   mutations.
8. Bound Home's new database fan-out to at most three simultaneous DB-backed
   branches per request. Do not increase total query count merely to reduce wall
   time. Reject the parallel flag at the measurement gate if pool wait, connection
   pressure, or another endpoint's p95 regresses.

### 6.4 Milestone D — lean social/targeting/powerup reads

1. Implement capacity milestone 5.5b for caller-only message access and bounded
   stealthed-name hydration.
2. Add an injected `queries/getRacePowerupTargetContext.js`; it owns targeting
   orchestration and calls race/effect/inventory/progress public model/service seams.
   `races/routes.js` only parses, invokes, and responds.
3. Add typed powerup targeting context and remove Pinecone's frontend fetch.
4. Add `Race.findPowerupUseContextV1` and the conservative full-projection fallback
   described in §5.6. Prisma access remains in models, not the command or route.
5. Keep each powerup branch's business logic intact; this milestone changes only
   how required input rows are loaded.

### 6.5 Milestone E — compact wire contracts

1. Backend lands every opt-in parser/serializer and flag first.
2. Flutter adds the capability and explicit request opt-ins only after the backend
   contracts are locked.
3. Enable compact race-list, compact ACTIVE bootstrap, conditional message streams,
   typed target context, and compact leaderboard independently on staging.
4. Never enable a compact flag in production before the carrying iOS and Android
   build is available and separately authorized.
5. Verify all four combinations of internal/contract switches where applicable:
   legacy calculation + legacy wire, optimized calculation + legacy wire, legacy
   calculation + compact wire, and optimized calculation + compact wire.

## 7. Frontend plan

Primary files:

- `lib/services/backend_api_service.dart`
- `lib/services/race_stream_coordinator.dart`
- `lib/screens/race_detail_screen.dart`
- `lib/screens/tabs/races_tab.dart`
- `lib/screens/tabs/leaderboard_tab.dart`
- `lib/demo/demo_race_api_service.dart`
- `lib/tutorial/tutorial_preview_data.dart`

Required changes:

1. Add `api_payload_compact_v1` to both feature-header branches.
2. Request and defensively parse each explicit compact view. A legacy response is
   always accepted.
3. Derive box count from well-formed `slotItems`; retain `mysteryBoxCount` fallback
   for legacy/malformed responses.
4. Read team totals from `teams`; retain flat-total fallback for legacy responses.
5. For compact ACTIVE bootstrap, use progress participants and detail summary
   fields; on an absent required summary, use the existing fallback network path.
6. Store message ETag with its complete request identity and retain existing stream
   state on 304.
   Preserve the existing `fetchRaceMessageStreams` method signature so current test
   and app subclasses remain valid; the concrete `BackendApiService` owns request
   ETag state internally and returns an additive
   `RaceMessageStreamsResult.notModified` value defaulting to false.
   Add a synchronous, non-network
   `resetRaceMessageConditionalState({String? raceId})` method to the base service;
   `RaceStreamCoordinator.pause()` calls it for its race before stopping polling.
   Existing test fakes may inherit the safe base implementation.
7. Add a separate additive `fetchRacePowerupTargetContext` method rather than
   changing the existing `fetchRacePowerupUseContext` signature. Send
   `powerupType` there and skip both context methods for Pinecone Toss. The new
   method accepts either the typed contract or the legacy v1 body returned by an
   older backend to the same URL, so downgrade costs no second request. On 404,
   malformed data, timeout, or 5xx, retain the already-loaded progress-page
   candidates exactly as the current screen does; do not retry the same endpoint
   through the legacy method.
8. Accept compact leaderboard without `top10` and without a duplicated current row.
9. Override `fetchRacePowerupTargetContext` and
   `resetRaceMessageConditionalState` in both `DemoRaceApiService` and
   `TutorialPreviewBackendApiService` (defined in
   `lib/tutorial/tutorial_preview_data.dart`). Their deterministic local participants intentionally
   exercise the typed success path; they never call the network. Keep the existing
   legacy context and message-stream overrides/signatures unchanged so protected
   structural and subclass tests remain valid without edits.

No existing public/injected `BackendApiService` method gains a named parameter or
changes its Dart signature. Compact race-list/bootstrap/leaderboard and conditional
message opt-ins are internal behavior of the concrete service's existing methods;
test fakes continue compiling unchanged, while the demo/tutorial subclasses add only
the target-context and local reset overrides required by the existing network-leak
guard and lifecycle contract.

Loading, empty, stale-data, error, lifecycle, demo, and tutorial rendering remain
visually unchanged. Both iOS and Android use the same Dart path and must advertise
the same capability.

## 8. Data model and migrations

No data-model change is planned.

Existing relevant indexes include:

- `race_participants(race_id,status)`;
- `race_participants(user_id,status)`;
- unique `race_participants(race_id,user_id)`;
- `race_active_effects(race_id,status)`;
- `step_samples(user_id,period_start,period_end)`;
- `step_samples(user_id,period_end)`;
- `race_messages(race_id,created_at)`; and
- the raw partial USER message watermark index.

If EXPLAIN evidence later requires an index, pause and amend this section with the
exact additive concurrent migration, old-code compatibility, rollback, and measured
write/storage cost before creating it. No destructive migration is permitted.

## 9. Existing-test-only verification plan

No test source is added or modified. Before implementation, record hashes/status of
all currently tracked test files so unrelated owner changes are distinguishable
from this work. After each milestone, `git diff -- test k6/test` in the frontend and
`git diff -- test` in the backend must show no changes attributable to this work.

Because the worktrees are already dirty, each implementation agent must capture the
initial `git status --short` and relevant diffs, edit only assigned production/spec
files, and never restore, overwrite, stage, or reformat an unrelated owner change.

Required verification uses the existing suites and existing operational tooling:

### Backend

- Confirm `DATABASE_URL` names a dedicated local/test database before any
  integration command.
- Run `npm run test:unit`.
- Run `npm run test:integration`; never run bare `npm test`.
- Run existing Redis-backed suites under their documented test Redis configuration
  and once with Redis unavailable where the existing command supports it.
- Use the existing k6/local capacity harness and production-log analysis scripts;
  do not edit their tests as part of this spec.
- On a dedicated local/test environment or staging, capture paired authenticated
  legacy and compact responses for the same fixture and compare them with a
  non-committed canonical JSON-diff command that permits only the removals and
  contract changes in §5. This supplies contract evidence without adding a test
  artifact.

### Reproducible non-committed flag-on verifier

The existing suites do not cover the ten new flags. Since the owner forbids adding
or modifying tests, implementation must produce
`docs/request-path-and-payload-optimization-verification-evidence.md` containing the
complete temporary verifier source, its SHA-256, exact environment/commands, fixture
manifest, canonical outputs, DB before/after snapshots, query counts, event/feed
captures, and pass/fail matrix. The verifier source is executed from a `mktemp`
directory and is not added under `test/`.

The evidence command form is fixed:

```sh
VERIFY_ROOT="$(mktemp -d /tmp/request-path-verify.XXXXXX)"
BACKEND_REPO="<backend path from CLAUDE.local.md>"
# Materialize the exact verifier source embedded in the evidence document at:
# $VERIFY_ROOT/request-path-verifier.mjs
DATABASE_URL="postgresql://.../steps_tracker_request_path_test" \
REDIS_URL="redis://127.0.0.1:6379/15" \
NODE_ENV=test \
node "$VERIFY_ROOT/request-path-verifier.mjs" \
  --backend "$BACKEND_REPO" \
  --output "$VERIFY_ROOT/redis-on.json"
DATABASE_URL="postgresql://.../steps_tracker_request_path_test" \
REDIS_URL= \
NODE_ENV=test \
node "$VERIFY_ROOT/request-path-verifier.mjs" \
  --backend "$BACKEND_REPO" \
  --output "$VERIFY_ROOT/redis-unset.json"
```

Before either run, the verifier itself aborts unless the parsed database name ends
in `_test`; it starts the real HTTP app, uses unique fixture users/races, and never
accepts a production/staging URL. Redis DB 15 is the only Redis namespace it may
clear. Each flag is restored to false in a `finally` path.

Required off/on cases:

| Flag/path | Required captured evidence |
|---|---|
| `raceListSqlSummaryV1Enabled` | canonical full JSON equality off/on for active, pending, completed, team, finisher-null-placement, equal-finish-time, identical-placement+finish-time anomaly fallback, zero-step/join/UUID ties; SQL count/rows and no full roster returned to Node on the non-anomalous path |
| `apiRaceListCompactV1Enabled` | legacy vs compact canonical diff contains only §5.2 contract/removals; all optional top-level capability blocks retained |
| `apiRaceBootstrapCompactV1Enabled` | ACTIVE solo sends one participant array; team/PENDING/COMPLETED/tokenless/flag-off remain legacy; malformed summary triggers existing fallback in a real app run |
| `homeRaceCardLeanLiveV1Enabled` | identical live totals, rank, top three, teams, effects, and selected card over active/fallback fixtures; presentation identities loaded bounded to serialized rows; query phases captured |
| `homeRaceCardParallelOptionalV1Enabled` | identical success and injected single-branch-failure bodies; maximum observed DB fan-out ≤3; query count unchanged; pool wait captured |
| `publicRaceCountSqlV1Enabled` | off/on count equality for membership, full/unlimited capacity, solo/team capability, team ACTIVE exclusion, tournament, seeded, review-account, and hidden-window truth-table rows; DB returns one scalar |
| `apiRaceMessageConditionalV1Enabled` | changed 200 body parity, unchanged authorized 304/no body, includeUser true/false, limit/request identity reset, partial-stream error, sender rename/photo change, Stealth activation/expiry, Redis on and unset |
| `apiRacePowerupTargetContextV1Enabled` | legacy fallback; typed non-Bounty minimal fields/no scoring; Bounty bounded-stale display with Redis on and Postgres fallback unset; team/forfeit/Stealth filters; Pinecone request count zero in a real Flutter run |
| `racePowerupLeanUseContextV1Enabled` | every `POWERUP_COPY_TYPES` value off/on: same status/body, participant/effect/powerup/coin rows, feed events, event-bus capture, and resolution enqueue; explicit Decoy redirect/fizzle, Mirror, Socks, jam guard, Power Outage cleanser, AOE, target forfeit/team, and Trail Mine cases |
| `apiLeaderboardCompactV1Enabled` | top-100 order/values/presentation identical; only `top10` and in-list current-user duplicate removed; outside-top-100 row retained; legacy fallback unchanged |
| inherited `raceProgressLeanProjectionV1Enabled` | exact capacity §5.1 warm/cold, Redis-on/unset, legacy/full and paged output/query/hydration evidence |
| inherited `legacyUploaderStepSamplePrefetchV1Enabled` | exact capacity §5.4 response/DB/box/effect/timezone/concurrent-version evidence |
| inherited `raceMessageLeanAccessV1Enabled` | exact capacity §5.5b authorization/redaction/query identity evidence with Redis on/unset |

The verifier compares database effects after each public mutation and never imports
a calculation helper as the oracle. The flag-off public response/database outcome
is the oracle for flag-on parity. Any difference outside an approved compact
transformation fails the matrix and blocks rollout.

### Frontend

- Run `flutter analyze`.
- Run `flutter test`.
- Account for both iOS and Android and run the repository's normal non-production
  build verification when implementation reaches the final gate.

### Regression invariants checked by the existing suites

- legacy response contracts and defensive missing/null reads;
- rank/tie/team/forfeit/finish behavior;
- step/sample overlap and same-request box semantics;
- powerup target validation and per-type use behavior;
- message authorization, redaction, cursor, and cache fallback;
- bootstrap/progress paging and fallback behavior; and
- leaderboard and races-tab rendering.

If an existing test fails because the new implementation changes established
behavior, fix the implementation. Do not alter the test. If an existing test is
red before implementation, record it as a pre-existing failure and obtain owner
direction; do not normalize or suppress it.

## 10. Measurement and acceptance gates

Use the same endpoint normalization and compressed-body interpretation as the
2026-08-18 organic monitor. Compare matched windows/topologies and report sample
count, average, p50, p95, status distribution, total bytes, and average bytes.

Milestone acceptance:

- `GET /races`: legacy output semantic parity; compact average bytes lower; SQL
  summary transfers no full roster into Node; average and p95 do not regress.
- Progress/bootstrap: full lean scoring input; presentation hydration bounded by
  returned page; compact ACTIVE bootstrap contains one participant page.
- Home: live totals/ranks identical; presentation hydration bounded to top three;
  optional branch failure semantics unchanged; average/p95 improve without shifting
  work to extra client requests or increasing query count/DB-pool pressure.
- Discovery: count exactly matches the existing public browser visibility result on
  the same fixture; database returns one scalar count rather than all candidate
  participant rows.
- Legacy samples/sync: response and immediate uploader box state unchanged; query
  growth follows unique windows rather than active-race count.
- Message streams: exact 200 body parity when changed; authorized 304 with zero body
  when unchanged; no stale 304 on name/photo/redaction/error changes; full-roster
  access load removed.
- Target context: non-Bounty targeting performs no standings scoring; Bounty uses
  the existing bounded-stale display source with Redis-unset Postgres fallback and
  remains advisory until authoritative POST validation; Pinecone performs no
  context request.
- Powerup use: every known non-Trail powerup receives the complete minimal roster
  plus required caster/branch fields; old validation/results/events are unchanged;
  Decoy/Mirror/shields and recipient alerts retain full inputs; Trail Mine retains
  full fresh scoring.
- Leaderboard: compact response omits `top10`; no duplicate current-user row when
  in top 100; displayed order/value/cosmetics unchanged.

For wire reductions, report measured byte delta but do not set an invented minimum
percentage before observing representative payloads. For latency, a change is a
win only with matched evidence and no protected-suite regression; small noisy
changes are reported as inconclusive.

For conditional messages, record canonicalization plus SHA-256 CPU time separately
from access, query/cache, serialization, and total request time. The flag fails its
gate if unchanged polls save bytes but materially increase per-poll CPU or worsen
matched message-stream or unrelated endpoint p95.

## 11. Backward compatibility and rollout

1. Implement and deploy backend support first, with every new flag false.
2. Verify legacy requests against the new backend before any app build opts in.
3. Build and verify the carrying Flutter version for iOS and Android from the same
   source/version.
4. Enable one flag at a time on staging and measure its endpoint independently.
5. App Store/Play rollout does not authorize backend production flags. Each
   production flag exposure requires separate, immediate authorization.
6. Frozen clients continue using legacy shapes indefinitely. Do not schedule field
   deletion based merely on the one-week phased rollout.
7. Rollback is flag off. The new frontend must parse legacy responses after rollback
   without requiring a new binary.

No new content asset, `testOnly` catalog item, or database backfill is involved.

## 12. Acceptance criteria and definition of done

Implementation is complete only when:

- the corrected one-worker/pool-3 prerequisite baseline was retained, reviewed,
  and separately authorized before source implementation;
- every in-scope milestone is implemented or explicitly removed by an approved
  spec revision;
- every legacy request path remains compatible with frozen clients;
- all compact/conditional behavior is capability + request + flag gated;
- canonical game calculations remain in the existing Node helpers;
- set-based persisted calculations run in the data/domain layer, not routes;
- no frontend or backend test file changed and no new test file was added;
- existing backend unit/integration suites pass on a confirmed test database;
- `flutter analyze` and the existing Flutter suite pass;
- both platforms are accounted for;
- matched endpoint and payload measurements satisfy §10;
- the complete non-committed flag-on verification matrix and evidence document in
  §9 pass without any unapproved delta;
- flag-off rollback is exercised on staging;
- architect review required changes are incorporated;
- the combined implementation receives the required code-reviewer review; and
- no production action occurs without a new explicit approval.

## 13. Owner approval gate

Approval of this document authorizes only the Milestone 0 staging baseline and
evidence work in §6.0. After reviewing that evidence, the owner must explicitly
authorize Milestones A–E before any optimization source change begins. Neither
approval authorizes a production deploy, production data access beyond separately
approved read-only measurement, a migration, or modification of any test.

## 14. Revision log

- **2026-08-18 — Phase 1 draft:** Converted the organic response-size/duration
  audit into a cross-repo implementation contract; separated database set work from
  canonical in-memory game rules; added additive compact contracts and explicit
  frozen-client gates; incorporated the owner-directed existing-test-only policy.
- **2026-08-18 — Gap pass 1 (contract and compatibility):** Added concrete
  frontend/backend source seams, made compact responses exact transformations of
  legacy output, removed the circular ETag definition by pinning deterministic hash
  input, and specified error/downgrade behavior for every changed endpoint.
- **2026-08-18 — Gap pass 2 (failure, rollout, and operability):** Made the owner's
  no-test exception explicit for inherited milestones, required parameterized SQL,
  pinned private conditional-response headers, made powerup scoping conservative,
  bounded Home DB fan-out, added flag-combination verification, protected the dirty
  worktrees, and required paired canonical response diffs without committed tests.
- **2026-08-18 — Architecture review (`REVISE`):** Refreshed the backend baseline
  to `6719393`; replaced unsafe caster/target scopes with a complete minimal roster
  that preserves Decoy and alert recipients; made Bounty display explicitly
  bounded-stale with Postgres fallback and POST authority; pinned SQL null/default/
  collation ordering; preserved existing Dart method signatures and added explicit
  demo/tutorial overrides; moved Home and target orchestration into injected
  services; expanded no-test verification to a reproducible per-flag public-path
  matrix; and restored the capacity spec's pool-3 baseline/owner-review prerequisite.
  Suggestions to measure ETag CPU and publish the discovery truth table were also
  incorporated.
- **2026-08-18 — Post-review fresh-eyes pass:** Re-read the full revised contract
  against the refreshed sources, removed a redundant same-URL target-context retry,
  confirmed existing Dart signatures remain intact, and cross-checked every new
  flag against the non-committed verification and rollback matrices.
- **2026-08-18 — Architecture re-review (`REVISE`):** Added an explicit
  `ambiguousFinisherOrder` detector and whole-request legacy fallback for duplicate
  finisher placement/time keys that the current comparator orders anomalously.
  Added a synchronous service reset seam called by `RaceStreamCoordinator.pause()`
  and local demo/tutorial overrides so conditional-message validators cannot leak
  across pause/resume while preserving protected method signatures and network
  guards.
- **2026-08-18 — Final architecture confirmation (`APPROVE`):** The architect
  confirmed both re-review blockers are resolved, found no new blocker, and issued
  no additional suggestion. The owner approval gate was clarified to authorize
  only Milestone 0 evidence work before a separate source-implementation approval.
