# Bara Power-Up Scale, Data Model, and Transaction Audit

Research-only audit for redirected duplicate effects and shop power-up cooldowns at large scale. No application code, tests, schema, migrations, deployment, or production benchmarks were changed or run.

## 1. Executive Scale Assessment

The current power-up system is transactionally careful but not yet scale-optimal for large concentrated races.

Strengths:

- Conditional `RacePowerup` claims.
- PostgreSQL transactions.
- Race write fences.
- Deterministic participant-lock ordering.
- Bulk `RaceActiveEffect.createManyForTargets()`.
- Bulk active-effect reads for some AoE paths.
- After-commit event/notification delivery.
- Existing race-scoped scoring invalidation and queued resolution.

Main risks:

1. Complex activations can lock the entire accepted participant cohort of a race.
2. Rainstorm can perform per-final-target defense/effect lookups.
3. `RaceActiveEffect` has no universal same-type uniqueness constraint, correctly allowing different policies but requiring application enforcement.
4. Global inventory is intentionally a per-user/type serialization point.
5. `RacePowerupEvent` and active-effect history are append-heavy.
6. Cooldown availability should be compact current state, not an unbounded history scan.
7. Activation performs invalidation, resolution enqueueing, and inventory repair work in the request flow, although notifications are deferred after commit.

Recommended direction:

```text
transaction
  -> claim power-up
  -> acquire appropriate race/participant locks
  -> bulk-load participants/effects/defenses
  -> validate cooldown
  -> resolve final targets
  -> apply policy-aware duplicate rules in memory
  -> bulk-write effects
  -> update compact cooldown state
  -> write durable event/outbox data
  -> commit
  -> notifications/scoring/projections after commit
```

Do not introduce sharding, Redis authority, microservices, or global distributed locks at this stage.

## 2. Current Activation Transaction

Primary files:

- `backend/src/modules/powerups/routes.js`
- `backend/src/modules/powerups/commands/usePowerup.js`
- `backend/src/modules/powerups/models/raceActiveEffect.js`
- `backend/src/modules/powerups/models/racePowerup.js`

The production path enters `runInPrismaTransaction()` in `usePowerup.js` around line 4897.

The wrapper:

1. Reads the candidate `RacePowerup` type.
2. For Leech, optionally reads the target participant and locks scoring-input state.
3. Chooses shared versus exclusive race-guard behavior.
4. Acquires the race-resolution guard.
5. Locks the race row or takes a shared lock.
6. Calls `lockPowerupUseParticipants()`.
7. Re-reads the power-up type for shared-guard validation.
8. Calls `usePowerupCore()`.

### Simple self instant power-up

Typical operations:

- Candidate `RacePowerup` read.
- Race guard acquisition.
- Power-up row `FOR UPDATE`.
- Owner participant lock.
- Race/participant context read.
- Effect-specific existing-state reads, if required.
- Instant result or effect mutation.
- Conditional update to `RacePowerup.status = USED`.
- Optional `RacePowerupEvent`.
- Resolution invalidation/enqueue.
- Inventory repair/refresh.
- After-commit notifications.

Exact count is branch-dependent.

### Single-target hostile power-up

Typical additions:

- Target validation.
- Mirror, Decoy, and Compression Socks reads.
- Same-type/conflict reads.
- Defense consumption updates.
- One effect insert.
- Activity/domain event writes.

### Decoy redirect

Additional operations:

- Decoy read on intended target.
- In-memory redirect selection.
- Decoy consumption update.
- Possible Mirror/Socks reads on redirected landing.
- Final duplicate/conflict policy check.
- Effect insert or blocked/no-op handling.

### Rainstorm

Rainstorm performs:

- `findActiveForRace(raceId)` for the caster's active-storm rule.
- In-memory victim selection.
- `resolveAoEDecoySlots()`.
- Per-victim Decoy reads unless an effect map is supplied.
- Per-landing Umbrella reads.
- Per-landing Compression Socks reads.
- One `RaceActiveEffect.create()` per final landing.
- Aggregate event plus recipient event emission.
- Conditional power-up update.
- Race invalidation/resolution enqueue.

Rows written are O(targets).

### Power Outage

Power Outage has a bulk active-effect prefetch path using `findActiveForParticipants()`. It then resolves final landings in memory, skips existing outage recipients, consumes defenses, bulk-creates effect rows using `createManyForTargets()`, emits events, and marks the power-up used.

