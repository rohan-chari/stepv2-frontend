# Watch after incremental scoring cache wiring

Production b20ad0b. September 11 2026, 22:43:38.461–22:53:39.176 UTC (6:43–6:53 PM EDT), 600.715 seconds. Eleven statement snapshots, 120 activity samples, 61 CPU samples; no collector errors. No global stats reset. One statement deallocation event (184 to 185); sample-read and sync-insert entries retained the same stats_since across all snapshots with monotonic counts, so these comparisons are intact. Other aggregate query totals may omit evicted work.

| Measurement | Before | After |
|---|---:|---:|
| Step-sync request inserts | 275 | 370 |
| Batched step-sample reads | 435 | 507 |
| Sample reads per sync insert | 1.582 | 1.370 |
| Sample-read execution seconds | 10.17 | 7.11 |
| Sample-read mean milliseconds | 23.38 | 14.02 |
| DigitalOcean non-idle CPU | 55.24% | 52.78% |
| All event fingerprint families, seconds | 22.33 | 21.03 |

Observed sample reads per sync decreased about 13.4%; sample query elapsed decreased about 30.1% despite 34.5% more sync inserts. This is an observational comparison, not direct cache-hit telemetry or a controlled causal benchmark: race fanout, scoring paths, data sizes, and load vary. New-input generations still require reads.

Completed-notification sweep: zero calls. Notification lane lock: 294 calls / 0.822 seconds. Shared operational counter upsert: five calls / 0.0028 seconds; other producers still use this statement, so these calls do not establish that removed scoring diagnostics returned.

Leading application work: all fingerprint families 1563 calls / 21.03 seconds; batched step samples 507 / 7.11 seconds; one sample-write shape 57 / 5.65 seconds; race-job upserts 355 / 4.98 seconds; scoring-version lock/create 370 / 4.17 seconds. Monitoring pg_stat_monitor SELECT itself accumulated 10.16 seconds in captured deltas and is excluded from application ranking.

Production API and Redis health passed after collection. Raw artifacts: /tmp/bara-db-watch-20260911-incremental-cache. No deployment or code changes during this observation.

Architecture clarification: this cache is per process. Multiple resolution workers on separate servers could duplicate it and its cold database reads; Redis would share data across those workers. HTTP request routing does not choose the resolution worker cache. Production currently has one resolution worker.
