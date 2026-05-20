# The Hunt — Tuning Spreadsheet v1

*Last updated: 2026-05-20 · Companion to [the-hunt.md](./the-hunt.md)*

All numbers were derived empirically via simulation (`scripts/simulate_hunt.py`), not from analytic percentile math. The simulator iteratively adjusts each tier's thresholds until the actual attrition curve matches design intent.

---

## Design intent (what we're tuning toward)

A Hunt should:
- Eliminate ~5 capybaras at Feeding 1 (gentle intro, ~17%)
- Accelerate elimination through the match
- Leave ~3–5 capybaras alive going into Last Stand
- Produce 1–2 clear winners
- Feel **fair within tier**: a tier-appropriate walker should expect to survive several feedings
- Feel **harder per tier** without being unwinnable at Diamond

**Target attrition curve:**

| Event | Alive | Eliminated | % of remaining cut |
|---|---|---|---|
| Hunt starts | 30 | — | — |
| Feeding 1 (T+1.5h) | 25 | 5 | 17% |
| Feeding 2 (T+3h) | 18 | 7 | 28% |
| Feeding 3 (T+4.5h) | 10 | 8 | 44% |
| Feeding 4 (T+5.5h) | 4 | 6 | 60% |
| Final (T+6h) | 1 | 3 | 75% |

---

## Step 1 — Player step rate assumptions

How many steps a player walks during a 6-hour hunt window while *engaged*.

| Tier | Pace (steps/hr) | 6h total |
|---|---|---|
| Bronze | 1,100 | 6,600 |
| Silver | 1,500 | 9,000 |
| Gold | 2,000 | 12,000 |
| Platinum | 2,600 | 15,600 |
| Diamond | 3,300 | 19,800 |

Reference: avg US adult ~3,500 steps/day; engaged walker 8–10k/day; fit person 12–15k/day. A 6-hour active window captures the bulk of daily steps.

---

## Step 2 — Variance assumptions

These are the levers that decide *how spread out* the outcomes are. Wrong variance = wrong thresholds.

| Variance | Value | Why |
|---|---|---|
| Per-match player variance | **±35%** of skill | Real walkers have ~30–50% day-to-day CV; 35% is realistic mid-range |
| Bot capybara variance | ±25% of tier pace | Tight enough to feel like a real player, varied enough to be unpredictable |
| CPU wolf variance | ±25% of CPU rate | Same reason |
| Player wolf pace | 80% of capybara pace | Converted players still walk, motivated but not as hard as when defending |

**Why the variance matters:** with low variance (e.g., 15%), almost everyone walks close to the mean and survives. With realistic variance (35%), there's a meaningful tail of slow walkers who get caught, and a tail of overachievers who survive. The thresholds were tuned *for the 35% variance assumption*. If real-world data shows different variance, retune.

---

## Step 3 — Tuning methodology

Rather than deriving thresholds analytically (which assumes a model of player behavior that may not match reality), we use **iterative simulation**:

```
For each tier:
  Build a synthetic lobby of skill-matched players
  Repeat until converged:
    Simulate 300 matches at current thresholds
    Measure actual attrition at each feeding
    Adjust threshold up if too few eliminated, down if too many
    (proportional, dampened to prevent oscillation)
  Round final thresholds to nearest 500
```

The advantage: this naturally accounts for Pack Pressure compounding, conversion dynamics, and any second-order effects that analytic math would miss.

The output is the master table below.

---

## Master tuning table (v1, simulation-tuned)

| Tier | F1 | F2 | F3 | F4 | Final | Pack ×factor | CPU rate/hr |
|---|---|---|---|---|---|---|---|
| Bronze   | 1,000 | 3,000 | 5,500  | 8,500  | 10,500 | 0.15 | 500   |
| Silver   | 1,500 | 4,000 | 7,500  | 11,500 | 14,500 | 0.20 | 750   |
| Gold     | 2,000 | 5,000 | 9,500  | 15,000 | 19,000 | 0.30 | 1,000 |
| Platinum | 2,000 | 6,500 | 12,500 | 19,500 | 25,000 | 0.40 | 1,300 |
| Diamond  | 2,500 | 7,500 | 15,500 | 24,500 | 31,500 | 0.50 | 1,500 |

**Note**: Gold F1 = Platinum F1 (both 2,000). This is intentional and emerges from the tuning. Plat players walk faster, so a lower absolute threshold still eliminates the target % of them. Don't enforce monotonicity across tiers — let the tuner decide.

**Universal rules:**
- Pack Pressure cap: +50% of base threshold
- Player wolf steps count 1:1 toward Pack Pressure average
- No marks or powerups in v1
- Lobby size: 30 (with bots backfilling unfilled human slots)

---

## Step 4 — Pack Pressure tuning (unchanged from v0)

Formula:
```
pack_pressure = avg_wolf_steps_since_last_feeding × tier_factor
                                          (capped at +50% of base)
```

**Tier factors** scale the pack's collective impact:

| Tier | Factor | Realized pack pressure (sim avg) |
|---|---|---|
| Bronze | 0.15 | +100 to +130 per feeding |
| Silver | 0.20 | +180 to +275 |
| Gold | 0.30 | +200 to +580 |
| Platinum | 0.40 | +325 to +965 |
| Diamond | 0.50 | +475 to +1,420 |

Higher tiers feel the pack more — Diamond's pack can add up to 1,400 steps per feeding (capped at +50% of base).

---

## Step 5 — CPU wolf step rates

CPU wolves are the always-on starter threat. Tuned slightly below converted player wolves so human conversions feel meaningfully strengthening.

| Tier | CPU rate (steps/hr) | Per 90-min window |
|---|---|---|
| Bronze | 500 | 750 |
| Silver | 750 | 1,125 |
| Gold | 1,000 | 1,500 |
| Platinum | 1,300 | 1,950 |
| Diamond | 1,500 | 2,250 |

Plus ±25% per-wolf variance.

---

## Step 6 — Ranked system tuning

| Lever | v1 value | Notes |
|---|---|---|
| Promote rate | **Top 10%** per tier | Lowered from 20% to reduce yo-yo |
| Relegate rate | **Bottom 10%** per tier | Same |
| Season length | 1 month | UTC reset |
| Skip-decay | None | Stagnate, don't lose |
| Placement matches | First 5 hunts | Algorithm finds your starting tier |

---

## HP awards (ranked points per match)

| Achievement | HP |
|---|---|
| 🏆 Last Capybara Standing | +100 |
| 🥈 Top 3 capybaras (by final step count) | +50 |
| 🐺 Alpha Wolf (most steps as wolf) | +50 |
| Survive past Feeding 2 | +20 |
| Survive past Feeding 3 | +15 |
| Hunt completed (participation) | +5 |

---

## Validation — simulation results

**Setup**: 1000 players (skill ~ N(2000, 800)), 5 seasons × 20 matches/player = 100 matches/player on average.

### Final tier distribution (after 5 seasons)

| Tier | Players | % |
|---|---|---|
| Bronze | 215 | 21.5% |
| Silver | 218 | 21.8% |
| Gold | 231 | 23.1% |
| Platinum | 191 | 19.1% |
| Diamond | 145 | 14.5% |

Healthy curve — Diamond is the smallest as intended; nobody bottlenecks at one tier.

### Attrition curve realized (avg per tier)

```
Target:     30 → 25 → 18 → 10 → 4 → 1
Bronze:     30 → 18 → 11 →  7 → 3 → 1.4
Silver:     30 → 24 → 19 → 13 → 6 → 2.8
Gold:       30 → 22 → 20 → 13 → 6 → 2.6
Platinum:   30 → 23 → 18 → 11 → 4 → 1.5
Diamond:    30 → 21 → 18 → 10 → 4 → 1.6
```

Hitting design intent: 1–3 winners per match across all tiers. Bronze finals are tightest because top Bronze players + outlier bots clear the threshold.

### Win rate by skill quintile

Within a tier, matches are skill-matched, so headline win rates compress to ~1–4%. Top quintile (Q5) wins **3× more often than bottom quintile (Q1)**, confirming skill matters.

### Tier mobility

Sample trajectories over 5 seasons:
```
Skill 858  → Bronze → Bronze → Bronze → Bronze → Bronze (stable, accurate)
Skill 1535 → Silver → Silver → Silver → Silver → Silver (stable, accurate)
Skill 1745 → Gold → Silver → Silver → Silver → Silver (corrected upward error)
Skill 2907 → Platinum → Platinum → Platinum → Platinum → Platinum (stable)
```

Mobility is now sane — no players yo-yoing across the whole ladder. Most players land in their "true" tier within 1–2 seasons.

---

## Open tuning levers

If playtesting shows imbalance, here's what to adjust:

| Symptom | Lever |
|---|---|
| Too many survive Final | Raise Final threshold by 10–15% |
| Too few survive Final (0 winners) | Lower Final threshold by 5–10% |
| Bronze too easy / Diamond too hard | Adjust TIER_PACE values |
| Pack Pressure feels invisible | Raise tier factors (e.g., Gold 0.30 → 0.40) |
| Wolves feel underpowered late | Increase WOLF_PACE_MULT (0.80 → 0.90) |
| Early eliminations too punishing | Lower F1 threshold by 20% across all tiers |
| Yo-yo tier movement | Drop promote/relegate further (10% → 5%) |

Re-run `scripts/simulate_hunt.py` after any change. The tuner will reconverge in ~30 seconds.

---

## Validation plan before launch

1. ✅ **Simulate** — current state (this doc reflects sim output)
2. **Real-data check** — pull step distributions from existing race participants to validate Step 1 (player pace assumptions) and Step 2 (variance assumptions)
3. **Internal playtest** — staff hunts at each tier to gut-check feel
4. **Closed beta** — 100 invited users for 2 weeks, watch retention + completion rate
5. **Public launch** — start with conservative numbers; tune up difficulty over time

---

*End of tuning doc.*
