# K6 Capacity Operator Requirements

Status: Approved — implementation authorized 2026-08-20

## Summary

Replace the current fragmented, fixture-first k6 harness with one repeatable
capacity-test operator that owns the complete disposable environment lifecycle:

1. confirm the intended production-shaped topology with the operator;
2. provision or reset isolated Lima VMs;
3. fetch a clean copy of the latest backend `origin/main` and the live production
   environment file;
4. restore a fresh production database backup into the isolated database VM;
5. sanitize every outbound-notification credential and delivery record;
6. deterministically inflate users, working identity tokens, races, and race
   memberships;
7. launch two clean backend workers with production flags and explicit safety
   overrides;
8. run a selected workload, observe the step-sync queue through drain, and
   produce a concise capacity report;
9. retain, stop, or destroy the environment according to an explicit policy.

The workflow must be easy to invoke again without relying on remembered terminal
commands, an old workbook, or undocumented local state.

## User story

As the operator, I want one guided k6 workflow that asks me to confirm the
production-shaped resources every time, builds an isolated environment from
current production inputs, makes that environment safe, and reports how the
step-sync queue behaves under a realistic workload so that repeated capacity
tests are comparable and trustworthy.

## Current-state problem

The tracked `k6/` implementation is a narrow load harness. It deliberately does
not provision Lima, restore PostgreSQL, fetch production flags, launch backend
workers, sanitize production data, or inflate the database. Those prerequisites
are manual and live outside the harness.

This creates several sources of delay and ambiguity:

- fixture construction, infrastructure preparation, and the load run are split
  across unrelated commands;
- a large JSON fixture is parsed and validated independently by many k6 VUs;
- smoke timing can conflict with production debounce flags;
- one long mixed workload obscures the specific step-sync saturation question;
- production environment provenance and safety overrides are not recorded as a
  single auditable manifest;
- queue setup, observation, barriers, postchecks, and report aggregation are
  concentrated in one large script;
- the harness cannot tell whether the environment it was handed is fresh,
  production-shaped, or safe.

## Scope

### In scope

- A single guided entry point for the full capacity-test lifecycle.
- A mandatory confirmation gate before infrastructure creation or reset.
- Production-shaped application and database VMs.
- A clean backend checkout at the latest fetched `origin/main` commit.
- Fetching the live production `.env` from the production backend host on every
  fresh workflow run, with checksum and source metadata.
- A fresh, consistent production database backup and isolated restore.
- Notification and outbound-integration sanitization before any backend starts.
- Deterministic data inflation for at least 10,000 active test users, each in
  between one and five active races.
- Identity credentials that authenticate against the isolated backend.
- Two backend workers started from the clean checkout.
- A focused step-sync queue workload and optional broader route-mix/soak modes.
- Queue, HTTP, application, and database observations through complete drain.
- A compact run manifest and final report suitable for comparing runs.
- A dedicated project skill and named k6 operator agent so future requests route
  through this contract instead of reconstructing the process from memory.
- Removal or consolidation of superseded tracked k6 scripts and documentation
  after the replacement is verified.

### Non-goals

- Mutating production data or running load against production endpoints.
- Reproducing managed-cloud internals that are not observable or configured in
  production.
- App UI changes.
- Product API behavior changes solely to accommodate the test harness.
- Treating synthetic capacity results as proof of production reliability.
- Keeping copied production credentials usable for outbound notifications or
  third-party writes.

## Proposed operator flow

### 1. Discover and present the run plan

The operator resolves current defaults but does not mutate anything. It prints a
single confirmation summary containing:

- app VM: 2 vCPU, 2 GiB RAM, 60 GiB disk;
- database VM: 1 shared vCPU, 2 GiB RAM, 30 GiB disk;
- PostgreSQL connection ceiling: 47;
- backend processes: 2;
- database pool size: 20 per backend process;
- backend ref: latest fetched `origin/main`, including resolved commit SHA;
- production environment source host and path;
- production database source, without printing credentials;
- user count, race membership range, workload mode, rate, and duration;
- whether existing VMs will be reset, reused, or replaced;
- final retention policy.

The workflow requires an explicit affirmative confirmation every time it starts.
No saved preference may bypass this gate.

