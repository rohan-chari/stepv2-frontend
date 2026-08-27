# Liftoff Monetize AdMob mediation requirements

## Summary and user story

Bara will add Liftoff Monetize as an in-app bidding demand source behind the
existing Google AdMob mediation layer. A user sees the same banner, rewarded,
and interstitial placements and reward semantics as today; Liftoff only adds
another bidder that may fill an existing AdMob request. Bara's existing native
AdMob surface receives no Liftoff demand in this release.

As the publisher, Rohan wants Liftoff active for Bara's existing iOS inventory
and adapter-ready on Android for later dashboard activation, without changing
ad-unit IDs, server-side reward verification, ad placement, or behavior for
already-shipped app versions.

The iOS Liftoff dashboard and AdMob mappings already established during setup
are:

- Application ID: `6a8fa46cee6b3074e0dd0999`
- Interstitial placement: `LIFTOFF_INTERSTITIAL-9752413`
- Rewarded placement: `LIFTOFF_REWARDED-3621920`
- Banner placement: `LIFTOFF_BANNER-2753052`
- `app-ads.txt`: `vungle.com, 6a8fa2a9a58d1846183babbd, DIRECT, c107d686becd2d77`

## Scope

- Add Google's official `gma_mediation_liftoffmonetize` Flutter adapter pinned
  exactly to `1.5.2`, the release built against `google_mobile_ads` 9.0.0.
- Resolve and lock the transitive Liftoff SDK and Google mediation adapters on
  iOS and Android.
- Add the exact current Liftoff SKAdNetwork identifiers that are not already
  present to `ios/Runner/Info.plist`, deduplicated against the existing list.
- Preserve existing Meta, Unity, ironSource, and AppLovin adapters.
- Ensure the adapter initializes through the existing guarded
  `MobileAds.instance.initialize()` path in `lib/services/ad_service.dart`.
- Integrate Google UMP on both platforms: refresh consent information on every
  launch, show the AdMob-configured form when required, and do not request ads
  until `ConsentInformation.instance.canRequestAds()` is true.
- Add a conditional `PRIVACY AND COOKIE SETTINGS` action to Settings under
  `HELP & LEGAL`, immediately before the existing `PRIVACY POLICY` row. Show it
  only when UMP reports that a privacy-options entry point is required; tapping
  it calls `ConsentForm.showPrivacyOptionsForm` and retains the established
  `_SettingsActionTile` visual language.
- Document Liftoff dashboard mappings, app-ads.txt authorization, privacy
  obligations, Ad Inspector validation, and iOS/Android release checks in
  `DEPLOYMENT.md`.
- iOS is the activated platform for this release. Android must compile and ship
  with the compatible adapter so later activation requires only creating the
  Android Liftoff application/placements and mapping them in AdMob. Record
  future Android IDs in deployment documentation; they are dashboard data, not
  build-time secrets and are not read by Dart code.

## Non-goals

- No new ad surfaces. The only visible UI change is the conditional UMP privacy
  options row required for consent revocation/US-state choices.
- No changes to existing AdMob app IDs or ad-unit IDs.
- No new feature flag, rollout percentage, runtime toggle, or dart-define.
- No direct use of Liftoff's standalone SDK API and no replacement of AdMob as
  the mediation platform.
- No waterfall mapping, bidding floor, or price/economy change.
- No backend API, database, reward, SSV, or coin-economy change.
- Native Liftoff demand is deferred until a Liftoff native placement is created
  and mapped in AdMob; the adapter may support native ads, but this change does
  not silently activate an unmapped format.

## Existing implementation and exact change path

- `pubspec.yaml` currently declares `google_mobile_ads: ^9.0.0` and
  `gma_mediation_unity: ^1.9.0`; add
  `gma_mediation_liftoffmonetize: 1.5.2` beside those dependencies and refresh
  `pubspec.lock` with `flutter pub get`.
