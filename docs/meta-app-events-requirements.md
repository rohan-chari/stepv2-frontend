# Feature batch: Meta events, artwork, sectioned Shop, and Red Card cap

Status: IMPLEMENTATION AUTHORIZED September 10 — prepare and verify the full batch;
production deployment, live asset publication and Soch credit remain pending operations.

The user approved implementation of all six issues. BUY/OWNED and Powerup filters
are retained as the stated default. The combined architect review found Issues
2–6 sound and required closure of the Meta permission/configuration contract.
Local implementation and deploy-ready checks are distinct from post-deployment
Meta event receipt, live CDN verification, and issuance of the goodwill credit.

## Issue 1 — Meta iOS App Events

The sections through Sources below describe Issue 1. Subsequent issues have
their own scope, delivery, and acceptance requirements later in this document.

## Summary and user story

As Bara's operator, I want Meta to receive supported iOS activation and install
signals so I can verify acquisition measurement and resolve the missing/partial
conversion-data warning shown for iOS Aggregated Event Measurement (AEM).

Add official Facebook iOS SDK CoreKit/App Events alongside existing AdMob
mediation. Event delivery and Meta's campaign eligibility are separate acceptance
checks: linking a library does not prove attribution or guarantee AEM eligibility.

## Current implementation

- `ios/Podfile:33`: `GoogleMobileAdsMediationFacebook` brings in Audience Network.
  `ios/Podfile.lock` contains those dependencies but no FBSDKCoreKit.
- `ios/Runner/AppDelegate.swift:68`: `com.steptracker/meta_ads` forwards the
  existing ATT result exclusively to `FBAdSettings.setAdvertiserTrackingEnabled`.
- `lib/services/ad_service.dart:790`: ATT is resolved in Mobile Ads initialization.
- `lib/main.dart:97`: the application wires the shared ad consent coordinator.
- `ios/Runner/Info.plist:31`: existing URL schemes; line 91 contains the ATT
  explanation, followed by the mediation SKAdNetwork list.
- `ios/Runner.xcodeproj/project.pbxproj:519`: bundle identifier is
  `com.rohanchari.steptracker`.
- Existing regression coverage includes `test/ad_consent_launch_bootstrap_test.dart`,
  `test/ad_sdk_initialization_safety_test.dart`,
  `test/settings_ad_privacy_options_test.dart`, and native
  `ios/RunnerTests/RunnerTests.swift`.

## Scope and non-goals

In scope:

- Official `FBSDKCoreKit`, its required dependencies, app configuration, native
  lifecycle integration, and consent-aware basic App Events.
- SDK-supported install reporting and activation/session behavior.
- Signup, onboarding completion, explicit race joins, Shop views, selected
  conversion-button taps as detailed below, using the same SDK integration.
- Physical-device verification in the correct Meta Events Manager data source.
- iOS and Android regression verification and coordinated release artifacts.

Out of scope for this first issue:

- LoginKit, ShareKit, another Audience Network SDK, or mediation changes.
- Android App Events, purchase/subscription/renewal/refund tracking,
  RevenueCat-to-Meta delivery, or a general analytics framework.
- HealthKit data, steps, race details, user profiles, email, or other custom
  personal data in event payloads; no advanced matching/user-data attachment.
- Campaign creation/spending, automatic store submission, or backend deployment.
- Feature flags, remote toggles, or temporary rollout controls.

Additional issues will be folded into this document before scope is finalized.

## Event and privacy behavior

1. Use Meta's native installation reporting. Do not emit a custom `install` or
   `first_open` event as a substitute. Distinguish SDK-first-observation from a
   proven new download; upgrading an existing installation is a required test.
2. Use one activation mechanism supported by the pinned SDK. Inspect its automatic
   lifecycle behavior before adding manual calls. Cold launch and foregrounding
   must not be double-reported by automatic plus manual activation.
3. App Events must not depend on an ad request, ad availability, or premium/ad-free
   state. Preserve the existing ad consent and mediation initialization ordering.
4. Reuse the existing ATT prompt owner. Read current authorization on launch and
   resume, including changes made in Settings. No second ATT prompt. Unknown,
   denied, or restricted status must never be treated as tracking authorization.
5. Configure CoreKit's own privacy settings using the pinned SDK's supported APIs;
   Audience Network's setting does not configure CoreKit. Account for SDK versions
   that derive tracking authorization directly from ATT.
6. ATT and permission to send App Events are distinct. Do not equate UMP's
   `canRequestAds` with analytics permission or require ATT authorization for all
   limited measurement. The exact consent-to-event policy must be settled before
   implementation (see open questions). Prevent automatic startup transmission
   until the applicable policy has been applied.
7. Keep automatic purchase logging and other out-of-scope automatic collection
   disabled using supported SDK controls. No purchase reporting integration or
   RevenueCat configuration is included in this batch.
8. SDK/network failures must not block startup, sign-in, Health sync, or ads. Use
   SDK batching/retries; no per-event backend relay, forced flush loop, or custom
   durable event queue. Do not print credentials or event payloads in release logs.

Consent controls here represent permanent privacy behavior, not release flags.

## API contract and data model

No Bara HTTP endpoints, parameters, response fields, database tables, migrations,
backfills, or production data operations are required. SDK traffic goes directly
to Meta. No dependency on a new backend version; older clients retain their
existing behavior.

A small native lifecycle coordinator may be added at
`ios/Runner/MetaAppEventsCoordinator.swift` to keep AppDelegate changes bounded.
If Dart must pass a resolved event-consent decision, define that narrow channel
contract in this spec after the policy is settled; do not create a generic event
logging bridge accepting arbitrary event names or payloads. The expanded scope
requires a typed, allowlisted conversion surface with a finalized contract.

The integration seam is a separate measurement-decision callback from the
application consent coordinator, invoked after consent resolution on every
outcome, including ads denied and resolution error. Invoke it again after
privacy-options edits. Do not put it inside the ads-allowed branch or behind
Mobile Ads initialization success. Keep measurement failures isolated from ads.
`MetaAppEventsCoordinator` owns native foreground/background observation and
reads ATT on launch/resume without prompting. Preserve Flutter superclass
lifecycle forwarding. Background-only Health sync launches must not activate a
foreground session. The existing ad path remains the single ATT prompt owner.

The following decision table constrains the implementation. The owner confirmed
Meta is selected in Google CMP; this establishes provider inclusion, not any
individual user's permission. The native contract below is authoritative:

| Meta measurement permission | ATT | Required behavior |
| --- | --- | --- |
| Unknown, unavailable, or error | Any | Do not infer permission; do not start new event collection |
| Denied | Any | Do not start new event collection |
| Permitted under confirmed policy | Authorized | Permit scoped events; advertiser ID collection only if the policy also permits it |
| Permitted under confirmed policy | Denied, restricted, or not determined | Only policy-permitted limited measurement; no advertiser ID collection or forced ATT prompt |
| Withdrawn after initialization | Any | Stop new collection; resolve and test SDK handling of persisted/queued transmissions before promising complete suppression |

Ads being permitted, denied, or failing does not change these outcomes. This is
independent of ad eligibility; native code evaluates the current CMP signals.

### Final native consent and lifecycle contract — September 10

The narrow channel accepts typed allowlisted action identifiers and current CMP
resolution completion/invalidation only. Native code reads UMP, IAB and ATT state.
Until successful current-launch UMP resolution, deny collection. GDPR applicability
requires consent to Meta Additional Consent provider **89**. Parse valid AC v1/v2
consented segments; disclosed-only membership is insufficient. Both `2~89~dv`
and `2~89~dv.` are valid empty disclosed-only lists. Never reuse Unity vendor1549
or impose an invented Meta TCF purpose mask. Meta is not a GVL vendor; AC is its
provider permission source. P1/P7 describe storage and advertising measurement,
not a separately established Meta-specific consent-bit declaration.

Successful native UMP `notRequired` may establish the non-required branch, but
never overrides explicit GDPR applicability, contradictory/malformed signals or
applicable US restrictions. Respect applicable GPP sale/sharing/targeted-advertising
and GPC opt-outs plus legacy USP; unknown applicable sections fail closed. ATT is
separate: ID collection requires both Meta permission and ATT authorization. Denied,
restricted or undetermined ATT does not force another prompt.

Register Bara lifecycle observation before SDK initialization. Initialize once,
in the foreground after permission, and call the first manual activation in that
same main-thread operation before deferred SDK observers can load the session.
Refresh permission and ATT on resume. Deduplicate activation invocations by real
foreground epochs, resetting on backgrounding, not temporary resign-active alerts.
Background Health launches do not activate. SDK session coalescing means an
invocation per epoch does not guarantee an activation event per epoch.

Keep automatic event logging disabled. At privacy-options opening or withdrawal,
stop accepting Bara events, set `explicitOnly` flush behavior before other SDK
settings, disable advertiser ID collection, and do not flush. Re-evaluate after
form resolution. This does not cancel in-flight installation/other requests, purge
persisted events, or stop every SDK internal observer/storage action. No private
observer removal or undocumented queue deletion is allowed.

Manual activation includes SDK-managed installation and session/deactivation
metadata (including previous-session duration), plus configuration traffic.
These are distinct from the Dart action allowlist. Automatic purchases remain off;
ambiguous signup remains deferred. Update the published privacy page's conflicting
no-analytics/race-sharing claims and iOS release disclosures before release.
Validate actual SDK event receipt for delayed consent/resume separately from wrapper
invocation counts and Meta AEM campaign eligibility.

