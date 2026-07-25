# Turtle base character — requirements

Status: **DRAFT — awaiting owner approval**
Author: PM/BA pass, 2026-07-24
Related: `docs/powerup-character-batch-requirements.md` (Corgi zoomies / Bara herd bonus),
backend `c88f919` (CHARACTER slot), backend `52d9d00` (character powers).

---

## 1. Summary & user story

**What.** A third purchasable base character — the **Turtle** — sold in the cosmetics
shop alongside Corgi Puppy. Equipping it swaps the walking capybara sprite for a
turtle everywhere the animal renders, and grants the Turtle's character power:

> **Shell** — every incoming box-earned attack has a **30% chance to bounce off
> your shell** and do nothing.

**For whom.** Players who keep getting sniped in races and want a defensive
identity, and players collecting characters.

**Why.** Characters are the highest-margin cosmetic (1000 coins) and the only
cosmetic tied to gameplay. Bara = economy (herd bonus), Corgi = burst offense
(zoomies), Turtle = defense. This completes the first triad and gives the
character picker a real "what do I want to play like" decision.

---

## 2. Scope / non-goals

### In scope
- Turtle walk-cycle sprite sheet (**already produced**, §3) + `animals.dart` entry.
- `data/cosmetics.json` CHARACTER-slot shop item `turtle`, 1000 coins,
  `active: true`, `testOnly: true`.
- Backend Shell block: a 30% roll evaluated at every site that currently consults
  a Compression Socks shield, subject to the shop-exemption rule (§5.2).
- `blockedBy: "SHELL"` on the use-powerup result + a `POWERUP_BLOCKED` race event
  and push, reusing the existing block plumbing verbatim.
- Frontend copy for the `SHELL` interceptor in the attack-outcome modal and feed.
- Gated behind the existing `CHARACTER_POWERS_ENABLED` env flag (ships `false`)
  plus a dedicated `TURTLE_SHELL_DISABLED` kill switch.
- **Herd-bonus race-feed line** (§5.4) — owner requirement attached to this
  build. Bara scope, not Turtle, but it is the precondition for flipping the
  shared flag live.

### Non-goals (explicitly out)
- **No new DB table, column, or migration.** The block is resolved once, inline,
  inside the existing use-powerup transaction; nothing about it is persisted
  beyond the `RacePowerupEvent` row the block already writes today.
- **No Trail Mine interaction.** A Trail Mine detonates outside the use-powerup
  resolution path (it is a self-placed trap resolved during scoring), where
  Compression Socks is never consulted either. The Shell does not block it.
  Deliberate: keeping the Shell exactly co-located with the Socks check is what
  makes live display and settlement agree for free.
- **No Shell block of the global-event / weather system**, the daily-reward
  system, or anything that is not a powerup use by another user.
- **No per-animal accessory-placement authoring** in this spec beyond shipping a
  rough `renderMetadata`; final placement is a tuner pass (§8.4).
- **No character picker redesign.** The Turtle appears in the existing shop
  CHARACTER row exactly as the Corgi does.
- **No Turtle downside.** The character is a pure upside; no speed penalty.

---

## 3. Art — DONE

Source: five owner-supplied 1000×1000 PNGs (iMessage attachments IMG_1862/1863/
1864/1866/1870). Verified to be a perfect 10 px pixel grid, i.e. 100×100 logical
pixels, flat white background, 15–17 colors, side-profile **facing right** with a
bold continuous black outline — house style, no regeneration needed. Per
`CLAUDE.md` no artwork was hand-drawn: the pipeline is a deterministic crop /
alpha / pack of the supplied frames.

Processing applied (scratchpad, reproducible):
1. Exact 10× block decimation 1000×1000 → 100×100 (`Image.NEAREST`; grid
   alignment verified — 0 of 10 000 blocks non-uniform).
2. Border flood-fill of white → alpha 0. Interior stays untouched; all four
   corners verified `(0,0,0,0)`, no chroma fringe.
