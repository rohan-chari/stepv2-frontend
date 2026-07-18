# Home and Races Refresh Performance - Requirements & Implementation Spec

**Repos:** `stepv2-frontend` (Flutter, iOS and Android) and `stepv2-backend`
(Node/Express, Prisma/Postgres).
**Date:** 2026-07-17
**Status:** Draft complete; implementation requires explicit approval.
**Build model:** contract first, backend compatibility first, tests first. Backend
deploys before the app. iOS and Android ship in lockstep.

---

## 1. Summary and user story

Home and Races pull-to-refresh become progressively slower for users who belong
to many active races. The current work grows with race count and participant
count in several places, and both screens await non-critical discovery/catalog
requests before dismissing the refresh indicator.

> As a highly active racer, I want Home and Races to refresh promptly regardless
> of how many races I have joined, so I can see my latest steps and race state
> without the app appearing stuck.

This project reduces database amplification, response volume, network round
trips, synchronous race-reconciliation work, and Flutter build/layout work. It
must not change race scoring, powerup awards, settlement, payout, or old-client
behavior.

## 2. Current behavior and problem statement

### 2.1 Home pull-to-refresh today

`MainShell._refreshHomeTabInner` starts five branches concurrently:

1. Local daily and hourly health reads.
2. `POST /steps`, followed by `POST /steps/samples` when nonzero hourly samples
   exist, then `GET /friends/steps` and `GET /auth/me`.
3. `GET /shop/catalog`.
4. `GET /home/race-card?homeActiveRaces=1&localDate=...`.
5. Standalone `GET /daily-reward/status` and
   `GET /users/me/step-milestones/today` widget refreshes.

The common case is eight API requests. The indicator waits for all branches.
The two reward requests duplicate data embedded in the current home race-card
response. The home race-card computes live totals for every accepted participant
in up to five active races.

Step upload performs one race-resolution pass. That pass loads every active race
for the uploader and recomputes every accepted participant, although only the
uploader supplied new health data.

### 2.2 Races pull-to-refresh today

The shell starts `GET /races` and `GET /friends/steps` together. After `/races`
returns, it awaits `GET /races/featured`, then awaits `GET /races/public` merely
to count the returned rows. `GET /tournaments/public` starts fire-and-forget only
after those calls settle.

`GET /races` loads deep participant/user/accessory data and then, for each active
powerup race, serially performs an active Detour lookup, queued-powerup count,
and slot inventory lookup. Current active and pending race lists are uncapped.

The Flutter Races screen places the complete content tree in one
`SliverToBoxAdapter`, eagerly building every expanded active/pending card.

### 2.3 Static performance hypotheses

No production data is required for this spec. The highest-confidence costs from
source inspection are:

- race-list N+1 queries proportional to active powerup-race count;
- step reconciliation proportional to active races times participants;
- home-card live recomputation proportional to participants in the five cards;
- complete public-race payload transfer when only a count is consumed;
- duplicate reward/milestone calls and repeated full shop-catalog transfer;
- serialized discovery calls and overlapping `_fetchRaces` invocations; and
- eager Flutter widget construction for long race lists.

## 3. Goals and success measures

### 3.1 Functional goals

- A Home pull shows the locally read step total immediately after persistence
  succeeds and normally waits only for uploader-scoped race totals and box state,
  not friends, profile, shop, or full-field reconciliation.
- A Races pull waits only for the user's core race list. Discovery and friends
  update in the background without blanking existing content.
- Race list, race detail, powerup inventory, placement, results, and payout
  behavior remain functionally identical.
- Repeated refresh/reveal/resume triggers coalesce rather than overlap.
- Missing new endpoints or fields always fall back safely.

### 3.2 Measurable performance requirements

All measurements use local or staging synthetic fixtures, never production data.

- `GET /races` must have a bounded query count independent of the user's active
  powerup-race count. A fixture increase from 1 to 50 active races must not add
  per-race Detour, queue-count, or slot-inventory queries.
- `/races` must not load participant equipped-accessory/shop-item relations for
  ordinary list summaries.
- New-client Home performs one step-sync request and one home-batch request on
  the awaited network path. Standalone reward endpoints run only as old-backend
  fallbacks.
- New-client Races performs one awaited request (`GET /races`) and at most one
  background discovery request per refresh generation.
- Repeated pulls while a Home or Races refresh is in flight share the same Future.
- The Races UI lazily builds list rows. Initial build work is bounded by visible
  rows plus framework cache extent, not total list size.
- On a staging fixture with 50 active races, 10 completed races, and 10 accepted
  participants per race, the optimized synchronous phases must reduce median
  `/races` duration by at least 50% versus a pre-change baseline captured on the
  same machine/database. Absolute staging target: median <= 750 ms and p95 <=
  1.5 s over 30 sequential requests after five warmups.
- For async-capable clients, `POST /steps/sync-v2` must acknowledge persisted step
  data with median <= 500 ms and p95 <= 1 s on the same fixture. Background job
  completion target is p95 <= 5 s. These targets exclude device HealthKit/Health
  Connect read time.

Targets are release gates, not promises that justify skipping correctness tests.
If staging hardware cannot meet an absolute target, record the baseline and
results in the PR and require the relative improvement plus no regression in
the other targets before changing a target in this document.

## 4. Scope and non-goals

### In scope

- Lean and bulk backend query paths for race lists.
- Cached-total home race cards.
- Parallel internal query execution where independent.
- A consolidated discovery-summary endpoint.
- Coalesced/stale-while-revalidate frontend refresh orchestration.
- Home batch consumption without guaranteed duplicate endpoint calls.
- Session/TTL shop catalog caching and explicit invalidation.
- Lazy Races slivers.
- User-scoped race reconciliation.
- A durable, database-backed async race-resolution queue and sync endpoint.
- Additive timing/diagnostic metadata and synthetic benchmarks.
- Defensive fallback for older backend deployments.

### Non-goals

- Changing scoring math, race duration, settlement, payouts, powerup rules, box
  thresholds, or tournament rules.
- Removing or changing any existing endpoint or existing JSON field.
- Silently capping active or pending races for existing clients.
- Paginating active/pending races in this release. This remains a later option if
  payload size is still material after lean serialization.
