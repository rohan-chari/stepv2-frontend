# Admin analytics TestFlight release — 2.3.14

User authorized a TestFlight upload, all pending frontend changes in one commit, and version 2.3.14. iOS target is 2.3.14 (1); matching Android versionCode is 203154. The Android counter remains monotonic above 203153: the prior version's more-than-ten uploads exhausted the documented decimal slot scheme, so the naive 203140 value cannot be used.

## Scope

The release includes shared admin snapshot freshness, bounded visible-screen refresh polling, purchase history with usernames for all three requested purchase categories, and the readable Mystery Box placeholder label. Remaining pending research documents, economy analysis and mouse-art source artifacts are included in the same frontend commit. Secrets and ignored build artifacts remain excluded. The new What's New entry matches 2.3.14.

Backend runtime 9f6add4 is already deployed. Its additive API remains compatible with older app binaries; this build can also tolerate absent purchase history on an older backend. Admin snapshots are request-triggered, not scheduled by cron: a request after 15 minutes starts one refresh while returning the previous snapshot. The visible frontend checks every 15 minutes and uses bounded follow-ups for a completed refresh.

## Validation

- 57 focused real-widget and API tests passed for admin snapshots, purchases, wire contracts and Mystery Box labels.
- 13 existing What's New tests passed after the version entry was added.
- Final analyzer clean after the version/copy update.
- Independent reviewer: SHIP for admin changes and the additional Mystery Box label correction.
- Earlier full-suite baseline failures remain disclosed in `admin-analytics-snapshots-verification.md`; complete repository suites are not claimed green.
- Manual iOS/Android placement checklist remains in `admin-analytics-snapshots-purchases-requirements.md`.

Signed native artifacts were verified before upload; Apple processing results are recorded below. This request does not include App Review submission, customer release or Google Play upload.

The first Android build reported success but artifact validation rejected stale merged/stripped Dart libraries from an older build. Those generated outputs were preserved outside the build directory, and a clean-output rebuild with Gradle build-cache reuse disabled succeeded. The final AAB matches fresh compiler output on arm64-v8a, armeabi-v7a and x86_64, including every allocated ELF section. No failed artifact was uploaded.

## Verified artifacts

- iOS 2.3.14 (1): production bundle ID/APNs/signatures/Meta settings and all README defines verified. Archive and export Mach-O sections/UUIDs match. IPA SHA-256: `ea29dd16526bf5130e248569b2b0ebb43e117d519a703ca6bcf0e10d53efc2d0`.
- Android 2.3.14 (203154): upload certificate, production manifest/ad app ID, required configuration and all three fresh native libraries verified. AAB SHA-256: `9096048befbc34cd2727313fcc835579b1a5c66783482e641864fa862319418e`.
- All 546 application/native/assets source fingerprints remained unchanged through upload preflight. Artifacts and detailed reports are retained under ignored `build/release-candidates/admin-analytics-2.3.14-1`.

## TestFlight completion

Upload completed successfully at 2026-09-13T20:53:41Z using the configured App Store Connect API key. Apple build `c44d2d82-134b-4733-aeb4-15d77d253bce` is **VALID / IN_BETA_TESTING**, with membership in the existing **bara testers** internal group confirmed at 2026-09-13T20:59:54.678Z. The unchanged exempt-encryption declaration matches build 2.3.13 (23). Existing AppLovinSDK and FBAudienceNetwork missing-dSYM warnings did not block upload or processing. No App Review submission, customer release, new tester invitation or Play upload occurred.

All pending frontend files are included in the single 2.3.14 release commit. Ignored credentials and native build outputs remain outside Git.