3. Crop each frame to an 88×88 square window at `(1, 0)`, which centres the
   81×37 content horizontally and lands its **bottom edge at y=69 → 0.784 of the
   frame**, matching the capybara's 0.781 so the feet sit on the track line.
4. Pack 8 frames left-to-right → **`turtle_walk_right.png`, 704×88, RGBA**.

Frame order (walk cycle), **owner-supplied 2026-07-24** — this supersedes the
geometry-derived 5-frame order that shipped first and read wrong in motion:
`1863 → 1866 → 1862 → 1866 → 1863 → 1870 → 1864 → 1870`. The two source poses
`1866` and `1870` are pass-through frames and each appear twice, which is why the
cycle is 8 slots over 5 distinct drawings; dropping the repeats (the original
`1864 → 1863 → 1866 → 1870 → 1862`) is what made the walk look wrong.

**Frame count is 8, not 6.** Both `AnimalSprite.frameCount` and the catalog's
`renderMetadata.animationFrames` are per-animal already, so 8 is a config value,
not a special case. Every consumer reads the count
(`home_course_track.dart:612,671,767`, `shop_tab.dart:778-779`); none hardcodes 6
for animals.

Deliverable path: `assets/images/turtle_walk_right.png` (covered by the existing
`assets/images/` glob in `pubspec.yaml:85` — **no pubspec change needed**).

---

## 4. Owner decisions (interviewed 2026-07-24)

| # | Question | Decision |
|---|---|---|
| D1 | Where does the Shell roll sit among existing defenses? | **After Mirror and Decoy, before Compression Socks.** A successful Shell roll saves the player's paid shield for later. |
| D2 | What can the Shell block? | **Everything Compression Socks is consulted for** — single-target attacks, Imposter, auto-targeted, and AoE with an independent per-victim roll — **minus** the shop exemption in D3. |
| D3 | Shop-purchased attacks | **Per TYPE, not per instance (owner correction 2026-07-24).** The Shell can block any powerup **type that is obtainable from an in-race roll** — regardless of how the attacker got that particular copy. Store-exclusive types are never blockable. On a Shell block the attacker still forfeits any upgrade coins. |
| D4 | Price | **1000 coins**, same as Corgi Puppy; `active: true`, `testOnly: true`. |
| D5 | AoE carve-out? (open item 1) | **No — confirmed 2026-07-24.** Race-rolled only; the Shell blocks no AoE, and that is accepted. |
| D6 | Separate enable flag? (open item 2) | **No — confirmed 2026-07-24.** Reuse `CHARACTER_POWERS_ENABLED`; flipping it lights up Bara herd bonus and Corgi zoomies at the same time, which is accepted. Old clients simply won't have the character. |

### D3 — the rule is per TYPE

> **Blockable ⟺ the powerup's type appears in the in-race mystery-box
> `dropPool`.** How the attacker obtained this particular copy is irrelevant: a
> Leg Cramp bought for coins, won on the daily spin, or opened from an in-race
> box is equally Shell-blockable, because Leg Cramp is a type you can get from a
> race roll.

The single authority is `dropPool` in
`src/modules/economy/balanceConfig.defaults.js:148` (equivalently: **not** in
`storeOnlyTypes`, line 182 — the two are complements by construction, and a
structural guard test should pin that).

**Do NOT use a per-instance `earnedAtSteps === null` test.** An earlier draft of
this spec proposed exactly that and it is wrong: the coin shop sells the
race-rollable attack types too (`powerupCopySeed.js` lists LEG_CRAMP, RED_CARD,
SHORTCUT, WRONG_TURN, DETOUR_SIGN, PINECONE_TOSS, SNEAKY_SWAP as purchasable).
Under a per-instance rule the Shell would fail to block every *bought* Leg Cramp
— which is how most of them are actually thrown — and the character would be
near-worthless in practice. The per-type rule is the owner's intent and the one
that makes the ability meaningful.

