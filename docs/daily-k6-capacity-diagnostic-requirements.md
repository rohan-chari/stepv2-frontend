# Daily k6 Capacity Diagnostic — Requirements

**Status:** Approved  
**Date:** 2026-08-18  
**Repositories:** `stepv2-frontend` k6 harness; read-only source and flag
provenance from `stepv2-backend`

## 1. Summary and user story

Replace the optimization-1 OFF/ON comparison as the normal k6 workflow with a
single-current-state daily diagnostic. As the operator, I want to run one command
each day against a sanitized local production-shaped environment, using the latest
remote backend `main` and production's effective flags, so I can record whether
the backend's approximate breaking RPS has moved materially over time.

This is a trend canary, not a deployment gate or certified production-capacity
claim. It never sends load to production or staging. Its only production access is
a bounded, read-only retrieval of non-secret flag values and the backend Git fetch.

## 2. Scope

### 2.1 In scope

- Add one supported command, provisionally
  `k6/local-prod-sim/run-daily-capacity-diagnostic.zsh`.
- Fetch backend `main`, pin `FETCH_HEAD`, and package that exact commit
  without merging, resetting, switching branches, or including dirty worktree
  files.
- Read production-effective DB-backed app settings and allowlisted performance
  environment flags without exposing unrelated environment values or database
  credentials.
- Merge the production snapshot over the fetched commit's declared defaults.
- Restore the sanitized corpus, apply the snapshot locally, remint local-only
  sessions, and run the released-client request mix on the existing isolated
  2-vCPU/2-GiB topology.
- Run one adaptive, comparable RPS checkpoint per daily invocation and maintain a
  known passing floor plus observed failing ceiling across days.
- Append one dated, secret-free row to the daily log in `k6/README.md`, including
  invalid runs.
- Preserve complete private artifacts under
  `~/.local/share/stepv2-capacity/runs/`.
- Retire the optimization-1 comparison from the main README/runbook path. Its
  historical script and finding may remain clearly labeled as historical.

### 2.2 Non-goals

- No production/staging load traffic, writes, flag changes, deploys, migrations,
  database dumps, or refresh of the sanitized corpus.
- No optimization A/B decision, automatic feature-flag recommendation, or flag
  mutation.
- No claim that local RPS converts exactly to production RPS or certified DAU.
- No automatic Git commit/push of the daily log.
- No Flutter UI, mobile behavior, public API, or backend business-logic change.
- No use of dirty/uncommitted backend source in a daily result.

## 3. Daily command contract

The runner acquires the lock, parses current ladder state, and creates the private
run directory plus a versioned preliminary result before Git fetch, SSH, database,
or VM work. Every later phase updates that record atomically, so early failure still
has a durable invalid reason and recovery row.

### 3.1 Source provenance

The runner shall:

1. Resolve the backend path from `BACKEND_REPO` or the existing sibling default.
2. run `git fetch origin main` and fail closed if it cannot fetch;
3. immediately resolve `FETCH_HEAD^{commit}` once, store that immutable full SHA,
   and use it for every later archive/default/remint/migration operation; never
   re-resolve a moving remote or assume the remote-tracking ref was updated;
4. create the VM artifact directly from that Git object using an allowlisted
   archive of `package.json`, `package-lock.json`, `prisma.config.ts`, `src`, and
   `prisma`; and
5. record the full SHA and commit time in the private result and the abbreviated
   SHA in the README row.

The runner must not require a clean backend worktree because it never reads source
from the worktree. It must not run `pull`, `checkout`, `switch`, `reset`, merge, or
rebase. Fetching the remote ref is the only backend-repository mutation.
Default extraction, Prisma commands, and token reminting must load code/dependencies
from the extracted fetched-SHA artifact. They must never resolve modules through
`BACKEND_REPO` or read its package manifest, tracked edits, untracked files, or
`node_modules` as an authority.

### 3.2 Production-effective flag snapshot

The snapshot has two explicit sources:

- **DB-backed flags:** the production deployment's read-only
  `appSettings.getAllFlags()` result, which returns stored values with deployed
  defaults filled in.
