# Gold Character Purchase Sheet and Animated Preview Requirements

Status: draft — awaiting explicit approval before implementation

## Summary & user story

As a non-Gold user browsing Characters, I can tap an unowned Gold character
such as Mouse, Hedgehog, Sea Lion, Turtle, or Corgi and see the normal bottom
purchase sheet. The sheet offers the server-configured coin price and an
Upgrade to Bara Gold action. The character art in that sheet is the same
accessory-free walking animation used by the edit/wardrobe screen.

## Current evidence and root cause

- `lib/screens/tabs/shop_tab.dart:_characterCard` only supplies `onBuy` when
  `row.canPurchase` is true.
- Gold-exclusive rows intentionally set `canPurchase: false` for non-Gold
  users, even though their catalog row still contains a valid `priceCoins`
  quote.
- `lib/widgets/shop_character_card.dart` therefore renders the generic
  `Unavailable` strip and never opens `_openStoreCosmeticSheet`.
- Production PM2 logs show `BILLING_UNAVAILABLE` messages but no corresponding
  mouse purchase request, consistent with the client rejecting the action
  before a purchase is attempted.

## Scope / non-goals

In scope:

- Route non-Gold taps on eligible Gold-exclusive characters into the existing
  bottom purchase sheet.
- Show the configured coin option and an Upgrade to Bara Gold option.
- Reuse the existing edit-screen bare walking animation for every character
  purchase preview.
- Add integration/widget coverage for locked Gold characters and preview art.

Out of scope:

- Changing Gold eligibility, character prices, billing products, or backend
  purchase authorization.
- Granting access or ownership from the client.
- Replacing existing owned-character wardrobe behavior.

## API contract

No endpoint changes are required. Continue consuming the additive
`GET /shop/characters` fields defensively:

- `goldExclusive: true` identifies the server policy classification.
- `canPurchase` remains authoritative for whether a coin purchase may execute.
- A valid `item.priceCoins` is displayable only; the client must not infer
  purchase authorization from it.
- `directPurchase` and membership policy remain server/billing-owned.

If `priceCoins` is absent/invalid, the sheet must show the existing unavailable
price state and must not invent a price or enable a coin purchase. If the Gold
membership action is unavailable, the sheet remains dismissible and does not
claim that membership checkout succeeded.

Older backends and older clients remain compatible because no response field
is removed or repurposed and no new request is required.

## Frontend plan

1. Extend the character-card action routing so a non-owned row with a valid
   server price can open the existing `_openStoreCosmeticSheet` even when
   `canPurchase` is false, but only for the Gold-exclusive/non-Gold policy
   state. Keep `canPurchase` as the guard for the actual coin operation.
2. In the sheet, render a coin option using the row's configured `priceCoins`
   and an Upgrade to Bara Gold action that opens the existing membership
   details flow. Do not bypass the existing confirmation, ad-funding, or
   server purchase path.
3. Extract or reuse the wardrobe/edit-screen walking-character renderer with
   no accessories and the character's server-provided asset key. It must work
   for all supported characters, including remote-first assets, with the
   existing safe fallback when an asset is unavailable.
4. Preserve existing preview behavior for accessories and existing owned or
   Gold-accessible character rows.
5. Keep both iOS and Android behavior identical at the Dart layer.

## Test plan (tests first)

- Real Shop widget test: a non-Gold Gold-exclusive Mouse row with a valid coin
  quote opens the bottom sheet instead of rendering only `Unavailable`.
- Real Shop widget test: the sheet displays the configured coin amount and
  Upgrade to Bara Gold, while the coin action remains disabled unless the
  server says `canPurchase`.
- Real Shop widget tests for missing/null/invalid price and missing membership
  policy prove safe unavailable behavior.
- Real purchase-preview widget test for Corgi, Turtle, Mouse, Hedgehog, and Sea
  Lion verifies the bare walking animation renderer is used and accessories
  are absent.
- Run targeted Flutter tests, `flutter analyze`, then the full Flutter suite;
  existing unrelated failures must be reported, not weakened.
- Run the required UI-placement manual checklist across the real Shop,
  Settings/tutorial entry points, narrow layouts, both themes, and both
  platforms.

## Backward compatibility and rollout

This is frontend-only and additive. No backend deploy is needed. Build iOS and
Android in lockstep using the README release commands after validation. The
existing production backend remains compatible with old app versions.

## Acceptance criteria / definition of done

- Rohan/non-Gold can tap Mouse and sees a bottom sheet with the configured
  price and Upgrade to Bara Gold rather than the generic unavailable message.
- Turtle and every other supported character follow the same path.
- Coin purchase is offered only when server policy authorizes it; no local
  entitlement or balance mutation occurs.
- Purchase-sheet art is the accessory-free walking animation used by edit for
  every supported character.
- Targeted tests pass, `flutter analyze` is clean, both platforms build, and
  the verified iOS build is uploaded to TestFlight after the matching Android
  artifact is built.

## Revision log

- Gap pass 1: separated display eligibility from purchase authorization so
  `canPurchase: false` cannot suppress the Gold upgrade sheet.
- Gap pass 2: added malformed/missing quote and remote-art fallback behavior;
  preserved older-client and backend-owned-policy constraints.
- Architect/UI review: pending tool availability and explicit approval.

## Manual UI-placement test plan

Pending UI-test-planner review. At minimum verify real Shop Characters for
Mouse, Turtle, Corgi, Hedgehog, and Sea Lion in light/dark themes, narrow and
large-text layouts, plus the Settings-launched Shop tutorial and any retained
Shop preview surfaces. Confirm the bottom sheet is the only overlay, the
walking preview is bare, and back/dismiss returns to the same character grid.
