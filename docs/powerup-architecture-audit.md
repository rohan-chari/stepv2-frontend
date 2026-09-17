# Bara Power-Up Architecture Audit

Research-only audit for the proposed redirected duplicate-effect fix and shop power-up post-use cooldown. No application code, tests, schema, migrations, or configuration were modified during this audit.

## 1. Executive Summary

The backend has a centralized activation command, `src/modules/powerups/commands/usePowerup.js`, a shared `RaceActiveEffect` table, race-bound `RacePowerup` inventory, global shop inventory, transactional activation locking, and dedicated scoring/expiration paths.

Duplicate behavior is policy-specific rather than generic. Existing guards cover many direct uses, but the final landing after Decoy/defense resolution is not protected consistently. Rainstorm creates a new effect after AoE Decoy resolution without a same-type check. Power Outage skips some already-outaged recipients in its custom AoE path. Wrong Turn has a direct guard and a reflected-target recheck, but no complete shared final-landing abstraction.

A blanket same-type uniqueness rule would change intentional behavior: Rainstorm overlap from different casters, Power Outage repeated casts, Trail Mine coexistence, Coin Flip stacking, Uprising merging, and specialized Leech/Hitchhike caps.

The safest Change #1 design is a policy-aware post-defense check immediately before effect creation, inside the existing activation transaction. Cooldowns currently exist only for Quick Rinse and Decoy post-pop. The global shop inventory has no general cooldown state. Duration-based cooldowns therefore likely require persistent DB state that records the actual effect end and cooldown end.

## 2. Power-Up Architecture

```text
POST /races/:raceId/powerups/:powerupId/use
  -> power-up route
  -> usePowerup()
  -> transactional locking wrapper
  -> usePowerupCore()
  -> validation
  -> target selection
  -> Mirror/Decoy/Socks resolution
  -> effect creation or instant resolution
  -> RacePowerup status USED
  -> RacePowerupEvent/domain events
  -> notifications/activity projection
  -> RaceActiveEffect-driven scoring
```

Important files:

- `backend/src/modules/powerups/commands/usePowerup.js` — activation, validation, target resolution, defense handling, consumption, events.
- `backend/src/modules/powerups/routes.js` — power-up HTTP routes.
- `backend/src/modules/powerups/models/raceActiveEffect.js` — effect persistence and active-effect queries.
- `backend/src/modules/powerups/models/racePowerup.js` — race-bound inventory rows.
- `backend/src/modules/powerups/models/userPowerupItem.js` — global shop inventory.
- `backend/src/modules/powerups/queries/getPowerupInventory.js` — global inventory reads.
- `backend/src/modules/powerups/queries/getRaceInventory.js` — race inventory reads.
- `backend/src/modules/powerups/commands/purchasePowerupItem.js` — shop purchase.
- `backend/src/modules/powerups/queries/getPowerupShopCatalog.js` — shop catalog.
- `backend/src/modules/races/services/effectiveStepScoring.js` — effect windows and scoring.
- `backend/src/modules/races/services/effectMultiplier.js` — multiplier precedence/stacking.
- `backend/src/modules/races/services/computeRaceState.js` — scoring state assembly.
- `backend/src/modules/powerups/commands/expireEffects.js` — effect expiry.
- `backend/src/modules/races/jobs/raceEffectDeadlineScheduler.js` — deadline scheduling.

PostgreSQL is authoritative for inventory, activation, effects, timestamps, and use history. Redis is used for cache/invalidation paths, not as the durable effect source.

## 3. Power-Up Catalog

The complete enum is `PowerupType` in `backend/prisma/schema.prisma`.