This is one consolidated approval covering VM provisioning/reset, read-only
production environment and backup acquisition, the derived workload, and final
destruction. After approval, the workflow proceeds autonomously unless a safety
gate fails or diagnostic evidence would otherwise be lost.

Confirmed defaults are two separate VMs and two backend workers, matching the
current production deployment. Healthy VM shells may be reused during setup,
retry, and investigation within the same workflow, but not across a completed
workflow because final cleanup destroys the environment.

### 2. Preflight

Before production access or VM mutation, verify:

- Lima, SSH, PostgreSQL client tools, Node, npm, and k6 versions;
- sufficient local disk space;
- access to the backend repository and production host;
- access to a production database backup source;
- production PostgreSQL major version and restore compatibility;
- that every intended destination is an isolated capacity-test target;
- that no configured workload URL resolves to production.

Failures stop before destructive work and identify the exact corrective action.

### 3. Provision or reset topology

Create two purpose-specific Lima VMs, or reset explicitly approved existing VMs:

- application VM matching the production droplet resources;
- database VM matching the managed database resources.

Record actual allocated CPU, memory, disk, addresses, and software versions in
the run manifest. Configure the database connection ceiling to represent the
production limit while retaining enough administrative access to observe and
recover the test.

k6 runs on the host or a dedicated unmeasured generator, never inside the 2 GiB
application VM. Requests traverse the same observable nginx-to-PM2 path as
production. Reproduce the production nginx and PM2 cluster settings, memory
restart policy, and two workers with `NODE_APP_INSTANCE=0/1`; verify that only
worker 0 schedules queue workers. The report states any cron/worker behavior
intentionally absent from the capacity entrypoint and records host hardware,
Lima backend, swap state, proxy/TLS path, and the limits of comparing Lima with
DigitalOcean shared CPU, storage, and managed networking.

The app-to-database connection uses either a measured tunnel or an authenticated,
run-bound private address accepted by a narrowly revised capacity safety guard;
the guard must never become a general non-loopback allowlist.

Inspect the current production connection configuration on every workflow and
reproduce the actual path used by the backend, including a pooler/proxy when one
is present. The confirmed baseline is a 47-connection managed-database ceiling
with two backend workers configured for pools of 20; the run manifest records any
observed production difference before confirmation.

Discover effective production Redis usage before confirmation. When enabled,
provision an isolated cache with recorded version, limits, and namespace and
replace `REDIS_URL`. If it cannot be reproduced, stop or label the run
non-production-comparable rather than silently falling back to PostgreSQL.

### 4. Acquire verified production inputs

- Fetch the backend repository cleanly and check out the resolved `origin/main`
  commit in a dedicated run directory.
- Copy the live production `.env` byte-for-byte to a protected, run-scoped
  evidence file.
- Record its SHA-256 checksum, acquisition timestamp, source, and permissions.
- Never commit, print, or include secret values in reports.
- Generate a separate runtime override file for isolation-only changes. The
  evidence copy remains byte-identical to production.

The evidence `.env` is never sourced by the backend. Build a separate effective
runtime environment with explicit replacements for database and peer-database
URLs, capacity signing secret, bind address, Redis, push, object storage, and all
outbound cron/integration switches. Validate the effective process environment
before application modules load. Compare non-secret production `.env` values
against both production workers' effective `/proc/<pid>/environ` values and show
drift in the confirmation summary. During backend execution, VM egress is default
deny except for the isolated database/cache path; environment scrubbing and the
in-process notification sink remain independent controls.

### 5. Back up and restore production

- Acquire a transactionally consistent backup using a PostgreSQL client version
  compatible with production.
- Use a read-only source role/transaction, stream the backup without placing a
  second copy on the 30 GiB database VM disk, record snapshot start/end and
  production database load, and abort when the confirmed production-impact
  threshold is crossed.
- Restore only into the isolated database VM.
- Prove the destination identity before restore and record source/target metadata.
- Keep the raw backup protected and run-scoped; never add it to the repository.
- Verify schema version and representative row counts after restore.
- Immediately before restore, sanitization, inflation, or any other write-capable
  command, prove the capacity database name, run ID marker, Lima VM identity, and
  non-production destination host.

### 6. Sanitize before backend startup

Sanitization is a hard gate, not a best-effort cleanup. At minimum:

- truncate device tokens;
- truncate or reset push-notification delivery/outbox tables;
- clear queued step-sync and race-resolution work inherited from production;
- disable APNs and FCM through runtime-only credential overrides;
- disable other outbound write integrations unless specifically allowlisted;
- verify zero sendable notification identities remain;
- verify outbound production hosts are blocked or absent from runtime config.

The backend must not start if any sanitization assertion fails.

No external write integration is allowlisted by default. Email, SMS, webhooks,
analytics, object-storage writes, push notifications, and third-party callbacks
are disabled. Only the isolated database and internal queue processing required
by the workload remain enabled.

The restored database is not generally anonymized. Production user/profile data
remains intact in the isolated VM because the complete environment is destroyed
after reporting. Device tokens and push-delivery state are always removed.

### 7. Inflate deterministic test data

- Generate exactly 10,000 eligible active synthetic identities by default unless
  the confirmation explicitly changes the count, without modifying restored
  production users.
- Give every synthetic user a unique marker tied to the run ID.
- Generate credentials accepted only by the isolated backend configuration.
- Create active races and assign every synthetic user to one through five races.
- Derive and record realistic active race-type and roster-size distributions from
  the restored database, avoiding singleton-only synthetic races, and guarantee
  that all generated races remain active through the longest possible run.
- Use a recorded random seed so the same topology can be reproduced.
- Batch database writes and index-aware validation to keep preparation time
  bounded.
- Emit a compact machine-readable identity/race dataset that avoids reparsing a
  multi-megabyte JSON document in every VU.
- Verify exact user count, membership distribution, active-race count, and token
  authentication before load begins.
- For every stage, generate canonical valid step-sync bodies with monotonically
  increasing totals/samples and fresh deterministic UUID idempotency keys. Never
  replay unchanged totals that can exercise cooldown, idempotency, or no-scoring-
  change paths instead of the queue. Provision every prerequisite declared by the
  eligible routes in the versioned route registry.

### 8. Start and prove the backend

- Install dependencies from the lockfile in the clean checkout.
- Apply only migrations already present on `origin/main`.
- Launch exactly two backend workers with pool size 20 each.
- Use the protected production environment evidence plus the reviewed isolation
  overrides.
- Record process IDs, commit SHA, effective non-secret flags, listening ports,
  health checks, and database pool configuration.
- Run a small authenticated canary and prove notification sending is disabled.

### 9. Execute an explicit workload mode

The sole default mode is an adaptive production-style route mix. It starts
at 50 requests per second. Each level has a 30-second warm-up followed by a
three-minute measured stage. A passing level advances by 10 requests per second.
There is no configured maximum RPS. A failing level is automatically repeated
once at the same rate to distinguish a durable limit from transient noise. If it
fails twice, the ramp stops and proceeds to drain, diagnosis, reporting, and
cleanup.

The workflow has an eight-hour wall-clock safety deadline. Reaching it is not a
capacity failure: stop new traffic, drain within the derived timeout, report the
highest passing level and deadline termination, and clean up normally.

A measured stage passes only when all of the following are true:

- HTTP failure rate is below 1%;
- p95 HTTP latency is below two seconds;
- zero dropped iterations and no VU saturation occur;
- achieved RPS remains within the confirmed tolerance of offered RPS;
- there are no database connection failures or deadlocks;
- the step-sync queue drains before progression to the next measured level;
- there are no permanently failed queue jobs.

Thresholds apply globally and per eligible route when that route reaches the
confirmed minimum sample count of 100. Achieved RPS must remain within plus or
minus 2% of offered RPS. Low-weight routes below that sample count are
reported but cannot independently pass or fail a stage. A generator-validity
failure is classified as `invalid/harness-limited`, not an application failure.
The operator may increase VU allocation and retry that level once; a second
generator-invalid result stops the run as inconclusive.

Immediately before each full run, derive route weights using read-only access to
the production vhost's active, rotated, and compressed nginx logs for the exact
half-open UTC interval `[runStart - 7 days, runStart)`. Aggregate by HTTP method
and normalized Express route template, never by raw URL. Exclude health checks,
administrative routes, recognized bots, non-application vhosts, and routes whose
required external writes are disabled. Record raw and eligible counts, exclusions,
coverage percentage, source file identities, and normalized weights. Raw URLs,
path parameters, query values, request bodies, IP addresses, and production user
identifiers never enter retained artifacts.

