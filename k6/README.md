# k6 capacity testing

The supported workflow is a single-current-state daily diagnostic. It uses the
latest fetched backend `main`, one redacted read-only snapshot of production's
effective flags, a sanitized private corpus, a 2-vCPU/2-GiB Lima VM, two Node
workers, and PgBouncer pool 25. Load traffic always stays on localhost.

## Run

From the frontend repository:

```bash
k6/local-prod-sim/run-daily-capacity-diagnostic.zsh
```

The first comparable run tests 150 RPS. A valid pass advances the next daily
invocation by 100 RPS; breaking and invalid runs retry that boundary. An
operator-only override may select another standard rung without changing the
daily ladder:

```bash
RPS_OVERRIDE=350 k6/local-prod-sim/run-daily-capacity-diagnostic.zsh
```

See [LOCAL-PROD-SIM-RUNBOOK.md](LOCAL-PROD-SIM-RUNBOOK.md) for private setup,
the production read boundary, teardown verification, and stale-lock recovery.
The command pins `FETCH_HEAD`, packages that exact Git object, captures only
allowlisted production settings, restores and migrates the local corpus,
remints local-only sessions, runs one checkpoint, saves private evidence,
appends the bounded log below, and verifies teardown.

## What the harness models

`prod-mix-load-test.js` is a constant-arrival-rate model of the released 2.3.7
client mix. Its contract lives in `harness-contract.mjs` and includes:

- exact released-client headers and 26 weighted endpoints;
- participant paging with `limit=15`;
- ACTIVE/PENDING/team/solo/roster-size fixture context;
- dedicated, current-run resolution jobs;
- exact selected/executed/status accounting;
- 429, hard-failure, dropped-arrival and resolution-state metrics; and
- deterministic endpoint, user, payload randomness and logical timestamps.

Every daily rung is a 35-second constant-arrival window. The first five
seconds' offered arrivals are warm-up; steady-state classification covers the
remaining 30 seconds. Raw HTTP accounting includes only samples explicitly
tagged `warmup` or `steady`; setup and resolution-drain requests are excluded
from offered-traffic counts. VU allocation is `ceil(RPS × 2.4)` initially and
`ceil(RPS × 3.2)` maximum.

## Interpreting results

The daily result is a trend canary, not a deployment gate, exact production
conversion, or certified DAU ceiling. Classification first validates scheduler
accounting plus load-generator and server-health evidence. Missing provenance,
accounting, or evidence is `invalid`; it is never silently treated as zero or
a passing run.

A valid rung is `breaking` for dropped arrivals, at least 1% steady capacity or
hard failures (including 429/0/5xx), HTTP p95 ≥2s or p99 ≥5s, critical-write
p95 ≥2s/p99 ≥5s/max ≥15s, resolution lag/failure/drain, P2028/pool timeout/
deadlock/OOM, a PM2 worker restart/non-online state, or guest `MemAvailable`
below 300 MiB. Load-generator exhaustion and incomplete evidence are invalid,
not backend breakage.

Historical optimization comparisons remain callable only as historical tools
and are indexed in [findings/README.md](findings/README.md). They never drive
the daily ladder.

## Daily run log

The visible row is paired with a strict machine JSON comment. The runner reads
only this bounded block while holding its single-run lock and atomically appends
one row per invocation. A compatibility-fingerprint change begins a new series
at 150 RPS. Rough DAU is offered RPS divided by the `0.0259` peak-RPS/DAU
coefficient and rounded to the nearest 100; invalid runs show `—`.

