# economy.md — the living economy model

**Owner:** `game-analyst` agent. Factual model only — analysis, verdicts and
recommendations live in agent reports, not here.

**Location note:** this file lives in the **frontend** repo alongside its seed
material (`docs/economy-balance-audit.md`, `docs/game-logic-audit.md`). It
documents backend behaviour; backend paths below are relative to
`/Users/rohan/repos/stepv2-backend`.

**Source-of-truth key**

| Tag | Meaning |
|---|---|
| `DB` | prod Postgres row — authoritative at runtime |
| `SEED` | `prisma/seed.js` — re-run on **every deploy**, can clobber DB |
| `CODE` | JS constant / default |
| `ENV` | droplet env var, read per call |

Where `DB` and `SEED`/`CODE` disagree, `DB` wins at runtime unless the seed's
`update` block reasserts the field on deploy.

---

## 0. Population baseline — verified 2026-08-08 (prod, read-only)

| Metric | Value | Source |
|---|---|---|
| Users with steps in 30d | 112 | `DB steps` |
| Steps/day (rows with steps>0, 30d) | p10 1,257 · **p50 5,775** · p90 13,948 · p99 21,901 · mean 6,869 | `DB steps` (n=2,545 user-days) |
| Coins earned per **active day** (users with ≥7 active days) | p10 0 · **p50 3** · p90 98 · max 296 · mean 33 | `DB coin_transactions` (n=92 users) |
| Coins earned per **earning day** (days with ≥1 positive txn) | p10 10 · p50 45 · p90 260 · p99 683 | `DB coin_transactions` (n=833 user-days) |
| Concurrent races per user-day | p50 3 · p90 7 · max 13 | `DB race_powerups` |
| Powerups minted per user-day | p50 6 · p90 36 · max 94 · mean 13.1 | `DB race_powerups` (n=956 user-days) |
| Powerups **wasted** (expired/discarded) per user-day | p50 2 · p90 5 · max 15 · mean 2.5 | `DB race_powerups` |

> **Median income is 3 coins/active-day**, not the ~6 quoted in
> `economy-balance-audit.md` (2026-07-20). The economy is *under-supplied*
> relative to its price list: the cheapest active cosmetic (250) is **83 days**
> of median play; the cheapest active store powerup (40) is **13 days**.

---

## 1. Coin sources — measured, 30 days to 2026-08-08

| Reason | Coins/day (app-wide) | Users | Rate / rule | Source |
|---|---|---|---|---|
| `daily_reward` | 780.7 | 71 | ladder `[10,20,30,40,50]` over a 6-day cycle; day 6 = unowned accessory, else 100 | `CODE src/modules/economy/constants/dailyReward.js:4-6` |
| `step_milestone` | 425.3 | 45 | 5k→10, 10k→20, 15k→30, 20k→50; cap 110/day | `CODE src/modules/steps/constants/stepMilestones.js:5-10` |
| `ad_extra_spin` | 299.7 | 15 | rewarded-ad extra daily spin (iOS only, SSV-verified) | `CODE src/modules/economy/adRewards.js` |
| `race_prize_pool_payout` | 296.7 | 31 | app-funded pools, see §4 | `CODE src/shared/economy/prizePool.js` |
| `race_buy_in_payout` | 294.9 | 20 | legacy buy-in pots (redistribution, not minting) | `CODE racePayoutPresets.js` |
| `race_finish_reward` | 268.3 | 20 | seeded daily/weekly challenges (legacy path, non-funded only) | `CODE races/constants/raceFinishReward.js:24-46` |
| `ad_coin_reward` | 123.3 | 9 | `AD_COIN_REWARD_AMOUNT` × `AD_COIN_REWARD_DAILY_CAP`; prod = **25 × 3 = 75/day** | `ENV` |
| `referral_reward` | 100.0 | 5 | one payout per provider identity | `CODE social/` |
| `tutorial_complete` | 73.3 | 22 | 100 one-off | `CODE` |
| `tournament_champion_reward` | 55.0 | 7 | funded, capped by `MAX_CHAMPION_PRIZE` | `CODE tournaments/` |
| others (`manual_grant`, `mystery_potion_refund`, refunds, `bounty_payout`, `piggy_bank`, `admin_grant`) | ~96 | — | — | `DB` |
| **Total sources** | **≈ 2,813 / day** | | | |

## 2. Coin sinks — same window

| Reason | Coins/day | Users | Source |
|---|---|---|---|
| `powerup_purchase` | −914.2 | 14 | `DB powerup_shop_items.price_coins` |
| `powerup_upgrade` | −628.5 | 27 | §3.4 |
| `shop_purchase` (cosmetics) | −216.7 | 9 | `DB shop_items.price_coins` |
| `race_buy_in_hold` | −146.6 | 35 | returns as `race_buy_in_payout` |
| `powerup_unlock_ads` | −11.0 | 1 | partial ad-funded unlock |
| **Total sinks** | **≈ −1,917 / day** (≈ −1,770 excl. buy-in holds) | | |

**Net ≈ +900 coins/day** app-wide (≈ +8 coins/day/active user).

---

## 3. Powerups

### 3.1 Store catalog — `DB powerup_shop_items`, verified 2026-08-08

Enum labels in this table are **lowercase**.

| Price | Active | Inactive (`active=false`) |
|---|---|---|
| 40 | `defense_scan` | `coin_flip`, `mystery_potion`(testOnly), `piggy_bank`, `pocket_watch` |
| 75 | `rainstorm`, `quick_rinse` | `imposter`, `signal_jammer`, `umbrella`, `bounty` |
| 150 | `ghost_pepper`, `decoy`, `power_outage` | `cleanse`, `hitchhike`, `rally_flag`, `drill_sergeant` |
| 300 | `leech` | `quicksand`, `uprising` |

**Cheapest purchasable powerup = 40 coins.** `SEED prisma/seed.js` still carries
different prices for some rows; its `update` block deliberately omits
`priceCoins`/`active` for the powerup upsert (see `admin/routes.js:492`) — do not
re-add them.

### 3.2 Rarity + drop pool — `DB balance_config` **v4** (`86a0d190-a45d-4937-bfe4-80badee7f82b`, created 2026-08-10 15:37:51) — verified 2026-08-10

Batch 2026-08-09 landed as config **version 4**. The live row now differs from
the v3 description that follows it; v4 is authoritative:

```
dropPool.COMMON   = PROTEIN_SHAKE, TRAIL_MIX, DETOUR_SIGN, RUNNERS_HIGH, PINECONE_TOSS   (unchanged)
dropPool.UNCOMMON = LEG_CRAMP, STEALTH_MODE, WRONG_TURN, RALLY_FLAG                       (unchanged)
dropPool.RARE     = RED_CARD, SECOND_WIND, COMPRESSION_SOCKS, LUCKY_HORSESHOE, TRAIL_MINE,
                    SNEAKY_SWAP, SHORTCUT, CLEANSE, MIRROR, POWER_OUTAGE
                    <- FANNY_PACK REMOVED, POWER_OUTAGE ADDED (total weight still 9.5)
positionOdds        first [0.48,0.25,0.27] / last [0.20,0.35,0.45]   (unchanged)
positionRules.leadingDownweight  = { RUNNERS_HIGH 0.5, POWER_OUTAGE 0.3 }   <- PO added
positionRules.trailingDownweight = { CLEANSE 0.5, MIRROR 0.5, STEALTH_MODE 0.5 } (unchanged)
typeWeights         = { RED_CARD: 0.5 }        teamOnlyTypes = [RALLY_FLAG]
luckyHorseshoe.rareChanceByLevel = [1, 1, 1, 1]   <- 100% forced RARE at every level
upgradeCosts.byType = { LEG_CRAMP [0,10,20,30], WRONG_TURN [0,15,30,45],
                        LUCKY_HORSESHOE [0,0,0,0] }   <- was {} in v3
rarityByType        WRONG_TURN RARE, SNEAKY_SWAP UNCOMMON, POWER_OUTAGE RARE, FANNY_PACK RARE
```

Consequence for §3.4: `LEG_CRAMP` and `WRONG_TURN` now charge the **arithmetic
`byType` ladders**, not `byRarity` — the §3.3f "Wrong Turn pays the RARE ladder"
drift is now priced around rather than reconciled (`rarityByType.WRONG_TURN` is
still `RARE`). `FANNY_PACK` is no longer rollable, so the Fanny-Pack rejection
loops in `openMysteryBox.js` / `rerollMysteryBox.js` are dead code.

### 3.2b Previous row — v3 (`5ba76396…`, created 2026-07-28 09:46:24), superseded

The DB row is authoritative and **has drifted from `data/balance-config.json`
(v1, 2026-07-21)**: DB adds `RALLY_FLAG` to the UNCOMMON drop pool, removes
`POCKET_WATCH` from RARE, adds `teamOnlyTypes`, `mysteryPotion`, `positionRules`,
and reclassifies `WRONG_TURN` COMMON→RARE and `SNEAKY_SWAP` RARE→UNCOMMON.
Treat the committed JSON as stale.

```
dropPool.COMMON   = PROTEIN_SHAKE, TRAIL_MIX, DETOUR_SIGN, RUNNERS_HIGH, PINECONE_TOSS
dropPool.UNCOMMON = LEG_CRAMP, STEALTH_MODE, WRONG_TURN, RALLY_FLAG
dropPool.RARE     = RED_CARD, SECOND_WIND, COMPRESSION_SOCKS, FANNY_PACK,
                    LUCKY_HORSESHOE, TRAIL_MINE, SNEAKY_SWAP, SHORTCUT, CLEANSE, MIRROR
typeWeights       = { RED_CARD: 0.5 }
teamOnlyTypes     = [RALLY_FLAG]
storeOnlyTypes    = IMPOSTER, RAINSTORM, SIGNAL_JAMMER, LEECH, DEFENSE_SCAN, HITCHHIKE, QUICK_RINSE
luckyHorseshoe.rareChanceByLevel = [0, 0.2, 0.45, 1.0]
upgradeCosts.byType = {}   (byRarity per §3.4)
discardPrices     = (key absent — code defaults apply)
```

