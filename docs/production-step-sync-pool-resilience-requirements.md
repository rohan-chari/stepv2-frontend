# Production step-sync pool resilience requirements

**Status:** Revised draft for telemetry-only backend plus admin visibility; no
implementation or production change authorized.

**Incident evidence:** 2026-08-29, approximately 14:29–14:30 America/New_York.

## Summary and user story

As a user on any shipped app version, my step upload should either commit once and
return its existing success response or recover safely on retry when many devices
sync together. As the operator, database connection ownership must be bounded by
process role and observable before pool pressure becomes user-visible `500`s. As an
authenticated administrator, I can inspect current pool health and the last hour's
aggregate pressure from the existing Admin Tools screen without SSH access.

The incident was a short arrival-rate burst, not host exhaustion. Normal
`POST /steps` traffic was roughly 10–18 requests/minute, then rose to 231 in one
minute and 143 in the next. Fifty legacy `/steps` requests returned `500`; the
dominant error was node-postgres `timeout exceeded when trying to connect` while
Prisma attempted to start `stepInputIntake` transactions. In the deployed
`pg-pool` 3.13.0, that exact message is emitted only when a pending checkout waits
past `connectionTimeoutMillis`; a physical establishment timeout has the different
message `Connection terminated due to connection timeout`. The failed requests
therefore timed out in the worker-local pending checkout queue. Existing logs do
not prove why checked-out/connecting capacity stayed unavailable—long transactions,
slow physical establishment, or both remain possible upstream causes. At the incident's
ten-minute host sample, CPU was about 87% idle, memory was about 24% used, and swap
was unused.

The current backend creates an explicit `pg.Pool` in `src/db.js` with `max: 20`
and `connectionTimeoutMillis: 5000`. Production runs two HTTP processes, one
resolution process, and one cron process from `ecosystem.config.js`; all import the
same pool factory. Their theoretical application maximum is therefore 80 while
PostgreSQL currently reports `max_connections=50`, three superuser-reserved slots,
and non-application/system consumers. During the investigation PostgreSQL had 39
connections, including 25 idle local application connections.

The existing durable race-resolution queue remains correct and in scope only for
verification. It begins after the step source transaction acquires a connection,
persists source/scoring state, discovers active races, and enqueues jobs. The
incident occurred before that queue could help: both HTTP-worker logs show pending
checkout timeouts, but current telemetry cannot reconstruct each worker's occupancy
or the upstream reason connections did not become available.

This specification does **not** claim that lowering pool sizes alone reduces
failures. A smaller HTTP pool can fail sooner if transaction service time is
unchanged. The change is promotable only when the complete package—role budgets,
attributable telemetry, and evidence-backed reduction of connection hold
time—passes the recorded-burst replay and the normal full-app capacity profile.

## Scope and non-goals

### In scope

1. Production-safe, role-specific database pool configuration with permanent
   defaults and fail-fast validation against the declared four-process topology.
2. Low-overhead production telemetry for pool ownership, acquisition waits,
   failures, and step-source transaction phases, with no user identity or payload.
3. A corrected capacity collector that aggregates both HTTP workers and the
   resolution/cron processes instead of sampling whichever HTTP worker answers.
4. A dedicated incident-replay profile matching the observed open-loop burst,
   tested with both distinct users and repeated submissions for the same users.
5. Evidence-gated shortening of the legacy step-source transaction while
   retaining atomic source/scoring/queue semantics and frozen-client response
   behavior.
6. Explicit verification that the existing durable resolution queue drains and
   that failed pre-acquisition writes recover through existing client retry paths.
7. A read-only admin API and `SYSTEM HEALTH` section showing fresh per-process pool
   state plus bounded 60-minute aggregate step/pool pressure.

### Non-goals

- No increase to PostgreSQL `max_connections`, no additional PM2 worker, and no
  database or host resize in this feature.
- No conversion of legacy `/steps` or `/steps/samples` to enqueue-only behavior;
  frozen clients retain the synchronous atomic source/scoring/durable-job commit
  and exact existing response JSON/status. Race and box resolution remain
  asynchronous under the existing queue contract.
- No new user-visible status, response field, required header, or request body.
- No generic request admission queue or `429` behavior in the first
  implementation. Frozen mutation retry semantics make that a separate contract.
- No distributed Redis lock or Redis authority for step persistence. Redis may
  carry short-lived, non-authoritative operational snapshots solely for the admin
  view; logs remain the durable evidence and Redis failure never affects requests.
- No per-user request coalescing until measurements prove overlapping duplicate
  submissions are material. The 2026-08-29 access log does not contain authenticated
  user IDs, so the incident cannot support that conclusion.
- No feature flag, rollout percentage, kill switch, or temporary runtime toggle.
- No production deployment, restart, environment edit, or production database
  mutation under approval of this specification.
- No editable pool control in the admin UI, no restart/deploy button, no raw-log
  viewer, no alert acknowledgement, and no historical retention beyond two hours.

### Relationship to existing capacity specifications

