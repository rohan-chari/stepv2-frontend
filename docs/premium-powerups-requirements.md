# Bara Gold Premium Powerups Requirements

## Summary & user story

Make Hitchhike, Leech, and Quicksand Bara Gold powerups. Every user can see
them in the shop and Daily Spin display, but only Gold users can acquire new
quantities. Existing quantities remain usable forever, including after Gold
expiry. Daily Spin selection remains backend-authoritative and excludes premium
items from the non-Gold eligible pool.

The implementation must preserve the existing 15% Gold discount, normal
quantity inventory, race effects, capability checks, mystery/race-box
exclusions, and older-client compatibility.

## Scope / non-goals

In scope:

- Backend-owned premium classification for `HITCHHIKE`, `LEECH`, and
  `QUICKSAND`.
- Shop visibility for all users, Gold-only new acquisition, and the
  `Get Bara Gold` upgrade path.
- Daily Spin display-vs-eligible pool separation and normalized odds.
- Defense-in-depth checks for shop purchase, rewarded unlock, Daily Spin
  claim, and extra spin.
- Flutter premium styling in shop and Daily Spin.
- Integration and frontend tests for security, eligibility, grandfathered
  inventory, and visual states.

Out of scope:

- App Store Connect, RevenueCat, subscription prices, Gold characters, or
  accessories.
- New mystery-box or race-box rewards.
- Removing, converting, refunding, or provenance-tagging existing inventory.
- Gold checks during powerup activation/use.
- Production deploy, TestFlight upload, commit, or push.
- A new entitlement, user premium boolean, or generic Gold claim ledger.

## Product rules

| Powerup | Internal type | Shop | Daily Spin display | Non-Gold Daily Spin eligibility | Mystery/race boxes |
|---|---|---:|---:|---:|---:|
| Hitchhike | `HITCHHIKE` | Yes | Yes | No | No |
| Leech | `LEECH` | Yes | Yes | No | No |
| Quicksand | `QUICKSAND` | Yes | Yes | No | No |

Gold users can acquire all three through the shop and receive them from Daily
Spin. Non-Gold users see them but cannot newly acquire them. Existing quantities
remain visible, redeemable, and usable regardless of current membership.

## API contract

### Shop catalog

The existing shop response remains compatible and gains additive fields on each
powerup item:

```json
{
  "sku": "hitchhike",
  "powerupType": "HITCHHIKE",
  "priceCoins": 128,
  "basePriceCoins": 150,
  "ownedQuantity": 1,
  "requiresGold": true,
  "goldEligible": false,
  "purchaseEligibility": "GOLD_REQUIRED"
}
```

For Gold users, `goldEligible` is true and `purchaseEligibility` is
`AVAILABLE`. For normal powerups, `requiresGold` is false and existing clients
can ignore all new fields. The exact existing envelope and item fields remain
unchanged.

`purchaseEligibility` is descriptive only; the purchase endpoint remains the
authority. Suggested values are `AVAILABLE`, `GOLD_REQUIRED`, and the existing
unavailable states where applicable.

### Purchase and rewarded unlock errors

Existing endpoints keep their request shape and idempotency behavior. A
non-Gold attempt to acquire a premium powerup returns the standard error
envelope with a stable typed code, for example:

```json
{
  "error": "Bara Gold is required for this powerup",
  "code": "GOLD_REQUIRED"
}
```

The endpoint must reject before coin debit, SSV grant, or inventory increment.
Gold purchase continues through the existing member-pricing and idempotent
inventory path.

### Daily Spin status

Keep the existing `powerupPool` field as the display pool for old clients and
additive compatibility. Add explicit eligibility metadata rather than making
the client infer it:

```json
{
  "powerupPool": [
    { "powerupType": "HITCHHIKE", "requiresGold": true, "eligible": false },
    { "powerupType": "POCKET_WATCH", "requiresGold": false, "eligible": true }
  ],
  "eligiblePowerupTypes": ["POCKET_WATCH"],
  "powerupOdds": {
    "POCKET_WATCH": 1.0
  }
}
```

