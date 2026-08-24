# Step Sync Fire-and-Forget Requirements

**Status:** Ready for development pending product approval

**Owners:** Mobile + backend

**Last updated:** 2026-08-24
**Related incident:** 2026-08-24, approximately 15:00 America/New_York

## 1. Summary and user story

At approximately 15:00 EDT, a burst of native background uploads saturated the
database transaction path even though the host itself remained healthy. The
current Flutter foreground path sends one durable `POST /steps/sync-v2`
request, but the current iOS and Android native background paths still send the
legacy pair `POST /steps` followed by `POST /steps/samples`. Those legacy
handlers persist input and then perform uploader race/box reconciliation before
returning. The queue therefore does not make those requests fire-and-forget.

The implementation must make **every step-upload path a short durable intake**:
validate, persist the canonical source input, atomically hand off any required
race work, respond, and let the race-keyed worker perform all race participant,
power-up, box, placement, and notification consequences. It must also move the
current native iOS and Android sidecars to the existing combined sync-v2
protocol so a normal background sync uses one request instead of two.

As a user, when my device uploads steps in the foreground or background, the
upload should finish quickly and reliably without making the app slow for
everyone, while my race totals and earned boxes become correct shortly after
the upload.

## 2. Goals

1. Remove race/box computation from the response path of all three write APIs:
   `POST /steps`, `POST /steps/samples`, and `POST /steps/sync-v2`.
2. Preserve every legacy endpoint, request shape, response shape, validation
   rule, authentication rule, and successful status code for frozen clients.
3. Guarantee that a successful response means both canonical step input and
   the required race-resolution ownership are durable; do not acknowledge a
   write that can be lost between source persistence and queue insertion.
4. Ensure the worker computes from newly persisted source data. A queued job
   must never take the existing `STEP_SYNC_COMMITTED` shortcut when its uploader
   participant row is still stale.
5. Use one sync-v2 request in current native iOS and Android background paths,
   with foreground-equivalent idempotency and fallback semantics.
6. Collapse overlapping device triggers so HealthKit, background task, silent
   push, WorkManager periodic work, and expedited work do not create a request
   stampede.
7. Suppress queue generations for scoring-equivalent repeat uploads while
   still refreshing sync-recency state as the current APIs require.
8. Prove correctness through public-path integration tests and a burst test
   that represents the observed legacy traffic shape.

## 3. Non-goals

- No visible UI, copy, navigation, animation, or placement change.
- No change to step scoring, power-up effects, box thresholds, race standings,
  payout rules, or economy values.
- No endpoint removal and no forced-upgrade policy.
- No release flag, percentage rollout, kill switch, temporary environment
  toggle, or third production API worker.
- No production deploy, production database write, staging startup, or App
  Store/Play Store submission as part of implementation approval. Each
  operational action retains its existing separate approval gate.
- No promise that a race read immediately following the upload sees the new
  total. Race-derived state is explicitly bounded eventual consistency.

## 4. Evidence and problem statement

### 4.1 Incident evidence

For the 15:00 EDT minute, native iOS generated approximately 458 `POST /steps`
and 456 `POST /steps/samples` requests. `/steps/samples` reached roughly 3.5 s
p50, 6.6 s p95, and 22.2 s maximum. The same minute's `/steps/sync-v2` traffic
was roughly 0.25 s p50 and 1.33 s p95. Cached manifest traffic remained near
3 ms, the host was about 89% idle, and memory, disk, network, nginx, Redis, and
both PM2 workers remained healthy. Prisma reported P2028 transaction-start
failures. This identifies database transaction contention on step ingestion,
not exhausted web-host CPU or network capacity.

### 4.2 Current path inventory

| Trigger/path | Current HTTP behavior | Current server behavior | Target |
|---|---|---|---|
| Flutter foreground (`MainShell`) | One `/steps/sync-v2` request | Durable source + reservation/queue, uploader reconciliation currently permanently deferred | Keep one request; fix deferred-worker correctness |
| iOS HealthKit observer | `/steps`, then `/steps/samples` | Legacy response path, including inline uploader reconciliation | One `/steps/sync-v2`; coalesced |
| iOS BGAppRefresh | `/steps`, then `/steps/samples` | Same legacy pair | One `/steps/sync-v2`; coalesced |
| iOS silent step-sync push | `/steps`, then `/steps/samples` | Same legacy pair | One `/steps/sync-v2`; coalesced |
| Android periodic WorkManager | `/steps`, then `/steps/samples` | Same legacy pair | One `/steps/sync-v2`; serialized |
| Android expedited sync | `/steps`, then `/steps/samples` | Same legacy pair | One `/steps/sync-v2`; serialized |
| Frozen app versions | Legacy pair | Inline uploader reconciliation | Same wire contract; durable queue-only derived work |

The current queue owns bulk race resolution, but both legacy commands still
call `reconcileUploaderRaces`. That call writes the uploader participant and
box state before returning, so “enqueue” is not equivalent to “respond.”

### 4.3 Correctness defect to fix before broadening queue-only behavior

`sync-v2` permanently reports uploader reconciliation as `DEFERRED`, but its
queue envelope is currently `STEP_SYNC`. On a zero-active-effect race, the
worker may select `STEP_SYNC_COMMITTED`, which deliberately republishes the
participant total already committed by an inline uploader reconciliation. If
no inline reconciliation occurred, that participant value can be stale. The
existing integration coverage proves the queue row exists, but does not prove
the worker later derives the new participant total from source input.

The implementation must fix this distinction first. Removing the remaining
legacy inline calls while retaining the same ambiguous reason would expand the
defect.

## 5. Required design

### 5.1 Two explicit queue meanings

Add the closed dirty reason `STEP_INPUT_CHANGED` with this invariant:

- `STEP_INPUT_CHANGED`: canonical daily/sample source input committed, but the
  uploader participant and box state are **not** known to be reconciled. The
  worker must compute the dirty uploader from persisted source data and may not
  choose `STEP_SYNC_COMMITTED`.
- `STEP_SYNC`: uploader participant state was already committed before enqueue.
  Existing cheap committed/incremental behavior and its tests remain valid.

`STEP_INPUT_CHANGED` is a correctness state, not a feature control. Add it to
the reason registry and every database-side allowlist. Its dirty envelope is
`dirtyUserIds:[uploader]`, the accepted participant ID when available,
`powerupTypes:[]`, and `priority:COALESCE`. Missing/invalid IDs, unknown reason
sets, scope-cap overflow, or incoherent state must degrade to `FULL`, never to a
narrow no-op.

Planner rules:

1. Before plan selection, load the scoring generation and
   `sourceQueueSemanticsGeneration` for every distinct processing trigger/dirty
   user without taking a row lock. If any pair differs (including null stamp),
   promote an existing `STEP_SYNC` claim to `STEP_INPUT_CHANGED` semantics in
   memory. This lets a new worker safely process a job enqueued by an old worker
   immediately, even if no later client request occurs. The promoted claim is
   fingerprint-fenced exactly like a native `STEP_INPUT_CHANGED` claim. Do not
   persist the ownership stamp from the worker while holding the race-job fence;
   intake owns that stamp to avoid the scoring-row → queue-row versus queue-row
   → scoring-row lock inversion. A later new intake may enqueue one harmless
   stamped repair, but correctness of the existing job does not depend on it.
2. Keep committed-scope admission and source-input closure admission as two
   different predicates. `buildRaceResolutionStepSyncScope` remains eligible
   only for existing `STEP_SYNC` sets and can never receive
   `STEP_INPUT_CHANGED`. A new source-input predicate admits a pure
   `STEP_INPUT_CHANGED`, or its explicitly allowed merge with
   `DISPLAY_REFRESH`, to the canonical dependency-closure planner for the dirty
   uploader.
3. It must account for active effects, team dependencies, Trail Mine,
   Hitchhike, Leech, Sneaky Swap, Pocket Watch, and any other dependency exactly
   as the full resolver does. If closure cannot prove a bounded safe scope, use
   `FULL` in the same worker generation.
4. A merge of `STEP_INPUT_CHANGED` with `STEP_SYNC` retains
   `STEP_INPUT_CHANGED` semantics. Already-committed work must never erase
   pending source work.
5. A merge with an unclassified scoring reason degrades to `FULL`.
6. Every claim whose merged reasons contain or are promoted to
   `STEP_INPUT_CHANGED` must capture
   and revalidate the exact input fingerprint and queue generation, regardless
   of whether its selected plan is dependency closure or `FULL`. Reuse
   `buildRaceResolutionInputFingerprint`, whose digest already includes scoring
   generations, membership, race state, effects, and global boundaries. Do not
   take a scoring-input row lock while holding the race-job fence; that would
   invert the intake/worker lock order. Before each compute attempt, capture
   `plannedAgainstGeneration` plus the fingerprint. At the fence, compare the
   current job generation to that captured generation and recompute the digest.
   If the digest, generation, or validity window changed, write/mint nothing,
   leave the transaction, refresh inputs, and recompute `FULL` in the same
   leased claim. A subsequent stable attempt may commit against the freshly
   captured current generation; normal `recordSuccess` supersession still
   leaves any later generation queued. This prevents a high upload corrected
   downward during an effect-heavy FULL computation from transiently minting a
   box or consuming an effect.
7. The worker remains the only writer of derived race participant and box state
   for queue-only uploads. Existing post-commit delivery intents and overtaken
   rival sync nudges remain worker-owned.

The queue-reason addition itself requires no schema change: queue reasons are
JSON and unknown reasons already fail closed to `FULL`. The separate one-time
repair stamp in section 7 is an additive migration that old workers ignore.
During a rolling PM2 reload, an old worker that claims a new reason therefore
computes the safe full plan. Tests must prove that mixed-version property rather
than relying on the comment.

### 5.2 Shared atomic source-intake transaction

Refactor source persistence behind `buildStepInputIntake(dependencies = {})`,
used by all three commands. Inject Prisma, source models, race/job models, and
clock following the repository's existing command/model factory pattern; allow
an optional caller-provided `tx` for composition and avoid hard-imported
singletons in the implementation seam. It accepts an optional daily row, an
optional normalized sample batch, authenticated user ID, request timezone, and
request timestamp. Cache invalidation and event emission remain outside this
service and outside its transaction.

For sync-v2, perform the preliminary same-key replay lookup before opening the
outer transaction. Within one database transaction, in this order:

1. For a new sync-v2 key, create/admit the idempotency reservation before the
   scoring lock or source work. A concurrent same-key unique-key loser rolls
   back without doing intake work, then reads/replays the winner. Legacy calls
   have no reservation step.
2. For a foreground home pull, conditionally admit the existing database-clock
   cooldown stamp.
3. Lock that user's scoring-input state once and read its current generation.
4. Read the canonical before-watermarks needed for no-op classification.
5. Upsert the supplied daily row and/or reconcile the supplied sample batch.
   Add caller-transaction variants to the model methods instead of opening a
   nested transaction. Keep existing model entry points as wrappers so other
   callers remain compatible.
6. Read the canonical after-watermarks, persist the scoring version exactly
   once, and derive `storageChanged`, `scoringChanged`, and the resulting
   scoring generation.
7. Compare `sourceQueueSemanticsGeneration` with that resulting scoring
   generation under the same lock. A mismatch means `repairRequired`, even if
   `scoringChanged` is false. This owns marker-less-era source and any newer
   generation written by an old/mixed worker that cannot stamp queue ownership.
8. If `scoringChanged || repairRequired`, select the user's currently ACTIVE
   accepted races using the transaction client in stable race-ID order and
   batch-upsert their queue rows as `STEP_INPUT_CHANGED`. Queue errors propagate
   and roll back source persistence. If no active races exist, no queue row is
   required.
9. Set `sourceQueueSemanticsGeneration` to the resulting scoring generation in
   the same transaction, after enqueue succeeds (or after proving there are no
   active races). Old code never updates this stamp, so any later old-worker
   generation automatically creates a detectable mismatch.
10. For sync-v2, store the complete response and mark the reservation
   `COMPLETE` only after source and all queue rows are ready to commit. A new
   request has no source-only PROCESSING stage.
11. Return the persistence result to the command only after commit.

The service must not perform participant resolution, box synchronization,
power-up resolution, placement computation, pushes, or remote cache work in
the transaction. Active-race selection must use a lean projection containing
only race and accepted-participant identity required for enqueue.

After commit, preserve current non-critical side effects without extending the
durability boundary:

- Best-effort update `lastStepSyncAt` for `/steps` and sync-v2, including a
  scoring-equivalent upload. A timestamp failure is observable but does not
  roll back source/queue or turn their successful wire response into a 5xx;
  holding the `users` row lock across sample reconciliation is prohibited.
- Invalidate the daily-step read cache for a daily write. Failure remains
  swallowed and observable as today.
- Emit the same logical `STEPS_RECORDED`/`STEPS_UPDATED` event once per accepted
  daily API call. Sync-v2 retains its reservation guard so replay emits once.
- Do not emit a new daily event for `/steps/samples`.
- Delivery intents and overtaken-rival nudges arise from the worker's committed
  race result, not from intake.

An acknowledged request can therefore mean either “no scoring change” or
“source and queue ownership committed.” There is no source-only success state.

