# Local-time daily 2x step event

**Status:** Implemented and independently reviewed. The feature remains
default-off and has not been deployed; production enablement requires the
rollout prerequisites in this spec and separate owner approval.

## 1. Summary and user story

The daily 30-minute 2x Race Steps event currently chooses one deterministic-
random wall-clock minute between 08:00 and 22:00 in `America/New_York`. That
single UTC window is applied to every participant worldwide. A New York user
therefore receives a daytime event, while a Madrid user can receive the same
event as late as 04:00 local time.

Change the event from one shared UTC window to one logical daily event with an
immutable, participant-specific local window. The logical event chooses one
wall-clock minute for the day; each user receives that same wall-clock minute
in their snapshotted IANA timezone. If the day's draw is 17:17, a New York user
gets 17:17 New York time and a Madrid user gets 17:17 Madrid time.

User story: as a racer anywhere in the world, I receive the same 30-minute 2x
opportunity during the configured local-time range as other racers, without
having to be awake according to New York's clock.

The authoritative score remains:

`window steps x signed participant multiplier x (global multiplier - 1)`

The event changes race score only. Mystery-box progress, raw steps, daily step
milestones, and coin-source calculations remain based on raw steps.

## 2. Goals, scope, and non-goals

### 2.1 In scope

- One logical 2x event per product event day.
- A participant-specific 30-minute UTC interval derived from one shared daily
  local wall-clock draw and that user's immutable timezone snapshot.
- Exactly one entitlement per user per logical event, even if the device
  timezone changes, the user travels, the app retries, or multiple backend
  workers process the same boundary.
- Participant-specific scoring in every live-display, reconciliation,
  settlement, attribution, summary, notification, multiplier, fingerprint,
  and boundary path.
- Viewer-specific Home and race-detail event banners using the existing
  optional `globalEvent` response shape.
- The existing `GLOBAL_EVENT_STARTED` push, sent only at that user's local
  event start.
- Existing `GlobalEventRaceImpact` and `GlobalEventUserSummary` behavior,
  aggregated under the one logical event ID across all of that user's races.
- Safe handling for missing, invalid, or newly changed timezones.
- Backend-first, flag-controlled rollout with a complete legacy-global path.

### 2.2 Explicit non-goals

- Changing the 2x multiplier, 30-minute duration, or once-per-day frequency.
- Changing the signed multiplier/powerup stacking formula.
- Changing powerup odds, prices, durations, box progress, step-milestone
  rewards, race prize-pool size, or coin minting.
- Letting users choose an event time or timezone in the app.
- Adding a new screen, moving an existing banner, or changing event artwork or
  copy in v1.
- Rewriting historical `GlobalStepEvent`, impact, or summary rows.
- Applying the local schedule to an already-started or already-materialized
  legacy event.
- Inferring residence, country, GPS position, or IP geolocation.

## 3. Current-system evidence

- `lib/services/backend_api_service.dart:442-444,4979,5019` resolves the
  device's IANA timezone and sends `X-Timezone` on ordinary API requests.
- Backend `src/middleware/extractTimezone.js:19-22` validates the header and
  falls back operationally to `America/New_York`.
- Backend `src/middleware/requireAuth.js:120-142` sticky-writes only a real,
  valid changed timezone to `users.timezone`.
- Backend `src/modules/steps/globalStepEvent.js:20-47,135-190` chooses one
  deterministic ET wall-clock minute in 08:00-22:00 and defines the current
  30-minute, 2x scoring window.
- Backend `src/modules/steps/jobs/globalStepEventScheduler.js:21-159` creates
  one row, enrolls all users in active races, enqueues global boundaries, and
  fans out the start push.
- Backend `src/modules/steps/models/globalStepEvent.js:17-192` treats every
  event row as globally eligible in active-at/range queries.
- Backend `src/modules/races/queries/getRaceProgress.js:466-726` and
  `src/modules/races/services/raceStateResolution.js:795-1068` load one shared
  event list and apply one active multiplier to the whole race field.
- Backend `src/modules/races/services/raceResolutionInputFingerprint.js:1-225`
  digests global rows and their boundaries once per race.
- Backend `src/modules/steps/services/globalEventEnrollment.js:31-58`
  atomically records event/race/user lifecycle impacts but does not currently
  decide scoring eligibility.
- Backend `prisma/schema.prisma:330-370` already relates per-race impacts and
  per-user summaries to one logical `GlobalStepEvent`.
- Flutter `lib/widgets/global_event_banner.dart` reads only multiplier and end
  time, self-expires, and needs no visual change.
- Flutter `lib/services/notification_service.dart:705-706` already routes
  `GLOBAL_EVENT_STARTED` to Home.

## 4. Product behavior

### 4.1 Logical event day and wall-clock draw

One `GlobalStepEvent` remains the logical parent for a daily event. It owns:

- a stable product event-day string (`YYYY-MM-DD`);
- the chosen local minute after midnight;
- duration and multiplier;
- schedule mode (`LEGACY_GLOBAL` or `LOCAL_ENTITLEMENTS`).

`eventDay` is a product civil-date label, not a UTC or New York day boundary.
The same label and hash input are used for every timezone. A user gets at most
one entitlement for that parent even when their local calendar date changes
during travel.

For `LOCAL_ENTITLEMENTS`, parent creation uses injected cryptographic randomness
(`crypto.randomInt` in production) to select one local minute from the
configured 08:00-22:00 range and persists it. Every timezone uses the same
persisted minute. The draw is never separately randomized per timezone and is
not recomputed from a public date hash. `LEGACY_GLOBAL` retains its existing
deterministic ET draw unchanged for compatibility.