- Changing the five-card Home product limit.
- Adding Redis or a new hosted queue dependency. The first durable queue uses
  Postgres, which is already operational infrastructure.
- Running analysis or tests against production data.
- Treating an in-process unawaited Promise as a durable background job.

## 5. Locked product and architecture decisions

| ID | Decision |
|---|---|
| D1 | Existing endpoints and their response fields remain supported indefinitely for shipped clients. |
| D2 | Low-risk query, request-orchestration, and lazy-rendering work ships before async step resolution. |
| D3 | Races pull completion means the core personal race list settled. Discovery and friends are stale-while-revalidate. |
| D4 | Home pull completion means health data was read and persisted, uploader-scoped race totals/box state completed (or explicitly returned `DEFERRED`), and the home batch settled. Friends/profile/shop and full-field reconciliation are not indicator blockers. |
| D5 | The current `/home/race-card` remains the home batch and keeps its old-backend fallback behavior. |
| D6 | New APIs are additive. Only a `404` causes a once-per-session capability downgrade. A malformed response falls back for that request, retains cached UI data, and remains observable as a contract error. |
| D7 | Async work is Postgres-backed, coalesced per user, restart-safe, retryable, and protected by a kill switch. |
| D8 | Old clients keep synchronous `/steps` and `/steps/samples` semantics. Only the new `/steps/sync-v2` endpoint opts into deferred reconciliation. |
| D9 | Sync-v2 updates the uploader's participant totals and box/powerup state in-band. The durable worker then runs the existing full-field reconciliation semantics for cross-participant effects/events. The existing five-minute placement job remains a full-field safety net. |
| D10 | Race-list reads use persisted participant totals. Home uses persisted totals only when the new client explicitly sends `homePersistedTotals=1`; clients without that opt-in retain today's live-computation path. Reads never write participant totals. |
| D11 | Shop catalog cache TTL is 15 minutes per authenticated session, invalidated immediately after purchase, equip, character change, sign-out, or release-channel change. |
| D12 | No production rollout is authorized by approval of this spec or implementation. Production deploy requires a separate explicit confirmation. |
| D13 | Hourly health buckets retain the existing platform aggregate semantics but execute with bounded concurrency of four; the separate daily aggregate remains authoritative. |
| D14 | New-client persisted-total Home cards guarantee the uploader is current but may initially show cached rival totals. Job-success refresh normally closes the gap within five seconds; the existing five-minute placement job is the worst-case safety net. This bounded rival-staleness tradeoff applies only to opted-in new clients and is accepted for refresh speed. |

## 6. API contract

### 6.1 Existing `GET /races` - contract unchanged

Request and response remain exactly compatible:

```http
GET /races
Authorization: Bearer <session token>
X-Client-Features: ...
```

```json
{
  "active": [],
  "pending": [],
  "completed": [],
  "tournaments": []
}
```

`tournaments` remains conditional on the existing `tournaments` capability.
All existing race-summary fields remain present with their current defaults.
The implementation changes only how those values are loaded:

- use an explicit lean race/participant select;
- fetch viewer Detour state for all relevant participant IDs in one query;
- fetch viewer slot/queued inventory for all relevant participant IDs in one
  query and group in memory;
- compute summaries without participant accessory relations;
- start `getRaces` and `getTournamentsForUser` concurrently when tournaments are
  supported; and
- retain the completed-race cap of 10 and uncapped current-race behavior.

Errors remain:

- `401` existing authentication error shape;
- `500 {"error":"Internal server error"}`.

### 6.2 New `GET /races/discovery-summary`

Purpose: replace three background calls used by the Races screen with one compact
request. It does not replace the full Public Races/Tournaments screens.

```http
GET /races/discovery-summary
Authorization: Bearer <session token>
X-Client-Features: characters,team_races,tournaments,...
```

Success `200`:

```json
{
  "publicRaceCount": 12,
  "featuredRaces": [
    {
      "raceId": "uuid",
      "seedKind": "DAILY_10K",
      "name": "Daily 10K",
      "endsAt": "2026-07-18T04:00:00.000Z",
      "participantCount": 42,
      "maxParticipants": 100,
      "isFull": false,
      "powerupsEnabled": true,
      "finishReward": {"pool": 500, "paidPlaces": 10},
      "myStatus": "ACCEPTED",
      "upcoming": null
    }
  ],
  "featuredTournaments": [],
  "resolved": {
    "publicRaceCount": true,
    "featuredRaces": true,
    "featuredTournaments": true
  }
}
```

Rules:

- `featuredRaces` entries use the existing `/races/featured` summary shape.
- `featuredTournaments` entries use the existing
  `/tournaments/public.featured` summary shape.
- Missing capability means the corresponding array is `[]`; team races and
  tournaments remain hidden under existing feature-token rules.
- `publicRaceCount` applies the same visibility, membership, capacity, seed, and
  team-race rules as `/races/public`, but does not serialize race cards.
- The three computations run concurrently and independently. One failed optional
  computation logs an error, returns its safe default (`0` or `[]`), and marks
  only that `resolved` key `false` while the endpoint remains `200`. The frontend
  commits a field only when its value has the correct type and its `resolved` key
  is `true`; otherwise it retains the last known value.
- Authentication failure remains `401`. Only failure of the route as a whole is
  `500 {"error":"Internal server error"}`.

Old-backend behavior: `404` is expected. The app marks discovery-summary as
unsupported for the session and asynchronously falls back to the existing
featured/public/tournament calls. A missing, null, or wrong-typed field uses the
last known value, or `0`/`[]` if none exists.

### 6.3 Existing `GET /home/race-card` - additive opt-in, shape preserved

No request or field is removed. Add optional `homePersistedTotals=1`. Only when
both `homeActiveRaces=1` and `homePersistedTotals=1` are present are active race
entries built from persisted `RaceParticipant.totalSteps` rather than recalculating
live health windows for every participant. Top-three, viewer placement, team totals,
Stealth masking, Detour masking, character data, and the maximum five cards keep
their current response shape.

Clients that omit `homePersistedTotals` retain the existing live-computation path,
including frozen old app binaries. An old backend ignores the new query parameter
and also retains live computation. The new app sends the parameter only after a
successful sync-v2 response whose `uploaderReconciliation.state` is `CURRENT`. If
that state is `DEFERRED`, it fetches the batch without the parameter, deliberately
using the existing live-computation fallback so a stale own-progress card cannot
replace good UI.

