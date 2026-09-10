# Backend-controlled powerup and accessory content

## User correction and authorization
After the Decoy build18 release, the user clarified that powerups, accessories and related content must be controlled by the backend, with no binary-specific product policy. This is a continuation of the authorized shop work and TestFlight release. Build18 remains valid and contains the original changes; ship the authority correction as the next verified build. Already installed binary filters cannot be changed remotely, so one carrying update is unavoidable. Subsequent supported-content changes must work from server responses alone.

## Scope
Remove client item-specific availability/retirement restrictions across Shop, race inventory/stash/cards, field manual, daily rewards, and box animation candidates. Prices, upgrade eligibility and paid-action policy must come from server data; explicit empty/zero/false values must not resurrect bundled rules. Retain defensive parsing, ownership presentation, server-provided earnOnly/canPurchase/canSelect/canEdit, and supported-slot/rendering validation. Preserve remote-first artwork/animation resolution. Do not alter real reward selection, odds, prices, race gameplay or infrastructure capacity. The app retains interaction renderers and advertises their compatibility to the backend; no capability-header removal or arbitrary new mechanic interpreter.

## Existing API contract — no new required fields
- Shop catalog/purchase/inventory responses already carry authoritative rows, priceCoins/basePriceCoins, quantities, ownership and adUnlock policy. Never filter by literal item type. Missing or invalid price/policy must not imply a free item or a bundled ad offer.
- Character/wardrobe endpoints already provide canPurchase/canSelect/canPreview/canEdit and fit. Preserve them and server earnOnly handling.
- GET /powerups/catalog already serves availabilityVersion2, stackingVersion2, entries with availability.shop/roll and upgradeTierLabels (valid [] means no upgrade). Live contract verified after build18. Explicit valid empty catalog is authoritative; malformed responses retain last good data, not silently manufacture a product roster.
- GET /races/:raceId/progress powerupData.dropOdds.byType maps eligible type to its real probability from the same roll calculation; rarityByType supplies presentation rarity. Pass those existing fields through both case-opening screens into CaseOpeningStrip. Add optional dropOdds.reelPreviewAvailable:boolean, derived from already loaded viewer effects and complete ordinary probabilities. It is true only for a safe ordinary context with no ACTIVE Lucky Horseshoe (match server opener authority); false otherwise. This is a permanent response fact, never a configurable rollout flag. Draw decorative candidates from existing byType only when reelPreviewAvailable is explicitly true; no duplicated probability map or added queries. Empty/missing metadata uses generic mystery placeholders, never a compiled drop pool. The server-returned winner always renders verbatim with safe fallbacks.
- Race progress already supplies upgradeCosts.byRarity/byType and discardPrices. Use valid server quotes for economic labels/actions; absent paid quote disables that paid choice with an unavailable state. A free/base use action that has no server price requirement must remain available. Discard can remain an unpriced action if its payout is unknown, without claiming a made-up amount.
- Daily reward server pools, odds and coinRanges control decorative content; remove literal exclusions and retired-winner overrides. Missing metadata uses neutral placeholders; no invented product eligibility or economic amount. Existing server winner/claim is authoritative.
All endpoint shapes remain compatible; old clients continue their existing behavior. No schema migration or rollout flag is planned; shared backend projection policy and safe preview metadata may require deployment before the carrying app.

## Implementation ownership and paths
Frontend agent owns:
1. lib/screens/tabs/shop_tab.dart: remove hiddenPowerupInventoryTypes/notForSalePowerupTypes and inferred legacy ad-price policy; keep server-driven affordability/ownership and safe malformed/missing price handling.
2. lib/screens/race_detail_screen.dart and lib/screens/tabs/races_tab.dart: remove literal retired-type filters; use server economic tables for upgrade/discard display; preserve inventory/refund and specialized action flows.
3. lib/constants/powerup_copy.dart: no literal exclusions; valid authoritative availability (including empty roster) wins. Explicit [] upgrade tiers disables upgrades. Bundled names/descriptions can remain rendering fallbacks; bundled data must not decide catalog eligibility or revive server-disabled paid actions.
4. lib/screens/daily_reward_screen.dart: show server pool and actual returned prize, no literal exclusions/retirement substitutions; neutral unknown decorative data.
5. lib/widgets/case_opening_strip.dart plus case_opening_screen.dart and multi_case_opening_screen.dart: use existing server probabilities; remove compiled candidate lists/weights. Server rarity wins; unknown rarity uses generic visual styling.
6. Update demo/tutorial/billing fixtures with explicit server metadata where the scene intentionally demonstrates paid choices, guide entries or reel candidates. No production policy may depend on demo fixtures.
Backend agent owns outgoing race inventory/progress/slotItems projections: apply the shared backend retirement predicate, preserving historical activity/effects and mutation rejection. Tests cover each real HTTP projection with held retired rows and ordinary rows, old and current headers. Add the pinned optional dropOdds.reelPreviewAvailable field using already loaded raw snapshot.activeEffects and myParticipant, before presentation filtering. Test ordinary true, ACTIVE Lucky Horseshoe false, unrelated rival effect does not block, incomplete metadata false, and unchanged existing byType. No prod test writes.