Pre-change sync-v2 PROCESSING reservations remain readable during rolling
deployment. The existing recovery branch may complete those legacy rows, but
new-code reservations use the one-transaction protocol. Once compatible old
PROCESSING rows have aged out under the existing retention policy, that branch
may be removed only in a separately reviewed cleanup.

For a foreground `homePull` sync-v2 request, `recordStepSyncV2` owns the outer
transaction. It resolves an existing same-key replay before opening the
transaction; for a genuinely new key, reservation admission is the first
transactional write, followed by the existing database-clock conditional
update of `last_home_pull_step_sync_at`, then
`buildStepInputIntake(..., tx)`. Different concurrent keys still admit at most
one request per cooldown window. Queue/source failure rolls the cooldown stamp
back; same-key replay during the window returns its stored 202 instead of 429.

### 5.3 Durable box consequences inside the worker fence

Removing inline uploader reconciliation makes the queue worker the only chance
to mint threshold boxes. The current post-commit `syncRacePowerupState` call is
best-effort after `recordSuccess`, so it is not sufficient.

Refactor `syncRacePowerupState` and `rollPowerup` to accept a caller-provided
transaction. Within the race worker's existing fenced write transaction:

1. validate the job/input fence;
2. resolve all triggering accepted participants, sort by user ID then
   participant ID, and acquire every existing participant advisory transaction
   lock in that order **before the first participant-row write**;
3. apply participant totals and scoring side writes;
4. process all triggering accepted participants in the same stable order,
   using their computed box-effective totals;
5. with its advisory lock already held, re-read `nextBoxAtSteps`, and atomically
   create/queue/forfeit each earned box, advance the threshold, and persist its
   feed row;
6. only after all participant and box writes succeed, call `recordSuccess`.

`rollPowerup` must not open a nested transaction or reacquire the advisory lock
in this path. Its existing standalone entry point remains a wrapper that opens
its own transaction for
other callers and preserves its advisory-before-participant order. Capture
post-commit event payloads during the transaction, then
publish event-bus notifications and Redis recent-box toast bookkeeping only
after commit. Those projections may be retried/rebuilt and never determine
whether the box exists. Any box write failure rolls back totals, box changes,
and job success together so the leased job retries. Race/participant status and
settlement fencing are rechecked inside the same transaction. The transaction
duration must have its own capacity gate because this change moves bounded box
writes under the fence.

### 5.4 Legacy endpoint contract

#### `POST /steps`

Keep all current authentication, validation, date parsing, and optional
`skipRaceResolution` acceptance. Keep HTTP 200 and the exact `{record: ...}`
JSON shape, including the compatibility `stepGoal` behavior. The parameter
`skipRaceResolution` becomes a compatibility no-op for scheduling: both true
and false use queue-only derived work. Do not remove or reject it.

Daily create/update races from concurrent devices continue to converge through
the unique `(userId,date)` authority. A scoring-equivalent update refreshes
`lastStepSyncAt`, invalidates the daily read cache, emits the current update
event, and does not bump a queue generation.

#### `POST /steps/samples`

Keep HTTP 200 and `{count:<normalized overlap-cleaned input count>}`. Preserve
manual-sample rejection, required fields, overlap/granularity behavior, same
start replacement, open-hour handling, 400 for empty/non-array input, and all
existing payload limits. Enable canonical no-op suppression. An identical or
scoring-equivalent batch does not bump the scoring version or queue generation.

#### Error semantics

- Validation/authentication failures remain their existing 4xx responses and
  create neither source rows nor queue rows.
- A source or queue transaction failure returns the existing generic 5xx path
  with neither source nor queue committed.
- Retried legacy requests may repeat after an ambiguous transport failure. The
  unique source keys plus canonical no-op suppression make those retries
  idempotent for scoring and queue generation even though frozen clients do not
  supply an idempotency key.

### 5.5 Sync-v2 contract

Keep the public request and response schema unchanged:

```text
POST /steps/sync-v2
Authorization: Bearer <session>
Idempotency-Key: <UUID>
X-Timezone: <IANA timezone>
Content-Type: application/json

{ "date": "YYYY-MM-DD", "steps": <nonnegative integer>, "samples": [...] }
```

Successful fresh requests and same-key replays both return HTTP 202, matching
the existing route contract, and retain `record`, `sampleCount`,
`uploaderReconciliation`, and `raceResolution`. Continue returning
`uploaderReconciliation.state:"DEFERRED"`, `resolvedRaceCount:0`, and
`boxStateCurrent:false`; do not claim current derived state. The reservation,
daily input, samples, and `STEP_INPUT_CHANGED` queue rows commit atomically
without an inline uploader pass. `lastStepSyncAt` is stamped best-effort after
that commit.

Add one optional field to fresh and stored replay responses:

```json
{ "stepIntakeSemantics": "CANONICAL_SOURCE_QUEUE_V1" }
```

Frozen clients ignore the additive field. It certifies that a 202 came from a
backend where source input is atomically owned by a worker plan that recomputes
from source. Store it in `responseJson`, so same-key replays preserve it. It is
not a release flag and has one permanent meaning.

The existing idempotency guarantees remain:

- same key + same canonical body replays the stored outcome;
- same key + different canonical body is 409 `IDEMPOTENCY_CONFLICT`;
- an expired PROCESSING lease is recoverable;
- event emission occurs once;
- no-op replay does not create another generation;
- malformed/oversized/unauthorized requests do not persist.

Recovery of a pre-change PROCESSING row must enqueue `STEP_INPUT_CHANGED`, not
`STEP_SYNC`, and finalize with the capability marker. New requests have no
source/enqueue crash gap: induced failures at any point in reservation, source,
active-race lookup, queue insertion, response storage, or finalization roll the
entire transaction back. A completed response is never stored before queue
ownership commits.

### 5.6 iOS native client

Replace the two calls in `BackgroundStepSyncCoordinator` with one combined
sync-v2 call using the same date, daily total, and closed hourly samples already
read from HealthKit. Preserve HealthKit authorization and local-date fallback
behavior.

Introduce a testable native request builder/transport with:

- UUID idempotency key;
- one immutable serialized request body per logical attempt;
- `Authorization`, `Idempotency-Key`, `X-Timezone`, `Content-Type`, and an
  `X-App-Version` derived from the bundle when available;
- one retry for an ambiguous timeout/connection failure or retryable 5xx,
  reusing the exact key and bytes;
- success on HTTP 202 replay/fresh responses only when
  `stepIntakeSemantics:"CANONICAL_SOURCE_QUEUE_V1"` is present;
- legacy fallback after a definite 404, JSON 503 `ASYNC_DISABLED`, or a
  confirmed 2xx response without that capability marker;
- no legacy fallback after an ambiguous result, 409 conflict, 400, 401/403,
  413, or 429, because sync-v2 may already have persisted or the result is a
  permanent/cooldown class;