## 3. Locking and Contention Model

### Race locks

`src/modules/races/services/raceWriteFence.js` exposes `acquireRaceWriteFence()`, delegating to `RaceResolutionJobV2.acquireForWrite()`.

Most complex power-ups acquire an exclusive race-resolution guard and then:

```sql
SELECT id
FROM races
WHERE id = $raceId
FOR UPDATE
```

Audited shared-guard types instead use `FOR SHARE` on the race-resolution row and race row.

### RacePowerup lock

`lockPowerupUseParticipants()` performs:

```sql
SELECT participant_id, type
FROM race_powerups
WHERE id = $powerupId
FOR UPDATE
```

The later conditional update requires the row to remain `HELD`, preventing concurrent double use.

### Participant locks

Self-only types lock the owner participant. Complex paths lock all accepted participants:

```sql
SELECT id
FROM race_participants
WHERE race_id = $raceId
  AND status = 'accepted'
ORDER BY user_id ASC
FOR UPDATE
```

This is the primary large-race contention point.

### Lock order

The documented order is:

```text
race fence
  -> race lifecycle row
  -> RacePowerup
  -> participants ordered by userId
  -> affected effect rows
```

The deterministic participant order reduces deadlock risk.

### Does activation serialize an entire race?

For Rainstorm and Power Outage, effectively yes. They are not in the shared race-guard set and use the exclusive path. Their accepted-participant cohort is also locked.

Therefore, 20 complex activations in one large race contend on the same race guard and participant rows. Different races do not contend on those same rows, except for shared user-level inventory.

## 4. Query and Write Profile

The exact count is branch-dependent.

| Operation | Self instant | Single target | Decoy redirect | AoE |
|---|---:|---:|---:|---:|
| Candidate read | 1 | 1 | 1 | 1 |
| Race guard | Constant | Constant | Constant | Constant |
| Power-up lock | 1 | 1 | 1 | 1 |
| Participant locks | 1 | Often cohort | Often cohort | Often cohort |
| Defense reads | 0/few | Few | More | O(targets) unless prefetched |
| Effect writes | 0/1 | 0/1 | 0/1 | O(targets) |
| Power-up update | 1 | 1 | 1 | 1 |
| Events | 0/few | 1/few | Several | Aggregate + recipients |
| Resolution wakeup | Usually 1 | Usually 1 | Usually 1 | Usually 1 |

The distinction matters between SQL statements, rows locked, and rows inserted. AoE rows naturally scale with targets; SQL query count should not.

## 5. AoE Scaling Analysis

### Rainstorm

Current logical complexity:

- Participant selection: O(N) memory work.
- Decoy resolution: O(N) logical work.
- Decoy reads: potentially O(N) queries.
- Umbrella reads: potentially O(N) queries.
- Compression Socks reads: potentially O(N) queries.
- Effect inserts: O(N) rows.
- Recipient events: O(N) logical records.
- Aggregate event and race wakeup: O(1).

Without prefetching, the query shape can approach constant transaction queries plus up to three defense/effect queries per target.

### Power Outage

The intended shape is:

```text
constant reads
  + one bulk active-effect query
  + O(N) in-memory evaluation
  + O(N) effect rows
```

It should remain on this path in production; fallback dependency paths should not reintroduce per-target reads.

### Large races

| Race size | Maximum Rainstorm effect rows | Preferred defense reads |
|---:|---:|---:|
| 10 | 9 | 1 bulk read |
| 50 | 49 | 1 bulk read |
| 100 | 99 | 1 bulk read |
| 500 | 499 | 1–few bulk reads |

## 6. Final-Landing Duplicate Check Design

### Per-target lookup

`findActiveByTypeForParticipant()` is simple and acceptable for one target, but O(targets) queries are not suitable for AoE paths.

### One bulk read

Preferred shape:

```sql
SELECT target_participant_id, type, expires_at, ...
FROM race_active_effects
WHERE target_participant_id IN (...)
  AND type IN (...)
  AND status = 'ACTIVE'
  AND (expires_at IS NULL OR expires_at > now())
```

Evaluate policy in memory.

### Reuse existing snapshots

Best option where available. Build:

```text
Map<participantId, Map<effectType, effectRows>>
```

Reuse it for Decoy, Mirror, Compression Socks, Umbrella, conflicts, and redirected duplicate policy.

### Database uniqueness

