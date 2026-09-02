# PostgreSQL Production Evidence Report

**System:** Bara / Steps Tracker backend  
**Evidence captured:** September 2, 2026  
**Scope:** Read-only production measurement following the static high-CPU audit  
**Safety:** No code, schema, configuration, process, or database state was changed

## Safety statement

All database queries used for this report were read-only. The investigation did
not:

- create or drop an index;
- run a migration;
- restart or reload a process;
- alter a PostgreSQL setting;
- enable or reset `pg_stat_statements`;
- run `VACUUM`, `ANALYZE`, `REINDEX`, or `CLUSTER`;
- terminate a query or connection;
- run `EXPLAIN ANALYZE` against a mutating statement; or
- expose database credentials, connection details, PII, or user step data.

## 1. Current production resource state

### PostgreSQL environment

| Item | Production evidence |
|---|---|
| Platform | DigitalOcean managed PostgreSQL |
| Version | PostgreSQL 18.6, 64-bit Linux |
| Database size | 2.99 GB |
| PostgreSQL CPU count | Not exposed through available database privileges or local DigitalOcean tooling |
| `shared_buffers` | 391 MB |
| `effective_cache_size` | 1,172 MB |
| `work_mem` | 2 MB |
| Maximum connections | 50 |
| Connections at initial snapshot | 20 |
| Active at initial snapshot | 1 |
| Idle at initial snapshot | 19 |
| Idle in transaction at initial snapshot | 0 |
| `max_worker_processes` | 8 |
| `max_parallel_workers` | 8 |
| Parallel workers per gather | 2 |
| PostgreSQL uptime at capture | Approximately 11 hours |
| `pg_stat_database.stats_reset` | NULL; no explicit reset recorded |
| `pg_stat_statements` | Not installed |
| Managed CPU graph | Not accessible through the available SSH/database credentials |

The DigitalOcean CPU graph could not be independently read from the available
credentials. The live database counters nevertheless show substantial
continuous work during the measurement window.

### Twenty-second database workload sample

Over a 20-second interval PostgreSQL recorded:

| Counter | Delta | Rate |
|---|---:|---:|
| Committed transactions | 1,503 | 75.2/s |
| Rollbacks | 1 | 0.05/s |
| Shared blocks read | 5,956 | 297.8/s |
| Shared-block hits | 744,777 | 37,239/s |
| Tuples returned | 1,010,231 | 50,512/s |
| Tuples fetched | 685,882 | 34,294/s |
| Rows inserted | 17 | 0.85/s |
| Rows updated | 114 | 5.7/s |
| Rows deleted | 0 | 0/s |

The workload is overwhelmingly cached reads rather than physical I/O. This is
consistent with high CPU caused by repeated index traversal, tuple filtering,
and tuple processing.

### Bara process topology

The production process layout matched the intended topology:

| Process | Count | `STEPS_PROCESS_ROLE` | Mode |
|---|---:|---|---|
| `steps-tracker` | 2 | `http` | PM2 cluster |
| `steps-tracker-resolution` | 1 | `resolution` | Fork |
| `steps-tracker-cron` | 1 | `cron` | Fork |
| Staging | 0 running | — | Stopped |

No process used the `all` role. No duplicate resolution or cron process was
found.

### Application-host resources

The application host had four CPUs and 7.8 GiB RAM. At inspection time:

| Process | CPU |
|---|---:|
| Resolution Node process | 28.3% |
| Cron Node process | 14.0% |
| HTTP worker 1 | 6.2% |
| HTTP worker 2 | 6.0% |
| Redis | 0.5% |

The resolution and cron processes were themselves doing meaningful work.
PostgreSQL is managed remotely, so its backend processes were not present in the
application-host process list.

## 2. Highest-impact PostgreSQL workloads

### Historical normalized-query limitation

`pg_stat_statements` was not installed. It was therefore impossible to produce
trustworthy historical top-query rankings by:

