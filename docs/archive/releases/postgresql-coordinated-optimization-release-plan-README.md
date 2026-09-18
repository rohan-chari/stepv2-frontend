We have completed both a static audit and a read-only production investigation of sustained PostgreSQL CPU around 90% in the Bara backend.

Do NOT modify code, schema, Redis, PostgreSQL, or production yet.

I want you to create a detailed engineering implementation plan for ONE coordinated release that addresses all of the priorities below.

There will be:

* one release
* no feature flags
* no staged rollout by subsystem
* no temporary dual-path behavior unless absolutely required for a safe migration
* no RabbitMQ/BullMQ migration

The implementation can contain multiple commits and migrations internally, but they will be deployed together as one release.

The priorities are:

1. Reduce the global-event summary query storm
2. Separate active notification work from terminal notification history
3. Fix the large terminal race-resolution post-task table and its polling behavior
4. Batch race-resolution step/sample scoring reads
5. Replace aggressive PostgreSQL polling with Redis wakeups plus slower PostgreSQL recovery polling
6. Reduce repeated race/participant hydration in placement processing
7. Improve queue retention, PostgreSQL VACUUM/ANALYZE behavior, and MVCC characteristics

Current production evidence:

### Global-event summaries

* `global_event_summary_work` had only about 90 active rows.
* It generated about 4,505 index scans per second.
* It generated about 13,384 tuple fetches per second.
* Its `(user_id, status, expires_at)` index had around 152 million scans since PostgreSQL startup.
* The table had about 428k updates and only about 0.48% were HOT updates.
* This was the strongest measured persistent database workload.

### Notifications

* `domain_event_outbox`: about 359k terminal rows, 0 active.
* `domain_event_notification_projections`: about 360k terminal rows, 0 active.
* Projection paths were fetching about 7,046 tuples per second despite no active projection backlog.
* Domain-event outbox was about 392 MB.
* Projection table was about 296 MB.
* Dead tuple estimates were very high.
* Existing indexes include terminal history.

### Race-resolution post tasks

* About 368k rows.
* All terminal.
* Around 610 MB.
* No active work at the snapshot.
* The worker still polls frequently.
* The intended due-state index appeared unused.

### Race scoring

* Participant scoring performs several SQL reads per participant.
* Production showed about 781 step-sample tuple fetches per second.
* Race participant reads were about 948 tuple fetches per second.
* Individual live scoring queries were observed around 0.4–0.7 seconds.
* Large race resolution can issue hundreds or thousands of scoring SQL statements.

### Polling

* Resolution, placement, and post-task workers poll approximately every 250 ms.
* Empty full-trigger promotion currently probes an empty table repeatedly.
* Redis is already used for some wakeup behavior but PostgreSQL polling remains authoritative.
* Polling is not the biggest current CPU source, but it creates a permanent baseline.

### Placement

* Placement processing reloads canonical race/participant context that resolution recently loaded/calculated.
* Some duplicate reads are needed for generation/fingerprint fencing, but full hydration may not always be necessary.

### MVCC/history

* Many queue/status tables retain terminal rows.
* Frequently changing indexed columns prevent HOT updates.
* Some tables have poor planner statistics and high dead-tuple estimates.
* No active autovacuum was observed during the production snapshot, but maintenance appears insufficient on some large historical tables.

The new implementation must preserve ALL current guarantees:

* durable work
* PostgreSQL as authoritative state
* atomic enqueue with business transactions where required
* crash recovery
* leases
* generation fencing
* idempotency
* replay safety
* race scoring correctness
* notification deduplication
* frozen/older client compatibility where applicable
* no lost work if Redis is unavailable
* no lost work if a process crashes immediately after PostgreSQL commit
* no stale worker may commit authoritative race results

Do not suggest replacing the whole system with RabbitMQ or BullMQ.

PostgreSQL should remain the authoritative durable queue/state system for critical work.

Redis should be used as a best-effort wake mechanism, not the source of truth.

# 1. Global-event summary query storm

Find exactly why:

`global_event_summary_work_user_id_status_expires_at_idx`

is being scanned thousands of times per second.

Trace every relevant call site, including:

* `globalEventSummaryCapture.js`
* `claimEligibleSummaryWork`
* `globalEventSummary.js`
* `runV2`
* `reconcileWorkRaceQueues`
* `claimActiveWork`
* Home-summary reads
* step-sync paths
* race-resolution/global-event impact paths
* any helper called once per participant
* any helper called once per step sync
* any helper called repeatedly with identical user/race/event inputs

I want an exact call graph showing where the 4,500 scans/sec most likely originate.

For each call site determine:

* frequency
* caller
* whether it is inside a loop
* whether identical queries can occur in the same logical request
* whether it is doing eligibility checking that could instead be represented durably
* whether results can be coalesced or loaded once
* whether a batch lookup is possible
* whether the one-second summary worker duplicates work already being performed synchronously

Design the preferred fix.

Do not solve this merely by adding another index unless the underlying access pattern genuinely requires it.

Consider designs such as:

* one summary-state lookup per user sync
* batch lookup for all affected event/user pairs
* durable readiness counters
* explicit state transitions instead of repeated eligibility probes
* wake-driven processing
* compact active-state tables/indexes

Preserve all current summary correctness and replay guarantees.

# 2. Notification terminal-history redesign

Trace the exact queries responsible for scanning:

* `domain_event_outbox`
* `domain_event_notification_projections`
* `notification_schedules`
* any completeness/reconciliation paths

Determine which queries are traversing terminal history despite there being no active backlog.

For each important query report:

* exact file/function
* SQL or Prisma access pattern
* WHERE clause
* ORDER BY
* current production index
* why terminal rows participate in the scan
* recommended query/index change

Design active-state partial indexes where appropriate.

Examples may include indexes restricted to:

* `PENDING`
* `RETRY`
* `EXPANDING`
* other truly claimable states

Do not assume these exact statuses. Verify them from code.

Also determine what terminal records are actually needed for:

* idempotency
* dedupe
* replay
* client polling
* recovery
* audit
* debugging

Then design a retention strategy.

If large historical rows are needed only to preserve a unique event/delivery key, consider whether a small durable receipt/tombstone table can preserve that guarantee while allowing large payload rows to be removed.

Be specific.

# 3. Race-resolution post-task redesign

Investigate why:

`race_resolution_post_tasks`

contains roughly:

* 368k terminal rows
* 610 MB
* 0 active tasks

while the worker still probes it frequently.

Trace:

* `raceResolutionPostTaskRunner.js`
* `tick`
* `recoverQualificationIntents`
* `raceResolutionPostTask.js`
* `claimNext`
* cleanup logic
* child intent handling

Determine:

* why qualification recovery runs when there is no active work
* whether recovery must run before every claim
* whether recovery can run on a slower schedule
* why the nominal due-state index is unused
* whether completed tasks need seven days of full retained payload
* whether completed child intents need identical retention
* what pieces of a completed task are needed after success

Design the active queue so that workers operate on a very small active index/table footprint.

Design safe terminal cleanup for this same release.

# 4. Batch race scoring

Trace all SQL called from:

* `calculateBaseAdjusted`
* `calculateCurrentTotal`
* `determineFinishSnapshot`
* `resolveRaceState`

Build a complete map of what each participant-specific query needs.

Then design a batch data-loading layer.

The goal should be closer to:

race resolution
→ load all relevant participants
→ load all relevant daily-step rows
→ load all relevant step samples
→ load effects/event inputs
→ organize data in memory
→ calculate each participant in Node
→ bulk/fenced persistence

rather than querying PostgreSQL several times per participant.

Investigate whether we can batch:

* daily steps
* step samples
* relevant dates
* effect windows
* finish-timeline inputs
* global-event sample ranges
* source/input-version information

Use bounded queries.

Do not load the entire historical step table for participants.

Preserve exact behavior around:

* time zones
* DST
* race start/end
* multi-day races
* sample overlap rules
* stale/missing samples
* global events
* Runner's High/multipliers
* penalties
* other powerups
* mystery-box thresholds
* finishing
* settlement
* source generations
* fingerprints

The current implementation should be treated as the reference implementation.

Estimate SQL statements before and after for:

* 10 participants
* 50 participants
* 500 participants

Also estimate worst-case memory usage for the batch data used by a 500-person race.

If one giant batch is unsafe, design chunking that still avoids N+1 behavior.

# 5. Redis wake + PostgreSQL recovery polling

Design a common wake pattern for the PostgreSQL-backed queues.

Target behavior:

business transaction
→ durable PostgreSQL work committed
→ AFTER COMMIT best-effort Redis wake
→ worker wakes immediately
→ worker claims authoritative PostgreSQL row
→ PostgreSQL remains source of truth

If Redis wake is:

* lost
* duplicated
* delayed
* unavailable
* restarted

the work must still eventually run.

Fallback PostgreSQL polling must remain.

However, idle polling should be substantially slower than the current 250 ms loops.

Investigate and propose appropriate fallback intervals for:

* race resolution
* placement
* post tasks
* full-trigger promotion
* domain-event projection
* notification schedule release
* inbox delivery
* global summaries

Do not use one arbitrary interval everywhere.

Account for:

* immediate work
* `not_before_at`
* `available_at`
* retry times
* lease expiration
* future scheduled notifications
* race settlement boundaries

Determine whether workers should maintain a timer for the next known due item so future work does not rely only on a slow fallback poll.

Multiple Redis wakes should coalesce naturally.

Redis must never contain authoritative queue state.

Keep existing `SKIP LOCKED`, lease, and fence semantics where they are useful.

# 6. Placement handoff redesign

Trace what data race resolution has immediately before successful commit and what placement processing loads again afterward.

Classify every placement read as:

1. required revalidation for correctness
2. mutable canonical state that must be reread
3. data resolution already calculated and could hand off
4. accidental duplicate hydration

Design a compact durable placement handoff.

Potential fields may include:

* source generation
* observation time
* participant IDs
* committed totals
* resulting placements
* input fingerprint/version
* race state/version

But verify what is actually safe.

Do not blindly duplicate large participant JSON into the queue.

Placement must still verify that its source generation is current before emitting transitions.

Preserve compare-and-set placement baseline behavior.

Estimate the DB reads removed per race.

# 7. Retention and MVCC redesign

Create a retention matrix for:

* `race_resolution_jobs_v2`
* `race_resolution_full_triggers`
* `race_placement_transition_jobs`
* `race_resolution_post_tasks`
* `race_resolution_delivery_intents`
* `domain_event_outbox`
* `domain_event_notification_projections`
* `notification_schedules`
* `inbox_delivery_outbox`
* `inbox_delivery_device_attempts`
* `global_event_summary_work`
* `global_event_race_impacts`

For each table identify:

* active purpose
* terminal purpose
* whether clients query it
* whether retry/recovery uses it
* whether uniqueness/dedupe relies on it
* current retention
* proposed terminal retention
* whether payload can be deleted while retaining a receipt
* cleanup frequency
* cleanup batch size

We currently have several tables where almost everything is terminal.

The new design should keep active queue indexes compact.

Also inspect opportunities to improve HOT updates.

Identify indexes on frequently changing columns such as:

* status
* state
* lease
* availability
* timestamps
* generation
* expiry

Do not remove necessary indexes, but identify where partial indexes or different index structure could reduce update amplification.

# 8. PostgreSQL maintenance

Review production evidence around:

* high dead tuple estimates
* stale planner statistics
* low HOT update rates
* missing recent autovacuum/analyze activity

Create a table-specific maintenance proposal.

Investigate whether certain large/high-churn tables should use different:

* `autovacuum_vacuum_scale_factor`
* `autovacuum_vacuum_threshold`
* `autovacuum_analyze_scale_factor`
* `autovacuum_analyze_threshold`
* fillfactor

Do not invent values yet unless you can justify them from current table size and churn.

If you propose values, show the math for approximately how many row changes would trigger vacuum/analyze.

Also explain whether one-time maintenance will be needed after deployment because some tables already contain substantial dead/terminal history.

Do NOT perform that maintenance yet.

# 9. Exact indexes

Produce the exact indexes you recommend adding as part of this release.

For each index include:

* CREATE INDEX statement
* table
* query it supports
* why the current index is insufficient
* whether it is partial
* expected active index cardinality
* whether `CONCURRENTLY` should be used
* migration considerations on DigitalOcean PostgreSQL

Pay particular attention to:

* active domain-event work
* active notification projections
* active post tasks
* active summary work
* notification schedules
* resolution queue claim branches if still worthwhile after polling reduction

Also identify indexes that may eventually be removable.

Do not include index drops in this release unless you are extremely confident they are redundant and removing them materially matters.

Prefer leaving old indexes temporarily over introducing correctness risk.

# 10. Cleanup/migration strategy

This release will include both new code and schema/data cleanup.

Design the safest deployment ordering inside the single release.

For example, you may use:

1. backward-compatible migrations/index creation
2. deploy application code
3. bounded cleanup job
4. analyze/maintenance

But all of this belongs to ONE release effort.

No feature flags.

No intentionally running old and new business logic side-by-side for an extended period.

For large deletes, do NOT propose one huge DELETE transaction.

Use bounded batches.

Account for:

* WAL generation
* locks
* transaction length
* managed PostgreSQL constraints
* replicas/backups if relevant
* table/index bloat after deletion

If cleanup should continue asynchronously after deployment, define exactly how the new cleanup worker behaves and how it remains bounded.

# 11. Testing plan

Because all changes ship together, testing must be strong.

Create a comprehensive pre-release test plan.

## Race-resolution equivalence

Build tests comparing old scoring results against the new batched implementation.

Cover:

* 3-day race
* 5-day race
* 7-day race
* 14-day race
* races crossing midnight
* different user time zones
* DST boundaries
* global events
* Runner's High/multipliers
* penalties
* powerups
* mystery boxes
* missing step samples
* delayed step sync
* stale source versions
* users joining/leaving
* settlement
* finish snapshots
* scoped resolution
* full resolution

Use randomized/property-style test generation if useful.

For each generated input, old and new implementations should produce identical authoritative results.

## Queue wakeups

Test:

* Redis unavailable before enqueue
* Redis unavailable after DB commit
* Redis restart
* dropped wake
* duplicate wake
* 100 wakes for the same race
* process crash after PostgreSQL commit but before wake
* worker crash after claim
* worker crash during compute
* worker crash before fenced commit
* expired lease
* multiple workers
* future due work
* retry delays

No work may be lost.

## Notifications

Test:

* duplicate domain event
* duplicate projection
* duplicate schedule release
* retries
* provider retries
* deleted recipient
* stale device ownership
* dedupe after historical source rows are cleaned
* reconciliation after cleanup

## Retention

Test old/frozen client behaviors that depend on historical job state.

Verify that cleanup does not break:

* polling
* receipts
* generation status
* retries
* idempotency
* replay
* recovery

# 12. Load testing

Design a pre-production load test that approximates Bara production behavior.

Include scenarios such as:

### Normal activity

* many small races
* normal step-sync traffic

### Large race

* 500 participants syncing around the same period

### Notification fan-out

* several hundred recipients

### Global-event boundary

* many affected users/races

### Idle system

* no active queue work for several minutes

Measure before/after:

* SQL statements/sec
* transactions/sec
* tuples fetched/sec
* buffer hits/sec
* Node CPU
* race resolution latency
* queue lag
* notification latency

One important acceptance criterion:

When the system is idle, database activity from durable queues should fall dramatically compared with the current implementation.

# 13. Production observability

We currently do not have `pg_stat_statements`.

Recommend how to enable it safely on DigitalOcean managed PostgreSQL.

Determine:

* whether the current DigitalOcean product supports it
* whether a restart is required
* expected overhead
* required configuration
* what statistics we should retain

This is allowed to be part of the same release/maintenance window if it requires configuration/restart, but do NOT enable it yet.

Also add application-level metrics where useful:

* summary eligibility lookups/sec
* summary eligibility lookups/step sync
* race resolutions/sec
* SQL calls/resolution
* participant count/resolution
* full vs scoped resolution
* resolution query time
* resolution compute time
* queue wake received
* fallback poll
* fallback poll that found work
* idle queue poll
* placement reads/resolution
* projection scans/completed projection
* active/terminal queue rows
* cleanup rows/delete batch
* oldest eligible queue item

# 14. Rollback plan

Because there are no feature flags, rollback must be deployment-level.

Design a safe rollback strategy.

Schema changes must remain compatible with the previous application version whenever possible.

Avoid migrations that make immediate rollback impossible.

For example:

* adding indexes is backward-compatible
* adding nullable columns is generally backward-compatible
* immediately dropping columns/tables is not
* deleting historical data may be irreversible

For any irreversible cleanup, explain why it is safe before deployment.

If necessary, recommend delaying destructive schema drops to a later cleanup release. That is acceptable.

The performance fixes themselves should still all ship together now.

# 15. Expected result

Estimate the effect of the combined release on:

* global-summary index scans
* notification projection tuple fetches
* post-task polling
* race scoring SQL calls
* overall DB transactions/sec
* overall tuple fetches/sec
* DB CPU
* Node resolution CPU
* storage

Do not invent precise CPU percentages.

However, provide clear expectations such as:

* expected 90%+ reduction in a particular query family
* order-of-magnitude reduction
* substantial reduction
* moderate reduction

where supported by the architecture.

# FINAL OUTPUT

Give me one implementation plan containing:

1. Root cause recap
2. Exact global-summary query-storm call path
3. Global-summary fix
4. Notification/history fix
5. Post-task fix
6. Batched scoring implementation
7. Redis wake + PostgreSQL fallback implementation
8. Placement handoff implementation
9. Retention matrix
10. PostgreSQL maintenance plan
11. Exact indexes/migrations
12. Exact source files that need modification
13. New modules/helpers you would create
14. Data migration/cleanup strategy
15. Single-release deployment order
16. Full testing strategy
17. Load-test plan
18. Rollback strategy
19. Observability changes
20. Expected performance improvement
21. Risks
22. Anything you recommend deliberately NOT changing

Do not implement anything yet.

The result should be detailed enough that I can review it with another engineer and then give you a single instruction to implement the entire plan.

Do not divide the work into Release 1, Release 2, Release 3, etc.

This is one coordinated optimization release with no feature flags.
