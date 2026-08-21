# Capacity bottleneck optimization requirements

**Status:** Specification complete; awaiting owner approval before implementation.

**Evidence date:** 2026-08-17  
**Frontend baseline:** `17ca1a8` plus uncommitted capacity-test corrections
**Backend staging baseline:** `f86dd81`  
**Historical measured topology:** one staging PM2 worker, PgBouncer pool 20,
production kept at two workers with cron ownership on production instance 0  
**Required next-baseline topology:** one staging PM2 worker, PgBouncer pool 3

The measured evidence and raw workstream notes live in the backend repository at
`docs/capacity-bottleneck-optimization-plan-2026-08-17.md`. This document is the
implementation contract. A faster result alone is not sufficient: every milestone
must preserve frozen-client behavior, prove its own effect, and remain independently
reversible.

## 1. Summary and user stories

As a user, step uploads, race standings, and messages remain responsive during
normal peak traffic and background race processing. As the operator, we can state a
capacity ceiling from a reproducible arrival-rate test rather than stale scenario
names or a linear worker-count assumption.

The historical 15-rps run had no hard failures or dropped arrivals; the 31-rps run
dropped arrivals, queued work for over 20 seconds, and produced double-digit p95
latency. Those runs used a temporary pool of 20 and the harness defects in §5.0, so
they do **not** establish a pool-3 capacity ceiling. Milestone 5.0 must be followed
by a corrected-harness, one-worker, pool-3 baseline before any optimization or DAU
claim. Two production workers do not imply exactly twice the DAU because they share
a host, database, Redis, and cron load.

## 2. Scope and non-goals

### In scope

1. Repair the capacity harness and conversion so repeated tests model the shipped
   client and produce enforceable endpoint/status results.
2. Add low-overhead phase/query-count telemetry before changing expensive paths.
3. Reduce placement baseline write amplification while preserving compare-and-set
   and notification behavior.
4. Reduce redundant race-resolution generations and worker follow-up work without
   losing a mutation across the enqueue/claim boundary.
5. Reuse safe scoring inputs for legacy `/steps` and `/steps/samples` while
   preserving same-response box/powerup freshness.
6. Remove full-roster cosmetic hydration from paged progress/bootstrap while still
   scoring and ranking the complete roster.
7. Optimize message/presentation cold misses only where the new measurements prove
   material cost.
8. Establish the first valid one-worker, pool-3 baseline, then re-run that identical
   protocol after each milestone.

### Explicit non-goals

- No scoring, ranking, tie, team, powerup, box, placement, or notification policy
  change.
- No API response-field removal, repurposing, or newly required request parameter.
- No conversion of frozen-client legacy step endpoints to enqueue-only behavior.
- No database-paging of the scoring roster; full accepted-roster inputs remain
  required for authoritative ranks, teams, effects, illusions, imposters, and drop
  odds.
- No re-enabling the removed advisory-transaction race lock. The current
  `withRaceResolutionLock` is intentionally a passthrough after a pool-drain
  incident; there is no existing serialization boundary to preserve.
- No broad response/list cache, Redis-as-authority behavior, or shared/prod Redis
  flush.
- No production deploy, database mutation, worker change, or further PgBouncer
  expansion under this approval. Those require separate, immediate authorization.
- No cron/web process split or overload/429 product behavior in the code-capacity
  result. Those are separately measured infrastructure/product phases.
- No visible Flutter UI or pagination-navigation behavior change. In particular,
  the existing page-2 periodic-refresh behavior and the completed-bootstrap defect
  described in §5.4 are isolated follow-ups unless separately approved.

## 3. Current evidence and fixed benchmark assumptions

Production traffic for the measured window was 495 DAU and 280,554 app
requests/day: 566.8 requests/DAU/day, 3.25 mean rps, a 12.82-rps peak ten-minute
bucket, and a peak coefficient of 0.0259 rps/DAU. Therefore 15 rps is approximately
580 DAU and 31 rps approximately 1,200 DAU. Each future claim must recompute and
publish the window, timezone, DAU definition, excluded non-app traffic, peak bucket,
and coefficient.

