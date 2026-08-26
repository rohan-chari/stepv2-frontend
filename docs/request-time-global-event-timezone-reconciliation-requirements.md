# Request-time global-event timezone reconciliation

**Status:** Draft for product and architecture review. No implementation or
production change is authorized by this document.

## 1. Summary and user story

The local daily 2x event currently snapshots a user's stable event timezone when
the entitlement is materialized, often several days before the event. Later
authenticated requests immediately update `users.timezone`, but they do not move
an already-created entitlement. A traveler can therefore be physically in New
York, have the app sending `X-Timezone: America/New_York`, and still receive that
day's event on a previously snapshotted Denver schedule.

When a valid authenticated request reports a changed IANA timezone, reconcile
that user's not-yet-started local-event entitlements to the newly observed
timezone. The database remains authoritative. Redis is not needed for correctness
or write suppression because the existing auth path already performs zero writes
when the request timezone matches `users.timezone`.

User story: as a racer who travels, I receive the daily 2x event according to my
device's current timezone when I use the app before either the old or new event
window begins, without receiving two opportunities or moving an event that has
already started.

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
database transaction:

1. parent mode is `LOCAL_ENTITLEMENTS`;
2. `startOutcome` is `PENDING` and `startProcessedAt` is null;
3. the old persisted `startsAt` is strictly in the future;
4. the newly calculated `startsAt` is strictly in the future; and
5. no `GlobalEventRaceImpact`, activation domain event, visible alert, or push
   exists for that event/user.

If any condition fails, retain the current event's immutable window. The newly
observed timezone still updates `users.timezone` and applies to future event
parents. A timezone change can therefore move an upcoming opportunity but can
never replay, extend, duplicate, or resurrect one.

Repeated legitimate travel before both windows begin may relocate the same
pending entitlement again. The unique `(eventId,userId)` row remains the only
opportunity; reconciliation updates that row rather than creating another.

### 3.3 Future materialization

New entitlements use the latest valid `users.timezone` first, then the existing
valid `globalEventTimezone`, then `America/New_York`. Existing 48-hour candidate
columns remain additive compatibility data but no longer override a newer
request-observed timezone for a not-yet-started entitlement.

### 3.4 Concurrency

Timezone reconciliation uses the same lock order as event enrollment and start
boundary processing. It locks the entitlement row, rereads its outcome/window,
and updates `users.timezone` plus eligible entitlement rows atomically. If the
start boundary wins first, relocation loses safely and changes only the user's
timezone for future events. If relocation wins first, the boundary observes the
new window.

The request remains usable if reconciliation fails. The failure is logged and
counted, but auth does not fail. A retry with the same header must retry pending
reconciliation even if `users.timezone` already equals the header; therefore
"timezone unchanged" cannot be the sole early-return once eligible pending
entitlements may still need repair.

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

No schema migration is required. Continue using:

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
2. Add a transaction service in
   `src/modules/steps/services/globalStepEventEntitlement.js` that reconciles a
   user's pending local entitlements to one validated timezone using the safe
   relocation and lock rules above.
3. Add a user-model/auth orchestration method that combines the changed
   `users.timezone` write with entitlement reconciliation, instead of separate
   eventually consistent writes.
4. Call it from the existing valid-header path in
   `src/middleware/requireAuth.js`. Preserve best-effort request behavior and
   ensure a prior partial failure can be retried.
5. Change future entitlement timezone selection to prefer `users.timezone`.
6. Best-effort invalidate `homeActiveGlobalEvent(userId)` after a committed
   relocation and record operational counters.
7. Update the original local-event requirements to replace the immutability and
   48-hour-travel statements that this behavior supersedes.

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

1. A real authenticated request changing Denver to New York before both starts
   updates `users.timezone` and the same entitlement row to the New York window.
2. The next boundary creates impacts, banner eligibility, domain projection, and
   push intent at the relocated instant—not the old instant.
3. Missing and invalid headers do not update the user or entitlement.
4. An unchanged header performs no entitlement write in steady state.
5. A retry after a simulated partial/best-effort failure repairs a still-pending
   entitlement even when `users.timezone` already matches.
6. Relocation is rejected when the old start has arrived, the new start has
   arrived, start processing won, an impact exists, or an activation event exists.
7. Eastward travel whose new window is already active/past does not backfill;
   westward travel after the old start does not postpone/replay.
8. Multiple pre-start changes update one row and preserve the unique
   event/user opportunity.
9. Concurrent request reconciliation and boundary processing produce exactly
   one valid result with no duplicate impacts, alerts, pushes, or score.
10. Redis unavailable: the DB reconciliation still commits and the request
    succeeds.
11. Frozen-client request without `X-Timezone` preserves existing behavior.
12. Real race progress and settlement score only the final persisted interval.

Run backend `npm run test:integration` only against a dedicated test database,
then `npm run test:unit`. Never run bare `npm test` or point tests at production.
Frontend verification is the existing relevant widget/header suites plus
`flutter analyze`; no UI-placement checklist is required because no visible
element is added, moved, or removed.

## 10. Rollout and backward compatibility

Deploy backend first; no app release dependency exists. This is permanent
version-compatible behavior, with no release flag. Existing entitlements that
already started remain untouched. Pending future entitlements reconcile only
when the user next makes a valid authenticated request, avoiding a bulk rewrite.

Before production deployment, measure the number of pending entitlements per
active user and run a production-shaped test to ensure a timezone-changing
request adds bounded queries/writes. Production verification is SELECT-only
until separately authorized; deployment and production writes require fresh
explicit approval.

## 11. Acceptance criteria and definition of done

- A traveler opening the app before both old/new starts gets today's future 2x
  event in the newly reported timezone.
- No user can obtain more than one entitlement, activation, push, or scoring
  interval for one logical event.
- Started/active/completed events never move.
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

