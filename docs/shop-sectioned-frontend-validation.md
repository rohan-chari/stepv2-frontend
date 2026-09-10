# Sectioned Shop and Red Card copy — frontend implementation

## Scope

Approved combined spec Issues 3 and 5 (bundled copy only). Meta integration,
artwork, backend enforcement, production operations, and release artifacts are
owned by the batch orchestrator.

- Shop is one scrolling page: Featured (standalone Bara+ row then coin offers),
  Powerups (local Buy/Owned and filters), Characters & Accessories.
- Theme-aware headers use Home's purple marker treatment. No Home environment or
  avatar was introduced. Both Shop and wardrobe category bars are removed.
- Powerup grids have three phone columns, two for narrow/enlarged text, five on
  tablets and a 1,000-pixel maximum width. Art has 10-pixel inset padding in a
  taller card and is contained without the previous 1.5x overflow transform.
- Existing membership/coin focus and insufficient-balance routes remain. Wardrobe
  Back preserves the Shop scroll position. Shop's first tutorial anchor is now
  Featured; its second scrolls to the default character and opens the existing
  four-step wardrobe tutorial. Explicit coin/member entry defers the tutorial
  until the user scrolls into Powerups or selects Owned.
- Initial wardrobe loading waits for bootstrap completion, because publishing a
  wardrobe appearance previously invalidated a still-pending bootstrap result.
  Recheck initial state inside the post-frame load callback to deduplicate loads.
  Programmatic section scrolling does not prefetch character pages; downward user
  scrolling near the end retains bounded pagination.
- Red Card bundled description now says: “Remove 10% of the leader's steps, up to
  10,000 steps.” Existing server copy precedence remains; no client cap enforcement.

## Compatibility and failure handling

No backend field, endpoint, or response contract changes. Existing defensive
catalog/wardrobe readers, unsupported-server character fallback, billing
unavailability messaging, reward verification, saved-outfit reconciliation and
identity checks remain. Catalog items used by Powerups are read through the
existing safe-item parser. A missing powerup component renders its existing
local empty/unavailable state; billing and character sections remain available.
The same Dart implementation covers iOS and Android, including bottom safe areas.

## Tests first

`shop_continuous_sections_test.dart` failed before implementation on the old
bottom navigation and four-column/14-pixel-spaced grid, then passed. Covers
section order, standalone membership row above coins, local Owned preserving
other sections, three columns, two-column enlarged-text layout, and a wide-grid
width cap (the width assertion separately failed at 1,600 before bounding).

`red_card_cap_copy_test.dart` pumps the real PowerupGuideSheet with absent server
copy. It failed on the old uncapped fallback, then passed with the full cap text.

## Protected assertion migration

The user explicitly approved removal of the category tabs and the new geometry.
The orchestrator confirmed that exact superseded behavior assertions should be
replaced; purchase, ownership, reward, identity, paging and tutorial completion
assertions were preserved.

| Previous assertion or navigation | Replacement |
| --- | --- |
| Category button tap in shared helper | Scroll to the corresponding section header; accessory entry still opens the default wardrobe |
| Bottom bar is present / category selection semantics | Bottom bar absent, sections present and ordered, section header semantics, product hit target retained |
| Membership is the same size as coin tile | Standalone full-width membership row appears before coin offers |
| Four compact phone Powerups; six tablet columns; 1.5x art | Three phone/five tablet columns, taller .68 cards, fully contained art, two columns for enlarged text |
| Powerup and character geometry identical | Powerup-specific geometry; original character/wardrobe grid breakpoints remain |
| Old bottom-bar tutorial target | Featured header target; same overlay-coordinate, route-transition, Back/Skip and completion checks |
| Wardrobe category action discards draft | Ordinary Back requires the same explicit discard and preserves canceled drafts |
| Items assumed always onscreen | Scroll/ensureVisible before real taps; lazy wardrobe rows located with scrollUntilVisible |
| Category switch hides unrelated content | Local controls preserve Featured and Characters in the continuous page |

## Verification record

- Analysis clean during the implementation pass (`flutter analyze --no-pub`).
- Shop/wardrobe/filter/tutorial/reward/coin/home-entry subset: 110 passed; one
  preview fixture needed its scrolled-away lazy item located by scrolling.
  After that mechanical interaction fix, the preview + store/inventory suites
  passed all 17 tests without missed-tap warnings.
- Wardrobe/batch layout/purchase confirmation/ad-unlock/equipped-shape subset:
  79 passed; only a stale uppercase Featured expectation remained. Its updated
  ad-unlock suite passed all 13 tests.
- Continuous-section suite passed all four tests after the wide-grid addition.
- Orchestrator owns the four root-migrated Shop suites, final complete test run,
  post-implementation review, and matching release builds. Those gates must be
  completed before the batch is declared ready.

## Manual UI checks still required