- **Process performance flags:** only a committed semantic-key/environment-key
  registry for values returned by `readPerformanceFlags()`. For the current main
  this includes its five boolean environment inputs and two bounded concurrency
  inputs. No full PM2 environment or `.env` may be printed, copied, or stored.

The snapshot is captured exactly once before the checkpoint. Exactly two
`steps-tracker` production PM2 workers must be online, have the expected
cwd/executable, and report the same normalized allowlisted performance values;
disagreement is invalid, not a value to majority-vote. The snapshot records
expected/observed worker count and the deployed production revision independently
from fetched `main`, so an undeployed main commit remains obvious.

Machine-specific SSH host/path values come from validated `PROD_SSH_TARGET` and
`PROD_BACKEND_DIR` private configuration, never a committed `/Users/...`, IP,
token, or production path. The runner owns a fixed remote helper and must not `eval`
or execute an operator-supplied command string. It delivers that helper over stdin
to `ssh -o BatchMode=yes`, with connection/command timeouts and strict host-key
checking. The helper validates production app name/cwd/executable before loading
anything.

`PROD_SSH_TARGET` accepts only a configured SSH alias or `user@host` composed of
letters, digits, dots, underscores, and hyphens. `PROD_BACKEND_DIR` must be an
absolute POSIX path containing only letters, digits, dots, underscores, hyphens, and
slashes, with no `..` segment. Both are passed as positional arguments, never
concatenated into evaluated shell text.

On the remote host only, the helper loads the deployed `.env` with dotenv diagnostic
output silenced, creates Prisma, begins a transaction whose first statement is `SET
TRANSACTION READ ONLY`, and calls
`buildAppSettings({ prisma: tx }).getAllFlags()` inside it. It disconnects and emits
exactly one strict versioned JSON document. `DATABASE_URL`, `.env`, raw AppSetting
rows, the full PM2 environment, and unrelated stdout/stderr must never cross SSH or
enter artifacts; extra stdout, timeout, or banner text makes the snapshot invalid.

The remote helper suppresses dependency diagnostics and maps failures to bounded
non-secret error codes. The local runner may retain only that code and SSH exit
status; it never stores raw remote stderr that could contain a connection string.

Before loading deployed modules, the helper proves they are the code loaded by both
workers. It resolves the production filesystem `HEAD`, requires no modified tracked
or untracked file under `package.json`, `package-lock.json`, `prisma.config.ts`,
`src`, or `prisma`, and validates both workers' cwd/executable. It then requires
either exact PM2/deployment revision metadata matching `HEAD`, or a fallback proof
that each worker uptime begins after the last HEAD reflog update and after the newest
mtime of every tracked runtime path. A pulled-but-not-reloaded checkout, dirty
runtime tree, indeterminate reflog/mtime, or worker/revision mismatch is invalid.
The snapshot labels this independently as `deployedLoadedRevision`.

For process flags, the helper combines deployed `.env` values with each worker's
allowlisted PM2 overrides using normal precedence (PM2 over dotenv), runs the
deployed `readPerformanceFlags()` once per worker, and emits only normalized
semantic results. The fetched-main registry is compared with the deployed registry:
main-only keys use fetched-main defaults and are disclosed; deployed-only keys are
retained only in provenance; any shared semantic/environment mapping change
invalidates until the harness registry is updated. Canonical environment values
derived from that normalized map are passed identically to both local workers.

The fetched `main` registry is authoritative for the locally runnable key set:

- a key present in both uses the production-effective value;
- a new key present only on fetched `main` uses its declared `main` default and is
  listed under `defaultedNewMainKeys`;
- a key present only in production is retained in provenance but is not inserted
  into the local DB because fetched `main` cannot read it;
- numeric/string settings retain their exact production-effective value; and
- `capacityPhaseMetricsV1Enabled` is the sole local diagnostic override and is set
  to `true` after the snapshot is applied. The override must be named separately
  in provenance and must not be described as production state.

The runner stores the full snapshot only in the private run directory with mode
`0600`. The committed daily row records a SHA-256 snapshot hash, not the full flag
map or banner text.

The hash input is canonical UTF-8 JSON with recursively sorted object keys and
contains exactly: snapshot schema version, normalized production DB-setting map,
normalized production performance-semantic map, and sorted ignored production-only
keys. Capture time, revisions, worker metadata, and the local observability override
are excluded.

