# Redis Derived-Data Layer — Requirements

Status: **APPROVED for phased implementation** (owner, 2026-08-07, post-v7).
Phase order per §7; C0 ownership/fencing, rollback, Redis fallback, compat, and
test coverage signed off.

## 1. Summary & user story

Prod is experiencing bursts of Postgres deadlocks, connection-pool exhaustion,
and transaction-start timeouts (2026-08-07 incident). Root cause is architectural:
many concurrent writers (step-sample ingestion, the async resolution worker, the
5-minute placement recompute, and — critically — the `GET /races/:id/progress`
read endpoint itself) all rewrite the same ~2,400 `race_participants` rows with
no mutual exclusion (6.3M updates recorded on 2,396 live rows; `withRaceResolutionLock`
is a deliberate passthrough since the 2026-07-18 advisory-lock pool-drain incident).

As a user, I want race standings, chat, and my profile to load fast and never
error during peak sync windows. As the operator, I want request-path reads served
from a cheap derived cache so that Postgres holds only source-of-truth ledgers
and single-writer derived state — eliminating the observed bulk-writer deadlock
class by ownership (and closing the residual class with a global lock order,
§5a) and buying headroom well past the current ~1,000-DAU comfort ceiling.

This spec introduces a **local Redis instance on the droplet** as a derived-data
layer, targeted by an analysis of 8 days of real prod traffic (~200k requests)
and Postgres scan statistics.

### Measured hot spots this design serves (prod data, 8 days)

| Rank | Surface | Requests / share | Backing today |
|---|---|---|---|
| 1 | `GET /races/:id/messages` | 82,185 (~33%) | PG query + cosmetics join per poll (5s interval per viewer) |
| 2 | `GET /auth/me` | 26,492 (~11%) | PG multi-table assembly per call |
| 3 | `GET /friends/steps` | 16,593 (7%) | PG per call |
| 4 | `GET /races` | 16,462 (7%) | persisted `race_participants` reads |
| 5 | `GET /races/:id/progress` | 14,841 (6%) | **full replay recompute + N-row UPDATE per poll** |
| 6 | `GET /powerups/inventory` | 14,303 (6%) | PG per call |
| 7 | `GET /home/race-card` | 11,457 (5%) | persisted or live recompute (flag-dependent) |
| 8 | catalogs (`/shop/catalog`, `/powerups/catalog`) | 9,896 (4%) | `shop_items`: 912k **seq scans**; near-static data |

Table-level: `race_active_effects` 14.8M reads (9.5k rows), `user_equipped_accessories`
1M seq scans (93 rows), `global_step_events` 557k reads (31 rows).

## 2. Scope / non-goals

### In scope
1. Redis infra: local `redis-server` on the droplet, localhost-only, `requirepass`,
   `maxmemory 100mb` + `allkeys-lru` (every key is rebuildable; expected working
   set is <20MB, so this is >5× headroom while leaving ~725MB of the droplet's
   ~825MB available RAM untouched — the app DB is DO-managed, not on this box),
   separate logical DB per env (prod `db0`, staging `db1`) plus a key prefix
   (`p:` / `s:`). Memory alarm threshold: 75MB (runbook).
2. Backend Redis client + health/fallback wrapper: **every cache read falls back
   to a Postgres path on any Redis error or when `REDIS_URL` is unset** — for
   most surfaces that is the existing query; for standings it is specifically
   the CHEAP persisted-columns read, never the expensive replay (pinned in
   Phase D step 7).
3. Cross-worker invalidation pub/sub (`cache:invalidate` channel) — also fixes
   the existing cluster-incoherent in-process caches (`balanceConfig`, `appSettings`).
4. Cache surfaces, in rollout order (each behind its own app-setting flag):
   - **C1 Catalogs & config**: shop catalog, powerup catalog, app settings,
     balance config, global step events, `/assets/manifest`.
   - **C2 Chat messages** per race (+ per-user equipped-cosmetics cache used by
     chat/leaderboard rendering).
   - **C3 Live standings**: shared per-race progress snapshot serving
     `GET /races/:id/progress`, plus removal of that endpoint's write-back
     (the M×N unlocked writes). Home race-card and `GET /races` keep reading
     persisted columns (unchanged), which stay fresh via the resolution worker.
   - **C4 Friends' daily steps** (`/friends/steps`) and `/powerups/inventory`.
   - **C5 `/auth/me` response cache** (owner decision 2026-08-07): 10s TTL +
     invalidation on **every** coin-balance write (single seam: the coin
     ledger/transaction write path), equip/unequip, and profile mutation. The
     short TTL is the safety net for any missed seam.
5. Nginx: drop rule for the ~3k/day WordPress-exploit bot probes.

### In scope (continued)
6. **Single-writer-per-race resolution (C0 — the structural deadlock fix).**
   Re-key `race_resolution_jobs` from per-user to per-race; the queue worker
   and `raceExpiry` become the only bulk writers of a race's
   `race_participants` rows, serialized against each other by the shared
   ownership/fencing protocol. See §5a.

### Non-goals (explicitly out)
- **No Postgres schema changes except the `race_resolution_jobs` re-key
  migration (§5a).** No changes to any ledger/source-of-truth table.
- **Settlement and coins never read Redis.** `raceExpiry` recompute →
  `completeRace` reading persisted `placement`/`totalSteps` is untouched.
  (C5 caches the *assembled `/auth/me` response*; coin **mutations** and their
  ledger always read/write Postgres directly.)
- The `race_resolution_jobs` durable queue (race-keyed after C0, §5a) stays in
  Postgres (its generation/superseded semantics are settlement-critical; Redis
  adds risk, not value).
- No cron leader election / queue migration; no WebSockets/push for chat.
- No frontend behavior change and no API shape change of any kind.

## 3. API contract

**No new or changed endpoints; every response stays JSON-contract compatible**
(same fields, same types, same semantics — verified by the deep-equality parity
tests in §8). One deliberate additive exception: `/health` gains an internal
`redis` field. Old app versions (frozen binaries) are unaffected because caching
is entirely backend-internal, whether a given response was assembled from Redis
or Postgres.

The only observable difference is freshness, bounded as follows:

| Surface | Today | With cache |
|---|---|---|
| `/races/:id/progress` | recomputed per call | snapshot ≤ 15s old (TTL) + immediate invalidation on powerup use / box open / forfeit / finish / join / leave / kick |
| `/races/:id/messages` | live | invalidated on every post — effectively live on the happy path. **Accepted degradation**: if the post's invalidation fails AND the failure-coordination (retry loop + broadcast) also fails, chat can serve stale for up to the 15min TTL |
| catalogs/config | 5–30s in-process TTL (per worker, incoherent) | ≤ 60s TTL + pub/sub bust on admin write (coherent across workers) |
| `/friends/steps` | live | ≤ 60s TTL + invalidation on the friend's step sync |

`asOf` / `totalsUpdatedAt` fields already in the progress/teams payloads express
staleness to clients and keep meaning exactly that.

