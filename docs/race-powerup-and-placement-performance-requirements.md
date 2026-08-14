# Race Powerup and Placement Performance — Requirements & Implementation Spec

**Repos:** `stepv2-backend` (implementation) and `stepv2-frontend` (compatibility
verification only).
**Date:** 2026-08-13
**Status:** Implementation-ready; architect and game-economy reviews returned
READY. No implementation is authorized without explicit owner approval.
**Release model:** tests first, backend-only additive/internal changes, staging
verification, then a separate in-the-moment confirmation before production.

---

## 1. Summary and user story

Powerup actions become slow when the server is busy, and the five-minute
placement job still creates a large burst of database and push work. Production
observations show both effects reinforcing each other: powerup requests that are
normally sub-second stretch to several seconds when the placement tick drives
CPU toward saturation.

> As a racer, I want opening a mystery box, choosing or casting a powerup, and
> planting a Trail Mine to respond promptly even in a large race, without any
> change to rolls, defenses, scoring, placements, notifications, or animations.

This project removes redundant hydration and N+1 queries from the interactive
powerup paths, removes work that is provably inert on every shipped client, and
bounds the placement job's database and push amplification. It is a performance
project only. The same inputs must produce the same response, roll, effect,
score, event, and user-visible notification as before.

## 2. Current behavior and evidence

### 2.1 Production correlation

The production sample gathered after revision `1ffd0c7` showed:

- powerup requests nearest CPU samples at or above 75%: `n=20`, average `2.062s`,
  13 at or above one second and 10 at or above two seconds;
- powerup requests nearest CPU samples below 25%: `n=4`, average `0.685s`, none
  at or above two seconds;
- examples included Leg Cramp at `5.008s` near 96% CPU, Trail Mine at `3.489s`
  near 89%, and mystery-box opens at `5.821s` and `4.372s` near 89%; and
- a low-CPU mystery-box open completed in `0.117s`.

Nginx request time matched upstream time, so the delay was in application/backend
work rather than client transfer or proxy buffering. This is a correlation, not
proof that CPU alone causes every slow call; the static query amplification below
provides the actionable mechanism.

### 2.2 Mystery-box opening

`openMysteryBox` currently performs all of the following on the request path:

1. loads the powerup;
2. calls general-purpose `Race.findById`, hydrating every participant plus each
   participant's profile, equipped accessories, shop items, and render metadata;
3. loads the caller's participant row again;
4. counts occupied inventory slots;
5. loads all accepted participants again to calculate raw-step odds position;
6. loads the balance snapshot and Lucky Horseshoe state;
7. persists the roll and audit event; and
8. calls `syncRacePowerupState`, which can load the full race again and performs
   occupied, queued, and promotion queries.

The normal `MYSTERY_BOX -> HELD` transition does not change occupied-slot count,
does not add steps, and therefore cannot mint or promote a box. Its unconditional
inventory synchronization is a generic post-action hook doing no useful work.
The full-inventory Fanny Pack auto-activation branch can change capacity and must
retain synchronization, even though Fanny Pack is absent from the current drop
pool. `openMysteryBoxBatch` serially invokes the single-open command up to 20
times, multiplying immutable context reads.

### 2.3 Sneaky Swap target selection

`GET /races/:raceId/powerups/sneaky-swap-targets` hydrates the full race and then
runs two queries per candidate: one active-Stealth lookup and one held-inventory
lookup. A 269-person race can therefore launch more than 500 queries from one
tap. The model layer already has bulk effect and inventory reads that can reduce
the candidate portion to two queries total.

### 2.4 Leg Cramp and the shared cast path

Leg Cramp correctly performs multiple rule checks: Signal Jammer/outage, target
Stealth, conflicting/stacking effects, Mirror, Decoy, and Compression Socks.
Those checks and their ordering are gameplay behavior and stay intact. However,
independent reads are often awaited serially, the command invokes inventory
synchronization after a cast even when the transition cannot create an open
slot or mint a box, and the shared tail reloads the caster plus all caster effects
to evaluate a high-multiplier alert for attacks that cannot change the caster's
multiplier.

### 2.5 Trail Mine

Trail Mine needs fresh canonical totals for every participant: the mine must be
planted at the caster's exact current total and the last-place restriction must
use the same field-wide ranking. `computeRaceState` is the required read-only
canonical scoring path. Today that computation hydrates a general race graph,
and `usePowerup` then loads the race again. The computation is necessary; the
cosmetics and duplicate race hydration are not.

### 2.6 Five-minute placement job after revision `1ffd0c7`

The previous release successfully stopped enqueueing every active race every
five minutes. It now enqueues races with due effects plus at most two stale or
failed resolution jobs. Due time-driven effects retain the historical roughly
five-minute processing bound, and resolution concurrency remains two.

The remaining tick still:

- performs sequential `lastNotifiedPlacement` writes per changed participant;
- emits `PLACEMENT_CHANGED` before persisting the new baseline;
- starts an async notification handler whose Promise is not observed by the
  in-process event bus;
- loads device tokens and sends a silent `PLACEMENT_CHANGED` push for every
  non-meaningful movement; and
- requests fresh steps through sequential per-user reads, per-user token reads,
  sequential per-token sends, and per-user updates.

Post-release ticks with only 36 active races and roughly 760 participants still
took 13–70 seconds and emitted 122–447 placement changes. The logged duration
does not include the full fire-and-forget notification handler tail.

The current iOS native handler and Android background/foreground handlers act on
the exact type `STEP_SYNC_REQUEST`; a data-only/silent `PLACEMENT_CHANGED` does
not refresh a race or update UI. The same commit that introduced placement
notifications already had this exact-type behavior. Visible took-first,
lost-first, and payout-drop notifications do work and remain required.

## 3. Goals and measurable success criteria

### 3.1 Functional goals

- Preserve every existing HTTP request, response, and error shape.
- Preserve mystery-box odds, random-call count/order, Lucky Horseshoe behavior,
  canonical rarity, stored config version, idempotent replay, events, and batch
  ordering.
- Preserve every powerup legality check and defense priority, including Mirror
  before Decoy before Compression Socks.
- Preserve Trail Mine's canonical all-participant scoring, exact plant total,
  last-place gate, and trailing resolution enqueue.
- Preserve all visible placement notifications, cooldowns, audit/claim behavior,
  mute semantics, baseline seeding/resync, and step-sync wakeups.
