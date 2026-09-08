# Android parity and billing artifact readiness

Status: implementation authorized by the user's instruction approving all audit
recommendations. Architect review precedes implementation. Production deployment
and store customer release remain separate, unapproved operations.

## Summary and user story

Android users must be able to connect a step provider, understand missing data,
recover revoked permissions, keep steps current in supported background contexts,
and reach notification destinations. Android native ads must have a real native
renderer. The next uploadable production-package Android bundle must include
Google Play Billing permission so the owner can create store products.

Scope includes all seven findings in `android-ux-audit-2026-09-08.md`, the already
reproduced startup fix, and the uploaded-binary billing permission issue. Existing
RevenueCat checkout and server-authoritative fulfillment are retained. No new
SKUs, prices, rewards, odds, flags, or economy behavior are introduced. Product
creation is the owner's subsequent action; this task prepares the app and exact
upload instructions, not a claim that uncreated products can already be bought.

## Current evidence

- `health_service.dart:207` requests Steps only; background authorization is a
  separate plugin operation. `restoreHealthAuthState` reads cached permission.
- `health_service.dart:181` sends serialized intent strings through url_launcher,
  whose Android implementation uses ACTION_VIEW rather than parsing intents.
- MainShell startup calls an unsupported native method; the current worktree
  already contains a tests-first MissingPluginException correction.
- Settings hides health reconnect based on cache; onboarding never explains the
  independent Google Fit sharing switch.
- NotificationService reads FCM launch data but not local notification launch data.
- AdInlineCard requests factory `raceFeedAd`; only iOS registers it.
- AndroidManifest already declares `com.android.vending.BILLING`. Existing local
  artifacts and the uploaded artifact must not be assumed to reflect this source.
- `LiveBillingScope` selects the proper RevenueCat public SDK key by platform;
  `store_billing_client.dart` implements both stores already.

## API contract and migrations

No new HTTP endpoints, parameters, response shapes, database tables, or migrations
are required for the seven UX fixes or billing permission. Existing billing
contracts remain authoritative, including safe behavior for missing bootstrap
support, absent configuration/products, isolated sandbox identities, and existing
transaction verification. Backend agent must verify that contract and document
any existing deployment prerequisite, without deploying or changing economics.
Frozen clients continue receiving the same server contract.

Native settings channel `com.steptracker/settings`:

- `openHealthSettings`, no arguments, boolean result. Android opens the real
  Health Connect settings action appropriate to OS/provider, with application
  details (`package:<actual package>`) fallback. iOS opens app settings.
- `openNotificationSettings`, no arguments, boolean result. Android opens
  notification settings with actual package extra, then app-details fallback.
  iOS opens app settings. Failed/unsupported launch returns false; Dart exposes
  readable guidance rather than swallowing failure.

These methods are additive; Android's existing expedited-sync/referral/privacy
channels and iOS's existing channels retain behavior.

## Frontend implementation plan

1. Keep existing startup correction and regression tests.
2. HealthService gains injectable platform seams for tests and real Android
   foreground permission verification. Reconcile on startup/resume and Settings
   return. A failed permission check is unknown, not a fabricated denial/zero.
   Actual revocation makes recovery visible and suppresses inappropriate reads;
   regrant restores normal foreground loading. iOS retains its privacy semantics.
3. Use installed health plugin availability and permission methods for optional
   background access. Request only after foreground Steps is granted and via an
   explicit explanatory action. No background prompt on each launch. Decline or
   unsupported OS does not block onboarding/foreground sync; persistent Settings
   access explains/retries it. The worker checks background access when executing
  outside the foreground and must not indefinitely retry permission denials.
   The native worker must paginate manual records in bounded pages, reject an
   incomplete read/page-budget exhaustion, and propagate read failure before any
   upload. Never substitute zero manual steps on failure. Tests cover later-page
   records, failed manual reads, permission denial and revocation during reads.
