# Scaling & Capacity Plan

**Status:** Draft for approval · **Measured:** 2026-07-25 · **Owner:** Rohan

Everything below is grounded in a real load test run against staging on
2026-07-25, not estimates. Reproduction steps are in §7 so the numbers can be
re-measured after each phase.

---

## 1. Summary

We can serve roughly **1,000 DAU comfortably** and **~2,500 DAU before the app
falls over**. Today we are at **117 DAU**, so we have ~8x headroom.

The bottleneck is **CPU on a single shared 1-vCPU droplet** — *not* the
database. The database is fast and mostly idle.

The cheapest large win is **not** an infrastructure upgrade. It is deleting
redundant client polling, which is responsible for ~30% of all traffic and
costs nothing per month.

**Critical blocker:** the obvious scaling move — raising pm2 `instances` to use
more cores — would currently **double-run every cron job**, minting duplicate
coins and double-pushing the entire user base. That must be fixed before any
multi-instance scaling. See §4 Phase 2.

---

## 2. Measured baseline (2026-07-25)

### Infrastructure shape

Both environments live on **one box**:

| Component | Spec | Notes |
|---|---|---|
| Droplet `167.172.225.16` | **1 vCPU / 2 GB** | Runs prod Node **+** staging Node **+** nginx **+** Docker |
| prod app | pm2 `steps-tracker`, port 3002 | `cluster_mode`, **`instances: 1`** |
| staging app | pm2 `steps-tracker-staging`, port 3003 | `cluster_mode`, **`instances: 1`** |
| Database | DO managed **`db-s-1vcpu-2gb`**, PG 18, single node | Cluster `stock-sentiment` (`7ae2dc3e-…`) |
| DB sharing | **Shared with an unrelated stock-sentiment/investorsavant project** | Their spike degrades Bara |
| Connections | **`max_connections = 50`**, ~36 in use | Only ~14 spare |
| PgBouncer pools (transaction mode) | prod `step-tracker-pool` = **19**, staging `bara-staging-pool` = **3** | Pooled port 25061, direct 25060 |
| Prod DB size | **106 MB** | Fits entirely in RAM |

### Load test results

Ramp against staging, concurrency 2 → 150, realistic weighted endpoint mix:

| Concurrency | req/s | p50 | p95 | p99 | errors |
|---|---|---|---|---|---|
| 2 | 30 | 58ms | 126ms | 220ms | 0 |
| 5 | 59 | 78ms | 164ms | 222ms | 0 |
| 10 | 71 | 124ms | 264ms | 371ms | 0 |
| 20 | 72 | 241ms | 517ms | 607ms | 0 |
| 40 | 88 | 405ms | 837ms | 1036ms | 0 |
| 80 | 82 | 877ms | 1643ms | 1917ms | 0 |
| 150 | 89 | 1530ms | 2837ms | 4120ms | 0 |

Throughput **plateaus at ~75–89 req/s from concurrency 10 onward**; past that,
latency grows linearly while throughput stays flat — textbook saturation. Note
there were **zero errors even at concurrency 150**: the system degrades by
getting slow, not by failing. That is good behaviour, but it also means
saturation will show up as user complaints about slowness, not as alerts.

### Where the time actually goes

| Endpoint | Throughput | DB txns/request |
|---|---|---|
| `/health` (no DB, no auth) | **600 req/s** | 0 |
| `/auth/me` | 124 req/s | 3 |
| `/races` | 75 req/s | 10 |
| `/home/race-card` | — | 12 |
| **Direct DB benchmark** (bypassing PgBouncer) | **1,000–2,000 qps** | — |

`/health` proves nginx + Node + TLS can do 600 req/s. The drop to 75 is
**our application work** — roughly **11–13 ms of CPU per request**, dominated by
Prisma. The database is not the constraint.

DB transaction counts were measured via `pg_stat_database.xact_commit` deltas
over 20 sequential requests.

### Traffic model

- **84,815 requests/day** across **117 DAU** = **~725 requests per user per day**
- Daily average ≈ 0.98 req/s; observed peak minute 228/min = 3.8 req/s
- **Peak ≈ 4× daily average** — use this factor for all projections

### Capacity today

| | Peak req/s | DAU | Concurrent in-app users |
|---|---|---|---|
| Current | ~4 | 117 | ~8 |
| Comfortable (p95 < 300ms) | ~35–40 | **~1,000** | **~70** |
| Cliff (multi-second latency) | ~85 | **~2,500** | **~170** |

### Staging load testing does not hurt prod

During a 2.5-minute ramp that pinned the core to 0% idle, **prod p50 stayed at
27ms vs a 31ms baseline**, and recovered to 29ms. Staging load tests are safe to
repeat. Caveat: staging's pool is 3 connections vs prod's 19, so staging
*understates* prod on the DB axis.

---

## 3. The next wall after CPU

Resizing the droplet does **not** buy unlimited runway. The DB wall is close:

```
~1,500 qps ÷ 10 txns per /races request  ≈  150 req/s
```