This is a narrow incident-resilience contract, not approval to implement every
milestone in `docs/capacity-bottleneck-optimization-requirements.md`. That older
document supplies useful endpoint and load-test evidence, but its historical
default-off rollout-switch strategy conflicts with the repository's current
permanent-behavior rule and is not imported here. The current guarded workflow in
the backend's `docs/capacity-load-runbook.md` is authoritative; commands in
superseded transaction-hold or retired-harness documents are evidence only.

The earlier investigation already established that merely raising pools moved the
failure wall and that enqueue/transaction service time matters. This specification
therefore measures pool policy and transaction changes independently and forbids a
capacity claim from a bundled before/after result.

## Current architecture and failure boundary

```text
Frozen/current app
       |
       v
requireAuth (user lookup + best-effort stamps)
       |
       v
worker-local pg.Pool (currently max 20, acquisition timeout 5 s)
       |                       |
       | acquisition fails in 5 s +--> HTTP 500 (the incident)
       v
stepInputIntake transaction
  - lock scoring-input state
  - read/upsert daily steps and reconcile samples
  - derive/persist scoring-input generation
  - find active memberships
  - enqueue durable race-resolution jobs
       |
       v
commit source + queue atomically
       |
       v
existing dedicated resolution process/queue
```

`POST /steps` and `/steps/samples` both use `stepInputIntake`. `sync-v2` adds an
idempotency reservation and has a single same-key retry on ambiguous failure. The
legacy foreground path retries the daily write once after one second. Native
background legacy writes leave a failed envelope pending for a later OS wake. The
daily row is an upsert and sample reconciliation is repeat-safe, but these recovery
properties must be proven through public paths rather than assumed from internal
helpers.

The resolution worker already limits race lanes to at most three. Cron contains
several independently bounded jobs. Pool budgets therefore need role-level load
evidence; equal division is not assumed.

## Configuration contract

Replace the capacity-only interpretation of `DB_POOL_MAX` with an explicit pool
policy function that reads `STEPS_PROCESS_ROLE` and returns one validated maximum.
Use these environment names:

```text
DB_POOL_MAX_HTTP
DB_POOL_MAX_RESOLUTION
DB_POOL_MAX_CRON
DB_POOL_MAX_ALL
```

- `http`, `resolution`, and `cron` select their matching value.
- The historical `all` role used by local development and staging selects
  `DB_POOL_MAX_ALL`.
- Runtime classification is centralized in the new pool-policy module and reused by
  `db.js`: `capacity` requires strict `CAPACITY_MODE`; explicit staging requires
  `NODE_ENV=production`, `PORT=3003`, and the currently validated staging database
  identity; production requires `NODE_ENV=production`, the validated production
  database identity, and the exact role/port mapping `http→3002`,
  `resolution→3010`, `cron→3011`; everything else is local/test. A mismatched
  production role/port or any other ambiguous
  production-like combinations fail before Prisma construction. Role `all` is
  categorically rejected against the production database.
- The four per-role variables are authoritative in production, staging, and the
  capacity harness. Legacy `DB_POOL_MAX` remains accepted only with strict
  `CAPACITY_MODE` for backward-compatible capacity configs. If `DB_POOL_MAX` and
  any per-role variable are both present, startup fails rather than choosing
  precedence. Capacity parent/child startup resolves the legacy value into each
  role explicitly and records all four resolved values in the manifest/results;
  no child silently injects `DB_POOL_MAX=20` after policy resolution.
- Values must be base-10 integers from 1 through 20. Missing values use committed
  permanent defaults; malformed/out-of-range values fail startup before Prisma is
  constructed.
- In production, validate the declared aggregate formula
  `2*HTTP + RESOLUTION + CRON` against a committed application budget. The first
  candidate budget is 32, leaving headroom beneath the current 47 non-superuser
  slots for PostgreSQL/system/operational connections. The final budget and role
  split are selected by the benchmark matrix below, not by intuition.
- Also validate the maximum rolling-reload formula across
  `3*HTTP + RESOLUTION + CRON`, `2*HTTP + 2*RESOLUTION + CRON`, and
  `2*HTTP + RESOLUTION + 2*CRON`. The production wrapper reloads all three app
  names separately. If the installed PM2 version is proven to kill a fork role
  before replacement, that role's doubled formula may be retired only with a
  recorded test. Sizing only steady state could recreate exhaustion during deploy.
  Reload attestation must sample the transient process and database-connection peak,
  not only final health. A persistent registered/unregistered orphan is a failed
  promotion and triggers the existing topology-guard remediation; if overlap cannot
  be bounded, choose limits safe for the observed maximum or fix reload topology.
- A production process with an unknown/missing role must fail startup. Local/test
  processes without a role retain a documented safe local default.
- Set PostgreSQL `application_name` to a bounded non-secret value containing role
  and PM2 instance, such as `steps:http:0`, so `pg_stat_activity` attributes usage.
- Log one startup record containing role, instance, resolved pool maximum, aggregate
  declared budget, and acquisition timeout. Never log a database URL.
- Keep `connectionTimeoutMillis=5000` and `idleTimeoutMillis=30000` unchanged in
  the pool-policy milestone so the comparison isolates pool ownership. Any timeout
  change requires a spec amendment: increasing it can hide errors as long latency,
  while decreasing it can manufacture failures.

