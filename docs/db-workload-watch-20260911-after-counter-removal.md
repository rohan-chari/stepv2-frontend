# Database watch after scoring diagnostic removal

Production commit: d1084cf. Read-only watch September 11, 2026, 21:21:33.574–21:31:34.477 UTC (5:21–5:31 PM EDT). 601 seconds; 11 statement snapshots, 120 activity samples, 61 DigitalOcean CPU samples; no collector errors or statistics resets. pg_stat_monitor analysis covers nine complete minute buckets, 21:22–21:31 UTC.

The operational counter upsert recorded zero calls, versus 1,006 calls / 96.08 seconds in the preceding watch. No claim that all other counter producers have been removed.

| Application query | Calls | Accumulated execution seconds |
|---|---:|---:|
| Notification release lane FOR UPDATE | 285 | 56.98 |
| Per-user scoring-input version lock/create | 441 | 36.90 |
| Notification completeness materialization check | 2 | 35.39 |
| Batched step-sample reads | 470 | 21.58 |
| Race fingerprint proof reads | 658 | 18.37 |
| Step-sync request inserts | 441 | 14.00 |
| Race-resolution job upserts | 372 | 11.76 |

All four event fingerprint query families combined: 1,628 calls / 37.06 seconds, versus 1,310 / 41.50 seconds in the preceding watch. Step-sync request inserts increased from 387 to 441; these are observational windows, not a controlled benchmark.

DigitalOcean average non-idle CPU: 74.47%, versus 74.32% previously. User 36.23%, system 32.51%, iowait 0.61%. No overall CPU improvement demonstrated. Monitor queries themselves contribute overhead: pg_stat_monitor SELECT accumulated 35.69 seconds; nine-minute plugin telemetry attributes about 5.41 CPU seconds to the monitoring application overall. Elapsed query time includes waits and is not CPU time.

Notification lane lock: ten sampled waiting backends (five transactionid, five tuple), all cron. Plugin reports only 0.127 CPU seconds for that statement in nine complete buckets. Scoring version lock: six sampled transactionid waits on HTTP workers, about 0.119 CPU seconds in plugin buckets. Exact blocking PIDs were not captured.

Code connection: src/modules/notifications/services/notificationAdmission.js:46 locks a shared admission-class lane. src/modules/notifications/jobs/notificationCompletenessReconciler.js:140 takes that lane lock inside a transaction before the materialization-gap scan. The scan ran twice, changed zero rows, and accumulated 35.39 seconds. This is the strongest next investigation: shorten the completeness check and its lock duration while preserving admission correctness. The code establishes a plausible blocking path; this watch does not prove the exact runtime blocker.

Per-user scoring locking is in src/modules/steps/services/scoringInputVersion.js:101. Step-sample reads are in src/modules/steps/models/stepSample.js:142. These are correctness-related paths, unlike the removed diagnostics.

Raw local artifacts: /tmp/bara-db-watch-20260911-no-scoring-counters. No implementation changes or deployment performed during this watch.
