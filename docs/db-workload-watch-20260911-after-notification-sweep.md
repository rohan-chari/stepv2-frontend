# Watch after notification sweep removal

Production 3ac1bcd. September 11, 2026, 22:20:09.073–22:30:09.569 UTC (6:20–6:30 PM EDT), 600.496 seconds. All collectors completed: 11 pg_stat_statements snapshots, 120 activity samples, 61 DigitalOcean CPU samples, nine complete pg_stat_monitor buckets. No collector errors or stats reset; deallocation counter unchanged at 183. Public API/Redis health passed.

| Work | Calls | Accumulated execution seconds |
|---|---:|---:|
| Removed completed-notification materialization sweep | 0 | 0 |
| Removed scoring diagnostic counter upsert | 0 | 0 |
| Notification admission lane lock | 235 | 1.42 |
| All four event fingerprint query families | 1266 | 22.33 |
| Step-sample reads | 435 | 10.17 |
| Per-user scoring-version lock/create | 275 | 6.85 |
| Race-resolution job upserts | 263 | 4.80 |
| Step-sync request inserts | 275 | 4.58 |
| Missing notification device-snapshot check | 2 | 4.49 |

Previous watch: notification lock 285 calls / 56.98 seconds; sweep two calls / 35.39 seconds. Current scan sampled no notification lock waits. Two scoring-version transactionid wait observations and one race-job transactionid wait observation remain. Sample absence does not establish no short waits.

DigitalOcean average non-idle CPU 55.24%, previously 74.47%. Traffic differs: step-sync request inserts 275 vs 441, so this is not a controlled CPU improvement measurement. Total statement execution elapsed 206.46 seconds vs 634.65 seconds previously, including monitoring queries and concurrent waits. Monitoring pg_stat_monitor SELECT itself accounts for 18.65 seconds in the statement window; exclude it from application ranking. Plugin monitoring application CPU totals about 4 seconds across nine complete buckets.

Fingerprint detail: proof 501 calls / 9.93 seconds; full event reads 475 / 5.52 seconds; local refresh 243 / 5.85 seconds; remaining fill calls included in the family total. Grouped fingerprints remain the largest listed application query family. Missing-device-snapshot recovery changed zero rows in two calls; do not infer that it is unnecessary solely from this window.

Raw artifacts: /tmp/bara-db-watch-20260911-no-notification-sweep. No implementation or production changes during this watch.