Staging has now been restored to PgBouncer pool 3. The historical load table below
was run at pool 20, not pool 3. It diagnoses bottlenecks but cannot certify 580 DAU
on the required topology. Pool size, one-worker topology, fixture corpus, backend
revision, config flags, Redis state, and cron phase are test inputs and must be
recorded. Raising the pool is not a code optimization.

The historical switched/partially-corrected-harness measurements at **pool 20** were:

| Offered load | Completed | Hard failures | Dropped | Overall p95 |
|---|---:|---:|---:|---:|
| 15 rps for 90s | 1,351 | 0 | 0 | 3.40s |
| 31 rps for 30s | 882 (23.17/s effective) | 1 timeout | 49 | 14.23s |

Measured hotspots include legacy step writes (25–29s p95 at 31 rps), progress
(12.89s), race list (11.35s), resolution queue lag (21.2s), hundreds of placement
CAS writes during changed-baseline ticks, and full-roster cosmetic hydration before
paging. Cache timings seen under global queueing are hypotheses, not proof of cache
cost.

## 4. Compatibility and API contract

All optimized and rollback paths must retain the current HTTP status, envelope,
field names, nullability, ordering, and semantics.

### 4.1 Race details and progress

- Current clients advertise `race_participants_paging`.
- Initial open uses
  `GET /races/:id/bootstrap?view=participants-v1&offset=0&limit=15`.
- Details fallback uses
  `GET /races/:id?view=participants-v1&offset=0&limit=15`.
- Progress paging uses
  `GET /races/:id/progress?view=participants-v1&offset=N&limit=15`.
- Bootstrap stays `contract: race-bootstrap-v1`. Details pagination remains at
  `race.participantsPagination`; progress pagination remains at
  `progress.pagination`; paged progress stays
  `contract: race-progress-participants-v1`.
- Details slicing remains double-gated by client capability and query view. Frozen
  clients without the capability still receive complete arrays even if they send
  the view. Old backends that ignore progress paging remain safe.
- ACTIVE solo progress may page. Team and non-ACTIVE progress remain whole. Public
  preview remains read-only, Redis failure remains persisted-read rather than
  request replay, and powerup-use context continues to force a full roster.
- `myStatus`, viewer totals/team, accepted counts, participant IDs, ranking/ties,
  effects, stealth/detour/imposter state, global event, powerup data, and money
  fields remain authoritative and identical.

### 4.2 Step writes and resolution jobs

- `POST /steps` remains `{record}` and `POST /steps/samples` remains `{count}`.
  Same-request uploader participant totals and box/powerup promotion remain visible
  before these legacy responses return.
- Sync-v2 job ID, integer generation, requested time, terminal states, and polling
  semantics remain unchanged. Multiple still-queued requests may safely share a
  generation only when their scopes/users are atomically merged under the conflict
  row lock. Once claim wins, enqueue must increment so the generation fence and
  follow-up cannot lose the new mutation.

### 4.3 Messages and cache failure

Message authorization, cursor/default shapes, stealth naming, mutation order, and
raw cache envelopes remain unchanged. Redis uncertainty always falls back to
Postgres. Generation/WATCH and ABA protections must not be weakened.

## 5. Ordered implementation milestones

Each milestone starts with a failing integration test, uses its own default-off
switch where behavior changes, ships and benchmarks alone, and can be rolled back
without reverting later milestones.

### 5.0 Harness and observability — prerequisite

Frontend-owned work:

- Correct `race_detail` to `offset=0&limit=15`; progress and bootstrap already use
  15 locally.
- Replace stale DAU-named rungs/thresholds with offered-rate identities and install
  thresholds for every selected rung. Report p95/p99, dropped arrivals, hard
  failures, 429s, and critical endpoint budgets.
- Count selected endpoint separately from executed endpoint/fallback. A fallback to
  `/races` must not silently satisfy another endpoint's weight.