| Power-up | Shop | Timing | Target/polarity |
|---|---:|---|---|
| LEG_CRAMP | No | Duration | Hostile single target |
| RED_CARD | No | Instant | Hostile auto-leader |
| SHORTCUT | No | Instant | Friendly/transfer |
| COMPRESSION_SOCKS | No | Shield | Defensive self |
| PROTEIN_SHAKE | No | Instant | Friendly self |
| RUNNERS_HIGH | No | Duration | Friendly self |
| SECOND_WIND | No | Instant | Friendly self |
| STEALTH_MODE | No | Duration | Defensive self |
| WRONG_TURN | No | Duration | Hostile single target |
| FANNY_PACK | No | Duration | Friendly self |
| TRAIL_MIX | No | Instant | Friendly self/history |
| DETOUR_SIGN | No | Duration | Hostile single target |
| LUCKY_HORSESHOE | No | Trigger window | Friendly self |
| CAMPFIRE_REST | No | Duration | Self freeze/boost |
| TRAIL_MAGNET | No | Trigger window | Friendly self |
| POCKET_WATCH | No | Instant extension | Self/targeted mode |
| TRAIL_MINE | No | Trap/trigger | Position-based |
| PINECONE_TOSS | No | Instant | Hostile single target |
| SNEAKY_SWAP | No | Instant | Hostile inventory |
| MIRROR | No | Shield/trigger | Defensive self |
| CLEANSE | No | Instant | Friendly self |
| IMPOSTER | Yes, retired | Duration | Presentation/self metadata |
| RAINSTORM | Yes | 1 hour | Hostile AoE |
| SIGNAL_JAMMER | Yes | 1 hour | Hostile single target |
| LEECH | Yes | 30/60 minutes | Hostile transfer |
| DEFENSE_SCAN | Yes | Instant | Informational self |
| HITCHHIKE | Yes | 1 hour | Friendly transfer |
| QUICK_RINSE | Yes | Instant | Friendly cleanup self |
| QUICKSAND | Yes | Duration | Hostile multi-target freeze |
| UPRISING | Yes | 1 hour/merge | Friendly/team |
| GHOST_PEPPER | Yes | 30m boost + 30m freeze | Self |
| COIN_FLIP | Yes | 1 hour | Mixed self |
| MYSTERY_POTION | Yes | Rolled | Depends on result |
| DECOY | Yes | 24 hours | Defensive self |
| POWER_OUTAGE | Yes | 30 minutes | Hostile AoE |
| UMBRELLA | Yes | 12 hours | Defensive self |
| RALLY_FLAG | Yes | 1 hour | Friendly/team |
| DRILL_SERGEANT | Yes | 1 hour | Hostile challenge |
| PIGGY_BANK | Yes | 24 hours | Friendly self |
| BOUNTY | Yes | Race-end objective | Hostile single target |
| MYSTERY_BOX | No | Container | Inventory |

The explicit shop source of truth is `PowerupShopItem`, backed by `powerup_shop_items`. Runtime code also declares `SHOP_POWERUP_TYPES` in `usePowerup.js`.

## 4. Power-Ups Affected by Redirected Duplicate Bug

| Power-up | Redirectable | Current duplicate behavior | Change #1 |
|---|---:|---|---:|
| Rainstorm | Yes, AoE Decoy | Different casters may overlap; redirected landing lacks a final same-type check | Yes, preserving cross-caster policy |
| Wrong Turn | Yes | Direct and reflected checks exist; final Decoy landing needs a shared check | Yes |
| Power Outage | Yes, AoE Decoy | Already-outaged recipients are skipped in custom code | Yes, preferably policy-driven |
| Leg Cramp | Yes | Direct duplicate rejected; indirect conflicts with Wrong Turn | Yes |
| Signal Jammer | Yes | Direct duplicate rejected | Yes |
| Leech | Yes | One live Leech per victim | Yes, retaining specialized cap |
| Detour Sign | Yes | Direct active duplicate rejected | Yes |
| Hitchhike | Yes | One link per caster and target | Specialized cap, not blanket hostile rule |
| Quicksand | Not ordinary Decoy path | Explicit target validation | Separate treatment |
| Drill Sergeant/Bounty | Policy-specific | Challenge/objective records | Do not blanket-include |