- Expected resolutions are Android adapter `7.7.7.0` with Vungle SDK `7.7.7`
  and iOS adapter `7.7.6.0` with Vungle SDK `7.7.6`. Any different resolution
  stops implementation for compatibility review.
- `android/app/build.gradle.kts` pins the direct ironSource adapter. Do not add
  a second direct Liftoff Android artifact unless dependency resolution proves
  the Flutter plugin does not bring it transitively. Inspect the Gradle release
  dependency graph to confirm exactly one compatible Liftoff adapter/SDK.
- `ios/Podfile` manually pins Meta, AppLovin, and ironSource adapters while
  Flutter plugins install their own pods. Let the Liftoff Flutter plugin own its
  iOS adapter unless CocoaPods compatibility requires an explicit pin; never
  loosen the existing pins merely to make resolution succeed.
- `ios/Runner/Info.plist` contains a large deduplicated SKAdNetwork list. Merge
  Liftoff's current official list, retain every existing identifier, and add a
  dated source comment.
- `lib/services/ad_service.dart` owns SDK initialization. The mediation adapter
  must use that existing initialization and must not initialize a second ad
  stack. Liftoff privacy calls, if required by the selected adapter version,
  must be added as independently guarded initialization seams before Mobile Ads
  initialization so failure cannot disable the rest of the app.
- Add a small consent coordinator/service around the UMP APIs exposed by
  `google_mobile_ads`. Create exactly one app-lifetime instance after Flutter's
  binding and root presentation surface exist; start it once from the app shell,
  and inject/share it with every ad path and Settings. A consent refresh/form
  error fails closed for that launch: ads
  remain unavailable, existing ad slots collapse through their current failure
  behavior, and a later launch retries. Do not initialize Mobile Ads merely
  because a stale cached consent value says ads were previously allowed.
- `lib/screens/settings_screen.dart` adds the conditional privacy-options action
  in the existing `HELP & LEGAL` section. Inject the coordinator/query seam so
  the real screen is widget-testable without invoking platform channels.
- `test/unity_ads_mediation_dependency_test.dart` is the existing structural
  adapter guard. Rename/generalize it or add a Liftoff-specific structural test
  without weakening any Unity/Meta/AppLovin/ironSource assertions.
- `test/ad_sdk_initialization_safety_test.dart` exercises independently guarded
  privacy initialization. Extend it first only if Liftoff requires an explicit
  runtime privacy call.

## API contract

No frontend/backend API contract changes. Existing AdMob requests and existing
SSV callbacks remain byte-for-byte unchanged. Liftoff's application and
placement identifiers live in AdMob's server-side mapping and are not sent to
the Bara backend.

Older app versions do not bundle the Liftoff adapter. They continue requesting
the same AdMob units; AdMob skips Liftoff when the client has no compatible
adapter and existing demand sources remain eligible. New builds can receive
Liftoff bids after their adapter is present.

## Data model and migrations

None. No database changes, backfills, seeds, or production data writes.

## Frontend behavior

There are no new screens, widgets, states, or placements. Existing ad loading,
loading failure, collapsed banner, rewarded completion, and SSV behavior remain
unchanged. A Liftoff no-fill or adapter failure degrades to the existing AdMob
mediation auction and current UI failure handling.

Both iOS and Android compile from the same Dart dependency and UMP path. iOS
must pass Liftoff device validation now. Android must pass compilation and UMP
validation now; Liftoff single-source validation remains a documented future
activation step because the user explicitly deferred Android dashboard IDs.

## Privacy and store declarations

- Initialization order is exact: create a stable Flutter presentation surface;
  UMP consent refresh; required UMP form; fresh `canRequestAds`; partner consent
  propagation; iOS ATT and Meta advertiser-tracking propagation; debug request
  configuration; then `MobileAds.initialize()`. No ad object may be constructed
  before this sequence grants ad requests.
