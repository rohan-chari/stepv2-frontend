# Simple Capacity Load Test — Requirements

**Status:** Approved; implementation in progress.
**Repositories:** `stepv2-frontend` (new k6 harness and primary ownership),
`stepv2-backend` (documentation references only; no runtime change).
**Destructive scope authorized by owner:** Delete the 39 tracked files in the
existing committed `k6/` implementation and rebuild that tracked tree from scratch.
Deletion is by exact tracked path, never recursive directory removal. Preserve
ignored/untracked private corpora, fixture files, run artifacts, PostgreSQL clusters,
and the Lima VM.

## 1. Summary and user story

As the operator, I want one understandable capacity workflow that answers three
questions:

1. At what offered request rate does this fixed non-production environment first
   violate the API service-level objectives?
2. What is the highest rate that passes repeatedly rather than by chance?
3. Can that confirmed rate remain healthy for a longer soak?

The replacement is a controlled capacity benchmark, not a claim that independent
random requests reproduce every production user journey. It favors a small,
auditable workload and repeatable test protocol over daily automation, production
snapshot plumbing, or exact DAU conversion.

The benchmark exercises API traffic and the resolution worker together. It rotates
write traffic across an explicit number of distinct fixture users, measures the
resulting race-keyed queue with a lightweight read-only sampler, and observes drain
after HTTP load stops. This approximates increasing traffic and dirty-race breadth;
it does not claim that user count alone determines worker cost.

The normal flow is:

```text
smoke -> stepped search -> three-repeat confirmation -> 30-minute soak
```

The search reports the first failed offered-RPS rung, not a repeated failure or exact
ceiling. After the operator verifies the three-repeat passing confirmation, the soak,
and server telemetry, the
recommended operating limit is `floor(confirmedRps * 0.70)` whole RPS. Thirty percent
headroom is the initial operator policy for burst and measurement uncertainty, not a
measured property; revisit it after several comparable confirmation/soak cycles. The runner
does not maintain cross-run state or manufacture this conclusion automatically.
Results remain specific to the recorded target topology and benchmark
profile; they are never silently converted to DAU.

## 2. Scope

### 2.1 Remove the existing system

Before deletion, enumerate the exact target with `git ls-files k6`, confirm it has 39
tracked paths, and save `git diff --binary -- k6` to a private timestamped archive
under `${XDG_DATA_HOME:-$HOME/.local/share}/stepv2-capacity/archives/`. Use
`apply_patch` to delete only those tracked files. Never run recursive removal against
`k6/`. After rebuilding, prove that the ignored existing `k6/users.json` and any
other pre-existing ignored/untracked paths still exist unchanged. The new harness
does not consume `users.json`; the operator may archive or remove it separately.

Delete the current contents of `k6/`, including:

- the daily adaptive ladder and README mutation;
- the Lima/PostgreSQL/PgBouncer lifecycle manager;
- production SSH flag capture and fetched-main packaging;
- production-clone sanitization and migration orchestration;
- historical OFF/ON optimization comparison runners and findings templates;
- the 26-endpoint released-client cohort harness and cohort aggregator;
- raw-sample normalization, compatibility fingerprinting, and custom host/server
  evidence classifiers;
- the old `staging-load-test.js`, profiling scripts, samplers, fixture validators,
  and their tests.

Delete `docs/daily-k6-capacity-diagnostic-requirements.md`. Retain historical
optimization specifications and evidence documents, but add a short banner to any
document that presents an obsolete k6 command as current. Update active references
to point to the new `k6/README.md`. Backend migrations explicitly include
`docs/pm2-cluster-scaling-plan.md`,
`docs/capacity-bottleneck-optimization-plan-2026-08-17.md`,
`docs/transaction-hold-time-requirements.md`, and
`docs/resolution-enqueue-cost-requirements.md`; historical evidence remains intact.

Do not remove backend runtime code as part of this tooling replacement. In
particular, retain `src/capacityLocal.js`, the tested `capacityHttpResolutionOnly`
startup option, the default-off `capacityPhaseMetricsV1Enabled` instrumentation, and
`X-Capacity-*` correlation support. They change no public response contract, their
existing tests are protected, and removing them would overlap unrelated owner edits
in the dirty backend worktree without improving the new harness. Backend documents
that present deleted frontend commands as current are updated or marked historical.

### 2.2 Build the minimal replacement

Recreate `k6/` with only these committed files:

```text
k6/
  README.md
  capacity-test.js
  capacity-contract.mjs
  run-capacity.zsh
  prepare-fixture.mjs
  queue-observer.mjs
  fixture.example.json
  test/capacity-contract.test.mjs
```

Runtime output goes under ignored `k6/results/`. The secret-bearing fixture is
ignored as `k6/fixture.json`.

The runner supports four explicit commands:

```bash
k6/run-capacity.zsh smoke
START_RPS=100 STEP_RPS=50 MAX_RPS=500 k6/run-capacity.zsh find
RPS=250 k6/run-capacity.zsh confirm
RPS=250 SOAK_DURATION=30m k6/run-capacity.zsh soak
```

- `smoke` executes every configured endpoint at least once at negligible load and
  stops on auth, fixture, context, or response-contract failure.
- `find` runs ascending sequence-dependent rungs until the first failure. Each rung has a
  60-second warm-up followed by five measured minutes. Near the boundary, the
  operator reruns `find` with a smaller `STEP_RPS`; the tool does not implement an
  adaptive ladder or mutate committed files.
- `confirm` runs the requested RPS three times with the same 60-second warm-up and
  five-minute measurement. The rate is confirmed only if all three pass.
