# Balance Config — Single Source of Truth

**Status:** DRAFT — awaiting owner approval (Phase 4 gate)
**Companion audit:** `docs/economy-balance-audit.md`
**Date:** 2026-07-20

---

## 1. Summary & user story

Every balance value in the game — power-up prices, rarity, drop odds, upgrade ladders,
daily-box curves — is currently defined in 2–9 places across two repos, and several of
those places disagree in ways that cost real coins (audit §2.3). Live prices
additionally drift from source with no audit trail and no way to tell it happened
(audit §2.1).

> **As the game owner,** I want one authoritative, versioned place to set every balance
> value, editable without a deploy, so that a change is deliberate, reversible, visible
> in history, and can never be silently reverted by a deploy or by another admin.

> **As a player,** I want to see the exact odds I'm playing against.

**Authority model (owner decision):** the **database is authoritative**, edited through
an admin UI. Code holds fallback defaults only.

---

## 2. Scope / non-goals

### In scope
- Canonical rarity, drop pool, position-odds curve, per-type weights.
- Power-up shop prices / `active` / `testOnly`, with an admin surface.
- Upgrade cost ladders.
- Daily-box streak curve, coin ranges, accessory weighting mode.
- Lucky Horseshoe graduated rare-chance ladder.
- Versioning, audit trail, rollback, concurrency safety, drift detection.
- **Admin UI**: structured editing form with diff preview.
- Player-facing exact-odds display.
- Removal of duplicated definitions in both repos + a structural guard test.
- `POWERUPS.md` generated from config.

### Non-goals
- **Cosmetic price/flag editing** — already solved by the Accessory Tuner
  (`admin.js:181-257`). Cosmetics enter only via the daily-box *weighting* fix.
- Coins, buy-ins, referral rewards, ranked rewards, ad rewards.
- **Retroactive changes of any kind** (owner decision). No refunds, no re-levelling, no
  recomputation of existing `upgradeLevel`. Everything is forward-only.
- Changing the *values* recommended in the audit beyond the two corrections in D5.

---

## 3. Design decisions (pinned before implementation)

| # | decision | rationale |
|---|---|---|
| D1 | New `balance_config` table, **not** `AppSetting` | `AppSetting` is boolean-only (`admin.js:138-140`) and per-environment/non-mirrored (`schema.prisma:1411-1412`). Balance config is nested JSON needing version history. |
| D2 | **Append-only versions**, one active row | Audit trail + one-click rollback — what the Leech drift lacked. |
| D3 | Per-environment, **explicit promote** — not auto-mirrored | Auto-mirroring (the `ShopItem` pattern) would make staging useless as a balance test bed. |
| D4 | Code keeps full fallback defaults; DB failure never throws | Mirrors `appSettings.js:57-69`. A DB blip must not break box drops mid-race. |
| D5 | Seeded config = current live values, with **four** deliberate corrections | `SHORTCUT: COMMON→RARE`, `accessoryWeightMode: legacy→inverse`, and — as a direct consequence of D7 — `RUNNERS_HIGH: UNCOMMON→COMMON` and `PINECONE_TOSS: UNCOMMON→COMMON`, which make those two ladders *cheaper*. **Originally written as "two"**, which undercounted: the audit §4 table always listed all four, but D5 didn't, so the landing deploy is slightly less behaviour-neutral than this row first claimed. |
| D6 | `priceCoins` + `active` removed from the seed upsert's `update` block | Direct fix for audit §2.1; follows the cosmetics precedent (`seed.js:81-87`). |
| D7 | Conflicts resolve toward `powerupOdds.js` (the drop table) | Prod drop history shows it holds the newer intentional values (audit §2.3). |
| D8 | All new API fields **additive**; nothing renamed, removed, or reinterpreted | Frozen-client rule. |
| **D9** | **Read-through cache, 5s TTL, + `configVersion` stamped on every roll** | Backend runs pm2 **cluster mode** — multiple workers, each with its own cache. `bustCache()` only busts the serving process. 5s bounds the skew; the stamp makes "odds shown" vs "odds rolled" reconcilable after the fact. See §3.1. |
| **D10** | **Optimistic concurrency**: `PUT` requires `expectedVersion`, 409 on mismatch | Without it, two admins both loading v7 silently overwrite each other — the *same* silent-overwrite class as the Leech drift this spec exists to prevent. |
| **D11** | **Soft bounds**: out-of-range saves warn and require explicit override, recorded in history | Protects against typos without blocking deliberate experiments. Bounds live in **code, not config** — see §3.2. |
| **D12** | Admin UI is a **structured form with diff preview** and a confirm step | Makes catastrophic edits visibly hard; pairs with D11. |
| **D13** | Config `dropPool` is the **only** drop-exclusion authority | `getEligiblePowerupPool.js`'s hardcoded gate lists are removed, not merely cross-validated. Two authorities is the problem we're solving. |