- normalized query ID;
- total or mean execution time;
- call count/calls per second;
- WAL bytes per query;
- block activity per normalized statement; or
- percentage of total SQL execution time.

The investigation did not enable the extension because that would violate the
safety requirements and ordinarily requires a settings/restart change.

The best available evidence consists of:

1. 20-second cumulative table/index-statistic deltas;
2. exact production index usage since PostgreSQL startup;
3. repeated live `pg_stat_activity` sampling;
4. queue status distributions; and
5. PM2 logs and worker resource usage.

### Top live table/index workloads

During the 20-second interval:

| Table or query family | Index scans/s | Index tuples fetched/s | Interpretation |
|---|---:|---:|---|
| `global_event_summary_work` | **4,505** | **13,384** | Dominant repeated index activity |
| Domain-event projections | 22 | **7,046** | Relatively few scans traverse many tuples |
| Race participants | 16 | 948 | Race resolution and hydration |
| Notification schedules | 2.8 | 970 | Schedule/admission scans |
| Step samples | 39 | 781 | Participant scoring |
| Steps | 20 | 42 | Daily-step scoring |
| Domain-event outbox | 279 | 96 | High probe/unique-key activity |
| Race-resolution queue | 35 | 18 | Polling, enqueue, and claims |
| Placement queue | 24 | 36 | Polling and state checks |
| Post-task queue | 16 | less than 1 | Mostly empty/terminal probes |
| Full-trigger queue | 10 sequential + 10 index scans/s | negligible | Empty but continuously probed |
| Inbox delivery outbox | 2.7 | negligible | No active delivery backlog |

The live ranking is therefore:

1. global-summary index probing;
2. domain-event projection scans over terminal history;
3. race/step reads; and
4. queue polling.

### High call count versus individually expensive statements

The evidence points primarily to high call count and repeated tuple scanning:

- 75 transactions/s;
- 37,239 buffer hits/s;
- only 298 physical reads/s;
- 50,512 tuples returned/s; and
- 34,294 tuples fetched/s.

Some live race-resolution/scoring queries lasted 0.4–0.7 seconds. Resolution
queue activity was also observed waiting on transaction locks for 0.7–1.9
seconds. Expensive individual queries and contention do occur, but the
persistent baseline is dominated by repeated cached work.

## 3. Polling cost

### Full-trigger promotion every 250 ms

Production facts:

- `race_resolution_full_triggers` contained zero rows.
- In 20 seconds it accumulated:
  - 204 sequential scans, or 10.2/s;
  - 204 index scans, or 10.2/s;
  - zero inserts, updates, or deletes.
- Since PostgreSQL startup it had:
  - 49,645 sequential scans;
  - 32,185 index scans;
  - 914 historical inserts; and
  - 913 deletes.
- The table used 8 KiB of heap and 208 KiB of indexes.

Conclusion: **HIGH unnecessary background work, but unlikely to be the sole
cause of 90% CPU.**

The static suspicion is confirmed: the empty trigger table is repeatedly
probed. The table is tiny, so each probe is currently cheap. This is noisy and
avoidable, but the evidence does not make it the dominant CPU consumer.

Relevant code:

- backend `src/modules/races/jobs/raceResolutionQueueV2.js`,
  `processOneUnbudgeted`
- backend `src/modules/races/models/raceResolutionJobV2.js`,
  `promoteFullScopeTriggers`

### Race-resolution claims

Over 20 seconds:

- queue index scans increased by 701: 35.1/s;
- queue index tuple fetches increased by 365: 18.3/s;
- queue-row updates increased by eight; and
- all 1,174 queue rows were `succeeded` at the status snapshot.

The SELECT-only claim equivalent was inspected with
`EXPLAIN (COSTS, VERBOSE)`. The plan was:

```text
Limit
  -> LockRows
       -> Sort
            Sort Key:
              CASE queue_priority ...,
              requested_at,
              race_id
            -> Bitmap Heap Scan
                 Recheck:
                   state = queued OR state = running
                 Filter:
                   retry/not-before eligibility OR expired lease
                 -> BitmapOr
                      -> Bitmap Index Scan for queued
                      -> Bitmap Index Scan for running
```

PostgreSQL was:

- using bitmap index scans;
- combining queued/running branches through `BitmapOr`;
- filtering timestamp eligibility after the heap scan;
- explicitly sorting for the custom priority order; and
- not using a sequential scan.

The plan mismatch identified statically is real. Its current estimated cost is
low because the table is only 1,174 rows and has no active work.

Conclusion: **MEDIUM steady overhead.** It contributes to the background floor
but is not the largest current source.

### Placement polling

Over 20 seconds:

- 476 index scans, or 23.8/s;
- 719 tuples fetched, or 36/s;
- six queue updates;
- 446 succeeded rows;
- six retry rows; and
- one queued row.

The production claim index was 1.15 MB and had fetched more than one million
tuples since startup despite only 453 live rows.

Conclusion: **MEDIUM background overhead.** The table is too small to explain
most CPU by itself.

### Resolution post-task polling

Over 20 seconds:

- 324 index scans, or 16.2/s;
- 14 tuples fetched;
- ten task updates; and
- every one of 368,431 rows was terminal.

The nominal due-state index
`race_resolution_post_tasks_state_not_before_at_idx` had zero scans. Other
indexes were being used against a 610 MB terminal table.

Conclusion: **HIGH structural concern.** The active queue was empty, but its
high-frequency probes operate against 368k retained tasks and 610 MB of
heap/index data.

### Redis wake-ups

Redis wake-ups supplement polling rather than replace it. Schedule release
still has a five-second fallback and inbox delivery a 15-second fallback, with
additional due timers. PostgreSQL remains the durable recovery path.

## 4. Race-resolution scoring cost

### Live step/sample activity

Over 20 seconds:

| Table | Index-scan delta | Rate | Tuple-fetch delta | Rate |
|---|---:|---:|---:|---:|
| `step_samples` | 781 | 39.1/s | 15,623 | 781/s |
| `steps` | 403 | 20.2/s | 838 | 41.9/s |
| `race_participants` | 320 | 16/s | 18,966 | 948/s |

Live sampling caught step-scoring statements on CPU for 0.445 and 0.661
seconds. The resolution Node process was using 28.3% host CPU.

### Cumulative index activity

Since PostgreSQL startup:

- `step_samples_user_id_period_end_idx`
  - 3.37 million scans;
  - 237.7 million tuples read;
  - 215.6 million tuples fetched.
- `step_samples_user_id_period_start_period_end_idx`
  - 17,868 scans;
  - 11.5 million tuples read.
- `race_participants_race_id_status_idx`
  - 1.38 million scans;
  - 60.6 million tuples read;
  - 54.5 million tuples fetched.

### Resolution-count correlation limitation

The last 200,000 resolution log lines contained 378
`race_resolution_v2_claim` records. That log slice was not a reliable time
window, so it could not support a defensible scoring-statements-per-resolution
ratio. Exact normalized statement counts require `pg_stat_statements` or an
approved temporary query telemetry mechanism.

Conclusion: **HIGH contributor during active resolutions.** Participant-linear
scoring is confirmed in production through busy sample indexes, several
hundred-millisecond live queries, substantial participant reads, and elevated
resolution-process CPU.

Relevant code:

- backend `src/modules/races/services/raceStateResolution.js`,
  `calculateBaseAdjusted`, `calculateCurrentTotal`, `determineFinishSnapshot`,
  and `resolveRaceState`
- backend `src/modules/races/jobs/raceResolutionQueueV2.js`,
  `processOneUnbudgeted`

## 5. Notification cost

### Terminal history

