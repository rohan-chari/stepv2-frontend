# Global 2x event summary boundary finalization and same-day expiry

## Summary & user story

After a user's local 2x step event ends, Home should show one recap of the
signed steps gained or lost across all races affected by that event. The recap
must become eligible after the event boundary even when those races remain
active. It is a same-local-day message, not an inbox: if the user does not see
it before the next midnight in the timezone stamped on that event entitlement,
the backend permanently stops returning it.

As a racer, I can open or refresh Home after today's 2x event and see today's
aggregate once. I never receive yesterday's recap on a later day.

## Current implementation and failure evidence

- Flutter reads the optional `globalEventSummary` from the Home race-card
  response and queues it in `lib/screens/main_shell.dart:3413-3425`.
- `MainShell._showPendingGlobalEventSummaryIfEligible` at
  `lib/screens/main_shell.dart:3461-3558` displays `2x STEPS COMPLETE` only on
  Home and acknowledges it after dismissal.
- Backend `src/modules/steps/services/globalStepEventEntitlement.js:713-739`
  processes a local entitlement's end by enqueueing affected races with
  `GLOBAL_EVENT_BOUNDARY`, but it does not finalize their
  `GlobalEventRaceImpact` rows.
- Backend `src/modules/races/jobs/raceExpiry.js:740-748` is currently the only
  writer that changes those rows to `FINAL`, so a summary waits for every
  containing race to settle.
- `src/modules/steps/jobs/globalEventSummary.js:46-49` refuses to create a
  summary while any enrolled row is not `FINAL`.
- A read-only production check on 2026-08-26 found a completed event with
  2,348 impact rows, 2,239 still pending, and no summaries; active enrolled
  races extended as late as 2026-09-25. It also found pending rows belonging to
  completed and cancelled races.

## Product decisions

1. Delivery is once per `(eventId,userId)`, not once per app open and not a
   rolling 24-hour window.
2. The delivery window ends at midnight immediately following the
   entitlement's stamped `localDate`, calculated in the entitlement's
   already-stamped IANA `timezone`. The timezone and local date are immutable
   audit inputs for this summary; later user timezone changes do not move the
   deadline.
3. An unacknowledged summary that reaches `expiresAt` is permanently ineligible
   and must not be returned on a later Home load, whether or not another event
   has occurred.
4. A modal already presented before expiry may remain open and may be
   acknowledged after midnight. A summary fetched while Home is hidden or
   another modal has priority must still be discarded if its deadline passes
   before presentation.
5. The amount is an immutable event-boundary attribution over the first
   canonical post-boundary step-sync generation. The scoring interval closes
   at `endsAt`, while the post-boundary upload supplies the latest synced
   samples. Later-arriving historical samples may affect authoritative race
   results but never rewrite a recap already created or acknowledged.
6. If no post-boundary step sync resolves before `expiresAt`, no recap is
   created. The lifecycle is discarded after expiry rather than finalized from
   an older pre-boundary upload.
7. The existing policy remains: create no summary for an all-zero per-race
   vector; preserve a legitimate mixed nonzero vector whose aggregate is zero.

## Scope

### In scope

- Finalize each enrolled race/user's global-event contribution from the first
  canonical post-boundary step-sync capture, independently of race completion.
- Aggregate the final boundary rows into the existing one-per-event/user Home
  summary.
- Stamp a durable same-local-day expiry and filter expired summaries in both
  Home response builders and every cache path.
- Preserve acknowledgement, retry, privacy, all-zero suppression, mixed
  net-zero delivery, and the existing Flutter modal.
- Permanently terminalize stranded version-2 work without a production-only
  manual data rewrite; version-1 rows retain legacy semantics and are not
  converted into new recaps.

### Non-goals

- Changing the 2x multiplier, scheduling windows, entitlement eligibility,
  race totals, prizes, power-up stacking, or coin economy.
- Showing the recap in Inbox, sending a completion push, or retaining a recap
  beyond its local day.
- Waiting for a race to finish or inventing a health-data ingestion grace
  period.
- Adding a feature flag, kill switch, rollout percentage, or temporary runtime
  control.
- Changing the existing Home modal's layout, copy, art, or acknowledgement
  gesture.

## Backend design and implementation path

### 1. Version the contract and persist exact lifecycle state

Add the permanent client capability `impact_summary_expiry_v1` to both feature-
header branches in `lib/services/backend_api_service.dart`. A boundary summary
is returned only when a request advertises both `impact_summaries` and
`impact_summary_expiry_v1`. Acknowledgement continues to require only
`impact_summaries`, allowing an old client holding a predeploy modal to dismiss
it.

