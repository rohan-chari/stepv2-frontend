# Shop Featured category revision

User-directed revision to the approved unified Shop: remove the extra Featured/Items navigation. Featured belongs in the existing category row below Store/Inventory, alongside Powerups, Characters and Accessories. Coins and Bara+ must use the existing product-grid tile dimensions, rather than large storefront panels. User explicitly requested implementation and TestFlight deployment.

Keep the existing dressing room, Store/Inventory structure and item category behavior. Featured is a Store category; Inventory shows owned item categories, remembering the last item selection. Home + and shortfall actions open Store/Featured coins; Profile Membership opens the membership details from Featured. Normal Shop opens Featured unless the first-visit/replayed tutorial needs Powerups. Category controls must remain legible at narrow widths and enlarged text.

Use a compact Bara+ tile in the same grid as all coin packs, with membership detail disclosure on tap (existing purchase/restore/legal/manage flow retained). Grid columns, spacing and aspect ratio must match the existing powerup/cosmetic grid at the same viewport. Reuse generated sack PNGs; no new art or economic changes. All product quantities/localized prices and membership state continue to come from the unchanged shared billing controller.

Frontend ownership: ShopTab, CoinPackOffers and relevant widget tests. Preserve existing billing guards, account generations, catalog callbacks, membership semantics and disabled tutorial billing isolation. Mechanical tests referencing retired ITEMS navigation must target existing product categories instead, keeping underlying assertions. Add failing-first tests for category placement, absent extra navigation, matching tile geometry and entry-point behavior. Capture actual layout on normal and narrow/enlarged text screens. Run full tests, clean analysis and code reviewer. Backend API and deployed commit 7e27dc1 unchanged, no migrations or backend deployment required; frozen clients unaffected.

Release: both signed iOS and Android candidates verified; upload iOS to TestFlight and verify availability. Stay on local main in both repos per user preference. No branch cleanup, remote push, App Review submission or Play upload requested.


## Review notes

- Gap pass 1: Featured is Store-only; Inventory must fall back to a remembered item category rather than presenting purchase offers.
- Gap pass 2: explicit Home/Profile focus defers tutorial; first visit/replay selects the existing product category so all spotlight anchors remain mounted. Account-isolated billing and equipment callbacks must survive detail dismissal.
- Existing powerups and cosmetics use slightly different grid metrics. Featured matches the Powerups grid exactly (3 columns on phones, 4 wide; 12/14 spacing; aspect 0.82 or 0.70 below350px available width), verified by actual rendered geometry.

## Manual UI-placement checklist

1. Home → Shop: Featured is below Store/Inventory, alongside product categories; no separate top Featured/Items selector.
2. Store → Featured → Powerups/Characters/Accessories: coin and Bara+ tiles share normal product scale; all four offers reachable, no oversized membership panel.
3. Featured → Inventory → Characters/Accessories → Store: owned items and dressing room remain reachable; no paid offers in Inventory.
4. Home +, Shop + and shortfall flows: Store/Featured coin tiles appear, with no retired Get Coins route or duplicate Shop.
5. Profile Membership and Featured Bara+ tile: both open details with plans, restore/legal/manage controls; dismissal returns to Featured.
6. First Shop visit and Settings → View Shop Tutorial: all four spotlights target visible Store/Inventory, category row, dressing room and product grid.
7. Smallest phone and larger text: four category labels readable/reachable; tile content fits; last row clears safe area. Repeat day/night and both platforms.
8. Billing preview Shop/Coins/Bara+ entrances use the same category layout and appropriate focus; disabled tutorials cannot present checkout.

Main tab tutorial only mirrors Home's Shop button. Demo race/race-detail preview do not embed Shop. Bottom navigation is unchanged.