- `soak` warms for two minutes and measures for 30 minutes by default. Duration may
  be increased explicitly.

Each invocation creates one timestamped directory containing the secret-free
effective config, one k6 JSON summary per run, aggregate-only queue samples when
configured, stdout/stderr, and a concise `result.json`. The runner
prints the artifact path and unambiguous HTTP, queue, and combined benchmark
`pass`/`fail`/`unverified`/`invalid` results. `confirm` additionally records HTTP and
queue confirmation separately; `soak`
records its independent result. Combining them with server telemetry and calculating
the operating limit is an explicit operator step documented in the README. The
runner never commits or edits a historical log.

Process exit codes are fixed: `0` means every configured benchmark gate passed, `1`
means a valid HTTP or queue capacity failure, and `2` means unverified queue evidence
or invalid/configuration/generator/runtime evidence. For `find`, the command stops on
the first failure, unverified, or invalid rung and returns its class. For `confirm`,
any invalid/unverified repeat makes the command invalid/unverified; otherwise any
non-pass makes it a failure with the corresponding confirmation false. A k6 threshold exit maps to failure only
when its expected summary is complete; every other nonzero exit or missing/malformed
summary maps to invalid.

Outcome precedence is `invalid`, then `unverified`, then `fail`, then `pass`. Failure
of an initial, post-warm-up, or post-measurement-setup clean barrier is `invalid`
because the measured starting state is contaminated; a complete measurement whose
lag/failure/drain gate is exceeded is a valid queue `fail`. `smoke` is the sole
exception to combined queue semantics: it is determined by HTTP plus its public seed
postcheck, may exit `0` while reporting informational `queueOutcome: "unverified"`,
and never claims combined capacity.

## 3. Benchmark workload

### 3.1 Traffic model

Use k6 `constant-arrival-rate`, not closed-loop VUs. One iteration performs exactly
one HTTP request, so configured RPS equals offered HTTP RPS. For each rung/repeat the
shell first runs a `PHASE=warmup` k6 process and waits for full process exit, then
starts a separate `PHASE=measure` k6 process. This process boundary prevents in-flight
warm-up requests or `gracefulStop` from overlapping measurement. Every k6 traffic
scenario pins `gracefulStop: "15s"`, matching the request timeout. Warm-up, setup,
measurement, and postcheck use distinct tags; every pass/fail traffic gate is filtered
to `phase=measure`.

Normal traffic uses a deterministic 100-slot route schedule whose slot counts equal
the weights below. The slot is selected from k6's globally unique scenario iteration
index plus a recorded run seed; fixture identity/race selection uses the same seed and
stable hashing. Thus each complete block of 100 arrivals has the exact profile mix,
while a partial block differs by at most one request per route. `smoke` bypasses the
weighted selector and issues one valid request to every route in the table in fixed
order, plus its required setup and resolution postcheck traffic.

Read routes select fixture context by stable hashing. Write routes instead rotate
without replacement through exactly `WORKLOAD_USER_COUNT` selected fixture users;
the input is a required integer from 200 through the fixture cohort size and has no
default. For verified queue runs it also cannot exceed the exact number of planned
measurement write slots, so every selected user receives at least one measured write.
Each user's successive write payload changes its canonical scoring input while
retaining the bounded logical timestamps below. A command-wide write ordinal is
precomputed across every phase, rung, and repeat; warm-up, setup, and measurement
occupy disjoint ordinal ranges, so measurement can never replay a warm-up payload and
be suppressed as unchanged. The result records selected user count, actual
`distinctMeasuredWriteUsers`, selected distinct ACTIVE race count, measurement-only
`offeredWriteRequests`, completed write cycles, writes per selected user, minimum
reuse interval, and queue-observed distinct dirty races. Increasing
`WORKLOAD_USER_COUNT` broadens potential queue work
without changing HTTP RPS or the route mix. Shared race membership remains shared,
so the server's normal race-keyed coalescing is exercised rather than bypassed.

The committed `capacity-benchmark-v1` profile contains thirteen routes. It is a
rounded, normalized subset of the prior measured traffic mix, selected to cover the
largest read paths, all three step-write paths, and resolution polling without
claiming current production equivalence:

| Endpoint | Weight |
|---|---:|
| `GET /races/:id/messages?limit=50` | 26 |
| `GET /challenges/current` | 9 |
| `GET /assets/manifest` | 9 |
| `GET /steps/race-resolution/:jobId?generation=N` | 7 |
| `POST /steps` | 7 |
| `GET /races` | 7 |
| `POST /steps/samples` | 6 |
| `GET /races/:id/progress?view=participants-v1&offset=0&limit=15` | 6 |
| `GET /auth/me` | 5 |
| `POST /steps/sync-v2` | 5 |
| `GET /home/race-card` | 5 |
| `GET /home/suggested-races` | 4 |
| `GET /powerups/inventory` | 4 |

Weights must total exactly 100 and are contract-tested. Each endpoint declares its
method, accepted statuses, required fixture context, and whether it is a critical
write. The exact `capacity-benchmark-v1` request contract is:

- race list is `GET /races?view=compact-v1`;
- Home is
  `GET /home/race-card?view=shell-v1&homeActiveRaces=1&localDate=YYYY-MM-DD`
  without `homePersistedTotals`;
- progress and messages use the exact paths shown in the table;
- suggested races and inventory use their exact parameterless paths;
- legacy `POST /steps` and `POST /steps/samples` require exactly `200`;
- `POST /steps/sync-v2` requires exactly `202`;
- resolution polling and every other normal GET require exactly `200`; and
- `challenges/current` alone accepts exactly `200` or its organic `404`.