Add `summaryAttributionVersion Int @default(1)` to `GlobalStepEvent`. New event
creation explicitly stamps version 2; an event created by an overlapping old
binary stays version 1. Version-2 enrollment explicitly stamps
`GlobalEventRaceImpact.attributionVersion = 2`.

Add these nullable columns to `GlobalEventRaceImpact`:

| column | rule |
|---|---|
| `captureKind` | v2 value `POST_BOUNDARY_SYNC` |
| `captureSyncRequestId` | copied opaque `StepSyncRequest.id`, intentionally no FK because sync requests retain only seven days |
| `captureCompletedAt` | database completion time of the qualifying sync |
| `captureCoverageThrough` | timestamp through which committed canonical input coverage was proven |
| `sourceScoringInputGeneration` | copied bigint `UserScoringInputVersion.generation` |
| `sourceResolutionGeneration` | race-keyed C0 generation that committed attribution |
| `terminalReason`, `terminalAt` | allowlisted terminal diagnostic and timestamp |

The existing string status has this application transition contract:

```text
PENDING -> FINAL
PENDING -> UNSCORABLE
PENDING -> EXPIRED_UNDELIVERED
```

Every destination is terminal, but only `FINAL` aggregates. One `UNSCORABLE`
row suppresses the whole event/user recap; partial “across all races” totals
are prohibited. Allowed reasons are `INPUTS_NOT_RETAINED`,
`RACE_CANCELLED_UNREPLAYABLE`, `PARTICIPANT_STATE_UNREPLAYABLE`,
`DEPENDENCY_INPUT_UNREPLAYABLE`, and `DEADLINE_PASSED`. Unknown failures retry.

Add `GlobalEventSummaryWork`, unique on `(eventId,userId)`, with:

- UUID `id` and event/user foreign keys;
- `status`: `WAITING_SYNC`, `QUEUED`, `PROCESSING`, `WAITING_RACES`,
  `CREATED`, `ALL_ZERO`, `UNSCORABLE`, or `EXPIRED_UNDELIVERED`;
- immutable `expiresAt`;
- nullable copied `captureSyncRequestId`, `captureCompletedAt`,
  `captureCoverageThrough`, and bigint `sourceScoringInputGeneration`;
- non-negative `requiredRaceCount`/`finalRaceCount` diagnostics (readiness
  always rechecks impact rows);
- `availableAt`, `leaseUntil`, `leaseToken`, `attemptCount`, `lastErrorCode`,
  and timestamps.

Index `(status,availableAt,leaseUntil)`, `(userId,status,expiresAt)`, and the
unique pair. Every compare-and-set transition includes current status and lease
token; terminal work never requeues.

Add `GlobalEventCaptureArtifact`, unique on `(workId,raceId)`, with UUID `id`,
work/event/race/user IDs, `captureSyncRequestId`, `captureCompletedAt`,
`captureCoverageThrough`, bigint `sourceScoringInputGeneration`, non-null JSONB
`payload`, SHA-256 `payloadDigest`, integer `schemaVersion = 1`, and timestamps.
The payload is an immutable, normalized, size-bounded copy of exactly the
canonical samples, participant states/cutoffs, event window, relevant effects,
and Leech/Hitchhike dependency inputs required for both counterfactuals. It
contains no profile/presentation data. Oversize or incomplete input makes the
whole group `UNSCORABLE`; it never falls back to mutable live rows. Limits are
2 MiB of canonical UTF-8 JSON per race artifact and 16 MiB across one work
group. Encoding follows RFC 8785 JSON Canonicalization Scheme (lexicographic
object keys, canonical number/string representation, no insignificant
whitespace); `payloadDigest` is lowercase SHA-256 hex over those exact UTF-8
bytes. Stored JSON must round-trip to the same canonical bytes/digest.

Extend `StepSyncRequest` with nullable `completedAt`,
`canonicalCoverageThrough`, and bigint `scoringInputGeneration`. Stamp them in
the transaction changing the request to `COMPLETE`, including no-op syncs.
Coverage is derived from committed server input, never trusted request
metadata. The first complete request satisfying
`completedAt >= entitlement.endsAt` and
`canonicalCoverageThrough >= entitlement.endsAt` may claim `WAITING_SYNC`.
A pre-boundary request completed afterward qualifies only when committed
coverage reaches the boundary. Provenance is copied into durable work/impact
rows, not referenced by FK.

