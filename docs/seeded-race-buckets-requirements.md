# Private seeded Daily/Weekly race buckets — requirements

## Summary and user story

Replace each globally shared seeded Daily and Weekly challenge field with small,
**private, server-assigned buckets**. A bucket has at most 15 accepted racers.
It is a normal seeded `Race` internally, but it is never discoverable or
readable by a non-participant. Daily buckets are matched using the participant's
previous completed **ET calendar day** of walked steps; Weekly buckets use the
previous completed **ET Monday-to-Monday week**. The matching priority is
friends first, then closest historical step totals.

> As an opted-in walker, I enter the Daily and Weekly challenge with a small
> group that includes friends where possible and otherwise people with a
> similar recent activity level. I can view only my own group, rather than
> other Daily/Weekly groups.

The canonical timezone remains `America/New_York`, consistent with the current
seeded lifecycle (`stepv2-backend/src/modules/races/jobs/seededRaceRenewal.js`).

## Scope

- Daily (`DAILY_10K`) and Weekly (`WEEKLY_50K`) only; both retain their current
  targets, time-based scoring, powerup configuration, prizes/payout policy,
  inactivity policy, cadence, and `autoJoinFeaturedRaces` preference.
- Maximum 15 **ACCEPTED** participants per bucket. Invited/declined rows do not
  consume a slot (seeded buckets normally have none).
- A user can have one accepted bucket per seed per time window. A Daily and a
  Weekly bucket can coexist.
- Existing opt-in / public join actions choose or create the caller's bucket.
  There is no bucket picker, invite link, sharing, spectating, or cross-bucket
  leaderboard.
- Assignment is final for that race period. A participant is never moved after
  boundary assignment, including when a friend later joins, a member leaves,
  or step history changes. Newcomers are grouped together where possible, but
  direct friendship overrides that preference.
- The existing featured card remains one Daily and one Weekly card for the
  viewer, but its `raceId`, count, availability, and `myStatus` describe only
  that viewer's bucket. A user with no bucket sees JOIN/OPT IN, not a global
  field count. A durable pending candidate is returned as `myStatus:
  "ELECTED"` with `raceId:null`; it is not merely local button state, so a
  refresh or app restart still renders the non-navigable pending card.

## Non-goals

- Changing race economics, targets, payout curve, powerup odds, rewards, or
  scoring. This is grouping, not a balance change.
- Matching against profile data, friend-of-friend graphs, rankings, device,
  timezone, or protected/sensitive attributes.
- Rebalancing/moving a participant after assignment, filling historical
  completed races, or guaranteeing every friend group is kept together.
- Changing user-created/public races, tournaments, Ranked cohorts, or the
  onboarding reward.

## Current-state findings and constraints

- Today one `RaceSeed` maps to one ACTIVE and one PENDING globally public race:
  renewal creates the active/upcoming rows and auto-enrols all opted-in users
  (`stepv2-backend/src/modules/races/jobs/seededRaceRenewal.js:61-459`).
  `RaceSeed.maxParticipants` is currently copied into each row and the live
  Daily/Weekly seed migration set it to 500
  (`prisma/migrations/20260625000000_add_race_timezone_bump_seed_cap/migration.sql`).
- `Race` has `seedId` but no time-window/bucket identity; `RaceParticipant` has
  only uniqueness on `(raceId,userId)` (`prisma/schema.prisma:899-1026`,
  `1165-1278`). New database constraints are therefore needed for safe,
  concurrent matching.
- `GET /races/featured` groups all live races by `seedId`, taking a single
  latest row, and `GET /races/public` exposes active seeded races. That violates
  private-bucket visibility as soon as there is more than one row per seed
  (`getFeaturedRaces.js`, `getPublicRaces.js`). `GET /races/:id` currently
  correctly requires participation except for a tournament exception, so it
  only needs an explicit seeded-private regression guard (`getRaceDetails.js`).
- Auto-enrollment currently bulk-slices users by account age, which cannot
  preserve friend-first/skill ordering and has a count-then-`createMany` race
  under concurrent joins (`commands/autoJoinFeaturedRaces.js`). It must be
  replaced for bucket seeds; do not reuse its capacity algorithm.
