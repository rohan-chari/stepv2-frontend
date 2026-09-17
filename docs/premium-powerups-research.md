# Bara Gold Premium Powerups Research

Research-only handoff for adding premium powerups to Bara Gold. This document records the current architecture and recommended implementation boundary. No code, schema, tests, App Store Connect, RevenueCat, or external systems were changed as part of this research.

## 1. Current Powerup Architecture

Powerup definitions are backend-owned. The main catalog record is `PowerupShopItem`, with `sku`, display metadata, `priceCoins`, `powerupType`, `active`, `testOnly`, `dailyRewardEligible`, and ordering fields. User-owned global inventory is represented by `UserPowerupItem` quantities keyed by `(userId, powerupType)`. Race-held inventory is represented separately by `RacePowerup` rows.

The end-to-end path is:

```text
PowerupShopItem / backend policy
  -> capability-filtered shop catalog
  -> purchase or rewarded unlock
  -> UserPowerupItem quantity
  -> redeem into a race
  -> RacePowerup HELD item
  -> server-authoritative use/effect logic
```

Important backend files:

- `src/modules/powerups/constants/powerupGating.js`
- `src/modules/powerups/models/powerupShopItem.js`
- `src/modules/powerups/models/userPowerupItem.js`
- `src/modules/powerups/queries/getPowerupShopCatalog.js`
- `src/modules/powerups/queries/getEligiblePowerupPool.js`
- `src/modules/powerups/commands/purchasePowerupItem.js`
- `src/modules/powerups/commands/unlockPowerupWithAds.js`
- `src/modules/powerups/commands/grantPowerupToUser.js`
- `src/modules/powerups/commands/redeemPowerupToRace.js`
- `src/modules/powerups/commands/usePowerup.js`
- `src/modules/economy/commands/claimDailyRewardBox.js`
- `src/modules/powerups/commands/rollPowerup.js`
- `src/modules/powerups/commands/openMysteryBox.js`

Important frontend files:

- `lib/screens/tabs/shop_tab.dart`
- `lib/screens/daily_reward_screen.dart`
- `lib/widgets/case_opening_strip.dart`
- `lib/widgets/powerup_icon.dart`
- `lib/constants/powerup_copy.dart`
- `lib/services/backend_api_service.dart`

The backend is authoritative for catalog visibility, prices, membership, purchase, reward selection, inventory, race redemption, and effect execution. The frontend currently renders backend responses and sends actions; it must not become the source of premium eligibility.

## 2. Current Powerup Catalog

The table reflects repository definitions and code paths. Live `active`, `priceCoins`, and `testOnly` values are database/admin-controlled; this research did not query production.

| Powerup | Internal key | Exists? | Shop? | Daily Spin? | Mystery Box? | Current price | Notes |
|---|---|---:|---:|---:|---:|---:|---|
| Hitchhike | `HITCHHIKE` | Yes | Yes when active/capability-supported | No by explicit `dailyRewardEligible: false` | No; store-only | 150 seed value | Fully implemented and targeted. |
| Leech | `LEECH` | Yes | Yes when active/capability-supported | Potentially yes | No; store-only | 300 seed value | Store-only, but seed does not explicitly disable daily eligibility; this is an inconsistency to resolve. |
| Quicksand | `QUICKSAND` | Yes | Yes when active and `powerups4` capable | Yes when eligible in the live catalog | No; absent from mystery-box drop pool | 300 seed value | Fully implemented, not merely a placeholder. |
| Imposter | `IMPOSTER` | Yes | Retired by code | No | No | 75 seed value | Permanently retired from active client visibility. |
| Rainstorm | `RAINSTORM` | Yes | Test-only | Usually not in production | Drop-pool/config dependent | 75 | Capability/content-gated. |
| Signal Jammer | `SIGNAL_JAMMER` | Yes | Yes when active | Eligible if the live row allows it | Config dependent | 75 | Existing powerup. |
| Cleanse | `CLEANSE` | Yes | Inactive in seed | No while inactive | Config dependent | 150 | Existing but inactive by seed. |
| Quick Rinse | `QUICK_RINSE` | Yes | Test-only/store-only | No intended daily use | No; store-only | 75 | Existing capability-gated type. |
| X-Ray / Defense Scan | `DEFENSE_SCAN` | Yes | Yes when active | Eligible if configured | Config dependent | 150 | Capability-gated. |
| Wave 5 types | `WAVE`, `GHOST_PEPPER`, `COIN_FLIP`, `MYSTERY_POTION`, `DECOY`, `POWER_OUTAGE`, `UMBRELLA`, `RALLY_FLAG`, `DRILL_SERGEANT`, `PIGGY_BANK`, `BOUNTY` | Yes | Mostly test-only | Depends on row | Depends on drop pool | Seed-specific | Existing gated/experimental content. |
| Pocket Watch | `POCKET_WATCH` | Yes | Yes when active | Eligible if configured | Config dependent | 40 | Existing active non-test seed entry. |

