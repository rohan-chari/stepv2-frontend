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
| `SPEC` | approved requirement, not live until implemented/deployed |

Where `DB` and `SEED`/`CODE` disagree, `DB` wins at runtime unless the seed's
`update` block reasserts the field on deploy.

**Historical-ledger retention caveat — verified 2026-08-18:** account deletion
explicitly deletes that user's `coin_transactions`; `ad_reward_grants` and
`daily_reward_claims` are also removed by their user-delete cascades. Historical
DB rollups of coin sources/sinks, rewarded-ad grants, and daily claims therefore
describe retained accounts and can revise downward after deletion. They are not
immutable totals of all issuance, spending, or verified ad interactions.
Sources: `CODE src/modules/users/commands/deleteUserAccount.js:243-279` and
`CODE prisma/schema.prisma:424-482` (backend repo).

---

## 0. Population baseline — verified 2026-08-08 (prod, read-only)

### 0d. IAP planning refresh — verified 2026-08-18 (prod, read-only)

Trailing 30 complete calendar days (`2026-07-19` through `2026-08-17`). Date
math uses the database's tz-naive `steps.date` and
`coin_transactions.created_at::date`. Review accounts are excluded from player
percentiles.

| Metric | Value | Source |
|---|---:|---|
| 30d step-active users / user-days | 642 / 4,491 | `DB steps × users` |
| Mean DAU with steps | 149.7 (daily min 79 · max 517) | `DB steps` (30 dates) |
| Per-user steps / active day | p10 1,584 · **p50 5,884** · p90 11,611 | `DB steps` (n=642 users) |
| Recurring positive coins / active day | p10 0 · **p50 9.0** · p90 75.4 · mean 29.4 | `DB steps × coin_transactions` (n=642 users; excludes tutorial, referral, admin/manual, refunds and redistributed buy-in payouts) |
| Positive coins / individual active step-day | p10 0 · **p50 0** · p90 141 · mean 60.6 | `DB steps × coin_transactions` (n=4,491 user-days) |
| Positive coins / earning day | p10 1 · **p50 74** · p90 280.7 · mean 122.7 | `DB coin_transactions` (n=2,274 user-days; 564 users) |
| Current balance, 30d step-active users | p10 10 · **p50 138** · p90 706.9 · max 9,238; 0 negative | `DB users.coins` (n=642) |

### 0e. Current review refresh — verified 2026-08-23 (prod, read-only)

Trailing 30 complete calendar days (`2026-07-24` through `2026-08-22`). Date
math uses the database's tz-naive `steps.date` and
`coin_transactions.created_at::date`; review accounts are excluded.

| Metric | Value | Source |
|---|---:|---|
| Step-active users / user-days | 829 / 7,029 | `DB steps × users` |
| Per-user steps / active day | p10 1,235 · **p50 5,774** · p90 13,572 · mean 6,832 | `DB steps` (n=7,029 user-days) |
| Recurring positive coins / active day | p10 0 · **p50 10.53** · p90 75.67 · mean 30.75 | `DB steps × coin_transactions` (n=829 users; excludes tutorial, referral, admin/manual, refunds and redistributed buy-in payouts) |
| Positive coins / earning day | p10 1 · **p50 56** · p90 257 · mean 114.14 | `DB coin_transactions` (n=3,892 user-days) |
| Total positive / negative ledger | **+14,807.7 / −6,079.7 per day**; net **+8,728.0** | `DB coin_transactions` (n=9,784 positive and 3,723 negative rows) |
| Active purchasable powerup / cosmetic minimum | **75 / 250 coins** | `DB powerup_shop_items`, `DB shop_items` (active, non-test-only) |

### 0f. Feature-batch refresh — verified 2026-08-26 (prod, read-only)

Trailing 30 complete calendar days (`2026-07-27` through `2026-08-25`). Date
math uses the database's tz-naive `steps.date` and
`coin_transactions.created_at::date`; review accounts are excluded.

| Metric | Value | Source |
|---|---:|---|
| Step-active users / user-days | 967 / 8,828 | `DB steps × users` |
| Per-user mean steps / active day | p10 1,766 · **p50 5,886** · p90 11,408 | `DB steps` (n=967 users) |
| Recurring positive coins / active day | p10 0 · **p50 10.46** · p90 75.08 · mean 30.59 | `DB steps × coin_transactions` (excludes tutorial, referral, admin/manual, refunds and redistributed buy-in payouts) |
| Total positive / negative ledger | **+19,520.87 / −7,738.30 per day**; net **+11,782.57** | `DB coin_transactions` (894 retained ledger users) |
| Daily-reward / funded-race-payout issuance | **1,888.50 / 7,019.17 coins/day** | `DB coin_transactions` |
| Powerup purchase / upgrade sinks | **−2,990.83 / −3,295.17 coins/day** | `DB coin_transactions` |

The current median makes a 150-coin item **14.3 active days** of recurring
income (p10 cannot afford it from recurring income; p90 takes 2.0 active days).

### 0c. Refresh — verified 2026-08-12 (prod, read-only)

| Metric | Value | Source |
|---|---:|---|
| Steps/day (steps>0, 30 calendar days) | p10 1,305 · **p50 5,826** · p90 14,069 · mean 6,957 | `DB steps` (n=2,533 user-days; 162 users) |
| Positive coins / active step-day | p10 0 · **p50 0** · p90 120 · mean 43.2 | `DB steps × coin_transactions` (n=2,533 user-days) |
| Positive coins / earning day | p10 10 · **p50 55** · p90 311 · mean 119.9 | `DB coin_transactions` (n=942 user-days; 125 users) |

Date math uses the database's tz-naive `date` / `created_at::date`, never
node-pg timestamp conversion.

### 0b. Refresh — verified 2026-08-11 (prod, read-only)

| Metric | Value | Source |
|---|---|---|
| Users with steps in 30d | 124 | `DB steps` |
| Steps/day (steps>0, 30d) | p10 1,241 · **p50 5,751** · p90 13,977 · mean 6,866 | `DB steps` (n=2,611 user-days) |
| Users with a live human-created race **right now** | 47 | `DB races × race_participants` |
| Users with **no** live human-created race (CTA target) | 77 | same |
| Steps/day, has live human race | p50 7,883 · p90 13,412 | `DB steps` (n=47) |
| Steps/day, **no** live human race | p50 5,537 · p90 10,553 | `DB steps` (n=77) |
| Concurrent **human-created** races per user-day (30d) | p50 2 · p90 6 · max 21 · mean 2.55 | `DB` (n=1,337 user-days) |
| Accepted participants per user-created race (started 30d) | p50 4 · p90 17 · max 30 · mean 6.58 | `DB` (n=52 races) |
| Box-sourced powerups per participant-race (user races, 30d) | p50 18 · p90 48 · max 115 · mean 23.5 | `DB race_powerups` (n=350) |
| Powerups minted/day (30d) | **471.3** total — 292.0 from user races, 179.3 from seeded | `DB race_powerups` |
| Total coin sources / sinks / net | **+3,544 / −2,421 / +1,123 per day** | `DB coin_transactions` |

### 0a. Original baseline — 2026-08-08

| Metric | Value | Source |
|---|---|---|
| Users with steps in 30d | 112 | `DB steps` |
| Steps/day (rows with steps>0, 30d) | p10 1,257 · **p50 5,775** · p90 13,948 · p99 21,901 · mean 6,869 | `DB steps` (n=2,545 user-days) |
| Coins earned per **active day** (users with ≥7 active days) | p10 0 · **p50 3** · p90 98 · max 296 · mean 33 | `DB coin_transactions` (n=92 users) |
| Coins earned per **earning day** (days with ≥1 positive txn) | p10 10 · p50 45 · p90 260 · p99 683 | `DB coin_transactions` (n=833 user-days) |
| Concurrent races per user-day | p50 3 · p90 7 · max 13 | `DB race_powerups` |
| Powerups minted per user-day | p50 6 · p90 36 · max 94 · mean 13.1 | `DB race_powerups` (n=956 user-days) |
| Powerups **wasted** (expired/discarded) per user-day | p50 2 · p90 5 · max 15 · mean 2.5 | `DB race_powerups` |

> The latest verified median recurring income is **10.53 coins/active-day**.
> The cheapest active cosmetic (250) is **23.7 days** of median play; the
> cheapest active store powerup (75) is **7.1 days**. Older snapshots above are
> retained as historical baselines.

---

## 1. Coin sources

### 1e. Rewarded-ad surface refresh — verified 2026-08-25

Current code defines six SSV-namespaced rewarded surfaces: `extra_daily_spin`,
`coin_reward`, `powerup_unlock`, `shop_unlock`, `box_reroll`, and
`race_payout_double`. The global `OPS_AD_VALUE_ISSUANCE_DISABLED=true` brake
stops value issuance; otherwise all six paths are enabled subject to their
endpoint/cap and client/ad-unit gates. Source: `CODE
src/modules/economy/adRewards.js`, `src/shared/config/operationalControls.js`,
and FE `lib/services/ad_service.dart`.

The checked production connection is a snapshot whose latest write is
2026-08-19 (server clock 2026-08-25), so it proves historical live behavior but
not post-snapshot deployment state. In the trailing snapshot window there were
349 `coin_reward` grants / 41 users (348 consumed for exactly 8,700 coins =
**25 coins/watch**), 391 extra spins / 89 users (388 consumed; 14,120 minted
coins plus non-coin prizes), 694 box rerolls / 67 users (681 consumed), 85
race-payout grants / 49 users (84 consumed; 6,672 coins), and 8 powerup-unlock
grants / 4 users (6 consumed). No `shop_unlock` grant appeared. Source: `DB
ad_reward_grants`, aggregate-only read-only query, 2026-07-26 through
2026-08-24 with the observed data ending 2026-08-19.

**Code/live drift:** current code specifies uniform random **25–50 coins**
(EV **37.5**) and **5/day** for capable clients, while the production snapshot
shows the preceding **25 coins** and at most **3 consumed per watcher-day**.
Do not use the new 187.5-coin/day ceiling as a live baseline until a fresh
production connection or deployment check confirms it. Source: `CODE
adRewards.js`, `getAdCoinRewardStatus.js`; `DB ad_reward_grants`.

### 1d. IAP planning refresh — 30 days to 2026-08-18 (`DB coin_transactions`)

| Reason | Coins/day | n | Users |
|---|---:|---:|---:|
| `race_prize_pool_payout` | 2,714.8 | 1,442 | 365 |
| `tutorial_complete` | 1,623.3 | 487 | 487 |
| `referral_reward` | 1,366.7 | 82 | 60 |
| `daily_reward` | 1,214.0 | 1,179 | 289 |
| `step_milestone` | 748.0 | 1,323 | 174 |
| `ad_extra_spin` | 502.3 | 301 | 70 |
| `race_buy_in_payout` | 278.9 | 58 | 21 |
| `ad_coin_reward` | **240.8** | 289 | 29 |
| `race_finish_reward` | 188.5 | 71 | 19 |
| `race_payout_ad_double` | 143.5 | 44 | 31 |
| `powerup_discard` | 90.3 | 440 | 54 |
| `tournament_champion_reward` | 90.0 | 18 | 13 |
| all other positive reasons | 103.2 | — | — |
| **Total positive ledger** | **9,304.3/day** | | |

The direct coin-ad rule remains **25 coins × 3/day = 75/day** (`ENV`, read by
`CODE src/modules/economy/adRewards.js`). Actual direct coin-ad use was 289
views / 7,225 coins over 30 days: 29 viewers, median 3 views/viewer, max 65,
and 9.6 views per calendar day app-wide (`DB coin_transactions`,
`reason='ad_coin_reward'`).

### 1b. Refresh — 30 days to 2026-08-11 (`DB coin_transactions`)

