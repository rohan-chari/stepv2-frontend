# Data and processing architecture audit — 2026-09-08

## Recommendation

Start with global-event enrollment query shape and leaderboard reads. Then batch generic notification projection reads and durable scoring checkpoints. These reduce actual work; adding workers would not address these costs and could increase database contention.

This is an investigation, not an implementation or deployment. Production access was read-only: DigitalOcean managed-database metrics, PostgreSQL statistics, two SELECT execution-plan probes, process status and bounded log tails. No configuration, application data, queue state, statistics reset, or running service was changed. Staging stayed stopped. Two HTTP workers and the existing cron/resolution processes were observed.

## Scope and evidence quality

- Production backend: `3b241ffbb3bfcbaeea5153d18f1efd6e69a293a4`, the isolated Power Outage release. Local backend: `ba6cfc3`, which also contains unreleased billing work. The audited steps, leaderboard, domain-event, and race-resolution job files have no committed differences between these revisions. Billing was not treated as deployed workload.
- Reviewed step intake and retries, event enrollment and summaries, durable capture/scoring, race-resolution fences and post-tasks, generic notification projection, leaderboard assembly/caches, and Flutter foreground sync/resume orchestration. This is a targeted heavy-workflow audit, not an exhaustive correctness review of every endpoint or platform-native background handler.
- Fresh statement intervals: **15:49:16–15:50:17 UTC** and **15:51:24–15:52:25 UTC**. Direct managed CPU: five samples about 30 seconds apart, **15:49:20–15:51:20 UTC**. These are short daytime observations, not a peak-load capacity test.
- PostgreSQL statement statistics evicted entries during the first interval (`dealloc` 56 → 57). Only entries present in both snapshots with unchanged `stats_since` were used. Counts are therefore observed lower bounds; new or evicted entries are excluded. No statistics reset occurred. Second interval `dealloc` stayed 57.
- Execution time includes waits and is not query CPU. Planning tracking and I/O timing were off in the sampled configuration. Host CPU also includes PostgreSQL maintenance, PgBouncer, monitoring, kernel work and CPU steal. SQL categories overlap and must not be added together.
- SELECT plan probes occurred after the statement windows. Neither executed a mutation. Each diagnostic transaction used `BEGIN READ ONLY` and a five-second local statement timeout.

## Production observations

Managed database is still the one-vCPU / 2-GB plan. Five CPU samples averaged **52.23% idle** (range 40.80–61.52%), or 47.77% non-idle. Mean user CPU was 27.21%, system 15.01%, I/O wait 0.71%, steal 2.28%, and IRQ/soft IRQ together 2.57%. PgBouncer process CPU averaged 2.35%, already included in host CPU. The desired 70% average idle target is not established.

| Observation | First interval, 60.8 s | Second interval, 61.3 s |
| --- | ---: | ---: |
| Matched statement calls, all databases | 4,827 (~79/s) | 6,707 (~109/s) |
| Matched statement execution time | 4.49 s | 8.48 s |
| Step-sync reservation INSERT calls | 19 | 32 |
| Enrollment candidate reads | 5, all returning zero rows | 5, all returning zero rows |
| Enrollment candidate execution time | 684 ms | 276 ms |
| Five identified empty queue checks combined | 332 calls, 13.3 ms | 330 calls, 18.0 ms |
| Operational-counter UPSERTs | 82 | 136 |
| Queries mentioning `domain_event` | 251 calls, 377 ms | 337 calls, 1,108 ms |
| Queries mentioning `durable_capture` | 23 calls, 198 ms | 23 calls, 217 ms |
| Queries mentioning `pg_stat_`, including monitoring | 13 calls, 8.5 ms | 15 calls, 230 ms |

The five empty checks cover progress-refresh intents, effect deadlines, entitlement starts, umbrella interceptions and admin commands. Other polls sometimes returned work and are excluded from this figure. These checks consume round trips and planning/protocol overhead despite very low recorded execution time; the measurements do not establish their CPU share.