Not suitable as a universal mechanism because Rainstorm, Uprising, Coin Flip, Trail Mine, Power Outage, Leech, and Hitchhike have different policies.

### Recommendation

Use one bulk active-effect snapshot for AoE, resolve final landings, apply policy in memory, and bulk-write effects. Single-target paths may use one indexed lookup.

## 7. Power-Up Policy Architecture

`powerupStackingGuide.js` is useful documentation but enforcement remains distributed in `usePowerup.js`.

A narrow runtime policy registry could centralize stable declarative properties:

```js
{
  RAINSTORM: {
    shop: true,
    targetMode: "AOE_ENEMY",
    persistence: "TIMED_EFFECT",
    directDuplicate: "PER_CASTER",
    redirectedDuplicate: "SKIP_IF_FINAL_TARGET_ACTIVE",
    duration: "FIXED",
    cooldown: "AFTER_EFFECT_END",
  }
}
```

Good registry properties:

- Shop classification.
- Target mode.
- Persistence type.
- Direct duplicate policy.
- Redirected duplicate policy.
- Duration strategy.
- Cooldown strategy.
- Defensive eligibility.
- Bulk-write capability.
- Per-participant versus link-row storage.

Keep Leech scoring, Hitchhike attribution, Trail Mine detonation, Coin Flip outcomes, Mystery Potion resolution, and Bounty/Drill Sergeant mechanics in executable handlers.

## 8. Cooldown Storage Options

### History table

One row per use gives auditability but creates unbounded growth and requires latest-row queries for availability. Use history for audit, not as the primary current-state lookup.

### Mutable current state

One row per scope/type gives constant availability reads, bounded active-state cardinality, and simple frontend projection.

### Derive from effects/events

Avoid as the primary design. Instant and duration effects have different records, early termination is ambiguous, and concurrent availability checks are harder to enforce.

### Store on existing rows

`RacePowerup` is per item; `UserPowerupItem` is global quantity. Neither naturally represents race/user/type cooldown state.

### Redis-only

Unsafe as the authority because restart, eviction, stale reads, and failover can bypass cooldowns.

## 9. Recommended Cooldown State Model

Use a compact mutable state model, likely race-scoped:

```text
PowerupUsageState
  id
  raceId
  userId
  powerupType
  lastUsedAt
  activeUntil
  nextUsableAt
  sourcePowerupId?
  updatedAt
  UNIQUE(raceId, userId, powerupType)
```

Global scope would instead use `UNIQUE(userId, powerupType)`.

Keep audit/history in `RacePowerup`, `RacePowerupEvent`, and domain-event tables.

## 10. Cooldown Transaction Design

The check must be inside the same transaction as the power-up claim.

Recommended order:

```text
begin transaction
  -> acquire existing race/user/item locks
  -> claim/lock RacePowerup
  -> lock/read usage state
  -> reject if nextUsableAt > now
  -> resolve final effect and actual end
  -> update usage state
  -> create effect or instant result
  -> mark RacePowerup USED
  -> append durable event
commit
```

For existing state rows, `SELECT ... FOR UPDATE` is straightforward. For first use, insert/upsert must handle unique conflicts inside the transaction. Do not perform an unlocked read followed by a later write.

## 11. Index Design

Required unique lookup for race scope:

```text
UNIQUE(race_id, user_id, powerup_type)
```

This supports both exact activation checks and one-query race-screen projection.

A `nextUsableAt` index is not initially needed because activation looks up a specific scope key. Add one only if cleanup queries globally by expiration.

Relevant existing indexes:

- `RaceActiveEffect`: `(targetParticipantId, status)`, `(raceId, status)`, `(targetParticipantId, type, decoyConsumedAt)`, unique `(powerupId, targetParticipantId)`.
- `RacePowerup`: `(participantId, status)`, `(raceId, userId)`, `(userId, status, raceId)`, unique `(participantId, earnedAtSteps)`.
- `UserPowerupItem`: unique `(userId, powerupType)`, `(userId)`.
- `RaceParticipant`: unique `(raceId, userId)`, `(raceId, status)`, `(userId, status)`.
- `RacePowerupEvent`: `(raceId, createdAt)`, `(actorUserId, eventType, createdAt)`.

## 12. API / Projection Read Path

Return all cooldown state for the current race/user in one read:

```sql
SELECT powerup_type, active_until, next_usable_at
FROM powerup_usage_state
WHERE race_id = ?
  AND user_id = ?
```