The parent is materialized before the earliest worldwide occurrence of that
event day. At minimum, the scheduler keeps the next two logical days
materialized so UTC+14 entitlements are never created after their local start.
Its required legacy `startsAt`/`endsAt` fields form a compatibility envelope:
the earliest and latest UTC instants that the selected local window can occupy
across supported IANA zones. They are metadata only for local-mode parents and
must never enter scoring or the legacy global-boundary cursor.

Every newly created parent, including `LEGACY_GLOBAL`, stamps `eventDay`.
`eventDay` plus an event-day advisory lock is the single creation fence. A
flag change, restart, or mixed worker cannot create both a legacy and local
parent for one day. Local cutover selects the earliest civil event day whose
compatibility-envelope start is still at least 24 hours in the future anywhere
on Earth, including UTC+14; it then materializes that day plus the following
day. An outage never backfills a parent after its earliest envelope start.

### 4.2 Immutable per-user entitlement

Each logical event has at most one entitlement per user. The entitlement
persists:

- logical event ID and user ID;
- the validated timezone snapshot;
- exact UTC `startsAt` and `endsAt`;
- the local event-day string;
- processed timestamps needed for idempotent start/end boundary delivery.

The unique `(eventId,userId)` constraint is the authority for once-per-event.
No scoring path may derive an event window from the user's current request
header or current `users.timezone` after the entitlement exists.

Timezone selection order when materializing an entitlement:

1. valid stable `users.globalEventTimezone`;
2. `America/New_York` for a null/invalid value.

`users.timezone` remains the device's immediate last-known zone for reminders
and calendar behavior. Event scheduling uses a separate stable zone:

- the migration backfills `global_event_timezone = timezone` for existing
  valid non-null zones; null remains null and therefore uses New York;
- a newly observed different valid `X-Timezone` becomes
  `globalEventTimezoneCandidate` with `candidateSince`;
- the candidate is promoted only after the same valid zone is observed again
  at least 48 hours later;
- candidate writes occur only when the value changes and promotion writes only
  once, never on every request;
- invalid/missing headers do not alter stable or candidate state.

This keeps legitimate longer travel/moves possible while preventing a player
from selecting tomorrow's event instant immediately before materialization.
The entitlement still snapshots the stable value and remains immutable.

A later timezone change applies only to a future logical event that has no
entitlement yet. It never moves or duplicates the current entitlement. This
prevents timezone chasing from producing multiple 2x windows.

Entitlements are materialized in bulk for users accepted into an active race,
not for every dormant account forever. The race-start, invite-accept, public-
join, share-join, and auto-enrollment transactions call one idempotent
`ensureEntitlementForUser` service for already-materialized future logical
events. It creates an entitlement only when that user's local start is still in
the future. This retains today's rule that a person who was not racing before
their opportunity does not receive a retroactive event.

### 4.3 Eligibility and race membership

An entitlement is a user's daily opportunity, not by itself a race award.
At the entitlement start boundary:

- find the user's `ACCEPTED` participation in races active at that instant;
- create `GlobalEventRaceImpact(status=PENDING)` for each affected race;
- send one start push if at least one affected race exists and the user has a
  valid device token;
- enqueue exactly those affected races for immediate full reconciliation.

If a race starts or a user becomes `ACCEPTED` during their active entitlement,
the existing transaction-locked late-enrollment hook adds the corresponding
impact row. It must match that user's active entitlement rather than the latest
globally active event.

Joining after the entitlement ends creates no impact and gives no retroactive
boost. Leaving or forfeiting does not rewrite the entitlement; existing race
settlement rules clip scoring to the participant/race window.

The boundary transaction and the late-enrollment transaction share the
existing global-enrollment advisory lock. A boundary/late-join race cannot
commit between the active-race scan and impact insertion without either path
creating the missing unique impact. A repair pass may fill a missing impact
after transient failure, but it must use the immutable entitlement interval and
must never shift the event or send a push outside the catch-up policy.

If a user's first race starts or first acceptance occurs while their stable-
timezone local window is already active, `ensureEntitlementForUser` may create
the entitlement for that currently open window, take the enrollment lock, and
insert impacts with `ACTIVATED_LATE_JOIN`. Scoring begins at
`max(entitlement.startsAt,race.startedAt,participant.joinedAt)`. This preserves
the current mid-event join behavior. It sends no retroactive start push; Home
and race detail may show the remaining countdown. After the local window ends,
no entitlement or impact is created.

### 4.4 Scoring and live standings

Scoring eligibility is per `(eventId,raceId,userId)`, backed by the entitlement
and impact row. Merely overlapping a `global_step_events` parent row is never
sufficient for a local-mode event.

Every canonical scorer receives event windows keyed by participant user ID.
For each participant:

- use every eligible legacy-global event under existing behavior;
- plus that participant's local entitlement windows for this race;
- clip to race start/end and the scoring `now` exactly as today;
- preserve `[startsAt,endsAt)` half-open boundaries;
- preserve signed powerup multiplication, freezes, reversals, Hitchhike, Leech,
  Rainstorm, and settlement/display parity.

Two participants in the same race can therefore have different active event
states and `currentMultiplier` values at the same real instant. The leaderboard
shows each participant's correct authoritative total.

