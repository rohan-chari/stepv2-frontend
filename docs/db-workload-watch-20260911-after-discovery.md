# Database workload after discovery completed — September 11, 2026

Read-only SQL window: **20:07:13.615–20:17:13.944 UTC**, 600.329 seconds (4:07–4:17 PM EDT). DigitalOcean managed PostgreSQL remains one vCPU / 2 GB. Production revision checked at start: `83940f9f341f5889e805c59e62693468c41c5dd7`.

## Receipt work is gone

Both historical discovery-page SQL and receipt-recovery completion SQL had **zero calls**. The start/end queue was empty of pending work, with successful counts unchanged (68,462 LEGACY_MISSING; 253 LEGACY_PROVISIONAL). Discovery stayed completed at 20:04:12.564 UTC, scanned 681,437 and discovered 211,553. The historical pass did not restart.

## CPU

61 DigitalOcean host samples: **38.09% idle / 61.91% non-idle**. Previous post-cleanup window, with discovery still running: 31.68% idle / 68.32% non-idle. Earlier pre-cleanup watch: 45.76% idle / 54.24% non-idle. Current user CPU 31.09%, system 23.30%, I/O wait 1.00%, steal 2.99%; the remaining non-idle includes interrupt handling. The 70% idle target is still unmet.

This is changing live traffic, not a controlled benchmark. Removing discovery is proven by its zero SQL calls; the host CPU difference cannot be attributed entirely to it. Current step-sync request inserts increased to 278 from 238 in the previous window; race event fingerprints increased to 821 from 743. These are workload proxies, not user/session counts.

## Remaining application query paths

Accumulated execution time includes waits, not just CPU. File references below are relative to deployed `src/modules/`.

| Path | Calls | Exec seconds | Rows returned/affected | Buffer hits |
|---|---:|---:|---:|---:|
| Race event fingerprint | 821 | 14.60 | 93,180 | 748,975 |
| Race proof/roster read | 461 | 14.14 | 18,186 | 313,559 |
| Step-sample batch reads | 393 | 14.97 | 190,081 | 70,858 |
| Race job bulk upsert | 280 | 13.65 | 625 | 12,792 |
| Step-sync request insert | 278 | 9.31 | 278 | 3,231 |
| Scoring-version row lock/create | 279 | 9.23 | 279 | 1,164 |
| Notification missing-push reconciliation | 2 | 4.62 | 0 | 261,609 |
| Notification missing-device-snapshot reconciliation | 2 | 1.97 | 0 | 128,601 |
| Race post-task claims | 849 | 6.38 | 386 | 579,108 |

Source mapping:

- Race event fingerprint: `races/services/raceResolutionInputFingerprint.js:135`.
- Race proof/roster read: `races/services/raceResolutionInputFingerprint.js:35`.
- Step-sample batch reads: `steps/models/stepSample.js:142`.
- Race job bulk upsert: `races/models/raceResolutionJobV2.js:858`.
- Step-sync request insert: `steps: step-sync request persistence`.
- Scoring-version row lock/create: `steps/services/scoringInputVersion.js:101`.
- Notification missing-push reconciliation: `notifications/jobs/notificationCompletenessReconciler.js:146`.
- Notification missing-device-snapshot reconciliation: `notifications/jobs/notificationCompletenessReconciler.js:213`.
- Race post-task claims: `races/models/raceResolutionPostTask.js:388`.

## Priorities suggested by the evidence

1. **Race fingerprint/proof work:** the two selected reads total 1,282 calls and 28.75 seconds. They are used by resolution workers and race-progress reads. Investigate repeated reads and cache/final-validation boundaries together; do not remove correctness fences or treat the full-query call count as cache hit rate.
2. **Step-sync/resolution pipeline:** 393 sample batches, 280 bulk race-job upserts, and 278 request inserts. Sample reads cost 14.97 seconds; the race-job upsert costs 13.65 seconds. Determine avoidable repeated work and row-lock contention before changing indexes or deduplication. Existing upsert is already bulk SQL; 280 calls does not mean 280 distinct jobs/users.
3. **Notification historical checks:** the missing-push and missing-device-snapshot checks each ran twice and affected zero rows. They inspect history on a five-minute cadence. Review query plans and a bounded/incremental repair strategy that preserves durable notification guarantees; do not simply disable reconciliation.
4. **Planning overhead:** plugin measurements below show substantial planning elapsed time in HTTP workers and resolution. Inspect the highest-frequency/repeated SQL and existing named prepared-query coverage. Planning elapsed time is not CPU and does not by itself prove a missing index.

These are investigation priorities, not implemented fixes or quantified savings forecasts.

## Plugin attribution and monitoring overhead

Nine complete, deduplicated pg_stat_monitor buckets: 20:08–20:17 UTC. Execution CPU does not partition total host CPU; planning elapsed is not CPU.

| Caller | Calls | Execution CPU s | Planning elapsed s | Execution elapsed s |
|---|---:|---:|---:|---:|
| steps-cron-0 | 14,308 | 6.18 | 10.67 | 29.10 |
| steps-resolution-0 | 48,285 | 23.33 | 35.23 | 138.95 |
| steps-http-1 | 16,373 | 5.06 | 28.28 | 64.75 |
| steps-http-0 | 15,927 | 5.06 | 46.99 | 53.22 |
| unknown | 11 | 0.02 | 0.01 | 1.03 |
| bara_readonly_repeat | 904 | 4.67 | 0.57 | 22.81 |
| steps-all-0 | 57 | 0.03 | 0.05 | 0.12 |

The resolution worker is the largest application caller by plugin execution CPU (23.33 seconds in nine full minutes). Both HTTP workers together accumulated 75.28 seconds of planning elapsed time. No per-user/request traces were captured, so workload amplification per individual sync cannot be calculated from this aggregate capture.

Monitoring is material: the plugin polling SELECT alone accumulated 18.49 seconds of pg_stat_statements execution time. The monitoring caller accumulated 4.67 seconds of plugin execution CPU and 22.81 seconds of execution elapsed time in the nine full buckets. Those costs are included, not attributed to application code. Activity samples included some pg_stat_monitor lock waits, disk reads, row-lock waits, and autovacuum; counts are sparse samples, not duration measurements.

## Capture quality

11 statement snapshots, 120 activity samples, no SQL collector errors, and 61 managed-host CPU samples. No statistics reset; deallocation increased 175→176. Consecutive stats_since-aware deltas handle counter changes but may omit entries evicted between snapshots. Plugin and pg_stat_statements totals have different windows/accounting and should not be equated. Planning tracking was available through the plugin; pg_stat_statements planning and I/O timing remain off.

No production writes, deployment, configuration change, service restart or integration tests. All three monitoring collectors finished; public health returned OK. Raw evidence and analysis scripts: `/tmp/bara-db-watch-20260911-final/`.