Add nullable `expiresAt` to `GlobalEventUserSummary` and index
`(userId,acknowledgedAt,expiresAt,settledAt DESC)`. All changes are additive.
Every v2 create explicitly stamps the existing `attributionVersion = 2`, and
the v2 eligibility query requires that value.

### 2. Compute immutable expiry

Resolve `expiresAt` by advancing entitlement `localDate` one civil day and
converting its `00:00` through existing `zonedDateTimeToUtc`; never add 24 UTC
hours. Version-1 events and null-expiry summaries are not served to the new
capability. For a version-2 legacy-global compatibility event, use the exact
`FALLBACK_EVENT_TIMEZONE` (`America/New_York`); underivable rows fail closed.

### 3. Produce full-interaction canonical attribution

Extract attribution into a dependency-injected shared race service used by
both settlement and boundary finalization; no duplicate formula and no hard
`StepSample` import. The version-2 counterfactual is:

```text
Score(with event, capture) - Score(without event, same capture)
```

It includes signed multipliers, Wrong Turn, freeze, positive buffs, Leech,
Hitchhike, clamping, and shared integer allocation. Use the existing
instrumented constant-pass path, not one replay per effect prefix.

The scoring horizon per participant is the earliest existing timestamp among
`entitlement.endsAt`, `race.endsAt`, `participant.finishedAt`, and
`participant.forfeitedAt`. A participant finishing during the event is replayed
to that cutoff; do not replace both counterfactual totals with one frozen total
and force zero. Cancelled/deleted membership is replayed from retained input or
becomes `UNSCORABLE`. Dependency participants use the latest committed
as-of-capture inputs, which may be older than the uploader's sync; missing
replay inputs suppress the whole group.

At event end, create work in `WAITING_SYNC` and retain the timer's
`GLOBAL_EVENT_BOUNDARY` enqueue only to remove the live multiplier. A timer or
pre-end upload cannot finalize attribution. Canonical step intake conditionally
claims eligible work only for that uploader. A race-wide resolution may score
all participants but finalizes only rows whose user has matching copied sync
provenance; another user's upload can never freeze this recap. A qualifying
no-op sync creates the work/enqueue path despite unchanged scoring generation.

Claiming a qualifying sync also creates every per-race capture artifact before
releasing the canonical intake transaction. Before canonical intake locks the
uploader, pre-discover the complete event/race dependency closure, then acquire
or create **every** required `UserScoringInputVersion` row—including the
uploader—in ascending user-ID order inside one repeatable-read transaction. If
the dependency closure changes after locks are acquired, abort and retry; never
acquire a newly discovered lower-sorted lock. Only after the full ordered lock
set is held may intake mutate uploader samples and copy normalized artifacts.
This replaces the current uploader-first lock order for qualifying capture
transactions and prevents A-holds-A/B-holds-B cycles. Artifact creation and the work transition out of
`WAITING_SYNC` commit together; any failure rolls both back. Later syncs may
change live `step_samples` but cannot supersede a claimed artifact. There is no
“latest generation wins” CAS after the first complete artifact set exists.

C0 post-tasks update a matching `PENDING` impact with `FINAL`, immutable delta,
attribution version 2, settled time, `POST_BOUNDARY_SYNC`, and every provenance
field, consuming only the artifact whose digest and provenance match group
work. Race settlement cannot finalize a v2 row without qualifying provenance
and never overwrites terminal rows. Version-1 final rows keep their historical
meaning and never mix into v2.

### 4. Durable group readiness and first-open delivery

Register a `GlobalEventSummaryWork` scheduler inside the existing guarded cron
role; no new PM2 process. Poll at a bounded one-second recovery interval, claim
with `FOR UPDATE SKIP LOCKED`, use short token-fenced leases, and enforce batch
and tick-time budgets. It never writes impacts outside C0: it enqueues required
race jobs with copied uploader provenance, then waits for fenced post-tasks.

Readiness recounts the impact vector. All `FINAL` creates a summary atomically;
an all-zero vector becomes `ALL_ZERO`; any `UNSCORABLE` becomes `UNSCORABLE`;
deadline passage changes work to `EXPIRED_UNDELIVERED` and enqueues race-fenced
C0 cleanup to terminalize remaining impacts. Expiry correctness depends on the
work state/deadline immediately, not on completion of that asynchronous cleanup.
Use job fence `global_event_summary:<eventId>:<userId>:v2` with outcomes
`CREATED`, `ALL_ZERO`, `UNSCORABLE`, and `EXPIRED_UNDELIVERED`.