| Reason | Coins/day | n | Users | vs 2026-08-08 |
|---|---|---|---|---|
| `daily_reward` | 840.8 | 712 | 80 | +8% |
| `race_prize_pool_payout` | **592.1** | 290 | 45 | **+100%** |
| `step_milestone` | 476.0 | 831 | 52 | +12% |
| `ad_extra_spin` | 367.2 | 166 | 20 | +23% |
| `race_buy_in_payout` | 294.9 | 57 | 20 | flat (legacy, redistribution) |
| `referral_reward` | **266.7** | 16 | 12 | **+167%** — see §11 |
| `race_finish_reward` | 253.2 | 105 | 19 | −6% |
| `ad_coin_reward` | 142.5 | 171 | 9 | +16% |
| `tutorial_complete` | 140.0 | 42 | 42 | +91% |
| `tournament_champion_reward` | 60.0 | 12 | 8 | +9% |
| others (`manual_grant`, `mystery_potion_refund`, refunds, `powerup_discard`, `bounty_payout`, `piggy_bank`, `admin_grant`) | ~106 | — | — | — |
| **Total sources** | **≈ 3,544 / day** | | | +26% |

### 1c. Featured tournament seed — verified 2026-08-12 (prod, read-only)

| Item | Live value | Source |
|---|---:|---|
| Active seed | `seed-tournament-daily-dash` / `DAILY_DASH`, display name **Tourneys** | `DB tournament_seeds` |
| Bracket / stored round duration / champion prize | 4 players / 1 day / 150 coins | `DB tournament_seeds` |
| Powerups | enabled; stored interval 2,500 | `DB tournament_seeds` |
| Completed featured brackets / champion mint, trailing 30d | 13 / 1,950 coins = **65.0 coins/day**; every mint was exactly 150 | `DB tournaments × coin_transactions` (`reason=tournament_champion_reward`, joined on `<tournamentId>:champion`) |
| Total bracket lifetime, completed brackets | p50 97.3h, p90 169.1h (n=13) | `DB tournaments` |

**Runtime drift:** `TournamentSeed.matchupDurationDays=1` is legacy stored
data. `CODE tournaments/constants/tournaments.js` clamps every newly-created
matchup to **2 days**, so a newly started 4-player bracket has a 4-day minimum
play window; existing legacy matchup races in prod remain 1 day. Likewise,
the renewal worker ignores the stored 2,500 interval and creates new
powerup-enabled matchups at the global fixed **2,000 steps/box**; old matchup
rows still include 2,500. `CODE tournaments/jobs/tournamentSeedRenewal.js`,
`races/services/validateRaceConfig.js`, `races/constants/powerupInterval.js`.

`powerup_discard` is now separately visible at **9.8 coins/day** (46 txns, 11
users) against a theoretical ceiling of 40/user/day × 124 users = 4,960/day.
The faucet has ~500× headroom; it is bounded by discard *behaviour*, not by the cap.

### 1a. Original — 30 days to 2026-08-08

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
| `tournament_champion_reward` | 55.0 | 7 | featured-seed champion mint (then-live seed prize 150) | `DB tournament_seeds × coin_transactions` |
| others (`manual_grant`, `mystery_potion_refund`, refunds, `bounty_payout`, `piggy_bank`, `admin_grant`) | ~96 | — | — | `DB` |
| **Total sources** | **≈ 2,813 / day** | | | |

## 2. Coin sinks

### 2d. IAP planning refresh — 30 days to 2026-08-18 (`DB coin_transactions`)

| Reason | Coins/day | n | Users |
|---|---:|---:|---:|
| `powerup_purchase` | −1,597.3 | 484 | 37 |
| `powerup_upgrade` | −1,224.0 | 1,763 | 85 |
| `shop_purchase` | −683.3 | 39 | 22 |
| `race_buy_in_hold` | −65.9 | 67 | 33 |
| `powerup_unlock_ads` | −28.6 | 7 | 4 |
| **Total negative ledger** | **−3,599.2/day** | | |

Gross sources / sinks / net were **+9,304.3 / −3,599.2 / +5,705.1 coins/day**.
Acquisition-period `tutorial_complete` and `referral_reward` contributed
2,990.0/day of sources; `race_buy_in_payout` is redistribution rather than new
issuance.

### 2c. Economy rollup — verified 2026-08-12 (prod, read-only)

Trailing 30 calendar days, grouped in pure SQL by the tz-naive ledger's stored
`created_at::date`: **+3,766.3 coins/day sources, -2,528.3 sinks, net +1,237.9/day**.
The positive-ledger earning-day distribution is p10 10, p50 55, p90 311 coins
(942 earning user-days, 125 users). Source: `DB coin_transactions`.

### 2b. Refresh — 30 days to 2026-08-11 (`DB coin_transactions`)

| Reason | Coins/day | n |
|---|---|---|
| `powerup_purchase` | −1,072.7 | 352 |
| `powerup_upgrade` | −702.3 | 1,152 |
| `shop_purchase` | −491.7 | 23 |
| `race_buy_in_hold` | −144.1 | 111 |
| `powerup_unlock_ads` | −11.0 | 4 |
| **Total sinks** | **≈ −2,421 / day** | |

**Net ≈ +1,123 coins/day** app-wide (≈ +9 coins/day per 30d-active user).

**Upgrade sink per box minted = 702.3 / 471.3 = 1.49 coins.** This is the
conversion factor for "what does one extra mystery box do to the coin economy":
each additional box drives ~1.49 coins of `powerup_upgrade` spend on average —
but the average is carried by leaders (§3.3e: 216 of 311 Protein Shake upgrades
came from the lead bucket, 9 from last), so boxes minted to trailing/low-engagement
players convert at well under 1.49.

### 2a. Original — 30 days to 2026-08-08

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

### 3.1a Current store catalog — `DB powerup_shop_items`, verified 2026-08-18

Enum labels are lowercase. Active, non-test-only rows are:

| Price | Types |
|---:|---|
| 75 | `decoy`, `defense_scan`, `quick_rinse` |
| 200 | `ghost_pepper`, `leech`, `rainstorm` |

There are six currently purchasable types. This supersedes the 2026-08-13
snapshot below; the DB remains runtime authority.

### 3.1b Hitchhike availability/value touchpoint — verified 2026-08-26

The authoritative prod row is **150 coins, `active=false`, `test_only=false`**.
The seed says 150, active, test-only, while its upsert deliberately preserves
the live admin-tuned availability fields. Lifetime retained-account history is
one successful 150-coin purchase by one user and one use; current global
inventory is zero. Sources: `DB powerup_shop_items`,
`powerup_purchase_requests`, `user_powerup_items`, `race_powerups`; `SEED
prisma/seed.js`.

Hitchhike copies one target's eligible effective steps 1:1 for 60 minutes; the
target loses nothing. One link may be active per caster and per target, but
there is no per-race or per-day purchase/use cap. Positive hourly step buckets
over the latest 30 complete days were p10 **19**, p50 **240**, p90 **1,404**,
p99 **4,343**, max **15,487** (n=110,286 user-hours; mean 548). At 150 coins
those observations correspond to 0.13 / 1.6 / 9.36 / 28.95 / 103.25 copied
steps per coin before any targeting advantage. Sources: `CODE
powerups/hitchhikeCopies.js`, `powerups/commands/usePowerup.js`; `DB
step_samples × users`.

The current daily-spinner implementation builds its powerup pool from the
active visible shop catalog. Therefore activating Hitchhike also makes it a
daily-spin prize for `powerups3`-capable clients; the balance-config
`storeOnlyTypes` list excludes it only from in-race mystery boxes. With the
current six-item pool (three 75-coin and three 200-coin items), adding the
150-coin Hitchhike gives it conditional powerup-hit probability **10.81% at
streak 1** and **6.81% at streak 30** under inverse-price weighting. Its
unconditional per-free-spin probability is 0.27%→1.53% when accessories
remain, or 0.54%→3.06% when the powerup pool receives the whole RARE slice.
Sources: `CODE economy/dailyBoxOdds.js`,
`powerups/queries/getEligiblePowerupPool.js`; `DB balance_config` v4 and
`powerup_shop_items`.

### 3.1 Store catalog — `DB powerup_shop_items`, verified 2026-08-13

Enum labels in this table are **lowercase**.

| Price | Active | Inactive (`active=false`) |
|---|---|---|
| 40 | `defense_scan` | `coin_flip`, `mystery_potion`(testOnly), `piggy_bank`, `pocket_watch` |
| 75 | `rainstorm`, `quick_rinse`, `decoy` | `imposter`, `signal_jammer`, `umbrella`, `bounty` |
| 150 | `ghost_pepper`, `power_outage` | `cleanse`, `hitchhike`, `rally_flag`, `drill_sergeant` |
| 300 | `leech` | `quicksand`, `uprising` |

**Cheapest purchasable powerup = 40 coins.** `SEED prisma/seed.js` still carries
different prices for some rows; its `update` block deliberately omits
`priceCoins`/`active` for the powerup upsert (see `admin/routes.js:492`) — do not
re-add them.

`decoy` is a concrete live drift: **DB = 75 coins, active, non-test-only**;
`SEED prisma/seed.js:327-335` still says 150 coins and test-only. DB is the
runtime authority because the seed update deliberately preserves admin-tuned
price/activation fields.

### 3.2 Rarity + drop pool — `DB balance_config` **v4** (`86a0d190-a45d-4937-bfe4-80badee7f82b`, created 2026-08-10 15:37:51) — verified 2026-08-19

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

`TRAIL_MAGNET` is likewise retired from generation: it is absent from every
live v4 `dropPool` tier and from the code-default pool. Prod retains 45
historical `race_powerups` rows, all box-sourced between 2026-05-16 and
2026-05-22; 44 are `used`, one `expired`, and none are held. Global inventory
also has zero positive quantity. Its rarity, enum, copy, and effect code remain
for historical/old-client compatibility. Sources: `DB balance_config`,
`race_powerups`, `race_powerup_events`, `user_powerup_items`; `CODE
balanceConfig.defaults.js:144-155`, `powerupOdds.js:6-9`.

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

### 3.3b Position-aware drop rules — `DB balance_config.positionRules`, verified 2026-08-13

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
| `leadingDownweight` | `{ RUNNERS_HIGH: 0.5, POWER_OUTAGE: 0.3 }` | full strength at npos ≤ 0.4, lerps to 1.0 at npos 0.5 |
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
| RED_CARD | 0 | 1.74 | 1.94 | 2.22 | 2.44 | 3.00 |
| SECOND_WIND | 0 | 3.48 | 3.89 | 4.45 | 4.87 | 6.00 |
| TRAIL_MINE | 3.70 | 3.48 | 3.89 | 4.45 | 4.87 | 0 |
| CLEANSE / MIRROR | 3.70 | 3.48 | 3.89 | 2.22 | 2.44 | 3.00 |
| COMPRESSION_SOCKS / LUCKY_HORSESHOE / SHORTCUT / SNEAKY_SWAP | 3.70 | 3.48 | 3.89 | 4.45 | 4.87 | 6.00 |
| POWER_OUTAGE | 1.11 | 1.04 | 1.17 | 4.45 | 4.87 | 6.00 |

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

### 3.3d Buff stacking + Wrong Turn sign rule — verified 2026-08-28

Source: `CODE races/services/effectMultiplier.js` and
`powerups/commands/usePowerup.js` in the backend repo.

`signedMultiplierAt(t)`, in order:

1. Any freeze active (`LEG_CRAMP`, `QUICKSAND`, Campfire freeze phase, Ghost
   Pepper freeze phase) → **m = 0**. Freeze beats everything, including Wrong Turn.
2. Buffs **SUM** (not multiply): RH 2 + Ghost Pepper 3 = 5. `M = 1` if no buff.
   Contributors: `RUNNERS_HIGH` 2, `CAMPFIRE_REST` meta, `UPRISING` 2,
   `RALLY_FLAG` 1.25, `COIN_FLIP` win, `GHOST_PEPPER` 3.
