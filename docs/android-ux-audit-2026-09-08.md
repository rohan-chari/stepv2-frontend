# Android UX audit — 2026-09-08

Scope: Android/native integration and user-flow source audit covering startup,
health permissions and recovery, notifications, authentication, sharing/deep
links, profile photos, billing, ads, review prompts, and navigation. This is not
a completed physical-device acceptance pass. Findings below are code-confirmed
gaps; their device symptoms are predictions unless explicitly described as
reproduced. No additional app changes were made during this audit.

## Already fixed locally: startup step loader

`MainShell._restoreAndFetch` awaited the iOS-only background registration method.
Android returns `notImplemented`, which produces `MissingPluginException`, not
the previously caught `PlatformException`. Startup stopped before loading Home.
Pull-to-refresh bypassed registration. The preceding fix catches the missing
method response. Real MainShell tests reproduced the Android failure before
the change and passed afterward, alongside the successful iOS response case.

## Findings, in recommended repair order

### 1. High: background step access is never requested

- Evidence: `lib/services/health_service.dart:207` requests only read access to
  `STEPS`. The manifest declares `READ_HEALTH_DATA_IN_BACKGROUND`, but no app
  code requests its runtime grant. The installed health 13.3.1 plugin exposes
  a separate `requestHealthDataInBackgroundAuthorization` method; normal step
  authorization does not include it.
- `android/app/src/main/kotlin/com/rohanchari/steptracker/StepSyncWorker.kt:184`
  checks ordinary step access, then attempts a read. Scheduling a worker does
  not grant background access.
- User impact: a normally onboarded user can sync while Bara is open but lose
  background race updates unless they manually grant background access on a
  supported device. OS scheduling can still delay work even with permission.
- Repair: check Health Connect feature availability, request the separate
  background grant in a clear flow, distinguish foreground/background access,
  and preserve foreground sync when background access is declined/unavailable.
- Verify: fresh Android install; grant Steps only; then grant background access;
  compare actual worker reads while the app is backgrounded in both cases.
