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

Both signed platform artifacts verified. iOS build 5 is VALID / IN_BETA_TESTING and appears in the existing bara testers group.

Manual UI-placement checklist: [approved plan](unified-shop-requirements.md#manual-ui-placement-test-plan). Also check suggested races immediately after granting health access and after an ordinary app reopen, without pulling to refresh.

### Android candidate

- Signed prod AAB built successfully: version 2.3.13, versionCode 203135, package `com.rohanchari.steptracker`.
- Actual merged bundle manifest contains BILLING permission and Billing Client 8.3.0. JAR signature verified with no unsigned entries; upload certificate matches the trusted existing key.
- All three compiled architectures contain the production backend URL. Bundled coin PNGs match source byte-for-byte.
- SHA-256: `751e9f1ff3c2e68a057c88f7c8c91a7e23d80f42c189cc562795e42685b047dd`.
- Saved under `build/release-candidates/2.3.13-5/`. Android billing retains its existing unavailable behavior where store configuration is absent. AAB verified locally; no Play upload was requested or performed.

### iOS candidate

- Signed App Store IPA built successfully: version 2.3.13, build 5, package `com.rohanchari.steptracker`, team `4NRKZL9H5J`.
- Exported IPA signature verified with `codesign --verify --deep --strict`; production APNs, no debugger entitlement. Verified all 11 expected public production configuration values in the compiled executable and coin assets byte-for-byte inside the IPA.
- SHA-256: `83832eb683f14a462d9264cf1a4cd08f119c9319531d5df82a7847716d75f4af`.
- Saved under `build/release-candidates/2.3.13-5/`. Source commit `ec100d6` on `release/unified-shop-20260908`.
- Build succeeded with existing migration notices for UIScene/plugin Swift Package Manager support and a launch-image placeholder warning. No dependency or launch-screen change was part of this release.

### App Store Connect upload

- Xcode account upload completed September 8, 2026 at 20:37:55 EDT: both `Upload succeeded` and `** EXPORT SUCCEEDED **` confirmed.
- Non-blocking upload warnings: missing third-party dSYMs for AppLovinSDK and FBAudienceNetwork (same SDK warnings as the prior build). These limit symbolication inside those SDKs.
- No App Review submission or customer release performed. TestFlight processing confirmed below.

### TestFlight availability confirmed

- Apple build ID: `f5d2ee36-0956-492e-b1b2-e1d2d6b502a8`.
- Version **2.3.13 (5)**: processing `VALID`; internal state `IN_BETA_TESTING`.
- Confirmed this exact build in internal group **bara testers** (`944d87b7-f952-438f-9703-173504ca4f1d`).
- Recorded `usesNonExemptEncryption: false`, matching build 4; this frontend change introduces no cryptography.
- Final state captured in `build/release-candidates/2.3.13-5/testflight-status.json`.
- Manual checklist handed to the user through the approved requirements document; physical-device purchase/ad smoke checks remain for TestFlight testing.
