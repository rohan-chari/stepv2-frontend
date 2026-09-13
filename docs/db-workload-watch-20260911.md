# Production database workload watch — September 11, 2026

Read-only observation: **16:44:55–16:54:56 UTC (12:44:55–12:54:56 EDT)**, 601 seconds. Database host: one vCPU / 2 GB; PostgreSQL 18.6. Deployed backend commit `ee8620049adb96795b5d637f9e59035fdb4eebc6` was checked during the watch. Two HTTP workers, one resolution worker, one cron worker; staging stopped. No deployment, configuration changes, query cancellations, or application data mutations.

## Database load

61 DigitalOcean database-host samples at approximately 10-second spacing: **40.29% average idle, 59.71% non-idle**, with non-idle ranging from 46.30% to 74.18%. This misses the 70% idle target during this traffic window. Average user CPU 33.10%, system CPU 20.72%, I/O wait 1.11%, steal 0.97%; remaining non-idle includes interrupt and nice time. Non-idle is not identical to executing application CPU. PgBouncer is included in host CPU, not additive to it.

## Measured query hotspots

Execution seconds include waits; they are not CPU seconds. Counts below come from incremental `pg_stat_statements` snapshots over the full watch.

| Work | Calls | Execution seconds | Evidence |
|---|---:|---:|---|
| Race event fingerprint | 1,060 | 12.67 | 922,245 buffer hits; 103,273 result rows |
| Batched step-sample reads | 512 | 11.80 | 235,480 result rows; 9,438 shared blocks read |
| Notification completeness: missing push delivery | 2 | 8.44 | Two runs, zero rows changed; 261,836 buffer hits; 6,635 shared blocks read |
| Race post-task claims | 1,059 | 6.42 | 473 successful claims from 1,059 attempts; 718,940 buffer hits |
| Race/roster fingerprint read | 997 | 5.38 | Repeated alongside protected scoring work |

## Source attribution and next investigations

1. **Receipt recovery: substantial background write/transaction volume.** `src/modules/domainEvents/jobs/domainEventReceiptRecovery.js:91–152` opens a transaction for each repair after loading context in batches; `:180` loops through repairs. Observed 4,310 outbox locking reads and 4,310 successful-recovery updates, plus 4,374 receipt lookups and 4,374 receipt insert attempts. These four SQL shapes alone account for 17,368 calls, before transaction controls, batch claims, discovery and context loading. The table recorded 8,604 recovery updates and 4,000 recovery inserts. A bounded queue sample contained 500 `LEGACY_MISSING` rows, and automatic discovery was unfinished: this is evidence of historical catch-up, not proof that normal user traffic requires this volume forever. First measure catch-up completion; then evaluate bounded set-based repair while preserving envelope validation, source locks, lease ownership and receipt identity. Do not simply disable recovery.

2. **Repeated event fingerprinting.** `src/modules/races/services/raceResolutionInputFingerprint.js:121` repeatedly reads global events, local entitlements, impacts and boundary state. Callers include `raceScoringDependencyClosure.js:1062`, `raceResolutionQueueV2.js` planning/fencing paths, and `queries/getRaceProgress.js:2413`. Each fingerprint has four protected reads. Reuse must preserve authoritative versions, time boundaries and final concurrency fences; an ordinary display cache is insufficient. Measured calls do not establish one-to-one attribution to individual step-sync requests.

3. **Step-sample hydration.** `src/modules/steps/models/stepSample.js:142` batches requested user/time windows but still returned 235,480 rows in 512 calls. Investigate overlapping/repeated windows across scoring attempts and whether already-read samples can be reused safely. These are returned rows, not a measurement of all rows scanned; the existing batch must not be described as a row-by-row N+1 query.

