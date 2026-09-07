# Endpoint optimization audit — September 6, 2026

This audit interprets the [one-hour production measurements](production-traffic-audit-2026-09-06.md) against backend revision `bf3a85621eae6b4479458345c98b5dd1d76270d8` and the current Flutter source. Backend HEAD matches the monitored revision. It is a source/evidence audit, not an implementation or benchmark. Request headers and payloads were not retained, so client-version mix, per-user request duplication, sample batch sizes, and individual 409 causes cannot be reconstructed from this dataset.

## What the numbers mean

- **There is no observed need for more HTTP workers.** The hour averaged 5.45 requests/second, peaked at 629 requests/minute, and used 11.1% average host CPU. Available memory stayed above 5.5 GiB. This establishes headroom for the observed traffic, not maximum capacity.
- **Latency remains worth improving despite low CPU.** Step sync, race list, and home race card each had p95 latency around 735–790 ms and p99 around 1.2–1.5 seconds. Requests can wait on database round trips, locks, or sequential tasks while application CPU is idle.
- **359 seconds for step sync is cumulative elapsed request time across 1,522 requests.** It does not mean one request took six minutes or the CPU was busy for six minutes. The three leading endpoints account for 55.5% of matched upstream time.
- **The intake queue and resolution queue are different.** Admission showed no waiting backlog or rejections. Resolution attempts took 441 ms median / 1,332 ms p95 of core time, while request-to-start was 5,034 ms median / 9,023 ms p95 / 37,044 ms maximum. The five-second median is consistent with the existing five-second coalescing delay. It does not prove every delayed job was intentionally waiting: eligible backlog and priority must be inspected separately.
- **Zero 5xx is reliability evidence, not proof every user flow succeeded.** In particular, 460 claim calls returned 409. Those may include speculative recovery checks, not only post-ad claims.

The top application endpoint counts match their corresponding normalized nginx counts. The shared nginx log lacks hostname attribution, so matching timings remain subject to the original report's limits, especially generic/probe paths.

## Priority 1: remove avoidable race-list reads

**Measured:** `/races` had 1,179 requests, 303 ms mean, 787 ms p95, and 357.4 seconds cumulative upstream time.

**Confirmed code opportunities:**

1. `src/modules/races/routes.js:883` loads a pending offer and passes it to `getRacePayoutDoubleOffer`. In `src/modules/races/queries/getRacePayoutDoubleOffer.js:36`, `pendingOffer || await model.findPending(userId)` repeats that lookup when the supplied result was null. Distinguish “not loaded” from “loaded and absent.” Preserve the first pending lookup because pending offers can add completed races to the response.
2. In the no-pending, preparation-enabled branch, the helper reads the user's identity, database time, and velocity aggregate before checking whether `completed` contains any eligible unseen races (`:69–93`). Check that necessary eligibility condition first. On the no-pending/no-eligible path this can avoid the redundant pending lookup plus three additional query calls. Actual savings depend on how often that branch runs; these are code-level calls, not a measured SQL count.
3. Race membership caching already exists (`src/modules/races/services/raceListCache.js`). It intentionally excludes live/user-bound fields and route-added tournaments, offers, eligibility, and review opportunities. “Cache `/races`” is therefore too vague: optimize the uncached composition and verify fragment hit/miss behavior rather than caching the entire response indiscriminately.

**Confidence:** high that avoidable reads exist; latency reduction is unmeasured. These backend changes can benefit old app versions without changing response shape.

## Priority 2: reduce work inside step transactions

**Measured:** `/steps/sync-v2` had 1,522 requests, 236 ms mean, 735 ms p95, and 359 seconds cumulative upstream time. Across the three step-ingestion contracts, transaction telemetry totals 341 seconds; the sample phase totals 109 seconds, durable enqueue 56 seconds, and summary finalization 51 seconds. Phases can nest or run multiple times; they are not independent CPU costs. The sample phase includes reconciliation and input-bound reads.

**Confirmed code opportunities:**

- **Repeated sorting/serialization:** `src/modules/steps/models/stepSample.js:328–331` rebuilds and sorts `kept.map(normalized)` inside `.every(...)`. When many entries match, the same array is rebuilt for each comparison. Normalize/sort both arrays once, then compare them. This removes avoidable repeated work with the same equality semantics. The size of the production benefit needs batch-size measurements; low host CPU means this should not be sold as the main proven latency cause.
- **Partial-batch no-op writes:** the whole-batch `exactNoop` path already avoids writes. But if one kept sample changes, `replaceSamplesOn` upserts every kept sample and its conflict update is unconditional (`:57–113`, `:357`). A guarded conflict update comparing all persisted fields could avoid rewriting unchanged same-start rows within a mixed batch. Preserve overlap deletion, metadata-only updates, and chronological reconciliation semantics. This can reduce physical writes and trigger invocation; the durable-capture trigger already suppresses unchanged canonical facts, so it would be incorrect to claim that every redundant update currently creates journal entries.
- **Investigate the remaining slow transaction tails:** sample, enqueue, and scoring-state phases sometimes reach multiple seconds. The current capture does not separate SQL execution from row-lock waits within those phases. Examine targeted query plans and lock-wait evidence before changing indexes, queue concurrency, or transaction boundaries. The `(user_id, period_end)` index is already declared in migration `20260814180000_step_samples_user_period_end_index`; do not prescribe it as a missing index without checking the deployed schema and plan.

**Already present:** set-based sample writes, whole-batch no-op suppression, durable enqueue batching/coalescing, and a single canonical intake transaction (`src/modules/steps/services/stepInputIntake.js`). Do not trade away idempotency or atomic step-to-queue ownership merely to shorten HTTP duration.