The census runs before lower-pool candidates are finalized. The control is retained
only to reproduce current unsafe behavior:

| Candidate | HTTP ×2 | Resolution | Cron | Aggregate | Purpose |
|---|---:|---:|---:|---:|---|
| Baseline | 20 ×2 | 20 | 20 | 80 | Current behavior/control |

After the census establishes the numeric steady/transient ceiling, generate at
least three candidates emphasizing HTTP, resolution, and cron respectively. Every
candidate must satisfy all three reload formulas before it is benchmarked. For
orientation only, `HTTP=8, resolution=8, cron=4` has normal aggregate 28 and maximum
reload declaration 36; it is not promotable unless the census leaves at least 36
application slots after external and administrative headroom. A candidate that
lowers global connections but raises step failures, resolution lag, or cron lateness
fails.

The final steady and reload budgets must be derived from a fresh read-only census of
PostgreSQL reserved/system/management connections rather than the single incident
snapshot. Record the maximum non-application occupancy observed across the approved
measurement window and retain explicit emergency/administrative headroom. The
disposable capacity environment must model that reserved headroom; otherwise its
pool result is not promotable to production.

## Production observability contract

Extend `src/db.js` without adding queries or per-acquisition log spam:

- Track queued-checkout entries, queued-checkout wait duration, queued-checkout
  timeouts, physical connection attempts, physical connection establishment
  duration, physical timeouts/errors, successful acquisitions, releases, and
  current exact checked-out clients. `pg.Pool.totalCount-idleCount` must be labeled
  `nonIdle` rather than `checkedOut`, because connecting clients already count as
  total. Exact checked-out count is derived from successful acquire/release events.
- Use fixed acquisition histogram boundaries
  `1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000 ms`, plus overflow. This
  resolves both the 100 ms and one-second gates without retaining individual
  samples.
- Instrument the two `pg-pool` timeout sites separately: waiting behind a full pool
  versus establishing a new physical socket. Test a deliberately full healthy pool
  separately from an unreachable/slow PostgreSQL target.
- Emit a structured aggregate once per minute per process and an immediate
  rate-limited warning when `waiting > 0`, acquisition exceeds 1 second, or a
  failure occurs.
- Include role, PM2 instance, resolved maximum, event-loop/process pressure, and
  deltas since the previous emission.
- Do not include user IDs, tokens, IPs, database URLs, SQL text, step values, sample
  bodies, race IDs, or usernames.
- Timer shutdown must integrate with graceful PM2 shutdown and must not keep tests
  alive.
- Acquisition counts and failures are never sampled; only optional detailed phase
  timing may be sampled. A quiet minute must still emit a zero-delta heartbeat so a
  missing process can be distinguished from zero pressure.
- Metric collection and emission must execute no database query, must be bounded in
  memory, and must fail open if logging is unavailable.

Add permanent aggregate step-ingestion timing at the existing command/service seam:

- pool acquisition wait;
- scoring-state lock/read;
- daily read/write;
- sample before/reconcile/after work;
- scoring-version persist;
- active-race discovery;
- durable enqueue;
- transaction total and outcome.

Instrumentation spans the full authenticated request rather than only
`stepInputIntake`. Add a privacy-safe request context after route classification and
measure authentication DB work, legacy transaction attempts, sync-v2 reservation/
recovery, each of sync-v2's up-to-three outer transaction attempts, summary-capture
fencing/finalization, whole request time, and post-commit bookkeeping. Because
`recordStepSyncV2` opens the outer transaction and passes its client into
`stepInputIntake`, the latter must report nested phases without pretending it owns
pool acquisition. Classify failures as authentication, legacy intake acquisition,
sync-v2 outer acquisition/intake, or post-commit work without logging request/user
identity.

Production metrics must be sampled/aggregated without enabling Prisma global query
events. Query-count capture remains restricted to the disposable capacity
environment. Existing `capacityPhaseMetricsV1Enabled` is not expanded into a release
control for this work.

Authentication remains inside the measured public path. `requireAuth` performs a
user lookup and occasional best-effort metadata stamps before `stepInputIntake`;
benchmarks and saturation tests must include that database demand and must classify
whether a failure occurred in authentication, source acquisition, or later route
work.

Update `scripts/capacity-metrics.js` and its result contract to collect every
process by role/instance. A single load-balancer-selected HTTP `/health` response is
not sufficient. In capacity mode, `capacity-cluster.js` owns a loopback-only IPC
census endpoint. For each collector nonce it requests a fresh snapshot over Node
IPC from exactly `http:0`, `http:1`, `resolution:0`, and `cron:0`; the response
contains all four identities and their sample timestamps. Missing, duplicate,
unknown, or stale identities fail the run. The census endpoint is absent outside
capacity mode. Combined results show each process's pool max/non-idle/checked-out/
idle/waiting/failure categories and the aggregate application total.

Record handled request arrivals by HTTP instance. Run both normal production-like
connection reuse and an intentionally skewed cohort that pins most arrivals to one
persistent HTTP connection/worker. Results report the per-worker arrival ratio; an
even aggregate may not conceal a worker-local timeout. Each HTTP worker independently
passes the timeout and latency gates.

### Admin snapshot transport