No other 2xx or status is silently accepted. No selected endpoint may fall back to
another endpoint.

The profile is deliberately ordinary, synthetic, and stable. It mixes legacy writes
with sync-v2 to preserve the previously observed compatibility traffic; it is not the
request sequence of one released client. Changing routes, weights, request bodies,
headers, thresholds, warm-up, or durations creates a new named benchmark profile and
makes old results non-comparable. A SHA-256 hash of the normalized profile definition
is included in every result. Profile changes are manual code review, not an automated
production-log read.

### 3.2 Client and payloads

The runner requires explicit `APP_VERSION`, `PLATFORM`, `CLIENT_FEATURES`,
`USER_AGENT`, `TIMEZONE`, and `RELEASE_CHANNEL` inputs and has no implicit client
default. `LOCAL_DATE` is also required as exact `YYYY-MM-DD`; Home and daily-step
payloads use it rather than attempting IANA timezone conversion inside k6. The result
records all inputs.
README examples use the current released iOS and Android inputs at implementation
time, but a version change cannot silently alter or stale the benchmark. This keeps
the harness simple while allowing separate iOS, Android, or older-client runs without
embedding an automated production cohort model. Changing these inputs alone does not
make this mixed-route profile representative of an older client; that requires a new
reviewed profile with the older client's exact route and payload contract.

Every authenticated non-asset request sends `Authorization`, `X-Timezone`,
`X-Release-Channel`, `X-App-Version`, `X-Client-Features`, `User-Agent`,
`X-Capacity-Run-Id`, and `X-Capacity-Repeat`; JSON writes also send
`Content-Type: application/json`. `/assets/manifest` follows its distinct released
request shape and sends only `X-Release-Channel` as an application header. Every HTTP
request has a 15-second timeout. Redirect following is disabled globally with
`maxRedirects: 0`; every 3xx response is a capacity failure.

Warm-up has no latency threshold, but its process must finish normally with complete
scheduler accounting. Fixture/setup/auth/context failures, any 401/403, and k6 or
generator failure make the rung invalid before measurement. Other warm-up response
failures are diagnostic and measurement still determines the HTTP capacity outcome.

Write payloads use bounded deterministic distributions:

- `POST /steps`: current logical date and a seeded step count from 500 through
  14,000;
- `POST /steps/samples`: two five-minute samples ending 12 and 17 minutes before the
  logical test time;
- `POST /steps/sync-v2`: current date, a seeded step count, three five-minute samples,
  and a unique deterministic idempotency key.

The workload records that these are benchmark payloads, not measured production
payload distributions. One `LOGICAL_EPOCH_MS` is fixed for the entire command.
Sample boundaries are aligned once to five-minute UTC buckets and reused across all
rungs/repeats in that command; they never advance per request. Daily step rows and
sample rows therefore upsert a bounded set rather than expanding with request count.

Sync-v2 idempotency keys remain unique per request because idempotent replay would
benchmark reservation-cache hits instead of write capacity. Each successful sync can
retain one reservation for seven days. For each run the result records the expected
reservation upper bound as
`ceil(0.05 * RPS * (warmupSeconds + measureSeconds)) + 12`, where twelve covers four
warm-up setup seeds, four measurement setup seeds, and four post-measurement queue
checks. A `find` result
also records the sum across all attempted rungs.

Rungs and repeats intentionally share the accumulating database/cache state inside
one command and are labeled `sequenceDependent: true`; they are not described as
independent samples. `CORPUS_ID` is a required operator input and is recorded with
the non-secret fixture fingerprint. Comparing code revisions or repeating a complete
capacity workflow requires restoring the same operator-managed baseline and reusing
the same `CORPUS_ID`. The README requires recording a before/after corpus fingerprint
or database snapshot identifier beside confirmation and soak evidence; the harness
does not inspect the database itself.

### 3.3 Fixture

`k6/fixture.json` has one exact top-level shape: `schemaVersion`, `issuedAt`,
`expiresAt`, `corpusId`, `cohortFingerprint`, `workloadUsers`, and `resolutionSeeds`.
`workloadUsers` contains at least 200 distinct objects with only `userId`, `token`,
`activeRaceIds`, and `activeRaceSetComplete: true`; every `activeRaceIds` array is
non-empty and unique within that user. `resolutionSeeds` contains exactly four
distinct objects with only `userId`, `token`, and `raceId`. All fixture IDs and tokens
are non-empty strings. Seed identities cannot be workload identities. Their ACTIVE
race IDs must be mutually distinct and must not occur in any workload identity's
complete ACTIVE race set. Fixture validation checks all of these properties so a
workload write cannot supersede a seed's race-keyed job. The required command
`CORPUS_ID` must exactly equal the fixture `corpusId`.

Every participant in every fixture-referenced race must also be an allowlisted
dedicated test identity with no device token; a race containing any non-allowlisted,
review, or notification-capable participant is excluded. This prevents the real
resolution/post-task workers from notifying an unrelated account while crons remain
enabled. The preparer validates the complete roster, not only the selected uploader.

The fixture preparer reports the aggregate count of distinct ACTIVE races available
to each requested cohort size. It never emits race or user identifiers into results.
A queue-oriented run should use a cohort large enough that writes do not merely cycle
through the same few race keys inside the worker debounce window; the result exposes
the counts so an undersized cohort is visible rather than silently called realistic.

