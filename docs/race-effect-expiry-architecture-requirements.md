# Timely race powerup expiry

Status: implementation approved by the user with tests-first integration and load verification. Production deployment requires separate in-the-moment authorization.

## Summary and user story

When a timed race powerup ends, racers should promptly see the server-confirmed result. Expiry must progress without anyone opening the app. A scheduler delay must never extend an effect's scoring window or duplicate its consequences.

Keep the existing race resolution writer and durable job infrastructure. Add durable deadline delivery, remove avoidable publication delays, and refresh visible clients around known deadlines. This is an incremental architecture change, not a new race engine.

## Evidence and scope

Backend paths below are relative to the separate backend repository; frontend paths are relative to this repository. These findings describe checked-out code, not a verified production deployment or measured production incident.

- Backend `src/modules/races/jobs/placementRecompute.js:52,652,829,1156`: five-minute sweep discovers overdue effects after loading active races, then enqueues resolution.
- Backend `src/modules/powerups/models/raceActiveEffect.js:218`: discovery uses the existing race/status index and a supplied active-race list; it is not a bounded global deadline queue.
- Backend `src/modules/races/models/raceResolutionJobV2.js:225`: enqueue already accepts a transaction, coalesces race work, and supports bypassing debounce.
- Backend `src/modules/races/jobs/raceResolutionQueueV2.js:3352`: durable worker has queue wakeups, next-due scheduling, and a five-second fallback. Reuse this infrastructure.
- Backend `src/modules/races/jobs/resolvedImpactBoundaryScheduler.js:7`: existing one-second boundary scheduler is specifically for pending Umbrella interceptions; it does not schedule all powerup expirations.
- Backend `src/modules/races/jobs/raceResolutionPostTaskRunner.js:141,197`: remaining effect consequences precede snapshot publication, but notification provider calls precede that entire stage. Failed or ambiguous snapshot attempts are terminal under the current contract.
- Backend `src/modules/races/services/raceProgressSnapshot.js:257` and `queries/getRaceProgress.js:2306`: freshness uses a 15-second age threshold; a stale response may be returned while refresh is queued. Paged projections are a separate path and must also be covered.
- Frontend `lib/screens/race_detail_screen.dart:1947,1965,7877`: 30-second live polling, one-second display ticker, and an Expiring label after zero. The ticker does not request expiry processing.

In scope: expiry delivery, snapshot convergence, instrumentation, and deadline-aware client refresh. Preserve all scoring formulas, time windows, late-step treatment, payouts, notification delivery semantics, inventory rules, visual layout, and existing server-confirmed effect removal. No new powerups, artwork, WebSocket service, general workflow platform, partition infrastructure, release flags, or capacity changes. Intermediate powerup phases and Umbrella interception resolution retain their existing owners; this project schedules final timed expiry only.

## Architecture and invariants

1. Authoritative effect `startsAt`/`expiresAt` values govern gameplay. Scheduling governs when consequences are materialized, not which steps qualify. Preserve existing scoring-version and race-settlement behavior, including late step samples.
2. Timed active effect writes atomically maintain durable deadline records, including writes made by older backend processes during deployment.
3. A bounded scheduler dispatches due records to the existing race queue. One dispatch per deadline revision; multiple due effects in one race become one job envelope.
4. The existing fenced race worker owns authoritative score writes. Existing transactional expiry handlers retain non-scoring consequences. Do not create a second writer.
5. Publish the confirmed race state promptly. Notification provider latency must not gate snapshot publication, while existing notification ordering and at-most-once delivery guarantees remain intact.
6. Visible clients request fresh progress near a deadline and briefly retry. The app does not invent payouts or remove pending effects based solely on its clock.

## Data model and migration

Add `race_effect_deadlines` and its Prisma model:

- `effect_id`: primary key, FK to active effect, cascade delete.
- `race_id`: FK to race, cascade delete.
- `deadline_at`: non-null timestamp copied exactly from effect expiry.
- `revision`: UUID replaced whenever the source deadline identity changes.
- `dispatched_revision`: nullable UUID.
- `dispatched_generation`: nullable integer, the durable race job generation.
- `dispatched_at`: nullable timestamp.
- `created_at`, `updated_at`: timestamps.
- Partial index `(deadline_at, race_id, effect_id)` where dispatched_revision is null; index `(race_id, deadline_at)` for scoped recovery/inspection.

A database trigger on effect INSERT and relevant UPDATE maintains this table in the source transaction. ACTIVE + non-null expiry creates a deadline. A changed expiry or target/race/type resets dispatch and changes revision. Unrelated metadata updates do not rearm it. Terminal status or expiry removal deletes it. Trigger logic performs no scoring, notification, or job enqueue. This small invariant belongs in the database so raw SQL and older command paths cannot silently omit scheduling.

Install table/index/trigger before backfill. Backfill existing active timed effects in bounded batches: lock candidate source effects in stable ID order, reread eligibility inside the transaction, then INSERT missing deadline rows ON CONFLICT DO NOTHING. Source effect locks always precede deadline locks; backfill and trigger never acquire job locks. A concurrent expiry/extension is serialized by the source lock and the trigger maintains the final deadline afterward. Do not resurrect a deadline from a stale initial scan. Make the command resumable and idempotent. New-table indexes do not require rebuilding the large effects table. Document row counts and backfill completion before calling migration ready.

## Deadline scheduler

New backend files: `models/raceEffectDeadline.js`, `jobs/raceEffectDeadlineScheduler.js`; export through the races module and register inside the existing guarded `startCrons()` in `src/index.js` under resolution/all roles. HTTP processes never run it. Keep production process capacity unchanged.

- Probe the partial due index using database time every second, at startup, and on applicable existing wake signals. Process at most 100 candidate deadlines per batch and yield between batches. These are initial engineering batch settings, not remotely configurable rollout controls.
- Avoid a full active-race scan. Select candidate race IDs without locks. In each short transaction acquire the existing race-job/C0 fence before deadline rows, using `RaceResolutionJobV2.acquireForWrite` (including its inert generation-0 insertion for missing jobs), then lock candidate deadlines with SKIP LOCKED. Revalidate exact revision/deadline and source eligibility using MVCC reads; acquire no race, participant or source-effect row locks in this scheduler. Use a bounded job-lock timeout and move busy candidates to the next pass. This preserves worker job-to-deadline ordering. The source trigger/backfill must never acquire a job lock after a deadline lock. The worker makes the final current-state decision if cancellation, extension or race completion commits after the scheduler's read.
- Coalesce all selected due effects for a race into `EFFECT_BOUNDARY`, including their types and affected users/participants. Call the existing transactional enqueue with `bypassDebounce: true`, normal LIVE queue priority, and existing race timezone resolution. Stamp dispatch revision and generation in that same transaction. Publish the existing resolution wake only after commit.
- Two schedulers must produce one durable dispatch per revision. A crash before commit changes nothing; after commit the job exists even if the wake is lost. The worker's fallback discovery remains effective.
- Pocket Watch extensions, cancellation, and race completion may make a delivered job obsolete. The worker must reread current source state and preserve its normal fencing checks. An old delivery never expires an extended effect.
- Extend the existing five-minute recovery sweep to inspect dispatched-but-unresolved deadlines in bounded pages. Existing queued/running/retryable jobs are not repeatedly re-enqueued. Failed/lost terminal work is repaired using existing queue retry rules and bounded backoff; one poison race cannot occupy the first page forever. Report overdue age and terminal failure separately. Keep race-end settlement ownership intact.

## Snapshot publication and cache freshness

Modify `raceResolutionPostTaskRunner.js` so transactional expiry convergence and snapshot publication occur before outbound notification provider calls. Preserve notification-to-notification ordering, intent receipts, and at-most-once rules. A snapshot failure must not block notification processing indefinitely.