Each production process keeps the same bounded in-memory minute aggregates used for
logs and, once per minute, writes a sanitized snapshot to its fixed namespaced Redis
key:

```text
ops:db-pool:v1:http:0
ops:db-pool:v1:http:1
ops:db-pool:v1:resolution:0
ops:db-pool:v1:cron:0
```

The existing `CACHE_ENV_PREFIX` still separates production, staging, and tests.
Each value has a 150-second TTL and contains schema version, role, instance, boot ID,
boot time, capture time, current pool/process state, at most 60 one-minute aggregate
buckets, and—on HTTP workers only—step endpoint aggregates. The complete serialized
value is capped at 64 KiB; writers discard oldest buckets before exceeding the cap.
Four writes/minute are the fixed production ceiling. Writes are best-effort,
execute no PostgreSQL query, and reuse the fail-open Redis wrapper. Logs are emitted
regardless of Redis outcome.

Snapshot keys contain no user/request/race identity, payload, SQL, URL, or secret.
During PM2 overlap, old and replacement processes may share a role/instance key;
`capturedAt` and `bootStartedAt` let the reader choose the freshest valid record.
This surface is observational only and is not used for reload attestation or pool
policy decisions without matching logs/capacity artifacts.

The admin reader performs one bounded `MGET` for exactly the four expected keys,
validates every field defensively, rejects records older than 150 seconds, and
aggregates the valid current/60-minute data in memory. Redis disabled/down returns
an `unavailable` admin envelope rather than falling through to PostgreSQL. One or
more missing/stale/malformed processes returns `partial`; it never fabricates a
healthy zero.

## Step-source transaction optimization plan

Do not rewrite transaction semantics before measurement. Implement in this order,
benchmarking each independently:

1. Add the phase telemetry above and capture baseline service time and wait time for
   `/steps`, `/steps/samples`, and `/steps/sync-v2` under the replay profile.
2. Audit `readCanonicalSampleInput` before/after calls and
   `StepSample.reconcileBatchOn` to determine whether unchanged daily-only uploads
   can avoid sample watermark work without weakening repair detection.
3. Add a safe no-change path only if it still verifies scoring/queue generation
   repair. “Same daily value” alone is insufficient because a prior source commit
   may require queue repair.
4. Inspect `RaceResolutionJobV2.enqueueMany` plans and timing for the incident
   fixture. Retain atomic source-plus-queue durability and ascending race-ID lock
   order. Do not move enqueue post-commit or restore the removed advisory lock.
5. Propose an index only after `EXPLAIN (ANALYZE, BUFFERS)` on representative
   test data proves the active-membership or enqueue query needs it. Any index is an
   additive concurrent migration and a separately identified rollout operation.
6. If connection hold time remains above the gate, reuse/batch only immutable
   step/sample inputs according to the existing legacy reconciliation requirements;
   retain just-in-time effects, membership checks, scoring-version fences, and
   existing source/scoring/job atomicity and asynchronous race/box behavior.

Per-user coalescing is a later evidence gate. Add only aggregate overlap counters
in the replay harness (same-user in-flight count and duplicate payload count). Do
not log identities in production. If the distinct-user replay fails similarly,
coalescing is not the primary fix.

## API contract

No public API shape changes.

### `POST /steps`

- Existing request remains `{ "steps": int, "date": "YYYY-MM-DD", "skipRaceResolution"?: bool }`.
- Existing success remains HTTP `200` with `{ "record": ... }`.
- Existing validation/authentication behavior remains unchanged.
- No new `202`, `429`, or required idempotency header is introduced.

### `POST /steps/samples`

- Existing request and HTTP `200` response remain byte/semantically compatible.
- The existing synchronous source/scoring/durable-job commit remains atomic and the
  response remains `{ "count": int }`. Race/box resolution remains asynchronous.

### `POST /steps/sync-v2`

- Existing request, idempotency-key, success/deferred/cooldown/error, and polling
  contracts remain unchanged.
- Same-key retry and reservation semantics must remain correct across pool waits.
- Existing success continues to report `uploaderReconciliation.state="DEFERRED"`,
  `resolvedRaceCount:0`, and `boxStateCurrent:false`; this feature must not claim or
  introduce synchronous uploader/box freshness.

An acquisition failure continues to be an internal `500` until a separately
specified overload contract is approved. This feature's acceptance gate is to
eliminate that failure in the recorded supported workload, not silently relabel it.

### `GET /admin/system-health?window=60m`

Add a read-only route under the existing admin router, inheriting `requireAuth` and
`requireAdmin`. `window` is optional and only `60m` is accepted; an unsupported
value returns HTTP `400` with `{ "error": "...", "code": "INVALID_WINDOW" }`.
Unauthorized/non-admin behavior remains the router's existing `401`/`403` contract.

HTTP `200` response:

```json
{
  "schema": "admin-system-health-v1",
  "status": "available",
  "overall": "healthy",
  "generatedAt": "2026-08-29T19:30:00.000Z",
  "windowMinutes": 60,
  "expectedProcesses": 4,
  "freshProcesses": 4,
  "processes": [
    {
      "role": "http",
      "instance": "0",
      "status": "healthy",
      "capturedAt": "2026-08-29T19:29:40.000Z",
      "pool": {
        "max": 20,
        "total": 12,
        "idle": 7,
        "nonIdle": 5,
        "checkedOut": 5,
        "waiting": 0
      },
      "last60m": {
        "acquisitions": 4100,
        "queuedCheckouts": 3,
        "queuedTimeouts": 0,
        "queuedWaitP95Ms": 12,
        "queuedWaitMaxMs": 44,
        "physicalAttempts": 2,
        "physicalErrors": 0
      },
      "process": {
        "rssBytes": 410000000,
        "cpuOneCorePercent": 18.2,
        "eventLoopP99Ms": 8.4
      }
    }
  ],
  "stepIngestion": {
    "requests": 920,
    "successes": 920,
    "failures": 0,
    "queuedTimeouts": 0,
    "latencyP95Ms": 640,
    "transactionP95Ms": 310,
    "endpoints": [
      {
        "endpoint": "steps",
        "requests": 330,
        "failures": 0,
        "latencyP95Ms": 710,
        "transactionP95Ms": 340
      }
    ]
  }
}
```

`status` is `available`, `partial`, or `unavailable`; `overall` is `healthy`,
`pressure`, `degraded`, or `unknown`. `processes` contains only fresh validated
records and is ordered `http:0`, `http:1`, `resolution:0`, `cron:0`.
Missing/null/malformed numeric fields are omitted, never coerced to zero. A Redis
miss/down response is HTTP `200` with `status:"unavailable"`, `overall:"unknown"`,
empty `processes`, and zero `freshProcesses`; the admin can distinguish telemetry
absence from an API/server failure. Route-internal unexpected errors return the
existing coded admin `500` envelope.

An older backend returns route-absence `404`; the new app renders “Requires server
update” only inside `SYSTEM HEALTH`. Existing `/admin/stats` requests and response
cost remain unchanged.

## Data model and migrations

No data migration is required for role budgets, telemetry, or transaction-code
optimization.

No PostgreSQL telemetry table or migration is introduced. PostgreSQL remains
authoritative for step source rows, sample rows, scoring generations, sync-v2
idempotency reservations, and the durable resolution queue. The four short-lived
Redis operational keys are derived snapshots only, expire after 150 seconds, and
may be deleted or absent without affecting whether a step commit succeeds or is
replayable.

If the query-plan audit proves an index is necessary, amend this section with the
exact table/columns, measured plan before/after, index size, concurrent migration,
lock/rollback procedure, and old-code compatibility before implementation. No
speculative index is approved by this draft.

## Frontend plan

Add a lazily loaded `SYSTEM HEALTH` `AdminSection` to both existing Admin Tools
layouts in `lib/screens/admin_screen.dart`: the iOS metrics-dashboard branch and
the Android/legacy branch. Place it immediately before `CONFIG`, after product
metrics/revenue. It is collapsed by default and makes no request until first
expanded. The screen-level refresh action refreshes it only after it has been opened,
matching existing lazy dashboard sections; no polling timer is introduced.

Design direction follows the app's existing trail-sign/pixel-tool aesthetic rather
than introducing generic Material monitoring cards:

- A compact status plate reads `HEALTHY`, `PRESSURE`, `DEGRADED`, or `UNKNOWN` in
  text plus semantic color; color is never the only signal.
- `POOL NOW` shows four fixed process rows with role/instance, checked-out/max,
  waiting, and freshness. Missing processes read `MISSING` rather than `0`.
- `LAST 60 MIN` shows queued timeouts, queued wait p95/max, physical errors, step
  failures, step latency p95, and transaction p95. Detailed endpoint rows are
  compact and omit unavailable values rather than inventing zeros.
- Show `Updated <relative time>` and a small `REFRESH` action inside the section.
- Loading uses the existing section spinner. `partial`, `unavailable`, route-absence
  `404`, transport/`5xx`, and malformed envelopes have distinct concise messages
  and retry actions; previously good data remains visible but marked stale after a
  refresh failure.
- The section supports night/light palettes, narrow devices, text scaling, iOS,
  and Android without horizontal scrolling.

Add a dedicated defensive model, for example
`lib/models/admin_system_health.dart`. It accepts `Object?` at every boundary,
allowlists roles/statuses, bounds counts/durations, rejects duplicate process
identities, and treats absent/null/malformed/additive fields as unavailable. Add
`BackendApiService.fetchAdminSystemHealth` for the exact endpoint above; a plain
route-absence `404` is represented separately from coded domain errors.

Existing clients provide the compatibility matrix:

- frozen legacy foreground client using `/steps` then `/steps/samples`;
- frozen native iOS background client using legacy endpoints;
- current native/background and foreground clients using `sync-v2` and same-key
  retry;
- Android foreground/background paths supported by the shared Dart/native service.

The admin UI is additive and admin-only. It does not alter step-sync client behavior
and cannot repair frozen binaries. Both platforms share the same new Dart section;
the two existing admin layout branches must both include it.

## Backward compatibility and rollout

- Backend behavior remains permanent and version-compatible; no release flag.
- Deploy backend telemetry/snapshot/API support before the app carrying `SYSTEM
  HEALTH` reaches users.