Queue samples showed 0–5 queued race-resolution jobs and oldest request ages up to 12.5 seconds. These sparse samples cannot establish latency percentiles. In the first window, application database counters increased by 326 inserted, 1,337 updated and 97 deleted tuples. These include background/trigger work and are not a per-request write budget. The roughly 79–109 statements/s must likewise not be divided by step-sync requests and attributed to individual syncs.

Earlier incident findings were checked against subsequent work: the pending-race repair loop is already fixed; Power Outage fanout is already batched. Neither is presented as a new outstanding optimization.

## 1. Enrollment repeatedly searches historical participants to discover no work

**Priority: first implementation candidate. Confidence: production plan and code confirmed.**

Sources: backend [globalStepEventEntitlement.js](../../stepv2-backend/src/modules/steps/services/globalStepEventEntitlement.js), `materializeEntitlementsForActiveRacers`; [globalStepEventScheduler.js](../../stepv2-backend/src/modules/steps/jobs/globalStepEventScheduler.js), `drainParent`.

Each scheduler tick begins a new per-parent pagination pass with `afterUserId = null`. The query combines ordered distinct users, active-race membership and an entitlement anti-join. Its result limit does **not** bound the work needed to prove the page is empty.

One read-only probe for a currently maintained event returned zero candidates while scanning **28,992 qualifying participant rows**, probing 627 distinct race IDs through a memoized lookup, and touching **30,296 shared buffers**. It took **426.9 ms execution / 8.2 ms planning**, entirely from cached pages.

An alternative SELECT explicitly materialized distinct active racers first, then anti-joined that smaller set against event entitlements. It used existing indexes:

| Probe | Current shape | Active racers first |
| --- | ---: | ---: |
| Returned candidates | 0 | 0 |
| Participants entering active-user aggregation | Historical scan: 28,992 | Active memberships: 2,354 |
| Distinct active users | Not isolated first | 907 |
| Shared buffer hits | 30,296 | 2,338 |
| Execution | 426.9 ms | 16.3 ms |
| Planning | 8.2 ms | 3.6 ms |

That is about **92% fewer buffer hits** and **26× lower execution time in these two non-simultaneous probes**. It is not a repeated benchmark, a full parity test, or a production-wide CPU saving. The natural interval query averages were lower than the slower probe.

Recommended progression:

1. Test an active-membership-first query with existing indexes. Compare empty, sparse and full pages, non-null cursors, multiple races per user and different parent events. Do not add an index before establishing a need from those plans.
2. Share a bounded active-user page across parent events when their eligibility semantics permit it, instead of rediscovering the same population for each event.
3. Longer term, use durable enrollment candidates maintained at race start/join and event creation, with a bounded repair scan. A persistent cursor alone is insufficient: a newly eligible user may sort behind it. Preserve the existing enrollment lock/transaction protocol and timezone/start-boundary behavior.

Correctness validation: real event creation and race-start/join paths, concurrent joins and scheduling, rollback/retry, already enrolled users, timezone changes and exact start boundaries. Assert identical durable entitlements and notification obligations through public workflows.

## 2. Leaderboard caching excludes the viewers who become the majority at scale

**Priority: high scaling value. Confidence: code confirmed; not a measured dominant query in these windows.**

Source: backend [getLeaderboard.js](../../stepv2-backend/src/modules/leaderboard/getLeaderboard.js), `assemble`, `cachedSteps`, `getStepLeaderboard`, `getRaceLeaderboard`.

Two separate issues:

- **Steps:** the global cache contains the top 100. For everyone outside it, `assemble` returns `outside-global`; the caller executes the full legacy path. That repeats the top-100 aggregation and profile loading, sums the viewer's steps, and loads *every grouped user above the viewer* merely to calculate `usersAbove.length + 1`. A cache hit therefore still leads to substantial database work for an ordinary low-ranked viewer.
- **Race records:** every request loads all accepted memberships in completed races, counts placements in JavaScript, loads identity/accessory data for all represented users, sorts them, and finally returns only 100. This path bypasses the step leaderboard cache. Cost grows with historical participation and population.

Recommended changes:

- Retain the shared top-100 result for off-board viewers. Fetch the viewer scalar separately; count higher-ranked aggregates inside SQL instead of returning every higher-ranked group. Define whether that scalar shares the cached board's `asOf` or is intentionally fresher; do not silently combine inconsistent rank semantics.
- For race records, first aggregate and select winners in SQL, then fetch presentation only for the displayed users plus viewer. This reduces presentation loading from O(all represented users) to at most 101 identities, without changing podium points or tie rules.
- If raw aggregation remains significant, maintain rebuildable per-user race-record and period-step totals. Source of truth remains settled memberships and canonical daily steps. Update aggregates transactionally on settlement/correction/deletion; handle corrected step totals as old→new deltas, not blindly additive uploads. An asynchronous alternative needs durable deduplication and explicit freshness semantics.

Keep existing old-client `top10`/`top100` aliases, viewer visibility exceptions, friend scope and tie behavior. Test real HTTP responses for off-top-100, hidden/review users, ties, historical corrections, user deletion, timezones and cache failure. No scoring-rule change is proposed.

## 3. Generic notification projection reloads whole audiences per recipient

**Priority: high for fanout. Confidence: code confirmed; generic-path share of current traffic is unmeasured.**

Sources: backend [domainEventOutbox.js](../../stepv2-backend/src/modules/domainEvents/models/domainEventOutbox.js), `loadProjectionContext`; [notificationProjector.js](../../stepv2-backend/src/modules/domainEvents/services/notificationProjector.js), `processOne`.

The generic worker claims two projections at a time. For each projection it loads its event **including the entire event audience**, then finds the one recipient in JavaScript. It separately checks the recipient's existence; message events also reload the message. Completion is written per projection and parent completion checked afterward.

For a generic event with N recipients and one projection each, the audience-loading pattern can transfer **N² audience rows**, although the data required is N audience rows plus one shared event. At 2,000 recipients that is a structural estimate of four million audience-row loads, not a production observation. Specialized batched paths already exist for some placement/no-device cases; they should not be counted as generic-path traffic. Power Outage's upstream command batching does not prove every downstream notification path is batched.

Recommended change: load a bounded claim page, batch recipient identities, fetch each distinct event/message once, and select only the claimed recipient audiences. Prefer joining projection→its audience directly where that avoids full parent hydration. Keep delivery concurrency bounded separately from the read batch size. Batch completion state updates and check each affected parent once where lease/failure semantics permit it.

Preserve immutable audience/privacy snapshots, lease tokens, deleted-message suppression, expiry checks, delivery deduplication, schedule admission and parent receipts. External push outcomes still need independent retry handling; a larger database batch must not turn one provider failure into replaying successful deliveries.

Validate through real durable-event creation and worker delivery with provider boundaries controlled: large audience, mixed success, deletion during processing, expired recipients, worker crash and reclaimed leases. Count database statements and audience rows across **both** command and downstream workers.

## 4. Durable scoring checkpoints are finer-grained than their recovery needs may require

**Priority: event-burst optimization. Confidence: code confirmed; inactive in current sample.**

Sources: backend [durableCaptureStageScoring.js](../../stepv2-backend/src/modules/steps/services/durableCaptureStageScoring.js), `fenced` and `checkpoint`; [durableCaptureIntervalProjection.js](../../stepv2-backend/src/modules/steps/services/durableCaptureIntervalProjection.js), root aggregation; [durableScoringMethod.js](../../stepv2-backend/src/modules/steps/services/durableScoringMethod.js).

Every scoring state transition calls a transaction that locks/checks the capture lease and updates the score cursor. Even a transition with no effect or transfer has that cost. Root aggregation performs a projection lookup and cursor UPSERT for each root even when the projection is already cached. Cold paths also persist method progress per fact page and save several related projections separately.

Structural lower-bound examples, excluding transaction-control statements and all input reads:

- 64 ordinary scoring checkpoints: **64 lease SELECTs + 64 cursor UPDATEs**, across 64 transactions. A 64-operation bounded page could potentially use one lease check and one cursor update, plus any required batched output writes.
- R cached roots: **R projection reads + R cursor writes**. Bounded multi-key reads and a page cursor can reduce those components to roughly **ceil(R/B) reads + ceil(R/B) cursor writes** for page size B.

