# Global-event enrollment query optimization

Status: implemented locally and code-reviewed after user approval. Before/after integration evidence recorded; three existing integration and three existing unit failures also reproduce on unchanged SQL. Deployed with explicit approval as backend `7e4132c`; five-minute production before/after measurements recorded. Natural nonempty-cohort verification remains pending.

## Summary and user story

As an active racer, I receive the same scheduled global-event entitlement and subsequent event behavior while the scheduler spends less database work discovering whom to enroll.

Optimize only the candidate SELECT inside `materializeEntitlementsForActiveRacers`. Select distinct active racers before checking existing event entitlements. Materialize this active-user CTE to retain the demonstrated benefit as historical membership grows. Keep the existing scheduler, pagination, timezone eligibility, transactional writes, deduplication and client contracts.

This is the first, focused implementation from the [workload audit](architecture-workload-audit-2026-09-08.md), not approval to implement the other audit findings.

## Evidence and success definition

At audit time production was backend `3b241ff`; local main was `ba6cfc3` and included unrelated billing changes. Relevant steps code matched those revisions. Reconfirm deployed HEAD and the changed-file diff at implementation and release time; never deploy unrelated main changes with this optimization.

Two approximately one-minute production samples each contained five enrollment candidate queries returning zero rows, with 684 ms and 276 ms aggregate execution. A separate read-only probe touched 30,296 shared buffers and scanned 28,992 qualifying historical memberships to find zero candidates. Selecting active users first touched 2,338 buffers and considered 2,354 active memberships / 907 distinct active users. Execution was 426.9 ms versus 16.3 ms in those two non-simultaneous probes.

These probes support the query-shape hypothesis, not a guaranteed speedup. They used LIMIT 100 and a null cursor; the real scheduler uses pages of 500. Validation must include 500, subsequent pages, nonempty results and large active populations. SQL count remains one candidate SELECT per page; the intended saving is rows visited/buffer work, not fewer page queries or fewer entitlement writes. Do not claim this change alone establishes the 70% idle database CPU target.

## Scope and non-goals

In scope: replace the one existing candidate SELECT, add real workflow and query-plan regression coverage, document measured before/after results, and verify compatibility.

Out of scope: new queues, persistent cursors, active-user caches or tables, sharing pages across parent events, new indexes, schema changes, enrollment write batching changes, scheduler frequency/budget changes, operational-counter changes, scoring/odds changes, leaderboard and notification optimizations, frontend sync changes, release flags, capacity changes and deployment without fresh authorization.

## Current implementation and ownership

Backend paths below are relative to the backend repository:

| Path / location at audit revision | Responsibility |
| --- | --- |
| `src/modules/steps/services/globalStepEventEntitlement.js:424` | Existing materializer; candidate SQL begins near line 445, preparation near 470, batched transaction near 495, page result near 553. Only the candidate SQL changes. |
| `src/modules/steps/jobs/globalStepEventScheduler.js:54` | `buildLocalGlobalStepEventTick`; resets cursor for each parent per tick, invokes 500-user pages under the shared five-second materialization budget. |
| `src/modules/steps/index.js` | Public module exports include scheduler builders; use this scheduled-work entry in new integration coverage. |
| `src/modules/steps/services/globalEventEnrollment.js` | Existing start/join enrollment lock and transaction protocol; do not modify. |
| `prisma/schema.prisma` and existing migrations | Existing race-status, membership and unique event/user indexes; verify against the target schema without introducing a migration. |
| `test/integration/local-global-step-event-entitlements.test.js` | Existing HTTP race progress, enrollment, concurrent late-join and boundary behavior coverage. |
| `test/integration/global-event-reliability.test.js` | Existing generation readiness and durable scheduled-event coverage. Preserve assertions. |
| `test/integration/global-event-enrollment-query.test.js` (new) | Scheduler-path functional and measured-query regression tests. |
| `scripts/perf/global-event-enrollment-query.js` (new, only if needed for repeatable plans) | Dedicated local/test fixture and baseline-vs-candidate read-plan benchmark; no production defaults or writes. |

Frontend repository owns this specification and the audit. Backend developer owns implementation, tests and backend evidence documentation. Frontend developer's later participation is compatibility verification and `flutter analyze`; there is no mobile code task.

## Exact proposed SELECT

Keep the existing parameter order and returned columns:

```sql
WITH active_users AS MATERIALIZED (
  SELECT DISTINCT participant.user_id
    FROM races race
    JOIN race_participants participant ON participant.race_id = race.id
   WHERE race.status = 'active'
     AND participant.status = 'accepted'
     AND participant.forfeited_at IS NULL
     AND participant.finished_at IS NULL
     AND ($3::text IS NULL OR participant.user_id > $3)
), enrollment_candidates AS MATERIALIZED (
  SELECT active.user_id
    FROM active_users active
   WHERE NOT EXISTS (
     SELECT 1 FROM global_step_event_entitlements entitlement
      WHERE entitlement.event_id = $1
        AND entitlement.user_id = active.user_id
   )
   ORDER BY active.user_id
   LIMIT $2
)
SELECT person.id, person.timezone,
       person.global_event_timezone AS "globalEventTimezone"
  FROM enrollment_candidates candidate
  JOIN users person ON person.id = candidate.user_id
 ORDER BY person.id
```

`$1 = event.id`, `$2 = batchSize`, `$3 = afterUserId`. Continue binding parameters through the existing Prisma raw-query call; no string interpolation of values. Use the database's existing text ordering/collation, not JavaScript sorting or UUID casts. User IDs are text.

The materialized intermediate contains distinct qualifying active users after the cursor, so it can still grow with the active population. The measured NOT MATERIALIZED alternative restored the pathological historical scan on the 300,000-membership fixture and failed all four history-growth combinations; retain MATERIALIZED. Only the returned page is bounded to batchSize. This design reduces historical scan exposure; it is not a constant-work guarantee or a new active-membership index. SQL join order and materialization do not force a physical join/access plan. If representative plans still scan history or large-active tests regress materially, revise the query/spec before implementation approval is treated as satisfied; do not silently add hints, indexes, caches or scheduler changes.

Do not put LIMIT inside `active_users`: already-enrolled users could consume that limit, produce a short page and falsely signal exhaustion. Keep distinct user selection before the candidate limit so multiple memberships cannot consume page slots.

## Behavioral invariants

1. A candidate has at least one active race with accepted, unfinished, unforfeited membership and no entitlement for this event. Completed/pending/cancelled races and other membership states cannot independently qualify a user. Multiple eligible races yield one candidate.
2. Existing entitlements exclude users irrespective of entitlement lifecycle state. Entitlements for another event do not exclude them. Preserve the exact `NOT EXISTS` predicate.
3. The cursor is exclusive, ordered on text user ID, and applied before the final candidate limit. Null cursor starts at the beginning. Do not persist a cursor between ticks; newly eligible users behind an earlier cursor remain discoverable on the next tick.
4. Timezone selection and local-window preparation remain in the existing JavaScript path. A candidate whose local start is at/before `now` is still counted as a candidate and advances the cursor even though preparation creates nothing. `created = 0` is not an exhaustion signal. Do not move timezone filtering into SQL.
5. Internal return shapes remain: integer created count when `returnPage=false`; otherwise `{ candidates, created, nextCursor, exhausted }`, with `nextCursor` from the last candidate or incoming cursor and `exhausted = candidates < batchSize`. Exactly full pages require a following query to establish exhaustion. Non-local-event short circuit remains unchanged.
6. Candidate eligibility is evaluated in the SELECT's existing statement snapshot. This change does not promise stronger selection/write atomicity. Preserve the existing insert transaction and event/user uniqueness when a race ends, user leaves, timezone changes or another producer enrolls the user between selection and insertion. A requirement to change those established semantics is a separate correctness task.
7. Keep scheduled-event generation readiness checks, immutable event/audience construction, source receipts, existing counter behavior, transaction timeouts, retry/error behavior and write order. No new locks and no lock-order changes. Failed batched writes must still roll back with their event obligations.
8. Each page has one candidate SELECT and returns only the three existing user columns. No per-user SQL, extra race update, queue job, Redis call or new transaction is introduced.

## API, data model and frontend contract

No endpoint is added or changed. Requests, response JSON, headers, status codes and error formats remain exactly those of the existing backend. There is no new JSON contract or required client parameter. The page result above is an internal service contract, not a mobile response.

No schema migration, backfill, index, data rewrite or new stored aggregate. Postgres remains the authoritative store for membership, entitlement and durable event data. No Redis surface or invalidation protocol is introduced.