The blockable set is therefore:

**Shell CAN block** — every attack type in `dropPool`, however obtained:
`DETOUR_SIGN`, `PINECONE_TOSS` (common), `LEG_CRAMP`, `WRONG_TURN` (uncommon),
`RED_CARD`, `SNEAKY_SWAP`, `SHORTCUT` (rare).

**Shell CANNOT block** — store-exclusive types: `IMPOSTER`, `RAINSTORM`,
`SIGNAL_JAMMER`, `LEECH`, `HITCHHIKE`, `DRILL_SERGEANT`, `BOUNTY`,
`POWER_OUTAGE`, `QUICKSAND`, `UPRISING`, `GHOST_PEPPER`, `MYSTERY_POTION`-
generated attacks, and every other wave-5 type.

Net: **no AoE attack is Shell-blockable**, because all three AoE attacks
(Rainstorm, Power Outage, Quicksand) are store-exclusive. The per-victim AoE roll
in §5.3 is therefore unreachable today and exists only so the rule stays correct
if a storm ever enters the drop pool. Implement it anyway; it costs nothing and
the alternative is a silent behaviour change the day the drop pool moves.
**Owner-confirmed 2026-07-24 (D5): no AoE carve-out.**

---

## 5. Backend design

### 5.1 The blockable test — per type, off the drop pool

```js
// The in-race mystery-box drop pool is THE authority. Read it from balance
// config at call time (never a second hardcoded list — that is the exact class
// of drift D13 removed).
function isRaceRolledType(type, config) {
  const pool = (config || balanceConfig.getConfigSync()).dropPool || {};
  return ["COMMON", "UNCOMMON", "RARE"].some((tier) =>
    (pool[tier] || []).includes(type)
  );
}
```

`RacePowerup.earnedAtSteps` is **not** consulted. A bought, spun, stolen, or
box-dropped Leg Cramp are all identical to the Shell.

Mystery Potion generates its enemy attack inline as a rolled `type`; apply the
same per-type test to the rolled type, so a potion that rolls a Leg Cramp *is*
Shell-blockable even though the potion itself is store-exclusive. Consistent:
the rule is about the attack that lands, not the wrapper it came in.

Add a **structural guard test** asserting `dropPool` and `storeOnlyTypes` are
complements, so the "blockable set" can never silently drift as the economy is
retuned.

### 5.2 Where the roll goes

New helper in `src/modules/races/services/characterPowers.js` (pure, DB-free, so
it is trivially testable and shares the existing gate):

```js
const SHELL_BLOCK_CHANCE = 0.30;

function isTurtle(user) { /* characterAnimal(user) startsWith "turtle" */ }

function shellBlocksAttack({ targetUser, powerupType, random = Math.random, config = null }) {
  if (!characterPowersEnabled()) return false;
  if (process.env.TURTLE_SHELL_DISABLED === "true") return false;
  if (!isTurtle(targetUser)) return false;
  if (!isRaceRolledType(powerupType, config)) return false; // D3 — per TYPE
  return random() < SHELL_BLOCK_CHANCE;
}
```

`random` is injected exactly like the existing `random` threaded through
`usePowerup` (see `weightedRoll`, `pickDecoyRedirectVictim`), so tests are
deterministic.

Call sites — the same ones that consult `COMPRESSION_SOCKS` today, with the
Shell checked **immediately before** each shield lookup (D1):

| Site (`usePowerup.js`) | Path |
|---|---|
| ~1776 | Main single-target offensive block (post-Mirror, post-Decoy) |
| ~1996 | Imposter dedicated block |
| ~1930 / ~2006 | Reflected/redirected variants |
| ~2463 | Rainstorm per-victim branch |
| ~973 | Quicksand per-victim branch |
| ~586 | Mystery Potion enemy-attack branch |

Every one of those becomes: *Shell roll → if blocked, take the existing block
branch with `blockedBy: "SHELL"` and the shield untouched; else fall through to
the shield lookup exactly as today.*