The canonical interface is a plain `eventsByUserId` map whose values are
normalized event descriptors. `eventsForUser(userId)` is the only lookup seam
inside scorers and counterfactuals. There is no local-mode race-wide event
array. Fingerprints digest entitlement ID/window and the qualifying impact
ID/status, so inserting or finalizing an impact invalidates stale artifacts.

### 4.5 Banner and push behavior

`GET /home/race-card` and `GET /races/:raceId/progress` expose the existing
optional `globalEvent` object only when the authenticated viewer has an active
entitlement that affects at least one active race (Home) or the requested race
(race progress):

```json
{
  "globalEvent": {
    "active": true,
    "multiplier": 2,
    "endsAt": "2026-08-20T15:47:00.000Z"
  }
}
```

The object retains exactly the existing keys and types. It remains absent when
the viewer has no active eligible entitlement or any dependency read fails.
The frontend continues to parse it defensively and collapses the banner after
`endsAt`.

`GLOBAL_EVENT_STARTED` keeps its current push type, copy, and Home route. The
backend creates one durable delivery intent per `(eventId,userId)` only after
the event/user boundary claim succeeds. No new `startsAt` or `endsAt` push
fields are introduced; clients obtain viewer-specific timing from the existing
Home/race `globalEvent` response. Worker retries cannot create a second durable
intent, while APNs/FCM delivery remains at-least-once and can display a
duplicate after provider acceptance followed by a worker crash.

Boundary processing locks due entitlements transactionally (`FOR UPDATE SKIP
LOCKED` or the Prisma-equivalent transaction). `startProcessedAt` is set only
in the same commit that creates unique impact rows and a durable notification
delivery intent; `endProcessedAt` is set only with durable affected-race queue
intents. A worker crash before commit rolls back the claim. Delivery after
commit retries from the durable intent, so there is no claim-before-send loss
window.

Start processing has an explicit terminal outcome:

- `PENDING`: not processed;
- `ACTIVATED_ON_TIME`: at least one active-race impact and durable push intent
  created during the catch window;
- `ACTIVATED_LATE_JOIN`: a user with no earlier active race joined/started one
  during the open window; impacts exist but no retroactive push is created;
- `NO_ACTIVE_RACES`: processed on time with no active race; a mid-window join
  transitions it to `ACTIVATED_LATE_JOIN`, adds impacts/banner, and sends no
  late push;
- `SKIPPED_STALE`: first claim occurred more than two minutes after start; no
  impact, boost, banner, push, repair, or later reactivation is permitted.

`SKIPPED_STALE` applies to an entitlement that existed before its start and
whose boundary worker was missed. It does not prohibit the explicit current-
behavior late-join path for a user who had no entitlement because they had no
active race before joining during the open window.

An on-time claim may credit from the scheduled `startsAt` even if the worker is
up to two minutes late. End processing enqueues only races with impacts. A
crash-recovery or settlement repair must preserve the same state machine.

### 4.6 Completion summary

All of one user's local-mode `GlobalEventRaceImpact` rows retain the same parent
`eventId`. The existing summary worker therefore continues to aggregate extra
race steps across races into at most one `GlobalEventUserSummary` per
`(eventId,userId)`.

Summary eligibility waits only for the races actually enrolled for that user.
Other timezones' later windows cannot hold an earlier user's summary open.
Existing nonzero/mixed-net-zero eligibility, acknowledgement, cache
invalidation, and optional Home response contract remain unchanged.

The summary worker uses that user's `entitlement.endsAt`, not the parent
compatibility-envelope end. It requires the entitlement not to be `PENDING`,
the user's enrollment window to be closed, and all of that user's actual
impact rows to be `FINAL`. It preserves the current dirty branch's nonzero /
mixed-net-zero eligibility, `job_runs` fence, Home-cache invalidations, and
account-deletion order.

### 4.7 DST, date-line, and timezone changes

- Convert each local date/time with the existing IANA helpers; never add 24
  hours to the prior UTC start.
- 08:00-22:00 avoids DST's normally missing/ambiguous early-morning hour, but
  tests still pin 23-hour and 25-hour local days.
- Consecutive valid entitlements may be 23 or 25 hours apart. Do not use a
  strict rolling-24-hour cooldown as the once-per-day authority.
- A user crossing the international date line still has one entitlement for
  the already-created logical event. The new timezone affects only a later
  unmaterialized event.
- The entitlement's timezone is audit data and is never returned publicly.

### 4.8 Short-race exposure fairness

Random daily local windows can be 10-38 real hours apart. In a race lasting
about 24 hours, different timezone participants can therefore receive `0`, `1`,
or `2` overlapping opportunities even though each user still has exactly one
entitlement per logical event. The current global design gives the whole race
the same event count, so localization trades simultaneous within-race exposure
for equal waking-hour access worldwide.

There is no clean normalization that preserves all three of: the same local
wall-clock window, one event per logical day, and identical exposure in an
arbitrary short cross-timezone race. The recommended v1 policy is to accept
this boundary tradeoff, cap only by one entitlement per user/logical event, and
measure participant-race `0/1/2+` exposure in staging/production. The owner must
explicitly accepted this policy. Implementation must not invent a mixed
global/local normalization rule. Observed exposure rates are a rollout metric
and can motivate a separately specified future change.

## 5. API contract

No new public endpoint or required request parameter is introduced.

### 5.1 Existing reads

- `GET /home/race-card`: optional `globalEvent` becomes viewer-specific but
  keeps the exact existing JSON shape. `globalEventSummary` is unchanged.