Merge in memory with race inventory, global inventory, active effects, and catalog data.

Relevant existing paths:

- `getPowerupInventory()` for global quantity.
- `getRaceInventory()` for race-bound items.
- Race detail/use-context projection queries.
- Frontend `lib/services/backend_api_service.dart`.

Do not issue one cooldown query per power-up card.

## 13. Effect / Cooldown State Interaction

Store `activeUntil` and `nextUsableAt` if UI needs three states:

```text
now < activeUntil                 ACTIVE
activeUntil <= now < nextUsableAt COOLDOWN
now >= nextUsableAt                AVAILABLE
```

Instant effects need only `nextUsableAt` semantically. Duration effects use:

```text
activeUntil = actualEffectEnd
nextUsableAt = actualEffectEnd + 1 hour
```

Availability should not require joining `RaceActiveEffect` on every inventory request.

## 14. Event / Outbox Path

The repository already uses:

- `deferUntilAfterCommit()`.
- `appendDomainEvent()`.
- `events.emit()` and `events.emitMany()`.
- Notification handlers under `src/modules/notifications`.

Preferred critical path:

```text
validate
claim power-up
resolve defenses
apply policy
write effects
write cooldown state
append durable event/outbox row
commit
```

After commit:

```text
push notifications
analytics
cache invalidation
non-critical projections
```

The current implementation is partially aligned; `finalizeSelfContainedUse()` also performs race invalidation, enqueueing, and inventory repair work that should be measured before any future change.

## 15. Scoring Separation

Cooldown should not participate in scoring.

Redirected duplicate policy should only determine whether an effect row is created. Scoring remains in:

- `computeRaceState.js`
- `effectiveStepScoring.js`
- `effectMultiplier.js`
- race progress/scoring prefetch services

Do not add duplicate checks to scoring loops. If historical duplicates need protection, normalize already-loaded effect rows in memory.

## 16. Table Growth and Retention

### RaceActiveEffect

Rows grow with effects and AoE targets. Existing race/status and participant/status indexes support active paths. Rows are retained for race lifetime and may support attribution/expiration.

### RacePowerup

Rows grow with earned and used race-bound inventory. Race cascade behavior controls lifecycle.

### RacePowerupEvent

Append-heavy and indexed by race/time and actor/type/time. It should not be scanned for every cooldown check.

### Derived impact tables

`RaceImpactEvent` and `RaceEffectImpact` are historical/derived records and should remain outside hot availability queries.

### Usage state

Race-scoped cardinality is approximately:

```text
active/recent race participants × distinct shop power-up types used
```

Do not delete rows synchronously during race completion. Use bounded asynchronous cleanup if needed.

## 17. Redis Role

Redis should not be cooldown authority.

Possible uses:

- Cached race power-up projection.
- Notification/wakeup coordination.
- Optional short-lived display cache after measured DB pressure.

Activation must always validate PostgreSQL state. A single indexed lookup is likely cheaper and safer than adding Redis invalidation for every use.

## 18. Future Partitioning Readiness

Do not partition now.

Race-scoped usage state naturally has `raceId` as a future partition key. Global usage state naturally partitions by `userId`.

`RaceActiveEffect` already has race-oriented and participant-oriented indexes, which preserve future options. Avoid a design where only a global time-ordered history table can answer current availability.

## 19. Million-User Failure Modes

### Race-lock contention

Complex activations serialize through race and participant locks. Severity is high for popular large races. Reduce lock duration with bulk reads and in-memory policy evaluation before reconsidering lock scope.

### Global inventory hot rows

`UserPowerupItem(userId, powerupType)` serializes a user's concurrent spending of one type. This is desirable for correctness and local to that user.

### N+1 AoE lookups

Rainstorm is the clearest risk. Use bulk active-effect snapshots.

### Connection exhaustion

Long transactions holding locks consume pool capacity. Reduce synchronous work and bound concurrency.

### Event amplification

AoE produces recipient-level logical events. Batch durable writes and defer delivery.

### Large active-effect reads

`findActiveForRace()` may read all active effects. Prefer participant-targeted bulk reads when only final landings matter.

### Cleanup transactions

Avoid mass synchronous cleanup during race completion.

### Job explosion

Coalesce race resolution/invalidation jobs where correctness allows.

### Excess indexes

Every added index increases activation write cost. Add only indexes tied to real access paths.

### Deadlocks

Current deterministic participant ordering reduces risk. New cooldown locks must follow the existing order.

