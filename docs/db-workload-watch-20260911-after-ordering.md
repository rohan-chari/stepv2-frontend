# Database watch after deterministic event ordering — September 11, 2026

Read-only capture on production `e6201f7838af1f2bfe27933627c921a05bc7c741`: **2026-09-11T20:43:47.458Z–2026-09-11T20:53:54.060Z**, 606.602 seconds. Final snapshot reads extended the scheduled ten minutes by about seven seconds. DigitalOcean PostgreSQL: one vCPU / 2 GB. Nine complete plugin buckets: 20:44–20:53 UTC.

## Outcome

The fingerprint cache change reduced full event reads, but substantial admin analytics activity appeared during this window. Overall host CPU therefore does not demonstrate a saving: **25.68% idle / 74.32% non-idle**, versus 38.09% idle / 61.91% non-idle before deployment. The 70% idle target remains unmet. User CPU averaged 37.03%, system 31.68%, I/O wait 0.91%, steal 0.83%; non-idle also includes interrupts.

Receipt repairs and historical discovery-page reads both remained at zero. Recovery queue counts were unchanged, no pending entries, and discovery retained its 20:04:12.564 completion marker.

## Fingerprint comparison — include refresh costs

| Query family | Before calls | After calls | Before exec s | After exec s |
|---|---:|---:|---:|---:|
| Full event reads | 821 | 482 | 14.60 | 9.87 |
| Proof + roster reads | 461 | 526 | 14.14 | 18.25 |
| Cache fills | 18 | 39 | 0.10 | 3.69 |
| Local cache refreshes | 24 | 263 | 0.07 | 9.69 |

Full event reads fell 41.3% (821→482), despite proof/roster calls rising 14.1% (461→526). Full reads per proof/roster read fell from 1.78 to 0.92. This is consistent with fewer planning fallbacks; it is not a directly measured cache hit rate. Final database checks remain expected.

Cache fills/local refreshes increased as tied races became cacheable. All four families total 1,324→1,310 calls and **28.90→41.50 seconds execution elapsed**. Do not present the full-query reduction alone as total workload or CPU savings. Latencies were affected by a very different shared workload; proof timings include roster work. Cache read counters were not captured directly.

## Remaining application work

| Path | Calls | Execution elapsed s | Rows returned/affected |
|---|---:|---:|---:|
| Admin DAU/action-history | 4 | 346.05 | 244 |
| Global-event operational counters | 1,006 | 96.08 | 2,002 |
| Step-sync scoring-version lock/create | 387 | 44.80 | 387 |
| Notification missing-push reconciliation | 2 | 32.94 | 0 |
| Step-sample batch reads | 401 | 25.70 | 201,229 |
| Race job upsert | 312 | 13.85 | 787 |
| Admin signup overview | 3 | 12.90 | 3 |
| Admin coverage/retention | 14 | 8.22 | 14 |

Execution elapsed includes waits and sums across concurrent calls; 346 seconds does not mean one query blocked the entire database for 346 seconds.

### Highest priority: admin analytics

`src/modules/admin/adminMetricsQueries.js:840` (`loadDauEngagement`, SQL at :850) builds action history across race participation, powerup usage, reward claims, leaderboard views, race creation and completion, with a roughly 60-day comparison history. It dispatches under `dashboard-dau-engagement` at :1105. The full-window statement delta recorded four calls and 346.05 seconds, about 86.5 seconds per call. This is the largest individual application statement by elapsed time.

The plugin also ranks this query first by measured execution CPU: 42.07 seconds across nine complete minute buckets. It reports six calls and 398.65 seconds elapsed in that dataset; this differs from pg_stat_statements accounting/window and should not be conflated with the four-call figure. Error/call-outcome detail was not captured, so the discrepancy is not assigned a cause.

Next investigation: trace repeated dashboard requests and existing refresh/cache behavior, inspect execution plans, then evaluate sharing results and maintaining bounded daily aggregates instead of rebuilding action history repeatedly. No analytics changes were made, and no index benefit is established by this capture alone.

### Other follow-ups

- `src/modules/steps/services/globalStepEventObservability.js:19`: operational counter upserts ran 1,006 times, affecting 2,002 rows, with 96.08 seconds elapsed. These update shared metric rows. Check lock contention and opportunities to batch/coalesce observability counters while preserving required durability; elapsed time alone does not prove CPU consumption or its cause.
- `src/modules/steps/services/scoringInputVersion.js:101`: 387 scoring-version lock/create calls, 44.80 seconds. Compare wait/lock evidence with per-sync work before changing concurrency.
- `src/modules/notifications/jobs/notificationCompletenessReconciler.js:146`: two historical completeness checks, 32.94 seconds, zero repairs. The repeated empty historical check remains an optimization candidate.
- `src/modules/steps/models/stepSample.js:142`: 401 bounded sample reads, 25.70 seconds. This remains a frequent scoring path.

Traffic differed materially: step-sync request inserts rose from 278 to 387; proof reads rose from 461 to 526; admin analytics appeared prominently. These counts are SQL workload proxies, not distinct users or completed jobs.

## Plugin callers and observer overhead

| Caller | Execution CPU s | Planning elapsed s | Execution elapsed s |
|---|---:|---:|---:|
| steps-http-0 | 29.98 | 81.81 | 382.15 |
| steps-resolution-0 | 24.96 | 83.66 | 304.63 |
| steps-http-1 | 29.34 | 74.21 | 313.21 |
| steps-cron-0 | 6.97 | 44.72 | 104.77 |
| bara_readonly_repeat | 6.08 | 2.39 | 72.32 |
| unknown | 0.01 | 0.00 | 0.72 |

Plugin execution CPU is not total host CPU; planning elapsed is not CPU time. Monitoring remains included separately. Full-window plugin polling consumed 58.11 seconds execution elapsed and statement snapshots 24.25 seconds; the nine-minute monitoring caller measured 6.08 seconds execution CPU. Their elapsed times include waits under the busy workload.

## Capture quality

11 statement snapshots, 120 activity samples, 61 host CPU samples, no SQL collector errors. Statistics reset time and deallocation count (178) stayed unchanged. Plugin snapshots were collected beyond the wall-clock ten minutes because each poll waits after reading; only the nine complete buckets inside the SQL window were aggregated once each. Production health returned OK afterward. No production mutations, deployment, configuration changes, cancellation of application queries, or tests.

Raw evidence: `/tmp/bara-db-watch-20260911-ordered/`, including `families.json`, `delta.json`, plugin buckets, host metrics and queue snapshots. Previous comparison window: `/tmp/bara-db-watch-20260911-final/`.