Warm-up setup uses all four seeds to create a warm-up-only status pool. After the
warm-up process has fully exited, the queue observer waits up to two minutes for all
warm-up-touched rows to become terminally successful and for claimable/running counts
to return to zero. Measurement never starts on top of residual warm-up queue work.
Measurement setup then creates four new jobs/generations with changed payloads and
waits up to two minutes for those jobs to become terminal and for the entire queue to
be clean. Only then does the observer take the measurement generation/dirty-row
baseline and start HTTP measurement. The four terminal jobs form the 7%
in-measurement status-read pool. This measures the
polling route against a small stable hot set and is not queue health evidence. After
measurement, each seed submits another changed sync payload that
must return a generation strictly greater than its setup generation, and the test
polls those post-measurement jobs to terminal success for up to 60 seconds
using `phase=postcheck`. Postcheck requests are excluded from measurement traffic,
latency, failure, and arrival accounting. Full measured-write queue/backlog health
is measured by the read-only queue observer described in §4. The four seed checks
remain an end-to-end public-contract assertion, not a substitute for aggregate queue
evidence.

`prepare-fixture.mjs` is a read-only convenience command for a local test/capacity
database. It requires an operator-supplied allowlist containing at least 204 dedicated
test user IDs and selects only those IDs, their complete ACTIVE race sets, and race
roster context. It rejects review accounts and every user with any `device_tokens`
row, so test traffic cannot notify a real device. Recent activity is not a test-account
predicate. It signs short-lived sessions using an explicitly supplied test session
secret. To avoid adding application dependencies to the Flutter repo,
it loads `pg` and `jsonwebtoken` from an explicitly supplied `BACKEND_REPO` using
Node `createRequire`; no machine-specific path is committed. It must:

- reject missing inputs;
- accept only `localhost`, `127.0.0.1`, or `::1`; require the database name to match
  the token rule `(^|[_-])(test|capacity)([_-]|$)`; and categorically reject the
  production API hostname, production database hostname, and production database
  name with no override path;
- start a database transaction and make its first statement
  `SET TRANSACTION READ ONLY`, perform no insert, update, delete, migration, flag, or
  schema operation, and roll back/close on every outcome;
- never print tokens, secrets, or connection strings;
- write the fixture with mode `0600`; and
- refuse fewer than 200 valid workload identities or four isolated resolution-seed
  identities;
- sign HS256 tokens with issuer `steps-tracker-api` and each user ID in `sub`, matching
  backend `requireAuth`; and
- include non-secret `issuedAt`, `expiresAt`, cohort count/shape, and a SHA-256 cohort
  fingerprint that excludes tokens, secrets, provider IDs, and database coordinates.

`TOKEN_TTL_SECONDS` is required when preparing a fixture. Validation decodes every
JWT and requires top-level `expiresAt` to equal the earliest integer JWT `exp`; it
does not trust metadata in place of the signed claims. For each rung/repeat, the exact
preflight ceiling is the sum of: 30-second initial baseline; one 15-second batched
warm-up setup; configured warm-up; 15-second graceful stop; 120-second warm-up drain;
one 15-second batched measurement setup; 120-second measurement-setup drain;
configured measurement; 15-second graceful stop; 120-second queue drain; one
15-second batched postcheck submission; and 60-second public postcheck polling. The
command deadline is `now + sum(all rung/repeat ceilings) + 300 seconds`. Smoke uses
its fixed request schedule plus the same applicable batched setup, graceful-stop,
submission, polling, and five-minute safety ceilings. All four seed submissions in a
setup/postcheck batch execute concurrently, so each batch contributes one 15-second
ceiling, not four. The runner rejects a fixture unless every decoded token remains
valid beyond its command deadline. Expiring credentials are `invalid` before traffic,
never a 401 capacity failure.

The example fixture and README allowlist snippet contain placeholders only. No token,
real user ID, race ID, database URL, host, or secret is committed.

Because the preparer categorically accepts only a local database, a staging fixture
must be provisioned separately by the operator from known dedicated accounts. It must
still satisfy the same schema, isolation, device-token exclusion, fingerprint, and
expiry validation before k6 sends traffic.

## 4. Target safety and environment contract

`BASE_URL` is required. There is no production default. Both the shell runner and
k6 setup parse it canonically and require an `http` or `https` origin with no
userinfo, path other than `/`, query, or fragment. Host comparison lowercases and
removes one trailing dot. The exact production host `steptracker-api.org` and every
subdomain of it except the exact staging host `staging.steptracker-api.org` are
categorically refused. `localhost`, `127.0.0.1`, `::1`, and the exact staging host
are accepted. Any other target requires `ALLOW_NONPROD_TARGET=1`; this opt-in cannot
override the production-domain refusal. The canonical target hostname is recorded.
Redirects are disabled (`maxRedirects: 0`) and any 3xx response fails, so a safe
origin cannot redirect traffic to production.

### 4.1 Lightweight resolution-queue observation

Verified `find`, `confirm`, and `soak` launch `queue-observer.mjs` beside k6 when an
explicit `QUEUE_DATABASE_URL` is supplied. Verified queue evidence additionally
requires a loopback `BASE_URL`, `QUEUE_TARGET_CONFIRMED=1`, and a recorded operator
assertion that the backend process serving that exact origin uses that exact database.
Staging or any other remote HTTP origin always has `queueOutcome: "unverified"`; a
coincidentally active local database can never be paired with it. The observer loads
`pg` from `BACKEND_REPO`, applies
the same local-host and test/capacity database-name allowlist as the fixture preparer,
and has no remote or production override. Each ten-second sample is one short
transaction whose first statement is `SET TRANSACTION READ ONLY`; it uses a two-second
statement timeout, rolls back, and closes cleanly. It never writes, acquires row
locks, returns identifiers, or prints the connection string.