| Table | Active | Terminal | Terminal percentage |
|---|---:|---:|---:|
| Domain-event outbox | 0 | 358,954 | 100% |
| Notification projections | 0 | 359,935 | 100% |
| Inbox delivery outbox | 0 | 47,353 | 100% |
| Device attempts | 0 | 63,701 | 100% |
| Notification schedules | 4,921 future admission-pending | 6,210 | 55.8% terminal/materialized |

The 4,921 admission-pending schedules were approximately 32 minutes in the
future at capture time; they were not an overdue delivery backlog.

### Table/index condition

| Table | Total size | Estimated dead percentage |
|---|---:|---:|
| Domain-event outbox | 392 MB | 68.4% |
| Notification projections | 296 MB | 60.1% |
| Device attempts | 53 MB | 47.5% |
| Inbox delivery outbox | 48 MB | 9.3% |
| Notification schedules | 19 MB | 17.0% |

No autovacuum had been recorded for the domain-event outbox or projection table
in the current statistics window.

### Live cost

Over 20 seconds:

- domain-event outbox:
  - 5,570 index scans, or 278.5/s;
  - 1,924 tuples fetched, or 96/s.
- notification projections:
  - 445 index scans, or 22.3/s;
  - 140,920 tuples fetched, or **7,046/s**.
- notification schedules:
  - 56 scans, or 2.8/s;
  - 19,404 tuples fetched, or 970/s.
- inbox delivery outbox:
  - negligible live delivery work.

Live activity included three concurrent domain-event statements, one running
for 0.645 seconds.

The general projection status index had:

- 36 MB size;
- 86,088 scans;
- 235.4 million index tuples read; and
- 90.4 million tuples fetched.

Conclusion: **CRITICAL contributor.** There was no active delivery backlog, but
projection and reconciliation paths were scanning large tables consisting
almost entirely of terminal history. The measured cost is primarily retained
notification history and database projection work, not APNs/FCM delivery.

## 6. Global-event cost

### Summary work status

| Status | Rows |
|---|---:|
| `WAITING_SYNC` | 90 |
| `ALL_ZERO` | 545 |
| `CREATED` | 1,192 |
| `EXPIRED_UNDELIVERED` | 2,983 |
| `UNSCORABLE` | 180 |

Active rows: 90, or 1.8%.  
Terminal rows: 4,900, or 98.2%.

`global_event_race_impacts` contained:

- 597 pending;
- 18,376 final;
- 6,401 expired-undelivered; and
- 641 unscorable.

Some pending impacts were almost 15 days old.

### Live summary workload

Over 20 seconds, `global_event_summary_work` generated:

- 90,109 index scans;
- 267,684 index tuples fetched;
- zero row updates during that interval.

Rates:

- **4,505 index scans/s**;
- **13,384 tuple fetches/s**.

Since PostgreSQL startup:

- 153.6 million index scans;
- 455.5 million index tuples fetched;
- 428,805 row updates;
- only 2,068 HOT updates;
- HOT-update rate: **0.48%**.

The dominant production index was:

```text
global_event_summary_work_user_id_status_expires_at_idx
(user_id, status, expires_at)
```

It had:

- 152.2 million scans;
- 447.4 million tuples read;
- 446.8 million tuples fetched.

Conclusion: **CRITICAL and the strongest measured root cause.** Only 90 rows
were active, yet the table generated more than 4,500 index scans/s. This points
to persistent eligibility/status probing from user/step-sync and lifecycle
paths rather than merely event-end aggregation bursts.

Relevant code:

- backend `src/modules/steps/services/globalEventSummaryCapture.js`,
  `claimEligibleSummaryWork`
- backend `src/modules/steps/jobs/globalEventSummary.js`, `runV2`,
  `reconcileWorkRaceQueues`, and `claimActiveWork`
- summary reads in Home and step-sync paths

## 7. Queue sizes and terminal history

