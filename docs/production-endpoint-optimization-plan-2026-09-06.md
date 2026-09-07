# Production endpoint optimization plan

Based on the [source audit](production-endpoint-optimization-audit-2026-09-06.md) and [one-hour production measurements](production-traffic-audit-2026-09-06.md).

Status: implementation plan; no implementation or deployment performed. The initial scope is optimization of existing behavior. Potential new conditional-response contracts or polling functionality are deferred until separately specified.

## Objectives and constraints

Reduce unnecessary database work and user-visible latency without changing step totals, race results, access rules, reward eligibility, or existing API responses. Preserve frozen clients and both mobile platforms. Keep exactly two production HTTP workers. Add no release flags or temporary runtime controls. Staging remains stopped unless separately authorized.

Baseline: 19,637 requests/hour; 629/minute peak; no 5xx; host CPU 11.1% average. Step sync, race list, and home card account for 55.5% of matched upstream time. Step admission had no observed backlog. These measurements motivate latency/work reduction, not a worker-capacity increase.

## Batch 0 — establish reproducible validation

**Deliverable:** baseline evidence and a test matrix before business-logic edits.

1. Record backend/frontend revisions and preserve unrelated worktree changes. Compare current code with the audited backend revision before implementing.
2. Inspect existing local performance tooling (`scripts/perf/benchmark.js`, `scripts/capacity.js`, and relevant integration suites) and select the smallest applicable workload. Confirm the resolved database host/name and every secondary connection are dedicated test resources before running fixtures, migrations, tests, or benchmarks. Never run integration tests against production; never use bare `npm test`.
3. Use fixed test users/workloads covering legacy and current capabilities, cold/warm caches, no pending offer, pending/claimed/forfeited offers, no eligible results, dense unchanged/partially changed step batches, and both mixed and single-kind message streams.
4. Record request p50/p95/p99, scoped database query counts, physical row updates, relevant lock/pool waits, and resolution lag. Use the same workload/concurrency and explicit cache state for each comparison. Cost assertions should fail for the existing inefficiency before its fix; retain the failing baseline evidence. Do not manufacture behavior failures for a semantics-preserving optimization.
5. Keep the source-identified optimizations separate from measured runtime savings. A historical production hour is not a controlled before/after benchmark.

## Batch 1 — three small backend-only changes

Implement and review these as separate commits so their effects can be attributed independently.

### 1A. Race-list offer query cleanup

**Files:** backend `src/modules/races/routes.js`, `src/modules/races/queries/getRacePayoutDoubleOffer.js`.

- Distinguish an omitted pending-offer result from an explicitly supplied null result. Reuse the route's completed lookup rather than querying again when no pending offer exists.
- Preserve the initial lookup: its pending items can extend the completed-race list.
- In the no-pending branch, check for eligible unseen completed races before loading identity, database time, and the velocity aggregate.
- Keep existing pending-offer serialization and all legacy economic behavior intact. This is read elimination, not an eligibility or payout change.

**Tests first:** extend public HTTP coverage in `test/integration/race-payout-double.test.js` and applicable race-list suites. Cover absent/present pending offers, supplied-null versus standalone helper callers, unseen/seen results, and old/new capabilities. Use scoped SQL observation to demonstrate the redundant pending read and unnecessary no-eligible reads before fixing them.

**Acceptance:** same successful response bodies and supported failure behavior; one pending lookup instead of two on the applicable path; no identity/time/velocity query calls when an absent pending offer and empty eligible set already determine the result.

### 1B. Step sample comparison cleanup

**File:** backend `src/modules/steps/models/stepSample.js`.

- Normalize and sort incoming/stored comparison arrays once each, then compare.
- Preserve exact equality and existing overlap/coarse-versus-fine rules. Do not combine this commit with persistence changes.

**Validation first:** run reconciliation HTTP cases in `test/integration/five-minute-step-samples.test.js`, `step-samples-source-validation.test.js`, and relevant legacy intake suites. Establish a counted-work or reproducible dense-batch performance regression for repeated normalization/sorting, using the pure-algorithm test exception if it cannot be expressed reliably through HTTP. Avoid wall-clock assertions in ordinary integration tests.

**Acceptance:** identical persisted samples, metadata, totals, and queue decisions; incoming comparison-array preparation no longer repeats for each matching stored row. Report the measured performance effect, even if small.

### 1C. Concurrent message cache reads

**File:** backend `src/modules/social/queries/getRaceMessages.js`.

- Construct USER and SYSTEM cache-read promises before awaiting either; resolve them together.
- Preserve access checks before data reads, viewer-specific redaction, TEAM isolation, ordering, pagination, and single-kind/non-cacheable branches.

**Tests first:** public message endpoint regressions for mixed/single-kind pages, legacy/timeline variants, private/team access, and stealth redaction. Establish overlapping-read evidence using controlled loader scheduling in the existing dependency-injection test surface, alongside real HTTP/database contract tests. A concurrency-only test does not substitute for public-path coverage.

**Acceptance:** the two eligible independent cache loads overlap; response/error contracts remain correct; no extra work is introduced for a single-kind request.

**Batch 1 exit:** appropriate backend unit/integration checks pass; code-reviewer review completed; per-commit before/after evidence documented. No migration or app release is expected. Do not infer production deployment authorization from implementation approval.

## Batch 2 — suppress unchanged rows in partly changed step uploads

**File:** backend `src/modules/steps/models/stepSample.js`, specifically `replaceSamplesOn`.