## 5. Rainstorm Architecture

Rainstorm is an untargeted, shop-only AoE. It affects every other eligible enemy participant and creates one `RaceActiveEffect` row per victim.

Relevant constants:

```js
RAINSTORM_DURATION_MS = 60 * 60 * 1000
RAINSTORM_MULTIPLIER = 0.5
```

Flow:

```text
usePowerupCore()
  -> type === RAINSTORM validation
  -> findActiveForRace()
  -> reject if this caster already has an active storm
  -> collect enemy victims
  -> resolveAoEDecoySlots()
  -> Umbrella check
  -> Compression Socks check
  -> RaceActiveEffect.create(type=RAINSTORM)
  -> mark RacePowerup USED
  -> POWERUP_USED event and recipient events
```

Effect fields are `raceId`, `targetParticipantId`, `targetUserId`, `sourceUserId`, `powerupId`, `type`, `status`, `startsAt`, `expiresAt`, and metadata including `multiplier` and `stepsAtStart`.

The schema uniqueness constraint is only `@@unique([powerupId, targetParticipantId])`; it prevents one cast from writing twice to one participant but does not prevent different Rainstorm casts from creating rows for the same participant.

Scoring in `effectiveStepScoring.js` merges Rainstorm windows and clamps the penalty. Multiple casters can intentionally overlap without producing `0.5 * 0.5`.

## 6. Wrong Turn Architecture

Wrong Turn uses the targeted path in `usePowerup.js`:

```text
validate target
  -> direct duplicate/conflict checks
  -> Mirror resolution
  -> Decoy resolution
  -> Compression Socks resolution
  -> Wrong Turn case
  -> optionally clear Leg Cramp
  -> RaceActiveEffect.create(type=WRONG_TURN)
  -> event/notification
```

Duration is computed through `upgradedDuration("WRONG_TURN", upgradeLevel)`. The active row stores target/source identity, power-up ID, start/end timestamps, and `stepsAtStart`.

Direct duplicate validation uses `findActiveByTypeForParticipant(targetParticipant.id, "WRONG_TURN")`. Reflected attacks have an explicit second check because the final target becomes the original attacker. This proves that pre-defense checks are insufficient.

Wrong Turn conflicts with Leg Cramp. Direct uses reject the conflict; indirect Wrong Turn paths can resolve the existing Cramp boundary with `resolveTimedEffectBoundary()`.

## 7. Power Outage Architecture

Power Outage is a custom AoE path:

```text
collect enemy victims
  -> resolveAoEDecoySlots()
  -> deduplicate final landing participant IDs
  -> inspect active POWER_OUTAGE
  -> inspect Compression Socks
  -> createManyForTargets()
  -> POWERUP_USED event
  -> recipient events
  -> consume RacePowerup
```

`POWER_OUTAGE_DURATION_MS` is 30 minutes. Repeated casts are accepted, but already-outaged recipients are skipped. This is intentional and differs from Wrong Turn.

Power Outage therefore already contains part of the requested behavior, but the rule is embedded in the custom AoE implementation rather than expressed through a shared final-landing policy.

## 8. Other Hostile Duration Effects

- Leg Cramp: active freeze, direct duplicate blocked, conflicts with Wrong Turn and Quicksand, stored in `RaceActiveEffect`.
- Signal Jammer: one-hour shop debuff, direct duplicate blocked, prevents power-up use including Cleanse and Quick Rinse.
- Leech: one live effect per victim, specialized transfer scoring and expiry checkpoints, `LEECH_MAX_PER_VICTIM = 1`.
- Hitchhike: one link per caster and target, specialized copy scoring and attribution.
- Detour Sign: active presentation effect, direct duplicate blocked, redirectable.
- Quicksand: explicit multi-target freeze, not ordinary Decoy routing, rejects Quicksand/Leg Cramp targets.
- Drill Sergeant/Bounty: challenge/objective records and should not be treated as ordinary active debuffs without separate policy review.