Before traffic, three consecutive samples must show zero total `queued` and zero
total `running` jobs, including work still delayed by `retry_at` or `not_before_at`.
It requires the same zero-queued/zero-running barrier after warm-up and again after
measurement setup before measurement can begin. During traffic the ten-second query
uses `WHERE state IN ('queued','running')` and the worker's exact claimable predicate:
queued with both `retry_at` and `not_before_at` due/null, or running with an expired
non-null lease. Its only projections are queued count, running count, claimable count,
maximum request age, and maximum claimable request age. The boundary query alone
captures failed count, `SUM(generation)`, and aggregate distinct rows whose
`requested_at` falls inside the measured window; it runs before measurement or after
HTTP traffic, never on the measured path. The observer samples through a fixed two-minute
drain window after HTTP measurement ends. Queue evidence
passes only when:

- at least one measured queue generation and one distinct dirty race are observed;
- no new failed job appears;
- sampled oldest claimable age p95 is at most the worker's existing 30-second alarm
  boundary;
- the final sample has zero total queued and zero total running jobs; and
- every race row touched during measurement is terminally successful by the end of
  the drain window.

Observer failure, incomplete samples, a dirty pre-measurement barrier, or missing
aggregate fields is `invalid`. A complete measured lag/drain/failure gate violation
is a valid queue `fail`. Omitting `QUEUE_DATABASE_URL` yields
`queueOutcome: "unverified"` for `smoke`; `find`, `confirm`, and `soak` reject it
during preflight with exit `2` before sending traffic. Queue sampling adds one indexed
service SELECT every ten seconds plus boundary snapshots. Observer query duration p95
must be at most 100 ms and maximum at most 250 ms; exceeding either budget makes queue
evidence `unverified`, not a target failure. Cadence, query p95/max, and boundary-query
durations are recorded so overhead remains visible.

`RESOLUTION_WORKER_ENABLED=1` is a required operator attestation for verified queue
runs. The harness does not toggle the worker or any cron. The environment must use
the intended production-equivalent resolution concurrency. All other application
crons/background workers remain operator-managed; their enabled/disabled state is
recorded. Database-wide scanning cron cost is represented only when the test corpus
has comparable size and shape, not by increasing k6 RPS alone.

The test environment is operator-managed. The harness does not create, restore,
migrate, start, stop, or delete infrastructure. Before a capacity claim, the operator
must record in the result metadata or adjacent run notes:

- backend revision and flags;
- CPU/memory limits and Node worker count;
- PostgreSQL and Redis topology;
- application and PgBouncer pool sizes;
- whether normal background workers are enabled;
- database corpus identity/size; and
- whether the load generator is on separate hardware.

`GENERATOR_CAPACITY_VERIFIED=1` is an explicit operator attestation that k6 is on
adequate hardware and its CPU/memory were observed for this command. It is recorded
in the result and has no default. Absence does not prevent a run, but any dropped
arrival then makes the result `invalid` rather than blaming the target.

The README states plainly that an absolute production-capacity claim requires a
non-production environment with comparable application, database, Redis, network,
and background-job characteristics. A local or differently sized staging result is a
relative benchmark only.

The runner never runs migrations, touches production via SSH, changes production
flags, deploys code, flushes Redis, or writes to a production database.
It never installs, edits, or invokes a scheduled k6 cron or crontab entry; all four
commands are explicit operator actions.

## 5. Gates and result semantics

Measurement traffic passes a rung only when all of these hold:

- planned arrivals equal completed plus dropped arrivals;
- dropped arrivals equal zero;
- capacity failure rate is below 1%;
- rate-limited responses are below 1% and are also capacity failures;
- overall HTTP p95 is below 2 seconds and p99 below 5 seconds;
- combined critical-write p95 is below 2 seconds, p99 below 5 seconds, and maximum
  below 15 seconds;
- context fallback is zero;
- every configured endpoint executes at least once; and
- every dedicated resolution job reaches a terminal success state within 60 seconds
  after traffic, with no failure/superseded result.

A combined benchmark rung passes only when the HTTP gates above and the §4.1 queue
gates both pass. An HTTP pass with unverified or failed queue evidence remains visible
as an HTTP pass but is not a combined benchmark pass. `find` therefore discovers the
first rung limited by either the HTTP service or the resolution worker.

Unexpected k6/runtime termination, malformed or missing fixture/config, missing
summary fields, incomplete scheduler accounting, or generator-side resource
exhaustion is `invalid`, not a backend failure. The runner cannot automatically prove
generator CPU/memory health without reintroducing host orchestration, so the README
requires running k6 on separate adequately sized hardware and checking its standard
`dropped_iterations`, VU, CPU, and memory output.

VU allocation is fixed by profile as
`preAllocatedVUs = max(50, ceil(RPS * 2.5))` and
`maxVUs = max(preAllocatedVUs, ceil(RPS * 6))`, with the exact values recorded.
When `GENERATOR_CAPACITY_VERIFIED=1`, scheduler-complete dropped arrivals are a valid
HTTP capacity failure. Without that attestation, any dropped arrival is `invalid`.
Warnings about insufficient VUs, generator CPU/memory exhaustion, or malformed VU
metrics are always `invalid` regardless of the attestation.

Every `result.json` uses this bounded shape (per-run measurements are repeated in the
`runs` array for `find` and `confirm`):