3. Reductions do not compound with copies of themselves. Each active Rainstorm
   independently proposes `M * 0.5`; each losing Coin Flip independently
   proposes `max(0, M - 0.5)`; the scorer keeps the lowest proposed result.
   Thus two Rainstorms remain **0.5M**, two losses remain **M - 0.5**, and when
   both overlap the stronger result at that `M` wins. Rainstorm is genuinely
   multiplicative; a losing Coin Flip is subtractive.
4. **`WRONG_TURN` returns `−M`** — it negates the *full* effective rate.

Consequence: Wrong Turn on a player running Runner's High is **−2×**, i.e. the
victim's paid buff is converted into double damage. Prod: **113 / 1,341
(8.4%)** of Wrong Turn windows overlap a self-buff window. No UI surfaces this.

Box progress is separate and immune to all of the above
(`CODE powerups/boxSteps.js` — raw walked steps only, additive bonuses excluded).

Same-type admission is not one global rule. Direct Runner's High, Ghost Pepper,
Stealth, Wrong Turn, Detour Sign, Lucky Horseshoe, Campfire Rest, Compression
Socks, Mirror, Fanny Pack, Decoy, Signal Jammer, Leg Cramp, Piggy Bank, and
Bounty paths reject another live copy in their respective user/target/race
scope. Quicksand rejects a selected target who already has either Quicksand or
Leg Cramp; the reverse direct Leg Cramp path checks Leg Cramp but not Quicksand,
so that accepted overlap is redundant under freeze precedence. Leech permits
one caster→victim link and at most two leechers per victim;
Hitchhike permits one link per caster and one per target. A caster may run only
one Rainstorm, while different casters' storms may overlap without multiplying
the 0.5x penalty. Uprising and Rally Flag merge a repeated beneficiary window to
the later expiry instead of adding a second multiplier row. Quick Rinse resolves
instantly but has a one-use-per-user-per-race-per-hour cooldown. Other
instantaneous actions have no active window to stack. Several effects without a
same-type guard can coexist; their payoff may still be redundant or clamped, so
"accepted twice" does not imply "twice the benefit."

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

### 3.3f Red Card × Decoy — verified 2026-08-13

Red Card auto-targets the current leader, then removes
`round(landingTarget.totalSteps × 10%)`. Decoy is resolved first: it consumes
the leader's Decoy and replaces the landing target with a uniformly random
alive third participant (excluding attacker and Decoy holder). The 10% basis is
therefore the **redirected participant's** total, not the leader's original
total. Source: `CODE powerups/commands/usePowerup.js:353,1604-1625,2261-2316,2756-2772`.

Prod example, August 13 Daily Challenge: the leader had 56,240 stored steps, so
a direct Red Card was worth 5,624. Their Decoy expired 14 ms before the use
event; the randomly redirected participant had 4,550 steps, producing the
stored penalty `round(4,550 × 0.10) = 455`. The HTTP result identifies
`outcome=REDIRECTED` / `redirectedBy=DECOY`, but the durable `POWERUP_USED`
feed metadata stores only `{penalty:455}`. Source: `DB races`,
`race_participants`, `race_active_effects`, `race_powerup_events` (aggregate,
read-only forensic query).

### 3.3g Config drift to flag

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
| `LEG_CRAMP`, `RUNNERS_HIGH`, `STEALTH_MODE`, `WRONG_TURN`, `DETOUR_SIGN` | 1h | 1h 15m | 1h 30m | 1h 45m |
| `POCKET_WATCH` | 1h | 2h | 3h | 4h |
| `COMPRESSION_SOCKS` | 24h | 30h | 36h | 48h |
| `CAMPFIRE_REST` | 45m | 60m | 75m | 90m |

Fixed (non-upgradeable) durations: `SIGNAL_JAMMER` 1h
(`usePowerup.js:170`), `POWER_OUTAGE` 30m (`:141`), Mystery Potion's cramps
**hardcoded 2h** self and enemy (`:546`, `:730`) with potion self-wrong-turn at
1h (`:559`) — the potion has never adopted the standard ladder.

**Cost per marginal duration minute** at the live ladders, with the empirical
targeted-victim walk rate of **1,737 steps/h** (§3.3c `LEG_CRAMP` realised
window average; 94% of those uses were L0/1h, so it is a clean per-hour rate):

| | +minutes vs L0 | coins | swing steps bought | steps/coin |
|---|---|---|---|---|
| `LEG_CRAMP` L1 | +15 | 10 | 434 | 43 |
| `LEG_CRAMP` L2 | +30 | 30 | 869 | 29 |
| `LEG_CRAMP` L3 | +45 | 90 | 1,303 | 14 |
| `WRONG_TURN` L1 | +15 | 15 | 869 (2× — sign flip) | 58 |
| `WRONG_TURN` L2 | +30 | 45 | 1,737 | 39 |
| `WRONG_TURN` L3 | +45 | 135 | 2,606 | 19 |

Market band for comparison (same value table): `PROTEIN_SHAKE` 150/100/67,
`SHORTCUT` 67/44/30, `PINECONE_TOSS` 50/50/33, `TRAIL_MIX` ≈50/…/22 steps/coin
at L1/L2/L3. `STEALTH_MODE` and `DETOUR_SIGN` buy 0 direct step value.

**Population walk-decay reference** (prod, 30d, hourly buckets from
`step_samples`, n=30,070 user-hours with steps>0): the hour *after* an active
hour averages **497 steps**, median 146, p90 1,459, and is **zero 23.4%** of the
time. A marginal duration extension is therefore worth 0.3–1.0× the first hour
depending on how well-timed the attack was; 1,737/h is the optimistic bound.

### 3.4d Jam counterplay — verified 2026-08-18

| Interaction | Rule | Source |
|---|---|---|
| `SIGNAL_JAMMER` | Blocks every powerup for 1h, including `CLEANSE` and `QUICK_RINSE` | `CODE usePowerup.js` jam guard |
| `POWER_OUTAGE` | Blocks ordinary powerups for 30m; post-fix guard permits only `CLEANSE` and `QUICK_RINSE` through | `CODE usePowerup.js:1041-1083` (2026-08-18 worktree; prod deployment not yet verified) |
| Both jams live | `SIGNAL_JAMMER` wins and both cleansers remain blocked | same guard; Signal Jammer lookup has precedence |
| `CLEANSE` | Ends every opponent-inflicted cleansable debuff immediately, including `POWER_OUTAGE`; self-buffs and `BOUNTY`/`RALLY_FLAG`/`UPRISING` survive | `CODE usePowerup.js:355-361,2892-2934` |
| `QUICK_RINSE` | Halves the remaining duration of every timed opponent-inflicted cleansable debuff, including `POWER_OUTAGE`; one use/race/hour | `CODE usePowerup.js:205-221,2088-2131,2720-2758` |

The bypass is type-specific, not a general jam immunity. `CLEANSE` remains a
free RARE box drop; its N=6 per-box odds are 2.22–3.89% by position (§3.3b).
`QUICK_RINSE` is store-only at **75 coins** (`DB powerup_shop_items`, active and
non-test-only). At the current 9 coins/active-day median recurring income
(§0d), one Rinse costs **8.3 median active days**.

Live usage baseline, 30 complete days through 2026-08-17 (`DB`, read-only): 127
Power Outage uses created 9,427 victim effects (mean 74.27 victims/use; p50 12,
p90 356, max 499); 259 Cleanses removed 285 effects; 126 Quick Rinses shortened
144 effects. A historical tray-state reconstruction found a Cleanse or Rinse
already held in-race for at most 334 / 9,427 outage victim rows (3.54%); this is
an upper bound because final row status cannot recover every intervening
discard/expiry. Current global inventory has 19 Quick Rinses across 9 users and
no Cleanse stock (race trays separately hold 83 Cleanses). Quick Rinse recorded
113 successful store purchases by 22 buyers for 8,475 coins in the same window
= **282.5 coins/day of sink** (`DB powerup_purchase_requests`, status label
`SUCCEEDED`).

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

### 3.7 Ad-funded mystery-box reroll — `CODE powerups/commands/rerollMysteryBox.js`, verified 2026-08-25

| Knob | Value | Source |
|---|---|---|
| Operational brake | enabled unless global `OPS_AD_VALUE_ISSUANCE_DISABLED=true` | `CODE operationalControls.js`, `adRewards.js` |
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

**Production-snapshot volume since launch (2026-08-10 through snapshot cutoff
2026-08-19):** 694 `box_reroll` grants / 67 users, 681 consumed. The snapshot's
write stream ends on 2026-08-19, so this is not a current-through-2026-08-25
counter. Source: `DB ad_reward_grants`, aggregate-only read-only query.

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

### 3.8 Pinecone zero-floor touchpoint — verified 2026-08-26

Live balance config v4 makes Pinecone Toss COMMON, with magnitudes
`[750,1000,1500,2250]` and upgrade costs `[0,5,15,45]`. The latest 30 days
contain 5,490 Pinecone feed events from 277 casters. The newer immutable impact
ledger covers 881 recipient impacts: 8 (0.91%) had fewer steps available than
the nominal penalty, so the durable displayed delta was clipped. Mean nominal
penalty was 1,041.7 steps and mean applied delta 1,037.0; the floor prevented
4,129 overkill steps total (516 per clipped cast). Six clipped casts are still
active and two completed; the two completed recipients received zero payout.
No current participant has a negative persisted `total_steps`, although 1,304
rows have a negative diagnostic `bonus_steps`. Sources: `DB balance_config`,
`race_powerup_events`, `race_impact_events`, `race_participants`; `CODE
powerups/powerupUpgrades.js`.

## 4. Race payouts

### 4.1 App-funded prize pool (current default)

`app_settings.fundedPrizePoolsEnabled` has **no prod row** → code default `true`
(`CODE src/shared/config/appSettings.js:103`). All new races are funded; buy-ins
are forced to 0.

> **Re-verified 2026-08-11.** `SELECT key,value FROM app_settings` returns 14
> rows and `fundedPrizePoolsEnabled` is **not among them**, so the code default
> stands. Consequence that is easy to get wrong: **a race created with
> `buyInAmount: 0` is not a race that pays nothing.** `createRace.js:211-242`
> coerces the buy-in to 0 *and* stamps `fundedPrize: true`, so every free race a
> user creates today mints `walkers × durationPoints × 20`. Measured over races
> created in the 30d to 2026-08-11: 40 of 52 user-created races carry
> `funded_prize = true` (the 12 that don't were all created 2026-07-12…23,
> pre-cutover). Any spec that reasons "free race ⇒ no payout" is wrong against
> live config.

Before payout rounding, per-participant EV is `durationPoints ×
PRIZE_COIN_UNIT` **independent of field size** (pool = N × dp × 20) — 40
coins for a 2-day race, 80 for a 7-day one. Races stamped
`payout_rounding_version=1` then round every positive recipient award up to a
multiple of 5 and mint the difference, so their final EV is weakly higher; see
§4.2. Realised payout remains highly placement-dependent. Measured
`race_prize_pool_payout` amounts, 30d: n=290, 45 users, p10 **2** · p50 **40**
· p90 **157** · max **336** (historical snapshot; current 30d source total is
in §1d).

Per participant-**day** the mint rate is `durationPoints × 20 / days`, which is
**higher for shorter races**: 1-day 20 · 2-day 20 · 3-day 13.3 · 7-day 11.4 ·
14-day 11.4. A quick-create preset menu therefore prices differently per preset.