### Internal contract: Redis key schema (v1)

All keys carry env prefix (`p:`/`s:`) and schema version. TTLs are safety nets;
invalidation is the primary mechanism.

| Key | Type | Content | TTL | Invalidated by |
|---|---|---|---|---|
| `v1:race:{id}:progress` | STRING (JSON, embeds `asOf`) | shared portion of progress payload, built from a **pinned field allowlist** (§5 Phase D) — never by deleting known-viewer fields from the full payload | **soft 15s / physical 60s**: key lives 60s; readers treat `asOf` older than 15s as "stale — serve it AND trigger rebuild". A physical 15s TTL would delete the value the moment it goes stale, making "losers serve the stale snapshot" impossible | DEL by: usePowerup, openMysteryBox, forfeit, finish, join/leave/kick, expireEffects, editRace/cancelRace. **Replaced (SET, never DEL)** by the resolution worker after its Postgres commit — the worker's SET is the freshest data and must not be followed by a delete |
| `v1:race:{id}:msgs:{kind}` | STRING (JSON array, capped 100) + `v1:race:{id}:msgver:{kind}` | last **raw** messages of kind USER/SYSTEM at default limit — cosmetics are NOT embedded; they hydrate at read time from `v1:user:{id}:cosmetics`, so an equip change never requires touching message lists | 15min (bounds worst-case staleness if every invalidation fails) | **`msgver` holds the latest durable message ID (monotonic, from the PG row), NOT a Redis counter** (a resettable `INCR` counter would be ABA-prone under `allkeys-lru`). Post (after PG commit): one Lua script does `SET msgver <newMsgId>` + `DEL list` atomically (a non-atomic pair could half-apply and let a stale rebuild reinstall). Cold rebuild uses **`WATCH msgver` → PG query → `MULTI` (SET list, SET msgver=M) → `EXEC`**, on a dedicated checked-out connection (WATCH is connection-scoped). Value-comparison CAS is NOT sufficient here: nil→set→evicted-back-to-nil between read and install would let a compare-against-nil succeed and reinstall a stale list — WATCH invalidates the EXEC on *any* modification or eviction of the key, even if its value returns to nil. Aborted EXEC ⇒ next read retries |
| `v1:race:msgwatermark:{raceId}:USER` | STRING (JSON, capped 50; cache wrapper adds `p:`/`s:`/`t:`) | body-free newest USER-message `{id,createdAt}` rows used for lazy-Chat unread detection; never contains body, sender, presentation, or access data | 15min | Shares the USER `msgver` WATCH fence. Post-commit USER send/delete and race membership/access mutations atomically advance/invalidate through the existing message invalidation seam and DEL both the full USER list and this key. Cold rebuild uses the same dedicated-connection `WATCH msgver` → bounded PG projection → `MULTI/EXEC` retry protocol |
| `v1:user:{id}:cosmetics` | STRING (JSON) | equipped accessories + character | 1h | equip/unequip, account delete |
| `v1:user:{id}:daily:{et-date}` | STRING (int) | today's step total for friends list | 60s | step sync for that user |
| `v1:user:{id}:inventory` | STRING (JSON) | powerup inventory payload | 60s | grant/use/open/purchase |
| `v1:user:{id}:authme` | STRING (JSON) | assembled `/auth/me` response | 10s | any coin-ledger write, equip/unequip, profile mutation, account state change |
| `v1:catalog:shop`, `v1:catalog:powerups`, `v1:settings:app`, `v1:balance`, `v1:events:global`, `v1:assets:manifest` | STRING (JSON) | full payload | 60s | admin writes → pub/sub `cache:invalidate` |
| `v1:lock:progress:{raceId}` | STRING NX PX | stampede lock for snapshot rebuild | 10s | self-expiry |

Pub/sub channel is **environment-namespaced** — `p:cache:invalidate` /
`s:cache:invalidate` — because Redis pub/sub is NOT isolated by logical DB;
subscribers subscribe only to their own env's channel and additionally reject
messages whose key prefix mismatches their env (belt and braces). Messages
carry `{key or prefix}`; every worker busts both Redis-adjacent and legacy
in-process caches.

### Cache mutation failure rules (transient-Redis-error safety)
- **Reads**: any Redis error → return null → caller falls through (existing rule).
- **Write paths never write caches directly** (no RPUSH-after-DEL patterns —
  a DEL+repush race would recreate a list containing only the new entry).
  Mutating requests only **invalidate** (atomic Lua `SET` version-to-durable-ID
  + DEL); reads rebuild under the WATCH/MULTI/EXEC guard (key table). The resolution worker's snapshot SET is the one
  exception (it *is* the authoritative replacement).
- **Failed invalidation (DEL error)**: retry once inline; if still failing,
  the process (a) enters a local read-bypass for that key prefix, (b)
  broadcasts the bypass on the env's `cache:invalidate` channel so peer
  workers bypass too (best-effort), and (c) keeps a background retry loop
  going until the DEL succeeds — the bypass stays open **until deletion
  succeeds**, not for a fixed 60s. Honest bounds: the cross-worker broadcast
  is best-effort (pub/sub through the same struggling Redis), so the hard
  backstop is each key's physical TTL — which is why chat's TTL is 15min, not
  24h, and every other key is ≤60s. Today prod runs a single pm2 instance, so
  the local bypass is in practice global; the broadcast is for the
  multi-instance future.
- **Pub/sub is lossy** across subscriber disconnects: on (re)connect, every
  worker flushes all its in-process caches; TTLs remain the backstop for missed
  messages while connected.

## 4. Data model / storage

- Postgres: **no changes to any source-of-truth table.** The only schema change
  is the C0 queue migration (§5a, expand/contract). `race_participants` remains
  the persisted standings store, bulk-written only by the race-keyed resolution
  worker and `raceExpiry`, plus small user-action transactions
  (join/leave/forfeit/powerups) — the request-path writer (`getRaceProgress`)
  is removed in C3 and `placementRecompute` becomes enqueue-only in C0.
- Redis sizing: worst case well under 20 MB at current scale (241 races × ~4 KB
  snapshots + 100-message lists + per-user keys for 131 users); `maxmemory 100mb`
  (matches §2; alarm at 75MB) gives >5× headroom. `allkeys-lru` is safe because
  every key is a rebuildable derived view — Redis flush = cold cache, never
  data loss.
- Backup/persistence: RDB snapshots off, AOF off. Deliberate: the cache must be
  disposable, and the droplet's disk/CPU budget is tight.

## 5a. Single-writer-per-race resolution queue (C0 — deadlock fix core)

**Principle** (owner-approved 2026-08-07): every `race_participants` row has one
bulk writer, determined by partitioning — the race. Concurrency is eliminated by
routing, not managed by locks. This is the scaled-down Kafka-keyed-partition /
actor-ownership pattern; the existing Postgres queue already provides the
claiming, generation/superseded, and lease semantics — only the key changes.