`stepMilestones`, `dailyReward`, and `globalEvent` remain additive and default-safe.
The frontend consumes them after every successful batch. It calls standalone
endpoints only when the field is absent/invalid, never merely because a pull
occurred.

### 6.4 New `POST /steps/sync-v2`

Purpose: persist the daily total and optional hourly samples in one request,
synchronously update the uploader's own persisted race totals and box/powerup
state, then enqueue durable full-field reconciliation for cross-participant
effects/events. This endpoint alone opts into deferred full-field semantics.

```http
POST /steps/sync-v2
Authorization: Bearer <session token>
Content-Type: application/json
Idempotency-Key: <client-generated UUID>
```

Request:

```json
{
  "date": "2026-07-17",
  "steps": 12345,
  "samples": [
    {
      "periodStart": "2026-07-17T13:00:00.000Z",
      "periodEnd": "2026-07-17T14:00:00.000Z",
      "steps": 731
    }
  ]
}
```

Validation and persistence reuse the existing `/steps` and `/steps/samples`
rules, including manual-sample rejection and overlap cleaning. Each sample accepts
the existing optional `sourceName`, `sourceId`, `sourceDeviceId`, `deviceModel`,
`recordingMethod`, and JSON `metadata` fields. Unknown top-level fields are ignored
for forward compatibility. `samples` is required as an array but may be empty.
`steps` is a non-negative integer. `date` is `YYYY-MM-DD`. The idempotency key must
be a canonical UUID string and is capped at 36 characters. Maximum 48 samples and
maximum encoded request body 64 KiB.
The app-wide JSON parser keeps its current outer limit; add a JSON error handler
for `entity.too.large` so an oversized body consistently returns the `413` contract
below rather than Express's default HTML response.

Success `202`:

```json
{
  "record": {
    "id": "uuid",
    "userId": "uuid",
    "date": "2026-07-17T00:00:00.000Z",
    "steps": 12345,
    "stepGoal": 5000
  },
  "sampleCount": 9,
  "uploaderReconciliation": {
    "state": "CURRENT",
    "resolvedRaceCount": 18,
    "boxStateCurrent": true
  },
  "raceResolution": {
    "jobId": "uuid",
    "generation": 14,
    "state": "QUEUED",
    "requestedAt": "2026-07-17T18:22:10.000Z"
  }
}
```

`uploaderReconciliation.state` is `CURRENT` or `DEFERRED`. On the normal path,
sync-v2 calculates and persists only the uploader's totals in each active race,
using the request timezone, and runs `syncRacePowerupState` for that uploader
before returning `CURRENT`. This keeps the uploader's Home progress and newly
earned mystery boxes current in the same pull. It does not run trail-mine
activation, overtake detection, rival writes, placement pushes, or other cross-
participant work in-band.

If uploader reconciliation fails after step/sample persistence, the endpoint still
returns `202` with `state: "DEFERRED"`, `resolvedRaceCount: 0`, and
`boxStateCurrent: false`; the already-queued full job owns recovery. The client
uses the live home-card fallback described in Section 6.3 and does not claim box
state is current. This degraded state is logged and counted against the queue/SLO
metrics. Daily-reward ad extra-spin state is not created by step reconciliation
and is unaffected; the timing guarantee here applies to race mystery boxes and
queued race powerups.

Idempotency:

- The first valid request for a key persists data and returns `202`.
- Reusing the same key with canonically equivalent normalized input returns the stored
  response with `202` and does not increment the queue generation.
- Reusing the key with different normalized input returns
  `409 {"error":"Idempotency key already used","code":"IDEMPOTENCY_CONFLICT"}`.
- Concurrent requests with different keys coalesce into the one per-user queue
  row and increment its generation. The newest persisted data wins.
- Server canonicalization validates and sorts samples by `periodStart`, then
  `periodEnd`; converts timestamps to UTC ISO-8601 milliseconds; represents all
  step values as integers; recursively sorts metadata object keys; drops unknown
  top-level fields; and hashes canonical UTF-8 JSON with SHA-256.
- The client creates one immutable normalized payload per sync attempt group,
  pre-sorts samples chronologically, uses UTC ISO-8601 timestamps and integer step
  values, and reuses that exact object and idempotency key for its one retry.

Errors:

| Status | Code | Meaning |
|---|---|---|
| 400 | `INVALID_STEP_SYNC` | Invalid date, steps, samples, manual sample, sample count, or body size. |
| 401 | existing auth code/shape | Missing or expired session. |
| 409 | `IDEMPOTENCY_CONFLICT` | Key reused with different canonical input; server may already have persisted the first input. |
| 413 | `STEP_SYNC_TOO_LARGE` | Encoded request exceeds 64 KiB or the app-wide JSON-parser limit. |
| 503 | `ASYNC_DISABLED` | V2 is disabled before any persistence; client may use legacy sync. |
| 500 | omitted | Persistence or enqueue transaction failed; no success is reported. |

The protocol is deliberately two-stage so the worker cannot race ahead of the
uploader pass:

1. Transaction A upserts daily steps/samples and creates the idempotency reservation
   in `PROCESSING`, including the validated timezone. It does not enqueue yet.
2. After commit, one owner performs locked uploader reconciliation and box/powerup
   synchronization. Step events are emitted once through the reservation claim.
3. Transaction B upserts the queue generation and finalizes the idempotency row to
   `COMPLETE` with the stored response. Only then can the full worker claim it.

Concurrent same-hash replay while the first request is reconciling waits for or
reads the same idempotency result; it never starts a second uploader reconciliation.
If the process dies between transactions, expired-reservation recovery resumes the
idempotent uploader pass, then performs Transaction B. After repeated uploader-pass
failure it finalizes a `DEFERRED` response and enqueues full recovery instead of
losing the sync.

Client retry rule: on timeout, connection loss, or `500`, retry v2 once with the
same idempotency key. If that retry also fails, show/retain the existing sync error
state and do not issue legacy writes because the server may already have committed.
Legacy fallback is allowed only after a definite pre-persistence `404` or
`ASYNC_DISABLED` response. A malformed `2xx` is treated as persisted-but-status-
unknown: update the local step display, skip job polling, fetch the home batch, log
the contract error, and do not issue legacy writes.