Because the block happens before the effect row is created, there is **nothing to
reconcile between live display and settlement** — a blocked attack simply never
existed. This is the same property the Socks block already has.

### 5.3 Block outcome — identical to the Socks precedent

On a Shell block:
- Attacker's powerup → `status: "USED"`, `usedAt`, `targetUserId`, `upgradeLevel`.
- Upgrade coins **forfeit** (D3); write the `PowerupUpgradeEvent` with
  `status: "BLOCKED"` when `upgradeLevel > 0`.
- `RacePowerupEvent` `POWERUP_BLOCKED`, `actorUserId` = defender, description:
  `"{defender}'s Shell bounced off {attacker}'s {Powerup Name}!"`
- `events.emit("POWERUP_BLOCKED", { raceId, attackerUserId, defenderUserId, blockedType, upgradeLevel })`
  — unchanged shape, so the existing push notification works with no change.
- Return `{ blocked: true, blockedBy: "SHELL", outcome: "BLOCKED", upgradeLevel, coinsSpent }`.
- The defender's Compression Socks, if any, is **not** consumed.

### 5.4 Herd-bonus race-feed line (owner requirement)

**Problem.** The herd bonus today surfaces **only** as the additive
`characterBonus` block on the race-progress payload (`getRaceProgress.js:449-453`),
which only a build that knows to read it can render. Every frozen binary just
sees its step total quietly inflated with no explanation — the bad UX the owner
called out. Feed lines are **server-rendered strings**, so a feed event reaches
every client ever shipped.

**Requirement.** Emit one race-feed event per participant per race-local calendar
day on which a herd bonus applies:

> `🦫 Herd Bonus — {displayName} +{perDay} steps ({capyCount} capybaras strong)`

**Where.** NOT in `getRaceProgress` — that is a read path and must never write.
Emit from `characterEffectScheduler.js`, which already ticks every 5 minutes for
zoomies and already owns the "materialize per-user-day character state" job.

**Dedup — read this.** Per the *cron-dedup-no-advisory-locks* incident: crons are
in-process `setInterval` and `JobRun.markRan` is **not** atomic. Use the
**insert-first unique key** pattern the zoomies windows already use — a unique
constraint on `(raceId, userId, localDay)` and let the DB reject the duplicate.
**Never** an advisory lock across the callback.

**Old-client safety.** A new `eventType` value could break a client that switches
exhaustively on the enum. Reuse an existing generic feed event type and carry the
text in `description`; do not mint a new enum value unless a check of the client's
feed renderer proves unknown types degrade gracefully. **The backend agent must
verify this against `feed_bubble.dart` before choosing.**

**Cost.** Zero extra scoring risk: this is presentational only. The bonus itself
is unchanged — do not recompute or re-mint anything, just describe what
`computeHerdBonus` already returns.

---

## 6. API contract

**No new endpoints. No changed request shapes. No migration.** Three additive
response changes:

### 6.1 `POST /races/:raceId/powerups/:powerupId/use` → result

```jsonc
{
  "result": {
    "blocked": true,
    "blockedBy": "SHELL",     // NEW enum value; was always "COMPRESSION_SOCKS"
    "outcome": "BLOCKED",     // unchanged
    "upgradeLevel": 0,
    "coinsSpent": 0
  }
}
```
`blocked` and `outcome` are unchanged, so a frozen old client renders its normal
BLOCKED modal. `blockedBy` is a free-form string the client already treats
defensively (`attack_outcome_modal.dart:84-85` defaults it, and
`PowerupCopy.nameFor` falls through to echoing the raw key —
`powerup_copy.dart:204-211`). Worst case on an old binary: the modal reads
"SHELL blocked your attack" instead of "Shell". Ugly, not broken. **Verified, not
assumed.**

### 6.2 `GET /shop/catalog`
One additional CHARACTER-slot item, served **only** to clients sending the
`characters` token in `X-Client-Features` (`src/shared/middleware/clientFeatures.js`).
No shape change.