- Replace VU-local opportunistic resolution jobs with fresh current-run jobs on
  dedicated fixture users having exactly one ACTIVE race; exclude those users and
  their race peers from write traffic. Require at least one lag sample and final
  outstanding jobs to equal zero. Any SUPERSEDED result invalidates the run rather
  than changing the frozen polling API; stale/terminal fixture jobs and a no-sample
  Trend may never satisfy the lag gate.
- Preserve ACTIVE/PENDING race IDs separately and choose status-valid endpoints.
  Record team/solo and roster-size strata. Label the 14-day fixture pool separately
  from the 24-hour DAU denominator.
- Replace fixed-column CSV parsing with tagged counters/trends and structured
  summary output. Mirror the released feature header or explicitly name/version
  each client cohort.
- Send a real allowlisted released activation-event payload; a soft-dropped
  `accepted: 0` analytics no-op is not representative write traffic.
- Aggregate three structured summaries/raw streams before enforcing sparse endpoint
  coverage: selected and executed totals must match exactly, and endpoint p95 is
  gated only at 20 or more aggregate samples. Include endpoint-by-status and
  resolution-state matrices. Bind every raw metric and summary to a unique run ID
  and repeat index, reject duplicate/mispaired runs, and require per-endpoint
  selected = executed = duration samples = summed exact-status samples. A duration
  override is explicitly diagnostic and non-claimable.

Backend-owned work:

- Add sampled phase duration and query-count telemetry for placement, uploader
  reconciliation, progress/bootstrap projection/hydration, enqueue, presentation
  cache, and message access. Do not log tokens, raw step samples, message bodies, or
  other personal payloads.
- Record placement proposals/CAS wins/events, resolution generation reuse/bumps and
  lag, cache hit/miss/load/install counts, page size versus hydrated IDs, and
  process/DB-pool pressure.
- Publish query-capture availability explicitly and omit query counts when Prisma
  query events are unavailable. A claimable run requires query capture enabled and
  recorded identically in paired runs. Concurrent fan-out uses one enclosing query
  phase or phase-local attribution—overlapping request-wide snapshots may not double
  count queries. Presentation metrics distinguish bypass/error, actual hits/misses,
  load operations, and loaded identity counts.
- Correlate each server telemetry record to a validated capacity run ID/repeat
  header without changing public responses. Claimable aggregation consumes
  server-derived evidence for every repeat and requires query capture available,
  measurement gate eligible, identical settings, and no placeholder revision/
  config/topology labels.

Gate: an inspection, deterministic smoke, and low-rate run prove that every
intended endpoint/status is represented and all selected-rung thresholds receive
samples. A mandatory cohort aggregator validates the three-run gates. Telemetry adds zero database queries; across three paired warm 5-rps,
60-second runs, its median p50 and process CPU-time/request regress by no more than
5%. Then run the first valid pool-3 baseline described in §8. Milestone 5.1 cannot
be approved until that baseline is recorded.

### 5.1 Paged progress/bootstrap projection — first code optimization

This has the clearest large-roster read amplification and can improve both cold and
warm standings without changing scoring.

- Add an audited lean progress read context containing race/access scalars and the
  complete participant scoring/inventory/drop-odds fields, but no participant
  user/accessory/shop graph.
- Initially optimize the Redis-standings-enabled path. Retain the fat legacy replay
  path while standings caching is off because that path persists derived state and
  has broader side effects.
- Version the standings snapshot schema. Store the complete honest scoring roster,
  totals, placements, teams, multipliers, base-adjusted data, and effects; remove
  embedded display names/photos/cosmetics.
- Apply viewer illusions, sort/rank, imposter swaps, and page selection over the
  complete roster. Then bulk hydrate presentation only for visible returned users
  (plus the viewer where required). Unpaged/legacy responses hydrate every returned
  row. Detour-masked rows need no cosmetic load.
- Stop treating the lean progress context as a fat details preload. Paged bootstrap
  uses the existing lean details core/page plan or a deliberately shared scalar
  summary. Old unpaged bootstrap/details retain full participant presentation.
Optional index candidates—`race_participants(race_id, joined_at, id)` and message
ordering indexes—require `EXPLAIN (ANALYZE, BUFFERS)` against representative test
data before an additive concurrent migration is proposed. No index is accepted from
query shape alone.