## 9. Team Effect Architecture

Effects are participant-level, not team-level. Team membership controls eligibility through `RaceParticipant.team` and `isEnemy()`.

Rainstorm and Power Outage fan out into one `RaceActiveEffect` row per final participant. A later teammate does not inherit an earlier row; a departing teammate does not automatically remove one. Duplicate checks therefore operate per participant landing.

## 10. Decoy and Defensive Power-Ups

Targeted defensive order is:

```text
Mirror -> Decoy -> Compression Socks
```

Relevant functions:

- `pickDecoyRedirectVictim()`
- `resolveAoEDecoySlots()`
- `consumeDecoy()`
- `findActiveByTypeForParticipant()`

Decoy redirects at most once. A second Decoy on the redirected victim does not chain. If no eligible third-party victim exists, the attack fizzles and the Decoy is consumed. AoE resolution processes each original victim independently and deduplicates final landing IDs.

Shop power-ups are excluded from Mirror reflection via `SHOP_POWERUP_TYPES`. Rainstorm and Power Outage use AoE Decoy handling.

## 11. Root Cause of Redirected Duplicate-Effect Bug

Rainstorm trace:

```text
POST /races/:raceId/powerups/:powerupId/use
  -> routes.js
  -> usePowerup()
  -> runPrismaTransaction()
  -> lock race/powerup/participants
  -> usePowerupCore()
  -> collect victims
  -> resolveAoEDecoySlots()
  -> final landing determined
  -> Umbrella/Socks checks
  -> RaceActiveEffect.create(type=RAINSTORM)
```

There is no generic active same-type check between final landing resolution and `create()`.

Wrong Turn has direct and reflected checks, but not one shared final-landing abstraction. Power Outage has recipient skipping in its custom AoE loop.

## 12. Direct Duplicates vs Redirected Duplicates

- Rainstorm: same caster duplicate rejected; different casters may overlap; redirected duplicate is not uniformly rejected.
- Wrong Turn: direct duplicate rejected; reflected final target rechecked; Decoy path needs unified final check.
- Power Outage: repeated casts accepted; already-outaged recipients skipped.
- Leech: one live effect per victim across attackers.
- Many self buffs/shields: one active copy blocked.

Do not change direct behavior generically until each stacking policy is preserved.

## 13. Existing Effect Stacking Rules

Canonical policy documentation: `src/modules/powerups/constants/powerupStackingGuide.js`.

Important rules:

- Rainstorm: `LIMITED`; one per caster, cross-caster overlap allowed, scoring clamped.
- Power Outage: `LIMITED`; repeated casts accepted, already-outaged recipients skipped.
- Wrong Turn/Leg Cramp/Signal Jammer/Quicksand: `BLOCKED`.
- Leech: `BLOCKED` per victim.
- Hitchhike: `LIMITED` per caster and target.
- Trail Mine: multiple independent mines allowed.
- Uprising: `EXTENDS`/merges.
- Coin Flip: `ALLOWED` stacking.
- Decoy: one active copy plus post-pop cooldown.
- Quick Rinse: instantaneous hourly cooldown.

The guide documents mechanics but is not itself a universal enforcement layer.

## 14. Scoring Impact of Duplicate Effects

Rainstorm rows are extracted and merged by `effectiveStepScoring.js`; overlapping windows are clamped, not compounded. Historical duplicates can still create redundant rows and attribution work.

Wrong Turn is a precedence/negation effect; duplicate rows can create redundant windows and reads even if the final multiplier is not multiplied.

Power Outage rows are redundant for use blocking and increase active-effect reads.

Leech/Hitchhike duplicates can compound transfer/copy work and therefore require their existing source/target caps.