`409 IDEMPOTENCY_CONFLICT` is also treated as persisted-but-status-unknown: never
fall through to legacy writes, fetch the live-computation home batch, and emit a
client contract diagnostic. It is a correctness alarm because the immutable retry
payload rule should make it unreachable in a conforming client.

Old-backend behavior: the app tries `/steps/sync-v2` until the first `404`, caches
"unsupported" for the authenticated session, and immediately performs the current
`POST /steps` plus optional `POST /steps/samples` flow. It must not send
`skipRaceResolution=true` based only on an unrecognized v2 request.

When `ASYNC_RACE_RESOLUTION_DISABLED=true`, the route returns its `503` before any
step, sample, idempotency, or queue write. The frontend can therefore run legacy
sync without duplicating a successful v2 persistence.

### 6.5 New `GET /steps/race-resolution/:jobId?generation=<integer>`

Purpose: optional foreground status polling. Only the authenticated owner can read
the job. `generation` is required and is the value returned by sync-v2. The Home
indicator never waits for this endpoint.

Success `200`:

```json
{
  "raceResolution": {
    "jobId": "uuid",
    "generation": 14,
    "state": "SUCCEEDED",
    "requestedAt": "2026-07-17T18:22:10.000Z",
    "startedAt": "2026-07-17T18:22:10.250Z",
    "completedAt": "2026-07-17T18:22:11.830Z",
    "retryAt": null
  }
}
```

`state` is one of `QUEUED`, `RUNNING`, `SUCCEEDED`, `FAILED`, or `SUPERSEDED`.
If the stored row has advanced beyond the requested generation, return
`SUPERSEDED` with the requested generation and current timestamps omitted/null;
the client stops polling because a newer sync owns freshness. Error detail is
never returned to the app. Missing/invalid generation returns
`400 {"error":"Valid generation is required","code":"INVALID_GENERATION"}`.
Unknown/not-owned job returns `404 {"error":"Race resolution job not found"}`
to avoid leaking identifiers.

The frontend may poll at 750 ms, 1.5 s, 3 s, and 5 s while foregrounded. It stops
on a terminal state, navigation away, pause, sign-out, or after the fourth poll.
On `SUCCEEDED`, it silently refreshes home race cards, personal races if already
loaded, and `/auth/me`; these follow-up reads are coalesced and do not show a new
indicator. On `FAILED` or timeout it keeps cached race data and catches up through
the existing placement job, foreground polling, or a later refresh.

## 7. Data model and migration

Add two tables using nullable/additive migration semantics.

### `StepSyncRequest`

```text
id UUID primary key
userId UUID not null
idempotencyKey varchar(36) not null
requestHash char(64) not null (SHA-256 hex)
resolutionTimeZone varchar(255) not null
state enum(PROCESSING,COMPLETE) not null
responseJson jsonb null
leaseExpiresAt timestamptz null
eventsEmittedAt timestamptz null
createdAt timestamptz not null default now()
updatedAt timestamptz not null
expiresAt timestamptz not null
unique(userId, idempotencyKey)
index(expiresAt)
foreign key userId -> User(id) on delete cascade
```

Rows retain for seven days. A same-hash replay of `PROCESSING` waits/polls the row
for up to the request timeout rather than repeating work. An expired processing
lease may be resumed idempotently using the already-persisted steps and reservation.
Step events are emitted only after a conditional `eventsEmittedAt IS NULL` claim,
so replay/recovery cannot emit them twice.
Cleanup runs best-effort from the worker and never affects sync correctness.

### `RaceResolutionJob`

```text
id UUID primary key
userId UUID not null unique
generation integer not null default 1
processingGeneration integer null
resolutionTimeZone varchar(255) not null
processingTimeZone varchar(255) null
state enum(QUEUED,RUNNING,SUCCEEDED,FAILED) not null
attempts integer not null default 0
requestedAt timestamptz not null
startedAt timestamptz null
completedAt timestamptz null
retryAt timestamptz null
leaseExpiresAt timestamptz null
lastErrorCode text null
createdAt timestamptz not null default now()
updatedAt timestamptz not null
index(state, retryAt)
index(leaseExpiresAt)
foreign key userId -> User(id) on delete cascade
```

Queue rules:

- Enqueue is an upsert by `userId`, increments `generation`, sets `QUEUED`, and
  preserves the stable row/job ID. It validates and stores the request's canonical
  IANA `X-Timezone` as `resolutionTimeZone`; absent/invalid input uses the same UTC
  fallback as today's request middleware.
- A worker atomically claims eligible rows with `FOR UPDATE SKIP LOCKED`, records
  `processingGeneration`, snapshots `resolutionTimeZone` into
  `processingTimeZone`, sets a 30-second lease, and commits before processing.
- Success is recorded only if `generation == processingGeneration`; otherwise the
  row returns to `QUEUED`, and the polled older generation is represented as
  `SUPERSEDED` by the status serializer.
- Retry transient failures at 1 s, 5 s, and 30 s. After three failures mark
  `FAILED`. A later enqueue resets attempts and queues the newest generation.
- Expired RUNNING leases are reclaimable. Processing is idempotent: participant
  totals are set, and existing powerup award idempotency remains authoritative.
- Every worker call into scoring passes `processingTimeZone` exactly where the
  synchronous request currently passes `req.timeZone`. Seeded races continue using
  their persisted race timezone through `raceTimeZone`; legacy null-timezone races
  use the persisted request context. A worker must never infer timezone from server
  locale, current device state, user profile, or UTC except via the existing invalid-
  header fallback.
- `ASYNC_RACE_RESOLUTION_DISABLED=true` stops new v2 requests with
  `503 {"error":"Step sync temporarily unavailable","code":"ASYNC_DISABLED"}`;
  the frontend treats this like unsupported for that request and uses legacy sync.
  Existing queued jobs continue unless `ASYNC_RACE_RESOLUTION_WORKER_DISABLED=true`.

No existing columns are removed or made required. During deploy, old backend code
continues ignoring the new tables; old clients continue using old routes.

## 8. Backend implementation plan

Implement in this order.

### Phase A - observe and lock behavior

1. Add tests that snapshot the required `/races` list fields and existing scoring,
   powerup, box, team, and tournament behavior.