No Flutter screens, widgets, loading/empty/error states, demo fixtures or tutorial placement change. Existing iOS and Android releases receive the same event behavior. Neither platform acquires a dependency on a new endpoint/field or new parsing logic; an older backend remains usable by current clients. No app build/version bump, content `testOnly` change or new feature flag is needed. Manual UI-placement plan is not applicable.

## Tests-first implementation path

### A. Establish safe baseline and fixtures

1. Read both repository contracts and current release runbook. Preserve existing working changes. Compare the implementation branch with current production and isolate this optimization from unreleased features.
2. Before any test/benchmark execution, parse and verify `DATABASE_URL` identifies a disposable local Postgres database ending in `_test`; reject non-local hosts and production aliases. Do not print credentials. Use the same dedicated test database for setup, EXPLAIN and teardown. Match production's PostgreSQL 18 major for performance acceptance; another supported version may supplement functional coverage. Use isolated local Redis db15 only if the existing harness requires it; also cover Redis unset.
3. Build bounded synthetic fixtures using existing test setup facilities: approximately 30,000 historical accepted memberships plus roughly 2,500 active memberships / 1,000 distinct active users; duplicate memberships across races; events with zero, sparse and all missing entitlements. A second scale case holds active membership fixed while growing history tenfold. A large-active case exercises at least 10,000 active users. Primary historical-heavy topology must reflect the audit: approximately 160 active and 600 completed races, with about 2,500 active memberships and 30,000 historical memberships. Retain the three-active/300-completed topology as an explicitly efficient-baseline non-regression control; the 75% improvement gate applies to the audit-shaped primary case, not a control that already avoids historical work. Fixed fixture dimensions must be logged; these are benchmark populations, not gameplay limits.

### B. Add failing performance coverage and passing behavior baselines

4. Exercise the real scheduled entry via `buildLocalGlobalStepEventTick` exported by `src/modules/steps`. Invoke the tick directly under a fixed clock because cron work has no HTTP trigger; do not call/import the internal materializer to shortcut the path, and do not invent an admin endpoint. Leave materialization, models, transactions, event append and generation-readiness logic real. Fixture the actual parent/generation state so unrelated parent creation does not dominate the measured section. Use test logging/clock control only, not fake business collaborators. The injected `now` controls business time but not the scheduler's `Date.now()` budget: control both clocks for deterministic functional pagination. Keep elapsed time real for budget and whole-tick performance measurements.
5. Enable the existing `PRISMA_QUERY_EVENTS_ENABLED=true` in the test process before loading `src/db`; never enable it in production or introduce a new runtime switch. Observe candidate SQL and bound parameters emitted during the real tick. Outside the timed workflow, execute SELECT-only `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` for those captured statements against the test fixtures. The real tick changes enrollment state: reset/reseed each benchmark case to its pre-tick state after capturing SQL, before baseline/candidate plan comparisons, so a sparse/full fixture does not silently become all-enrolled. SELECT-only comparisons can then share a stable fixture snapshot. Keep the original SQL in the benchmark/test baseline only; application code has one permanent path. Compare exact ordered rows for null/non-null cursors and page sizes 100 and 500 against the baseline under a stable fixture snapshot. This supplementary structural/performance check cannot be established through HTTP response assertions alone.
6. Before editing production SQL, record at least one red query-work regression on the historical-heavy empty-page fixture, with functional expectations already passing. Fix the plan/row budget in the test before implementation based on the captured baseline; target at least 75% lower total shared-buffer accesses for the candidate than baseline on this fixture. Measure query root buffer hits + reads, never sum nested plan buffers. If the baseline already meets a chosen absolute budget on PostgreSQL 18, choose an evidenced discriminating budget or report the hypothesis unproven; do not manufacture a failure or substitute a wall-clock-only assertion.
7. New workflow cases must cover: all membership/race status exclusions; duplicate memberships; unrelated-event entitlements; none/some/all users enrolled; more than 500 eligible users across pages; exactly 500 eligible users and terminal empty page; full candidate pages with zero created due to elapsed local windows followed by later eligible users; fallback/valid timezones and exact start boundary; repeated tick idempotency; another producer inserting the same entitlement; and a new low-sorting user becoming eligible between ticks. Assert durable entitlements/event obligations and the API response a client sees where applicable.
8. Retain/run real HTTP concurrent start/join vs boundary coverage and generation-ready/not-ready scheduled-event tests. New HTTP compatibility cases use the established race-progress contract and capability fixtures for legacy and current clients, asserting identical baseline/candidate response shape and event visibility after the same scheduler lifecycle. Existing tests that directly call internals are preserved; new tests do not copy that shortcut.