> **Raw-pool invariant: 20 coins per player-day is the formula ceiling before
> recipient rounding or rewarded-ad duplication.** Verified 2026-08-16 by
> scanning every legal integer duration 1..30: `max(durationPoints(d) × 20 / d)`
> = **20**, attained at `d = 1` and `d = 8`. Nothing in the current system can
> put more than 20 raw pool coins per walker per elapsed day into a normal
> individual race. Version-1 per-recipient rounding can mint a subsidy above
> that raw pool, and a claimed payout-double ad mints up to 100 additional coins
> from the final base award. Two properties hold up the raw-pool invariant, and
> any change to race timing must preserve **both**:
> 1. `maxDurationDays` is an **integer number of days**, so a race is never
>    priced at a band it only barely entered (there is no 24h+1min race).
> 2. `maxDurationDays` equals the race's **actual elapsed length**, because
>    `endsAt = startedAt + maxDurationDays × 24h` (`CODE
>    races/commands/startRace.js:124-127`). Priced duration and real duration
>    are the same number by construction.
>
> A fractional window derived with `ceil` breaks (1): a 24h+1min window prices
> at 2 points over 1.0 elapsed days = **39.97 coins/player-day (2.00×)**.
> `round` gives 26.67 (1.33×) at a 1.5-day window; `floor` gives exactly 20.00
> and is the only rounding that preserves the invariant. A stamped end instant
> decoupled from `startedAt` breaks (2): a race priced at 30 days that actually
> runs 24h mints 8 points in one day = **160 coins/player-day (8×)**.

**Live footprint — re-verified 2026-08-16 (prod, read-only, pure-SQL dates).**
`race_prize_pool_payout` over the trailing 30 days: **1,616 coins/day**
(n=955 credits, 304 distinct users; p50 4 · p90 157 · max 2,163). That is
**21% of all coin minting** (all positive ledger rows: 7,561/day) against
3,122/day of sinks — the economy runs ~2.4× net-inflationary, and race pools
are its single largest source. 79 funded races completed in 30 days minting
48,600 coins; by `max_duration_days`: 1d n=52 (34,640) · 2d n=8 (2,480) · 3d
n=8 (1,640) · 7d n=10 (9,520) · 14d n=1 (320). Race durations created in the
same window: 1d ×107 · 2d ×68 · 7d ×57 · 14d ×28 · 3d ×27.
`DB coin_transactions`, `DB races`.

**Graded presets cannot be a quick-create default.** `startRace.js:87-95` rejects
the start of any non-`WINNER_TAKES_ALL` preset below
`MIN_MULTI_PAYOUT_PARTICIPANTS = 4` accepted, with a 400. `TOP3_70_20_10` and
`TOP3_80_15_5` are fixed-percentage and have **no** minimum, and unfilled places
mint nothing (`completeRace.js:346-352` skips a payout index with no ranked
recipient), so a 2-person TOP3 race mints 90% of its pool and pays two people.

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

**Live footprint — verified 2026-08-12 (prod, read-only).** *(Superseded by the
2026-08-16 re-verification above; the 691.5 coins/day figure here has since
grown to 1,616/day.)* There are 15
active funded races: individual n=13 (p50 3 accepted / 3 walkers,
max 104 accepted) and team n=2 (p50 6 / 6); neither has a forfeited row.
In the preceding 30 calendar days, 37 completed funded individual races minted
19,180 coins (p50 pool 440, p90 1,020, max 4,240) and 3 funded team races
minted 1,680 (800 each). The ledger's `race_prize_pool_payout` source is
691.5 coins/day (333 credits). `DB races × race_participants ×
coin_transactions`; `created_at::date` is used in SQL to avoid node-pg
timezone shifts.

### 4.1a Seeded Daily/Weekly V2 payout stamp — verified 2026-08-28 (prod, read-only)

Seeded `DAILY_10K`/`WEEKLY_50K` races use the creation-time V2 stamp from
`CODE backend src/modules/races/services/fundedExposure.js` (`unit=10`,
`max=8,000`), not the generic legacy/user-race defaults above (`20`/`16,000`).
For a weekly field of `N` walkers, the raw pool is
`min(N × durationPoints(7) × 10, 8,000) = min(40N, 8,000)`. Seeded races use
`TOP_HALF`; production's permanent settings stamp `GEOMETRIC` and payout
rounding v1 on new rows. Rounding rounds each positive award up to a multiple
of five and mints the subsidy.

The current prod weekly private stream has 48 active bucket races / 604
accepted participants; their rows are stamped `funded_prize=true`,
`payout_curve=GEOMETRIC`, `payout_rounding_version=1`, `prize_coin_unit=10`,
and `prize_pool_max_coins=8000` (`DB races × seeded_race_buckets`).

The 2026-08-28 Daily private stream has 22 active bucket races / 750 accepted
participants. Its planned capacities are
`[97,39,37,35,33,33,33,32,31,31,31,31,31,30,30,30,30,30,30,30,30,30]`;
every row is stamped calculation v2, `unit=10`, `max=8,000`, `TOP_HALF`,
`GEOMETRIC`, and payout-rounding v1. The latest three completed Daily windows
(2026-08-25..27 ET) had accepted membership exceed the sum of stored
`max_participants` by 41, 31, and 18 respectively. The 2026-08-27 window had
22 cohorts, 743 stored capacity, 761 accepted, 679 walkers, and 8,395 settled
payout coins; one stored-30 cohort settled 59 walkers. These are aggregate
facts, not a recommended cohort policy. Source: `DB seeded_race_buckets ×
races × race_participants`, prod read-only.

### 4.2 Individual payout presets — `CODE races/racePayoutPresets.js`

| Preset | Split | Notes |
|---|---|---|
| `WINNER_TAKES_ALL` | [100] | |
| `TOP3_70_20_10` | [70,20,10] | |
| `TOP3_80_15_5` | [80,15,5] | |
| `TOP_HALF` | `ceil(N/2)` places | funded + `payout_curve IS NULL` ⇒ even; funded + `GEOMETRIC` (seeded challenges) or legacy buy-in ⇒ geometric r=0.7 |
| `ALL_BUT_LAST` | `N−1` places | same curve rules |

Graded presets need ≥4 accepted (`MIN_MULTI_PAYOUT_PARTICIPANTS`). Geometric
floor per paid place = 1 coin. Every race has an immutable
`payout_rounding_version`: version 0 pays the raw whole-coin split; version 1
maps each positive award independently to `max(5, ceil(raw/5)×5)` and mints the
rounding subsidy. New-row stamping is controlled by
`DB app_settings.payoutRoundingV1Enabled` (currently `true`, verified
2026-08-18); missing/legacy rows remain version 0. Source: `CODE
races/services/payoutRounding.js`, `races/commands/completeRace.js`,
`races/jobs/seededRaceRenewal.js`.

### 4.3 Team race payouts — `CODE races/commands/completeRace.js:143-243`

- Team size 1–5 (`validateRaceConfig.js:96`); **1v1 is legal**. Sides must be
  equal and ≥1 to start (`startRace.js:67-79`). No minimum field for a funded pool.
- Pool = same §4.1 formula, `isTeamRace: true` walker count (includes forfeiters'
  frozen totals).
- **Winning team's non-forfeited members split 100% of the pool evenly**;
  remainder to the team's top stepper. **Losing team gets 0.** Placements: all
  winners 1, all losers 2.
- **Tie** ⇒ everyone placement 1. Legacy buy-ins are refunded. A *funded* tie
  mints its settled pool and splits it evenly among all **non-forfeited**
  members of both teams; `prizePoolCoins` is stamped. This differs from the
  pre-2026-08-08 behaviour, which neither paid nor stamped funded ties.
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

### 4.3a Active forfeit (current team-only behaviour, verified 2026-08-12)

`forfeitRace.js` rejects individual races. For an accepted active team member,
it snapshots the live effective total to `race_participants.total_steps`, sets
`forfeited_at`, and every progress/reconcile path preserves that frozen value.
The forfeiter remains `ACCEPTED`, so a positive frozen total remains a settled
pool walker, but receives no team payout; their surviving winning teammates
split the same pool. A zero-step forfeiter is not a settled walker, so it does
not add a funded-pool unit. If every member of one side forfeits, the race
settles immediately for the other side. Source: `CODE
races/commands/forfeitRace.js`, `races/racePrizePool.js`, and
`races/commands/completeRace.js`. This is current behaviour, not an
individual-race policy.

### 4.4 Seeded challenge finish rewards — `CODE races/constants/raceFinishReward.js`

Non-funded seeded races only (retired for funded).

| Seed | perHead | minPool | maxPool | paidFraction | places | tail floor |
|---|---|---|---|---|---|---|
| `seed-daily-10k` | 15 | 100 | 1,500 | 0.5 | 3–15 | 10 |
| `seed-weekly-50k` | 40 | 500 | 5,000 | 0.2 | 3–20 | — |

Split by descending linear weights (`computeGradedPayouts`).

### 4.5 Live Daily/Weekly challenge configuration — verified 2026-08-28

| Item | Daily (`seed-daily-10k`) | Weekly (`seed-weekly-50k`) | Source |
|---|---:|---:|---|
| Seed cap / duration / target | 500 / 24h / 0 | 500 / 168h / 0 | `DB race_seeds` |
| New-race payout preset | `TOP_HALF` | `TOP_HALF` | `CODE races/jobs/seededRaceRenewal.js:83-122` |
| Funding | app-funded | app-funded | `DB app_settings` has no `fundedPrizePoolsEnabled` row, so `CODE` default is `true` |
| New-race curve | `GEOMETRIC` | `GEOMETRIC` | `DB app_settings.seededGeometricPayoutsEnabled=true`; stamped by renewal |
| New-race payout rounding | v1: each positive award rounds up to 5 | same | `DB app_settings.payoutRoundingV1Enabled=true`; stamped by renewal |
| Raw pool EV per eligible walker, newly created rows | 10 coins / 1-day race | 40 coins / 7-day race | `CODE races/services/fundedExposure.js` v2 stamp; confirmed by current `DB races` rows. Rounding v1 raises realised EV above raw pool EV |

The active rows observed at verification had 61 accepted / 50 walkers (Daily)
and 68 accepted / 57 walkers (Weekly). These are live operational counts, not
configuration. `race_seeds.powerup_step_interval=2500` in DB is legacy stored
data; renewal deliberately stamps the global fixed 2,000 raw-steps/box cadence
(§3.3).

**2026-08-17 Daily settlement (verified 2026-08-18, prod read-only).** The
completed race displayed as a 496-person field but had 425 settled walkers;
settlement deliberately excludes accepted no-shows. Its raw funded pool was
`425 × 1 × 20 = 8,500`, `TOP_HALF` paid `ceil(425/2)=213` places, and the
row's stamped `GEOMETRIC` curve used ratio 0.7 plus a 1-coin floor. For fourth:
`1 + floor((8,500−213) × 0.7³ / Σ[i=0..212]0.7ⁱ) = 853`. The row was
created before payout-rounding v1 and retained immutable version 0, hence 853
rather than 855. The complete top six were
`[2501, 1741, 1219, 853, 597, 418]`; 213 awards summed exactly to 8,500.
At equal rank odds across 425 walkers, the raw outcome distribution was mean
20, p10 0, median 1, p90 1, p99 418, max 2,501. Applying current v1 to the same
raw split would pay 9,310 (mean 21.91/walker), a +810 / +9.53% rounding subsidy,
with fourth rounded to 855. Source: `DB races × race_participants`; `CODE
shared/economy/prizePool.js`, `races/racePayoutPresets.js`,
`races/services/payoutRounding.js`.

### 4.6 Feature-control cleanup economy snapshot — verified 2026-08-20 (prod, read-only)

Trailing 30 complete calendar days (`2026-07-21` through `2026-08-19`) now
show **10,953.7 coins/day of sources, 4,619.3/day of sinks, and +6,334.4/day
net** across 647 retained ledger users. App-funded ordinary/seeded race payouts
were **103,784 coins = 3,459.5/day**; rewarded race-payout ads added another
**6,752 = 225.1/day**. Sources: `DB coin_transactions` using tz-naive
`created_at::date`; historical-ledger deletion caveat in the document preface
still applies.