These are design estimates, not measured savings. Memory, execution-time, lease-duration and serialized-output budgets must jointly bound each page. Compute from pinned immutable inputs outside a long database transaction, then atomically commit the final cursor and all newly emitted transfers under the lease/revision fence. A crash may replay bounded arithmetic; it must never duplicate accepted transfers or skip work. Checkpoint at yield/time-budget boundaries and before externally visible publication. Do not simply remove fences.

Existing prepared-input caching, interval journal reuse and fact-root pinning are useful and should remain. There were **zero score-cursor statements** in the matched live windows; almost all measured durable-capture execution was compaction, not active scoring. Historical reports establish this path can be active during event bursts, but do not establish today's CPU share.

Validation: real capture→worker→summary lifecycle; crash before/after page commit; lease loss during compute; corrupt/missing pinned input; retirement and revision reuse; timezone/date boundaries; final totals identical across page sizes and retries. Preserve versioned cursor interpretation for in-flight captures.

## 5. Repeated full race fingerprints are a longer-term architectural target

**Priority: investigate after simpler reductions. Confidence: live query frequency and code confirmed; proposed replacement requires a writer audit.**

Sources: backend [raceResolutionQueueV2.js](../../stepv2-backend/src/modules/races/jobs/raceResolutionQueueV2.js), planning and `fenceValidation`; [raceResolutionInputFingerprint.js](../../stepv2-backend/src/modules/races/services/raceResolutionInputFingerprint.js).

The worker reads a race input fingerprint during planning and reconstructs it inside the commit fence to reject stale computation. It already reuses planning inputs in some paths. In the two windows, the roster/fingerprint read and event-boundary query each ran 44 and 66 times respectively. Their combined recorded execution was about 317 ms and 703 ms. Matching counts alone do not prove an exact number of reads per resolved job.

The second read is currently a **correctness barrier**, not redundant work that can simply be cached away. A possible evolution is a compact version vector: race membership/effects revision, canonical participant-input revisions, event-schedule revision, balance semantics and next time boundary. Load the bounded input set once, then validate revisions at commit rather than rebuilding full row payloads.

This only works if every relevant writer, including legacy endpoints, effect expiry, joins, global boundaries, corrections and administrative mutations, advances the proper revision atomically. Avoid one global revision row or a new race-row update on every user sync; that could exchange read cost for write contention. Existing per-user scoring generations provide part of the foundation.

No numeric savings target is justified yet. First capture payload bytes, planning time, rejected work, lock duration and SQL counts by resolution reason. Prove stale computation is rejected under concurrent mutations and boundary passage before replacing any fingerprint.

## 6. Consolidate idle scheduling and telemetry writes

**Priority: smaller, relatively contained reductions. Confidence: live counts and code confirmed.**

Sources: backend [raceEffectDeadlineScheduler.js](../../stepv2-backend/src/modules/races/jobs/raceEffectDeadlineScheduler.js), [raceAdminCommandRunner.js](../../stepv2-backend/src/modules/races/jobs/raceAdminCommandRunner.js), [raceResolutionPostTaskRunner.js](../../stepv2-backend/src/modules/races/jobs/raceResolutionPostTaskRunner.js), [globalStepEventObservability.js](../../stepv2-backend/src/modules/steps/services/globalStepEventObservability.js).

- Several one-second timers each ask separate durable queues whether anything is due. The effect deadline tick also checks progress-refresh and snapshot-repair queues. Five identified empty query shapes alone ran about **5.4 times/s combined**. Use a shared bounded readiness/next-deadline read and existing wake coordination, dispatching only due families. Retain bounded fallback polling for lost wakeups, process restart and Redis failure. Reusing one returned readiness result matters; merely adding another scheduler on top would increase work. Maintain the existing effect-boundary latency contract.
- `recordOperationalCounters` issues one UPSERT per metric in a loop. First combine a caller's deltas into one set-based UPSERT. If counters are diagnostic rather than contractual, separately consider per-process accumulation with periodic batch flushes. **Do not assume lossy buffering is acceptable**: define crash semantics and distinguish diagnostic counters from ledgers. Shared metric rows can also become contention points as writers multiply; current samples do not prove counter lock contention.