- `GET /races/:raceId/progress` and the participants-v1 progress variant:
  participant totals and `currentMultiplier` use each participant's eligible
  windows; the top-level optional `globalEvent` describes only the viewer's
  entitlement for that race.
- Existing race/home/bootstrap responses that embed these projections inherit
  the same semantics without adding keys.

### 5.2 Existing mutations and notifications

- Step upload endpoints remain unchanged. `X-Timezone` remains optional and
  backward compatible.
- `POST /home/global-event-summaries/:id/acknowledge` is unchanged.
- `GLOBAL_EVENT_STARTED` payload fields and navigation behavior remain
  additive/backward compatible.

### 5.3 Errors and failure posture

- The viewer-banner overlay is fail-soft: its lookup failure omits the optional
  `globalEvent` and must not fail Home or race progress.
- Entitlement/impact loading for canonical scoring is not fail-soft. A load
  failure aborts/retries resolution without writing totals, or serves a
  previously committed snapshot without performing new scoring writes. It may
  never substitute an empty event set. Settlement likewise fails/retries.
- Scheduler/materialization failure is retried before the affected boundary.
- A missed first start claim beyond the two-minute window atomically stamps
  `SKIPPED_STALE`. It sends no push, creates no impacts, grants no historical or
  remaining boost, shows no banner, and cannot be reactivated by repair or a
  later join.
- Settlement reads Postgres directly and fails/retries under existing race
  settlement behavior; it never substitutes the viewer's timezone.

### 5.4 Viewer overlay and cache contract

Viewer-specific event state is never embedded in a shared race snapshot or
resolution artifact. After authentication, response assembly overlays the
viewer/race `globalEvent` onto the shared authoritative participant totals.
Timezone and entitlement audit fields are never serialized.

Race progress reuses the Postgres `eventsByUserId` read already required for
canonical scoring and adds no Redis lookup. Home may use one viewer-specific,
default-off cache:

- flag: `redisCacheHomeActiveGlobalEventEnabled`;
- key: environment-prefixed `v1:user:<userId>:active-global-event`;
- TTL: 30 seconds;
- value allowlist: only `eventId`, numeric `multiplier`, and `endsAt`;
- filter `startsAt <= now < endsAt` again after cache read;
- invalidate after impact creation/repair, forfeiture/removal of the viewer's
  last eligible active-race impact, and event processing transitions;
- Redis unset/error always falls back to Postgres.

Canonical scoring, fingerprints, attribution, and settlement never read this
cache.

## 6. Data model and migrations

All changes are additive and nullable/default-safe.

### 6.1 `GlobalStepEvent`

Add:

- `scheduleMode String @default("LEGACY_GLOBAL")` mapped to
  `schedule_mode`;
- `eventDay String? @unique` mapped to `event_day`;
- `localStartMinute Int?` mapped to `local_start_minute`.
- `durationMinutes Int?` mapped to `duration_minutes`.

Existing rows backfill through the database default to `LEGACY_GLOBAL`; their
`startsAt`/`endsAt` remain authoritative and every frozen client sees current
behavior. Local rows require a valid `eventDay`, `localStartMinute` in
`[480,1320)`, multiplier greater than one, and positive duration. Enforce
validation in the creation command and integration tests; add DB checks only
if they are deploy-safe under the backend migration contract.

For a local parent, `startsAt` and `endsAt` are compatibility envelope bounds
computed from the supported IANA-zone set, not from whichever users happened
to exist at creation. `durationMinutes` is 30 in v1. These fields are not
scoring authority. Every reader must branch on `scheduleMode`.

Every parent created after migration, including legacy mode, requires a unique
`eventDay`. Pre-migration historical rows remain null. Parent creation is an
upsert/locked insert by `eventDay`; `startsAt` is no longer the daily identity.

### 6.2 `GlobalStepEventEntitlement`

Add a new table/model:

- `id` UUID primary key;
- `eventId` FK to `GlobalStepEvent`, `onDelete: Restrict`;
- `userId` FK to `User`, `onDelete: Cascade`;
- `timezone` non-null string;
- `localDate` non-null string;
- `startsAt` / `endsAt` non-null timestamps;
- `startOutcome` non-null string defaulting to `PENDING`;
- `startProcessedAt` / `endProcessedAt` nullable timestamps;
- `createdAt` / `updatedAt`.

Constraints/indexes:

- unique `(eventId,userId)`;
- index `(startsAt,startProcessedAt)`;
- index `(endsAt,endProcessedAt)`;
- index `(userId,startsAt,endsAt)`;
- check `endsAt > startsAt` when migration policy permits.

No backfill is performed. Absence of entitlements for a legacy event means
legacy-global semantics.

Allowed `startOutcome` values are exactly `PENDING`, `ACTIVATED_ON_TIME`,
`ACTIVATED_LATE_JOIN`, `NO_ACTIVE_RACES`, and `SKIPPED_STALE`. State transitions
are forward-only except the explicit `NO_ACTIVE_RACES` to
`ACTIVATED_LATE_JOIN` transition.

### 6.3 Stable event timezone on `User`

Add nullable `globalEventTimezone`, `globalEventTimezoneCandidate`, and
`globalEventTimezoneCandidateSince` columns. The migration backfills
`global_event_timezone = timezone` only where the existing timezone is
non-null; this is a bounded one-time update whose exact production execution
still requires deploy approval. New candidate/promotion logic is best-effort
bookkeeping and cannot fail authentication.

### 6.4 Impact and delivery lifecycle

