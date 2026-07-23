# Powerups Wave 5 — Requirements Spec

Status: DRAFT — pending owner approval. Source ideas: `docs/powerup-ideas-catalog.md`.

## 1. Summary & user story

Add 11 new powerups behind a new `powerups5` client-feature token: **Uprising,
Ghost Pepper, Coin Flip, Mystery Potion, Decoy, Power Outage, Umbrella, Rally
Flag, Drill Sergeant, Piggy Bank, Bounty**. All are store-only purchases (no
drop-pool entries this wave). They add four missing motifs to the store:
comeback mechanics, gambles, new defenses, and economy items.

*As a racer who is losing, I want comeback tools (Uprising) so I stay engaged.
As a competitive racer, I want new attacks/defenses (Power Outage, Decoy,
Umbrella, Drill Sergeant, Bounty) so races stay dramatic. As a casual player,
I want cheap thrills (Coin Flip, Mystery Potion, Ghost Pepper) and ways to earn
coins by walking (Piggy Bank).*

## 2. Scope / non-goals

**In scope:** 11 new `PowerupType` enum values, store catalog entries, use-time
logic, scoring/settlement integration, expiry-time hooks (Drill Sergeant, Piggy
Bank), settlement hook (Bounty, Piggy Bank early-settle), one new shield
resolution step (Decoy), one new AoE jam (Power Outage), frontend shop/copy/
icons/target-pickers/outcome-modal, `powerups5` gating end-to-end, tests.

**Non-goals:** no drop-pool (mystery box) changes; none of the new types are
upgradeable this wave (`upgradeableTypes` untouched); no new endpoints; no
changes to existing powerups' behavior except the three explicit touch points
(jam check, shield chain, rainstorm merge); Tether/anything Tier C; Android/iOS
store pricing (coins only).

## 3. The 11 powerups — exact behavior

Prices are seed values; live price is admin-tunable (seed update block does not
clobber `priceCoins`/`active` — `prisma/seed.js:259-264`).

| # | Type | Name | Price | Target | Duration | Shape |
|---|---|---|---|---|---|---|
| 1 | `UPRISING` | Uprising | 300 | AoE (bottom half, incl. caster) | 2h | windowed 2x buff, multi-row |
| 2 | `GHOST_PEPPER` | Ghost Pepper | 75 | self | 30min boost + 30min freeze | two-phase (Campfire inverted) |
| 3 | `COIN_FLIP` | Coin Flip | 40 | self | 1h | windowed 2x OR 0.5x (server roll) |
| 4 | `MYSTERY_POTION` | Mystery Potion | 40 | varies (rolled) | varies | use-time roll → existing effect |
| 5 | `DECOY` | Decoy | 150 | self (held shield) | until consumed or 24h | shield: redirect next attack |
| 6 | `POWER_OUTAGE` | Power Outage | 150 | AoE (all enemies) | 30min | jam, multi-row |
| 7 | `UMBRELLA` | Umbrella | 75 | self | 12h | AoE-debuff immunity |
| 8 | `RALLY_FLAG` | Rally Flag | 150 | own team (team races only) | 1h | windowed 1.25x buff, multi-row |
| 9 | `DRILL_SERGEANT` | Drill Sergeant | 150 | one enemy | 2h | dare, evaluated at expiry |
| 10 | `PIGGY_BANK` | Piggy Bank | 40 | self | 24h | coin mint at expiry/settlement |
| 11 | `BOUNTY` | Bounty | 75 | one enemy ahead of caster | until race end | placement wager, settled at settlement |

### 3.1 Uprising
- Usable only while the caster is in the **bottom half** of standings. FFA:
  rank participants (accepted, not forfeited/finished) by effective steps desc
  via the `sortedActiveParticipants` helper (`usePowerup.js:244-259`); caster's
  rank must be `> ceil(n/2)` (with n≥3; in a 2p race, caster must be 2nd).
  Ties broken as the existing rank helper does. **Team races: usable only by a
  member of the currently-losing team (team scoreline via
  `buildTeamsBlock`); beneficiaries = entire losing team.**
- Creates one `UPRISING` effect row per beneficiary (bottom-half racers
  including the caster in FFA; the losing team in team races), `targetUserId` =
  beneficiary, `sourceUserId` = caster, metadata `{ "multiplier": 2 }`, 2h.
- Beneficiary set is snapshotted at activation; no re-evaluation mid-effect.
- **Stacking:** per-beneficiary windows MERGE (Rainstorm's per-victim merge
  pattern, `mergeRainstormWindows` precedent) — two Uprisings never exceed 2x.
  Overlap with `RUNNERS_HIGH`/`CAMPFIRE_REST` boost takes **max, not sum**
  (existing Campfire×RH precedent in `effectiveStepScoring.js:159-183`).
