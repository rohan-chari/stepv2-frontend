# Infrastructure Load-Testing Harness — Requirements

**Status:** Approved for implementation  
**Owner:** Rohan  
**Scope owner:** Backend performance tooling; this frontend repository stores the cross-repo requirements.

## Summary & user story

As the infrastructure owner, I need a repeatable way to create simulated users,
drive realistic authenticated traffic across the Home, Races, and Race Details
request flows, and identify the throughput/latency limit of the API, database,
Redis, queue, and host before a release or capacity change.

The first deliverable is a command-line load runner in the backend repository,
executed against a disposable capacity VM that mirrors the production VPS and
uses a separately provisioned PostgreSQL instance with a scrubbed production
backup. The environment must be snapshot-based so an operator can restore,
start, test, export, and destroy it within minutes.
It must produce machine-readable and human-readable results, stop safely when
the target is unhealthy, and make it difficult to target production by mistake.

## Current-state evidence

- The backend already has a sequential `/races` benchmark in
  `scripts/perf/benchmark.js` and fixture generation in
  `scripts/perf/generateFixtures.js`; these measure query/response improvements,
  not concurrent users or an HTTP capacity ceiling.
- Existing fixture generation refuses non-local databases unless
  `PERF_STAGING_OK=true`; the new runner must preserve and strengthen that
  boundary.
- `docs/scaling-capacity-plan-v2.md` explicitly says load tests must not target
  production and identifies staging as the safe measured environment.
- Staging is shut down by default per the frontend and backend agent contracts;
  it is not part of this v1 workflow.

## Scope / non-goals

### In scope

- A backend-repository CLI load runner, preferably with no production runtime
  code or app build changes.
- A disposable capacity VM image/snapshot with the same relevant VPS shape (CPU, RAM, disk,
  OS/runtime, PM2 worker count, reverse proxy, and network topology) and a
  separately provisioned PostgreSQL instance with the same relevant database
  shape/configuration.
- A documented production-backup clone workflow that scrubs all externally
  meaningful identity, authentication, notification, and secret material
  before the clone is reachable by the load generator.
- Deterministic synthetic identities/fixtures and isolated run tagging layered
  on top of the scrubbed baseline.
- Configurable virtual-user count, arrival rate or concurrency, duration,
  warm-up, endpoint mix, request timeout, and stop thresholds.
- Authenticated HTTP traffic against existing public endpoints, including
  screen-specific profiles and disposable write profiles.
- Per-endpoint request count, status classes, error rate, latency p50/p95/p99,
  throughput, timeouts, and run metadata (target, commit, profile, parameters).
- A preflight that proves the target is the approved capacity VM, verifies the
  test database is not production, validates the scrub attestation, and checks
  health.
- A dry-run mode that prints the planned request mix without sending traffic.

### Non-goals

- Any new app screen, Flutter dependency, app API endpoint, migration, or
  production feature flag.
- Running against production, the production database, or real user accounts.
- Making an un-scrubbed production backup available on the capacity VM.
- Testing third-party providers (Apple, Google, Firebase, APNs, AdMob) by
  default.
- Fuzzing, credential attacks, bypassing rate limits, or unbounded traffic.
- Making the load runner a permanent background service or CI job that can
  unexpectedly generate traffic.
- Building a dashboard, control plane, long-lived test cluster, or multi-
  environment orchestrator in v1.

## Capacity replica and data-clone workflow

The capacity VM is the system under test. It runs the selected backend commit
(initially `main`) with production-equivalent runtime settings, but it has
separate credentials, domains, queues, Redis namespace, storage, notification
sinks, and database credentials. It must not share a writable database, Redis
namespace, object-storage bucket, or provider credentials with production.

The clone workflow is intentionally short and snapshot-oriented. V1 uses a
pre-verified scrubbed snapshot plus a thin capacity wrapper; automated
production-backup refresh, cloud provisioning, and orchestration are out of
scope.

1. Build a golden capacity image and scrubbed database snapshot once from an approved,
   documented infrastructure specification; record CPU/RAM/disk/PostgreSQL/
   Redis/PM2/reverse-proxy settings in the image manifest.
2. Take a production database backup using the approved backup mechanism, or
   refresh the golden scrubbed snapshot when data freshness is required. The
   backup remains protected and inaccessible to the load generator during
   transfer and restore.