The counter writes were only 6–28 ms of recorded execution per sample. They are a cleanup opportunity, not evidence of the principal CPU bottleneck. Reducing several counters to one query per batch is a statement-count saving; it is not necessarily fewer updated rows unless increments are also coalesced.

## 7. Preserve step-sync coalescing and strengthen overlapping trigger ownership

**Priority: useful burst protection; no duplicate rate measured.**

Sources: frontend [main_shell.dart](../lib/screens/main_shell.dart), `_persistSteps`, `_loadHomeAndShowResults`, `_fetchSteps`; backend [stepInputIntake.js](../../stepv2-backend/src/modules/steps/services/stepInputIntake.js), [recordStepSyncV2.js](../../stepv2-backend/src/modules/steps/commands/recordStepSyncV2.js).

Already good: foreground sync is every five minutes, pauses in the background, home startup/resume loads share an in-flight future, native health windows are batched, samples are reconciled in sets, unchanged daily writes are suppressed, scoring changes control race enqueueing, and multiple race enqueue operations use a batched model.

`_persistSteps` itself has no shared in-flight owner and creates a fresh idempotency key per invocation. Home load, manual home pull and foreground polling can enter through different callers. Home-load coalescing therefore does not cover every overlapping trigger. A user/session-scoped sync coordinator can merge eligible simultaneous requests and retain one immutable request/key across ambiguous retries, while scheduling a follow-up when newer input arrived during the first read.

Do not merge away explicit home-pull cooldown semantics, account changes, historical sample corrections or a required boundary refresh. Never suppress a sync just because the displayed daily total is unchanged: samples, closed windows and global-event capture coverage can change independently.

Even an unchanged accepted backend sync still reserves/finalizes its idempotency record, checks sample bounds, persists input state and stamps last-sync time. These protect recovery and observable freshness. Coalesce redundant logical calls first; only then evaluate conditionally avoiding identical state writes, with an explicit durability contract. Thousands of simultaneous legitimate syncs still need backend admission limits and durable queue backpressure regardless of improvements in new app builds.

Validate real Flutter shell overlap/resume/account-switch behavior on both platform paths and backend HTTP retries, no-op samples, corrections and boundary passage. Old frozen clients must continue to work; backend capacity must not rely on everyone installing the coordinator.

## Implementation order and measurement contract

1. **Enrollment query:** smallest demonstrated query-shape improvement. Add failing integration/query-budget coverage on a dedicated local test database, then implement and compare plans over representative pages.
2. **Leaderboard read bounds:** remove the off-top-100 fallback duplication and historical membership hydration. Establish correction/rebuild semantics before committing to aggregates.
3. **Notification read batching:** measure ordinary generic projection and specialized paths separately; target audience rows as well as SQL count.
4. **Durable checkpoint pages:** benchmark at event boundaries with recovery faults, not only successful arithmetic.
5. **Shared idle readiness and counters:** straightforward bounded improvements; measure overhead rather than expecting a large CPU gain.
6. **Version-based resolution validation and unified sync ownership:** broader changes requiring concurrency and compatibility coverage.

For each implementation, measure one complete user workflow including downstream jobs: SELECTs, writes, transaction count, rows/bytes read, jobs enqueued/coalesced, useful vs empty attempts, retries and queue age. Record direct managed CPU over comparable 5–10 minute traffic windows, including event-boundary bursts; retain monitoring-query costs. Local per-query speedups must not be advertised as production-wide savings.

No implementation tests, Flutter analysis or platform builds were run for this read-only audit and documentation change. No new runtime flags, balance changes, migrations or API contracts are proposed as prerequisites. Implementation should use additive/version-compatible behavior, real workflow tests written first, required code review, and separately authorized production deployment.
