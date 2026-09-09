# Timezone refresh release — 2026-09-09

Merged `codex/event-ends-timezone-20260909` into `main` and pushed the release source as `185efb7`. The implementation is `00c749e`: HTTP requests refresh the device timezone after timezone changes, with coalesced native lookups and a cached fallback. Existing API contracts remain compatible; the corresponding backend changes were deployed before this app release. The implementation received independent review before release.

## Verification

- Full Flutter suite: 3,114 tests passed; `flutter analyze` clean.
- iOS 2.3.13 (8): signed production IPA, correct bundle/team, production APNs, no debug entitlement. Verified all ten public production configuration values from README, including RevenueCat and seven retained AdMob units; inline native ad ID absent.
- Android 2.3.13 (203138): signed production AAB, correct package/version and upload certificate. Verified production URL and README Android ad IDs in all three architectures; inline native IDs absent.
- Android's first packaging pass retained compiled libraries from build 7. Removed generated JNI merge/native/strip outputs and rebuilt. Final packaged libraries match the fresh compiler outputs and differ from build 7 on all three architectures.
- No private keys or local secret files packaged. iOS coin artwork matches the source assets.
- Android was built and verified locally; no Play upload was requested or performed.

## Artifacts

Local ignored artifacts and verification logs are retained under `build/release-candidates/2.3.13-8/`.

| Artifact | SHA-256 |
| --- | --- |
| Signed local IPA | `6d6427638574a80cded074956632340e3529b02024af27cdabb9efc2639d8823` |
| Final Android AAB | `7ad0a5383794612eee7e7dd553930846524deb622cbf5d3c6b8b674865a10360` |

## TestFlight

The signed-in Xcode account uploaded the archive successfully at approximately 07:48 EDT. Both `Upload succeeded` and `EXPORT SUCCEEDED` were confirmed. Apple issued nonblocking missing-dSYM warnings for AppLovinSDK and FBAudienceNetwork.

Apple build `82322680-bbd1-4527-86cd-323720581429` is `VALID` / `IN_BETA_TESTING`, and membership in the existing internal **bara testers** group was confirmed. The unchanged exempt-encryption declaration was carried forward from build 7. A redundant group-assignment attempt returned HTTP 422 while automatic assignment completed; subsequent reads verified the intended build in the group. No App Review submission or customer release was performed.
