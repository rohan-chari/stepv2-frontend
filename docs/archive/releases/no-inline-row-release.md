# Remove inline-row ad from TestFlight release

Candidate: iOS 2.3.13 (7), Android 2.3.13/203137.

The prior production release configuration included the native inline-row ad.
Remove its existing build define from the saved iOS production configuration
and release instructions. Preserve all seven other iOS ad units: daily spin,
box reroll, footer banner, double payout, box-top banner, race-detail exit,
and race-results exit. Android retains the README’s provisioned rewarded-spin and footer-banner units
and omits native and unprovisioned ad units.

No Dart business logic, backend, API, or runtime controls change. The existing
native-unit gate prevents loading and renders zero height when the define is
absent. Older installed versions retain their baked configuration and remain
compatible with the unchanged API.

## Validation

- Flutter analysis clean.
- All 39 relevant existing tests passed: ad placement, banner control, SDK
  initialization safety, and races-tab state pills (including zero-height
  native placement without its unit).
- Independent code review: SHIP, no blockers, issues, or nits.
- Signed iOS IPA verified: version 2.3.13 (7), expected package/team,
  production APNs, no debugger entitlement, all ten public production values
  present (seven ad units, RevenueCat, backend, Google OAuth), inline-row ID
  absent. Bundled coin artwork remains byte-exact.
- Signed Android AAB verified: 2.3.13/203137, expected package and trusted
  upload certificate, Billing 8.3.0. Production URL and README spin/banner
  IDs present in all three architectures; both native ad IDs absent.
- Android packaging initially reused stale merged JNI libraries. Rebuilt
  affected generated intermediates and verified the final packaged binaries.
- Artifacts and reports preserved in `build/release-candidates/2.3.13-7`.
- Xcode upload succeeded September 8, 2026 at 23:37 EDT; both
  `Upload succeeded` and `EXPORT SUCCEEDED` recorded.
- Existing non-blocking AppLovinSDK/FBAudienceNetwork missing-dSYM warnings
  remain. No backend deployment, Play upload, or App Review submission.

## Manual UI checklist

- On the new iOS and Android builds, open populated Active, Pending, and
  Completed Races lists and scroll to their ends. Confirm no inline ad or
  ad-sized gap. Switch tabs and return; confirm it stays absent.
- Open Settings → Help & Legal → View Tutorial and inspect the Races steps.
  Confirm no inline ad/gap and that race cards, boxes, and spotlights align.
- On iOS, check existing footer/box-top banners and eligible daily extra-spin,
  box-reroll, double-payout, and race-detail/results exit ad placements.
  Availability depends on eligibility and ad fill.
- Demo race onboarding and tutorial race-detail previews use RaceDetailScreen,
  which has no inline-row placement; confirm their existing layout remains.

Physical-device checks remain for testers.

## TestFlight confirmed

Build 2.3.13 (7), ID `a8df209b-c567-4c11-a2be-1eeb6eb18452`, is VALID /
IN_BETA_TESTING and present in the existing **bara testers** group. The exempt
encryption declaration matches build 6; this configuration change adds no
cryptography. Status evidence is saved with the release artifacts.