| Table | Total size | Active rows | Terminal rows | Terminal percentage |
|---|---:|---:|---:|---:|
| Race-resolution jobs | 4.1 MB | 0 | 1,174 | 100% |
| Full triggers | 240 KB | 0 | 0 | — |
| Placement jobs | 1.6 MB | 7 | 446 | 98.5% |
| Post-tasks | 610 MB | 0 | 368,431 | 100% |
| Post-task intents | 5.1 MB | 0 | 2,898 | 100% |
| Domain-event outbox | 392 MB | 0 | 358,954 | 100% |
| Notification projections | 296 MB | 0 | 359,935 | 100% |
| Notification schedules | 19 MB | 4,921 future | 6,210 | 55.8% |
| Inbox delivery outbox | 48 MB | 0 | 47,353 | 100% |
| Device attempts | 53 MB | 0 | 63,701 | 100% |
| Summary work | 5.4 MB | 90 | 4,900 | 98.2% |

The suspected “small active queue plus large terminal history” pattern was
confirmed for post-tasks, domain events, projections, inbox delivery, global
summaries, placement, and race resolution.

## 8. MVCC, dead tuples, and autovacuum

### Most concerning statistics

| Table | Dead tuples | Estimated dead % | Updates | HOT updates | HOT % |
|---|---:|---:|---:|---:|---:|
| Domain-event outbox | 23,003 | 68.4% | 23,003 | 0 | 0% |
| Notification projections | 16,767 | 60.1% | 16,767 | 0 | 0% |
| Device attempts | 1,759 | 47.5% | 2,740 | 1,029 | 37.6% |
| Global-event impacts | 1,815 | 93.5% estimate | 2,246 | 431 | 19.2% |
| Placement jobs | 115 | 20.3% | 29,589 | 0 | 0% |
| Race-resolution jobs | 202 | 14.7% | 48,575 | 16,798 | 34.6% |
| Summary work | 508 | 7.3% | 428,805 | 2,068 | **0.48%** |
| Post-tasks | 19,914 | 5.1% | 50,496 | 27,849 | 55.2% |

Planner statistics for the domain-event tables were stale: actual counts were
approximately 359k, while `n_live_tup` estimates were only 10–11k. That
discrepancy is itself evidence of missing or ineffective recent analyze work.

### Active vacuum

`pg_stat_progress_vacuum` returned no rows. No vacuum was active during the
snapshot.

### Long transactions

- no transaction older than 30 seconds;
- no transaction older than five minutes;
- oldest observed transaction was milliseconds old.

Long transactions were not preventing dead-tuple cleanup at capture time.

Conclusions:

- MVCC/write amplification: **HIGH**;
- active autovacuum as the immediate sampled CPU consumer: **RULED OUT**;
- insufficient vacuum/analyze history for large notification tables: **HIGH
  operational concern**.

Low HOT rates are expected when updates change indexed status, availability,
lease, expiry, or timestamp fields. Summary and placement are especially poor:

- summary: 0.48% HOT;
- placement: 0%;
- domain-event outbox and projections: 0%.

## 9. Production index findings

### Most consequential indexes

#### `global_event_summary_work_user_id_status_expires_at_idx`

- definition: `(user_id, status, expires_at)`;
- size: 576 KB;
- scans: 152.2 million;
- tuples read: 447.4 million;
- tuples fetched: 446.8 million;
- conclusion: primary measured hot spot.

#### `domain_event_notification_projections_status_available_at_id_id`

- definition: `(status, available_at, id)`;
- size: 36 MB;
- scans: 86,088;
- tuples read: 235.4 million;
- tuples fetched: 90.4 million;
- includes terminal history.

#### `step_samples_user_id_period_end_idx`

- size: 68 MB;
- scans: 3.37 million;
- tuples read: 237.7 million;
- represents legitimate but participant-linear scoring work.

#### Notification admission index

- size: 2.3 MB;
- scans: about 22k;
- tuples read: 17 million.

#### `race_resolution_post_tasks_state_completed_at_id_idx`

- size: 76 MB;
- scans: about 227k;
- operates over approximately 368k terminal tasks.

