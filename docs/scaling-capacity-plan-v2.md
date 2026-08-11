# Scaling & Capacity Plan v2 — Redis audit, revised ceiling, road to 10k

**Status:** Draft for approval · **Measured:** 2026-08-10 · **Owner:** Rohan

**Supersedes `docs/scaling-capacity-plan.md` (2026-07-25).** That document's
headline numbers (~1,000 DAU comfortable / ~2,500 cliff) are **wrong by ~15x**
— see §3.3 for why. Its infrastructure inventory and its identification of the
cron blocker remain correct and are carried forward here.

Everything below is measured against **prod** on 2026-08-10, not estimated.
Reproduction procedure in §7.

---

## 1. Summary

Three findings, in order of how much they should change your plans.

1. **The Redis layer works, but for one of the six things it does.** The win is
   the write-deferral (C0 queue + zero-write read path), not the caching. Zero
   deadlocks in 3 days across 34M transactions; `/races/:id/progress` p50 down
   55–66% under 1.7x traffic. Three of the five cache surfaces are not paying
   for themselves at current read volume, and `/auth/me` is net negative. §2.

2. **The real capacity ceiling is ~140 DAU comfortable, ~210 hard.** We are at
   **104 DAU** burning **57% of the single core at peak**. That is ~1.3x
   headroom, not the ~8x the July plan claimed. §3.

3. **10,000 DAU is a re-platform, not a tuning exercise** — ~96x current load,
   four independent walls. But at 149 total accounts it is also premature. The
   recommended action is Phase 1 (an afternoon) plus the cron leader election,
   then re-measure. §4, §6.

---

## 2. Redis derived-data layer — is it doing its job?

Rolled out 2026-08-07; all five cache flags plus `redisCacheDiscardCapEnabled`
have been `true` in prod since 23:45 UTC that day. `raceQueueV2ClaimingDisabled`
and `inlineRaceResolutionFallback` rows do not exist → defaults false → the C0
v2 worker is the live path with no fallback engaged. `/health` reports
`{"status":"ok","redis":"ok"}`. Zero Redis errors in the last 5k lines of prod
logs.

### 2.1 Memory on the droplet — a non-issue

```
used_memory_human:       2.98M      maxmemory:      100.00M
used_memory_peak_human:  3.55M      maxmemory_policy: allkeys-lru
used_memory_rss_human:  13.97M      evicted_keys:   0
db0 (prod): 70 keys                 db1 (staging): 17 keys
```

~3 MB logical / ~14 MB RSS = **0.7% of the box's 1,967 MB**, 3% of the 100 MB
cap, well under the runbook's 75 MB alarm and under the spec's "<20 MB working
set" expectation. Fragmentation ratio 4.71 looks alarming but is meaningless at
this dataset size — allocator overhead dominates when the payload is 3 MB.

Redis is not the memory pressure on this box. Two 311–387 MB pm2 Node processes
are; only 343 MB is free.

### 2.2 What the queue is doing — working

`race_resolution_jobs_v2`: 43 rows, **all `succeeded`**, newest requested 0.7s
ago, nothing stuck in `RUNNING`. Job rows are upserted per race.

`pg_stat_database.deadlocks` = **2, unchanged from the pre-rollout baseline**
(`/root/redis-rollout-baseline-2026-08-07.txt`) across an additional ~34M
commits (97.95M → 131.96M `xact_commit`). The 2026-08-07 deadlock incident has
not recurred. **This was the entire point of the project and it succeeded.**

### 2.3 Latency, before vs after

nginx `timed` logs, 17:00–19:00 ET window on each day (same clock time, to
control for daily shape):

| endpoint | Aug 7 (flags off) | Aug 8 | Aug 10 |
|---|---|---|---|
| `/races/:id/progress` p50 | 803 ms | 272 ms | 365 ms |
| `/races/:id/progress` p95 | 2.41 s | 1.39 s | 1.77 s |
| `/races/:id/progress` n | 357 | 517 | 615 |
| `POST /steps/samples` p50 | 2.60 s | 0.83 s | 0.81 s |
| `POST /steps/sync-v2` p50 | 1.72 s | 1.05 s | 1.13 s |