- Platform reference: [Android background-read guidance](https://developer.android.com/health-and-fitness/health-connect/read-data).

### 2. High: health settings recovery does not launch the intended Android action

- Evidence: `lib/services/health_service.dart:181` passes serialized `intent:`
  strings to `url_launcher`. Installed `url_launcher_android` 6.3.29 constructs
  `Intent(ACTION_VIEW).setData(Uri.parse(url))`; it does not call `Intent.parseUri`
  or execute the embedded action. Manifest query entries do not change this.
- The fallback also omits the normal `package:<applicationId>` data URI for
  application details, instead encoding the package as an extra.
- User impact: the onboarding/banner/settings recovery button can fail to open
  Health Connect, leaving denied users with only manual instructions. A browser
  resolving an intent URI would not constitute a reliable native recovery path.
- Repair: use an actual Android intent launcher/native method for Health
  Connect settings and a valid application-details fallback.
- Verify: deny step permission until a settings recovery is needed, then use
  the button on Android 14+ and standalone Health Connect; verify destination
  and return-to-app recovery, including unavailable destination handling.

### 3. High: revoked health access can remain displayed as connected

- Evidence: `HealthService.restoreHealthAuthState` (`health_service.dart:107`)
  reads a persisted boolean without checking current Android permissions.
  `_ConnectHealthRow._load` (`settings_screen.dart:1047`) uses that boolean and
  hides the connection row at line 1095. MainShell restores the same state.
  `_reprobeSteps` only operates when the inconclusive state is already armed;
  successful Android authorization does not arm it.
- User impact: after revoking Steps in Health Connect, users can get failed/
  empty reads while the app hides the reconnect control. This is distinct from
  an authorized provider having no step records.
- Repair: reconcile the real Android grant on startup/resume and expose the
  recovery state when revoked; retain iOS's intentionally different semantics.
- Verify: connect successfully, revoke Steps outside Bara, return and cold-start;
  confirm reconnect is offered, then regrant and verify automatic recovery.

### 4. Medium: Google Fit setup stops at permission, not data availability

- Evidence: `lib/screens/onboarding_flow.dart:159` explains data privacy but not
  enabling provider-side sharing. `HealthService.setUpHealthAccess` marks
  Android authorized immediately after the grant; the empty-data probe is
  iOS-only. `lib/tutorial/tutorial_screen.dart:60` names Health Connect but does
  not walk the user through Google Fit's sharing switch.
- User impact: the exact setup confusion encountered in this session: all Bara
  permissions can be granted while Google Fit has written nothing to Health
  Connect, leaving zero steps without a useful diagnosis.
- Repair: show Android provider-sharing instructions and an empty-data recovery
  path. Keep permission state separate from data availability; an idle user
  with zero steps must not be mislabeled as permission-denied or blocked.
- Verify: Google Fit has steps but sharing is off; enable sharing inside Fit;
  confirm useful instructions and eventual automatic step display. Also test
  an authorized user who genuinely has zero steps.

### 5. Medium: locally displayed notification loses its cold-launch destination

- Evidence: `lib/services/notification_service.dart:123` registers the local
  notification response callback. Foreground FCM messages become local
  notifications at line 143. Startup reads FCM `getInitialMessage` at line 177,
  but never local notifications' `getNotificationAppLaunchDetails`.
- User impact: receive a race notification while Bara is open, leave it in the
  tray, let the process terminate, then tap it. Bara can open without navigating
  to the referenced race. This does not imply all FCM cold-start taps are broken.
- Repair: feed local launch payloads into the existing pending-action path,
  preserving authentication/onboarding gating and avoiding duplicate routing.
- Verify: foreground notification → process termination → tray tap; repeat for
  race and tournament destinations and compare normal FCM background taps.
- Plugin reference: [local-notification initialization and launch handling](https://pub.dev/packages/flutter_local_notifications).

### 6. Medium, conditional: Android native in-feed ad renderer is missing

- Evidence: `lib/widgets/ad_inline_card.dart:66` always asks for `raceFeedAd`.
  Only `ios/Runner/AppDelegate.swift` registers that native ad factory. Android
  `MainActivity.configureFlutterEngine` has no equivalent. Meanwhile
  `AdService.nativeAdsEnabled` accepts an Android native unit and
  `DEPLOYMENT.md:448` documents that unit as available.
- User impact: configuring the Android native unit cannot produce the intended
  in-feed row. The widget catches load errors and collapses, so this is missing
  functionality/monetization rather than an established whole-screen crash.
- Repair: implement and register the Android native layout/factory; verify the
  rendered attribution and layout. An Android unit alone cannot complete this.
- Verify: build with a test native unit, load Races, inspect both success and
  no-fill behavior, then verify the existing iOS factory path.

### 7. Medium, shared with iOS: denied notification permission has no settings recovery

- Evidence: `_NotificationToggle._enable` (`settings_screen.dart:1156`) only
  reissues `requestPermission`; a false result leaves the same button. There is
  no notification-settings launcher or denial-specific recovery instruction.
- User impact: where the OS no longer prompts after denial, “ENABLE
  NOTIFICATIONS” appears to do nothing. This is not exclusively Android.
- Repair: consult actual permission state and offer the appropriate OS settings
  destination when another prompt cannot resolve the denial.
- Verify: deny until the OS stops prompting, use Settings → Enable
  Notifications, grant externally, and confirm the app reflects the change.

## Implemented paths and deliberate platform differences

- Google sign-in has an Android path; Android does not show Apple sign-in.
- FCM registration, token rotation, foreground display, ordinary FCM background
  and launch routing exist. The local-notification launch hole above is narrower.
- RevenueCat supports Android products, trials, plan replacement, restore, and
  Google Play subscription management. Actual store configuration was not
  verified in Play Console/RevenueCat.
- App/custom links and Play Install Referrer have Android handlers. Share
  actions use the shared plugin path. Domain association and actual Play-signed
  installation behavior were not verified on a phone.
- Profile photo picking/cropping has an Android crop activity in the manifest;
  only iOS gets custom crop UI options, but that is not a missing Android cropper.
- Rewarded/banner/interstitial ads have Android unit paths. Omitted units hide
  the offers intentionally. ATT/Meta tracking calls are correctly iOS-gated.
- Native review uses the cross-platform review plugin. The admin metrics
  dashboard is explicitly iOS-scoped; Android retains the legacy admin path.
- Shared navigation/back guards exist for tutorial, box reveal, race detail,
  and forced-update flows. A full Android back-gesture/device layout pass remains
  necessary; source inspection alone does not establish visual correctness.

## Validation and limits

82 existing targeted tests passed across notification registration/routing,
store billing adapter, deep links, install attribution, ad SDK initialization,
and health service. These do not cover all the identified native gaps and must
not be treated as proof those flows work. The preceding startup fix separately
passed 64 relevant tests and clean Flutter analysis. No new implementation,
build, installation, production mutation, or release occurred in this audit.

Recommended first repair batch: health settings launch, grant reconciliation,
and background permission handling. Provider setup UI needs a concrete design
and the normal UI-placement review/checklist before implementation.