3. Restore into the isolated PostgreSQL instance and run the tested scrub
   transaction/script while the application is stopped. A repeat run may
   restore the verified scrubbed snapshot; it must not use a raw production
   restore as a shortcut.
4. Scrub at minimum: device/APNs/FCM tokens, Apple and Google identity values,
   emails, display names, profile photo references, session/auth tokens, ad or
   SSV identifiers, referral/IP-derived identifiers, notification delivery
   data, provider credentials, webhook secrets, and free-text fields that can
   contain personal data. Preserve only the distributions and relational
   shapes needed for capacity testing.
5. Verify with structural queries that no production secret/token pattern,
   provider endpoint, real identity domain, or unsanitized externally routable
   identifier remains. The verification must fail closed.
6. Create a signed scrub attestation tied to the exact database snapshot hash,
   scrub-script hash, verification result, expiry, and baseline row-count/
   checksum manifest. Record the attestation in the existing capacity safety
   marker before the application can start.
7. Configure the capacity VM with clone-only secrets and inert sinks for email,
   push, webhooks, ads, and other external side effects. Start the application
   only after scrub verification passes.
8. Start the capacity VM, generate additional synthetic users/races under a
   unique run namespace, and run the load profile.
9. Export the report and infrastructure metrics, stop the VM, and destroy the
   VM and database. The next run restores the golden image/scrubbed database
   snapshot rather than repairing the previous run in place.

The original backup must have a short, documented retention period and access
control. It must never be committed, copied into the frontend workspace, or
left on the capacity VM after restore. Scrubbing device tokens alone is not a
valid release gate.

The clone is a capacity approximation, not proof of production safety: record
any differences in kernel, disk class, network path, managed services, data
volume, background jobs, and secrets/providers, and include them in every
report.

### Lifecycle commands

The wrapper exposes only these idempotent operations:

```text
capacity preflight --snapshot <verified-snapshot> --profile full-app
capacity restore --run-id <id>
capacity start --run-id <id>
capacity status --run-id <id>
capacity stop --run-id <id>
capacity destroy --run-id <id>
```

Each run has a state (`verified → restored → started → stopped → destroyed`),
an exclusive run lock, bounded operation timeouts, and a cleanup path after
SIGINT/SIGTERM. `destroy` is the normal terminal action and is safe to repeat.
The operator can run `status` without starting the application. Before every
`start`, the wrapper prints the complete approved VPS-equivalent manifest and
requires fresh interactive confirmation. The confirmation includes CPU count,
RAM, disk class/size, OS/runtime, PM2 worker count, reverse-proxy settings,
database engine/version, PostgreSQL instance vCPU/RAM/disk/IOPS/storage,
PostgreSQL pool size/max-connections/shared-buffers/work-memory, database name,
snapshot identity and migration/schema state, Redis version/config/namespace,
network placement, backend commit, and expected queue
worker/scheduler topology. It then probes the live environment and refuses to
start if any measured value differs from the approved manifest or if the scrub
attestation is missing/expired. There is no `--yes` bypass for this start
confirmation. The target must meet the “within minutes” startup objective
using the prebuilt image and snapshot; the measured restore/start time is
recorded in the report.

## Proposed operator interface

The backend package should expose commands along these lines (names are
provisional until architect review):

```text
npm run load:preflight -- --target capacity-vm --profile smoke
npm run load:run -- --target capacity-vm --profile full-app --users 25 --duration 5m --confirm-capacity-vm
npm run load:report -- --input results/<run-id>.json
```

The runner must reject production-looking URLs/hostnames, production database
names, missing target declarations, capacity-VM runs without an explicit
`--confirm-capacity-vm`, and any target whose scrub-verification attestation is
missing or stale. It must also reject unsafe combinations such as a write
profile without an isolated run namespace and a bounded cleanup plan.

The runner must not accept arbitrary JavaScript as a profile. Profiles are
versioned, reviewed code/config entries with bounded endpoint weights and
payload sizes.

## Profiles and request behavior

Initial profiles (the same names must appear in the CLI and result schema):

1. **smoke** — 1–2 users, short duration, health plus representative reads;
   validates that the harness and fixture identities work.