Re-verified unchanged 2026-08-09 (`version 3`, `active`, `created_at
2026-07-28 09:46:24`). Note `storeOnlyTypes` in the DB row does **not** list
`POWER_OUTAGE`; the `CODE` default does, and `enforceStoreOnlyExclusion` unions
both lists before filtering `dropPool` — so a drop-pool addition for a
code-listed store-only type is silently zeroed until `defaults.js` is edited too.

**Observed 30d roll volume (verified 2026-08-09):** 11,695 typed rolls =
**389.8/day** across 54 users; mix C 37.7% / U 28.7% / R 30.3% (396 rows, 3.4%,
still `type IS NULL` unopened boxes). Rare drops by type, 30d: `sneaky_swap` 408,
`compression_socks` 394, `lucky_horseshoe` 379, `trail_mine` 374, `shortcut` 369,
`second_wind` 347, `mirror` 338, `cleanse` 302, `fanny_pack` 300, `red_card` 184,
`pocket_watch` 147 (legacy, no longer in the pool).

### 3.3 Mystery-box supply and rarity odds

| Knob | Value | Source |
|---|---|---|
| Steps per box | **2,000 raw walked steps**, per race, immune to all multipliers | `CODE races/constants/powerupInterval.js:5`, `powerups/boxSteps.js` |
| Box coin cost | **0** — boxes are free with walking | — |
| Rarity odds, race **leader** | C 0.48 / U 0.25 / R 0.27 | `DB balance_config.positionOdds.first` |
| Rarity odds, race **last** | C 0.20 / U 0.35 / R 0.45 | `DB balance_config.positionOdds.last` |
| Observed 30d mix | C 39% / U 29.5% / R 31.5% (n=10,908 rolled) | `DB race_powerups` |
| Boxes crossed per sync | capped (anti back-mint) | `CODE powerups/commands/rollPowerup.js:8-16` |

**Supply is per-race, not per-player.** A user in 5 concurrent races mints 5×
the boxes for the same steps. Prod: mean 3.49 concurrent races/user-day, max 13.
Measured 11,826 box-sourced powerups + 659 non-box (spin/store/grant) in 30d.

### 3.3b Position-aware drop rules — `DB balance_config.positionRules`, verified 2026-08-08

Mechanics: `CODE powerups/powerupOdds.js`. Spec:
`stepv2-backend/docs/position-aware-drops-requirements.md`.
`normalizedPosition` (npos) = `(position − 1) / (totalParticipants − 1)`;
0 = leader, 1 = last. Team races collapse to 1-of-2 / 2-of-2.

Two independent layers:

1. **Tier layer** — `positionOdds` linear-interpolates [C,U,R] between `first`
   and `last` (§3.3). Trailers get more RARE.
2. **Within-tier layer** — `positionRules`. Acts strictly inside an
   already-chosen tier; never changes the tier distribution.

| Rule | Live value (`DB`) | Effect |
|---|---|---|
| `leaderExcluded` | `RED_CARD`, `SECOND_WIND` | hard-removed when player is at/tied for max steps (both 400 at use time for a leader) |
| `lastPlaceExcluded` | `TRAIL_MINE` | hard-removed when nobody is behind |
| `leadingDownweight` | `{ RUNNERS_HIGH: 0.5 }` | full strength at npos ≤ 0.4, lerps to 1.0 at npos 0.5 |
| `trailingDownweight` | `{ CLEANSE: 0.5, MIRROR: 0.5, STEALTH_MODE: 0.5 }` | full strength at npos ≥ 0.6, lerps to 1.0 at npos 0.5 |
| `leadingDownweightFrom` / `trailingDownweightFrom` | 0.4 / 0.6 | ramp endpoints |
| neutral point | 0.5 | `CODE powerupOdds.js:71` (not config) |

Clearing all four lists is the kill switch (restores pre-2026-07-26 behaviour,
no deploy).