Preferred approach: prevent new duplicates at activation. Avoid adding per-effect duplicate queries in scoring loops. Consider defensive scoring deduplication only after confirming historical duplicate data.

## 15. Shop and Inventory Architecture

Shop catalog and purchase files:

- `PowerupShopItem`
- `PowerupCopy`
- `getPowerupShopCatalog()`
- `purchasePowerupItem()`

Global inventory is:

```prisma
UserPowerupItem {
  userId
  powerupType
  quantity
  @@unique([userId, powerupType])
}
```

Using a shop item decrements global quantity, creates/redeems a race-bound `RacePowerup`, then uses the normal race flow. The race row becomes `USED` with `usedAt`.

There is no general `PowerupUsage` or `PowerupCooldown` model.

## 16. Duration vs Instant Power-Ups

Duration shop effects include Rainstorm, Signal Jammer, Leech, Hitchhike, Quicksand, Uprising, Ghost Pepper, Decoy, Power Outage, Umbrella, Rally Flag, Drill Sergeant, Piggy Bank, and Bounty.

Instant shop effects include Defense Scan, Quick Rinse, Pocket Watch, Cleanse, and Mystery Potion resolution. Not every effect creates a timed `RaceActiveEffect`; Quick Rinse explicitly creates none.

## 17. Existing Cooldown Infrastructure

Quick Rinse uses `QUICK_RINSE_COOLDOWN_MS` and derives the race-scoped cooldown from `POWERUP_USED` history. Decoy uses `DECOY_POST_POP_COOLDOWN_MS` plus `RaceActiveEffect.decoyConsumedAt` and an index.

There is no general cooldown infrastructure for shop power-ups.

## 18. Recommended Cooldown Data Model

A persistent model is safer than reconstructing duration cooldowns from events:

```text
PowerupCooldown
  id
  userId
  powerupType
  raceId?
  usedAt
  effectStartedAt?
  effectEndedAt?
  cooldownEndsAt
  sourcePowerupId?
  createdAt
```

A current-state row could be cheaper, but a history table is better for auditing and analytics. The final choice depends on scope.

## 19. Cooldown Scope Options

| Scope | Fit | Main risk |
|---|---|---|
| user + type | Global restriction | Blocks use in another race |
| user + race + type | Matches Quick Rinse | Allows use in another race |
| inventory item | Per-copy state | Conflicts with quantity-by-type inventory |
| existing event/effect history | Minimal schema | Cannot reliably anchor duration end |
| dedicated cooldown row | Persistent/clear | Migration and concurrency work |

The current architecture most naturally supports `userId + raceId + powerupType`, but product intent does not conclusively decide this.

## 20. Cooldown Edge Cases

Current semantics are clear for ordinary invalid target failures and ordinary blocked defenses: invalid uses generally remain held; blocked attacks generally consume the attacker item. They are not clear for whether a redirected duplicate no-op starts cooldown.

Other unresolved cases include race ending before effect expiry, early cancellation, manually removed effects, worker delay, configuration duration changes, and simultaneous uses. DB timestamps survive restart; workers are not required for a timestamp comparison.

## 21. API Impact

Use endpoint:

```text
POST /races/:raceId/powerups/:powerupId/use
```

Frontend wrapper: `lib/services/backend_api_service.dart`, `usePowerup()`.

Frontend caller: `lib/screens/race_detail_screen.dart`, `_usePowerup()`.

Recommended additive cooldown response:

```json
{
  "cooldownEndsAt": "2026-09-16T15:00:00.000Z",
  "unavailableReason": "POWERUP_COOLDOWN"
}
```

Use stable server error codes and keep old clients functional without requiring new request fields.

## 22. Frontend Impact

Relevant files:

- `lib/screens/race_detail_screen.dart`
- `lib/services/backend_api_service.dart`
- `lib/utils/powerup_error_copy.dart`
- `lib/widgets/attack_outcome_modal.dart`
- `lib/demo/demo_race_engine.dart`
- `lib/demo/demo_race_api_service.dart`
- tutorial fixtures under `lib/tutorial`