A versioned route registry defines each replayable method/template, auth persona,
headers and client capabilities, synthetic prerequisites, request builder,
accepted statuses, and allowed isolated mutations. Unknown routes are listed as
excluded before confirmation. The workflow refuses to claim production-style
comparability when eligible registry coverage falls below the confirmed minimum.
The minimum coverage is 95%. Weights are never silently reused from an older run.

Additional explicitly selected modes may include:

- `step-sync-burst`: one authenticated step-sync submission per synthetic active
  user as a focused queue diagnostic, never selected implicitly;
- `step-sync-find-limit`: short stepped rates to locate the useful capacity
  boundary;
- `mixed-route`: a compact production-shaped route mix after the step-sync result
  is understood;
- `soak`: an explicitly requested sustained run, never the default.

Production debounce and queue timing values must be read from the captured
configuration and incorporated into barriers and timeouts. Fixed harness delays
must not silently contradict production flags.

Traffic stops after every warm-up and measured stage. Before measurement,
progression, or a same-rate retry, the operator reaches a clean barrier across
`step_sync_requests` processing reservations, the active
`race_resolution_jobs` or `race_resolution_jobs_v2` implementation,
`race_resolution_post_tasks`, and race-resolution delivery intents. The finite
drain timeout is derived from captured debounce, lease, retry, and backoff flags
and displayed in the confirmation plan. A drain timeout, deadlock, worker loss,
or database exhaustion is terminal and is never followed by another load wave.
Tokens are refreshed between stages using the capacity-only signing secret.
Operator cancellation stops new traffic, attempts bounded drain, preserves the
diagnostic report, and then follows the confirmed cleanup policy.

### 10. Observe through drain and report

The run is incomplete until the queue drains or an explicit maximum drain timeout
is reached. Report:

- requested, started, completed, accepted, rejected, and timed-out HTTP requests;
- p50, p95, and p99 latency by endpoint and wave;
- effective arrival rate and VU saturation;
- queue jobs created versus submissions, peak depth, oldest age, processing rate,
  retries, failures, and final depth;
- database active/idle/waiting connections, peak total, lock waits, deadlocks,
  slow queries, and connection errors;
- backend worker CPU/memory/event-loop health and errors;
- observed coalescing ratio and complete drain time;
- resolved commit, environment checksum, topology, seed, and workload inputs;
- a clear classification: harness limitation, application limit, database limit,
  or inconclusive.

### 11. Retain or clean up

After the final report is safely copied outside the VMs, destroy both VMs and all
run-scoped secrets, raw backups, copied environments, fixtures, credentials, and
temporary artifacts. Retain only the redacted report and non-secret comparison
metrics. If reporting cannot be completed, pause for an explicit operator choice
instead of destroying the only diagnostic evidence.

Cleanup first stops new traffic and backend workers, atomically copies the report,
and then requires both the recorded Lima identity and in-VM run marker before
destroying anything. Partial cleanup is reported as partial, never as success. A
small redacted cleanup receipt is retained beside the report containing hashes
and deletion outcomes—but no secret values or sensitive paths—for the backup,
environment evidence, generated credentials, raw logs, and both VMs.

## Command and artifact contract

The single CLI is `k6/operator.zsh` with the public commands `run`, `status`,
`resume`, and `cleanup`. Phase-level helpers are private implementation details.
The automatic routing contract lives in `.agents/skills/k6-operator/SKILL.md` and
the executable agent in `.codex/agents/k6-operator.toml`. Matching routing rules
are added to both `AGENTS.md` and `CLAUDE.md`. The skill is authoritative for
natural-language routing; the agent reads this spec and host-owned run state and
never treats conversational memory as operational state.

At the conversational level, the complete public trigger is simply `do a k6
run` (and close natural-language equivalents). The project skill routes that
request to the named k6 operator agent. The agent must not assume remembered VM
specifications: it freshly discovers current production inputs and presents the
resolved application VM, database VM, two-worker/pool topology, rolling-seven-day
traffic window, and workload plan for explicit confirmation before acting.

Every run receives a unique run ID and directory containing only:

- redacted manifest;
- checksums and provenance metadata;
- sanitized preparation statistics;
- process logs;
- raw k6 summary;
- queue/database observations;
- final human-readable report.