### 3.1 Honest limit of D9

The stamp gives **auditability, not prevention**. A player views odds at time T and
opens a box at T+n; if config changed in between, the roll legitimately uses the newer
version. D9 guarantees you can always answer *"which config rolled this box?"* — it does
not guarantee the number shown equals the number rolled. Preventing that would require
pinning config per race, which is out of scope and probably undesirable.

The 5s TTL is chosen against measured load: 94 active users. Per-roll querying (the
zero-skew option) was rejected as scaling worst, and the DB cluster has hit
`max_connections` before (`DEPLOY_RUNBOOK.md:180`), which also ruled out a LISTEN/NOTIFY
listener per worker.

### 3.2 Why soft bounds live in code

If bounds were stored in config, an admin could raise the bound and then exceed it —
circular, and the guardrail would be worthless. Bounds are a code constant in
`src/services/balanceConfig.defaults.js`; changing them requires a deploy and review.

---

## 4. Data model / migrations

### 4.1 New table

```prisma
model BalanceConfig {
  id            String   @id @default(uuid())
  version       Int      @unique
  config        Json
  note          String?
  createdBy     String?  @map("created_by")
  boundOverride Boolean  @default(false) @map("bound_override")
  active        Boolean  @default(false)
  createdAt     DateTime @default(now()) @map("created_at")

  @@index([active])
  @@map("balance_config")
}
```

**`version` is assigned by the application inside the write transaction**, not by
`@default(autoincrement())` — Prisma only supports autoincrement on `@id` fields for
this connector, so the original draft would not have generated. The write path is:

```
BEGIN
  SELECT version FROM balance_config ORDER BY version DESC LIMIT 1 FOR UPDATE
  -- assign max+1; row lock serialises concurrent writers
  UPDATE balance_config SET active = false WHERE active = true
  INSERT ... (version = max+1, active = true)
COMMIT
```

The `FOR UPDATE` lock is the second line of defence behind D10's `expectedVersion` —
D10 catches a *stale-read* overwrite, the lock catches a *simultaneous-write* race.

### 4.2 Roll provenance (additive)

```prisma
// RacePowerup
configVersion Int? @map("config_version")
```

Nullable, additive, no backfill. Rows created before this ships stay `NULL`. Set at roll
time in `openMysteryBox` / `openMysteryBoxBatch` / `rollPowerup`. This is what makes D9
auditable.

Daily-box claims are **not** stamped in this build — `DailyRewardClaim` has no natural
per-roll row for accessories, and the daily config changes far less often. Noted as a
known asymmetry rather than silently omitted.

### 4.3 Config JSON shape (v1)

```json
{
  "schemaVersion": 1,
  "rarityByType": {
    "PROTEIN_SHAKE": "COMMON", "TRAIL_MIX": "COMMON", "DETOUR_SIGN": "COMMON",
    "RUNNERS_HIGH": "COMMON", "PINECONE_TOSS": "COMMON", "TRAIL_MAGNET": "COMMON",
    "LEG_CRAMP": "UNCOMMON", "STEALTH_MODE": "UNCOMMON", "WRONG_TURN": "UNCOMMON",
    "CAMPFIRE_REST": "UNCOMMON",
    "SHORTCUT": "RARE", "COMPRESSION_SOCKS": "RARE", "LUCKY_HORSESHOE": "RARE",
    "POCKET_WATCH": "RARE", "TRAIL_MINE": "RARE", "SNEAKY_SWAP": "RARE",
    "MIRROR": "RARE", "CLEANSE": "RARE", "RED_CARD": "RARE", "SECOND_WIND": "RARE",
    "FANNY_PACK": "RARE",
    "IMPOSTER": "RARE", "RAINSTORM": "RARE", "SIGNAL_JAMMER": "RARE",
    "LEECH": "RARE", "DEFENSE_SCAN": "RARE", "HITCHHIKE": "RARE", "QUICK_RINSE": "RARE"
  },
  "dropPool": {
    "COMMON":   ["PROTEIN_SHAKE","TRAIL_MIX","DETOUR_SIGN","RUNNERS_HIGH","PINECONE_TOSS"],
    "UNCOMMON": ["LEG_CRAMP","STEALTH_MODE","WRONG_TURN"],
    "RARE":     ["RED_CARD","SECOND_WIND","COMPRESSION_SOCKS","FANNY_PACK",
                 "LUCKY_HORSESHOE","POCKET_WATCH","TRAIL_MINE","SNEAKY_SWAP",
                 "SHORTCUT","CLEANSE","MIRROR"]
  },
  "storeOnlyTypes": ["IMPOSTER","RAINSTORM","SIGNAL_JAMMER","LEECH",
                     "DEFENSE_SCAN","HITCHHIKE","QUICK_RINSE"],
  "typeWeights": { "RED_CARD": 0.5 },
  "positionOdds": { "first": [0.48, 0.25, 0.27], "last": [0.20, 0.35, 0.45] },
  "upgradeCosts": {
    "byRarity": { "COMMON": [0,5,15,45], "UNCOMMON": [0,10,30,90], "RARE": [0,15,45,135] },
    "byType": {}
  },
  "upgradeableTypes": ["PROTEIN_SHAKE","SHORTCUT","DETOUR_SIGN","TRAIL_MIX",
    "RUNNERS_HIGH","LEG_CRAMP","STEALTH_MODE","WRONG_TURN","COMPRESSION_SOCKS",
    "LUCKY_HORSESHOE","CAMPFIRE_REST","TRAIL_MAGNET","POCKET_WATCH","TRAIL_MINE",
    "PINECONE_TOSS"],
  "luckyHorseshoe": { "rareChanceByLevel": [0, 0.20, 0.45, 1.0] },
  "dailyBox": {
    "streakCap": 30,
    "odds": { "first": [0.70, 0.25, 0.05], "last": [0.20, 0.35, 0.45] },
    "coinRanges": { "COMMON": [10,30], "UNCOMMON": [40,80], "RARE_FALLBACK": [100,200] },
    "rareCoinsShare": 0,
    "accessoryWeightMode": "inverse"
  }
}
```