### Design
1. **Migration — expand/migrate/contract (zero-downtime under `pm2 reload`)**:
   - **Expand (deploy N)**: create a NEW table `race_resolution_jobs_v2`
     (`raceId` unique, `generation`, `processingGeneration`, lease columns,
     `leaseToken`, retry state, `notBeforeAt`, `triggeredByUserIds` JSONB,
     `processingTriggeredByUserIds` JSONB, `lastCompletedAt`). The old table
     is untouched. The new binary reads and
     writes ONLY v2. During the `pm2 reload` overlap window, old workers keep
     draining the old table against the old schema (still intact) while new
     workers run v2 — no worker ever sees a schema it doesn't expect.
   - **Worker handoff (no old/new concurrent bulk-writing)**: schema
     compatibility alone would recreate the bulk-writer race during the
     `pm2 reload` overlap (old worker draining old jobs while the v2 worker
     resolves the same races). Therefore the v2 worker observes a **startup
     quiet period of 60s** (> the old worker's 30s lease + the reload window;
     analogous to the existing `CRON_START_DELAY_MS`) and, until it has once
     observed the old table with zero RUNNING-with-unexpired-lease rows, does
     not claim (this check tolerates the old table already being dropped, for
     post-contract restarts). pm2 kills old workers within seconds of reload,
     so by first v2 claim the old bulk writer is provably gone. Old-binary
     *inline* request-path writes during those same seconds are the status quo
     ante, not a new risk.
   - **Cutover loss bound**: jobs pending in the old table at overlap end are
     abandoned; they regenerate from the next sync or the 5-minute
     `placementRecompute` enqueue backstop, so worst-case convergence delay at
     cutover is ~5 minutes + the 60s quiet period, once.
   - **Rollback — reverse handoff (schema safety alone is NOT enough)**:
     starting old workers while a v2 worker holds a lease or is mid-write
     would recreate the concurrent-bulk-writer race in reverse. Ordered
     procedure, encoded in the runbook: (i) flip the
     `raceQueueV2ClaimingDisabled` app-setting — the v2 worker checks it
     **per tick, uncached** (this flag exists precisely for rollback; the env
     kill switch can't change on a running process); (ii) wait ≥ the 30s
     lease and verify the v2 table has zero RUNNING-with-unexpired-lease rows
     (in-flight fenced transactions bound the wait); (iii) only then deploy
     the old binary. The old table still exists with its old schema, so the
     old binary needs no awareness of any of this. A reverse-handoff test
     (5h) exercises the drain-before-old-claims sequence.
   - **Contract (deploy N+1, ≥1 week later)**: drop the old table and rename
     v2 if desired. Never in the same deploy as expand.
2. **Coalescing without losing work**: enqueue appends the triggering user to
   `triggeredByUserIds` (JSONB, append-distinct in the upsert). The claim
   atomically moves the array into a dedicated
   **`processingTriggeredByUserIds`** column (and empties the live array), and
   the worker computes `boxEffectiveSteps` / powerup-state sync / nudges for
   **every** user in that processing snapshot — not just the last one. Retry
   safety: `processingTriggeredByUserIds` persists in the job row across a
   worker crash/lease expiry, and a re-claim **unions** it with any
   newly-accumulated live array into the new processing snapshot, so a failed
   run's triggering users are re-processed, never dropped. `recordSuccess`
   clears the processing column. Users who enqueue after the claim land in the
   live array for the follow-up run that the generation bump forces.
3. **Explicit debounce (the work cap is a rule, not an emergent property)**:
   `recordSuccess` sets `notBeforeAt = now + RACE_RESOLVE_DEBOUNCE_MS`
   (default 5s, env-tunable); claim eligibility requires `notBeforeAt <= now`.
   Generation bumps mark the race dirty but can never make it run more than
   once per debounce window — a continuously-bumped busy race resolves at most
   every 5s, it does not spin. Progress-poll-driven bumps additionally only
   happen on snapshot expiry (15s), so watch-driven cadence is 15s.
4. **Enqueue sites** (upsert race row + bump generation + append triggering
   user; O(1) each):
   - sync-v2 Transaction B: enqueue each of the uploader's active races
     (replaces the single per-user enqueue).
   - Legacy `/steps` and `/steps/samples`: **stop calling `resolveRaceState`
     inline**; enqueue instead. Response shapes unchanged; any race fields they
     echo come from persisted state (≤ one resolution behind — same contract
     `GET /steps/race-resolution/:id` pollers already accept).
   - `getRaceProgress` (per §5 Phase D): enqueues the viewed race.
   - `placementRecompute` cron: becomes enqueue-only (bumps every active race
     every 5 min — the convergence backstop when nobody syncs); notification
     logic stays in the worker's post-write hook.
   - Powerup use/open, join/leave/kick, forfeit, edit/cancel: after their own
     (small, short-transaction) writes, enqueue the race.
5. **The worker and expiry share the serialized ownership protocol — no bulk
   write happens outside it — with lease fencing ACQUIRED FIRST**:
   claims one race via `FOR UPDATE SKIP LOCKED` (claim mints a fresh
   `leaseToken`), runs `resolveRaceState`'s *computation* (bases → effects →
   hitchhike → leech → trail mines) outside any transaction, then opens the
   write transaction in this order: **(i) `SELECT … FOR UPDATE` the job row
   `WHERE id = ? AND leaseToken = ?` — zero rows ⇒ abort immediately, having
   touched no participant rows; (ii) only as the verified lock-holder, write
   all N participant rows (ascending userId, see 7); (iii) update the job row;
   commit.** Fence-then-write, not write-then-fence: two workers can never
   both be mid-flight on participant rows, because the loser is turned away at
   the job-row lock before its first participant write. The held job-row lock
   also serializes against `raceExpiry` (item 6) for the transaction's
   duration. Only after the Postgres commit succeeds does the worker SET
   (replace) the Redis snapshot — commit first, publish second, never a DEL
   after the SET. Then notifications.
   Trail-mine detonation — a stateful fire-once event that is racy today —
   becomes correctly serialized for free.
6. **Settlement**: `raceExpiry` acquires the race through the SAME
   fence-first protocol — its write transaction also begins with the
   `FOR UPDATE` job-row acquisition before any participant/`setPlacement`
   write — so expiry and a live worker can never both be writing one race;
   the loser blocks or aborts at the fence. `completeRace` unchanged (pure
   reader).
7. **Residual direct writers** (accepted, with a shared lock-order rule): user
   actions (join/leave/forfeit/powerup target writes, chat/placement mutes)
   keep their small transactions — 1–2 rows, ~0.5% of traffic. Honest scoping:
   C0 makes the observed **bulk-vs-bulk deadlock class** impossible; a
   residual writer could still theoretically deadlock against the bulk worker,
   so all multi-row `race_participants` writers (the worker, `forfeitRace`'s
   `FOR UPDATE` scan, any multi-target powerup like Rainstorm) MUST acquire/
   write rows in **ascending userId order** — a single shared lock order means
   no cycle is constructible — and residual writers wrap in a retry-on-40P01
   (once) as defense in depth. Each such action enqueues its race afterward,
   so the owner re-converges.