## 3. Quicksand Current State

Quicksand is already a real powerup, not an unimplemented concept.

- Backend definition: `PowerupType.QUICKSAND`, catalog seed row, and `POWERUPS4_GATED_TYPES`.
- Purchase: available through the normal catalog/purchase route when its row is active and the client has the required capability.
- Race use: implemented in the normal redeem/use path.
- Effect logic: implemented and covered by `test/integration/quicksand-powerup.test.js`.
- UI artwork: `assets/images/powerups/quicksand.png` and `quicksand_thumb.png`; the frontend icon map includes it.
- Shop: appears when the backend row is active and capability filtering permits it.
- Daily Spin: eligible through the capability-filtered shop-row pool when `dailyRewardEligible` is true.
- Mystery boxes: not in the normal mystery-box drop pool because the store-only/drop-pool configuration excludes it.
- Tests: integration coverage exists for the race behavior and frontend coverage exists for the icon/race presentation.
- Hidden/incomplete: not inherently hidden or incomplete; live activation remains backend policy/database controlled.

The important distinction is that Quicksand is capability-gated today, not Gold-gated today.

## 4. Current Premium / Gold Item Architecture

Gold membership is determined by the backend primitive `goldMembershipForUser(db, userId)` in `src/modules/billing/queries/goldPolicy.js`. It checks the billing identity, active membership, and `benefitContract === GOLD_BENEFIT_VERSION`. Frontend `BillingScope`/billing snapshots consume the resulting state defensively.

Gold characters use backend policy to expose access/ownership state. The frontend renders lock/owned/equipped states, the Gold visual treatment, coin purchase or direct IAP actions, and persisted ownership. Membership and ownership are not inferred solely from a frontend boolean.

Reusable concepts:

- authoritative Gold membership helper;
- backend policy/catalog response;
- member pricing through `memberDiscount`, `priceFields`, and `pricedItem`;
- additive capability/policy fields parsed defensively by Flutter;
- shared premium visual treatment for lock/outline/upgrade CTA;
- durable ownership/inventory records.

Powerups differ from characters because powerups are quantities, can be redeemed into races, can arrive through multiple reward sources, and may already be held by users. That makes acquisition policy and use-after-expiry policy explicit product decisions rather than a direct copy of character ownership.

## 5. Powerup Purchase Architecture

The current purchase path is:

```text
Shop tile in `shop_tab.dart`
  -> `POST /shop/powerups/:sku/purchase`
  -> `purchasePowerupItem`
  -> active catalog lookup + member pricing
  -> idempotent coin debit (`PowerupPurchaseRequest`)
  -> atomic `UserPowerupItem` increment
  -> serialized inventory response
```

Rewarded unlocks use `unlockPowerupWithAds`, SSV grant verification, and their own idempotency/claim behavior. Gold already bypasses eligible rewarded-ad flows while preserving server-side caps and idempotency. The existing 15% Gold discount is applied centrally to powerup pricing through the member pricing helper.

Purchase is server-authoritative. A premium restriction should be added at the shared backend eligibility/purchase boundary, not only in the Flutter tile. The same restriction must cover coin purchase, rewarded unlock, and any other new-acquisition route.