- Preserve due-effect recovery and the resolution worker concurrency of two.
- Keep both iOS and Android behavior unchanged; no Flutter or native app release
  is required.

### 3.2 Performance gates

All automated fixtures use a dedicated local/disposable test database. Staging
measurements use synthetic or ordinary staging data, never production-mutating
tests.

- Single mystery-box open performs one lean race/participant context query and
  does not call the general cosmetic-hydrating `Race.findById` path. The ordinary
  pre-RNG occupied count remains the authoritative Fanny snapshot; the narrow
  post-open repair also counts occupancy only after passing the exact current
  active/powerups-enabled/interval/accepted-participant gates.
- A normal `MYSTERY_BOX -> HELD` open avoids full
  `syncRacePowerupState`/race hydration but still runs a narrow repair for the
  current max-bonus and pre-existing free-slot/queued-box invariants. The Fanny
  Pack capacity-changing branch observes its current slot count and runs the same
  narrow repair after mutation.
- Opening 20 boxes in one batch re-reads a lean `joinedAt`-ordered standings and
  slot snapshot per roll, matching current live odds semantics, but never loads
  cosmetics or duplicate participant graphs and never runs full inventory
  synchronization.
- Sneaky Swap target lookup performs a bounded number of SQL statements
  independent of candidate count. Expanding a fixture from 10 to 300 candidates
  may increase returned rows, but must not add per-candidate SQL statements.
- A non-reflected Leg Cramp cast preserves the current high-multiplier evaluator
  call (including re-arm behavior) but avoids redundant participant/effect
  reloads when the already-loaded state is sufficient; inventory promotion uses
  the narrow repair path.
- Trail Mine runs the existing canonical scoring pipeline, but hydrates no
  accessory/shop graph and reuses `computeRaceState().result.race` instead of
  loading the race a second time.
