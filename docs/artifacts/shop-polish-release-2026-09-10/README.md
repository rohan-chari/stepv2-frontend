# Shop polish release verification

Runtime source: `12bf042`. Flutter full suite: **3,315 passed**. Flutter analysis clean. Independent code review: **SHIP**, no outstanding findings.

- iOS: **2.3.13 (15)**, distribution signed, production APNs, non-debuggable. Actual exported IPA and archive signatures pass; Mach-O sections and UUID match across export. README configuration, CoreKit, current UI strings, and exact Turtle/Hitchhike artwork verified.
- Android: **2.3.13 / 203145**, production flavor, trusted upload signature. Fresh compiler output matches JNI merge stages; packaged code matches stripped output and all allocated ELF sections for all three ABIs. Production defines, current UI, artwork and billing manifest verified.
- No credential files bundled. Existing ASC key remains outside the repository; ignored local environment stores references. No backend runtime change or deployment required. Purchase amounts and fulfillment behavior are unchanged.
- Artifacts: `build/verification/shop-polish-15/Bara.ipa` and `build/verification/shop-polish-15/app-prod-release.aab`. Checksums are recorded in adjacent reports.

[Manual UI checklist and capture evidence](../../shop-polish-validation-2026-09-10.md). Physical-device visual acceptance remains the user checklist; automated fixture checks cover light/dark and enlarged text.

Apple upload succeeded (Xcode reported Upload succeeded and EXPORT SUCCEEDED). At 2026-09-10T14:06:42Z the Apple build-list API had not listed build 15 yet; TestFlight readiness is not yet confirmed. See `testflight-status.json`. Existing AppLovinSDK/FBAudienceNetwork missing-dSYM warnings did not block upload. No App Review submission, customer release, or Play Store upload is included.