- `step_samples` has timestamped samples and a batched/prorated window helper;
  `steps` is a client-local day fallback. The existing inactivity implementation
  deliberately combines them defensively (`prisma/schema.prisma:350-381`,
  `modules/steps/models/stepSample.js:293-340`,
  `services/seededInactivity.js:20-145`). Skill matching must use the same
  source precedence, not a raw sum that produces a different historical total.
- Retention currently keeps step samples 45 days while protecting unsettled
  races (`modules/steps/jobs/stepSampleRetention.js`). Previous-day/week
  matching needs only a closed recent window, but the matcher must run before
  deletion and should persist its immutable input value rather than recompute it
  later.
- The frontend already parses featured payloads defensively and renders the
  Races/Public Races real screens plus tutorial fixtures
  (`lib/services/backend_api_service.dart:2240-2257`,
  `lib/screens/public_races_screen.dart:715-750`,
  `lib/widgets/featured_race_card.dart`,
  `lib/tutorial/tutorial_preview_data.dart:852-875`).

## Product decisions and matching algorithm

### Window and eligibility

1. A bucket belongs to exactly one `(seedId, windowStart)` where `windowStart`
   is the DST-correct ET start instant used by renewal. Its `windowEnd` is the
   corresponding next ET midnight / next Monday.
2. The eligible population is the users elected into the PENDING window by
   auto-join or explicit OPT IN, less the existing inactivity exclusions. An
   explicit POST can add its caller to the *pending candidate pool*, but never
   directly to a bucket. Disabling auto-join does not remove a previously
   elected candidate.
3. `GET /races/featured` is always virtual/no-side-effect while unassigned.
   Only explicit `POST /races/seeded/:seedKind/assign` (Join/Opt In) elects the
   caller. A deterministic batch job finalizes all candidates before the ET
   boundary; it creates races/participants only from that final plan. There is
   no current-window assignment, late join, transfer, replacement, or singleton
   created after the period begins.
4. A 0/missing historical total is valid and is matched as `0`; a new account
   is not rejected. This avoids turning missing telemetry into a hidden
   eligibility rule.

### Historical skill snapshot

At batch finalization, calculate and persist `matchSteps`:

| Seed cadence | Source window |
| --- | --- |
| Daily | trailing 28 completed ET days, excluding the immediately preceding day |
| Weekly | four completed ET Monday-to-Monday weeks, excluding the immediately preceding week |

Use prorated `step_samples` for those exact closed UTC intervals. To retain compatibility
with older app uploads, use the maximum of that sample total and the relevant
`steps` daily rows under the existing safe ET policy; no row means zero. Clamp
negative/malformed values to zero and integer floor. Persist the result once so
late HealthKit corrections cannot reshuffle an already-created bucket.

### Deterministic pre-boundary batch clustering

One transaction-scoped PostgreSQL advisory lock keyed by `(seedId, windowStart)`
elects the authoritative stream and snapshots the candidate set. A repeatable,
versioned deterministic batch algorithm then produces the complete plan:

1. Sort candidates by `matchSteps`, then stable user ID. Build friendship
   components using only edges that meet the skill-band guard
   `abs(a-b) <= max(2000, 0.5 * max(a,b))`. Edges outside the band do not force
   co-location, even for friends.
2. Split oversized components deterministically at the lowest-cost permitted
   skill-band edges until every atomic group is <=15. Place groups friend-first,
   then pack newcomer-only groups, then fill remaining capacity by nearest
   group/bucket median. All ties use stable user IDs then deterministic bucket
   ordinal—never database insertion order or wall-clock timing.
3. Emit buckets of at most 15. Where the eligible cohort has at least two users,
   every emitted bucket must contain at least two users; merge/rebalance trailing
   singleton groups into the closest legal bucket. A one-person bucket is legal
   only when the entire eligible cohort has exactly one person.
4. Persist the planned durable assignments and corresponding `RaceParticipant`
   rows atomically, then mark the plan FINAL. Retry returns the same plan;
   no post-finalization movement occurs.

