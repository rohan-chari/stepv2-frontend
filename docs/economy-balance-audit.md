# Economy and Power-Up Balance Audit

**Date:** 2026-07-20
**Scope:** shop power-ups, race drop power-ups, cosmetics, upgrade ladders, daily box.
**Status:** findings + recommendations. No production change, DB write, or catalog
update was made as part of this audit. One source-only correction was applied
(`prisma/seed.js` Leech price — see §2.1) because it was an active regression risk.

---

## 1. Method and data provenance

- **Source inventory:** full read of both repos (`stepv2-backend`, `stepv2-frontend`).
- **Live data:** read-only aggregate queries against the prod DB with
  `default_transaction_read_only = on` and a statement timeout. **Aggregates only** —
  no user-level rows were read or retained, and every reported segment has n ≥ 5.
- **A prod dump was deliberately NOT used.** `BACKUP.md:54-65` mandates deleting local
  dumps because they contain the full users table (PII). A dump present at the start of
  this session had already been correctly removed by that procedure.
- Population at time of audit: **111 real (non-review) users; 94 active in 30d; 86 in 7d.**

> **Caveat on N.** 94 active users is a small economy. Percentiles are stable enough to
> act on, but per-type drop statistics with fewer than ~50 events are indicative only.
> This is flagged inline where it matters.

---

## 2. Headline findings

### 2.1 Leech price drift — CONFIRMED, and it was armed to reverse ✅ fixed

| | Leech price |
|---|---|
| prod `powerup_shop_items` | **300** |
| `prisma/seed.js` (source) | **150** |

300 is the intended price (owner-confirmed). The danger was not the drift itself but
its direction of travel: `node prisma/seed.js` runs on **every deploy**
(`DEPLOY_RUNBOOK.md:80`, `DEPLOYMENT.md:104`), and the `powerupShopItem.upsert`
`update` block **includes `priceCoins` and `active`** (`seed.js:234-241`). It
deliberately omits `testOnly` — so the author understood the semantics, but price and
active were left exposed.

**The next deploy would have silently reset Leech from 300 → 150**, with no error and
no log line. Source corrected to 300 with an explanatory comment (`seed.js:173`).

This is the same failure class as the tuner `renderMetadata` wipe, and it is the single
strongest argument for versioned balance config regardless of where authority lives.

**Also exposed by the same mechanism:** `active` is clobbered. Re-enabling Cleanse (or
retiring anything) via the DB is undone by the next deploy.

### 2.2 The whole economy is ~7x too expensive for the median player 🔴

This is the most important finding in the audit, and it reframes every price question.