If the production snapshot cannot be obtained, parsed, revision-labeled, or
validated against fetched `main`, the run is `invalid`; no load starts. There is no
silent fallback to corpus flags, all-on, all-off, or source defaults.

### 3.3 Local environment and state

The runner retains the existing isolation controls:

- localhost traffic only;
- dedicated PostgreSQL cluster/database name validation;
- sanitized-corpus marker and checksum validation through the application
  connection;
- private fixture checksum/revision validation;
- two Node workers, PgBouncer pool 25, empty Redis at startup, and only HTTP plus
  race-resolution workers;
- local dummy session secret and locally reminted fixture tokens;
- fetched-main migrations applied to the dedicated local database after every
  restore and before flag application, so a newer `main` never runs against a stale
  dump schema;
- PM2 executable/cwd/restart checks; and
- exit-trap teardown of PM2, Lima, PgBouncer, PostgreSQL, temporary fixtures, and
  the single-run lock.

Fixture tokens must be minted and verified against the exact fetched-main artifact
and local database configuration. Before starting traffic, one authenticated probe
must succeed; a 401 makes the run invalid immediately.

If a fetched-main migration cannot apply cleanly to the restored corpus, the run is
invalid and stops before traffic. Migration commands must use only the constructed
local benchmark `DATABASE_URL`; production and staging URLs are neither read nor
passed to the migration process.

After migration, an artifact-owned Node helper applies settings in one parameterized
local transaction. Through that same transaction it revalidates the expected local
database name and corpus marker, deletes all stale `app_settings` rows except the
marker, inserts exactly the fetched-main known DB-setting map, and then writes the
local-only `capacityPhaseMetricsV1Enabled=true` override as a separately recorded
step. No value is shell-interpolated into SQL; quoted, multiline, numeric, string,
and boolean values round-trip through parameters. The helper verifies the final
resolved settings hash before the backend starts.

### 3.4 RPS checkpoints and execution

The standard checkpoint ladder is `150,250,350,450,...` RPS in 100-RPS increments,
with an implementation safety cap of 950 RPS. One standard checkpoint runs per
daily invocation. Every checkpoint uses the same released-client cohort,
deterministic warm-up rule, 35-second constant-arrival period, thresholds, topology,
corpus, and harness protocol. Backend source and the once-captured production flag
snapshot are current inputs and are recorded for that day.

The next checkpoint is derived from the current worktree's bounded machine-readable
daily log while the run lock is held:

- no prior valid standard checkpoint: test 150 RPS;
- last standard checkpoint passed: test the next 100-RPS boundary on the next
  invocation;
- last standard checkpoint broke: retry that same boundary on the next invocation;
- last invocation was invalid: retry the same checkpoint; and
- 950 RPS passed: hold at 950 until the owner explicitly extends the safety cap.

Only a final standard record that survived evidence validation, verified cleanup,
and successful atomic README persistence may advance ladder state. A preliminary
pass later changed to invalid by cleanup/evidence/append failure does not advance;
the same boundary is retried.

This produces a known passing floor and a first observed failing ceiling over
multiple days without paying to rerun every lower checkpoint daily. A passing 250
RPS day followed by a breaking 350 RPS day reports floor `250`, ceiling `350`. A
later 350 pass advances the next daily invocation to 450. It does not claim an exact
breakpoint between the boundaries.

Every invocation starts from a fresh restore of the corpus and freshly reminted
tokens. A private `RPS_OVERRIDE` is allowed only when it is one of the standard
ladder values; using it labels the row `nonstandard` and does not advance or change
the standard ladder's floor/ceiling state.

The runner reads the current worktree `k6/README.md` while holding the single-run
lock; it does not require prior rows to be committed. Ladder state is parsed only
from bounded `DAILY_K6_LOG_V1_START/END` markers and one strict versioned JSON HTML
comment immediately paired with each visible row. Each record includes day,
standard/nonstandard mode, tested RPS, classification, floor, ceiling, and a
compatibility fingerprint. Historical A/B rows and override rows never affect
standard state.