**p50 down 55–66% on the target endpoint while serving 1.4–1.7x the traffic.**

Regressions in the same window:

| endpoint | Aug 7 p50 | Aug 10 p50 |
|---|---|---|
| `GET /races` | 88 ms | 187 ms |
| `GET /auth/me` | 37 ms | 69 ms |
| `GET /races/:id/messages` | 52 ms | 77 ms |
| `POST /steps` | 22 ms | 105 ms |

**Caveats, stated plainly:** the pre-flip sample is only ~3 hours (the `timed`
nginx format only went live 16:42 ET that day); traffic is ~1.7x higher on
Aug 10 on a single vCPU; and two backend batches (2026-08-10, 2026-08-10b)
shipped in between. The regressions are confounded and should not be attributed
to Redis with confidence — but they are also not what you would expect from
adding caches, and §3 gives a likelier explanation (CPU contention).

### 2.4 Per-surface hit rates — measured, not assumed

Two `redis-cli MONITOR` samples (60s and 180s, ~23:00 ET, the quietest hour):

| key | reads | rebuilds | effective hit rate | verdict |
|---|---|---|---|---|
| `user:cosmetics:*` | 21 | 0 | ~100% | **working** |
| `race:msgs:*` | 14 | 0 | ~100% | **working** |
| `user:daily:*` | 28 | 17 (+11 del) | ~39% | marginal |
| `catalog:*`, `assets:manifest` | 8 | 4 | ~50% | fine, tiny volume |
| `settings:app` | 5 | 5 | **0%** | 60s TTL, read slower than it expires |
| `user:authme:*` | 8 | 6 (+6 del) | ~25% | **net negative** |
| `race:progress:*` | **0** | 11 sets | — | write-only in this window |

Low-traffic window, so read-driven rates improve at peak; the fixed-cadence
writes do not.

### 2.5 Why `/auth/me` (C5) is net negative

`authMeCache.js:79` sets a **10-second TTL**, and the invalidation inventory in
that file's header hangs a `DEL` off `User.update` plus both coin seams — so
every coin award, profile write, and friend request nukes it.

Measured: 20 Redis round-trips + 6 invalidation writes bought 2 avoided
Postgres assemblies.

The cause is structural, not a bug. A **per-user** key with a 10s TTL only pays
off if the same user calls `/auth/me` twice within 10 seconds. At ~4 calls/min
across the entire user base, that essentially never happens. C5 also carries
the single largest correctness liability in the layer — a hand-maintained
invalidation inventory that must stay true on every future write site.

### 2.6 Why `race:progress` (C3) is write-inverted

11 SETs, zero GETs in three minutes. Two compounding causes:

- `raceProgressSideEffects.js:169` publishes a snapshot on **every** worker
  `onCommitted`, and `recordSteps.js:168` / `recordStepSamples.js:157` enqueue a
  job for **every active race the syncing user is in**. So standings are
  recomputed and published for races nobody is viewing.
- Soft TTL is 15s (`raceProgressSnapshot.js:41`) but clients poll every 30s. A
  race with one viewer expires its snapshot before that viewer returns. The
  snapshot only earns a hit when ≥2 people watch the same race within 15s.

**Yet `/progress` p50 still fell 803 → 272 ms.** That improvement did not come
from cache hits. It came from `getRaceProgress.js:1281` — the rebuild now runs
`persist: false`. The old path replayed *and wrote back every participant* on
every poll. The Redis snapshot is close to incidental to the measured win.

### 2.7 Verdict: worth keeping, but rebalance it

**You did not build a cache layer; you built a write-deferral layer, and that
part works.** The caching bolted onto it is mostly waiting for a DAU you do not
have yet.

Carrying the value:
- **C0** — the race-keyed single-writer queue + zero-write read path. The entire
  return on the project. Note it needs Redis only for the rebuild lock; the
  queue itself lives in Postgres.