Do not repurpose `GlobalEventRaceImpact` into the entitlement table. It remains
the per-race attribution/summary lifecycle. Add only indexes or an optional
entitlement FK if profiling proves necessary. The logical `(eventId,userId)`
join is sufficient for v1 and preserves existing rows.

Account deletion adds entitlement deletion before deleting parent-dependent
rows. Parent events remain retained as historical shared records.

Reuse the existing Postgres `InboxAlert` + `InboxDeliveryOutbox` as the only
local-event start delivery path. In the entitlement start transaction call the
Inbox creation seam with:

```json
{
  "type": "GLOBAL_EVENT_STARTED",
  "title": "2x STEPS EVENT",
  "body": "Double steps are LIVE for 30 minutes. Every step counts 2x in your races! Go!",
  "destination": {"route": "home"},
  "sourceKey": "visible:GLOBAL_EVENT_STARTED:<userId>:<eventId>"
}
```

The unique `(userId,sourceKey)` alert and `(alertId,kind)` outbox constraints
dedupe worker retries. The existing Inbox delivery worker uses 25-row leases,
30-second leases, exponential retry capped at one hour, and 30-day alert/outbox
retention. Provider delivery is at-least-once: APNs/FCM acceptance followed by
a worker crash can cause a duplicate device notification, so the spec does not
promise exactly-once provider display. The backend does promise one durable
delivery intent.

## 7. Backend implementation plan

Implementation order is mandatory.

1. Write failing migration/model integration tests, then add the additive
   schema and migration.
2. Split pure scheduling from persistence in
   `src/modules/steps/globalStepEvent.js`:
   - retain the legacy ET decision unchanged;
   - inject a cryptographically secure logical-day random draw, execute it
     exactly once under the event-day creation lock, and persist the winning
     minute; concurrent processes and retries adopt the winning row rather
     than drawing again;
   - add exact local-date/timezone-to-UTC entitlement conversion;
   - validate schedule mode and bounds defensively.
3. Add a `globalStepEventEntitlement` model/service with bulk idempotent
   materialization and due-boundary claims. Never create one row per request.
   Add stable-timezone candidate/promotion to the existing sticky timezone
   bookkeeping without adding a per-request hot write.
4. Update `globalStepEventScheduler.js` behind a strict default-off setting:
   - keep the legacy scheduler byte-compatible while off;
   - materialize future logical parents/entitlements;
   - claim due timezone/user cohorts;
   - in bounded batches of at most 100 entitlements and a five-second tick
     budget, create race impacts, Inbox alerts/outbox rows, and
     `race_resolution_jobs_v2` intents transactionally/idempotently;
   - call `enqueueRaceResolution(..., tx)` only for affected race IDs at
     start/end;
   - hold the global enrollment lock only for the active-race scan and durable
     writes, never for provider delivery or step scoring.
5. Update `globalEventEnrollment.js`, `commitRaceStart`, invite acceptance, and
   public/share join paths so late enrollment matches each user's entitlement,
   including first entitlement creation during an already-open window.
6. Add model queries that return eligible events keyed by user and race. Keep
   `findActiveInRange`/`findActiveAt` legacy-safe; do not silently broaden their
   signatures or make a local parent globally eligible.
7. Change the canonical scorer inputs from one race-wide event array to an
   event-set resolver/map keyed by user ID. Thread it through:
   - `effectiveStepScoring.js` and `globalStepEvent.js`;
   - `getRaceProgress.js`;
   - `raceStateResolution.js` / `computeRaceState.js`;
   - uploader reconciliation and scoring prefetch;
   - Hitchhike/Leech copies and side effects;
   - forfeit and race-expiry settlement;
   - counterfactual attribution and global summaries.
   Per-participant `currentMultiplier`, high-multiplier alert/re-arm logic, and
   active side effects must consult that participant's event set; there is no
   race-wide `eventMult` in local mode.
   Explicitly include `raceProgressSideEffects`, the current dirty active-impact
   capture, and every `computeSettlementAttributionVector` call. Active-impact
   notices must remain correct when two participants' local windows differ.
8. Update `raceResolutionInputFingerprint.js`, dependency-closure planning,
   display-artifact reuse deadlines, and the boundary cursor so each race
   fingerprints only entitlements belonging to its participants. Any active or
   unclassifiable local event retains the conservative FULL fallback.
   The legacy cursor SQL explicitly filters `schedule_mode='LEGACY_GLOBAL'`;
   local entitlement boundaries use their own durable claimant and never cause
   a global all-races fan-out.
   Digest both entitlement identity/window and qualifying impact identity/status.
9. Make Home active-event reads authenticated-user-specific and race-progress
   banner reads viewer/race-specific through the concrete cache/overlay contract
   in section 5.4. Remove `globalEvent` from shared race snapshots and
   resolution captures. Preserve response bytes when the flag is off.
10. Preserve `GlobalEventUserSummary` aggregation under the parent event and
    ensure one user's summary closes against `entitlement.endsAt`, not the
    worldwide parent envelope, without weakening current dirty eligibility.
11. Add account-deletion cleanup and retention/observability counters.
12. Add a strict `localGlobalStepEventsEnabled` app setting plus an emergency
    creation switch `LOCAL_GLOBAL_STEP_EVENTS_DISABLED`. Both switches choose
    mode only when a new event-day parent is stamped. A flag flip never changes
    an existing parent, entitlement, boundary, score, or summary; those drain
    under their stamped mode.
