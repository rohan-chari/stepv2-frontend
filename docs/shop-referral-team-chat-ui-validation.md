# Shop, referral, and team chat UI fixes — 2.3.13

## Scope

- Shop tutorial step 1 surrounds the full Store/Inventory control. Targets are measured in the overlay's coordinate space so opening-route animation does not leave a displaced cutout.
- Referral dashboard Official Rules uses theme-aware text. Overview, dashboard, and rules-page prizes use readable gold ink; the rules-page OPEN badge and overview rules link also have readable foregrounds.
- Team races place the full-width ACTIVITY / TEAM CHAT selector above the content panel, using the existing arcade selector. ACTIVITY retains the existing race-wide timeline and composer; TEAM CHAT retains the private teammate feed and composer.
- Activity & Chat uses the same white text, shadow, gold marker, and spacing as other race section headers.

## Compatibility

All changes are shared Flutter UI. No backend source, API contracts, capability gates, privacy rules, migrations, dependencies, or runtime controls changed. Older servers still follow the existing capability/fallback paths. Frozen old app versions retain their current behavior. No backend deployment is required for these fixes.

## Automated validation

New regression checks failed before implementation for displaced Shop bounds, referral contrast, and missing ACTIVITY / TEAM CHAT labels. Existing assertions were preserved; TEAM selector taps were mechanically renamed to TEAM CHAT.

- `flutter analyze`: clean, including release metadata.
- Full `flutter test` run: **2,969 passed**.
- Additional Shop route-animation/Back tests: **2 passed**, covering first visit and Settings replay.
- Focused Shop/referral/race suites: **72 passed** before the two additional route tests.
- Release/version/What's New suites after bumping to 2.3.13+1: **31 passed** (overlaps full-suite coverage).
- Code-reviewer: **SHIP**, no blockers, issues, or nits; final metadata/test delta also reviewed.

The contrast tests pump the real referral dashboard and navigate to the rules screen in both themes. They require 4.5:1 for the rules button and OPEN badge, and 3:1 for the large prize text. Race tests cover private audience binding, selector order, matching header ink, and read-only completed team history.

Both platforms compiled successfully against production configuration before the version bump. The first Android attempt encountered generated registration for a test-only plugin; rebuilding with refreshed Flutter metadata after tests passed without any source workaround.

## Release artifacts

Both final production builds succeeded. Nothing was uploaded, submitted, or deployed.

| Platform | Artifact | Version / build | Validation |
| --- | --- | --- | --- |
| iOS | `build/ios/ipa/Bara.ipa` | 2.3.13 / 1 | App Store IPA export; package identity and strict deep codesign verification passed |
| Android | `build/app/outputs/bundle/prodRelease/app-prod-release.aab` | 2.3.13 / 203131 | Production flavor; package/version manifest and JAR signature verified; release keystore configured |

Both use `BACKEND_BASE_URL=https://steptracker-api.org`. iOS carries the production ad units and Google client ID from `DEPLOYMENT.md`; Android omits unprovisioned Android ad units as documented. The What's New entry matches version 2.3.13.

SHA-256:

- IPA: `6a86c93ba8436a5bb054dd55693f9d14cd5bc56f059e7152dd72591d91be7dea`
- AAB: `fafa2f97008d5f504ad2f6e756f77571fe19f9833eb6e0b53e9d8ade03937b06`

Existing toolchain advisories remain: iOS default launch-image placeholder and future UIScene/Swift Package Manager migration notices; Android plugin Kotlin migration notices. These did not prevent either production build.

## Manual UI checklist

Run on both iOS and Android, including light/dark mode, a smaller phone, and larger system text:

1. Home → Shop on an account with unfinished Shop tutorial: step 1 fully surrounds both Store and Inventory and their outer edges. Advance then Back; the target remains covered and the callout does not overlap it.
2. Profile → Settings → Help & Legal → View Shop Tutorial: verify the same coverage during entry and after the navigation animation settles.
3. Referral contest: check prize text on overview/dashboard/rules, Official Rules on overview/dashboard, and the OPEN badge. Tap rules and return to confirm navigation.
4. Joined active team race → Activity & Chat: heading, selector, then panel; one selector only, with ACTIVITY / TEAM CHAT. Switch both ways and open the keyboard. Verify private messages/send audience and no selector remains above the composer.
5. Finished team race: selector remains above read-only history. Solo race: no team selector or leftover gap.
6. Onboarding demo race and Settings → View Tutorial race-detail preview: shared headers remain aligned and the Powerups & Boxes spotlight remains correct. These fixtures are solo, so verify the team selector in a real team race.

The general tutorial has a Home Shop launcher but no separate Shop-screen copy. Shop first visit and Settings replay both render the real ShopTab. Demo race and general tutorial race preview render the real RaceDetailScreen.

Physical-device checklist execution remains a user release check; this task supplies the checklist and automated screen coverage.