The compatibility fingerprint canonically covers corpus/fixture revision, client
cohort, topology, duration, warm-up rule, threshold/classifier schema, VU-allocation
formula, k6/Node/PM2/Lima/PostgreSQL/PgBouncer versions, and host/guest architecture.
A new fingerprint starts a new series at 150 RPS with no inherited floor/ceiling.
The visible row is labeled `series reset/non-comparable`.

For every standard rung, `preAllocatedVUs = ceil(RPS * 2.4)` and `maxVUs =
ceil(RPS * 3.2)`. These formulas are part of the protocol fingerprint. Load-generator
resource exhaustion is invalid evidence, not backend breakage.

The first five seconds' worth of offered arrivals are tagged as warm-up. Breaking
classification uses steady-state traffic metrics, plus resolution drain and server
health evidence that necessarily occurs after traffic.

## 4. Breaking and invalid classification

### 4.1 Breaking checkpoint

Classification is ordered. First validate provenance/setup, then prove scheduler/raw
accounting and required server evidence are complete, and only then evaluate breaking
gates. For a 35-second constant-arrival window, planned iterations are `RPS * 35`;
the scheduler is complete when `executed + dropped == planned`. Nonzero dropped
iterations are therefore valid breaking evidence. An unaccounted deficit or
premature scheduler termination is invalid. k6 exit 99 caused solely by a threshold
failure is not invalid.

Steady-state rates and percentiles are reconstructed from raw samples tagged
`traffic_phase=steady` (planned steady iterations are `RPS * 30`) and cross-checked
against normalized summary counters when dropped arrivals are zero. Dropped
iterations never execute harness code and therefore cannot reliably receive the
iteration-index phase tag. When total scheduler accounting is complete and dropped
arrivals are nonzero—whether they occurred during nominal warm-up, steady time, or
both—the checkpoint is breaking immediately after load-generator evidence is proven
healthy; it does not also require `RPS * 30` executed steady samples. Available phase
metrics remain diagnostic only for that breaking run. When drops are zero, executed
warm-up and steady counts must equal `RPS * 5` and `RPS * 30` respectively.
Warm-up-only request failures are reported but do not break a no-drop steady
checkpoint. Drain/server evidence is evaluated in its own post-traffic window.

A valid checkpoint is breaking when any of these occurs:

- nonzero dropped arrivals;
- capacity/hard failure rate reaches 1%, including 429s, status 0, and 5xx;
- HTTP p95 reaches 2s or p99 reaches 5s;
- persistence-critical p95 reaches 2s, p99 reaches 5s, or max reaches 15s;
- race-resolution lag reaches 5s, a resolution job fails, or the queue does not
  drain by the deadline;
- a P2028, pool timeout, deadlock, OOM, or PM2 worker restart occurs; or
- guest-VM `MemAvailable` falls below 300 MiB.

The reported ceiling is the lowest currently observed failing standard checkpoint.
If no lower comparable checkpoint has passed, render it as `below N RPS`. Passing a
checkpoint raises the known floor but clears the old ceiling at that same boundary;
the next boundary is tested on the next invocation.

### 4.2 Invalid run

The run is invalid, and establishes no breaking RPS, for missing/malformed metrics,
failed auth/setup, fixture fallback, missing resolution samples, endpoint-accounting
mismatch, source/snapshot provenance failure, unexpected target/topology, teardown
failure, premature scheduler termination, or an unaccounted planned-arrival deficit.

The classifier must not infer success from an absent k6 counter. Zero-valued
required counters must be normalized explicitly in the summary or reconstructed
from validated raw metrics. This prevents the missing-all-zero-counter failure seen
in the aborted 2026-08-18 260-RPS comparison.

### 4.3 Required server-health evidence

Every checkpoint produces versioned `load-generator-health-v1.json` and
`server-health-v1.json` artifacts with bounded windows and completeness fields.

The load-generator artifact samples once per second from immediately before k6
startup through process exit and records host logical CPUs, total/available memory,
memory-pressure/OOM state, overall CPU, k6 PID/start identity, k6 CPU/RSS, VU/max-VU
metrics, exit status, stderr parse status, and sampler timestamps. It is invalid if:

- the sampler misses more than one consecutive expected sample or does not cover
  both process start and exit;
- k6 PID identity changes unexpectedly, exit status is neither success nor the
  expected threshold-failure status, or stderr contains a generator/runtime error;
- k6 consumes at least 80% of total logical host CPU capacity for three consecutive
  samples;
- host available memory falls below the greater of 2 GiB or 5% of total, host memory
  pressure becomes critical, or host OOM/swap-exhaustion evidence appears; or
- VU metrics are absent/malformed or exceed the configured maximum.

Reaching configured `maxVUs` is recorded but is not by itself generator exhaustion:
when CPU/memory/process evidence is healthy, scheduler-complete drops at the pinned
VU cap remain breaking evidence for the backend/protocol. Missing, incomplete, or
exhausted load-generator evidence takes validity precedence over dropped-arrival
classification.

The server artifact records:

- guest `/proc/meminfo` `MemAvailable` sampled at least once per second from backend
  readiness through the end of drain; minimum below 300 MiB is breaking;
- `pg_stat_database.deadlocks` for the benchmark DB immediately before traffic and
  after drain; positive delta is breaking;
- backend stdout/stderr files created for this run ID only, scanned for exact
  classified P2028, pool-timeout, deadlock, and fatal/OOM signatures;
- PM2 pre/post identity, cwd, executable, status, restart count, exit code, and
  unstable-restart metadata for both workers; any restart/non-online state is
  breaking;
- guest kernel/journal OOM-kill evidence bounded by run start/end; a backend OOM is
  breaking; and
- dedicated resolution drain capped at 60 seconds, followed by global queue drain
  capped at 90 seconds and requiring five consecutive one-second zero-backlog
  samples. Exceeding either deadline is breaking.

Artifact collectors record start/end timestamps, sample counts, commands/schema
versions, and parse status. Missing, malformed, truncated, out-of-window, or
unclassifiable required evidence is invalid. Tests exercise each gate individually.

## 5. Result and documentation contract

The private run directory contains:

- versioned production snapshot and hash;
- fetched backend SHA/commit timestamp;
- exact topology/client/rung/warm-up inputs;
- raw k6 samples and normalized summary for the tested checkpoint;
- health, PM2, backend, backlog, drain, and teardown evidence; and
- one generated secret-free Markdown row.

Private and committed summaries also carry a `seriesCompatibility` field. It is
`comparable` only when topology, corpus revision, client cohort, checkpoint protocol,
and threshold schema match the preceding valid row. Backend revision and production
flag hash are expected daily inputs and do not by themselves split the series, but
their changes remain visible. Any protocol-input change labels the row `series
reset/non-comparable`; the runner still records it and never calculates a trend delta
against the preceding row.

The runner records the README file hash when it selects the rung. After finalization
it verifies the hash again and atomically replaces only the bounded log block. A
concurrent/manual README change prevents replacement; the generated recovery row is
preserved privately and the command exits nonzero.

The bounded log contains one machine JSON comment plus one visible row per invocation:

| Day / local date | Backend | Prod flags | Tested RPS | Result | Known floor / ceiling | Rough DAU | Note |
|---|---|---|---:|---|---|---:|---|
| Day N / YYYY-MM-DD | `abcdef1` | `sha256:…` | `250` | `pass` / `breaking` / `invalid` | `250 / unknown`, `250 / 350`, etc. | estimate or `—` | shortest decisive gate or invalid reason |

Day/date uses `America/New_York`, while private timestamps remain UTC. Day numbers
increase per appended invocation, not per calendar date. Re-running on one day
therefore creates another row. The runner refuses to edit the README if its table
markers are missing or ambiguous and leaves the generated row in the private
directory for manual recovery.

Failures before source or snapshot acquisition use `—` for unavailable SHA/hash
fields. Machine records have a bounded schema and length, reject duplicate day/run
IDs, and contain no free-form backend log text or private values.

### 5.1 Two-phase finalizer