- on permitted fallback, preserve the existing `/steps` then `/steps/samples`
  calls and response handling for a backend older than the app.

The background request must not send the foreground home-pull intent header,
so it does not consume the interactive cooldown contract.

Add an actor/serial-queue single-flight gate around the whole read-and-upload
cycle. At most one request is active. Triggers arriving while it runs set one
trailing-run bit and attach their OS completion handlers. After the active run,
perform at most one fresh HealthKit read/upload for all accumulated triggers;
triggers arriving during that trailing run repeat the same bounded rule. This
does not lose a step change that arrived mid-flight and does not issue one
request per callback. Every silent-push fetch completion and BG task completion
must be invoked exactly once. Expiration cancels/join-detaches only the expired
OS task; it must not double-complete another trigger or corrupt the active
request.

Persist one pending sync-v2 envelope before network transmission in the app's
shared preferences: owner backend user ID, backend base URL, idempotency key,
canonical body bytes, and creation time. On the next invocation, replay that
envelope before reading/sending fresher data. Keep it after an ambiguous
outcome. Any HTTP 2xx makes persistence status known: clear the v2 envelope,
record malformed/missing-marker diagnostics when applicable, and run a trailing
fresh read. A 2xx without the capability marker additionally starts the legacy
pair. On 409, clear the conflicting envelope and immediately build a fresh
key/body from a new Health read, without legacy fallback. On 400, 401/403, 413,
or 429, clear the envelope, apply the terminal outcome mapping, and let a future
normal trigger re-read Health data.

Legacy fallback has its own persisted envelope containing the immutable daily
and samples bodies plus `dailyComplete` and `samplesComplete`. Clear it only
when both required legacy calls succeed. On partial success, retain/retry the
unfinished stage; repeating either call after process death is safe through
source uniqueness and canonical no-op suppression.

The v2 and legacy envelopes are valid only when both stored owner ID and
backend URL match the current session. Missing owner ID means do not send.
Sign-out/delete-account must remove them; a different account or backend must
discard them without transmission. A corrupt envelope is discarded locally and
followed by a fresh sync. A structurally valid owner/backend-matching envelope
has no age TTL and remains until definitively resolved; replaying an old
idempotency key after server retention expires is still safe because canonical
no-op suppression handles a possible earlier commit.

Persist a negative capability result by owner/backend with a 24-hour expiry so
an older backend does not receive a compatibility probe on every trigger. A
positive result is never trusted without checking the marker on each 202, so a
backend rollback is detected immediately. Account/backend change clears the
cache; expiry permits discovery after an older backend is upgraded.

Before starting a retry or trailing run, compare the remaining iOS background
execution budget with a conservative request deadline. If insufficient, retain
the relevant envelope and complete/detach that OS callback exactly once; the
next trigger resumes it. One BG task's expiry must not cancel the shared logical
sync for other attached triggers.

### 5.7 Android native client

Give `StepSyncWorker` the same combined request builder, response classifier,
idempotency retry, pending-envelope, account/backend partitioning, capability,
and legacy fallback contract as iOS. Keep the existing Health Connect query but
change sample emission to closed buckets only: floor the cutoff to the last
completed local-hour boundary and never send a partial current-hour interval.
The floor must be correct across DST gaps and repeated hours.

Periodic and expedited work must share one process-wide serialized sync engine
and one cross-invocation durable pending envelope. WorkManager may schedule the
two work types independently, so correctness cannot rely only on their current
different unique-work names. Use a process `Mutex` for simultaneous workers;
after acquiring it, re-read preferences and Health Connect rather than using a
pre-lock snapshot. A worker that finds/resolves an ambiguous pending envelope
then performs one fresh read. Existing unique periodic `KEEP` scheduling stays;
expedited requests may continue replacing queued expedited requests, but they
must not bypass the shared mutex.

Map outcomes deliberately:

- valid server success, definitive auth loss, invalid payload, cooldown, or
  supported legacy success: `Result.success()` (a future user/device event can
  try again; WorkManager must not hammer a permanent 4xx);
- ambiguous/retryable network or 5xx after the one inline retry:
  `Result.retry()` with the pending envelope retained;
- absent session, backend URL, backend user ID, Health Connect permission, or
  available data: `Result.success()` with no request;
- corrupt local pending state: delete it and attempt one fresh sync.

Refactor native health/state/network dependencies behind interfaces so JVM
tests do not require real Health Connect or production HTTP.

### 5.8 Shared preference lifecycle

The existing Flutter `auth_backend_user_id` key is readable natively as
`flutter.auth_backend_user_id`. Extend both native state stores to require it.
Add platform-specific v2 pending, legacy-stage pending, and negative-capability
keys under the existing Flutter
SharedPreferences/UserDefaults container and list those keys in
`AuthService.signOut()` cleanup. Delete-account inherits sign-out cleanup.
Backend base URL remains build-time-derived and persisted by
`BackgroundSyncBootstrapService`; a mismatch invalidates a pending envelope.

Preference writes must be atomic from the client's perspective: write the full
serialized envelope to one string key, then read/decode/validate it as a unit.
Never log the session token, body, user ID, raw step counts, or samples.

## 6. Edge cases and invariants

1. **No active races:** persist valid source input, return normally, enqueue no
   race job.
2. **Many active races:** batch enqueue in stable race-ID order in one SQL
   statement; preserve deadlock prevention and scope caps.
3. **Concurrent devices:** the per-user scoring-input lock serializes canonical
   classification. Final worker state reflects the latest committed source,
   and a generation remains when an input commits during a running claim.
4. **Legacy split pair:** `/steps` may enqueue before `/steps/samples`; debounce
   should normally coalesce them. If the worker claims between calls, the
   second scoring change queues/follows with a newer generation, so final state
   uses samples without relying on timing.
5. **Daily succeeds, samples never arrives:** daily-derived race state still
   resolves; there is no dependence on the second legacy call.
6. **Identical repeats:** preserve storage/last-sync/event semantics, but create
   no scoring generation.
7. **Ambiguous mobile response:** never switch to legacy, because the first
   request may have committed. Replay exact sync-v2 key/body.
8. **Process death:** pending envelope is replayed before fresh data. Server
   idempotency resolves whether the earlier request committed.
9. **Logout/account switch:** never upload one account's pending body under
   another account's token.
10. **Backend URL/flavor switch:** never replay staging data to production or
    production data to staging.
11. **Timezone travel/DST:** preserve the request's IANA timezone and existing
    local-date/sample-window semantics. Queue merge may use the latest request
    timezone, while race scoring continues to honor the race's pinned timezone.
12. **Open buckets:** native clients keep excluding the unclosed current bucket;
    backend overlap/granularity guards remain authoritative.