### Worker capacity (measured 2026-08-07, prod)
Per-race resolve time from prod logs (`ms ÷ races` over 274 jobs): **p50 525ms,
p90 936ms, p99 1.76s** — and these figures *include* today's lock contention,
which C0 removes. The work cap is the explicit `notBeforeAt` debounce (design
item 3): worst case one resolve per race per 5s (sync-driven), 15s cadence for
watch-driven bumps. Capacity at the 15s watch cadence: concurrency 1 ≈ 28
continuously-watched races; concurrency 2 ≈ 57; a pathological all-races-
sync-storming case at the 5s debounce floor supports ~9–19 races per worker —
still above the ~8 currently-meaningful races. Current reality is ~130 DAU —
an order of magnitude of headroom on realistic load. Coalescing caps work per
race regardless of viewer count.
**Backpressure guard**: the worker logs queue lag (`max(now − requested_at)`)
each minute; alarm at lag > 30s (that is D-3's bound becoming visible), first
response is raising `ASYNC_RACE_RESOLUTION_CONCURRENCY` (the 1–2 cap in
`raceResolutionQueue.js:126` exists to protect the pool from *contended*
resolves; post-C0 resolves are contention-free and the cap can rise safely).

### Why this ends the observed deadlock class
A deadlock needs two transactions each holding part of the other's write set.
After C0+C3, every *bulk* write set on `race_participants` is wholly owned by
the single fenced worker for that race — the bulk-vs-bulk class (where every
observed 40P01 cycle lived) has no second writer to form a cycle with. The
residual small-writer-vs-worker class is closed by the shared ascending-userId
lock order plus 40P01-retry (design item 7) — precision matters here: the
guarantee is "single bulk owner + one global lock order," not magic. This also
fixes the today-racy last-writer-wins on `totalSteps`
(`withRaceResolutionLock` has been a deliberate no-op since 2026-07-18).

## 5. Backend plan (implementation path, in order)

### Phase A0 — baseline metrics (BEFORE any behavior change)
0. Acceptance criteria must be measured, not vibes. Pre-work:
   (a) add `$request_time`/`$upstream_response_time` to the nginx `log_format`
   and capture ≥48h of per-endpoint p50/p95 baseline (today's combined format
   records no timing at all);
   (b) snapshot `pg_stat_database` (deadlocks, xact counters) with
   `stats_reset` timestamp into the runbook;
   (c) ship the queue-lag log line (§5a) ahead of C0 so before/after lag is
   comparable.

### Phase A — infra (no behavior change)
1. Install redis-server (apt), bind 127.0.0.1, requirepass, maxmemory policy.
2. Add `ioredis` dependency. New module `src/shared/cache/redisCache.js`:
   `getJSON/setJSON/del/withLock/publishInvalidate/subscribe`, all wrapped so
   any Redis error → log once/minute + return null (callers fall through to PG).
   `REDIS_URL` unset (staging until enabled, tests by default) = wrapper inert.
3. Health: `/health` gains an internal `redis: ok|down|disabled` field (additive,
   old clients ignore it).

### Phase A2 — C0 race-keyed single-writer queue (§5a)
3a. Expand migration (new `race_resolution_jobs_v2` table — §5a item 1), model
    change, worker claim loop with lease-token fencing, debounce, enqueue-site
    conversions, `raceExpiry` claim step. Rollback levers, in order:
    (i) the reverse-handoff procedure of §5a item 1 — flip
    `raceQueueV2ClaimingDisabled`, drain/verify v2 leases, THEN redeploy the
    old binary (never redeploy first; the old table's intact schema makes the
    old binary *schema*-safe, not *concurrency*-safe); (ii) `inlineRaceResolutionFallback`
    app-setting restores inline `resolveRaceState` on the legacy paths if the
    new worker misbehaves while staying on the new binary (the worker kill
    switch alone would leave totals frozen). Contract migration ships ≥1 week
    later, separately. Ships before the cache surfaces because it is the
    incident fix and the Redis snapshot publisher (Phase D) hangs off the
    worker's fenced post-commit hook.

### Phase B — C1 catalogs/config + pub/sub (flag `redisCacheCatalogsEnabled`)
4. Read-through wrap the catalog/config query sites; admin mutation sites
   (`POST /admin/shop/items`, settings/balance writes, global-event creation)
   publish invalidation. Existing in-process TTL caches subscribe and bust.

### Phase C — C2 chat (flag `redisCacheMessagesEnabled`)
5. `getRaceMessages` (default `limit=50`, `kind` USER/SYSTEM only — any other
   query shape bypasses the cache) reads the cached **raw** array and hydrates
   sender cosmetics at read time via `v1:user:{id}:cosmetics` (cosmetics are
   never embedded in the list — an equip change propagates without touching
   message caches). On miss/stale, one PG query rebuilds under `withLock`,
   installed via the WATCH/MULTI/EXEC protocol (key table). `postRaceMessage`
   never writes the cache list: after its PG commit it runs the atomic Lua
   `SET msgver <durableMessageId>` + `DEL list`.

### Phase D — C3 standings (flag `redisStandingsEnabled`) — the incident fix
6. `getRaceProgress` split: **shared snapshot** (all-participant compute) vs
   **viewer overlay** (requester's `myPlacement`, box progress, `dropOdds` —
   computed per request from the snapshot + the requester's own cheap reads).
   The shared snapshot is built from a **pinned field allowlist** — fields are
   explicitly copied IN, never scrubbed OUT — so a future viewer-specific
   field added to the payload is absent from the cache by default rather than
   leaked to every viewer. A two-viewer isolation test (§8 item 5b) guards this.
7. On snapshot miss/expiry: acquire `v1:lock:progress:{raceId}`; the winner runs
   the existing read-only recompute (the same math `getHomeRaceCard` live mode
   uses — compute **without persisting**), stores the snapshot. **Losers NEVER
   fall through to the recompute path**: they serve the stale snapshot if one
   exists (possible because the key physically lives 60s past its 15s soft
   freshness — §3 key table); on a true cold start they wait ≤1s (event-loop wait on Redis only —
   zero PG connections held) and re-read; if still empty they serve the cheap
   persisted-columns read (one indexed query — the `getRaceDetails` shape).
   The expensive replay is only ever executed by the lock winner. This is the
   explicit anti-recurrence guard for the 2026-07-18 pool-drain incident: that
   incident pinned two *pooled PG connections* per waiter; here waiters hold
   none, and the lock self-expires (PX) so a crashed winner cannot wedge it.
   **Redis fully down (no lock possible): EVERY request serves the cheap
   persisted-columns read — the expensive replay never runs in the request
   path, with or without Redis.** The general "fall back to the existing
   Postgres path" rule in §2 explicitly does NOT mean the old recompute here;
   standings freshness during a Redis outage degrades to worker-convergence
   cadence (§5a), which is the correct trade.
8. **Remove the `updateTotalSteps` write-back and effect-expiry/high-multiplier
   side effects from `getRaceProgress`.** Those side effects move to the
   resolution worker and `expireEffects` cron where they already exist. Progress
   polls instead enqueue **the viewed race's job** (cheap upsert, race-keyed
   per §5a, only on snapshot expiry) so persisted totals keep converging while
   anyone is watching.
9. Invalidation hooks at the write seams (`usePowerup`, `openMysteryBox`,
   `forfeitRace`, `expireEffects`, join/leave/kick, `editRace`/`cancelRace`):
   DEL the race's snapshot. The resolution worker is **not** in this list —
   it replaces via SET post-commit (§5a item 5) and must never DEL what it
   just published.

### Phase E — C4 friends/inventory (flag `redisCacheUserBitsEnabled`)
10. Read-through caches per the key table; invalidation from the sync path and
    powerup grant/use/purchase sites.

### Phase E2 — C5 `/auth/me` (flag `redisCacheAuthMeEnabled`)
11. **First implementation task: a written invalidation inventory.** Enumerate
    every table/field the `/auth/me` response is assembled from (the frontend
    consumes more than coins+equips: feature flags, onboarding state,
    visibility settings, photo-prompt state, held coins, etc.). Classify each
    field by one rule: **any field the client re-reads immediately after
    mutating it MUST invalidate at its write site; everything else explicitly
    accepts ≤10s staleness.** Known-immediate today: coin balance (seam:
    `awardCoins`/`deductCoinsAtomic`), equip/unequip, profile edits, and every
    onboarding-progression command (the onboarding flow reads back its own
    writes step-to-step). Known-acceptable-at-10s: server feature flags,
    display counters. The inventory (with its classifications) goes into the
    implementation PR description and the C5 flag does not flip until it is
    reviewed. 10s TTL remains the backstop for anything misclassified. Parity
    test: purchase → immediate `/auth/me` new balance; onboarding step →
    immediate state readback.

### Phase F — nginx bot-drop rule (independent, anytime)
12. Requirement, not a vibe: `location` blocks matching `~* \.php$`,
    `^/wp-admin`, `^/wp-content`, `^/wp-includes`, `^/wordpress`,
    `^/xmlrpc.php` → `return 444` (connection drop, no response bytes), logged
    to a separate `access_bots.log` (so the main log stays clean but the
    volume stays observable). Safety precondition, verified by test: the
    Express API surface contains no `.php` or `/wp*` route (grep the route
    table), and a post-change smoke hits every route in §1's traffic table
    expecting unchanged status codes.

## 6. Frontend plan

**No frontend changes required in this release.** All polling intervals,
endpoints, and payload shapes are unchanged; iOS and Android are automatically
in lockstep because no client build ships. (Follow-up opportunity, out of scope:
chat could poll faster or standings could surface `asOf`, but nothing here
depends on it.)

Degradation: for C1/C2/C4/C5 a missing/stale cache is indistinguishable from
today's behavior (their fallback is the original query). **C3 is the deliberate
exception**: Redis-down standings serve the cheap persisted read, which is
*less* fresh than today's per-poll replay — accepted by design (Phase D step 7,
D-3).