2. Add test-only query-count instrumentation around Prisma calls.
3. Add `Server-Timing` entries (`auth`, `handler`, `serialize`) and structured logs
   containing route template, status, duration, response bytes, race-count bucket,
   and request ID. Never log token, display name, email, exact step count, race
   name, or response body.
4. Create a local/staging fixture generator for 1/10/50 active races and 2/10
   participants. It must refuse non-local/non-staging database URLs.
5. Add the JSON `entity.too.large` error serializer before adding sync-v2; verify
   all existing normal-size JSON routes are unchanged.

### Phase B - shape-preserving race read optimization

1. In `src/models/race.js`, add `findSummariesForUser` with an explicit select.
   Keep `findForUser` unchanged for other callers until references are audited.
2. Add bulk model methods:
   `RaceActiveEffect.findActiveByTypeForParticipants(participantIds, type)` and
   `RacePowerup.findInventoryForParticipants(participantIds, statuses)`.
3. Refactor `src/queries/getRaces.js` to group bulk results by participant ID and
   serialize the exact old JSON shape. No database await is permitted inside the
   per-race serialization loop.
4. Run tournament lookup concurrently in `src/routes/races.js`.
5. Add `getPublicRaceCount` using a database count/aggregate query with the same
   filters as `getPublicRaces`; do not load/serialize full public cards.
6. Add `getRaceDiscoverySummary` and its route. Run its three branches concurrently
   with isolated safe defaults.
7. Enable standard gzip Express response compression for compressible JSON responses
   above 1 KiB. Preserve bodies/statuses, set `Vary: Accept-Encoding`, and verify
   Dart `HttpClient.autoUncompress` transparently decodes gzip. Do not advertise or
   require Brotli for this client contract.

### Phase C - home read and reconciliation optimization

1. Add the `homePersistedTotals` opt-in to `checkActiveRaces` in
   `getHomeRaceCard.js`. The opt-in path uses persisted totals and bulk active-
   effect reads; the omitted/false path remains today's live computation. Preserve
   response masking and ordering in both paths.
2. Extract a narrowly scoped `reconcileUploaderRaces({userId,timeZone})` service.
   It calculates/writes only that accepted, non-forfeited participant in each
   active race and runs `syncRacePowerupState` for that uploader. It explicitly
   does not evaluate trail mines, overtakes, rival totals, or placement events.
3. Keep `resolveRaceState` full-field behavior for worker, legacy, expiry/detail,
   and placement-job callers. The async worker invokes the full existing resolver
   with its persisted request timezone, then performs existing powerup-state and
   overtake-nudge work in the same order as today's synchronous path.
4. Add `withRaceResolutionLock(raceId, callback)`, backed by a Postgres transaction-
   scoped advisory lock derived from the race UUID. Uploader-scoped reconciliation,
   async full reconciliation, legacy full reconciliation, and placement recompute
   all use the same lock before reloading/mutating that race. Process race IDs in
   stable sorted order to avoid deadlocks.
5. The uploader pass and later full pass are intentionally two stages. The first
   guarantees own progress/box timing; the locked full pass is the sole owner of
   cross-participant effects/events. It recomputes all accepted participants from
   source data, so simultaneous crossings are evaluated using the current full
   field rather than an uploader-plus-stale-rivals approximation.

### Phase D - v2 step sync and durable worker

1. Add the migration and Prisma models.
2. Add `recordStepSyncV2` with the two-transaction reservation/finalization protocol,
   canonical hashing, persisted timezone, and expired-reservation recovery.
3. Add `POST /steps/sync-v2` and the owner-only status endpoint.
4. Add `src/jobs/raceResolutionQueue.js`; register it in `src/index.js` after the
   existing cron startup delay. Poll every 250 ms, claim one job at a time, and
   default to one concurrent job per process to protect the DB pool. Allow a bounded
   `ASYNC_RACE_RESOLUTION_CONCURRENCY` override of 1-2 after staging verification.
5. The worker runs locked full-field reconciliation with `processingTimeZone`, then
   existing uploader powerup sync and overtake nudging. Add lease recovery, retry,
   cleanup, both kill switches, and structured metrics.
6. Do not remove synchronous resolution from legacy commands.

### Expected backend file map

- Modify: `prisma/schema.prisma`, `src/app.js`, `src/index.js`,
  `src/routes/steps.js`, `src/routes/races.js`, `src/models/race.js`,
  `src/models/racePowerup.js`, `src/models/raceActiveEffect.js`,
  `src/queries/getRaces.js`, `src/queries/getHomeRaceCard.js`,
  `src/services/raceStateResolution.js`, and the relevant startup tests.
- Add: one additive Prisma migration, `src/commands/recordStepSyncV2.js`,
  `src/services/reconcileUploaderRaces.js`,
  `src/services/withRaceResolutionLock.js`, `src/queries/getPublicRaceCount.js`,
  `src/queries/getRaceDiscoverySummary.js`, and
  `src/jobs/raceResolutionQueue.js`.
- Add focused unit/HTTP/job/integration tests under the matching `test/` folders;
  do not replace existing coverage.

## 9. Frontend implementation plan

### 9.1 API service

In `lib/services/backend_api_service.dart`:

- add `recordStepSyncV2`, `fetchRaceResolutionStatus`, and
  `fetchRaceDiscoverySummary`;
- extend `fetchHomeRaceCard` with `usePersistedTotals` defaulting false; serialize
  `homePersistedTotals=1` only when true;
- add session-scoped support states `unknown/supported/unsupported` for each new
  endpoint;
- mark unsupported only on `404`, not timeout/500;
- retry sync-v2 once with the same idempotency key on timeout/connection/500;
- treat malformed sync-v2 success JSON as persisted-but-status-unknown and never
  follow it with a legacy write; malformed discovery JSON retains last-known data;
- treat `IDEMPOTENCY_CONFLICT` as persisted-but-status-unknown, emit diagnostics,
  use the live home-card path, and never issue legacy writes;
- use legacy sync only after definite 404 or pre-persistence `ASYNC_DISABLED`, and
  do not cache transient/malformed failures as unsupported;
- parse every new field by type with safe defaults;
- preserve the current legacy methods; and
- clear capability/cache state on sign-out, authenticated-user change, or backend
  base URL change; ordinary session-token rotation does not clear it.