Friends may correctly land in different buckets in different periods as the
eligible set, skill band and capacity differ. The algorithm is deliberately not
online greedy: request arrival order must never decide a group.

Friendship is **direct and accepted mutual friendship only**, using the existing
social friendship authoritative table/model. Pending, blocked, removed, and
one-way requests do not count. The response does not disclose friend count,
other bucket IDs, or why a match occurred.

## Data model and migration plan

Introduce a dedicated, additive `SeededRaceBucket` table rather than overloading
names or assuming a `Race` is public:

```text
SeededRaceBucket
  id              UUID PK
  seedId          text FK race_seeds(id)
  windowStart     timestamptz
  windowEnd       timestamptz
  raceId          text UNIQUE NOT NULL FK races(id) -- sole Race↔Bucket FK
  status          PENDING | ACTIVE | COMPLETED
  createdAt/updatedAt
  UNIQUE(seedId, windowStart, id)             -- lookup/index prefix
  INDEX(seedId, windowStart, status, createdAt)

SeededRaceBucketAssignment
  bucketId        UUID FK seeded_race_buckets(id) ON DELETE CASCADE
  userId          text FK users(id)
  raceParticipantId text UNIQUE NOT NULL FK race_participants(id)
  matchSteps      integer NOT NULL CHECK >= 0
  assignedAt      timestamptz
  state           ELECTED | ASSIGNED | PRUNED | FINAL
  PRIMARY KEY(bucketId,userId)
  UNIQUE(seedId, windowStart, userId)         -- denormalized, mandatory
```

`Race.seededBucketId UUID? UNIQUE` is the only reciprocal relation; no second
FK is permitted. Use a deferred FK/check or equivalent migration ordering to
create the one-to-one relation safely. Durable assignments link each planned
member to the exact `RaceParticipant`, so inactivity pruning marks an assignment
`PRUNED` and cannot leave invisible occupancy or permit a second assignment.
The DB also enforces exactly one membership per `(user, seed, window)` across
both streams through a `SeededRaceWindowMembership` ledger (or equivalent) with
`stream LEGACY|BUCKET`, `raceId`, and unique `(seedId, windowStart, userId)`.
Do not rely on a cross-table application check.

Add `Race.isPublic` handling so every bucket row is `false`. Do not change the
meaning of existing seeded `Race` rows. Do not lower the seed's legacy 500 cap:
new bucket creation stamps 15 directly; legacy fallback continues its own cap.

Migration sequence:

1. Create tables/nullable FK/indexes/checks only. No backfill and no destructive
   changes; all existing global seeded races remain legacy rows.
2. Add the private-query/matcher code and tests with a default-off
   `seededRaceBucketsEnabled` setting. A second server instance must tolerate
   schema-present / flag-off and flag-on / no compatible users.
3. Introduce authoritative stream election per `(user, seed, window)` before
   enrollment: exactly one of LEGACY or BUCKET wins and is recorded in the
   membership ledger. Turn on only after the carrying app is available; new
   compatible-user windows receive buckets. Existing in-flight legacy races
   finish unchanged.
4. At final old-client retirement (explicit operational decision), stop minting
   legacy global rows in a future migration/release; do not delete historical
   races or participant rows.

## API contract and privacy

Use feature token `seeded_race_buckets`. The Flutter build sends it in
`X-Client-Features`; all behaviour below is selected from the request token,
not sticky `User.clientFeatures` (a user can switch devices/builds).

### Existing endpoint changes for capable clients

`GET /races/featured` remains `{ "races": [...] }`, exactly two-or-fewer
Daily/Weekly cards. For a capable user it returns only their assigned bucket;
when unassigned, it returns a virtual joinable card with no race ID until
assignment. **GET never assigns**; only an explicit POST Join/Opt In elects a
candidate for the next batch, so:

```json
{
  "races": [{
    "raceId": null,
    "seedKind": "DAILY_10K",
    "name": "Daily Challenge",
    "endsAt": "2026-08-13T04:00:00.000Z",
    "participantCount": 0,
    "maxParticipants": 15,
    "isFull": false,
    "myStatus": null,
    "bucketPrivate": true,
    "upcoming": { "raceId": null, "scheduledStartAt": "...", "participantCount": 0,
      "maxParticipants": 15, "isFull": false, "myStatus": null, "bucketPrivate": true }
  }]
}
```