The host owns an atomic state machine with run-bound VM names and matching
in-VM app/database markers. Each phase records `pending`, `running`, `complete`,
or `failed` plus explicit postconditions for discovery, approval, provisioning,
input acquisition, dump, restore, sanitization, inflation, backend startup,
traffic, drain, report copy, and cleanup. Resume always revalidates the phase's
postconditions and production-safety assertions; it never assumes an interrupted
dump, restore, sanitize, migration, traffic wave, or cleanup completed.

Secrets, `.env` contents, database backups, and usable identity credentials are
stored separately with restrictive permissions and are never included in normal
result bundles.

## Safety and compatibility

- Production access is read-only except for copying existing configuration and
  creating a consistent database backup.
- Every write-capable database command verifies the destination host, database,
  and run marker immediately before execution.
- The load target must be a loopback, Lima, or explicitly allowlisted capacity
  address; production domains and addresses are denied.
- Push safety has two independent controls: data removal and runtime credential
  disablement. A canary proves both before load.
- Synthetic authentication material should be isolated from production so a token
  created for capacity testing cannot authenticate to production. A capacity-only
  signing secret is a required runtime override.
- The workflow does not change public API contracts and therefore introduces no
  older-client compatibility dependency.
- No frontend release is involved; iOS and Android behavior is unchanged.

## Data model and migrations

No product migration is planned. Inflation uses the schema at the resolved
backend commit. Synthetic rows must be identifiable by run marker and must exist
only in the isolated restored database.

If efficient generation cannot be achieved through existing schema-compatible
batch inserts, any proposed helper schema must be temporary, capacity-only, and
excluded from application migrations.

## Verification plan (no test-suite changes)

Per operator direction, this workflow will not add, modify, delete, or otherwise
rework an automated test suite, test fixture, or test case. This is an explicit
exception to the repository's normal tests-first workflow for this operational
tooling project.

Verification is limited to runtime gates and a disposable end-to-end rehearsal:

- refuse provisioning until the confirmation gate is satisfied;
- reject production targets for restore destinations and workload URLs;
- verify the copied environment evidence file remains byte-identical while
  runtime overrides remain separate;
- verify no sendable notification identity or pending delivery remains;
- block backend startup when sanitization assertions fail;
- authenticate a sample of generated identities and verify the complete generated
  population has one-to-five active race memberships using database assertions;
- launch two backend workers, submit a small step-sync rehearsal, observe queue
  creation, and wait for verified drain;
- interrupt and resume a disposable run at representative phase boundaries;
- prove cleanup targets only the selected run and not unrelated Lima instances;
- Compare displayed and actual VM allocations.
- Compare production `.env` checksum between source and protected evidence copy.
- Confirm two backend worker processes and their pool sizes.
- Inspect the final report against raw k6, PostgreSQL, and queue observations.
- Confirm retained/stopped/destroyed state matches the selected policy.

## Acceptance criteria

- Every full workflow begins with an explicit topology and workload confirmation.
- Saying `do a k6 run` is sufficient to invoke the correct guided workflow; the
  operator does not require the user to name scripts, phases, fixtures, or a
  workbook.
- A normal run requires one guided invocation after confirmation, not a workbook.
- The backend is a clean latest `origin/main` checkout, and the live production
  `.env` evidence copy is byte-for-byte verified.
- The restored database is isolated and all required notification identities and
  delivery state are removed before backend startup.
- APNs, FCM, and other non-allowlisted outbound writes are disabled independently
  of database sanitization.
- At least 10,000 synthetic active users authenticate successfully and each has
  one through five active race memberships.
- Exactly two backend workers run with the confirmed pool configuration.
- The selected step-sync workload completes and queue observation continues until
  verified drain or a reported timeout.
- Reports include enough provenance and telemetry to compare two runs and explain
  the limiting layer.
- Interrupted runs can safely resume or clean up.
- Superseded tracked k6 workflow files are removed only after the replacement's
  disposable end-to-end rehearsal succeeds and their behavior is either retained
  intentionally or documented as removed.
- No integration or load test writes to production.

## Superseded-workflow cleanup

Cleanup is part of this feature, not a later optional project. Before deletion,
inventory every k6-related tracked script, document, agent, skill, example,
fixture contract, and generated-artifact path across both repositories. Classify
each item in the implementation plan as:

- retained as part of the new public workflow;
- replaced by a named new component;
- generated and ignored with an explicit retention rule; or
- obsolete and deleted after the disposable rehearsal succeeds.

The final tracked surface should contain one operator entry point, its small
internal phase modules, the automatic routing skill, the named operator agent,
the current requirements/operations documentation, and no competing workbook or
legacy happy path. Old results, copied databases, environments, identity files,
and VM-local artifacts are destroyed under the confirmed cleanup policy.

Per explicit operator direction, existing automated test-suite files are outside
this cleanup scope and remain unmodified even when they reference the superseded
workflow. Any resulting stale-test concern must be reported plainly rather than
resolved by changing the suite.

The current protected capacity contract test imports legacy contract, fixture,
observer, and runner modules. Those exact dependencies remain as private
compatibility support unless they can be removed without changing or breaking the
protected test. Their prior documentation and public happy-path status are still
removed; the new skill, agent, and `k6/operator.zsh` are the only supported entry
path.

## Open decisions for operator interview

All operator decisions are resolved. Architect review may identify implementation
gaps that require a further operator decision.

## Gap review log

### Pass 1 — completeness and ambiguity

- Clarified that the live production `.env` has two roles: an immutable evidence
  copy and a separate runtime override layer. The operator must decide which
  secrets, especially auth signing material, may remain effective in capacity.
- Added open decisions for VM reuse, two-VM topology, PII anonymization,
  production proxy/pool behavior, workload defaults, and retention.
- Made notification truncation insufficient on its own: runtime push credentials
  must also be disabled and verified before startup.
- Identified that an auto-routing skill and an executable named agent serve
  different purposes; the desired combination remains an interview decision.
- Confirmed there are no frontend, public API, migration, or older-client changes.
- Recorded the operator's explicit direction that no test suite be created or
  modified.

### Pass 2 — failure modes and operator usability

- Added production destination and workload-target denial, exact destination
  verification before writes, and a hard sanitization gate.
- Added run IDs, phase state, status/resume, targeted cleanup, and protected
  artifact separation to prevent ambiguous recovery after interruption.
- Made debounce and queue flags drive barriers/timeouts so production settings do
  not conflict with fixed smoke timing.
- Replaced the large per-VU JSON assumption with a compact/generated input design;
  the exact transport remains an implementation decision.
- Required observation through drain and classification of harness, application,
  or database limits so a VU-initialization bottleneck is not misreported as
  backend capacity.
- Kept the happy path to one guided command plus status/resume and cleanup; low
  level phase commands are implementation details, not the operator workbook.

## Revision log

- 2026-08-20: Initial draft created from the requested full-lifecycle workflow
  and the observed limitations of the current fixture-first harness.
- 2026-08-20: Operator explicitly excluded all automated test-suite creation and
  modification; verification changed to runtime gates and disposable rehearsal.
- 2026-08-20: Confirmed two VMs, two backend workers, no general PII
  anonymization, capacity-only auth signing, adaptive production-style traffic
  beginning at 50 RPS with 10 RPS increments, post-run failure analysis, creation
  of both a routing skill and named agent, and full environment destruction after
  the report is secured.
- 2026-08-20: Confirmed a newly derived rolling-seven-day production route mix
  for every run, reproduction of the current production database connection path,
  deletion of superseded k6 scripts and documentation after successful rehearsal,
  and one consolidated approval before autonomous execution.
- 2026-08-20: Clarified the end-state conversational contract (`do a k6 run`) and
  made an inventory-driven removal of competing k6 workflows and artifacts part
  of the feature itself, while preserving all existing testing-suite files.
- 2026-08-20: Confirmed disabling all external writes, 30-second warm-up plus
  three-minute measured stages, the five-part pass gate, one same-rate retry after
  failure, 10 RPS increments, and no artificial maximum RPS.
- 2026-08-20: Applied architect review: made the adaptive seven-day mix the sole
  default; specified log normalization, route registry, realistic inflation,
  generator-validity gates, queue barriers, two-VM/nginx/PM2/Redis topology,
  fail-closed effective environment, database safety, atomic resume/cleanup, and
  exact public skill/agent/CLI contracts. Adopted an eight-hour deadline, 95%
  route coverage, ±2% achieved-rate tolerance, 100 per-route samples, and private
  compatibility retention for dependencies of the protected test.
- 2026-08-20: Operator approved implementation after architect review.