Do not change existing post-task terminal-state meanings. On failed/ambiguous snapshot publication, atomically record a durable repair intent with terminal snapshot disposition; recovery of a crashed `attempting` snapshot must do the same. Do not enqueue the race job while holding a post-task lock: the worker uses job-to-post-task ordering. Add `race_snapshot_repair_intents` with task ID primary/dedupe key, race ID, source generation, attempt count, availableAt, lease token/expiry and terminal timestamp; index pending availableAt and lease expiry. A separate bounded drain claims and commits a lease, releases its transaction, enqueues a coalesced DISPLAY_REFRESH repair, then acknowledges its intent. A crash between enqueue and acknowledgement may redeliver safely; never acknowledge before durable enqueue. Repair uses bounded retry/backoff, is superseded by newer successful publication, and never resends notification intents. Distinguish superseded publication from actual failure: `publishSnapshot` currently returns false for both; return an internal structured outcome and adapt every caller without changing public API. A bounded startup/recovery census must also admit failures created by older processes during rolling deployment; use retained task/receipt history and skip already-covered successful publication. A fresh repair generation uses current committed data. Verify that cache generation guards prevent older publication from overwriting newer state on both full and paged paths.

Add internal optional `nextEffectBoundaryAt` to full, lean and paged snapshot metadata, derived from the earliest still-ACTIVE timed expiry included in the computation, including overdue unresolved effects. Freshness becomes age-valid AND before that boundary. For older cached values without the field, derive a boundary where complete effects are available; otherwise use existing age-based fallback and rely on independent deadline delivery. An overdue boundary must not be replaced with the next future one while consequences are pending.

For `getRaceProgress.js`, `raceProgressSnapshot.js`, `raceProgressPageProjection.js`, and `raceProgressSideEffects.js`: carry this metadata consistently through publication and reads, including compact, paged, team, and Redis-unavailable paths. Never block HTTP on race-wide computation or add one expensive replay per viewer. Returning persisted/stale progress during a failure remains allowed; background delivery and repair own convergence.

**Refresh admission is part of this change, not an assumption about existing coalescing.** Existing pure-display coalescing does not cover mixed boundary jobs. For a refresh of an overdue effect, check durable coverage by `(effect_id, revision, dispatched_generation)` and requested viewer scope. Covered queued/running expiry work must not receive another generation merely because of a poll. Uncovered deadlines use the deadline admission path. Preserve genuine source mutations as independent invalidations.

For distinct viewer work arriving during that covered generation, durably merge into an additive `race_progress_refresh_intents` table keyed by `(race_id, user_id)` with a request UUID, requestedAt, availableAt, minimumCommittedGeneration, and the existing viewer request scope and scoring timezone. Preserve current timezone merge semantics. The minimum generation persists even after a source deadline is deleted; use the existing durable committed-generation state to prove it has completed (or a newer committed generation covers it), not merely that a job was attempted. Index `(availableAt, race_id)`; cascade on race/user deletion. Do not mutate the active generation's captured scope. A bounded drain admits the merged viewer scope after that covered generation commits, using one subsequent coalesced job per batch; acknowledge/delete only exact request UUIDs admitted in the enqueue transaction, so racing requests survive. Unadmitted records never age out silently: failed generations follow existing bounded recovery, ended races are resolved against settlement state, and obsolete records are cleaned in bounded batches after proving no remaining viewer work. Drain only after releasing intake locks and use the job-first order when enqueue and acknowledgement share a transaction. Race-wide snapshot refresh alone does not require one follow-up per viewer; only existing viewer-specific work does. This table is an intake buffer, not a second computation queue. Add model/drain integration to the existing resolution wake/recovery paths and migrate it additively. All coverage/admission checks use Postgres correctness state, so Redis failure cannot reintroduce generation churn.

Test a slow notification on the preceding task as well as on the current task. If the existing provider timeout and runner concurrency cannot meet the publication objective, give snapshot work independent bounded scheduling within the existing post-task process before claiming success; do not increase process count or silently change notification retry semantics.

## API contract

No new endpoint, required parameter, or public response shape. Existing authenticated `GET /races/:raceId/progress`, including compact/paged query variants, retains its complete current contract and error behavior. Existing `progress` effect entries continue to carry their existing `expiresAt` and identity fields; all other properties are preserved. The internal snapshot field is not a client requirement and must not leak as a replacement contract.

