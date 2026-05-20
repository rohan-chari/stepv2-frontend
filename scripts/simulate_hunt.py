"""
The Hunt — ranked mode simulator with auto-tuning.

Phase A: iteratively tunes per-tier feeding thresholds until each tier hits
         the target attrition curve (30 → 25 → 18 → 10 → 4 → 1).
Phase B: prints final tuned thresholds in table form, ready for the tuning doc.
Phase C: runs a full 5-season, 1000-player simulation with tuned numbers
         and prints ranked-system health stats.

Usage: python3 scripts/simulate_hunt.py
"""

import random
import statistics
from collections import defaultdict
from dataclasses import dataclass, field

# ---------- Tuning constants ----------

TIERS = ["Bronze", "Silver", "Gold", "Platinum", "Diamond"]

TIER_PACE = {
    "Bronze": 1100, "Silver": 1500, "Gold": 2000, "Platinum": 2600, "Diamond": 3300,
}
TIER_PACK_FACTOR = {
    "Bronze": 0.15, "Silver": 0.20, "Gold": 0.30, "Platinum": 0.40, "Diamond": 0.50,
}
TIER_CPU_RATE = {
    "Bronze": 500, "Silver": 750, "Gold": 1000, "Platinum": 1300, "Diamond": 1500,
}

# Initial thresholds — will be overwritten by Phase A tuning
INITIAL_THRESHOLDS = {
    "Bronze":   {"F1": 1000, "F2": 3000, "F3": 4500, "F4":  6000, "Final":  7000},
    "Silver":   {"F1": 1500, "F2": 4000, "F3": 6000, "F4":  8000, "Final":  9500},
    "Gold":     {"F1": 2500, "F2": 5500, "F3": 8500, "F4": 11000, "Final": 13000},
    "Platinum": {"F1": 3000, "F2": 7000, "F3":11000, "F4": 14000, "Final": 16500},
    "Diamond":  {"F1": 4000, "F2": 9000, "F3":14000, "F4": 18000, "Final": 21000},
}

FEEDING_TIMES_HR = {"F1": 1.5, "F2": 3.0, "F3": 4.5, "F4": 5.5, "Final": 6.0}
FEEDING_ORDER = ["F1", "F2", "F3", "F4", "Final"]

# Target alive AFTER each feeding (start at 30)
TARGET_ALIVE = {"F1": 25, "F2": 18, "F3": 10, "F4": 4, "Final": 1}

HP = {
    "win": 100, "top3": 50, "alpha": 50,
    "survive_f2": 20, "survive_f3": 15, "completed": 5,
}

WOLF_PACE_MULT = 0.80
PACK_PRESSURE_CAP_PCT = 0.50
PLAYER_MATCH_VARIANCE = 0.35  # bumped from 0.20 (realistic walker day-to-day)
BOT_VARIANCE = 0.25
CPU_VARIANCE = 0.25

LOBBY_SIZE = 30
STARTER_WOLVES = 2

PROMOTE_PCT = 0.10  # dropped from 0.20 (less yo-yo)
RELEGATE_PCT = 0.10

# ---------- Player model ----------

@dataclass
class Player:
    id: int
    skill: float
    tier: str
    hp: int = 0
    matches: int = 0
    wins: int = 0
    top3_finishes: int = 0
    alphas: int = 0
    times_eaten: int = 0
    tier_history: list = field(default_factory=list)

# ---------- Match simulation ----------