The actual response should follow the repository's current item shape and
envelope. `powerupPool` includes all displayable active shop powerups,
including premium entries. `eligiblePowerupTypes` and `powerupOdds` describe
the user-specific actual selection pool. Odds are normalized after removing
premium entries for non-Gold users. Gold odds include premium entries.

Older clients ignore additive fields and continue receiving a backend-selected
result. The backend never trusts a client-selected result.

### Daily Spin claim

Claim requests remain unchanged; no result SKU or segment index becomes
client-authoritative. The server authenticates, recomputes membership, rebuilds
the eligible pool, selects the result, grants it, and records the existing
claim/idempotency record. Extra-spin claims use the same policy.

## Data model / migrations

Preferred implementation: no Prisma migration. Add a central backend policy
constant/helper for the three premium powerup types and serialize
`requiresGold`/eligibility as computed catalog metadata. This remains backend
owned without duplicating policy in Flutter.

Update seed/config metadata so Hitchhike and Leech are Daily Spin eligible and
all three remain outside mystery/race-box drop pools. Preserve the existing
quantity-based `UserPowerupItem` model. Do not add ownership provenance or a
new claim table.

If inspection proves persisted catalog metadata is required, use one additive,
default-safe `PowerupShopItem.requiresGold` field, default false, and mark only
the three intended rows. No destructive migration or unrelated catalog
backfill is permitted.

## Backend implementation plan

1. Add a shared premium powerup policy in the powerups domain, using the
   existing `goldMembershipForUser`/`goldPolicyForUser` authority.
2. Extend catalog serialization and `getPowerupShopCatalog` with additive
   premium and user eligibility fields.
3. Make `getEligiblePowerupPool` return/derive separate display and eligible
   pools. Keep premium items out of the non-Gold selection pool and normalize
   weights.
4. Enforce `GOLD_REQUIRED` before coin debit in `purchasePowerupItem`.
5. Enforce the same rule before rewarded-ad/SSV fulfillment in
   `unlockPowerupWithAds`.
6. Update daily status, free claim, and extra claim to use the user-specific
   eligible pool and defense-in-depth validation.
7. Set Hitchhike and Leech `dailyRewardEligible` true while retaining all
   mystery/race-box exclusions, including an explicit Quicksand exclusion if
   the current drop configuration relies on absence rather than metadata.
8. Leave redeem/use code unchanged except for regression coverage proving
   non-Gold users can use grandfathered quantities.

All powerup acquisition routes must be audited. Admin/event/promo grants must
either be explicitly allowed as privileged grants or reject premium grants
unless the product policy says otherwise; no accidental public grant path may
bypass Gold.

## Frontend implementation plan

1. Parse additive catalog and Daily Spin fields defensively. Missing fields
   mean ordinary legacy rendering; no unchecked casts or crashes.
2. Generalize the existing Gold premium visual treatment into a compact,
   theme-aware outline/marker usable by shop tiles and spin entries.
3. In `shop_tab.dart`, render premium state from backend metadata. Gold users
   retain the normal purchase action; non-Gold users get `Get Bara Gold` and
   navigate to the existing Bara Gold paywall.
4. In `daily_reward_screen.dart` and `case_opening_strip.dart`, keep premium
   display entries visible for all users, style them as premium, and continue
   animating only to the backend-provided result.
5. Do not add client-side item allowlists, probability selection, Gold
   authority, or mystery-box policy.
6. Handle missing additive fields from an older backend safely. A backend
   enforcement response remains authoritative if a client lacks premium
   metadata.

## Backward compatibility & rollout

Deploy backend first, then the app. The backend change is additive:

- Old clients ignore new response fields.
- Old clients may show a premium item as a normal tile, but backend purchase,
  rewarded unlock, and Daily Spin selection still enforce Gold.
- New clients tolerate an older backend missing premium fields without
  crashing; they must not invent a premium classification from local lists.
- Existing inventory and race-use behavior remain compatible.
- No feature flag or runtime toggle is needed; this is permanent policy.

## Test plan (tests first)

Backend integration tests:

- Gold shop visibility, discounted purchase, and inventory increment for all
  three premium types.
- Non-Gold visibility with `GOLD_REQUIRED`, no coin debit, no inventory
  increment, and rewarded-unlock rejection.