13. Before canonical race-expiry scoring, under the race fence and global
    enrollment lock, call `ensureRaceGlobalEventEligibility`. It processes or
    repairs any due entitlement consistently with the catch-up state machine,
    inserts missing unique impacts, then loads `eventsByUserId`. If it cannot
    prove eligibility, settlement aborts/retries rather than finalizing without
    event credit.

## 8. Frontend plan

No production Flutter visual or API-surface change is expected.

- Continue reading `globalEvent` defensively as an optional map with numeric
  multiplier and parseable `endsAt`.
- Continue hiding/collapsing the banner when missing, malformed, or expired.
- Continue routing `GLOBAL_EVENT_STARTED` to Home.
- Add widget/service regression coverage proving the existing Home and race
  banners render a viewer-specific end time without assuming a globally shared
  instant.
- Verify both iOS and Android native background step uploads still send their
  IANA timezone; they do not decide event eligibility.
- Demo/tutorial fixtures require no change because no UI placement or response
  key changes.

## 9. Backward compatibility and rollout

### 9.1 Frozen clients

Old app binaries keep sending their existing requests and reading the existing
optional event object. They do not need to know that competitors can have
different windows. They receive authoritative totals and their own banner.
Missing `globalEvent` already renders no banner.

No existing key is removed, renamed, made required, or repurposed. No existing
endpoint gains a required parameter.

### 9.2 Mixed backend deploy

- Migration first: additive columns/table/defaults only.
- Deploy code with the feature disabled. Legacy event creation/scoring remains
  byte-compatible, but every newly created legacy parent stamps `eventDay` and
  is fenced by the event-day lock.
- During rolling deploy, new legacy creation takes both the existing exact-
  start advisory lock and the new event-day lock. Under those locks it adopts
  any exact-start row created by an older worker with null `eventDay` by
  stamping the day instead of creating another row. Local mode cannot be
  enabled until every cron-owning process runs the new code.
- Materialize and inspect test/staging entitlements without enabling scoring.
- Do not percentage-roll this feature in production: an unscoped legacy-global
  row and local entitlements cannot safely coexist for different user cohorts.
  Exercise cohorts in staging, then stamp one future logical event as the
  atomic production cutover. Never create local parents while any production
  scorer can interpret them as global.
- Enable production only after boundary, scoring, settlement, and summary
  parity checks pass.
- The initial production horizon is the earliest civil event day whose
  worldwide envelope begins at least 24 hours later, plus the following day.
  Each tick fills missing future horizon days; it never catch-up-creates a day
  whose earliest envelope start has passed.
- Rollback/disable creates future parents in legacy mode only when no parent
  already owns that `eventDay`. Every existing local parent—future, active, or
  ended—continues through entitlement boundaries, scoring, settlement, and
  summaries.
- Binary rollback to code whose generic event queries treat local parent
  envelope bounds as globally eligible is prohibited while any local parent
  remains future/active or has unsettled impacts/summaries. Operational rollback
  is flag-only until all local lifecycle data drains.

Backend deploys before any optional app update. Both iOS and Android remain in
lockstep; no build-time configuration is added.

### 9.3 Unknown timezones

Null/invalid timezone users receive a snapshotted `America/New_York`
entitlement. The raw absence remains distinguishable in `users.timezone`; the
fallback is stored only on the entitlement for audit. Once a later event is not
yet materialized, a newly known valid timezone can be used for that event.

## 10. Tests-first plan

### 10.1 Backend pure/service tests

Write these tests and observe the intended failures before business logic:

- One deterministic local wall-clock draw is shared across IANA zones.
- New York and Madrid map the same 17:17 local draw to different UTC instants.
- UTC+14/UTC-12 materialization spans the date line correctly.
- Spring-forward/fall-back days produce correct local wall-clock windows and
  may be 23/25 hours from the prior event.
- Unique `(eventId,userId)` prevents timezone hopping and duplicate workers.
- A changed device timezone remains a candidate for 48 hours, promotes only
  after a later matching observation, and cannot select the next event instant.
- Parent envelope fields cover UTC+14 through UTC-12 but never grant scoring or
  trigger the legacy boundary cursor.
- Changing `users.timezone` after materialization does not move an entitlement.
- Null/invalid timezone snapshots New York without overwriting the user row.
- Fixed half-open boundary and sample proration remain unchanged.
- Participant-specific event maps never apply Madrid's row to New York or vice
  versa, including overlapping UTC intervals.
- Signed multiplier vectors remain: neutral 2x, stacked positive, reversed
  negative, frozen zero, Rainstorm, Hitchhike, and Leech.

### 10.2 Backend integration tests

Use only the dedicated test Postgres after confirming `DATABASE_URL` is not
production.

- Real HTTP/step-upload/race-progress test with two users in one race and two
  timezones: each gets boosted only inside their entitlement.
- At an instant where only one user's event is live, their `currentMultiplier`
  and total are boosted, the other's are not, and each authenticated viewer
  sees only their own top-level banner state.
- Settlement equals live display for both users after delayed sample upload.
- Settlement racing a delayed start-boundary transaction repairs/proves
  eligibility under the shared lock before scoring and cannot omit event credit.
- The same physical steps participating in multiple races aggregate correctly
  into one summary for that user/event.
- Other timezones' pending/end boundaries do not delay that summary.
- Event start and end enqueue only impacted races, once across concurrent
  workers/restarts.
- A crash before/after the entitlement transaction cannot lose or duplicate
  impacts, queue intents, or the durable start-push intent; provider delivery
  is asserted as at-least-once rather than exactly-once display.
