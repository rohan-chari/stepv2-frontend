# Unified shop TestFlight release

User approved the unified-shop design and TestFlight upload, then requested the Home suggested-races loading fix in the same build.

## Candidate

- Version 2.3.13, iOS build 5; matching Android versionCode 203135.
- Production backend URL; existing iOS RevenueCat/OAuth/AdMob public build values preserved.
- Backend contract verified unchanged locally and on production at 7e27dc1. No backend deploy, migrations, product/price/reward changes, or release flags.
- Apple read-only preflight: latest 2.3.13 build 4 is VALID / IN_BETA_TESTING. Play read-only preflight: latest bundle 203133; signed Android key fingerprint matches the trusted existing upload certificate.

## Included Home bug fix

Reproduced through the real MainShell: cold startup returns at the health-permission gate; granting health access then called the step and main-card paths without ever loading suggestions. Home became visible with zero suggestion requests and stayed on the initial skeleton. Added the missing discovery request beside the existing main-card request in the health-grant path, without waiting on secondary friends/profile refreshes. Normal startup keeps its existing persistence-before-Home-read dependency graph.

A second regression reproduced an interrupted or never-completing suggestion response leaving the shell loading indefinitely. The shell now catches failures and bounds the complete fetch at 20 seconds, preserving cached cards or showing its existing retry state. Late responses cannot overwrite the completed/newer state. The shell owns each response deadline and cancels/settles it on disposal, so leaving Home cannot leave a timeout pending. No periodic retry or extra polling is added; successful normal startup still issues one compact discovery request. The health-grant path changes from zero discovery requests to the one required request.

Tests written and run red before logic: missing request (expected 1, got 0), uncaught response exception, and stalled loading state. All three new regressions pass after the fix, including rendering a real suggested race without pulling, retry recovery, and rejecting late failed responses.

## Artwork

Three built-in-imagegen coin sacks installed with transparent alpha; visual white/green checks at 100px confirmed distinct increasing fullness and no paw icons. Editable Aseprite sources round-trip exactly; targeted export cases installed in local art repository. Prompts and source context: [artwork](design/unified-shop/artwork.md).

## Review and intermediate verification

- Independent code reviewer cleared compatibility, checkout preservation, preview isolation and the final Home deadline lifecycle.
- Review found and fixed missing catalog callbacks on Home + and Profile membership routes. Real-shell regressions equip an owned accessory through each entrance and verify Home immediately renders it.
- Actual Flutter renders checked Featured, Coins, expanded membership, Items, dark theme, and 320px enlarged text. Captures in `docs/design/unified-shop/implemented-*.png` use isolated preview billing and sample prices, not a live purchase session.
- First complete suite exposed disposal timers in existing shell tests and one obsolete Get Coins heading assertion. No protected behavior assertions were removed. Owned deadlines fixed the timer failures; targeted onboarding/activation/ad-placement/main-shell batch passed 135 tests and share-link batch passed 5 tests. The final full-suite run follows all corrections.

## Final application verification

- `flutter test`: all **3,098 tests passed** after the final fixes.
- `flutter analyze --no-pub`: **No issues found**.
- Independent code review: **SHIP**, no remaining blockers/issues/nits.
- Seven actual-widget visual captures passed: Featured, Coins, membership, Items, dark theme, narrow Coins and narrow membership at 1.6× text. Membership cosmetic copy and plan choices now stack at constrained sizes.
- Preview tests cover unavailable/loading/error/pending billing, unchanged membership semantics, tutorial isolation and retained Items flows. No live-money purchase or physical-device ad flow was exercised in this session.
- Existing backend contract and defensive parsing retained: frozen clients are unaffected and the new binary requires no new endpoint or server field.

## Platform release verification

Signed platform builds and TestFlight processing verification are in progress. This document is not a release-success claim until evidence is recorded below.

Manual UI-placement checklist: [approved plan](unified-shop-requirements.md#manual-ui-placement-test-plan). Also check suggested races immediately after granting health access and after an ordinary app reopen, without pulling to refresh.