def simulate_match(lobby_players, tier, thresholds):
    """Simulate one hunt. Returns per-player results + attrition data."""
    base_pace = TIER_PACE[tier]
    pack_factor = TIER_PACK_FACTOR[tier]
    cpu_rate = TIER_CPU_RATE[tier]

    # Build capybara list
    capys = []
    for p in lobby_players:
        rate = max(200, random.gauss(p.skill, p.skill * PLAYER_MATCH_VARIANCE))
        capys.append({"player": p, "rate": rate, "eaten_at": None, "wolf_steps": 0.0})
    while len(capys) < LOBBY_SIZE:
        rate = max(200, random.gauss(base_pace, base_pace * BOT_VARIANCE))
        capys.append({"player": None, "rate": rate, "eaten_at": None, "wolf_steps": 0.0})

    # CPU wolves
    cpus = []
    for _ in range(STARTER_WOLVES):
        rate = max(100, random.gauss(cpu_rate, cpu_rate * CPU_VARIANCE))
        cpus.append({"rate": rate})

    surviving = list(capys)
    converted = []
    last_t = 0.0
    feeding_results = {}

    for fname in FEEDING_ORDER:
        t = FEEDING_TIMES_HR[fname]
        window = t - last_t

        wolf_window = [c["rate"] * window for c in cpus]
        for c in converted:
            time_in_window = min(window, max(0.0, t - c["eaten_at"]))
            steps = c["rate"] * WOLF_PACE_MULT * time_in_window
            wolf_window.append(steps)
            c["wolf_steps"] += steps

        avg_wolf = statistics.mean(wolf_window) if wolf_window else 0
        base = thresholds[fname]
        pack_pressure = min(avg_wolf * pack_factor, base * PACK_PRESSURE_CAP_PCT)
        threshold = base + pack_pressure

        new_surv = []
        for c in surviving:
            if c["rate"] * t < threshold:
                c["eaten_at"] = t
                converted.append(c)
            else:
                new_surv.append(c)
        surviving = new_surv
        feeding_results[fname] = (threshold, len(surviving))
        last_t = t

    winner = max(surviving, key=lambda c: c["rate"] * 6.0) if surviving else None
    by_perf = sorted(capys, key=lambda c: c["rate"] * (c["eaten_at"] or 6.0), reverse=True)
    top3_set = set(id(c) for c in by_perf[:3])
    eligible_alphas = [c for c in converted if c["player"] is not None]
    alpha = max(eligible_alphas, key=lambda c: c["wolf_steps"]) if eligible_alphas else None

    per_player = []
    for c in capys:
        if c["player"] is None:
            continue
        p = c["player"]
        h = HP["completed"]
        if c is winner: h += HP["win"]
        if id(c) in top3_set: h += HP["top3"]
        if c is alpha: h += HP["alpha"]
        if (c["eaten_at"] or 6.0) > FEEDING_TIMES_HR["F2"]: h += HP["survive_f2"]
        if (c["eaten_at"] or 6.0) > FEEDING_TIMES_HR["F3"]: h += HP["survive_f3"]
        per_player.append({
            "player": p, "hp": h,
            "won": c is winner, "top3": id(c) in top3_set, "alpha": c is alpha,
            "eaten_at": c["eaten_at"],
        })
    return per_player, feeding_results

# ---------- Phase A: auto-tune thresholds ----------

def make_dummy_lobby(tier, count=30):
    """Build a synthetic lobby of skill-matched players for tuning."""
    base = TIER_PACE[tier]
    players = []
    for i in range(count):
        # Skill spread within tier ~ ±20% of TIER_PACE
        skill = max(500, random.gauss(base, base * 0.20))
        players.append(Player(id=-i, skill=skill, tier=tier))
    return players

def measure_attrition(tier, thresholds, n_matches=500):
    """Run n matches and return avg alive count after each feeding."""
    alives = {f: [] for f in FEEDING_ORDER}
    for _ in range(n_matches):
        lobby = make_dummy_lobby(tier)
        _, fr = simulate_match(lobby, tier, thresholds)
        for f in FEEDING_ORDER:
            alives[f].append(fr[f][1])
    return {f: statistics.mean(alives[f]) for f in FEEDING_ORDER}

def tune_tier(tier, n_iterations=15, n_matches_per=300):
    """Iteratively adjust thresholds until attrition matches target curve."""
    thresholds = dict(INITIAL_THRESHOLDS[tier])
    for it in range(n_iterations):
        actual = measure_attrition(tier, thresholds, n_matches=n_matches_per)
        max_err = 0
        for f in FEEDING_ORDER:
            diff = actual[f] - TARGET_ALIVE[f]
            max_err = max(max_err, abs(diff))
            # If too many alive (diff > 0), raise threshold. If too few, lower.
            # Adjustment proportional to error, dampened.
            adj = 1 + (diff / 30) * 0.20
            adj = max(0.85, min(1.20, adj))  # clamp
            thresholds[f] *= adj
        # Round to nearest 100 for cleanliness during tuning (helps convergence)
        thresholds = {f: round(thresholds[f] / 100) * 100 for f in FEEDING_ORDER}
        if max_err < 0.5:
            break
    return thresholds, actual