Example of the existing timestamp shape inside an effect (illustrative, not a replacement response):

```json
{"expiresAt":"2026-09-06T18:00:00.000Z"}
```

No new auth or error cases. Clients must continue tolerating missing/null/malformed timestamps. `queries/getRaceProgress.js:1479` already emits effect `id`; use `(id, expiresAt)` for deadline identity. Existing contract tests must confirm that mapping across each response variant. Missing/invalid identity disables the accelerated refresh for that entry and retains normal polling; do not guess identities or require a new field.

## Frontend plan: iOS and Android

Modify `lib/screens/race_detail_screen.dart` and extract a small refresh coordinator under `lib/utils/` if needed. Keep the real screen, effect rail, copy, and all layout intact. No visual redesign is proposed; the same expired effects disappear on server confirmation, sooner.

- Track the earliest visible timed effect expiry from existing progress, keyed by effect identity plus deadline. On crossing it, request progress with 0–500ms jitter to avoid synchronized viewers. Schedule once per deadline revision.
- If the same overdue effect is still present, retry after 2, 4 and 8 seconds with jitter. At most four expiry-triggered requests per screen per 30 seconds, shared across all effects. Reuse an in-flight progress request and preserve the existing `_progressFetchSeq` ordering guard. Where present, also use existing optional `RaceProjectionMetadata` generation/source data to reject older server projections; do not assume request order proves server-state freshness. Coordinate append-page requests and ordinary polling so they cannot overwrite fresher results or cause duplicate work.
- Stop the burst when the effect is absent or its deadline changes. Preserve ordinary 30-second polling after the burst budget is exhausted. Missing timestamps use the existing behavior, with no retry loop.
- Pause/cancel timers on background, hidden route, logout, and disposal. On resume refresh once, then recompute deadlines. Device time is only a refresh hint; a wrong clock cannot settle effects. Do not add a new required server-clock field in this project.
- Preserve current data and existing loading/error presentation during transient refresh failures. Demo mode retains its own deterministic clock and three-second poll; do not let real deadline retries advance its frozen tutorial state. Test demo and tutorial uses of the real screen.

## Implementation sequence and rollout

1. Baseline first: add structured timing for deadline, dispatch, resolution commit, consequence completion, snapshot publication and client observation. Join by effect ID/deadline revision and race generation; no tokens or personal data. Record histograms and bounded sampled traces rather than high-cardinality metric labels. Confirm deployed revision/process roles and investigate one reported slow race with read-only evidence if available.
2. Write failing database/HTTP integration tests, then add deadline table/trigger/backfill, scheduler and recovery. Pin the unchanged API contract before frontend work begins.
3. Write failing publication/failure tests, then remove notification blocking, add durable repair, and cover deadline freshness on every projection path.
4. Write failing real-screen widget tests, then add bounded client refresh for both platforms. This may run alongside backend implementation after the contract is pinned.
5. Run architect requirements review before implementation; code-reviewer review after implementation. Keep existing assertions protected.
6. Deploy backend first only with in-the-moment authorization. Verify migrations/backfill and server latency; existing app binaries benefit through their current polls. Ship matching iOS/Android changes afterward through normal versioned releases. No feature flags or changes to the two-worker production capacity; no staging startup without explicit authorization. Rolling old/new backend overlap must be supported by additive storage and trigger maintenance. Retain additive schema if application rollback is needed; do not drop pending deadlines.

## Longer-term scaling decisions

This plan does not claim the present deployment can support millions of concurrent users. Size the supported load using deadlines per second, effects/participants per race, active viewers, and DB/worker throughput. The first release uses indexed due work and bounded batches on current infrastructure. If measurements require more capacity, separately propose partitioning by race ID so one race retains one writer, plus independent notification delivery capacity. Do not multiply application processes as an implicit part of this change.

