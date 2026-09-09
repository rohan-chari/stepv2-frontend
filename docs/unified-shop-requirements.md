# Unified Bara shop

> Navigation revision for build 6: the user replaced the separate Featured/Items selector with Featured in the existing Store category row. See [the approved revision](shop-featured-category-revision.md); this document records the original build 5 design.
Status: approved by user; architect required changes incorporated; implementation and TestFlight upload authorized.

## Summary and user story

As a player, I want one recognizable storefront for all real-money purchases so I can compare coin packs and Bara+ without moving through unrelated earning screens. Replace the scattered presentation with an illustrated, framed shop inspired by the hierarchy of the supplied Clash Royale reference, using Bara's existing green, cream, gold and pixel typography.

## Evidence and current flow

- `lib/screens/tabs/home_tab.dart:1428`: balance + pushes GetCoinsScreen. Home already offers rewarded coins and referral access.
- `lib/screens/get_coins_screen.dart:271`: coin packs and Bara+ sit above ad, referral and daily reward cards.
- `lib/screens/tabs/shop_tab.dart:1514`: Shop currently renders dressing room/store/inventory controls and an inserted Bara+ promo. Its balance + and insufficient-funds routes also push GetCoinsScreen (`:3005`).
- `lib/screens/main_shell.dart:4794`: Shop is a pushed page from Home, not a main-shell bottom tab. Preserve this navigation structure.
- `lib/screens/tabs/profile_tab.dart:275`: another Bara+ promotion.
- `lib/widgets/coin_pack_offers.dart`: vertical text rows with Material paw icons.
- `lib/screens/bara_plus_screen.dart`: existing trial, permanent, subscription management, restore, legal and pending-purchase behavior.
- `lib/models/billing.dart:19` and backend `src/modules/billing/catalog.js`: current packs are 500, 2,800 and 6,000; no 28,000 product. Do not reinterpret or repurpose a product identifier.

## Scope and proposed layout

1. One Shop destination with top-level Featured and Items selectors. Featured is the purchase storefront. Items preserves existing Store/Inventory and Powerups/Characters/Accessories controls and dressing room. Do not rename all item shopping to Cosmetics: powerups and characters must remain discoverable.
2. Opening Shop normally shows Featured; Home + opens Featured focused on Coins (confirmed by user). A Shop-local balance + selects Coins in place. Insufficient-funds purchase links select Coins without stacking duplicate shops; returning to Items preserves the selected item and outfit preview.
3. Featured: compact SHOP header and balance, a full-width Bara+ feature panel, COINS heading, three illustrated pack tiles in a consistent two-column grid; wrap to one column for large text or narrow widths. Keep the same card sizing for all coin offers, including the last single tile. Clear amount above artwork and localized price button below; no faux scarcity, invented discounts or unrelated earning cards.
4. Bara+ panel shows member state or a succinct offer summary. Tapping expands the existing membership content within the Shop route, with plan choice, benefits and confirmation CTA. Refactor the current BaraPlusScreen content into a reusable embedded body without duplicating its purchase/management state machine. All real-money checkout starts here. Existing standalone BaraPlusScreen may remain as an internal/test wrapper, but app navigation must route to this shared Shop content.
5. Remove the Profile upsell panel; retain a quiet Membership entry leading to this same shop section for status/management, including expired and permanently owned memberships with a separate renewing subscription.
6. Retire Get Coins from all app navigation, including Shop shortfall routes and billing preview. Keep existing screen implementation temporarily only if protected tests depend on it; do not leave it reachable as a second purchase hub. Ads remain on Home; retain independent referral and daily reward entry points and verify they remain reachable without the old page.
7. Match existing AppPalette and PixelText in both themes. Framed cream product cards on green, gold price buttons, strong silhouettes, restrained pressed-state motion. No imitation Clash Royale logos, season currency, timers or blue awning. Hand-code UI chrome only.

## Artwork

Generated concept preview: [coin-sacks-concept.png](design/unified-shop/coin-sacks-concept.png). Built-in imagegen; white-background preview, not production assets. Visual critique: strong plain gold coin silhouettes and progressive spill; final assets need transparent backgrounds and size checks.