### C. Implement and validate

9. Replace only the candidate SELECT at the existing seam; add a concise comment explaining active-user distinct materialization and why LIMIT follows the entitlement anti-join. Keep API names, parameters, scalar preparation and all downstream writes unchanged.
10. Run the new test suite and existing local-event entitlement/reliability integration suites. The current `npm run test:integration` hardcodes a local database and full-suite glob; it does not offer reliable file selection. For focused runs, first prepare the verified dedicated test database with the same migrations and identity-search indexes, then use `node --test --test-concurrency=1 --test-force-exit test/integration/global-event-enrollment-query.test.js` with the required test-only environment from the existing harness, and the analogous commands for the two existing suites. Use `npm run test:integration` for the full suite when applicable. Diagnose failures one suite at a time; never weaken assertions or use bare `npm test`. Add the relevant scheduler/model unit suites only where they cover internal page-contract details that the public job path cannot directly expose.
11. Benchmark baseline and candidate in alternating order, at least five measured runs after warmup per fixture/page/cursor combination. Record planning/execution distributions, buffer hits/reads, rows visited, temporary blocks, candidate rows, query counts and whole-tick behavior. Use the same indexes, statistics and fixture data. Run ANALYZE only on the dedicated test fixture. Report a whole-tick scheduler-budget overrun if a single SELECT exceeds the budget: the loop's five-second check does not interrupt a running SELECT.
12. Require functional parity for every fixture, at least 75% median buffer reduction in the historical-heavy empty-page case, and no more than 20% median buffer-work regression on representative sparse/full/large-active pages relative to baseline. These are engineering acceptance gates, not observed results. Record timing regressions and any newly introduced temporary-file spills for explicit review even if buffer gates pass; materialization must not exchange buffer savings for unexamined temporary I/O. If gates fail, revise design with evidence instead of loosening them silently. For large populations, compare eventual per-parent entitlement/obligation counts and ticks-to-convergence as well as first-tick duration: the existing shared five-second materialization budget can split a cohort across ticks, so different completed work cannot be labeled a speedup.
13. Frontend verifier runs `flutter analyze` and documents why the query-only backend change affects both platforms equally. Platform builds are not required for this change because no mobile/build/dependency artifact changes. Run required code-reviewer review after implementation, with query semantics, test independence and release isolation in scope.

## Release and rollback

Implementation approval authorizes code/tests, not production deployment. Once the reviewed change is concrete and verified, obtain fresh deployment authorization under the backend contract. Staging must remain stopped unless explicitly authorized in the moment.

Deploy the isolated backend change through the current runbook, preserving exactly two production HTTP workers and existing dedicated worker topology. No migration, environment change, pool change, PgBouncer setting or app upload is part of this release. Old/new backend workers can overlap safely because both read and write the same contracts.

Before and after an authorized deployment, collect comparable 5–10 minute read-only windows containing scheduler ticks: candidate-query calls/rows/latency, scheduler failures, entitlement/event creation counts and due-age, managed database CPU components and traffic/event-boundary context. Confirm a naturally eligible cohort progresses without synthetic production writes. If no new cohort occurs, mark functional production confirmation pending and revisit a natural future event; health checks alone are not proof.

Use unfiltered `pg_stat_statements` snapshots, matching database/user/query/toplevel and unchanged `stats_since`, and report resets/evictions. Query execution is not CPU. Do not promise 70% idle from this single optimization. Any production SELECT plan probe uses a short read-only transaction and statement timeout; no EXPLAIN ANALYZE of mutations.

Rollback means reverting this isolated SQL change and redeploying the previous verified backend artifact under the same deployment-authorization policy. Already-created entitlements/events remain valid; no compensating data deletion or migration is required. Trigger rollback/review for new SQL errors, skipped/duplicate obligations, scheduler timeouts or a demonstrated workload regression. Do not introduce a rollback flag.

## Acceptance criteria / definition of done

- Candidate eligibility, ordering, pagination, time-window behavior and durable obligations match baseline, including legacy/current client HTTP behavior.
- One candidate SELECT per page, existing bounded response and write path, no new schema/index/cache/flag/worker/API/mobile changes.
- Tests existed before SQL implementation; the performance regression failed for the intended work-budget reason and passes after the change. All relevant integration tests pass without weakened assertions; any pre-existing failure is explicitly reported and prevents an unqualified done claim.
- PostgreSQL 18 representative plan comparisons meet the stated gates; evidence distinguishes buffer work, execution, planning and host CPU.
- Flutter analysis is clean, both platforms accounted for and required implementation review completed.
- Production deployment is separate and authorized; post-deploy evidence and any still-pending natural-cohort verification are reported plainly.