- Frozen clients receive their exact existing status and response shapes.
- Old admin clients never request the new route. New admin clients against an old
  backend isolate route-absence to one “Requires server update” section; every
  other admin section remains usable.
- Production remains exactly two HTTP workers plus the existing dedicated
  resolution and cron processes.
- Staging remains stopped by default. Running a staging/capacity environment
  requires explicit in-the-moment authorization and must be shut down afterward.
- Capacity and integration tests must use only a dedicated test/disposable
  PostgreSQL database. Never run them against production.
- Production deployment, environment edits, PM2 reload, and PostgreSQL changes
  require separate explicit authorization after implementation and review.
- Rollback is the prior backend revision/config followed by a graceful one-worker-at-
  a-time reload; rollback details must preserve the two-worker topology. Pool values
  are operational capacity configuration, not a feature switch, and their owner and
  deployed values must be documented in the runbook.

## Test-first plan

### Backend integration and structural tests

Write tests before business logic:

1. Spawn role-specific processes/config readers and assert resolved defaults,
   valid overrides, unknown-role failure, invalid-value failure, and aggregate
   production-budget failure before Prisma construction.
2. Assert `application_name` contains only the expected role/instance and no URL or
   secret material.
3. Through real HTTP and real test PostgreSQL, saturate a deliberately small HTTP
   pool and prove metrics report queued checkout/timeout separately from physical
   connection attempt/timeout/error, exact acquire/release/checked-out state, and
   total/non-idle/idle/waiting without changing response bodies. Run a distinct
   unreachable/slow-PostgreSQL test so the two failure classes cannot collapse.
4. Exercise real `/steps`, `/steps/samples`, and `/steps/sync-v2` success, no-op,
   repair-required, transaction rollback, ambiguous retry, and concurrent same-user
   paths. Assert exact persisted source/scoring/queue state and existing JSON.
5. Prove an acquisition timeout commits no partial source or queue rows; a later
   retry converges exactly once.
6. Prove resolution and cron progress under concurrent HTTP load and that process
   pool totals never exceed their role maxima.
7. Assert the telemetry timer shuts down cleanly and emits no identity/payload
   fields.
8. Assert the capacity IPC census accepts exactly one fresh response per expected
   role/instance/nonce and fails on missing, duplicate, stale, or unknown identity.
9. Exercise PM2-wrapper-equivalent overlap calculations and topology snapshots for
   HTTP, resolution, cron, and a persistent orphan; unsafe steady/transient budgets
   fail before reload authorization.
10. Through real HTTP, assert `/admin/system-health` rejects unauthenticated and
    non-admin users, performs one bounded Redis multi-read and no route-owned
    PostgreSQL query, orders/aggregates four valid snapshots, and returns exact
    `available`/`partial`/`unavailable` envelopes for fresh, stale, missing,
    malformed, Redis-disabled, and Redis-error cases.
11. Assert snapshot writers cap history/count/serialized bytes, TTL every write,
    emit logs when Redis is unavailable, never include forbidden fields, and cannot
    affect a successful or failed step request.

### Capacity tests

Use the current guarded disposable capacity workflow and production-like topology.
Do not use retired harness commands or the production database.

Run three repeats for each candidate and baseline in these cohorts:

1. Normal full-app profile: 15 offered rps for 90 seconds; advance to 31 rps for
   30 seconds only if 15-rps gates pass.
2. Incident replay: reproduce the observed second-by-second shape, including the
   peak of 46 `/steps` arrivals in one second and 374 `/steps` arrivals over two
   minutes, alongside the observed non-step route mix.
3. Distinct-user replay: every step request uses a valid distinct/rotating fixture
   identity.
4. Duplicate-user replay: the same total request volume is concentrated over a
   bounded user set with repeated unchanged and increasing values.
5. Cron-overlap and resolution-backlog cohorts, separately labeled, so HTTP
   protection is not purchased by starving durable/background work.
6. Worker-skew cohort: reuse one/few persistent HTTP/1.1 connections to place at
   least 80% of step arrivals on one observed worker, then repeat with the other
   worker. A run that cannot prove its worker distribution is non-claimable.

Record pool wait histogram/failures for all four processes, PostgreSQL active/idle/
idle-in-transaction/lock waits, CPU/memory, endpoint latency/status, source commit
count, queue lag/drain, cron lateness, and final database parity.

### Frontend compatibility tests

Use existing real service/screen paths to confirm:

- legacy daily write retry remains once-after-one-second;
- failed samples remain best-effort and a later reconciliation repairs them;
- sync-v2 retries once with the identical idempotency key and payload;
- no missing/null server field behavior changes;
- iOS and Android background/foreground ownership remains accounted for.

Write real widget/service tests first for the admin addition:

- exact authenticated `GET /admin/system-health?window=60m` request;
- defensive parsing of full, partial, unavailable, missing, null, malformed,
  duplicate-process, unknown-role/status, negative/overflow, and additive payloads;
- `SYSTEM HEALTH` appears before `CONFIG` in both iOS metrics and Android/legacy
  Admin layouts, collapsed by default, and does not fetch before expansion;