JSON decoding remains on the main isolate initially. After response slimming and
lazy rendering, move `/races` decoding to `compute` only if the synthetic 50-race
profile still shows a frame-budget violation; do not add isolate complexity without
that evidence.

### 9.2 Home refresh orchestration

First, refactor `HealthService.getHourlySteps` to construct all hourly windows and
evaluate them with a maximum of four platform aggregate calls in flight. Return
samples in chronological order, continue excluding null/zero buckets, and preserve
the current iOS dedup/manual-exclusion and Android aggregate-minus-manual semantics.
If either platform proves unstable under concurrency in platform tests, use a
platform-specific bound of two; do not revert to unbounded concurrency.

Refactor `MainShell` into these stages:

1. Coalesce on the existing `_homeRefreshInFlight` Future.
2. Read daily and hourly health data.
3. Try `POST /steps/sync-v2` with one immutable normalized payload and a fresh
   idempotency key. On endpoint `404` or `ASYNC_DISABLED`, use the existing legacy
   sync flow. On ambiguous failure, retry only v2 once with the same payload/key.
4. Update `_stepData` immediately after persistence success.
5. When uploader reconciliation is `CURRENT`, fetch and await `/home/race-card`
   with `homePersistedTotals=1`. When it is `DEFERRED`, conflicted, or status-unknown,
   omit the parameter and use the backend's existing live-computation path. In both
   cases the post-persistence ordering ensures milestones use the new daily total.
6. Complete the refresh indicator.
7. Fire background, coalesced refreshes for `/auth/me` and friends. Fetch shop only
   when cache is absent/expired. Start bounded job-status polling when v2 returned
   a job.

Extract the persistence work into one shared `_syncSteps` orchestration used by
initial load, app resume, the five-minute foreground poll, and manual Home pull.
Initial load/resume and manual pull also fetch the home batch after persistence;
the five-minute poll preserves today's narrower behavior and does not fetch the
home batch unless job completion changes an already-loaded home race surface.

Remove direct streak/milestone `refresh()` calls from the normal pull. After the
home batch lands, widgets consume `dailyReward` and `stepMilestones`. Their existing
standalone fallback remains active only when the batch field is absent/invalid.

Failures:

- Local health failure keeps existing error presentation and skips persistence.
- Step persistence failure retains previous server-derived surfaces and shows the
  existing step-sync error; it must not claim the refresh succeeded.
- Home batch failure keeps its last known card and reward state; because steps were
  persisted, the indicator may finish with the card's non-critical error behavior.
- Background refresh or job-status failure never replaces successful cached data
  with an empty state.

### 9.3 Shop cache

Add an in-memory authenticated-session cache owned by `MainShell`:

- TTL 15 minutes from successful fetch;
- deduplicate in-flight catalog requests;
- stale data may render while a refresh runs;
- invalidate after purchase/equip/character change, sign-out, auth-user change, or
  release-channel change; and
- do not persist catalog JSON across app launches in this project.

### 9.4 Races refresh orchestration

1. Add `_racesRefreshInFlight` and make tab reveal, pull, route-return, Home initial
   load, and profile-triggered race refresh share it when overlapping.
2. The pull awaits only `GET /races` and commits its generation if it is still the
   newest request.
3. Start one background discovery-summary fetch. On a cached 404 capability result,
   start the legacy discovery calls in parallel, never serially.
4. Refresh friends only if friend data is absent, older than 60 seconds, or a friend
   mutation invalidated it. Never await it from a Races pull.
5. Retain last-known featured/public/tournament values on background failure.
6. Guard state commits with request generations so a slower old response cannot
   overwrite a newer refresh.

For discovery-summary, commit each field only when its `resolved` bit is true. A
partial backend failure must not turn a previously nonzero public count into zero
or erase previously loaded featured content.

Split today's `_fetchRaces` into core-list and discovery methods. Initial Home load
may await the core list because result-modal detection consumes completed races,
but it must not await discovery. Result-modal ordering and acknowledgment behavior
remain unchanged.

### 9.5 Lazy Races UI

Replace the single `_buildContent()` `Column` inside `SliverToBoxAdapter` with a
`CustomScrollView` composed from:

- fixed/header `SliverToBoxAdapter` sections;
- featured horizontal row adapters;
- a `SliverList.builder` per expanded race section; and
- collapsed section headers that instantiate no child race cards.

Preserve card order, keys, animations, scroll position, pull-to-refresh physics,
accessibility semantics, and all current empty/error/loading states. Do not paginate
active/pending data or change completed-history product behavior in this release.

### Expected frontend file map

- Modify: `lib/services/backend_api_service.dart`, `lib/services/health_service.dart`,
  `lib/screens/main_shell.dart`, `lib/screens/tabs/races_tab.dart`,
  `lib/widgets/streak_chip.dart`, and `lib/widgets/step_milestones_section.dart`.
- `main_shell.dart` exclusively owns Home/Races orchestration changes: core/discovery
  splitting, `_racesRefreshInFlight`, generations, TTLs, v2 fallback, and polling.
  `races_tab.dart` remains presentational and changes only for Section 9.5's lazy
  sliver construction.
- Add small typed response/cache helpers under `lib/models/` or `lib/services/`
  only where they remove dynamic parsing from `MainShell`; avoid a new state
  management framework.
- Add focused tests beside the existing health, backend API, tab refresh, Home,
  and Races tests.

### 9.6 Operational observability

Expose/log non-PII aggregates for v2 request duration, queue depth, oldest queued
age, running leases, retry count, failed jobs, superseded generations, jobs per
minute, and reconciliation duration bucketed by active-race count. Alerting or
manual rollout checks must disable async intake if oldest queued age exceeds 30
seconds for five consecutive minutes or failed jobs exceed 1% over 15 minutes.
The worker-disabled kill switch is for emergency load control; the intake-disabled
switch is the normal rollback because it gives clients a definite legacy fallback.

## 10. Backward compatibility and rollout

### Compatibility matrix

| Client | Old backend | New backend |
|---|---|---|
| Old app | Existing synchronous step routes and existing race/discovery routes continue unchanged. | Same synchronous behavior, JSON, and live-computed Home rival freshness; benefits from shape-preserving race-list query optimization and gzip when advertised. |
| New app | v2/discovery endpoints 404, capability caches unsupported, app uses legacy flow and defensive batch/live-home fallbacks. | Uses v2 uploader-current sync, durable full-field reconciliation, compact discovery, persisted-total Home opt-in, and lazy UI. |