Gate: output parity; warm paged progress hydrates no more than the returned page;
cosmetic query work does not scale from 10 to 500 participants; presentation changes
appear on the next read; a 500-person bootstrap materially reduces DB rows/bytes and
latency.

### 5.2 Placement baseline worker batch

- Add a new default-off switch; do not repurpose the already-enabled lean-baseline
  switch. The five-minute placement cron must not become a second bulk writer.
- Register a closed `PLACEMENT_BASELINE` resolution reason. With the switch on, cron
  enqueues only the race ID plus that reason—never in-memory proposals. After claim,
  the race-keyed resolution worker recomputes ordered proposals from current
  persisted standings, then applies the batch inside its fence-first lease
  transaction. A crash or process handoff therefore cannot lose proposal state.
  This preserves the C0 single-writer rule for bulk participant updates.
- Put the raw batch SQL in the injected race-participant domain model with optional
  `tx`; orchestration stays in the job/worker. Batch `(participant id, user id,
  expected baseline, next baseline)` with a null-safe expected-value CAS and
  `RETURNING` of actual winners.
- Buffer returned winners and emit ordinary placement events only after commit, in
  original ranked proposal order. Fence loss emits nothing and leaves retryable
  work under the queue contract.
- Preserve silent first observation, resync, muted baseline advancement, payout
  crossing, frozen-client push payloads, and unrelated totals/forfeit fields.
- PostgreSQL `VALUES` order is not a lock-order guarantee. The implementation must
  establish/prove a global `user_id,id` lock order compatible with resolution
  writes, or use another reviewed deadlock-safe construction.
- A failed worker chunk rolls back its transaction and follows the queue retry path;
  cron never falls back to direct bulk writes. With the flag off, the existing
  scalar cron CAS path remains the rollback behavior.
- Team baseline writes remain explicitly out of this first batch. A later team batch
  requires all-baselines-before-deduped-team-event parity and separate approval.

Gate: real-DB query counts are constant per configured chunk at 10/100/750
proposals; exact event/payload parity; forced fence loss, settlement/expiry overlap,
lost CAS, deadlock stress, and injected transaction failure lose no later work; a
structural test permits no direct cron bulk writer; a deterministically triggered
changed-baseline tick finishes under three seconds without an HTTP latency wave.

### 5.3 Queued resolution generation merge

- Add a separate default-off application setting. Preserve old generation-bump
  assertions with the flag off.
- Decide reuse inside the existing atomic `INSERT ... ON CONFLICT DO UPDATE` row
  lock. A separate unlocked SELECT may never authorize skipping/bypassing enqueue.
- Reuse generation only when the conflict-locked row is `state=QUEUED`, has no live
  lease, and `processing_generation IS NULL OR processing_generation < generation`,
  while atomically merging users, dirty scope/reasons, timezone/priority,
  display-artifact rules, retry/error reset, processing crash scope, and caps. A
  failed claimed generation returned to QUEUED with
  `processing_generation = generation` must bump. A successor generation not yet
  claimed may reuse. RUNNING, live-leased, and SUCCEEDED work bump under existing
  rules.
- Malformed scope degrades safely to FULL. Pure display refresh replacement and
  mixed-reason artifact invalidation retain current semantics.
- Benchmark generation reuse separately from a safe containment branch. Reuse still
  takes the row conflict lock and may still pay JSON/WAL cost; it is expected to
  reduce worker follow-ups, not automatically eliminate the hot enqueue statement.

Gate: barrier-driven enqueue-versus-claim integration tests prove either same-gen
scope capture or a bumped follow-up, never loss; both HTTP requests can poll a shared
queued generation; explicit failed-retry, superseded-successor, lease-expiry,
lock-order/deadlock, crash-recovery, closure, settlement, and query-plan cases pass;
queue lag improves without a promised SQL-share target.

### 5.4 Legacy uploader reconciliation reuse