2. **home** — the authenticated requests made by the Home screen, including
   step-sync/refresh behavior where applicable.
3. **races** — the authenticated requests made by the Races screen.
4. **race-details** — the authenticated requests made by Race Details,
   including progress, messages, powerup/inventory reads, and other heavy
   detail requests.
5. **full-app** — a weighted mixture of Home, Races, and Race Details flows,
   plus step sync and queue pressure. This is the primary capacity profile.
6. **contention** — bounded concurrent requests aimed at known write/contention
   paths, using generated fixtures only; disposable writes are allowed on the
   isolated dummy database, but no external-provider side effects.

The operator can increase users, concurrency, and request rate between runs
without changing code. Each run still has explicit operator-supplied bounds
and a circuit breaker.

Each profile is a reviewed method/path matrix, not a vague screen simulation.
The matrix records method, exact path/template, headers, payload shape,
preconditions, allowed statuses, weight, client persona, and whether the
request is read-only or disposable-write. It must include:

- Home sync → race-card → races → friends/me fan-out.
- Races discovery and its fallback path.
- Race Details bootstrap, legacy progress, message-stream polling, inventory,
  and heavy race/powerup reads.
- Current-client `POST /steps/sync-v2` and frozen-client `/steps` plus
  `/steps/samples`, with realistic sample windows and payload sizes.
- Queue result polling through `GET /steps/race-resolution/:jobId` where the
  flow produces a job.

The full-app profile mixes these three screen flows and step/queue traffic.
The runner records the exact profile version so results remain comparable.
Queue pressure targets the durable PostgreSQL queue, never Redis. It defines
arrival rate, payload distribution, retry/same-key behavior, worker service
rate, queue-lag threshold, and drain criteria. Arrivals stop before the drain
phase; the report separates request latency from queue drain time.

Redis is disposable derived cache only, never queue or source of truth. The
capacity VM uses an isolated run-prefixed Redis namespace. The same profile is
run with Redis configured and with `REDIS_URL` unset when validating fallback
behavior, recording cache hits/misses, memory, evictions, invalidations, and
the fallback mode.

Each simulated user has its own generated identity and session token. Requests
must use a per-run correlation header and a stable synthetic-user marker that
the backend logs can recognize without logging secrets or personal data. The
runner must honor server rate-limit responses and must not retry non-idempotent
writes automatically.

## Results contract

The runner writes one JSON document and one concise text summary per run. The
JSON top-level shape is:

```json
{
  "schema": "load-test-result-v1",
  "runId": "string",
  "target": "capacity-vm",
  "baseUrl": "redacted-or-approved-host",
  "commit": "full git sha or null",
  "profile": "smoke|home|races|race-details|full-app|contention",
  "startedAt": "ISO-8601",
  "endedAt": "ISO-8601",
  "parameters": {
    "users": 25,
    "arrivalRatePerSecond": 10,
    "durationSeconds": 300,
    "timeoutMs": 5000
  },
  "summary": {
    "requests": 0,
    "throughputPerSecond": 0,
    "errorRate": 0,
    "latencyMs": {"p50": 0, "p95": 0, "p99": 0},
    "stopReason": "completed|threshold|operator|error"
  },
  "personas": {"legacy": 0, "current": 0},
  "queue": {"enqueued": 0, "completed": 0, "lagMs": {"p95": 0}, "drainSeconds": 0},
  "infrastructure": {"cpu": {}, "memory": {}, "db": {}, "redis": {}},
  "endpoints": {
    "GET /health": {
      "requests": 0,
      "status": {"2xx": 0, "4xx": 0, "5xx": 0, "timeout": 0},
      "latencyMs": {"p50": 0, "p95": 0, "p99": 0}
    }
  },
  "safety": {"targetConfirmed": true, "databaseCheck": "scrub-attested", "snapshotHash": "string", "scrubAttestationHash": "string"}
}
```

No access tokens, cookies, email addresses, response bodies, or raw request
payloads may be written to results. The text report must call out the offered
load, achieved load, saturation/stop reason, and the endpoint responsible for
the worst p95 and error rate.

## Safety and cleanup

- Local runs require a database whose URL is localhost/loopback and whose
  database name clearly identifies a test database.
