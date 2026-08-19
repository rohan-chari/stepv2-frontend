# k6 capacity testing

The supported workflow is local, production-shaped, and one command. It uses a
sanitized private corpus, a 2-vCPU/2-GiB Lima VM, two Node workers and PgBouncer
pool 25. It never contacts production or staging during a normal run.

## Run

From the frontend repository:

```bash
k6/local-prod-sim/run-optimization1-comparison.zsh
```

The default is a direct 160-RPS OFF/ON diagnostic. For the optional aggressive
probe:

```bash
RPS=260 k6/local-prod-sim/run-optimization1-comparison.zsh
```

See [LOCAL-PROD-SIM-RUNBOOK.md](LOCAL-PROD-SIM-RUNBOOK.md) for the one-time VM,
database and private-corpus setup. The command restores both variants, remints
local-only session tokens, checks provenance, runs k6, saves a dated private
report, and shuts down PM2, Lima, PgBouncer and Postgres on success or failure.

## What the harness models

`prod-mix-load-test.js` is a constant-arrival-rate model of the released 2.3.7
client mix. Its contract lives in `harness-contract.mjs` and includes:

- exact released-client headers and 26 weighted endpoints;
- participant paging with `limit=15`;
- ACTIVE/PENDING/team/solo/roster-size fixture context;
- dedicated, current-run resolution jobs;
- exact selected/executed/status accounting;
- 429, hard-failure, dropped-arrival and resolution-state metrics; and
- deterministic endpoint, user, payload randomness and logical timestamps for
  matched comparisons.

The local runner uses a 35-second direct load and tags the first five seconds'
worth of offered arrivals (800 at 160 RPS) as warm-up. It does not staircase.

## Interpreting results

The one-command comparison is intentionally `DIAGNOSTIC ONLY`. It never
auto-approves a flag or certifies a DAU ceiling. Missing metrics, mismatched
inputs, endpoint-accounting differences or invalid private artifacts fail
closed.

One fixed-order pair is fast feedback. A rollout decision still needs
counterbalanced repeated pairs, server telemetry, architecture review and code
review. Current retained findings are indexed in [findings/README.md](findings/README.md).

## Safety

- Normal runs accept only `localhost`/`127.0.0.1` traffic targets.
- Only Git-visible runtime source enters the VM artifact; ignored files,
  `.env`, keys and service-account files are excluded.
- The backend receives a constructed local-only database URL and dummy session
  secret. The runner validates the database name and sanitized-corpus marker
  through that same application connection before k6 starts.
- Fixture tokens are reminted locally and deleted during teardown.
- Refreshing the sanitized corpus from production is a separate operation that
  requires explicit, in-the-moment authorization.

## Verification

```bash
node --test k6/test/*.test.mjs
RUN_ID=inspect REPEAT_INDEX=1 \
  BACKEND_REVISION=abcdef123456 BACKEND_FLAGS=diagnostic \
  BACKEND_CONFIG=local WORKER_COUNT=2 PGBOUNCER_POOL=25 \
  REDIS_STATE=local CRON_COHORT=capacity-http-resolution-only \
  MATCHED_PAIR_EPOCH_MS=1787097600000 \
  WARMUP_ITERATIONS=800 \
  USERS_FILE="$HOME/.local/share/stepv2-capacity/users-20260818-v2.json" \
  TARGET_RUNG=diagnostic_160rps \
  k6 inspect --include-system-env-vars k6/prod-mix-load-test.js
```