### Deploy order

1. Backend Phases A-C, with no public contract removal.
2. Validate unit/integration and synthetic staging benchmarks.
3. Backend Phase D with `ASYNC_RACE_RESOLUTION_DISABLED=true` initially.
4. Deploy backend to staging and exercise v2 queue/lease/retry behavior.
5. Enable v2 on staging; verify legacy endpoints simultaneously.
6. Build and verify both iOS and Android against staging.
7. Separately request explicit production deployment approval.
8. Deploy backend first. Keep async disabled initially; internal optimizations and
   discovery endpoint are immediately safe for old clients.
9. Enable async for staging/prod server only after queue health is verified. The old
   app cannot call v2, so it remains synchronous.
10. Release iOS and Android together. During phased rollout, both flows coexist.

Rollback:

- Disable async v2 with the kill switch; new apps fall back to legacy sync on 503.
- Disable only the worker to stop DB load while preserving queued rows; use this
  only briefly because clients will observe queued/timeouts.
- Frontend discovery failures retain last-known values and fall back on 404.
- Never roll back the additive migration during a mixed-version window.

## 11. Test plan - tests must be written first

Existing tests must not be modified or deleted to force a pass. Add new tests,
then implement.

### Backend unit/query tests (`npm run test:unit`)

- `getRaces` returns every existing summary field and defensive default.
- Query-count test proves 1 versus 50 active powerup races does not add per-race
  effect/inventory queries.
- Bulk inventory correctly distinguishes queued boxes, mystery boxes, and held
  powerups per participant.
- Detour masking, team totals, completed results, tournament exclusion, payout
  tiers, and old-client team filtering remain unchanged.
- `getPublicRaceCount` matches `getPublicRaces(...).length` across membership,
  full/unlimited, seeded pending, review-account, team-feature, and tournament cases.
- Discovery-summary isolates branch failures and applies safe defaults.
- Discovery `resolved` bits prevent partial failures from erasing last-known values.
- Home cached-total serialization preserves top-three ordering, Stealth/Detour,
  character gating, team blocks, invites, and five-card limit.
- Home requests without `homePersistedTotals=1` retain the live-computation path;
  opt-in requests use stored totals without changing JSON.
- Uploader-scoped reconciliation writes only the uploader, uses the supplied IANA
  timezone, updates race mystery-box/powerup state in-band, and does not emit any
  cross-participant event.
- Queue enqueue/claim persists and snapshots timezone per generation; seeded races
  retain race timezone and null-timezone races use the request timezone exactly as
  the synchronous path does.
- Full worker reconciliation preserves trail-mine, global-event, forfeit, overtake,
  and placement behavior. Adversarial fixtures cover two users crossing the same
  mine boundary before either job runs, reverse job order, duplicate job delivery,
  and a placement-job overlap; each event fires at most once and final state matches
  one serialized execution of today's full resolver.
- Advisory locking serializes uploader, worker, legacy, and placement resolution for
  the same race without deadlocking across multi-race users.
- Other full reconciliation callers remain behaviorally unchanged.
- V2 validation, 64 KiB/JSON-parser rejection, canonical idempotency hashing,
  same-key replay, conflict, empty samples, overlap cleaning, manual rejection,
  and transaction rollback.
- Idempotency PROCESSING replay, lease recovery, canonical sample/key ordering, and
  a deliberately changed retry payload yielding conflict without a legacy write.
- Queue generation is created only during idempotency finalization; a worker cannot
  run before the uploader pass, and crash recovery between Transactions A/B resumes
  or safely defers without losing the persisted sync.
- Queue coalescing, generation supersession, lease recovery, retry schedule,
  terminal failure, later requeue, multi-worker `SKIP LOCKED`, cleanup, and kills.
- Status endpoint generation validation, superseded generation behavior, ownership,
  and non-leaking 404 behavior.
- Gzip and uncompressed `/races` responses have identical decoded JSON and include
  correct `Vary` behavior; Brotli is not part of the app contract.
- Startup registers the worker after the cron delay and respects kill switches.

### Backend integration tests (`npm run test:integration`)

Run only against the dedicated local `steps-tracker-integration` database after
confirming its URL.

- Old `/steps` and `/steps/samples` still synchronously update race state.
- V2 returns 202 only after uploader totals and race box state are current on the
  normal path; cross-participant work completes later.
- A forced uploader-pass failure returns `DEFERRED`, and the full job restores the
  same final totals/boxes as legacy sync using the persisted request timezone.
- V2 replay is idempotent and concurrent requests converge on newest data.
- Newly crossed race mystery boxes are visible to the immediate post-202 profile/
  race reads; daily-reward ad extra-spin state remains unrelated and unchanged.
- Final race totals/effects after worker completion equal the legacy flow for the
  same timezone-sensitive fixture.
- Pre-optimization and post-optimization `/races` responses retain equivalent
  existing fields.
- Discovery count matches the full public list.
- Migration deploy works with old backend code and existing rows.

### Frontend tests (`flutter test`)

- Home v2 success request order: health -> sync-v2 -> home batch; indicator does
  not await profile/friends/job status.
- Home 404 fallback invokes the legacy endpoints exactly once and caches support;
  async-disabled 503 falls back without duplicate persistence.
- Sync-v2 transient retry reuses the same key; malformed/lost success never triggers
  a legacy write.
- Retry payload samples are immutable/canonical; 409 conflict is treated as
  persisted-unknown and never triggers a legacy write.
- `CURRENT` requests fetch Home with `homePersistedTotals=1` and immediately show
  the uploader's new race total. The same pull's subsequent profile/race reads see
  current race-box state; this does not add a new box element to Home. `DEFERRED`
  requests omit the flag and use live computation.
- Home batch fields suppress standalone reward/milestone requests; absent fields
  trigger one fallback each.
- Shop TTL, in-flight dedupe, invalidations, stale rendering, and sign-out clearing.
- Race pull awaits only personal races; discovery and friends complete later.
- Discovery 404 fallback calls legacy discovery in parallel and retains old values
  on failure.
