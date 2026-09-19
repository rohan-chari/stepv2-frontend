# TestFlight 2.3.14 (25)

Status: frontend fixes verified; corrected signed iOS archive and IPA built and verified. **Available in TestFlight for `bara testers`: Apple processing `VALID`, internal state `IN_BETA_TESTING`, and group membership confirmed.** Android explicitly excluded by the user. No App Review or customer release authorized.

Source: `main` at `ee55164` plus the local release-fix diff. Version advanced from the stale pubspec build 22 to 25 after App Store Connect confirmed 2.3.14 (24) as its latest build.

## Fixes and verification

- Gold carousel sizing now measures its actual horizontal and vertical insets, including the indicator area; membership price/badge layouts fit enlarged text.
- Demo target selection now supplies the v2 eligible-rival contract required by the real screen. Self, forfeited and hidden racers are excluded; the tutorial coach still enforces the scripted rival. All 21 demo/reel tests pass.
- Mystery-box reel centering accounts for its two-pixel border on each side.
- Admin cards provide a local Material surface so chart detail rows retain visible interaction feedback.
- Analyzer warnings/lints resolved. No backend API, economic policy, or native dependency changes.

Initial preflight on the untouched checkout: 3,583 passing / 86 failing tests and five analyzer issues. User explicitly approved migrating obsolete assertions with equivalent coverage on the accepted designs. No tests skipped. Migrations use current server-owned targeting fixtures, painted standings rank, current carousel/plan copy, current character renderer, and real admin overview/detail/Tools navigation. Intentional retired analytics remain absent. Retained loading, error/retry, zero/null, provenance, source denominator, operational tools, and accessibility coverage is preserved.

Validation: full suite **3,669 passed**. Three additional reviewer-requested retained-metric tests were then added; the complete admin metrics suite **18 passed**, covering exact ad viewers/grants, zero-denominator retention, and onboarding source/denominator. Final analysis clean after all additional assertions. Reviewer approves frontend changes; the original backend dependency finding and subsequent checkout verification are recorded below.

Logs and source fingerprints: `build/release-candidates/testflight-2.3.14-25/` (ignored local evidence).

App Store Connect build ID: `27aa07b4-bd3b-44ba-bc14-1dd542283f86`. Export compliance matches the preceding build (`usesNonExemptEncryption=false`); no encryption or native dependency changes were introduced.

## Verified artifact

- IPA: `build/release-candidates/testflight-2.3.14-25/Bara.ipa`
- Bundle: `com.rohanchari.steptracker`, version 2.3.14, build 25.
- SHA256: `035dc513cf4956e935b3afca94cb14684084614235e675880da25db52b0d172c`.
- Archive signature passes deep/strict verification. Production backend, OAuth, RevenueCat public key, all seven retained ad units, and native Meta configuration verified without printing tokens. Inline native ad defines absent; staging URL absent from compiled Dart binary.
- All 502 source/asset/Runner fingerprints unchanged across the final build.
- Build reports the existing default launch-image warning and plugin Swift Package Manager migration notices. Upload succeeded with exit code 0. Apple reported missing vendor dSYMs for AppLovinSDK and FBAudienceNetwork; these are non-blocking and limit symbolication for crashes inside those frameworks.

## Backend compatibility verification

Initial read-only inspection found both production HTTP processes running `/var/www/step-tracker-backend/src/index.js` at `bcaf50b`. Its target-context query emits `race-powerup-target-context-v1`. The frontend requires `race-powerup-target-context-v2` and correctly refuses untrusted target lists, so live targeted-powerup actions would fail before presenting a picker.

Reviewer identified merged backend PR #3 (`a809ae5`, first-parent delta) as an isolated candidate: seven runtime files and two unit-test files; no migrations, package, environment, or topology changes. Read-only patch applicability check against production succeeded. It has **not** been applied or validated with real HTTP integration tests against a local test database. Backend main also includes a much broader queue/worker rollout and must not be deployed wholesale as a side effect of this frontend release.

The user deployed the backend independently and explicitly instructed proceeding with TestFlight. A subsequent read-only check confirmed the production checkout is now `e3e78ff5`, with `race-powerup-target-context-v2` in both target-context response paths. This verifies checked-out source, not an authenticated live target-selection request.

Production health and Redis reported OK. Social rewards are already present; no dependency blocker there. No backend mutation, restart, staging start, or deploy occurred.

## Manual placement checklist

Not yet performed on a physical device:

- Shop → Featured: cycle all four Gold benefits on narrow and wider iPhones. Text, icons, dots, and upgrade button must fit without overlap in light/dark and enlarged text.
- Open the Gold modal: check both plans and the selected monthly crossed-out-price state. Cards remain symmetric; badge, prices, intervals, subscription button, and footer remain contained and reachable.
- Daily spin → Remove ads: repeat the large-text plan check on the standalone Gold page. Race-results and box-reroll links reuse this body.
- Rotate the phone: the app should remain portrait without clipping.
- Tutorial: finish the Shortcut picker lesson through the win card; the user is excluded and all three rivals are shown, while the coach rejects an off-script choice. Check the idle/opened reel centers beneath its pointer.
- Daily reward and active race boxes: check idle and landed centering. Repeat with Open All, inspecting every independently stacked reel.
- Admin → Growth, Activity, Races & friends, Ads: expand/collapse daily chart values. Rows stay inside their card and push later cards down without overlap; repeat large-text light/dark. System health and Tools remain reachable.

UI planner confirmed the Shop/Gold layouts are not duplicated in tutorial previews, and Get Coins' Gold card is disabled in source. The tutorial adapter and shared reel are explicitly tested above.