Concept prompt: “Create a single art direction concept sheet for Bara, a cozy pixel-art capybara walking game. White background, three separate coin sacks arranged left to right with ample whitespace between them, no text. Small tan burlap pouch with a few gold coins visible; medium larger open burlap sack filled with gold coins and several spilling at base; largest bulging open burlap sack with an extravagant mound of gold coins overflowing from its mouth and spilling into piles around it. Consistent chunky retro pixel art, clearly visible large square pixels, bold continuous black silhouette outlines, warm earthy tan and golden yellow palette, simple soft stepped shading. Three-quarter product view appropriate for shop tiles, not wearable accessories. Coins plain embossed rims, absolutely no paw print or animal symbol, no currency symbols. Each silhouette must read strongly at 100px wide. No photorealism, no smooth vector or 3D render, no decorative scene. This is a preview sheet for choosing artwork style, not final sliced app assets.”

Use built-in imagegen; concept sheet first, then separate generated small/medium/large transparent PNG assets under `assets/images/shop/` after critique. Small pouch: a few visible coins. Medium sack: fuller opening and spill. Large sack: a conspicuous mound overflowing and pooling at the base. Plain gold coins, no paw icon. Match chunky pixel art and black outlines; these are product illustrations, so wearable side-profile placement rules do not apply. Inspect on white and green at actual tile size and verify alpha/no clipping. Register the asset directory in pubspec. Add editable Aseprite sources/export wiring using local machine paths only outside committed files. No cosmetic catalog records: these are bundled UI assets, not equippable/server catalog content.

## API contract and data model

No endpoint, request, response, database, migration, product ID, price, entitlement, reward or economy change is proposed. Reuse BillingController, LiveBillingController and the existing `/billing/bootstrap?platform=…` and `/billing/sync?platform=…` contract unchanged. Backend remains authority for balances/entitlements; store adapter remains authority for localized prices. No new network path or polling loop. Use the existing shared billing scope; no controller per tile or per section.

Actual offers drive amount, price and availability. Unknown/new offer IDs use a generic sack fallback without inventing an amount. Preserve backend/store intersection filtering. Do not display preview prices in live unavailable states. Stable offer-to-art mappings for the known pack IDs; no quantity derived from the image. User confirmed 28,000 was a typo for 2,800; existing 500/2,800/6,000 packs remain unchanged.

Economy review: SOUND for UI-only scope. Direct mint/sink delta is zero at unchanged purchase volume; any conversion-driven issuance change is unmeasured. Do not carry preview-only BEST VALUE/EXTRA COINS labels into live offers without verified localized price comparisons. Never label the 2,800 grant as 28,000. Preserve shared checkout exclusion and authoritative reconciliation.

## Frontend implementation path (after approval)

1. Backend agent verifies unchanged contract and catalog; locks no-change API contract. No deployment or environment mutation.
2. Frontend agent writes failing real-widget navigation/layout tests before logic. Inspect protected tests; retain assertions, surface conflicts instead of silently deleting or weakening them.
3. Add a Featured/Items selection and optional initial focus to ShopTab. Keep existing Store/Inventory logic inside Items. Separate the current header so the dressing room cannot push Featured purchases downscreen. Preserve item selection, refresh and ad-unlock behavior.
4. Refactor BaraPlusScreen into a reusable membership body and embed under the Featured panel. Route existing BaraPlusCard/management entry points to Shop. Preserve all trial and renewal disclosures, including permanent purchase not cancelling an existing subscription, plan changes and legal links.
5. Redesign CoinPackOffers as adaptive illustrated tiles, retaining buyCoins, per-operation messages, busy exclusion, pending refresh and success reconciliation. Supply approved bundled images. Avoid stale feedback after account switching or navigating away.
6. Rewire Home/main shell, Profile, Shop shortfall and preview routes. Review all `GetCoinsScreen`, `BaraPlusScreen`, `BaraPlusCard` references. Refresh auth balance through existing reconciliation; do not grant coins optimistically.
7. Update billing preview app (fake services only), including its separate Get Coins and Bara+ page-selector destinations, settings shop tutorial replay and any demo fixtures. Explicit Coins/Membership entry takes precedence over automatic first-visit tutorial; defer that tutorial until normal Shop/Items entry. Normal first visit with tutorial due and Settings replay start Items so all four spotlight targets mount. Tutorial Home/Profile share real widgets under disabled billing below their Navigator; suppress unavailable preview navigation callbacks or supply complete fake Shop catalog/bootstrap reads and explicitly propagate disabled billing to any pushed route. Do not let a missing callback fall through to live navigation. A preview/tutorial must never inherit live billing or navigate into live checkout.
8. Run required widget tests and flutter analyze; then code-reviewer review. Account for both platforms and themes. Build/verify matching platform artifacts and upload the iOS archive to TestFlight as explicitly authorized by the user. No App Review submission or customer release.

