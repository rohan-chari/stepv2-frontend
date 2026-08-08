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

### 3.2 Rarity + drop pool — `DB balance_config` (latest row `5ba76396…`, created 2026-07-28 09:46:24)

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
```

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
| `rarityByType.WRONG_TURN` | `RARE` | `UNCOMMON` | drops from the **UNCOMMON** tier (dropPool wins) but upgrades on the **RARE** ladder — 195 coins to max instead of 130 |
| `rarityByType.SNEAKY_SWAP` | `UNCOMMON` | `RARE` | drops from RARE, tinted/priced as UNCOMMON |
| `storeOnlyTypes` | 7 entries | 17 entries | harmless — `enforceStoreOnlyExclusion` unions the code list before filtering `dropPool` |
| `dailyBoxExcludedTypes` | present | removed | ignored at runtime |

### 3.4 Upgrade ladder — `DB balance_config.upgradeCosts.byRarity`

| Rarity | L1→L2 | L2→L3 | L3→L4 | Full |
|---|---|---|---|---|
| COMMON | 5 | 15 | 45 | 65 |
| UNCOMMON | 10 | 30 | 90 | 130 |
| RARE | 15 | 45 | 135 | 195 |

15 upgradeable types (`upgradeableTypes`). `TRAIL_MAGNET` and `CAMPFIRE_REST`
are upgradeable but **no longer generated** (`powerupOdds.js:6`).

### 3.5 Discard — current behaviour

`CODE powerups/commands/discardPowerup.js` — sets status `DISCARDED`, writes a
race event, emits `POWERUP_DISCARDED`. **Pays 0 coins today.** Eligible statuses:
`HELD` and `MYSTERY_BOX` (i.e. an *unopened* box can be discarded).

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
dominant term. Sandbagging remains unprofitable: last place still earns 6×
fewer boxes than the leader.

**Option F — repeat-target cap (code change)** e.g. max 2 offensive effects
from the same attacker on the same victim per rolling 24h per race. Prod tail
today: p99 = 10, max = 19 uses per (race, attacker, victim) pair.

**Option G — Wrong Turn sign clamp (code change)**
`effectMultiplier.js:132` currently returns `−M`. Clamping to `−min(M, 1)`
removes the "your paid buff is turned into double damage" interaction (8.4% of
Wrong Turns today).

---

*Last full verification pass: 2026-08-08 (prod SELECT-only, aggregates only).*