- Reveal plus immediate pull coalesces; stale generations cannot overwrite new data.
- Async job poll schedule, cancellation, success refresh, failure, and timeout.
- Initial load, resume, foreground poll, and manual pull all share the same v2/legacy
  step-sync capability state without overlapping step writes.
- Hourly health reads never exceed four concurrent platform calls and return
  chronological nonzero samples identical to the sequential implementation.
- Defensive parsing for missing/null/wrong-typed new fields.
- Lazy Races sections render correct order/count, collapsed completed rows are not
  instantiated, scrolling reveals later rows, and pull-to-refresh still works.
- Existing loading/refreshing/error data remains visible and no text/layout overlap
  occurs at supported phone sizes.

### Platform verification

- iOS HealthKit and Android Health Connect both produce the v2 sample shape.
- Background/pause during job polling does not leak timers or issue requests.
- Build and smoke-test iOS and Android in lockstep.

### Synthetic benchmark

Add a documented non-production benchmark command that creates deterministic
fixtures and reports endpoint timing, response bytes, and Prisma query count. It
must abort unless the database host is localhost or an explicit staging guard is
set. Record before/after results in the implementation PR; do not commit generated
fixture data.

## 12. Acceptance criteria / definition of done

- [ ] No existing endpoint or field is removed, renamed, or made newly required.
- [ ] Old apps retain synchronous step-resolution behavior on the new backend.
- [ ] New apps fall back correctly against an old backend.
- [ ] `/races` has no database await inside its per-race serialization loop.
- [ ] `/races` query count is bounded under the 1/50-race test.
- [ ] Public race count no longer requires transferring full public race cards to
      the Races tab.
- [ ] Partial discovery failures retain last-known values via `resolved` flags.
- [ ] Home pull has no guaranteed duplicate reward/milestone requests.
- [ ] Hourly device health reads use bounded concurrency and preserve totals/order.
- [ ] Home and Races refreshes coalesce overlapping triggers.
- [ ] Non-critical work does not hold either refresh indicator open.
- [ ] Home persisted-total cards are new-client opt-in; old clients retain live
      computation and existing rival freshness.
- [ ] Opted-in Home cards show the uploader's current total/box state immediately,
      preserve masking/team behavior, and silently refresh cached rivals on job
      success.
- [ ] V2 step sync persists and completes normal uploader-scoped totals/box sync
      before acknowledging, then uses a durable queue for full-field work.
- [ ] Ambiguous v2 outcomes retry idempotently and never fall through to duplicate
      legacy writes.
- [ ] Retry payload canonicalization is pinned; 409 is handled as persisted-unknown
      without a legacy write.
- [ ] Queue work is per-user, coalesced, leased, retryable, restart-safe, and
      kill-switch controlled.
- [ ] Every queue generation persists/snapshots the validated request timezone and
      timezone-sensitive fixtures match synchronous scoring.
- [ ] Same-race reconciliation is advisory-locked across uploader, worker, legacy,
      and placement paths; simultaneous mine/overtake cases match serialized full
      reconciliation without duplicate cross-participant events.
- [ ] Legacy and v2 reconciliation produce equivalent final user totals, boxes,
      inventory, and effects.
- [ ] Races lists render lazily with existing states and ordering preserved.
- [ ] Compressible JSON responses negotiate compression without changing decoded
      contracts for old or new apps.
- [ ] Staging synthetic performance targets in Section 3.2 pass and results are
      attached to the PR.
- [ ] Backend unit and dedicated-DB integration tests pass.
- [ ] Flutter tests pass and both iOS and Android builds succeed.
- [ ] No production data was used for implementation testing or benchmarking.
- [ ] Backend is ready before app rollout; production deploy still awaits explicit
      approval.

## 13. Implementation ownership and sequence

After approval, follow the repository's required two-agent implementation model:

1. Backend developer writes tests and pins Sections 6-8 in code first.
2. Once the contract is locked, backend continues Phases B-D while frontend writes
   tests and implements Section 9 against that contract.
3. Backend never changes a pinned response without updating the spec and notifying
   frontend. Frontend never invents an undeclared field.
4. Both agents preserve existing tests and report any apparent conflict instead of
   editing the old expectation away.

## 14. Open questions

None. The staged rollout, performance targets, stale-data semantics, cache TTL,
queue choice, retry policy, and compatibility behavior are explicitly locked above.

## 15. Revision log

- **Initial draft (2026-07-17):** Captured the static Home/Races request graphs,
  query amplification, payload waste, lazy-rendering work, additive API contracts,
  Postgres queue model, compatibility matrix, rollout, and tests-first plan.
- **Fresh-eyes pass 1 (2026-07-17):** Required `generation` on status polling so
  coalesced jobs can report `SUPERSEDED`; aligned the v2 body contract with the
  current Express parser and added JSON 413 behavior; clarified that only 404
  caches endpoint absence; required the async-disabled check before persistence;
  extended shared step orchestration to initial load, resume, and foreground
  polling; and separated core races from discovery so result-modal loading does
  not accidentally retain the discovery delay.
- **Fresh-eyes pass 2 (2026-07-17):** Added partial-discovery validity bits so a
  failed branch cannot erase good cached data; pinned ambiguous v2 retry/no-duplicate
  semantics; bounded and validated idempotency keys/body size; added user FKs and
  conservative worker concurrency; added response compression; clarified cache
  lifetime across token rotation; added bounded concurrent hourly health reads;
  added queue health rollback thresholds; and added exact backend/frontend file
  maps plus missing tests and acceptance gates.
- **Correctness review fold-in (2026-07-17):** Persisted and snapshotted the request
  timezone per queue generation; changed sync-v2 to update uploader totals and race
  mystery-box state before normal acknowledgment; made cached-total Home cards an
  explicit new-client opt-in so old clients retain live rival computation; assigned
  all trail-mine/overtake/cross-participant work to locked full-field worker
  reconciliation with simultaneous-crossing tests; pinned server/client canonical
  idempotency plus 409 handling and a recoverable two-transaction protocol that
  prevents the worker racing the uploader pass; clarified `main_shell.dart` versus
  presentational `races_tab.dart` ownership; narrowed compression to gzip; and
  documented the
  accepted, bounded new-client rival-staleness tradeoff. Also clarified that daily-
  reward ad extra spins are unrelated to step-sync race mystery-box awards.
