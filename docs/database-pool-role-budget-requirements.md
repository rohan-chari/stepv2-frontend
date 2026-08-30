# Role-aware database pool budgets

**Status:** proposed; awaiting approval. No backend, environment, staging, or
production change is authorized by this document.

## Summary and operator story

The backend currently creates the same `pg.Pool({ max: 20 })` in every process.
Production runs two HTTP processes plus one resolution process and one cron
process, so application demand can reach 80 connections even though PostgreSQL
reports 50 total connections and reserves 3 for superusers. During the
2026-08-29 incident, HTTP requests exhausted pool capacity and produced
connection-checkout timeouts and Prisma `P2028` errors while host CPU and memory
remained healthy.

As the production operator, I need each process role's pool ceiling to be
configured through environment variables, validated before serving traffic,
and visible in health/telemetry output so the four processes share a deliberate
database budget instead of independently assuming they each own 20 connections.

## Current evidence and touched surfaces

- `stepv2-backend/src/localCapacitySafety.js:43-54` returns 20 in every normal
  runtime. The existing `DB_POOL_MAX` is intentionally honored only by a
  validated, non-production capacity environment and must keep that contract.
- `stepv2-backend/src/db.js:44-64` resolves that value once and passes it to
  `pg.Pool`; checkout timeout is 5 seconds.
- `stepv2-backend/ecosystem.config.js:62-101` defines two `http` instances, one
  `resolution`, one `cron`, and a stopped-by-default staging `all` process.
- Live production inspection on 2026-08-29 confirmed all four processes have
  no pool override, PostgreSQL `max_connections=50`,
  `superuser_reserved_connections=3`, and 33-40 observed application database
  sessions during the investigation.
- The DigitalOcean endpoint is the managed pooler on port 25061. Its current
  control-plane pool size is not exposed by the host's SQL credentials, so the
  rollout must verify it in the DigitalOcean control plane rather than infer it
  from `SHOW max_connections`.
- `stepv2-backend/src/db.js` and adjacent observability files already contain
  unrelated, uncommitted telemetry work. Implementation must preserve and build
  on those edits rather than replace or revert them.

## Functional contract

### Environment variables

Add these runtime configuration variables:

| Variable | Applies to `STEPS_PROCESS_ROLE` | Production target | Unset behavior |
|---|---|---:|---|
| `DATABASE_POOL_MAX_HTTP` | `http` | 10 per process | fall through |
| `DATABASE_POOL_MAX_RESOLUTION` | `resolution` | 8 | fall through |
| `DATABASE_POOL_MAX_CRON` | `cron` | 4 | fall through |
| `DATABASE_POOL_MAX_ALL` | `all` | staging-specific, initially 10 | fall through |
| `DATABASE_POOL_MAX_DEFAULT` | non-production role without its own value | unset in production | 20 |
| `DATABASE_POOL_TOTAL_BUDGET` | topology validation only | 32 | no aggregate enforcement outside production |

Outside production, resolution order is role-specific value, then
`DATABASE_POOL_MAX_DEFAULT`, then the compatibility default of 20. Production
requires a known role and its exact role-specific variable; it may not fall
through to the generic/default value. These are capacity settings, not feature
flags, rollout toggles, or kill switches.

Every supplied value must be a canonical base-10 integer from 1 through 50.
Empty, signed, decimal, hexadecimal, whitespace-padded, zero, negative, or
out-of-range values fail process startup with an error that names the variable
but prints no database URL or credential. The resolver itself must fail before
opening a listener when production has a missing/unknown `STEPS_PROCESS_ROLE`
or lacks that role's variable. The known `all` role is permitted for staging;
missing/unknown roles retain the default-20 fallback only for non-production
local/test entrypoints.

The existing capacity-only `DB_POOL_MAX` retains its current name, validation,
and isolation rules. It takes precedence only when the existing validated
`CAPACITY_MODE` path is active. Production must never be able to enable that
path or use `DB_POOL_MAX` as an alias for the new variables. The final contract
described here is deployment B; deployment A's versioned missing-variable
compatibility exception exists only to establish a safe code-first transition.