4. Add compact Android Health Connect provider guidance using existing pixel/
   parchment UI components. Explain Google Fit bottom Profile tab → gear → Sync
   Fit with Health Connect, Steps write permission for Fit and read for Bara.
   Provide an empty-data state/help action when permission is granted but no steps
   are available. Do not classify genuine zero steps as revoked permission, block
   a new user, or label a read error as zero. Preserve onboarding/tutorial mirrors.
5. Replace invalid settings launch with native channel above. Surface false/error
   outcomes in existing recovery UI. Reconcile grant state on return.
6. NotificationService consumes local launch details once and routes through the
   existing pending-action pipeline, retaining login/onboarding/race gating and
   preventing duplicate navigation. Keep normal FCM cold/warm taps working.
7. Notification settings handles OS denial with an actionable settings recovery;
   refresh on lifecycle resume so external grants are reflected. First-time users
   can still request permission. Use correct behavior on both platforms.
8. Android registers `raceFeedAd` with GoogleMobileAdsPlugin and a Kotlin native
   view matching the existing 144 logical-pixel row: attribution, headline/body,
   CTA, AdChoices space, and at least 120x120 media. Register all assets with
   NativeAdView; support missing optional assets and no-fill safely. Existing
  iOS renderer and unit gating remain. No new artwork required.
   There is currently no AdInlineCard callsite: add exactly one row after real
   populated Races content, with no row in empty/onboarding/demo/tutorial views.
   No-fill and missing unit retain zero reserved space on both platforms.

Mirror review explicitly covers `demo_race_api_service.dart`,
`demo_race_engine.dart`, `tutorial_preview_data.dart`, `demo_auth_service.dart`,
and `tutorial_real_screens.dart`. Preserve `home.steps` spotlight on the number,
not the help control. Tutorial/demo tests must prove no live services or OS
permission prompts are introduced. No new health data fields are required in the
demo engine/API; populated authorized fixtures suppress new recovery UI.

## Ownership and sequence

- Root owns spec, Android/iOS native settings handlers, Android native ad factory,
  StepSyncWorker.kt and native regression tests (including bounded accurate
  reads), release artifact inspection/build scripts/docs and release verification.
- Backend-developer first locks the unchanged HTTP contract and verifies existing
  billing prerequisites/tests in its repo; no production writes/deployment.
- Frontend-developer then owns Dart health/notification/settings/onboarding flow
  changes and related Flutter tests. Both agents follow tests-first and preserve
  existing assertions. All workers are concurrent and must preserve others' edits.
- Native contract above is fixed before frontend implementation begins.
- Architect and UI planner review before implementation; code reviewer after.

## Billing release artifact plan

1. Inspect existing AAB package/version/permission and compare its age to source;
   distinguish local evidence from the Play-uploaded binary, which may be older.
2. Retain explicit BILLING permission. Add a meaningful artifact verification
   command that decodes the final bundle manifest and checks exact prod package,
   expected version, BILLING permission, signing, and embedded billing library.
   Fail release verification if any required property is absent.
3. Build matched iOS and Android artifacts from final code, prod backend, correct
   OAuth/AdMob configuration, established versionCode mapping, and real public
   RevenueCat keys where locally available. Never embed server secrets. If store
   setup/public keys are not yet available, distinguish product-creation-enabling
   build readiness from live-checkout readiness; do not claim checkout verified.
4. Produce checksums, version identifiers, artifact paths, and concise upload
   certificate fingerprints, plus
   instructions: upload the new prod-package signed AAB to Play's appropriate
   test/draft release and confirm its processed permissions before creating
   products. No backend deploy can update an already uploaded AAB.
5. Do not upload, deploy, publish customer releases, or mutate prod data as part
   of this predeployment request. No additional permission question until the
   concrete release candidate and outstanding external requirements are known.

## Tests-first and acceptance criteria

- Real MainShell: cold Android launch, supported iOS registration, revoked Android
  permission on resume and regrant; no stuck loader, no fabricated success.
- Real Settings/onboarding widgets: provider instructions only on Android;
  connected-but-empty, revoked, denied/unsupported background, settings failure,
  re-entry and iOS recovery all remain actionable and nonblocking.
- Native handler tests: intended Android actions, actual package, fallbacks and
  no handler. Native ad view/factory registration and missing asset handling.