def round_thresholds_for_doc(thresholds):
    """Round to nearest 500 for the final doc."""
    return {f: round(thresholds[f] / 500) * 500 for f in FEEDING_ORDER}

def run_tuning_phase():
    print("=" * 70)
    print("PHASE A — Auto-tuning thresholds to match target attrition")
    print("=" * 70)
    print(f"Target: 30 → 25 → 18 → 10 → 4 → 1")
    print(f"Per-match player variance: ±{int(PLAYER_MATCH_VARIANCE*100)}%\n")

    tuned = {}
    for tier in TIERS:
        thresholds, actual = tune_tier(tier)
        rounded = round_thresholds_for_doc(thresholds)
        # Re-measure after rounding
        final_actual = measure_attrition(tier, rounded, n_matches=1000)
        tuned[tier] = rounded
        print(f"  {tier}: thresholds = {rounded}")
        att_str = "  →  ".join(f"{final_actual[f]:5.1f}" for f in FEEDING_ORDER)
        print(f"           attrition  =   30.0  →  {att_str}")
        print()
    return tuned

# ---------- Phase B: print final table ----------

def print_master_table(tuned_thresholds):
    print("=" * 70)
    print("PHASE B — Final Tuned Master Table")
    print("=" * 70)
    print(f"{'Tier':<10} {'F1':>7} {'F2':>7} {'F3':>7} {'F4':>7} {'Final':>7} {'Pack×':>7} {'CPU/hr':>8}")
    print("-" * 70)
    for tier in TIERS:
        t = tuned_thresholds[tier]
        print(f"{tier:<10} "
              f"{t['F1']:>7} {t['F2']:>7} {t['F3']:>7} {t['F4']:>7} {t['Final']:>7} "
              f"{TIER_PACK_FACTOR[tier]:>7.2f} {TIER_CPU_RATE[tier]:>8}")
    print()

# ---------- Phase C: full season sim ----------

def init_players(n=1000, seed=42):
    random.seed(seed)
    players = []
    for i in range(n):
        skill = max(500, random.gauss(2000, 800))
        if skill < 1300: tier = "Bronze"
        elif skill < 1800: tier = "Silver"
        elif skill < 2400: tier = "Gold"
        elif skill < 3000: tier = "Platinum"
        else: tier = "Diamond"
        players.append(Player(id=i, skill=skill, tier=tier))
    return players

def run_season(players, thresholds_by_tier, matches_per_player=20):
    for p in players:
        p.hp = 0
    attrition_data = defaultdict(list)
    season_matches = defaultdict(int)
    target_total = (matches_per_player * len(players)) // LOBBY_SIZE * 2
    match_count = 0

    while match_count < target_total:
        tier_choices = list(TIERS)
        random.shuffle(tier_choices)
        chose = None
        for tier in tier_choices:
            eligible = [p for p in players
                        if p.tier == tier and season_matches[p.id] < matches_per_player]
            if len(eligible) >= 5:
                lobby = random.sample(eligible, min(LOBBY_SIZE, len(eligible)))
                results, fr = simulate_match(lobby, tier, thresholds_by_tier[tier])
                for r in results:
                    r["player"].hp += r["hp"]
                    r["player"].matches += 1
                    season_matches[r["player"].id] += 1
                    if r["won"]: r["player"].wins += 1
                    if r["top3"]: r["player"].top3_finishes += 1
                    if r["alpha"]: r["player"].alphas += 1
                    if r["eaten_at"] is not None: r["player"].times_eaten += 1
                attrition = [LOBBY_SIZE] + [fr[f][1] for f in FEEDING_ORDER]
                attrition_data[tier].append(attrition)
                match_count += 1
                chose = tier
                break
        if chose is None:
            break

    for tier in TIERS:
        tier_players = [p for p in players if p.tier == tier]
        if len(tier_players) < 5: continue
        tier_players.sort(key=lambda p: p.hp, reverse=True)
        n = len(tier_players)
        promote_n = max(1, int(n * PROMOTE_PCT))
        relegate_n = max(1, int(n * RELEGATE_PCT))
        tier_idx = TIERS.index(tier)
        if tier_idx < len(TIERS) - 1:
            for p in tier_players[:promote_n]:
                p.tier = TIERS[tier_idx + 1]
        if tier_idx > 0:
            for p in tier_players[-relegate_n:]:
                p.tier = TIERS[tier_idx - 1]

    for p in players:
        p.tier_history.append(p.tier)
    return attrition_data, match_count