## States, compatibility and rollout

- Initial loading: tile skeletons and accessible progress; no invented purchasable offers.
- Missing BillingScope, unavailable platform, failed bootstrap or empty products: a clear unavailable/retry state within Featured; Items continues working. Show only verified membership management where supported. Rendering should observe billing availability changes. Evaluate membership and coin section availability independently: controller.isAvailable can mean either packs or plans exist.
- Busy/pending: prevent duplicate checkout across all Shop products; show pending status and existing refresh action. Cancellation is recoverable, failures actionable; keep verified balance until sync succeeds.
- Restore, legal links and applicable membership management remain reachable. A cancelled renewal with remaining access and permanent ownership plus a recurring subscription must retain their current semantics.
- Backend remains unchanged, so frozen iOS/Android apps continue to use existing billing and legacy shop APIs. New frontend relies only on current defensively parsed contracts. No rollout flags or catalog `testOnly` changes required for local UI artwork. If backend changes become necessary, stop and revise the contract; backend deploy precedes app.
- Run platform-independent widget checks for iOS and Android billing availability. Build both platforms when preparing the authorized TestFlight release artifacts; Android native checkout remains unavailable under its existing unconfigured store state.

## Tests first

Architect identified four intentional navigation expectation conflicts: `test/get_coins_screen_test.dart:517`, `test/main_shell_nav_order_test.dart:1435`, `test/home_rewarded_coins_test.dart:357`, `test/tutorial_rewarded_ad_isolation_test.dart:59`. User-approved removal of Get Coins requires updating those destination assertions to the new Shop flow. Preserve their substantive token-refresh, ad-allowance, claim-count and tutorial-isolation assertions via the new Home/Shop path; keep standalone legacy-screen coverage. This is a specified behavior migration, not permission to weaken or delete assertions. Surface any further conflicts before changing them.

Existing item-specific Shop fixtures may explicitly select `ShopFocus.items` to preserve their original precondition under the new Featured default; keep all item assertions and cover the new default in separate navigation tests.

- Pump Home, tap balance +, assert intended Shop section and absence of old Get Coins hub; check Home ad/referral/daily reward paths remain reachable.
- Pump actual Shop: Featured/Items switching, shortfall route, preserved selected item/inventory, and all current item/ad unlock behavior.
- Real product tiles render supplied localized prices and quantities, increasing artwork tiers, unknown-offer fallback; tapping uses correct offer. Busy blocks all other purchase actions; pending, cancel, failure and success remain usable.
- Membership embedded in Shop covers new, trial, active, expired, permanent and permanent-plus-renewing states; restore, disclosures, legal/management links and plan changes retain existing protected coverage.
- Missing scope/empty products/unavailable Android and refresh-to-available work without live sample prices or crashes.
- At 320px and 390px widths, large text, both themes and bottom safe insets, controls remain visible and no RenderFlex overflow occurs.
- Billing preview and tutorial replay maintain no-network isolation, correct spotlight mounting and no real purchase access.

## Acceptance criteria

All app purchase entry points converge on Shop; Home rewards remain usable; old earn-coins page is unreachable. Bara+ and all actual coin offers share a coherent visual hierarchy. Sack fullness increases by pack size and no paw placeholder remains on pack tiles. No checkout semantics, prices or grants change. Existing protected assertions stay intact, new tests fail before implementation and pass afterward, analyze is clean, required reviews run, manual UI checklist is handed to the user.

## Confirmed decisions

- Home + opens the new Shop directly at Coins; retain the + control.
- 28,000 meant 2,800. Preserve the existing 500, 2,800 and 6,000 packs.
- No unresolved product questions. User approved the design and TestFlight deployment.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Unified Shop**

*Elements under test:*

Coin packs and Bara+ → Shop’s Featured section; illustrated sacks replace pack icons.
Dressing room, Store/Inventory and item categories → Items section.
Profile upsell → Membership entry; Get Coins page removed from navigation.
Confirmed: Home + opens Shop’s Coins section; pack quantities remain 500, 2,800 and 6,000.

*Checklist*