### 6.3 `animal` field
Already exists and already ships on every social payload (`c88f919`). It will now
carry the value `"turtle"`. Clients that don't recognise it fall back to the
capybara by construction (`animals.dart:30-32`). No contract change.

### 6.4 Old-client compatibility summary
| Old client does | Result |
|---|---|
| Omits `characters` feature token | Never offered the Turtle; never receives `animal: "turtle"` in the equipped map. Renders capybara. |
| Has `characters` but no bundled turtle PNG (i.e. builds between the Corgi ship and this one) | `animalSpriteFor("turtle")` misses the map → capybara. This is why the item ships `testOnly: true` until the carrying build rolls out. |
| Gets attacked and Shell-blocked | Sees its normal BLOCKED modal; `blockedBy` string may render raw. |
| Attacks a turtle and gets blocked | Standard block push + feed line. |

---

## 7. Data model / migrations

**None.** Everything reuses existing tables:
- `ShopItem` row via `data/cosmetics.json` (`slot: "CHARACTER"`).
- `RacePowerup.earnedAtSteps` (existing) as the shop-purchase signal.
- `RacePowerupEvent` / `PowerupUpgradeEvent` (existing block rows).

Catalog entry:
```json
{
  "sku": "turtle",
  "name": "Turtle",
  "description": "Slow and steady — and armored. Shell: 30% chance to bounce off any attack a rival throws your way.",
  "slot": "CHARACTER",
  "priceCoins": 1000,
  "assetKey": "turtle",
  "active": true,
  "testOnly": true,
  "earnOnly": false,
  "bobble": false,
  "sortOrder": 201,
  "renderMetadata": { "offsetX": 0, "offsetY": 0.085, "rotation": 0, "scale": 0.70, "animationFrames": 5 }
}
```
`scale`/`offsetY` are derived starting values, not final: the turtle's content
fills 92% of its frame vs the capybara's 66%, so ~0.70 matches body length, and
+0.085 re-seats the feet after centre-scaling. **Fine-tune in Admin → Accessory
Tuner, then `npm run cosmetics:pull`** — never edit prod by hand.

⚠️ **Sanitizer trap** (see memory *tuner-rendermetadata-wipe-incident*): three
copies of the renderMetadata whitelist exist (admin tuner sanitizer,
`scripts/cosmetics-apply.js`, shop cosmetics util). `animationFrames` is already
whitelisted; **no new key is introduced by this spec** — if that changes, all
three must be updated or the tuner silently wipes it.

---

## 8. Frontend plan

### 8.1 Sprite registration
`lib/config/animals.dart`:
```dart
'turtle': AnimalSprite(asset: 'assets/images/turtle_walk_right.png', frameCount: 8),
```
That single entry lights up every surface — home course track, race detail,
leaderboard, ranked, friends, race cards, onboarding, the shop tile
(`shop_tab.dart:778`), and the admin tuner's animal dropdown
(`admin_accessory_tuner_screen.dart:567`) — because all of them already route
through `animalSpriteFor`.

### 8.2 Copy
`lib/constants/powerup_copy.dart` — add `SHELL` to the extra display-name map so
the attack-outcome modal reads "Shell" rather than the raw key:
```dart
'SHELL': 'Shell',
```
Also add the interceptor-icon mapping in `lib/widgets/powerup_icon.dart` (fall
back to a generic shield glyph rather than shipping new art — no hand-drawn art,
per CLAUDE.md).

### 8.3 States
- **Loading / empty / error:** none new. The Turtle is one more shop tile in an
  already-built grid; the block modal is an already-built screen.
- **Missing-field degradation:** `blockedBy` absent → modal already defaults to
  `COMPRESSION_SOCKS` (unchanged path). `animal` absent/unknown → capybara.
  A backend that predates this spec simply never sends `"SHELL"`.