The current 30-day funded-race settlement population was 165 races. Its
stamped raw pools totalled 103,900 coins: 18,500 ordinary individual, 2,320
team, and 83,080 seeded. Replaying the same settled fields with a coin unit of
10 and permanent payout-rounding v1 gives:

| v2 pool ceiling | Raw pools | Rounded awards | Rounding subsidy | Reduction vs stamped v1/20-unit pools |
|---:|---:|---:|---:|---:|
| 16,000 (unchanged) | 60,110 | 65,115 | 5,005 | **37.3%** |
| 8,000 (scaled with the halved unit) | 52,110 | 57,550 | 5,440 | **44.6%** |

Thus `PRIZE_COIN_UNIT: 20 -> 10` does **not** by itself halve realised
issuance. The unchanged 16,000 ceiling keeps a large weekly seed close to its
old payout, and rounding every positive geometric tail award up to 5 mints a
subsidy. Source: exact replay of `DB races × race_participants` through `CODE
shared/economy/prizePool.js`, `racePayoutPresets.js`, and
`services/payoutRounding.js`.

Current live funded exposure (PENDING/ACTIVE accepted memberships, excluding
tournament matchup rows and featured champion-prize tournaments), recalculated
at unit 10 and including stamped team-pool multipliers, covers 686 users:
p50 **60**, p90 **140**, p95 **220**, p99 **603.6**, max **962.5** expected
coins. A 300-coin concurrent ceiling places 25 users (3.64%) above the limit;
the amount above the ceiling is 9.04% of all current exposure. The corresponding
expected-issuance-rate distribution, `membership EV / priced duration`, is
p50 **11.4**, p90 **27.1**, p99 **71.4**, max **120.9 coins/day**. A raw
concurrent ceiling alone is weakest against one-day races: unit 10 permits up
to 30 simultaneous one-day entries (300 expected coins/day) while the same
steps count in every race. Sources: `DB races × race_participants × tournaments
× tournament_participants`; `CODE teamPoolMultiplier.js` and tournament
`MAX_CHAMPION_PRIZE`.

Imposter retirement inventory remains **5 units across 4 owners**. Those owners
have two successful historical purchases totalling **575 coins** and three
consumed ad-spin grants totalling three free units; the inactive catalog row is
75 coins. Exact replacement is therefore **575 + 3×75 = 800 coins**. Sources:
`DB user_powerup_items × powerup_purchase_requests × powerup_shop_items ×
ad_reward_grants`.

Legacy buy-in status labels are not escrow balances. The one PENDING May race
has two `HELD` participant markers totalling 300 but **zero matching
`race_buy_in_hold` ledger debits**; cancelling it through a field-driven refund
path would incorrectly mint 300 coins. Eight COMPLETED races retain 40 `HELD`
markers totalling 1,155; 36 of those markers have real, unrefunded debits
totalling **830 coins**, while four have no matching debit. The 830 represents
late-join money that never entered those races' stamped pots, not a still-held
account balance. Sources: exact `(user_id, reason, ref_id)` joins over `DB
race_participants × races × coin_transactions`; `CODE joinRaceCore.js` stamps
active public paid joins `HELD` without increasing `potCoins`, whereas the
invite-accept path commits and increases the pot.

### 4.7 Payout-presence touchpoint — verified 2026-08-26

Six currently active funded team races have payout-rounding version 1 and hit
the current `buildRaceMoneyView` branch that deliberately returns a null
pre-settlement prize projection. They contain 42 accepted memberships; their
already-stamped projected pools total **2,900 coins** (min 80, p50 480, max
900). Rendering those existing projections changes no settlement or ledger EV.
Sources: `DB races × race_participants`; `CODE races/racePrizePool.js`.

Separately, 14 active tournament matchup races are intentionally
`funded_prize=false`, free, and zero-pot because their tournament pays the
champion rather than each matchup. One other open free non-funded race has only
one accepted no-show, so the funded formula would currently produce zero.
These rows are not missing-payout evidence by themselves: a response-level
payout representation must not silently convert a tournament matchup into a
second funded race settlement. Source: `DB races × race_participants ×
tournaments`.

---

## 5. Daily spinner (daily reward box) — verified 2026-08-19

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
gated by client capability tokens). The live prod catalog has six active,
non-test-only rows: `defense_scan`, `quick_rinse`, and `decoy` at 75 coins;
`rainstorm`, `leech`, and `ghost_pepper` at 200. `TRAIL_MAGNET` has no
`powerup_shop_items` row at all, so it cannot appear in the server-provided
daily-spinner pool. Retained-account audit rows contain zero `TRAIL_MAGNET`
free-daily or extra-spin grants.

Within a powerup hit, inverse-price weighting makes the conditional store-price
proxy **109.09 coins at streak 1** and **90.41 at streak 30**. With both an
unowned-accessory pool and powerup pool stocked, a spin hits a powerup with
probability `RARE × 50%`: 2.5% at streak 1 and 22.5% at streak 30, contributing
2.73 and 20.34 coins of store-price proxy per spin respectively. If the user
owns every accessory, the powerup gets the whole RARE slice: 5%→45%, or
5.45→40.68 proxy coins/spin. These are value proxies, not coin minting.

Trailing 30 complete days (2026-07-19 through 2026-08-17) produced 79 free-spin
and 43 extra-spin powerup grants among retained accounts. The catalog has
changed within that window, so historical grant types are not the current pool.
Source: `DB powerup_shop_items`, `daily_reward_claims`, `ad_reward_grants`.

`dailyBoxExcludedTypes` still exists in the `DB balance_config` row
(`DEFENSE_SCAN, LEECH, HITCHHIKE, QUICK_RINSE, RALLY_FLAG`) but is **dead data** —
it was removed as an authority on 2026-07-28 (`balanceConfig.js:264`,
`getEligiblePowerupPool.js:8`). The rule is now: **visible in the store ⟺
winnable from the spin.** Consequently the spinner remains a free source of the
most expensive active powerups (currently the 200-coin tier).

### 5.1 Unclaimed-reward reminder touchpoint — verified 2026-08-26

Current production sends daily-box reminders at 17:00 and 21:00 local. The
durable Inbox rows began on 2026-08-24 and currently contain 462 slot-17 and
467 slot-21 reminders, so there is not yet enough post-launch history for a
causal conversion estimate. Source: `CODE notifications/dailyRewardReminder.js`;
`DB inbox_alerts`.

Over the latest 30 complete days, 2,302 free daily claims by 489 retained users
minted 56,655 coins (**24.61 coins/claim**) plus 101 powerups and 116
accessories. Local-time claim timing was 1,602 before 17:00, 437 from
17:00–20:59, and 263 (11.4%) at/after 21:00; the late group minted 5,110 coins.
Config EV with both prize pools stocked is **17 coins at streak 1** and **34
coins at streak 30**, before valuing a RARE non-coin prize. Sources: `DB
daily_reward_claims × users`; `DB balance_config` v4.

At the verification instant, 537 users held 2,170 unopened mystery boxes in
open races (p50 3, p90 7, max 13). Among reminder-enabled non-review accounts,
491 had both a currently unclaimed daily reward and at least one unopened race
box, 38 box-only, 449 daily-only, and 48 neither. Opening an already-minted box
does not mint coins; the latest 30-day observed downstream rates were 1.97
coins of upgrade spend and 0.17 coins of discard issuance per box minted
(50,108 boxes). Sources: `DB users × race_powerups × races ×
coin_transactions`.

---

## 6. Cosmetics — `DB shop_items`, verified 2026-08-08

### 6.1 Current catalog refresh — verified 2026-08-18

| Price | Active, non-test-only, non-earn-only items |
|---:|---:|
| 250 | 6 |
| 500 | 9 |
| 750 | 1 |
| 1,000 | 1 |
| 2,000 | 1 |

There are 18 currently coin-purchasable cosmetics. At the current p50 recurring
rate of 9 coins per active day, these tiers represent 27.8, 55.6, 83.3, 111.1
and 222.2 active days respectively.

| Segment | n | Prices |
|---|---|---|
| active, not testOnly | 8 | 0 (×1), 250 (×3), 500 (×2), 1000 (×2) |
| active, testOnly | 56 | 250–1500 (avg 629) |

Affordability at p50 income (3/day): 250 ⇒ 83 days. At p90 (98/day): 2.5 days.

---

## 7. Known structural properties (carry forward)

- **Buff stacking** is sum-of-multipliers with a signed rate; Wrong Turn negates
  the complete effective rate after reductions (for example, Runner's High
  becomes −2x, not −1x). See §3.3d.
- **Effect scoring** uses closed buckets only; open-bucket inclusion once paid
  ~1.48×.
- **Box progress** uses raw walked steps only — never buffed/debuffed.
- **Position-aware drops**: `positionRules` excludes RED_CARD/SECOND_WIND from
  the leader, TRAIL_MINE from last place, and down-weights RUNNERS_HIGH and
  POWER_OUTAGE (leader) / MIRROR, CLEANSE, STEALTH_MODE (trailing). See
  §3.3b–§3.3f and §8.
- **Box supply is uncapped and purely step-linear**, so the front-runner's
  powerup income scales with the very quantity the race scores. This dominates
  every drop-table knob (§8).
- **No repeat-target cap / target cooldown** exists in `usePowerup.js`.
- **Position is read at box-OPEN time**, not mint time — unopened boxes can be
  banked and opened from a worse position (§8).
- **No concurrent-race limit** exists anywhere in the codebase. Observed max: 10
  simultaneous active races per user.
- **Referral farming** is bounded by one payout per provider identity (§11).
- **Box volume per race is an order statistic of field size.** Boxes are
  `raw_steps / 2000`, so the leader:last box ratio grows monotonically with the
  number of participants purely from the spread of the step distribution — no
  config change required. Monte Carlo (2×10⁵ trials/cell, lognormal fitted to
  the prod 30d steps/day p50 5,751 / p90 13,977, 7-day race):

  | Field | leader boxes | last boxes | leader:last (mean) | p50 | p90 | boxes/race |
  |---|---|---|---|---|---|---|
  | N=4 | 46.1 | 10.5 | **4.4×** | 4.1 | 10.3 | 100.4 |
  | N=7 | 55.3 | 8.0 | **6.9×** | 6.6 | 15.5 | 172.7 |
  | N=10 | 62.6 | 6.9 | **9.1×** | 8.7 | 19.7 | 248.0 |

  (N=7 and N=10 rows model the extra bodies as lower-step joiners, median 5,537.)
  Any feature whose success metric is "more participants per race" therefore
  worsens the §8 box-volume imbalance mechanically. Sim:
  scratchpad `boxsim.js`, 2026-08-11.

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

## 11. Referral economy — verified 2026-08-25 (prod SELECT-only)

### 11.1 Rates and guards

| Knob | Value | Source |
|---|---|---|
| Referrer reward | **500** coins | live production env unset; `CODE social/referralRewards.js:11-13` fallback |
| Referee reward | **500** coins (double-sided since batch 2026-07-27 D6) | live production env unset; `CODE social/referralRewards.js:14` fallback |
| **Total per successful referral** | **1,000 coins minted** | |
| Attribution window | 30 days signup → first qualifying race; then `EXPIRED`, never pays | live production env unset; `CODE social/referralRewards.js:20-22` fallback |
| Referrer velocity cap | **5 / rolling 24h**, **25 / rolling 30d** → the next referral becomes `FLAGGED`, with both sides held | live production env has no overrides; `CODE social/referralRewards.js:29-30` fallbacks are authoritative |
| Payout trigger | **not install** — the referee's first *qualifying completed race* (Apple 3.2.2) | `CODE grantReferralReward.js` |
| Qualifying race | `seedId == null` **and** ≥2 ACCEPTED participants with `rawSteps >= 2,000`; referee must have `placement != null` and `rawSteps >= 2,000` | `CODE grantReferralReward.js:188-226` |
| Idempotency | `@@unique(refereeSubHash, role)` on `referral_reward_grants` — one payout per **human provider identity per role, forever**, surviving delete + reinstall | `CODE grantReferralReward.js:29-46` |
| Attribution idempotency | `@@unique(Referral.refereeSubHash)` — one attribution per human, ever; written only on the account-create branch | `CODE recordReferral.js` |
| Self-referral | blocked (`referrer.id === newUser.id`) | same |
| Review accounts | excluded on both sides (`EXCLUDED`) | same |
| IP fallback | `link_opens.kind = 'referral'` only; tier 1 exact IP hash (48h, ≤10 opens, exactly 1 distinct code); tier 2 /24-/64 net prefix **OFF by default** | `CODE findLinkOpenReferralCode.js` |

