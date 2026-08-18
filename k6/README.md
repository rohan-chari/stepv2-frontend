# k6 load testing + performance profiling

| Script | Use it for |
|---|---|
| **`prod-mix-load-test.js`** | **Capacity questions.** Weighted to the measured app request mix, distinct identities, fixed arrival rate, executable gates. |
| `harness-contract.mjs` | Shared endpoint/rung/status/fixture contract used by k6 and deterministic Node tests. |
| `mint-staging-users.js` | Mints a status-aware fixture and reserves dedicated resolution users/races outside workload traffic. |
| `validate-fixture.mjs` | Validates a fixture without issuing HTTP requests. |
| `aggregate-capacity-cohort.mjs` | Mandatory exact-three-repeat summary/raw/server-evidence aggregator and aggregate endpoint gate. |
| **`profile-worker.js`** | **"Which code burns the CPU?"** Attaches to a Node worker's inspector and captures a V8 CPU profile. See [Profiling](#profiling-which-code-burns-cpu). |
| **`sample-db-queries.sh`** | **"Which SQL burns the database?"** Samples the running statement; a poor-man's `pg_stat_statements`. |
| `sample-db-state.sh` | Samples `active` / `idle in transaction` / lock-wait counts. |
| `staging-load-test.js` | The original 2026-08-15 harness. Kept only so old results stay reproducible — see [Why the old script understates load](#why-the-old-script-understates-load). |

**Which tool answers which question** — reach for the right one, because
inferring hot spots from response times is how three wrong diagnoses got made
on 2026-08-16:

| Question | Tool |
|---|---|
| How many users can we serve? | `prod-mix-load-test.js` |
| Is it CPU, or waiting on the DB? | `profile-worker.js` (idle % of the profile) |
| Which *code* is hot? | `profile-worker.js` |
| Which *SQL* is hot? | `sample-db-queries.sh` |
| Are connections stuck rather than working? | `sample-db-state.sh` |
| How many queries does one endpoint issue? | `PRISMA_QUERY_EVENTS_ENABLED=true`, see below |

Everything targets **staging**. Never point either script at production.

---

## Safe validation (no load traffic)

```bash
node --test k6/test/harness-contract.test.mjs k6/test/cohort-aggregator.test.mjs
node k6/validate-fixture.mjs k6/users.json
set -a; . k6/capacity-load-test.env.example; set +a
k6 inspect --include-system-env-vars -e TARGET_RUNG=rate_15rps k6/prod-mix-load-test.js
k6 inspect --include-system-env-vars -e TARGET_RUNG=rate_31rps k6/prod-mix-load-test.js
k6 inspect -e MODE=smoke -e RUN_ID=smoke-inspect -e REPEAT_INDEX=smoke k6/prod-mix-load-test.js
```

`k6 inspect` proves that each offered-rate identity installs its thresholds. It
does not contact the backend. The ignored legacy array-form `users.json` must be
re-minted before a smoke or measured run; runtime setup intentionally rejects a
fixture that cannot distinguish race status or reserve resolution identities.

## Measured-run protocol

Milestone 5.0 does not authorize a run. When a staging run is separately
authorized, do the deterministic smoke first, then a low-rate run, then three
matched 15-rps repeats. A 31-rps repeat is allowed only after every 15-rps gate
passes. Run one offered-rate rung per process so cache/cron cohorts and failures
cannot be averaged together.

```bash
# 0. one-time: brew install k6

# 1. refresh staging from prod (~6 min) — see "Sync prod into staging" below
# 2. mint user tokens (~5 s)
cd /Users/rohan/repos/stepv2-backend && set -a && . ./.env && set +a
export SESSION_TOKEN_SECRET="$(ssh root@167.172.225.16 \
  'grep "^SESSION_TOKEN_SECRET=" /var/www/step-tracker-backend-staging/.env | cut -d= -f2-')"
NODE_PATH=/Users/rohan/repos/stepv2-backend/node_modules \
  node ~/repos/stepv2-frontend/k6/mint-staging-users.js \
  --count=400 --resolution-seeds=4 \
  --out=~/repos/stepv2-frontend/k6/users.json

# 3. validate the generated fixture and script without traffic
cd ~/repos/stepv2-frontend/k6
node validate-fixture.mjs users.json
k6 inspect -e MODE=smoke -e RUN_ID=smoke-inspect -e REPEAT_INDEX=smoke \
  prod-mix-load-test.js

# 4. only with separate authorization: deterministic endpoint smoke
k6 run -e MODE=smoke \
  -e RUN_ID=smoke-$(date +%s) -e REPEAT_INDEX=smoke \
  -e SUMMARY_JSON=/tmp/capacity-smoke-summary.json \
  --out json=/tmp/capacity-smoke-samples.json prod-mix-load-test.js

# 5. only with separate authorization: one measured cohort/rung
k6 run -e TARGET_RUNG=rate_15rps \
  -e CLIENT_COHORT=ios_bara_2_3_7_ads_payout \
  -e BACKEND_REVISION=<revision> \
  -e BACKEND_FLAGS=<flags> -e BACKEND_CONFIG=<config> \
  -e WORKER_COUNT=1 -e PGBOUNCER_POOL=3 \
  -e REDIS_STATE=warm-process-warm-redis \
  -e CRON_COHORT=warm-steady-outside-heavy-tick \
  -e RUN_ID=pool3-baseline-r1 -e REPEAT_INDEX=1 \
  -e SUMMARY_JSON=/tmp/capacity-rate-15-summary-1.json \
  --out json=/tmp/capacity-rate-15-samples-1.json prod-mix-load-test.js

# 6. Export capacity telemetry NDJSON from the server after each repeat, then
# extract its server-owned evidence in the backend repo. Embed that output as
# `telemetry` in one harness-owned capacity-telemetry-evidence-v1 JSON file per
# repeat alongside the matching runId, repeatIndex, booleans, and setting.
node scripts/extract-capacity-telemetry-evidence.js \
  --run-id pool3-baseline-r1 --repeat 1 \
  < /tmp/capacity-metrics-1.ndjson \
  > /tmp/capacity-rate-15-server-evidence-1.json

jq -n \
  --slurpfile summary /tmp/capacity-rate-15-summary-1.json \
  --slurpfile telemetry /tmp/capacity-rate-15-server-evidence-1.json \
  '{
    schema: "capacity-telemetry-evidence-v1",
    runId: $summary[0].inputs.runId,
    repeatIndex: $summary[0].inputs.repeatIndex,
    queryCaptureAvailable: $telemetry[0].queryCaptureAvailable,
    measurementGateEligible: $telemetry[0].measurementGateEligible,
    setting: ($summary[0].inputs | {
      backendRevision, flags, config, workerCount, pgBouncerPool, redisState,
      cronCohort
    }),
    telemetry: $telemetry[0]
  }' > /tmp/capacity-rate-15-evidence-1.json

# 7. after exactly three matched triples, this output is the cohort gate
node aggregate-capacity-cohort.mjs \
  --summary /tmp/capacity-rate-15-summary-1.json \
  --raw /tmp/capacity-rate-15-samples-1.json \
  --evidence /tmp/capacity-rate-15-evidence-1.json \
  --summary /tmp/capacity-rate-15-summary-2.json \
  --raw /tmp/capacity-rate-15-samples-2.json \
  --evidence /tmp/capacity-rate-15-evidence-2.json \
  --summary /tmp/capacity-rate-15-summary-3.json \
  --raw /tmp/capacity-rate-15-samples-3.json \
  --evidence /tmp/capacity-rate-15-evidence-3.json \
  --out /tmp/capacity-rate-15-cohort.json
```

The JSON sample stream carries the unique `run_id`, `repeat_index`, `endpoint`,
exact `status`, `rung`, selected and executed endpoint, client cohort, race
status, team/solo, and roster-size-stratum tags. `handleSummary` emits the same
run binding in a separate structured gate/status summary. An individual repeat
is never claimable before post-run server evidence exists. The mandatory cohort
aggregator binds each summary/raw/evidence triple, rejects reused IDs or
mispaired/truncated raw files, requires exact selected = executed = duration
sample = status totals for every endpoint, and applies endpoint p95 only at 20+
aggregate samples. Each repeat summary independently records those four
per-endpoint custom-metric counts, so removing an entire endpoint quartet from a
raw file also fails reconciliation. Claimable cohorts require the exact
`https://staging.steptracker-api.org` base URL, a real commit revision, recorded
flag/config labels, pool size 3, and structured worker/Redis/cron topology
labels. Localhost remains available only for diagnostic, non-claimable runs. Do
not parse fixed CSV column positions.

---

## Users → VUs → rps

**Do not think in VUs.** A VU is not a user and, with a `ramping-vus` executor,
is not even a fixed amount of load: each VU waits on its own response, so when
the server slows the test quietly backs off exactly when it should be pushing.
That is why the 2026-08-15 run flatlined at ~190 rps no matter how many VUs it
was given.

Convert through **request rate** instead. The evidence window recorded in the
approved 2026-08-17 capacity spec was:

| Measure | Value |
|---|---|
| Real app requests / 24h | 280,554 |
| DAU | 495 |
| Requests per DAU per day | **566.8** |
| Mean rps | 3.25 |
| Peak 10-min rps | 12.82 |
| **Peak rps per DAU** | **0.0259** |

```
peak rps = DAU × 0.0259
```

Rungs are named only by offered rate. DAU is a later evidence conversion, never
part of a scenario identity:

| Rung | Offered rate | Duration | Role |
|---|---:|---:|---|
| `rate_5rps` | 5 rps | 60 s | low-rate harness/telemetry gate |
| `rate_15rps` | 15 rps | 90 s | conservative capacity gate |
| `rate_31rps` | 31 rps | 30 s | only after 15-rps gates pass |

`DURATION_OVERRIDE` is rejected in capacity mode unless
`ALLOW_DIAGNOSTIC_OVERRIDE=1` is also set. Such summaries are stamped
`claimable:false` and the cohort aggregator rejects them.

### Re-derive the constant

The coefficient drifts. Recompute it before quoting capacity, and publish the
window, timezone, DAU definition, excluded non-app traffic, peak bucket, and
coefficient. The 14-day fixture corpus is not the 24-hour DAU denominator; both
windows are labeled separately in every generated fixture.

```bash
ssh root@167.172.225.16 'cat /var/log/nginx/access.log.1 /var/log/nginx/access.log \
  | grep -vE "k6|curl/|Mozilla/" | awk -F\" "\$6!=\"-\"" > /tmp/app.log
  # requests in the trailing 24h
  awk -F"[][]" "{print \$2}" /tmp/app.log | awk -F: "{print \$1\":\"\$2}" | wc -l
  # peak 10-min bucket
  awk -F"[][]" "{print \$2}" /tmp/app.log \
    | awk -F: "{printf \"%s:%s:%s0\n\", \$1,\$2,substr(\$3,1,1)}" \
    | sort | uniq -c | sort -rn | head -5'
```

Then DAU from prod: `SELECT COUNT(*) FROM users WHERE last_seen_at > NOW() - INTERVAL '24 hours';`

Cross-check the peak bucket's composition before using it; retry loops and test
traffic are not organic app demand.

---

## Profiling: which code burns CPU

**`pm2 profile:cpu` does NOT work.** It profiles the pm2 God daemon, not your
app — the result is 97.6% `(idle)` with `amp` / `child_process` / `cluster`
frames. It looks like a valid profile and is worthless. Use `profile-worker.js`,
which drives the worker's own inspector.

```bash
# 1. start load in one shell (background it — k6 blocks)
cd ~/repos/stepv2-frontend/k6
k6 run -e TARGET_RUNG=rate_15rps -e DURATION_OVERRIDE=120s \
  -e ALLOW_DIAGNOSTIC_OVERRIDE=1 prod-mix-load-test.js

# 2. ~15s in, attach and capture 50s from the droplet
scp k6/profile-worker.js root@167.172.225.16:/tmp/
ssh root@167.172.225.16
  PID=$(pm2 jlist | python3 -c "import json,sys; print([p['pid'] for p in json.load(sys.stdin) if p['name']=='steps-tracker-staging'][0])")
  kill -USR1 $PID          # opens the inspector on 127.0.0.1:9229
  sleep 3
  node /tmp/profile-worker.js 50000 /tmp/worker.cpuprofile
```

Then aggregate self-time by module. The headline number is **idle %** — if the
profile is mostly busy, the app is CPU-bound and the database is not the wall.

Load the `.cpuprofile` in Chrome DevTools (Performance → Load profile) for a
flame graph, or aggregate by `callFrame.url` for a module breakdown.

**Gotchas:**
- Attach *while load is running*. A profile of an idle worker says nothing, and
  a 120s load run with a 50s capture starting at +15s leaves margin.
- The profiler holds its samples in the worker's heap — a 186k-sample capture
  pushed the process from ~380 MB to 630 MB. On this droplet that is close to
  the OOM line. **Restart the worker afterwards** to reclaim it.
- `SIGUSR1` is a one-way door for the process lifetime; the inspector port stays
  open until it restarts.

### Which SQL burns the database

`pg_stat_statements` is **not installed** on this cluster. `sample-db-queries.sh`
substitutes for it: it polls the currently-executing statement in a tight loop,
so a statement appearing in N% of samples is consuming ~N% of database busy
time.

```bash
scp k6/sample-db-queries.sh root@167.172.225.16:/tmp/
ssh root@167.172.225.16 "bash /tmp/sample-db-queries.sh '<STAGING_DATABASE_URL>' > /tmp/sql.out"
# then, ranked:
grep -v '^$' /tmp/sql.out | sed -E 's/\$[0-9]+/?/g' \
  | awk '{print substr($0,1,95)}' | sort | uniq -c | sort -rn | head
```

`sample-db-state.sh` answers a different question — whether connections are
`active` (doing work), `idle in transaction` (held open doing nothing), or
lock-waiting. A high `idle in transaction` count means transactions are held
across non-database work.

### Per-endpoint query counts

Set `PRISMA_QUERY_EVENTS_ENABLED=true` in **staging's** `.env` and restart. The
app then logs one `api_contract_performance` JSON line per response carrying
`sqlCount`, which is how you find N+1s:

```bash
pm2 logs steps-tracker-staging --lines 4000 --nostream --out \
  | grep -o '{"event":"api_contract_performance".*}' > /tmp/api.jsonl
```

Only responses carrying a `contract` field are instrumented, so coverage is
partial.

**Leave it `false` in prod, and turn it off on staging when done** — `db.js`
notes it deliberately adds hot-path work. It inflates absolute latency, so a
before/after comparison must have it set the same way in both runs.

---

## Sync prod into staging

The naive `scripts/sync-prod-to-local.js --target=staging` **does not work** —
it calls a bare `pg_dump` (16.x) against a PG 18.4 server, and it drops the
staging schema *before* the dump fails, leaving staging empty. A one-shot
`pg_dump | psql` over the home→DigitalOcean link also dies partway through with
random TLS `bad record mac` errors.

Working procedure — dump locally with v18, restore from inside DO's network:

```bash
cd /Users/rohan/repos/stepv2-backend && set -a && . ./.env && set +a

ssh root@167.172.225.16 'pm2 stop steps-tracker-staging'

PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH" \
  pg_dump "$PROD_DATABASE_URL" --no-owner --no-acl -f /tmp/prod.sql   # ~127 MB
scp /tmp/prod.sql root@167.172.225.16:/tmp/prod-sync.sql

ssh root@167.172.225.16 "export S='$STAGING_DATABASE_URL';
  psql \"\$S\" -v ON_ERROR_STOP=1 -c 'DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;' &&
  psql \"\$S\" -v ON_ERROR_STOP=1 -q --single-transaction -f /tmp/prod-sync.sql &&
  psql \"\$S\" -c 'TRUNCATE device_tokens;' &&
  cd /var/www/step-tracker-backend-staging && npx prisma migrate deploy"

ssh root@167.172.225.16 'pm2 start steps-tracker-staging; rm /tmp/prod-sync.sql'
```

- `--single-transaction` is mandatory: without it a mid-restore failure leaves
  staging half-loaded, which is worse than empty.
- `TRUNCATE device_tokens` is what stops staging pushing APNs to real users.
- The staging pm2 process is **`steps-tracker-staging`** — address it by name,
  not id (cluster mode renumbers).
- Prod is only ever read here. Sanity-check the two URLs differ before running:
  prod is `db=step-tracker`, staging is `db=step-tracker-staging`.

---

## Auth: minting user identities

There is no email/password login (Apple/Google Sign-In only). `mint-staging-users.js`
signs session tokens **directly** with staging's `SESSION_TOKEN_SECRET`
(HS256, `subject: userId`, `issuer: steps-tracker-api`), for N real
prod-cloned users. It records ACTIVE and PENDING races separately, plus
team/solo and full accepted-roster size. It reserves dedicated users and every
live race they share; those users and races are excluded from workload traffic.
At setup, the harness posts a fresh sync-v2 request for each reserved user and
polls the returned current job/generation across all VUs. Teardown requires at
least one lag sample and drains every reserved job to zero outstanding.

This matters: the older harness authenticated every VU as the single App Store
reviewer account, which serialises all writes onto one user's rows and hands
every read the same warm cache line. That is nothing like N distinct users.

Gotchas:
- Run with `NODE_PATH=/Users/rohan/repos/stepv2-backend/node_modules` — the
  script lives in the frontend repo, which has no `node_modules`.
- The script strips `sslmode` from the URL and sets `rejectUnauthorized: false`;
  DO's chain is self-signed and `sslmode` in the URL otherwise wins over the
  `ssl` option in pg v8+.
- Race status enum labels are **lowercase** (`active`, `pending`) — `'ACTIVE'`
  raises `invalid input value for enum`.
- Tokens expire in 2 days. Re-mint for a later campaign.

The **reviewer bypass** (`POST /auth/review` with `APP_REVIEW_EMAIL` /
`APP_REVIEW_PASSWORD`, account `AppReviewer67@gmail.com`) still works and is
what `staging-load-test.js` uses, but prefer minting.

---

## Why the old script understates load

`staging-load-test.js` was built from guesses. Measured against the real 24h
mix, it is wrong in ways that all point the same direction — too easy:

- `/health` carries an **18% weight**; in prod it is ~0% of traffic.
- `/races/:id/messages` is **28% of all real requests** and the old script never
  issues it.
- `/home/race-card` is **30% of all server time** (1,558 ms/req at 4.5% of
  requests) and the old script under-weights it.
- `ramping-vus` self-throttles under load, as above.

`prod-mix-load-test.js` weights all 26 endpoints by their raw 24h request
counts. If you re-derive the mix later, replace the `w:` values — they are
literally request counts, so any consistent scale works.

Two endpoint quirks encoded in the script:

- **`/steps/race-resolution/:jobId` takes a JOB id, not a race id.** Setup
  creates fresh jobs for dedicated identities and distributes the returned
  current job/generation globally. New VUs therefore preserve poll weight
  without stale fixture jobs or empty VU-local history.
- **`/challenges/current` 404s on every request.** That is faithful to prod —
  the route has never existed. (The iOS caller was removed 2026-08-16; once
  no shipped build sends it, drop it from the mix.)

Only the documented organic `challenges_current` 404 is excluded from the
capacity-failure rate, and it remains visible in exact tagged status counts.
Every other non-2xx response, including 429, is a capacity failure.

---

## The two machines (both named `stock-sentiment`)

This trips people up constantly — the Node app and the database are separate
DigitalOcean resources that share a name:

| | vCPU | RAM | Disk | Notes |
|---|---|---|---|---|
| **Droplet** (Node app, nginx) | **2** | 2 GB | 60 GB | runs prod + staging as separate pm2 processes |
| **DB cluster** (`db-s-1vcpu-2gb`, 1 node) | **1** | 2 GB | — | PG 18, `max_connections` 50 (47 usable), shared with the `stock-sentiment` project |

When a capacity claim says "1 vCPU" it means the **database**; the droplet has
two. Verify rather than assume:

```bash
ssh root@167.172.225.16 'doctl databases list --format Name,Size,NumNodes; \
  doctl compute droplet list --format Name,Memory,VCPUs,Disk'
```

### Connection budget

`max_connections` is 50 with 3 reserved for superuser → **47 usable**. Only
`backend_type='client backend'` rows count; Postgres's own background
processes (checkpointer, walsender, autovacuum, pg_cron, TimescaleDB worker —
about 12 of them) do **not**. Counting raw `pg_stat_activity` rows overstates
usage by ~12 and will make a watchdog fire spuriously:

```sql
SELECT COUNT(*) FROM pg_stat_activity WHERE backend_type='client backend';
```

The two PgBouncer pools' sizes must sum to comfortably under 47, since each
pool holds its backends open at idle:

```bash
ssh root@167.172.225.16 'doctl databases pool list <cluster-id> --format Name,Mode,Size'
```

Resizing a pool needs a **write-scoped** DO token; the droplet's default
`doctl` context is read-only and returns 403 on PUT.

---

## Historical results are diagnostic, not a capacity ceiling

The switched/partially corrected harness produced the following one-worker
measurements at a temporary PgBouncer pool of 20:

| Offered load | Completed | Hard failures | Dropped | Overall p95 |
|---|---:|---:|---:|---:|
| 15 rps for 90 s | 1,351 | 0 | 0 | 3.40 s |
| 31 rps for 30 s | 882 (23.17/s effective) | 1 timeout | 49 | 14.23 s |

Those runs predate the corrected fixture, resolution, status, and summary
behavior in this harness and used pool 20. They diagnose queueing and hot paths;
they do not certify any one-worker, pool-3 capacity or DAU count.

The first valid baseline must use one staging worker and PgBouncer pool 3,
record all inputs named in the structured summary, and pass the exact gates in
the approved capacity specification. Production capacity is measured
independently; never multiply a one-worker result by the production worker
count.