### Zero-scan or redundant-looking indexes

These reported zero scans in the current PostgreSQL statistics window:

- `race_resolution_post_tasks_state_not_before_at_idx`;
- non-unique `race_resolution_post_tasks_race_id_source_generation_idx`, while
  an equivalent unique index exists;
- `race_resolution_post_tasks_dedupe_key_key`;
- `race_resolution_jobs_v2_requested_at_idx`;
- `race_resolution_jobs_v2_state_not_before_at_idx`;
- `inbox_delivery_outbox_lease_token_idx`;
- `domain_event_outbox_aggregate_type_aggregate_id_occurred_at_idx`;
- non-unique `steps_user_id_date_idx`, while a unique equivalent exists.

This is not authorization to drop any index. Constraint enforcement,
mixed-version behavior, uncommon administrative paths, and the short
statistics window must be reviewed first.

### Claim-index conclusion

The race-resolution claim uses bitmap scans and a sort. Its mismatch is real
but currently cheap because the queue table is small. The more urgent indexing
issue is separating active from terminal history for:

- notification projections;
- domain-event outbox;
- post-tasks;
- global summaries; and
- notification schedules.

## 10. Connections, activity, locks, and waits

### Connections

- 20 of 50 connections were used.
- Usually 18–19 were idle.
- No connection exhaustion was evident.
- No process-role duplication was present.

### Live activity samples

Repeated samples caught:

- several CPU-running global-summary statements;
- one global-summary session briefly idle in transaction;
- three concurrent domain-event statements, one around 0.645 seconds old;
- step-scoring statements around 0.445 and 0.661 seconds old;
- resolution queue statements waiting on transaction locks for approximately
  0.7 and 1.9 seconds;
- occasional short data-file reads.

### Blocking

At the explicit blocker snapshot:

- zero ungranted locks;
- no blocker chain;
- no long transaction.

Localized resolution hot-row overlap exists, but sustained global lock
contention was not observed.

Conclusions:

- excessive connections: **RULED OUT**;
- general lock contention: **LOW**;
- localized resolution transaction contention: **MEDIUM but intermittent**.

## 11. Root-cause ranking

### CRITICAL — Global-event summary eligibility/index storm

Static evidence:

- per-sync/user summary eligibility reads;
- one-second summary worker;
- repeated waiting/reconciliation paths.

Production evidence:

- 4,505 summary index scans/s;
- 13,384 tuple fetches/s;
- 152 million scans since startup;
- 428k updates with 0.48% HOT updates;
- only 90 active rows.

Conclusion: strongest measured persistent CPU source.

### CRITICAL — Notification/domain-event terminal-history scanning

Static evidence:

- one-second projector;
- specialized claims and recovery statements;
- per-recipient projection processing.

Production evidence:

- approximately 359k terminal events and 360k terminal projections;
- tables sized 392 MB and 296 MB;
- 60–68% dead-tuple estimates;
- 7,046 projection tuple fetches/s;
- concurrent live domain-event queries.

Conclusion: major sustained contributor without an active notification backlog.

### HIGH — Participant-linear scoring and repeated race reads

Static evidence:

- several step/sample reads per participant;
- fingerprint, hydration, fence, and placement reloads.

Production evidence:

- 781 step-sample tuple fetches/s;
- 948 race-participant tuple fetches/s;
- live scoring queries lasting 0.4–0.7 seconds;
- resolution Node process at 28.3% CPU.

Conclusion: material workload-driven contributor.

### HIGH — Terminal post-task history

- 368,431 terminal tasks;
- 610 MB total size;
- active queue empty;
- high-frequency polling continues;
- nominal due-state index unused.

Conclusion: likely raises polling and cleanup cost.

### HIGH — MVCC and poor HOT-update rates

- summary 0.48% HOT;
- placement 0%;
- domain events/projections 0%;
- substantial dead-tuple estimates.