- Use the Google UMP flow configured in AdMob on both platforms. Call
  `requestConsentInfoUpdate()` on every launch, then
  `loadAndShowConsentFormIfRequired()`, and only initialize/request Mobile Ads
  after `canRequestAds()` is true. UMP writes the applicable consent strings for
  Google and mediation adapters; no guessed GDPR/US-state boolean is permitted.
- Liftoff 1.5.2 automatically reads UMP's GDPR Additional Consent signal. For
  US-state consent, add a platform consent-signal reader for UMP-written IAB
  TCF/AC/GPP values and map only a determinate opt-out/consent choice to
  `GmaMediationLiftoffmonetize.setCCPAStatus()` before Mobile Ads initialization.
  Update the existing Unity GDPR/CCPA propagation from the same authoritative
  state. Unknown, absent, malformed, or failed reads invoke neither partner
  setter; they are never coerced to `false`. Cite the selected partner setter
  semantics and covered IAB GPP sections in code comments and tests before
  production logic is written.
- Query `getPrivacyOptionsRequirementStatus()` after the refresh and expose the
  Settings entry point only when required. The action reopens the Google-managed
  privacy options form so EEA/UK/Swiss revocation and applicable US-state
  choices remain available.
- When that form completes, re-query `canRequestAds` and requirement status,
  republish coordinator state, refresh determinate partner signals, and
  invalidate/dispose future cached ad loads if permission has been withdrawn.
  Guard against repeated taps while a form is open. Use the stable widget key
  `settings-privacy-options`.
- The UMP path must expose independently guarded, injectable initialization
  seams and be covered first in
  `test/ad_sdk_initialization_safety_test.dart`.
- Add Liftoff to AdMob Privacy & messaging's GDPR and US-state ad-partner lists.
- Review App Store privacy nutrition labels and Play Data safety disclosures
  against Liftoff's current data disclosures before release and record the
  result in the release checklist.

## Backward compatibility and rollout

- No backend deployment is required; the public `app-ads.txt` Liftoff record is
  already deployed and additive.
- Existing binaries remain safe because all AdMob units, SSV data, and backend
  allowlists are unchanged.
- Ship the adapter permanently in the next iOS and Android builds; no release
  flag is permitted or needed.
- Dashboard mappings may exist before the carrying app build: old binaries
  simply cannot load Liftoff's adapter and fall through to other demand.
- iOS and Android must both build successfully and implement UMP before release.
  iOS Liftoff mappings and device validation are required now. Android Liftoff
  dashboard activation is explicitly deferred, but the adapter must be present
  and dependency-compatible so activation is server-side plug-and-play later.

## Tests-first plan

1. Extend the structural mediation dependency test before editing dependencies.
   It must require the official Liftoff Flutter plugin, preserve the current
   Google Mobile Ads and other mediation pins, require the resolved Liftoff
   adapter/SDK in both lock/dependency artifacts, and require the official iOS
   SKAdNetwork identifiers.
2. Add UMP coordinator tests before implementation: required form shown before
   ads, not-required path initializes once, `canRequestAds == false` never initializes,
   refresh/form errors fail closed and retry next launch, and simultaneous ad
   surfaces share one consent/bootstrap flight.
3. Add Settings widget tests before implementation: the privacy row appears
   immediately before Privacy Policy only when required, tapping it invokes the
   injected form seam once, errors do not crash, and absence preserves layout.
   Also test repeated-tap suppression, Settings opened before any ad surface,
   and form completion changing permission from allowed to disallowed: state is
   republished, partner signals refresh, and future/cached ad loads are stopped.
4. Add a launch-bootstrap widget test proving the app-lifetime coordinator runs
   without any ad widget being mounted.
5. Run the new focused tests and observe the correct missing-behavior failures.
6. Add the dependency, UMP coordinator/settings row, resolve packages/pods, and
   merge the SKAdNetwork list.