Capable `POST /steps/sync-v2` responses return an owner-scoped work receipt even
for qualifying no-op sync. Flutter polls the new narrow status endpoint below,
independent of the single lexicographically first race job. On `CREATED`, it
refetches Home and uses the existing overlay coordinator. Reverse race-job
completion cannot declare readiness early. Polling uses the existing bounded
foreground cadence (750 ms, 1.5 s, 3 s, then one coalesced request at most every
5 seconds) and continues until terminal state, backgrounding, sign-out, or
expiry. “Bounded” limits concurrency and frequency, not total foreground
duration. Resume/Home refresh starts a fresh read.

### 5. Reconciliation and failure handling

The same permanent work scheduler discovers ended version-2 entitlements and
stranded work. Before expiry it re-enqueues only with qualifying copied capture
evidence; it never manufactures freshness from worker time. Active, completed,
cancelled, forfeited, and terminal races all use the same scorer/C0 path.
Unreplayable input makes the row and group `UNSCORABLE`. After expiry, unresolved
rows become `EXPIRED_UNDELIVERED` without calculating a stale value. No manual
production rewrite is required.

Update account deletion to remove capture artifacts and summary-work rows in
dependency order before deleting the user. Extend global-event retention so
`UNSCORABLE` and `EXPIRED_UNDELIVERED` impacts/work are terminal rather than
perpetually unresolved; delete terminal v2 work, artifacts, and the
`global_event_summary:...:v2` job fence in the same retention transaction as
their event lifecycle. Preserve existing v1 retention behavior.

### 6. Summary query and cache expiry

Create a v2 summary only before expiry when every enrolled impact is v2
`FINAL`; keep the summary and v2 job-run outcome atomic. The shared Postgres
query requires owner, new capability/version, `acknowledgedAt IS NULL`,
`expiresAt > database NOW()`, and at least one nonzero final impact.

Replace the generic byte-identical 60-second cached read for this surface with
a specialized helper shared by both Home builders. Cache only immutable fields
plus `expiresAt`; never cache `validForMs`. The Postgres loader returns
`remainingMsAtLoad` from the same database-time snapshot as eligibility. On a
cache miss, calculate one conservative `adjustedRemainingMs =
remainingMsAtLoad - monotonicElapsedBeforeSet`. Use that same adjusted upper
bound for the fresh response and set physical Redis TTL to
`floor(adjustedRemainingMs / 1000)`—not the former 60 seconds. Skip caching
when adjusted remaining time is below one second. Add an atomic narrow
GET+PTTL helper; on a cache hit, `validForMs` comes only from positive,
well-formed Redis PTTL, whose original TTL was bounded by database time. A
missing/non-positive/malformed PTTL falls back to Postgres or no summary. Node
wall-clock time never extends the relative lifetime, and `validForMs` is
redecorated on every HTTP response.
Both Home builders wrap summary/cache failure so it omits the optional field
instead of failing Home. Bump the cache key to v3 and invalidate it on every
terminal impact/work transition, summary creation, and acknowledgement.

Expired rows are not synchronously deleted on Home requests; retention removes
them later.

## API contract

No existing endpoint gains a required parameter. New summary delivery is
capability-gated by `impact_summary_expiry_v1`.

### `POST /steps/sync-v2` additive response

For a capable user with version-2 ended-event work, the existing response may
add:

```json
{
  "globalEventSummaryWork": {
    "id": "work-id",
    "state": "WAITING_RACES",
    "expiresAt": "2026-08-27T04:00:00.000Z"
  }
}
```

The key is absent when there is no eligible work. It can be present even when
the sync is a scoring no-op. Old clients ignore it. Work ID is opaque and
owner-bound.

### `GET /home/global-event-summary-work/:id`

Owner-only status for foreground polling:

```json
{
  "state": "WAITING_RACES",
  "expiresAt": "2026-08-27T04:00:00.000Z"
}
```

States are `WAITING_SYNC`, `QUEUED`, `PROCESSING`, `WAITING_RACES`, `CREATED`,
`ALL_ZERO`, `UNSCORABLE`, or `EXPIRED_UNDELIVERED`. `CREATED` tells Flutter to
refetch Home; terminal non-created states stop polling. Return generic
`404 {error,code:"NOT_FOUND"}` for absent/foreign IDs, `400` for malformed ID,
and standard `401` for auth failure. The endpoint requires both summary
capabilities and never returns step totals, race IDs, capture provenance, or
diagnostic reasons.

