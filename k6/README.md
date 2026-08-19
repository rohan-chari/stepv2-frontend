# Simple capacity benchmark

This directory contains the only current k6 capacity workflow for Steps Tracker. It
finds where a fixed **non-production** environment first misses the pinned HTTP or
resolution-queue gates, whether a rate passes three times, and whether it survives a
longer soak. It is a relative benchmark unless the application, database, Redis,
network, background jobs, and limits are production-comparable. It never converts
RPS to DAU or certifies system capacity from HTTP alone.

The old daily ladder, production snapshot/Lima lifecycle, cohort replay,
optimization comparison, and `users.json` workflows are obsolete. Historical
documents may describe them as evidence, but they are not current commands.

## Hard safety boundary

`BASE_URL` has no default. The runner categorically refuses `steptracker-api.org`
and every subdomain except exact staging, even with `ALLOW_NONPROD_TARGET=1`. It
accepts loopback and `staging.steptracker-api.org`; another non-production origin
needs `ALLOW_NONPROD_TARGET=1`. Origins may not contain userinfo, a path, query, or
fragment. Redirects are disabled and every 3xx fails.

Verified `find`, `confirm`, and `soak` runs require a loopback `BASE_URL`, a
loopback PostgreSQL test/capacity database, and:

```sh
QUEUE_TARGET_CONFIRMED=1
RESOLUTION_WORKER_ENABLED=1
BACKEND_REPO='<local backend checkout>'
QUEUE_DATABASE_URL='postgresql://<local-user>:<local-password>@127.0.0.1/<database_capacity_test>'
```

`QUEUE_TARGET_CONFIRMED=1` attests that the process serving the exact origin uses
that exact database. Remote targets can never borrow local queue evidence. The
observer performs one indexed aggregate SELECT every ten seconds in a short
read-only transaction with a two-second statement timeout. It returns no IDs and
never writes or locks rows.

The harness does not provision, restore, migrate, start, stop, deploy, SSH, toggle
flags, flush Redis, manage Lima, or install cron entries. It never targets a
production database. Keep normal background workers in the intended state and
record that state with the run.

## Fixture

The secret fixture is `k6/fixture.json` (ignored, mode 0600). The example shows
shape only and intentionally cannot run: replace placeholders and provide at least
200 workload identities plus exactly four isolated seeds. `k6/users.json` remains
private but is not consumed by this harness.

Create a private JSON allowlist with at least 204 dedicated test IDs:

```json
[
  "<dedicated-test-user-id>",
  "<another-dedicated-test-user-id>"
]
```

Then run the local, SELECT-only preparer. It loads `pg` and `jsonwebtoken` from the
backend checkout, makes `SET TRANSACTION READ ONLY` the first transaction statement,
rejects review/device-token identities and unsafe complete race rosters, and always
rolls back and closes.

```sh
DATABASE_URL='postgresql://<local-user>:<local-password>@127.0.0.1/<database_capacity_test>' \
BACKEND_REPO='<local backend checkout>' \
SESSION_SECRET='<explicit test-only session secret>' \
TOKEN_TTL_SECONDS=14400 \
CORPUS_ID='<restored-baseline-id>' \
ALLOWLIST_PATH='<private allowlist.json>' \
node k6/prepare-fixture.mjs
```

The preparer signs HS256 sessions with issuer `steps-tracker-api` and user ID in
`sub`. The runner decodes every JWT and requires top-level `expiresAt` to equal the
earliest signed `exp`; every token must outlive the exact command ceiling plus five
minutes. Staging fixtures are provisioned separately from known dedicated accounts
and must satisfy the same schema/isolation checks.

## Required client inputs

Every run requires `APP_VERSION`, `PLATFORM`, `CLIENT_FEATURES`, `USER_AGENT`,
`TIMEZONE`, `RELEASE_CHANNEL`, `LOCAL_DATE`, `CORPUS_ID`, and
`WORKLOAD_USER_COUNT`. `LOCAL_DATE` is exact `YYYY-MM-DD`; user count is an integer
from 200 through fixture size and, for verified queue runs, no larger than planned
measured write slots.

These examples pin the repository's current 2.3.8 release inputs as of 2026-08-19.
They do not turn the mixed profile into a released-client journey; re-verify inputs
against the actual binary whenever the version changes.

```sh
# Current iOS App Store build (prod ad defines enabled)
export APP_VERSION='2.3.8'
export PLATFORM='ios'
export USER_AGENT='Bara/2.3.8 CFNetwork/3860.700.1 Darwin/25.6.0'
export RELEASE_CHANNEL='prod'
export CLIENT_FEATURES='characters,ads,jammer,spinpowerups,team_races,tournaments,race_leave,powerups2,powerups3,powerups4,powerups5,stealth_runner_duration,hitchhike_effective_steps,remote_assets,remote_asset_preferred,next_race_cta,discoverable_identity,home_suggested_races,seeded_race_buckets,home_invite_modal,race_participants_paging,race_preview,impact_notices,impact_summaries,review_prompt,inbox_v1,api_payload_compact_v1,admin_metrics_v2,race_payout_double'

# Current Android prod build (add ad capabilities only when its defines exist)
export APP_VERSION='2.3.8'
export PLATFORM='android'
export USER_AGENT='Dart/3.12 (dart:io)'
export RELEASE_CHANNEL='prod'
export CLIENT_FEATURES='characters,jammer,spinpowerups,team_races,tournaments,race_leave,powerups2,powerups3,powerups4,powerups5,stealth_runner_duration,hitchhike_effective_steps,remote_assets,remote_asset_preferred,next_race_cta,discoverable_identity,home_suggested_races,seeded_race_buckets,home_invite_modal,race_participants_paging,race_preview,impact_notices,impact_summaries,review_prompt,inbox_v1,api_payload_compact_v1'

export BASE_URL='http://127.0.0.1:3000'
export TIMEZONE='America/New_York'
export LOCAL_DATE='2026-08-19'
export CORPUS_ID='<restored-baseline-id>'
export WORKLOAD_USER_COUNT=1000
export FIXTURE_PATH="$PWD/k6/fixture.json"
```