- **C1 catalogs, C2 messages, C4 cosmetics** — shared keys, many readers, high
  hit rates, real Postgres load removed. Cheap and correct.

Not carrying value: **C5 `/auth/me`** (net negative), **`settings:app`**
(0% hit), **the progress snapshot** (a publish channel with few subscribers).

Redis costs ~14 MB RSS and near-zero CPU, so keeping it is nearly free in
resources. The real price is the maintenance surface — a kill-switch ladder,
per-prefix bypass breakers, and an invalidation inventory. Three of five
surfaces are not currently paying that back.

### 2.8 Recommended actions (Redis)

1. **Turn `redisCacheAuthMeEnabled` off.** One `app_settings` update, no
   deploy, instantly reversible. Removes the largest correctness liability in
   the layer for zero measured loss.
2. **Raise the progress soft TTL from 15s to ~35s** so it sits above the
   client's 30s poll. Single-viewer races start hitting instead of rebuilding
   every poll. Low risk — physical TTL is already 60s.
3. **Stop publishing snapshots for unwatched races** — gate `publishSnapshot`
   on a recent-reader marker instead of firing on every `onCommitted`. This is
   the biggest wasted-CPU item on a 1-vCPU box (see §3).
4. **Expose the counters.** `raceProgressSnapshot.js` already tracks
   `snapshotHits` / `requestReplays` / `staleServes`, but nothing reads them —
   they increment into a void. A line in `/health` or a per-minute log means
   nobody ever has to reach for `MONITOR` to answer this question again.

---

## 3. Revised capacity model

### 3.1 The model

Box CPU regressed against request rate across **140 ten-minute buckets** from
one day of `sar -u` plus bot-filtered nginx logs:

```
busy% = 11.0 + 9.43 × rps        (n = 140)
```

Predicts well at both ends: 2.1 rps → 30.8% predicted vs 30.2% observed;
4.7 rps → 55.3% predicted vs 57.1% observed.

- **Fixed background: 11% of one core** (crons + worker + staging idling)
- **Marginal: ~94 ms CPU per request**

### 3.2 Where we are

| | value |
|---|---|
| DAU (synced in 24h) | **104** (WAU 115, 149 total accounts) |
| Real requests today | 88,622 → **852 req/DAU/day** |
| Peak 10-min | **4.70 rps** (4.6x daily average) |
| CPU at that peak | **57% busy** |
| `%steal` | 0.4% — not a noisy-neighbor problem |
| DB size | 151 MB |

Derived conversion: **0.0452 peak rps per DAU.**

**The ceiling:**

| target | peak rps | **DAU** |
|---|---|---|
| 70% busy — comfortable, p95 holds | 6.3 | **~140** |
| 85% busy — latency climbing visibly | 7.9 | **~175** |
| 100% — saturation, queue collapse | 9.4 | **~210** |

**~1.3x headroom.** At ~140 DAU it starts to hurt; around 200 it falls over.

### 3.3 Why the July estimate was 15x optimistic

July concluded ~1,000 DAU comfortable from a throughput plateau of 75–89 rps,
implying ~13 ms CPU/request. Real traffic costs **94 ms**. Two reasons the
synthetic test missed it:

1. **It hammered cheap read endpoints.** The real cost center is step ingest.
   Today `POST /steps/sync-v2` (avg 1.31s) + `POST /steps/samples` (avg 1.05s)
   + `POST /steps` = **39% of all upstream time on 10% of requests**. The load
   test never exercised that path.
2. **It could not see the async worker.** Every step sync calls
   `enqueueRaceResolutionForUser`, which enqueues a job per active race, and
   each job's `onCommitted` runs a full standings recompute + publish (§2.6).
   That CPU is *caused by* the request but lands *off* the request — invisible
   to a latency-based load test, fully visible in a CPU regression.

**The empirical number is the one to trust.** If the ceiling were really
75–89 rps, 104 DAU at 4.7 rps would sit at ~6% CPU. It sits at 57%.