- Not blockable/reflectable (it is a buff; shield chain only runs for
  `OFFENSIVE_TYPES`). Jam (Signal Jammer/Power Outage on the caster) blocks
  use, like all powerups.

### 3.2 Ghost Pepper
- Self-only. Single effect row, `expiresAt = now + boostMs + freezeMs`,
  metadata `{ "boostMs": 1800000, "multiplier": 3, "freezeMs": 1800000,
  "stepsAtBoostStart": <snapshot> }` — CAMPFIRE_REST's mechanism
  (`usePowerup.js:1825-1853`) with the phases swapped: boost window =
  `[startsAt, startsAt+boostMs)`, freeze window = `[startsAt+boostMs,
  expiresAt)`.
- Scorer: boost phase adds `(multiplier−1)×steps` to `buffedSteps`; freeze
  phase adds steps to `frozenSteps`. Overlaps: boost phase takes max with
  RH/Campfire/Uprising/Rally Flag (never multiplicative); freeze phase behaves
  exactly like LEG_CRAMP freeze in every overlap rule (freeze beats buff, rain
  suspended during freeze).
- The freeze phase is **self-inflicted**: NOT removable by Cleanse or Quick
  Rinse (both act only on opponent-sourced debuffs; `sourceUserId` = self
  ensures the existing filters skip it — verify in tests).

### 3.3 Coin Flip
- Self-only. Server rolls 50/50 at use-time. Single `COIN_FLIP` row, 1h,
  metadata `{ "multiplier": 2 }` (win) or `{ "multiplier": 0.5 }` (lose).
- Scorer: `multiplier > 1` → buff branch, `(m−1)×steps` to `buffedSteps`,
  max-not-sum with other boosts; `multiplier < 1` → Rainstorm-style additive
  reduction `(1−m)×steps` folded into `frozenSteps`, merged with any Rainstorm
  window on the same user (never below 0.5x combined — reuse the rain merge).
  The Umbrella overlap subtraction (§3.7) applies ONLY to opponent-sourced
  RAINSTORM rows, never to a self-sourced COIN_FLIP window.
- Use response adds `"flip": "WIN" | "LOSE"` and `"multiplier"` so the client
  can play the win/lose moment.
- Lose outcome is self-inflicted → not Cleanse/Quick Rinse-removable (same
  rule as Ghost Pepper). Umbrella does NOT protect against it (not an AoE
  debuff from an opponent).

### 3.4 Mystery Potion
- Self-activated, no target picker. Server rolls one outcome from a weighted
  pool stored in balance config (new `config.mysteryPotion.pool` — see §6).
  Launch pool (owner-set mix: 50% helpful / 25% attacks a random enemy /
  15% defense-jackpot / 10% self-harm), weights in parentheses:
  - Helpful (50): `PROTEIN_SHAKE` (30), `RUNNERS_HIGH` (20)
  - Attack random enemy (25): `PINECONE_TOSS` (10, random direction),
    `LEG_CRAMP` on a random alive enemy (10), `SHORTCUT` on a random alive
    enemy (5)
  - Defense/jackpot (15): `COMPRESSION_SOCKS` (10), coin refund of 2× price (5)
  - Self-harm (10): `LEG_CRAMP` on SELF (5), `WRONG_TURN` on SELF (5) — both
    `sourceUserId` = self, so like Ghost Pepper's crash they are NOT
    Cleanse/Quick Rinse-removable.
- Rolled offensive outcomes route through the **normal apply path** — the same
  internal helpers `usePowerup.js` uses for that type — so Mirror/Socks/Decoy
  on the rolled victim, team `isEnemy` filtering, and event emission all apply
  unchanged. The created effect rows carry the ROLLED type (existing enums),
  so old clients render them natively.
- Use response adds `"rolled": "<TYPE>"` plus the rolled type's normal result
  fields; `"rolled": "COIN_REFUND"` with `"coins"` for the refund outcome
  (refund via `awardCoins`, reason `mystery_potion_refund`, refId = the
  RacePowerup id).
- Edge: rolled enemy-targeted outcome with no eligible enemy (all forfeited)
  → re-roll into the self-only subset. If a rolled outcome is invalid for any
  other reason (e.g. rolled COMPRESSION_SOCKS while one is already active and
  stacking rules would reject it) → fall back to `PROTEIN_SHAKE`. A potion use
  must never fail after the item is consumed.

### 3.5 Decoy
- Self-only held shield, 24h row (`DECOY`), hidden from opponents (add to
  `HIDDEN_FROM_OPPONENTS`, `getRaceProgress.js:71-78`).
- **Shield chain order: Mirror → Decoy → Socks** (new pre-check block modeled
  on the Mirror block at `usePowerup.js:972-1027`, placed after it). Decoy
  triggers for the same attack set Socks blocks: `OFFENSIVE_TYPES` **plus**
  `SHOP_POWERUP_TYPES` single-target attacks (Imposter/Leech/Hitchhike/Signal
  Jammer) — i.e. Mirror-proof attacks are still Decoy-able, matching Socks
  semantics. AoE attacks (Rainstorm, Power Outage, Quicksand multi-target) are
  NOT redirected (per-victim socks rules apply there instead; Decoy is
  consumed only by single-target attacks).