The frontend currently renders inventory/effects and handles server errors, but has no general shop cooldown UI. A future change should add timestamp parsing, matching-type disabled state, optional countdown, refresh after use, and defensive handling of missing fields. Backend enforcement remains authoritative.

## 23. Notifications and Activity Feed

Existing event types include `POWERUP_USED`, `POWERUP_BLOCKED`, and `POWERUP_REFLECTED`. Redirect information is carried in use responses and event metadata. Rainstorm and Power Outage create aggregate activity plus recipient events.

There is no dedicated redirected-duplicate event. Possible additive metadata is `redirected`, `redirectedBy`, `duplicateCancelled`, and `duplicateType`. Visibility to attacker, target, Decoy owner, and team remains a product decision.

## 24. Inventory Consumption Semantics

Successful use conditionally changes `RacePowerup.status` from `HELD` to `USED` and sets `usedAt`. The conditional update prevents double use. Invalid validation normally leaves the row held. Redeemed shop items have refund-on-rejection logic through `refundRedeemedOnRejection()`.

Whether a redirected duplicate no-op consumes the item, refunds it, or records a consumed-but-cancelled use is unresolved.

## 25. Concurrency and Transaction Safety

Activation uses Prisma transactions, race fences, race locks, conditional power-up claims, participant locks ordered by user ID, and defense/effect snapshots. A generic duplicate check must execute inside this transaction while the relevant participant rows are locked.

The existing `@@unique([powerupId, targetParticipantId])` constraint does not prevent two different power-up rows from creating same-type effects for one participant.

## 26. Worker / Redis / Cache Impact

Expiration uses `expireEffects.js` and `raceEffectDeadlineScheduler.js`. Active effects remain PostgreSQL truth. Preventing a duplicate before creation should not require scoring cache changes, though ordinary race/inventory invalidation remains necessary.

Cooldowns should be DB-authoritative. Redis can cache availability but must not be the only durable copy.

## 27. Performance Impact

Duplicate checks should happen during activation, not in scoring loops. Rainstorm currently performs per-landing defense lookups; a new check should reuse prefetched effects where possible. Existing useful indexes include `(targetParticipantId, status)`, `(raceId, status)`, and `(targetParticipantId, type, decoyConsumedAt)`.

## 28. Test Coverage

Relevant backend suites include:

- `test/integration/powerups-shop-defenses.test.js`
- `test/integration/powerup-shared-race-guards.test.js`
- `test/commands/teamRacePowerups.test.js`
- `test/commands/newPowerups.test.js`
- `test/commands/detourSign.test.js`
- `test/integration/quicksand-powerup.test.js`
- `test/integration/race-effect-deadlines.test.js`
- `test/integration/red-card-cap.test.js`
- `test/utils/signedMultiplierAt.test.js`
- `test/utils/globalStepEventBoost.test.js`
- `test/http/powerup-store.test.js`

Missing tests include redirected duplicates for Rainstorm, Wrong Turn, and Power Outage; preservation of original timestamps; no duplicate scoring/impact event; direct duplicate regression behavior; simultaneous attempts; duration-end cooldown anchoring; exact boundary behavior; cross-race scope; and blocked/no-op cooldown policy.

## 29. Recommended Implementation Point for Redirected Duplicates

Use a shared, policy-aware helper in the power-up activation domain, called after final Mirror/Decoy resolution and immediately before `RaceActiveEffect.create()` or `createManyForTargets()`.

Inputs should include effect type, final participant, source/attack mode, redirect status, current time, and optionally prefetched active effects.

Do not implement this as a universal DB uniqueness constraint. Preserve specialized policies for Rainstorm, Power Outage, Leech, Hitchhike, Uprising, Coin Flip, and Trail Mine.