The runner chooses one command-wide logical epoch anchored exactly two minutes after
a five-minute UTC boundary. This makes sample ends exactly 7, 12, and 17 minutes
before that epoch while keeping every end on a five-minute boundary. An explicit
`LOGICAL_EPOCH_MS` must use the same anchor or preflight rejects it.

## Commands

```sh
k6/run-capacity.zsh smoke
START_RPS=100 STEP_RPS=50 MAX_RPS=500 k6/run-capacity.zsh find
RPS=250 k6/run-capacity.zsh confirm
RPS=250 SOAK_DURATION=30m k6/run-capacity.zsh soak
```

- `smoke` executes all thirteen routes once and the public four-seed postcheck. It
  may pass with `queueOutcome: "unverified"` and never claims combined capacity.
- `find` runs ascending sequence-dependent rungs with 60 seconds warm-up and five
  measured minutes, stopping at the first fail/unverified/invalid rung. Near the
  boundary, restore the corpus and use a smaller `STEP_RPS`.
- `confirm` runs one rate three times. HTTP and queue confirmation are independent
  and require 3/3; 2/3 is not confirmed.
- `soak` warms for two minutes and measures for 30 minutes by default.

Every normal iteration sends exactly one request under `constant-arrival-rate`, so
RPS is offered HTTP RPS, not VUs. Warm-up and measurement are separate processes
with `gracefulStop: "15s"`. A parent watchdog terminates a non-smoke k6 phase after
its nominal duration plus at most 30 seconds (smoke uses its pinned five-minute
maximum), and any HTTP request that materially exceeds the configured 15-second
request timeout makes the evidence invalid. Four seed generations are prepared and polled, with
aggregate clean queue barriers after warm-up and measurement setup; each barrier also
requires terminal success for the four exact setup job/generation pairs. The observer
records timestamps and rejects missing or materially late ten-second samples. Four strictly
newer post-measurement generations are then polled outside measured gates while the
observer samples a fixed two-minute drain.

The fixed `capacity-benchmark-v1` route weights total 100:

| Route | Weight |
|---|---:|
| `GET /races/:id/messages?limit=50` | 26 |
| `GET /challenges/current` | 9 |
| `GET /assets/manifest` | 9 |
| `GET /steps/race-resolution/:jobId?generation=N` | 7 |
| `POST /steps` | 7 |
| `GET /races?view=compact-v1` | 7 |
| `POST /steps/samples` | 6 |
| `GET /races/:id/progress?view=participants-v1&offset=0&limit=15` | 6 |
| `GET /auth/me` | 5 |
| `POST /steps/sync-v2` | 5 |
| `GET /home/race-card?view=shell-v1&homeActiveRaces=1&localDate=…` | 5 |
| `GET /home/suggested-races` | 4 |
| `GET /powerups/inventory` | 4 |

Changing routes, weights, bodies, headers, statuses, timeout, gates, warm-up, or
durations requires a new profile name. Results include its normalized SHA-256. The
payloads are bounded synthetic benchmark inputs, not measured production payloads.

## Results and interpretation

Each invocation creates a private timestamped directory under ignored `k6/results/`
with secret-free effective config, stdout/stderr, one measurement summary and
aggregate-only queue evidence per run, per-run classifications, and `result.json`.

- Exit `0`: every configured benchmark gate passed.
- Exit `1`: a valid HTTP or queue capacity gate failed.
- Exit `2`: evidence is invalid/unverified, configuration failed, or a
  generator/runtime failed.

Precedence is `invalid`, `unverified`, `fail`, `pass`. A complete k6 threshold exit
is a valid failure; crash or missing/malformed summary is invalid. Without
`GENERATOR_CAPACITY_VERIFIED=1`, dropped arrivals are invalid. That attestation says
k6 hardware was observed and adequate; insufficient-VU or generator resource
warnings are always invalid.

Runs accumulate database/cache state and report `sequenceDependent: true`. Before
comparing revisions, restore the same baseline, reuse `CORPUS_ID`, and record a
before/after corpus fingerprint or snapshot identifier beside confirmation/soak.

After 3/3 confirmation and an independent soak, check server telemetry and only then
apply the initial operator policy:

```text
operating limit = floor(confirmed RPS × 0.70)
```

The 30% headroom is policy, not a measured property. The runner never calculates or
claims it. Verify CPU below 90% sustained, no OOM/restart, zero pool timeouts, zero
deadlock delta, draining resolution backlog, and agreed free-memory headroom. Record
backend revision/flags, limits, Node workers, PostgreSQL/Redis topology, application
and PgBouncer pools, background-worker state, corpus size, and generator placement.
The runner cannot ingest these, so `systemTelemetryVerified` is always false.

## Verification

```sh
node --test k6/test/*.test.mjs
zsh -n k6/run-capacity.zsh
node --check k6/*.mjs
k6 inspect --include-system-env-vars k6/capacity-test.js
```

Only smoke after supplying an explicitly safe local/staging target and dedicated
fixture. Never use production.