**Resulting per-type drop probability, N=6 solo race, live prod config**
(computed with the backend's own `typeOddsForPosition`, %):

| Type | P1 | P2 | P3 | P4 | P5 | P6 |
|---|---|---|---|---|---|---|
| PROTEIN_SHAKE | 10.67 | 9.42 | 8.18 | 6.24 | 5.12 | 4.00 |
| TRAIL_MIX | 10.67 | 9.42 | 8.18 | 6.24 | 5.12 | 4.00 |
| DETOUR_SIGN | 10.67 | 9.42 | 8.18 | 6.24 | 5.12 | 4.00 |
| PINECONE_TOSS | 10.67 | 9.42 | 8.18 | 6.24 | 5.12 | 4.00 |
| RUNNERS_HIGH | 5.33 | 4.71 | 4.09 | 6.24 | 5.12 | 4.00 |
| LEG_CRAMP | 8.33 | 9.00 | 9.67 | 12.40 | 13.20 | 14.00 |
| WRONG_TURN | 8.33 | 9.00 | 9.67 | 12.40 | 13.20 | 14.00 |
| STEALTH_MODE | 8.33 | 9.00 | 9.67 | 6.20 | 6.60 | 7.00 |
| RALLY_FLAG | 0 | 0 | 0 | 0 | 0 | 0 (team-only gate) |
| RED_CARD | 0 | 1.61 | 1.80 | 2.22 | 2.44 | 3.00 |
| SECOND_WIND | 0 | 3.22 | 3.60 | 4.45 | 4.87 | 6.00 |
| TRAIL_MINE | 3.38 | 3.22 | 3.60 | 4.45 | 4.87 | 0 |
| CLEANSE / MIRROR | 3.38 | 3.22 | 3.60 | 2.22 | 2.44 | 3.00 |
| COMPRESSION_SOCKS / FANNY_PACK / LUCKY_HORSESHOE / SHORTCUT / SNEAKY_SWAP | 3.38 | 3.22 | 3.60 | 4.45 | 4.87 | 6.00 |

Because `RALLY_FLAG` is team-gated out of solo races, the UNCOMMON tier in a
solo race is only `LEG_CRAMP` / `STEALTH_MODE` / `WRONG_TURN`, and
`STEALTH_MODE` is down-weighted at the back. Last place therefore has
**28.0%** of all drops be Wrong Turn or Leg Cramp, vs **16.7%** for the leader.

### 3.3c Empirical step value per powerup — `DB race_powerup_events` / `race_active_effects`, 30–90d to 2026-08-08

Averages over realised uses (blended upgrade levels). Used as the EV weight
table for position analysis.

| Type | Self gain | Target loss | n | Note |
|---|---|---|---|---|
| SECOND_WIND | +3,620 | — | 553 | leader-excluded |
| RUNNERS_HIGH | +2,739 | — | 952 | avg steps inside the buff window; median **0** (fires while idle) |
| PROTEIN_SHAKE | +1,757 | — | 2,065 | |
| TRAIL_MIX | +1,005 | — | 1,961 | |
| SHORTCUT | +1,114 | −1,114 | 1,551 | steal → 2,228 swing |
| RED_CARD | — | −7,156 | 371 | leader-excluded |
| WRONG_TURN | — | ≈ −3,474 | 1,337 | 1h at −M; window steps lost *and* not gained |
| TRAIL_MINE | — | −1,699 | 967 | |
| LEG_CRAMP | — | −1,737 | 1,320 | avg frozen window steps; median **0** |
| PINECONE_TOSS | — | −802 | 1,171 | |
| DETOUR_SIGN | 0 | 0 | 1,654 | information denial only — hides leaderboard |
| STEALTH_MODE / CLEANSE / MIRROR / COMPRESSION_SOCKS / FANNY_PACK / LUCKY_HORSESHOE | 0 | 0 | — | conditional / meta value |

### 3.3d Buff stacking + Wrong Turn sign rule — `CODE races/services/effectMultiplier.js`

`signedMultiplierAt(t)`, in order:

1. Any freeze active (`LEG_CRAMP`, `QUICKSAND`, Campfire freeze phase, Ghost
   Pepper freeze phase) → **m = 0**. Freeze beats everything, including Wrong Turn.
2. Buffs **SUM** (not multiply): RH 2 + Ghost Pepper 3 = 5. `M = 1` if no buff.
   Contributors: `RUNNERS_HIGH` 2, `CAMPFIRE_REST` meta, `UPRISING` 2,
   `RALLY_FLAG` 1.25, `COIN_FLIP` win, `GHOST_PEPPER` 3.
3. Reductions subtract additively at the **max** lost fraction among active
   ones (`RAINSTORM`, `COIN_FLIP` lose), floored at 0 — never stacks to 0.25x.
4. **`WRONG_TURN` returns `−M`** — it negates the *full* effective rate.

Consequence: Wrong Turn on a player running Runner's High is **−2×**, i.e. the
victim's paid buff is converted into double damage. Prod: **113 / 1,341
(8.4%)** of Wrong Turn windows overlap a self-buff window. No UI surfaces this.

Box progress is separate and immune to all of the above
(`CODE powerups/boxSteps.js` — raw walked steps only, additive bonuses excluded).

### 3.3e Realised position data — prod, 90d to 2026-08-08

Solo races, ≥3 accepted participants. Enum labels in `race_powerups`,
`race_active_effects`, `race_powerup_events.powerup_type` and
`powerup_upgrade_events.powerup_type` are **lowercase**;
`race_powerup_events.event_type` and `powerup_upgrade_events.status` are
UPPERCASE. `race_participants.status` = `accepted`, `race_powerups.rarity` =
`common|uncommon|rare`, `race_active_effects.status` =
`active_effect|expired_effect|blocked`.

Boxes and outcomes by final-placement quintile (n = 1,685 participants in races
with ≥3 accepted players; 219 solo races in window):

| npos | participants | avg race steps | boxes earned | % who got ≥1 Protein Shake |
|---|---|---|---|---|
| 0 (leader) | 252 | 56,676 | **18.71** | 64.3% |
| 0.25 | 386 | 43,377 | 12.59 | 45.9% |
| 0.5 | 398 | 29,809 | 7.22 | 25.4% |
| 0.75 | 386 | 18,770 | 4.01 | 14.5% |
| 1 (last) | 263 | 9,339 | **1.97** | 9.5% |

Drop mix by reconstructed position **at open time** (n = 16,775 drops; position
rebuilt from each participant's `earned_at_steps` track):

| npos | drops | %C | %U | %R | % Wrong Turn or Leg Cramp | % Protein Shake or Trail Mix |
|---|---|---|---|---|---|---|
| 0 | 7,242 | 50.5 | 27.8 | 21.7 | 13.1 | 23.1 |
| 0.25 | 5,389 | 44.9 | 29.0 | 26.1 | 14.7 | 20.6 |
| 0.5 | 2,655 | 35.4 | 31.7 | 32.9 | 16.4 | 16.4 |
| 0.75 | 1,192 | 27.3 | 33.4 | 39.3 | 17.4 | 12.4 |
| 1 | 297 | 25.6 | 33.0 | 41.4 | 14.5 | 10.4 |

Offensive uses, attacker bucket → target bucket (buckets: `<0.25` = lead,
`0.25–0.75` = mid, `>0.75` = last; 252 / 1,170 / 263 participants):

| Type | thrown by lead | by mid | by last | received by lead | by mid | by last |
|---|---|---|---|---|---|---|
| WRONG_TURN | 435 | 410 | 86 | 566 | 316 | 49 |
| LEG_CRAMP | 456 | 406 | 83 | 531 | 361 | 53 |
| SHORTCUT | 767 | 481 | 65 | 716 | 501 | 96 |
| DETOUR_SIGN | 749 | 502 | 83 | 712 | 515 | 107 |
| SNEAKY_SWAP | 136 | 113 | 33 | 115 | 131 | 36 |

Per capita Wrong Turns thrown: **lead 1.73, mid 0.35, last 0.33**.
Per capita Wrong Turns received: **lead 2.25, mid 0.27, last 0.19**.

Upgrades (top 14 types = 967 APPLIED events, 31,150 coins), by upgrader bucket:

| Type | upgrades | coins | lead | mid | last |
|---|---|---|---|---|---|
| PROTEIN_SHAKE | 311 | 9,245 | 216 | 86 | 9 |
| SHORTCUT | 211 | 9,695 | 139 | 65 | 7 |
| TRAIL_MIX | 176 | 3,830 | 122 | 49 | 5 |
| PINECONE_TOSS | 81 | 2,540 | 49 | 27 | 5 |
| RUNNERS_HIGH | 37 | 855 | 18 | 17 | 2 |
| LEG_CRAMP | 36 | 950 | 20 | 7 | 9 |
| WRONG_TURN | 35 | 1,020 | 12 | 15 | 8 |
| TRAIL_MINE | 27 | 1,250 | 18 | 8 | 1 |

Lead retention (`day_start_placement`), completed solo races ≥3p:

| day-start placement | n | % won race |
|---|---|---|
| 1 | 78 | 53.8 |
| 2 | 78 | 17.9 |
| 3 | 79 | 12.7 |
| 4 | 75 | 5.3 |
| 5 | 72 | 2.8 |
| 6 | 70 | 4.3 |
| 7–10 | 244 | ≈ 0.4 (1 win total) |

Leaders by incoming offensive effects (Wrong Turn + Leg Cramp received):

| incoming | leaders | % won | avg final placement |
|---|---|---|---|
| 0 | 17 | 58.8 | 1.82 |
| 1–2 | 31 | 45.2 | 2.90 |
| 3–5 | 18 | 55.6 | 1.61 |
| 6+ | 12 | **66.7** | 1.67 |

Repeat targeting: 3,031 (race, attacker, victim) pairs for offensive types —
mean 2.08 uses, p50 1, p90 4, p99 10, **max 19**. There is **no target
cooldown or repeat-target cap anywhere in `usePowerup.js`**.

Box hoarding: gap between box mint and box open — mean 16.0h, **p50 1.1h, p90
28.9h, p99 285h** (n = 8,818). Position is read at **open** time
(`openMysteryBox.js:120-149`), not mint time.

### 3.3f Config drift to flag

| Key | `DB balance_config` v3 | `CODE balanceConfig.defaults.js` | Consequence |
|---|---|---|---|
| `rarityByType.WRONG_TURN` | `RARE` | `UNCOMMON` | drops from the **UNCOMMON** tier (dropPool wins) but upgrades on the **RARE** ladder — L3 costs **135**, not 90. Confirmed against prod upgrade events (§3.4) |
| `rarityByType.SNEAKY_SWAP` | `UNCOMMON` | `RARE` | drops from RARE, tinted/priced as UNCOMMON |
| `rarityByType.POWER_OUTAGE` | `UNCOMMON` | `UNCOMMON` | agrees; sets its would-be discard price at 5 |
| `storeOnlyTypes` | 7 entries | 17 entries | harmless — `enforceStoreOnlyExclusion` unions the code list before filtering `dropPool` |
| `dailyBoxExcludedTypes` | present | removed | ignored at runtime |

### 3.4 Upgrade ladder — `DB balance_config.upgradeCosts` (verified 2026-08-09)

**Upgrades are NOT cumulative and NOT persistent.** `upgradeLevel` is a
parameter of the *use* call; the price is a single lookup
`byRarity[rarity][level]` (`CODE powerupUpgrades.js:68-80`) charged once, and the
level is stamped onto the consumed `race_powerups` row. Playing at L3 costs the
L3 price only — there is no ladder to climb and nothing carries to the next copy.

| Rarity | L1 | L2 | L3 |
|---|---|---|---|
| COMMON | 5 | 15 | 45 |
| UNCOMMON | 10 | 30 | 90 |
| RARE | 15 | 45 | 135 |

`upgradeCosts.byType` overrides `byRarity` per type and is `{}` in both `CODE`
and `DB` — it is the intended seam for repricing a single type.

15 upgradeable types (`upgradeableTypes`). `TRAIL_MAGNET` and `CAMPFIRE_REST`
are upgradeable but **no longer generated** (`powerupOdds.js:6`).

Which ladder a type charges is `rarityByType`, **not** its drop tier — so the
§3.3f drift is a live price fact: `WRONG_TURN` drops from the UNCOMMON tier but
charges the **RARE** ladder. Confirmed against prod `powerup_upgrade_events`
(all-time, `status='APPLIED'`):

| Type | L1 n / avg cost | L2 n / avg | L3 n / avg | Ladder in force |
|---|---|---|---|---|
| `wrong_turn` | 54 / 17.3 | 18 / 42.5 | 6 / 120.0 | RARE `[15,45,135]` |
| `leg_cramp` | 60 / 16.4 | 19 / 30.0 | 2 / 90.0 | UNCOMMON `[10,30,90]` |
| `stealth_mode` | 33 / 16.4 | 12 / 30.0 | 3 / 90.0 | UNCOMMON |
| `lucky_horseshoe` | 4 / 73.8 | 0 | 0 | retired premium ladder (2026-07-14) |

(L1 averages exceed the nominal price because rows predate the 2026-07-28
rarity reclass.) Level mix across all types: **≈74% L1 / 22% L2 / 5% L3**.

Wrong Turn + Leg Cramp upgrades in the last 30d: **145 events, 3,525 coins =
117.5 coins/day**, i.e. **18.7% of the whole `powerup_upgrade` sink** (§2).

### 3.4b Step-swing value per tier — computed 2026-08-09

`typeOddsForPosition` (live prod config, N=6) weighted by the §3.3c empirical
value table (`SNEAKY_SWAP` conservatively 0). "Swing" = self gain + damage dealt.

| Race position | E[COMMON] | E[UNCOMMON] | E[RARE] | E[box] |
|---|---|---|---|---|
| P1 (leader) | 1,096 | **1,737** | 491 | 1,093 |
| P2 | 1,096 | **1,737** | 1,171 | 1,292 |
| P3 | 1,096 | **1,737** | 1,171 | 1,308 |
| P4 | 1,261 | **2,084** | 1,309 | 1,534 |
| P5 | 1,261 | **2,084** | 1,309 | 1,552 |
| P6 (last) | 1,261 | **2,084** | 1,257 | 1,547 |

**Rarity is inverted relative to value.** UNCOMMON is the most valuable tier at
every position (it is 100% Wrong Turn / Leg Cramp / Stealth in a solo race) and
RARE is the least (half the tier — Socks, Cleanse, Mirror, Horseshoe, and now
Power Outage — has zero direct step swing). At the leader, RARE is worth 45% of
UNCOMMON because `leaderExcluded` removes Red Card and Second Wind, the only two
high-swing rares. Every "guaranteed rare" mechanic inherits this.

### 3.4c Timed-effect durations — `CODE powerupUpgrades.js:35-45` (NOT balance config)

`DURATIONS_MS` and `MAGNITUDES` are deliberately **code constants**, not admin
config (file comment `:14-18`). They are stamped into the effect row's
`expiresAt` at use time, so a deploy changes all future uses instantly on every
app version and leaves in-flight effects alone.

| Type | L0 | L1 | L2 | L3 |
|---|---|---|---|---|
| `LEG_CRAMP`, `RUNNERS_HIGH`, `STEALTH_MODE`, `WRONG_TURN`, `DETOUR_SIGN`, `POCKET_WATCH` | 1h | 2h | 3h | 4h |
| `COMPRESSION_SOCKS` | 24h | 30h | 36h | 48h |
| `CAMPFIRE_REST` | 45m | 60m | 75m | 90m |

Fixed (non-upgradeable) durations: `SIGNAL_JAMMER` 1h
(`usePowerup.js:158`), `POWER_OUTAGE` 30m (`:129`), Mystery Potion's cramps
**hardcoded 2h** self and enemy (`:546`, `:730`) with potion self-wrong-turn at
1h (`:559`) — the potion has never adopted the standard ladder.

**Cost per marginal duration minute** at the live ladders, with the empirical
targeted-victim walk rate of **1,737 steps/h** (§3.3c `LEG_CRAMP` realised
window average; 94% of those uses were L0/1h, so it is a clean per-hour rate):

| | +minutes vs L0 | coins | swing steps bought | steps/coin |
|---|---|---|---|---|
| `LEG_CRAMP` L1 | +60 | 10 | 1,737 | 174 |
| `LEG_CRAMP` L2 | +120 | 30 | 3,474 | 116 |
| `LEG_CRAMP` L3 | +180 | 90 | 5,211 | 58 |
| `WRONG_TURN` L1 | +60 | 15 | 3,474 (2× — sign flip) | 232 |
| `WRONG_TURN` L2 | +120 | 45 | 6,948 | 154 |
| `WRONG_TURN` L3 | +180 | 135 | 10,422 | 77 |

Market band for comparison (same value table): `PROTEIN_SHAKE` 150/100/67,
`SHORTCUT` 67/44/30, `PINECONE_TOSS` 50/50/33, `TRAIL_MIX` ≈50/…/22 steps/coin
at L1/L2/L3. `STEALTH_MODE` and `DETOUR_SIGN` buy 0 direct step value.

**Population walk-decay reference** (prod, 30d, hourly buckets from
`step_samples`, n=30,070 user-hours with steps>0): the hour *after* an active
hour averages **497 steps**, median 146, p90 1,459, and is **zero 23.4%** of the
time. A marginal duration extension is therefore worth 0.3–1.0× the first hour
depending on how well-timed the attack was; 1,737/h is the optimistic bound.

### 3.5 Discard — `CODE powerups/commands/discardPowerup.js` (batch 2026-08-08)

Sets status `DISCARDED`, writes a race event, emits `POWERUP_DISCARDED`, and
pays `discardPrices[rarity]` coins capped per user per LOCAL day.

| Knob | Value | Source |
|---|---|---|
| `discardPrices` | COMMON 2 / UNCOMMON 5 / RARE 10 | `CODE balanceConfig.defaults.js:248-252` — the **live DB row has no `discardPrices` key**, so code defaults apply via `mergeOverDefaults` |
| Daily cap | 40 coins/user/local day | `ENV POWERUP_DISCARD_DAILY_COIN_CAP`, default `CODE discardRewards.js:10` |
| Unopened `MYSTERY_BOX` | pays **0** — a rule, not a knob | `CODE discardRewards.js:41-48` |
| Partial award at the cap | `min(price, capRemaining)` | `CODE discardRewards.js` |

Price keys off `race_powerups.rarity` (the tier actually rolled), not
`rarityByType`. Eligible statuses: `HELD` and `MYSTERY_BOX`.

**Now live in prod** (verified 2026-08-10): `coin_transactions` has **29** rows
with reason `powerup_discard`, **168 coins** total, avg 5.8/discard —
consistent with the 4.9–6.7 expected yield below. 286 `POWERUP_DISCARDED`
events in 30d (most discards therefore land at 0 coins or on unopened boxes).

Expected discard yield per box at live odds (no horseshoe): **P1 4.91 · P3 5.70 ·
P6 6.65 coins**. The 40/day cap therefore binds at ~6–8 discarded rolls/day.

### 3.6 Lucky Horseshoe — `DB balance_config.luckyHorseshoe`, verified 2026-08-09

| Fact | Value | Source |
|---|---|---|
| `rareChanceByLevel` | **`[1, 1, 1, 1]`** (`DB` v4, 2026-08-10) — was `[0, 0.2, 0.45, 1.0]` in v3 | `DB balance_config` v4 |
| Roll timing | at **use** time, frozen into `race_active_effects.metadata.minRarity` | `CODE usePowerup.js:397-403, 3129-3141` |
| Floor on a miss | `UNCOMMON` | same |
| Forced pick | weighted draw from the **position-filtered** RARE pool — may currently return another Horseshoe | `CODE openMysteryBox.js:186-194` |
| Reroll path | **no horseshoe logic at all** — an ad-funded reroll is a fresh roll and ignores `minRarity` | `CODE rerollMysteryBox.js:295-297` |
| Shop SKU | **none** — `powerup_shop_items` has no `lucky_horseshoe` row | `DB` |
| Duplicate guard | one active Horseshoe per participant (400 otherwise) | `CODE usePowerup.js:1909-1917` |
| Hard validation | 4 entries in `[0,1]`, non-decreasing, `[3]` must be exactly `1.0` | `CODE balanceConfig.js:484-500` |
| Soft bound | `luckyHorseshoe.rareChanceByLevel.1` ∈ `[0, 0.5]` → a save above it returns **422 `bound_warnings`** unless `acknowledgeBoundWarnings`, and stamps `boundOverride=true` on the row | `CODE defaults.js:441-446`, `balanceConfig.js:759-767` |

**Prod usage, all-time (verified 2026-08-09):** 594 copies ever
(580 used, 10 expired, 4 used at L1); 375 uses by 32 users in the last 30d.
Upgrades: **4 events, 3 users, 295 coins, all tier 1, all already consumed.**
**Zero upgraded Horseshoes are currently held** — `upgrade_level` lives on the
`race_powerups` row and the row is consumed on use, so retiring the ladder
strands nothing.

**Rare-inflation and chain length** (Monte Carlo, 2×10⁶ boxes per cell, RARE pool
after Fanny Pack removal + Power Outage addition, horseshoe used immediately on
the next box):

| Position | baseline rare rate | with 100% horseshoe, self-excluded | without self-exclusion | mean chain (excl / no-excl) | max chain seen |
|---|---|---|---|---|---|
| P1 | 27.0% | **29.4%** | 29.8% | 1.00 / 1.14 | 1 / 6 |
| P3 | 36.2% | **38.5%** | 38.8% | 1.00 / 1.12 | 1 / 6 |
| P6 | 45.0% | **48.1%** | 48.6% | 1.00 / 1.16 | 1 / 7 |

Closed form: with `r` = P(rare) and `h` = the Horseshoe's share of the RARE pool,
the forced-box fraction is `rh/(1+rh)` and the un-excluded chain is geometric
with ratio `h ≈ 0.105–0.133`, converging to **1.12–1.16 forced rares per
Horseshoe**. There is no rare-farming loop with or without the self-exclusion.

**Discard interaction — no coin loop.** Discarding a Horseshoe pays 10. Using it
converts one box worth 4.91–6.65 in expected discard coins into one worth 10, a
gain of 3.4–5.1 — less than the 10 it was worth unspent. Simulated coins/box:
**never use 4.913 / use 4.752 at P1**, **6.650 / 6.273 at P6**. Using the
Horseshoe is strictly coin-negative and step-positive, which is the correct
incentive.

### 3.7 Ad-funded mystery-box reroll — `CODE powerups/commands/rerollMysteryBox.js`, verified 2026-08-10

| Knob | Value | Source |
|---|---|---|
| Kill switch | `ADS_BOX_REROLL_ENABLED === "true"` (defaults **OFF**) | `ENV`, `CODE adRewards.js:56` |
| Grant kind | `box_reroll`, SSV custom_data `box_reroll:<userId>:<localDate>` | `CODE grantAdReward.js:30,95` |
| **Daily cap on reroll ad watches** | **NONE** — unlike `ad_coin_reward` (25×3) and the ad unlock kinds, no cap exists | `CODE` |
| Cost | 1 verified watch = 1 reroll, consumed CAS | `CODE rerollMysteryBox.js:225-250` |
| Eligibility | `status=HELD`, `rarity != null`, `upgradeLevel = 0`, `rerolledAt = null` | same |
| Odds used | fresh roll at **current raw-steps position**, no Lucky Horseshoe floor | `CODE :283-297` |
| Platform | iOS only (`ADMOB_BOX_REROLL_AD_UNIT_ID`); Android compiles the button out | `FE AdService` |

**Rerollable population.** Spin-granted powerups carry a rarity (506 rows with
`earned_at_steps IS NULL` and non-null rarity) and are therefore rerollable.
**Store purchases carry a null rarity** (all `rainstorm`/`leech`/`quick_rinse`
rows), so coins can *not* be converted into a box roll via reroll.

**Prod volume since launch (2026-08-10):** 29 `box_reroll` grants / 8 users,
27 rerolls performed, 27 `POWERUP_REROLLED` events.

**Simultaneous-box ceiling (bounds any "reroll all" batch).**
`DEFAULT_POWERUP_SLOTS = 3` + `MAX_QUEUED_BOXES = 1`; further crossings are
**forfeited** (2,486 `POWERUP_FORFEITED` events in 30d). Max observed
`race_participants.powerup_slots` = **4**, so the physical maximum openable at
once is **5**. Live holdings right now: 1 box ×26 participants, 2 ×38, 3 ×26,
4 ×28 (0 at 5).

Measured open-burst sizes (15s windows per user, 30d, n=10,288 opens):
**1 → 6,829 · 2 → 1,111 · 3 → 290 · 4 → 83 · 5 → 7.** 82.1% of opens are
singletons; mean burst 1.24; mean burst given ≥2 boxes **2.32**.

**Reroll EV** (Monte Carlo 4×10⁵ per cell, live v4 config via the backend's own
`typeOddsForPosition`, N=6 solo, valued with the §3.3c swing table, Lucky
Horseshoe valued 0):

| Position | E[box swing] | sd | cherry-pick 1 box | all-or-nothing N=2 | N=3 | N=4 | N=5 |
|---|---|---|---|---|---|---|---|
| P1 | 1,106 | 1,109 | **+470** | +643 (322/box) | +777 (259) | +892 (223) | +1,000 (200) |
| P3 | 1,340 | 1,472 | **+586** | +818 (409/box) | +1,003 (334) | +1,155 (289) | +1,305 (261) |
| P6 | 1,547 | 1,682 | **+686** | +939 (470/box) | +1,158 (386) | +1,340 (335) | +1,503 (301) |

Gain formula: reroll is a fresh iid draw, so the optimal rule is "reroll iff the
current holding is below its mean" and the gain is `E[(μ−S)⁺]`. Per-box gain
falls like `1/√N` for an all-or-nothing batch; per-**ad** gain rises like `√N`.

---

## 4. Race payouts

### 4.1 App-funded prize pool (current default)

`app_settings.fundedPrizePoolsEnabled` has **no prod row** → code default `true`
(`CODE src/shared/config/appSettings.js:75`). All new races are funded; buy-ins
are forced to 0.

```
pool = playerCount × durationPoints(days) × PRIZE_COIN_UNIT      (clamped to PRIZE_POOL_MAX)
durationPoints: d≤1 → 1 ; d≤3 → 2 ; d≤7 → 4 ; d≥8 → 8
PRIZE_COIN_UNIT  = 20    (ENV, default CODE prizePool.js:11)
PRIZE_POOL_MAX   = 16000 (ENV, default CODE prizePool.js:24)
```
`playerCount` at settlement = ACCEPTED **and** `totalSteps > 0` (team races skip
the placement check). Projection uses accepted count. Fewer than 2 players mints 0.

Verified against prod completions 2026-08-08: 4 walkers × 1d → 80; 10 walkers ×
7d → 800. Formula confirmed.

### 4.2 Individual payout presets — `CODE races/racePayoutPresets.js`

| Preset | Split | Notes |
|---|---|---|
| `WINNER_TAKES_ALL` | [100] | |
| `TOP3_70_20_10` | [70,20,10] | |
| `TOP3_80_15_5` | [80,15,5] | |
| `TOP_HALF` | `ceil(N/2)` places | funded ⇒ **even** split; buy-in pot ⇒ geometric r=0.7 |
| `ALL_BUT_LAST` | `N−1` places | same |

Graded presets need ≥4 accepted (`MIN_MULTI_PAYOUT_PARTICIPANTS`). Geometric
floor per paid place = 1 coin.

### 4.3 Team race payouts — `CODE races/commands/completeRace.js:143-243`

- Team size 1–5 (`validateRaceConfig.js:96`); **1v1 is legal**. Sides must be
  equal and ≥1 to start (`startRace.js:67-79`). No minimum field for a funded pool.
- Pool = same §4.1 formula, `isTeamRace: true` walker count (includes forfeiters'
  frozen totals).
- **Winning team's non-forfeited members split 100% of the pool evenly**;
  remainder to the team's top stepper. **Losing team gets 0.** Placements: all
  winners 1, all losers 2.
- **Tie** ⇒ everyone placement 1, buy-ins refunded, and for a *funded* race the
  pool is **never minted** — nobody is paid and `prizePoolCoins` is never stamped.
- Per-head winner payout is therefore
  `durationPoints × 20 × 2` — **independent of team size**.

| Race | Pool | Winner each | /day | Loser each |
|---|---|---|---|---|
| 5v5 × 14d | 1,600 | 320 | 22.9 | 0 |
| 5v5 × 7d | 800 | 160 | 22.9 | 0 |
| 3v3 × 14d | 960 | 320 | 22.9 | 0 |
| 1v1 × 14d | 320 | 320 | 22.9 | 0 |

Prod team-race population 2026-08-08: 7 rows total (3 completed, 1 active,
1 pending, 2 cancelled). **No 14-day team race has ever settled.**

### 4.4 Seeded challenge finish rewards — `CODE races/constants/raceFinishReward.js`

Non-funded seeded races only (retired for funded).

| Seed | perHead | minPool | maxPool | paidFraction | places | tail floor |
|---|---|---|---|---|---|---|
| `seed-daily-10k` | 15 | 100 | 1,500 | 0.5 | 3–15 | 10 |
| `seed-weekly-50k` | 40 | 500 | 5,000 | 0.2 | 3–20 | — |

Split by descending linear weights (`computeGradedPayouts`).

---

## 5. Daily spinner (daily reward box)

`CODE economy/dailyBoxOdds.js`, config `DB balance_config.dailyBox`.

| Knob | Value |
|---|---|
| `streakCap` | 30 (odds interpolate linearly over streak 1→30) |
| Odds at streak 1 | C 0.70 / U 0.25 / R 0.05 |
| Odds at streak 30 | C 0.20 / U 0.35 / R 0.45 |
| Coin ranges (scaled by streak, snapped to 5) | COMMON 10–30 · UNCOMMON 40–80 · RARE_FALLBACK 100–200 |
| `rareCoinsShare` | 0 (RARE never pays coins unless both prize pools are empty) |
| `accessoryWeightMode` | `inverse` — cheaper items more likely (never set `legacy`) |
| RARE sub-roll | 50% accessory / 50% powerup when both pools stocked |

**The spinner's powerup pool is the shop catalog** (`getEligiblePowerupPool`,
gated by client capability tokens). Prod 30d: 659 non-box powerups granted,
including 16 free `leech` (300-coin store price) and 62 `cleanse`.

`dailyBoxExcludedTypes` still exists in the `DB balance_config` row
(`DEFENSE_SCAN, LEECH, HITCHHIKE, QUICK_RINSE, RALLY_FLAG`) but is **dead data** —
it was removed as an authority on 2026-07-28 (`balanceConfig.js:228`,
`getEligiblePowerupPool.js:8`). The rule is now: **visible in the store ⟺
winnable from the spin.** This is why 16 free `leech` (300-coin store price) and
63 `quick_rinse` were granted in the last 30d. Consequence: **the spinner is a
free source of the most expensive powerups in the game.**

---

## 6. Cosmetics — `DB shop_items`, verified 2026-08-08

| Segment | n | Prices |
|---|---|---|
| active, not testOnly | 8 | 0 (×1), 250 (×3), 500 (×2), 1000 (×2) |
| active, testOnly | 56 | 250–1500 (avg 629) |

Affordability at p50 income (3/day): 250 ⇒ 83 days. At p90 (98/day): 2.5 days.

---

## 7. Known structural properties (carry forward)

- **Buff stacking** is sum-of-multipliers with a signed rate; Wrong Turn can net
  a paid buff to −1 (see `wrong-turn-silently-cancels-paid-buffs`).
- **Effect scoring** uses closed buckets only; open-bucket inclusion once paid
  ~1.48×.
- **Box progress** uses raw walked steps only — never buffed/debuffed.
- **Position-aware drops**: `positionRules` excludes RED_CARD/SECOND_WIND from
  the leader, TRAIL_MINE from last place, and down-weights RUNNERS_HIGH (leader)
  / MIRROR, CLEANSE, STEALTH_MODE (trailing). See §3.3b–§3.3f and §8.
- **Box supply is uncapped and purely step-linear**, so the front-runner's
  powerup income scales with the very quantity the race scores. This dominates
  every drop-table knob (§8).
- **No repeat-target cap / target cooldown** exists in `usePowerup.js`.
- **Position is read at box-OPEN time**, not mint time — unopened boxes can be
  banked and opened from a worse position (§8).
- **No concurrent-race limit** exists anywhere in the codebase. Observed max: 10
  simultaneous active races per user.
- **Referral farming** is bounded by one payout per provider identity.

---

## 8. Position-fairness rebalance — candidate option set (2026-08-08, NOT APPLIED)

Recorded here as candidate numbers only. Nothing below is in code, seeds or the
DB. EV computed with the backend's own `typeOddsForPosition` against the live
prod config, weighted by the empirical value table (§3.3c) and the empirical
box counts (§3.3e). N = 6 (prod median race size).

**Baseline (A = live prod v3)**

| npos | boxes/race | E[self]/box | E[dmg]/box | self steps/race | dmg steps/race | %offense | %self-boost |
|---|---|---|---|---|---|---|---|
| 0 | 18.71 | 499 | 635 | 9,328 | 11,881 | 48.1 | 33.4 |
| 0.25 | 12.59 | 553 | 783 | 6,966 | 9,852 | 48.2 | 32.7 |
| 0.5 | 7.22 | 576 | 841 | 4,160 | 6,069 | 46.9 | 31.8 |
| 0.75 | 4.01 | 551 | 1,054 | 2,210 | 4,226 | 53.5 | 30.5 |
| 1 | 1.97 | 540 | 1,079 | 1,064 | 2,126 | 51.0 | 30.0 |

Leader:last self-steps ratio **8.8×** — of which the *per-box* odds contribute
0.92× and box **volume** contributes 9.5×.

**Option B — flat rarity curve (existing kill switch)**
`positionOdds.last = positionOdds.first = [0.48, 0.25, 0.27]`.
Leader:last self-steps 6.6×. Leader %self-boost 33.4 vs last 39.6.

**Option C — soft rarity + leader self-boost nerf + trailer offense nerf**
`positionOdds first [0.44,0.27,0.29] / last [0.34,0.30,0.36]`;
`leadingDownweight { RUNNERS_HIGH 0.5, PROTEIN_SHAKE 0.55, TRAIL_MIX 0.55, SECOND_WIND 0.6 }`;
`trailingDownweight { CLEANSE 0.5, MIRROR 0.5, STEALTH_MODE 0.5, WRONG_TURN 0.6, LEG_CRAMP 0.7 }`.
Leader:last self-steps 6.3×; leader %offense rises to 53.3 (over-corrects).

**Option D — config-only recommendation**
`positionOdds first [0.46,0.26,0.28] / last [0.40,0.28,0.32]`;
`leadingDownweight { RUNNERS_HIGH 0.5, PROTEIN_SHAKE 0.6, TRAIL_MIX 0.6, SHORTCUT 0.6 }`;
`trailingDownweight { CLEANSE 0.4, MIRROR 0.4, STEALTH_MODE 0.6, WRONG_TURN 0.5, LEG_CRAMP 0.6 }`.

| npos | boxes/race | E[self]/box | E[dmg]/box | self steps/race | dmg steps/race | %offense | %self-boost |
|---|---|---|---|---|---|---|---|
| 0 | 18.71 | 423 | 661 | 7,915 | 12,361 | 51.8 | 28.5 |
| 0.5 | 7.22 | 642 | 759 | 4,632 | 5,478 | 46.3 | 35.3 |
| 1 | 1.97 | 674 | 754 | 1,328 | 1,485 | 45.1 | 37.2 |

Leader:last self-steps 6.0×. Trailer's Wrong Turn + Leg Cramp share falls from
28.0% to ~16%; trailer's E[dmg]/box falls 1,079 → 754.

**Option E — D + position-scaled box interval (requires a code change)**
`k(npos) = 1.20 − 0.45·npos` applied to `powerupStepInterval`.

| npos | k | boxes/race | E[self]/box | self steps/race | dmg steps/race |
|---|---|---|---|---|---|
| 0 | 1.20 | 15.59 | 423 | 6,596 | 10,301 |
| 0.25 | 1.09 | 11.58 | 520 | 6,018 | 8,860 |
| 0.5 | 0.97 | 7.41 | 642 | 4,751 | 5,618 |
| 0.75 | 0.86 | 4.65 | 656 | 3,049 | 3,614 |
| 1 | 0.75 | 2.63 | 674 | 1,770 | 1,980 |

Leader:last self-steps **3.7×**. This is the only option that moves the
dominant term. Sandbagging remains unprofitable (dynamic sim, Option H section:
min winning walk-fraction 125% with damage, 105% without). **But it raises the
hoarding edge from +1.0% to +7.4%** — see the Option H exploit re-check; the
raw-steps-position fix is a prerequisite for E as well as for H.

**Option F — repeat-target cap (code change)** e.g. max 2 offensive effects
from the same attacker on the same victim per rolling 24h per race. Prod tail
today: p99 = 10, max = 19 uses per (race, attacker, victim) pair.

> **Owner decision 2026-08-09 — Option E DECLINED.** Selected scope is
> **Option H config + the raw-steps position fix** (its stated prerequisite),
> plus the `rarityByType` drift reconcile (`WRONG_TURN` → UNCOMMON, 195→130;
> `SNEAKY_SWAP` → RARE, 130→195). Spec:
> `docs/box-raw-steps-position-and-option-h-requirements.md`. Options E, F and
> G remain unselected. **Everything in §8 is still NOT APPLIED** until the
> backend deploy and the `balance_config` row land; mark APPLIED with the
> config version id at that point.
>
> Ordering is mandatory: the raw-steps fix ships **before** the Option H row.
> Option H roughly doubles the value of trailing odds (E[self]/box 635 → 1,180),
> so applying the config first amplifies the hoarding incentive it depends on
> the code fix to remove.

**Option G — Wrong Turn sign clamp (code change)**
`effectMultiplier.js:132` currently returns `−M`. Clamping to `−min(M, 1)`
removes the "your paid buff is turned into double damage" interaction (8.4% of
Wrong Turns today).

### Option H — trailers catch up by SELF-BOOST, not griefing (2026-08-09, NOT APPLIED)

Design goal (owner): players in lower positions should receive catch-up /
self-boost powerups rather than offensive ones. Offense should sit with
mid-pack and the front, which is where prod already shows it being *used*
(§3.3e: the lead bucket throws 46% of all Wrong Turns; last place throws 9%).

**Enabling mechanic.** `validateConfig` (`balanceConfig.js`) requires only that
a `dropPool` member *has* a rarity in `rarityByType` — it does **not** require
the tier to equal `rarityByType[type]`. So `PROTEIN_SHAKE`, `TRAIL_MIX` and
`RUNNERS_HIGH` can be added to `dropPool.UNCOMMON` while leaving `rarityByType`
(and therefore the upgrade ladder, §3.4) untouched. Without this the UNCOMMON
tier in a solo race is only `LEG_CRAMP` / `STEALTH_MODE` / `WRONG_TURN`
(`RALLY_FLAG` is team-gated out), i.e. 100% grief with nowhere for the mass to
move.

> **Empty-weight trap — verified.** If the UNCOMMON tier is left as-is and all
> three members are given `trailingDownweight: 0`, `drawWeighted` sees
> `total === 0` and falls back to a **uniform** pick over the pool
> (`powerupOdds.js:226`). Wrong Turn + Leg Cramp then become **66.7%** of the
> tier — the down-weight silently inverts into an up-weight. Any zero-weight
> tier is unsafe; a tier must always retain a positively-weighted member.

**H — full config (config-only; `validateConfig` returns `[]`)**

```
dropPool.UNCOMMON  = LEG_CRAMP, STEALTH_MODE, WRONG_TURN, RALLY_FLAG,
                     PROTEIN_SHAKE, TRAIL_MIX, RUNNERS_HIGH   <- 3 added
dropPool.COMMON    unchanged
dropPool.RARE      unchanged
rarityByType       unchanged (upgrade prices unchanged)
positionOdds.first = [0.52, 0.20, 0.28]     (was [0.48, 0.25, 0.27])
positionOdds.last  = [0.30, 0.36, 0.34]     (was [0.20, 0.35, 0.45])
positionRules.leaderExcluded     = RED_CARD, SECOND_WIND        (unchanged)
positionRules.lastPlaceExcluded  = TRAIL_MINE                   (unchanged)
positionRules.leadingDownweight  = { RUNNERS_HIGH 0.5, PROTEIN_SHAKE 0.7, TRAIL_MIX 0.7 }
positionRules.trailingDownweight = { WRONG_TURN 0.2, LEG_CRAMP 0.25,
                                     PINECONE_TOSS 0.4, DETOUR_SIGN 0.4,
                                     SNEAKY_SWAP 0.5, CLEANSE 0.5, MIRROR 0.5,
                                     STEALTH_MODE 1 }   <- MUST be explicit
positionRules.leadingDownweightFrom  = 0.4   (unchanged)
positionRules.trailingDownweightFrom = 0.6   (unchanged)
```

`STEALTH_MODE`'s down-weight is neutralized with an **explicit `1`** — NOT by
omitting the key. `mergeOverDefaults` merges plain objects recursively (only
arrays replace), so a stored `trailingDownweight` missing the key would
silently inherit the code default's `0.5` and the restore would do nothing
(caught during implementation, 2026-08-09). Rationale: prod shows trailers
are barely attacked (0.19 Wrong Turns received per head), so weighting them
*away* from defense was correct but the freed mass is better spent on
self-boost.

**Per-type drop probability under H, N=6 (%)**

| Type | P1 | P2 | P3 | P4 | P5 | P6 |
|---|---|---|---|---|---|---|
| PROTEIN_SHAKE | 12.19 | 11.86 | 11.53 | 17.70 | 17.36 | **17.01** |
| TRAIL_MIX | 12.19 | 11.86 | 11.53 | 17.70 | 17.36 | **17.01** |
| RUNNERS_HIGH | 8.71 | 8.47 | 8.23 | 17.70 | 17.36 | **17.01** |
| SECOND_WIND | 0 | 3.07 | 3.20 | 3.95 | 4.10 | 4.86 |
| DETOUR_SIGN | 13.33 | 12.21 | 11.08 | 4.08 | 3.62 | 3.16 |
| PINECONE_TOSS | 13.33 | 12.21 | 11.08 | 4.08 | 3.62 | 3.16 |
| WRONG_TURN | 4.08 | 4.73 | **5.39** | 1.50 | 1.66 | **1.82** |
| LEG_CRAMP | 4.08 | 4.73 | **5.39** | 1.87 | 2.08 | **2.28** |
| STEALTH_MODE | 4.08 | 4.73 | 5.39 | 3.75 | 4.15 | 4.56 |
| RED_CARD | 0 | 1.54 | 1.60 | 1.98 | 2.05 | 2.43 |
| TRAIL_MINE | 3.50 | 3.07 | 3.20 | 3.95 | 4.10 | 0 |
| CLEANSE / MIRROR / SNEAKY_SWAP | 3.50 | 3.07 | 3.20 | 1.98 | 2.05 | 2.43 |
| COMPRESSION_SOCKS / FANNY_PACK / LUCKY_HORSESHOE / SHORTCUT | 3.50 | 3.07 | 3.20 | 3.95 | 4.10 | 4.86 |

Wrong Turn + Leg Cramp now **peak at mid-pack (P3, 10.8%)**, not at the back.

**EV by position, before vs after**

| | npos | boxes/race | E[self]/box | E[dmg]/box | self/race | dmg/race | %self-boost | %WT+LC |
|---|---|---|---|---|---|---|---|---|
| **A (current)** | 0 | 18.71 | 499 | 635 | 9,328 | 11,881 | 33.4 | 16.7 |
| | 0.5 | 7.22 | 576 | 841 | 4,160 | 6,069 | 31.8 | 20.0 |
| | 1 | 1.97 | 540 | 1,079 | 1,064 | 2,126 | 30.0 | **28.0** |
| **H** | 0 | 18.71 | 635 | 439 | 11,884 | 8,215 | 40.1 | 8.2 |
| | 0.25 | 12.59 | 721 | 568 | 9,080 | 7,150 | 41.3 | 9.8 |
| | 0.5 | 7.22 | 882 | 537 | 6,367 | 3,878 | 48.4 | 9.3 |
| | 0.75 | 4.01 | 1,164 | 393 | 4,668 | 1,577 | 64.5 | 3.6 |
| | 1 | 1.97 | 1,180 | 371 | 2,325 | 730 | **65.6** | **4.1** |
| **H + Option E** | 0 | 15.59 | 635 | 439 | 9,904 | 6,846 | 40.1 | 8.2 |
| | 0.5 | 7.41 | 882 | 537 | 6,530 | 3,977 | 48.4 | 9.3 |
| | 1 | 2.63 | 1,180 | 371 | 3,100 | 974 | 65.6 | 4.1 |

Leader:last self-steps per race: **A 8.8× → H 5.1× → H+E 3.2×**.

**Step inflation.** Total self-boost steps injected per race (5 sampled slots)
rises 23,728 → 34,324 (**+45%**). No coin impact (boxes are free), but
`target_steps` races will complete faster and effective-step leaderboards
inflate. Lower `positionOdds.*` COMMON/UNCOMMON mass, or trim `MAGNITUDES`, if
that is unwanted.

**H-hard variant — REJECTED.** Adding `WRONG_TURN`/`LEG_CRAMP` to
`lastPlaceExcluded` is **rejected by `validateConfig`** when those types also
appear in `trailingDownweight` (*"a type may be in at most one positionRules
list"*). Even with the down-weights removed it is worse:
`lastPlaceExcluded` keys off `isStepLast` (nobody strictly behind), so it fires
only for the literal last player — and for **every** player in a 2-player race
and for **everyone at a 0–0 race start**, where the whole field is
simultaneously `isStepLeader` and `isStepLast`. Verified pools at a 0–0 start:
UNCOMMON `[STEALTH_MODE, PROTEIN_SHAKE, TRAIL_MIX, RUNNERS_HIGH]`, RARE loses
Red Card, Second Wind and Trail Mine. The ramped down-weight (H) reaches
4.1% at last place without any of these edge cases.

**Exploit re-check under H** — Monte Carlo, 6 players × 7 days × 10,000
steps/day, interval 2,500, position recomputed from `totalSteps` (raw + bonus)
every 3h, offense targeted at the prod-measured share (61% lead / 34% mid / 5%
last), 70% use rate, 200 races per bisection step:

| Config | min winning walk-fraction φ (with damage) | φ (damage off — worst case) | hoarder edge |
|---|---|---|---|
| A current | 119.2% | 105.3% | +785 (+1.0%) |
| A + Option E | 125.1% | 105.2% | +5,932 (+7.4%) |
| H | ~115% | 107.7% | **+10,300 (+12.5%)** |
| H + Option E | ~125% | 115.2% | **+19,958 (+24.9%)** |

- **Sandbagging (walking less on purpose): NOT viable** under any variant.
  φ > 1.05 even with all incoming damage disabled. The static break-even
  estimate (74–88%) is **wrong** because it holds npos fixed; bonus steps feed
  into `totalSteps`, which feeds position, so the catch-up switches itself off
  as soon as it works. Box supply also still scales with raw steps.
- **Hoarding IS viable and is created by this change.** Unused powerups do not
  raise `totalSteps`, so a player who banks everything stays pinned at the back
  and farms trailing odds all race, then dumps on the final day. Worth **+1.0%
  today**, **+12.5% under H**, **+24.9% under H + Option E** — for a player
  walking exactly the field average. This is the §7 box-banking exploit
  (mint-vs-open position) plus a new *hold-unused-powerups* variant that
  mint-time snapshotting alone does **not** fix.
  > **Magnitude correction (2026-08-09).** Those percentages are an **upper
  > bound**: the sim let the hoarder bank unlimited items. In reality inventory
  > is capped at `DEFAULT_POWERUP_SLOTS = 3` plus `MAX_QUEUED_BOXES = 1`, and
  > further crossings are **forfeited** (`rollPowerup.js:5-6,137-145`), so at
  > most 4 items can be banked. The perverse *incentive* is real and is what
  > the raw-steps fix removes; the realised edge is well under +12.5%.
  > Residual after the fix: deliberately resting so opponents pass you on **raw**
  > steps, then opening ≤4 banked boxes at trailing odds — worth ≤ 4 × (1,180 −
  > 635) ≈ 2,200 steps against a ~10,000-step rest day. Unprofitable.
- **Prerequisite for shipping H:** compute the drop-odds position from **raw
  walked steps** (the quantity `boxSteps.js` already treats as
  manipulation-proof) instead of `totalSteps`. Keep `isStepLeader` /
  `isStepLast` on `totalSteps` so the RED_CARD / SECOND_WIND hard exclusions
  still match the use-time check. Code change in `openMysteryBox.js` and
  `getRaceProgress.js` (pass a second `rawStepTotals` into `buildRollContext`).

**Config-only vs code change**

| Piece | Config-only? |
|---|---|
| H weight table (`dropPool`, `positionOdds`, `positionRules`) | **Yes** — one `balance_config` row, `validateConfig` clean, no `schemaVersion` bump, no deploy. Kill switch unchanged. |
| Option E interval scaling | No — `powerupStepInterval` is a per-race column |
| Raw-steps position (hoarding prerequisite) | No — `openMysteryBox.js` / `getRaceProgress.js` |
| Repeat-target cap (F), Wrong Turn clamp (G) | No |

**Frozen-client safety.** `positionOdds` rows still sum to 1.0, so the odds
sheet's `rarity` block renders (it hides itself below 1.0 ± 0.01).
`typeOddsForPosition` sums a type's contribution across every tier it appears
in, so a type listed in two tiers is disclosed correctly. No new powerup types,
no new fields, no client gate involved — old binaries are unaffected. One
cosmetic wrinkle: a Protein Shake rolled from the UNCOMMON tier is stamped
`race_powerups.rarity = uncommon`, so a frozen client tints that copy as
uncommon while its upgrade price stays COMMON (`rarityByType` untouched).
Confusing, not wrong, and reversible.

---

## 9. Batch 2026-08-09 — proposed numbers (analysed 2026-08-09, NOT APPLIED)

Spec: `docs/feature-batch-2026-08-09-requirements.md`, items 1, 6, 8. Nothing in
this section is in code, seeds or the DB.

### 9.1 Item 1 — Wrong Turn / Leg Cramp duration nerf

`DURATIONS_MS.LEG_CRAMP` / `.WRONG_TURN` `[1h,2h,3h,4h]` → `[1h,1h15,1h30,1h45]`
(`CODE powerupUpgrades.js:36,:41`). Costs proposed unchanged.

Marginal value per level after the nerf (same 1,737 steps/h basis as §3.4c):

| | +min | coins (live ladder) | swing steps | steps/coin | was |
|---|---|---|---|---|---|
| `LEG_CRAMP` L1 | +15 | 10 (UNCOMMON) | 434 | 43 | 174 |
| `LEG_CRAMP` L2 | +30 | 30 | 868 | 29 | 116 |
| `LEG_CRAMP` L3 | +45 | 90 | 1,302 | **14.5** | 58 |
| `WRONG_TURN` L1 | +15 | **15** (RARE ladder, §3.3f) | 868 | 58 | 232 |
| `WRONG_TURN` L2 | +30 | **45** | 1,737 | 39 | 154 |
| `WRONG_TURN` L3 | +45 | **135** | 2,605 | **19** | 77 |

The duration ladder is arithmetic (+15 min per level) while the cost ladder is
geometric (×3 per level), so marginal price per minute rises 0.67 → 1.0 → 2.0
c/min for Leg Cramp and 1.0 → 1.5 → 3.0 for Wrong Turn.

Repricing candidate (arithmetic cost to match an arithmetic duration; uses the
existing, currently-empty `upgradeCosts.byType` seam, config-only, no deploy):

```
upgradeCosts.byType.LEG_CRAMP  = [0, 10, 20, 30]    -> 43 steps/coin flat
upgradeCosts.byType.WRONG_TURN = [0, 15, 30, 45]    -> 58 steps/coin flat
```

L1 prices are unchanged, so the entry point is untouched. `byType` is not
covered by any `SOFT_BOUNDS` entry (`upgradeCosts.byRarity.*.3` only).

Mystery Potion alignment (hardcoded 2h cramps → 1h): pool weights are
`LEG_CRAMP` (enemy) 10/100 and `LEG_CRAMP_SELF` 5/100, so the swap costs the user
`0.10 × 1,737 = 174` swing steps and refunds `0.05 × 1,737 = 87`, net **−87 swing
steps per potion (≈ −5% of potion EV)**. `mystery_potion` is `active=false,
test_only=true` at 40 coins in prod, so the bypass it closes is currently
unreachable anyway.

### 9.2 Item 6 — Power Outage from shop to `dropPool.RARE`

`POWER_OUTAGE`: 30-min AoE powerup lockout of **every enemy** (teammates exempt —
`isEnemy`), non-stackable (already-jammed victims are skipped), countered by
Umbrella (immune, not consumed) and Compression Socks (consumed, blocks).
`CODE usePowerup.js:1387-1461`, duration `:129`. Not upgradeable, no step swing.

> **Umbrella is unobtainable in prod**: `powerup_shop_items.umbrella` is
> `active=false` and it is in no `dropPool`. Compression Socks (a free RARE,
> 3.4–6.0% per box) is the only reachable counter today.

Prod all-time: **13 copies used by 6 users**, 76 victim effects, 5 Socks blocks.
Purchases ≈ 1,950 coins all-time — a negligible share of the −914/day
`powerup_purchase` sink.

**Item 6 and item 8a cancel out on tier size.** The spec's "RARE weight 9.5 →
10.5" holds only if Fanny Pack stays; with 8a it is 9.5 → 9.5 and Power Outage
takes Fanny Pack's slot **exactly**. Verified with the backend's own
`typeOddsForPosition`: **every other type's per-position odds are byte-identical
before and after.**

Per-position `POWER_OUTAGE` drop probability, N=6, live prod config
(spec estimated 2.6% / 4.3% — both low):

| | P1 | P2 | P3 | P4 | P5 | P6 |
|---|---|---|---|---|---|---|
| weight 1.0 | 3.38 | 3.32 | 3.79 | 4.76 | 4.87 | **6.00** |
| weight 0.5 | 1.80 | 1.75 | 2.00 | 2.53 | 2.59 | 3.21 |
| w1.0 + `leadingDownweight 0.3` | 1.11 | 1.07 | 3.79 | 4.76 | 4.87 | 6.00 |

RARE-tier internal share after the swap: **12.5% at the leader** (pool loses Red
Card + Second Wind), 10.5% mid, **13.3% at last** (pool also loses Trail Mine and
halves Cleanse/Mirror).

**Absolute supply is leader-skewed, not trailer-skewed.** Multiplying by the
measured boxes/race per quintile (§3.3e):

| npos | boxes/race | P(PO) | PO per race | with `leadingDownweight 0.3` |
|---|---|---|---|---|
| 0 (leader) | 18.71 | 3.38% | **0.631** | 0.208 |
| 0.25 | 12.59 | 3.32% | 0.417 | 0.135 |
| 0.5 | 7.22 | 3.79% | 0.274 | 0.274 |
| 0.75 | 4.01 | 4.76% | 0.191 | 0.191 |
| 1 (last) | 1.97 | 6.00% | 0.118 | 0.118 |
| **leader : last** | | 1 : 1.78 | **5.34 : 1** | **1.76 : 1** |

App-wide supply at 389.8 rolls/day, weighted by the observed drop-position mix
(§3.3e, n=16,775): **3.57% → ≈13.9 Power Outages/day**, i.e. more free copies per
*day* than have been bought in the product's entire history. With
`leadingDownweight { POWER_OUTAGE: 0.3 }` it is **1.87% → ≈7.3/day**.

Discard: the rarity change lifts its would-be discard price 5 → 10
(`race_powerups.rarity` is stamped `rare` by the roll). At 13.9/day that is at
most +139 coins/day of faucet, replacing Fanny Pack's ~10/day × 10 = 100/day —
and the 40/day per-user cap binds long before either.

### 9.3 Item 8 — Fanny Pack out, Lucky Horseshoe to a 100% rare floor

RARE pool after both items (weights in parens):

```
RED_CARD (0.5), SECOND_WIND, COMPRESSION_SOCKS, LUCKY_HORSESHOE, TRAIL_MINE,
SNEAKY_SWAP, SHORTCUT, CLEANSE, MIRROR, POWER_OUTAGE          total 9.5
  leader   -> RED_CARD, SECOND_WIND excluded                  total 8.0
  last     -> TRAIL_MINE excluded, CLEANSE/MIRROR ×0.5        total 7.5
```

Fanny Pack: 300 drops in 30d (≈10/day), zero step swing, permanent +1 inventory
slot. Removing it tightens inventory slightly and removes one 0-swing rare; it
does not move any EV number in §3.4b.

**Horseshoe as a "guaranteed rare" voucher is EV-neutral-to-negative in step
swing**, because RARE is the *lowest*-value tier (§3.4b). Forced-RARE EV vs the
unforced box EV it replaces, N=6:

| Position | E[unforced box] | E[forced RARE, horseshoe excluded] | ratio |
|---|---|---|---|
| P1 (leader) | 1,093 | 561 | **0.51** |
| P2 | 1,292 | 1,309 | 1.01 |
| P3 | 1,308 | 1,309 | 1.00 |
| P4 | 1,534 | 1,483 | 0.97 |
| P5 | 1,552 | 1,483 | 0.96 |
| P6 (last) | 1,547 | 1,450 | 0.94 |

(With `SNEAKY_SWAP` valued at 1,500 steps the ratios become 0.68 / 1.11 / 1.09 /
1.05 / 1.04 / 1.03 — the leader stays clearly negative.) The current L0 behaviour
(force UNCOMMON) is *better* in swing terms than the proposed L0 (force RARE),
because UNCOMMON is 100% Wrong Turn / Leg Cramp / Stealth in a solo race.

No-refund sizing: **4 upgrade events, 3 users, 295 coins, all tier 1, all already
consumed; zero upgraded copies held** (§3.6). There is no SKU to reprice —
`powerup_shop_items` has no `lucky_horseshoe` row.

Self-exclusion on forced boxes removes a geometric tail of ratio 0.105–0.133,
i.e. **12–16% of forced-rare value**; it is a feel/anti-dud change, not an
exploit fix (§3.6).

Soft bound: `[1,1,1,1]` passes hard `validateConfig` (monotone, ≤1, `[3]===1`)
but trips `SOFT_BOUNDS` entry `luckyHorseshoe.rareChanceByLevel.1` (max 0.5) →
**422 `bound_warnings`** unless the PUT sets `acknowledgeBoundWarnings`, which
stamps `boundOverride=true` on the row. Because the bound is a *level-1 ramp*
guard and the ramp is being retired, the entry should be **deleted** from
`SOFT_BOUNDS` rather than widened to `[0,1]` (a vacuous bound that would still be
advertised to the admin UI by `serializeBounds`). Leaving it in place means every
future balance-config save inherits `boundOverride`, masking genuine warnings.

### 9.4 Spec corrections found while verifying

1. **Item 1 cost premise is wrong for Wrong Turn.** Live prod
   `rarityByType.WRONG_TURN = RARE`, so its ladder is `[0,15,45,135]`, not the
   UNCOMMON `[0,10,30,90]` the spec quotes. Leg Cramp is UNCOMMON as stated.
2. **Item 6's "RARE weight 9.5 → 10.5" and "≈2.6% / ≈4.3%" are wrong** once item
   8a lands in the same PUT: total stays 9.5 and the real rates are 3.38% /
   6.00% (§9.2).
3. **Item 8b's "duplicated block in `rerollMysteryBox.js`" does not exist.**
   The reroll path deliberately ignores `minRarity`
   (`rerollMysteryBox.js:295-297`); the only horseshoe-forced pick is
   `openMysteryBox.js:186-194`. The duplicated function in the reroll file is
   `resolveNullRoll`, a different mechanism.
4. **Frozen-client edge for item 8b step 2.** Removing `LUCKY_HORSESHOE` from
   `upgradeableTypes` makes `usePowerup.js:1013-1015` reject any
   `upgradeLevel > 0` with a **400** ("… is not upgradeable"). Shipped binaries
   still render the tier picker (`FE/lib/constants/powerup_copy.dart:552-557`),
   so a player picking a tier gets a hard error until the next release. Setting
   `upgradeCosts.byType.LUCKY_HORSESHOE = [0,0,0,0]` and leaving it in
   `upgradeableTypes` makes those requests free no-ops instead.

---

## 10. Rainstorm — measured facts (verified 2026-08-10, prod SELECT-only)

| Fact | Value | Source |
|---|---|---|
| Store price | **75 coins**, `active=true`, not testOnly | `DB powerup_shop_items` |
| Duration / magnitude | 60 min, `metadata.multiplier = 0.5` (fixed, non-upgradeable) | `CODE usePowerup.js:167-168` |
| Targeting | untargeted **AoE**: every alive enemy participant (enemy team only in team races); caster exempt | `CODE usePowerup.js:2907-2980` |
| Counters | `UMBRELLA` = immune, not consumed — **but `umbrella` is `active=false` in the store and in no drop pool, i.e. unobtainable**; `COMPRESSION_SOCKS` = consumed, blocks. Mirror cannot reflect it (shop-powerup rule) | `CODE`, `DB` |
| Supply | 61 copies ever, **all** `earned_at_steps IS NULL` (store purchase or daily-spin grant); never a box drop | `DB race_powerups` |
| Usage | 60 casts by 9 casters → **588 victim-rows**, i.e. **9.8 victims per cast** | `DB race_active_effects` |
| Steps walked inside a storm window, per victim | mean **590**, p50 192, p90 1,842, 20.4% zero | `DB step_samples × race_active_effects` |
| Victim buffed during the storm | **72 / 588 rows (12.2%)**; **16.3%** of all storm-window steps fall inside a buff sub-window; step-weighted mean buff multiplier in those segments **M = 2.66**, time-weighted mean M = 2.16, max 4.39 | same |

Realised damage at the **current subtractive** rule (`M − 0.5`):
`0.5 × 347,128` = **173,564 scored steps** all-time, ≈ **2,893 per cast**
(= 38.6 swing-steps/coin at 75).

Multiplicative rule (`M × 0.5`) recomputed over the same rows:
`0.5 × (290,375 unbuffed + 151,038 buffed-M-weighted)` = **220,707**, ≈ **3,678
per cast** — **+27.2%**, 49.0 swing-steps/coin. Unbuffed victims (M = 1) are
bit-identical under either rule.

`COIN_FLIP`'s losing side is hardcoded `multiplier = 0.5`
(`CODE usePowerup.js:3515`), so its `lostFraction` is always exactly 0.5 —
identical to Rainstorm's. All-time coin-flip effect rows: **5**.

---

*Last full verification pass: 2026-08-08 (prod SELECT-only, aggregates only).
§3.2 (config v4), §3.5, §3.6, §3.7 and §10 verified 2026-08-10 (prod
SELECT-only, aggregates only).
§3.2 / §3.4 / §3.4b / §3.4c / §3.5 / §3.6 / §9 verified and added 2026-08-09
(prod SELECT-only, aggregates only). §8 Option H and §9 are analysis only —
nothing in either has been applied.*