- Existing premium quantities visible and usable by non-Gold users.
- Daily display pool includes premium entries for both membership states.
- Non-Gold eligible pool and normalized odds exclude all three.
- Gold eligible pool and odds include all three.
- Client-chosen/forced result attempts cannot grant premium rewards.
- Claim replay remains idempotent.
- Extra-spin path follows identical eligibility rules.
- Hitchhike, Leech, and Quicksand remain absent from mystery/race-box pools.
- Existing Hitchhike, Leech, and Quicksand race-use/effect tests pass.
- Warm-cache and public HTTP paths expose the same policy.

Frontend integration/widget tests:

- Premium shop metadata renders in light and dark themes.
- Gold sees normal purchase; free user sees `Get Bara Gold`.
- Tapping the CTA routes to the existing paywall.
- Premium Daily Spin entries are visible and outlined to free users.
- Backend-selected normal and premium results animate correctly.
- No client-side probability or winner selection is introduced.
- Normal powerups remain unchanged.

Validation commands:

```bash
npm run test:integration -- <focused premium/shop/spin suites>
npx prisma validate
flutter test <focused shop/spin/Gold suites>
flutter analyze --no-pub
```

Integration tests must use the repository's dedicated test database/Redis,
never production.

## Acceptance criteria / definition of done

- Exactly Hitchhike, Leech, and Quicksand have `requiresGold` semantics.
- Gold discount remains centralized and applies to premium powerups.
- Free users see premium shop/spin content but cannot acquire it.
- Gold users can acquire it normally.
- Non-Gold Daily Spin never selects or grants premium items, with normalized
  actual odds.
- Gold Daily Spin can select premium items.
- Existing quantities remain usable after Gold expiry.
- Premium types remain excluded from mystery/race boxes.
- No new membership authority, entitlement, provenance, or claim ledger is
  introduced.
- Older clients remain safe against the additive backend response.
- Focused backend/frontend tests and static validation pass.
- No deploy, push, App Store Connect, or RevenueCat change occurs in this
  implementation task.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Bara Gold premium powerups**

*Elements under test:*

- Premium outline/marker added to powerup shop tiles.
- `Get Bara Gold` action shown in place of purchase for non-Gold users.
- Premium outline/marker added to Daily Spin display entries.

*Checklist*

1. **Shop — real screen** — Get there: open Shop → Powerups as a Gold and a
   non-Gold account. Verify all three premium tiles remain in the same grid,
   the outline does not cover artwork, Gold sees the purchase action, and free
   users see `Get Bara Gold`. Verify no duplicate marker appears.
2. **Shop — light/dark themes** — Get there: repeat the above in both theme
   modes. Verify border, label, text contrast, and CTA remain inside tile bounds.
3. **Daily Spin — real screen** — Get there: open Daily Rewards and inspect the
   reel before spinning. Verify premium entries are visible and marked, but no
   oversized ribbon obscures the art or changes reel geometry.
4. **Daily Spin — free account result** — Get there: claim several deterministic
   test spins through the test environment. Verify the animation lands on the
   backend result and never visually resolves to a premium result for free users.
5. **Tutorial/demo mirrors** — Get there: run first-launch/tutorial Daily
   Rewards or Shop previews if those fixtures include these surfaces. Verify
   missing premium fields do not crash the preview and no premium marker is
   duplicated by hand-copied tutorial chrome.

*Surfaces confirmed unaffected:* race powerup tray, race activation screens,
character/accessory tiles, and paywall layout are not changed by this feature.

*Risks found while planning:* the current Daily Spin/shop parity assumption
must be replaced by an explicit display-vs-eligible contract; Leech seed and
comments disagree about Daily Spin eligibility; the existing frontend reel is
visual-only and must remain so.

## Revision log

- Initial draft: converted the approved product rules into an additive,
  backend-authoritative contract with no ownership migration.
- Gap pass 1: added old-client behavior, rewarded unlock enforcement,
  grant-time defense, warm-cache consistency, and explicit Daily Spin odds.
- Gap pass 2: added Leech metadata cleanup, Quicksand drop exclusion review,
  admin/event grant audit, integration-first tests, and manual UI checks.
- Architect/game-balance/UI review: pending before implementation approval.