## 20. Scale Model

Define:

```text
D = DAU
U = shop uses per DAU per day
P = peak multiplier
S = SQL statements per activation
W = durable rows per activation
T = average AoE targets
```

Average activations/sec:

```text
D × U / 86,400
```

Hypothetical assumptions:

```text
U = 0.10 shop uses/user/day
P = 20x peak factor
```

| DAU | Average activations/sec | Hypothetical peak/sec |
|---:|---:|---:|
| 100,000 | 0.116 | 2.31 |
| 1,000,000 | 1.16 | 23.15 |
| 10,000,000 | 11.57 | 231.48 |

At 10 SQL statements per activation, the 10M DAU case would imply approximately 115.7 average SQL statements/sec and 2,315 at the hypothetical peak. These are illustrative calculations, not forecasts.

For AoE, effect row volume scales with targets. Query volume must not also scale linearly.

## 21. Large-Race Stress Model

| Race size | Maximum Rainstorm rows | Preferred defense reads | Risk |
|---:|---:|---:|---|
| 10 | 9 | 1 bulk read | Low |
| 50 | 49 | 1 bulk read | Moderate |
| 100 | 99 | 1 bulk read | High if per-target fallback |
| 500 | 499 | 1–few bulk reads | High due locks/transaction duration |

Power Outage already has a stronger bulk-read/bulk-write shape. Rainstorm should converge on it.

## 22. Observability Plan

Activation metrics:

```text
powerup_use_duration_ms
powerup_use_db_time_ms
powerup_use_transaction_retries
powerup_use_lock_wait_ms
powerup_use_outcome
```

AoE metrics:

```text
powerup_target_count
effect_rows_written
defense_rows_consumed
redirect_count
duplicate_noop_count
```

Cooldown metrics:

```text
cooldown_rejection_count
cooldown_scope
cooldown_lookup_duration_ms
```

Use bounded dimensions such as power-up type, outcome, race-size bucket, target-count bucket, platform, and client capability. Do not use user ID, race ID, power-up ID, or target ID as metric dimensions.

Database metrics should include DB CPU, active connections, lock waits, deadlocks, transaction rate, WAL volume, rows read/written, and normalized query latency.

## 23. Future Load-Test Plan

Do not run this audit as a load test. A future local or explicitly authorized staging benchmark should use a dedicated test database.

Scenarios:

1. Many independent small races.
2. Concentrated activation in one 100-person race.
3. Concentrated activation in one 500-person synthetic race.
4. Rainstorm burst.
5. Power Outage burst.
6. Decoy-heavy burst.
7. Same-user concurrent uses across races.
8. Same-user same-type concurrent uses.
9. Cooldown rejection burst.
10. Mixed direct and redirected duplicate attempts.

Measure p50/p95/p99, DB time, normalized query count, retries, lock waits, deadlocks, DB CPU, connections, effect rows/sec, and event rows/sec.

Correctness assertions must include no inventory overspend, no forbidden duplicate effects, preserved intentional stacking, unchanged original timestamps, deterministic concurrent outcomes, and one durable event per accepted use.

## 24. Architecture Options

### Option A — Minimal extension

Keep the current structure and add compact cooldown state, bulk effect snapshots, policy-aware final-landing evaluation, and existing transaction integration.

Complexity: low/moderate. DB cost: low. Migration risk: moderate. Scalability: good if AoE reads become bulk. Correctness risk: lowest.

### Option B — Central Power-Up Policy Engine

Introduce a runtime policy registry and shared activation phases.

Complexity: moderate/high. Scalability: good. Maintainability: potentially better. Risk: specialized mechanics could be generalized incorrectly.

Best as a gradual extension of Option A, not a rewrite.

### Option C — Event-derived availability

Use existing effects/events to derive cooldown state.

Low initial schema work, but poor hot-read scalability, ambiguous early termination, and weaker concurrency guarantees.

Not recommended.

### Option D — Redis-driven availability

Could reduce reads but weakens correctness and adds invalidation complexity. Not recommended as authority.

## 25. Recommended Target Architecture

```text
request
  -> begin PostgreSQL transaction
  -> choose lock plan
  -> claim/lock RacePowerup
  -> acquire race/participant locks
  -> bulk-load effects/defenses
  -> read compact cooldown state
  -> reject if unavailable
  -> resolve intended target(s)
  -> resolve Mirror/Decoy/Socks
  -> deduplicate final landing IDs
  -> apply per-type duplicate policy in memory
  -> bulk-create effects
  -> update cooldown state
  -> mark RacePowerup USED
  -> append durable event/outbox data
  -> commit
  -> notifications/cache/scoring wakeups after commit
```