- Add a separate default-off switch and instrument first.
- Build a specialized uploader-only prefetch for **steps and samples only**, grouped
  by unique scoring window, score timezone/box timezone, and a single explicit
  request `asOf`. Reuse one global-event superset filtered per race and retain
  canonical scoring functions. Effects and Hitchhike state stay just-in-time unless
  a later design introduces a durable race-scoped fence that covers them.
- Do not reuse the generic full-race scoring prefetch, which can load every user in
  a 500-person race and has unsafe missing-user behavior for Hitchhike targets.
- Before capture, idempotently materialize the user's version row with
  `INSERT ... ON CONFLICT DO NOTHING`; historical users and sample no-op paths may
  not have one. Capture the user's step/sample scoring-input generation. The final
  generation check, membership/status recheck, and participant write must share one
  transaction that locks that now-present version row. A check followed by an
  independent Prisma update is forbidden. On mismatch, reload just in time and
  retry through the same atomic path; do not overwrite a newer upload.
- Preserve the second box-timezone score when score and box timezones differ.
  Revalidate participant membership/status before write. Do not reintroduce the
  removed pooled-connection advisory lock.
- The current reason-aware flow already passes reconciled races to enqueue. Do not
  add a second optimization for an active-race lookup that is already avoided.

Gate: real HTTP/real Postgres tests over 1/5/16 active races prove exact JSON,
immediate box/powerup results, query growth by unique window, global event,
  Leech/Hitchhike, timezone, finish/forfeit behavior, and both commit orders of a
  forced concurrent-upload pair with no stale total regression, including a user
  starting with no version row. Legacy write p95 is below two seconds at the
  15-rps gate.

### 5.5 Message/presentation follow-ups — individually evidence gated

These are separate submilestones and must never be enabled or benchmarked together
for their first attribution:

- **5.5a race-list podium presentation:** use the guarded presentation cache for
  only the bounded podium names on `GET /races`; never cache the whole list.
- **5.5b lean message access:** replace message-stream/full-message access loads with a lean query for only
  the caller, tournament access, seeded marker, and required flags. After effects
  reveal stealthed target IDs, hydrate only those names through the presentation
  cache.
- **5.5c marker batching:** batch watched generation-marker reads without weakening
  the install fence.
- **5.5d local singleflight:** add a bounded per-process singleflight only for
  identical presentation loads.
- Never weaken list-cache mutation Lua, WATCH/version/ABA protection, cursor
  behavior, or authorization.

Gate for each submilestone: large-roster access queries load only the documented
bounded identities; warm response p95 meets its endpoint budget; concurrent mutation
cannot install or serve stale presentation; and the targeted query/miss metric
improves by at least 10% across the three-repeat protocol in §8.

### 5.6 Exact rollout flags

The following exact keys must be added to backend `KNOWN_FLAGS`, all defaulting to
`false`. “Cached request read” means one `getFlag` at the request/job entry point,
using the existing 30-second in-process settings cache and invalidation. No inner
loop may re-read a flag.

| Flag | Read cadence | Prerequisite | False behavior |
|---|---|---|---|
| `capacityPhaseMetricsV1Enabled` | cached request/tick read | none | only existing metrics/logs |
| `raceProgressLeanProjectionV1Enabled` | cached request read | Redis standings on; paging-capable request | current fat progress/bootstrap path |
| `placementBaselineWorkerBatchV1Enabled` | uncached once per placement tick | worker understands closed `PLACEMENT_BASELINE` reason | current scalar cron CAS |
| `raceResolutionQueuedGenerationMergeV1Enabled` | cached once per enqueue operation | queue v2 | every enqueue bumps generation as today |
| `legacyUploaderStepSamplePrefetchV1Enabled` | cached once per legacy write | scoring-input version row available | current per-race just-in-time reads |
| `raceListPresentationCacheV1Enabled` | cached request read | generation-safe presentation invalidation | current bounded DB presentation query |
| `raceMessageLeanAccessV1Enabled` | cached request read | none | current full access load |
| `presentationMarkerBatchV1Enabled` | cached presentation-load read | a generation-safe presentation consumer | current sequential watched marker reads |
| `presentationSingleflightV1Enabled` | cached presentation-load read | marker correctness unchanged | independent cold loads as today |