- Add an equality guard to the conflict-update path so an unchanged same-start sample is not physically updated when another row in the upload changes.
- Compare every persisted update field, including nullable source/device fields and metadata. A metadata-only change still must be stored.
- Preserve insertion, removal of genuinely replaced overlapping rows, user-level serialization, idempotency, generation decisions, and atomic durable enqueue.
- Keep the durable-capture journal behavior correct. Its trigger already suppresses unchanged canonical facts; expected savings are physical row updates and trigger work, not an assumed one-journal-entry saving per skipped row.

**Tests first:** real HTTP uploads against the dedicated test database. Use test-only update observation to show that one changed row currently causes updates to unchanged siblings. Cover fully unchanged, one changed, all changed, metadata-only, null transitions, coarse/fine overlaps, overlapping concurrent requests, and idempotency replay. Retain the source data and durable ownership invariants.

**Acceptance:** unchanged same-start rows receive no physical update; changed rows and required overlap deletes remain correct; integration suites pass; observed write reduction matches the fixture. Re-run step latency/lock/queue benchmarks before combining with any other step optimization.

**Release:** separate backend commit/review and deploy candidate from Batch 1 because this changes the physical write path. No schema migration is expected; any newly discovered schema need must be planned before implementation.

## Batch 3 — ad-claim recovery, separately scoped

Treat this as a user-flow/correctness investigation, not proof of 460 failed ads.

### 3A. Establish the cause

- Inspect existing aggregate endpoint reason codes and server-verification evidence; distinguish recovery probes from claims after an earned-ad callback where the available data permits it.
- Reproduce prepared-offer reopening, no grant, delayed grant, already-claimed offer, forfeiture, and account/session changes locally.
- Confirm whether the five-attempt/two-second loop blocks preparation in the affected path. Record actual state transitions and timing.

### 3B. Implement only after the behavior is pinned down

**Frontend:** `lib/screens/race_results_summary_screen.dart`; **backend, if justified:** `src/modules/races/commands/claimRacePayoutDouble.js`.

- Proposed default: make speculative recovery a single bounded claim probe; on `AD_NOT_VERIFIED`, continue preparation rather than running the full retry loop. Retain bounded retry behavior after an actual earned callback.
- Recheck recovery where necessary immediately before presenting another ad so a grant that arrived late can be consumed without an unnecessary new presentation. Specify and test this race before coding; do not infer an earned reward from a local boolean alone.
- Consider a cheaper backend negative-readiness path only if it preserves ownership checks, already-claimed idempotency, forfeiture/error precedence, and full authoritative transaction checks before an award. If that equivalence is difficult, keep the backend claim ordering and ship only the verified frontend improvement.
- Preserve reward amounts, eligibility, limits, and verification authority. Add no new endpoint or response field by default. If a readiness contract becomes necessary, write a separate additive API specification first.

**Tests first:** pump the real results screen in `test/race_payout_double_results_test.dart` and relevant results-screen suites. Cover immediate/delayed grants, repeated taps, reopen, already claimed, dismissal, disposal, logout/user switch, network failure, and stale callbacks. Retain backend replay/concurrent-claim and unauthorized-access regressions in `test/integration/race-payout-double.test.js`.

**Acceptance:** no multi-attempt delay for a speculative no-grant recovery; successful late-grant recovery and earned-ad claims still work; no duplicate award, unauthorized claim, stale-user mutation, or changed legacy contract. Do not pursue a lower 409 count by weakening verification.

**Release:** backend first if changed; then matching iOS and Android app builds. Run `flutter analyze`, relevant screen tests, and required platform builds. New frontend behavior reaches users only after updating; old clients must continue working. Existing layout is retained; any visible placement change requires the UI-test-planner checklist and mirrored-screen review.

## Batch 4 — benchmark home scheduling; defer polling changes

Only after the earlier batches have measurable results:

- Audit each home assembler branch for actual dependencies and side effects. Prototype earlier scheduling of independent reads using a bounded work queue, initially preserving the existing maximum of three database-backed branch tasks per request. Avoid replacing all four waves with unbounded `Promise.all`.
- Preserve authorization, viewer/capability separation, required-core failure, optional-field fallbacks, and missing-field handling. Compare warm/cold cache and concurrent request workloads; retain only reproducible latency gains without increased pool waits, errors, or resolution lag.
- Investigate timeline conditional reads/adaptive intervals only if remaining polling work justifies it. Existing foreground pause and in-flight suppression already exist. Specify freshness expectations, resume/send refresh, and compatibility before changing the five-second schedule. New conditional contracts or functionality require their own feature plan.
- Attribute cron pool contention to particular jobs before changing cron concurrency or pool sizes. Do not increase database connections or remove the queue's coalescing delay based on the hourly totals alone.

## Release and post-release verification

For each deployable batch:

1. Complete test-first evidence, focused checks, required repository checks, and code-reviewer review. Preserve all existing assertions. Frontend changes require clean `flutter analyze`, relevant real-screen tests, and both platforms accounted for.
2. Prepare a concrete diff, measured effects, compatibility statement, and rollback procedure. No flags, worker-count changes, or staging startup are part of this plan.
3. Obtain explicit in-the-moment production deployment authorization only when that candidate is ready. Backend before app. App upload/release permissions remain separate.
4. Use the same lightweight read-only audit after an authorized deployment, covering all HTTP workers and both queues. Compare traffic mix, cache state, and client capabilities; do not treat two different production hours as a controlled experiment.
5. Check endpoint p95/p99, SQL/write reductions, 5xx and business failures, pool waits, queue age/failures, and reward recovery outcomes. Roll back a batch on confirmed correctness regression; report performance regressions rather than masking them with capacity changes.

Expected first deliverable: Batch 1's three reviewed backend commits and a before/after evidence sheet. Larger latency or write-volume percentage improvements are not promised before benchmarking.
