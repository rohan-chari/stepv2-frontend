# Repeat database workload watch — September 11, 2026

Read-only capture: **2026-09-11T18:35:32.247Z to 2026-09-11T18:45:32.607Z**, 600.4 seconds. DigitalOcean managed PostgreSQL: one vCPU / 2 GB, PostgreSQL 18.6. Production commit verified unchanged at start and end: `83940f9f341f5889e805c59e62693468c41c5dd7`; first watch used `ee8620049adb96795b5d637f9e59035fdb4eebc6`. The new deployment includes event-fingerprint caching and proof reads. This is a live-traffic comparison, not a controlled before/after benchmark.

## Host load comparison

| Metric | First watch | Repeat |
|---|---:|---:|
| Average idle CPU | 40.29% | 45.76% |
| Average non-idle CPU | 59.71% | 54.24% |
| User CPU | 33.10% | 30.08% |
| System CPU | 20.72% | 18.60% |
| I/O wait | 1.11% | 1.40% |
| Steal | 0.97% | 0.91% |

Repeat non-idle range: 38.95%–73.91%. 61 host samples. The 70% idle target remains unmet if this window is representative. Non-idle includes waits and steal, not just application execution.

## SQL comparison

Full-window `pg_stat_statements` deltas. Execution seconds include waits and are not CPU seconds. A dash means the SQL shape was not observed in that window, rather than a proven absence of equivalent work.

| Query / code path | First calls | Repeat calls | First exec s | Repeat exec s |
|---|---:|---:|---:|---:|
| Full event fingerprint | 1,060 | 701 | 12.67 | 7.66 |
| Step-sample batch reads | 512 | 345 | 11.80 | 8.17 |
| New proof-bearing race/roster read | — | 386 | — | 7.82 |
| Notification materialization-gap reconciliation | 2 | 2 | 8.44 | 3.81 |
| Race post-task claim | 1,059 | 750 | 6.42 | 4.40 |
| Original race/roster read | 997 | 334 | 5.38 | 1.35 |
| Receipt recovery completion | 4,310 | 4,438 | 1.89 | 1.80 |
| Receipt insert attempts | 4,374 | 4,456 | 4.05 | 4.59 |

## Interpretation and source locations

- **Event-fingerprint work must be evaluated as a family.** `src/modules/races/services/raceResolutionInputFingerprint.js:35` now adds a proof to selected race/roster reads; `raceFingerprintEventProof.js:9` builds that witness. `readRaceFingerprintEvents.js` performs cache fills, local refreshes and authoritative fallback. `raceResolutionQueueV2.js:1510` admits worker planning to the cache; final fences and HTTP callers still use authoritative SQL. The full event query's call count alone is not a cache hit-rate measurement. No process-local cache counters were available through the read-only capture.
- **Step-sample hydration** remains attributable to `src/modules/steps/models/stepSample.js:142`; compare returned rows and blocks below, rather than assuming every batch is equally sized.
- **Receipt recovery** opens per-repair transactions in `src/modules/domainEvents/jobs/domainEventReceiptRecovery.js:91` after batched context loading. Both start and end samples contained 500 queued `LEGACY_MISSING` entries; discovery remained unfinished. Historical catch-up can dominate this path independently of new user activity; sampling 500 queued rows does not measure total backlog size.
- **Notification completeness** at `src/modules/notifications/jobs/notificationCompletenessReconciler.js:146` searches for missing push outboxes. Its default five-minute cadence and zero-result scans remain worth checking.
- **Queue claims** at `src/modules/races/models/raceResolutionPostTask.js:388` can return no task. Claim attempts, successful claims and database work are distinct measures.

| Repeat query | Returned/affected rows | Buffer hits | Shared blocks read |
|---|---:|---:|---:|
| Full event fingerprint | 81,259 | 654,849 | 124 |
| Step-sample batch reads | 144,464 | 52,332 | 7,156 |
| New proof-bearing race/roster read | 15,759 | 268,720 | 302 |
| Notification materialization-gap reconciliation | 0 | 260,010 | 9,984 |
| Race post-task claim | 350 | 521,659 | 309 |

## Plugin CPU and planning

Nine complete buckets, 18:36:00–18:45:00 UTC, counted once each. Plugin execution CPU does not partition total host CPU; planning elapsed time is not CPU time.

| Caller | Execution CPU s | Planning s | Execution elapsed s |
|---|---:|---:|---:|
| steps-http-0 | 3.04 | 9.07 | 12.99 |
| steps-http-1 | 2.63 | 8.77 | 13.67 |
| steps-resolution-0 | 16.75 | 15.21 | 62.04 |
| steps-cron-0 | 14.44 | 8.56 | 37.22 |
| bara_readonly_repeat | 3.67 | 0.31 | 10.20 |
| unknown | 0.00 | 0.00 | 0.00 |

Top planning queries (query IDs map to normalized SQL in the private artifacts):

| Query ID | Calls | Planning s | Execution s |
|---|---:|---:|---:|
| `4282444812282879035` | 105 | 1.44 | 0.08 |
| `-5562446031611005566` | 3990 | 1.13 | 1.56 |
| `-6471849990781115159` | 399 | 0.87 | 1.01 |
| `-2382482178559971389` | 330 | 0.77 | 1.86 |
| `3743891669488216191` | 207 | 0.73 | 3.57 |
| `-4853610946093832639` | 278 | 0.69 | 0.19 |

## Capture quality

- 11 statement snapshots; 120 activity samples; 0 SQL collector errors.
- Statement metadata before: `[{"dealloc": "172", "stats_reset": "2026-09-01T23:25:56.323Z"}]`; after: `[{"dealloc": "172", "stats_reset": "2026-09-01T23:25:56.323Z"}]`. Deallocation or reset invalidates naive cumulative subtraction. This report uses consecutive snapshots with `stats_since` checks; totals may omit work in evicted entries between snapshots. First-watch totals had this limitation.
- Monitoring work remains included under `bara_readonly_repeat` in the plugin table, rather than being attributed to the app. Host metrics include monitoring overhead and PgBouncer.
- `pg_stat_statements` planning tracking is off, while the separate `pg_stat_monitor` planning tracker is on; I/O timing is off. No configuration was changed.
- Backend source was extracted at the observed deployed commit; the working tree was not used as production truth. No deployment, cancellations, production data mutations, staging starts or integration tests.
- Raw artifacts and analysis scripts: `/tmp/bara-db-watch-20260911-repeat/`. Prior capture retained separately in `/tmp/bara-db-watch-20260911/`. Raw plugin query text and user rows were not collected.

## Comparison conclusion

Average non-idle CPU fell by 5.47 percentage points, but step-sample query calls fell from 512 to 345 (32.6%) and post-task claim attempts from 1,059 to 750 (29.2%). Receipt repairs increased from 4,310 to 4,438. These workload changes prevent attributing the host difference to caching. The new proof-bearing query consumed 7.82 execution seconds in addition to continuing full event reads, and replaces part of the original roster-read workload. Both notification gap checks again affected zero rows. No statement-stat reset or deallocation occurred in this repeat. All three collectors completed and stopped.