When progress, race list, or message access becomes a presentation-cache consumer,
its flag must also activate the existing generation-safe invalidation mode; that
mode cannot depend only on the older messages/leaderboard/friends flags. Existing
versioned keys, physical TTLs, mutation invalidations, generation guard, WATCH/ABA
checks, and Postgres fallback remain unchanged.

A flag-off rollback changes only new requests/ticks. Already queued
`PLACEMENT_BASELINE` work remains a recognized, safely processable closed-registry
reason; it is never stranded or interpreted as FULL by a mixed worker fleet.

### 5.7 Implementation ownership map

| Concern | Required seam |
|---|---|
| Prisma/raw SQL and optional transaction client | domain model (`race`, `raceParticipant`, or `raceResolutionJobV2`) |
| Request orchestration and response compatibility | existing race/step query, command, or route seam |
| Placement scheduling and fenced execution | placement cron enqueues; race-resolution worker writes |
| Presentation loading/invalidation | `userPresentationCache` public service |
| Cross-module calls | module public `index.js`, never a deep private import |
| Tests/forced races | existing dependency-injection collaborators plus real DB/HTTP |

No route or cron embeds raw SQL, and no test imports an internal calculation to
simulate public-path correctness.

## 6. Pre-existing contract issues isolated from this effort

Research found two behaviors that need their own owner decision and tests, but are
not prerequisites for invisible backend optimization:

1. A normal 30-second progress refresh uses offset zero, so a viewer on page two is
   returned to page one despite a comment implying current-page refresh. Changing
   this is visible paging behavior and therefore requires UI-placement planning.
2. Backend bootstrap returns `progress: null` for every non-ACTIVE race. The current
   supported-bootstrap COMPLETED client path does not refetch when this is null, so
   final standings can error. A frontend-only fix cannot repair frozen clients; a
   backend bootstrap change increases completed-race cost. Specify and approve this
   compatibility fix separately, with a real backend response plus real screen test.

Neither issue may be “fixed” incidentally in a capacity patch or benchmark.

## 7. Test-first matrix

Before business logic, add or extend real HTTP/real Postgres integration coverage:

- Progress/bootstrap: warm/cold, 10 versus 500 participants, query capture, complete
  ranking/ties/teams/finishers/forfeiters, two viewers, effects, stealth, detour,
  imposter, Redis down, cache flag off, presentation rename/equip, public preview,
  powerup full-context, and snapshot allowlist/version. With the lean flag on, a
  frozen request without `race_participants_paging` still receives the full roster.
  During a mixed old/new PM2-style test, each process safely rejects and rebuilds or
  falls back from an unsupported inner snapshot schema; the existing inner-schema
  rejection must not be relaxed.
- Placement: null CAS, first/muted/resync/frozen paths, lost CAS, unrelated mutation,
  event order/payload parity, team non-regression, chunk failure, and deadlock stress.
- Queue: flag-off old behavior; queued union/reuse; enqueue/claim barrier; RUNNING and
  SUCCEEDED bump; retry/crash scope; malformed/capped scope; artifact/timezone/
  priority; HTTP polling; lock order; spawned-worker crash recovery.
- Legacy writes: 1/5/16 active races, repeated/distinct timezones/windows, response
  shape, immediate boxes, effects/events, membership change, and concurrent version
  fence.
- Messages: caller-only access, target-name hydration, cache parity, rename/equip,
  cursor variants, WATCH/ABA post race, and optional cold-miss query count.
- Milestone telemetry: flag-off silence and byte parity; known DB-backed HTTP route
  with query capture available and `queryCount > 0`; explicit unavailable behavior;
  exact controlled concurrent-fan-out attribution; bootstrap, messages,
  presentation hit/miss/bypass, placement tick, and queue-lag entry seams.

Frontend tests extend existing suites rather than mocking around the wire:

- Real `BackendApiService` with fake `HttpClient` asserts exact `limit=15` bootstrap,
  details fallback, and progress URLs and exact capability header.
