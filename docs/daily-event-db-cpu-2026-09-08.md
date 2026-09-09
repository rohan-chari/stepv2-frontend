# Daily event database CPU investigation — September 8, 2026

Read-only production investigation of backend `7e27dc1`, starting 00:52 UTC September 9 (20:52 EDT September 8). No production data/configuration changes, deployments, restarts, cancellations, or statistics resets. Two HTTP workers, cron and resolution workers online; staging stopped. Database remains one vCPU / 2 GB, PostgreSQL 18.6.

## Finding

The event demonstrably caused a race-resolution burst at 20:23–20:24 EDT, followed by heavier HTTP/step traffic. This supports it as a contributor to the screenshot's rise, but does not prove that every spike or the entire near-100% peak came from event work. Baseline CPU was already approximately 50–65% in the supplied screenshot, and an earlier peak occurred around 20:05 before this boundary.

Exact entitlement window: 2026-09-09 00:23–00:53 UTC, or September 8 20:23–20:53 EDT. 520 entitlements processed between 00:23:01.023 and 00:23:29.766: 415 ACTIVATED_ON_TIME and 105 NO_ACTIVE_RACES. Timestamp-without-time-zone columns were read as text to avoid the diagnostic Node client's host-timezone conversion.

## Reconstructed timeline

Retained structured logs from the current two HTTP workers and resolution process:

| Eastern minute | HTTP requests | Step intake requests (included) | Resolution attempts | Attempts including event boundary | Maximum resolution queue lag |
|---|---:|---:|---:|---:|---:|
| 20:20 | 339 | 28 | 46 | 0 | 6.7 s |
| 20:21 | 716 | 61 | 79 | 0 | 28.1 s |
| 20:22 | 459 | 35 | 60 | 0 | 12.8 s |
| 20:23 | 514 | 59 | 77 | 75 | 57.5 s |
| 20:24 | 285 | 31 | 95 | 51 | 61.8 s |
| 20:25 | 766 | 46 | 71 | 0 | 29.4 s |
| 20:26 | 975 | 71 | 70 | 0 | 47.8 s |
| 20:27 | 208 | 12 | 40 | 0 | 23.6 s |
| 20:28 | 1,397 | 95 | 81 | 0 | 24.5 s |

The 126 boundary-tagged attempts map to 117 distinct races. Nine races ran twice. Mixed reason sets include step changes, so repeats are not automatically redundant. 101 boundary attempts changed zero participant rows; activation can legitimately change dependencies, snapshots, or attribution without changing current totals. Do not suppress these jobs simply because changedRows is zero.

Aggregate logged core elapsed time rose from 21.5 seconds at 20:22 to 106.2 and 102.8 seconds at 20:23 and 20:24. Concurrent worker elapsed time is not database CPU. HTTP telemetry shows no server 5xx for 20:18–20:32 inclusive. Queue delay nevertheless affected freshness. The graph and log minute boundaries should not be treated as identical sampling intervals.

## Fresh database measurements and limitations

`pg_stat_monitor` is installed with planning tracking enabled, 60-second buckets and ten buckets retained. Captured buckets cover 00:44–00:53 UTC; completed buckets cover 00:44–00:52 inclusive (nine minutes). The 00:23–00:28 query-level history had already expired. `pg_stat_statements` is cumulative and cannot reconstruct that interval without a before snapshot. No claim of exact historical per-query CPU attribution is made.