## Tests first
Real widget/screen tests must fail before business edits:
- Backend-returned previously suppressed types and an unknown type show in Shop, inventory, stash/card and rewards; removing them from next server response hides them.
- Price changes and explicit server eligibility alter rendered actions without changing binaries. Invalid/missing price never shows a buy-for-zero action; missing ad policy never invents ads.
- Guide obeys authoritative availability and empty catalog; explicit [] upgrade labels disables bundled upgrade UI, missing/malformed data is safe.
- Single/multiple box reels use a deterministic server-only candidate pool, support unknown types, respect zero probability/empty pool with neutral tiles, preserve the actual winner and tutorial reveal boundary. No copied hardcoded odds remain.
- Daily rewards render server Decoy/Imposter candidates and actual prizes. Missing pools/amounts render safely without fabricated prizes.
- Upgrade/discard unknown prices do not invent amounts; valid prices follow server tables. Existing base-use and inventory refund assertions remain intact.
Run relevant suites and final flutter analyze. Existing assertions requiring compiled retirement/legacy price pools are obsolete under this explicit user correction; surface and replace only those policy expectations with backend-authority assertions, preserving unrelated behavior checks. Known36 baseline admin failures and unrelated backend Drill failure remain disclosed.

## Compatibility, performance and release
No new endpoint dependency, no new database reads/writes or step-sync work for these projection changes. Optional new preview metadata must be verified live before the carrying app is uploaded. Catalog data is authoritative under its existing cache/invalidation behavior. Runtime malformed data must not crash or reinterpret missing values as enabled/free. Older installed clients need the carrying update to remove old filters; server capability gates remain to protect them from unsupported interactions.
Architect, economy/display-odds, UI placement and independent code review required. Read README immediately before each build/upload, build next unused iOS19 and matching Android203149, verify exact signed artifacts/source/config, upload through existing ASC API key, verify VALID/IN_BETA_TESTING and existing tester group membership. Deploy required backend projection/metadata changes first; do not submit App Review/Play release.

## Revision log
Pass1: expanded item-filter audit beyond Shop to race cards/stash, guide, daily winners and decorative reels; preserved actual server reward selection.
Pass2: existing dropOdds.byType eliminates need for additive API; distinguished valid empty/false server policy from missing/malformed metadata, included explicit empty upgrade tiers and safe unknown-price states. Preserved remote-first assets and compatibility headers.
Economy review SOUND WITH CHANGES: reward EV/costs unchanged; use neutral race previews for special guaranteed contexts unless server provides exact-context odds. Daily itemOdds.accessories is truncated: preserve omitted mass as neutral, do not renormalize. Use itemOdds.rareMix (includes COINS); coinRanges are bounds, not uniform payout odds, so decorative coin tiles should show a generic/range label rather than invent an exact payout probability. Final contract pinned: dropOdds.reelPreviewAvailable boolean plus existing byType, minimizing bytes without duplicating40 probabilities. Architect APPROVE with no required changes. Pin complete-map validation: nonempty finite nonnegative probabilities, total within1e-6 of1; retain zero probabilities as ineligible, never normalize missing mass. Compute preview fact only in viewer overlay, outside shared snapshot. Apply shared retirement predicate without shop sale/capability restrictions. Test warm-cache and uncached paths.

## Manual UI-placement test plan
**Manual UI-Placement Test Plan — Server-controlled product visibility**

*Elements under test:*

Shop, race inventory, stash, and guide rows display server-returned items, including unfamiliar items.

Daily reward and box reels display eligible returned items, with neutral mystery artwork when decorative reel data is unavailable.

Upgrade choices and purchase/ad actions appear only where server policy supplies them.

*Checklist*

1. **Real Shop and Shop tutorial**
   - **Get there:** Home → Shop; repeat via Settings → VIEW SHOP TUTORIAL.
   - **Verify:** With prepared server responses, returned Decoy, Imposter, and an unfamiliar item appear once; omitted items do not remain as extra cards. Missing purchase/ad policy shows the unavailable state without a guessed-price action.

2. **Races tab and race detail**
   - **Get there:** Races → an active race containing prepared inventory → open race → Powerups.
   - **Verify:** Returned items appear in both the tab’s inventory rail and detail inventory. Check global stash separately. No item disappears solely because its type is unfamiliar. If available, check an active tournament row’s inventory rail too.