Use the combined spec's “Manual UI-Placement Test Plan — Unified Shop and
Hitchhike artwork” on iOS and Android: real Shop section order and bottom safe
area; local Powerups controls at normal/narrow/enlarged text sizes; owned/locked
character flows and wardrobe Back; coin-shortfall and membership routes; automatic
and replay tutorial anchors; billing preview. Root-owned artwork additionally
requires the listed compact/enlarged icon and turtle checks.

## Follow-up: Meta onboarding completion

`MainShell` now arms the typed `onboardingCompleted` signal only from real
onboarding gate actions (first-race finish/skip, teaching-step completion/skip,
or health escape). It emits when the same account subsequently has no remaining
onboarding gate. A per-shell account guard prevents duplicate callbacks/rebuilds;
existing persisted onboarding flags prevent ordinary later launches from arming.
No existing-account login or Settings tutorial-reward call emits this event.
Local completion is counted even when the existing best-effort server marker
fails, because the user has successfully exited onboarding on this device.
No identifiers or other parameters are sent to Meta.

Tests: `meta_onboarding_completion_test.dart` initially failed its two real-final-
CTA cases with expected `onboardingCompleted` versus no event. All four cases
now pass: confirmed exit with server marker success/failure; no duplicate on a
repeat callback/rebuild; no premature event after the teaching step; no event on
an existing login or the real AuthService tutorial-replay reward path.
Existing `onboarding_revamp_test.dart` and `demo_race_onboarding_test.dart` pass
all 49 cases. Android suppression remains in the shared typed event service.

## Actual rendered Shop evidence

Captured the real `ShopTab` pushed as a route (including Back) using existing
`PreviewBillingApi`/`PreviewBillingController`, with six bounded powerup fixture
rows matching the user's pictured collection. These are Flutter render captures,
not image-generated concepts. Loaded bundled Space Grotesk, DM Sans, Jersey25 and
Material Icons into the actual text styles; no Ahem placeholder glyphs. Local
assets were given decode frames before capture. The standalone capture passed.

Logical sizes: 390×844 and 320×844; light and dark palettes; 2× exported pixels;
44 top and 34 bottom logical safe-area insets. The empty status-bar area belongs
to the widget capture (OS status chrome is not simulated). Sample USD prices and
the PREVIEW note come from the offline billing fixture, not a live storefront.

| Theme / width | Featured | Powerups | Characters / bottom |
| --- | --- | --- | --- |
| Light 390 | [image](artifacts/shop-sectioned-2026-09-10/light-390-featured.png) | [image](artifacts/shop-sectioned-2026-09-10/light-390-powerups.png) | [image](artifacts/shop-sectioned-2026-09-10/light-390-characters.png) |
| Dark 390 | [image](artifacts/shop-sectioned-2026-09-10/dark-390-featured.png) | [image](artifacts/shop-sectioned-2026-09-10/dark-390-powerups.png) | [image](artifacts/shop-sectioned-2026-09-10/dark-390-characters.png) |
| Light 320 | [image](artifacts/shop-sectioned-2026-09-10/light-320-featured.png) | [image](artifacts/shop-sectioned-2026-09-10/light-320-powerups.png) | [image](artifacts/shop-sectioned-2026-09-10/light-320-characters.png) |
| Dark 320 | [image](artifacts/shop-sectioned-2026-09-10/dark-320-featured.png) | [image](artifacts/shop-sectioned-2026-09-10/dark-320-powerups.png) | [image](artifacts/shop-sectioned-2026-09-10/dark-320-characters.png) |

Visual inspection found and corrected one mismatch: section markers were using
green accent colors. The orchestrator changed them to Home's existing
`pillGold`/`pillGoldDark` tokens; final captures show purple in dark mode and gold
in light mode, matching Home's theme behavior.

Final inspection: three powerups per row; all six icons fully contained; clear
thumb-up silhouette; readable labels/prices; no card or section-header overflow.
At 320, Ghost Pepper wraps inside its name band and Characters & Accessories
wraps into two lines. All three character cards clear the bottom safe area.
The last section scroll naturally clamps at the document end, so some Powerups
remain above Characters instead of introducing empty space to top-align it.
The fixed Shop header remains usable while the content scrolls beneath it.
These static captures do not establish all-frame turtle cleanup or physical-
device/native billing behavior.

[Capture harness](artifacts/shop-sectioned-2026-09-10/capture_shop_test.dart.txt)
is archived as text outside `test/` so it does not run during the production test
suite. To reproduce, copy it to `test/_shop_evidence_capture_test.dart`, run that
single test with `flutter test --no-pub`, then remove the temporary copy. It uses
only local asset aliases to load bundled fonts without network font fetches.
[Manifest](artifacts/shop-sectioned-2026-09-10/manifest.json) records image sizes,
SHA-256 hashes and the corresponding Shop/grid/Hitchhike source hashes.