<!-- DAILY_K6_LOG_V1_START -->
| Day / local date | Backend | Prod flags | Tested RPS | Result | Known floor / ceiling | Rough DAU | Note |
|---|---|---|---:|---|---|---:|---|
<!-- DAILY_K6_LOG_V1 {"schemaVersion":"daily-k6-log-v1","day":1,"runId":"historical-aborted-20260818-260rps","localDate":"2026-08-18","standard":false,"testedRps":260,"classification":"invalid","floor":null,"ceiling":null,"fingerprint":"historical-invalid","seriesCompatibility":"historical-invalid","backend":"b4f3f4642005","snapshotHash":null,"roughDau":null,"note":"resolution seed sync returned 401 before traffic"} -->
| Day 1 / 2026-08-18 | `b4f3f4642005` | — | `260` | `invalid` | unknown / unknown | — | resolution seed sync returned 401 before traffic |
<!-- DAILY_K6_LOG_V1 {"schemaVersion":"daily-k6-log-v1","day":2,"runId":"daily-20260819T032108Z-58715","localDate":"2026-08-18","standard":true,"testedRps":150,"classification":"invalid","floor":null,"ceiling":null,"fingerprint":"sha256:07533a7b309eb1a826e999e39110c1c3a205c77fa1d6b69b2e8d693b9092a201","seriesCompatibility":"series reset/non-comparable","backend":"af892b1da07f34b6d8373b0be7dec0694e4a7e1f","snapshotHash":null,"roughDau":null,"note":"production snapshot invalid"} -->
| Day 2 / 2026-08-18 | `af892b1da07f` | — | `150` | `invalid` | unknown / unknown | — | production snapshot invalid |
<!-- DAILY_K6_LOG_V1 {"schemaVersion":"daily-k6-log-v1","day":3,"runId":"daily-20260819T032216Z-59059","localDate":"2026-08-18","standard":true,"testedRps":150,"classification":"invalid","floor":null,"ceiling":null,"fingerprint":"sha256:9b083c2e11572e1393c3680888bf0d6647c06071e95edc228feebc8c08a6b533","seriesCompatibility":"series reset/non-comparable","backend":"af892b1da07f34b6d8373b0be7dec0694e4a7e1f","snapshotHash":null,"roughDau":null,"note":"production snapshot invalid"} -->
| Day 3 / 2026-08-18 | `af892b1da07f` | — | `150` | `invalid` | unknown / unknown | — | production snapshot invalid |
<!-- DAILY_K6_LOG_V1 {"schemaVersion":"daily-k6-log-v1","day":4,"runId":"daily-20260819T032500Z-59661","localDate":"2026-08-18","standard":true,"testedRps":150,"classification":"invalid","floor":null,"ceiling":null,"fingerprint":"sha256:9b083c2e11572e1393c3680888bf0d6647c06071e95edc228feebc8c08a6b533","seriesCompatibility":"series reset/non-comparable","backend":"af892b1da07f34b6d8373b0be7dec0694e4a7e1f","snapshotHash":"sha256:c83e1cf8abbfc04403d485025f9df8cb175088649910255034ea899390669b1b","roughDau":null,"note":"local settings application failed"} -->
| Day 4 / 2026-08-18 | `af892b1da07f` | `sha256:c83e1cf8abbf…` | `150` | `invalid` | unknown / unknown | — | local settings application failed |
<!-- DAILY_K6_LOG_V1 {"schemaVersion":"daily-k6-log-v1","day":5,"runId":"daily-20260819T032636Z-60123","localDate":"2026-08-18","standard":true,"testedRps":150,"classification":"invalid","floor":null,"ceiling":null,"fingerprint":"sha256:9b083c2e11572e1393c3680888bf0d6647c06071e95edc228feebc8c08a6b533","seriesCompatibility":"series reset/non-comparable","backend":"af892b1da07f34b6d8373b0be7dec0694e4a7e1f","snapshotHash":"sha256:c83e1cf8abbfc04403d485025f9df8cb175088649910255034ea899390669b1b","roughDau":null,"note":"PgBouncer live database routing drift"} -->
| Day 5 / 2026-08-18 | `af892b1da07f` | `sha256:c83e1cf8abbf…` | `150` | `invalid` | unknown / unknown | — | PgBouncer live database routing drift |
<!-- DAILY_K6_LOG_V1 {"schemaVersion":"daily-k6-log-v1","day":6,"runId":"daily-20260819T032842Z-60686","localDate":"2026-08-18","standard":true,"testedRps":150,"classification":"invalid","floor":null,"ceiling":null,"fingerprint":"sha256:3741e4b8c8d4906fce047fd72da9a9fa621bf3b15231e6869e7ed90c8e6f4b45","seriesCompatibility":"series reset/non-comparable","backend":"af892b1da07f34b6d8373b0be7dec0694e4a7e1f","snapshotHash":"sha256:c83e1cf8abbfc04403d485025f9df8cb175088649910255034ea899390669b1b","roughDau":null,"note":"cleanup verification failed"} -->
| Day 6 / 2026-08-18 | `af892b1da07f` | `sha256:c83e1cf8abbf…` | `150` | `invalid` | unknown / unknown | — | cleanup verification failed |
<!-- DAILY_K6_LOG_V1 {"schemaVersion":"daily-k6-log-v1","day":7,"runId":"daily-20260819T033102Z-61419","localDate":"2026-08-18","standard":true,"testedRps":150,"classification":"invalid","floor":null,"ceiling":null,"fingerprint":"sha256:01ddee6fc323c12475b5b23f6bda2e0c795671390c7629203d4cac2705e3b692","seriesCompatibility":"series reset/non-comparable","backend":"af892b1da07f34b6d8373b0be7dec0694e4a7e1f","snapshotHash":"sha256:c83e1cf8abbfc04403d485025f9df8cb175088649910255034ea899390669b1b","roughDau":null,"note":"cleanup verification failed"} -->
| Day 7 / 2026-08-18 | `af892b1da07f` | `sha256:c83e1cf8abbf…` | `150` | `invalid` | unknown / unknown | — | cleanup verification failed |
<!-- DAILY_K6_LOG_V1 {"schemaVersion":"daily-k6-log-v1","day":8,"runId":"daily-20260819T033252Z-62458","localDate":"2026-08-18","standard":true,"testedRps":150,"classification":"invalid","floor":null,"ceiling":null,"fingerprint":"sha256:01ddee6fc323c12475b5b23f6bda2e0c795671390c7629203d4cac2705e3b692","seriesCompatibility":"series reset/non-comparable","backend":"af892b1da07f34b6d8373b0be7dec0694e4a7e1f","snapshotHash":"sha256:c83e1cf8abbfc04403d485025f9df8cb175088649910255034ea899390669b1b","roughDau":null,"note":"raw metric presence/accounting validation failed"} -->
| Day 8 / 2026-08-18 | `af892b1da07f` | `sha256:c83e1cf8abbf…` | `150` | `invalid` | unknown / unknown | — | raw metric presence/accounting validation failed |
<!-- DAILY_K6_LOG_V1 {"schemaVersion":"daily-k6-log-v1","day":9,"runId":"daily-20260819T033743Z-69108","localDate":"2026-08-18","standard":true,"testedRps":150,"classification":"invalid","floor":null,"ceiling":null,"fingerprint":"sha256:9b083c2e11572e1393c3680888bf0d6647c06071e95edc228feebc8c08a6b533","seriesCompatibility":"series reset/non-comparable","backend":"af892b1da07f34b6d8373b0be7dec0694e4a7e1f","snapshotHash":"sha256:c83e1cf8abbfc04403d485025f9df8cb175088649910255034ea899390669b1b","roughDau":null,"note":"load-generator evidence missing or malformed"} -->
| Day 9 / 2026-08-18 | `af892b1da07f` | `sha256:c83e1cf8abbf…` | `150` | `invalid` | unknown / unknown | — | load-generator evidence missing or malformed |
<!-- DAILY_K6_LOG_V1 {"schemaVersion":"daily-k6-log-v1","day":10,"runId":"daily-20260819T034126Z-74227","localDate":"2026-08-18","standard":true,"testedRps":150,"classification":"breaking","floor":null,"ceiling":150,"fingerprint":"sha256:3741e4b8c8d4906fce047fd72da9a9fa621bf3b15231e6869e7ed90c8e6f4b45","seriesCompatibility":"series reset/non-comparable","backend":"af892b1da07f34b6d8373b0be7dec0694e4a7e1f","snapshotHash":"sha256:c83e1cf8abbfc04403d485025f9df8cb175088649910255034ea899390669b1b","roughDau":5800,"note":"resolution lag max 43.7s; server-health breaking gate"} -->
| Day 10 / 2026-08-18 | `af892b1da07f` | `sha256:c83e1cf8abbf…` | `150` | `breaking` | below 150 RPS | ~5,800 at 0.0259 RPS/DAU | resolution lag max 43.7s; server-health breaking gate |
<!-- DAILY_K6_LOG_V1 {"schemaVersion":"daily-k6-log-v1","day":11,"runId":"daily-20260819T035125Z-80152","localDate":"2026-08-18","standard":false,"testedRps":150,"classification":"breaking","floor":null,"ceiling":null,"fingerprint":"sha256:3741e4b8c8d4906fce047fd72da9a9fa621bf3b15231e6869e7ed90c8e6f4b45","seriesCompatibility":"nonstandard","backend":"af892b1da07f34b6d8373b0be7dec0694e4a7e1f","snapshotHash":"sha256:c83e1cf8abbfc04403d485025f9df8cb175088649910255034ea899390669b1b","roughDau":5800,"note":"aggregate resolution concurrency 4: server-health breaking gate"} -->
| Day 11 / 2026-08-18 | `af892b1da07f` | `sha256:c83e1cf8abbf…` | `150` | `breaking` | unknown / unknown | ~5,800 at 0.0259 RPS/DAU | aggregate resolution concurrency 4: server-health breaking gate |
<!-- DAILY_K6_LOG_V1_END -->