- Exactly one PM2 process wins each five-minute placement bucket through an
  atomic database claim. Placement baselines remain individual (to preserve the
  fenced resolution worker's sole-bulk-writer invariant), but use scalar-only
  compare-and-set writes with bounded concurrency instead of relation-hydrating
  generic updates. Only won rows may emit a placement event.
- Non-visible placement changes perform zero device-token reads and zero push
  sends while the silent-placement compatibility switch is disabled.
- Step-sync scheduling performs bounded bulk user/token reads and bounded send
  concurrency. Database query count is constant with respect to recipient count,
  excluding bounded batch chunks if Postgres parameter limits require them.
- APNs reuses a healthy HTTP/2 session per host/process, has explicit connect and
  request timeouts, and retires/recreates broken sessions without hanging a job.
- On staging fixtures of 300 participants, compare at least 30 warmed requests
  before and after on the same machine/database. Each optimized endpoint must
  reduce median server duration by at least 50%, with absolute targets of median
  <= 500ms and p95 <= 1.5s for mystery-box open and Sneaky targets, and median
  <= 1s and p95 <= 2.5s for Trail Mine. If staging cannot meet an absolute gate,
  retain the relative gate and attach query counts plus `EXPLAIN ANALYZE` evidence
  before changing this document.
- A 750-participant placement fixture must reduce non-baseline database
  statements and APNs connection establishments by at least 90% in the
  no-visible-alert case; baseline statement count remains proportional to actual
  changes until it can be moved into the fenced race-keyed writer.

## 4. Scope and non-goals

### In scope

- Lean race projections dedicated to mystery-box context and canonical race
  resolution.
- Lean per-roll mystery-box context that preserves live batch standings.
- Replacement of full normal-open inventory synchronization with its exact lean
  drift-repair subset.
- Bulk Sneaky Swap target effect/inventory reads.
- Safe parallelization or bulk prefetch of independent use-time validations.
- Runtime-gated narrow inventory repair and reuse of already-loaded multiplier
  inputs while preserving the exact existing evaluator call sites.
- Reuse of the canonical computed Trail Mine race result.
- Cross-process five-minute tick claiming and scalar-only compare-and-set
  placement baseline writes with bounded concurrency.
- Suppression of inert silent `PLACEMENT_CHANGED` pushes before token lookup,
  behind a reversible server flag.
- Bulk, bounded step-sync push scheduling and dead-token/bookkeeping writes.
- Reusable, timeout-protected APNs HTTP/2 sessions.
- Additive structured timing/counter logs and staging benchmarks.

### Non-goals

- No scoring, multiplier, effect duration, defense, odds, drop-pool, rarity,
  random-number, inventory-capacity, placement, payout, cooldown, or notification
  copy/routing changes.
- No Redis-derived Trail Mine shortcut. Persisted snapshots may be stale and are
  not sufficient for its exact plant/rank guarantees.
- No best-effort or deferred acknowledgement for a powerup action; the existing
  success/error response still waits for the same required durable mutations.
- No frontend animation timing change. The existing case-opening reel continues
  to start after the API response and retain its four-second spin plus reveal.
- No new client endpoint, field, capability token, or app build.
- No change to race-resolution worker concurrency (remains two), five-minute
  cadence, due-effect selection, or two-race stale-recovery cap.
- No global change to event-bus Promise semantics. The placement path is made
  safe at its own persistence boundary; a broader durable event/outbox project
  is separate.
- No new multi-row writer of `race_participants` outside the fenced race-keyed
  resolution worker. Placement keeps per-row baseline writes in this release.
- No database-pool-size change. Connection count is not the identified source of
  latency, and higher concurrency could worsen CPU/DB contention.

## 5. Locked implementation decisions

| ID | Decision |
|---|---|
| D1 | API contracts stay byte-for-byte compatible at the JSON-field level. Internal function options must never leak into responses. |
| D2 | Each lean projection explicitly selects every consumed scalar. It must not reuse `participantInclude` or hydrate creator/winner/tournament/accessory relations unless the command consumes them. |
| D3 | Mystery-box odds continue to use `rawPositionFor` over persisted accepted rows with its all-or-nothing raw-step fallback. No live scoring or cached leaderboard substitutes it. |
| D4 | Normal open skips full `syncRacePowerupState`, but not its latent repair semantics. The lean helper first applies the exact current gates: race ACTIVE, powerups enabled, positive interval, and caller participant ACCEPTED. Only then may it repair `maxBonusSteps`, count occupied slots, promote oldest queued boxes into already-free slots, and return queued count. Otherwise it returns the current disabled/enabled no-op shape without repair. Fanny Pack uses the same helper after capacity mutation. |
| D5 | Batch opening creates context lazily but does not cache participant standings, participant order, race status, or slot state across rolls. Each roll re-reads a lean snapshot ordered by `joinedAt`, exactly as the current single-open re-entry does. Caller membership may be any existing participant status. Balance and Lucky Horseshoe also remain per roll. Rolls remain sequential to preserve live odds, eligibility, RNG, and state ordering. |
| D6 | Sneaky target selection uses one active-Stealth query and one HELD-inventory query across all candidate IDs, then applies the existing filters in memory in original participant order. |
| D7 | Validation reads may run concurrently only when neither read depends on the other's result and both would have run before any mutation. Error precedence visible to clients must remain pinned by deterministic evaluation after the reads settle. |
| D8 | The post-cast path carries explicit internal facts such as `inventoryCapacityChanged` and `casterEffectStateChanged` to decide whether cached inputs remain exact—not whether an existing evaluator call site executes. It must not infer solely from a broad powerup-type allowlist. Mirror/reflection can make the original caster a target, and Cleanse/self-buffs can change caster effect state. |
| D9 | High-multiplier evaluation runs on exactly the successful control-flow branches that invoke it today—no new early-return branch gains an alert and no shared-tail direct attack loses its re-arm check. Performance comes from reusing already-loaded participant/effect state or updating it in memory; when exact current state cannot be proven, retain the refresh. Evaluation remains best-effort and uses the same helper. |
| D10 | Trail Mine calls canonical `computeRaceState` once and, when it returns a result, uses `result.race` plus `totalsByParticipantId` for every subsequent gate. If it returns null, it falls back to the lean powerup-use context and current stored totals. This preserves current ACTIVE-with-null-`startedAt` behavior (there is no not-started rejection), plus existing inactive and elapsed-`endsAt` validation; it never falls back to general `findById`. |
| D11 | Every PM2 worker may schedule placement, so the job must first atomically claim `placement-recompute-v2:<UTC five-minute bucket>` through `JobRun.claimRun`. A loser returns before any race/effect/user/token read. The process-local `running` guard remains defense in depth. No advisory lock is used. |
| D12 | Placement baseline writes remain per participant to honor the race-keyed worker's sole-bulk-writer invariant. A dedicated scalar-only CAS method updates only when the stored baseline equals the tick snapshot and returns whether it won. A bounded pool (default 4, clamp 1–8) replaces sequential relation-hydrating updates; events emit only after won writes. Team lead events additionally require an atomic race/transition claim so split CAS results cannot duplicate one logical flip. |
| D13 | Seeding, resync, and muted rows use the same scalar CAS method but never emit. An unmuted non-null won change emits the same payload as today. A lost CAS emits nothing because another actor owns the newer baseline. |
| D14 | All behavior-changing cron/transport paths ship dark behind positive default-false environment switches: `PLACEMENT_DISTRIBUTED_CLAIM_ENABLED`, `PLACEMENT_INERT_PUSH_SUPPRESSION_ENABLED`, `PLACEMENT_LEAN_BASELINE_WRITES_ENABLED`, `STEP_SYNC_BULK_ENABLED`, and `APNS_SESSION_REUSE_ENABLED`. They are enabled one at a time after staging. |
| D15 | With inert-push suppression enabled, pure alert classification happens before token lookup; only definitely non-visible placement changes return early. For a potentially visible alert, token lookup still precedes cooldown stamping and payout-drop claim, preserving no-token semantics. |
| D16 | When `STEP_SYNC_BULK_ENABLED=true`, recipient eligibility uses one bulk user read and one bulk token read. Sends use a bounded worker pool with `STEP_SYNC_PUSH_CONCURRENCY` default 8, clamped 1–16. Flag false retains the current service exactly. |
| D17 | Bulk step-sync captures one `attemptedAt` anchor before eligibility evaluation. Successful bookkeeping uses monotonic `GREATEST(existing, attemptedAt)`/equivalent—not completion time—and writes only users with at least one successful token send, preserving the current cooldown anchor during slow bursts. It bypasses broad `/auth/me` invalidation because the timestamp is internal scheduler metadata. Unregistered deletion matches exact `(userId,token)` tuples, never independent `IN` cross-products. |
| D18 | With `APNS_SESSION_REUSE_ENABLED=true`, APNs maintains at most one reusable HTTP/2 client per primary/fallback host/process, coalesces concurrent connects, uses 5s connect and 10s request timeouts, and evicts on close/goaway/error/timeout. An idempotent `close()` handles connected/pending sessions and is wired into `SIGINT` and `SIGTERM`. Flag false retains one connection per send. |
| D19 | Concurrent mystery-box mutation semantics are unchanged in this performance project. Batch retains its outer skip read and each single-open invocation retains its own authoritative powerup read before rolling. The prepared optimization applies only to lean race context; it never substitutes a stale powerup row. Atomic double-open prevention is a separate correctness/economy spec. |
| D20 | The first release order is observability and interactive query reductions, then distributed tick claim, lean baseline writes, inert push suppression, bulk step sync, and APNs reuse. Each switch is enabled and observed independently. |
| D21 | Spec approval authorizes implementation only. Every production deploy still requires a fresh explicit owner confirmation after staging evidence and code review. |

## 6. API contract

No public contract changes are permitted. The implementation agents must capture
golden responses for the following routes before changing business logic and
assert deep equality afterward, excluding nondeterministic timestamps already
present in the contract.

### 6.1 Single mystery-box open

```http
POST /races/:raceId/powerups/:powerupId/open
Authorization: Bearer <session token>
X-Client-Features: <existing tokens>
```

Success, status codes, and response fields remain exactly current, including
idempotent `alreadyOpened` behavior where supported:

```json
{
  "result": {
    "id": "powerup-uuid",
    "type": "LEG_CRAMP",
    "rarity": "UNCOMMON",
    "autoActivated": false,
    "alreadyOpened": true
  }
}
```

`alreadyOpened` remains absent on a fresh open. Existing `400`, `403`, `404`,
and `500` status/error shapes and validation order remain unchanged.

### 6.2 Batch mystery-box open

```http
POST /races/:raceId/powerups/open-batch
Authorization: Bearer <session token>
Content-Type: application/json

{"powerupIds":["uuid"],"includeQueued":true,"maxCount":20}
```

The current response, cap, explicit-ID ordering, queued ordering, per-item
`queued`/`alreadyOpened` semantics, and `remainingQueuedBoxCount` remain exactly
unchanged. Rolls stay sequential and individually audited.

### 6.3 Sneaky Swap targets

```http
GET /races/:raceId/powerups/sneaky-swap-targets
Authorization: Bearer <session token>
```

```json
{
  "targets": [
    {"userId":"uuid","displayName":"Racer"}
  ]
}
```

The exact existing envelope and field nullability discovered in the handler must
be preserved. Candidate order stays the race participant order. Membership,
race-active, team/enemy, accepted, finished, forfeited, Stealth, and stealable
inventory filters remain unchanged. A HELD Mystery Box or Sneaky Swap is not
stealable.

### 6.4 Powerup use

```http
POST /races/:raceId/powerups/:powerupId/use
Authorization: Bearer <session token>
Content-Type: application/json

{
  "targetUserId": "optional-uuid",
  "targetUserIds": [],
  "targetDirection": null,
  "swapOfferedPowerupId": null,
  "swapRequestedPowerupId": null,
  "targetEffectId": null,
  "upgradeLevel": 0
}
```

Every currently accepted legacy/additive request subset remains accepted. No
parameter becomes required. Success bodies, typed error codes, HTTP statuses,
refund-on-rejection behavior, event payloads, and notification payloads remain
unchanged for every powerup type and defense outcome. The ordinary response
remains `{"result": ...}`. X-Ray/Defense Scan retains its additive top-level
`{"ok":true,"scan":...,"result":...}` shape.

### 6.5 Cron/push contracts

There is no client API change. Visible `PLACEMENT_CHANGED` pushes retain:

```json
{
  "type": "PLACEMENT_CHANGED",
  "route": "race_detail",
  "params": {"raceId": "uuid"},
  "placement": 2
}
```

Titles/body copy, collapse ID, audit type, payout-drop delivery claim, and
cooldown behavior stay current. `STEP_SYNC_REQUEST` remains the exact silent
payload handled by iOS and Android:

```json
{"type":"STEP_SYNC_REQUEST"}
```

No new push type or client parser is introduced.

## 7. Backend implementation plan

### Phase A — measurement and safety seams

1. Add structured duration/query counters around single/batch box open, Sneaky
   target selection, `usePowerup` by type/outcome, placement phases, step-sync
   scheduling, and APNs sends. Do not log tokens, payload secrets, or user PII.
2. Capture current integration responses and database side effects before logic
   changes. Add Prisma query-event counting only in the disposable-test harness.
3. Add safe-parsed, startup-logged positive switches, all default false:
   `PLACEMENT_DISTRIBUTED_CLAIM_ENABLED`,
   `PLACEMENT_INERT_PUSH_SUPPRESSION_ENABLED`,
   `PLACEMENT_LEAN_BASELINE_WRITES_ENABLED`, `STEP_SYNC_BULK_ENABLED`, and
   `APNS_SESSION_REUSE_ENABLED`. Add `PLACEMENT_BASELINE_WRITE_CONCURRENCY=4`
   (clamp 1–8) and `STEP_SYNC_PUSH_CONCURRENCY=8` (clamp 1–16). These are
   environment switches, not `app_settings`; if implementation moves any to the
   DB, it must add them to `KNOWN_FLAGS` and retain default false.

### Phase B — mystery-box query and reconciliation reduction

1. Add `Race.findMysteryBoxContext(raceId)` using an explicit select for only:
   race id/status/powerup fields/team fields and all participants' id, userId,
   status, totalSteps, rawSteps, bonus/max-bonus, next-box, finishedAt,
   finishTotalSteps, team, and any scalar directly proven necessary by
   `rawPositionFor` or the lean repair helper. Do not include participant users
   or cosmetics. Participants must be ordered by `joinedAt` exactly as
   `findAcceptedByRace`/current race hydration, because stable tie order affects
   raw odds rank and Trail Mine's tied-last gate.
2. Derive the caller participant from all statuses exactly as current
   `findByRaceAndUser` does, while separately filtering accepted participants for
   odds. Remove both duplicate reads without turning invited, declined, pruned,
   or other retained participant statuses into a false non-member error.
3. Introduce an internal prepared context consumed by `openMysteryBox`. The
   public command signature/route response stays unchanged. In a single open,
   retain the current order: ownership/type/status checks and idempotent replay
   happen before active-race/member validation. Batch opening builds the context
   lazily at the first item current behavior would open, then passes it to later
   sequential opens. Thus a batch containing only missing, foreign, expired, or
   already-opened/skipped rows retains its current response even for an inactive
   race. The prepared object is scoped to one roll only; batch calls acquire a
   fresh lean context for every actually opened box so steps, status, and slots
   can change between rolls exactly as today. Never trust caller-supplied context.
4. Preserve both powerup reads in the batch path: the outer read owns current
   skip/ordering behavior and the single-open read is the authoritative current
   business check. Do not pass a prepared powerup row or add locking/transaction
   semantics in this performance scope. Query reduction comes from lean race
   context and narrow repair—not weakening or changing concurrent mutation
   behavior.
5. Keep balance snapshot and Lucky Horseshoe lookup/consumption per roll exactly
   as today; the first roll can consume the effect and a config version can change
   during a long batch.
6. Treat `powerupSlots` as mutable. The fresh per-roll snapshot is taken before
   RNG and is the exact value used by the existing Fanny re-roll/full-inventory
   rules; do not add a post-roll lock/re-read that changes snapshot timing. The
   next sequential batch roll obtains a new snapshot and therefore observes the
   earlier expansion. A deterministic two-Fanny batch pins this behavior.
7. Replace normal-open `syncRacePowerupState` with a narrow repair helper that
   preserves its gates and non-rolling behavior. It first returns unchanged when
   the race is not ACTIVE, powerups are disabled, the interval is null/zero, or
   the participant is not ACCEPTED. Past those gates it repairs max-bonus
   high-water, counts occupied slots, promotes oldest queued boxes into any
   already-free slots, and returns queued count. Fanny invokes the same helper
   after expansion. No branch hydrates a general race, and resolution enqueue
   remains exactly where current capacity mutation requires it.
8. Keep event writes and `MYSTERY_BOX_OPENED` emission per box. Do not batch or
   reorder RNG calls, events, or response items.

### Phase C — bulk Sneaky Swap target selection

1. Extract a DI-built `modules/races/queries/getSneakySwapTargets.js`, export it
   from `modules/races/index.js` before routes, and inject it into the thin
   `asyncHandler` route. Its lean projection contains only race status/team
   fields and participants' id, userId, status, finishedAt, forfeitedAt, team,
   and displayName, ordered by `joinedAt` ascending exactly as today.
2. Build candidate IDs using the existing membership/team filters.
3. In parallel, run exactly one
   `findActiveByTypeForParticipants(ids, "STEALTH_MODE")` and one
   `findInventoryForParticipants(ids, ["HELD"])` query.
4. Build sets of stealthed participant IDs and participant IDs holding at least
   one `isStealable` item. Filter the original candidate array in memory so
   response order/null display names stay unchanged.

### Phase D — cast-path conditional work

1. Add `Race.findPowerupUseContext(raceId)`, an explicit lean projection for
   every race/participant/user scalar actually consumed by `usePowerup`. Replace
   its general cosmetic-hydrating `findById` for all powerup types, not only Trail
   Mine. Preserve participant order and nullable user/display fields used in
   events and results. Participants remain ordered by `joinedAt` ascending. A
   structural test must fail if the projection gains equipped accessories/shop
   items.
2. Inventory every pre-mutation validation in `usePowerup`, including early
   branches that currently call `syncRacePowerupState`. Group only truly
   independent reads into `Promise.all`, then evaluate results in the current
   source order so the same competing invalid conditions return the same error.
3. Record internal mutation facts while executing the selected powerup and any
   Mirror/Decoy/Socks outcome. These facts choose whether already-loaded effect
   state can be reused; they do not change which current control-flow branches
   invoke high-multiplier evaluation.
4. Replace full `syncRacePowerupState` only at control-flow call sites that invoke
   it today, using the same narrow repair/promotion helper from Phase B wherever
   exact parity is proven. An early return that currently skips sync—including
   blocked Compression Socks and Imposter outcomes—continues to skip repair even
   if it consumed or changed a row. If a current sync call depends on any other
   side effect, retain full sync there until an integration test and explicit
   helper preserve it.
5. At each current repair/sync call site, re-read the caster's lean participant
   id/status/powerupSlots/bonus/max-bonus/next-box/finish scalars before counting
   occupied inventory. This preserves post-cast freshness under a concurrent
   Fanny expansion without reloading a full race. Promote oldest queued rows in
   the same order and return the same queued count if consumed by a caller.
6. Preserve the exact current set of `evaluateHighMultiplierAlert` call sites.
   Shared-tail direct Leg Cramp/Sneaky Swap/Trail Mine casts still evaluate so
   below-threshold re-arm state is unchanged, but may reuse the lean caster and
   known-unchanged preloaded effects. Self-buffs, Cleanse, and reflections update
   the in-memory effect set only when parity is provable; otherwise refresh.
   Self-contained early-return paths that currently skip evaluation keep skipping
   it, even if their multiplier could conceptually change.

### Phase E — Trail Mine canonical lean path

1. Add `Race.findForResolution(raceId)` (or a common exact-select helper shared
   with `findActiveForUser`) containing every scalar consumed by
   `raceStateResolution`, scoring prefetch, team logic, finish/freeze logic,
   box-effective calculations, and event metadata—but no cosmetics, creator,
   winner, seed, or tournament relation unless a contract test proves one is
   consumed. Preserve `participants.orderBy = {joinedAt: "asc"}`; tied totals
   must resolve in the same stable order for Trail Mine and odds gates.
2. Make `computeRaceState`/canonical resolution use that lean path for a single
   race. Keep `prefetchRaceScoringModels` and the one canonical scoring pipeline.
3. In Trail Mine, use `computed.result.race` as the race object and overlay
   `totalsByParticipantId`; remove the subsequent general `findById`. Do not
   compute a second rank or use persisted/cache totals.
4. If canonical computation returns no processable result, load the lean
   powerup-use context and continue exactly as current code: reject inactive or
   elapsed races, but allow an ACTIVE legacy/null-`startedAt` row to use stored
   participant totals. This fallback performs no scoring.
5. Preserve the read-only write-capture guarantee and enqueue the same durable
   resolution job after a successful plant.

### Phase F — distributed placement claim, lean baselines, and inert pushes

1. At the beginning of each scheduled callback, derive a stable UTC five-minute
   bucket key and call `JobRun.claimRun("placement-recompute-v2", bucketKey)`
   when `PLACEMENT_DISTRIBUTED_CLAIM_ENABLED=true`. A losing PM2 worker logs and
   returns before the active-race scan. Do not use an advisory lock. The existing
   process-local `running` guard remains. Claim-before-work accepts that a winner
   crash can defer work to the next five-minute bucket, rather than duplicate a
   whole tick across workers.
2. Keep participant baseline writes individual so the fenced race-resolution
   worker remains the sole multi-row writer. Add a dedicated
   `compareAndSetPlacementBaseline(id, expected, next)` that updates only the
   scalar baseline with null-safe expected-value matching and returns whether it
   won; it must not include user/accessory relations.
3. When `PLACEMENT_LEAN_BASELINE_WRITES_ENABLED=true`, run those per-row CAS
   writes through a bounded pool (default 4, clamp 1–8), with failure isolation
   per race. Apply resync, first-observation, muted, team, and ordinary semantics
   in proposal metadata. Emit only after a won ordinary unmuted change. Flag
   false uses the current sequential update/emission path.
4. For `TEAM_LEAD_CHANGED`, after member CAS results are known, atomically claim
   the logical transition using a race-scoped key and transition value (for
   example `JobRun.claimRun("team-lead:<raceId>", "<old>-><new>:<generation>")`)
   before emitting. The key design must allow a later legitimate A→B after an
   intervening B→A, while two concurrent calculations of one flip yield one
   winner. If all-or-none semantics cannot be proven with per-row CAS, keep the
   existing sequential team baseline path behind the flag.
5. The notification handler first performs pure meaningful-alert classification.
   With `PLACEMENT_INERT_PUSH_SUPPRESSION_ENABLED=true`, a definitely inert
   change returns before token lookup. A potentially visible change still loads
   tokens next; zero tokens returns before cooldown timestamp changes or payout
   claim, exactly as today. Only then run time window, cooldown, durable claim,
   fallback, and send in their existing order.
6. Preserve payout-drop's insert-first deterministic claim and fallback to
   lost-lead behavior. Baseline CAS is not a notification delivery claim.
7. Before a production enable, verify PM2 instance/exec mode and ensure old/new
   scheduler generations cannot overlap: retain the startup delay and observe a
   full old-worker drain. The new distributed claim cannot make an overlapping
   old unconditional scheduler atomic.

### Phase G — bulk step-sync scheduling

1. Add model methods to select only `id`, `lastStepSyncAt`, and
   `lastSilentPushSentAt` for all unique recipients and to load all their device
   tokens in one query. Group by user in memory.
2. Apply the existing one-hour/default, caller override, and 15-minute hard-floor
   throttle rules exactly once per user against one `attemptedAt` timestamp
   captured before the reads. Users without tokens remain no-ops.
3. Flatten eligible token sends and execute through a bounded concurrency pool
   (default 8). Route Android to FCM and iOS/other to APNs exactly as today.
4. Collect successful user IDs and unregistered `(userId, token)` pairs. Perform
   bounded bulk deletes matching those exact tuples and one monotonic bulk
   `attemptedAt` update (`GREATEST` or equivalent) after sends. Reversed completion
   order can never move `lastSilentPushSentAt` backward. A partial send marks a
   user successful exactly as today.
5. Keep the single-user public service as a wrapper over the bulk engine so
   friends/other callers share the same semantics and do not fork behavior.
   `STEP_SYNC_BULK_ENABLED=false` retains the current implementation.

### Phase H — reusable APNs transport

1. Separate request construction/parsing from connection acquisition.
2. Maintain primary and fallback host clients in process-local state. Share a
   pending connect Promise so a burst cannot create one connection per token.
3. Set connect and per-stream timeouts; resolve every call exactly once. On
   GOAWAY, close, session error, or timeout, evict the session and fail that
   request normally so the next send reconnects.
4. Keep JWT caching, APNs headers, alert/background priority, collapse IDs,
   unregistered detection, and BadDeviceToken environment fallback unchanged.
5. Add a shutdown hook owned by the push module or existing server shutdown path
   to close reusable clients without preventing process exit. Expose an
   idempotent `close()` that settles/cleans both connected and pending-connect
   sessions. Wire it into both `SIGINT` and `SIGTERM`; stop accepting HTTP first,
   close APNs after in-flight drain, and retain the hard-exit backstop.
6. `APNS_SESSION_REUSE_ENABLED=false` retains the current one-session-per-send
   transport. Only the true branch installs/reuses process-local sessions.

## 8. Data model and migrations

No schema migration is expected.

- Existing race/participant/effect/powerup indexes cover lean ID/status queries.
- Placement CAS updates use participant primary-key IDs and compare the
  already-read baseline; no new index is required. `JobRun` already supplies the
  unique cross-process tick-claim row.
- Bulk user/token reads use existing user primary keys and device-token user
  indexing. Before implementation is accepted, run `EXPLAIN ANALYZE` on the
  300-participant Sneaky reads and 750-user token read in the disposable/staging
  database. Add an additive concurrent index migration only if the plans prove
  a sequential scan that materially misses the gates.
- No column is removed, renamed, repurposed, or made required.

Truth and transient-state placement is explicit:

| Data/state | Store | Reason |
|---|---|---|
| Race, participant totals/baselines, effects, powerups, users, device tokens | Postgres | Exact mutation-sensitive source of truth; never cache for a decision in this spec. |
| Five-minute scheduler and team-transition claims | Postgres `JobRun` | Cross-process uniqueness across PM2 workers/restarts. |
| Balance config | Existing balance service/cache | Existing per-roll semantics and version stamping remain unchanged. |
| APNs HTTP/2 clients/pending connects | Process-local memory | Disposable transport only; evicted on errors and closed on shutdown. |
| Endpoint/query metrics | Existing logs/metrics | Observability only; never feeds gameplay. |

No new Redis surface is justified: the optimized reads make exact Postgres
queries smaller/bulk, while caching odds, effects, inventory, throttle truth, or
baselines would introduce staleness into decisions.

If a migration becomes necessary after plan inspection, amend this document and
repeat architect review before writing it. Production migration still deploys
before code that relies on it and must remain compatible with the old backend.

## 9. Frontend plan and defensive compatibility

There is no frontend implementation.

- Existing iOS and Android requests receive identical responses and errors.
- Existing case-opening animation and reveal timing are unchanged.
- Existing foreground notification routing and notification-tap routing are
  unchanged.
- Silent `PLACEMENT_CHANGED` suppression is server-only. Source/history guards
  must prove that the placement feature's shipped client implementations act
  only on `STEP_SYNC_REQUEST` for background work.
- Old clients require no field, endpoint, capability, or app update.

Because nothing visible is added, moved, resized, or removed, the UI-placement
test planner is not required for this project. If implementation discovers a
frontend or visible-placement change, stop, amend the spec, and run that planner
before proceeding.

## 10. Backward compatibility, rollout, and rollback

### 10.1 Compatibility rules

- All route shapes and validation precedence remain compatible with every frozen
  app version.
- Internal lean queries must retain null/default behavior. Missing optional race
  or participant values continue through existing fallbacks.
- Optimization code must not require a coordinated frontend release.
- Randomness and state ordering are compatibility behavior: do not parallelize
  rolls or mutable effect consumption.

### 10.2 Rollout order

1. Land tests and Phase A instrumentation with every new positive switch false.
2. Deploy Phases B–E to staging; run correctness/query-count/latency gates.
3. Deploy Phase F dark. In staging, enable distributed tick claim first, then
   lean baseline CAS, then inert push suppression, observing at least six
   five-minute ticks after each—including a tick with visible placement movement.
4. Deploy Phase G/H dark. Enable bulk step sync, observe both iOS APNs and Android
   FCM, then enable APNs reuse and exercise primary/fallback, unregistered tokens,
   partial failures, SIGINT/SIGTERM, shutdown, and reconnect.
5. Run the backend code reviewer over the complete implementation and resolve all
   blockers/issues.
6. Present staging evidence and request fresh production authorization. Spec or
   implementation approval alone does not authorize production.
7. If authorized, deploy one phase at a time during observation. Compare CPU,
   event-loop lag, endpoint p50/p95, DB active connections/query rate, placement
   duration/emitted count, step-sync eligible/sent/failure counts, and APNs
   connection establishments for at least six ticks before advancing.

### 10.3 Kill switches and rollback

- Setting any positive switch in D14 to false restores that path's legacy
  implementation without a code rollback.
- `PLACEMENT_BASELINE_WRITE_CONCURRENCY=1` and
  `STEP_SYNC_PUSH_CONCURRENCY=1` serialize their respective new pools.
- Each phase lands in a separate commit so it can be reverted independently.
- If visible notification counts/copy, box distributions, powerup errors, or
  Trail Mine results differ, stop rollout and revert the responsible phase.
- Do not compensate by increasing DB pool size or race worker concurrency.

## 11. Test plan — tests first

Backend behavior tests default to real HTTP plus a real disposable Postgres DB.
Before any integration suite, assert `DATABASE_URL` names a dedicated `*_test`
database or disposable container. Never run these tests against production.

### 11.1 Mystery-box integration coverage

- Fresh single open returns the same type/rarity/status/event/inventory state.
- Idempotent replay returns existing data and creates no second event or roll.
- Inactive race, non-member, foreign powerup, invalid status, and old-client
  capability failures retain exact status/error shapes and precedence.
- Caller participant statuses `PENDING`, `ACCEPTED`, `DECLINED`, and any seeded
  retained/pruned status match current membership/error behavior; only accepted
  rows enter odds ranking.
- Raw-step all-present and NULL-fallback races produce the same odds tier; team
  ties still count both as leading. Solo equal-raw-step fixtures pin the
  `joinedAt` tie order and resulting odds tier.
- Lucky Horseshoe affects exactly one sequential roll and is expired afterward.
- Fanny Pack auto-activation fixture (injected config) expands slots and promotes
  queued boxes exactly as before.
- Drift fixtures with `maxBonusSteps < bonusSteps` and a queued box plus an
  already-free slot prove normal opening retains both narrow repairs.
- Cross-product repair guards cover inactive race, powerups disabled,
  null/zero interval, and caller statuses `PENDING`/`DECLINED`/retained-pruned;
  even with deliberately drifted max-bonus/queued rows, none may repair or
  promote. The ACCEPTED/active/enabled/positive-interval control does both.
- A deterministic two-Fanny injected-config batch proves the second roll sees
  the first roll's updated slot count and consumes the same RNG sequence.
- Batch explicit/queued ordering, cap 20, mixed replay, foreign IDs, and remaining
  queued count remain identical.
- Query-count guard proves a 20-box batch performs one lean joined-order
  standings read per actual roll, no cosmetic hydration, and exactly the narrow
  normal-open repair rather than full inventory synchronization.
- Deterministic RNG parity test asserts identical call count/order and results for
  a fixed sequence before/after optimization.
- Batch compatibility cases include an inactive race with only missing/foreign/
  skipped IDs and prove lazy context creation preserves the current non-error
  response; the first actually openable box still produces the current inactive
  race error.
- Concurrent single/open-batch fixtures record current behavior and prove the
  performance work neither adds a stale prepared-powerup seam nor claims to fix
  the separate double-open race.

### 11.2 Sneaky Swap integration coverage

- 300 accepted candidates with mixtures of same team, forfeited, finished,
  Stealth, empty inventory, only box, only Sneaky Swap, and stealable inventory
  return the exact eligible ordered list.
- Non-member identity disclosure remains `403`; inactive race and normal errors
  remain current.
- Prisma query-event assertion proves query count is bounded from 10 to 300
  candidates and neither per-participant model method is invoked.

### 11.3 Powerup and Trail Mine integration coverage

- Table-driven public-route cases cover every powerup type and meaningful defense
  outcome. Assert response/error, powerup/effect/event/coin state, target, and
  enqueue behavior.
- Dedicated Leg Cramp cases pin Jammer, Stealth, existing Leg Cramp/Wrong Turn,
  Mirror, Decoy, Socks, upgrade stacking, reflection, and simultaneous-invalid
  error precedence.
- High-multiplier branch-parity coverage proves shared-tail direct casts still
  evaluate/re-arm, and self-contained early-return Uprising/Rally/Potion branches
  still do not gain evaluation. Self-buffs, Cleanse, and reflections that
  currently evaluate retain their exact state and alert behavior. Cover both
  durable resolution-worker enabled and rollback/inline resolution modes.
- Cast consumption promotes the same oldest queued box despite removal of full
  synchronization only at branches that currently synchronize. Blocked
  Compression Socks, Imposter, and every other current no-sync early return keep
  their existing inventory tempo. Normal mystery-box opening preserves promotion
  only for a pre-existing drifted free slot; its own `MYSTERY_BOX -> HELD`
  transition does not create a new slot.
- Trail Mine with 300 participants plants at canonical computed total, rejects
  exact last place/ties as currently defined, triggers mines in the same order,
  performs zero captured writes before success, and enqueues resolution.
- A tied-last fixture with different `joinedAt` values pins which participant is
  considered last before/after the lean projection.
- Structural/query guard proves Trail Mine uses the lean resolution projection,
  never loads cosmetics, and does not call a second race hydration.
- Structural/query guard proves every `usePowerup` type uses the lean use-context
  projection and a branch/call-site guard pins exactly which paths perform
  narrow repair versus no repair.
- Repair-time concurrency coverage changes `powerupSlots` between the initial
  race read and shared-tail repair, proving the lean participant refresh observes
  the new capacity. ACTIVE/null-`startedAt` Trail Mine keeps using stored totals
  and current success/error semantics.

### 11.4 Placement integration coverage

- A 750-participant fixture covers individual and team ranks, ties, finished and
  forfeited rows, seed-null baselines, resync flag, muted rows, unchanged rows,
  took-first, lost-first, payout-drop inside/outside window, cooldown, and durable
  payout claim.
- Assert final baselines and emitted payloads equal the pre-change behavior.
- Two scheduler instances against one real DB prove the five-minute `JobRun`
  claim has exactly one winner and the loser performs no active-race/effect/user/
  token scan. Flag false proves current scheduling remains available.
- Concurrent placement CAS versus the fenced resolution worker and race expiry
  proves no deadlock, no total overwrite, and only one placement emitter per won
  baseline transition. Failure for one race emits nothing there and does not
  block later races.
- Concurrent team lead calculations prove one logical flip emits once and all
  later legitimate reverse flips remain claimable; if this cannot pass, team
  baseline writes remain on the legacy path.
- With inert-push suppression enabled, non-meaningful movement performs no token
  read, push, or audit. Flag false restores the legacy silent path. Each new
  rollout flag has a default-false/legacy-parity integration case.
- A no-token payout-drop candidate creates no delivery claim and does not stamp
  cooldown state.
- Visible alerts load/send/delete tokens exactly as before under either flag.
- Due ACTIVE effects with more than two stale races still enqueue immediately and
  are processed through the worker; resolution concurrency remains two.

### 11.5 Step-sync and APNs coverage

- Bulk vs legacy parity fixtures cover recent step sync, recent push, no tokens,
  iOS, Android, multiple tokens, mixed success, unregistered, thrown sender,
  caller interval override, and 15-minute floor.
- Query count remains bounded as recipients increase from 10 to 750.
- Send concurrency never exceeds configured/clamped limit.
- Only users with at least one success receive `lastSilentPushSentAt`; internal
  bookkeeping does not invalidate `/auth/me` cache.
- Overlapping bulk calls completing in reverse order cannot move the timestamp
  backward, and a deliberately cross-paired `(userId,token)` fixture proves
  unregistered deletion removes exact tuples only.
- APNs fake HTTP/2 integration tests prove one connection serves many streams,
  simultaneous first sends share connect, GOAWAY/close/error evicts, request and
  connect timeouts settle, next send reconnects, shutdown closes, JWT is reused,
  and BadDeviceToken fallback still uses the alternate host.
- Both `SIGINT` and `SIGTERM`, including shutdown during pending connect and
  active streams, settle through idempotent `close()` before the hard-exit bound.

### 11.6 Commands and verification

- Focused tests first while implementing.
- `npm run test:unit`
- `npm run test:integration` only after confirming a disposable/test DB.
- Never run bare `npm test`.
- No Flutter code changes are expected. Still run `flutter analyze` and the
  existing focused client notification/case-opening tests as compatibility
  evidence. If implementation unexpectedly touches frontend code, stop and amend
  this spec before running the full required Flutter suite and both-platform
  verification.

## 12. Observability and operational acceptance

Structured logs/metrics must include no PII and expose:

- endpoint name, powerup type/outcome, total duration, DB duration/query count in
  test/staging instrumentation, and whether optional post-work ran;
- placement tick active races/participants, due/recovery enqueues, proposals,
  CAS wins/losses, emitted visible candidates, skipped inert silent events,
  phase durations, and complete handler-drain duration where measurable;
- step-sync requested/unique/throttled/no-token/eligible users, token attempts,
  successes/unregistered/failures, send concurrency, and duration; and
- APNs session connect/reuse/evict/timeout counts by host class, never token.

Production success after six observed ticks means:

- no increase in 4xx/5xx rates or box/powerup rejection mix;
- no difference in deterministic box-distribution canaries;
- visible placement alert and step-sync success behavior remains plausible;
- placement tick p95 and CPU spike area materially decline from the pre-phase
  baseline; and
- powerup endpoint p50/p95 improve without resolution-queue lag regression.

## 13. Acceptance criteria and definition of done

- All scoped phases are implemented test-first and pass relevant full backend
  unit/integration suites against a verified test DB.
- Query-count and staging latency gates in section 3 pass with evidence attached.
- Every invariant in sections 3–6 has real public-path integration coverage; no
  existing assertion is weakened, skipped, or deleted.
- Old-client/API compatibility is explicitly reviewed and no frontend release is
  required.
- Game-economy review confirms no scoring, odds, RNG, drop, exploit, or payout
  change.
- Architect review has no unresolved blockers.
- Post-implementation code reviewer has no unresolved blockers/issues.
- Staging verification covers both APNs/iOS and FCM/Android paths.
- No production deploy occurs without a new explicit confirmation after the
  implementation and staging report.

## 14. Revision log

- **2026-08-13 — Initial consolidation:** combined mystery-box overfetch,
  Sneaky Swap N+1, conditional cast post-work, Trail Mine canonical lean loading,
  placement baseline writes, inert silent placement pushes, bulk step-sync
  scheduling, and APNs connection reuse into one backend-only performance spec.
- **2026-08-13 — Fresh-eyes gap pass 1 (contract and behavior):** corrected the
  public `{result}`/X-Ray envelopes, expanded lean hydration to every powerup use,
  moved Fanny-only occupied counting off normal rolls, eliminated the batch's
  duplicate per-item read without weakening checks, and prohibited caching the
  mutable balance snapshot or Lucky Horseshoe across sequential rolls.
- **2026-08-13 — Fresh-eyes gap pass 2 (failure/rollout safety):** made batch
  context creation lazy to preserve skipped-row and inactive-race precedence,
  pinned single-open idempotent validation order, specified Trail Mine's lean
  fallback when canonical resolution returns no race, preserved the rare Fanny
  repair/promotion path, and aligned verification with the frontend repository's
  analyze rule.
- **2026-08-13 — Architect correction pass:** removed the proposed set-based
  participant writer to preserve the fenced race-resolution invariant; added a
  cross-process five-minute `JobRun` claim, scalar CAS baselines, team-transition
  claiming, default-dark switches, all-status box membership, narrow drift
  repair, monotonic/exact-tuple push bookkeeping, explicit Postgres/process-local
  storage boundaries, and complete SIGINT/SIGTERM APNs shutdown semantics.
- **2026-08-13 — Game-economy correction pass:** prohibited batch odds/slot
  caching, pinned `joinedAt` tie order, preserved exact multiplier-evaluator call
  sites and re-arm behavior, added two-Fanny/raw-tie/tied-last fixtures, anchored
  step-sync cooldown to attempt time, and explicitly excluded concurrent-open
  hardening from this performance-only scope.
- **2026-08-13 — Final review:** architect verdict READY and game-economy verdict
  READY after the repair gates, pre-RNG Fanny snapshot, current-sync-only cast
  repair sites, ACTIVE/null-`startedAt` Trail Mine fallback, and repair-time lean
  participant refresh were pinned with integration cases.
