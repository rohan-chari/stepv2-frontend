# Twenty-minute production watch

Production b20ad0b. September 11 2026, 22:59:49.007–23:19:49.567 UTC (6:59–7:19 PM EDT), 1200.56 seconds. All collectors completed: 21 pg_stat_statements snapshots, 240 activity samples, 121 DigitalOcean CPU samples, 19 complete pg_stat_monitor minute buckets. No collector errors; no global stats reset. Deallocation counter advanced 185 to 186. Main sample-read, sync-insert, and fingerprint-proof entries retained their original stats_since throughout all 21 snapshots; overall totals can omit evicted query work.

| Work | Calls | Accumulated execution seconds |
|---|---:|---:|
| All four event fingerprint families | 3036 | 56.49 |
| Step-sample replacement/upsert variants combined | 419 | 33.38 |
| Batched step-sample reads | 965 | 21.37 |
| Scoring-version lock/create | 779 | 15.88 |
| Notification missing-device-snapshot check | 4 | 13.46 |
| Step-sync request inserts | 777 | 12.79 |
| Active-effect reads | 2342 | 11.88 |
| Race-job upserts | 657 | 10.58 |
| Notification admission lane lock | 896 | 3.56 |
| Removed materialization sweep | 0 | 0 |
| Operational counter upsert | 0 | 0 |

Execution elapsed includes waits, not just CPU. Monitoring query cost is excluded from the application table: pg_stat_monitor SELECT captured 36.07 seconds, pg_stat_statements snapshot SELECT 8.54 seconds. Plugin attributes about 10.37 CPU seconds to the monitoring application over its 19 complete buckets.

DigitalOcean average non-idle CPU 62.02%, versus 52.78% in the preceding ten-minute scan. User 32.70%, system 23.67%, iowait 0.78%, steal 1.31%. This observation does not demonstrate another CPU reduction. Sync inserts per ten minutes: 388.5 vs 370 previously. Sample reads per sync: 1.242 vs 1.370; sample elapsed per ten minutes 10.69 seconds vs 7.11 previously. Different race fanout, input sizes, traffic mix, cache state, and load prevent causal attribution from these windows alone.

First half: 423 sync inserts, 516 sample reads / 9.59 seconds, 612 fingerprint proofs / 13.56 seconds. Second half: 354 sync inserts, 449 sample reads / 11.78 seconds, 583 fingerprint proofs / 12.57 seconds. Sample-read elapsed increased despite lower counts in the second half, illustrating why read counts and latency must be considered separately.

Five sampled transaction lock waits: three scoring-version, one race-job, one other resolution query. No notification lane wait was sampled. The device-snapshot recovery check changed zero rows in four calls; it is distinct from the removed completed-materialization sweep and needs a separate historical/correctness investigation before any removal recommendation.

Health endpoint returned status ok / redis ok after collection. No production code or data changes performed. Raw artifacts: /tmp/bara-db-watch-20260911-20min.
