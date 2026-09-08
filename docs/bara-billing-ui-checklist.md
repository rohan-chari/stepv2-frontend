**Manual UI-Placement Test Plan — Live Bara+ billing**

*Elements under test:*\
Shop: membership card above catalog and member-price annotations beside existing prices.\
Get Coins: three purchase offers and membership card above earning methods.\
Bara+: localized plan prices, subscription actions, management and legal links.\
Profile: membership card below identity header and member badge beside identity.\
Boxes: shared funding sheet reached from single, batch and both held-item sheets.\
Navigation: existing app navigation retained.

*Checklist*

1. **Surface:** Normal app and Shop\
   **Get there:** Sign in → Home → Shop; inspect a cosmetic, dressing-room selection and powerup detail.\
   **Verify:** Existing navigation remains in place; no preview bar or sample controls appear. One membership card sits above the catalog. Price annotations stay beside their corresponding prices without overlapping purchase buttons or duplicating labels.

2. **Surface:** Every Get Coins entrypoint\
   **Get there:** Home coin balance “+”; repeat through Shop’s coin balance, then an unaffordable Shop purchase → Get Coins.\
   **Verify:** Each route shows the three offers, then membership card, then existing earning methods. No repeated offer sections; header, back action and bottom content remain accessible.

3. **Surface:** Bara+ offer and membership screen\
   **Get there:** Open the membership card from Shop, Get Coins and Profile. Use supplied free, trial-eligible, trial, active and expired test accounts.\
   **Verify:** Monthly/yearly selectors, localized prices, current subscription action, credit sections and management/restore actions occupy one scrollable sequence. Trial and ordinary subscription actions do not stack accidentally. Terms and Privacy links remain reachable below the offer.

4. **Surface:** Native purchase and subscription management\
   **Get there:** From Get Coins open native checkout and dismiss it; from Bara+ open checkout and subscription management, then return to Bara.\
   **Verify:** Native surfaces fit their safe areas. Returning leaves one original app screen with its header and actions visible; no duplicate paywall, blank overlay or stranded loading layer covers navigation.

5. **Surface:** Profile tab and pushed Profile\
   **Get there:** Open Profile from the main navigation, then through a screen’s profile/avatar shortcut; repeat with a member account.\
   **Verify:** Both show one membership card below the identity header. The member badge sits beside identity without covering the name or avatar. Pushed Profile retains its back button.

6. **Surface:** Single and batch box reveals\
   **Get there:** Active race with unopened boxes → open one → Reroll; repeat with multiple boxes → Open All → Reroll All. Use an ad-supported device for the ad-choice variation.\
   **Verify:** Each reveal has one reroll footer action. The shared sheet places credits, coins and available ad choice in a consistent order, followed by Cancel. No second ad-only reroll footer remains alongside it.

7. **Surface:** Held ordinary item and Pocket Watch\
   **Get there:** Active race → powerup stash → eligible held ordinary powerup → Reroll; repeat with Pocket Watch.\
   **Verify:** Both sheets expose one reroll action and the same funding layout. Pocket Watch’s separate footer retains its other controls; nothing covers discard, confirmation or dismissal actions.

8. **Surface:** Tutorial and onboarding mirrors\
   **Get there:** Profile → Settings → View Tutorial, including Profile and race-detail beats; Settings → View Shop Tutorial; fresh-account onboarding → demo race → box reveal.\
   **Verify:** Membership cards, member badges and paid funding sheets are absent from these tutorial surfaces. Existing elements appear once, and spotlights still surround the shop, box and powerup targets. Tutorial navigation retains its original arrangement.

9. **Surface:** Store/backend unavailable presentation\
   **Get there:** Use the developer-supplied build/account with unavailable store configuration, then the supplied older-backend scenario. Visit Shop, Get Coins, Profile and an eligible box.\
   **Verify:** Existing gameplay sections retain their positions. No sample prices, preview controls or empty purchase-panel gaps appear. Any unavailable notice appears once. Where paid rerolls are unsupported, the existing supported reroll footer remains correctly placed.

