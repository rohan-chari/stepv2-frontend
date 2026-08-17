# k6 load testing + performance profiling

| Script | Use it for |
|---|---|
| **`prod-mix-load-test.js`** | **Capacity questions.** Weighted to the real prod request mix, N distinct user identities, fixed arrival rate. This is the one you want. |
| `mint-staging-users.js` | Mints N staging session tokens for real prod-cloned users (see [Auth](#auth-minting-user-identities)). |
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

## TL;DR — run a test

```bash
# 0. one-time: brew install k6

# 1. refresh staging from prod (~6 min) — see "Sync prod into staging" below
# 2. mint user tokens (~5 s)
cd /Users/rohan/repos/stepv2-backend && set -a && . ./.env && set +a
export SESSION_TOKEN_SECRET="$(ssh root@167.172.225.16 \
  'grep "^SESSION_TOKEN_SECRET=" /var/www/step-tracker-backend-staging/.env | cut -d= -f2-')"
NODE_PATH=/Users/rohan/repos/stepv2-backend/node_modules \
  node ~/repos/stepv2-frontend/k6/mint-staging-users.js \
  --count=400 --out=~/repos/stepv2-frontend/k6/users.json

# 3. run (ALWAYS in the background — the full ladder takes ~18 min)
cd ~/repos/stepv2-frontend/k6
k6 run --summary-trend-stats="avg,p(90),p(95),p(99),max" \
  --out csv=/tmp/ladder.csv prod-mix-load-test.js > /tmp/ladder.txt 2>&1

# 4. per-rung breakdown (the summary alone averages all rungs together and
#    is therefore useless — always break down by rung)
awk -F, 'NR>1 && $1=="http_req_duration" {
  r=$12; st=$14; n[r]++; sum[r]+=$3;
  if(st=="0") zero[r]++; else if(st>=500) e5[r]++;
  else if(st==401||st==403) e401[r]++; else if(st>=200&&st<400) ok[r]++;
} END { printf "%-10s %8s %8s %8s %8s %8s %8s\n","rung","reqs","mean_ms","ok%","timeout%","5xx%","401%";
  for(r in n) printf "%-10s %8d %8.0f %7.1f%% %7.1f%% %7.1f%% %7.1f%%\n",
    r,n[r],sum[r]/n[r],100*ok[r]/n[r],100*zero[r]/n[r],100*e5[r]/n[r],100*e401[r]/n[r]
}' /tmp/ladder.csv | sort
```

**`k6 run` blocks for the whole ramp.** Launch it with `run_in_background`, not a
foreground shell — a 2-minute foreground timeout kills a multi-minute ramp
mid-run (this ate the first attempt on 2026-08-15).

---

## Users → VUs → rps

**Do not think in VUs.** A VU is not a user and, with a `ramping-vus` executor,
is not even a fixed amount of load: each VU waits on its own response, so when
the server slows the test quietly backs off exactly when it should be pushing.
That is why the 2026-08-15 run flatlined at ~190 rps no matter how many VUs it
was given.

Convert through **request rate** instead. Measured from 24h of prod nginx logs
on **2026-08-16** (bots, scanners, and k6's own traffic excluded):

| Measure | Value |
|---|---|
| Real app requests / 24h | 217,144 |
| DAU (`users.last_seen_at`, agreed with distinct step-sample posters) | 471 |
| Requests per DAU per day | **467** |
| Mean rps | 2.51 |
| Peak 10-min rps (organic) | 5.68 (2.26× daily mean) |
| **Peak rps per DAU** | **0.0122** |

```
peak rps = DAU × 0.0122
```

The rungs in `prod-mix-load-test.js` are built from this:

| Rung | Offered rate | Models |
|---|---|---|
| `dau_1250` | 15 rps | 1,250 DAU |
| `dau_2500` | 31 rps | 2,500 DAU |
| `dau_5000` | 61 rps | 5,000 DAU |
| `dau_10000` | 122 rps | 10,000 DAU |
| `dau_20000` | 244 rps | 20,000 DAU |

Run one rung with `TARGET_ONLY=dau_5000`, and shorten it with
`DURATION_OVERRIDE=45s` (handy for smoke-testing script edits).

### Re-derive the constant

It drifts — it was **0.0452** in the older notes and is 3.7× lower now (DAU grew
104 → 471 while per-user requests fell 852 → 467/day). Recompute before quoting
capacity numbers:

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

**Discard anomalous peak buckets.** The top bucket on 2026-08-16 was a single
device retry-looping a 404 at 6.5 req/s — 3,907 of the bucket's 5,850 requests.
Cross-check the top bucket's composition before using it.

---

## Profiling: which code burns CPU

**`pm2 profile:cpu` does NOT work.** It profiles the pm2 God daemon, not your
app — the result is 97.6% `(idle)` with `amp` / `child_process` / `cluster`
frames. It looks like a valid profile and is worthless. Use `profile-worker.js`,
which drives the worker's own inspector.

```bash
# 1. start load in one shell (background it — k6 blocks)
cd ~/repos/stepv2-frontend/k6
k6 run -e FAST=1 -e TARGET_ONLY=dau_5000 -e DURATION_OVERRIDE=120s prod-mix-load-test.js

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
prod-cloned users, and records each one's live/pending race ids.

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

- **`/steps/race-resolution/:jobId` takes a JOB id, not a race id.** The client
  gets one from a `/steps/sync-v2` response and then polls it. The script
  harvests job ids from its own sync responses; passing a race id returns 400.
- **`/challenges/current` 404s on every request.** That is faithful to prod —
  the route has never existed. (The iOS caller was removed 2026-08-16; once
  no shipped build sends it, drop it from the mix.)

Expect ~9% non-2xx at rest. That is correct, not a bug: prod's own baseline is
~10% non-2xx (404s plus 304s).

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

## 2026-08-16 results — the current ceiling

Staging on prod-cloned data, 400 distinct users. **Read the pool-size caveat
below before quoting any of these numbers.**

| Rung | Offered | reqs | mean | ok | timeout | 5xx | 401 |
|---|---|---|---|---|---|---|---|
| `dau_1250` | 15 rps | 2,701 | 402 ms | **90.0%** | 0.0% | 0.0% | 0.0% |
| `dau_2500` | 31 rps | 5,181 | 9,882 ms | 61.5% | 12.3% | 12.8% | 2.2% |
| `dau_5000` | 61 rps | 13,935 | 11,487 ms | **31.3%** | 9.4% | 37.0% | 12.4% |
| `dau_10000` | 122 rps | 20,788 | 9,450 ms | 22.1% | 3.1% | 40.2% | 24.9% |
| `dau_20000` | 244 rps | 39,384 | 8,842 ms | 5.7% | 66.9% | 6.1% | 18.1% |

**CAVEAT: this ladder ran while `bara-staging-pool` was size 3** (prod's was
19). It therefore measured a 3-connection pool, not production, and the DAU
numbers above are far too pessimistic. Kept for the shape of the curve only.

### Re-run at pool = 20 (same day)

With `bara-staging-pool` raised to 20, the 5,000-DAU rung improved a lot and
still failed:

| 61 rps (5,000 DAU) | pool = 3 | pool = 20 |
|---|---|---|
| ok | 31.3% | **52.6%** |
| 5xx | 37.0% | **19.2%** |
| timeout | 9.4% | 16.5% |
| mean | 11.5 s | 12.9 s |

The 10,000-DAU rung hit 33.8% 5xx and tripped the abort. **5,000 users does not
work today**; prod's pool is 25 vs staging's 20, so prod's ceiling is ~25%
higher, not multiples higher.

### The bottleneck is NOT the droplet's CPU, and NOT Prisma's `connection_limit`

Two dead ends worth recording so nobody re-walks them:

- **Droplet CPU is not the wall.** Through the failing rungs the droplet held
  **23–52% idle**. Requests took 11 s while two cores sat a third idle. The one
  genuine CPU event was at 244 rps where `%system` hit 93% — kernel saturation
  from connection churn, not application work.
- **`connection_limit` does nothing here.** This backend uses the Prisma
  **driver adapter**: `src/db.js` builds an explicit
  `new pg.Pool({ max: 20, connectionTimeoutMillis: 5000 })` and wraps it in
  `PrismaPg`. Prisma's own pool (and its `num_cpus*2+1` default) is not in play,
  and a `connection_limit` URL param is silently ignored.

**The wall moves as you fix it.** Two distinct signatures, in order:

1. At pool = 3 — `P2028 Transaction API error: Unable to start a transaction in
   the given time`, from PgBouncer starvation. Fixed by sizing the pool.
2. At pool = 20 — `Error: timeout exceeded when trying to connect`, which is
   node-postgres' own `connectionTimeoutMillis: 5000` in `src/db.js`. The app
   runs `max: 20` **per process** × 2 pm2 instances = **40 app connections
   competing for 20 PgBouncer backends**, a 2:1 oversubscription. Deadlocks also
   appear at this stage (8 of them), which pool = 3 was too starved to reach.

Underneath both sits the **1-vCPU database**. `/home/race-card` costs 1,558
ms/req and `/races` 648 ms at prod's *current* ~5 rps; a single core is the
likely floor under everything else. Before spending money on a resize, settle it
by running one 61-rps minute while sampling connection state — if the pooled
backends are mostly `active` the DB is saturated and pool tuning is futile; if
mostly `idle` it is purely app-side config:

```sql
SELECT state, COUNT(*) FROM pg_stat_activity
 WHERE datname='step-tracker-staging' AND backend_type='client backend'
 GROUP BY state;
```

### Prod impact

Staging and prod share the droplet *and* the DB cluster, so a run of this size
is felt in production. Measured on endpoints the test never issues
(`/leaderboard`, `/coins`, `/daily-reward`, `/tournaments`, `/ranked`, …):

| Window | reqs | mean | 5xx |
|---|---|---|---|
| Before (13:30–14:10) | 294 | **69 ms** | 0.0% |
| During (14:14–14:34) | 136 | **579 ms** | 0.7% |

Real users saw an **8.4× latency increase** but almost no errors. Run in a
low-traffic window, or accept that.

**Prod and staging share one nginx access log with no vhost field**, and this
script deliberately sends a realistic `Bara/2.3.7` user-agent — so you cannot
separate the two by UA. Use endpoints the test never touches, as above.