Success, breaking thresholds, setup failure, SIGINT, and SIGTERM all enter one
idempotent finalizer. Phase one attempts every cleanup independently—owned PM2
processes, Lima, owned PgBouncer PID, dedicated PostgreSQL, fixture/temp files—and
records each outcome without an early return. It then verifies the VM is stopped,
owned processes are absent, PostgreSQL reports stopped, and ports 3302/56432/55432
have no listener. Any failed/missing cleanup verification changes the result to
`invalid`.

Phase two generates the final/recovery row, attempts the hash-guarded atomic README
append while still holding the run lock, then releases the owned lock last. Append
failure preserves the row privately and exits nonzero. If lock release fails, the
runner rewrites its just-appended record to `invalid` when safely possible, preserves
the correction privately, and exits nonzero.

The lock stores owner PID, process start time, and run ID. SIGKILL or machine loss
cannot execute traps; the runbook defines stale-lock recovery that first proves the
owner identity is gone and repeats all process/port/cluster shutdown verification.
No recovery command deletes or signals an unverified PID.

Rough DAU uses the documented coefficient `0.0259 peak RPS/DAU` until explicitly
updated by a new production evidence window. The row always includes the coefficient
or links to the immediately preceding table note. Compute `tested RPS / coefficient`
and round to the nearest 100 DAU. For a breaking rung this is offered-load
equivalence, not supported capacity. Invalid runs have no DAU estimate.

The previously added Day 1 row based on the historical 160-RPS optimization pair is
not a valid daily-current-state run and must be replaced. The aborted 260-RPS A/B
attempt is recorded as invalid because setup returned 401 before load traffic.
Its initial machine record is fixed as: Day 1, local date 2026-08-18,
`standard=false`, tested RPS 260, result `invalid`, compatibility
`historical-invalid`, backend label `b4f3f4642005`, production snapshot `—`, no
floor/ceiling/DAU, and reason `resolution seed sync returned 401 before traffic`.
It never seeds adaptive ladder state; the first implemented standard invocation is
therefore Day 2 at 150 RPS.

## 6. API contract

No public or mobile API changes are allowed. `GET /admin/settings` remains unchanged
and is not required for the implementation if the bounded SSH read is used. The
production snapshot mechanism is an operator-only read contract and must never add
an unauthenticated endpoint.

There are no request/response compatibility changes for old app versions. The k6
client continues sending the frozen released-client headers and consuming responses
defensively under the existing harness contract.

## 7. Data model and migrations

No schema migration or production data mutation. Local `app_settings` rows are
replaced/upserted only inside the dedicated restored benchmark database. The runner
validates that database identity through the application connection before any
local mutation.

## 8. Frontend plan and platform impact

No Flutter screens, widgets, services, assets, or mobile platform files change.
iOS and Android behavior is identical because neither app binary nor API contract
changes. No UI-placement test plan is required.

Implementation is confined to `k6/`, its Node contract tests, the local runner, and
documentation. Any helper needed solely to expose fetched-main defaults should live
under `k6/local-prod-sim/`; backend runtime source should remain unchanged unless
architect review proves a tested backend helper is necessary.

## 9. Backward compatibility and rollout

This is an operator-tooling change with no app/backend deployment. Old clients and
the production backend are untouched. The normal workflow switches only after the
new tests and one successful local validation run. The optimization comparison
remains callable only as historical tooling and is removed from the primary README
and runbook instructions.

If production adds/removes flags or backend `main` changes, each run's source SHA,
snapshot hash, new-main defaults, and ignored prod-only keys preserve interpretability.
A source/flag/topology/client change is visible as a provenance change and should be
annotated when evaluating the time series.

## 10. Tests-first implementation plan

Before implementation logic, add failing Node tests that prove:

1. a stale `origin/main` tracking ref cannot win over pinned `FETCH_HEAD`, and a
   moving remote after pinning cannot change the packaged SHA;
2. the archive includes `prisma.config.ts`, excludes sensitive/unallowlisted paths,
   and ignores modified tracked source, untracked files, dirty package manifests,
   and worktree `node_modules`;
3. defaults, migrations, and token reminting resolve exclusively from the extracted
   fetched artifact;
4. the fixed remote helper validates app/worker identity, uses an enforced read-only
   transaction, has strict timeout/SSH behavior, and emits exactly one redacted JSON
   document; full env, DB URL, tokens, raw rows, and dotenv/banner output never cross
   the fake SSH boundary;
