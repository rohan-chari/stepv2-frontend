# Bara+ frontend preview

User authorization: build the frontend now to see it and iterate. This supersedes
the full billing spec's backend-first implementation gate for this isolated visual
preview only. No real checkout, backend writes or release is authorized.

## Accepted product content

- Coin packs: 500/$0.99, 2,800/$4.99, 6,000/$9.99.
- Bara+: $4.99/month or $49.99/year. 15% off cosmetic and powerup shop items.
- Monthly grants 500 coins and 10 reroll actions; annual grants 6,000 coins and
  120 actions upfront. Shared monthly cosmetic using existing art as a sample.
- Seven-day trial: active discounts/styling and 3 expiring trial rerolls;
  permanent gifts after first payment. Paid credits roll over and survive expiry.
- Reroll costs 50 coins/action including batch, or uses one available credit,
  or the existing ad flow. One reroll per item and existing replacement rules.

## Scope and contract

Implement real reusable Flutter screens/widgets with an injected billing service,
plus an isolated `lib/main_billing_preview.dart` entrypoint using offline fake
auth/API/billing state. It renders the REAL ShopTab, GetCoinsScreen, ProfileTab,
and box reveal components; no hand-forked shop or purchase screens. Include a
preview navigator so the user can jump among Shop, Coins, Bara+, Profile and
single/batch box examples. Preview controls allow trial, monthly, annual,
expired-with-credits, insufficient-coins and failed/pending purchase states.

`BillingScope` exposes an optional `BillingController` to descendants. Missing
scope means billing is unavailable and existing live UI/requests remain unchanged.
This is dependency injection, not a release flag. No RevenueCat SDK until real
purchase credentials and backend fulfillment are ready. Never install a globally
accessible fake billing service into the production app.

Controller owns immutable offer/snapshot models and notifies listeners; preview
implementation updates only its fake auth wallet. Public UI uses service methods
for purchase/trial/restore/manage and funding; no client-calculated live grant.
Cash strings in preview are sample USD labels and the preview is clearly marked.
Real adapter will supply localized store price metadata. No new backend requests
or migrations are part of this task.
Use independent fake auth, not DemoAuthService (which proxies real credentials).
Inject unsupported/offline ad controllers into every preview screen. Nested
referral/daily-reward/settings routes that are outside this prototype must show
an explicit preview-unavailable message rather than construct real ad/services.
Put BillingScope above the preview Navigator so pushed routes inherit it.

## UI

Use AppColors/PixelText, parchment/forest green/gold and existing capybara and
cosmetic assets. No new art generated. Membership hero features sample monthly
cosmetic; plan selector shows upfront annual amounts and renewal/trial disclosure.
Members see balance, paid/trial credit distinction, current sample reward and
manage/restore affordances. Preview management is clearly simulated.

Get Coins adds three offers above existing earn methods. Shop adds a compact
membership card and member-price explanations wherever an effective price is
provided by the injected API (catalog, selection, details and affordability).
Profile adds membership entry and active badge through the same scope. All new
routes retain the scope when pushed. Demo/tutorial paths must not initiate new
billing actions, including when launched under a billing-enabled parent.

Use a shared reroll funding sheet in single reveal, batch reveal, ordinary held
item sheet and Pocket Watch sheet. It shows cost, available credits, replacement
warning and returns explicit choice. Never reinterpret existing ad requests as
coin consent. Unsupported backend keeps paid controls unavailable. Prototype
funding examples exercise the same shared UI against offline outcomes.

## Test-first acceptance criteria

- Real widget tests cover all pack quantities and purchase/failed/pending states;
  trial versus monthly/yearly state and correct grant presentation; credits after
  expiry; restore/manage flow and no network on preview actions.
- Shop/profile integration updates with injected state; missing scope preserves
  existing UI. Catalog prices and confirmations agree in preview member state.
- All reroll placements use common selector when injected support exists; no
  credit/coin debit on cancel or failed result; batch is one action; repeat is
  unavailable. Ad-only legacy and existing tutorial tests stay green.
- Layout checks at small phone width and large text, light/dark palettes. Capture
  rendered preview screenshots for user review; run the preview on an available
  simulator/browser. Both iOS and Android accounted for.
- `flutter analyze` clean; focused tests first then full suite; frontend-only
  build verification for both platforms where tools permit; code-reviewer runs.

## Revision log

Pass 1: isolated preview composition rather than fake backend payment routes or
runtime flags; real shared screens, explicit unavailable live adapter.
Pass 2: included all held/batch reroll mirrors, scoped navigation, preview price
labels, reward sample disclosure and trial/paid credit distinction.
Architecture and manual placement reviews completed; user authorized this
frontend-only implementation. Backend policy interview resumes after UI feedback.
Architect required change incorporated: explicit ad and nested-navigation
isolation, fake independent identity, scope above navigator. No runtime release
flag or real purchase surface is introduced.

## Review and implementation notes

Architect review completed before implementation. Required isolation changes were
incorporated: independent auth, offline ads and APIs, disabled out-of-scope nested
routes, and billing scope above the preview Navigator. Code review completed;
root-route back navigation and saved held-coin isolation findings were fixed.
The sample monthly reward consistently uses the existing Wizard Hat artwork.

Launch the preview with:

```sh
flutter run -d <ios-simulator-id> -t lib/main_billing_preview.dart
flutter run -d <android-emulator-id> --flavor staging -t lib/main_billing_preview.dart
```