## 30. Recommended Implementation Point for Cooldowns

Enforce cooldown in `usePowerupCore()` after ownership/status validation but before effect mutation and consumption. Validation, cooldown write, power-up claim, and effect creation must share the same transaction.

Expose cooldown state through inventory/race projections and use responses. Update `backend_api_service.dart`, `race_detail_screen.dart`, and `powerup_error_copy.dart` defensively.

## 31. Files Likely To Change

| File | Change #1 | Cooldown | Risk |
|---|---:|---:|---:|
| `backend/src/modules/powerups/commands/usePowerup.js` | Yes | Yes | High |
| `backend/src/modules/powerups/models/raceActiveEffect.js` | Maybe | No/maybe | Medium |
| `backend/src/modules/powerups/constants/powerupStackingGuide.js` | Maybe | No | Medium |
| `backend/prisma/schema.prisma` | No | Likely | High |
| New cooldown migration/model | No | Likely | High |
| `backend/src/modules/powerups/queries/getPowerupInventory.js` | No | Likely | Medium |
| Race detail/projection query files | No | Likely | Medium |
| `frontend/lib/services/backend_api_service.dart` | No | Yes | Medium |
| `frontend/lib/screens/race_detail_screen.dart` | No | Yes | Medium |
| `frontend/lib/utils/powerup_error_copy.dart` | No | Yes | Low |
| Backend integration tests | Yes | Yes | High |

## 32. Risks / Backwards Compatibility

Backend-first deployment is feasible because new response fields can be additive and old clients already handle server-side use failures. Risks include changing Rainstorm’s intentional cross-caster overlap, leaving old duplicate rows, choosing the wrong cooldown scope, and producing poor messaging for old clients.

## 33. Historical Duplicate Effect Handling

The schema permits historical duplicates across different power-up IDs. Rainstorm scoring already merges/clamps overlapping windows, suggesting overlap may be expected. Before implementation, inspect production only through approved read-only tooling. Do not assume cleanup or add a destructive migration.

## 34. Analytics / Telemetry Impact

Existing activation, blocked, redirected, and purchase events can be extended with metadata such as `duplicateCancelled`. A dedicated event is optional. Cooldown rejection should have a stable code such as `POWERUP_COOLDOWN`.

## 35. Product Decisions Needed Before Implementation

1. Is cooldown global or race-scoped?
2. Does a blocked attack start cooldown?
3. Does a redirected duplicate no-op start cooldown?
4. Does the original attacker own the cooldown after redirect?
5. Should direct duplicate behavior remain type-specific?
6. Should cross-caster Rainstorm overlap remain allowed?
7. Does a skipped Power Outage recipient count as a used effect?
8. Does cooldown continue after race end?
9. Should cooldown be visible as a countdown?

## 36. Suggested Implementation Order

1. Resolve cooldown scope and blocked/no-op semantics.
2. Add integration tests first for Rainstorm, Wrong Turn, Power Outage, direct duplicates, and concurrency.
3. Implement a policy-aware final-landing duplicate guard inside the activation transaction.
4. Reuse prefetched active effects in AoE paths.
5. Verify original timestamps and scoring/notification behavior remain unchanged.
6. Design and migrate persistent cooldown state.
7. Enforce cooldown atomically in `usePowerupCore()`.
8. Add additive API fields and stable errors.
9. Update frontend state and error presentation defensively.
10. Add duration-based, instantaneous, cross-race, race-end, blocked, redirected, and concurrent cooldown tests.
11. Run backend integration tests against a dedicated test database, then frontend tests and analysis.

## Final Research Conclusion

Change #1 should be fixed after final defense resolution through a shared policy-aware activation helper, not a universal same-type database constraint. Change #2 needs persistent, transactionally enforced cooldown state; Quick Rinse is a useful precedent for instantaneous race-scoped cooldowns, but it is insufficient for duration-based cooldowns anchored to actual effect end time.