> ### 🔴 CORRECTED IN IMPLEMENTATION — `storeOnlyTypes` was wrong as specced
>
> The 7-item `storeOnlyTypes` above, presented as replacing
> `POWERUPS2_GATED_TYPES` / `POWERUPS3_GATED_TYPES`, **conflated two different
> exclusions and would have deleted the daily-box power-up prize pool.** Those old
> lists contain only **four** types (`DEFENSE_SCAN`, `LEECH`, `HITCHHIKE`,
> `QUICK_RINSE` — `powerupGating.js:33-34`). Imposter, Rainstorm and Signal Jammer
> have always been winnable daily-box prizes. §5.3's own example advertises
> `itemOdds.powerups: [{"type": "SIGNAL_JAMMER", ...}]`, which is impossible if
> Signal Jammer is daily-box-excluded — the spec contradicted itself.
>
> **Implemented as two keys, one authority each:**
> - `storeOnlyTypes` (7) — "can an **in-race mystery box** roll this?"
> - `dailyBoxExcludedTypes` (4) — "can the **daily box** award this?"
>
> Behaviour-preserving, config-driven, no hardcoded list. **Test #15 as written is
> wrong** and asserts the broken behaviour; it must be read as covering
> `storeOnlyTypes` for in-race drops only.

**`storeOnlyTypes`** implements D13 for **in-race drops**: it replaces the
in-race drop-exclusion use of the hardcoded lists in `powerupGating.js`. *Client-feature* gating (which
clients may *see* a type) stays in `powerupGating.js` — that is a compatibility
concern, not a balance one, and must not be admin-editable.

**`rarityByType` covers the full `PowerupType` enum**, closing audit registers #11
(RED_CARD / SECOND_WIND / FANNY_PACK missing) and #12 (LEECH / DEFENSE_SCAN / HITCHHIKE
/ QUICK_RINSE have no rarity anywhere, frontend silently defaults them to COMMON).

**`accessoryWeightMode`** ∈ `"inverse" | "uniform" | "legacy"`. Ships `"inverse"`.
`"legacy"` is the 36x prestige inversion (audit §2.5) and is retained only so a rollback
can reproduce historical behaviour — it must never be the active value in prod.

### 4.4 Migration

1. `CREATE TABLE balance_config` + `ALTER TABLE race_powerups ADD COLUMN config_version INT NULL` (both additive).
2. Insert **version 1** from current code constants with D5's two corrections.
3. No backfill. No existing row read or written.

**Rollback:** drop both; code falls back to its own defaults (D4). Safe.

---

## 5. API contract

> Pinned before either agent implements. The frontend agent implements against exactly
> this and invents nothing.

### 5.1 Admin — power-up shop items (new)

Mirrors the existing `ShopItem` admin shape (`admin.js:163-257`). `requireAuth` + `requireAdmin`.

**`GET /admin/powerup-shop/items`** → `200`
```json
{ "items": [
  { "id": "uuid", "sku": "POWERUP_LEECH", "name": "Leech", "powerupType": "LEECH",
    "priceCoins": 300, "active": true, "testOnly": true, "sortOrder": 4 }
]}
```

**`PATCH /admin/powerup-shop/items/:itemId`** — body all-optional, ≥1 key required:
```json
{ "priceCoins": 300, "active": true, "testOnly": false, "sortOrder": 4 }
```
→ `200 { "item": { ...updated } }`

| status | when |
|---|---|
| 400 | empty body; `priceCoins` not integer ≥ 0; non-boolean `active`/`testOnly` |
| 403 | not admin · 404 unknown `itemId` |

`name`/`description` are not editable — `PowerupCopy` owns copy. Deliberate.