- Start recovery before two minutes activates from scheduled start; first
  recovery after two minutes but before end stamps `SKIPPED_STALE`; recovery
  after end remains skipped; none can later reactivate.
- Boundary-vs-race-start and boundary-vs-late-join races cannot miss an impact
  under the shared enrollment lock; the repair pass is idempotent.
- Push fan-out is timezone/entitlement scoped, creates one durable intent, and
  tolerates possible duplicate provider display under at-least-once delivery.
- Race start/late join during a live entitlement enrolls; join after end does
  not; concurrent join/boundary processing cannot miss or duplicate impact.
- Timezone header spoofing after entitlement creation cannot move or duplicate
  the window.
- Fingerprint/artifact/closure tests prove no reuse crosses a participant's
  start/end boundary and no unrelated timezone invalidates an unaffected race.
- Home/race caches cannot leak one user's active event to another user.
- Home active-event cache tests cover Redis enabled, failing, and unset, all
  invalidation sources, and post-read expiry filtering. Race scoring and
  settlement perform no Redis reads.
- High-multiplier alert and re-arm behavior use each participant's own event
  state when two timezone windows differ inside one race.
- Legacy-global fixtures remain byte-for-byte and score-for-score unchanged
  with the flag off and for pre-migration rows.
- Old-client requests without timezone or new capability remain successful.
- Account deletion removes entitlements/impacts/summaries without FK failure.
- Kill switch stops future materialization without changing an in-flight event.
- Enable then disable with two materialized future days creates no duplicate
  day or mode reinterpretation; a rolling-deploy fixture proves a local parent
  cannot reach a legacy-global reader.
- New scheduler plus an old-style exact-start insert with null `eventDay`
  adopts/stamps the same row under the two locks and never creates a second
  event; local enablement remains rejected while an old cron owner is present.
- Seeded 24-hour Daily and cross-timezone user-race fixtures report each
  participant's event opportunity count (`0`, `1`, or `2+`) and lock the
  owner-selected short-race policy.
- Active-impact capture and notices remain participant-correct when only one
  timezone window is active.

### 10.3 Frontend widget tests

- Home renders the existing banner from a viewer-specific `globalEvent`.
- Race detail renders the same end time/countdown.
- Missing, null, malformed, and expired event data renders no banner and does
  not crash.
- Existing notification payload routes to Home on iOS and Android behavior.

### 10.4 Verification commands

- Backend: targeted pure suites, targeted integration suites, then
  `npm run test:unit` and `npm run test:integration`; never bare `npm test`.
- Frontend: targeted widget tests, `flutter analyze`, then `flutter test`.
- Staging soak: at least one full logical event day covering an American,
  European, Asian, and Oceanian test account plus an unknown-timezone account.

## 11. Observability and operations

Record aggregate metrics/logs without exposing user timezone lists:

- logical event materialized, schedule mode, and chosen local minute;
- entitlement counts by coarse timezone/UTC-offset cohort;
- due/claimed/failed start and end boundaries;
- users with no timezone fallback;
- timezone candidates changed/promoted and entitlements created after their
  planned start (the latter is an alert);
- impacted races, pushes attempted/sent, and duplicate claims suppressed;
- per participant-race event opportunity counts (`0`, `1`, `2+`) grouped by
  race duration and coarse timezone-offset separation;
- scoring queries/latency and boundary queue depth;
- summaries pending/finalized per logical event;
- invariant alarms for more than one entitlement per `(eventId,userId)`, a
  local parent read through a legacy-global scorer, or an entitlement window
  changed after creation.

Admin/debug output must remain aggregate or access-controlled. The feature does
not add a user-location API.

## 11.1 Concurrent-work integration constraint

The working backend tree already contains uncommitted active-race-impact and
global-summary eligibility work, including schema, Home query, race resolver,
settlement, summary-worker, and account-deletion edits. Implementation agents
must build on the current tree, preserve those changes, and run their tests.
They must not restore those files to `HEAD`, duplicate their models, or weaken
their summary-eligibility rules. The local-event entitlement is an additional
eligibility dimension layered onto the existing impact lifecycle.

Entitlements are retained until every dependent impact is final, the user
summary lifecycle is complete/acknowledged or expired, and the existing
30-day presentation-retention horizon has elapsed. A cleanup job may then
delete entitlements with no remaining dependent rows; parent events remain for
historical audit. Cleanup is fail-closed and never deletes an entitlement used
by an active race or unsettled summary.

## 12. Economy and abuse analysis

The required game-analysis pass used production step samples:

| Schedule | Mean | Distribution / sample |
|---|---:|---|
| Current live global ET events | 146 | p50 0, p90 440, p99 2,214, max 4,509; 5,498 user-events across 29 events |
| Random 08:00-22:00 local proxy | 202 | p10 55, p50 190, p90 360, p99 578, max 959; 683 users / 4,955 active user-days |
| Fixed 17:00-17:30 local | 231 | p10 0, p50 153, p90 529, p99 1,326, max 2,661; same localized cohort |

The live 146 and localized 202 figures use different cohorts/denominators and
are not a controlled before/after estimate; their apparent uplift is
indicative, not causal. The live value is observed raw steps inside live event
windows per eligible racer-event, equivalent to the event bonus only at a
neutral participant multiplier; it is not the canonical signed-powerup bonus.
The randomized-local proxy is each active user's raw steps inside their local
08:00-22:00 span divided by 28 possible half-hour slots. The fixed-local value
directly prorates samples in 17:00-17:30.