Conclusion: significant write/index amplification, although no vacuum was
active during sampling.

### MEDIUM — 250 ms queue polling

- resolution queue: 35 index scans/s;
- placement: 24/s;
- post-tasks: 16/s.

Conclusion: meaningful background floor but not the largest measured source.

### MEDIUM — Empty full-trigger promotion

- zero current rows;
- about 20 aggregate scans/s;
- tiny table.

Conclusion: unnecessary and worth fixing, but currently cheap.

### MEDIUM — Placement worker

Small table, approximately 24 scans/s, some retries. Contributes to baseline but
is not dominant.

### LOW — Inbox provider delivery

No active backlog and all outboxes terminal. Not materially responsible during
measurement.

### LOW — Event-boundary summary creation burst

Only 90 active summary rows. Persistent index reads, not a creation burst,
dominated.

### RULED OUT — Active autovacuum during capture

No vacuum was running.

### RULED OUT — Excessive connections

Only 20 of 50 connections were used, mostly idle.

### RULED OUT — Duplicate workers/process roles

Topology exactly matched the intended layout.

### RULED OUT — Sustained global lock contention

No blockers or long transactions were present at the explicit snapshot.

## 12. Recommended fixes in order

No fix was applied.

### Quick wins

#### 1. Reduce global-summary eligibility probes

- Expected impact: **very high**
- Difficulty: medium
- Correctness risk: medium
- Code:
  - `globalEventSummaryCapture.js/claimEligibleSummaryWork`
  - summary reads in Home and step-sync paths
  - `globalEventSummary.js/runV2`
- Evidence:
  - 4,505 index scans/s;
  - 13,384 tuple fetches/s;
  - only 90 active rows.

Trace the exact call path repeatedly probing `(user_id,status,expires_at)`.
Coalesce or batch the read per user sync without weakening capture fencing,
expiry, or idempotency.

#### 2. Stop promoting an empty trigger queue every 250 ms

- Expected impact: medium
- Difficulty: low
- Correctness risk: low to medium
- Code:
  - `raceResolutionQueueV2.js/processOneUnbudgeted`
  - `raceResolutionJobV2.js/promoteFullScopeTriggers`
- Evidence:
  - zero trigger rows;
  - about 20 scans/s.

Keep a durable fallback poll, but use a lower-frequency promoter, cheap
existence gate, or wake plus fallback.

#### 3. Stop post-task probes from traversing terminal history

- Expected impact: high
- Difficulty: medium
- Correctness risk: low to medium
- Code:
  - `raceResolutionPostTaskRunner.js/tick`
  - `raceResolutionPostTask.js/claimNext`
- Evidence:
  - 368k terminal tasks;
  - zero active tasks;
  - 610 MB table;
  - 16 scans/s;
  - intended due-state index unused.

### Structural optimizations

#### 4. Batch participant scoring reads

- Expected impact: very high during race activity
- Difficulty: high
- Correctness risk: high
- Code:
  - `raceStateResolution.js/calculateBaseAdjusted`
  - `calculateCurrentTotal`
  - `determineFinishSnapshot`
- Evidence:
  - live 0.4–0.7 second scoring queries;
  - 781 sample tuple fetches/s;
  - participant-linear implementation.

Preserve exact time windows, global-event eligibility, effect math, source
generations, and fingerprint semantics.

#### 5. Hand compact committed resolution context to placement

- Expected impact: medium to high
- Difficulty: high
- Correctness risk: medium
- Code:
  - `racePlacementTransitionWorker.js/processOne`
  - `racePlacementBaseline.js/loadCanonicalContext`
- Evidence:
  - repeated canonical hydration;
  - placement/participant indexes remain active with little queued work.

Retain final generation/fingerprint fencing.

#### 6. Batch domain-event projection by parent event

- Expected impact: high
- Difficulty: high
- Correctness risk: medium
- Code:
  - `notificationProjector.js/expandOne`
  - `notificationProjector.js/processOne`