## 6. Proposed Premium Powerup Access Rule

Use an additive backend catalog/policy field such as `requiresGold: true` or a richer `goldAccess` object on premium powerup catalog entries. Reuse `goldMembershipForUser` to compute the user-specific eligibility. A code-only set of premium powerup types would be a weaker fallback because the backend already owns product policy and catalog rows.

Recommended response semantics:

- Gold user: premium item is visible, priced normally through existing member pricing, and purchasable.
- Non-Gold user: premium item remains visible with `requiresGold` and an explicit unavailable/upgrade state; purchase and rewarded acquisition return a safe, typed eligibility error.
- Existing ordinary powerups remain unchanged.

Do not create a second `isPremium`/`isGold` source of truth in the client.

## 7. Shop UI

The powerup shop is rendered by `_storePowerupTile` and `_ShopTile` in `lib/screens/tabs/shop_tab.dart`. It displays art, name, owned quantity, current/base price, and a purchase/detail action. The current Gold discount is already rendered from backend price fields.

Premium powerups should use the same reusable premium visual abstraction as Gold characters/accessories: a compact outline or border plus a small `Bara Gold` label/lock state, adapted for the tile dimensions. The UI should derive premium state from the server catalog field, not from a hardcoded type list. Non-Gold purchase buttons should become an upgrade CTA or locked action while Gold users retain the normal purchase action.

## 8. Daily Spin Architecture

The current Daily Spin flow is backend-authoritative:

1. Flutter requests status and receives `powerupPool`, `accessoryPool`, `rarePrizeMix`, and `itemOdds`.
2. Flutter calls the claim endpoint before the animation.
3. The backend re-loads eligible pools, rolls rarity/prize kind, selects the item using weighted selection, grants the result, and records `DailyRewardClaim`.
4. Flutter receives the result and places it at a fixed reel position while the reel animation supplies visual decoys.

Relevant files are `getDailyRewardStatus.js`, `claimDailyRewardBox.js`, `claimExtraDailyRewardBox.js`, `dailyBoxOdds.js`, `daily_reward_screen.dart`, and `case_opening_strip.dart`.

The wheel/reel is therefore visual. It does not independently select a reward or encode authoritative probability. The result is known before animation, and the frontend cannot legitimately force a result.

There is currently a parity invariant between the shop powerup catalog and the Daily Spin powerup pool, covered by `daily-reward-box-shop-parity` integration tests. That invariant must change if free users see premium shop/spin entries while premium entries have zero eligibility.

## 9. Daily Spin Premium Rule for Non-Gold

The safest design is to separate display catalog from eligible reward pool:

- Display catalog: includes premium entries for non-Gold users, marked with premium styling.
- Eligible pool: excludes premium entries for non-Gold users.
- Gold eligible pool: includes premium entries normally.
- Backend RNG: selects only from the eligible pool and normalizes weights there.
- Flutter animation: continues to use the backend-selected result; it must not select a premium segment for a non-Gold user.

Simply adding zero-weight entries to the current pool may work mathematically, but it risks assumptions in pool validation, parity tests, rare-prize calculations, and analytics. Separate `displayPool` and `eligiblePool` fields are clearer and preserve the backend authority boundary.

The current fixed-result reel can support this design because the result is returned before animation. The UI should use display entries only for decoys and must never derive the selected result from a segment index.

## 10. Probability / Fairness Impact

For non-Gold users, premium entries must be removed before weighted selection. The remaining normal-item weights should be normalized, so their relative probability increases compared with a pool that included premium weights. Rare-prize mixes and `itemOdds` must be recalculated from the eligible set.

Affected areas include `dailyBoxOdds.js`, status payloads, claim logic, parity tests, reward analytics, expected-value documentation, and any UI that assumes the displayed list is the eligible list. The change must not silently preserve a denominator containing zero-probability entries.

## 11. Spin Result Security

A modified client must not be able to:

- submit a chosen premium result;
- claim a result not selected by the server;
- bypass Gold membership;
- call a grant endpoint directly with a premium type.

The backend must authenticate the user, compute Gold membership itself, choose the result itself, persist the claim/result, and grant only the selected eligible reward. Any generic/admin grant route must have an explicit policy for premium types. Client-supplied item IDs should be treated as display/request context only, never as authority.

## 12. Reward Fulfillment

Daily Spin fulfillment calls the normal `grantPowerupToUser` quantity path after backend selection and records a `DailyRewardClaim`. Selection-time eligibility is necessary but grant-time defense-in-depth is recommended: the claim transaction should verify that the selected item belongs to the eligible pool for the current user and that the claim has not already been fulfilled.

Existing idempotency/claim records should be reused. Do not create another generic Gold claim table without proving a missing idempotency boundary.

## 13. Membership Authority

Reuse `goldMembershipForUser` / `goldPolicyForUser` on the backend for:

- premium powerup shop acquisition;
- premium Daily Spin eligibility;
- premium visual state in serialized catalog responses;
- upgrade CTA eligibility.

The frontend `BillingScope` is a rendering snapshot, not an authorization source. No additional premium boolean should be introduced.

## 14. Hitchhike and Leech Migration

Both Hitchhike and Leech already have race behavior, art/copy, shop support, inventory support, and tests. Hitchhike is explicitly excluded from Daily Spin by `dailyRewardEligible: false`. Leech is marked store-only in the balance configuration, but its seed row does not explicitly set `dailyRewardEligible: false`; this should be resolved before premium classification.

Current ownership is quantity-based, not provenance-based. Therefore the compatible options are:

- A: existing inventory remains usable forever;
- B: existing inventory remains usable, but new acquisition requires Gold;
- C: existing inventory becomes locked after Gold expires;
- D: inventory is converted/refunded/removed.

Option B best preserves current ownership semantics and avoids destructive user impact: gate new acquisition, allow already-owned quantities to remain usable. This is a product decision, not something to infer silently. If C or D is chosen, provenance or migration logic would likely be required.

## 15. Quicksand Launch Semantics

Quicksand already needs no basic implementation launch. To make it premium, publication must be decided across:

- active shop catalog row;
- `powerups4` capability filtering;
- Daily Spin display and eligible pools;
- mystery-box policy, currently excluded by drop-pool configuration;
- race redemption/use, already implemented;
- analytics and admin catalog controls.

There is no separate public/private race catalog for Quicksand; race availability follows the normal powerup capability and use checks.

## 16. Mystery Box / Other Reward Sources

| Source | Can grant powerups? | Membership checked? | Premium rule needed? |
|---|---:|---:|---|
| Daily free spin | Yes | Not for Gold premium today | Yes: eligible-pool filtering and grant defense. |
| Extra/ad spin | Yes | Gold bypass exists, premium classification does not | Yes: same eligible-pool rule. |
| Shop coin purchase | Yes | No premium rule today | Yes: central purchase gate. |
| Rewarded/ad unlock | Yes | Gold ad bypass exists | Yes: acquisition gate before SSV/grant. |
| Mystery box | Race-scoped powerup grant | Capability/drop-pool rules, not Gold | Decide whether premium types remain excluded or can be Gold-only in race boxes. |
| Admin/direct grants | Likely yes through grant helpers | Depends on caller | Explicit admin/promo policy required. |
| Race rewards/events/onboarding | Possible through grant paths | Must audit each caller | Add premium policy if any source can grant new premium inventory. |

## 17. Inventory and Expiration

Today a user inventory row stores a quantity by type. It does not store Gold membership provenance. If Gold expires, an existing quantity naturally remains and the current race-use path would generally allow it because use checks inventory/capability, not Gold membership.

The least disruptive architecture is: Gold required for new premium acquisition; previously acquired quantities remain usable. If the intended behavior is to lock use after expiry, the current quantity model is insufficiently explicit and should be extended deliberately rather than adding an ad hoc use check.

## 18. Race Use Enforcement