## 7. Backward-compat & rollout

- Deploy order (owner decision 2026-08-07, "faster" track): infra (Phase A) →
  **C0 re-key (Phase A2) deploys and soaks on staging first, alone** — it is a
  structural change with a migration, so it must not share a soak window with
  the cache flags (attribution). Then:
  backend deploy with **all five flags OFF** → flip **all flags together on
  staging** (staging shares the droplet's Redis but uses `db1` + `s:` prefix —
  zero key overlap), soak ~24h with a full race lifecycle + purchase exercised,
  then flip prod in one pass. If a prod regression appears, flags come off
  one at a time (standings first) to attribute it.
- Frozen old clients: unaffected at every stage (no API change). The backend
  serving both old and new clients reads the same cache.
- Kill switches: each flag is an `app_settings` row (already cluster-coherent
  within 30s; immediately after Phase B, coherent via pub/sub). Master kill:
  unset `REDIS_URL` + `pm2 reload` (deploy via `pm2 reload`, never restart —
  see backend deploy notes).
- Settlement safety invariant (must hold at every stage): `raceExpiry` +
  `completeRace` read only Postgres, and the resolution worker remains the
  writer that keeps `race_participants` converging. C3 removes a *redundant*
  writer, it does not move settlement inputs into Redis.
- Risk note — divergence bounds between `/progress` (snapshot) and `GET
  /races`/home (persisted), reconciled per scenario (D-3):
  (a) watched race with sync activity: worker runs within debounce (5s) —
  divergence ≈ seconds; (b) watched race, no syncs: each snapshot expiry (15s)
  enqueues the race, worker persists within the same cycle — bound ≈ 15–30s
  (this is the "≤30s-ish" D-3 figure and the only scenario a user can
  actually observe both surfaces in); (c) unwatched race: no `/progress`
  reads exist, so no observable divergence — persisted totals converge on the
  5-minute `placementRecompute` enqueue backstop; (d) worker down (kill
  switch left on, or a worker-loop bug — the worker is in-process with the
  API, so a dead *process* takes both down together): the read-only snapshot
  rebuild keeps `/progress` fresh while persisted `GET /races`/home totals
  stop advancing — divergence grows **unbounded** until the worker recovers.
  The 30s lease only reassigns jobs between *live* workers; it does not
  resurrect a down one. Detection: the 30s queue-lag alarm; runbook's first
  check for "races list disagrees with race detail" is worker/kill-switch
  state.

## 8. Test plan (tests first, integration over unit)

Integration tests run against a **local test Redis** (`REDIS_URL` → localhost
test instance, `db15`, flushed in setup) and the existing **test Postgres** —
never prod anything. Redis-less CI: suite must also pass with `REDIS_URL` unset.

Written before implementation, per phase:
1. **Fallback**: with flag on and Redis stopped, every cached endpoint returns
   200 (kill the test Redis mid-suite). Payload assertion is per-surface:
   deep-equal to flag-off for C1/C2/C4/C5 (their fallback IS the old query) —
   but **C3 standings asserts contract shape + status + zero replay-path
   invocations instead**, because its Redis-down behavior is deliberately the
   cheap persisted read, which need not deep-equal the old replay (that
   degradation is the design, per Phase D step 7).
2. **Parity**: for each surface, cold-cache response ≡ flag-off response
   (deep-equal on JSON) for: a race with effects + teams + finished + forfeited
   participants; messages of both kinds; catalogs.
3. **Invalidation**: post message → next read includes it; use powerup →
   progress snapshot reflects the effect on next read; equip cosmetic → chat
   sender payload updates; admin shop write → catalog updates across two
   concurrently-running server processes (pub/sub coherence test).