### Aggregate budget invariant

Extend the existing PM2 topology/live-config guard so production validation
calculates:

`HTTP instances × HTTP max + resolution instances × resolution max + cron instances × cron max`

The guard has three explicit modes rather than applying one strict rule during
a rolling transition:

1. **Static preflight:** before any reload, validate the new ecosystem file's
   topology, role variables, and `2 × 10 + 1 × 8 + 1 × 4 = 32` arithmetic.
2. **Role-scoped transition:** after each role reload, require all new PIDs for
   that role to match the ecosystem value and allow only the documented legacy
   value 20 for roles not yet reloaded. Reject every other mixed state.
3. **Final strict:** after cron, resolution, and both HTTP PIDs have transitioned,
   require every live production PID to match the ecosystem source of truth and
   require the live aggregate to equal `DATABASE_POOL_TOTAL_BUDGET` before
   `pm2 save`.

The initial committed production topology is 32. Strict verification fails
when that total differs, a required role-specific value is absent, or any final
live process environment differs from source of truth.
The guard must not restart or rewrite healthy processes merely because the
DigitalOcean control plane cannot be queried; control-plane verification is a
manual deploy prerequisite.

Staging remains stopped by default and is excluded from the production total.
If explicitly authorized for a load test, its `all` role uses
`DATABASE_POOL_MAX_ALL` and its pooler budget is verified independently.

### Runtime observability

- `getDbPoolPressure().max` and the existing/new database-pool telemetry must
  report the resolved role-specific maximum.
- On successful startup, each process logs one structured, non-secret record
  containing role, PM2 instance, resolved maximum, and source variable name. It
  must not log `DATABASE_URL`. No separate aggregate-budget version is needed;
  the committed `DATABASE_POOL_TOTAL_BUDGET` value is the source of truth.
- The admin system-health representation, if the in-progress telemetry work
  lands first, exposes each process snapshot's role and resolved maximum. This
  is additive and admin-only.

## API contract

There is no public API request or response change. All existing routes, status
codes, bodies, authentication, and retry/idempotency semantics remain unchanged.
No mobile client needs to know the database pool size.

Ordinary public `/health` remains unchanged. The in-progress authenticated
`/admin/system-health` contract already returns `processes[]` entries with
`role`, `instance`, and `pool.max`; the only optional additive field is
`processes[].pool.configSource`:

```json
{
  "processes": [{
    "role": "http",
    "instance": "0",
    "pool": {
      "max": 10,
      "configSource": "DATABASE_POOL_MAX_HTTP"
    }
  }]
}
```

Older admin callers ignore these fields. Missing telemetry must continue to
degrade to the existing unavailable/null representation rather than fail the
health endpoint.

## Data model and migrations

No table, column, index, migration, backfill, seed, or production data write is
required. Environment configuration is read once during process startup; a
change requires the existing safe PM2 reload workflow. Role limits remain
environment/source-controlled configuration. Redis may contain only rebuildable
telemetry observations, continues to fail open, and is not a configuration
authority.

## Backend implementation plan

1. Write failing tests for parsing, precedence, role mapping, capacity-mode
   isolation, startup failure, and aggregate topology validation.
2. Add a small pure configuration module, for example
   `src/shared/config/databasePoolConfig.js`. It accepts an injected environment
   and returns `{ role, max, source }`; it does not read files or connect to the
   database.
3. Preserve the existing `capacityDatabasePoolMax` contract. In `src/db.js`,
   use it only for validated capacity mode; otherwise use the new role-aware
   resolver.
4. Pass the resolved maximum unchanged into `pg.Pool` and existing pool
   telemetry. Do not change `idleTimeoutMillis`, `connectionTimeoutMillis`, SSL,
   Prisma adapter behavior, transaction timeouts, or endpoint behavior in this
   change.