- Real `RaceDetailScreen` widget paths cover supported paged bootstrap, 404-only
  cached legacy fallback, malformed/5xx non-fallback, progress unavailable, paging
  ignored by an old backend, server-clamped/short/empty pages, off-page viewer,
  team/non-ACTIVE whole rosters, 403 polling stop, transient stale display, and
  lifecycle pause.
- Missing/null/malformed additive fields never crash. Existing protected assertions
  are not weakened; old semantics remain exercised with new switches off.
- Harness contract tests cover the allowlisted activation payload, fresh dedicated
  resolution-job lifecycle/final drain, endpoint/status and resolution-state
  aggregation, sparse 20-sample thresholding, and diagnostic duration overrides.

Before any backend integration run, verify `DATABASE_URL` targets a dedicated
`*_test` database. Run `npm run test:integration`, never bare `npm test`. Frontend
completion requires `flutter analyze` and `flutter test` plus both iOS and Android
impact review. Redis-backed integration suites use local test Redis DB 15 only, and
the relevant suite must also pass once with `REDIS_URL` unset. A generic “Redis
down” mock is not a substitute for either configuration.

## 8. Benchmark and rollout protocol

For each milestone, record commit, flags, worker count, pool 3, fixture revision,
race-status/team/size mix, Redis state, cron timestamps, memory, DB pool pressure,
queue lag, endpoint/status counts, and phase/query telemetry.

The harness status allowlist is exact: every endpoint must return 2xx, except
`challenges_current`, which may return 200 or the documented organic 404. Status 0,
401, 403, 408, 409, 429, or any 5xx is a capacity failure; 429 is reported
separately as well. Context fallback count must be zero. Selected and executed
endpoint counters must both be nonzero for every configured endpoint in the
aggregate three-repeat cohort, and their difference must be zero.

Every 15-rps and capacity-claiming 31-rps cohort has these executable thresholds:

- `dropped_iterations == 0`;
- at 15 rps, `capacity_failure_rate == 0`; at 31 rps,
  `capacity_failure_rate < 0.01`;
- overall duration `p(95) < 2000ms` and `p(99) < 5000ms`;
- combined persistence-critical traffic (`steps_post`, `steps_samples`,
  `steps_sync_v2`) has `p(95) < 2000ms`, `p(99) < 5000ms`, and no completed request
  at or above 15 seconds;
- every endpoint with at least 20 aggregate samples has `p(95) < 2000ms`; and
- resolution lag peaks below five seconds and drains to zero before the next run.

Expected `challenges_current` 404s are excluded only from the custom capacity
failure metric, never hidden from the status summary.

Run three cache/process states separately:

1. warm process + warm Redis;
2. cold process/L1 + warm Redis (restart only);
3. cold process + targeted cold **staging test namespace** in Redis.

Never flush shared or production Redis. Keep startup-cron overlap separate from cold
cache. For every claimed cache/cron cohort, discard one warm-up and run at least
three measured repeats. Include warm steady state outside a heavy tick, controlled
overlap, and restart/startup overlap as separately labeled cohorts. At least one
measured 15-rps repeat deterministically triggers a 600+-proposal changed-baseline
placement tick while load is active; a 90-second run may not rely on chance to meet
the five-minute schedule. Run 15 rps for 90 seconds. Run 31 rps for 30 seconds only
after all 15-rps gates pass.

Compare medians of the three matched repeats. A result is a material improvement
only when its target latency/query/lag metric improves by at least 10% without any
gate failure. A greater-than-10% regression in any endpoint p95 with at least 20
aggregate samples is a rollback; smaller changes are reported as inconclusive noise,
not a win.

Promotion sequence for every behavioral switch is default off → staging canary →
full staging → measured run → separately approved production exposure. Because app
settings affect both PM2 workers and no deterministic cohort mechanism is proposed,
“production canary” means a separately authorized, time-boxed **global** flag
exposure, not a user/worker cohort. Its authorization must name duration, observer,
rollback command, and abort metrics: any semantic mismatch, capacity failure,
P2028/pool timeout/deadlock, PM2 restart, memory headroom below 300 MB, resolution
lag at or above five seconds, or greater-than-10% matched endpoint-p95 regression.
Turning the flag off is the rollback.