### 5.2 Admin — balance config (new)

**`GET /admin/balance-config`** → `200`
```json
{ "version": 7, "config": { ...§4.3 }, "note": "shortcut to rare",
  "createdBy": "uuid", "boundOverride": false,
  "createdAt": "2026-07-20T12:00:00.000Z",
  "bounds": { "dailyBox.coinRanges.COMMON": [5, 500], "positionOdds.*.RARE": [0, 0.6] }
}
```
`bounds` is served so the UI can warn **before** submitting (D11/D12).

**`PUT /admin/balance-config`**
```json
{ "expectedVersion": 7,
  "config": { ...full §4.3 object },
  "note": "raise daily box coin ranges",
  "acknowledgeBoundWarnings": false }
```
→ `201 { "version": 8, "config": {...}, "warnings": [] }`

| status | when |
|---|---|
| **409** | `expectedVersion` ≠ current active version. Body: `{ "error": "stale_version", "currentVersion": 9, "config": {...current} }` so the UI can re-diff without a second request (D10). |
| **422** | one or more **soft-bound** warnings and `acknowledgeBoundWarnings` is false. Body: `{ "error": "bound_warnings", "warnings": [{ "path": "dailyBox.coinRanges.COMMON", "value": [0,0], "bound": [5,500], "message": "..." }] }`. Re-submitting with `acknowledgeBoundWarnings: true` succeeds and records `boundOverride: true` (D11). |
| 400 | **hard** validation failure (below). Never overridable. |
| 403 | not admin |

**Hard validation** (structural — always rejects):
- every `positionOdds` / `dailyBox.odds` row is 3 non-negative numbers summing to `1.0 ± 0.001`;
- every `dropPool` entry is a valid `PowerupType`, appears in `rarityByType`, and is **not** in `storeOnlyTypes`;
- `rarityByType` covers every `PowerupType` enum value;
- each `upgradeCosts.byRarity` ladder is exactly 4 entries, non-negative, `[0]` = 0, monotonically non-decreasing;
- `upgradeableTypes` ⊆ `PowerupType`, and every entry has a rarity;
- `luckyHorseshoe.rareChanceByLevel` is 4 entries in `[0,1]`, monotonically non-decreasing, last = 1.0;
- `coinRanges` are `[min, max]` with `0 <= min <= max`;
- `rareCoinsShare` ∈ `[0,1]`; `accessoryWeightMode` ∈ the enum;
- `schemaVersion` is recognised.

**Soft bounds** (warn + override, code-defined per §3.2) — initial set:

| path | sane range | rationale |
|---|---|---|
| `dailyBox.coinRanges.*` | 5 – 500 | `[0,0]` silently zeroes the largest income source |
| `positionOdds.*[RARE]` | 0 – 0.6 | >60% rare makes rares meaningless |
| `upgradeCosts.byRarity.*[3]` | 10 – 1000 | max-out cost sanity |
| `dailyBox.streakCap` | 7 – 90 | |
| `luckyHorseshoe.rareChanceByLevel[1]` | 0 – 0.5 | L1 shouldn't near-guarantee rare |

**`GET /admin/balance-config/versions?limit=50`** → `200`
```json
{ "versions": [ { "version": 7, "note": "...", "createdBy": "uuid",
                  "boundOverride": false, "createdAt": "...", "active": true } ] }
```

**`POST /admin/balance-config/rollback`** `{ "version": 6, "expectedVersion": 8 }` → `200 { "version": 9 }`
Copies v6's config into a **new** version 9 and activates it. History never rewritten.
409 semantics identical to `PUT`. 404 if the target version doesn't exist.

### 5.3 Player-facing — additive only

**`getRaceProgress` → `powerupData.dropOdds`** (beside existing `upgradeCosts` /
`capabilities` at `getRaceProgress.js:791-797`):
```json
"dropOdds": {
  "configVersion": 7,
  "position": 3, "totalParticipants": 8,
  "rarity": { "COMMON": 0.38, "UNCOMMON": 0.29, "RARE": 0.33 },
  "byType": { "SHORTCUT": 0.031, "RED_CARD": 0.015 }
}
```

**`getDailyRewardStatus` → `box.itemOdds`** (beside existing `box.powerupPool` /
`box.rarePrizeMix` at `getDailyRewardStatus.js:135-153`):
```json
"itemOdds": {
  "configVersion": 7,
  "rarity": { "COMMON": 0.44, "UNCOMMON": 0.31, "RARE": 0.25 },
  "rareMix": { "ACCESSORY": 0.4, "POWERUP": 0.4, "COINS": 0.2 },
  "accessories": [ { "sku": "cowboy_hat", "p": 0.31 } ],
  "powerups": [ { "type": "SIGNAL_JAMMER", "p": 0.5 } ]
}
```
`rareMix` **includes the COINS slice**, fixing audit register #9 (the existing
`rarePrizeMix` omits it and is wrong whenever `rareCoinsShare > 0`). `rarePrizeMix` is
left unchanged for old clients.