Specific recommendations:

- Preserve current exclusive race guards for correctness-sensitive broad effects until measured otherwise.
- Eliminate per-final-target reads through one active-effect snapshot.
- Keep global inventory decrement atomic.
- Use mutable current cooldown state for availability.
- Preserve existing race power-up/event records for audit.
- Keep scoring independent of cooldown.
- Keep Redis optional and non-authoritative.

## 26. Exact Models / Files / Functions That Would Change

No changes should be made yet. Likely future touch points are:

Backend:

- `src/modules/powerups/commands/usePowerup.js`
  - `usePowerup()`
  - `usePowerupCore()`
  - `lockPowerupUseParticipants()`
  - `resolveAoEDecoySlots()`
  - `finalizeSelfContainedUse()`
- `src/modules/powerups/models/raceActiveEffect.js`
  - bulk active-effect reads and transaction-client support
- `src/modules/powerups/constants/powerupStackingGuide.js`
  - only if promoted into validated runtime policy
- `src/modules/powerups/queries/getPowerupInventory.js`
  - possible cooldown projection
- race detail/use-context projection queries
  - one bulk cooldown read
- `src/modules/domainEvents/commands/appendDomainEvent.js`
  - only if new metadata/event behavior is required

Database:

- `prisma/schema.prisma`
- additive migration for compact usage state and any proven cleanup index

Frontend:

- `lib/services/backend_api_service.dart`
- `lib/screens/race_detail_screen.dart`
- `lib/utils/powerup_error_copy.dart`
- relevant state models

Tests:

- Backend integration tests for concurrency, bulk query shape, and policy behavior.
- Frontend integration/widget tests for cooldown projection and stale-state handling.

## 27. Migration Strategy

No migration should be created during this audit.

If compact state is selected:

1. Add the table with additive-compatible fields.
2. Deploy schema before enabling writes.
3. Treat absent state rows as available.
4. Start writing state on new successful uses.
5. Backfill only if product requires legacy cooldown enforcement.
6. Do not infer old duration cooldowns unless timestamps are reliable.
7. Add bounded asynchronous cleanup after observing growth.
8. Preserve old-client compatibility.

Avoid synchronous mass deletion during race completion.

## 28. Risks

- Removing race locks prematurely could reintroduce scoring/participant races.
- Bulk reads must use the transaction client, not global Prisma.
- A policy registry could accidentally turn documentation categories into enforcement rules.
- Rainstorm cross-caster overlap must remain intact.
- Power Outage recipient skipping must remain distinct.
- Cooldown upsert without locking can permit bypass.
- Global inventory plus race-scoped cooldown can confuse users across races.
- New indexes increase activation write cost.
- Large AoE transactions remain O(targets) in rows and locks even after query reduction.
- Historical duplicate rows may require defensive scoring handling.
- Old clients may not show specialized cooldown messaging.

## 29. Open Product Decisions

1. Cooldown scope: global user/type or race/user/type.
2. Whether blocked attacks start cooldown.
3. Whether redirected duplicate no-ops start cooldown.
4. Whether cooldown continues after race end.
5. Whether both `activeUntil` and `nextUsableAt` should be exposed.
6. Whether cross-caster Rainstorm overlap remains intentional.
7. Whether skipped Power Outage recipients count as a successful use.
8. Whether usage-state rows are retained for audit or cleaned after race completion.
9. Whether redirected duplicate no-ops emit visible events.
10. Whether cooldown state is shown as a countdown.

## 30. Go / No-Go Recommendation for Implementation Design

Go for design work, but do not implement until product decisions are resolved.

The scale-safe direction is:

- PostgreSQL as authority.
- Existing transaction and lock model initially.
- Constant-query bulk reads for AoE defense/effect state.
- Policy-aware final-landing evaluation.
- Compact mutable cooldown state.
- Existing race power-up/event records for audit.
- Scoring independent of cooldown.
- Notifications and non-critical projections after commit.
- No Redis-only authority, global locks, event-derived availability, microservices, or premature partitioning.

Future implementation should first be validated with query-count and lock-wait instrumentation in a dedicated local/test environment before production consideration.