### 11.2 Measured volume (all-time, 2026-08-25)

| Metric | Value |
|---|---|
| `referrals` rows, all time | **312** — 110 `REWARDED`, 195 `PENDING`, 7 `FLAGGED` |
| First referral | 2026-08 (the program has one month of data) |
| Attribution source | 217 `provision_body` (69 rewarded), 59 `ip_fallback_exact` (28 rewarded), 28 `redeem` (5 rewarded), 8 legacy null-source (all rewarded) |
| `referral_reward` coin txns, 30 complete days | 204 txns, **102,000 coins = 3,400 / day**; 145 recipient users |
| Completed-referral concentration, all time | 58 referrers; p50 **1**, p90 **4.3**, max **7**, total 110 |
| Completed referrals per referrer-day, trailing 30d | 75 referrer-days; p50 **1**, p90 **2.6**, max **5** |
| Reward latency, all rewarded referrals | p50 **74.0h**, p90 **189.1h**, max **268.1h** (n=110) |

### 11.2a Network-prefix fallback surface (tier 2 remains off)

Production retains no signup-IP hashes for organic users, so the incremental
number of signups tier 2 would attribute cannot be measured directly. Recent
anonymous link-open aggregates bound the matching surface:

The prefix only bridges address churn *within* one IPv4 /24 or one IPv6 /64.
Despite broader comments in the implementation, a normal IPv4 address and an
IPv6 address produce different prefix keys, and Wi-Fi and cellular usually do
too; tier 2 therefore does not generally bridge IPv4↔IPv6 or Wi-Fi↔cellular.

| Metric | Value | Source |
|---|---:|---|
| Referral opens / net-hash coverage in retained 90d window | 1,496 / 1,297 (86.7%); 493 distinct net prefixes | `DB link_opens` |
| Net prefixes with >1 code / >1 exact IP | 76 / 493 (15.4%) / 57 / 493 (11.6%) | same |
| Open-anchored rolling 48h net windows | 1,297 | same |
| Windows eligible under unique-code + ≤10-open rule | 1,041 (80.3%) | same |
| Ambiguous-code / hot windows | 235 (18.1%) / 34 (2.6%); categories may overlap | same |
| Eligible windows already spanning >1 exact IP | 71 (5.5%) | same |
| Latest 48h net-prefix snapshot | 66 / 72 prefixes eligible; 6 ambiguous; 0 hot; 2 eligible prefixes spanned >1 exact IP | same |

Hash coverage needs an operational check before any tier-2 launch: on
2026-08-20, all 40 referral opens observed by 03:54 UTC had null exact and net
hashes, versus full coverage on 2026-08-18. `CODE hmacClientIpHashes` deliberately
stores nulls when the active HMAC version/secret is missing or invalid, and a
null net hash can never match.

### 11.3 Affordability frame

At the current p50 recurring earn rate of **10.53 coins/active-day** (§0e), one
500-coin side is **47.5 days** of median play; the 1,000-coin pair is **95.0
days**. At p90 (75.67/day) it is 6.6 and 13.2 days. The cheapest active cosmetic
is 250 and the cheapest active store powerup is 75, so one paid referral gives
each side two cheapest cosmetics or 6.7 cheapest powerups.

### 11.4 Cap headroom vs the live economy

Against the trailing-30-complete-day **18,103.3 coins/day total positive
ledger** (of which referrals are 3,400/day):

| | Coins the guard still permits | × total daily supply |
|---|---|---|
| One referrer at the daily cap (5) | 2,500/day self + 2,500/day to referees | **0.28×** |
| One referrer at the monthly cap (25) | 12,500/30d self + 12,500 to referees | **4.6%** of a whole month's supply |

The cap now materially bounds one account's automatic minting, but it also
creates a hard scoring seam for any competition that equates a completed
referral with the durable paid grant: the 26th completion inside a rolling 30
days becomes `FLAGGED` and cannot count unless a documented review path clears
and grants it. The observed maximum is currently 7 completed referrals for one
referrer, below that seam.

### 11.5 Race share links do NOT carry referral attribution

`app.js:181-247`: `/r/:token` disambiguates on the reserved `BARA-` prefix.
A **referral** link logs `logLinkOpen("referral", code, req)`; a **race share**
link logs `logLinkOpen("race_share", token, req)` with the race token in `code`.
`findLinkOpenReferralCode` queries `where: { kind: "referral" }` only. The race
share text built in `FE lib/screens/race_detail_screen.dart:5807-5840` uses
`createRaceShareLink`, i.e. the race token.

**Therefore an install originating from a shared race link is attributed to
nobody and pays nobody**, unless the installer separately opens a `/r/BARA-…`
link or types the code in onboarding. Any copy promising coins for sharing a
*race* is false against current code.

### 11.6 Referral contest prize and scoring surface — verified 2026-08-25

The referral contest is a winner-take-all supplement to the ordinary referral
program. It does **not** replace the ordinary 500/500 payout in §11.1. A
qualifying referral therefore mints 1,000 ordinary coins across the pair, while
one eventual contest winner receives one additional configured coin mint.

| Fact | Value | Source |
|---|---:|---|
| Live published contest / prize | 1 contest; **5,000 coins**, cash minor = 0 | `DB giveaway_contests` |
| Live contest duration / entrants / awards so far | 42.0 days / 0 / 0 | `DB giveaway_contests × giveaway_entrants`; `DB coin_transactions reason='giveaway_winner'` |
| Draft contests | 2; both 5,000 coins and cash minor = 0 | `DB giveaway_contests` |
| Implemented global admin range / default | integer **1–25,000 coins** / **5,000 coins** | `SPEC docs/referral-contest-experience-requirements.md:§8.4`; frontend/backend validation |
| Winner rule | most verified referrals; then earliest time reaching the final count | `CODE src/modules/giveaways/queries/getContestStandings.js` |
| Contest point | ordinary durable referral fact in `QUALIFIED`/`REWARDED`, or reviewed-approved `FLAGGED`, inside the entrant's post-join window | same |
| Ordinary acquisition mint per contest point | **1,000 coins** (500 referrer + 500 referee) | `CODE src/modules/social/referralRewards.js`; §11.1 |
| Observed completed-referral distribution | 58 referrers / 110 rewards; p50 1, p90 4.3, max 7; histogram: 1→34, 2→13, 3→4, 4→1, 5→3, 6→2, 7→1 | `DB referrals status='REWARDED'` |
| Human-race qualification capacity | user-created race allows 2–100 participants; each qualifying referee needs ≥2,000 raw steps and at least two accepted ≥2,000-step finishers | `CODE validateRaceConfig.js`; `CODE grantReferralReward.js` |
| Qualifying participant-race rows, trailing 30 complete days | 730 across 247 users | `DB races × race_participants` (non-seeded, non-tournament, completed, qualifying thresholds) |

At the latest verified recurring-income distribution (§0e), 5,000 coins are
**474.8 median active-days** or **66.1 p90 active-days**. They buy 66.7 cheapest
active powerups (75 coins) or 20 cheapest active cosmetics (250 coins). Among
the 912 step-active users in the latest read-only balance refresh, current
balances were p50 181, p90 910.9, and max 9,866; the prize is therefore 27.6×
the median balance, 5.5× p90, and 50.7% of the maximum.

Trailing 30 complete days currently contain +18,103.3 source coins/day and
−7,190.6 sink coins/day (net +10,912.7). A 5,000-coin prize amortizes to
166.7/day over a 30-day contest (**0.92%** of gross sources) or 119.0/day over
the live 42-day window (**0.66%**). The implemented 25,000-coin global maximum
amortizes to 833.3/day over 30 days: **4.60%** of gross sources and **7.64%**
of current net issuance. An earlier, rejected 1,000,000-coin proposal would
have amortized to 33,333/day (**184%** of gross sources and **305%** of net
issuance); it is historical analysis only and was never the shipped global
limit. These figures exclude behavioral lift in ordinary referrals.
Each incremental completed referral caused by the contest adds another 1,000
coins; one extra per day is +5.5% to current gross issuance, while five extra
per day is +27.6%.

With symmetric entrants, expected contest-prize value is `5,000 / N`: 500
coins at N=10, 100 at N=50, 50 at N=100, and 10 at N=500. Using the 58
historically observed rewarded referrers as a participation frame gives 86.2
coins/entrant, although actual skill and acquisition reach make the payout
highly concentrated. At the ordinary automatic monthly threshold, 25 completed
referrals mint 25,000 coins across the pairs; adding the contest prize makes the
winner-associated issuance 30,000 coins.

The mechanical abuse seam is batching: five controlled referee identities can
qualify inside one five-player race with 10,000 aggregate reported raw steps,
remaining at the ordinary automatic daily threshold. That mints 5,000 ordinary
coins across the accounts and produces a contest score of five, already above
the historical p90 and near the observed maximum of seven. A single race can
technically carry as many as 100 qualifying referee accounts, but referrals
beyond the 5/day or 25/30-day threshold are `FLAGGED` and require manual review.
The candidate API reports same-race, rapid, shared-device/network, and
synchronized-step signals; current finalization only blocks on unresolved
outcome-changing `FLAGGED` facts, not on unresolved risk signals attached to
already `QUALIFIED`/`REWARDED` points. Sources: `CODE giveawayService.js`
candidate/finalize paths and `CODE getContestStandings.js`.

---

## 12. Race-payout rewarded-ad bonus — hard-capped at 100 (corrected implementation; deployment pending 2026-08-18)

One SSV-verified ad awards up to 100 additional coins from the authoritative
eligible race-ledger payout:

```
baseCoins  = sum(exact positive ledger rows for the results batch
                 where reason IN (race_prize_pool_payout, race_finish_reward))
remaining  = 100 - durable provider-identity grants in the trailing 24h
bonusCoins = min(baseCoins, 100, remaining)
```

`race_buy_in_payout`, refunds, tournament/referral coins and all other reasons
remain ineligible. Exact source `reason + refId`, persisted offer items,
provider-identity locks, a unique participant fence, SSV verification and
exactly-once claim receipts prevent client-submitted amounts or duplicate
claims. Source: `CODE races/models/racePayoutDouble.js`,
`races/commands/createRacePayoutDoubleOffer.js`,
`races/commands/claimRacePayoutDouble.js`.

The hard ceiling is non-configurable upward: malformed, absent, or greater
environment values resolve to 100. Offer reads and persistence apply the cap;
claim settlement recomputes the rolling allowance under the durable identity
lock and uses the capped amount for the coin ledger, consumed ad grant,
velocity grant, claim receipt, and repaired offer row. Thus an older persisted
offer above 100 cannot issue more than 100. `DB
app_settings.racePayoutDoubleRolloutPercent=100` controls cohort reach, not the
coin amount.

For the §4.5 fourth-place Daily, base 853 therefore offers at most +100. At
100% take-up the race can add no more than 100 per eligible claiming identity,
and each identity can receive no more than 100 total across the trailing 24h.

Prod before the correction: lifetime 53 claimed offers / 4,846 bonus coins,
median 87, p90 100, max 500; none had yet claimed after the brief uncapped
backend deploy.
Trailing 30 complete days: 4,305 `race_payout_ad_double` coins = 143.5/day (44
ledger rows, 31 users). Gross sources/sinks/net were 9,304.3 / 3,599.2 /
+5,705.1 coins/day. Source: `DB race_payout_double_offers`,
`DB coin_transactions` (aggregate-only, tz-naive SQL date math).