- On trigger: expire the Decoy row, pick a new victim uniformly at random from
  alive participants excluding the attacker and the Decoy holder (team races:
  excluding the Decoy holder's teammates — redirect must land on an enemy of
  the attacker's original intent, i.e. any alive racer on the holder's enemy
  side... see Decision D3 in §11). If no eligible third party exists (2-player
  race), Decoy behaves as a block (attack fizzles, decoy consumed).
- The redirected victim gets the full normal treatment **including their own
  Mirror/Socks** (one redirect max — a second Decoy on the new victim does
  not chain; it is skipped to prevent loops). This includes SNEAKY_SWAP: a
  redirected steal robs the new victim — chaotic but consistent, keep it.
- Attacker response: `{ redirected: true, redirectedBy: "DECOY",
  redirectedToUserId, outcome: "REDIRECTED", ... }` (new outcome value —
  frontend modal case added; old-client fallback in §7).

### 3.6 Power Outage
- AoE jam: one `POWER_OUTAGE` row per alive enemy (`isEnemy` filter,
  `usePowerup.js:448-449`), 30min.
- The jam check that currently looks for an active `SIGNAL_JAMMER` on the
  acting user extends to `type IN (SIGNAL_JAMMER, POWER_OUTAGE)`.
- Per-victim Compression Socks exemption, exactly like the Rainstorm loop
  (`usePowerup.js:1543-1566`): a Socks holder is skipped (shield consumed,
  counted in `blockedCount`). Victims already jammed are skipped (windows do
  not extend); response includes `affected` / `blockedCount` like Rainstorm.
- Mirror does not reflect it (AoE; also add to `SHOP_POWERUP_TYPES`-equivalent
  exclusion). Umbrella-immune (§3.7).

### 3.7 Umbrella
- Self-only, 12h row (`UMBRELLA`), hidden from opponents
  (`HIDDEN_FROM_OPPONENTS`).
- Grants immunity to **AoE debuffs only**: at use-time, an Umbrella holder is
  skipped by Rainstorm and Power Outage fan-out (checked in the per-victim
  loops, before Socks — Umbrella is not consumed; it is a timed aura, Socks
  stays intact for targeted attacks).
- Scorer: for RAINSTORM windows already active when the Umbrella is raised,
  subtract the overlap of `[umbrella.startsAt, umbrella.expiresAt]` from the
  victim's merged rain window (one more overlap-subtraction loop in the rain
  merge, `effectiveStepScoring.js:274-345`, mirrored in `multiplierForTime`,
  `raceStateResolution.js:273-323`).
- Does NOT protect against targeted attacks, self-inflicted debuffs (Ghost
  Pepper crash, Coin Flip lose), or Uprising (a buff).

### 3.8 Rally Flag
- Usable **only in team races** (`race.isTeamRace`; otherwise 400
  `INVALID_TARGET` "Rally Flag needs a team race"). Self-activated, no picker.
- One `RALLY_FLAG` row per accepted, alive member of the caster's team
  (including the caster), metadata `{ "multiplier": 1.25 }`, 1h.
- Stacking: per-beneficiary merge (two flags never exceed 1.25x); combined
  with RH/Campfire/Ghost Pepper boost/Uprising takes **max** of active
  multipliers, not sum.
- Not blockable/reflectable (buff). Jam on the caster blocks use.

### 3.9 Drill Sergeant
- Targeted (`TARGETED_TYPES`), offensive (`OFFENSIVE_TYPES` — Mirror can
  reflect it, Socks/Decoy apply). Not a shop-excluded type: it IS
  Mirror-reflectable (unlike Leech et al).
- Effect row on target, 2h, metadata `{ "goalSteps": 3000, "penaltySteps":
  1500, "stepsAtStart": <snapshot> }`.
- Target sees the dare in `activeEffects` (normal visibility) and receives a
  push (`POWERUP_ATTACK`-family payload; new copy). The countdown renders in
  race detail like other timed debuffs.
- **Evaluation at expiry** (new branch in `expireEffects.js:16-70`, the first
  substantive expiry-time work alongside Piggy Bank): sum target's steps in
  `[startsAt, expiresAt]` via `StepSample.sumStepsInWindow` (snapshot-diff
  fallback when no samples). The branch first checks the race: if it
  ended/settled/voided before `expiresAt`, the dare is VOID (no penalty).
  Otherwise `< goalSteps` → apply an instant penalty of
  `penaltySteps` using the Red Card bonus-subtraction mechanism
  (`usePowerup.js:1363-1381` pattern), floored at 0 like Pinecone; write an
  event so both parties see the outcome. `>= goalSteps` → dare survived, no
  effect (event records success).