13. **Manual Health data:** preserve current rejection/filtering; do not make
    migration to sync-v2 admit manual samples.
14. **Finished, forfeited, cancelled, or ended races:** intake only selects
    currently ACTIVE accepted participation. Worker fencing rechecks race and
    participant status before writes.
15. **Race finishes while queued:** canonical settlement/fence behavior wins;
    no post-finish live write or duplicate payout.
16. **Power-up/box boundary:** worker commits the same totals, one-time effects,
    inventory/queued box behavior, and `nextBoxAtSteps` as the prior
    inline+worker sequence in the fenced transaction, before job success,
    without duplicate minting.
17. **Queue insertion failure:** source transaction rolls back and the API does
    not return success.
18. **Worker failure/lease expiry:** existing retry/backoff/recovery owns the
    job; source remains durable and no second intake is required.
19. **Unknown/new reason under old worker:** normalize/degrade to `FULL`; never
    drop the work or select the committed shortcut.
20. **Oversized/corrupt payload or pending envelope:** fail closed without
    alternate-path double posting. The native payload remains within sync-v2's
    existing sample-count/body limits (normally at most 24 hourly rows).
21. **Silent push burst:** iOS single-flight and server no-op suppression bound
    device and queue amplification even when several trigger sources coincide.
22. **PM2 topology:** production remains exactly two application workers.

## 7. API, storage, and data contract

No public route or required parameter is added or removed. The one public
change is the optional additive sync-v2 response field
`stepIntakeSemantics:"CANONICAL_SOURCE_QUEUE_V1"`; frozen clients ignore it.

Add one backward-compatible database column to
`user_scoring_input_versions`:

```text
source_queue_semantics_generation bigint NULL
```

Null or a value different from the row's `generation` means the canonical
source generation is not proven to have atomic queue ownership. Equality means
the new intake transaction durably enqueued that generation (or proved there
were no active races). This ownership stamp is not a feature flag. New code
reads/sets it under the existing per-user scoring-input row lock. Old code
ignores the additive column and advances only `generation`, so mixed workers or
a rollback naturally make the values differ. A new worker promotes any already-
queued `STEP_SYNC` claim with that mismatch to source-input computation without
waiting for another client request; the next new-code intake also stamps the
generation and, if necessary, owns one repair enqueue. The migration is safe
before and during a rolling application reload. No column is dropped or made
newly required in an API.

Internal additive contract:

```json
{
  "reason": "STEP_INPUT_CHANGED",
  "dirtyUserIds": ["<uploader-user-id>"],
  "dirtyParticipantIds": ["<accepted-participant-id-if-known>"],
  "powerupTypes": [],
  "priority": "COALESCE"
}
```

Internal semantics, not wire-visible:

- `STEP_INPUT_CHANGED` means “read canonical source and score.”
- `STEP_SYNC` means “participant is already committed; publish/sync derived
  consequences.”
- `FULL` remains the safe fallback.

The queue row continues to be keyed by race, with generation merge,
`triggeredByUserIds`, lease fencing, retry, debounce, and queue priority as
currently implemented.

Postgres remains the source of truth for daily steps, samples, scoring-input
generations, sync-v2 reservations/responses, race queue ownership, participant
and box state, settlement, payouts, and coins. The durable race queue remains
Postgres. Redis gains no key, flag, lock, or source-of-truth role. Existing
daily/race caches and recent-box toast signals remain rebuildable projections
with PostgreSQL fallback. All correctness suites must pass with `REDIS_URL`
unset; tests that explicitly exercise Redis use local test database 15 and
never production Redis.

## 8. Compatibility and rollout

### 8.1 Version matrix

| Client | Backend | Result |
|---|---|---|
| Frozen legacy | New | Same legacy 200 JSON; derived race state updates asynchronously |
| Current Flutter sync-v2 | New | Same fields plus ignored additive marker; corrected queue computation |
| New native | New | One idempotent sync-v2 request with required marker |
| New native | Pre-fix backend that already has sync-v2 | Confirmed marker-less 202 is resolved, then durable legacy pair runs and negative capability is cached |
| New native | Older backend without sync-v2 | Definite 404/`ASYNC_DISABLED` falls back to durable legacy pair |
| New native | Backend rollback after app release | Every 202 is marker-checked; marker loss immediately selects legacy compatibility |
| Any client | Rolling mixed backend workers | Old code ignores the additive generation stamp; new workers promote its mismatched STEP_SYNC jobs to source-input work, and unknown reasons degrade to FULL |

### 8.2 Deployment order

1. Land backend tests first and demonstrate the current deferred sync-v2
   zero-effect failure.
2. Implement the additive compatibility-stamp migration, backend reason/planner,
   and atomic intake changes; run backend unit, integration, and isolated
   capacity suites.
3. With separate in-the-moment authorization, apply the additive migration and
   deploy backend first. Production
   remains two PM2 workers. Verify error rate, P2028 count, intake latency,
   queue lag, failure/retry/dead-letter counts, and final-state parity.
4. Implement and verify iOS and Android native clients against the already
   compatible backend.
5. Build both platforms in lockstep and release through the normal phased store
   process. Frozen clients continue using the now-lightweight legacy handlers.

No release flag is necessary: the backend behavior is permanent, legacy
contracts remain present, and unknown reason values are fail-safe during mixed
code deployment.

### 8.3 Eventual-consistency service objectives

Against the isolated two-worker capacity profile and a dedicated non-production
database:

- each step intake endpoint: p95 <= 2 seconds and p99 <= 5 seconds;
- source-intake transaction duration: p95 <= 1 second and p99 <= 3 seconds;
- worker fenced transaction including box consequences: p95 <= 2 seconds,
  p99 <= 10 seconds, and no transaction reaches its 15-second timeout;
- no P2028 transaction-start failures, deadlocks, or pool timeouts;
- claimable queue oldest-age p95 <= 10 seconds and never above 30 seconds in a
  steady-state gate;
- 99% of successful changed uploads reflected in canonical race/box state
  within 15 seconds and 100% within 60 seconds absent a declared worker outage;
- identical repeat traffic creates zero additional scoring generations;
- one current native background cycle creates one HTTP write, except a single
  same-key retry or definite legacy fallback.

These are release gates for this change, not a promise that every individual
mobile network completes within those durations.

## 9. Observability

Use existing structured capacity and queue metrics; add only bounded,
non-sensitive dimensions needed to distinguish:

- intake endpoint (`steps`, `samples`, `sync-v2`);
- source outcome (`changed`, `scoring_noop`, `validation_error`,
  `transaction_error`);
- queue reason/plan (`STEP_INPUT_CHANGED`, `STEP_SYNC`, `FULL` and selected
  resolution plan);
