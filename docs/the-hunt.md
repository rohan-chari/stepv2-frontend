# The Hunt — Design Doc v1

*Last updated: 2026-05-20 · Status: Draft*

---

## TL;DR

**The Hunt** is a new ranked competitive mode where 30 capybaras try to survive a 6-hour hunt against a growing wolf pack. Players who get eliminated **become wolves** and hunt the remaining survivors. Matches are queue-based with hidden bot backfill, ranked across 5 tiers (Bronze→Diamond), with monthly seasons.

The hook nobody else has: **getting eliminated isn't punishment, it's a role-swap.** Engagement stays high all 6 hours regardless of how early you "lose."

---

## Goals

- Add a marquee competitive mode that drives daily ranked engagement
- Reuse existing race infrastructure (steps, powerups, chat, feed) — minimize new systems
- Give every player a reason to walk *and stay engaged* even after being "eliminated"
- Create a long-term progression ladder (tiers, seasons) on top of single-match drama

## Non-Goals (v1)

- Buy-in or coin prize pools
- Player-chosen wolf role
- Special events (Wolf Moon, Grand Hunt, etc.)
- Android support
- Friend-priority matchmaking
- Coin-economy integration beyond participation

---

## Core Loop

1. Player taps **Matchmake** in the Hunt tab
2. Backend queues player against others of similar rank
3. Within ~5 min, lobby is built (real players + hidden bots to fill)
4. Push notification: *"Your Hunt starts in 5 minutes"*
5. Match begins: **30 capybaras + 2 CPU wolves**
6. Over 6 hours, **4 Feedings + a Last Stand** thin the herd
7. At each feeding, capybaras below their personal threshold are eaten → become wolves
8. Wolves walk to apply pack pressure; can Mark Prey to target individuals
9. Last capybara standing wins; top wolf earns Alpha title
10. Rank points distributed → tier movement at month end

---

## Player Flow

### Queue → Match