5. Put the production role values and total budget in
   `ecosystem.config.js`, not only in the mutable server `.env`, so every safe
   reload reapplies the reviewed source of truth. Permit `.env` configuration
   for non-PM2/local deployments through the same resolver.
6. Extend `scripts/pm2-topology-guard.js` and its protected tests to validate
   role values, aggregate total, and the static/role-scoped/final modes. Update
   `scripts/pm2-safe-prod-reload.sh` to invoke those modes in the specified
   order. Keep exactly two HTTP workers.
7. Document every variable and example in `.env.example`, `DEPLOYMENT.md`, and
   `DEPLOY_RUNBOOK.md`, including the arithmetic, DigitalOcean pooler check, SQL
   connection census, rollback, and the fact that a lower pool is containment
   rather than a throughput optimization. Reconcile the runbook's stale claim
   that staging runs two workers with the committed stopped, one-process
   staging topology.
8. Integrate with the uncommitted pool telemetry work carefully; no unrelated
   edit may be reverted, reformatted wholesale, or claimed as part of this
   feature.
9. Update the protected disposable capacity harness so its role children use
   capacity-only `DB_POOL_MAX` values 10/10/8/4. Do not weaken `CAPACITY_MODE`
   database/target isolation or make the production variables active there.

## Frontend plan

No Flutter, iOS, Android, screen, widget, service, model, asset, or app build
change is required. Frozen older clients continue sending the same requests and
receiving the same response shapes. Both platforms are accounted for by the
unchanged public API contract.

## Tests-first plan

Add the tests before production logic and confirm they fail for the expected
missing behavior.

1. Unit tests for every known role, role-specific precedence, default fallback,
   capacity-mode precedence, unset variables, and every malformed boundary.
2. Startup subprocess tests proving invalid values and production
   missing/unknown roles exit nonzero before opening a listener and never print
   secrets.
3. PM2 topology-guard tests proving `2×10 + 8 + 4 = 32`, static preflight,
   every allowed intermediate role transition, final strict state, and rejection
   of a missing role value, mismatched total, unexpected mixed state, extra HTTP
   worker, or included stopped staging.
4. An integration test using dedicated local/test Postgres and Redis db15 that
   starts one process per role and asserts authenticated `/admin/system-health`
   reports `processes[].role`, `pool.max`, and `pool.configSource`. Confirm
   `DATABASE_URL` names the test database before running. If the admin telemetry
   work has not landed, use direct `db.js` subprocess inspection as a structural
   test and do not invent a public endpoint.
5. Existing backend unit and relevant integration suites. Never run bare
   `npm test` and never run an integration test against production.
6. Production-shaped disposable capacity verification, only after explicit
   authorization, using updated capacity-only values 10/10/8/4. Run an
   identical legacy-20 baseline and candidate against infrastructure matching
   the verified managed-pool mode/size. Compare per-endpoint latency/errors,
   resolution throughput/lag, and cron completion—not only aggregate p95. The
   ordinary stopped staging `all` process is not a substitute for this topology.

## Rollout and rollback

1. Before implementation, record the current DigitalOcean pool configuration
   from the control plane: pool mode, pool size, reserve size if any, and direct
   database maximum. Do not guess from SQL session counts.
2. **Production deployment A, with fresh authorization:** land the resolver,
   tests, observability, guard modes, and reload-wrapper support while leaving
   production role variables absent and retaining the legacy 20 behavior for
   this specifically versioned transition. Verify all roles remain at 20. This
   compatibility allowance exists only in deployment-A code and must be removed
   by deployment B; it is a versioned rollout state, not a runtime flag.
3. With explicit staging/capacity-environment authorization, configure the
   isolated role-shaped harness and staging's separate `all` budget,
   start it, verify startup/telemetry, run the isolated production-shaped load
   protocol, and shut staging down afterward.
4. Require zero checkout timeouts, zero new `P2028` errors, zero deadlocks, less
   than 1% hard failures, overall p95 below 2 seconds, p99 below 5 seconds, and
   resolution backlog returned to zero before approving production values.