```json
{
  "schemaVersion": "simple-capacity-result-v1",
  "command": "smoke|find|confirm|soak",
  "benchmarkOutcome": "pass|fail|unverified|invalid",
  "httpOutcome": "pass|fail|invalid",
  "queueOutcome": "pass|fail|unverified|invalid",
  "httpConfirmed": false,
  "queueConfirmed": false,
  "systemTelemetryVerified": false,
  "reasons": [],
  "profile": {"name": "capacity-benchmark-v1", "sha256": "..."},
  "targetHostname": "127.0.0.1",
  "queueTargetConfirmed": true,
  "client": {
    "appVersion": "...", "platform": "...", "clientFeatures": "...",
    "userAgent": "...", "timezone": "...", "releaseChannel": "...",
    "localDate": "YYYY-MM-DD"
  },
  "corpusId": "...",
  "fixtureFingerprint": "sha256:...",
  "workloadUserCount": 1000,
  "distinctMeasuredWriteUsers": 1000,
  "selectedActiveRaceCount": 1400,
  "sequenceDependent": true,
  "generatorCapacityVerified": false,
  "runs": [{
    "rps": 250,
    "plannedTotal": 90000,
    "plannedMeasure": 75000,
    "completedMeasure": 75000,
    "dropped": 0,
    "expectedSyncReservationsMax": 4512,
    "offeredWriteRequests": 13500,
    "queue": {
      "observed": true,
      "sampleIntervalSeconds": 10,
      "distinctDirtyRaces": 900,
      "generationDelta": 1200,
      "oldestClaimableAgeP95Ms": 12000,
      "drainSeconds": 34,
      "newFailedJobs": 0,
      "observerQueryP95Ms": 18,
      "observerQueryMaxMs": 41,
      "finalQueued": 0,
      "finalRunning": 0
    },
    "gates": {},
    "benchmarkOutcome": "pass|fail|unverified|invalid",
    "httpOutcome": "pass|fail|invalid",
    "queueOutcome": "pass|fail|unverified|invalid",
    "reasons": []
  }]
}
```

`httpConfirmed` is true only for a `confirm` command with three HTTP passes;
`queueConfirmed` independently requires three queue passes. Neither means full system
capacity is confirmed. `systemTelemetryVerified` is always false because the minimal
runner ingests only the narrow queue snapshot, not CPU, memory, pool, Redis, or other
server telemetry. The search output is called the
`firstFailedRung`; one failed search rung is not a consistently failing ceiling.

The HTTP result alone does not certify operational capacity. Confirmation and soak
also require the operator to check and record:

- application CPU remains below 90% sustained;
- no OOM or worker restart;
- database and application pool timeouts are zero;
- deadlock delta is zero;
- resolution backlog drains rather than grows; and
- available memory retains an agreed production headroom.

The tool reports these as a required manual checklist, not fabricated automated
evidence. A run with unchecked server telemetry may be called an HTTP benchmark pass,
but not a confirmed system capacity.

## 6. API contract

There is no new or changed public endpoint and no response-shape change. The harness
uses a pinned synthetic mix of existing released request contracts as specified in
§3.1; it does not claim one client issues that whole mix. It may send the existing
optional `X-Capacity-Run-Id` and `X-Capacity-Repeat` observability headers; older or
newer backends that ignore them remain compatible. A distinct older-client benchmark
requires a separately named profile pinning that client's routes, headers, bodies,
timeouts, and statuses.

No backend field is required beyond fields already consumed by the corresponding
released client request, except the existing sync-v2 resolution job ID/generation
used for polling. Setup fails clearly if the selected backend does not provide that
existing contract.

## 7. Data model and migrations

No schema change, migration, backfill, seed, or production data write is introduced.
Fixture generation is SELECT-only. Load traffic intentionally writes only to the
explicitly supplied non-production target and its dedicated test identities.

## 8. Frontend and platform plan

There is no Flutter UI or Dart runtime change. iOS and Android application behavior
is unchanged. Both platforms are represented operationally by running the same
benchmark with their actual released version, feature header, and platform label;
this is a benchmark input, not a mobile build change.

No manual UI-placement plan is required.

## 9. Backward compatibility and rollout

Deleting the old tooling changes no mobile/backend HTTP behavior. The backend
capacity-only startup entrypoint and default-off capacity phase telemetry remain
available and unchanged.

There is no backend/app deploy order because this is developer tooling only. No
production deployment is authorized by implementation approval. Backend changes are
documentation-only and do not require a runtime deployment.

Private historical artifacts outside the repository remain recoverable and are not
automatically erased. Existing committed historical results disappear with the old
`k6/` tree as explicitly authorized.

## 10. Tests-first implementation plan

### 10.1 Frontend/k6 agent

Before deleting or writing implementation logic, add the new
`k6/test/capacity-contract.test.mjs` against the intended replacement interfaces and
observe failures for missing modules/files. It must prove:

1. profile weights total exactly 100 and endpoint keys are unique;
2. every endpoint has the exact method/path/query, context, accepted status,
   released header shape, body, 15-second timeout, redirect refusal, and request
   construction pinned in §3.1; the deterministic 100-slot selector has the exact
   per-route counts and smoke executes every route once in fixed order;
3. canonical target parsing rejects userinfo/path/query/fragment, production and
   production-subdomain targets remain categorical refusals, trailing-dot/case
   normalization cannot bypass them, redirects fail, and unknown non-production
   targets require the explicit opt-in;