We are at ~85 req/s. **The DB wall is roughly 2x away — about one resize step.**
A 4-vCPU droplet would overshoot into a database that cannot be fed.

Additionally, `max_connections = 50` with ~36 used leaves **14 spare
connections**. Prod's pool is 19 for a single instance; several instances would
demand far more than the cluster has, on a cluster we share with another
project.

**Conclusion:** resizing is worth ~2x, not ~10x. It must be sequenced with
traffic reduction and a DB plan, not done alone.

---

## 4. The plan

Ordered by return on effort. **Do not reorder** — Phase 2 is a hard prerequisite
for Phase 4.

### Phase 1 — Cut redundant client polling (biggest win, zero cost)

**Problem.** Race detail runs **two independent 5-second pollers** against the
same resource:

- `lib/services/race_chat_service.dart:201` → `/races/:id/messages?kind=USER`
- `lib/services/race_feed_service.dart:164` → `/races/:id/messages?kind=SYSTEM`

That is ~0.4 req/s per user just sitting on a screen. Race messages were **~30%
of all requests** yesterday. 725 req/user/day is far above what this app needs.

**Actions.**
1. Collapse the two pollers into **one request** returning both kinds (either a
   combined `kind=ALL` response or a single call the client splits).
2. Back the interval off **5s → 15s**. Optionally adaptive: 5s while the user is
   actively typing/scrolling chat, 15–30s otherwise.
3. Pause polling when the screen is not foregrounded.
4. Audit `main_shell.dart:617` (5-min foreground poll) and
   `race_detail_screen.dart:797` (30s) for overlap with the above.