For the recommended grandfathering policy, Gold membership is checked at acquisition, not at use. Race use still checks the normal inventory, race, capability, and effect rules. Checking membership again at activation would cause already-owned powerups to become unusable after expiry and would need a clear error/state model.

If product chooses subscription-bound use, enforce both acquisition and activation server-side, with tests for expiration, race-held items, and account changes. Never rely on the client to enforce either policy.

## 19. Premium Visual Treatment

Use one small reusable premium-style abstraction with variants rather than reusing a large character ribbon everywhere:

- shop tile: compact Gold outline/label and locked/upgrade state;
- Daily Spin segment: light/dark premium outline or border, no large ribbon that obscures the wheel art;
- paywall CTA: existing Gold card/upgrade styling;
- owned/available state: same border family with ordinary action controls.

The component should accept `isPremium`, `isLocked`, and theme context from server-derived state. It should not decide eligibility.

## 20. Analytics

Existing purchase, Daily Spin, reward-result, paywall, upsell, and powerup-use analytics should be located and extended with additive properties rather than replacing existing events.

Useful events/properties:

- premium powerup viewed: SKU, surface, Gold state;
- premium acquisition blocked: SKU, source, reason;
- premium spin segment displayed: SKU, Gold state;
- Gold premium spin win: SKU, source, membership contract;
- non-Gold premium spin excluded: SKU/pool version;
- Gold upsell from premium powerup: SKU, source, CTA result;
- existing purchase/use events: `isPremium`, `requiresGold`, and acquisition source.

Do not make analytics the source of eligibility.

## 21. Tests

| Area | Existing tests | Required new tests |
|---|---|---|
| Shop | Catalog gating, purchase, ad unlock, shop UI | Gold can buy premium; free sees premium but cannot buy; free CTA; normal items unchanged; 15% pricing behavior. |
| Daily Spin | Box powerups, shop parity, odds, screen tests | Gold pool includes premium; free display includes premium; free eligible pool excludes premium; normalized odds; forced-result attempts fail; claim replay is idempotent. |
| Inventory | Grant, purchase, redeem/use | Existing premium inventory behavior after Gold expiry; quantity and account fencing. |
| Race use | Hitchhike, Leech, Quicksand use/scoring | Acquisition-only vs activation policy, held-item behavior, capability compatibility. |
| Visual | Powerup icon and shop/widget tests | Premium outline/lock in light/dark themes; Daily Spin segment treatment; no art obstruction. |
| Quicksand | `quicksand-powerup.test.js` and icon tests | Premium classification does not regress existing effect/capability behavior. |

Follow the repository preference for integration tests through public HTTP/UI paths; use unit tests only for pure algorithms or structural guards.

## 22. Schema Assessment

No schema change is required if premium classification is a code/config policy and existing quantities remain usable after expiry. The cleanest extensible design is an additive catalog field, which likely requires a `PowerupShopItem` schema/migration change if persisted in the database.

Do not add a new ownership/provenance table merely to mark premium items. Add provenance only if the product chooses subscription-bound use, conversion/refunds, or differentiated grandfathering that quantity-only inventory cannot represent.

## 23. Exact Files Likely to Change

Backend, priority order:

1. `src/modules/billing/queries/goldPolicy.js` — reuse or extend shared policy only if required.
2. `src/modules/powerups/models/powerupShopItem.js` — serialize premium metadata.
3. `src/modules/powerups/queries/getPowerupShopCatalog.js` — premium display/eligibility state.
4. `src/modules/powerups/queries/getEligiblePowerupPool.js` — separate display and eligible pools.
5. `src/modules/powerups/commands/purchasePowerupItem.js` — block non-Gold acquisition.
6. `src/modules/powerups/commands/unlockPowerupWithAds.js` — block non-Gold premium unlock.
7. `src/modules/economy/queries/getDailyRewardStatus.js` and `src/modules/economy/commands/claimDailyRewardBox.js` — split display/eligible spin semantics and defense-in-depth.
8. `src/modules/economy/commands/claimExtraDailyRewardBox.js` — same policy for extra spins.
9. `src/modules/economy/dailyBoxOdds.js` — normalize eligible weights.
10. `prisma/schema.prisma`, seed/config, and a migration only if catalog metadata is persisted.
11. Related integration tests and analytics modules.

