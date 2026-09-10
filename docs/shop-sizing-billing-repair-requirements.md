> **Release resumed:** The owner added the Bara+ hold and outfit-editor changes,
> explicitly requested direct implementation, and authorized deployment afterward.
> The earlier build hold is superseded. Final verification covers the combined batch.

# Shop sizing, guidance and billing repair — 2026-09-10

## Summary and authorization

The owner requested fixing the shipped Shop: character cards must match Powerup
card sizes; every section needs a brief description, including character tap to
customize; unowned characters need a small lock indicator; unavailable coin packs
must be diagnosed and repaired. The screenshot also shows unavailable membership.
The owner explicitly instructed implementing these fixes and uploading another iOS
build to App Store Connect. That authorizes this scoped implementation/upload;
no repeat implementation approval is needed. New backend production mutations, if
required by diagnosis, must be made concrete and checked against current authority.

## Scope and design

Latest owner additions supersede membership visibility in the original repair:
Bara+ entry points and profile branding are commented out for easy restoration;
existing entitlements remain. The wardrobe now groups compatible accessories into
Owned and Unowned, removes Other owned items, and keeps Save outfit/Reset in a
persistent safe-area footer. See [restoration notes and manual UI checklist](shop-outfit-release-checklist.md).

1. Featured description: “Stock up on coins for powerups and accessories.”
2. Powerups description: “Buy powerups to use in races, or view the ones you own.”
3. Characters & Accessories description: “Tap a character to customize its outfit or unlock a new one.”
4. Character cards share the Powerups merchandise grid: identical widths, heights,
   insets, spacing and column count at the same viewport/text scale. Normal phones
   show three columns; narrow/large-text layouts use two; wide layouts are bounded
   to1000 logical pixels with five columns. Match card geometry and expand preview
   space while preserving each species' correct proportions and outfit fit.
5. Add a small, high-contrast top-right lock badge only when `character.owned` is
   false. Reuse the existing Home `Icons.lock_rounded` UI icon (no new raster asset
   is necessary). Keep the visible LOCKED status and existing accessible ownership
   label. Badge is decorative/noninteractive; taps still reach the card. Owned and
   active cards have no lock, retaining their statuses and active border.
6. Preserve the current buy/unlock sheet for purchasable unowned characters and
   outfit/action menu for owned ones, including existing unavailable/unsupported
   behavior. Do not change prices, ownership rules or outfit data.
7. Billing repair must address the demonstrated cause, not fake availability,
   hardcode localized prices, grant client-side value, or bypass realm/identity
   checks. Membership and coin offers remain independently renderable where their
   valid product data is available. Existing signed build13 already contains the
   intended public RevenueCat SDK key; verify native store and backend evidence.

## Existing code and implementation path

- `lib/screens/tabs/shop_tab.dart:1889` `_buildSectionHeader`: add theme-aware
  readable description below each heading, preserve section keys/anchors.
- `lib/screens/tabs/shop_tab.dart:1924` `_buildCharacters`: replace compact-only
  grid geometry with shared Powerups geometry; update character loading skeleton.
- `lib/widgets/shop_product_grid.dart:4`: shared responsive merchandise grid;
  avoid separate copied character sizing rules and keep unrelated coin grids stable.
- `lib/widgets/shop_character_card.dart:6`: badge, enlarged responsive art area,
  readable name/status and preserved tap behavior/semantics. No animal distortion.
- `lib/widgets/coin_pack_offers.dart`, `lib/services/live_billing_controller.dart`,
  `lib/services/store_billing_client.dart`: diagnose/repair real catalog loading.
- Existing real-screen tests: `test/shop_continuous_sections_test.dart`,
  `test/full_screen_shop_test.dart`, `test/character_wardrobe_screen_test.dart`,
  billing component/controller/native-boundary suites. Add focused failing tests
  before implementation. Do not weaken existing assertions.

## API, data model and compatibility

