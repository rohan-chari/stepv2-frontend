# Post-cleanup database watch — September 11, 2026

The historical receipt **repair workload stopped**, but the one-time discovery scan was still running at the end. No configuration, application code, or production data was changed during this watch.

SQL window: 2026-09-11T19:47:12.130Z–2026-09-11T19:57:12.472Z (600.342 seconds). DigitalOcean managed PostgreSQL: one vCPU, 2 GB. CPU capture used 61 ten-second samples starting shortly after the SQL baseline. Plugin results use nine complete, deduplicated minute buckets, 19:48–19:57 UTC.

## Receipt result

- Receipt-recovery completion SQL: **0 calls**, versus **4,438** in the prior ten-minute watch.
- Start/end queue counts identical: 68,462 SUCCEEDED LEGACY_MISSING and 253 SUCCEEDED LEGACY_PROVISIONAL; no queued, retrying, processing or failed entries.
- Discovery candidates stayed at 211,553. Its cumulative scanned counter rose from 264,000 at 19:46:45 to 523,500 at 19:57:24; these queue snapshots bracket the SQL interval and are not exact ten-minute deltas.
- Exact SQL interval: **487 discovery page reads, 243,500 returned source rows, 53.95 seconds accumulated execution time**, approximately 1.58 million buffer hits. No new candidate admissions observed in the checkpoint counters.
- Discovery `completed_at` remained null. The deployed implementation advances a durable cursor in bounded pages and stops this historical source scan when exhausted. Clearing missing rows did not mark that scan complete. No checkpoint was manually changed.

Code: `src/modules/domainEvents/models/domainEventReceiptRecovery.js:93` performs source-page discovery; `:136` advances the checkpoint. `src/modules/domainEvents/jobs/domainEventReceiptRecovery.js:75` implements the now-idle per-event repair path. These references use the previously extracted deployed revision, not unrelated local edits.

## CPU comparison

| Metric | Before cleanup | After cleanup |
|---|---:|---:|
| Idle | 45.76% | 31.68% |
| Non-idle | 54.24% | 68.32% |
| User | 30.08% | 29.25% |
| System | 18.60% | 33.14% |
| I/O wait | 1.40% | 1.37% |

The 70% idle target was not met. This is live traffic immediately following a large deletion, not a controlled or steady-state benchmark. Non-idle includes waits and steal. The results establish disappearance of repairs, not overall CPU savings or the cause of higher host CPU.

## Selected query comparison

Execution time includes waits and is not CPU time. Counts are consecutive pg_stat_statements deltas with stats_since checks.

| Query | Prior calls | Current calls | Prior exec s | Current exec s |
|---|---:|---:|---:|---:|
| Receipt repair completion | 4,438 | 0 | 1.80 | 0.00 |
| Historical discovery pages | 9 | 487 | 1.21 | 53.95 |
| Notification completeness reconciliation | 2 | 2 | 3.81 | 25.62 |
| Step sample batch read | 345 | 339 | 8.17 | 20.62 |
| Race proof/roster read | 386 | 405 | 7.82 | 19.50 |
| Full event fingerprint | 701 | 743 | 7.66 | 14.28 |
| Race post-task claim | 750 | 702 | 4.40 | 7.87 |

Other substantial execution paths remain notification completeness (`src/modules/notifications/jobs/notificationCompletenessReconciler.js:146`), step-sample loading (`src/modules/steps/models/stepSample.js:142`), and race fingerprint/proof reads (`src/modules/races/services/raceResolutionInputFingerprint.js`). SQL elapsed rankings cannot establish host CPU attribution.

## Plugin observations

| Caller | Execution CPU s | Planning elapsed s | Execution elapsed s |
|---|---:|---:|---:|
| steps-http-0 | 3.41 | 33.38 | 50.98 |
| steps-http-1 | 3.80 | 32.07 | 49.34 |
| steps-cron-0 | 13.18 | 19.50 | 85.82 |
| steps-resolution-0 | 20.73 | 40.71 | 153.20 |
| bara_receipt_investigation | 0.13 | 0.00 | 1.58 |
| bara_readonly_repeat | 3.66 | 0.98 | 13.10 |

The discovery query accumulated 7.46 seconds of plugin execution CPU across those nine complete buckets. Plugin execution CPU does not account for all host CPU, and planning elapsed time is not CPU time. Monitoring remains explicitly included rather than attributed to the app.

## Capture quality

The first SQL/plugin startup reads exceeded their five-second timeout. Those partial captures were retained separately; both collectors were restarted with a 20-second read-only statement timeout. The complete restarted SQL capture has 11 snapshots, 120 activity samples and no collector errors. No statistics reset occurred; statement deallocation increased from 174 to 175, so work in entries evicted between snapshots can be omitted. No resets or server configuration changes were performed.

Public health returned OK after capture. Temporary raw evidence and scripts are in `/tmp/bara-db-watch-20260911-post-cleanup/`. The initial and aligned CPU captures are separate; this report uses `metrics-aligned.jsonl`.
