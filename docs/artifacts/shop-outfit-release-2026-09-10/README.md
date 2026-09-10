# Shop/outfit release verification

Runtime source: `5071aa2` (includes the preceding Shop/billing repair `09f92e2`).
Final full Flutter suite: **3,309 passed**. Flutter analysis clean. Both rounds of
independent final code review returned SHIP with no issues. Manual device checks:
[Shop/outfit checklist](../../shop-outfit-release-checklist.md).

- iOS: Bara **2.3.13 (14)**, distribution-signed, production APNs, non-debuggable.
  Verified required README configuration in the actual exported app/native plist;
  CoreKit present; Login/Share frameworks absent. Checked current scene/status
  strings and exact Hitchhike/Turtle artwork bytes. Export and archive signatures
  both pass; every file-backed Mach-O section and UUID matches across re-signing.
- Android: **2.3.13 / 203144**, production flavor, trusted upload signature,
  billing permission/client present. Fresh compiler output matches both JNI merge
  stages. The packaged libraries match the stripping outputs; every allocated ELF
  section matches fresh compiler output for arm64-v8a, armeabi-v7a and x86_64.
  Required Android README configuration, current UI and artwork verified.
- No credential files are bundled. The ASC private key remains outside the repo;
  ignored local `.env` contains only its references. Meta client token values were
  compared without printing them. Android omits Meta defines as documented.
- Preserved artifacts: `build/verification/shop-outfit-14/Bara.ipa` and
  `build/verification/shop-outfit-14/app-prod-release.aab`.

See the adjacent sanitized verification reports for checksums. No backend runtime
change or deployment was needed. No paid purchase was made during validation;
real StoreKit and RevenueCat product availability evidence is recorded separately.

Apple upload succeeded. Build14 is **VALID / IN_BETA_TESTING** and present in
**bara testers**, confirmed2026-09-10T13:34:34Z; see `testflight-status.json`.
Existing AppLovinSDK/FBAudienceNetwork missing-dSYM warnings did not block upload.
No App Review submission or customer release was performed.
