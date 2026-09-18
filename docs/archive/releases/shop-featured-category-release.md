# Featured category TestFlight revision

User explicitly requested the existing Shop layout be restored, with Featured alongside the existing Store categories and compact purchase tiles, then deployment to TestFlight.

## Candidate

- iOS 2.3.13 (6), Android versionCode 203136; local main in both repos.
- Backend remains 7e27dc1, already deployed. No product, economic, API, migration, or release-flag changes.
- Reuses build 5 imagegen coin sacks and existing membership checkout/management body.
- iOS production configuration retains the same 11 public build values; Android retains existing unavailable billing until its store configuration is supplied.

## Verification checklist

- Failing-first placement and exact grid-geometry regressions; preserved purchase/account/tutorial tests.
- Actual normal/narrow/enlarged-text and dark-mode renders of Featured, categories and membership details.
- Clean Flutter analysis, full suite and independent code review.
- Signed Android/iOS artifacts, compiled production URL and packaged artwork, correct versions and signing identities.
- Xcode upload success and exact build 6 VALID / IN_BETA_TESTING in bara testers.

Manual checks: [revision checklist](shop-featured-category-revision.md#manual-ui-placement-checklist).

## Intermediate checks

- Five new acceptance tests first failed against build 5 UI: extra ITEMS selector, oversized packs/membership controls, missing Store/Inventory on Featured. All five pass after implementation, including exact Powerups grid geometry at 320/390/800 widths.
- Initial actual-widget captures passed 7 render checks. Visual review required replacing wrapped categories with one horizontally scrollable row.
- Review found that the modal membership body must rekey when billing account changes; fixing before final verification.


## Final review and platform evidence

- Independent review: SHIP; no remaining blockers/issues/nits. Membership account switches remove only the owned sheet; pending action completion and unrelated routes are covered. Bootstrap loading retains the open membership details.
- Category controls remain one horizontal row. Four labels fit at normal phone size; enlarged text scrolls horizontally. Store-only Featured and remembered Inventory category are covered.
- Seven actual Flutter captures passed; saved in `docs/design/shop-featured-category/` (preview prices and simulated billing, no charges).
- Final analysis: No issues found. First complete suite found 19 obsolete offscreen-category tap failures; shared scroll-aware test navigation fixes preserve all assertions. Their affected suites pass 45+18 tests. Final stable suite: **all 3,107 tests passed**.
- Android signed prod AAB 2.3.13/203136 verified: package, Billing 8.3.0 metadata/permission, full JAR signing and trusted certificate. Production URL verified in all 3 architectures; bundled sack PNGs match source bytes.
- Android SHA256: `ccdd2703785724d279c4b985c0ac4a0e6689abccaa15c23bfeac6489bbc179e0`. Artifact preserved in `build/release-candidates/2.3.13-6/`; no Play upload requested.

- iOS App Store IPA 2.3.13 (6) verified with strict codesign, production APNs, no debugger entitlement, expected bundle/team, all 11 public production configuration values and byte-exact packaged artwork.
- iOS SHA256: `3b0d81c766403a042d4afc8f2eadabe55d7564473f4b6da0c293cb49187c4a29`. Preserved with Android artifact under the candidate directory.
- Live-money purchases and physical-device ad flows were not exercised. Native builds and real-widget tests passed; device smoke testing remains for testers.
- Xcode upload completed September 8, 2026 at 21:20:16 EDT with both `Upload succeeded` and `** EXPORT SUCCEEDED **`. Apple TestFlight availability confirmed below.
- Existing non-blocking third-party dSYM warnings: AppLovinSDK and FBAudienceNetwork. Build also reports existing UIScene/plugin migration and launch-image placeholder notices; no native dependency or launch-screen change in this revision.
- Source commit `30f5960` on local `main`; no remote push or branch deletion. No App Review/customer release or backend deployment.

## TestFlight confirmed

- Build **2.3.13 (6)**, ID `5800251f-889c-41f0-9000-e86173b14a0c`: processing `VALID`, internal state `IN_BETA_TESTING`.
- Exact build verified in **bara testers** group `944d87b7-f952-438f-9703-173504ca4f1d`.
- Exempt-encryption declaration matches build 5; this layout change adds no cryptography.
- Verification record saved under `build/release-candidates/2.3.13-6/testflight-status.json`.
- All 3,107 tests passed; analysis clean; independent review SHIP; both signed artifacts verified.
- Manual checklist handed to user: [Featured category checklist](shop-featured-category-revision.md#manual-ui-placement-checklist). Device purchase/ad smoke checks remain for TestFlight testers.