- **Race ends before expiry → dare is VOID** (no penalty, event records void).
  Settlement therefore ignores un-expired dares; no `multiplierForTime`
  involvement (it never multiplies anything).

### 3.10 Piggy Bank
- Self-only, 24h row (`PIGGY_BANK`), metadata `{ "stepsPerCoin": 300,
  "coinCap": 80, "stepsAtStart": <snapshot> }` (values frozen at use-time from
  env so mid-flight tunes don't change live piggies).
- Env-tunable like ad rewards (`src/modules/economy/adRewards.js:40-45`
  pattern): `PIGGY_BANK_STEPS_PER_COIN` (default 300), `PIGGY_BANK_COIN_CAP`
  (default 80). Seed price 40.
- **Mint at the earlier of expiry or race settlement**: new branch in
  `expireEffects.js` and in settlement (`raceExpiry` path) — compute
  `min(floor(windowSteps / stepsPerCoin), coinCap)` from samples (snapshot
  fallback) over `[startsAt, min(expiresAt, raceEndedAt)]`, then
  `awardCoins({ reason: "piggy_bank", refId: effect.id })` —
  `awardCoins`' refId idempotency (`src/shared/economy/awardCoins.js`)
  guarantees exactly-once even if both paths run.
- **Only one ACTIVE Piggy Bank per user GLOBALLY, across all races** (owner
  decision, revised D8): the use-time check queries for any ACTIVE
  `PIGGY_BANK` effect for this user in ANY race → 409 (message names the
  blocking race). This kills the multi-race same-steps faucet exploit — no
  global mint cap needed. Not an attack; invisible to opponents
  (`HIDDEN_FROM_OPPONENTS`).
- Economy: break-even at 12,000 steps; max net +40/user/day (single piggy by
  rule). Curve: 5k→16, 10k→33, 12k→40 (break-even), 20k→66, 24k+→80 (cap).

### 3.11 Bounty
- Targeted at **one enemy currently ahead of the caster** in standings (400 if
  target is behind/tied, mirroring Red Card's leader guard style).
- Row lives until race end (`expiresAt = race.endsAt`; time-based races only —
  400 on target-step races, which have no fixed end). **Publicly visible** to
  all participants (NOT in `HIDDEN_FROM_OPPONENTS`) — the social pressure is
  the mechanic.
- Not blockable, not reflectable, not Decoy-able (it creates no debuff on the
  target — exclude from the shield chain trigger sets). Jam blocks placing it.
- **Settlement hook** (in the settlement path with a `raceStateResolution.js`
  parity guarantee): if the caster's final placement is strictly better than
  the target's (forfeit/DNF counts as "behind"), mint `BOUNTY_PAYOUT_COINS`
  (env, default 150) to the caster via `awardCoins({ reason: "bounty_payout",
  refId: effect.id })`. Otherwise nothing. Voided races → no payout.
- One active Bounty per caster per race (409 on second). **Disabled in team
  races** (400 — team settlement is by team, individual placement wagers don't
  map cleanly; revisit later).
- **Expiry-vs-settlement race:** `expireEffects` may flip the row to EXPIRED
  before settlement runs (late settles happen). The settlement hook must read
  Bounty rows regardless of ACTIVE/EXPIRED status; `awardCoins` refId
  idempotency makes double-processing harmless.
- Economics: price 75, payout 150 — positive-EV only if you out-place someone
  ahead of you more often than 50% of the time; it's a skill wager, net coin
  flow ≈ neutral-to-small-faucet. Env-tunable.

## 4. API contract (backend owns; frontend consumes verbatim)

**No new endpoints.** All three existing routes gain behavior only behind the
new feature token.

### 4.1 Feature token
- New token `powerups5`, parsed like the others: `powerupGating.js` gains
  `POWERUPS5_GATED_TYPES = [all 11 new types]`; `getPowerupShopCatalog.js`
  filter + `shop.js:38-44` gain `supportsPowerups5:
  req.clientFeatures.has("powerups5")`; `usePowerup.js` rejects use of a
  wave-5 held item from a non-powerups5 client with the existing
  `UPDATE_REQUIRED` 400 code.
- Frontend appends `,powerups5` to both header strings in
  `backend_api_service.dart:118-120`.

### 4.2 `GET /shop/powerups`
Unchanged shape (`getPowerupShopCatalog.js:82-93`). With `powerups5` present,
`items` additionally contains the 11 new SKUs (`POWERUP_UPRISING`, …,
`POWERUP_BOUNTY`), each `{ sku, name, description, priceCoins, powerupType,
ownedQuantity }`. Without the token, they are filtered out — old clients see
an identical catalog to today.

### 4.3 `POST /shop/powerups/purchase`
Unchanged (`shop.js:53-71`). Add the same powerups4-style guard
(`shop.js:55-57` pattern) rejecting wave-5 `powerupType`/`sku` purchases from
non-powerups5 clients.

### 4.4 `POST /races/:raceId/powerups/:powerupId/use`
Wave-5 items follow the **exact same shop-inventory → in-race held item → use
flow as existing shop powerups** (RAINSTORM/LEECH et al) — the backend agent
must mirror LEECH's inventory/equip mechanics verbatim, no new flow.

Request body unchanged; `targetUserId` required for `DRILL_SERGEANT` and
`BOUNTY` (both added to `TARGETED_TYPES`); all others self/AoE (added to
`SELF_ONLY_TYPES` where applicable: GHOST_PEPPER, COIN_FLIP, MYSTERY_POTION,
DECOY, UMBRELLA, PIGGY_BANK; UPRISING/RALLY_FLAG/POWER_OUTAGE are targetless
like RAINSTORM).

Response: base `{ blocked, upgradeLevel, coinsSpent, outcome }` envelope
(`usePowerup.js:1145-1152`) with per-type additions:
- `UPRISING`: `{ affected, effect }` (count + own row)
- `GHOST_PEPPER` / `UMBRELLA` / `PIGGY_BANK` / `DECOY`: `{ effect,
  durationMs }`
- `COIN_FLIP`: `{ effect, durationMs, flip: "WIN"|"LOSE", multiplier }`
- `MYSTERY_POTION`: `{ rolled: "<TYPE>"|"COIN_REFUND", ...rolled type's
  fields }`
- `POWER_OUTAGE`: `{ affected, blockedCount, durationMs }`
- `RALLY_FLAG`: `{ affected, effect, durationMs }`
- `DRILL_SERGEANT`: `{ effect, durationMs, goalSteps, penaltySteps }`
- `BOUNTY`: `{ effect, payoutCoins }`
- New attack outcome (any attacker whose single-target attack hits a Decoy):
  `{ redirected: true, redirectedBy: "DECOY", redirectedToUserId, outcome:
  "REDIRECTED" }`.

Error cases reuse existing codes/statuses (`routes.js:731-736`): 400
INVALID_TARGET (Bounty target not ahead; Rally Flag outside team race; Bounty
on target-step race; Uprising while top-half), 409 already-active
(PIGGY_BANK/BOUNTY second use; already jammed), 400 UPDATE_REQUIRED (wave-5
use from old client), plus all standard ones.

### 4.5 `activeEffects` payload (`getRaceProgress.js:588-612`)
Entry shape unchanged (`{ id, type, expiresAt, onSelf, targetUserId,
sourceUserId }`, no metadata). Visibility/compat per type:
- Add to `HIDDEN_FROM_OPPONENTS`: `DECOY`, `UMBRELLA`, `PIGGY_BANK`.
- **Old-client (no `powerups5`) downcast/withhold rules** (QUICKSAND→LEG_CRAMP
  precedent, `getRaceProgress.js:607`): `POWER_OUTAGE` → downcast
  `SIGNAL_JAMMER`; `UPRISING`, `RALLY_FLAG` → downcast `RUNNERS_HIGH`;
  `GHOST_PEPPER`, `COIN_FLIP`, `DECOY`, `UMBRELLA`, `PIGGY_BANK`,
  `DRILL_SERGEANT`, `BOUNTY` → withheld (like HITCHHIKE,
  `getRaceProgress.js:602`). Scores remain authoritative server-side either
  way.

### 4.6 Pushes
`DRILL_SERGEANT` and `BOUNTY` placement send the existing attack-notification
shape with new copy. Old clients ignore unknown route cases safely (established
by the reminder-push rollout).

## 5. Data model / migrations

- **Migration 1 (schema):** 11 new `PowerupType` enum values with `@map`
  snake_case (`prisma/schema.prisma:634-696`, inserted before `MYSTERY_BOX`):
  `UPRISING @map("uprising")`, `GHOST_PEPPER @map("ghost_pepper")`,
  `COIN_FLIP @map("coin_flip")`, `MYSTERY_POTION @map("mystery_potion")`,
  `DECOY @map("decoy")`, `POWER_OUTAGE @map("power_outage")`,
  `UMBRELLA @map("umbrella")`, `RALLY_FLAG @map("rally_flag")`,
  `DRILL_SERGEANT @map("drill_sergeant")`, `PIGGY_BANK @map("piggy_bank")`,
  `BOUNTY @map("bounty")`.
- **No new tables.** All state fits `RaceActiveEffect` metadata (shapes in
  §3), `RacePowerup`, coin ledger via `awardCoins`.
- **Seed (`prisma/seed.js:93-246`):** 11 `powerupShopItems` entries, all
  `active: true, testOnly: true` at launch; prices per §3 table. Copy entries
  in `POWERUP_COPY_SEED` (name/description/short per §9 frontend copy).
- **Balance config (`data/balance-config.json` + `balanceConfig.defaults.js`):**
  all 11 added to `rarityByType` (UPRISING/DECOY: RARE; POWER_OUTAGE/
  RALLY_FLAG/DRILL_SERGEANT/BOUNTY: UNCOMMON; rest COMMON — cosmetic only,
  since none are droppable) and to `storeOnlyTypes`; add
  `dailyBoxExcludedTypes` membership; new `config.mysteryPotion.pool` key
  (array of `{ outcome, weight }` per §3.4). NOT added to `dropPool` or
  `upgradeableTypes`.
- **Env:** `PIGGY_BANK_STEPS_PER_COIN=300`, `PIGGY_BANK_COIN_CAP=80`,
  `BOUNTY_PAYOUT_COINS=150` (all optional with those defaults).

## 6. Backend implementation path (ordered)

1. Migration + enum + seed + copy seed + balance-config defaults (+ gating
   constants `POWERUPS5_GATED_TYPES`, catalog filter, purchase guard, header
   plumb-through). **This pins the contract; land first.**
2. Type-set membership in `usePowerup.js`: `TARGETED_TYPES` += DRILL_SERGEANT,
   BOUNTY; `OFFENSIVE_TYPES` += DRILL_SERGEANT (only); `SELF_ONLY_TYPES` +=
   GHOST_PEPPER, COIN_FLIP, MYSTERY_POTION, DECOY, UMBRELLA, PIGGY_BANK;
   `UNSTEALABLE_TYPES` += **all 11 wave-5 types** (owner decision D6 — Sneaky
   Swap cannot steal them).
3. Use-time switch cases (11), including Uprising/Rally Flag/Power Outage
   fan-out loops, Coin Flip roll, Mystery Potion roll + re-roll rule, Decoy
   row creation, Bounty/Drill Sergeant validation.
4. Shield chain: Decoy pre-check block between Mirror (`usePowerup.js:
   972-1027`) and Socks (`1029-1092`); extend jam lookup to POWER_OUTAGE;
   Umbrella skip in Rainstorm/Power Outage fan-out loops.
5. Scorer: new branches in `computeEffectModifiers`
   (`effectiveStepScoring.js:108-389`) for UPRISING/RALLY_FLAG/COIN_FLIP
   (generic metadata-multiplier buff/debuff branch), GHOST_PEPPER (two-phase),
   UMBRELLA (rain-overlap subtraction); mirror every branch in
   `multiplierForTime` (`raceStateResolution.js:273-323`) and in
   `computeEffectModifiersFallback` (`effectiveStepScoring.js:4-48`); add the
   four windowed step-modifier types (UPRISING, GHOST_PEPPER, COIN_FLIP,
   RALLY_FLAG) to the `stepsAtExpiry` snapshot list (`expireEffects.js:27-32`).
   UMBRELLA needs no snapshot (it only subtracts from rain windows; its
   fallback is "ignore rain overlap when samples are missing" — documented
   conservative choice in the fallback fn).
6. Expiry/settlement hooks: Drill Sergeant evaluation + Piggy Bank mint in
   `expireEffects.js`; Piggy Bank early-mint + Bounty payout in the settlement
   path (`raceExpiry`), all idempotent via `awardCoins` refId.
7. `getRaceProgress.js`: visibility + downcast/withhold rules (§4.5).

## 7. Frontend plan (iOS + Android in lockstep)

- **Header:** add `powerups5` to both strings
  (`backend_api_service.dart:118-120`).
- **Copy (`lib/constants/powerup_copy.dart`):** 11 bundled
  name/description/short entries; add DRILL_SERGEANT + BOUNTY to
  `kTargetedPowerupTypes` (lines 35-53).
- **Icons (`lib/widgets/powerup_icon.dart` `_assetNames:19-53`):** 11 new
  sprites, generated via the **Codex imagegen pipeline** (CLAUDE.md — no
  hand-drawn art), matching existing powerup icon style; critique loop before
  install.
- **Shop (`shop_tab.dart`):** no structural change — new items appear from the
  catalog automatically; `_hiddenShopPowerupTypes` untouched.
- **Use flow (`race_detail_screen.dart:1393-1433`):** DRILL_SERGEANT/BOUNTY
  route to `_showTargetPicker` via `kTargetedPowerupTypes`; Bounty picker
  filters to enemies ahead of me (client-side pre-filter; server still
  validates); everything else instant-use.
- **Result moments:** Coin Flip win/lose reveal (flip animation, reuse spinner
  juice); Mystery Potion reveal (reuse case-opening reveal pattern); Uprising/
  Power Outage/Rally Flag show `affected` count toast/modal.
- **Attack outcome modal (`attack_outcome_modal.dart:13,26-40`):** add
  `REDIRECTED` outcome + `redirectedBy`/`redirectedToUserId` rendering.
  (Old clients fall through their legacy bool parsing and show "applied" for a
  redirected attack — accepted degradation; the leaderboard is truthful.)
- **Effect rendering:** new types render via existing timed-effect chips;
  unknown-type fallback already exists (`powerup_icon.dart:78`) but is never
  hit because the backend withholds/downcasts for old clients.
- **States:** all shop/use flows already have loading/error handling; missing
  `flip`/`rolled`/`redirected` fields (older backend, newer app) must degrade
  to the generic "used" toast — read defensively, never crash on absence.
- **Design skills:** load `mobile-design` + `frontend-design` before any UI
  work (house rule).

## 8. Backward-compat & rollout

- **Deploy order: backend first.** Backend with all 11 types is invisible to
  every existing client (no `powerups5` header → catalog identical, effects
  downcast/withheld). Old app + new backend: fully safe.
- New app + old backend (staging edge): catalog simply lacks the items;
  `powerups5` header is ignored. Safe.
- **`testOnly: true` at launch** for all 11 — visible only on TestFlight/dev
  channel until the carrying App Store build has rolled out (~a week, phased),
  then flip `testOnly` per item via admin. (Known caveat: testOnly items ARE
  visible to TestFlight users with real coins — the Hitchhike precedent — so
  coin-faucet envs default LIVE values; set `PIGGY_BANK_COIN_CAP=0` /
  `BOUNTY_PAYOUT_COINS=0` in prod .env until deliberately enabled if that's a
  concern.)
- Kill switches: per-item `active=false` via admin
  (`PATCH /admin/powerup-shop/items/:id`) hides from catalog immediately; the
  seed never re-asserts `priceCoins`/`active` (`seed.js:259-264`), so admin
  state survives deploys. Env kill for the coin faucets: set
  `PIGGY_BANK_COIN_CAP=0` / `BOUNTY_PAYOUT_COINS=0` stops minting without
  touching effects.
- Reminder: fix the stale seed comment at `seed.js:168-172` (claims the update
  block includes `priceCoins`; code at 259-264 says otherwise) while in there.

## 9. Test plan (tests FIRST, both agents; backend `test:unit`/`test:integration`, never bare `npm test`, never prod DB)

Backend integration (pattern: `test/integration/powerups-hitchhike-quick-rinse.test.js`
— shared server, real Postgres, feature header const including `powerups5`,
clock via explicit `startsAt`/`expiresAt` writes, settlement via
`resolveExpiredRaces`):
1. **Gating matrix:** catalog with/without `powerups5`; purchase guard; use →
   `UPDATE_REQUIRED`; activeEffects downcast (POWER_OUTAGE→SIGNAL_JAMMER,
   UPRISING→RUNNERS_HIGH) and withhold set for old headers.
2. **Uprising:** bottom-half gate (top-half caster 400; 2p race; team race
   losing-team rule); fan-out row set; merge on double-cast; max-not-sum vs
   RUNNERS_HIGH; settlement parity.
3. **Ghost Pepper:** phase math via seeded StepSamples in each window;
   freeze×rain suspension; not cleansable/rinsable; settlement parity test
   (dedicated `*-settlement-parity` file).
4. **Coin Flip:** both outcomes (inject roll), scorer math each way, lose not
   cleansable, rain merge floor at 0.5x, settlement parity.
5. **Mystery Potion:** each pool outcome (inject roll); rolled LEG_CRAMP
   respects victim's Socks/Mirror; enemy-less re-roll; refund idempotency.
6. **Decoy:** redirect to third party; chain order Mirror→Decoy→Socks (holder
   with Mirror+Decoy; redirected victim's own shields); shop-type attack
   (Leech) redirected; 2p fizzle-as-block; no Decoy chaining; team race
   redirect never hits holder's teammate; REDIRECTED response shape.
7. **Power Outage:** all enemies jammed; use-while-jammed 409 for both jam
   types; Socks exemption + blockedCount; already-jammed skip; Umbrella skip;
   team race enemies-only.
8. **Umbrella:** skipped by Rainstorm/Power Outage fan-out (shield NOT
   consumed); pre-existing rain window overlap subtraction; targeted attacks
   still land; settlement parity.
9. **Rally Flag:** non-team 400; team fan-out incl caster; merge; max-not-sum;
   parity.
10. **Drill Sergeant:** fail → penalty at expiry (floor 0); success → no-op;
    race-end-first → void; snapshot fallback (user w/o samples); Mirror
    reflect / Socks block / Decoy redirect of the dare.
11. **Piggy Bank:** mint at expiry (rate/cap math incl cap hit); early race
    settlement mint; **exactly-once when both paths run** (refId); second use
    409 **including from a DIFFERENT race while one is active (global
    one-piggy rule)**, and usable again after the first expires; env override
    respected; frozen metadata beats mid-flight env change.
12. **Bounty:** target-ahead validation; payout when out-placed (incl target
    forfeit); no payout otherwise; void race no payout; target-step race 400;
    idempotent payout; public visibility in activeEffects for opponents.
13. **Purchase/idempotency smoke** for one new SKU (existing pattern).

Frontend (widget/integration, real screens pumped):
- Shop renders the 11 items from a stubbed catalog; target picker routing for
  DRILL_SERGEANT/BOUNTY; Bounty picker filters to ahead-of-me enemies;
  attack-outcome modal renders REDIRECTED; Coin Flip result handles missing
  `flip` field (old backend) without crashing; effect chips render all new
  types.

Unit (allowed exceptions): scorer branch math for the generic
metadata-multiplier branch and Ghost Pepper phase split (many-case date math),
via the injectable `now` deps.

## 10. Acceptance criteria / definition of done

- [ ] All 11 purchasable + usable on staging with `powerups5` header; invisible
      without it (catalog byte-identical for old headers).
- [ ] Every windowed type has a green settlement-parity integration test.
- [ ] Drill Sergeant + Piggy Bank + Bounty expiry/settlement hooks idempotent
      (tests prove exactly-once minting).
- [ ] Old-client downcast/withhold verified by integration tests.
- [ ] All 11 seeded `testOnly: true`; admin can price-tune and `active=false`
      each; envs documented in backend README/.env.example.
- [ ] Frontend: both header strings updated; icons installed via imagegen
      pipeline; **iOS `flutter build ipa` and Android
      `flutter build appbundle --flavor prod` both build clean**.
- [ ] No existing test modified or deleted; pre-existing failures (fanny-pack
      13, hitchhike settlement 2) not worsened and surfaced, not "fixed".
- [ ] Deploy runbook: backend deploy (migrate deploy via pm2 reload flow) →
      verify staging → App Store/Play submission → after rollout, flip
      `testOnly` per item.

## 11. Resolved owner decisions (interviewed 2026-07-23)

- **D1 — Bounty economics:** price 75, payout 150. Env-tunable.
- **D2 — Uprising:** 300 coins, 2h, confirmed.
- **D3 — Decoy redirect pool (team races):** alive racers excluding the holder
  AND the holder's teammates — the redirect can hit the attacker's teammate or
  any of the holder's enemies, never friendly-fire the holder's side.
- **D4 — Mystery Potion pool:** owner-set mix 50% helpful / 25% attack a
  random enemy / 15% defense-jackpot / **10% self-harm** (Leg Cramp on self,
  Wrong Turn on self). Weights in §3.4.
- **D5 — Ghost Pepper:** boost-then-freeze, confirmed.
- **D6 — Sneaky Swap:** all 11 wave-5 types added to `UNSTEALABLE_TYPES` —
  expensive purchases cannot be sniped.
- **D7 — Coin Flip:** true 50/50, 2x or 0.5x, confirmed.
- **D8 — Piggy Bank (revised 2026-07-23):** price 40, 1 coin/300 steps, cap
  80/race — and only ONE active piggy per user globally across all races
  (cross-race 409), closing the multi-race same-steps exploit.

## 12. Revision log

- **Gap pass 1:** (a) documented that wave-5 items reuse the existing
  shop-inventory→held-item→use flow (LEECH mirror) — the draft never said how
  purchased items reach a race; (b) scoped Umbrella's rain-overlap subtraction
  to opponent-sourced RAINSTORM rows only (it must not erase a Coin Flip lose
  window); (c) added the Bounty expiry-vs-settlement race fix (settlement reads
  rows regardless of ACTIVE/EXPIRED; refId idempotency); (d) disabled Bounty in
  team races (individual placement doesn't map to team settlement); (e) made
  the Drill Sergeant expiry branch explicitly re-check race state before
  penalizing; (f) trimmed the `stepsAtExpiry` snapshot list to the four real
  step-modifier types and documented Umbrella's conservative fallback; (g)
  noted the TestFlight-sees-testOnly-with-real-coins caveat and the
  faucet-env=0 mitigation.
- **Gap pass 2:** (a) Mystery Potion: any invalid roll (stacking rejection
  etc.) falls back to PROTEIN_SHAKE — a potion may never fail after
  consumption; (b) documented Decoy redirecting SNEAKY_SWAP (steal lands on
  the new victim) as intended; (c) surfaced the multi-race Piggy Bank
  same-steps question as decision D8 with the accepted-by-default rationale;
  (d) verified every §6 step names a real file/line from the contract report
  and that no new endpoint or table is introduced anywhere in the spec.
- **Owner interview fold-in (2026-07-23):** all 8 decisions resolved (§11);
  Mystery Potion pool rebalanced to the 50/25/15/10 mix including the new
  self-harm category (self-sourced → not dispellable, matching the Ghost
  Pepper/Coin Flip rule); all 11 types added to `UNSTEALABLE_TYPES` in §6
  step 2. Zero open questions remain.