## Safety

- Load accepts only `localhost`/`127.0.0.1`. Production access is limited to
  `git fetch origin main` and the fixed SSH-stdin read helper.
- The VM artifact is made directly from pinned `FETCH_HEAD` and allowlists only
  package manifests, `prisma.config.ts`, `src`, and `prisma`; worktree files,
  `.env`, keys, and service-account files cannot enter it.
- The remote helper requires a clean deployed runtime tree, exactly two online
  `steps-tracker` workers (instances 0/1), stable Git/PM2/`.env` identity, and a
  Prisma transaction whose first statement is `SET TRANSACTION READ ONLY`.
- Only one redacted JSON line crosses SSH. Full PM2 environment, `.env`, DB URL,
  raw rows, tokens, and remote stderr are never persisted.
- The local backend receives a constructed benchmark DB URL and dummy session
  secret. Local settings are parameterized and the sole override,
  `capacityPhaseMetricsV1Enabled=true`, is recorded separately.
- Fixture tokens are minted against the fetched artifact and local DB, then
  deleted during teardown. Production data refresh is a separate authorized
  operation and is not part of this command.
- The runner measures and fingerprints guest CPU, memory and architecture,
  verifies PgBouncer's dedicated DB mapping, nginx's 8080→3002 upstream, and
  the live localhost 3302 route before traffic. Configuration drift is invalid.
- Host load evidence begins before k6 is spawned and uses wall plus monotonic
  timestamps, PID/start identity, exit coverage, VUs, RSS/CPU/memory pressure,
  swap and bounded host-OOM evidence.

## Safe verification

These checks do not contact production or start load:

```bash
zsh -n k6/local-prod-sim/*.zsh
node --check k6/local-prod-sim/*.mjs
node --check k6/local-prod-sim/*.cjs
git diff --check
```