### `GET /home/race-card`

The existing optional response remains:

```json
{
  "globalEventSummary": {
    "id": "summary-id",
    "eventId": "event-id",
    "extraRaceSteps": 1500,
    "raceCount": 3,
    "settledAt": "2026-08-26T20:30:05.000Z",
    "expiresAt": "2026-08-27T04:00:00.000Z",
    "validForMs": 26995000
  }
}
```

`globalEventSummary` is omitted unless both capabilities are present, and for
absent, version-1, acknowledged, all-zero, malformed, or expired summaries.
`expiresAt` is the immutable server deadline and
`validForMs` is the non-negative remaining lifetime calculated with the same
database-time snapshot used by the eligibility read. Both are additive:
frozen old clients ignore them. New Flutter requires both to retain an
off-Home/behind-another-modal summary; missing, malformed, non-finite, or
non-positive `validForMs`, or missing/malformed `expiresAt`, suppresses the
specialized popup safely. The backend clamps `validForMs` to the interval from
its authoritative read time to `expiresAt`.

Standard Home authentication and error behavior is unchanged. Summary lookup
remains fail-soft within the Home batch: a summary read/cache failure omits the
optional field rather than failing unrelated Home content.

### `POST /home/global-event-summaries/:id/acknowledge`

Empty request body and existing responses remain unchanged:

- `200 {"acknowledged":true}` for the authenticated owner's unacknowledged
  summary, including a modal served before midnight and dismissed just after;
- `404 {error,code:"NOT_FOUND"}` for absent/foreign IDs;
- `409 {error,code:"ALREADY_ACKNOWLEDGED"}` for an already acknowledged row.

Acknowledging an already-expired owned row is harmless but is not required for
correctness; the endpoint must not disclose another user's row.

## Frontend plan

Keep the existing modal and acknowledgement flow. Extend `MainShell`'s pending
summary parser/state so it:

- advertises `impact_summary_expiry_v1` from both feature-header branches;
- parses an optional sync-v2 `globalEventSummaryWork` receipt and polls its
  owner-only status independently of the existing single race-job poll;
- refetches Home on `CREATED` and stops on other terminal states, expiry,
  backgrounding, or sign-out; after the initial backoff it keeps one coalesced
  request at most every five seconds until the deadline;
- queues the optional Home summary only with valid additive expiry metadata;
- gates presentation to the visible/current Home route;
- renders the signed aggregate;
- acknowledges only after dismissal.

The backend is authoritative for same-day eligibility. Flutter must not derive
local midnight from device timezone or compare only against the device wall
clock. Start a monotonic stopwatch immediately before each Home request. On
receipt calculate `clientValidForMs = validForMs - completeRequestRoundTripMs`
and suppress when it is non-positive; subtracting the full round trip is
conservative because server calculation occurs within that interval. The app
then starts/continues a monotonic lifetime no longer than `clientValidForMs`;
before presenting a queued summary it checks that adjusted lifetime. A
timer clears pending state at expiry, but correctness also requires the
pre-presentation check because timers can pause in the background. A modal
already on screen is not dismissed by the timer. Missing
`globalEventSummary` continues to mean “show nothing.” A new app against an old
backend safely suppresses legacy summaries lacking the expiry fields rather
than risk showing yesterday's recap.

Work-status loading is invisible: there is no new spinner, card, toast, or
error surface. Network/not-found/malformed responses stop that poll and leave
Home usable; a later resume or pull-to-refresh can retry through normal sync.

The same Dart path ships on iOS and Android. Demo/tutorial Home previews do not
host `MainShell` summary state and remain unaffected.

## Backward compatibility and rollout

- Deploy backend first. No production deployment or database mutation occurs
  without explicit, in-the-moment user authorization.
- The migration is additive/nullable, so the old production backend remains
  valid during a rolling reload.
- Frozen old app versions do not advertise `impact_summary_expiry_v1`, so the
  new backend temporarily suppresses new recaps for them. This is intentional:
  those binaries can queue a pre-midnight response and display it after
  midnight. They retain all other Home behavior and can acknowledge a recap
  already served by the predeploy backend.
- A payload already held in an old process's memory before backend deployment
  cannot be recalled and may produce one late modal during that session. The
  rollout prevents all newly served violations; there is no safe server-side
  way to mutate an already-received payload.
