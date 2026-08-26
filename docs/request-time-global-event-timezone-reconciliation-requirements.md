# Request-time global-event timezone reconciliation

**Status:** Superseded as a standalone approval document by
`docs/global-event-reliability-requirements.md`, which folds this reviewed
timezone design into the activation/notification reliability work. No
implementation or production change is authorized by either document until the
consolidated spec is approved.

## 1. Summary and user story

The local daily 2x event currently snapshots a user's stable event timezone when
the entitlement is materialized, often several days before the event. Later
authenticated requests immediately update `users.timezone`, but they do not move
an already-created entitlement. A traveler can therefore be physically in New
York, have the app sending `X-Timezone: America/New_York`, and still receive that
day's event on a previously snapshotted Denver schedule.

When a valid authenticated request reports a changed IANA timezone, reconcile
that user's eligible future local-event entitlements once to the newly observed
timezone, but only before that logical event's earliest worldwide envelope
start. The database remains authoritative. Redis is not needed for correctness
or write suppression because the existing auth path already performs zero writes
when the request timezone matches `users.timezone`.

User story: as a racer who travels, I receive the daily 2x event according to my
device's current timezone when I use the app before the event has begun anywhere
in the world, without receiving two opportunities or choosing a later window
after the daily minute has been revealed.

### 1.1 Scope and non-goals

In scope: authenticated request-time detection, one durable relocation of
already-materialized pending entitlements, additive audit fields, universal
writer lock ordering, presentation-cache invalidation, and backend-only rollout.

Non-goals for the timezone portion: moving an event after its earliest worldwide disclosure boundary;
proving physical location with GPS/IP; replacing the 48-hour stable timezone;
using Redis as authority; changing event duration/multiplier/frequency; fixing
event odds/economy; or adding/changing UI. The previously separate boundary and
notification reliability incident is now covered by the consolidated spec.

## 2. Current-system evidence

- Flutter sends `X-Timezone` on every GET and JSON request
  (`lib/services/backend_api_service.dart:5555-5615`). No app release is needed.
- Auth validates the real header, skips absent/invalid values, and writes
  `users.timezone` only when it changed
  (backend `src/middleware/requireAuth.js:127-149`).
- A separate 48-hour candidate mechanism promotes `globalEventTimezone`
  (backend `src/modules/users/services/globalEventTimezone.js:1-54`). This was
  designed to prevent timezone chasing, but it also prevents ordinary short
  travel from affecting a pre-materialized event.
- Entitlement creation reads `globalEventTimezone`, persists an immutable
  timezone/window, and returns an existing entitlement unchanged
  (backend `src/modules/steps/services/globalStepEventEntitlement.js:63-113`).
- Banner/scoring eligibility reads the entitlement's persisted window and
  eligible start outcome, not the request header
  (backend `src/modules/steps/models/globalStepEventEntitlement.js:90-128`).
- Production incident on 2026-08-26: `emersonz` was currently observed and
  stably stored as `America/New_York`, but the August 26 entitlement remained
  `America/Denver` because it had been created on August 22.
- Production is already running local entitlements despite the original
  requirements' stale default-off status. On 2026-08-26 production contained
  nine local parents and 7,852 entitlements; the original requirements must be
  corrected as part of this work.

## 3. Product behavior

### 3.1 Authoritative observation

Only a valid, explicit `X-Timezone` accepted by the existing timezone middleware
may trigger reconciliation. Missing, invalid, fallback-injected, anonymous, and
internal requests do nothing. Frozen clients that omit the header retain current
behavior.

The header is device timezone, not verified physical location. The product
accepts that limitation; GPS/IP geolocation is out of scope.

### 3.2 Safe relocation rule

On a genuine timezone change, calculate the entitlement window in the newly
observed timezone from the already-persisted parent `eventDay`,
`localStartMinute`, and `durationMinutes`.