4. **Notification reconciliation scans with no repair.** `src/modules/notifications/jobs/notificationCompletenessReconciler.js:146` checks materialized schedules with a correlated absence check against alerts and push outboxes. It ran twice, taking 6.49 and 1.95 seconds, changing zero rows. Default cadence is five minutes (`:9`). The output LIMIT 500 does not bound how many already-correct schedules must be checked. Investigate an indexed, checkpointed candidate scan or durable gap tracking that retains eventual repair guarantees. No production mutation was replayed with EXPLAIN ANALYZE.

5. **Queue claims and SQL planning.** `src/modules/races/models/raceResolutionPostTask.js:388` claimed 473 tasks in 1,059 attempts (586 empty attempts). Inspect repeated wakeups and due-time scheduling as well as plan shape; do not infer the cost is entirely idle polling. `src/modules/steps/services/viewerActiveEventReadBatch.js:11` is a separate planning hotspot: in nine complete plugin buckets, 182 calls spent 2.54 seconds planning versus 0.16 seconds executing and returned zero rows. It already has a prepared-read annotation, so adding that annotation is not a fix. Check actual plan reuse and parameter sensitivity. Analytics insert batching (`src/modules/analytics/services/activationEventInsertBatch.js:5`) also accumulated 1.30 seconds planning across 181 calls.

## Plugin attribution (nine complete minutes)

`pg_stat_monitor` buckets cover 16:45:00–16:54:00 UTC, wholly inside the main watch. Buckets were retained once complete and counted once, not summed across repeated scrapes. These figures are plugin-reported execution CPU and planning elapsed time, not a decomposition of total database-host CPU.

| Caller | Execution CPU seconds | Planning seconds | Execution elapsed seconds |
|---|---:|---:|---:|
| steps-cron-0 | 14.08 | 8.84 | 42.60 |
| steps-http-0 | 4.57 | 18.06 | 22.41 |
| steps-http-1 | 4.27 | 16.38 | 23.86 |
| steps-resolution-0 | 20.77 | 18.02 | 80.23 |
| bara_readonly_10min | 3.72 | 0.53 | 13.10 |

Resolution and cron lead plugin execution CPU; both HTTP workers together have substantial planning time. These counters do not explain all host CPU: parsing, planning CPU, extension overhead, background processes and kernel work are not fully attributed here. Planning elapsed time is not a direct CPU measurement. CPU/elapsed units follow [Percona's view reference](https://docs.percona.com/pg-stat-monitor/reference.html).

## Evidence quality and limitations

- 120 activity samples, 11 statement/database/table snapshots; no collector SQL errors. No stats reset, but statement-entry deallocation increased 165 → 166 near 16:51. Consecutive snapshots preserve observed increments and handle changed `stats_since`; work in evicted entries between snapshots can be lost. Overall statement totals are lower bounds, not exact traffic totals. The ranked application SQL shapes above remained measurable.
- Monitoring is visible and retained: the plugin attributes 3.72 execution CPU seconds, 0.53 planning seconds and 13.10 execution elapsed seconds to `bara_readonly_10min` in its nine-minute window. This includes our diagnostic reads and is not application work. Read-only sampling therefore had measurable overhead.
- `pg_stat_statements` planning tracking and I/O timing are off. The separate `pg_stat_monitor` planning tracker is on. No settings were changed.
- Table counters are asynchronous and cannot uniquely assign all writes or scans to one caller. No synthetic traffic or integration tests were run. No per-request query-count claim or before/after savings claim is made.
- The sampled discovery cutoff was later than the observation time despite an unfinished pass; its origin was not investigated. Do not use it to estimate backlog age or time to completion.
- Local main differs from production. Source attribution uses an extracted copy of the deployed commit, not the current working tree. Private raw captures, scripts, normalized query IDs/text, and deployed source are in `/tmp/bara-db-watch-20260911/`. No user rows, tokens or raw parameterized plugin query text were collected.

Suggested order: establish the remaining legacy catch-up workload; investigate the zero-result reconciliation scan; then target repeated scoring reads and measured planning costs. A new comparable watch after each authorized change is needed to establish actual savings.