10. **Surface:** Legal browser pages and compact layouts\
    **Get there:** Bara+ → Terms, then Privacy; return to Bara. Repeat Shop, Get Coins, Bara+, Profile and one funding sheet on iPhone and Android with enlarged system text.\
    **Verify:** Legal page headings, paragraphs and links fit the mobile viewport without horizontal scrolling. App prices, plan selectors, legal links and footer actions remain separated and reachable; nothing clips beneath navigation or the bottom safe area.

*Surfaces confirmed unaffected:*\
Main app tab bar and tutorial’s hand-copied tab bar: billing adds screen content, not destinations.\
Races-tab effect plates and inventory row: reroll controls are added inside race detail, not these separate renderers.\
Daily reward reel: separate screen with no billing or reroll-funding integration.\
Demo create-race and invite prologue: no billing elements are added to these screens.

*Risks found while planning:*\
Settings’ Shop Tutorial directly opens `ShopTab(forceTutorialReplay: true)`; it needs explicit billing isolation like the other tutorial hosts.\
Profile has both tab and pushed-route renderings; Get Coins has Home plus two Shop entrypoints.\
Pocket Watch has its own footer, so an ordinary held-item check does not cover it.\
Missing store configuration can coexist with supported paid rerolls; their placement checks need separate supplied scenarios.

**Manual UI-Placement Test Plan — Bara+ plan-change supplement**

*Elements under test:*\
Bara+: Change billing plan added immediately below Manage membership.\
Plan-change sheet: alternate plan and localized price, renewal explanation, Continue to Store, then Keep current plan.\
Grace-period membership: existing member section and management controls remain visible.

*Checklist*

1. **Surface:** Every Bara+ entrypoint\
   **Get there:** With an active subscription, open Bara+ through Shop, Get Coins, Profile tab and the pushed Profile reached through an avatar shortcut.\
   **Verify:** Each opens the same layout, with one Change billing plan action directly below Manage membership. It does not also appear beside the plan selectors or elsewhere.

2. **Surface:** Plan-change bottom sheet\
   **Get there:** Bara+ → Change billing plan; repeat with monthly and annual test accounts.\
   **Verify:** The sheet presents heading, alternate plan with localized price, renewal explanation, Continue to Store, then Keep current plan. All appear once; neither action covers the explanation or bottom safe area.

3. **Surface:** Dismissal and native-store return\
   **Get there:** Dismiss using Keep current plan; reopen and swipe down; reopen → Continue to Store → cancel native confirmation and return. Also open Manage membership and return.\
   **Verify:** Every return exposes one Bara+ screen with its back button and management controls. No duplicate sheet, blank overlay or loading layer remains over them.

4. **Surface:** Trial, expired and grace-period accounts\
   **Get there:** Use supplied trial, expired and verified grace-period test accounts → Profile → Bara+.\
   **Verify:** Trial and grace accounts show one member section and management controls; Change billing plan sits below Manage membership when an alternate offer is supplied. Expired accounts show the plan selectors and subscription action without a leftover Change billing plan action. Credit information remains above the benefits section without duplication.

5. **Surface:** Tutorial mirrors\
   **Get there:** Profile → Settings → View Tutorial, including Profile; Settings → View Shop Tutorial; fresh-account onboarding → demo race.\
   **Verify:** No membership card or plan-change action appears in these isolated surfaces. Existing tutorial content and navigation retain their positions without empty billing gaps.

6. **Surface:** Compact iPhone and Android layouts\
   **Get there:** On both platforms, enlarge system text → active account → Bara+ → Change billing plan; repeat with a grace-period account.\
   **Verify:** Membership information, management actions and sheet content remain scrollable and reachable. Long localized prices wrap without covering adjacent content; both sheet actions clear the bottom safe area.

*Surfaces confirmed unaffected:*\
Main navigation and tutorial’s hand-copied tab bar: this supplement adds no destinations or tab changes.\
Single/batch box reveals and held-item sheets: they do not render the membership plan-change controls.\
Demo create-race and invite screens: no plan-change entrypoints.

*Risks found while planning:*\
Grace is represented through verified membership access, not a separate grace panel; use a supplied grace account to inspect this layout.\
The change-plan action requires a known current plan and an available alternate offer; missing store metadata can conceal it during testing.\
Profile has both tab and pushed renderings; testing only the tab misses an entrypoint.