- The new app advertises the additive capability and safely suppresses a
  malformed/old-backend summary lacking expiry fields. No existing field or
  request parameter becomes mandatory.
- The carrying Flutter build, if tests alone change, still accounts for both
  iOS and Android; no platform-specific implementation exists.
- Version-1 pending rows and summaries are treated as legacy/expired rather
  than reinterpreted. The normal v2 worker handles only version-2 lifecycle;
  no one-off production update is required or authorized by implementation
  approval.
- Production remains exactly two HTTP workers plus the established resolution
  and cron companions. No additional PM2 process is introduced.

## Tests-first plan

### Backend integration tests

Before business logic, add tests through real public/worker paths against the
dedicated local integration database:

1. A local event ends while two enrolled races remain active; the timer-only
   boundary resolution does not freeze the recap, the next user step sync
   finalizes both contributions, job-success Home refresh occurs, and one
   aggregate summary is returned.
2. The same summary is returned repeatedly before acknowledgement, is removed
   after acknowledgement, and is never duplicated by worker retry/concurrency.
3. The Home response omits an unacknowledged summary at exactly `expiresAt` and
   afterward even when no later event exists.
4. The expiry is the next midnight in the stamped entitlement timezone across
   ordinary, 23-hour, and 25-hour local days; changing the user's current
   timezone after entitlement creation does not move it.
5. No post-boundary upload before expiry, or a worker delayed until after
   expiry, records a terminal expired outcome and never creates a deliverable
   summary.
6. Mixed `+100/-100` final impacts yield a net-zero summary; an all-zero vector
   yields none.
7. A later race settlement cannot overwrite a boundary-finalized impact or
   alter an existing summary.
8. Completed and cancelled races with version-2 pending rows are reconciled or
   terminally diagnosed without a partial summary; one unscorable row suppresses
   the group.
9. A missing/untrusted timezone fails closed; version-1/null-expiry summaries
   cannot leak through Redis or cold Postgres paths.
10. Old capability receives no v2 summary; new capability receives expiry
    metadata; acknowledgement remains available to a legacy client holding a
    previously served summary.
11. A cached summary's TTL is bounded by expiry and a cache hit at/after expiry
    returns no summary.
12. A no-op post-boundary sync with adequate canonical coverage creates work;
    a request completed after the boundary without coverage does not.
13. User A's upload cannot finalize user B's impact during a full-field race
    resolution; reverse completion of two race jobs cannot ready the group
    early.
14. Version-2 parity cases cover 2x plus Wrong Turn (signed negative), freeze
    (zero), positive buff (multiplicative), Leech, Hitchhike, participant finish
    during the event, and identical boundary/settlement captures.
15. Race settlement before qualifying fresh sync does not finalize a v2 row;
    later settlement cannot overwrite a boundary-finalized value.
16. Redis loader delay, sub-second lifetime, invalidation failure, and Redis-
    absent paths preserve identical eligibility; both Home builders fail soft.
17. A second historical upload between two race-job commits cannot change the
    first capture artifact or produce a mixed-generation aggregate; every row
    verifies the same artifact provenance/digest.
18. Account deletion removes work/artifacts without FK failure; event retention
    recognizes both terminal non-final states and deletes v2 work, artifacts,
    and v2 job fences atomically.
19. Only summary rows explicitly stamped `attributionVersion = 2` are eligible
    for the new capability.

Use `npm run test:integration` only after confirming its `DATABASE_URL` is the
dedicated `*_test` database; never run bare `npm test` or any test against
production.

### Backend unit tests

Use unit tests only for structurally pure timezone/deadline vectors and
idempotent allocation helpers that integration cannot economically enumerate.
Run `npm run test:unit`.

### Frontend widget/integration tests

1. Pump the real `MainShell` with no `globalEventSummary`; no recap appears.
2. Pump it with a valid future `expiresAt`/`validForMs`; it appears once on
   Home, queues while off Home, and acknowledgement follows dismissal.
3. Fetch while off Home, advance the fake monotonic lifetime through expiry,
   then navigate Home; no recap or acknowledgement request occurs.
4. Present immediately before expiry, advance past expiry while the modal is
   open, then dismiss; the modal stays visible and acknowledgement occurs.
5. Missing, malformed, expired, or non-positive expiry metadata suppresses
   only the recap and does not break Home.
6. A sync work receipt polls independently of the reported race job; `CREATED`
   refetches Home, other terminal states stop, foreign/malformed/error responses
   fail soft, and background/sign-out cancels polling.