Sources: [Google Additional Consent](https://support.google.com/adsense/answer/9681920?hl=es),
[Google Meta integration](https://developers.google.com/admob/ios/mediation/meta),
[pinned SDK implementation](https://github.com/facebook/facebook-ios-sdk/blob/v18.1.1/FBSDKCoreKit/FBSDKCoreKit/AppEvents/FBSDKAppEvents.m).

### Owner-selected Dart-define configuration

The owner requested `META_APP_ID` and `META_CLIENT_TOKEN` as normal Flutter
`--dart-define` arguments in every README iOS command. An automatic shell Xcode
build phase decodes only those two keys from `DART_DEFINES`, validates them and
writes a derived copy of the native Info.plist. All Runner configurations point
`INFOPLIST_FILE` to that declared build output. The tracked source plist and SDK
runtime lifecycle remain unchanged in purpose: fixedBara display name, automatic
logging off, advertiserID off, and native permission checks before initialization.
No manual Python configuration command, local Meta xcconfig, generic config
channel, or embedding of unrelated Dart defines is needed. Release/Profile fail
closed on missing/duplicate/invalid values; incomplete Debug yields both values
empty so measurement stays disabled. Test fresh and incremental changed/removed
values, source preservation, built plist contents and actual SDK initialization.

## Configuration and implementation sequence

### Expanded conversion scope — September 10

User narrowed the expansion to straightforward events within the existing SDK
integration, without separate purchase/RevenueCat work. Small event calls and
verification are still required; no custom event is zero-implementation.
Implementation is approved. If an event cannot be reliably identified from
existing successful app paths without new backend fields or a separate subsystem,
defer that event and report the limitation instead of expanding this batch.

| Conversion | Proposed trigger and guard |
| --- | --- |
| Completed registration | Confirmed new account creation; never ordinary login, session restoration, or an existing account's first SDK launch |
| Onboarding completed | First confirmed completion of real onboarding; never tutorial replay |
| Race joined | Successful explicit user join; no failed/full-race attempt, refresh, already-member response, or automatic enrollment |
| Shop viewed | Actual Shop route visit; not every rebuild or newly visible section |
| Selected button taps | Initially membership details, coin offers, and purchase intent only; allowlisted action names, no general tap capture |

Use Meta's CompletedRegistration for confirmed signup; give remaining events
stable custom names finalized before code.
No usernames, emails, health/step values, race names, chat, or raw arbitrary
payloads. Button intent and completed conversion are separate events. Retain
consent handling and document deduplication keys/lifetime for each conversion;
do not send historical completions merely because this build adds tracking.

Setup: configure the correct Meta app/data source and client token; test event
receipt and parameters, then verify which events Meta makes available for campaign
optimization. No Facebook Login or additional App Events SDK is required for
custom events. No additional purchase integration or RevenueCat dashboard setup.

Before approval, finalize precise event names and
parameter/channel contracts, confirmed-success hooks, permitted identifier policy,
and tests for failure, retry, duplicate callback, existing-account
login, onboarding replay, and auto-enrollment. Add real-screen/service-path tests
before implementation; re-review this expanded scope with the architect.

Source: [Meta standard event names](https://github.com/facebook/facebook-ios-sdk/blob/main/FBSDKCoreKit/FBSDKCoreKit/AppEvents/FBSDKAppEventName.m).

### Implementation order

1. Resolve the open questions and append the user's remaining issues. Complete
   two updated gap passes, architect review, and user approval before code.
2. Confirm Meta App ID `1600882908142439` from the supplied screenshot against the
   intended dashboard app, its iOS bundle ID, App Store ID, and ad-account access.
   Obtain its client token through existing local configuration or user input.
   Never substitute the Meta app secret. Verify the dashboard display name.
3. Select and pin an official stable CoreKit release compatible with the current
   iOS 15 deployment target/toolchain. Inspect release-specific initialization,
   ATT, automatic-event, and AEM behavior. Record the version and exact APIs here
   before implementation. Do not depend on an unpinned `main` branch.
4. Write failing tests for the public launch/lifecycle/consent behavior below
   before adding business logic. Existing assertions remain protected.
5. Add CoreKit through the existing CocoaPods path in `ios/Podfile`; regenerate
   `ios/Podfile.lock`. Allow required CoreKit Basics/AEM dependencies, with no
   unrelated mediation dependency upgrades or duplicate SDK installation.
6. Add `FacebookAppID`, `FacebookClientToken`, and `FacebookDisplayName` to the
   native configuration, plus explicitly chosen automatic-event/privacy settings.
   Preserve existing Google Sign-In/deep-link schemes. Add URL forwarding only
   if the selected App Events/AEM integration requires it, preserving Flutter's
   existing handlers and testing those routes.
7. Implement the coordinator and wire it into
   `ios/Runner/AppDelegate.swift`. Register new Swift files in the Xcode target
   when required. Integrate the resolved consent policy at the narrowest existing
   application bootstrap boundary; likely touch points are `lib/main.dart`,
   `lib/services/ad_consent_coordinator.dart`, and `lib/services/ad_service.dart`.
   Do not tie event initialization to `MobileAds.initialize()` success.
8. Preserve the published mediation SKAdNetwork identifiers. Verify any separate
   advertised-app attribution configuration against the pinned SDK instructions;
   the current publisher-side identifier list alone is not proof of App Events.
9. Document required native release configuration in `README.md` and align
   `DEPLOYMENT.md`/local define files if build configuration changes. Missing
   production configuration must be caught before upload; malformed runtime
   configuration must not crash the app. Review resulting privacy disclosures
   against the actual enabled collection.
10. Run verification, required code review, and matching platform builds after
    approval. Read README release commands immediately before builds. Retain all
    required production values, seven retained iOS AdMob units, and omitted
    inline-row ad defines. No build/upload is requested during this draft phase.

## Frontend and platform behavior

No new screen, loading indicator, error dialog, or visible placement change is
proposed. Existing screens remain usable while initialization or network delivery
is pending or fails. No server-provided fields are introduced.

Android has no new measurement integration in this issue. Shared Dart changes
must be guarded and Android must not invoke iOS-only channels. Both platform
artifacts must still build and retain existing consent, sign-in, and ad behavior.

## Tests-first verification plan

- Pump the real application bootstrap widget to verify consent initialization
  remains independent of mounted ad surfaces. Exercise accepted, denied, unknown,
  changed, and failed consent paths according to the final policy.
- Through native lifecycle entry points, verify cold launch, foreground resume,
  delayed consent, repeated callbacks, and failure do not double initialize or
  double-trigger activation. Use structural tests only where real SDK network
  behavior is not observable through the native integration path.
- Verify no ad load is required for permitted activation, including ad-free use;
  verify denied/unknown tracking never enables advertiser ID collection.
- Preserve existing consent, privacy-options, SDK initialization, and tutorial
  isolation tests. Add Android coverage for any shared bootstrap changes.
- On a physical iOS device, use Meta Test Events/diagnostics to observe receipt
  under the intended App ID: fresh installation, upgrade from the previous
  binary, cold launch, resume, ATT acceptance/denial, and Settings changes.
  Record SDK semantics for session batching; do not demand one visible event for
  every foreground callback if the SDK coalesces sessions.
- Test offline launch/recovery without startup blocking or forced event flushing.
- Specifically cover ads allowed with Meta permission absent, Mobile Ads failing
  with measurement permitted, withdrawal with an offline event queue, and
  background-only Health sync launches producing no foreground activation.
- Verify existing Google sign-in, referral links, and ad load/reward flows.
- Run clean `flutter analyze`, the Flutter suite (diagnose failures individually),
  relevant native tests, and matching iOS/Android builds. Never use production DB
  integration tests; no backend tests or database access are needed here.

## Backward compatibility and rollout

Frozen old clients continue to function and do not gain App Events retroactively.
New clients work with the current backend without additions. There is no backend
deploy in this scope. Do not claim historical installs are backfilled.

Ship the verified application changes in the normal paired platform release.
Distinguish real new installs from existing users upgrading, and account for
phased adoption when evaluating event coverage. No rollout control is introduced.

## Acceptance criteria

- Required CoreKit dependencies are present; existing mediation remains intact.
- Correctly configured, permitted activation/install signals are observed in
  Meta for the intended app, with no custom substitute install event.
- Consent policy and automatic collection are explicit and verified; no duplicate
  ATT prompt or double activation path exists.
- No new backend contract, user-facing UI, or Android SDK requirement is created.
- Required tests, analysis, both builds, and code review pass before calling
  implementation complete.
- Record Meta's AEM eligibility result separately. If events arrive but the
  warning persists, document dashboard diagnostics and unresolved requirements;
  do not claim the campaign issue is resolved or promise a fixed clearing time.

## Open questions / next interview

1. Turtle white-spot cleanup added as Issue 2; further user issues may follow.
2. Confirm the Meta app identity, client-token source, and dashboard access.
3. Resolve how App Events consent maps to Bara's current privacy choices,
   including limited measurement with ATT denied and later consent withdrawal.
   Inspect existing configuration before asking the user for unavailable details.
4. Pin the SDK version and finalize scoped event controls and the Dart/native
   consent contract before the spec is considered implementation-ready.

## Follow-up investigation

- Existing `PartnerConsentSignals.gdprConsent` is calculated for Unity's vendor
  and purposes, not Meta. It must not be repurposed as Meta App Events permission.
  Preserve existing partner calculations and define a distinct decision from an
  authoritative applicable source once the privacy configuration is confirmed.
- The current coordinator reads partner signals on the ads-allowed path. Event
  permission evaluation must have its own outcome even when ads are unavailable
  or disallowed; no inference from that missing ad-path callback is valid.
- CoreKit v18.1.1 was inspected as a candidate, not approved as the release pin.
  Its application delegate automatically activates when automatic logging is
  enabled and handles activation after deferred setup. Its settings document
  direct ATT status use for newer SDK/OS combinations. These findings rule out
  blindly copying a manual activation call or the Audience Network tracking
  setter into the new integration.
- An SDK auto-log setting is not a proven stop-all-network/withdrawal API.
  Inspect initialization traffic, queued events, and previously persisted events
  before specifying consent revocation guarantees.

Release-specific evidence:
[v18.1.1 lifecycle](https://github.com/facebook/facebook-ios-sdk/blob/v18.1.1/FBSDKCoreKit/FBSDKCoreKit/ApplicationDelegate.swift),
[v18.1.1 settings](https://github.com/facebook/facebook-ios-sdk/blob/v18.1.1/FBSDKCoreKit/FBSDKCoreKit/Settings.swift).

## Required workflow reviews

Provisional architect review completed with a REVISE verdict. Required changes
about the independent initialization seam, Unity-specific consent, background
launches, and concrete regression cases are incorporated. Final Meta consent
source/transitions, supported withdrawal behavior, and pinned SDK/API/channel
details remain required before implementation approval. Re-review the combined
scope after the additional issues and these open items are resolved.
Backend and frontend implementation agents have been launched following approval. Following approval, the backend
agent confirms the unchanged API contract/no backend work, then the frontend
agent owns the application implementation. Run code-reviewer afterward.

UI test planner and game analyst are not applicable to this issue as written.
Reassess both when additional issues arrive. If placement changes enter scope,
include the planner's checklist verbatim before approval and completion.

## Sources

- [Official CoreKit dependency definition](https://github.com/facebook/facebook-ios-sdk/blob/main/FBSDKCoreKit.podspec)
- [Meta SDK settings](https://github.com/facebook/facebook-ios-sdk/blob/main/FBSDKCoreKit/FBSDKCoreKit/Settings.swift)
- [Meta application lifecycle integration](https://github.com/facebook/facebook-ios-sdk/blob/main/FBSDKCoreKit/FBSDKCoreKit/ApplicationDelegate.swift)
- [Meta install/event implementation](https://github.com/facebook/facebook-ios-sdk/blob/main/FBSDKCoreKit/FBSDKCoreKit/AppEvents/FBSDKAppEvents.m)

These moving-branch sources establish design direction; implementation must use
the selected release's corresponding documentation/source.

## Issue 2 — Remove turtle white spots visible in dark mode

### Problem and desired result

The supplied Home screenshot shows conspicuous pale/white spots at the turtle's
upper shell and lower body/foot edges against the dark blue scene. Remove stray
white/fringe pixels belonging to the turtle artwork so its outline reads cleanly
in dark mode. Retain intentional shell/skin shading and the approved appearance.
The screenshot demonstrates the symptom, not the exact asset version or cause.

### Evidence and affected paths

- Bundled sheet: `assets/images/turtle_walk_right.png`; registration in
  `lib/config/animals.dart:62`.
- Home sprite/attachment rendering: `lib/widgets/home_course_track.dart`.
- Shop preview: `lib/screens/tabs/shop_tab.dart:2292`; thumbnails use
  `lib/widgets/accessory_thumbnail.dart`; team rendering also uses
  `lib/widgets/team_scoreboard_cards.dart`.
- Shell effect icon resolves the turtle sprite in
  `lib/widgets/powerup_icon.dart:168`. Do not assume the separate cosmetic
  `assets/images/accessories/turtle_shell.png` is affected.
- `docs/turtle-shell-alignment-2026-09-09.md` records prior shell-fringe cleanup,
  approved gentle bounce, and independently moving tail tip. Its last recorded
  remote version is `f3410027eade` (eight 88×88 frames, 704×88 sheet). Verify the
  live manifest and bytes before treating this historical record as current.
- The prior note references `scripts/stabilize_turtle_shell.lua`, which is absent
  at that path in this frontend checkout. Locate the authoritative art source and
  reconstruction/export script through `CLAUDE.local.md` before editing anything.

### Bounded scope and implementation path after approval

1. Compare all eight current bundled frames, current CDN frames, and authoritative
   native source on dark navy, black, white, and the real Home backgrounds.
   Inspect RGBA pixels and frame boundaries; separate opaque pale remnants from
   alpha halos, background clouds visible through gaps, and sampling artifacts.
   Check with and without the screenshot's cowboy hat/accessories. Do not assume
   every light pixel or visible cloud belongs to the turtle.
2. Record baseline sheet geometry and approved per-frame motion. Build a failing
   reproduction for the confirmed defect before correction: frame-specific pixel
   assertions if it is an asset defect, or a real-widget rendering regression if
   it is compositing/sampling. Do not ban all white pixels or use snapshots that
   merely bless a replacement sheet.
3. Follow the accessory-art skill and imagegen editing workflow if artwork needs
   modification. Work in scratch with current art as reference, then critique
   before installing it. Do not hand-paint replacement artwork or redesign the
   turtle. Reconcile the corrected asset with its authoritative Aseprite source
   and reproducible export path so future exports cannot restore the defect.
4. Preserve frame count/dimensions/order/timing, baseline, shell geometry and
   pattern, bounce, moving tail tip and fixed tail root, head/leg motion, palette,
   attachment points, and transparent background. Any correction that changes
   these approved properties must be revised before acceptance.
5. If investigation instead establishes a rendering bug, limit the fix to the
   proven path and test other animals/accessories for regression; do not regenerate
   correct artwork to compensate for a rendering defect.
6. Update the bundled fallback. If remote bytes need correction, prepare a new
   immutable asset and version update for the existing turtle record using the
   established character-asset process. Read backend instructions before backend
   work. Verify new public bytes before changing the manifest; retain old URLs,
   identity, schema, and all unrelated catalog metadata. No new SKU or new asset
   capability is introduced. Preparing this spec authorizes no production write.

### Compatibility, API, and release

No game rules, prices, health data, or new client API are involved. A corrected
image at unchanged geometry is compatible with existing remote-capable clients;
older bundled-only clients keep their frozen artwork until an application update.
If delivery needs an existing catalog version change, use its current contract
without adding required fields. No migration, rollout flag, service-capacity
change, or staging startup is required. Confirm caching does not reuse old bytes
under a new version. Both iOS and Android must receive the corrected fallback in
the paired build and be included in device checks.

### Acceptance and verification

- No unintended white islands or pale outline residue in any frame at normal
  display size on dark backgrounds; no new fringe on light backgrounds.
- All eight frames preserve approved motion, silhouette connectivity and intended
  highlights. No clipping, detached tail/limbs, frame bleed, or accessory drift.
- Confirm the screenshot's Home appearance with the cowboy hat and bare turtle.
- Check live remote, cached/offline, and bundled-fallback rendering separately.
  Record the exact version used so stale cached art cannot masquerade as a fix.
- Preserve and run existing turtle widget tests; run Flutter analysis and relevant
  regression coverage. Run code review after implementation; both platforms are
  accounted for. Run the applicable checks during the approved implementation.

### Manual UI/visual checklist

**Manual UI-Placement Test Plan — Turtle sprite cleanup**

*Elements under test:* Turtle body, tail, feet and attached accessories retain their current positions, size and frame boundaries after stray-pixel cleanup. No UI relocation is planned.

*Checklist* — repeat on iOS and Android with Turtle equipped; use the screenshot’s nighttime Home scene.

1. **Home — real screen**
   - **Get there:** Home → Shop → OWNED → equip Turtle, then return Home.
   - **Verify:** Watch three complete loops, including last-to-first. Feet retain ground contact, tail stays attached, and the body remains fully visible without duplicate outlines. Repeat with the screenshot’s cowboy hat and without accessories.

2. **Shop and character wardrobe — real screens**
   - **Get there:** Home → Shop → Characters → Turtle; inspect its card and open its wardrobe. Check OWNED too.
   - **Verify:** One complete Turtle fits each preview. Preview available head, face, neck, back and feet accessories; attachments remain in place through the animation, with no clipped or duplicated parts.

3. **Races — real screens**
   - **Get there:** Races → an individual race containing Turtle; then a team race containing Turtle, including a team where Turtle is the displayed top scorer.
   - **Verify:** Check Races card thumbnails, race lanes, participant thumbnails, team lobby and team scoreboard heroes. Body/accessories remain inside their containers; feet, grass and shadows retain their alignment.

4. **Boards, public profiles and contest — real screens**
   - **Get there:** Boards with a Turtle participant in its podium; Friends → a Turtle user’s profile; Home → referral contest banner → VIEW while Turtle is equipped.
   - **Verify:** Each Turtle remains complete and correctly contained, with attached accessories. No second sprite or neighboring-frame fragment appears.

5. **Shell icon — static rendering**
   - **Get there:** Open race activity or an outcome showing an existing Turtle Shell block.
   - **Verify:** The icon contains one complete static Turtle frame, with no clipped tail or neighboring frame.

6. **Cached and bundled rendering**
   - **Get there:** After the corrected artwork has downloaded, go offline and reopen Home and the Turtle wardrobe. Separately use a carrying build with a prepared device state that forces the bundled fallback.
   - **Verify:** Repeat containment, grounding and accessory checks. Both paths retain the same geometry.

*Surfaces confirmed unaffected:*

- Home/tab tutorial and demo-race fixtures do not select Turtle; their shared screens cannot establish this correction. The name “TurtleBot” does not select the Turtle animal.
- Shop’s wardrobe tutorial explicitly launches the **default Capybara**, so it cannot establish the Turtle correction.
- Start-screen mascot and onboarding use Capybara.
- Tab-bar copies, coach overlays and tutorial spotlight anchors have no planned placement change.

*Risks found while planning:*

- The previous alignment document’s “Shop tutorial with Turtle equipped” checkpoint is stale: current code selects the default character for that wardrobe tutorial.
- Ranked cards contain a shared Turtle-capable renderer, but no `RankedTab` instantiation was found in current screen routing; treat this as a conditional checkpoint if a reachable entry exists.
- Offline after a download tests cached art, not the bundled fallback. A prepared carrying build is required for that separate check.
- Pale-pixel appearance is an artwork acceptance check outside this placement plan; preserving the approved bounce and independent tail-tip motion also needs a dedicated animation review.

### Open items

Confirm defect source from current full-resolution frames; identify authoritative
source/export location; verify current remote version. These are investigation
tasks, not requests for the user to diagnose the artwork. Re-run architect review
on the combined spec before implementation approval.

## Issue 3 — One continuous Shop with Home-style sections

### User request and visual direction

Replace the bottom Featured/Powerups/Characters category tabs with a single
vertically scrolling Shop. Match Home's section treatment shown in the supplied
Suggested Races screenshot: purple vertical marker, prominent light title,
consistent inset, and existing theme-aware card styling. Retain the Shop's
checker background, Back/SHOP header and coin balance/add button. Do not add
Home's sky/environment, avatar, or step hero to Shop.

The page order is:

1. **Featured:** Bara+ membership row, followed by coin offers row.
2. **Powerups:** section-local purchase/inventory controls and a more spacious
   three-column product grid at normal phone text sizes.
3. **Characters & Accessories:** the existing character collection. Tap a
   character to reach its existing buy/customize flow and character-specific
   accessories; do not flatten accessories into an unrelated global grid.

Headers borrow Home's visual language, not its race actions. Do not add a
meaningless VIEW ALL action when the section's content is already on the page.
Content determines section height; no viewport-height category containers or
bottom spacer replacing the removed navigation bar.

### Current paths and changes after approval

- `lib/screens/tabs/shop_tab.dart:1535` supplies `ShopCategoryBar` through
  `Scaffold.bottomNavigationBar` and conditionally renders one category. Replace
  that branching with ordered sections in the existing main scroll view.
- `_buildFeatured` currently inserts the membership tile as `CoinPackOffers`'
  leading tile. Present membership as its own tappable row, then reuse the coin
  offer component below it. Preserve membership status/details and existing
  billing availability behavior, localized store prices, and purchase flows.
- `_buildItemsHeader`, `_buildSegmentControl`, `_buildPowerupControls`, and
  `_buildBody` must become local to Powerups. Proposed default: preserve BUY /
  OWNED plus existing filter/sort functionality inside that section; user
  clarification is pending. Other sections stay visible when these controls change.
- `_buildCharacters` / `_openCharacterMenu` retain owned/locked character cards,
  saved outfits, selection/equip, buying, and customization navigation.
- `CharacterWardrobeScreen` also has a `ShopCategoryBar` and returns category
  selections to Shop. Remove that duplicate bar and migrate its return behavior
  to ordinary Back/section focus, preserving purchase/customization controls.
  Main application Home/Races/Friends/Boards/Profile navigation is separate.
- `lib/widgets/shop_product_grid.dart` currently chooses four compact columns
  from 360 logical pixels. Add explicit geometry for the Powerups use case;
  avoid globally changing character, wardrobe, or coin-offer grids by accident.
- `lib/screens/tabs/home_tab.dart:2520` contains `_HomeRaceHeader`. Extract a
  small shared section-header primitive if that avoids duplication, preserving
  the Home header's existing title/action behavior and spacing.

### Proposed layout measurements

Use existing PixelText/AppColors tokens and the Home section marker treatment.
Start with 16 logical pixels of section/content side padding, 24 between
sections, and 8–12 between section header and content. Powerup grid: three
columns at default text scale on phones, 12 horizontal and 16 vertical gutters,
with at least 10 logical pixels of breathing room around contained icon art.
Tile width follows available width; increase the art region with the wider tile
instead of retaining the current four-column icon size. Preserve a readable name
area and coin-price footer, badges, tap target, and image aspect ratio.

At narrow widths or large accessibility text, allow two columns and/or taller
cards so names and prices remain readable without clipping. Wider layouts must
remain bounded and intentional, not stretch three cards indefinitely. Final
visual verification must compare default-phone tiles against the supplied
screenshot: art slightly larger, more internal padding, no clipped fingertips,
effects, or labels. This is a layout change, not an increase to item prices.

### Navigation, loading, and state

- Normal Shop entry begins at Featured. Preserve existing `initialCategory` and
  `initialFocus` public inputs/callers by translating categories to section
  scroll targets. Existing membership entry may still open membership details;
  coin-plus and insufficient-balance actions scroll to coin offers after layout.
- Preserve requested Powerups BUY/OWNED state on entry. Returning from character
  customization, details, or a purchase restores the prior Shop position and
  relevant filter/selection. Do not reset the whole page to Featured on refresh.
- All sections share one main vertical scroll. Existing horizontal coin offers
  may retain their horizontal scroll. No independently scrolling powerup grid.
- Load catalog/wardrobe data once through existing controllers, deduplicating
  in-flight calls. Removing category switching must not create per-frame fetches,
  unbounded wardrobe loading, or requests per product tile. Preserve pagination.
- Refresh updates catalog and the now-visible character collection, with each
  section retaining its current data while refresh is pending where supported.
  Loading/error/empty states are section-local; failed billing must not hide
  Powerups or Characters. Keep existing wardrobe unsupported-backend fallback.
- Preserve existing availability decisions for accounts without powerups; do not
  show an empty full-height replacement. Purchase failures and purchase overlays
  retain their current retry/back/dismiss behavior.

### Tutorial and mirrors

Shop tutorial currently targets `shop-bottom-navigation` and says PICK A CATEGORY
(`shop_tab.dart:537`). Replace the obsolete target/copy with the sectioned layout:
first explain scrolling through the Shop using a stable section-header anchor,
then scroll to the character target before measuring its spotlight. Preserve
completion/replay and wardrobe tutorial handoff; no spotlight may reference a
removed widget. Recompute bounds after scrolling, loading, and route transitions.
The Shop wardrobe tutorial deliberately uses default Capybara; do not silently
change that fixture while reorganizing the entry page.

### API, economy, and compatibility

No new backend endpoint, required field, purchase rule, price, currency amount,
discount, payout, or entitlement behavior. Maintain defensive missing/null reads,
older-backend wardrobe fallback, and current billing/platform limitations. Old
clients keep their existing Shop against the same backend. iOS and Android use
the same layout, with both platform navigation/safe areas verified. No feature
flag or database migration is required. No economy analysis is needed unless
subsequent scope changes actual prices or rules.

### Tests first and acceptance

- Pump the real Shop with existing fake services: all three section headers and
  corresponding content are reachable by scrolling, with no bottom category bar.
- Verify three Powerups per row at representative default phone widths; use
  bounds/overflow assertions at narrow widths and enlarged text. Do not weaken
  protected tests that expect old category navigation: identify those assertions
  explicitly during review and obtain resolution before replacing their behavior
  expectations. Add new failing requirements tests before business logic.
- Exercise local BUY/OWNED and filter/sort without hiding Featured/Characters;
  preserve current purchase confirmations, owned counts and ad-unlock flows.
- Test category/focus entry points and coin-shortfall navigation, scroll restore
  after a character wardrobe round trip, and refresh with bounded request counts.
- Exercise partial failures and absent fields through real Shop rendering;
  preserve membership and coin purchase callbacks and unsupported wardrobe state.
- Replay the real Shop tutorial through the new anchors, including Back, Skip,
  slow loading, and wardrobe handoff. Existing relevant suites include
  `test/shop_featured_category_revision_test.dart`, `test/full_screen_shop_test.dart`,
  `test/unified_shop_test.dart`, `test/shop_dressing_room_test.dart`,
  `test/shop_powerup_filter_sort_test.dart`, and Shop purchase/ad-unlock tests.
- Run Flutter analysis, tests, code review, and iOS/Android validation under the
  combined batch's release checks. Implementation is authorized; production deployment remains pending.

### Open choice

An optional clarification was sent about retaining BUY/OWNED and filter/sort
inside Powerups. Draft assumption is retention, preserving functionality; fold
any response into this spec before final approval.

### Manual UI-placement checklist

**Manual UI-Placement Test Plan — Unified Shop and Hitchhike artwork**

*Elements under test:*
- Featured, Powerups and Characters & Accessories move from separate Shop tabs into one vertically scrolling page, in that order.
- Powerups become three-column cards with larger artwork and more padding; BUY/OWNED and filters remain inside that section, pending confirmation.
- Shop category navigation disappears from both Shop and its wardrobe screen.
- Hitchhike artwork changes within its existing icon containers.

*Checklist* — repeat on iOS and Android, including a narrow screen.

1. **Shop — real screen**
   - **Get there:** Home → SHOP.
   - **Verify:** Scroll through Featured → Powerups → Characters & Accessories. Each section appears once with its marker/title header. Featured contains Bara+ and coin rows. The bottom Featured/Powerups/Characters tabs are absent; the final character row clears the bottom safe area.

2. **Powerups — real Shop section**
   - **Get there:** Scroll to Powerups; inspect BUY and OWNED and available filters.
   - **Verify:** Full rows contain three cards. Larger art, labels and controls fit without overlap or clipping. BUY/OWNED and filters sit within Powerups; Featured and Characters remain present above/below.

3. **Character wardrobe — separate screen**
   - **Get there:** Characters & Accessories → owned character → customize; also inspect an available locked character.
   - **Verify:** Character preview, accessory choices and existing purchase/customization controls remain reachable and contained. Old category tabs do not survive at the wardrobe bottom. Back returns to the character section.

4. **Coin and membership entry points — shared Shop**
   - **Get there:** Home → coin “+”; Shop → Bara+ details; a prepared insufficient-coins flow → GET COINS.
   - **Verify:** Coin entry reveals the Featured coin rows; membership details fit correctly. Dismiss details and scroll through all three sections; no former category-only screen remains.

5. **Shop tutorial — automatic and replay**
   - **Get there:** An account with the Shop tutorial incomplete → SHOP; separately Profile → Settings → VIEW SHOP TUTORIAL.
   - **Verify:** The first spotlight surrounds its replacement target, never the removed bottom bar. The character spotlight scrolls to and surrounds its character card. Continue into wardrobe: its accessory spotlights fit and obsolete tabs remain absent.

6. **Hitchhike — compact and enlarged surfaces**
   - **Get there:** Shop → Powerups → Hitchhike card/details; Races with Hitchhike in inventory → race detail → inventory/guide; prepared Hitchhike reward → single/multiple box result or reveal.
   - **Verify:** The complete replacement icon fits every container, including compact inventory slots and enlarged reveals. No clipped thumb, neighboring artwork, or duplicate icon appears. Also inspect existing Hitchhike activity/effect displays where available.

*Surfaces confirmed unaffected:*

- Main Home/Races/Friends/Boards/Profile navigation is separate from Shop category navigation.
- Main tab tutorial uses real tab previews but does not instantiate Shop; its copied main tab bar remains unchanged.
- Demo race and tab tutorial fixtures contain no explicit Hitchhike entry; their absence cannot establish the artwork correction.
- Shop wardrobe tutorial selects the default Capybara; it remains a valid wardrobe-placement check, but cannot establish Turtle artwork correction.

*Risks found while planning:*

- **Wardrobe has its own `ShopCategoryBar`.** It returns category selections to Shop; both the bar and that return-navigation behavior need migration.
- **Shop tutorial currently targets `shop-bottom-navigation`.** Removing it without replacing the anchor prevents the tutorial from starting. Its second-step category switch must become section scrolling.
- Coin focus currently scrolls to `_coinsKey`; membership focus opens details. Preserve those entry destinations in the continuous page.
- Billing preview also instantiates Shop with coin/membership focus and needs the same placement smoke check when that preview is used.
- Hitchhike uses shared `PowerupIcon` in race/reveal surfaces, while Shop wraps its asset in `AccessoryThumbnail`; check both paths.
- Artwork recognizability and colors require separate art acceptance checks; this checklist covers containment and placement.

Implementation must include the billing-preview smoke check, both wardrobe
navigation migrations, and both icon rendering paths listed above. Three-column
placement applies at normal phone text size; the accessibility fallback specified
above remains intentional.

## Issue 4 — Make Hitchhike unmistakably a thumbs-up

The user finds the current hand icon unclear. Replace its artwork with a clear
upright thumbs-up: one raised thumb visibly separated from four folded fingers,
readable hand/wrist silhouette, warm current palette, bold continuous outline,
chunky pixel treatment consistent with other powerups, and clean transparency.
This is a specific hand-gesture correction; accessory side-profile orientation
guidance must not override the requested recognizable thumbs-up pose.

Current assets inspected: `assets/images/powerups/hitchhike.png` (128×128) and
`assets/images/powerups/hitchhike_thumb.png` (106×88). Existing
`test/hitchhike_asset_test.dart` protects both names, sizes and transparent corners.
`lib/widgets/powerup_icon.dart` maps HITCHHIKE to the shared artwork key.

After approval, use the accessory-art/imagegen editing pipeline with current
art and neighboring powerups as references. Generate into scratch, critique at
actual Shop and smaller icon sizes on light/dark surfaces, and derive coherent
full/thumbnail variants without distorting the gesture. Keep both existing asset
keys/canvas sizes and preserve transparent corners; reconcile authoritative art
sources/exports so future exports retain the correction. No hand-drawn shippable
replacement. Present the visual result for critique before installing it.

Verify the three-column Shop, item details and existing shared race/inventory
icon surfaces all depict the same unambiguous gesture without clipping or pale
fringes. Preserve existing asset tests and applicable real-widget tests. Human
visual review establishes gesture readability; opaque-pixel tests cannot prove it.

No Hitchhike mechanic, targeting, availability, price, quantity, identifier or
backend rule changes. Ship both variants in the paired iOS/Android build. If
investigation finds a remote override, document and use its established immutable
delivery contract; do not assume a bundle replacement updates frozen clients.

## Issue 5 — Red Card removes at most 10,000 steps per use

### Rule

Keep Red Card's existing 10% deduction and integer rounding, with a hard
10,000-step maximum per successful activation against its final recipient:

```text
nominalPenalty = min(10000, max(0, round(finalRecipient.totalSteps * 0.10)))
actualPenalty = existing atomic penalty helper's applied loss
```

The existing helper also prevents loss exceeding the recipient's available race
score. The cap applies to race score, not raw HealthKit/daily steps. Preserve
leader targeting, eligibility, defenses, item consumption, cooldowns, and existing
rounding. Resolve Mirror/Decoy using existing rules before calculating against
the final recipient. Blocks continue to remove zero steps.

This is per activation, not a shared daily/race budget. Multiple distinct uses
may remove more than 10,000 cumulatively. In team races preserve the existing
targeting and team-score aggregation; do not introduce a deduction per teammate.
No retrospective adjustment to past events or race standings.

### Backend and frontend implementation after approval

- Backend `src/modules/powerups/commands/usePowerup.js` RED_CARD case (currently near line
  3758; `RED_CARD_PERCENT` near 457): clamp the rounded nominal penalty before
  the existing `applyImmediatePenalty` call. Its existing atomic helper in
  `src/modules/races/models/raceParticipant.js` (`applyPenaltyAtomic`, near line 497) remains responsible
  for clamping to available score and returning the actual deduction.
- Preserve the helper's actual applied value throughout the HTTP result, durable
  effect/event records, feed, popups, notifications, and team aggregate updates.
  Do not cap display text while leaving the stored score deduction uncapped.
- Audit alternate/legacy Red Card execution paths before coding and apply the
  same invariant wherever required; no new query, queue job, lock, or per-user
  loop is justified by a scalar cap. Keep existing transactional concurrency and
  idempotency behavior. Expected added database work: zero.
- Update server-provided powerup copy and bundled fallback at
  `lib/constants/powerup_copy.dart:598` to say
  “Remove 10% of the leader's steps, up to 10,000 steps.” Audit guide/detail and
  tutorial copy for stale uncapped descriptions. Preserve existing layout.

### Compatibility and release

Enforce the cap on the backend for every app version; do not trust a client
parameter or make the rule depend on a newly added field. Keep all existing
request/response shapes and return actual capped deductions using existing fields.
Older clients still work, though frozen bundled descriptions may remain stale.
No database migration, backfill, release flag, or configuration toggle. Deploy
backend first after separate production authorization, then the paired app release
with updated copy. Implementation is authorized; production deployment remains pending.

### Tests first

Through the real HTTP powerup path against a verified dedicated test database:

- Final-recipient scores below, at, and above the rounding/cap boundary: preserve
  current rounding below the cap and never remove more than 10,000.
  Include 100,004 and 100,005: the latter is the first integer score whose
  rounded 10% deduction is reduced by the cap.
- Large score (for example 200,000) loses 10,000 instead of 20,000; lower score
  (for example 50,000) still loses 5,000. These are illustrative, not production
  measurements.
- Decoy/Mirror final recipients, zero/low score, supported blocks, leader
  eligibility, and team aggregate changes retain existing behavior.
- Repeated independent uses each obey the cap; duplicate request retries do not
  multiply a single activation. Concurrent penalties cannot make score negative.
- Assert actual response loss equals durable score/event changes and values
  exposed by the public feed; cover current and supported legacy entry paths.
- Pump real powerup detail/guide with server copy and missing-description fallback
  to verify the cap is visible without overflow. Preserve protected assertions.

Run required backend integration/unit commands, Flutter analysis/relevant tests,
and code review after implementation. No production DB tests.

### Economy review and acceptance

Game analyst reviewed the current deduction path and recorded the proposed,
unshipped rule in `docs/economy.md` section 3.3f.1, with verdict SOUND. Team mode
continues to target the enemy team's highest eligible individual, not combined
team steps. Historical replay must retain recorded penalties, including old
deductions above 10,000. The change preserves ordinary
10% deductions and reduces extreme-score attacks; it adds no direct coin source
or sink. Quantitative impact on race winners/rewards requires a score distribution
and is not claimed here. Multiple-card coordination remains possible under the
existing rules; no new cumulative immunity is implied.

Acceptance: each successful Red Card activation deducts at most 10,000 from its
final recipient, all reported results match actual deduction, copy explains the
cap, old clients remain functional, and existing defenses/atomic safety hold.

## Issue 6 — One-time goodwill gift to Soch

User requests a **500 Bara Coin** goodwill credit to the user named **Soch**,
who was frustrated by a large Red Card deduction. This is a fixed one-time gift,
not a reversal of race steps or a formula-based reimbursement policy.

### Operation after the spec phase

1. Resolve the exact existing username to its canonical account ID through an
   authorized account lookup. Do not guess from display-name similarity. If more
   than one plausible account exists, resolve identity before issuing the gift.
2. Use the existing audited administrative coin-credit path. Increase the current
   balance by 500; never replace it with 500. Record the actual account ID,
   amount, administrative reason (Red Card goodwill compensation), and a stable
   operation reference for this specific gift.
3. Check durable credit/audit history for the same operation before applying it.
   Use existing transactional/idempotency safeguards so retries cannot grant it
   twice. A timeout requires checking the recorded outcome before retrying, not
   assuming failure. Do not invent a second ledger or new compensation subsystem.
4. Verify one +500 transaction and the resulting balance, accounting for concurrent
   legitimate spending/earnings. Record completion evidence without exposing
   unrelated account data. Leave race scores and prior Red Card records intact.
5. No direct user message is included. Do not send email/push/other correspondence
   merely because the gift was requested; document any built-in notification side
   effect of the chosen admin path before using it.

### Scope and acceptance

This task is recorded in the spec; no coins have been issued. Implementation approval covers preparing this operation. Execute production writes only at the authorized
operations stage under the repository's production-write requirements.

No new UI, schema, backend API, item pricing, drop odds, or older-client behavior
is required. Existing clients receive the updated balance through their normal
refresh. The single intended coin-source increase is exactly 500; no recurring
grant, automatic eligibility, or rewards tied to repeated complaints are created.
Use a test account/local test DB for any necessary automated verification; never
run integration tests against Soch's production account.

Acceptance: canonical Soch account identified, one and only one audited +500
credit issued at the authorized stage, outcome verified and recorded. Any identity
ambiguity or already-completed gift is reported instead of issuing another credit.

Economy review: SOUND, with +500 total supply once and no recurring reward rule.
Use backend `scripts/grant-coins-manual.js` with canonical user ID, amount 500,
and stable ref `red-card-goodwill-2026-09-10`; it previews without `--apply`.
Resolve Soch via the unique `User.displayName`, then retain the immutable user ID
on retries. The existing `admin_grant` reason and unique ledger key
`[userId, reason, refId]` provide durable duplicate protection through
`src/shared/economy/awardCoins.js`, with atomic credit and wallet-cache invalidation.
Verify any existing matching entry is exactly +500 before treating it as complete.
Use the stable ref as the incident linkage rather than introducing a new reason
that would evade the existing duplicate key. No production lookup or grant has
been performed during planning.

## Revision log

- Added Issue 6: one-time 500-coin goodwill gift for Soch, pending execution;
  canonical identity verification and durable duplicate-credit safeguards required.

- Added Issue 5: user-requested 10,000-step maximum loss per Red Card use;
  backend enforcement, outcome consistency, copy updates, and economy review.

- September 10 scope reduction: retain straightforward same-SDK conversion calls;
  remove purchase/subscription reporting and RevenueCat integration research/work.
  Defer any event requiring new backend support or a separate tracking subsystem.

- Initial draft: recorded current mediation-only integration and scoped native
  App Events without backend, Android measurement, or custom conversions.
- Gap pass 1 (privacy/lifecycle): separated ATT from event permission, added
  delayed-consent and resume handling, prevented automatic/manual duplication,
  and made automatic purchase collection an explicit exclusion.
- Gap pass 2 (release/measurement): added upgrade-versus-new-install verification,
  configuration checks, release-specific SDK/API resolution, both-platform
  validation, and separate event-delivery versus AEM eligibility acceptance.
- Provisional architect review: incorporated independent callback/lifecycle
  ownership, a constrained permission decision table, background-launch behavior,
  and failure/withdrawal regressions. Final consent-source and release-specific
  API details remain open; this draft is not approved for code.
- Added Issue 2 from the user's dark-mode Home screenshot: diagnose and remove
  turtle white artifacts while preserving approved animation and geometry; cover
  source/export consistency, immutable remote delivery, and bundled fallback.
- Added Issues 3–4: continuous Home-style Shop sections, three-column padded
  Powerups, preserved character wardrobe flow, and recognizable thumbs-up art.
- Shop gap pass 1: preserved entry/focus/shortfall routes, section-local state,
  billing/wardrobe failures, and bounded loading after removing category switches.
- Shop gap pass 2: identified removed tutorial anchor, shared-grid side effects,
  accessibility layout, protected old-navigation assertions, and art variants.

### Resumed implementation decisions

The owner answered yes to the Aseprite cleanup exception and requested production-readiness notification. Precise native cleanup may replace confirmed fringe pixels while preserving geometry and motion; no redesign. The architect's final consent/lifecycle corrections above replace earlier unresolved provider/queue notes.

The architect approved the automatic derived-plist Dart-define design. Pre-initialization Settings setters through a Dart channel were rejected because the pinned SDK requires configuration first and snapshots the appID during AEM configuration. Native plist delivery preserves that contract.