For an elected-but-not-finalized candidate, the same virtual response uses
`"myStatus":"ELECTED"`; it never leaks candidate-pool or future-bucket
counts. `POST /races/seeded/:seedKind/assign` is new, static-before-`/:raceId`, requires
the token and accepts only `{ "window": "UPCOMING" }`. It elects the caller
into the authoritative BUCKET stream/candidate pool and returns `202` with
`{ "elected": true, "raceId": null, "finalizesAt": "..." }`; it never
selects/creates an online bucket. After finalization the normal card has a
non-null `raceId`. Errors: `400 INVALID_WINDOW`, `404 SEED_NOT_FOUND_OR_DISABLED`,
`409 WINDOW_FINALIZED`, `409 LEGACY_STREAM_ELECTED`, and `503 MATCHING_UNAVAILABLE`
with no election/participant created. Never return another bucket ID.

For every `POST /races/:raceId/join`, reject a private seeded bucket with
`403 RACE_PRIVATE`; the new client calls `/assign`, not guessed IDs.
`GET /races/:raceId`, progress,
chat, powerup and mutation routes enforce the same member-only access for a
bucket race; participants continue to work unchanged.

`GET /races`, Home suggestions, `GET /races/discovery-summary`, and
`GET /races/public`:

- return the caller's assigned bucket only via their personal race list;
- exclude **all** bucket races from public/discovery/home suggestion queries and
  counts, at SQL predicate level (`seeded_bucket_id IS NULL` / join exclusion),
  not merely after fetching;
- do not let an unassigned virtual card inflate public count;
- retain current legacy responses byte-for-byte for callers without the token.

Privacy also covers push deep-link targets, notification payload creation,
Universal/App Link navigation, cached route restoration, analytics properties,
and error logs: each carries only a member's own race ID (or none) and every
server request authorizes membership. Client-side hiding is never a privacy
control.

The frontend service must parse `raceId` nullable and the new fields defensively.
Missing `bucketPrivate` / null ID means the current legacy card path. It must
never manufacture a URL or call `joinPublicRace` with null.

### Frozen-client compatibility and rollout bridge

Old apps currently call `/races/public`, `/races/featured`, and direct
`/:raceId/join`; they cannot render virtual cards nor keep private IDs secret.
Therefore a single immediate switch is unsafe and violates the privacy goal.

Recommended bridge: while any non-capable traffic is supported, keep the legacy
global daily/weekly stream **only for non-capable requests/users**, and allocate
private buckets only to token-capable users. Legacy rows are excluded from
capable-user featured/public/discovery responses; bucket rows are excluded from
non-capable-user responses. The renewal job must reconcile the two populations
per window without mixing them. This preserves old binaries while ensuring no
capable user sees another capable user's bucket. It does mean friends split
across app versions cannot be matched until both upgrade.

Backend deploys/migrates first with flag off, then the iOS and Android build
ships together carrying the token and nullable parsing. Enable a small server
cohort only after builds are available, observe, then expand. Do not activate
global-only retirement until an explicitly accepted old-client support cutoff.
Rollback disables new bucket assignment for future windows; it never makes an
already private race public or moves an active player.

## Backend implementation plan

1. Add Prisma models/migration and a `seededRaceBucketMatcher` service that
   owns window calculation, historical snapshots, friend query, advisory lock,
   eligibility and idempotence. Share `windowFor`/ET helpers with renewal; do
   not duplicate date arithmetic.
2. Refactor renewal to reconcile a legacy stream and a bucket stream behind the
   flag/token policy. For buckets, create only a window template/virtual card
   state until assignment; create races lazily per bucket. Promotion/expiry,
   inactivity prune, push, boxes, prize settlement, and cleanup must iterate
   every bucket race, not assume one race per `seedId`.