7. Re-run focused tests and existing ad SDK initialization safety tests.
8. Run `flutter analyze` and the full `flutter test` suite.
9. Build iOS with the production backend and existing production ad defines.
10. Build Android `prod` with the production backend and the existing Android ad
   defines. Run Gradle `dependencyInsight` against
   `prodReleaseRuntimeClasspath` for the Liftoff adapter and Vungle SDK. Inspect
   iOS `Podfile.lock` for the expected iOS adapter/SDK, and verify the resolved
   GMA versions remain compatible with every preserved adapter.
11. On a physical iOS device, enable Liftoff test mode and use AdMob Ad Inspector
    single-ad-source testing for every mapped banner, rewarded, and interstitial
    AdMob unit. Verify rewarded SSV/reward behavior remains unchanged.
12. On physical iOS and Android devices, force UMP test geography during a
    debug-only test session and verify initial form, denied/limited path,
    accepted path, and the conditional Settings privacy-options form. Remove all
    debug geography/test-device overrides before release.
13. Disable Liftoff test mode on the iOS production application, verify normal
    bidding status, and fetch `https://barastep.com/app-ads.txt` to confirm the
    Vungle seller record remains public before release. Repeat Liftoff device
    testing and test-mode shutdown for Android when its dashboard mappings are
    created.

## Acceptance criteria and definition of done

- The official compatible Liftoff Flutter adapter is locked for both platforms.
- Existing mediation adapters remain present and compatible.
- Liftoff's required iOS attribution identifiers are present without duplicate
  or lost existing entries.
- No Liftoff application/placement identifier is hardcoded into Dart or native
  application code.
- All existing ad formats behave identically from the user's perspective.
- The Google-managed consent form precedes ad initialization when required, ads
  are not requested without UMP permission, and regulated users can reopen the
  form from the conditional Settings row.
- The focused regression test, ad initialization tests, full Flutter tests, and
  `flutter analyze` pass.
- iOS and Android production-shaped builds pass; iOS Ad Inspector validation
  passes for every mapped Liftoff unit and iOS Liftoff test mode is disabled.
- Android contains the verified adapter and UMP implementation but no claim is
  made that Android Liftoff demand is active before its future dashboard setup.
- Version-skew safety is explicitly verified: old apps fall through, and the
  backend/SSV contract is unchanged.
- A code-reviewer reviews the combined implementation before completion.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Liftoff mediation UMP privacy controls**

*Elements under test:*
`PRIVACY AND COOKIE SETTINGS` is added conditionally in Settings → `HELP & LEGAL`, immediately before `PRIVACY POLICY`.
The Google-managed UMP consent form is added as a full-screen presentation over the app when required; the privacy-options form is reopened from Settings on iOS and Android.

*Checklist*

1. **Settings — real screen, iOS (privacy options required)**
   - **Get there:** On a physical iPhone with UMP debug geography/test-device configuration forcing a regulated region, sign in → Profile tab → Settings → scroll to `HELP & LEGAL`.
   - **Verify:** `PRIVACY AND COOKIE SETTINGS` appears directly after `SUPPORT` and directly before `PRIVACY POLICY`; it is not duplicated anywhere else in `HELP & LEGAL` or elsewhere on Settings.

2. **Settings — real screen, Android (privacy options required)**
   - **Get there:** On a physical Android device with the same UMP debug setup, sign in → Profile tab → Settings → scroll to `HELP & LEGAL`.
   - **Verify:** `PRIVACY AND COOKIE SETTINGS` appears directly after `SUPPORT` and directly before `PRIVACY POLICY`; it is not duplicated elsewhere on the screen.

3. **Settings — real screen, privacy options not required**
   - **Get there:** On each platform, use a UMP test state where the privacy-options entry point is not required → Profile tab → Settings → `HELP & LEGAL`.
   - **Verify:** The new row is absent; `SUPPORT` is followed immediately by `PRIVACY POLICY`, with no blank slot or duplicated spacing where the conditional row would have been.