Relocate an entitlement only when all of the following remain true inside one
database transaction, using one comparison instant captured after locks are
held (equality counts as already started):

1. parent mode is `LOCAL_ENTITLEMENTS`;
2. `startOutcome` is `PENDING`, `startProcessedAt` is null, and
   `endProcessedAt` is null;
3. `timezoneRelocatedAt` is null;
4. the parent compatibility-envelope `startsAt` is strictly in the future,
   meaning no timezone can have disclosed this event's minute yet;
5. the old persisted `startsAt` and newly calculated `startsAt` are strictly in
   the future;
6. the new interval does not overlap the user's preceding or following local
   event entitlement; and
7. no artifact exists under the exact authorities for this event/user:
   `GlobalEventRaceImpact(eventId,userId)`, domain-event key
   `GLOBAL_STEP_EVENT_ACTIVATED_V1:<entitlementId>`, user summary, visible-alert
   source key, notification projection/outbox, or delivery row.

If any condition fails, retain the current event's immutable window. The newly
observed timezone still updates `users.timezone` and enters the existing
48-hour stable-timezone candidate flow for later materialization. A timezone
change can therefore move an eligible upcoming opportunity but can never replay,
extend, duplicate, or resurrect one.

This safe rule deliberately would not have moved `emersonz`'s August 26 event if
her first New York request arrived after that parent's earliest worldwide start.
Supporting that exact same-day case would require accepting post-disclosure
timezone selection or adding stronger location proof, both out of scope.

One entitlement may be relocated at most once. The unique `(eventId,userId)` row
remains the only opportunity; reconciliation updates that row rather than
creating another. Each successful row update atomically replaces `timezone`,
`localDate`, `startsAt`, and `endsAt`, stamps `timezoneRelocatedAt`, and records
the prior timezone for audit.

### 3.3 Future materialization

New entitlements continue using the valid stable `globalEventTimezone`, then
`America/New_York`. The existing 48-hour candidate mechanism remains the default
anti-chasing authority. Request-time relocation is a bounded, once-per-event
travel correction, not a replacement for stable future materialization.

### 3.4 Concurrency

All writers that can activate, enroll, repair, settle, or relocate a local event
use one universal lock order: race C0 fences when applicable, then the global
enrollment advisory lock, then entitlement rows ordered by `(startsAt,id)`.
After locking, each writer rereads and revalidates its predicates. The
reconciliation transaction updates `users.timezone` plus eligible entitlement
rows atomically. If the start boundary wins first, relocation loses safely and
changes only the user's immediate timezone metadata. If relocation wins first,
the boundary observes the new window.

The request remains usable if reconciliation fails. The failure is logged and
counted, but auth does not fail. `users.timezone` is the durable retry marker:
its update and entitlement relocation commit in the same transaction. A DB
failure rolls both back, so the next request still appears changed and retries.
Post-commit cache/counter failure never re-runs reconciliation. An unchanged
header performs zero reconciliation SQL and zero writes.

## 4. Redis decision

Do not use Redis as the source of truth or as a required write-behind queue.

- The auth path already has the stored user timezone and writes only on change.
- A real timezone change requires one durable DB transaction anyway because the
  entitlement row controls scoring, banners, and notifications.
- Redis eviction, restart, lag, or split-worker races must not move or lose an
  event window.
- Write-behind would create a period where requests, cron boundaries, scoring,
  and notifications disagree.

The existing Home active-event Redis cache is presentation-only. Reconciliation
invalidates that user's Home active-event key best-effort after commit. Redis
outage never blocks the DB update. No new runtime flag or kill switch is added.
Redis may not be used as a correctness retry marker, relocation counter, or
write-behind queue.

## 5. API contract

No endpoint or response shape changes.

Existing authenticated requests continue to send optional `X-Timezone`. A valid
changed value may now reconcile future pending entitlements as a backend side
effect. Status codes and response bodies remain unchanged, including when
reconciliation fails best-effort.