The original capped-model measurements below are retained only as historical
pre-launch evidence; their 500-cap counterfactual is not current behavior.

### 12.1 Historical capped-model input distribution (30 days to 2026-08-12; superseded)

Prod eligible ledger aggregate: 435 user/race awards, 51 users, **27,780 coins
= 926.0/day**.

| Ledger reason | n | Eligible coins/day | Proposed status |
|---|---:|---:|---|
| `race_prize_pool_payout` | 330 | 672.8 | eligible |
| `race_finish_reward` | 105 | 253.2 | eligible |
| `race_buy_in_payout` | 57 | 294.9 | **excluded transfer** |

`DB coin_transactions`, read-only. Treating every user/race award as a separate
immediate batch, an exact chronological rolling-window replay awarded 27,325
coins (**910.8/day**), clipping 455/27,780 (1.64%) across 9 constrained events;
3 events had zero remaining allowance. Simulation parameters: deterministic
event order `(created_at, race_id)`, one claim at each qualifying ledger event,
500 per batch and 500 across the preceding half-open 24-hour window. This is a
100%-claim upper proxy, not a take-rate forecast; real popup batching can only
reduce it.

### 12.2 Historical capped-model economy frame (superseded)

Thirty-day live ledger at verification: **+3,707.5 sources / −2,536.5 sinks /
+1,171.0 net coins/day** (`DB coin_transactions`). At 100% redemption under the
chronological upper proxy, the revised source adds at most **+910.8/day**:
sources become 4,618.3/day (+24.6%) and net becomes 2,081.8/day (+77.8%),
before induced spending. At the required initial 10% stable-provider rollout, a
uniform-value estimate is +91.1/day (+2.5% of sources); the configured
370/day alert bounds cohort-value concentration. Sixteen of the 51 eligible
payout users already used a rewarded-ad surface and held 18,381/27,780 (66.2%)
of eligible value before the rolling cap, so rollout membership by user is not
the same as rollout by economic exposure.

Among 94 users with at least seven active step-days, current positive coin
income/day was p10 0 / p50 9.52 / p90 124.11 / p99 293.21. Adding every
revised eligible rolling bonus would make it 0 / 10.02 / 150.22 / 356.08;
bonus alone was p10 0 / p50 0 / p90 43.54 / p99 91.60 per active day. Thus
median affordability barely moves (250-coin cosmetic: 26.3 → 25.0 active
days), while the upper tail receives most issuance.

### 12.3 Historical capped-model bounds (superseded)

- `CODE raceBuyIns.js:26-32`: legacy buy-in is at most 200 coins per accepted
  participant, but the pot can be transferred to a controlled winner. Prod
  still had two active and one pending legacy buy-in races at verification.
- `CODE prizePool.js`: a funded race pool is capped at 16,000; the proposed
  500 bonus therefore duplicates between 100% of a small payout and 3.125% of
  the theoretical maximum single payout.
- `CODE createRace.js` / `validateRaceConfig.js`: user races can be one day and
  normal creation has no global concurrent-race cap. The same walked steps can
  participate in multiple funded races.
- Offer preparation, claim and results-seen share a transactional durable
  provider-identity lock before the user/offer locks; a partial unique index
  permits at most one `PENDING` offer per user. Frozen allowance plus durable
  velocity grants make separate pages, concurrent calls and delete/recreate
  with the same Apple/Google subject share one hard 500-coin rolling limit and
  one persistent rollout cohort.
- `CODE deleteUserAccount.js:208-227` deletes the User coin ledger; the proposed
  offer also has a cascading User relation, while the velocity row and immutable
  claim receipt deliberately survive. The deletion transaction stamps the
  receipt before the cascade, allowing reconciliation to distinguish expected
  erasure from corruption. Account deletion joins the provider-identity → user
  lock order before selecting receipts, so a concurrent claim either does not
  award or commits a receipt that deletion observes and tombstones.
- The proposed five-minute reconciliation job has its own default-off
  `RACE_PAYOUT_DOUBLE_RECONCILE_ENABLED` flag. The release sequence now requires
  enabling it and observing a healthy scheduled run while rollout is still zero.

The unique offer-item participant fence prevents the same race payout from
being doubled twice and prevents a modified client from submitting subsets of
one current page. The provider lock, one-pending invariant and durable velocity
sum prevent those legitimate separate batches from exceeding 500 in any
rolling 24 hours, including across account recreation.

---

## 13. Consumable coin IAP — planning defaults, NOT LIVE (2026-08-18)

No IAP product, purchase ledger or IAP-sourced coin transaction exists in the
verified production model. The accepted planning defaults are product inputs,
not DB/code values:

| Pack | Base + displayed bonus | Total coins | US reference price | Coins / US$ |
|---|---:|---:|---:|---:|
| Small | 500 + 0 | 500 | $0.99 | 505.1 |
| Medium | 1,250 + 250 | 1,500 | $3.99 | 375.9 |
| Large | 2,500 + 500 | 3,000 | $7.99 | 375.5 |
| XL | 4,000 + 1,000 | 5,000 | $14.99 | 333.6 |

The client is planned to show Apple/Google localized store price metadata; the
US figures are reference prices only. At the current p50 recurring rate of 9
coins per active day, the packs equal 55.6 / 166.7 / 333.3 / 555.6 active days
of play; at p90 75.4/day, 6.6 / 19.9 / 39.8 / 66.3 days. The packs equal 20 /
60 / 120 / 200 direct coin-ad grants, or 6.7 / 20 / 40 / 66.7 days at the live
three-grant (75-coin) daily cap.

The displayed bonuses are 20%, 20% and 25% of each larger pack's stated base,
but the base is not tied to the small-pack exchange rate. At US reference
prices, four small packs cost $3.96 and provide 2,000 coins (500 more than the
$3.99 medium); eight cost $7.92 and provide 4,000 (1,000 more than the $7.99
large); fifteen cost $14.85 and provide 7,500 (2,500 more than the $14.99 XL).

Until this source ships, economy projections must represent paid issuance as:

`paid coins/day = 500 × small grants + 1,500 × medium grants + 3,000 × large grants + 5,000 × XL grants − refunded coins`

and must not count store checkout starts or client purchase callbacks as
issuance.

## 14. Funded-exposure cap removal — verified inputs and safeguards (2026-08-23)

This is a factual model for the proposal in
`stepv2-backend/docs/remove-funded-exposure-cap-requirements.md`; the release
decision remains in the analyst report.

### 14.1 Live rules and source-of-truth reconciliation

| Item | Live value | Source |
|---|---:|---|
| Existing aggregate funded-exposure guard | 600 coins | `CODE src/modules/races/services/fundedExposure.js:8,904-912` |
| Existing daily exposure guard | 80 coins/day | `CODE src/modules/races/services/fundedExposure.js:9,904-912` |
| New funded race coin unit / pool ceiling | 10 / 8,000 coins | `CODE src/modules/races/services/fundedExposure.js:12-14`; stamped v2 rows |
| New funded tournament champion ceiling | 500 coins | `CODE src/modules/races/services/fundedExposure.js:16`; stamped v2 rows |
| Missing-env fallback unit / race ceiling | 20 / 16,000 coins | `CODE src/shared/economy/prizePool.js:9-24`; `.env.example:21-22` |
| Box interval | 2,000 raw walked steps per powerup-enabled race | `CODE src/modules/races/constants/powerupInterval.js:1-5`, `powerups/boxSteps.js:3-27` |

The exposure service is shared by user-created races, user tournaments, and
seeded allocation paths. Removing its `enforceLimits` branch globally would
change more than the proposal's stated scope; caller-level scoping is required.
The 30-day production sample contained 215 v1 user-funded race rows and 48 v2
rows; completed user-funded races in the review window had a p50 pool of 240,
p90 744, and maximum 5,920 coins (`DB races`, 98 completed rows).

### 14.2 Production baseline for the proposed change

Trailing 30 complete calendar days, 2026-07-24 through 2026-08-22; all date
arithmetic used tz-naive SQL dates and all queries were session read-only.

| Metric | Value | Source |
|---|---:|---|
| Step-active player steps/day | p10 1,235 · **p50 5,774** · p90 13,572 | `DB steps` (7,029 user-days) |
| Recurring positive coins/active day | p10 0 · **p50 10.53** · p90 75.67 | `DB steps × coin_transactions` (829 users) |
| Daily positive / negative / net ledger | +14,807.7 / −6,079.7 / **+8,728.0** | `DB coin_transactions` |
| User-funded race payout mint | **34,005 total / 1,133.5/day** | `DB coin_transactions` joined to `DB races` (97 payout races) |
| Seeded funded race payout mint | 113,029 total / 3,767.6/day | same join (215 payout races) |
| User-funded rolled boxes | **12,870 / 429.0/day** | `DB race_powerups` joined to non-seeded funded races |
| User-funded box concentration | top 10% of users held **70.7%** of 15,740 box rows | `DB races × race_participants × race_powerups` (453 users) |
| User-funded participant-race box volume | 12.86 boxes/participant-race | same join; 15,928 participant-races |
| Current live user-funded exposure | p50 120 · p90 320 · max 1,380 coins | `DB race_participants`, 372 users; 18 exceed 600 and 7 exceed 80/day |

The race-step duplication check found 48.15M raw steps across user-funded race
participant records versus 31.18M unique step rows for the same 30-day user
cohort (1.54x aggregate; race and unique-step windows are not perfectly
identical because a race can span dates). This is evidence of replicated
walking input, not additional physical activity.

### 14.3 EV conversion for one additional funded membership

For a new v2 race without a team multiplier:

`pool = participants × durationPoints(days) × 10`

Thus a symmetric participant's expected coin credit is 10 coins for a 1-day
race, 20 for 2–3 days, 40 for 4–7 days, and 80 for 8–30 days. At the live
median step rate, one additional active race also creates
`5,774 / 2,000 = 2.89` boxes/day; p10 and p90 players create 0.62 and 6.79.
For a four-player, two-day funded tournament the champion pool is 80 coins
(20-coin symmetric EV); a full 16-player, two-day bracket reaches the 500-coin
cap, with 31.25-coin symmetric EV and 500 coins to a controlled champion.
Tournament settlement uses the same formula at
`CODE src/modules/tournaments/commands/advanceTournament.js:234-255`.

### 14.4 Required monitoring/safeguard inputs before cap removal

The following are the minimum facts/controls to preserve in any implementation:

- Scope the bypass to non-seeded user-created funded races and non-seeded funded
  tournaments. Keep seeded allocation and legacy buy-in paths on their current
  admission/settlement rules; do not delete exposure stamps or locking.
- Replace unlimited live membership with an atomic per-user funded-membership
  ceiling or an equivalent per-user funded-payout velocity budget. A ceiling of
  no more than the existing **5 live quick memberships** is the upper bound
  supported by current anti-duplication policy (`CODE
  src/modules/races/services/nextRacePolicy.js:7-13`); the current live p90 is
  3 user-funded memberships. “Unlimited” is not a safe default.
- Require a minimum honest raw-step contribution before a funded payout is
  eligible (recommended: **2,000 raw steps per entrant per race**), or retain
  the existing exposure cap. Otherwise a pair of zero-step accounts can create
  a 1-day, 2-player, winner-takes-all race that mints 20 coins to one account.
- Monitor daily user-funded payout coins, user-funded box rows, per-user live
  funded memberships, per-user funded payout p95/p99, zero-step payout share,
  repeated participant-pair share, top-decile box share, and raw-race-steps /
  unique-steps. Alert at 2x the verified baselines: 2,267 user-funded payout
  coins/day, 858 user-funded rolled boxes/day, or top-decile box share above
  80%; page immediately on any zero-step winner or a user above 5 live funded
  memberships.