4. fixtures under 200 workload users, without four isolated seeds, with duplicate
   identities, missing complete ACTIVE race context, overlapping seed races, or a seed
   race present in any workload identity are rejected; races with any non-allowlisted,
   review, or device-token-bearing participant are rejected; `WORKLOAD_USER_COUNT`
   is required and bounded by the fixture and planned measurement writes, write
   selection cycles without replacement, warm-up/measurement ordinals cannot replay,
   and actual measured-user/distinct-ACTIVE-race counts are accurate;
5. expected challenge 404 is accepted while 401/403/408/409/429/5xx/status 0 classify
   correctly;
6. missing counters and scheduler-accounting mismatch are invalid rather than pass;
7. dropped arrivals with and without generator attestation, insufficient-VU warnings,
   VU formulas, latency, failure-rate, write-latency, context, and post-measurement
   resolution gates classify correctly at exact boundaries;
8. `confirm` requires three passes and never accepts a 2/3 result;
9. `confirm` reports confirmed only for 3/3 passes, `soak` remains independent, and
   the documented operating-limit formula floors 70% to a whole RPS without claiming
   that the runner verified server telemetry;
10. fixed logical time aligns/reuses sample buckets, reservation upper bounds are
    correct for every command, results are sequence-dependent, and `CORPUS_ID` is
    required;
11. exact `simple-capacity-result-v1` output separates benchmark, HTTP, and queue
    outcomes/confirmation, never sets `systemTelemetryVerified`, exposes the first
    failed rung without calling it a repeated ceiling, includes workload/dirty-race
    counts and all required gates/reasons/profile hash, and contains no token, secret,
    database coordinate, user/race identifier, or authorization header;
12. hermetic runner integration tests put a temporary fake k6 executable in
    `K6_BIN` and exercise pass, threshold exit, process crash, missing/malformed
    summary, warm-up process exit before measurement launch, find stopping at its
    first HTTP- or queue-failed rung, 3/3 confirmation, 2/3 rejection, unverified
    queue evidence, outcome precedence, the smoke queue exception, soak invocation,
    command exit codes `0/1/2`, and secret-free
    artifacts; regex/source
    assertions are not substitutes for those executions;
13. fixture-preparer tests use a fake backend dependency directory/DB client to prove
    the local DB allowlist and categorical production refusal, the first transaction
    statement is `SET TRANSACTION READ ONLY`, rollback/close occurs on failure, the
    operator allowlist/device-token/review filters apply, JWTs use HS256 with issuer
    `steps-tracker-api` and `sub=userId`, top-level expiry equals the earliest decoded
    JWT `exp`, and the exact per-run token-expiry formula covers every baseline, batch,
    phase, graceful stop, barrier/drain, and postcheck plus five minutes;
14. setup status-read seeds and post-measurement generations are distinct, postcheck
    requests cannot enter measured metrics, warm-up setup cannot supply measurement
    status IDs, warm-up and measurement-setup queue work drain before the measurement
    aggregate baseline, and
    failed/superseded/timeout postchecks fail;
15. the example fixture and README allowlist example contain no real identifiers or
    tokens; and
16. ignored runtime paths cover `k6/fixture.json` and `k6/results/`, exact tracked-file
    deletion preserves pre-existing ignored/untracked paths, and the pre-deletion
    binary diff archive exists outside the repo; and
17. queue-observer tests use a fake `pg` backend to prove local/test database safety,
    loopback HTTP/database target binding and remote-target refusal, first-statement
    read-only transactions, rollback/close and two-second timeout, exact indexed
    ten-second service query versus boundary-only aggregates, aggregate-only output,
    zero-total-queued/running barriers before traffic/after warm-up/after measurement
    setup, exact 30-second lag and 100/250 ms observer-overhead boundaries, failure
    detection, two-minute drain, dirty-race/generation counts, and fail-closed handling
    of incomplete samples.

After the tests fail for the intended missing implementation, archive the existing
k6 diff, delete the exact old tracked-file manifest with `apply_patch`, prove ignored
private paths survived, and land the replacement in the order: contract/profile, k6
workload, fixture preparer, runner, documentation.

The manual smoke acceptance test then runs against an explicitly configured local or
staging target and verifies all thirteen routes execute successfully. It must never
run against production.

### 10.2 Backend agent

Lock the unchanged API/startup contract and update only stale backend documentation
commands to the new frontend README or label them historical. Do not edit backend
runtime source, tests, configuration, migrations, or dependencies. Verify with
`git diff --check`; existing backend tests need not be rerun for documentation-only
edits.

### 10.3 Verification

- `node --test k6/test/*.test.mjs`
- `zsh -n k6/run-capacity.zsh`
- `node --check k6/*.mjs`
- `k6 inspect --include-system-env-vars k6/capacity-test.js` with non-secret dummy
  inputs
- deterministic local/staging smoke, when a safe target and fixture are available
- `git diff --check`
- `flutter analyze`
- `flutter test`
- backend `git diff --check` for documentation-only edits
- final `code-reviewer` review across both repositories

No iOS/Android build is required because Dart, plugins, dependencies, and platform
projects are untouched. Both platform request cohorts remain an explicit benchmark
input and are documented.

## 11. Acceptance criteria

- The exact old 39 tracked k6 files are gone; their pre-deletion diff is privately
  archived; ignored/untracked private paths survive unchanged; and the replacement
  contains only the eight listed committed files plus ignored runtime artifacts.
- One documented command performs each of smoke, find, confirm, and soak.
- Offered RPS is constant-arrival HTTP request rate, not VU count or multi-request
  iteration rate.