Older clients:

- with a valid `X-Timezone` gain the corrected behavior automatically;
- without the header retain their persisted schedule;
- never receive a new required field, parameter, or endpoint.

## 6. Data model and migration

Add one backward-compatible migration with nullable columns on
`global_step_event_entitlements`:

- `timezone_relocated_at timestamp null` — durable at-most-once fence; and
- `timezone_relocated_from text null` — audit of the prior IANA zone.

No existing row is backfilled; null means never relocated. Old backend code and
all old app versions ignore both columns safely. Continue using:

- `users.timezone` as the latest valid request-observed timezone;
- `global_step_event_entitlements.timezone`, `starts_at`, and `ends_at` as the
  authoritative scoring/notification window; and
- unique `(event_id,user_id)` as the once-per-event fence.

Add an operational counter for successful pending-entitlement relocations and
one for rejected/failed reconciliation attempts using the existing global-event
counter infrastructure. This is additive data/configuration, not a release flag.

## 7. Backend implementation plan

1. Tests first in
   `test/integration/local-global-step-event-entitlements.test.js` through real
   authenticated HTTP requests.
2. Add the nullable entitlement relocation columns and Prisma fields.
3. Add a transaction service in
   `src/modules/steps/services/globalStepEventEntitlement.js` that reconciles a
   user's pending local entitlements to one validated timezone using the safe
   relocation and lock rules above.
4. Keep user-table access in the users model with optional `tx`; keep
   entitlement access in the steps model/service. Inject one reconciliation
   collaborator into `buildRequireAuth(dependencies)` rather than putting
   transaction business logic in middleware or entitlement access in the user
   model. Export/import that collaborator explicitly.
5. Call the collaborator from the existing valid changed-header path in
   `src/middleware/requireAuth.js`. After success update the request-scoped user
   timezone. Preserve best-effort request behavior.
6. Bound the synchronous request path to at most four future entitlement rows,
   one set-based artifact check, no per-row transaction loop, no more than eight
   application SQL statements excluding transaction control, `lock_timeout`
   100ms, `statement_timeout` 400ms, and transaction timeout 500ms. Perform no
   inline retry; timeout rolls back and fails open to the requested endpoint.
7. Best-effort invalidate `homeActiveGlobalEvent(userId)` after a committed
   relocation and record operational counters.
8. Update the original local-event requirements' deployment status and replace
   the absolute immutability statements with this once-before-envelope rule.
9. Change every local-event activation/enrollment/repair writer to the universal
   lock order before enabling relocation.

## 8. Frontend plan

No Dart change is required: both iOS and Android already resolve the device IANA
timezone and attach it to every request. Existing banner, countdown, and push
routing continue reading the same backend contract.

Verification must still cover both platforms' existing timezone-header tests.
If a platform cannot resolve a timezone, it omits no new data and the backend
retains the prior entitlement safely.

## 9. Tests-first plan

Integration tests must exist and fail for the intended reason before business
logic lands:

1. A real authenticated request changing Denver to New York before the parent
   envelope and both personal starts updates `users.timezone` and the same
   entitlement row to the New York window.
2. The next boundary creates impacts, banner eligibility, domain projection, and
   push intent at the relocated instant—not the old instant.
3. Missing and invalid headers do not update the user or entitlement.
4. An unchanged header performs zero reconciliation SQL and writes in steady
   state.
5. A simulated transaction failure rolls back both user timezone and
   entitlement; the next changed-header request retries. Post-commit cache or
   counter failure does not retry the DB mutation.
6. Relocation is rejected when the old start has arrived, the new start has
   arrived, start processing won, an impact exists, or an activation event exists.
7. Eastward travel whose new window is already active/past does not backfill;
   westward travel after the old start does not postpone/replay.
8. A second pre-start relocation is rejected by the durable stamp.
9. A request after the parent's earliest worldwide envelope start is rejected,
   including a UTC+14 disclosure followed by westward spoofing.