- **`feed_bubble.dart:21`** `_shieldTypes` gains `'SHELL'` so a Shell block gets
  the shield treatment in the race feed.

### 8.4 Placement pass
After the build installs, run Admin → Accessory Tuner with the turtle selected
and check every accessory slot's `perAnimal.turtle` override — HEAD and FACE in
particular, since the turtle's head sits far right and low compared to the
capybara's. Then `npm run cosmetics:pull` and commit. This is expected to be the
largest hand-tuning chunk of the feature.

### 8.5 iOS + Android lockstep
No platform-specific code. Both builds must be produced from the same commit per
CLAUDE.md — `flutter build ipa` (no `--flavor`) **and**
`flutter build appbundle --flavor prod`, same `--dart-define` and version.

---

## 9. Backward-compat & rollout

**Deploy order: backend first, app second.** Non-negotiable.

1. **Backend**, with `CHARACTER_POWERS_ENABLED` still `false` in prod. Ships the
   catalog item (`testOnly: true`) and the Shell code path, both inert.
2. **App Store + Play builds** carrying `turtle_walk_right.png`. Wait out the
   ~1-week phased rollout.
3. **Flip `CHARACTER_POWERS_ENABLED=true`** in prod. Per D6 this deliberately
   switches on Bara herd bonus and Corgi zoomies at the same time — accepted, no
   separate Turtle flag. Because all three go live together, watch the first
   settlement after the flip: herd bonus changes `bonusSteps` for every capybara
   in every active race, which is the largest blast radius of the three.
4. **Flip `testOnly` to `false`** in `data/cosmetics.json` only after step 2's
   build has rolled out, so no frozen binary is offered a character whose PNG it
   does not bundle.

Kill switch: `TURTLE_SHELL_DISABLED=true` disables only the Shell roll and leaves
the cosmetic purchasable — one env flip, no redeploy (read at call time).

Rollback: the Shell block writes no new rows and creates no effects, so disabling
it is complete and instantaneous. Nothing to backfill or repair.

⚠️ **Deploy-time seed clobbers `priceCoins` and `active`** (memory
*leech-price-300-intentional*) but **not** `testOnly`. Landing 1000/`active:true`
in source is what makes the deploy idempotent.

---

## 10. Test plan (tests FIRST, then logic)

### Backend — `test/integration/` (real HTTP, real DB, test Postgres only)
1. Turtle equipped + box-earned Leg Cramp → over a seeded RNG, blocked path
   returns `blockedBy: "SHELL"`, `outcome: "BLOCKED"`, no `RaceActiveEffect` row
   created, attacker's powerup `USED`.