5. **Production deployment B, with separate fresh authorization:** commit the
   reviewed ecosystem values and remove deployment A's production default
   allowance. Run static preflight, then transition background roles before
   HTTP: resolution to 8, cron to 4, then roll the two HTTP workers to 10 one at
   a time. After each role, wait for the old PID to exit and run the role-scoped
   guard. Run final strict verification before `pm2 save`; do not change worker
   count.
6. During deployment B, calculate and record worst-case configured overlap.
   With the old 20/20/20/20 state, a zero-downtime resolution replacement can
   briefly expose 88 configured slots (80 old plus the new 8); after it drains,
   cron overlap is 72; after both background roles drain, an HTTP replacement
   overlap is 62. The wrapper must serialize roles, wait for old PIDs to exit,
   and never begin the next role while the previous overlap remains. Actual
   checked-out/server connections must stay below the verified managed-pool and
   PostgreSQL limits; otherwise stop the rollout without `pm2 save`.
7. Observe at least 30 minutes including a normal step-sync burst: nginx
   latency/status buckets, pool waiting/checkout failures, P2028s, resolution
   queue lag, cron completion, DB sessions, CPU, and memory.
8. Roll back by restoring the last known-good reviewed pool values and using the
   same safe rolling reload. Do not use a runtime kill switch, add workers, start
   staging, or increase database capacity as an implicit rollback.

## Backward compatibility

- Old and new app binaries see an unchanged HTTP contract.
- Deployment A preserves 20 through a versioned compatibility path. Deployment
  B removes that production allowance and requires every production role value;
  its guard tolerates only the explicitly ordered old/new PID transition before
  final strict verification.
- New backend code with unset variables preserves 20 only for non-production
  local/test environments, so developer entrypoints do not silently change.
- No flag, percentage rollout, temporary toggle, or client version branch is
  introduced.

## Non-goals

- Increasing PostgreSQL or DigitalOcean pool size.
- Changing the fixed two-worker production HTTP topology.
- Changing checkout or transaction timeouts.
- Making writes fire-and-forget, adding request shedding, or changing retry
  semantics.
- Optimizing `/steps/samples`; that remains a separate throughput change.
- Deploying, restarting, starting staging, or writing production data as part
  of specification approval.

## Acceptance criteria

- Every process role resolves its documented environment value and exposes it
  through non-secret telemetry.
- Production's validated application ceiling is exactly 32 with two HTTP
  workers, one resolution worker, and one cron worker.
- Missing configuration preserves the legacy value 20 outside the committed
  production ecosystem; production missing/unknown roles and malformed supplied
  configuration fail closed before listening.
- Capacity-only `DB_POOL_MAX` cannot affect production.
- Existing HTTP/API behavior and frozen mobile clients remain compatible.
- Tests are written first and pass; backend unit and relevant integration suites
  pass; no existing assertion is weakened.
- The architect and post-implementation code reviewer report no unresolved
  required findings.
- No production action occurs without fresh authorization.

## Revision log

- **Draft:** separated role-specific limits from the existing capacity-only
  `DB_POOL_MAX`; selected 10/10/8/4 and a 32-connection aggregate budget; kept
  unset compatibility at 20.
- **Gap pass 1:** added managed-pool control-plane verification, aggregate PM2
  validation, staging exclusion, strict parsing, and explicit preservation of
  the dirty telemetry worktree.
- **Gap pass 2:** added old/new rolling-overlap behavior, fail-safe rollback,
  non-secret startup evidence, integration-test database protection, and
  explicit non-goals for timeouts, request shedding, and step-path optimization.
- **Architect review:** split rollout into separately authorized code and value
  deployments; added static, role-scoped, and final guard modes; made production
  roles fail closed; corrected observability to the existing admin
  `processes[]` contract; updated the protected capacity harness plan; and
  calculated serialized rolling-overlap ceilings.
- **Post-review gap pass:** clarified that deployment B is the final fail-closed
  contract, kept configuration out of Redis, and added correction of stale
  staging-topology runbook text.