- Single button: **"Find Hunt"**
- Player sees: estimated wait, current queue size, their tier
- Matchmaker searches tier ± 0 for up to 5 minutes
- If lobby not full at 5 min: backfill with bots (hidden — players assume they're real)
- Lobby locked → players get push: *"Hunt starting in 5 min. Get ready."*
- Pre-hunt screen: roster, CPU wolves named ("🐺 Fang and Ash have caught your scent")
- **No late joins** — once the match starts, the door is closed

### Active Hunt — Capybara View

The Hunt tab is dominated by **the threat meter**:

```
🐾 STATUS: SAFE
Next Feeding in 1h 23m

Base threshold:       8,000 steps
+ Pack Pressure:     +1,350 (rising)
────────────────────────
Your threshold:       9,350
Your steps:           7,200
Gap:                 -2,150

[ Active Effects ] [ Kill Feed ] [ Chat ]
```

Color-coded: green/yellow/red urgency. Updates live as wolves walk.

### Active Hunt — Wolf View

After conversion, UI shifts to red palette. Different layout:

```
🐺 THE HUNT IS ON
Pack: 12 wolves · Capybaras: 18

Today's Prey:
  Sarah    ████████░░  12,400
  Marcus   ██████░░░░   9,200
  Alex     █████░░░░░   7,800
  ...

[ Pack Chat ] [ Kill Feed ]
```

### Conversion Moment

When eaten:
1. Screen darkens
2. Comic-panel animation: capybara caught by wolves
3. Cut: full moon, transformation
4. UI flips to red
5. Banner: **"YOU HAVE JOINED THE HUNT"**
6. Player auto-dropped into Pack Chat
7. Wolf-mode tab unlocks

### Results

- Hunt over screen with placement, rank points earned, season progress
- Shareable card (your placement / kills / longest streak)
- Replay-style scrollable timeline of who fell when

---

## Mechanics

### Feeding Schedule (6h hunt)

| Time | Event | Base threshold (Gold) |
|---|---|---|
| T+0:00 | Hunt begins (2 CPU wolves) | — |
| T+1:30 | Feeding 1 | 2,000 |
| T+3:00 | Feeding 2 | 5,000 |
| T+4:30 | Feeding 3 | 9,500 |
| T+5:30 | Last Stand begins | — |
| T+6:00 | Final Feeding | 19,000 |

Thresholds scale by tier (see Ranked System).

### Pack Pressure

The collective wolf mechanic.

```
pack_pressure = average_wolf_steps_since_last_feeding × tier_factor
                                    (capped at +50% of base_threshold)
```

- Uses **average**, not total — pack size doesn't break the math
- **Capped** so capybaras always have a chance
- **Visible in real time** to all players — no hidden math
- Updates as wolves walk

### Personal Threshold Formula

```
your_threshold = base + pack_pressure
```

If `your_steps < your_threshold` at feeding → eaten → become wolf.

**v1 has no individual targeting mechanic.** Wolves contribute exclusively through Pack Pressure (the collective). Mark Prey is deferred to v2 as a layered-on strategic tool.

### Step Sync at Feedings

To handle HealthKit sync lag fairly:

1. **T-10 min before feeding**: silent push to all participants triggers HealthKit sync
2. **At T-0** (announced feeding time): step count "freezes" — no more steps accepted for this feeding
3. **5-min grace window**: late syncs (samples timestamped before T-0) still accepted
4. **At T+5 min**: feeding evaluates against final synced counts → eliminations happen

Feedings *announce* at the scheduled time; *resolve* 5 min later. Trades 5 minutes of suspense for fairness.

If a player's phone is offline: last known step count is used. No appeals.

### CPU Wolves — Starter Pack & Bots

**Starter wolves** (every hunt begins with these):
- 2 wolves at all tiers in v1
- Named cast: **Fang, Ash, Whisper, Boulder, Saber**
- Each has flavor (kill feed lines, mark heuristics) but mechanically similar
- Generate synthetic step samples on a schedule (tuned per tier)
- Mark heuristic: target the capybara closest to their threshold

**Bot backfill capybaras** (when not enough humans queue):
- Anonymous (named like other players)
- Walk at **randomized rates scaled to the lobby's tier** (each bot gets its own habits — some "morning walkers," some "evening grinders," etc.)
- Can be eaten and "convert" to bot wolves
- Undisclosed to players — they should feel like a full lobby

---

## Ranked System

### Tiers

5 tiers: **Bronze → Silver → Gold → Platinum → Diamond**

Each tier has its own:
- Base thresholds (Bronze easiest, Diamond hardest)
- Pack Pressure tuning factor
- Number of starter CPU wolves (consider scaling up at higher tiers post-v1)
- Tier badge cosmetic

| Tier | Base Feeding 1 | Base Final | Pack tuning | Vibe |
|---|---|---|---|---|
| Bronze | 1,000 | 10,500 | 0.15 | Chill intro |
| Silver | 1,500 | 14,500 | 0.20 | Real but forgiving |
| Gold | 2,000 | 19,000 | 0.30 | The grind starts |
| Platinum | 2,000 | 25,000 | 0.40 | Sweaty |
| Diamond | 2,500 | 31,500 | 0.50 | Brutal |

*Full per-feeding numbers in [the-hunt-tuning.md](./the-hunt-tuning.md). Tuned via simulation against the target attrition curve.*

### Hunt Points (HP)

Earned per match, regardless of outcome:

| Achievement | HP |
|---|---|
| 🏆 Last Capybara Standing | +100 |
| 🥈 Top 3 capybaras | +50 |
| 🐺 Alpha Wolf (most pack steps as wolf) | +50 |
| 🩸 First Blood (first wolf to mark a successful kill) | +10 |
| Survive past Feeding 2 | +20 |
| Survive past Feeding 3 | +15 |
| Hunt completed | +5 |

### Seasons

- **Monthly seasons** — reset 1st of every month at **00:00 UTC**
- Surface "season ends in X" in user's local time
- **Top 20% of each tier promotes** at season end
- **Bottom 20% relegates**
- **Middle 60% stays**
- **No decay** for players who skip a season — stagnate, don't lose
- **Placement matches** (first 5 hunts of season) determine starting tier for new players

### Top-Tier Glory

- End-of-season Diamond #1 → permanent named trophy on profile
- Tier-themed cosmetic unlocks each tier reached
- Profile shows current tier + highest tier ever reached

---

## Powerups

**Not in v1.** All powerups (including themed Hunt-specific ones) are deferred to v2.

v1 keeps the mechanic clean: walking is the only verb on either side. After we have data on whether the base loop is fun, we'll add powerups for depth and tradeoffs.

### v2+ candidates

**Capybara side:**
- 🥖 **Trail Snack** — burst +1,500–4,500 steps. Panic button before a feeding.
- 🛡️ **Thick Fur** — survive one Feeding even below threshold. Single-use shield.

**Wolf side:**
- 🐺 **Blood Hunt** — your steps count 1.5× toward Pack Pressure for a window.
- 🎯 **Pack Mark** — re-introduces Mark Prey targeting.

Plus the existing race powerups (LEG_CRAMP, STEALTH_MODE, etc.) re-themed for The Hunt context.

---

## Notifications

Lean and intentional. Three per hunt by default; user-configurable:

- T-5 min: *"Your Hunt starts in 5 minutes"*
- T-10 min before each Feeding: silent sync push + visible warning *"⚠️ Feeding in 10 min. You need 1,200 more steps."* (only if at risk)
- On conversion: *"🐺 You have joined the Hunt"*
- Last Stand begins: *"Only 5 capybaras remain..."*
- Hunt over: results

Push to **all participants** (including converted wolves) for Last Stand and results. Don't let the wolves miss the climax.

---

## Visual Identity (high level)

- **Capybara mode**: warm, green, daylight, cozy
- **Wolf mode**: cool, red, moonlit, predatory
- **CPU wolf cast**: 5 distinct silhouettes/colorways (lead with Fang and Ash for v1)
- **Conversion animation**: comic-panel reveal — invest here, it's the screenshot moment
- **Tier badges**: use existing capybara character; add tier-specific accessory (laurel, crown, etc.)
- **Hunt tab icon**: paw print

Figma deliverables: 4 key screens (lobby, capybara active, conversion, wolf active) + tier badge set + 2 powerup icons.

---

## v1 Scope — what ships

✅ **In:**
- Single ranked mode, queue-based matchmaking with bot backfill
- 30-player lobby, 6 hours, 4 Feedings + Last Stand
- 5 tiers (Bronze→Diamond), monthly seasons, promote/relegate
- Pack Pressure (the *only* wolf mechanic in v1)
- Conversion-to-wolf flow with full UI swap
- 5 named CPU starter wolves (2 spawn per hunt)
- HP system + tier movement
- iOS only

🚫 **Out (future work):**
- All powerups (themed or otherwise)
- Mark Prey / any individual wolf targeting
- Buy-in lobbies & coin prize pools
- Player-chosen wolf role
- Wolf Moon / Grand Hunt special events
- Friend-priority matchmaking
- Android
- Tier-specific CPU wolf scaling beyond v1 defaults
- Cosmetic shop integration for Hunt-exclusive items
- Spectator mode for non-participants

---

## Resolved Open Questions

| # | Question | Resolution |
|---|---|---|
| 1 | Late join handling | **No late joins.** Match locks at start. |
| 2 | Bot capybara behavior | **Randomized step habits scaled to lobby's tier.** |
| 3 | Season time zone | **UTC.** Surface "ends in X" locally. |
| 4 | Step sync delays | **T-10 sync push + 5-min grace window after feeding time.** |
| 5 | Sandbagging | **Ignored in v1.** Revisit when rewards land. |

---

## Future Work (v2+)

- **Wolf Moon** monthly event: humans choose to play as 5 wolves vs 25 capybaras racing to safe zone
- **Grand Hunt**: 18h, 60-player, no-ranked epic format
- **Pack Loyalty**: Diamond-tier veterans can opt to queue as wolf instead of capybara
- **Seasonal CPU wolves**: rotating cast for variety (Winter wolves, Desert wolves)
- **Friend lobbies**: opt into matchmaking with up to 2 friends
- **Hunt streaks** with daily login bonuses
- **Buy-in lobbies** with real coin pools
- **Replay system**: full timeline scrubbing, share to social

---

## Build Phases (from build plan)

1. **Phase 0** (1 wk) — finalize tuning spreadsheet + Figma
2. **Phase 1** (3–4 wks) — single hunt MVP, internal testing
3. **Phase 2** (2–3 wks) — matchmaking + bot backfill + multiple concurrent lobbies
4. **Phase 3** (3 wks) — ranked tiers, monthly seasons, HP system
5. **Phase 4** (2 wks) — polish, cosmetics, tier badges (powerups deferred to post-launch)
6. **Phase 5** (ongoing) — live ops, tuning, season events

**Target: public launch ~12 weeks from kickoff.**

---

## Success Metrics

- **Daily Hunt participation rate**: % of DAU who queue at least one hunt
- **Hunt completion rate**: % who stay until the match ends (even as wolves)
- **D7 retention** for Hunt participants vs non-participants
- **Tier progression**: distribution across tiers (avoid >50% in any single tier)
- **Conversion engagement**: do post-conversion wolves walk more or less than pre-conversion? (Should be more — that's the magic.)

---

*End of doc.*