- healthy, pressure, degraded, partial, unavailable, old-backend, loading, stale-
  after-refresh-failure, and retry states render distinct text;
- four process rows, missing-process labeling, 60-minute totals, endpoint details,
  freshness, inner refresh, and screen refresh behavior;
- narrow width, large text, light/night palettes, and no overflow/horizontal scroll.

## Quantitative promotion gates

The role-budget change is not an improvement unless all gates pass against the same
baseline revision/fixture/protocol:

- zero pool-acquisition timeouts and zero `5xx` at 15 rps and in all incident-replay
  repeats;
- at 31 rps, capacity failures below 1%, with no pool timeout, P2028, deadlock,
  uniqueness error, ambiguous partial write, dropped arrival, or PM2 restart;
- persistence-critical p95 below 2 seconds, p99 below 5 seconds, and no completed
  step request at or above 15 seconds;
- resolution claimable lag peaks below five seconds and drains to zero;
- aggregate application connections remain within the selected declared budget;
- no process reports `waiting > 0` for three consecutive one-second samples or for
  more than five cumulative seconds in any minute; queued-checkout wait p95 is below
  100 ms and max below one second in the incident replay;
- source, scoring generation, idempotency reservation, resolution envelope, box,
  and participant outcomes match the control exactly;
- host available memory remains at least the greater of 1.5 GiB or 20% of host
  memory; host and PostgreSQL remain below 90% of their allocated multi-core CPU,
  and each Node process remains below 90% of one logical core, for every rolling
  30-second window. The collector normalizes `process.cpuUsage()` to elapsed time
  and one logical core before applying the Node threshold;
- scheduled race expiry, global-event boundary/entitlement, notification/inbox
  delivery, cleanup, placement, and payout jobs start no later than
  `max(5 seconds, 25% of their configured interval)` after due time, complete p95
  within their configured interval, and report no overlap skip/error. Resolution
  has the separate five-second queue-lag gate above;
- for any targeted latency/wait metric with a non-zero measurable baseline, the
  median of three matched repeats improves by at least 10%; zero-baseline safety
  metrics must remain zero and are not subject to a meaningless percentage. No
  endpoint p95 regresses above 10% when it has at least 20 aggregate samples.

`capacity failure rate` is the number of distinct selected app requests having
transport status 0, an unexpected HTTP status, any `5xx`, or any `429`, divided by
all selected app requests; one request is counted once even if it satisfies multiple
categories. Expected organic statuses must be enumerated by the existing profile
and are still reported. A dropped scheduled arrival is separately required to be
zero and is not removed from evidence.

Before selecting a production budget, collect a read-only 24-hour PostgreSQL census
at one-minute resolution covering an organic peak and every daily scheduled-job
boundary. Inventory application pools plus peer mirroring, monitoring/management,
backup/migration tooling, authorized staging activity, and operator sessions. Use:

```text
usableSlots = max_connections - superuser_reserved_connections - reserved_connections
steadyAppBudget <= usableSlots - maxExternalOccupancy - 5 administrative slots
transientReloadBudget <= usableSlots - maxExternalOccupancy - 5 administrative slots
```

`maxExternalOccupancy` is the maximum observed non-primary-application occupancy,
not an average. The capacity collector's own connection counts as external. The
lazy peer pool's potential three connections count whenever `PEER_DATABASE_URL` is
configured. If the census misses a required busy/scheduled period, it must be
extended rather than extrapolated.

Run two isolated comparisons. First compare each pool policy with identical current
transaction code. Then, at the selected policy, compare each transaction
optimization with its unchanged-code control. A combined pool-plus-code result
cannot attribute improvement and cannot promote either change.

If every safe lower-pool candidate increases failures or background lag, do not
deploy a lower maximum. The evidence then directs work to transaction service time
before repeating the matrix. A lower global connection ceiling is a safety property,
not proof of higher throughput.

## Acceptance criteria and definition of done

- The selected role budgets are configurable, validated, documented, and proven
  against the real four-process topology.
- Production telemetry attributes pressure to each role/worker without personal or
  secret data and without enabling global query logging.
- Authenticated admins can read fresh/partial/unavailable current and 60-minute
  telemetry in both Admin layouts; ordinary users cannot access the API or screen.
- The recorded incident burst completes without pool timeout or incorrect write in
  the disposable production-like environment.
- Frozen legacy and current sync-v2 clients retain exact contracts and recovery
  semantics.
- The durable resolution queue drains within its gate and cron is not starved.
- Backend integration tests are written first and pass against a dedicated test DB;
  `npm run test:unit` and `npm run test:integration` are green, never bare
  `npm test`.
- Frontend real-screen/service tests pass and `flutter analyze` is clean; iOS and
  Android admin layouts are both verified.
- Architect, UI-test-planner, and code-reviewer requirements are satisfied, and the
  manual UI-placement checklist is handed to the owner.
- No work is presented as deployed without separate, immediate production approval.

## Implementation ownership and order after approval

1. **Backend contract first:** pool-policy resolver, validation, role/instance
   application name, aggregate telemetry schema, and capacity collector schema.
2. **Frontend agent in parallel after the telemetry/admin API contract locks:** add
   the defensive model/service and the same lazily loaded `SYSTEM HEALTH` section to
   both Admin layout branches, plus legacy/sync-v2 compatibility tests.