- Evidence:
  - 7,046 projection tuple fetches/s;
  - 360k terminal projections;
  - concurrent live domain-event statements.

### Index and schema work for review only

#### 7. Add partial active-state indexes

- Expected impact: high
- Difficulty: medium
- Correctness risk: low for semantics, medium operationally
- Candidates:
  - active projection claim index;
  - active domain-event claim index;
  - active post-task claim index;
  - active summary-work index;
  - separate resolution queued and expired-lease indexes.

Do not add anything until exact normalized query plans can be captured and
reviewed.

#### 8. Define terminal-history retention contracts

- Expected impact: high
- Difficulty: medium to high
- Correctness risk: high
- Evidence:
  - 368k post-tasks;
  - 359k domain events;
  - 360k projections;
  - all terminal.

Retention must preserve frozen-client status polling, deduplication,
idempotency, audit needs, replay, and crash recovery.

#### 9. Review per-table autovacuum settings

- Expected impact: medium to high
- Difficulty: medium
- Correctness risk: medium operationally
- Evidence:
  - high dead-tuple estimates;
  - stale planner row estimates;
  - no recorded autovacuum on the largest notification tables.

Do not tune without first capturing managed defaults and vacuum metrics.

### Things not to optimize first

- connection pool size: no exhaustion evidence;
- general lock handling: no sustained blockers;
- inbox provider delivery: no active backlog;
- full-trigger table indexing: frequency, not table access, is the issue;
- race-resolution priority index alone: the table and plan are currently small;
- active autovacuum CPU: no vacuum ran during capture.

## 13. Evidence supporting each priority

| Recommendation | Direct production evidence |
|---|---|
| Reduce summary probes | 90,109 summary index scans in 20 seconds |
| Batch scoring | 15,623 sample fetches and 18,966 participant fetches in 20 seconds |
| Reduce empty trigger polling | Zero triggers and 408 scans in 20 seconds |
| Isolate active notification rows | 359k terminal events/projections and 7,046 projection fetches/s |
| Address post-task history | 368k terminal rows, 610 MB, no active task |
| Investigate MVCC | Summary 0.48% HOT; placement/projection 0% HOT |
| Do not prioritize connections | 20/50 connections, mostly idle |
| Do not prioritize global locking | No blockers and no long transactions |

## 14. Diagnostic information not obtainable

1. Current DigitalOcean database CPU percentage; monitoring API/CLI credentials
   were unavailable.
2. Managed PostgreSQL host CPU count and memory allocation.
3. Historical normalized query ranking because `pg_stat_statements` was absent.
4. Exact calls/s and execution time for `promoteFullScopeTriggers`.
5. Exact calls/s and execution time for the mutating resolution claim.
6. Exact execution-time percentage for scoring, notification, and summary
   families.
7. WAL bytes by normalized statement.
8. Reliable scoring-statements-per-resolution ratio.
9. Historical autovacuum duration and resource consumption.
10. `EXPLAIN ANALYZE` results for mutating claims, intentionally not run.

The strongest available measurement is sufficient to reorder priorities:
global-summary probing and notification terminal-history scans rank above the
empty full-trigger promoter, while participant-linear scoring remains a major
workload-dependent contributor.

## 15. Production evidence summary

The architecture is not inherently too expensive. PostgreSQL-backed durable
queues can retain the current durability, fencing, idempotency, and recovery
properties. The production evidence shows that the present implementation is
doing removable work:

- repeatedly probing an empty trigger queue;
- repeatedly checking a summary table with only 90 active rows thousands of
  times per second;
- scanning projection indexes containing hundreds of thousands of terminal
  rows;
- polling an empty post-task queue backed by 610 MB of terminal history; and
- issuing participant-linear scoring queries during race resolution.

The first engineering review should focus on identifying and coalescing the
exact global-summary eligibility call path, followed by active/terminal
separation for notification and post-task queues, then participant scoring
batching.