- The warm-up k6 process fully exits before the measurement process starts, preventing
  warm-up from contaminating measured load or gates.
- The first failed search rung stops the search and remains visible in artifacts.
- Confirmation requires three consecutive passes at one RPS.
- Soak defaults to 30 measured minutes.
- Write traffic rotates through the explicit workload-user cohort and results record
  selected users, distinct ACTIVE races, queue generations, and observed dirty races.
- Verified find/confirm/soak runs sample the local non-production resolution queue,
  begin measurement only after warm-up queue drain, and require bounded claimable lag
  plus a successful two-minute post-load drain.
- Queue evidence is accepted only for a loopback HTTP target explicitly bound to the
  observed local test/capacity database; remote targets cannot borrow local evidence.
- The tool never targets production, mutates committed result logs, reads production
  via SSH, manages infrastructure, or reports DAU.
- Fixture generation is SELECT-only and refuses ambiguous database targets.
- Fixture generation requires an explicit dedicated-test-user allowlist, excludes
  review/device-token users, uses a DB-enforced read-only transaction, isolates seed
  races, emits the exact JWT contract, and preflights expiry for the whole command.
- Results use the exact bounded schema, contain no secrets, include a profile hash,
  and never conflate `httpConfirmed` with system capacity.
- Results clearly separate HTTP benchmark pass from manually verified system
  capacity.
- Existing mobile API behavior and old clients are unaffected.
- Required tests and analysis are green, or skipped safe-target smoke/integration
  steps are reported plainly.

## 12. Non-goals

- Exact replay of production sessions, per-user burst behavior, platform shares, or
  payload distributions.
- Automatic production-log analysis or traffic-profile refresh.
- Automated infrastructure provisioning, database restore/migration, process
  management, Redis flushing, or production flag capture.
- Production load generation or production DB writes.
- DAU conversion or a certified production capacity number from unlike hardware.
- Autoscaling, chaos, failover, cold-start, or disaster-recovery testing.
- UI, API, scoring, economy, or game-balance changes.

## 13. Implementation ownership and order

1. Backend agent locks the unchanged public API/startup contract and updates stale
   documentation only.
2. After that contract is fixed, the frontend/k6 agent performs the tests-first
   replacement. Work may proceed in parallel once both agree no API change is needed.
3. The root agent runs combined verification and the `code-reviewer` subagent.
4. No production deployment or private artifact deletion is included.

Both agents must preserve unrelated dirty-worktree changes. In particular, backend
runtime, startup, scheduler, test, schema, and migration files currently contain
unrelated owner work and are out of scope.

## 14. Revision log

- **Draft (2026-08-19):** Replaced the daily production-snapshot/Lima system with an
  explicit smoke/find/confirm/soak workflow; fixed the benchmark to thirteen routes;
  separated HTTP pass from system-capacity verification; scoped destructive cleanup;
  preserved generic capacity telemetry; and prohibited production targeting.
- **Gap pass 1 (2026-08-19):** Removed hidden cross-run state and automatic capacity
  claims; made confirmation and soak independent artifacts; defined the 70% whole-RPS
  calculation as an operator conclusion; raised the fixture floor to 200 users; and
  pinned dependency loading for the read-only fixture preparer without adding Flutter
  repo packages or machine-specific paths.
- **Gap pass 2 (2026-08-19):** Preserved protected backend runtime/tests and narrowed
  backend work to documentation; corrected the teardown inventory to 39 files;
  required explicit version/platform/features/User-Agent inputs; required
  secret-free effective-config artifacts; and made the fixture database allowlist
  concrete.
- **Architect review (2026-08-19):** Pinned exact mixed-profile routes, headers,
  statuses, timeout, and redirect policy; added a profile hash; required allowlisted
  notification-free test identities and race-isolated resolution seeds; moved queue
  verification to fresh post-measurement generations; bounded sample/reservation
  mutation and labeled sequential state; hardened URL/DB/JWT/expiry safety; defined
  VU and dropped-arrival semantics; introduced the exact non-claiming result schema;
  replaced structural runner checks with hermetic fake-k6 integration tests; and
  required exact tracked-file deletion plus private dirty-diff preservation.
- **Post-architect gap pass 1 (2026-08-19):** Required an explicit local date instead
  of implicit timezone math; defined warm-up validity versus diagnostic failures;
  fixed pass/fail/invalid exit codes and multi-run aggregation; and made threshold
  exits conditional on complete summaries.
- **Post-architect gap pass 2 (2026-08-19):** Pinned deterministic 100-slot route and
  smoke selection; defined the exact fixture schema and corpus match; separated
  warm-up resolution jobs from measurement jobs; and included every possible
  postcheck timeout in credential-expiry preflight.
- **Queue-load refinement (2026-08-19):** Added required distinct-user rotation and a
  lightweight read-only aggregate queue observer; separated HTTP, queue, and combined
  outcomes; required clean pre-measurement state and bounded post-load drain; and kept
  other cron/background-worker configuration operator-managed and explicitly
  recorded.
- **Queue architecture re-review (2026-08-19):** Bounded configured users by actual
  measured write slots and recorded touched users; isolated measurement from warm-up
  and setup queue work; made all barriers reject delayed queued rows; bound local DB
  evidence to a loopback HTTP target; pinned indexed periodic versus boundary-only
  observer queries and overhead budgets; resolved smoke/outcome precedence; and made
  JWT expiry validation an exact sum of every possible phase ceiling.
- **Final architect confirmation (2026-08-19):** Approved with no remaining required
  changes or suggestions.