- Preserve idempotent payout references and add a daily aggregate reconciliation
  of stamped pool, awarded pool, and ledger mint. Any mismatch must block the
  next deployment or trigger rollback; no production data update is part of
  this change.
- Owner and rollback: the backend on-call owns the daily alerts and may reload
  the previous commit; the game analyst owns the seven-day post-deploy economy
  review. Any threshold breach above, any zero-step winner, any user above the
  membership ceiling, or any stamped-pool/ledger mismatch is a code-only
  rollback criterion. No runtime flag or production data edit is required.

These are safeguards for the proposed removal, not new live configuration.

## 15. Daily local-time 2x Race Steps event — verified 2026-08-27

| Fact | Live value | Source |
|---|---:|---|
| Frequency / duration / multiplier | once per logical event day / 30 minutes / 2x race steps | `CODE src/modules/steps/globalStepEvent.js`; `DB global_step_events` |
| **Materialized v1 local start draws** | event days through 2026-08-31 remain one uniformly random minute in `[480,1320)`, i.e. 08:00–21:59 local; **1/840 per minute, 1/14 per start hour** | `DB global_step_events.local_start_minute`, `schedule_policy_version=1`; immutable after creation |
| Timezone rule | same drawn wall-clock minute in each user's snapshotted `global_event_timezone`; missing values fall back to `America/New_York` | `CODE globalStepEvent.js`, `globalStepEventEntitlement.js` |
| Live timezone coverage | 944 / 1,099 non-review accounts have a stored event timezone; 155 use fallback; 62 stored zones | `DB users`, aggregate-only read-only query |
| Completed local events observed | 6 event days, 2026-08-21 through 2026-08-26; 780–978 non-review entitlements/day | `DB global_step_events × global_step_event_entitlements` |
| Users with positive overlapping raw steps | 44.0%–50.4% per event; event-level mean 140.7–188.7 raw steps per entitlement | `DB entitlements × step_samples`, overlap-prorated, n=5,195 entitlements |

The event changes race score only. It does not advance mystery boxes, raw-step
milestones, or direct coin faucets, so changing only the start-time distribution
has approximately zero direct coin-source/sink delta. It can redistribute race
placement and changes the situational value of timed multipliers. Six live days
are not enough to infer a causal hour-of-day participation curve.

### 15.1 Weighted-v2 policy — deployed 2026-08-27

The permanent v2 policy keeps the live frequency, duration,
multiplier, eligible support, stable-timezone snapshot, and immutable persisted
draw. It changes only the probability assigned to each local start minute.
It was deployed at backend commit `d553d2b` on 2026-08-27. Event days through
2026-08-31 had already been persisted under v1 and remain unchanged; the first
weighted-v2 event day is 2026-09-01. Source: `SPEC
docs/weighted-local-2x-event-schedule-requirements.md`; production migration,
process census, health, and persisted policy versions verified 2026-08-27.

| Local start window | Probability | Minutes | Tickets/minute | Band tickets | Probability/hour |
|---|---:|---:|---:|---:|---:|
| 08:00–11:59 | 15% | 240 | 45 | 10,800 | 3.75% |
| 12:00–14:59 | 18% | 180 | 72 | 12,960 | 6.00% |
| 15:00–16:59 | 18% | 120 | 108 | 12,960 | 9.00% |
| 17:00–18:59 | 21% | 120 | 126 | 15,120 | 10.50% |
| 19:00–20:59 | 21% | 120 | 126 | 15,120 | 10.50% |
| 21:00–21:59 | 7% | 60 | 84 | 5,040 | 7.00% |
| **Total** | **100%** | **840** | — | **72,000** | — |

The integer ticket construction is exact: all 840 minutes remain reachable,
every minute within a band has equal probability, and one cryptographic ticket
in `[0,72000)` determines the persisted minute. The expected local start moves
from **14:59:30 under uniform v1 to 16:17:12 under weighted v2**. V2 assigns
33% before 15:00, 67% from 15:00 through 21:59, and 42% from 17:00 through
20:59.

**Historical activity-profile EV estimate.** A read-only prod calculation over
1,031 non-review users who have held a local-event entitlement and 31 complete
days of five-minute `step_samples` bucketed in each user's stable/fallback event
timezone estimates the following expected raw-step overlap for one 30-minute
event. This is an observational time-of-day estimate, not a causal forecast;
it assumes the historical activity profile continues and does not imply that
all overlapping raw steps score in a race.

| Per-entitled-user expected event-window raw steps | Uniform v1 | Weighted v2 | Change |
|---|---:|---:|---:|
| Mean | 57.7 | 58.8 | **+2.0%** |
| p50 | 37.5 | 37.7 | +0.3% |
| p90 | 136.2 | 136.7 | +0.4% |
| p99 | 360.7 | 376.6 | +4.4% |

Direct coin-source/sink EV remains **zero**: event timing changes race score,
not raw steps, box progress, milestones, payout-pool size, or direct coin
issuance. A zero-step player still receives zero value. For a walking player,
event score value scales with the signed timed-effect multiplier already active
in that race, so the policy can redistribute placement without changing total
prize funding.

**Timed-effect predictability bound.** If a player blindly activates an effect
before the event is revealed, the maximum chance that the event starts during
the effect is 10.5% / 21% / 31.5% / 42% for a 1h / 2h / 3h / 4h effect under
v2, versus 7.14% / 14.29% / 21.43% / 28.57% under uniform v1. The strongest
four-hour window is 17:00–21:00 and still misses 58% of event starts. Reacting
after the start notification can guarantee partial overlap, but that behavior
already exists under v1. Future draws remain secret; stable timezone snapshots,
one persisted draw, the event-day advisory lock, and immutable entitlements
prevent timezone chasing, duplicate windows, and redraw farming.

## 16. Active-competition and Hitchhike-v3 review inputs — verified 2026-08-28

This section records the factual inputs used to review
`docs/feature-batch-2026-08-28-requirements.md`. Release A and Hitchhike
Release B are live as of 2026-08-28. The checked production connection is a snapshot whose
latest ledger, daily-step, and sample dates are 2026-08-19, 2026-08-23, and
2026-08-22 respectively.

### 16.1 Proposed active-competition limit

Before Release A, the backend admitted at most five newly accepted memberships
in user-created funded races/tournaments. The live replacement setting defaults to 20,
allows administrators to save 1–20, and counts all accepted, non-terminal
memberships in PENDING/ACTIVE user-created races and tournaments while excluding
seeded competitions and tournament matchup races.

At the verification snapshot, that proposed count covered **589 memberships /
322 non-review users**: p50 1, p90 3.9, max 15. Twenty-two users were above five
because existing memberships are never ejected; zero were above 20. All 589
memberships were app-funded, and **518 / 589 (87.9%)** had powerups enabled.
Source: `DB races × race_participants × tournaments ×
tournament_participants × users`, aggregate-only read-only query.

For a one-day, non-team funded race, raw symmetric payout EV is 10 coins per
entrant. A two-player winner-takes-all field mints 20 coins when both entrants
record positive eligible score. The same walked steps can qualify in every
concurrent race. At the proposed numeric bounds:

| Concurrent one-day funded memberships | Raw symmetric payout EV/player/day | Controlled two-account WTA payoff to one winner/day | Boxes/day at p10 / p50 / p90 steps |
|---:|---:|---:|---:|
| 5 (live prospective guard) | 50 | 100 | 4.42 / 14.72 / 28.52 |
| 20 (`SPEC` default and validation maximum) | 200 | 400 | 17.66 / 58.86 / 114.08 |

The box calculation is `memberships × daily raw steps / 2,000`, using the
latest feature-batch p10/p50/p90 per-user daily rates 1,766 / 5,886 / 11,408
from section 0f and assuming every membership is powerup-enabled. Boxes do not
directly mint race-prize coins; historically each extra box correlated with
1.49 coins of upgrade sink and about 0.17 coins of discard issuance, with strong
leader concentration and possible store-purchase cannibalization (sections 2b,
3.3, and 3.5). Payout rounding v1 can raise realised awards above the raw values
in the table.

### 16.2 Deferred creator removal/reinvite

Participant removal and reinvite changes are explicitly outside this batch.
The live behavior remains unchanged and any later proposal requires its own
payout, griefing, effect-cleanup, and repeated-reentry economy review. Source:
`SPEC docs/feature-batch-2026-08-28-requirements.md` non-goals.

### 16.3 Hitchhike v3 value boundary

The authoritative production Hitchhike catalog row remains **150 coins,
`active=false`, `test_only=false`**; retained history has one effect row from
one caster. Thus the v3 scoring correction has zero current catalog purchase
volume unless availability changes separately. Source: `DB
powerup_shop_items × race_active_effects`.

Positive sampled user-hours over 2026-07-24 through 2026-08-22 were p10 19,
p50 234, p90 1,460, p99 4,288, max 12,568, mean 551.59 (n=62,390). At a 1:1
copy and 150-coin price those are 0.13 / 1.56 / 9.73 / 28.59 / 83.79 copied
steps per coin before target selection or score multipliers. Source: `DB
step_samples × users`, UTC-hour aggregate, non-review users.

The live v1/v2 scorer excludes the in-progress hour. For a cast minute uniformly
distributed over 0–59 and constant walking rate, its final closed-hour window
contains an average **50.83%** of the promised 60 minutes; a full-window v3
therefore raises copied-step EV by about **96.7%** relative to that timing path.
Existing v1/v2 rows retain that interpretation unchanged throughout the rollout.
Release A added v3 read/support paths without creating v3 effects. After all
production workers ran A and the owner separately authorized the cutover,
Release B began stamping v3 on new casts at backend commit `a16670a`. Existing
v1/v2 effects remain on their immutable versioned paths; no runtime feature
flag is used. Source: `SPEC docs/feature-batch-2026-08-28-requirements.md`
rollout and the deployed backend release tags.

V3 changes placement only: copied steps do not advance boxes, milestones, or
prize-pool size, and the target loses nothing. If Hitchhike is later made
purchasable, each store-origin cast preserves the 150-coin purchase sink while
redistributing the already-funded race payout by placement.

---

*Last full verification pass: 2026-08-08 (prod SELECT-only, aggregates only).
§0d, §1d, §2d, §3.1a, §3.4d, §6.1 and §13 verified/added 2026-08-18 (prod
SELECT-only aggregates + accepted planning inputs; IAP is explicitly not live).
§12 verified/added 2026-08-12 (prod SELECT-only aggregates + current code/spec).
§0b, §1b, §2b, §4.1, §7 (box-volume order statistic) and §11 verified/added
2026-08-11 (prod SELECT-only, aggregates only).
§3.2 (config v4), §3.5, §3.6, §3.7 and §10 verified 2026-08-10 (prod
SELECT-only, aggregates only).
§3.2 / §3.4 / §3.4b / §3.4c / §3.5 / §3.6 / §9 verified and added 2026-08-09
(prod SELECT-only, aggregates only). §8 Option H and §9 are analysis only —
nothing in either has been applied. §14 verified/added 2026-08-23 (prod
SELECT-only aggregates + current backend code; no production data changed).
§15/§15.1 verified/added 2026-08-27 (prod SELECT-only aggregates + current
backend code + weighted-v2 spec); weighted-v2 deployed and post-deploy verified
2026-08-27 at backend commit `d553d2b`, with v1 rows preserved through
2026-08-31 and the first v2 event day on 2026-09-01. §16 verified/added
2026-08-28 (prod SELECT-only aggregates + current backend code + feature-batch
spec); Release A deployed at `51ab388` and Hitchhike Release B at `a16670a`.*

*Runner's High stacking and the standardized 15-minute upgrade-duration ladder
in §3.4c re-verified 2026-08-28 from current backend code
(`effectMultiplier.js`, `powerupUpgrades.js`) plus a prod SELECT-only aggregate
of the active team race used for the carousel visual check; no production data
was changed by this verification.*