`byType` / `accessories` / `powerups` are **omitted entirely** (not `null`) when empty,
so clients can use presence checks.

**`getRaceProgress` → `powerupData.rarityByType`** (additive; sibling of `upgradeCosts`):
```json
"rarityByType": { "SHORTCUT": "RARE", "RUNNERS_HIGH": "COMMON", "...": "..." }
```
Served verbatim from `config.rarityByType`. **Added in revision pass 5** — the original
§5.3 defined no field carrying rarity to the client, while §6.3.B.8 instructed the
frontend to source the reel's rarity from "server `rarityByType`" and §5.4 promised the
SHORTCUT mislabel "self-heals on update". Without this field that promise was false and
new clients would mislabel SHORTCUT exactly like frozen ones.

Clients treat a partial map as partial: types named by the server override the bundled
map, unnamed types fall back. Absent block → bundled map entirely.

### 5.4 Old-client compatibility

- Every field is **new**. Nothing renamed, removed, retyped, or reinterpreted.
- `powerupData.upgradeCosts` keeps its exact current shape, now sourced from config.
- `rarePrizeMix` unchanged and still sent.
- Only player-visible behaviour change for a frozen client: values move (SHORTCUT costs
  more; daily-box weighting inverts). Both server-computed and correctly displayed.
- **Known, accepted drift:** frozen clients keep their bundled `_rarityByType` and label
  SHORTCUT `COMMON` until update. Cost is server-authoritative, so this is a
  colour/label mismatch only. Self-heals on update.

---

## 6. Implementation plan

### 6.1 Backend

**Steps 1–2 before anything else.**

1. **`prisma/seed.js`** — remove `priceCoins` and `active` from the
   `powerupShopItem.upsert` `update` block (`seed.js:234-241`); keep them in `create`.
   Comment pointing at the cosmetics precedent (`seed.js:81-87`).
2. Migration + `BalanceConfig` model + `RacePowerup.configVersion` (§4).
3. **`src/services/balanceConfig.js`** — read-through cache, **5s TTL** (D9);
   `getConfig()` merges active config over code defaults and **never throws** (D4);
   `bustCache()` on write (best-effort, local process only — the 5s TTL is what bounds
   cross-worker skew).