5. production filesystem HEAD/cleanliness plus PM2 revision metadata—or the strict
   uptime/reflog/mtime fallback—prove loaded-code identity; dirty, pulled-not-reloaded,
   indeterminate, stale-worker, and revision-mismatch fakes are invalid;
6. PM2-over-dotenv precedence, every semantic/environment mapping, worker mismatch,
   exact-two-worker count/status/cwd/exec mismatch, and main/deployed registry drift
   produce the specified normalized snapshot or invalid result;
7. snapshot canonicalization and hash inputs are exact, stable, capture-time
   independent, and exclude revisions/local overrides;
8. parameterized local settings application round-trips quoted/multiline strings,
   booleans, and numbers, deletes stale corpus settings, preserves/revalidates the
   marker, rejects the wrong DB, and separates the observability override;
9. snapshot/migration/authenticated-preflight failure prevents k6 traffic and records
   an invalid row with correct unavailable-field placeholders;
10. required absent all-zero counters normalize to explicit zero and are cross-checked
   against raw samples rather than accepted blindly;
11. scheduler completeness accepts `executed+dropped==planned`; warm-up-only,
    steady-only, and mixed drops are breaking without impossible phase-count
    requirements; zero-drop runs require exact phase counts; truncated/unaccounted
    schedules are invalid; warm-up-only request failures do not break steady gates;
    and threshold exit 99 is not invalid by itself;
12. complete/healthy, missing, malformed, and exhausted load-generator artifacts
    classify objectively, including CPU, RSS, host memory/CPU pressure, PID/exit,
    VU-cap, stderr, and sampler-window cases;
13. each breaking gate independently classifies: failure rate/429/hard failure,
    HTTP latency, critical latency/max, resolution lag/failure/drain, P2028,
    pool timeout, deadlock delta/log, memory headroom, OOM, and PM2 restart/status;
14. missing, malformed, truncated, or out-of-window evidence for every required
    server-health artifact is invalid;
15. first compatible standard run selects 150; pass advances by 100 on the next
    invocation; break/invalid retries; later pass advances; override/historical rows
    do not mutate standard state; and 950 holds;
16. a compatibility-fingerprint change starts a new 150-RPS series with cleared
    floor/ceiling and exact tool/VU protocol inputs;
17. strict machine markers/JSON reject ambiguity, duplicate records, excess length,
    and malformed state; README append is atomic, America/New_York dated, and detects
    a concurrent hash change while preserving a recovery row;
18. the two-phase finalizer attempts and verifies every cleanup on success, breaking,
    setup failure, SIGINT/SIGTERM, and append failure; cleanup failure makes the row
    invalid; stale-lock recovery refuses live/unverified owners; and
19. existing harness tests remain protected and green except mechanical routing
    updates from the historical runner to the new default command.

The source/snapshot/classifier properties are structural/operator-tool properties
that cannot be expressed through a Flutter screen; Node integration/CLI tests are
the appropriate public path. No production database or production mutation is used
by tests. Production flag reads are represented by a local fake command fixture.

## 11. Implementation order and ownership

1. Backend-contract agent confirms the read-only remote snapshot shape and that no
   backend API/runtime change is required. If a backend change becomes necessary,
   it owns that helper and its integration tests first.
2. Frontend/k6 agent writes the CLI tests first, observes the intended failures,
   then implements snapshot validation, fetched-main packaging, daily runner,
   classifier, README append, and runbook changes.
3. Run `node --test k6/test/*.test.mjs`, `git diff --check`, and `flutter analyze`.
4. Run one standard local validation only after the operator provides/validates the
   private read-only production snapshot command configuration.
5. Run code review on the combined diff before calling the workflow done.

## 12. Acceptance criteria and definition of done

- One documented daily command uses pinned fetched backend `main`, never dirty
  worktree source.
- It mirrors production-effective flags locally with a versioned, validated,
  private snapshot and no production writes/load.
- It runs one adaptive standard checkpoint per invocation against a fresh corpus,
  advances only after a valid pass, and retains a passing floor/failing ceiling.