Tap **Sample account · Controls** to reset to Free, Trial, Monthly, Annual,
Expired, or Empty; simulate failed/pending checkout; complete pending checkout;
or switch day/night. Sample balances reset when changing scenarios. Sample
purchases affect this in-memory account only. Close/relaunch resets all state.
Ads are unavailable; box outcomes illustrate placement rather than simulate odds.
The ordinary app entrypoint has no billing adapter and retains existing behavior.
Real RevenueCat integration, server fulfillment, store configuration, subscription
policy decisions and release remain outside this frontend preview.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Bara+ frontend preview**

*Elements under test:*\
Shop: membership card and member-price annotations added to existing shopping surfaces.\
Coins: coin-pack offers and membership card added above earning methods.\
Bara+: new plan, benefits, credits and membership-management screen.\
Profile: membership card and active-member badge added.\
Boxes: shared funding sheet added to single, batch and held-item reroll entrypoints.\
Preview: sample-account controls and five navigation destinations added.

*Checklist*

1. **Surface:** Preview navigation\
   **Get there:** Launch `lib/main_billing_preview.dart` on iPhone and Android.\
   **Verify:** Shop, Coins, Bara+, Profile and Boxes each appear once in the bottom navigation. Sample-account controls sit above the content without covering screen headers or creating a second tab bar.

2. **Surface:** Real Shop inside preview\
   **Get there:** Controls → Monthly → Shop. Inspect a cosmetic, its dressing-room selection, and a powerup detail sheet.\
   **Verify:** One membership card appears above the catalog. Member-price annotations appear alongside prices in catalog tiles, selected cosmetic details, dressing room and powerup purchase sheet. They do not overlap purchase buttons or leave duplicate price labels.

3. **Surface:** Real Get Coins and pushed routes\
   **Get there:** Open Coins directly; repeat through the Shop coin balance. Controls → Empty → Shop → attempt an unaffordable purchase → Get Coins.\
   **Verify:** Every entry shows the three packs and membership card above earning methods, with no duplicated offers. Back navigation and bottom actions remain accessible.

4. **Surface:** Bara+ screen\
   **Get there:** Open the Bara+ tab, then repeat from Shop and Profile membership cards. Use Controls to sample Free, Trial, Monthly, Annual and Expired.\
   **Verify:** Plan choices, benefit sections, sample reward, credit balances and available management actions fit in a clear scrollable sequence. State-specific sections occupy their intended places without stacking duplicate membership panels.

5. **Surface:** Real Profile inside preview\
   **Get there:** Controls → Monthly → Profile; repeat with Free.\
   **Verify:** The membership card appears once. The member badge sits beside the profile identity without covering the name or avatar; it is absent in Free.

6. **Surface:** Single and batch box reveals\
   **Get there:** Boxes → Open One Box → Reroll; repeat with Open Three Boxes → Reroll All.\
   **Verify:** Each reveal has one reroll action in its footer. Both open the same funding-sheet layout, with credit and coin choices, supporting information and Cancel reachable. The previous ad-only footer is not duplicated alongside the new action.

7. **Surface:** Ordinary held item and Pocket Watch\
   **Get there:** Boxes → View Race Stash → open an ordinary held powerup, then Pocket Watch → Reroll.\
   **Verify:** Both item sheets expose one reroll action and the shared funding sheet. Pocket Watch’s separate sheet retains its other controls; reroll does not cover the discard or confirmation area.

8. **Surface:** Demo and tutorial mirrors; normal app\
   **Get there:** Launch the normal app entrypoint. Profile → Settings → View Tutorial; inspect race-detail and Profile beats. Also run the fresh-account demo through its box reveal and Settings → View Shop Tutorial.\
   **Verify:** No preview navigation, paid-reroll sheet, membership card or member badge leaks into these unscoped surfaces. Existing shop, box and profile elements remain in place. Tutorial spotlights still surround their intended shop, mystery-box and powerup targets.

9. **Surface:** Compact-device and accessibility layouts\
   **Get there:** Repeat Shop, Coins, Bara+, Profile and one funding sheet on a small phone with enlarged system text; use Controls → Switch Day / Night.\
   **Verify:** Cards, price labels, plan selectors and footer actions remain separated and reachable by scrolling. Nothing is clipped beneath the keyboard-free bottom safe area or navigation.

*Surfaces confirmed unaffected:*\
Main app tab bar and tutorial’s hand-copied tab bar: the five-destination preview navigation belongs only to the standalone preview host.\
Daily-reward reel: separate implementation with no billing-scope or funding-sheet integration.\
Races-tab effect plates and inventory row: no new billing placement; held-item reroll changes are in race detail.

*Risks found while planning:*\
Get Coins has multiple Shop entrypoints; all need the same offer placement.\
Pocket Watch has a separate held-item sheet, so checking an ordinary powerup alone is insufficient.\
Demo race and tutorial Profile reuse production screens; their explicit disabled billing scopes are essential to prevent new UI appearing there.\
Preview ads are unavailable, so an ad-choice placement requires a separately supported fixture; its absence in this preview is expected.

## Verification record

- Full Flutter suite: 3,018 tests passed. Relevant suite after final contrast
  polish: 27 passed; preview flow/host checks: 6 passed.
- `flutter analyze`: no issues. `git diff --check`: clean.
- iOS simulator debug build and Android staging debug APK built successfully;
  standalone preview launched on both simulators. No store upload or release.
- Code reviewer: no remaining blockers after back-navigation and persistence
  fixes. Final visual polish improves coin-pack text contrast and status-bar
  readability; the sample cosmetic matches the granted Wizard Hat.
- Manual checklist above is handed off for product feedback; this is not a claim
  that every manual scenario has been exercised on physical devices.