The completed monitor buckets report 128,820 calls, 316.00 s execution elapsed, 203.21 s planning elapsed, and 42.47 s query CPU user+system. These different measures are not additive CPU percentages. Planning elapsed is substantial and deserves direct measurement in a local benchmark; query CPU counters alone do not account for total managed-host CPU, planning, monitoring overhead, PgBouncer, and maintenance. See [Percona column definitions](https://docs.percona.com/pg-stat-monitor/reference.html).

Five direct authenticated DigitalOcean managed DB metrics samples at 00:53:07–00:55:07 UTC averaged 76.41% non-idle: user 46.14%, system 23.65%, IRQ/softirq 4.38%, steal 1.63%, I/O wait 0.60%. This is an event-END window, not the historical start peak or a matched quiet baseline. Disk wait was small in this sample. The 70% idle target is not met.

Fresh unfiltered pg_stat_statements delta, 00:53:05.217–00:54:08.582 UTC: 12,690 calls (200.3/s), 29.68 s aggregate execution elapsed, 755,015 shared-buffer hits and 4,917 reads. Reset timestamp and deallocation counter unchanged. The diagnostic monitor read and initial statement snapshot account for about 2.06 s of the recorded execution; monitoring was not free. End-of-event work included 140 summary-work inserts and 19 durable-capture compaction checks. These totals include background work and must not be represented as per-HTTP-request query counts.

## Prioritized improvements

### 1. Reduce repeated planning in stable worker queries

Completed nine-minute monitor window:

| Query family | Calls | Planning elapsed | Execution elapsed |
|---|---:|---:|---:|
| Placement transition claim | 1,230 | 9.73 s | 0.99 s |
| Resolution claim | 1,045 | 8.95 s | 2.39 s |
| Batched active-event lookup | 374 | 8.87 s | 1.87 s |
| Post-task claim | 805 | 5.61 s | 2.24 s |
| Placement next-due lookup | 681 | 5.29 s | 0.25 s |

These five account for 38.45 s of planning elapsed. Existing named prepared reads show much smaller planning totals, but this is not a controlled causal comparison. Benchmark bounded named statement reuse for the above fixed SQL through local PgBouncer, and reduce empty claim attempts using existing due-time/wakeup mechanisms where possible. Preserve SKIP LOCKED, lease recovery, fairness and prompt wakeup. Test generic/custom-plan sensitivity across sparse and busy queues; do not blindly name every Prisma query or assume saved planning elapsed equals CPU saved. Existing prepared support is already enabled; no new release flag is needed.

### 2. Bound notification completeness repair scanning

`notificationCompletenessReconciler.js` runs every five minutes (sooner on a full page). Two repair statements executed twice each in the retained window:

- Missing materialization repair: 3.35 s execution, 190,214 buffer hits + 3,141 reads.
- Missing device snapshot repair: 7.08 s execution, 108,975 hits + 5,696 reads.

Their combined query CPU counter was 2.24 s. This is a concrete periodic cost, not evidence that it caused the earlier 20:27 peak. Candidate LIMIT 500 bounds output/updates, but the anti-joins can still inspect a large history to find no missing rows. The first query also holds the notification admission lock during its scan.

Benchmark candidate SELECTs against realistic completed-history growth on a dedicated test database. Prefer indexed outstanding-repair candidates or a durable bounded cursor that eventually covers all historical gaps. Preserve crash repair, deduplication, receipt invariants and late recovery; do not simply add a recent-date cutoff that abandons old gaps. Verify indexes using plans before adding write overhead. Production mutation EXPLAIN ANALYZE was not run.

### 3. Reduce race-input reloads and boundary fan-out work

The boundary code already uses batches of at most 100 entitlements, bulk impact insertion, set-based write fences and enqueueMany. It is not a naive per-user enqueue loop. It intentionally rechecks membership under locks; removing that read without another concurrency guarantee is unsafe.

The retained monitor window still shows 874 race/event fingerprint reads (434,691 buffer hits), 852 race reads and 415 bounded step-range reads. Fresh event-end stats show 104 step-range reads consuming 2.88 s execution elapsed. Investigate sharing an immutable, generation-validated scoring input bundle between resolution and snapshot work, and merging eligible boundary scopes across microbatches. Validate source-version fences, race joins/leaves, simultaneous step sync, timezone differences and end-of-event settlement. The nine repeated start-boundary races imply at most nine attempts saved in that observed start window if all proved redundant; do not promise hundreds of eliminated jobs.

### 4. Preserve evidence before the next event

Export completed pg_stat_monitor buckets and direct CPU metrics once per minute to bounded, rotated telemetry outside the database. Store normalized query identifiers and aggregates, not literal user-bearing SQL. The current monitor has normalized_query=off, making raw exported query text unsuitable for a committed artifact. Capture at least 10 minutes before, the 30-minute event, and 10 minutes after. Compare matched HTTP/step counts, SQL calls, planning time, buffer accesses, WAL, queue lag, errors, and direct managed CPU. This is a proposed operational improvement, not an installed collector.

## Validation and scope

Investigation only; application code is unchanged and no tests/builds are claimed. No game rules, event duration, scoring, client API or platform behavior changed. Proposed implementation should preserve old-client responses for iOS and Android, use integration tests on a dedicated local/test database, and receive code review before deployment. No production deployment is authorized by this investigation.