4. **C3 write-removal**: hit `/progress` N times concurrently → assert **zero**
   `race_participants` UPDATEs originate from the endpoint (pg_stat / query log
   assertion), totals still converge via the enqueued resolution job, and
   `raceExpiry`→`completeRace` settles identically to a flag-off control race
   (same placements, same payouts).
5. **Stampede**: 20 concurrent cold `/progress` requests → exactly one
   recompute (lock assertion), and **every request receives either the
   snapshot or the valid persisted-columns fallback** — NOT "all 20 get the
   snapshot": the loser wait is ≤1s while recompute p99 is 1.76s, so some
   losers legitimately serve the fallback. Assert zero additional
   replay-path invocations from the losers.
5h. **Reverse handoff (rollback drill)**: with a v2 worker mid-run, flip
    `raceQueueV2ClaimingDisabled` → v2 claims stop within one tick, in-flight
    fenced run completes or aborts, v2 table reaches zero unexpired RUNNING
    leases within 30s — only then may old-binary workers start (simulated) and
    bulk-write without overlap.
5b. **Two-viewer isolation**: viewers A and B hit `/progress` on one race
    back-to-back (warm cache) → B's response contains B's `myPlacement`/box/
    `dropOdds`, never A's (allowlist regression guard).
5c. **Cache-mutation failure**: with a Redis proxy dropping the DEL, post a
    chat message → subsequent reads serve the PG path (bypass open) and
    include the message; bypass closes only after the retried DEL succeeds.
5g. **Concurrent post vs cold rebuild**: start a cold-cache rebuild (WATCH
    armed), commit a new message + its atomic `SET msgver`+DEL mid-rebuild →
    the rebuild's EXEC must abort (WATCH invalidation), and the next read
    includes the new message. Second case: evict `msgver` mid-rebuild
    (simulated DEL by the test) with the value ending back at nil → EXEC must
    STILL abort — this is exactly the nil→set→evicted ABA a value-compare CAS
    would wrongly pass.
5d. **Debounce**: continuous generation bumps on one race → resolves at most
    once per `RACE_RESOLVE_DEBOUNCE_MS`, and `triggeredByUserIds` from bumps
    during a run are all processed by the follow-up run.
5e. **Redis fully down + standings flag on**: `/progress` serves the persisted
    cheap read for every request; assert zero replay-path invocations
    (instrumented counter), pool usage flat.
5f. **Expand/overlap**: with both job tables present and both binaries'
    worker code running (the pm2 reload window, simulated), the v2 worker
    performs **no bulk claim** until the old table shows zero
    RUNNING-with-unexpired-lease rows and the quiet period has elapsed —
    coexistence is asserted, concurrent bulk-writing is asserted NOT to occur.
5a. **C0 single-writer**: two users in the same two races sync concurrently →
    exactly one worker resolves each race (claim assertion), totals match a
    serial control run, and zero deadlocks under a 50-iteration concurrent-sync
    loop (the deadlock repro that fails against the per-user-keyed baseline).
    Legacy `/steps` response shape unchanged with inline resolution removed;
    generation coalescing verified (N rapid syncs → ≤2 worker runs, final
    totals correct); `raceExpiry` vs live-worker mutual exclusion under
    concurrent expiry+sync.
6. **C5 coin freshness**: shop purchase (coins debited) → immediate `/auth/me`
   returns the new balance (invalidation, not TTL, must be what makes it pass:
   assert within 1s of the purchase).
7. **Existing tests are never modified or deleted**; surface any that look wrong.

## 9. Acceptance criteria / definition of done

- [ ] All phase flags OFF ⇒ behavior and test suite identical to pre-change
      (exception: C0 is structural — its acceptance is the parity + deadlock
      tests in 5a plus a flat `pg_stat_database.deadlocks` counter over a 48h
      prod window with active races).
- [ ] Redis down ⇒ all endpoints serve from PG (verified by test 1 and a manual
      staging `systemctl stop redis` drill).
- [ ] With C3 on in staging: zero `UPDATE race_participants` from
      `getRaceProgress`; deadlock count in `pg_stat_database` stays flat over a
      24h soak with active races.
- [ ] Prod after full rollout: `/races/:id/messages` and `/races/:id/progress`
      p95 latency reduced (nginx timing or app metric before/after), no new
      error classes in pm2 logs over 48h.
- [ ] Settlement parity verified on staging: one full race lifecycle (create →
      sync → powerups → expiry → payouts) with all flags on matches a control.
- [ ] Both iOS and Android builds unaffected (no client change shipped).
- [ ] Runbook section added to backend docs: install, kill switches, flush
      procedure, memory alarm at 75 MB, queue-lag alarm at 30s, baseline
      metrics snapshot (Phase A0) recorded before and after each flip.
- [ ] C5 seam verification stays true at merge time: `awardCoins` and
      `deductCoinsAtomic` remain the only direct `users.coins` mutation sites
      (guard: a structural grep test over `src/` asserting no other
      `coins: { increment | decrement }` or raw-SQL coin write exists).

## 10. Open questions

None — all four resolved by owner interview 2026-08-07:
- Q1 Redis host → **local on droplet**.
- Q2 Standings snapshot TTL → **15s**.
- Q3 `/auth/me` → **include now** (C5, 10s TTL + ledger-seam invalidation).
- Q4 Rollout → **faster track** (all flags soak together on staging ~24h, then
  prod in one pass; per-flag rollback order documented).

## 11. Revision log

- **Draft v1** — initial spec from prod traffic analysis (8 days nginx,
  pg_stat_user_tables) + full codebase exploration report.
- **Gap pass 1**:
  - Split `/progress` into shared snapshot + per-viewer overlay after realizing
    the payload contains requester-specific fields (`myPlacement`, box progress,
    `dropOdds`) — a naive whole-response cache would leak viewer A's fields to B.
  - `getRaceProgress` side effects (effect expiry, high-multiplier alert claim,
    powerup state sync) can't just be deleted with the write-back — reassigned
    to the resolution worker / crons where equivalents already run (Phase D
    step 8), and progress polls now enqueue the resolution job so totals keep
    converging for watched races.
  - Added the `GET /races` vs `/progress` divergence risk after C3 (D-3 accept).
  - Chat cache constrained to the default query shape (`limit=50`, kind
    USER/SYSTEM); other shapes bypass — avoids caching unbounded variants.
  - Added stampede lock + test 5 (30s poll × many viewers of one race is the
    exact cold-miss thundering herd).