**Backward-compat (CLAUDE.md rule #1).** Old app binaries will keep polling the
existing endpoint at 5s forever — they are frozen. So:
- The existing `/races/:id/messages?kind=…` contract **must keep working
  unchanged**. Add the combined response as a *new* shape or a new param;
  never change or remove the old one.
- The traffic reduction therefore only materialises **as the new build rolls
  out** (~1 week phased). Model the win as gradual, not instant.

**Expected gain:** ~30% traffic cut immediately on updated clients; roughly
**2x effective DAU headroom** once rolled out. Also pushes back the §3 DB wall,
which resizing does not.

**Measure:** re-run §7 and confirm req/user/day drops from ~725 toward ~350.

---

### Phase 2 — Gate crons to one instance (BLOCKER for Phase 4)

**Problem.** `src/index.js` starts **~17 cron jobs unconditionally in every
process**. There is no `NODE_APP_INSTANCE` guard. The code comment at
`src/index.js:68` already acknowledges the hazard:

> *"the in-process overlap guards don't reach across processes; e.g.
> seededRaceRenewal could double-create a PENDING race, which has no DB unique
> to stop it"*

`JobRun.markRan` is not atomic, so nothing dedups at the DB layer either
(see the `cron-dedup-no-advisory-locks` incident).

**Consequences if `instances > 1` without this fix:** duplicate race
settlement, **duplicate minted coins**, double seeded-race creation, and
**double push fan-outs to the entire user base** (`livePlacement`,
`dailyMover`). This is a correctness and money bug, not a performance one.

**Actions.**
1. Wrap the `startCrons()` body in an instance guard:
   ```js
   const isCronLeader = Number(process.env.NODE_APP_INSTANCE ?? 0) === 0;
   if (!isCronLeader) { logger.log("cron leader election: standby instance, crons skipped"); return; }
   ```
2. Keep the existing `CRON_START_DELAY_MS` reload guard — it solves a different
   problem (old/new process overlap during `pm2 reload`) and is still needed.
3. Log clearly which instance won, so it is verifiable in `pm2 logs`.
4. **Tests first** (per CLAUDE.md): assert `startServer` schedules zero crons
   when `NODE_APP_INSTANCE=1` and the full set when `NODE_APP_INSTANCE=0`.
5. Longer term, replace in-process `setInterval` with insert-first unique-key
   dedup or CAS so leader election is not the only safeguard.

**Note:** this is a **no-op at `instances: 1`**, so it can ship safely well
before any resize.

---

### Phase 3 — Move staging off the prod droplet

Staging Node currently competes with prod Node, nginx, and Docker for the single
core. A staging deploy or test steals prod's CPU for free.

**Actions.**
1. Move staging to its own small droplet.
2. Move staging to its own DB (or at minimum stop sharing the connection budget).
3. Update `DEPLOYMENT.md` — the two-checkouts-one-droplet table becomes stale.

**Cost:** ~$12/mo. **Gain:** prod gets the whole core; staging load tests become
truly isolated and can be run aggressively.

---

### Phase 4 — Resize the prod droplet

**Only after Phase 2 has shipped.**

**Actions.**
1. Resize droplet **1 → 2 vCPU** (~$12 → ~$24/mo).
2. Raise pm2 `instances` from 1 → 2 **only once the Phase 2 cron guard is
   verified in prod logs.**
3. Confirm the prod pool (19) still fits the connection budget with 2 instances.

**Safe intermediate:** resizing to 2 vCPU while leaving **`instances: 1`** is
safe with or without Phase 2, and still helps materially, because prod Node stops
fighting staging/nginx/Docker for one core. Take this step first if Phase 2 is
not ready.

**Expected gain:** ~2x app tier — which lands right on the §3 DB wall.

---

### Phase 5 — Database: own cluster, then scale up

Required to go past ~150 req/s.

**Actions.**
1. **Get off the shared `stock-sentiment` cluster** — an unrelated project can
   currently degrade Bara and is consuming our connection budget.
2. Resize the DB plan; raise `max_connections` accordingly.
3. Reduce transactions per request — `/home/race-card` at **12 txns** and
   `/races` at **10 txns** are the top targets. Batch, cache, or denormalise.
4. Enable **`pg_stat_statements`** (currently not installed) so slow queries can
   be identified without guesswork.
5. Add read caching for hot, rarely-changing payloads (`/shop/catalog`,
   `/powerups/catalog`, `/app-version/policy`).

---

## 5. Projected capacity by phase

Approximate, assuming the 4× peak factor holds.

| After phase | Peak req/s | Comfortable DAU | Monthly cost delta |
|---|---|---|---|
| Today | ~85 cliff | ~1,000 | — |
| Phase 1 (polling) | ~85 cliff, traffic halved | **~2,000** | $0 |
| Phase 3 + 4 (staging out, 2 vCPU) | ~150 (DB-bound) | **~3,500** | ~+$24 |
| Phase 1 + 3 + 4 combined | ~150 (DB-bound) | **~7,000** | ~+$24 |
| Phase 5 (DB) | 300+ | **15,000+** | ~+$60–100 |

---

## 6. Monitoring to add before we need it

The system degrades into slowness with **zero errors**, so error-rate alerting
will never fire. Add:

1. **Request latency logging** — nginx currently logs no timing. Add
   `$request_time` / `$upstream_response_time` to `log_format`. This is the
   single highest-value observability gap.
2. **Alert on p95 latency**, not error rate.
3. **Droplet CPU alert** at sustained >70%.
4. **DB connection-count alert** at >40 of 50.
5. Track **req/user/day** as the key efficiency metric — it is the number that
   Phase 1 is trying to move.

---

## 7. How to re-measure (reproducible)

Re-run after each phase to validate the projections.

1. **Baseline traffic** — on the droplet:
   ```bash
   zcat -f /var/log/nginx/access.log.1 | wc -l          # requests/day
   zcat -f /var/log/nginx/access.log.1 \
     | awk '{print $6, $7}' | sed -E 's#/[0-9a-f-]{36}#/:id#g; s#\?.*##' \
     | sort | uniq -c | sort -rn | head -25             # endpoint mix
   ```
2. **Mint a staging token** (never a prod one) using
   `signSessionToken` from `src/modules/users/services/sessionToken.js`.
3. **Ramped load test** against `staging.steptracker-api.org` with a weighted
   endpoint mix, concurrency 2 → 150, ~15s per step, **while polling a prod
   endpoint (`/app-version/policy`) as a watchdog** with an automatic abort if
   prod median latency exceeds 8× baseline.
4. **DB txns/request** — read `pg_stat_database.xact_commit` before and after N
   sequential requests and divide.
5. **DB ceiling** — benchmark via the **direct** connection (port **25060**,
   database `step-tracker-staging`) to bypass the 3-connection PgBouncer pool.
   Strip `sslmode` from the URL and pass `ssl: { rejectUnauthorized: false }`,
   or `pg` v9 will reject the DO self-signed chain.

**Rules.** Never load test against the prod database. Never point
`cosmetics:apply` or integration tests at prod. Staging ramps are safe for prod
(measured), but keep the watchdog in place anyway.

---

## 8. Acceptance criteria

- [ ] **Phase 1:** single combined message poll at ≥15s; old endpoint contract
      unchanged for frozen clients; req/user/day measured below 400.
- [ ] **Phase 2:** crons run on exactly one instance, verified in prod `pm2
      logs` with `instances: 2`; tests cover both leader and standby.
- [ ] **Phase 3:** staging serves from its own droplet and DB; `DEPLOYMENT.md`
      updated.
- [ ] **Phase 4:** prod on 2 vCPU; `instances` raised only after Phase 2 is
      verified; re-test shows ≥140 req/s.
- [ ] **Phase 5:** Bara on a dedicated DB cluster; `pg_stat_statements` enabled;
      `/home/race-card` under 6 txns/request.
- [ ] **Monitoring:** nginx logs response times; p95 and CPU alerts live.

---

## 9. Open questions

1. Is the stock-sentiment project's DB usage growing? It shares our 50
   connections and 1 vCPU today.
2. Do we want push/WebSocket for race chat instead of polling? That removes the
   dominant load source entirely, but is a much larger change than Phase 1 —
   Phase 1 should ship first regardless.
3. What is the actual DAU growth target and timeline? That decides whether we
   stop after Phase 1 or go straight through Phase 5.