def run_full_simulation(tuned_thresholds):
    print("=" * 70)
    print("PHASE C — Full simulation (1000 players, 5 seasons)")
    print("=" * 70)
    players = init_players(n=1000, seed=42)
    print("Initial tier distribution:")
    for tier in TIERS:
        n = sum(1 for p in players if p.tier == tier)
        print(f"  {tier}: {n}")
    print()

    merged_attrition = defaultdict(list)
    total_matches = 0
    for season in range(5):
        print(f"  Season {season + 1}/5...")
        att, mc = run_season(players, tuned_thresholds, matches_per_player=20)
        total_matches += mc
        for t in TIERS:
            merged_attrition[t].extend(att[t])

    print()
    print(f"Total matches simulated: {total_matches}")
    print(f"Avg matches per player: {sum(p.matches for p in players)/len(players):.1f}")
    print()

    print("── FINAL TIER DISTRIBUTION ──")
    for tier in TIERS:
        n = sum(1 for p in players if p.tier == tier)
        bar = "█" * int(n / 10)
        print(f"  {tier:<10} {n:>4}  ({n/10:5.1f}%) {bar}")
    print()

    print("── ATTRITION CURVE (avg per tier) ──")
    print("              start →    F1 →    F2 →    F3 →    F4 → Final")
    print("  Target:        30      25      18      10       4      1")
    for tier in TIERS:
        runs = merged_attrition[tier]
        if not runs: continue
        avgs = [statistics.mean(col) for col in zip(*runs)]
        avg_str = "   ".join(f"{a:5.1f}" for a in avgs)
        print(f"  {tier:<10} {avg_str}")
    print()

    print("── WIN RATE BY SKILL QUINTILE ──")
    sorted_players = sorted(players, key=lambda p: p.skill)
    quintile_size = len(sorted_players) // 5
    for i in range(5):
        q = sorted_players[i*quintile_size:(i+1)*quintile_size]
        avg_skill = statistics.mean(p.skill for p in q)
        m = sum(p.matches for p in q)
        w = sum(p.wins for p in q)
        wr = (w/m*100) if m else 0
        print(f"  Q{i+1} (skill ~{avg_skill:>5.0f} steps/hr): "
              f"{w:>4} wins / {m:>5} matches = {wr:5.2f}%")
    print()

    print("── TIER MOBILITY (8 sample players, season-by-season) ──")
    sample = random.sample(players, 8)
    for p in sample:
        traj = " → ".join(p.tier_history)
        print(f"  Player {p.id:>4} (skill {p.skill:>5.0f}): {traj}")
    print()

    print("── ALPHA WOLF FREQUENCY ──")
    total_alphas = sum(p.alphas for p in players)
    total_m = sum(p.matches for p in players)
    print(f"  Total Alpha titles: {total_alphas} (1 per match expected: ~{total_m/LOBBY_SIZE:.0f})")
    print()

    print("── ELIMINATION TIMING ──")
    for tier in TIERS:
        tps = [p for p in players if p.tier == tier]
        if not tps: continue
        m = sum(p.matches for p in tps)
        e = sum(p.times_eaten for p in tps)
        if m:
            print(f"  {tier:<10} {e/m*100:5.1f}% of matches eaten")
    print()

def main():
    tuned = run_tuning_phase()
    print_master_table(tuned)
    run_full_simulation(tuned)

if __name__ == "__main__":
    main()