## Open questions

No product decisions remain for this focused query-only change. Exact baseline query-work budgets and release HEAD are implementation-time measurements, not permission to expand scope. If the chosen SQL cannot meet performance gates, bring back an amended design.

## Revision log

- Draft: fixed scope to audit finding 1's query shape, leaving durable enrollment candidates and cross-event sharing for later work.
- Gap pass 1: preserved cursor progression for zero-created/full candidate pages, kept candidate selection's existing snapshot semantics, and made explicit that active-user materialization is population-sized even though results are paginated.
- Gap pass 2: corrected audit LIMIT 100 vs scheduler 500 coverage; specified public scheduled entry plus real HTTP client assertions, PostgreSQL 18 performance acceptance, baseline-failing query-work evidence, and isolation from unreleased billing changes. Clarified no mobile/UI work or new flag.
- Architect review: APPROVE, no required changes. Incorporated all three suggestions: reseed pre-tick state before plan comparisons, control business and scheduler-budget clocks separately in functional tests, and require review of new temporary-file spills. Final harness check documented existing query-event opt-in and focused test-run commands.

- Implementation approval: user approved and explicitly required before/after database statistics and performance measured with integration tests. Retain matched-fixture baseline and after artifacts, including full scheduled workflow timing; production comparisons remain separate from synthetic test evidence.
- Measurement refinement: PostgreSQL 18 showed the three-active-race control already has an efficient baseline; retain it as a non-regression case and freeze the primary historical-work budget against the audit-shaped 160-active/600-completed topology. Architect reviewed retained dense-page timing overhead (about 1.7 ms worst median at page 500 in the initial matrix), no observed temporary spills and no buffer regressions; original SELECT remains acceptable conditional on real before/after workflow parity and convergence. No SQL-scope or performance gate relaxation.
- Alternative review: NOT MATERIALIZED was provisionally approved after quick probes, then rejected by the full matrix: it failed all four 10×-history buffer gates. Active-race-ID and LATERAL alternatives also failed required cases. These results are retained in implementation evidence.
- Final architecture decision: APPROVE original MATERIALIZED query, the only candidate passing all 32 original buffer gates. Current-scale full and recurring-empty checks improve; the 10,000-user full-page stress case remains slower (5.542 → 15.951 ms in the retained paired-plan matrix). Three real-budget workflow pairs did not reproduce an additional tick—all six needed two ticks—but candidate first-tick throughput was lower in two pairs. This tradeoff is accepted explicitly, not described as universally faster or proof of production CPU savings. Restore original exact SQL and validate the final selected source; no further variants or scope expansion.

## Implementation evidence

See the backend [measured before/after report](../../stepv2-backend/docs/global-event-enrollment-query-performance.md) and its source-identified JSON artifacts. The selected original MATERIALIZED query passes all 32 buffer gates; representative recurring-empty buffer accesses fall from 35,097 to 748. Dense 10,000-user pages remain slower and that tradeoff was explicitly accepted in the final architecture review. Final code review reported no blockers. Existing protected-suite failures are documented as baseline failures, not hidden or repaired by unrelated changes; the broader validation is not fully green.
- Final validation: new enrollment integration 8/8 and performance matrix 32/32 pass. Combined targeted integrations 70/73 and focused existing units 31/34; all three integration and three unit failures reproduce on the original SQL and are detailed in backend evidence. Flutter analysis is clean and 10 existing banner widget tests pass. Required final code review has no blockers. No deployment or production performance claim.

- Production release: user explicitly authorized deployment. Isolated release `7e4132c` on production base `030aebd`; exact-release local integration 8/8 passed. Guarded reload and health checks passed with two HTTP workers and existing cron/resolution roles. Observed empty-query mean execution 323.8 → 89.6 ms and buffers/call 14,334.5 → 2,315.4. Direct managed CPU idle 29.97% → 37.49% under differing traffic; no causal CPU or 70% target claim. Detailed counters and deployment limits are in backend `docs/global-event-enrollment-query-production.md`. No new natural cohort appeared during observation.