- enqueue race count and generation outcome when available;
- worker queue age, duration, retry, lease recovery, dead-letter, and fallback
  reason;
- native trigger kind, coalesced/trailing-run count, protocol selected
  (`sync-v2` or definite legacy fallback), and broad outcome class.

Never log auth tokens, user IDs, participant IDs, idempotency keys, request
bodies, step totals, sample timestamps, or health metadata. Alerts should cover
P2028/deadlock/pool errors, oldest claimable queue age >30 seconds, nonzero
dead-letter growth, and sustained intake p95 above the gate.

## 10. Test-first implementation plan

All business-logic changes begin with failing tests that demonstrate the public
behavior. Backend integration tests must confirm `DATABASE_URL` names the
dedicated `steps-tracker-integration_test` database before any mutation. Never
run them against production.

### 10.1 Backend integration tests

1. Through real HTTP and the real test DB, pause worker claiming, post to each
   endpoint, and assert the response returns with source + queue durable while
   participant totals/box state have not changed inline. Run the worker and
   assert exact eventual total and box state.
2. Add the regression that currently fails: sync-v2 deferred upload into a
   zero-effect race whose participant total is stale. After worker completion,
   assert the new source total is reflected and the selected plan is not
   `STEP_SYNC_COMMITTED`.
3. Preserve an existing already-committed `STEP_SYNC` integration case and
   assert it still selects `STEP_SYNC_COMMITTED`.
4. Force queue insertion failure inside intake and prove neither daily/sample
   source nor queue commits and no 2xx is returned.
5. Post identical daily and sample payloads twice. Assert wire responses remain
   compatible, `lastStepSyncAt` normally advances for daily, and generation
   does not after generation ownership is current. Seed a null ownership stamp
   plus a pre-change COMPLETE marker-less reservation and stale zero-effect
   participant; assert the first scoring-equivalent new request enqueues one
   repair, stamps the current generation, and heals the row, while concurrent/
   subsequent no-ops enqueue none. Then let an old-worker simulation advance
   scoring generation N to N+1 without the ownership stamp and enqueue the old
   `STEP_SYNC` reason. Without another intake request, run a new worker and
   assert it promotes that existing claim, computes N+1 from source, and never
   selects `STEP_SYNC_COMMITTED`. A later scoring-equivalent new intake may then
   stamp/enqueue its single ownership repair; subsequent no-ops enqueue none.
   Inject a timestamp-stamp failure and assert committed source/queue still
   returns the normal response.
6. Post changed input while the prior generation is RUNNING. Assert the newer
   generation remains and final derived state uses the latest canonical input.
7. Race concurrent `/steps` and `/steps/samples` calls and separately force a
   worker claim between the pair. Assert no deadlock and final sample-aware
   result.
8. Exercise zero, one, sixteen, and the supported maximum practical active
   races; assert stable lock order, bounded SQL calls, and one row per race.
9. Exercise active effects and dependencies: self-only effects, team effects,
   Trail Mine, Hitchhike, Leech, Sneaky Swap, and Pocket Watch. Compare eventual
   participant writes/events/box state to canonical full resolution. During an
   effect-heavy FULL run, pause after compute, commit a corrective lower input,
   and assert the stale plan writes/mints/consumes nothing before the same claim
   refreshes and recomputes FULL.
10. Cross box thresholds with free inventory, full inventory/queued box,
    multiple-threshold input, and repeat/replay; assert no missing or duplicate
    box and correct `nextBoxAtSteps`. Inject a box write failure before
    `recordSuccess`; assert totals/boxes/job-success roll back together and a
    worker retry commits exactly once. Pin ascending triggering-user order and
    race-finish/settlement fencing. Race a standalone `rollPowerup` against the
    worker and assert advisory locks are acquired before participant rows in
    stable order with no deadlock.
11. Cover join-time clamping, timezone travel/DST, race finishing/forfeit while
    queued, settlement fencing, and multiple concurrent uploaders in one race.
12. Seed an unknown/new dirty reason as an old-worker simulation and assert
    normalization/claim produces FULL, never committed no-op.
13. Force failures after reservation admission, source writes, queue insertion,
    response storage, and finalization in the new sync-v2 transaction; each must
    leave no partial new request. Separately seed a pre-change PROCESSING row and
    prove mixed-worker recovery enqueues `STEP_INPUT_CHANGED`, stores the
    capability marker, and completes once.
14. Through real HTTP, assert fresh and replayed sync-v2 success both return
    exactly HTTP 202 and preserve the legacy fields plus the additive marker.
15. Through real HTTP, race two different home-pull keys and assert one
    database-authoritative cooldown admission; replay the admitted same key
    during cooldown and assert stored 202; force queue failure and assert the
    cooldown stamp rolls back with the transaction.
16. Assert `/steps` and `/steps/samples` old request/response fixtures byte-for-
    shape compatible, including `skipRaceResolution`, empty samples, invalid
    recording method, manual data, auth errors, and compatibility `stepGoal`.
17. Run the correctness cases with `REDIS_URL` unset. Run explicit projection
    cases only against local Redis db15 and prove a Redis failure cannot lose a
    box or alter the API outcome.

Unit/structural tests may supplement but not replace the HTTP/worker cases:
pin the closed reason registry, every raw-SQL allowlist, merge precedence,
the separate committed-scope/source-input predicates, source-input fingerprint
fencing for every allowed reason merge and FULL fallback, advisory-before-row
lock order, generation-mismatch promotion before committed-scope selection, and
the prohibition on legacy inline reconciliation.

### 10.2 Native iOS tests

Extend `RunnerTests` with injected health, clock, state, and transport fakes:

1. One trigger produces one sync-v2 request with exact headers and combined
   immutable body.
2. Ambiguous failure retries once with the identical key/body; process restart
   replays the stored envelope before one fresh read.
3. Definite 404, JSON `ASYNC_DISABLED`, and a confirmed 2xx without the
   capability marker execute the staged legacy pair. Cover the immediately
   pre-fix backend, backend rollback, marker-preserving replay, and a
   proxy/header loss that cannot affect the body marker.
4. Any 2xx clears the v2 envelope; marker-less/malformed 2xx takes the defined
   compatibility path. A 409 clears and creates a fresh key/body without legacy
   fallback. Assert exact transitions for 400, 401/403, 413, 429, timeout, and
   5xx, including partial legacy fallback restart.
5. HealthKit observer + BG task + silent push overlap yields one active request
   and at most one trailing fresh request; all completion handlers fire once.
6. BG expiration during a joined sync cannot double-complete or cancel another
   trigger's work.
7. Pending envelopes are partitioned by user/backend, removed on sign-out,
   rejected when corrupt, retained regardless of age while valid/unresolved,
   and never sent without a current matching owner/token. Cover negative
   capability expiry and positive marker revalidation.