Frontend, priority order:

1. `lib/services/backend_api_service.dart` — defensive parsing for additive premium fields/pools.
2. `lib/screens/tabs/shop_tab.dart` and its tile/widget helpers — premium outline, lock, and CTA.
3. `lib/screens/daily_reward_screen.dart` and `lib/widgets/case_opening_strip.dart` — premium display styling without client-side selection.
4. `lib/widgets/powerup_icon.dart` / shared premium visual widget — reusable theme-aware treatment.
5. `lib/models` billing/catalog models if a typed field is introduced.
6. Focused shop, spin, catalog, and visual integration tests.

## 24. Product Decisions Still Needed

1. What happens to existing Hitchhike, Leech, and Quicksand quantities when Gold expires?
2. Should existing premium inventory remain usable after expiry? Recommended default: yes.
3. Can mystery boxes, events, admin grants, onboarding, or promotions grant premium powerups to non-Gold users?
4. Does the existing 15% Gold discount apply to premium powerups? The current pricing machinery supports it; confirm product intent.
5. What should the non-Gold CTA say: `Get Bara Gold`, `Unlock with Gold`, or another approved copy?
6. Should Daily Spin premium entries show only the premium outline, or also a lock/Gold label?
7. Should Quicksand become Gold-only now, or remain capability-gated/normal?
8. Should Leech remain eligible for Daily Spin? Current code/comments and seed metadata are inconsistent and need one decision.
9. Are premium powerups intentionally excluded from mystery boxes permanently, or should Gold users receive them there?

## 25. Recommended Implementation Architecture

1. Keep membership authority in `goldMembershipForUser`.
2. Additive backend catalog metadata identifies premium powerups; do not hardcode product policy in Flutter.
3. Return separate display and acquisition/eligible state where needed.
4. Gate all new acquisition routes server-side: shop purchase, rewarded unlock, Daily Spin, admin/promo grants, and any event paths.
5. Keep Daily Spin RNG backend-owned. For non-Gold users, display premium entries but select only from a normalized eligible pool. For Gold users, include premium entries normally.
6. Recheck eligibility and idempotency during reward fulfillment.
7. Preserve quantity-based existing ownership unless product chooses a different policy requiring schema/provenance work.
8. Reuse one compact theme-aware premium outline/lock abstraction across shop and Daily Spin; do not use a large ribbon on wheel segments.
9. Add integration coverage before implementation changes, especially for free-user exclusion and forced-result attempts.

This avoids frontend-only entitlement checks, duplicate Gold state, client-controlled spin eligibility, and unnecessary schema changes.

## 26. Final Handoff

- Current powerups are backend-catalogued, quantity-owned, server-purchased, and server-used.
- Hitchhike and Leech are implemented store-only types; Hitchhike is explicitly excluded from Daily Spin, while Leech needs a metadata/comment consistency decision.
- Quicksand is already implemented, capability-gated, shop-visible when active, Daily Spin-eligible when configured, and excluded from mystery-box drops.
- Premium classification should be an additive backend catalog/policy field backed by the existing Gold membership helper.
- Shop should show premium items to everyone, but block non-Gold acquisition with a server-authoritative upgrade state.
- Daily Spin needs distinct display and eligible pools so free users can see premium entries with zero selection probability.
- Existing quantity inventory supports the recommended grandfathered-use policy without a migration; subscription-bound use would require additional ownership/provenance design.
- Required security boundary is backend membership, RNG, fulfillment, idempotency, and grant validation.
- Likely changes span backend catalog/purchase/spin paths, Flutter catalog parsing/shop/spin visuals, and integration tests.
- Product decisions remain around grandfathering, reward sources, discounts, CTA copy, Quicksand classification, and Leech spin eligibility.

**READY FOR PRODUCT DECISIONS**
