# K6 load testing setup (Digital Ocean staging architecture)

Use this when you want repeatable pressure tests against a staging backend
without changing app code.

## Prereqs

- k6 installed locally (`brew install k6`) **or** Docker available.
- A valid staging identity token.
- Do **not** point this at production.

## Run (local k6)

```bash
export BASE_URL="https://staging.steptracker-api.org"
export IDENTITY_TOKEN="eyJhb..."
k6 run k6/staging-load-test.js
```

## Run (Docker, if no local k6)

```bash
docker run --rm -i --network host \
  -v "$PWD":/work \
  -w /work \
  grafana/k6 run \
  -e BASE_URL=https://staging.steptracker-api.org \
  -e IDENTITY_TOKEN="eyJhb..." \
  k6/staging-load-test.js
```

## Recommended knobs for your architecture

| Variable | What it controls |
|---|---|
| `BASE_URL` | Target API host (staging base URL). |
| `IDENTITY_TOKEN` | JWT used for authenticated routes. |
| `START_VUS` | Initial concurrency. |
| `STAGE_1_TARGET`, `STAGE_2_TARGET`, `STAGE_3_TARGET` | Ramp targets by stage. |
| `STAGE_1_DURATION` ... `STAGE_5_DURATION` | Ramp hold durations. |
| `THINK_SECONDS` | Think time between iterations. |
| `WATCHDOG_EVERY_ITER` | Poll `/app-version/policy` as a watchdog every N requests. |
| `WATCHDOG_BASELINE_MS` | Baseline policy latency in ms (optional). |
| `WATCHDOG_P95_BUDGET_MS` | Hard watchdog ceiling in ms. Defaults to `WATCHDOG_BASELINE_MS * 8` if set. |
| `API_P95_BUDGET_MS` | API workload p95 ceiling. |
| `HARD_FAILURE_RATE_BUDGET` | Non-5xx request failure budget (`0.02` default). |
| `AUTH_UNAUTH_RATE_BUDGET` | Unauthorized-budget for authenticated endpoints. |

## Output and guardrails

The script runs:

- a ramp (`2 -> 12 -> 40 -> 150 -> hold -> teardown`) with default timings,
- weighted realistic mix across read/write routes,
- periodic `/app-version/policy` watchdog checks.

It enforces thresholds on:

- API workload p95 latency,
- watchdog p95 latency,
- hard 5xx failure rate,
- auth unauthorized rate.

Tune thresholds before a campaign; defaults are intentionally conservative.

## Why these endpoints

The profile is built from the existing capacity plan:
- authenticated app-facing reads (`/auth/me`, `/races`, `/home/race-card`, `/friends/steps`)
- app-state writes (`/steps`, `/steps/samples`, `/steps/sync-v2`)
- cheap availability checks (`/health`, `/shop/catalog`, `/powerups/catalog`, `/app-version/policy`).

If you want a stricter run, pin weights and add/remove entries in
`k6/staging-load-test.js` before execution.