- Notification launch: foreground-created local notification cold launch and
  ordinary FCM launch preserve destination and do not double-handle payloads.
- Native bundle manifest verifier tested against missing permission/wrong package
  and exercised against the final release AAB. Existing billing adapter tests stay
  green; do not substitute them for actual store checkout.
- Flutter analyze clean; relevant tests plus full suite once after integration.
  Kotlin tests and both platform builds pass; reviewer blockers resolved.
- Manual UI planner checklist included here and in final handoff. Physical-device
  gaps are explicit, not claimed as tested. No version-skew regression or flags.
- Ready for production deployment means code/release artifacts reviewed and
  verified, exact deployment/upload actions and prerequisites known. Store product
  creation and real sandbox purchase lifecycle verification remain necessary
  before customer purchase release; this task must not conflate these stages.

## Revision log

- Gap pass 1: separated cached grant, actual denial, provider empty data, and
  read failure; background access optional and feature-checked; iOS unchanged.
- Gap pass 2: confirmed BILLING already in source, requiring artifact verification
  rather than redundant edits; separated product-creation bootstrap upload from
  live billing release and prohibited unsupported claims about Play state.
- Architect review: assigned native worker ownership, bounded/fail-closed manual
  reads with worker-path tests, explicit demo/tutorial fixture and no-live-prompt
  checks, null-aggregate error coverage, and upload certificate fingerprint.
- UI planner: identified missing native-ad callsite; scope explicitly adds one
  real populated Races row, suppressed in demo/tutorial/onboarding/empty views.
- User approval: instruction explicitly approves the recommendations and asks for
  implementation through predeployment readiness; no repeat approval gate needed.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Android parity and billing readiness**

*Elements under test:*
Onboarding: “USING GOOGLE FIT?” added above the primary health action; guidance opens in a scrollable dialog.
Home: “MISSING STEPS?” added below “STEPS TODAY” for connected Android users with zero steps.
Settings: provider help and optional background-access controls added in Profile & Privacy; revoked-access recovery restored.
Shell: existing reconnect banner becomes visible after revocation.
Notifications: system-settings recovery added above reminder preferences.
Races: one native ad added after populated content in the selected list, on both platforms.

*Checklist*

1. **Surface:** Android onboarding.
   - **Get there:** Fresh test account → health permission screen; inspect initial and denied-access states.
   - **Verify:** “USING GOOGLE FIT?” sits above Continue/recovery. Open it: guidance scrolls while Close and Open Health Connect remain reachable. No duplicate inline guidance. At large system text size, the primary action and “Continue without steps” remain reachable without overlap.
2. **Surface:** Android Home.
   - **Get there:** Prepared account/device with Steps permission granted and zero steps → Home.
   - **Verify:** “MISSING STEPS?” appears once, immediately below “STEPS TODAY”, without covering digits, header controls, or the capybara. Its dialog has reachable actions. With populated steps, the help action disappears without a blank panel.
3. **Surface:** All five real tabs.
   - **Get there:** Revoke Bara’s Steps permission in Health Connect → return → visit Home, Races, Friends, Leaderboard, Profile.
   - **Verify:** One reconnect banner appears above the tab bar and any footer ad. Tab buttons and the banner action remain uncovered. Restore access and return: no stale banner or empty reserved strip remains.
4. **Surface:** Android Settings.
   - **Get there:** Profile → Settings → Profile & Privacy; inspect connected, revoked, background-denied, and unsupported-background device states.
   - **Verify:** Connect Google Fit, background status, and applicable background action stay grouped below profile controls. Revoked access adds one reconnect control. On the narrow Moto at large text size, background-action labels remain fully visible and all rows scroll into view. Open provider help: any launch-failure guidance must appear above the dialog barrier, not behind it.
5. **Surface:** Notifications settings, both platforms.
   - **Get there:** Disable notifications in system settings → Profile → Settings → Notifications.
   - **Verify:** Recovery appears above reminder preferences without a second enable control. Return after enabling notifications: obsolete recovery disappears without a gap; reminder rows remain reachable.