2. Same, RNG above 0.30 → attack applies normally, effect row exists.
3. Type rule (D3) — three cases, all required:
   a. **inventory-redeemed `LEG_CRAMP`** (`earnedAtSteps: null`, bought or spun)
      → **IS blocked** with RNG forced low. This is the case that pins per-type
      over per-instance; it must not be dropped or inverted.
   b. store-exclusive `RAINSTORM` → **never** blocked, RNG forced to 0.0.
   c. Mystery Potion that rolls a `LEG_CRAMP` → **IS blocked** (the rolled type
      is what's tested); a potion rolling a store-exclusive attack is not.
4. Turtle equipped + box-earned attack + Compression Socks held → Shell blocks,
   **socks row still ACTIVE**. (D1 ordering.)
5. Shell fails the roll + socks held → socks consumed (`status: "BLOCKED"`),
   `blockedBy: "COMPRESSION_SOCKS"`. Regression guard on the existing behaviour.
6. Mirror on the target → reflect happens, Shell never consulted (D1: Mirror
   precedes Shell).
7. Upgraded (tier ≥ 1) attack Shell-blocked → `PowerupUpgradeEvent` written with
   `status: "BLOCKED"`, coins **not** refunded.
8. Capybara/Corgi target → Shell never fires regardless of RNG.
9. `CHARACTER_POWERS_ENABLED=false` → never fires. `TURTLE_SHELL_DISABLED=true`
   → never fires.
10. Catalog: client **with** `characters` token sees `turtle`; client **without**
    it does not, and its equipped map contains no CHARACTER entry.
11. Statistical guard: 1000 rolls with real `Math.random` land in [0.25, 0.35].
12. Structural guard: `dropPool` ∪ `storeOnlyTypes` covers every attack type and
    the two sets are disjoint — so the blockable set can't silently drift.
13. **Herd feed (§5.4):** scheduler tick on a race with 4 capybaras writes exactly
    one feed row per participant per race-local day, with the right
    `perDay`/count in the text; a second tick in the same day writes **none**
    (insert-first dedup); a race with the flag off writes none. Assert through
    the race-feed API response, not the model.

### Frontend — widget tests that pump the real screen
1. Pump the home course track with `animal: 'turtle'` → the turtle sheet is the
   rendered image and the frame count used is 5.
2. Pump with `animal: 'unknown_animal'` and with `animal: null` → capybara. No
   exception. (Old/new backend skew.)
3. Pump `AttackOutcomeModal` with `{blocked: true, blockedBy: 'SHELL'}` → title
   "BLOCKED!", interceptor name "Shell".
4. Pump the same modal with `blockedBy` **absent** → still renders, defaults to
   Compression Socks. (Degradation.)
5. Pump the shop CHARACTER row with the turtle catalog entry → tile renders the
   animated sheet at 8 frames, price 1000.

Unit tests only where an integration test structurally cannot reach:
`shellBlocksAttack` truth table over the gate/animal/shop-purchase/RNG matrix.

**Neither agent modifies or deletes an existing test.** Anything that looks wrong
gets surfaced to the owner instead.

---

## 11. Acceptance criteria / definition of done

- [ ] `assets/images/turtle_walk_right.png` (704×88, 8 frames) committed; corners
      transparent; renders correctly composited on white **and** on the in-app track.
- [ ] `animals.dart` entry added; turtle renders on home track, race detail,
      leaderboard, ranked, friends, race cards, and the shop tile.
- [ ] `cosmetics.json` entry present with `testOnly: true`, 1000 coins, 8 frames.
- [ ] Shell blocks race-rollable attack **types** at ~30% however the copy was
      obtained, never blocks store-exclusive types, and never consumes the
      target's Compression Socks on a successful roll.
- [ ] Herd-bonus feed line appears once per participant per race-local day and
      is readable on a client that predates `characterBonus`.
- [ ] Attacker forfeits upgrade coins on a Shell block; block event + push fire.
- [ ] Every test in §10 written first, failing for the right reason, then green.
- [ ] Backend deployed with `CHARACTER_POWERS_ENABLED=false`; verified inert in prod.
- [ ] iOS **and** Android builds produced from the same commit with matching
      version/build number and `--dart-define`.
- [ ] Tuner pass done for `perAnimal.turtle` accessory placement; `cosmetics:pull`
      committed.
- [ ] No migration in the diff. No new renderMetadata key. No modified existing test.

---

## 12. Open items for the owner (approval gate)

**None — both resolved 2026-07-24 (D5, D6).**

1. ~~AoE carve-out~~ → No. Race-rolled only; the Shell blocks no AoE.
2. ~~Separate enable flag~~ → No. `CHARACTER_POWERS_ENABLED` stays shared;
   `TURTLE_SHELL_DISABLED` remains as the Turtle-only kill switch.

---

## 13. Revision log

**Gap pass 1** (fresh re-read):
- Caught that D2 ("everything Socks blocks") and D3 (shop exemption) collide:
  every AoE attack is store-only, so the AoE branch is unreachable. Added §4's
  "D3 consequence" table, the explicit blockable/unblockable type lists, and
  open item #1 rather than silently implementing a weaker power than the owner
  pictured.
- Replaced a per-type exemption list with the per-instance `earnedAtSteps === null`
  test (§5.1) — same behaviour today, and it does not silently break if the drop
  pool ever changes. Documented the Sneaky-Swap-stolen and Mystery-Potion cases,
  both of which a type list would have gotten subtly wrong.
- Frame count: the first draft assumed a 6-frame sheet to match the capybara.
  Verified every consumer reads `frameCount`/`animationFrames` per animal, so 5
  needs no special case. Recorded the evidence (file:line) instead of the assumption.

**Gap pass 2** (second independent re-read):
- Old-client `blockedBy: "SHELL"` handling was asserted, not checked. Read
  `attack_outcome_modal.dart:84-85` and `powerup_copy.dart:204-211` and replaced
  the claim with the actual fallback behaviour ("renders the raw key") in §6.1.
- Added the missing rollout hazard in §9 step 3: `CHARACTER_POWERS_ENABLED` is
  shared with two other unshipped powers, so the flip is not Turtle-scoped.
  Raised as open item #2.
- Added the Trail Mine non-goal (§2). The first draft said "any debuff" without
  bounding it, which would have pulled the roll outside the use-powerup
  transaction and reintroduced a live-vs-settlement divergence risk.
- Added the deploy-seed clobber warning (§9) and the three-copy sanitizer
  warning (§7) from prior incidents; neither was in the first draft.
- Made the D1 ordering testable rather than assumed: §10 tests 4, 5 and 6 pin
  Mirror → Decoy → Shell → Socks as observable behaviour.

**Gap pass 4** (owner correction, 2026-07-24 — supersedes parts of pass 3):
- **The per-instance rule was wrong and is removed.** The coin shop sells the
  race-rollable attack types (`powerupCopySeed.js`: Leg Cramp, Red Card,
  Shortcut, Wrong Turn, Detour Sign, Pinecone, Sneaky Swap), so keying off
  `earnedAtSteps` would have let every *bought* Leg Cramp through the Shell —
  i.e. most real attacks — leaving the character nearly worthless. The rule is
  **per type, off `dropPool`** (§5.1). Pass 3's "free daily-spin powerups are
  Shell-proof" finding is void: under the type rule a spun Leg Cramp is blocked
  like any other.
- Mystery Potion now tests the **rolled** type rather than the potion wrapper,
  so a potion-rolled Leg Cramp is blockable. Pass 3 had it exempt.
- Added a structural guard (test 12) pinning `dropPool` and `storeOnlyTypes` as
  complements, so the blockable set cannot drift when the economy is retuned.
- Added §5.4, the herd-bonus race-feed line, as an owner requirement gating the
  live flip — with the insert-first dedup rule and the "don't mint a new
  eventType without checking the client renderer" warning.

**Gap pass 3** (post-interview, after D5/D6 landed):
- Audited **all five** `RacePowerup` creation sites rather than trusting the two
  the first draft had read. Result: the `earnedAtSteps === null` test is exact —
  welcome boxes and auto-enroll boxes set it, so they stay Shell-blockable and
  are not accidentally exempted. Table added to §4.
- Found the case neither the spec nor the interview had named: **daily-spin
  powerups are exempt**, because the spinner grants to inventory and inventory
  enters a race through the same redeem path as a coin purchase. It matches
  "race rolled" literally, but it means a *free* powerup can be Shell-proof.
  Documented in §4 rather than left as a surprise at review time.
- §9 step 3 rewritten for D6: called out that the shared flip also enables the
  herd bonus, whose blast radius (every capybara's `bonusSteps` in every active
  race) is larger than the Shell's, and that the first post-flip settlement is
  the thing to watch.
- §10 test 3 reworded — it said "shop-redeemed Rainstorm", which under D5 is now
  doubly-exempt (store-only AND redeemed) and so would pass for the wrong
  reason. The regression that matters is a **redeemed copy of a normally
  box-rolled type** (e.g. an inventory Leg Cramp), which isolates the
  `earnedAtSteps` test from the type. Both cases are now listed.