8. Preserve local-date fallback, DST boundary, hourly closed-bucket exclusion,
   missing-token/authorization no-op, and preference prefix coverage.
9. When the execution budget cannot fit another request, retain the envelope
   and complete/detach each OS callback exactly once for later recovery.

### 10.3 Native Android tests

Add JVM tests for the extracted sync engine and worker mapping (Robolectric only
if Android framework storage is unavoidable; prefer pure Kotlin interfaces):

1. Mirror the iOS protocol, marker, retry, staged fallback, pending-envelope,
   account/flavor, corrupt/no-age-expiry, and outcome-classification cases.
2. Run periodic and expedited worker instances concurrently; assert the mutex
   permits one network operation at a time and the second re-reads state after
   locking.
3. Assert retryable ambiguity returns `Result.retry()` with pending state and
   permanent/no-data outcomes return `Result.success()` without hammering.
4. Preserve Health Connect permission, local-date/DST, sample normalization,
   missing-preference, unique-work scheduling, and expedited replacement
   behavior. Add exact DST gap/repeated-hour cases and prove no partial current
   hour is emitted.

### 10.4 Flutter tests and platform verification

- Test bootstrap persistence and sign-out/delete-account clearing for every new
  native pending-envelope key and the existing backend-user identity key.
- No widget placement test is required because no visible UI changes.
- Run `flutter analyze`, the relevant Flutter tests, then the full
  `flutter test` suite.
- Run iOS XCTest and Android JVM tests.
- Build iOS and both required Android release flavors/configurations according
  to the repository deployment commands, keeping version/build and backend URLs
  aligned. Production AdMob defines remain production-only as documented.

### 10.5 Isolated burst/capacity verification

Extend the existing non-production load harness with both traffic profiles:

- frozen-client burst: approximately 456 `/steps` + 456 `/steps/samples` calls
  concentrated into one minute, including same-user repeats and multi-race
  users;
- current-client burst: the same logical sync cycles as single sync-v2 calls,
  including a controlled ambiguous-retry fraction.

Run with exactly two backend workers against a disposable capacity/test
Postgres and isolated Redis namespace. Verify the objectives in section 8.3,
final source/participant/box parity, generation amplification, DB pool wait,
transaction duration, worker lag, and zero test writes to production. Do not
start staging without current user authorization.

## 11. Acceptance criteria

Development is complete only when all of the following are true:

1. All current and frozen step-write APIs return their existing fields and
   statuses for equivalent requests; sync-v2 adds only the optional capability
   marker and returns HTTP 202 for both fresh and replay success.
2. No intake command calls `reconcileUploaderRaces`, `resolveRaceState`, or
   `syncRacePowerupState` before responding.
3. Every successful changed input has atomic durable queue ownership; induced
   queue failure cannot leave acknowledged source-only state.
4. Deferred sync-v2 and both legacy paths eventually compute the uploader from
   persisted source, including a zero-effect race; they never incorrectly use
   `STEP_SYNC_COMMITTED`. A new worker promotes an old worker's already-queued
   generation-mismatched STEP_SYNC without waiting for another upload.
5. Existing committed `STEP_SYNC` optimization remains correct and covered.
6. A null/mismatched queue-ownership generation creates at most one repair
   generation even when scoring-equivalent. Once ownership equals scoring
   generation, identical/scoring-equivalent repeats create no queue generations;
   any old-worker generation advance makes the mismatch repairable again.
7. Current iOS and Android background cycles normally send one sync-v2 request,
   retry ambiguities with the exact key/body, and fall back only on definite
   unsupported-server responses or confirmed marker-less 2xx compatibility.
8. Concurrent native triggers are coalesced/serialized without lost updates,
   cross-account replay, completion-handler leaks, or WorkManager retry storms.
9. Canonical scoring, effects, boxes, placements, settlement, and notifications
   have eventual parity with the pre-change behavior; participant/box/job
   success is atomic and Redis/event publication cannot determine correctness.
10. Backend unit and integration suites, native tests, Flutter tests, and
    `flutter analyze` are green; both mobile platforms build.
11. The isolated burst test meets section 8.3 and produces no P2028, deadlock,
    pool-timeout, stale-final-state, duplicate-box, or dead-letter failure.
12. Backward-compatibility reasoning is verified for old client/new backend,
    new client/old backend, and mixed backend workers.
13. A code-reviewer subagent finds no unresolved correctness, compatibility, or
    test-quality issue after implementation.
14. No feature flag, destructive schema migration, UI change, capacity
    increase, staging start, or production mutation is introduced. The one
    additive compatibility-stamp migration is old-code-safe and still requires
    explicit in-the-moment production-deploy approval.

## 12. File-level implementation map

### Backend

- `src/modules/steps/commands/recordSteps.js`: delegate persistence/handoff;
  remove inline uploader/box work; preserve wire side effects.
- `src/modules/steps/commands/recordStepSamples.js`: same; enable canonical
  no-op suppression.
- `src/modules/steps/commands/recordStepSyncV2.js`: emit
  `STEP_INPUT_CHANGED`; make new reservations atomic; preserve legacy
  PROCESSING recovery and add the stored response capability marker.
- `src/modules/steps/models/steps.js` and `stepSample.js`: add/reuse
  caller-transaction persistence variants.
- `prisma/schema.prisma` plus one additive migration: persist
  nullable `sourceQueueSemanticsGeneration` on the scoring-input row.
- New `buildStepInputIntake(dependencies = {})` service under
  `src/modules/steps/services/`, with explicit Prisma/model/job/clock injection
  and caller transaction support.
- `src/modules/races/services/raceResolutionReasonRegistry.js`: classify new
  reason and merge behavior.
- `src/modules/races/models/raceResolutionJobV2.js`: update all SQL allowlists.
- `src/modules/races/services/raceResolutionStepSyncScope.js`: keep committed
  STEP_SYNC admission isolated.
- `src/modules/races/services/raceScoringDependencyClosure.js`,
  `raceResolutionInputFingerprint.js`, and
  `src/modules/races/jobs/raceResolutionQueueV2.js`: source-input admission,
  plan, fingerprint fence, durable box step, and post-commit projections.
- `src/modules/races/services/racePowerupStateSync.js` and
  `src/modules/powerups/commands/rollPowerup.js`:
  caller-transaction box mutation and deferred event publication.
- `src/modules/races/models/race.js` / enqueue service: lean transaction-aware
  active-race lookup.
- Integration tests under `test/integration/`; focused structural/unit guards
  under existing `test/services/`, `test/commands/`, and `test/jobs/` trees.
- Existing isolated capacity scripts/fixtures for the observed burst profile.

### Frontend/native

- `ios/Runner/AppDelegate.swift`: combined transport, single-flight/trailing
  coordination, pending envelope, response classifier.