6. **Surface:** Real Races tab, Android and iOS.
   - **Get there:** Use the verification build configured with test ads → Races → inspect each populated list selection and scroll past its race content.
   - **Verify:** Exactly one inline ad follows the selected content; none appears above or between its race entries. Media, attribution, CTA, headline, and AdChoices fit inside the row on the narrow device. The row does not cover footer ads or tab controls. An empty selection or no-fill leaves no ad-sized gap or stray divider.
7. **Surface:** Tab tutorial, both platforms.
   - **Get there:** Profile → Settings → Help & Legal → View Tutorial → Home steps beat, then Races and remaining tabs.
   - **Verify:** The steps spotlight surrounds the number. Provider help, empty-step help, background asks, reconnect banners, and inline ads remain absent from the populated previews. The separately rendered tutorial tab bar and Next/Close controls stay unobstructed.
8. **Surface:** Demo tutorial and iOS health screens.
   - **Get there:** Fresh test account → onboarding → demo race and box-opening beats; separately visit iOS onboarding, Home, and Settings.
   - **Verify:** No health help, background controls, or inline ads intrude into demo coach/box screens. iOS retains its existing health controls without Android-only additions or duplicate recovery controls.

*Surfaces confirmed unaffected:*
Race-detail tutorial preview: reuses RaceDetailScreen, which hosts none of the added controls.
Create/invite demo prologue: no proposed health, notification-settings, or inline-ad placement.
Race effect trays and inventory mirrors: unchanged renderers and ordering.
Shop and purchase screens: billing permission adds no visual element.
Settings mirror: tutorial Profile does not embed a second Settings layout.

*Risks found while planning:*
Provider-help failure currently uses a snackbar beneath an open dialog; surface recovery inside the dialog or close it before showing feedback.
The background-action button currently uses a single-line label that can truncate on a narrow device with large text.
Home tutorial must preserve its authorized/populated fixtures and absent help callback; keep `home.steps` attached to the step display.
Reconnect placement belongs to MainShell, so every real tab needs inspection.
The original code had no AdInlineCard callsite. The agreed insertion must explicitly suppress tutorial previews and empty lists; factory registration alone does not create the placement.
Unsupported-background, settings-launch-failure, and native no-fill states require prepared verification states; ordinary successful device use does not verify them.

Implementation follow-up: the first two planning risks are fixed (failure inside dialog; wrapping background action) and widget-tested. Physical-device checks remain manual. This checklist describes verification states, not a claim that a test-ad device build or physical checks were performed.

## Implementation notes

The implementation-agent service rejected both new implementation agent requests with its lifetime thread limit. The primary agent therefore implemented the approved changes; the existing architect, UI planner and read-only code reviewer were reused. No backend mutation or deployment was needed for this release candidate.

Backend inspection: production checkout lacks `/billing` routes and all seven billing configuration entries. Local backend already implements the additive `bara-billing-v1` contract. The frontend safely treats missing endpoint/key/config as unavailable. Deploying that separately reviewed backend, configuring RevenueCat/products and sandbox lifecycle checks remain prerequisites to customer checkout.

Background synchronization adds no HTTP requests per successful snapshot. It gates on current read/background permission and retains the existing one combined v2 intake (legacy compatibility unchanged). Manual-record paging is bounded to 100 pages of 1,000 records per interval; incomplete reads fail before upload. This reduces erroneous retries/writes on revoked devices and preserves bounded per-user work during simultaneous syncs.


Review follow-up: hourly sample failure originally still allowed a partial snapshot; it now rechecks permission and fails before any upload. External notification grant now registers the device token. Both regressions were reproduced with failing public-path tests before correction. Release verifier rejects unsigned-entry warnings, checks the compiled manifest's Billing permission and SDK metadata, and matches the upload certificate. Metadata is not a substitute for sandbox checkout.

Full-suite investigation found an unrelated pre-existing remote-asset test teardown race: refreshManifest starts asynchronous prefetch. The affected test now joins the coalesced prefetch before deleting its temporary directory; all assertions are unchanged.