3. **Held-item and stash action sheets**
   - **Get there:** Race detail → tap a held powerup, then a stash powerup; include Pocket Watch.
   - **Verify:** An explicit empty upgrade-tier list leaves no upgrade choices. Missing paid/ad policy leaves no guessed-price action. Available base controls remain in their intended positions.

4. **Single-box, multiple-box, and guide surfaces**
   - **Get there:** Active race with unopened boxes → open one → guide; then return and Open All.
   - **Verify:** Both reel layouts display server-provided decorative items, or neutral mystery tiles when odds are missing. Actual revealed items occupy the winner position. In both guide tabs, only available items appear; an explicit empty availability list does not restore the compiled catalog.

5. **Daily reward**
   - **Get there:** Home → daily reward; also check its entrance through Get Coins when available.
   - **Verify:** With a prepared Decoy/Imposter reward fixture, the item appears in the reel and winner position. No blank result or substituted card occupies its place.

6. **Onboarding demo and general tutorial**
   - **Get there:** Fresh account → onboarding demo race; Settings → VIEW TUTORIAL for Races and race-detail previews.
   - **Verify:** Inventory remains visible on both tutorial surfaces; their powerup/box spotlights still align. During demo box openings, missing odds produce neutral mystery tiles. Do not count absent fixture items as verified positive coverage.

7. **Offline billing preview**
   - **Get there:** Device preview build → Shop; then OPEN ONE BOX, OPEN THREE BOXES, and VIEW RACE STASH.
   - **Verify:** Returned fixture items remain visible. Both box reels handle missing odds with neutral tiles. Guide and stash sheets handle absent/empty policy without populated fallback lists or guessed-price controls.

*Surfaces confirmed unaffected:*

- **Tutorial tab-bar copy:** No navigation placement changes.
- **Friends, leaderboard, and profile previews:** Do not render these item lists.
- **Demo/tab tutorials’ daily rewards:** Neither directly renders the daily reward screen; its live entry points share `DailyRewardScreen`.

*Risks found while planning:*

- Races-tab inventory is a separate implementation from race detail and also appears on active tournament rows.
- Daily reward has its own reel and winner handling; race-box changes do not propagate there.
- Single-box and multiple-box screens are separate implementations.
- Guide has two independently populated tabs.
- Demo, tutorial, and billing-preview data are hand-maintained. Positive coverage requires supplied items/policy; missing-data coverage alone is insufficient.
- Prepared fixture states are needed for unfamiliar items, explicit empty tiers/availability, and absent quotes/ad policy. These checks concern visibility and placement only.

### Additional quote-policy placement checks

- **Character wardrobe:** Shop → Accessories → Edit outfit → unpurchased accessory; repeat through Characters → owned character → Edit outfit. Missing/invalid quotes leave the accessory visible with the unavailable purchase control in its normal position. Valid zero quotes retain a purchase control without duplicates.
- **Wardrobe tutorial:** Settings → VIEW SHOP TUTORIAL → wardrobe steps. Check accessory cards, unavailable purchase states, preview/grid layout, and control spotlights with prepared responses.
- **Pocket Watch:** Active race → Powerups → held Pocket Watch; repeat from global stash. With zero, two, and five server tier labels, only supplied choices appear. Missing quotes show unavailable controls without extra priced actions. Production data alone cannot verify these fixture states.

## Additional authorized Shop placement change

Remove the bottom Edit outfit button. Place an Edit button with a pencil inside each server-eligible owned character tile in Characters, using existing button, typography and icon styling. The button opens that character's wardrobe and remains separate from select/purchase actions. Verify the real Shop and Shop tutorial, plus narrow layouts. This supersedes the original release's bottom edit placement and the checklist routes through that removed button.

## Final character-tile manual checklist

1. Home → Shop → Characters: each eligible owned tile has one pencil Edit button; locked/ineligible tiles have none. Scroll to the bottom and confirm the old Edit outfit button is absent.
2. Edit the active character, then another owned character: each opens its own wardrobe. Back returns to Shop. Tapping Edit does not also open the surrounding tile's character action sheet.
3. Repeat through Home's coin + entrance on small iPhone/Android screens and with larger text: icon, label, character name, ownership and art fit without overlap; adjacent buttons stay separate.
4. Settings → VIEW SHOP TUTORIAL: character spotlight includes Edit; continue through wardrobe and return. The `shop-character-default` anchor remains intact and the bottom button stays absent.
5. Offline billing preview → Shop → Characters: eligible owned fixture characters have Edit; locked characters do not. No bottom Edit outfit button.

General tab and demo race tutorials do not render these character tiles. Prepared eligible ownership fixtures are required for positive preview coverage. These routes supersede all earlier checklist references to the removed bottom control.