- **Gap pass 2**:
  - Staging shares the droplet's Redis: pinned db-index + key-prefix isolation
    and made the staging soak plan explicit (prior draft implied a separate
    instance that doesn't exist).
  - Test suite must pass with `REDIS_URL` unset (CI has no Redis today) — added
    to test plan preamble; wrapper defined as inert when unset.
  - Eviction: switched an early `volatile-lru` choice to `allkeys-lru` and
    documented *why* it's safe (all keys rebuildable; no queues/locks that
    matter live in Redis — the stampede lock self-expires and eviction of it
    only costs a duplicate recompute).
  - Kill-switch note corrected to `pm2 reload` (never `restart`) to match the
    documented deploy footgun.
  - Cut `/auth/me` from scope into an explicit non-goal with rationale (was
    ambiguously "maybe" in v1; coins staleness is a real bug class).
    *(Historical note: superseded by the owner interview the same day — C5
    brought it back in scope. Kept here because the revision log is a log.)*
  - Added nginx bot-drop as Phase F after the traffic analysis showed ~3k/day
    exploit probes.

## Decision log (proposed, pending owner)

- D-1: Redis is a **cache, never a source of truth** — every key rebuildable
  from Postgres; settlement/coins never read it.
- D-2: The Postgres-backed resolution queue stays; Redis does not become a queue.
- D-3 (v6 precision): Accept bounded divergence between persisted-column
  surfaces and the snapshot surface per §7's scenario table: ≈seconds when
  syncing, ≤15–30s watched-idle (the only observable case), 5-min backstop for
  unobserved races — and, per §7(d), **unbounded** divergence while the worker
  is down (alarmed at 30s queue lag; accepted because the alternative is
  request-path bulk writes, i.e. the incident).
- D-4 (superseded by owner 2026-08-07): `/auth/me` caching is IN scope as C5
  with 10s TTL; the coin-ledger write seam is the invalidation chokepoint.

- **Owner interview 2026-08-07**: Q1 local droplet Redis; Q2 15s TTL; Q3
  `/auth/me` included (C5 added, non-goal removed, test plan gains the
  purchase-parity case); Q4 faster rollout (combined staging soak, one-pass
  prod flip, per-flag rollback order).
- **Owner addition 2026-08-07 (v2)**: folded in C0 — re-key the resolution
  queue per **race** and make its worker the sole bulk writer of that race's
  `race_participants` rows (§5a, Phase A2, test 5a). This supersedes "remove
  the `getRaceProgress` write-back" as the primary deadlock fix: C3 removes one
  redundant bulk writer; C0 removes the *category* (per-user-keyed jobs and
  inline sync-path resolution could still bulk-write one race from two workers
  at once). Amended the no-schema-change non-goal accordingly; legacy `/steps`
  paths switch from inline resolution to enqueue with response shapes frozen.
- D-5: Accepted residual small-transaction writers (join/leave/forfeit/powerup
  targets) outside the single-writer path; invariant enforced is "no concurrent
  multi-row bulk writers." Each such action enqueues its race afterward.
- **Owner review round 2026-08-07 (v3)** — five challenges answered with prod
  measurements; spec amended: (1) worker-capacity section added to §5a
  (measured p50 525ms/race ⇒ ~28–57 watched races at 15s cadence, queue-lag
  alarm + concurrency-raise playbook); (2) stampede-loser path pinned to
  "never recompute, hold zero PG connections" with explicit 07-18
  anti-recurrence rationale; (3) Redis cap cut 200→100MB, alarm 150→75MB,
  after confirming the app DB is DO-managed (droplet RAM: ~825MB available);
  (4) C5 coin seam verified by grep — `awardCoins`/`deductCoinsAtomic` are the
  only `users.coins` mutation sites (37 callers route through them), and a
  structural guard test now pins that; (5) Phase A0 added — nginx has no
  request timing today, so per-endpoint p50/p95 + deadlock-counter baselines
  are captured before any change ships.
- **External design review 2026-08-07 (v4)** — 11 findings + 10 document
  contradictions, all addressed:
  1. Queue migration re-specified as **expand/migrate/contract** with a new
     `race_resolution_jobs_v2` table — pm2-reload overlap safe (old workers
     keep the old table), old-binary rollback trivially safe, ≤5-min one-time
     convergence gap at cutover, contract deploy ≥1 week later.
  2. `triggeredByUserId` → `triggeredByUserIds` JSONB append-distinct; claim
     snapshots-and-clears; worker processes box/nudges for EVERY triggering
     user (coalescing no longer loses work).
  3. Work cap made explicit: `notBeforeAt` debounce (5s default) — generation
     bumps mark dirty but cannot cause continuous re-runs; capacity section
     redone against the debounce floor.
  4. Redis-down standings pinned: cheap persisted read for ALL requests; the
     replay never runs in the request path under any Redis state.
  5. Deadlock claim de-overstated: bulk-vs-bulk eliminated by ownership;
     residual-vs-bulk closed by a global ascending-userId lock order + 40P01
     retry (design item 7).
  6. Expiry/worker exclusion given real fencing: participant writes + a
     conditional lease-token job-row update commit in ONE transaction; 0-row
     match ⇒ full rollback (covers lease expiry mid-slow-run).
  7. Snapshot lifecycle contradiction fixed: worker SETs (replaces)
     post-commit and is removed from the DEL list.
  8. Cache-mutation failure rules added: DEL-first ordering, per-prefix 60s
     read-bypass breaker on failed DEL, pub/sub reconnect flush.
  9. Progress snapshot built from a pinned field allowlist + two-viewer
     isolation test (5b).
  10. C5 requires a written per-field invalidation inventory with the
      "re-read-after-write ⇒ must invalidate" rule before the flag flips.
  11. Contradictions fixed: per-user wording (§2), zero-changes claim (§4),
      100MB everywhere, placementRecompute described as enqueue-only, /health
      additive exception named, "byte-shape" → JSON-contract compatible,
      viewer→race enqueue wording, auth/me revision-log annotation, pub/sub
      env-namespaced channels, D-3 four-scenario reconciliation, nginx rule
      fully specified (patterns, 444, separate log, route-safety test).