10. Neighboring event windows cannot overlap after relocation; adversarial
    event-day bunching remains single-multiplier.
11. Concurrent real HTTP reconciliation versus boundary processing and versus
    late enrollment force both lock-winning orders and produce no deadlock,
    stale impact, old-time push, duplicate alert, or duplicate score.
12. With the Home key pre-warmed in local Redis DB 15, relocation invalidates
    it; with `REDIS_URL` unset or Redis failing, the DB commit and request still
    succeed.
13. Race-end targeting and repeated timezone changes cannot move an event after
    disclosure or activation.
14. Frozen-client request without `X-Timezone` preserves existing behavior.
15. Real race progress and settlement score only the final persisted interval.
16. A production-shaped test proves at most four rows, the pinned query ceiling,
    and the lock/statement/transaction timeouts.

Run backend `npm run test:integration` only against a dedicated test database,
then `npm run test:unit`. Never run bare `npm test` or point tests at production.
Frontend verification is the existing relevant widget/header suites plus
`flutter analyze`; no UI-placement checklist is required because no visible
element is added, moved, or removed.

## 10. Rollout and backward compatibility

Deploy the additive migration, then backend; no app release dependency exists.
This is permanent version-compatible behavior, with no release flag. Existing
entitlements that have reached their parent envelope start remain untouched.
Eligible future entitlements reconcile only when the user next makes a valid
authenticated changed-timezone request, avoiding a bulk rewrite.

Before production deployment, measure the number of pending entitlements per
active user and run a production-shaped test to ensure a timezone-changing
request adds bounded queries/writes. Production verification is SELECT-only
until separately authorized; deployment and production writes require fresh
explicit approval.

## 11. Acceptance criteria and definition of done

- A traveler opening the app before the event begins anywhere gets one future
  2x event relocated to the newly reported timezone.
- No user can obtain more than one entitlement, activation, push, or scoring
  interval for one logical event.
- Disclosed/started/active/completed events never move, and one entitlement can
  move at most once.
- Redis loss cannot alter correctness.
- Old clients and missing/invalid headers remain safe.
- Integration tests prove the public HTTP-to-boundary-to-banner/scoring path.
- Required architect, game-analyst, and code-review reviews are complete.
- Backend unit/integration tests pass on a test DB; Flutter tests/analyze remain
  clean if any frontend file changes.

## 12. Revision log

- Draft: replaced immutable multi-day snapshots with request-time reconciliation
  for strictly future pending windows; rejected Redis write-behind as an
  authoritative design; retained one durable entitlement row.
- Gap pass 1: added retry-after-partial-failure behavior, activation-artifact
  guards, cache invalidation, concurrency lock ordering, and east/west boundary
  cases.
- Gap pass 2: added future-materialization precedence, no-header frozen-client
  behavior, bounded production verification, operational counters, and explicit
  no-flag rollout.
- Architect review: established one universal writer lock order; made the
  atomic user/entitlement transaction the retry marker; added exact artifact
  fences, request-path timeouts/caps, dependency-injected layering, and Redis
  cache/concurrency integration coverage.
- Game-analyst review: rejected repeated relocation while only personal windows
  were future (estimated foreknowledge ceiling about 6.4x mean bonus); limited
  relocation to once before the parent's earliest worldwide envelope start;
  retained stable timezone materialization and added adjacent-event overlap and
  adversarial timezone-chasing guards.
- Post-review gap pass 1: made the same-day limitation explicit, corrected the
  future-materialization statement to retain the 48-hour candidate flow, added
  scope/non-goals, and pinned the SQL statement ceiling.
- Post-review gap pass 2: verified old-client/no-header behavior, migration
  additivity, no-Redis correctness, lock-race outcomes, non-overlap, and the
  separate boundary-throughput non-goal; no further open implementation
  ambiguity remains.
