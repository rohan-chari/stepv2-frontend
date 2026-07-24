# Buff stacking (sum) + multiplicative event scoring — requirements

Status: **spec locked 2026-07-23**; owner pre-approved implementation and
answered the two rule questions directly. Backend-only (scoring is fully
server-authoritative; no frontend change, no API shape change).

## 1. Summary & user story

> As a racer, when I stack boosts during a global step event, my steps should
> multiply the way the store copy implies: Ghost Pepper (3x) during a 2x event
> = **6x**; add Runner's High (2x) = **10x**; and if I'm Wrong Turned while at
> 10x I go **backwards at 10x**.

Two problems today:

1. **Bug** — `computeGlobalEventBoost` was designed for multiplicative
   stacking (`m_p × event`), but its caller
   (`effectiveStepScoring.js:606`) passes `effectGroups: { legCramps,
   runnersHighs, wrongTurns, campfires }` — the wave-5 groups (ghostPeppers,
   uprisings, rallyFlags, coinFlips) were never added when wave 5 landed, and
   `wrongTurns` is passed but never destructured inside
   `globalStepEvent.js`. Observed in prod 2026-07-23 (DrAmogh): pepper boost +
   2x event paid 4x (1 base + 2 pepper extra + 1 event extra) instead of 6x.
   Latent siblings: pepper-freeze steps and wrong-turned steps still earn
   *positive* event credit.
2. **Rule change (owner decision 2026-07-23)** — overlapping self-buffs now
   **SUM their multipliers** (pepper 3x + RH 2x = 5x), replacing the shipped
   max-not-sum rule (which yields 3x). Owner confirmed with the concrete case:
   100 real steps under RH+pepper = **500**, not 300/400. Second owner
   decision: Wrong Turn **negates the full effective rate including the event
   segment math** (100 steps under WT+pepper+RH+2x event = **−1,000**).

## 2. Scope / non-goals

In scope (backend only):
- One shared definition of the **signed effective multiplier at time t** and
  its use in all three existing copies of the logic:
  `effectiveStepScoring.js` (`computeEffectModifiers`),
  `raceStateResolution.js` (`multiplierForTime` → `determineFinishSnapshot`),
  `globalStepEvent.js` (`positiveMultiplierForTime` + `multiplierBoundaries`).
- Detailed integration tests for the stacking table in §4.