If visible polling becomes a material HTTP/DB cost, a later proposal can add authenticated race subscriptions with a versioned `race updated` signal over SSE/WebSockets. Signals would prompt reads, with reconnect/catch-up and existing polling for older clients. A durable expiry queue remains necessary regardless of transport. Evaluate that separately after the deadline/publication improvements; a new transport is not required to validate this plan's initial latency targets.

## Tests first and acceptance criteria

Backend integration tests use real HTTP entrypoints to activate/extend/cancel powerups and fetch progress, real Postgres, and the production scheduler/worker entrypoints. Assert final API-visible results and durable dispatch/consequence state. Never bypass the public path by importing scoring utilities. Tests run only on a verified dedicated test database. Extend relevant suites under `test/integration/` (including post-task storage, powerup expiry, Pocket Watch and progress projection coverage).

Required cases:

- Expiry with no client polls; simultaneous expirations coalesce; multiple schedulers; crash before/after dispatch commit; lost wake; worker failure/retry; no duplicate effect consequence or feed result.
- Extend before dispatch, after dispatch and concurrent with expiry; raw SQL/legacy source mutations; unrelated metadata edits; cancel/delete/race end; backfill concurrent with mutation; null expiry.
- Preserve historical-window scoring and current late-sync treatment through existing public-path tests. No economy or scoring rules change.
- Slow/failing notification provider cannot delay cache publication; lost cache response/crashed publisher causes safe repair; no duplicate notification; older full/paged generations cannot overwrite newer publication.
- Redis outage/recovery; full/compact/paged/team progress; overdue snapshot; old snapshot without metadata; poison race fairness; recovery cannot flood healthy jobs. Concentrated concurrent viewers with intentionally slow expiry must produce bounded generation growth, eventual committed publication, and complete viewer-specific follow-up without repeatedly invalidating the expiry generation.
- Real-screen tests: deadline refresh, repeated overdue response bounded by budget, extension, missing fields, network error, concurrent pagination/poll, clock jump, hidden route/resume/dispose, demo/tutorial clocks; no optimistic payout or effect removal.
- Controlled local load with many idle races and concentrated expirations: work scales with due batches, not registered users; record query plans, DB lock wait, queue age, notification latency and cache latency. Test a large race fanout as well as many small races. Set final supported throughput from measured hardware, not a hypothetical million-user count.

Proposed latency objectives under the measured supported load: p95 deadline-to-published-result <=5 seconds and visible current-client confirmation <=10 seconds; p99 <=30 seconds. These are targets to validate, not promises or hard timing guarantees. Alert on growing overdue age and starvation. Older clients retain their poll latency. Offline devices have no display-latency guarantee.

Definition of done: integration and relevant real-screen tests pass; `flutter analyze` is clean; both platforms accounted for; backend unit/integration commands used (never bare npm test); code review passed; API compatibility demonstrated. Final implementation report must identify any failing/skipped checks. Implementation and verification evidence are recorded in `race-effect-expiry-validation.md`; production deployment remains separately authorized.

## Revision log

- Gap pass 1: removed a proposed platform/streaming rewrite; pinned unchanged public API and visual behavior; specified backend-first/older-process-safe trigger maintenance, no flags, and both app platforms.
- Gap pass 2: added race-first lock order, atomic dispatch, exact deadline revision checks, concurrent backfill safety, poison-job fairness, snapshot crash repair, full/paged cache parity, and a shared bounded client retry budget. Distinguished latency targets from measured guarantees and kept late-step/scoring semantics unchanged.
- Architect review, pass 1: required revisions incorporated: scheduler uses job-first fencing and MVCC source checks; backfill uses source-to-deadline ordering; repair uses durable intents to avoid post-task/job inversion and covers older-process failures; supersession is distinguished from failure; explicit deadline/scope coverage and deferred viewer intake prevent poll-driven generation churn. Also incorporated existing client ordering/identity protections, preceding-task notification latency testing, and registration inside the guarded `startCrons()` resolution/all roles.
- Architect review, pass 2: original blockers resolved; incorporated remaining required durable minimum committed generation and viewer scope/timezone on refresh intents, plus indexed draining and safe cleanup. Performance remains an implementation acceptance gate.