- **Implementation corrections 2026-08-07 (v8, from the C1/C2 build)**:
  (1) Chat messages have never carried cosmetics — the payload is
  senderId/Name/PhotoUrl only, so the per-user presentation key
  (`v1:user:cosmetics:{id}`) holds the sender's whole presentation bundle
  (name/photo) and the "equip → chat updates" test is realized as
  "rename → chat updates" with the cached raw list proven byte-unchanged;
  adding cosmetics to chat would be an API change and stays out of scope.
  (2) Message IDs are random UUIDv4, not monotonic — msgver holds the
  sortable pair `zeroPadded(createdAt epoch ms):uuid` (matches the feed
  cursor's existing tie-break).
  (3) Global step events are cached ONLY for the home banner via a dedicated
  `findActiveAtCached` (caching the row set, not the answer-for-now);
  the shared model stays uncached because `raceExpiry`/`raceStateResolution`
  call it on the settlement path, which must never read Redis.
  (4) `/shop/catalog` caches only the global `shop_items` read, keyed by
  channel+capability variants so testOnly items can't leak across build
  channels (two-user isolation test added); coins/ownership stay per-request.
- **Implementation corrections 2026-08-07 (v9, from the C3 build)**:
  (1) The spec's claim that the endpoint's side effects "already have
  equivalents in the worker/crons" was 1/3 true: `syncRacePowerupState` yes,
  but **`expireEffects` had NO cron — `getRaceProgress` was its only call
  site** (Piggy Bank minting, Drill Sergeant judging, Fanny Pack revert, and
  `stepsAtExpiry` stamping all rode on the poll), and the high-multiplier
  event-crossing re-arm was endpoint-only. Both are now wired into the v2
  worker's post-commit hook.
  (2) Box-toast decision RESOLVED (owner, 2026-08-07): preserve via a
  per-user recent-mints key — the worker records each mint
  (`v1:user:{id}:recentmints`, short TTL, consumed-on-read), and the
  `/progress` viewer overlay folds unconsumed mints into the existing
  `newMysteryBoxes`/`newQueuedBoxes` fields. Toast survives with ≤2–15s
  delay, no API change, frozen clients keep working. Consumed-on-read must
  be per-viewer-request atomic (GETDEL) so one poll can't re-toast.
- **Implementation corrections 2026-08-07 (v10, from the C4/C5 build)**:
  (1) The C5 invalidation inventory is written (module header of
  `authMeCache.js` + build report): 8 immediate-invalidation fields hooked at
  their write sites (users-model chokepoint + coin seams + friendship model +
  equip + delete), 14 fields accepting ≤10s, grounded in an audit of all 7
  frontend `fetchMe` call sites. Honest residual: `deductCoinsAtomic` inside a
  caller-supplied tx DELs pre-commit — the four tx-passing purchase commands
  re-invalidate post-commit, TTL covers the rest.
  (2) `/auth/me` cache is variant-keyed on ONE axis: the
  `stepSampleBucketMinutes` fine-bucket app-version floor — a warm modern
  payload served to a 1.7.0 binary would reopen the 2026-07-23 step-inflation
  incident. Both variants deleted on invalidate.
  (3) Inventory caches the unfiltered row set with per-request capability
  filtering, so warm payloads can't leak unrenderable powerups to old binaries.
  (4) Latent product bug found & fixed: `upsertBuffWindow` re-read `now()`
  after an awaited round trip, so `startsAt`/`expiresAt` drifted 1ms apart
  (UPRISING/RALLY_FLAG); clock anchor now threaded through.
  (3) Null-timezone user races score in the requester's tz — the snapshot
  embeds its tz and a mismatch is a cache miss (lock-winner-or-fallback), so
  correctness and the ≤1-replay bound hold but multi-tz viewers of one
  user race lose cache hits; persisting a creator tz would remove the case.
  (4) The worker's snapshot publish re-runs the shared compute (one builder,
  two callers) — roughly doubles per-race worker time, off the request path;
  watch the queue-lag alarm.
- **External review round 2 2026-08-07 (v5)** — 7 correctness findings + 5
  clarifications, all addressed:
  1. Expand-phase worker handoff added: 60s v2-worker startup quiet period +
     old-table RUNNING-lease check before first claim, so old and v2 bulk
     writers never run concurrently during `pm2 reload`.
  2. Fence reordered to fence-THEN-write: the write transaction acquires the
     job row `FOR UPDATE … AND leaseToken = ?` before touching any
     participant row; loser aborts having written nothing. Same protocol
     restated for `raceExpiry`.
  3. Snapshot TTL split soft/physical (15s freshness via embedded `asOf`,
     60s key lifetime) — a physical 15s TTL would delete the value the
     "serve stale" path depends on.
  4. Breaker redesign: bypass stays open until DEL succeeds (not fixed 60s),
     broadcast to peers via pub/sub (best-effort, single-instance today),
     background retry loop; chat TTL cut 24h→15min as the hard backstop;
     mutating requests now never write caches (invalidate-only), killing the
     DEL+RPUSH one-message-list bug.
  5. Removed "resolution worker post-write" from Phase D's DEL hook list
     (SET-only, per key table).
  6. Worker-down scenario (d) corrected: `/progress` stays fresh via
     read-only rebuilds while persisted surfaces stall — divergence unbounded
     until recovery; lease reassigns only between live workers; added the
     in-process-worker observation and runbook check.
  7. Fallback test 1 made per-surface: deep-equal where fallback is the old
     query; contract-shape + zero-replay for C3 (its degradation is by design).
  Clarifications: `processingTriggeredByUserIds` column added with
  crash/retry union semantics; concurrent post-vs-rebuild test 5g +
  `msgver` compare-and-set guard; chat caches raw messages with read-time
  cosmetics hydration (equip changes never touch lists); summary's
  "structurally impossible" narrowed to the two-class guarantee; "top-20
  routes" → the actual §1 table.
- **External review round 3 2026-08-07 (v6)** — approval granted for Phase
  A0/A; two material fixes required before C0/C2, both applied:
  1. Reverse handoff specified: `raceQueueV2ClaimingDisabled` app-setting
     (checked per tick, uncached, exists specifically because env can't
     change on a running process) → wait ≥30s lease + verify zero unexpired
     RUNNING v2 rows → only then start the old binary. Reverse-handoff drill
     added as test 5h.
  2. Chat versioning made atomic and eviction-safe: `msgver` now holds the
     durable monotonic PG message ID (never an INCR counter — LRU reset of a
     counter is ABA-prone); post = one Lua `SET msgver` + `DEL list`;
     rebuild = Lua CAS on msgver (eviction ⇒ nil ⇒ CAS fails ⇒ retry, never
     a stale install).
  Small corrections: `processingTriggeredByUserIds` added to the v2 column
  list; test 5 re-stated (one recompute; every request gets snapshot OR valid
  persisted fallback — losers' 1s wait < recompute p99 1.76s); D-3 aligned
  with §7(d)'s unbounded-divergence wording; §5a item 5 heading now "worker
  and expiry share the serialized ownership protocol"; "Dart" → "Express";
  chat's 15-min worst-case staleness explicitly accepted in the §3 freshness
  table (was implied "effectively live" unconditionally).
- **External review round 4 2026-08-07 (v7) — final; approval granted after**:
  1. Material: msgver rebuild guard upgraded from Lua value-comparison CAS to
     **WATCH/MULTI/EXEC** — value-compare fails the nil→set→evicted-to-nil
     ABA (compare-against-nil would wrongly succeed); WATCH invalidates EXEC
     on any modification or eviction even if the value returns to nil.
     Dedicated-connection requirement noted; test 5g gained the eviction-ABA
     case.
  2. Stale wording purged: Phase C + failure-rules INCR references → atomic
     `SET msgver <durableId>` + DEL; Phase A2 rollback lever (i) now points
     at the reverse-drain procedure (never redeploy-first); test 5f asserts
     no v2 bulk claim until old-worker drain (not "run simultaneously");
     scope item 6 says worker + expiry under the shared ownership protocol;
     §6 degradation statement carves out C3's deliberate freshness downgrade.