3. **Backend measurement milestone:** run the baseline/candidate matrix in the
   authorized disposable capacity environment.
4. **Backend optimization milestone:** implement only phase-proven transaction
   reductions, with new failing public-path integration tests first.
5. **Review:** code reviewer checks the combined diff, evidence artifacts, version
   skew, and whether the chosen budgets actually improved failure/latency without
   starving background work.

The pool-policy capability can be benchmarked with run-bound capacity environment
overrides before production defaults are finalized. The implementation is not done
until the winning measured values become committed safe defaults and the production
runbook names the environment override owner. Leaving production on an
oversubscribed implicit default while claiming the feature is complete is forbidden.

### Exact implementation seams

Backend repository:

- `src/db.js`: consume the resolved policy, construct `pg.Pool`, set bounded
  `application_name`, collect acquisition statistics, and expose snapshots.
- `src/shared/config/databasePoolPolicy.js` (new): parse/validate per-role values,
  steady/reload aggregate constraints, production unknown-role failure, and safe
  local/capacity behavior. Keep generic production policy out of
  `localCapacitySafety.js` except for its existing capacity-target checks.
- `ecosystem.config.js`: retain exactly two HTTP instances and the dedicated
  resolution/cron roles; document resolved defaults, but do not place secrets or a
  second conflicting source of numeric truth here.
- `src/shared/observability/databasePoolMetrics.js` (new), Redis snapshot adapter,
  and `src/index.js`: bounded aggregate emission/snapshot plus graceful start/stop
  ownership for every role.
- `src/modules/steps/services/stepInputIntake.js` and its existing model/service
  collaborators: phase measurement and only benchmark-proven transaction changes.
- `src/modules/steps/commands/recordStepSyncV2.js`, legacy step commands, step
  routes, and the authentication/request-context seam: per-attempt and whole-request
  attribution across outer transactions, retries, finalization, and post-commit
  work.
- `scripts/capacity-metrics.js`, `src/modules/loadTesting/*`, and
  `docs/capacity-load-runbook.md`: all-process collection, incident replay,
  candidate matrix, provenance, and interpretation rules.
- `test/integration/` plus focused startup/observability suites: public-path
  correctness, saturation, policy validation, and metric privacy.
- `src/modules/admin/routes.js` plus an admin system-health query/service: exact
  admin-only Redis aggregation contract; no raw SQL or PostgreSQL fallback.

Frontend repository:

- `lib/services/backend_api_service.dart`: additive admin system-health read.
- `lib/models/admin_system_health.dart` (new): defensive projection.
- `lib/screens/admin_screen.dart` plus a focused reusable section body/widget: one
  placement shared by both existing Admin layout branches.
- `lib/screens/main_shell.dart` and `ios/Runner/AppDelegate.swift` remain audit/test
  targets for retry compatibility; do not introduce a second sync implementation.

## Open questions for owner interview

None currently. The specification deliberately makes the final numeric split an
evidence outcome and requires a separate authorization before starting any
staging/capacity environment or production operation.

## Revision log

- **2026-08-29 — Draft 1:** Incorporated the production incident, distinguished
  the pre-transaction pg-pool wait queue from the existing durable resolution
  queue, defined role-specific configuration and privacy-safe telemetry, and made
  pool reduction conditional on a like-for-like burst replay rather than treating
  fewer connections as automatic throughput improvement.
- **2026-08-29 — Gap pass 1 (architecture/operations):** Added authentication-path
  demand, exact code ownership seams, fresh system-connection census requirements,
  and a separate rolling-reload budget so transient old/new PM2 overlap cannot
  exceed the connection envelope.
- **2026-08-29 — Gap pass 2 (measurement/compatibility):** Separated this incident
  contract from older flag-based capacity proposals, froze acquisition/idle
  timeouts for attributable comparison, made failure counters unsampled and
  query-free, and required measured values to become committed permanent defaults
  before completion.
- **2026-08-29 — Architecture review:** Defined runtime/override precedence and
  prohibited production role ambiguity; covered HTTP, resolution, and cron reload
  overlap/orphans; separated queued checkout from physical connection failures;
  expanded telemetry across sync-v2's outer transaction and authentication;
  required deterministic all-process IPC plus worker-skew replay; made promotion
  formulas and operational gates executable; and corrected legacy/sync-v2
  invariants to asynchronous race/box resolution with atomic source/scoring/job
  commit.
- **2026-08-29 — Architecture re-review:** Restored the dependency-specific queued-
  checkout diagnosis, corrected production role/port classification, moved candidate
  generation after the external-connection census because the initial splits could
  not satisfy reload headroom, and normalized the CPU gate explicitly.
- **2026-08-29 — Owner scope revision:** Narrowed implementation authority to
  telemetry first while adding an admin-visible `SYSTEM HEALTH` surface. Added
  short-lived non-authoritative Redis snapshots, exact admin API/UI states, both
  existing Admin layout branches, defensive parsing, admin authorization, and
  backend-first old-server degradation. Pool sizing and transaction optimization
  remain later owner decisions after telemetry.
