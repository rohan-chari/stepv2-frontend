# Android parity and billing bootstrap — release handoff

This candidate fixes Android cold-start step loading and the approved Android parity gaps. It enables the Google Play product-creation prerequisite through a newly signed bundle containing `com.android.vending.BILLING` and Play Billing client metadata. Purchase completion is a separate store/backend setup milestone.

## Validation

- `flutter analyze --no-pub`: no issues.
- Full Flutter suite: 3,074 passed; one existing remote-asset cleanup race failed. The test now joins its background prefetch before teardown, preserving all assertions; affected suite: 17 passed. No unresolved test failures.
- Android native tests: 35 passed, covering native settings/ad binding and worker read/permission/pagination failures.
- Bundle verifier: seven tests passed, including missing permission, wrong package/version, absent billing metadata and partially unsigned archive rejection.
- Architect and final code reviewer: approved; no remaining blockers.
- Physical Android/iOS permission prompts, Health Connect provider timing, native ad fill and real purchase lifecycle are not claimed as tested. Use the [manual device checklist](android-parity-billing-readiness-requirements.md#manual-ui-placement-test-plan).

## Store setup boundary

Production backend currently lacks billing routes/configuration. This app handles older backends and missing public SDK keys safely, leaving checkout unavailable. RevenueCat public SDK keys were unavailable for these bootstrap builds. No placeholder key is embedded. This does not prevent a correctly packaged Billing-enabled AAB from satisfying Play's binary prerequisite for creating products.

Before customer purchases: configure store products and RevenueCat, supply the correct public SDK keys in both platform builds, deploy the separately approved additive billing backend, and verify sandbox purchase/restore/renewal/cancellation/refund behavior. See [store setup](bara-billing-store-setup.md). This handoff does not claim live checkout is ready.

Android production ad units are not provisioned; Android ads remain unavailable under the existing configuration. The native factory and real-list placement are implemented for the correctly configured build. iOS uses the established production units. No new rollout flags or API dependencies were added.

## Release actions

No deployment or upload has been performed. Upload the verified new prod-package AAB to the appropriate Play internal/draft release; let Play process it and confirm Billing permission, then create products. The older local `2.3.13 (203131)` bundle lacked Billing; changing a source manifest cannot update that uploaded binary.

Both platforms use version `2.3.13`, iOS build `3`, Android mapped versionCode `203133`, and `https://steptracker-api.org`. Both final artifacts were built, signed and verified successfully; checksums are recorded below.

Version audit: the prior iOS IPA dated September 7 already used `2.3.13 (2)`, so this candidate advances pubspec to `2.3.13+3` and Android to `203133`.

Build warnings: existing iOS launch-image placeholder warning and plugin migration/dependency update warnings are outside this parity change. They did not fail compilation/signing.

## Verified Android artifact

- File: [Bara-2.3.13-203133.aab](../build/release-candidates/2.3.13-3/Bara-2.3.13-203133.aab)
- Package: `com.rohanchari.steptracker`; version `2.3.13 (203133)`.
- Compiled manifest: `com.android.vending.BILLING`; Billing Client metadata `8.3.0`. BillingClient references are present in `classes.dex` and `classes3.dex`.
- Production backend URL verified in compiled Dart library.
- JAR signature verified with no unsigned-entry warning; certificate matches the configured upload keystore.
- SHA-256: `b38db37e91075aed67db649317e88fba729965a8a96909f2d7300fefb9e34ed0`
- Upload certificate SHA-256: `CF:06:4C:DD:CA:14:CB:6B:27:91:BC:86:77:39:EF:14:EC:0E:AE:13:3C:68:E2:71:30:E5:0D:0F:8B:EE:14:3A`

## Verified iOS artifact

- File: [Bara-2.3.13-3.ipa](../build/release-candidates/2.3.13-3/Bara-2.3.13-3.ipa)
- Bundle: `com.rohanchari.steptracker`; version `2.3.13 (3)`.
- Apple Distribution signature verified recursively with strict validation; team `4NRKZL9H5J`.
- Distribution provisioning: production APNs, `get-task-allow=false`, correct application identifier.
- Production backend URL verified in compiled Dart library.
- SHA-256: `2323ff94e546146d127dcee0074ab4c6d1946d9ed1831055a9386e4d05c21a57`

## Readiness decision

Ready for production app-candidate upload and Google Play product setup. Code review, analysis, relevant tests and both signed builds are complete. No deployment/upload has occurred. Customer checkout still requires the store/backend setup and sandbox validation described above; manual device checklist remains with the tester.