Non-goals:
- No API shape change; `GET /races/:id/progress` fields are unchanged (values
  change, shapes don't). No frontend work, no store copy changes.
- No retro adjustment: **forward-only** (owner decision). Active races
  self-heal on next recompute because scoring is recomputed from samples;
  settled races stay as settled.
- Leech, Hitchhike, bonus-step events (Protein Shake / Shortcut / Red Card /
  Pinecone / Trail Mine), box-progress math (explicitly multiplier-immune),
  and Sneaky Swap / Imposter display illusions: all unchanged.
- No stacking cap. Theoretical max (~13x summed buffs × 2 event ≈ 26x) is an
  accepted owner risk; revisit only if abused.

## 3. The rule — signed effective multiplier m(t)

For a participant at instant `t`, with that participant's effect rows:

1. **Freeze wins over everything.** If any of LEG_CRAMP, QUICKSAND,
   CAMPFIRE_REST freeze phase (`[startsAt, startsAt+freezeMs)`), or
   GHOST_PEPPER freeze phase (`[startsAt+boostMs, expiresAt)`) is active:
   `m(t) = 0`. Frozen steps earn no base, no buff, no event credit — and no
   reversal either (you can't be dragged backwards while frozen; matches
   today's freeze-beats-buff precedent extended to freeze-beats-WT, which is
   also today's `multiplierForTime` order).
2. **Buffs sum.** Let B = the set of active boost phases among: RUNNERS_HIGH
   (2), CAMPFIRE_REST boost phase (`metadata.multiplier`), UPRISING
   (`metadata.multiplier` || 2), RALLY_FLAG (`metadata.multiplier` || 1.25),
   COIN_FLIP win (`metadata.multiplier` || 2), GHOST_PEPPER boost phase
   (`metadata.multiplier` || 3). `M = |B| ? Σ multiplier_i : 1`. (Multiple
   rows of the same type each count — today's re-use rules already prevent
   meaningful same-type overlap; do not add new dedup.)
3. **Reductions subtract, additively, floored at 0** (existing model kept):
   for each active RAINSTORM or COIN_FLIP loss with reduce-multiplier `r`
   (default 0.5, valid range [0,1]): `M = max(0, M − (1 − r))` — unless the
   reduction is suspended (existing rules unchanged: suspended while frozen —
   moot, m=0 — and UMBRELLA subtracts its overlap from opponent-sourced
   rainstorm windows before this point, exactly as the current umbrella pass
   does).
4. **Wrong Turn negates.** If any WRONG_TURN is active: `m(t) = −M`.

A global event with multiplier `E` over window W scales the whole signed rate:
steps walked at instant `t ∈ W` count `m(t) × E`; outside W they count `m(t)`.
Equivalently (and how it's implemented, keeping the additive-boost payload
shape): event extra = `Σ_segments steps × m(t) × (E − 1)` with **signed** m —
positive segments gain, wrong-turned segments lose more, frozen segments get 0.

### Worked examples (these are the acceptance numbers; 100 real steps each)

| Active                                   | m(t) | ×2 event | steps counted |
|------------------------------------------|------|----------|---------------|
| nothing                                  | 1    | 2        | 200           |
| Ghost Pepper boost                       | 3    | 6        | 600           |
| Pepper boost + Runner's High             | 5    | 10       | 1,000         |
| Pepper + RH + Wrong Turn                 | −5   | −10      | −1,000        |
| Wrong Turn alone                         | −1   | −2       | −200          |
| Pepper freeze phase (or any freeze)      | 0    | 0        | 0             |
| Freeze + Wrong Turn                      | 0    | 0        | 0             |
| RH + Uprising(2) + Pepper (3-way)        | 7    | 14       | 1,400         |
| Campfire boost (2.25) + RH               | 4.25 | 8.5      | 850           |
| Rainstorm (0.5) alone                    | 0.5  | 1        | 100           |
| RH + Rainstorm                           | 1.5  | 3        | 300           |

Note two deliberate behavior changes beyond the headline: (a) 3-way overlaps
sum fully (old pairwise reconciliation would mis-handle them); (b) during an
event, a rainstormed participant now earns `0.5×E` rather than
`0.5 + (E−1)` — the event multiplies your *current* rate, whatever it is.

## 4. Implementation plan (order matters)

### 4.1 One shared multiplier module (kills the 3-copy drift trap)

Create `src/modules/races/services/effectMultiplier.js` exporting:
- `signedMultiplierAt(timeMs, groups)` — implements §3 exactly. `groups` =
  `{ legCramps, runnersHighs, wrongTurns, campfires, rainstorms, uprisings,
  rallyFlags, coinFlipWins, coinFlipLoses, ghostPeppers }` (umbrella-adjusted
  rainstorm windows are resolved by the caller BEFORE this, as today).
- `multiplierBoundaries(windowStart, windowEnd, groups)` — every startsAt /
  expiresAt / phase-transition (`campfire startsAt+freezeMs`, `ghost pepper
  startsAt+boostMs`) instant inside the window, clamped, sorted, deduped.

Both are pure (no DB); unit-test the truth table in §3 directly here (this is
the "pure algorithmic math with many cases" exception where unit tests are the
right tool), but the behavior MUST also be proven end-to-end per §6.

### 4.2 `computeEffectModifiers` (effectiveStepScoring.js) — segment rewrite

Replace the per-effect additive loops + pairwise overlap-reconciliation passes
(the RH/legCramp strip, campfire×RH strip, WT×RH double-negate, wave-5
boostWindows max-not-sum pass, ghost-freeze strip) with one segment walk:
slice `[effectiveStart-of-earliest-effect, now]` at `multiplierBoundaries`,
compute `m` per segment via `signedMultiplierAt`, read segment steps once via
`sumStepsInWindow`, and bucket into the EXISTING return shape so callers and
the total formula (`base − frozen + buffed − 2×reversed + event + bonus`,
`raceStateResolution.js:232`) are untouched:
- `m = 0` → `frozenSteps += s`
- `m > 0` → `buffedSteps += (m − 1) × s`
- `m < 0` → `reversedSteps += s` and `buffedSteps += (m + 1) × s`
  (algebra: `s − 2s + (m+1)s = m·s` ✓ — keeps `reversedSteps` meaning "raw
  steps walked while reversed").
Efficiency: segments only exist where effects exist; a participant with no
effects must not regress to extra queries (early-return exactly as today).
Batch the per-segment sums with `sumStepsInWindows` (plural) where available.

Snapshot-fallback (`hasSampleData === false`): keep the existing per-effect
snapshot approximations as the no-samples degradation path — unchanged
behavior, documented imprecision.

### 4.3 `computeGlobalEventBoost` (globalStepEvent.js)

Delete the local `positiveMultiplierForTime`/`multiplierBoundaries` and use
the shared module with the FULL groups (caller passes them all from
`computeEffectModifiers`). The segment formula is already
`s × m_p × (E − 1)` — with signed `m_p` it produces the §3 numbers, including
negative event extra during Wrong Turn and 0 during freezes.

### 4.4 `multiplierForTime` (raceStateResolution.js)

Replace its body with a delegation to `signedMultiplierAt` (it already has the
same signature shape and signed/zero semantics; today it's wave-5-blind and
uses max). `determineFinishSnapshot`'s boundary set must also come from the
shared `multiplierBoundaries` so finish-time interpolation sees pepper/uprising
phase edges.

### 4.5 Compatibility & rollout

- Scoring is 100% server-side: old and new app binaries both just display
  server totals. No client gating, no `testOnly`, no env flag needed.
- Deploy = standard backend deploy (`pm2 reload`, zero-downtime). Live races
  recompute on next sync/progress read — totals will visibly jump for anyone
  currently stacking buffs (expected, forward-only decision).
- Settlement and display share the changed code, so no live-vs-settlement
  divergence window exists.

## 5. Existing tests that encode the OLD rule (owner-authorized updates)

Hard rule "never modify existing tests" gets a **narrow, enumerated
exception**, owner-approved via this spec: assertions that exist specifically
to pin max-not-sum / old-WT / old-event math are obsolete under the new rule.
The implementer must:
1. Run the full integration suite BEFORE changing code (baseline).
2. After the change, for each newly-failing existing test: if its failure is
   exactly "old stacking/reversal/event arithmetic expected", update ONLY the
   expected numbers (never the scenario/setup) and annotate with a one-line
   comment `// 2026-07-23 sum-stacking rule (see buff-stacking spec)`.
   Known members of this class: `powerups-campfire-runners-high.test.js`
   (max(2x,2.25x) assertions), WT×RH doubling assertions in
   `powerups-wrong-turn.test.js`, and any max-not-sum / event-composition
   assertions in `powerups5-wave.test.js` and global-event tests.
3. Any OTHER failure (setup breaks, crashes, unrelated assertions) → STOP and
   report; do not adapt the test. Pre-existing failures (13 fanny-pack,
   1 ad-coin, 2 hitchhike) stay untouched and unclaimed.

## 6. Test plan — tests FIRST (integration; real HTTP + test DB, never prod)

New file `test/integration/buff-stacking-event-scoring.test.js`, following
`powerups5-wave.test.js` conventions (seeded users/races/effects, real
progress endpoint, `test:integration` runner). Insert step samples fully
inside effect windows (closed hours) so proration is exact; assert on the API
leaderboard totals a client would see. One test per row of the §3 table:

1. Pepper boost + 2x event → 6x (DrAmogh's case; the headline bug).
2. Pepper + RH, no event → 5x (sum replaces max).
3. Pepper + RH + 2x event → 10x (the owner's target number).
4. Pepper + RH + WT + 2x event → −10x (walk 100, total drops 1,000 vs
   pre-walk total, floored at 0 by the total clamp when applicable — seed
   enough prior steps that the floor doesn't mask the assertion).
5. WT alone + 2x event → −2x (event credit goes negative, not positive — the
   latent leak).
6. Pepper FREEZE phase + 2x event → 0 (frozen steps earn no event credit).
7. Freeze + WT overlap → 0 (freeze beats reversal).
8. Three-way RH + Uprising + Pepper → 7x (proves true sum, not pairwise).
9. Campfire boost 2.25x + RH → 4.25x (the old max test's scenario, new rule).
10. Rainstorm + 2x event → 1x (reduction is multiplied by the event).
11. Settlement parity: run the race to expiry (raceExpiry path) with scenario
    3 active at race end → settled `finish_total_steps`/placements equal the
    live math; and a target-steps race crossing the target mid-pepper-boost
    interpolates the finish time with the summed multiplier
    (`determineFinishSnapshot`).
12. No-effects regression: participant with zero effects, with and without an
    event → identical totals to today (1x / 2x), and no added queries (assert
    via the existing query-count harness if present, else skip the count).

Plus the §4.1 unit truth-table for `signedMultiplierAt` (pure math, many
cases: every table row, phase edges at exact boundary instants, umbrella-
pre-adjusted rain windows, invalid metadata fallbacks).

## 7. Acceptance criteria / definition of done

- [ ] All 12 integration scenarios green through the real endpoint against the
      test DB; unit truth-table green.
- [ ] Exactly one implementation of m(t) (`effectMultiplier.js`); the three
      former copies delegate to it — verified by grep: no remaining
      `Math.max`-based buff reconciliation in the three files.
- [ ] Live and settlement paths share the changed code (no new divergence).
- [ ] Existing-test updates confined to §5's enumerated class, each annotated;
      every other pre-existing test untouched and green (minus the known 16
      pre-existing failures).
- [ ] No API shape change (progress payload fields identical; only values
      move).
- [ ] Forward-only: no backfill, no settled-race mutation.

## Revision log

- **Gap pass 1:** (a) pinned freeze-beats-Wrong-Turn (m=0, not −0/−M) — the
  draft left freeze+WT undefined; today's `multiplierForTime` order already
  returns 0 first, so codify it; (b) added the reversedSteps/buffedSteps
  bucketing algebra so the existing total formula and return shape survive
  (callers untouched); (c) added §3 note that rain×event becomes
  multiplicative (0.5×2=1x, was 1.5x) — a real behavior change that needed to
  be explicit, not implicit; (d) added test 8 (3-way sum) because the old
  pairwise reconciliation cannot express it and a 2-way-only suite would pass
  a wrong pairwise implementation.
- **Gap pass 2:** (a) §5 enumerated-exception protocol for obsolete
  max-not-sum tests — without it the implementer hits an unresolvable rule
  conflict ("never modify tests" vs. changed semantics) mid-build; (b) added
  test 11 settlement/finish-snapshot parity including target-steps
  interpolation (the `multiplierForTime` copy is only reachable through
  `determineFinishSnapshot`, which scenario 1–10 never exercise); (c) required
  snapshot-fallback (no-sample) path keep today's behavior explicitly, so the
  segment rewrite doesn't silently drop the degradation path; (d) added the
  no-cap accepted-risk note (~26x worst case) and test 12's no-regression
  guard for the effect-free hot path; (e) clarified umbrella ordering: rain
  windows are umbrella-adjusted BEFORE m(t), preserving the existing pass.