**Recurring earn velocity, active users, 30-day window** (excludes referrals, admin
grants, refunds, and redistributed buy-in pots, per the philosophy's own rule):

| percentile | coins/day |
|---|---|
| p25 | 2.3 |
| **median** | **6.0** |
| p75 | 15.3 |
| p90 | 73.5 |

The mean is 19.0 — **badly skewed by whales**. Any pricing decision made off the mean
is a decision made for the top decile. Median balance is 155 coins (p25 55, p75 369,
p90 975, max 4,562).

Against the stated philosophy:

| goal | target | actual @ median 6/day | gap |
|---|---|---|---|
| Small power-up | 1–2 active days | 75 coins = **12.5 days** | **6–12x** |
| Standard cosmetic | 1–2 active weeks | 250 coins = **42 days (6 wk)** | **3–6x** |
| Prestige cosmetic | 4–8 active weeks | 1500 coins = **250 days (36 wk)** | **4.5–9x** |

Even at **p75** (15.3/day) a prestige cosmetic is 98 days ≈ 14 weeks — still ~2x the
target ceiling.

**The prices are not the problem. The earn rate is.** Solve for the velocity that makes
the *existing* ladder hit the stated targets:

| item | price | days @ 45/day | target | fit |
|---|---|---|---|---|
| small power-up | 75 | 1.7 d | 1–2 d | ✅ |
| Leech | 300 | 6.7 d | — | ✅ |
| entry cosmetic | 250 | 5.6 d | 7–14 d | slightly fast |
| standard cosmetic | 500 | 11.1 d | 7–14 d | ✅ |
| upper cosmetic | 1000 | 22 d (3.2 wk) | — | ✅ |
| prestige cosmetic | 1500 | 33 d (4.8 wk) | 4–8 wk | ✅ |

**A median recurring velocity of ~40–45 coins/day makes the current price ladder land
almost exactly on the stated philosophy.** Today's median is 6.

**Recommendation: raise earn velocity ~7x; do not gut prices.** Cutting a prestige
cosmetic to 200 coins to fit a broken earn rate destroys the prestige anchoring the
philosophy explicitly asks for (exclusivity, visual prominence, collection role). The
only price nudge worth making is entry cosmetics **250 → 350**, to restore separation
from the small-power-up band.

**Where the 7x comes from — two levers, both needed:**

- **Claim rate.** `daily_reward` fired 664 times across 72 users in 30 days ≈ **31% of
  eligible days claimed**. The single largest income source is being left on the table
  by ~2 in 3 users on any given day. Retention/notification work here is worth more than
  any coin-value change.
- **Per-claim value.** Mean daily reward is **32.9 coins/claim** (`21,864 / 664`),
  consistent with `DAILY_BOX_COIN_RANGES` COMMON `[10,30]` / UNCOMMON `[40,80]`
  (`dailyBoxOdds.js:21-25`).

Neither lever alone gets to 45/day. Exact recommended curves in §5.

### 2.3 The rarity fracture is a half-finished migration, and it is costing real coins 🔴

Three tables define power-up rarity and they disagree:

| type | `powerupOdds.js:4-8` (drop) | `powerupUpgrades.js:34-69` (price) | frontend `case_opening_strip.dart:504-525` |
|---|---|---|---|
| **SHORTCUT** | **RARE** | **COMMON** | COMMON |
| **RUNNERS_HIGH** | **COMMON** | **UNCOMMON** | UNCOMMON |
| **PINECONE_TOSS** | **COMMON** | **UNCOMMON** | UNCOMMON |

Prod drop history proves these are **migration artifacts**, not design intent — each of
these types has records under *both* rarities:

| type | drops as common | drops as uncommon | drops as rare |
|---|---|---|---|
| shortcut | 1,290 | — | **57** |
| runners_high | **133** | 479 | — |
| pinecone_toss | **159** | 457 | — |

Someone retiered these in `powerupOdds.js` and never updated `RARITY_BY_TYPE`.

**Why it costs coins:** `upgradeCost()` (`powerupUpgrades.js:103-114`) resolves price
via `RARITY_BY_TYPE`, not the drop table. So:

> **SHORTCUT drops from the RARE tier but upgrades on the COMMON ladder** —
> `[0,5,15,45]` = **65 coins to max**, instead of RARE's `[0,15,45,135]` = **195**.

And SHORTCUT is not a marginal power-up. It is:
- the **#1 coin sink in the entire game** — 9,210 coins across 19 users, more than all
  cosmetic purchases combined (7,250);
- **100% used** when it drops as rare (57/57) — the most desirable item in the pool.

The strongest power-up in the game is simultaneously the cheapest to max out. That is
exactly backwards, and the 190 upgrade purchases show players found the arbitrage.

**Recommendation:** SHORTCUT is RARE (the drop table is the newer, intentional value).
Correcting the ladder raises its max-out cost 65 → 195. Note this is a **price rise on
a popular item** — see §6 for rollout handling of already-upgraded copies.

### 2.4 Lucky Horseshoe sells upgrades that do nothing 🔴 player-trust issue

`luckyMinRarity()` (`usePowerup.js:253-255`):

```js
upgradeLevel >= 3 ? "RARE" : "UNCOMMON"
```

**Levels 1 and 2 have no mechanical effect whatsoever.** Level 0, 1 and 2 all guarantee
UNCOMMON. Only level 3 changes anything.

But the upgrade tier labels sold to players (`powerup_copy.dart:490-495`) read
"Better rare odds" / "Strong rare odds".

**Prod confirms every horseshoe upgrade ever sold was worthless:**

| tier reached | purchases | users | coins |
|---|---|---|---|
| 1 | 3 | 3 | 280 |

Max tier ever reached is **1**. No player has ever reached level 3 — the only level that
does anything. 280 coins were sold for a strictly null effect, against copy that
promised an improvement.

Small in absolute terms (3 users, n < 5 — reported as a *mechanism* finding, not a
segment statistic), but it is a correctness and trust defect, not a balance opinion.

**Recommendation:** make L1/L2 mechanical — graduated rare *probability* (e.g. L0 = min
UNCOMMON, L1 = min UNCOMMON + 15% rare floor, L2 = +30%, L3 = min RARE) — or remove
LUCKY_HORSESHOE from `UPGRADEABLE_TYPES` and refund. Do not ship copy promising an
effect the code does not implement.

### 2.5 The daily box makes your rarest cosmetics your most common drops 🔴

`pickWeightedByPrice()` (`dailyBoxOdds.js:136-150`):

```js
exponent = 1 + t                              // t = streak progress, 0→1 over 30 days
weight_i = max(1, priceCoins_i) ^ exponent
```

Weight is **monotonically increasing** in price. Prod cosmetics span 250 → 1500, so at
streak cap a 1500-coin accessory is `(1500/250)^2` = **36x more likely** than a
250-coin one.

The prestige tier — the items the philosophy wants gated behind 4–8 weeks of play — is
the tier the daily box hands out most often.

The comment at `dailyBoxOdds.js:134` correctly describes the code ("weight grows with
priceCoins"). The comment at `:157-160` claims the opposite ("pricier powerups are
*rarer*") and **contradicts itself within one sentence**. The audit scope doc inherited
the confused framing and pointed it at power-ups; power-ups are all 75/150 so the effect
there is minor. **The damage is on cosmetics.**

**Recommendation:** invert to `weight ∝ 1 / price^(1+t)`, or better, decouple entirely —
give each cosmetic an explicit `dropWeight` independent of price, per the philosophy's
own "do not reuse store price as a positive probability weight."

**Note:** this is currently masked in prod. Only **5 cosmetics are purchasable**
(61 of 68 are `testOnly`, 1 inactive, 1 earn-only), so the accessory pool is nearly
empty and `dailyBoxOddsForPool` folds RARE toward 0. **The 36x skew goes live the moment
the testOnly cosmetics ship.** Fix before that rollout, not after.

### 2.6 Sink concentration: upgrades dominate, and it's ~1 in 5 users

The scope doc's claim that upgrade pricing is the largest discretionary sink —
which I could not substantiate from source — **is confirmed by prod data.**

30-day discretionary spend:

| sink | coins | users | share |
|---|---|---|---|
| **power-up upgrades** | **17,575** | 22 | **57%** |
| cosmetics | 7,250 | 13 | 24% |
| power-up purchases | 5,775 | 8 | 19% |

Upgrades are more than half of all spending, concentrated in 22 of 94 active users
(~800 coins each). Race buy-ins (11,780 held) are mostly redistribution, not a sink —
9,355 paid out + 800 refunded, so only ~1,625 is actually destroyed.

Two implications:
- Upgrade ladders are the highest-leverage pricing surface in the game. They are also
  currently the *least* governed — hardcoded in `powerupUpgrades.js`, duplicated in the
  frontend, with no admin surface.
- 76% of active users spend nothing at all. Combined with §2.2, the likeliest reading is
  that most players never accumulate enough to participate in the economy.

### 2.7 Items players reject

Use rates from prod (all-time, n ≥ 100):

| type | rarity | drops | use % | discarded | expired |
|---|---|---|---|---|---|
| cleanse | uncommon | 366 | **49.5%** | 67 | 118 |
| pocket_watch | rare | 284 | **56.7%** | 45 | 73 |
| sneaky_swap | rare | 285 | **67.4%** | 42 | 47 |
| runners_high | common | 133 | 78.2% | 0 | 23 |
| detour_sign | common | 1,385 | 84.1% | 149 | 65 |
| *(everything else)* | | | 86–99% | | |

**Cleanse is retired from the shop (`active: false`) but still drops** — deliberately
(`seed.js:145-149`) — and is rejected half the time. It occupies RARE-tier drop mass it
does not earn. **Pocket Watch and Sneaky Swap are RARE-tier drops with the two worst use
rates in the game** — they are taking slots from items players actually want.

---

## 3. Prioritized inconsistency register

| # | severity | issue | evidence |
|---|---|---|---|
| 1 | 🔴 | Deploy-time seed clobbers live `priceCoins` + `active` | `seed.js:234-241`, `DEPLOY_RUNBOOK.md:80` |
| 2 | 🔴 | SHORTCUT: RARE drop on COMMON upgrade ladder (#1 sink) | §2.3 |
| 3 | 🔴 | Median earn velocity ~7x below what the price ladder assumes | §2.2 |
| 4 | 🔴 | Lucky Horseshoe L1/L2 are no-ops sold with effect copy | §2.4 |
| 5 | 🔴 | Daily box price-weighting inverts cosmetic prestige (36x) | §2.5 |
| 6 | 🟠 | RUNNERS_HIGH / PINECONE_TOSS rarity disagreement | §2.3 |
| 7 | 🟠 | `POWERUPS.md` leader RARE odds documented 5%, actual **27%** | `POWERUPS.md:67` vs `powerupOdds.js:22` |
| 8 | 🟠 | Frontend daily-box fallback odds `0.50/0.35` match **no** backend row (0.70 or 0.20) | `daily_reward_screen.dart:689-706` |
| 9 | 🟠 | `rarePrizeMix` ignores the coins slice — advertised odds wrong if `DAILY_SPIN_RARE_COINS_SHARE` > 0 | `getDailyRewardStatus.js:137-152` |
| 10 | 🟠 | No admin surface for `PowerupShopItem` at all (cosmetics have one) | `admin.js` |
| 11 | 🟡 | RED_CARD / SECOND_WIND / FANNY_PACK missing from `RARITY_BY_TYPE` — latent throw if ever made upgradeable | `powerupUpgrades.js:34-69` |
| 12 | 🟡 | LEECH / DEFENSE_SCAN / HITCHHIKE / QUICK_RINSE have no rarity anywhere; frontend defaults to COMMON | `case_opening_strip.dart:581` |
| 13 | 🟡 | 3 duplicate `RARITY_ORDER` arrays; 2 byte-identical rarity→color maps | `powerupOdds.js:10`, `dailyBoxOdds.js:6`; `case_opening_strip.dart:401`, `case_opening_screen.dart:495` |
| 14 | 🟡 | `POWERUPS.md` claims equal within-tier odds; RED_CARD is halved | `powerupOdds.js:67-70` |
| 15 | 🟡 | Two independent implementations of the RARE sub-roll | `claimDailyRewardBox.js` / `claimExtraDailyRewardBox.js` |
| 16 | 🟡 | Cleanse retired but still drops at 49.5% use | §2.7 |
| 17 | 🟡 | Latent non-uniform fallback: hard-picks `RARITY_TIERS[min][0]` (always LEG_CRAMP / RED_CARD) | `openMysteryBox.js:104-107` |
| 18 | 🟡 | `PowerupCopy.isUpgradeable()` derives upgradeability from *label presence* — a copy edit can silently change mechanics | `powerup_copy.dart:250` |

---

## 4. Recommended power-up rarity (single canonical set)

Resolve every conflict toward the **drop table** (`powerupOdds.js`), which holds the
newer intentional values, then propagate to pricing and display.

| type | canonical rarity | change | upgrade ladder |
|---|---|---|---|
| PROTEIN_SHAKE, TRAIL_MIX, DETOUR_SIGN | COMMON | — | `[0,5,15,45]` |
| **RUNNERS_HIGH** | **COMMON** | ⬇ from UNCOMMON | `[0,5,15,45]` (was 10/30/90) |
| **PINECONE_TOSS** | **COMMON** | ⬇ from UNCOMMON | `[0,5,15,45]` (was 10/30/90) |
| LEG_CRAMP, STEALTH_MODE, WRONG_TURN | UNCOMMON | — | `[0,10,30,90]` |
| **SHORTCUT** | **RARE** | ⬆ from COMMON | **`[0,15,45,135]`** (was 5/15/45) |
| COMPRESSION_SOCKS, LUCKY_HORSESHOE, POCKET_WATCH, TRAIL_MINE, SNEAKY_SWAP, MIRROR, RED_CARD, SECOND_WIND, FANNY_PACK, CLEANSE | RARE | — | `[0,15,45,135]` |
| TRAIL_MAGNET, CAMPFIRE_REST | *(not generated)* | retire from ladders or restore to pool — currently orphaned | — |
| IMPOSTER, RAINSTORM, SIGNAL_JAMMER, LEECH, DEFENSE_SCAN, HITCHHIKE, QUICK_RINSE | store-only | assign explicit rarity for display | n/a |

Net effect: SHORTCUT costs 3x more to max (correct — it is a rare); RUNNERS_HIGH and
PINECONE_TOSS get cheaper (correct — they are commons). Two of three moves are player-
favourable, which softens the SHORTCUT rise.

---

## 5. Recommended daily box changes

1. **Invert or decouple the price weighting** (§2.5). Preferred: explicit `dropWeight`
   per cosmetic, defaulting to `1/price` normalized. **Must land before the 61 testOnly
   cosmetics ship.**
2. **Raise coin ranges** toward the 45/day target — proposed
   COMMON `[25,60]`, UNCOMMON `[80,160]`, RARE_FALLBACK `[200,400]`
   (≈2.2x current, contributing ~+40/day at 100% claim rate, ~+13/day at today's 31%).
3. **Attack the 31% claim rate** — this is worth more than (2). The reminder pushes are
   built but shipped dark; flipping them on is the highest-ROI action in this audit.
4. **Fix `rarePrizeMix`** to include the coins slice (register #9).
5. **Fix the frontend `0.50/0.35` fallbacks** to a real row (register #8).

Coin-range changes are **safe for frozen clients** — old apps display whatever the
server sends. The claim-rate work is likewise server-side.

---

## 6. Backward compatibility and rollout

Deploy order is **backend first, then app**, per repo policy.

| change | frozen old client behaviour | safe? |
|---|---|---|
| Coin range / odds curve changes | server-computed; client displays what it's given | ✅ |
| Rarity corrections (SHORTCUT et al.) | old clients keep their bundled `_rarityByType` → will show SHORTCUT as COMMON until they update. Cosmetic only; cost is server-authoritative via `powerupData.upgradeCosts` | ✅ (visual drift only, self-heals on update) |
| Upgrade ladder changes | already server-shipped (`getRaceProgress.js:791`), client tables are fallback-only (`race_detail_screen.dart:96-99`) | ✅ |
| Daily-box weight changes | server-side | ✅ |
| Leech 300 in source | matches prod; no client impact | ✅ |
| New `dropWeight` / rarity fields | additive only; absent-field fallback already the established pattern (`box.powerupPool`, `powerupData.capabilities`) | ✅ |

**Already-upgraded SHORTCUT copies:** raising the ladder must **not** retroactively
charge or downgrade existing `upgrade_level` values. Grandfather them — 190 upgrades
across 19 users are already applied. Charge the new price only for upgrades purchased
after the change.

**Do not** ship the cosmetic `testOnly` flip and the daily-box weighting fix in
opposite order (§2.5).

---

## 7. Acceptance criteria

- [ ] One canonical rarity per power-up; no code path defines a second table.
- [ ] `upgradeCost()` resolves from the same rarity the drop pool uses.
- [ ] All rarity distributions sum to 1.0 and remain monotonic leader → trailer.
- [ ] No drop pool contains a retired or store-only type.
- [ ] Lucky Horseshoe L1/L2 either do something or are not sold.
- [ ] Daily-box cosmetic weighting is not positively correlated with price.
- [ ] `POWERUPS.md` regenerated from code, not hand-maintained.
- [ ] Median recurring earn velocity ≥ 40 coins/day, measured 30d post-change.
- [ ] Deploy-time seed can no longer overwrite a live-tuned price.
- [ ] Every change verified against a frozen-old-client scenario.

---

## 8. Telemetry to monitor post-rollout

Median/p25/p75 recurring coins/day · daily-box claim rate · median balance ·
SHORTCUT upgrade volume (expect a drop at 195) · per-type use/discard rates ·
cosmetic purchase rate after the earn-rate change · balance Gini (whale concentration).

**Rollback thresholds:** daily-box claim rate falls below 25%; median balance falls;
SHORTCUT upgrade volume falls >80% (over-corrected); any drop distribution failing to
sum to 1.0.

---

## 9. Companion document

The single-source-of-truth implementation is specified separately in
`docs/balance-config-requirements.md`. This audit deliberately contains **no**
implementation instructions beyond the values above.

---

## Revision log

**Pass 1 (fresh-eyes).** Original scope doc asserted three claims that source could not
support: live Leech = 300 (unverifiable in-repo → confirmed against prod), "upgrade
pricing is the largest discretionary sink" (unsubstantiated → confirmed at 57% of
spend), and the `priceCoins` contradiction framed as a power-up problem (→ corrected;
the material impact is on cosmetics, 36x, currently masked by the testOnly gate).

**Pass 2 (fresh-eyes).** Found the earn-velocity gap (§2.2) by testing the philosophy's
affordability targets against measured data rather than assuming prices were the free
variable — this inverted the audit's central recommendation from "reprice items" to
"raise earn rate, keep the ladder." Also caught that the mean (19/day) and median
(6/day) diverge 3x, so any mean-based conclusion silently prices for the top decile.
Added the Lucky Horseshoe no-op finding (§2.4) and the SHORTCUT migration-artifact
evidence (§2.3) after checking historical drop records for multi-rarity rows.