Within the controlled localized cohort, fixed 17:00 raises mean EV about 15%
over localized random, lowers the median, produces a much larger upper tail,
and makes pre-stacking timed powerups/debuffs a dominant scheduled strategy.

Direct coin-source/sink change is approximately zero because this multiplier
does not advance boxes or milestone coin rewards and does not enlarge funded
prize pools. It can redistribute race placement and increases the situational
value of timed powerups.

Required abuse controls are immutable entitlements, server-owned uniqueness,
no live-header eligibility, and participant-specific scoring. Creating one
ordinary global row per timezone is prohibited because current scoring would
stack every overlapping row onto every participant.

## 13. Acceptance criteria and definition of done

- Every entitled user receives exactly one 30-minute 2x opportunity at the
  logical event's local wall-clock minute in their snapshotted timezone.
- No user can receive multiple windows for one event by changing timezone.
- Cross-timezone participants in one race receive only their own boosts; live
  display, settlement, attribution, summaries, and current multipliers agree.
- The existing Home/race banner and push contracts remain compatible.
- Frozen clients and legacy rows continue working against the new backend.
- Unknown timezone behavior is explicit and safe.
- Local events never pass through a legacy-global scoring query.
- All tests above are written first and pass; existing tests are not weakened.
- Backend unit/integration suites pass against the test DB.
- `flutter analyze` and `flutter test` pass.
- Both platforms are accounted for.
- Architect, game-analyst, implementation, and code-reviewer agents complete
  the repo-required workflow.
- Production deployment still requires separate, in-the-moment owner approval.

## 14. Resolved owner decisions

1. **Schedule shape:** choose one cryptographically random daily minute in
   08:00-22:00 once under the event-day creation lock, persist it, and interpret
   that same wall-clock minute in every entitlement's snapshotted local
   timezone. Do not use a fixed 17:00 event.
2. **Cutover:** stamp the next not-yet-started logical event day after the
   production flag is enabled as `LOCAL_ENTITLEMENTS`. Any already-started
   legacy event finishes globally and unchanged.
3. **Unknown timezone:** snapshot `America/New_York` for users whose stored
   timezone is null or invalid. Do not exclude them from the event.

4. **Short-race fairness:** the owner accepts that participants in the same
   approximately 24-hour race can receive different numbers of local event
   windows (`0/1/2+`) near race boundaries. V1 measures this outcome and does
   not add a mixed global/local normalization rule.

## 15. Revision log

- Initial draft: mapped the current global scheduler, shared scoring paths,
  impact/summary lifecycle, Home/race contracts, notification routing,
  fingerprint/boundary system, compatibility requirements, and economy review
  into an immutable per-user entitlement design.
- Gap pass 1: added explicit compatibility-envelope semantics and duration,
  prevented local parents from entering the legacy global cursor, bounded
  entitlement materialization to racers plus transactional join/start hooks,
  and closed the race-start/boundary write-skew with the existing advisory
  lock and an idempotent repair path.
- Gap pass 2: defined the global civil event-day identity, replaced lossy
  claim timestamps with transactional processed boundaries plus durable
  notification/queue intents, made multiplier alerts and caches explicitly
  participant/viewer scoped, removed an unsafe percentage rollout where local
  and unscoped legacy events could double-award, and documented integration
  with the existing dirty active-impact/summary worktree.
- Owner interview: selected randomized local timing, next-eligible-day atomic
  cutover, and New York fallback for unknown timezones; all open product
  decisions are resolved.
- Architect review: required scoring-load fail-closed behavior; universal
  `eventDay` identity and worldwide cutover; mid-window first-race entitlement;
  a durable boundary/Inbox-outbox state machine; explicit stale-start outcomes;
  one participant-specific scorer/fingerprint contract including dirty impact
  work; post-auth viewer overlays with a concrete Home cache; entitlement-end
  summary closure; flag-only rollback; and retention. All are incorporated.
- Game-analyst spec review (`SOUND WITH CHANGES`): required a stable 48-hour
  event-timezone policy, explicit short-race exposure decision, settlement
  boundary repair, worldwide cutover, and corrected economy evidence labels.
  The technical/evidence changes are incorporated; short-race policy awaits
  owner acceptance.
- Post-review gap pass 1: resolved the contradiction between stale scheduled
  entitlements and legitimate first-race mid-window joins by splitting on-time,
  late-join, no-race, and stale outcomes with forward-only transitions.
- Final review reconciliation: made the one-time persisted random draw explicit
  in the implementation plan and aligned all notification claims/tests with
  one durable intent plus at-least-once APNs/FCM delivery. The economy evidence
  now labels the live 146-step figure as observed raw in-window steps rather
  than canonical signed-powerup bonus.
- Implementation: backend and Flutter changes landed tests-first against the
  locked additive contract. Three independent review passes found and then
  verified fixes for production dependency wiring, participant-window clipping,
  lock ordering, maintenance pagination/draining, all race-start paths,
  forfeiture and attribution eligibility, viewer/cache isolation, cron-owner
  fencing, observability, retention, and real DB/HTTP coverage. Final review:
  approved with no release-blocking findings.
- Post-review gap pass 2: closed rolling-deploy duplication between an old
  exact-start writer and the new event-day identity by requiring both locks,
  null-day row adoption, and all-new cron ownership before local enablement.
- Final owner interview: explicitly accepted the documented short-race
  `0/1/2+` exposure tradeoff with monitoring and no v1 normalization. No open
  product decisions remain.