7. Both feature-header branches advertise the new capability; structural
   coverage prevents iOS/Android divergence.
8. Delay a Home response so its full round trip exceeds `validForMs`; the
   client-adjusted lifetime is non-positive and no modal is queued or shown.

Run the narrow suites first, then `flutter test` and `flutter analyze`.

## Observability and operations

Extend existing global-event observability with aggregate counts only:

- boundary impact rows finalized;
- ended-entitlement rows still pending, with oldest age;
- rows terminally unscorable by reason;
- summaries created before expiry;
- summary groups discarded as expired;
- unacknowledged unexpired summaries.

Do not log user IDs, race IDs, step samples, or individual totals. A healthy
state has no indefinitely pending row for an ended entitlement. Verification
is SELECT-only unless a later production repair receives separate explicit
authorization.

## Acceptance criteria and definition of done

- An eligible recap becomes available after the user's 2x entitlement ends,
  on the first completed post-boundary step sync, regardless of whether
  affected races remain active.
- It aggregates the canonical immutable signed event-boundary contribution
  across all enrolled races and appears at most once.
- It is never returned at or after the next midnight in the entitlement's
  stamped timezone, even if unacknowledged and no later event occurred.
- A response queued before midnight is not presented after midnight; a modal
  already presented before midnight may be completed normally.
- Yesterday's legacy or delayed recap cannot leak from Postgres or Redis.
- All-zero groups are suppressed; legitimate mixed net-zero groups remain.
- Race settlement cannot mutate a boundary-finalized recap.
- Existing endpoints, acknowledgement semantics, and consumed Home fields
  remain compatible; frozen clients intentionally receive no newly created v2
  recap because they cannot enforce expiry.
- Tests were written first and fail for the intended reason before business
  logic; backend unit/integration tests and frontend tests pass; `flutter
  analyze` is clean.
- Both platforms are accounted for; required architect, game-economy,
  UI-placement, and final code reviews are complete.
- No feature flag, staging start, production deploy, or production data write
  occurs without the authorization required by repository rules.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — same-day expiry for the global 2× event recap**

*Elements under test:* Existing `2× STEPS COMPLETE` modal remains centered over the real Home screen; it is conditionally presented only while an eligible recap is still valid, with no new inline Home card, banner, Inbox item, or duplicate modal added.

*Checklist*

1. **Real Home — cold app open (iOS)**
   - **Get there:** Use an iOS account with an eligible, unacknowledged same-day 2× recap → fully terminate the app → reopen it and land on Home.
   - **Verify:** The existing recap appears as one centered modal over Home after loading. It is not embedded in the Home feed, duplicated elsewhere on Home, or shown behind another route.

2. **Real Home — pull-to-refresh (Android)**
   - **Get there:** Use an Android account for which the eligible recap becomes available while the app is already open on Home → pull down to refresh Home.
   - **Verify:** The existing recap appears once as a centered modal after refresh. It is not also added as an inline Home element and does not remain or reappear in a second position after dismissal.

3. **Off-Home queued presentation**
   - **Get there:** Start on Races, Boards, Friends, or Profile with an eligible unacknowledged recap returned during a background/resume Home load → remain on that tab briefly → navigate to Home.
   - **Verify:** No recap overlays the non-Home tab. On entering Home before expiry, exactly one recap appears over Home; it is not left visible on the prior tab or duplicated during the tab transition.

4. **Non-current route and resume**
   - **Get there:** From Home, push a full-screen route such as Inbox or race details → background and resume the app while an eligible recap is available → return to Home before expiry.
   - **Verify:** The recap does not appear over the pushed route. It appears only after that route is closed and Home is again the current visible route, with no copy remaining behind it.

5. **Expiry before presentation**
   - **Get there:** Fetch an eligible recap while off Home or while another route/modal is covering Home → leave it queued until its supplied lifetime expires → navigate back to Home.
   - **Verify:** No recap appears anywhere after expiry: not over Home, not over the prior surface, and not as an inline or delayed duplicate after another refresh or resume.

6. **Expiry after presentation**
   - **Get there:** Open Home just before the recap expires so the modal is already visible → keep it open through expiry.
   - **Verify:** The centered modal remains in place until the user dismisses it; expiry does not remove it or reveal a second copy underneath. After dismissal, it does not reappear on Home.

7. **Home overlay ordering**
   - **Get there:** Use an account with both pending race results and an eligible 2× recap; repeat with a pending Home invitation as well → cold-open or resume on Home.
   - **Verify:** Pending race results appear first, the 2× recap appears only after results close, and the Home invitation appears only after the recap closes. No overlays stack visually, render behind one another, or cause the recap to appear outside Home.