## 9. Acceptance criteria and definition of done

A higher capacity/DAU claim requires:

- hard failures below 1% and zero at the conservative rung;
- zero dropped arrivals;
- overall p95 below 2s and p99 below 5s;
- no completed persistence-critical request at or above 15s;
- resolution lag below 5s and drained before the next rung;
- no new P2028, deadlock, uniqueness, pool-timeout, ambiguous write, OOM, or PM2
  restart;
- at least 300 MB shared-host memory headroom;
- parity tests and switch-off rollback paths green;
- the post-change run matching the pre-change protocol and cron/cache cohort; and
- the DAU coefficient recomputed from a documented current production window.

Implementation is done only after the relevant integration tests, frontend wire/
widget tests, full required suites, static analysis, platform/version-skew review,
architecture review, and final code review pass. No UI-placement checklist is needed
while output and visible behavior remain identical. Any visible pagination,
degradation, or completed-race behavior change triggers that workflow.

Until the corrected pool-3 baseline is run, this investigation makes no validated
one-worker DAU-capacity claim. After that, the highest arrival rate satisfying every
gate may be converted with the contemporaneous coefficient. Production capacity
remains independently measured, not a 2× extrapolation.

## 10. Owner decisions and approval gate

Recommended approval is for **Milestone 5.0 only**, followed by the first valid
corrected-harness, one-worker, pool-3 baseline. Review that result before approving
any optimization. Then approve/implement one code milestone at a time in this order: **5.1 paged
progress**, **5.2 placement batch**, **5.3 queued generation merge**, **5.4 legacy
reconciliation**, and **5.5 cache work only if measured**. This ordering favors the
best-evidenced, lowest-contract-risk work and keeps attribution intact.

No unresolved product question blocks Milestone 5.0 or 5.1. Approval of this spec
does not approve deployment, production mutation, infrastructure resizing, the two
isolated behavior fixes in §6, or all milestones as one implementation batch.

## 11. Revision log

- **2026-08-17 — Phase 1:** Converted the measured backend plan into a cross-repo,
  contract-first specification and corrected the DAU coefficient.
- **2026-08-17 — Gap pass 1 (behavior/version skew):** Added exact 15-person wire
  contracts, capability/legacy gating, team/non-ACTIVE exceptions, frozen legacy
  write freshness, Redis fallback, and the completed-bootstrap/page-refresh issues.
- **2026-08-17 — Gap pass 2 (failure/concurrency/operability):** Added enqueue/claim
  atomicity, scoring-input version fences, explicit absence of a live race lock,
  PostgreSQL lock-order requirements, chunk fallback, three cache states, cron
  cohorts, per-switch rollback, memory/pool gates, and evidence-only indexes.
- **2026-08-17 — Specialist research:** Folded independent frontend/harness,
  backend read-path, and backend write-path audits into §§4–8. No specialist changed
  code.
- **2026-08-17 — Architecture review:** Corrected historical pool provenance and
  withdrew the unsupported pool-3 ceiling; moved placement batching behind the
  fenced single writer; made queued-retry eligibility exact; limited legacy prefetch
  to atomically fenced step/sample inputs; added exact flags, mixed-version/Redis
  tests, numeric thresholds/repeats, ownership seams, and global-production-exposure
  abort rules. Architecture review then returned for final confirmation.
- **2026-08-17 — Architecture re-review:** Made placement proposals durable by
  recomputing them in the claimed worker, defined absent scoring-version-row
  materialization/locking, and removed the underspecified distributed Redis rebuild
  lock from this approval.
- **2026-08-18 — Implementation code review:** Prevented false-green lag from stale
  or no-sample resolution jobs, moved sparse gates to the three-run aggregator,
  replaced a soft-dropped analytics payload, required endpoint/status matrices and
  non-claimable overrides, and made query availability/concurrency and presentation
  cache accounting explicit before staging use.