3. Replace bucket-path `autoJoinFeaturedRaces.enroll` with candidate elections,
   then one pre-boundary deterministic batch-clustering run. The job must bound
   DB work, be resumable/idempotent, write no bucket race before plan finality,
   and fail closed before the boundary rather than produce online singletons.
4. Update list/find models and all public discovery SQL so private rows cannot
   leak. Update every race detail/mutation authorization path, including share
   token creation/preview/join: bucket races may not receive share tokens.
5. Add the feature-gated API route and feature token plumbing. Never use a
   client-supplied match score, bucket ID, friend list, seed ID, or time window
   timestamp as authority.
6. Audit cleanup/diagnostic/admin scripts: `cutover-seeded-races-to-midnight.js`,
   `diagnose-challenge-boxes.js`, seeded inactivity hooks and step-sample
   retention must understand multiple bucket rows. Diagnostics aggregate only
   privileged operational data and must never be exposed to player APIs.

## Frontend plan (iOS and Android)

- Add `seeded_race_buckets` to the shared client feature header.
- Extend `BackendApiService.fetchFeaturedRaces` and its discovery fallback to
  accept nullable `raceId` and `bucketPrivate`; add `assignSeededRaceBucket`.
  All casts must be guarded (`Map`/`num`/string checks).
- Update `PublicRacesScreen`, `FeaturedRaceCard`, Home suggested-race flow and
  MainShell callbacks: unassigned card CTA is JOIN/OPT IN and elects the user;
  while elected but not finalized, render a non-navigable “YOU'RE IN” pending
  state; after finalization, VIEW opens the returned bucket. Display `n racing`
  only for the viewer's bucket and never
  say it is globally full. Keep the 15-cap internals out of copy unless product
  requests a "small group" label.
- Existing assigned bucket route opens the ordinary `RaceDetailScreen`; no new
  detail UI is required. Its normal participant board is therefore inherently
  private once backend authorization is fixed.
- Update real-screen tutorial fixtures with `bucketPrivate: true`, a valid
  non-null assigned `raceId`, and small counts; validate both the Public Races
  preview and any Home feature fixture. Tutorials must not call assignment.
- Loading: preserve current skeleton/last known data. Error: retain the card and
  show existing retry/toast; never falsely show another bucket's card. Empty:
  a capable user sees Daily/Weekly virtual cards when the seed is active; an
  old backend/absent fields follows the present legacy behavior.

## Tests-first plan

All backend integration tests run only against the dedicated test database;
never production. Add failing tests before implementation.

- Migration fresh/upgraded: tables/indexes/checks exist; legacy races are
  untouched; only new bucket races have private linkage and max 15.
- Batch matching: same candidate set presented in every permutation yields the
  identical plan; friends co-locate only inside the `max(2000, 0.5×max)` band;
  out-of-band friends do not force a match; newcomer grouping and skill fill
  are deterministic; every bucket is <=15 and, with cohort >=2, >=2; no online
  or post-boundary singleton is minted. Daily uses the correct 28-day exclusion
  and Weekly the correct four-week exclusion, including ET/DST boundaries.
- Concurrency: parallel explicit POST elections and auto-join election yield
  one authoritative LEGACY/Bucket membership per user/seed/window; exactly one
  batch plan/race per bucket and no duplicate `RaceParticipant`; retry returns
  the same election/final plan.
- Lifecycle: auto-enroll, setting enable, virtual GET/no assignment, explicit
  upcoming election, boundary finalization/no active join, promotion, inactivity
  prune (including durable assignment state/slot handling), weekly sweep, box initialization, settlement,
  retention, and next-window creation operate across multiple buckets.
- Privacy HTTP regressions: Alice cannot obtain Bob's bucket via featured,
  public, discovery summary, Home suggestions, guessed ID, share token,
  progress/chat/powerup/mutation endpoint, push/deep link, restored navigation,
  analytics payload, or public count. Alice can read her
  own detail and participant list. Bucket rows never leak in a raw public SQL
  model path.
- Legacy HTTP regressions: no-token caller gets the current one-global-card
  shape, public row, preregistration semantics, and direct join behaviour;
  capable client never sees a legacy/global or another user's bucket.