4. **Google-managed initial consent form — iOS**
   - **Get there:** Reset UMP consent/test state on a physical iPhone, force a geography where consent is required, then cold-launch Bara.
   - **Verify:** The Google-managed consent form presents as a full-screen layer above the current Bara launch surface, only once, and no second copy is stacked behind or over it; dismissing/completing it returns to the same underlying Bara surface.

5. **Google-managed initial consent form — Android**
   - **Get there:** Reset UMP consent/test state on a physical Android device, force a geography where consent is required, then cold-launch Bara.
   - **Verify:** The Google-managed consent form presents above the current Bara launch surface, only once, without a duplicate stacked form; dismissing/completing it returns to the same underlying Bara surface.

6. **Google-managed privacy-options form — Settings action, both platforms**
   - **Get there:** In the privacy-options-required state, Profile tab → Settings → `HELP & LEGAL` → tap `PRIVACY AND COOKIE SETTINGS` on iOS, then repeat on Android.
   - **Verify:** The Google-managed privacy-options form opens above Settings; Settings remains the underlying route, and closing the form returns to the same `HELP & LEGAL` position rather than opening another screen or leaving a duplicate form visible.

*Surfaces confirmed unaffected:*
Demo race tutorial — `demo_race_host.dart` does not render `SettingsScreen`; no placement mirror exists there.
Tab tutorial — `tutorial_real_screens.dart` reuses the real `ProfileTab`, but contains no hand-forked Settings screen or `HELP & LEGAL` section; the new row belongs only to the shared `SettingsScreen` reached from the real Profile settings action.
Onboarding — no Settings or hand-copied `HELP & LEGAL` surface exists; only the platform-managed initial UMP form may overlay the active launch surface.
Existing banner, rewarded, and interstitial surfaces — the spec adds no ad placement or movement, so they need no UI-placement checkpoint.

*Risks found while planning:*
The row’s condition is asynchronous platform state; implementation must avoid a transient empty gap, late duplicate insertion, or ordering drift while the requirement status loads.
The initial UMP form can be requested while navigation/startup is changing routes; presentation must use a stable host so it does not stack twice or return the user to the wrong underlying surface.
`tutorial_real_screens.dart` uses the real `ProfileTab`; if tutorial taps are not intercepted, its Settings button can navigate to the shared real `SettingsScreen`. No forked row needs implementation, but this escape path is worth eyeballing during tutorial regression testing.
Debug geography/test-device overrides must be removed before release.

## Revision log

- Draft: mapped the change to the existing AdMob initialization, dependency
  pins, platform lockfiles, SKAdNetwork list, dashboard configuration, and
  release process.
- Gap pass 1: explicitly prohibited guessed privacy booleans, direct SDK
  initialization, new flags, and hardcoded placement IDs; added native-format
  deferral and dependency-graph verification.
- Gap pass 2: made old-client fallthrough and SSV compatibility explicit;
  required Android dashboard setup and honest pending status while allowing the
  shared SDK integration to compile before Android demand is activated.
- Architect review: pinned exact Flutter/native versions, made Android setup
  and validation mandatory, limited this release consistently to banner,
  rewarded, and interstitial, added dependencyInsight/lockfile checks and the
  test-mode shutdown/public app-ads.txt release gates, and surfaced the missing
  authoritative consent design as an approval-blocking decision.
- User decision: adopted Google UMP using the existing AdMob dashboard messages;
  added a conditional Settings privacy-options entry; activated Liftoff on iOS
  while making Android adapter-ready for later server-side ID mapping.
- Architect re-review: defined the single app-lifetime coordinator and exact
  startup order, made partner consent propagation authoritative and tri-state,
  required re-gating/disposal after changed privacy choices, corrected
  `canRequestAds` semantics, and aligned the user story with iOS activation.
- UI placement review: added the manual checklist verbatim and captured async
  row insertion, stable form presentation, tutorial escape-path, and debug-
  override removal risks.