- Capacity-VM runs require an explicit target and confirmation. The runner must
  never infer a safe target from a URL alone.
- Production-like hostnames, production database names, and unset/ambiguous
  database URLs fail closed.
- Generated users, races, samples, and other rows carry a unique run namespace.
  Cleanup runs in a finally block and is idempotent; a separate explicit
  cleanup command handles interrupted runs.
- Before any write-profile run, the operator sees the target, profile, user
  count, duration, and expected request volume and must confirm.
- A circuit breaker stops new requests when configurable defaults are crossed:
  sustained 5xx rate, timeout rate, target health failure, or runaway achieved
  request rate. Thresholds are CLI parameters bounded by safe maxima.
- The runner uses one bounded worker pool and graceful SIGINT/SIGTERM shutdown.
- The capacity VM must be network-restricted to the load generator/operator
  access path; it must not be publicly discoverable or able to call production
  provider endpoints.

## Synthetic write boundary and integrity

Write traffic is allowed only against generated users/races created for the
current run. The run has a synthetic root record/manifest, explicit endpoint
allowlist, deterministic idempotency/refIds where the endpoint supports them,
and a complete dependent-row ID manifest. Cleanup is transactional and
foreign-key ordered; it proves baseline row counts/checksums are unchanged
before the VM is destroyed. The runner must never mutate scrubbed baseline
users or races. Any endpoint without a safe synthetic fixture or cleanup path
is read-only/excluded from the profile.

## Runtime topology

Capacity mode must explicitly select which workers and schedulers run. The
resolution worker and queue drain behavior are part of the test; unrelated
cron jobs and provider delivery are disabled or redirected to inert sinks.
The report records PM2 worker count, `NODE_APP_INSTANCE` behavior, Redis mode,
database pool size, and queue worker configuration. The harness must verify
that exactly the intended capacity workers are live before traffic begins.

## API contract

No public API endpoint is added or changed. The runner consumes existing public
HTTP contracts exactly as an app client does. Every profile entry must document
the method, path template, required auth, generated fixture prerequisites,
allowed status codes, and whether it is read-only or disposable-write.

Because there is no API change, frozen iOS and Android clients are unaffected;
there is no new field, endpoint, migration, release flag, or app rollout. The
load test nevertheless includes legacy and current personas concurrently:
legacy headers/routes and current additive routes use separate generated
identities, and the report breaks metrics down by persona. If a profile
encounters a missing optional response field, it records the response
status/latency and continues without assuming the field exists.

## Data model / migrations

No schema migration. Run metadata and results are local files. Generated test
rows reuse existing models and are identified by a run namespace; cleanup must
use exact recorded IDs or an unambiguous namespace predicate and must never
touch non-synthetic rows.

## Implementation path

1. In the backend repository, inspect the public route registry and existing
   integration-test fixture helpers; define the reviewed profile registry and
   safety guard first.
2. Add tests first for target rejection, capacity-VM confirmation, snapshot/
   scrub-attestation validation, test-database rejection, bounded parameters,
   redacted output, no retry on writes, graceful stop, cleanup-after-failure,
   baseline-integrity checks, and result aggregation.
3. Implement the fixture lifecycle and synthetic-user/session creation through
   public HTTP setup paths where practical; otherwise use the existing fixture
   generator only for disposable test data and keep the HTTP request phase
   authoritative.
4. Implement the bounded scheduler, exact screen/step/queue profiles,
   per-request metrics, circuit breaker, queue drain, and SIGINT/SIGTERM
   handling.
5. Add the smoke profile and local end-to-end run; then add Home, Races,
   Race Details, full-app, and contention profiles one at a time with measured
   request weights.
6. Document capacity-VM operations, including provisioning from the exact VPS
   specification, production-backup handling, scrub verification, explicit
   start/stop authorization, monitoring commands, result interpretation, and
   cleanup/retention verification.
7. Run backend unit tests, integration tests only against the dedicated
   integration database, a local smoke run, and an authorized capacity-VM run.
   Never run a load test against production.

## Test plan (tests first)

- Unit tests for URL/database safety classification and parameter bounds.
- Unit tests for profile validation and weighted scheduling determinism.
- Unit tests for percentile/status aggregation and schema-versioned redaction.
- Integration test against local test Postgres and a real HTTP server proving
  generated users are isolated, writes are bounded, and cleanup is idempotent.