### 3.4 What is *not* the bottleneck

The database, still — as July also found. 151 MB DB, `blks_hit` 2.4B vs
`blks_read` 13,398 lifetime (entirely resident in RAM), zero deadlocks since
the Redis rollout, and July's direct benchmark was 1,000–2,000 qps. The
bottleneck is **Node CPU on one shared core**.

Memory is quietly tight, though: 343 MB free with prod Node at 387 MB and
staging Node at 310 MB on the same 2 GB box.

### 3.5 Caveat

This is a one-day fit at 10-minute granularity, so bursts inside a bucket are
not captured — true 1-minute peaks run higher, which makes ~140 an
**optimistic** comfortable ceiling rather than a conservative one. Re-run
across several days (§7) to tighten it.

---

## 4. Scaling to 10,000 DAU

10,000 DAU is **~96x** today. At today's conversion that is **452 rps peak**
(~8.5M req/day), and at today's 94 ms/request, **~42 cores of Node**. Hardware
alone would mean ~12 four-core boxes. Per-request cost must come down *and* the
system must go horizontal; either alone is insufficient.

### 4.1 The four independent walls

1. **Node CPU** — 94 ms/request × 452 rps.
2. **Database** — still `db-s-1vcpu-2gb`, `max_connections = 50` with **35
   already in use**, on cluster `stock-sentiment` **shared with an unrelated
   project**. July measured 3–12 transactions/request; at 452 rps that is
   ~2,700 tps against something benchmarked at 1,000–2,000 qps. Throughput
   *and* connection count are both hard walls.
3. **Single-process crons** — `src/index.js:82` starts ~17 schedulers in every
   process with **no `NODE_APP_INSTANCE` guard** (re-verified 2026-08-10), so
   `instances` is pinned at 1. Worse, `placementRecompute.js:26` recomputes
   standings for **every active race every 5 minutes** in-process; at 10k DAU
   that job cannot finish inside its own interval.
4. **Push fan-out** — `apns.js` opens per-notification HTTP/2 requests with no
   batching, and there are three whole-base push jobs (live placement, daily
   mover, daily-reward + milestone reminders).

### 4.2 Phase 1 — buy time (→ ~400 DAU)

No architecture change. An afternoon of work.

- Resize droplet 1 → 4 vCPU.
- Move staging to its own box and off the shared DB cluster.
- **Collapse the two 5s race-detail pollers into one endpoint at 15s.**
  `/races/:id/messages` is 21,956 req/day = **25% of all traffic**. Biggest
  free cut available. (Carried over from the July plan; still not done.)
- Gate `publishSnapshot` on a recent-reader marker (§2.8 item 3).
- Turn off `redisCacheAuthMeEnabled` (§2.8 item 1).

### 4.3 Phase 2 — make horizontal scaling legal (→ ~1,500 DAU)

**The real unlock. Nothing past this point works without it.**

- **Leader election for crons.** A `job_leases` row with atomic CAS — per the
  existing "no advisory locks" rule (`cron-dedup-no-advisory-locks`, the
  3e6c827 outage). Every scheduler acquires before running. Until this exists
  you cannot run two processes, period.
- **Audit module-level `Map`/`Set` state for multi-instance correctness.** ~20
  files hold in-process state — `userPresentationCache`, `balanceConfig`,
  `clientFeatures`, `derivedCache`'s bypass breaker. Each is either fine
  (idempotent cache), needs moving to Redis (shared invariant), or is a
  correctness bug the moment a second process exists.
- Then `instances: 4` on the 4-core box.

### 4.4 Phase 3 — the data layer (→ ~5,000 DAU)