## Priority 3: investigate the claim/recovery flow

**Measured:** all 460 `/races/results/double-payout/:id/claim` requests returned 409, consuming 47.9 seconds of upstream time. This is a stronger user-experience investigation than a capacity issue.

**What the source explains:**

- `lib/screens/race_results_summary_screen.dart:266` attempts a recovery claim whenever a prepared offer already exists.
- The same `_claimPreparedOffer` retry loop runs for recovery and earned-ad claims: up to five attempts, with a default two-second delay (`:43`, `:443–457`). A pending offer without a verified grant can therefore incur eight seconds of deliberate retry delays, plus request time, before preparation continues. This is a possible flow delay, not an observed per-user timing from the audit.
- The backend takes identity/user/offer locks, locks offer items and participants, and validates the snapshot before checking for an ad grant (`src/modules/races/commands/claimRacePayoutDouble.js:56–186`). An unverified retry can perform substantial work before returning 409.

**Recommended direction:** distinguish a cheap, bounded recovery probe from retrying after an actual earned-ad callback. Investigate the 409 reason distribution and successful server-verification callbacks before diagnosing an ad-provider failure. Consider an inexpensive negative readiness path, but preserve ownership, already-claimed idempotency, forfeiture/error behavior, and full transactional verification before any award. Do not remove verification or change reward amounts, eligibility, or limits.

Frontend improvements require a new iOS and Android build; backend improvements must retain compatibility for frozen clients. The current frontend code explains a plausible source of the traffic, but the hour's logs do not prove every caller used this build or that every 409 was `AD_NOT_VERIFIED`.

## Priority 4: improve home composition selectively

**Measured:** `/home/race-card` had 1,102 requests, 279 ms mean, 790 ms p95, and 307.1 seconds cumulative upstream time.

`src/modules/home/buildHomeRaceCardResponse.js:84–246` already parallelizes work within four successive waves. Much of the event, milestone, inbox, summary, and banner work depends on request/user inputs rather than the completed core card. There may be room to schedule independent tasks earlier under a bounded concurrency budget instead of waiting for each entire wave.

The recorded phase telemetry confirms this assembler was exercised during the hour. Its first/core and second/event waves contain the larger observed phase latencies. The telemetry stores per-minute percentiles, so those cannot be averaged into a true hourly percentile or used to promise a specific saving from overlap.

**Confidence:** source-backed candidate requiring a benchmark, not an automatic improvement. Unbounded `Promise.all` could shift waits into the database pool. Preserve optional-field fallback behavior and authorization/viewer-specific data. Existing lean/snapshot paths and launch batches must be accounted for before proposing another cache or batch layer.

## Priority 5: reduce message refresh work

**Measured:** `/races/:id/messages` was second by volume: 1,657 requests, 65.5 ms mean, 179 ms p95, 108.5 seconds cumulative upstream time.

- **Small confirmed backend opportunity:** `src/modules/social/queries/getRaceMessages.js:252–287` places two awaited cache reads inside the array passed to `Promise.all`. In the cacheable mixed stream, array evaluation awaits the USER read before starting the SYSTEM read. Create both promises before awaiting them. This saves only the overlap available in these two reads, not all message latency.
- **Larger traffic candidate:** `lib/services/race_stream_coordinator.dart:155–230,472–518` refreshes the top timeline on a five-second timer. Lifecycle pause and in-flight suppression already exist. Consider adaptive refresh intervals or conditional/watermark handling for the timeline path, while refreshing promptly on resume, send, and relevant updates. Existing combined-stream conditional behavior should be reused where applicable, rather than inventing duplicate infrastructure.
- Cache hits still require access checks and viewer-specific redaction. Do not remove those checks or serve another viewer's private/team/stealth state. The aggregate counts do not prove duplicate timers or hidden-screen polling, so those should not be presented as diagnosed bugs.

## Lower priority and unresolved attribution

- **Asset manifest:** 1,859 requests but only 7.5 seconds upstream, p95 9 ms, and 0.33 MiB of response bodies. Reducing repeated checks might improve radio/battery use, but this is a poor first target for backend latency.
- **Resolution status polling:** 1,073 calls cost 24.5 seconds. It is not the main processing expense. Do not shorten the queue's five-second coalescing delay blindly: that can increase duplicate work. Conversely, classify the 37-second tail by priority/deferral versus genuinely claimable wait before dismissing it as intended.
- **Cron pool:** 9,434 queued checkouts and a 952 ms maximum wait deserve attribution to individual jobs. There were no pool checkout timeouts. Existing role-level telemetry cannot identify the offending cron, and increasing pool size without checking database capacity may simply move contention downstream.

## Recommended sequence and validation

1. Backend race-offer query cleanup; step comparison cleanup; truly parallel message cache reads.
2. Benchmark partial-batch step write suppression against representative unchanged, partly changed, metadata-only, overlapping hourly/fine-grained, and concurrent sync cases.
3. Separately investigate recovery versus earned-ad claims and improve the retry path while preserving server authority.
4. Benchmark bounded home scheduling and adaptive timeline refresh if the earlier work does not meet latency goals.

For any implementation, write public-path integration/widget regressions first, preserve old-client response contracts, and use a dedicated test database. Compare identical workload mixes before/after: endpoint p95/p99, query calls, rows physically updated, pool/lock waits, and resolution lag. No app/backend behavior, flags, worker capacity, production data, or deployments were changed for this audit.