- `ios/RunnerTests/RunnerTests.swift`: protocol and trigger concurrency tests.
- `android/.../StepSyncWorker.kt`: combined sync engine, mutex, pending
  envelope, response classifier and worker mapping.
- `android/app/src/test/...`: new pure Kotlin/JVM coverage and minimal Gradle
  test dependencies if required.
- `lib/services/auth_service.dart`: pending-key cleanup.
- `lib/services/background_sync_bootstrap_service.dart`: ensure native identity
  and backend configuration lifecycle is explicit/tested.
- Existing Flutter tests for preference lifecycle; no screen files.

## 13. Spec-flow gap passes

### Gap pass 1 — correctness and durability

Issues found and incorporated:

- A queue-only change using existing `STEP_SYNC` could republish stale totals on
  zero-effect races. Added the explicit `STEP_INPUT_CHANGED` contract and a
  failing end-to-end regression requirement.
- Existing legacy enqueue is best-effort and occurs outside source persistence.
  Added atomic source + queue ownership with rollback on enqueue failure.
- Split legacy requests can be claimed between daily and sample writes. Added
  generation/fence coverage proving final convergence without timing reliance.
- No-op suppression existed for daily/sync-v2 but not legacy samples. Added
  canonical sample no-op suppression and amplification assertions.
- Removing inline uploader resolution moves box minting and overtake nudges.
  Assigned box mutation to the fenced worker transaction, retained only
  rebuildable notification/toast work post-commit, and added rollback,
  parity, and duplicate tests.

### Gap pass 2 — client lifecycle, rollout, and operations

Issues found and incorporated:

- iOS has three trigger sources and no in-flight coalescer. Added single active
  run plus trailing fresh run and exact completion ownership.
- Android periodic and expedited work use different unique names and can
  overlap. Added one shared mutex and post-lock re-read.
- Process death after an ambiguous response could create fresh-key duplicates.
  Added a durable, immutable, account/backend-partitioned pending envelope.
- Falling back after ambiguity can double-post. Limited fallback to definite
  unsupported responses on both platforms.
- New app against old backend and new reason against an old rolling worker were
  not explicit. Added both version-matrix cases and fail-closed integration
  tests.
- A capacity claim without the observed frozen-client shape would miss the
  incident. Added paired legacy and single-request profiles, two-worker parity,
  queue-lag and transaction-error gates.
- Persistent pending data creates logout/flavor/privacy hazards. Added sign-out
  cleanup, owner/backend matching, corruption handling, indefinite retention of
  valid unresolved work, atomic string storage, and a sensitive-log prohibition.

### Gap pass 3 — post-architecture consistency audit

Required architecture findings found and incorporated:

- Split the source-input closure predicate from the committed STEP_SYNC scope,
  and pinned fingerprint revalidation without a lock-order inversion.
- Replaced new sync-v2's source-only Transaction A / replay-dependent handoff
  with one atomic reservation/source/queue/response transaction; retained only
  mixed-worker recovery for already-existing PROCESSING rows.
- Moved `lastStepSyncAt` outside correctness transactions so a bookkeeping row
  lock cannot recreate ingestion contention.
- Moved box mutation before worker `recordSuccess`, with caller-transaction
  injection, rollback/retry, stable ordering, and separate transaction gates.
- Added the response capability marker needed to distinguish the immediately
  previous marker-less sync-v2 backend and a later backend rollback.
- Defined every pending-envelope terminal transition, partial legacy progress,
  no-age-expiry recovery, and iOS execution-budget behavior.
- Corrected Android's current partial-hour behavior to an explicit completed-
  hour/DST contract.
- Pinned sync-v2 success to HTTP 202, Postgres/Redis ownership, factory-style
  dependency injection, and Redis-independent correctness tests.

### Gap pass 4 — architecture follow-up concurrency audit

The follow-up review found and the spec now resolves:

- Source-input fingerprints and captured job generations now fence **every**
  STEP_INPUT_CHANGED plan, including FULL fallback and effect-heavy runs.
- Worker box advisory locks are acquired in stable order before any participant
  row write, matching standalone roll lock order and removing an inversion.
- Foreground home-pull cooldown admission remains inside the atomic outer
  transaction, after same-key replay and before intake, with rollback coverage.
- An additive per-user semantics-generation stamp gives exactly one new backend
  request ownership of repairing stale marker-less-era input, including a
  scoring no-op, and automatically detects later generations written by an old
  mixed/rollback worker.
- Idempotency reservation admission is the first transactional write after the
  preliminary replay lookup, so a concurrent duplicate cannot perform source
  work before losing at the unique-key boundary.

### Gap pass 5 — mixed-worker no-future-request audit

The final rolling-reload audit found that detecting an ownership-generation
mismatch only at the next intake could leave an old worker's stale-compatible
queue job unresolved when the client never uploads again. New workers now check
the generation stamp before plan selection and promote the existing STEP_SYNC
claim to fingerprint-fenced source-input computation. The worker deliberately
does not update the stamp under the race fence, avoiding lock-order inversion;
intake remains the durable stamp owner.

## 14. Decisions and revision log

| Date | Revision | Reason |
|---|---|---|
| 2026-08-24 | Initial draft | Convert every step intake path to durable queue-only derived work and migrate current native background clients to sync-v2. |
| 2026-08-24 | Added `STEP_INPUT_CHANGED` | Gap pass found that deferred sync-v2 can otherwise select `STEP_SYNC_COMMITTED` against stale uploader state. |
| 2026-08-24 | Added atomic legacy handoff | Gap pass found source persistence plus best-effort enqueue cannot support a truthful fire-and-forget success contract. |
| 2026-08-24 | Added durable native pending envelope and trigger coalescing | Covers ambiguous response, process death, concurrent OS triggers, account switch, and flavor isolation. |
| 2026-08-24 | Folded required architecture review | Made sync-v2 atomic, box work durable, closure predicates distinct, rollback compatibility explicit, and native recovery terminal. |
| 2026-08-24 | Folded architecture follow-up | Fenced FULL fallback, corrected advisory lock order, preserved home-pull cooldown, and added one-time marker-less state repair ownership. |
| 2026-08-24 | Folded final mixed-worker audit | Replaced the boolean repair version with scoring-generation ownership and made reservation admission the first transactional write. |
| 2026-08-24 | Added worker-side mixed-generation promotion | Ensures an old worker's queued STEP_SYNC is healed by a new worker even if no client sends another request. |
| 2026-08-24 | Architecture review approved | Final read-only review returned APPROVE with no required or suggested findings. |

No unresolved product question remains in this draft. The intended product
tradeoff is explicit: frozen clients keep the same APIs but race-derived state
may update seconds after the upload rather than inside that response.