UI additions require no API changes, migrations or backend fields. Ownership reads
already default false. Existing endpoints, prices, product IDs, realm isolation,
transaction idempotency and authoritative backend fulfillment remain unchanged.
Billing contract is unchanged: keep bara-billing-v1 and all existing products/IDs.
Diagnosis confirmed native category/trial failures currently discard all products;
repair isolates categories and makes trial eligibility optional (no advertised trial
on lookup failure). Backend configuration and both RevenueCat keys verified. ASC
6000-coin product lacks localization; correct existing-product metadata without
changing price, amount or identifier. All-product failure remains diagnosable and
unavailable, never replaced with fictional offers. Paid Apps Agreement/bank/tax and
actual native StoreKit results were checked: by12:44:11UTC AppleStoreKit and
pinnedRevenueCat both returned allfive realproducts/prices, with eligibilityreturning
successfully. No paid purchase or fulfillment was performed. The missing6000
localization propagated between12:39and12:44UTC; normalbackendbootstrapavailabletrue.
Never assume missing/partial backend or store data is successful availability.
Old app binaries remain supported. No feature flag or rollout toggle is added.
A new local UI lock icon is supported on both platforms and has no catalog entry.

## Tests and acceptance

- Pump real Shop at normal/narrow/wide widths and large text: character and Powerup
  tile rectangles match; labels and descriptions wrap without overflow.
- All three descriptions present under the correct heading. Section scrolling,
  coin focus, inventory selector, tutorial/preview anchors continue to work.
- Owned/default/active character shows no lock; purchasable and unavailable unowned
  characters show one lock. Accessible status remains correct. Taps still open the
  correct existing flow. Test through the actual card/screen.
- Billing: reproduce diagnosed failure at the real public boundary before code
  changes; prove available data appears and checkout still uses server-approved
  products/native prices. Failures remain retryable without cross-account leakage.
- Preserve pending purchases, restoration and realm guards; never perform a real
  paid purchase without explicit authorization.
- Clean Flutter analyze, appropriate targeted and full Flutter tests, independent
  review. Build matching production iOS2.3.13(14) and Android2.3.13/203144 using all
  README defines; verify signatures, fresh AOT, both Meta defines only on iOS,
  exact art/config and seven retained iOS ad units. Upload iOS with existing local
  ASC env references; no App Review submission or customer release.
- Do not claim billing fixed solely from mocked store products or a green build:
  include evidence from actual backend/store product configuration or native SDK.

## Revision log

- Gap pass1: equal sizes means complete grid/card rectangles, not stretched animal
  sprites; matched loading geometry and large-text behavior included.
- Gap pass2: locked indicates unowned rather than untappable; badge must not block
  buy/customize flows. Existing lock icon avoids an unnecessary new art dependency.
  Coin and membership failure must be traced independently of UI appearance;
  simulator/fake catalog evidence cannot establish live store availability.

## Architect review

UI approved: no required changes. Preserve tall-accessory compositor and explicitly
check Settings tutorial, billing preview and coin-focused entry. Billing contract
and resilient native-loading amendment approved in follow-up review. Cache must
contain only fresh successful products; test both category failure directions.
No claim of outage recovery without actual store evidence.

## Billing implementation details

Fetch non-subscription and subscription categories independently. If one fails,
retain valid products from the other; fail if all requested categories fail.
Initial native catalog loading must render a loading state instead of an immediate
unavailable message, without overwriting in-flight purchase/reconciliation state.
Trial eligibility is optional: retain fetched products and conservatively advertise
no trial if it fails. Preserve native product cache/serial access, identity generation
checks, and server-authoritative checkout. Diagnostic messages identify only stage
and sanitized native error code, never token/customer/receipt/error payloads.
Tests pump actual product UI with real LiveBillingController/RevenueCat adapter
and mocked native channel: category partial failure; eligibility failure; all failure;
retry recovery; identity switch. No new backend endpoint or runtime change planned.

Apple reference: https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox

User authorization is the explicit fix-and-upload request. Reuse existing UI lock;
no new artwork is required. No product prices or coin amounts are changed.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Shop sizing and guidance**

*Elements under test:*
Character cards expand to the same grid and card dimensions as Powerups.
Descriptions appear beneath all three section headings.
Unowned characters gain a small top-right lock badge.
Recovered coin offers change Featured’s height and scroll targets.

*Checklist*

1. **Surface:** Real full-screen Shop
   **Get there:** Home → Shop, using an account with both owned and unowned characters.
   **Verify:** Featured → Powerups → Characters & Accessories remain in order. Each description sits directly below its heading, above its content. Character and Powerup cards have matching widths, heights, spacing and outer margins; the old compact character row is gone. Character images, names and statuses fit inside their cards.

2. **Surface:** Character cards and their destinations
   **Get there:** Shop → Characters & Accessories → tap an owned character → Edit outfit; return and tap an unowned character.
   **Verify:** Each unowned card has one top-right lock; owned/active cards have none. Locks do not cover artwork, names or status. The character menu, wardrobe and existing purchase sheet remain fully visible, including their close/back and bottom actions. Return to Shop without duplicate cards or overlays. No purchase is needed.

3. **Surface:** Coin-focused Shop and membership panel
   **Get there:** Home → coin balance “+”; then scroll down and use the Shop header “+”. Open the Featured Bara+ row.
   **Verify:** Both coin shortcuts bring the coin offers into view after loading, without hiding them behind the header. Featured content and subsequent headings do not overlap when offers appear. Bara+ opens one panel with reachable close and bottom controls; closing it leaves one Shop screen beneath.

4. **Surface:** Shop tutorial
   **Get there:** Profile → Settings → Help & Legal → View Shop Tutorial; also check first Shop entry on an account that has not completed this tutorial.
   **Verify:** The Featured spotlight still targets Featured after the description is added. The character spotlight scrolls to and surrounds the enlarged default-character card. Coach text/buttons stay on-screen and do not obscure the target. Descriptions and cards appear once, with no leftover compact row.

5. **Surface:** Responsive Shop on iOS and Android
   **Get there:** Repeat the Shop scroll on a normal phone, a narrow phone or largest system text setting, and a tablet; check both light and dark modes.
   **Verify:** Both merchandise sections use matching columns: three normally, two for narrow/large-text layouts, five on wide layouts. Descriptions wrap above their content; badges remain inside cards; bottom cards and actions remain reachable. No horizontal clipping, overlapping rows or duplicated headings.

6. **Surface:** Billing preview mirror, on a developer-provided preview build
   **Get there:** Billing preview → Shop/Get Coins/Bara+ entry → Open Shop; switch day/night using its controls.
   **Verify:** The shared Shop shows the same descriptions and enlarged character layout. Coin-focused entry lands on offers; membership-focused entry opens its panel without misplaced or duplicated Shop content.

*Surfaces confirmed unaffected:*

- General tab tutorial: renders Home and its Shop button, not the Shop merchandise layout; its `home.shop` spotlight remains on the unchanged Home button.
- Demo race tutorial: renders race/create/invite screens, not Shop cards or section headings.
- Character wardrobe: separate accessory layout; it does not reuse `ShopCharacterCard`. Its navigation placement is checked above.
- Standalone `GetCoinsScreen` and `BaraPlusScreen`: no active constructor call sites found; current Shop uses embedded coin offers and `BaraPlusBody`, covered above.

*Risks found while planning:*

- Shop tutorial anchors use `shop-section-featured` and `shop-character-default`; added description height and larger cards can misalign the spotlight or its scroll position.
- Settings’ Shop tutorial explicitly disables billing, so its Featured height can differ from the live Shop. Check both surfaces.
- Recovered coin offers can change Featured’s height after initial navigation; verify coin focus after loading settles.
- Billing preview uses separate fixture data. Missing locked-character fixtures cannot count as a successful lock-placement check.