8. **Cross-platform placement parity**
   - **Get there:** Repeat the eligible recap presentation once on iOS and once on Android, using cold open or Home refresh.
   - **Verify:** On both platforms the same existing centered Home modal is used, and neither platform adds a platform-specific alternate placement, duplicate, or stale recap after dismissal.

*Surfaces confirmed unaffected:*

- **Tutorial Home previews:** `tutorial_real_screens.dart` renders the shared `HomeTab` directly with offline fixture data, not the shell-owned `MainShell` recap state, so no recap should appear anywhere in the tab tutorial.
- **Demo race tutorial:** The demo flow hosts race/create/invite/detail surfaces rather than the shell-owned Home recap coordinator, so the recap should not appear over demo beats or coach chrome.
- **Race detail and its demo/tutorial mirrors:** Their active-event countdown banner is separate from the post-event Home recap; no placement change is expected.
- **Inbox:** The spec explicitly keeps the recap out of Inbox; no new row, badge, or completion message should appear there.
- **Onboarding:** The recap is owned by the authenticated real Home shell and should not overlay onboarding or tutorial steps.

*Risks found while planning:*

- The recap state is owned by `MainShell`, while tutorial Home renders `HomeTab` without `MainShell`; adding presentation logic to `HomeTab` would incorrectly leak the modal into tutorial previews.
- The shell has a deliberate overlay order—race results → 2× recap → Home invitations. Expiry clearing must not allow the recap to stack with or jump ahead of those surfaces.
- A queued recap can outlive a paused timer while the app is backgrounded; the placement gate must be rechecked before presentation on resume or Home navigation.
- A recap presented before expiry must stay visible through expiry, so cleanup must clear only queued state and must not pop the active dialog route.
- Standalone Home refresh can request presentation outside the coordinated initial-load path; it must still respect current-tab, current-route, and existing-modal placement guards.

## Revision log

- Draft 1: traced the production failure to event-end resolution enqueueing
  without impact finalization; proposed canonical boundary attribution,
  immutable race-settlement behavior, and server-owned same-local-day expiry.
- Gap pass 1: closed the off-Home queue/cache midnight leak by making expiry
  metadata additive in the Home contract, bounding cache lifetime, and adding
  a monotonic Flutter pre-presentation expiry guard while allowing an already
  visible modal to complete.
- Gap pass 2: prevented stale boundary totals by requiring the first committed
  post-event step-sync generation before immutable attribution; pinned expiry
  to `localDate + 1` midnight (DST-safe), specified job-poll Home refresh as the
  in-app delivery path, and made no-sync-before-midnight a terminal discarded
  outcome rather than a zero or late recap.
- Architect review: added a new-client capability gate; exact capture/work
  schema and terminal states; per-user no-op-sync provenance; full-interaction
  scoring and early-finish cutoffs; a durable group readiness/status-poll path;
  v2 event/job stamping; specialized deadline-aware Redis reads; and fail-soft
  handling in both Home builders.
- Game-economy review (`SOUND WITH CHANGES`): pinned zero score/coin EV, required
  that only the uploader's own capture can finalize their rows, prohibited
  partial groups, required full Wrong Turn/freeze/buff/Leech/Hitchhike parity,
  and versioned boundary attribution separately from historical settlement.
- UI-placement review: added the verbatim eight-scenario manual checklist and
  made shell ownership, overlay ordering, background timer rechecks, and
  already-visible-modal behavior explicit implementation constraints.
- Post-review gap pass: removed the last outside-C0 expiry-write ambiguity and
  made cached relative lifetime depend on database-bounded Redis PTTL, so
  process clock skew cannot extend delivery.
- Architect verification pass: added one immutable repeatable-read capture
  artifact set so later mutable sample uploads cannot split generations; made
  work polling continue at a coalesced cadence until expiry; added account-
  deletion and v2 retention seams; required summary attribution version 2; and
  removed Node wall-clock time from cached `validForMs` calculation.
- Final lock/cache verification: required the full dependency lock set,
  including uploader, in ascending order before intake; fixed canonical
  artifact limits/encoding/digest; and made cache TTL use the same monotonic-
  elapsed-adjusted lifetime as the fresh response.
- Final transport-expiry verification: subtracted the complete Home request
  round trip from server `validForMs` before queueing and added a latency-
  crosses-expiry frontend test.