1. **Real Home** — **Get there:** Home → Shop, then separately balance +. **Verify:** Shop opens Featured; + focuses Coins; neither opens Get Coins.
2. **Real Featured** — **Get there:** Home → Shop. **Verify:** header/balance, Featured/Items, Bara+, then coin grid; amounts above sacks and purchase buttons below; no dressing room or earning cards mixed into Featured.
3. **Real Items** — **Get there:** Shop → Items → each category and Inventory. **Verify:** Powerups, Characters, Accessories, dressing room and item details remain reachable; no duplicated coin-pack or membership promotion.
4. **Shop shortfall entry points** — **Get there:** with insufficient coins, open powerup and cosmetic purchase details; also tap Shop balance +. **Verify:** each displays Coins within the same Shop; Items returns to the selected item/outfit; Back does not reveal another Shop or Get Coins.
5. **Profile and membership** — **Get there:** Profile → Membership → expand Bara+ in Shop. **Verify:** old Profile upsell is absent; plans, restore/legal links and applicable membership-management controls remain reachable inside Shop. Use preview member/nonmember states where available.
6. **Home earning surfaces** — **Get there:** Home with an available daily reward; inspect ads, referral and daily reward entry points. **Verify:** all remain reachable outside Featured; no Get Coins hub is required.
7. **Shop walkthroughs** — **Get there:** first Shop visit on an account without completed shop tutorial; separately Profile → Settings → View Shop Tutorial. **Verify:** Items is visible and all four spotlights ring Store/Inventory, categories, dressing room and product grid; Featured does not hide targets.
8. **Tab tutorial mirrors** — **Get there:** Profile → Settings → View Tutorial → Home and Profile beats. **Verify:** Home shop spotlight still targets Shop; Profile upsell is absent; replacement entries match the intended preview; no purchase storefront overlays the walkthrough.
9. **Billing preview** — **Get there:** launch the supplied billing-preview build → its page selector. **Verify:** Shop/Profile show the new placements; old Get Coins and standalone Bara+ destinations are retired or lead to the same Shop sections.
10. **Device layouts** — **Get there:** repeat Featured, expanded Bara+ and Items on iOS/Android, narrow screen and enlarged text, light/dark themes. **Verify:** grid becomes one column where needed; amounts/buttons, selectors, close/back and bottom controls remain visible without overlaps or clipping.

*Surfaces confirmed unaffected:*

Demo race tutorial and race-detail preview: inspected host references; neither embeds Shop, Get Coins or membership cards.
Race effects, inventory trays and box-opening surfaces: no moved shop elements are shared with these surfaces.
Hand-copied tutorial bottom navigation: unchanged under the proposed pushed-Shop route; Shop is not a bottom tab.

*Risks found while planning:*

- First-visit Shop tutorial also needs Items mounted; handling only Settings replay misses this path. Its launcher explicitly requires all four target widgets mounted.
- Shop’s old Get Coins helper serves multiple shortfall branches, including powerups and cosmetics; replacing only the header + leaves old routes reachable.
- Billing preview has separate Get Coins and Bara+ page-selector destinations requiring explicit updates.
- Tutorial Home/Profile share real widgets under disabled billing. Replacement membership/Shop entries must preserve preview isolation and intentional visibility.
- Navigation and pack decisions are now confirmed; the checklist uses Home + → Coins and existing pack quantities.

## Revision log

- Gap pass 1: corrected the assumption that Shop is a bottom tab; kept existing pushed route and preserved powerups/characters under Items.
- Gap pass 2: added Shop shortfall routes, Profile management, tutorial Items default, preview isolation, protected test handling, membership disclosures, unavailable platforms and no-change backend contract. Distinguished UI artwork from cosmetic catalog assets.
- UI planner: added first-visit tutorial in addition to replay, all shortfall branches, both billing-preview legacy destinations, and disabled-billing Home/Profile mirrors. Checklist preserved verbatim above.
- Game analyst: confirmed no mechanical economy change; added live value-claim constraint and explicit prohibition on mislabeling 2,800 as 28,000. Local-code verification note added to docs/economy.md; no production access.
- User clarification: Home + opens Shop at Coins, and 28,000 meant 2,800. Closed both open questions; retained all existing product amounts. Updated checklist assumptions without changing its ten verification steps.
- User approved full design and requested deployment to TestFlight. Architect review incorporated explicit destination-test migration, Coins/Membership precedence over automatic tutorial, route-level disabled billing/fake API isolation, independent product section availability and shared checkout exclusion. No new user-facing scope or API changes.

- Final implementation review: Home/Profile entry routes forward equipment/catalog changes to the shell; embedded membership omits duplicate marketing and stacks cosmetic/plan layouts for narrow or enlarged text. Fresh-sign-in test migrates only the retired heading assertion to Coins and a concrete pack purchase control, preserving token coverage.
