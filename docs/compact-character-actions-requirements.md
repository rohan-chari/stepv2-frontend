# Compact character shop actions

## Summary and authorization
The user requests direct compact character-card Edit/Equip/Buy actions, gold
coin prices instead of LOCKED for unowned characters, TestFlight upload, and
replacement App Review submission including the new coin packs. These adapt
existing interactions. The explicit implement-and-submit instruction authorizes
this scope; no additional release approval is needed.

## Scope and frontend plan
Use the existing parchment/pixel/gold shop design. Replace the 44px full-width
Edit pill with visually compact price-tag-sized actions. Owned inactive cards
show Edit and Equip; active cards show Edit and an active/equipped indicator.
Unowned purchasable cards show Buy and the actual server price with gold coin
icon. Remove the intermediate owned-character menu. Buy opens the existing
purchase confirmation flow; Edit opens the real wardrobe; Equip calls the
existing guarded activation flow. Preserve adequate touch targets, semantic
labels, busy/session guards, tutorial mirrors, and large-text readability.

Files: lib/widgets/shop_character_card.dart and lib/screens/tabs/shop_tab.dart;
real-screen tests in test/character_wardrobe_screen_test.dart and related shop
suites. Update obsolete menu-navigation tests mechanically while retaining
behavior assertions. Add failing regression tests before changing behavior.

## API, data, compatibility
No new endpoints, parameters, economic values, catalog rules, or migrations.
GET /shop/characters already supplies item.priceCoins and canPurchase,
canEdit, canActivate, owned, active and outfit/appearance revisions. Use
wardrobeCoinPrice to reject absent/malformed quotes, preserve valid zero.
Server policy remains authoritative. Missing quote or eligibility disables
purchase with an unavailable state. No invented price or local SKU rules.
Existing PUT /shop/active-character and purchase/outfit APIs stay unchanged.
Both iOS and Android use the same Dart changes; old apps remain compatible.

## Implementation and validation
Backend agent verifies the current contract without changing product policy.
Frontend agent implements tests first, then direct actions and compact layout.
Run relevant real-widget tests and clean flutter analyze, then independent
code review and hand over manual mirrored UI checklist.
Build signed iOS and Android from the same source using README production
configuration. Upload iOS to TestFlight, wait for VALID/IN_BETA_TESTING and
existing tester group membership. Replace the waiting app-review build with
this build and explicitly include all three current coin packs (500, 3000,
7500), verifying submission items and states. Preserve manual customer release.
Bara+ draft products remain outside the enabled coin-pack flow; do not invent
missing product metadata. Preserve existing prices and store identifiers.

## Acceptance
Unowned turtle displays server gold price and Buy. Owned cards offer direct
compact Edit/Equip with no intermediate menu. Repeated switches retain outfits.
No duplicate writes on rapid taps; stale sessions cannot mutate. No overflow at
supported narrow widths/large text. TestFlight and App Review include the exact
verified build; all three coin packs verified in submitted review items.

## Revision log
Pass 1: clarified purchase confirmation remains and zero/missing-price handling.
Pass 2: added stale-session/busy guards, mirrored tutorials, exact IAP readback,
paired Android artifact, and manual customer-release preservation.

## Architect requirements
Legacy/unsupported rows must not invent purchase eligibility from !owned:
require explicit legacy server purchase policy and a valid quote, otherwise
show unavailable. Cover absent policy and absent/malformed price in widgets.
Use separate at least 48x48 hit targets around compact visuals and avoid
nested/card-level button semantics when only child controls perform actions.
Tutorial guidance must name the new direct actions; preserve measured card key.

## Manual UI-placement test plan
Repeat on iOS and Android, including a narrow phone and increased text size.
1. Home → Shop → Characters: unowned Turtle shows gold price and Buy under
   artwork/name; owned cards show compact Edit/Equip and active status. No
   oversized buttons, duplicate prices, clipped controls or overlapping cards.
2. Tap Edit and return, then Equip; tap Turtle Buy without completing purchase.
   Customization and purchase open directly, Equip has no intermediary menu,
   and tapping the card never opens the old Edit outfit / Use character menu.
3. Home → coin-balance + → Characters: same price and controls once per card.
4. Settings → View Shop Tutorial → character step (also first shop entry on a
   fresh account): spotlight includes resized Capybara controls, coach chrome
   does not obscure them, wardrobe tutorial/return leaves no duplicate menu.
5. Billing preview build → Shop → Open Shop → Characters, then Coins → Open
   Shop: fixture characters match compact controls and unowned price placement.
Demo race/prologue and tab/onboarding tutorial do not render character cards;
wardrobe accessory grid is separate. Physical-device checks are handed to the
user, not claimed as automated device verification.

Backend contract verified unchanged. Architect fallback-policy requirement
incorporated; economy review SOUND with no changes to prices or rewards.

Final review revisions: compact buttons expose semantic tap actions; purchase
confirmation closes and rejects retained callbacks after identity changes and
rechecks current server policy. Character-specific minimum width applies to
the actual column count (including600px tablet breakpoint), preserving48px
action targets and artwork space. Existing merchandise grids retain geometry.