- Breaking versus invalid classification follows Section 4 and cannot treat absent
  counters as zero implicitly.
- It appends one accurate, secret-free README row per invocation and keeps complete
  private evidence.
- It always tears down all benchmark services and clears its lock.
- Tests are written first and pass; existing assertions are not weakened.
- `flutter analyze` is clean, or pre-existing unrelated analyzer failures are
  reported plainly and this change adds none.
- No production/staging mutation, deployment, public API change, mobile change, or
  version-skew risk is introduced.
- Architect and final code-review requirements are satisfied.

## 13. Open owner decisions

None. Owner clarified that standard checkpoints are 150 RPS plus 100-RPS increments,
with the next boundary tested on the next invocation after a pass. Owner also
clarified that the desired environment is a production clone; this spec defines the
safe clone as latest-main code plus production-effective flags and the existing
sanitized corpus, never production secrets or unsanitized live data.

## 14. Revision log

- **Draft (2026-08-18):** Replaced optimization OFF/ON semantics with a single
  current-state daily diagnostic; pinned backend input to fetched `main`;
  defined production flag mirroring, comparable checkpoints, breaking/invalid rules,
  private evidence, and README logging.
- **Gap pass 1:** Separated DB-backed and environment performance flags; added merge
  behavior for flags that differ between deployed production and fetched `main`;
  prohibited full environment capture; added authenticated preflight and the sole
  observability override. Added fetched-main local migration deployment and replaced
  an arbitrary snapshot-command seam with validated SSH target/path inputs plus a
  fixed read-only command.
- **Gap pass 2:** Added a fresh corpus restore per invocation, explicit handling
  for absent zero counters and the observed 401 failure, teardown/documentation
  atomicity, local-date/day numbering, dirty-worktree isolation, nonstandard-run
  labeling, and bounded checkpoint behavior. Required one immutable flag snapshot
  per invocation, PM2-worker agreement, distinct deployed/fetched revisions, and
  explicit time-series compatibility/reset labeling.
- **Owner interview:** Replaced the same-day `160,260` staircase with one adaptive
  daily checkpoint at `150,250,350,450,...`; pass advances the next invocation,
  while break/invalid retries the boundary and maintains a floor/ceiling. Clarified
  “clone prod” as latest-main code, production-effective flags, and sanitized corpus
  only—never raw production data, `.env`, keys, or credentials.
- **Architect review (REVISE):** Pinned `FETCH_HEAD` and artifact-only dependencies;
  included Prisma 7 config; made the remote snapshot an identity-checked,
  stdin-delivered SSH helper with an enforced read-only transaction and exact
  PM2/dotenv normalization; defined canonical hashing and parameterized local flag
  replacement; added machine-readable series-scoped ladder state; established
  scheduler-validity-before-breaking precedence; specified every required
  server-health artifact; added a verified two-phase finalizer/stale-lock recovery;
  pinned VU/tool compatibility inputs; and expanded tests for each failure mode.
- **Post-review gap pass 1:** Required a durable preliminary result before any
  external/setup phase, corrected the memory gate to guest `MemAvailable`, and
  ensured early provenance failures can still produce an accurate invalid recovery
  row.
- **Post-review gap pass 2:** Tightened SSH target/path validation and positional
  argument handling, prohibited raw remote stderr retention, and required bounded
  non-secret remote error codes so diagnostic failures cannot leak production
  connection material.
- **Architect confirmation review (REVISE):** Added proof that the clean production
  filesystem revision is the code loaded by exactly two PM2 workers; made
  scheduler-complete drops breaking without impossible phase attribution; added
  objective versioned host/k6 generator-health evidence and invalid thresholds;
  fixed the historical Day 1 invalid machine record; and defined DAU rounding as
  offered-load equivalence rather than supported capacity.
- **Final gap pass 1:** Made adaptive state transitions depend on the final verified
  and successfully persisted standard classification, so a preliminary pass followed
  by evidence, cleanup, or append failure cannot advance the boundary.
- **Final gap pass 2:** Rechecked early-failure placeholders, nonstandard/historical
  isolation, compatibility resets, snapshot immutability, and production/local
  mutation boundaries; no additional requirement changes were needed.
