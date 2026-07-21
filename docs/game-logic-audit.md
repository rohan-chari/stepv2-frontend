# Economy and Power-Up Balance Audit

## Summary

Create `docs/economy-balance-audit.md` covering the full coin economy, store
pricing, upgrade ladders, daily rewards, and race power-up odds. The deliverable
will contain evidence, exact recommended values, migration/rollout guidance, and
proposed interfaces—but no product-code or production changes.

The target philosophy is:

- Fair but impactful purchasable power-ups.
- Small power-up affordable after roughly 1–2 active days.
- Standard cosmetic affordable after 1–2 active weeks.
- Prestige cosmetic affordable after 4–8 active weeks.
- Moderate position-based catch-up assistance.
- Cosmetic prices based on visual prominence, special treatment, and
  exclusivity.
- Exact rarity and item odds visible to players.
- Existing price anchors may be freely replaced.

## Audit and Recommendations

- Inventory every live, test-only, retired, and source-defined price/odds value
  across both repositories and production. Explicitly reconcile
  source-versus-live drift, including Leech’s source price of 150 versus the
  live catalog’s 300.
- Analyze anonymized production aggregates over 7-, 30-, and 90-day windows:
  - Balance distribution and affordability among active, non-review accounts.
  - Recurring coin income separately from referrals, administrative grants,
    refunds, and redistributed buy-in pots.
  - Spend by cosmetics, power-up purchases, upgrades, and buy-ins.
  - Purchase, use, discard, upgrade, defense-block, and inventory-stranding
    rates by power-up.
  - Race size, duration, step totals, and placement context needed to estimate
    competitive impact.
  - Suppress user-level data and any segment smaller than five users.
- Establish a single pricing rubric:
  - Cosmetic tiers based on prominence, animation/special treatment,
    exclusivity, and collection role.
  - Power-up prices based on expected step impact, affected-player breadth,
    reliability, flexibility, counterplay, and inventory friction.
  - Snap recommended prices to a small, documented set of coin bands derived
    from recurring earning velocity.
  - Produce an exact item-by-item table containing current source price, live
    price, recommended price, rationale, and expected earning time.
- Establish one canonical rarity/odds model:
  - Remove conceptual disagreement between drop rarity, display rarity, upgrade
    rarity, documentation, and daily-box classification.
  - Give every power-up one canonical rarity and a separate explicit item
    weight where equal-within-tier odds are inappropriate.
  - Use inverse utility weighting so stronger rewards are less common; do not
    reuse store price as a positive probability weight.
  - Define moderate catch-up guardrails, including maximum leader-to-last
    rarity spread and expected-value spread, then select exact endpoints through
    deterministic calculations and simulations.
  - Cover solo and team positioning, ties, Lucky Horseshoe minimum rarity,
    Fanny Pack rerolls, retired types, full inventory, and store-only types.
- Model daily boxes independently from race boxes:
  - Calculate expected coin value and reward value at streak days 1, 7, and 30.
  - Correct the current contradiction where higher `priceCoins` makes an item
    more likely despite comments claiming it becomes rarer.
  - Recommend exact rarity curves, coin ranges, accessory weights, and power-up
    sub-rolls without making daily rewards depend on unavailable inventory.
- Include a prioritized inconsistency register. Known entries include duplicated
  rarity definitions, stale `POWERUPS.md` odds, historical multi-rarity records,
  source/live catalog drift, upgrade pricing as the largest discretionary sink,
  and store power-ups with materially different effects sharing the same price.

## Proposed Future Interfaces

The audit will specify, but not implement, a versioned backend balance
configuration as the sole authority for prices, rarity, weights, upgrade
ladders, and odds.

For player-facing transparency, propose additive response fields:

- Race progress: `powerupData.dropOdds` containing `configVersion`, current
  position basis, rarity probabilities, and exact per-item probabilities.
- Daily reward status: optional `box.itemOdds` containing the exact currently
  eligible accessory/power-up probabilities.
- New clients hide detailed odds when these blocks are absent or malformed;
  existing rarity fields and endpoint behavior remain unchanged.
- Old app versions continue receiving and using all existing fields and
  endpoints. No existing field is renamed, removed, or reinterpreted.

## Validation and Acceptance

- Verify all probability distributions sum to 100%, contain no
  retired/ineligible types, and remain monotonic from leader to trailer.
- Use exact calculations plus seeded Monte Carlo simulations for 2-, 5-, and
  20-player solo races, both team positions, ties, and representative short/long
  races.
- Confirm recommended price bands meet the chosen earning cadences for median
  and upper-quartile recurring earners without relying on referral windfalls.
- Compare expected competitive value, observed use/discard behavior, and
  recommended price/weight; document every intentional exception.
- Calculate daily-box expected value for empty, partial, and exhausted accessory
  pools and for clients with and without eligible power-up support.
- Include compatibility scenarios for old app/new backend, new app/old backend,
  phased rollout, already-owned cosmetics, stored power-ups, and purchases made
  at historical prices.
- Finish with an exact proposed balance table, risks, telemetry to monitor after
  any future rollout, and rollback thresholds. No deployment, database write,
  catalog update, or production-code change is part of this audit.