- Integration test that kills the runner mid-run and verifies the cleanup
  command removes only that run's synthetic rows.
- Integration tests with local Redis `db15` and with `REDIS_URL` unset,
  proving the cache fallback contract and isolation.
- Integration tests for scrub canaries, snapshot-attestation expiry, lifecycle
  interruption during restore/start/stop/destroy, baseline checksums, queue
  drain, and intended two-worker `NODE_APP_INSTANCE` behavior.
- Real-HTTP mixed-persona tests using legacy and current request profiles.
- HTTP smoke run against a local server with a fixed low request budget.
- Capacity-VM run checklist: preflight and scrub attestation, monitor API/DB/
  Redis/host, run one profile, collect report, verify cleanup, destroy/reset
  the clone according to the approved retention policy.

## Acceptance criteria / definition of done

- A new operator can restore/start a documented capacity-VM smoke test without
  production credentials or manual code edits, and can destroy it afterward.
- Unsafe/ambiguous targets fail before the first request.
- At least one realistic concurrent profile reports per-endpoint p50/p95/p99,
  throughput, status classes, errors, and stop reason.
- Write profiles use only synthetic data and leave no rows after successful or
  interrupted cleanup.
- Results contain no secrets or personal data and are reproducible from the
  recorded profile/parameters/commit.
- The runner stops on health/error thresholds and handles operator interruption.
- Backend `npm run test:unit` and `npm run test:integration` pass; no test uses
  the production database.
- A code review confirms production cannot be targeted accidentally.
- The scrub attestation is tied to the exact snapshot and expires; capacity
  startup fails closed without it.
- Restore/start/stop/destroy are idempotent, locked, bounded, and repeatable
  within the documented minutes-level objective.
- Every start requires fresh confirmation of the complete VPS-equivalent
  specification and rejects runtime drift from the approved manifest.
- No Flutter/iOS/Android code changes are required; both platforms remain
  unchanged and version-skew safety is preserved.

## Open decisions for product/owner interview

None. V1 targets the disposable capacity VM; local execution can be added later
without changing the capacity profile contract.

## Revision log

- **Phase 1:** Drafted from the existing backend benchmark/fixture tools,
  scaling-capacity plan, and repo safety contracts. Chose a backend CLI because
  load generation is operational tooling, not end-user Flutter functionality.
- **Gap pass 1:** Added explicit production/database fail-closed checks,
  staging confirmation, bounded profiles, synthetic-data cleanup, circuit
  breaker, and secret redaction.
- **Gap pass 2:** Added write-vs-read profile separation, no automatic retries
  for writes, interruption cleanup, versioned results, endpoint-level metrics,
  and explicit no-API/no-app-change compatibility reasoning.
- **Owner clarification 2:** Selected step-sync and queue pressure plus all
  Home, Races, and Race Details flows; allowed writes against the dummy clone;
  chose operator-driven scale-up; and required destroy-after-run.
- **Owner clarification 3:** Confirmed the capacity VM—not staging or a local
  server—is the v1 target; local execution remains a later convenience.
- **Simplicity pass:** Replaced per-run provisioning and repair with a golden
  VM image plus verified scrubbed database snapshot, and explicitly excluded a
  dashboard/control plane/orchestrator from v1.
- **Owner clarification:** Reframed the target as a disposable VM matching the
  VPS, with a separately restored and comprehensively scrubbed production-data
  clone. Added clone isolation, scrub attestation, inert external sinks,
  network restrictions, and backup-retention requirements.
- **Architect review:** Required an exact snapshot-bound scrub attestation;
  explicit idempotent lifecycle/state commands; one canonical profile enum;
  exact Home/Races/Race Details and step/queue request matrices; synthetic
  write manifests and baseline checksums; queue drain semantics; isolated
  Redis configured/unset comparisons; explicit scheduler topology; and mixed
  legacy/current personas. Suggested keeping automated snapshot refresh and
  cloud provisioning out of v1. All required changes were folded in.
- **Owner clarification 4:** Added mandatory fresh confirmation of the full
  VPS-equivalent and database specification before every capacity start, with
  live drift checks and no confirmation bypass.
