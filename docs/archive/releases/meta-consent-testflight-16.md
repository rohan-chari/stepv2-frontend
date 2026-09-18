# Meta consent fix — TestFlight 2.3.13 (16)

Uploaded on 2026-09-10 using the existing App Store Connect API key, as requested.
Xcode confirmed `Upload succeeded` and `EXPORT SUCCEEDED`. Apple subsequently
confirmed **VALID / IN_BETA_TESTING**, with the build present in the existing
**bara testers** internal group. No export-compliance or tester-group mutation
was necessary. [Apple status](artifacts/meta-gpp-fix-2026-09-10/testflight-build-16.json).

This build includes the [US consent parsing fix](meta-gpp-fix-validation.md).
All **3,315 Flutter tests** pass; static analysis is clean. Native policy tests,
99 independently encoded consent fixtures and 16 real-SDK offline checks pass.
Independent review approved the fix and release gates.

Signed iOS 2.3.13 (16) and Android 2.3.13 / 203146 artifacts passed package,
version, production configuration and signature checks. iOS native and Dart
Mach-O sections match across archive/export, and the native decoder is present.
Android's three packaged ABI libraries match fresh compiled/stripped output;
the production AdMob app ID and non-debuggable release state were verified.
Source fingerprints were checked again immediately before upload.

The IPA, AAB, full verification reports and source fingerprints are retained in
`build/verification/meta-consent-16/`.
[Artifact hashes and release checks](artifacts/meta-gpp-fix-2026-09-10/release-build-16.json).

Existing AppLovinSDK and FBAudienceNetwork missing-dSYM warnings were nonblocking.
No backend deployment, Play upload, App Review submission or customer release.
The fix reaches a device when it installs build 16; live US consent
allow/opt-out/regrant verification remains a physical-device check.