- Existing `seeded-race-prereg.test.js`, `featured-auto-join.test.js`, seeded
  payouts/inactivity and discovery tests are retained—not weakened—and expanded
  to assert multi-bucket rules.
- Flutter widget/integration: malformed/missing fields do not throw; virtual
  card calls assignment once; assigned card opens only returned ID; UI reports
  the bucket count; legacy payload remains renderable; Public Races/Home and
  tutorial real-screen fixtures render on iOS/Android shared Dart path.

## Acceptance criteria / definition of done

- Every new Daily/Weekly private bucket has at most 15 accepted participants,
  and every bucket has at least 2 when the eligible cohort has at least 2.
  It has a persisted closed-window skill snapshot using the approved lookback.
- Friend co-location respects the stated skill band; batch clustering is
  deterministic regardless of request arrival order, then groups newcomers and
  fills by skill using deterministic ties.
- A player can access exactly their own bucket; no other bucket appears in any
  player-visible list, count, deep link, detail, mutation, notification,
  analytics or restored-navigation route.
- A user is never moved after assignment and never occupies two same seed/window
  buckets; Daily/Weekly remain independently joinable.
- Existing seeded lifecycle, payments, scoring and activity cleanup work for
  multiple races per seed; no economy behavior changes.
- Version skew is tested and rollout/rollback do not strand old binaries.
- `flutter analyze` is clean; relevant Flutter integration/widget tests pass;
  backend `npm run test:unit` and `npm run test:integration` pass against test
  DB. iOS and Android are both accounted for.
- Manual UI-placement checklist is supplied by `ui-test-planner` before
  implementation is presented as complete.

## Unresolved questions requiring product decision

1. **Resolved implementation default:** until an explicit old-client retirement
   date is selected, non-capable callers use the temporary LEGACY/global stream
   and capable callers use BUCKET. Friends on different app versions can
   therefore be in different streams. This is the safe compatible bridge.
2. Backend implementation must identify the existing authoritative predicate
   for direct accepted mutual friendship, including deletion/block behavior,
   and record it in its implementation notes and integration coverage. This is
   a technical discovery, not a reason to fall back to a looser social rule.

## Revision log

- 2026-08-12, Phase 1: drafted after inspecting the frontend featured card/API
  consumers and backend schema, renewal, auto-enroll, visibility/discovery,
  lifecycle, retention and integration-test paths. Identified existing global
  per-seed assumptions and required a private bucket relation rather than a
  name-only convention.
- 2026-08-12, Phase 2 pass 1: added the immutable ET historical snapshot,
  advisory-lock/concurrency rule, direct-friend definition, all player API
  privacy surfaces, and cleanup-script audit.
- 2026-08-12, Phase 2 pass 2: added explicit old-client dual-stream bridge,
  non-public virtual featured card contract, no share-token rule, no
  post-assignment migration, test DB constraint, and unresolved product choices.
- 2026-08-12, product decisions folded in: fixed the hard 15-person cap,
  friend-first priority, newcomer-before-skill fallback, ET boundary
  finalization, per-period friend placement, and privacy across all discovery,
  direct/deep-link, notification, analytics and app surfaces.
- 2026-08-12, approved safer matching revision: replaced online greedy matching
  with deterministic pre-boundary batch clustering; set Daily to trailing 28
  completed days excluding D-1 and Weekly to four completed weeks excluding the
  immediately prior week; bounded friend co-location by the approved skill band;
  required 2+ buckets for 2+ eligible users; made GET virtual and POST election
  only; and added architect-required authoritative stream election, one-to-one
  Race/Bucket FK, durable RaceParticipant-linked assignments, and inactivity
  handling.
- UI-placement plan requires manual verification of: unassigned and assigned
  cards in both Public Races and Home; only the viewer's small bucket count;
  no other Daily/Weekly bucket through direct navigation; the elected
  non-navigable state; legacy cards; and real tutorial/demo fixtures on iOS and
  Android. Tutorial fixture counts must be changed from global-style values to
  small private buckets.
- Architecture, UI-placement, economy, and product review complete; the
  approved implementation must retain the legacy bridge until separately
  retired.