4. **`src/services/balanceConfig.defaults.js`** — full code defaults **and** the soft
   bounds table (§3.2). This module plus `balanceConfig.js` are the only files permitted
   to contain balance tables (enforced by test #11).
5. Rewrite as thin consumers of `getConfig()`, deleting their local tables:
   - `powerupOdds.js` — `RARITY_TIERS`, `RARITY_ORDER`, `ODDS_TABLE`, hardcoded RED_CARD halving → `typeWeights`.
   - `powerupUpgrades.js` — `RARITY_BY_TYPE`, `COSTS_BY_RARITY`, `COSTS_BY_TYPE`, `UPGRADEABLE_TYPES`.
   - `dailyBoxOdds.js` — streak curve, coin ranges, `RARITY_ORDER`; `pickWeightedByPrice` honours `accessoryWeightMode`.
   - `usePowerup.js` — `luckyMinRarity` → `rareChanceByLevel` (§6.2).
6. **`getEligiblePowerupPool.js`** — drop-exclusion now reads `config.storeOnlyTypes`
   (D13). The hardcoded `POWERUPS2/3_GATED_TYPES` lists in `powerupGating.js` remain
   **only** for client-feature gating; they are no longer consulted for drop eligibility.
7. Stamp `configVersion` at the point rarity/type is **decided** — `openMysteryBox.js`
   and `openMysteryBoxBatch.js` only. **Not** `rollPowerup.js`: it mints `MYSTERY_BOX`
   rows at step intervals and does not roll rarity, so a version stamped there would
   record a config that never influenced the outcome.
8. Admin routes (§5.1, §5.2) with `expectedVersion` / 409 / 422 semantics.
9. Player-facing `dropOdds` / `itemOdds` builders (§5.3).
10. **`scripts/balance-pull.js`** — DB → `data/balance-config.json`, mirroring
    `cosmetics-pull.js`. The committed snapshot is the git history the Leech drift lacked.
11. **Deploy-time drift report** — compares active DB config to the committed snapshot
    and **logs a warning**. Reports, never blocks (the cosmetics drift currently *aborts*
    deploys, which is worse than the problem).
12. **`scripts/generate-powerups-md.js`** — regenerates `POWERUPS.md` from active config.
    Fixes audit register #7 (documented leader RARE 5% vs actual 27%) and stops the doc
    re-rotting. CI/deploy check that the committed file matches generated output.
13. **Structural guard test** — see test #11.

### 6.2 Lucky Horseshoe (forward-only)

Replace the binary cliff (`usePowerup.js:253-255`):

```js
// before: upgradeLevel >= 3 ? "RARE" : "UNCOMMON"   // L1, L2 were no-ops
function luckyRoll(upgradeLevel, rng, config) {
  const p = config.luckyHorseshoe.rareChanceByLevel[clamp(upgradeLevel, 0, 3)];
  return rng() < p ? "RARE" : "UNCOMMON";   // floor stays UNCOMMON
}
```

Rarity is rolled at **use** time and stored in effect metadata (`minRarity`,
`consumedOnNextBox`), so effects already in flight resolve on their stored value — no
migration, no retroactive change. Existing `upgradeLevel` values untouched.

### 6.3 Frontend

Load the **mobile-design** skill before any UI work (repo rule).

**A. Admin balance editor** (new screen — this is what makes DB-authority usable)
1. New `lib/screens/admin_balance_config_screen.dart`, reachable from the existing
   `admin_screen.dart`.
2. **Structured form** (D12), sectioned: Rarity · Drop pool · Position odds · Upgrade
   ladders · Lucky Horseshoe · Daily box. Typed inputs, not raw JSON.
3. **Inline soft-bound warnings** using the `bounds` block from `GET` — warn as the user
   types, before submit.
4. **Diff preview + confirm**: before saving, show a before/after diff of changed paths
   only. Client-side diff against the fetched config; no extra endpoint.
5. **409 handling**: on stale version, show "someone else changed this", re-diff against
   the `config` returned in the 409 body, require re-confirm. Never auto-merge.
6. **422 handling**: render warnings, require an explicit "I understand" toggle that
   sets `acknowledgeBoundWarnings: true`.
7. Version history list + rollback action with the same confirm flow.

**B. Player-facing**
8. **Delete duplicated tables**, replace with server values + existing fallbacks:
   - `case_opening_strip.dart:504-525` `_rarityByType` → server `rarityByType`; bundled map becomes absent-field fallback only.
   - `case_opening_screen.dart:495-504` `_rarityColor` → delete; call existing `caseRarityColor()` (byte-identical duplicate today).
   - `race_detail_screen.dart:100-108` `_upgradeCosts` → already fallback-only; unchanged.
9. **Fix `daily_reward_screen.dart:689-706`** — `0.50 / 0.35` fallbacks match no backend
   row (actual 0.70 or 0.20). Replace with the streak-1 row `0.70 / 0.25`.
10. **Odds transparency UI**: an "Odds" affordance on case-opening and daily-reward
    screens opening a sheet rendering `dropOdds` / `itemOdds`.
    - **Absent or malformed → hide the affordance entirely.** A wrong odds display is
      worse than none.
    - States: loading (skeleton) · present (table) · absent (no entry point).
11. **iOS + Android in lockstep** — build and verify both before calling done.

---

## 7. Backward-compat & rollout

**Deploy order: backend first, then app.** Non-negotiable.

| step | action | risk |
|---|---|---|
| 1 | Deploy backend: migration + config seeded at current values | Behaviour-neutral except D5's two corrections |
| 2 | Verify `GET /admin/balance-config` returns v1; drops still roll; `configVersion` stamping | — |
| 3 | Tune on **staging** via admin, verify, promote to prod (D3) | — |
| 4 | Ship app build (admin editor + odds UI) | phased ~1 week |
| 5 | Apply the audit's **daily-box** earn-rate changes via admin | config action, not a deploy |

> ⚠️ **This build only partially delivers the audit's headline recommendation.** Audit
> §2.2 calls for raising median recurring earn velocity ~7x (6 → ~45 coins/day). Of the
> six income sources, only `daily_reward` coin ranges are in this spec's scope —
> `step_milestone`, `race_finish_reward`, `ranked_week_reward`, `ranked_promotion_bonus`
> and `ad_extra_spin` are explicit non-goals (§2). And the single largest lever, the
> **31% daily-box claim rate**, is a retention/notification problem this spec does not
> touch at all.
>
> Raising daily-box coin ranges to the §5 recommendation contributes roughly **+13
> coins/day at today's claim rate** — meaningful, but not the 7x. Closing the rest needs
> separate work: the reminder-push rollout check and a review of the other five income
> sources. Tracked, not silently dropped.

### 🔴 Hard ordering constraint

**`accessoryWeightMode: "inverse"` MUST be live before the 61 `testOnly` cosmetics are
flipped active.** Today the prestige inversion is masked because only 5 cosmetics are
purchasable (audit §2.5). Flip cosmetics first and 1500-coin accessories become the most
common daily-box drop. These must not be reordered.

### Frozen old client

| scenario | behaviour |
|---|---|
| Old app / new backend | Unchanged field shapes; new keys ignored. Costs/odds server-sourced as before. SHORTCUT labelled COMMON locally (accepted, §5.4). |
| New app / old backend | `dropOdds` / `itemOdds` absent → odds affordance hidden. Admin editor: `GET /admin/balance-config` 404s → show "not supported by this backend" rather than an empty form. |
| Backend rollback mid-rollout | Table dropped → code defaults (D4). New app hides odds UI, admin editor shows unsupported. No crash. |

No `testOnly` gating needed: the backend changes values, not surfaces; the odds UI and
admin editor both self-hide on absent fields.

---

## 8. Test plan (tests-first — written before any logic)

### Backend — `test/integration/` (real HTTP, real DB, real handler chain)
1. `PUT` with valid config + correct `expectedVersion` → 201, becomes active, `GET` returns it.
2. Each hard-validation rule (§5.2) → 400 naming the failing field (one case per rule).
3. **Stale `expectedVersion` → 409** with `currentVersion` and current `config` in the body.
4. **Concurrent writers**: two simultaneous `PUT`s at the same `expectedVersion` → exactly one 201, one 409; version sequence has no gap or duplicate. *(Timing-sensitive — drive both requests from a single test with an explicit barrier rather than relying on wall-clock overlap, or it will flake in CI.)*
5. Soft-bound violation without ack → **422** listing warnings; same body with `acknowledgeBoundWarnings: true` → 201 and `boundOverride: true` recorded.
6. Non-admin → 403 on every new route.
7. Rollback creates a *new* version with the old config; history not rewritten; stale `expectedVersion` → 409.
8. `PATCH /admin/powerup-shop/items/:id` changes price; `GET` reflects it.
9. **Seed-clobber regression:** set a price via admin, run `prisma/seed.js`, assert the admin price survives. *This is the test that would have caught the Leech drift.*
10. `getRaceProgress` includes `powerupData.dropOdds`, rarity sums to 1.0; absent when powerups disabled.
11. `getDailyRewardStatus` includes `box.itemOdds` whose `rareMix` includes COINS and sums to 1.0; `rarePrizeMix` still present and unchanged (old-client compat).
12. Opened box row has `configVersion` matching the active version (D9 provenance).
13. DB unavailable → drops still roll from defaults, no 500 (D4).
14. Config change is picked up within the 5s TTL without a restart.
15. A type in `storeOnlyTypes` never appears in a drop, and `getEligiblePowerupPool` excludes it (D13, single authority).

### Backend — unit (only where integration structurally cannot reach)
16. **Structural guard:** no rarity map, cost ladder, or odds table defined outside `balanceConfig.js` / `balanceConfig.defaults.js`. *This is what stops the 9 sites returning.*
17. Odds interpolation across positions 1..N for N=1,2,5,20, both team positions, ties — sums to 1.0, monotonic leader → trailer.
18. `luckyRoll` per level: L0 never rare, L3 always rare, L1/L2 within tolerance over a seeded run. *Fails against today's code — that is the point.*
19. Seeded Monte Carlo: no store-only or retired type ever drops.
20. `POWERUPS.md` generator output matches the committed file.

### Frontend — widget/integration (pump the real screen)
21. Race detail with `dropOdds` → affordance visible, values match payload.
22. `dropOdds` absent → affordance **not** rendered, screen otherwise unchanged.
23. `dropOdds` malformed (rarity sums to 0.4) → affordance not rendered, no crash.
24. Daily reward with `itemOdds` → sheet renders accessory + powerup + coins slices.
25. Server `rarityByType` overrides the bundled map in the case-opening reel.
26. Server absent → bundled fallback used, reel still renders.
27. **Admin editor:** edit a field → diff preview lists exactly that path, confirm → `PUT` sent with correct `expectedVersion`.
28. **Admin editor 409:** stale save → conflict UI shown, no silent overwrite, re-diff against returned config.
29. **Admin editor 422:** bound warning rendered; save blocked until the ack toggle is set.

**Never modify or delete an existing test.** Three existing fixtures disagree on the
Leech price (300 / 300 / 150 — audit §2.1); surface to the owner, do not "fix".

---

## 9. Acceptance criteria

- [ ] One canonical rarity per power-up; structural guard test passes.
- [ ] `upgradeCost()` resolves from the same rarity the drop pool uses.
- [ ] SHORTCUT is RARE; new upgrades cost `[0,15,45,135]`. Existing `upgradeLevel` untouched.
- [ ] Lucky Horseshoe L1/L2 have measurable effect; L0 never rare, L3 always rare.
- [ ] Running `prisma/seed.js` cannot change an admin-set price or `active`.
- [ ] Admin can edit every balance value in a structured form, see a diff before saving, view history, and roll back.
- [ ] Concurrent admin saves cannot silently overwrite each other (409).
- [ ] Out-of-range values warn and require explicit override, recorded in history.
- [ ] Every rolled box records the `configVersion` that produced it.
- [ ] `storeOnlyTypes` is the single drop-exclusion authority.
- [ ] All distributions sum to 1.0; monotonic leader → trailer.
- [ ] `accessoryWeightMode: "inverse"` live **before** any cosmetic `testOnly` flip.
- [ ] `POWERUPS.md` generated, matches config.
- [ ] Odds UI renders when present, hides cleanly when absent/malformed.
- [ ] Old-client scenarios in §7 verified.
- [ ] iOS **and** Android built and verified.
- [ ] No retroactive change to any existing row.

---

## 10. Revision log

**Pass 1 (during drafting).** Moved balance config out of `AppSetting` — it is
boolean-only at the route guard (`admin.js:138-140`) and per-environment/non-mirrored, so
it could hold neither the JSON shape nor a promote workflow (D1). Added versioning +
rollback with copy-forward semantics (D2).

**Pass 2 (during drafting).** Made `accessoryWeightMode: "inverse"` an explicit exception
to D5 — seeding "current values" would have shipped the 36x prestige inversion into a
system that makes it harder to notice — and promoted the cosmetic-flip ordering
constraint to a 🔴 callout. Required `rarityByType` to cover the full enum, closing
registers #11/#12 rather than preserving them. Documented that horseshoe rarity is
rolled at use time, which is what makes "forward-only" actually hold.

> **Correction:** passes 1 and 2 were made *while drafting*, not as independent re-reads
> of the finished document, and the original log overstated them. The pass below is the
> first genuine fresh-eyes review.

**Pass 3 (genuine fresh-eyes re-read).** Seven gaps, four of which needed owner input:
1. **Multi-process cache incoherence.** The draft copied `appSettings.js`'s 30s TTL
   without noticing pm2 runs cluster mode and that odds have different semantics from
   boolean flags — different workers would roll from different configs, and displayed
   odds could disagree with the roll. → D9 (5s read-through + `configVersion` stamped on
   every roll), with §3.1 stating honestly that this buys auditability, not prevention.
2. **No optimistic concurrency.** `PUT` took a full config with no `expectedVersion`, so
   two admins would silently overwrite each other — the same silent-overwrite class as
   the Leech drift this spec exists to prevent. → D10, 409, plus a `FOR UPDATE` lock in
   §4.1 for the simultaneous-write case the version check can't catch.
3. **No admin UI at all.** The owner chose "DB is authority, *admin UI edits it*" and the
   frontend plan covered only player-facing work. The authority model was unusable as
   written. → §6.3.A.
4. **No value guardrails.** Structural validation passed `[0,0]` coin ranges and 100%
   RARE odds. → D11 soft bounds with 422 + explicit override, and §3.2 explaining why
   bounds must live in code (config-stored bounds are circular).
5. **`version Int @default(autoincrement())` on a non-`@id` column** would not have
   generated. → app-assigned inside the write transaction (§4.1).
6. **Two exclusion authorities.** The draft cross-validated `dropPool` against
   `getEligiblePowerupPool`'s hardcoded lists, which is two authorities — the exact
   problem being solved. → D13 + `storeOnlyTypes`, with client-feature gating explicitly
   left in `powerupGating.js` as a compatibility concern that must not be admin-editable.
7. **`POWERUPS.md` unaddressed** despite being an audit acceptance criterion. → §6.1.12
   generator + CI check.

Also added `upgradeableTypes` to config (it was still going to be a hardcoded list in
`powerupUpgrades.js`, quietly violating the single-source goal) and documented the
daily-box provenance asymmetry in §4.2 rather than omitting it silently.

**Owner interview (Phase 3).** Four decisions taken: 5s read-through + roll stamping;
structured admin form with diff preview; soft bounds with warn-and-override; single
combined build rather than split delivery.

**Pass 4 (second genuine fresh-eyes re-read, post-interview).** Three issues:
1. **Internal contradiction.** §7 step 5 said "apply the audit's earn-rate changes via
   admin", but §2's non-goals exclude five of the six income sources, and the largest
   lever (31% claim rate) isn't a config value at all. The spec was quietly promising
   the audit's headline outcome while scoping out most of its means. → §7 now states
   plainly that this build delivers roughly +13 coins/day of the needed ~39, and names
   the follow-up work instead of leaving it implied.
2. **Wrong stamping site.** §6.1.7 listed `rollPowerup.js` among the `configVersion`
   stamp points, but it mints `MYSTERY_BOX` rows at step intervals and never rolls
   rarity — stamping there records a config that didn't influence the outcome, making
   the provenance trail misleading rather than absent. → restricted to the two commands
   that actually decide rarity.
3. **Flaky-test risk.** Test #4 (concurrent writers) as written depends on wall-clock
   overlap. → noted that it needs an explicit barrier.

**Open questions:** none.

**Known scope limits, stated rather than hidden:** the earn-rate gap above; daily-box
rolls are not version-stamped (§4.2); frozen clients will mislabel SHORTCUT's rarity
until they update (§5.4); and `accessoryWeightMode: "legacy"` remains selectable so
rollback can reproduce history, which means the 36x inversion is one admin action away
and is guarded only by the soft-bounds warning.