- **Get off the shared cluster** onto a dedicated 4–8 vCPU managed Postgres,
  and size pgbouncer properly (transaction pooling, ~2x cores — not 19 slots on
  a 50-connection ceiling shared with someone else's project).
- **Attack step ingest.** 39% of all upstream time on 10% of requests; this is
  where the 94 ms lives. Batch the per-race enqueue fan-out instead of one job
  per race per sync.
- **Fix the O(all races) 5-minute job.** Shard by race ID across workers, or
  make it event-driven off the resolution queue rather than a full sweep.
- Read replica for leaderboard/standings reads.

### 4.5 Phase 4 — 10,000 DAU

- Split the API from the workers into separate deploy units so a push storm
  cannot starve request serving.
- Real queue infrastructure for pushes, with batched APNs delivery over a
  persistent connection pool.
- Redis stops being optional — at that scale the hit rates in §2.4 invert and
  the layer finally earns what it was designed for. The surfaces underperform
  today purely because read volume is too low to fill a TTL window.
- Load balancer + ≥3 API nodes, autoscaled.

---

## 5. Carried-forward context (from the July plan, still true)

- Droplet `167.172.225.16` = **1 vCPU / 2 GB**, runs prod Node (3002) AND
  staging Node (3003) AND nginx AND Redis AND Docker on one core.
- DB = DO managed `db-s-1vcpu-2gb`, PG 18, single node, cluster
  `stock-sentiment` (`7ae2dc3e-d42a-4444-90a1-eabc79a41539`), shared with an
  unrelated project. Pooled port **25061**, direct **25060**. Prod pool
  `step-tracker-pool` = 19 conns, staging `bara-staging-pool` = 3.
- Testing staging does **not** meaningfully hurt prod (measured July): during a
  ramp pinning the core to 0% idle for 2.5 min, prod p50 stayed 27 ms vs 31 ms
  baseline. Safe to repeat.
- Redis operational detail lives in `stepv2-backend/docs/redis-cache-runbook.md`
  (kill-switch ladder, C0 reverse-handoff order). Password in
  `/root/redis-rollout-baseline-2026-08-07.txt` (0600).

---

## 6. Recommendation

There are **149 total accounts**. Phases 3–4 are months of work to serve
traffic that does not exist, and every hour spent there is an hour not spent
finding out whether 10,000 people want this.

**Do now:**
1. **Phase 1** (§4.2) — an afternoon; droplet resize + poller collapse alone
   gets ~4x headroom.
2. **The cron leader election** from Phase 2 — not because multiple instances
   are needed today, but because it is the one blocker that gets harder the
   longer it waits, and it currently stands between you and simply adding
   hardware in an emergency.
3. **The four Redis actions** in §2.8 — all cheap, one is a flag flip.

**Then re-measure** (§7). The regression is cheap to re-run and will say
exactly when the next wall arrives, instead of guessing — which is how the July
estimate ended up 15x optimistic.

---

## 7. Reproduction procedure

All read-only. Run from a machine with SSH access to the droplet.

**Capacity model:**
1. Bucket bot-filtered nginx requests into 10-minute windows:
   `grep -v "wp-login\|xmlrpc\|\.php\|\.env" /var/log/nginx/access.log` →
   extract `HH:M0` from field 4 → count / 600 = rps.
2. Extract matching CPU buckets: `sar -u`, `busy = %user + %system`.
3. Least-squares fit `busy% = intercept + slope × rps`. Intercept is fixed
   background load; `slope × 10` = ms CPU per request.
4. Ceiling: `rps_max = (target_busy − intercept) / slope`; convert with the
   measured `peak_rps / DAU` ratio.

**Redis hit rates:** `timeout 180 redis-cli MONITOR > /tmp/mon.txt`, then tally
`(command, key-prefix)` pairs for db0. Reads with no matching write in the same
window = hits. Run at peak *and* off-peak; they differ a lot.

**DAU:** `select count(*) from users where last_step_sync_at > now() - interval
'24 hours'`.

**Deadlock check:** `select deadlocks from pg_stat_database where datname =
'step-tracker'` — compare as a delta against
`/root/redis-rollout-baseline-2026-08-07.txt` (`stats_reset` is NULL, so these
are lifetime counters).

**Do not** run load tests against prod. Staging is safe (measured, §5).
