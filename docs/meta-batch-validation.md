> Released backend and uploaded iOS on 2026-09-10; see
> [release audit](meta-batch-release-2026-09-10.md) for actual results.

# Current release status — 2026-09-10

User authorized backend production deployment if the documented failures are
unrelated, followed by App Store Connect upload using the existing external API key.
The implementation and scoped independent reviews are complete. Deployment and
upload results will be recorded in `meta-batch-release-2026-09-10.md`.

- Flutter analysis clean; full suite **3,277 passed**.
- Backend Red Card HTTP suite **23 passed**, gift CLI **1 passed**, privacy/billing
  HTTP suites **21 passed**. Full unit suite **3,391 passed**.
- Full backend integration suite remains red: **3,210 passed, 92 failed, one
  existing skip**. Of those failures, 88 reproduced on untouched baseline
  `68da3a1`; the other four passed isolated on the changed checkout. No protected
  assertions were weakened. Backend runbook contains the diagnostic evidence.
- Native Meta simulator smoke **16 checks passed** against pinned CoreKit, plus
  native policy/lifecycle verification and **eight build-phase tests**. The final
  configuration uses `META_APP_ID` / `META_CLIENT_TOKEN` Dart defines and an
  automatic Xcode shell phase; no manual Python configuration step.
- Signed iOS **2.3.13 (13)** verified with production configuration, Meta plist,
  seven ad units, OAuth, RevenueCat and exact new art. IPA SHA-256:
  `af7a5ca954dfe65db19e3706b4c138d419c66b8eb65fba0db528d9f0e73417db`.
- Signed Android **2.3.13 / 203143** verified with production configuration and
  exact art on all three ABIs. AAB SHA-256:
  `41fc9d58a8491d913b4b128ece26ba6c5e427fc7344bbf2d45a40c3aebbffdd2`.
- Final pair and reports: `build/verification/meta-batch-dart-defines/`.
- Shop, artwork, backend, native Meta and revised configuration reviews returned
  SHIP/APPROVE. Manual device checklist: `shop-sectioned-frontend-validation.md`
  and `meta-app-events-requirements.md`.
- Actual Meta Events Manager receipt/AEM eligibility remains a post-install
  verification; intercepted simulator requests do not establish live attribution.

The chronological preparation notes below retain earlier findings and superseded
intermediate builds. This current status supersedes their incomplete-state notes.

---

# Meta, Shop, artwork and Red Card batch validation

This is a work-in-progress evidence record. The batch is **not ready for
production deployment** while the native Meta integration and final paired builds remain incomplete.

## Completion audit

| Spec issue | Current evidence | Remaining requirement |
| --- | --- | --- |
| 1. Meta App Events | Dart hooks, consent-resolution boundary, pinned CoreKit and safe plist defaults; focused tests and scoped review pass; user-supplied client token saved locally | Native coordinator/channel, lifecycle tests and actual event receipt; configuration and consent contract now reviewed |
| 2. Turtle white spots | Approved Aseprite cleanup:90fringe pixels, unchanged alpha/remainingpixels, editable source and immutable remote file prepared | Four real-widget renders and independent native/asset review pass; final shared builds remain; live publication is deployment-stage |
| 3. Sectioned Shop | Implemented with retained buy/customize paths, three-column Powerups, real-widget tests and 12 rendered captures | Final paired artifacts after remaining changes; manual mirrored-surface checklist |
| 4. Hitchhike thumbs-up | Generated replacement, imported production canvases, editable sources, asset tests and rendered inspection | Final shared-surface verification with release artifacts |
| 5. Red Card cap | Backend implementation, 23 real HTTP tests, copy updates and scoped review pass | Authorized backend/copy deployment; full-suite pre-existing failures remain disclosed |
| 6. Soch goodwill gift | Exact account identified by read-only lookup; canonical ID kept in ignored local handoff; idempotent +500 runbook and CLI tests | Authorized operations-stage credit and durable ledger verification |

All backend test processes have finished. The three owned disposable Redis
instances on ports 6401–6403 are stopped, and the temporary cap baseline worktree
is removed. Native implementation and final verification are now in progress.
No production deployment, asset publication or goodwill credit has occurred.

## Hitchhike replacement

The user reviewed the regenerated Hitchhike asset and explicitly accepted it;
their concern came from viewing the previous asset in the change set. Keep the
current replacement. This acceptance does not authorize a different turtle
repair method.

The replacement was generated with imagegen as an upright orange thumbs-up,
with folded fingers, a dark outline and a transparent background. The generated
hand was visually inspected before import. No hand-drawn replacement was used.

`scripts/import_hitchhike_icon.lua` imports that generated source through
Aseprite, removes faint alpha residue, crops its visible bounds and resamples
with nearest-neighbor selection into the existing production canvases. It keeps
the complete hand within each canvas. The corresponding editable Aseprite
sources and the local art export mapping were updated in the art workspace.
The script accepts source and output paths; no machine-specific paths are
required in this repository.

| Asset | Canvas | SHA-256 |
| --- | --- | --- |
| `assets/images/powerups/hitchhike.png` | 128 × 128 | `6fbfe79192cf33da51b4ef14c49ee81bcea0d3f6cc9b5f6206c72a500a0d55c7` |
| `assets/images/powerups/hitchhike_thumb.png` | 106 × 88 | `3bcf04acb84fb59ca0afd8063a161bd64b185570f90498063b7a6aa69aba4eaa` |

The existing Hitchhike asset tests pass for dimensions, visible artwork and
transparent corners. These tests do not prove visual placement: the manual
checklist in `meta-app-events-requirements.md` still applies to Shop, inventory,
details, activity and reward reveals on both platforms.

## Turtle precise cleanup

After two rejected generated replacements changed geometry/transparency, the owner
approved precise Aseprite cleanup. The bundled source and live manifest's previous
`turtle@f3410027eade.png` were verified byte-identical. The authoritative native
source exported pixel-identically too.

`scripts/clean_turtle_fringe.lua` copies adjacent original outline colors over
90 inspected opaque pale residues across eight frames. No alpha, geometry,
frame order, animation duration (80ms), tail-tip/root motion, or other pixels
change. `scripts/verify_turtle_cleanup.py` failed on the original visible defect,
then passed after correction, asserting exactly that bounded diff and no newly
invented colors. Seven existing real turtle-widget tests also pass.

The editable source in the local art workspace is updated, with its original
preserved. The committed baseline and reproduction script allow exact rebuilding.
Light/black/navy/green all-frame previews show clean edges. Evidence is under
`docs/artifacts/turtle-cleanup-2026-09-10/`.

Prepared immutable backend file: `public/assets/characters/turtle@a87ad177f0a0.png`.
SHA-256: `a87ad177f0a048147465f127de10db147d036c9a4f1fbd7d2a0a67fd3ad6fccd`.
Publication and the existing turtle record's assetVersion update are deployment
operations; neither has occurred. Retain all old URLs and change no other catalog
metadata. The public manifest still correctly advertises the previous version.

## Meta conversion boundaries

The Dart boundary accepts only a fixed enum and sends no user-provided event
parameters. Non-iOS platforms do not invoke the channel. Missing or failed native
channel calls are isolated from the user's action.

Real transport tests confirm all four explicit public/share-token join paths
emit only after HTTP 201 with a valid participant identifier. Already-member
errors, ambiguous HTTP 200, malformed successes and Android do not emit.
These tests establish the client trigger, not delivery to Meta.

Real Shop/billing widget tests cover a route visit without rebuild duplicates,
membership details, purchase intent, and preview suppression. Purchase intent
does not mean purchase completion; purchase/subscription revenue tracking is
outside this batch.

Registration is deferred: the current Apple and Google sign-in responses do not
distinguish new accounts from returning accounts. Adding a backend field would
exceed the user's narrowed event scope.

Pinned SDK source inspection confirms that manual `activateApp` also manages
session deactivation, duration and interruption metadata. This is SDK lifecycle
measurement, not health or step tracking. Its activation method uses a separate
install request and a stored attribution marker; setting event flushing to
explicit-only does not cancel that install request. The public API exposes no
general event-queue purge or cancellation of already-issued install traffic.
Withdrawal behavior must therefore describe stopping new app-triggered events
and transmission requests, without claiming to recall data already sent or
cancel all in-flight SDK requests. SDK lifecycle observers can persist session
state after initialization, even with automatic event logging disabled.

Evidence: official `facebook/facebook-ios-sdk` tag `v18.1.1`, commit
`80d0ee82f6370d1bace1431a80cb80575f98ee90`, `FBSDKAppEvents.h` activation API,
`FBSDKAppEvents.m` `publishInstall` and lifecycle observers, and
`FBSDKTimeSpentData.m` `restoreTimeSpendDataWithCalledFromActivateApp:`.

Real consent-bootstrap widget tests cover ads denied, failed CMP resolution,
privacy edits, failed privacy forms, ad initialization failure and a failed
measurement callback. CMP resolution is only a signal that consent information
can be evaluated; it does not itself establish permission for Meta App Events.
The user supplied the client token, saved in ignored `.secrets/meta-ios.env`
with owner-only permissions. Its value is not recorded in this document or
validation logs. Native configuration wiring and the permission policy are now finalized and
reviewed; coordinator implementation remains underway. The existing Unity partner consent boolean cannot be substituted for
Meta consent.

## Verification status

### Completed local Flutter checks

- Full suite: 3,267 passed, three failures, all caused by obsolete Shop layout
  expectations. Two expected uppercase `FEATURED`; the third expected the removed
  bottom category navigation in the billing preview.
- Updated those assertions to the new `Featured` section title and, in the
  preview, absence of bottom navigation plus presence of all three sections.
  Navigation and wallet-isolation assertions remain intact.
- Focused rerun of all three failing files plus Shop Meta events: **120 passed**.
- Meta channel/consent/join/Shop focused verification: **14 passed** before the
  additional Coins-shortcut regression, which was written red then passed in the
  120-test rerun.
- Onboarding completion: **4** new real-flow tests passed after their initial
  expected failure; **49** existing onboarding/demo tests passed.
- Flutter analysis after onboarding implementation: clean.

This is full-suite evidence plus a focused correction rerun, not a claim that a
second complete suite was run. Native Meta work and subsequent changes will
require their own relevant checks.

Intermediate Android prod build `2.3.13 / 203143` passed with README configuration.
The actual AAB passed bundle validation, package/version/billing checks and
signature verification against the trusted upload certificate. Its SHA-256 is
`3711a9045f001c2e9f2485a2610581335904575777f4281980a8cff0bbfc96f5`.
This build preceded the purple section-marker correction and does not contain a
completed turtle fix or native Meta integration; it is explicitly not a release
candidate. Artifact and logs are preserved under
`build/verification/meta-batch-intermediate/`.

Intermediate iOS `2.3.13 (13)` also built and exported successfully. The actual
exported IPA passed strict signature verification and has production push
entitlements, debugging disabled, production backend/Google OAuth/RevenueCat
configuration and all seven retained ad units. Its SHA-256 is
`237d50486767364611e6b9a45614311b5fbdea1024596dd60280dc0738c01a04`.
Its packaged plist has automatic Meta event logging and advertiser-ID collection
disabled by default. The archive is development-signed before export; production
entitlements were verified on the exported IPA itself. This artifact is also
intermediate: native Meta initialization and turtle correction remain missing.

Independent code review of the Dart Meta hooks, consent boundary, configuration
defaults, migrated Shop assertions and Hitchhike import returned **SHIP**, with
no blockers/issues/nits. The reviewer independently ran six focused Meta files:
**21 passed**. That scoped verdict explicitly excludes the incomplete native
integration, turtle correction and final deployment readiness.

The sectioned Shop has 12 actual font-loaded Flutter renders covering light/dark,
320/390-point phone widths, and Featured/Powerups/Characters scroll positions.
The review caught and corrected the section-marker colors to use Home's tokens.
Evidence and reproducible capture harness are under
`docs/artifacts/shop-sectioned-2026-09-10/`; the temporary capture test was removed
from the production test suite after capture. The manual mirrored-surface
checklist remains in the spec and frontend validation document.

### Remaining work

The backend full integration run is not green: 3,303 tests, 3,210 passed,
92 failed and one existing skip. The new Red Card cap suite (23 cases) and the
goodwill-grant CLI test passed within that run. Diagnostic reruns of the 40
failing files on untouched backend HEAD initially reproduced 84 of those 92
failures. Targeted follow-ups account for all 92: **88 reproduced on untouched
HEAD**, while the other **four pass on the changed checkout** (including the
2,000-write burst with its missing local Redis prerequisite restored). These
failures have not been hidden, skipped or repaired by weakening assertions. The
full suite remains red despite no demonstrated batch regression. The backend
handoff records the comparison and local test-service cleanup.

- Complete native Meta initialization, lifecycle, permission handling and
  allowlisted event mapping; review against the pinned SDK.
- Turtle cleanup and real-widget rendering are complete; retain its source/asset evidence in the release.
- Finish full Flutter and backend regression runs and diagnose failures.
- Run the final code review and both configured release builds.
- Perform the manual UI checklist; retain device screenshots as evidence.
- Prepare the production run order and keep the Soch +500 credit unissued until
  the authorized operations stage.

Meta Events Manager receipt and campaign eligibility require post-install
external verification. No live delivery or eligibility is claimed here.

## Privacy disclosure gap identified and corrected locally

The previous backend privacy-page source (`web/src/pages/PrivacyPage.vue`) said
that Bara did not use third-party analytics SDKs and never shared race activity
with advertising partners. The reviewed local amendment corrects those statements
for Meta App Events, including the generic race-joined event, before publication.
Health/step data and detailed race content remain excluded from Meta payloads.
Updating a disclosure does not itself establish consent, and the currently
AdMob European partner configuration was verified from the owner's screenshot. Individual user permission remains a runtime decision.

Google's [Meta mediation guidance](https://developers.google.com/admob/ios/mediation/meta)
identifies Additional Consent as the Meta partner-consent mechanism and calls
for Meta in the European and US-state partner lists. It describes Audience
Network mediation, so it is not proof that the current Bara consent message
covers the separate CoreKit App Events use. The existing Unity partner boolean
remains unsuitable as a substitute.

## Resumed configuration and privacy review

All five README iOS command examples now configure/check private Meta xcconfig;
Android explicitly requires no iOS Meta configuration. DEPLOYMENT's four iOS
examples and actual archive-plist upload gate are aligned. Nine independent CLI/
Xcode-phase tests pass; two Flutter configuration guards pass. Debug/Release/Profile
build settings resolve correctly; Release/Profile guard rejects missing or mismatched
configuration before Flutter. Token remains ignored and owner-readable only.

Backend privacy-page source and compiled public pages disclose the scoped SDK
measurement, excluded data, separate ATT, and actual withdrawal limitations.
Two new real HTTP tests failed before copy changes; complete marketing/billing
files pass21tests against the verified local test database. Website build and
asset check pass. No privacy publication occurred. Independent config/privacy
review returned SHIP with no blockers, issues or nits; native coordinator and
final artifacts were explicitly outside its scope.

## Final turtle review and rendered evidence

Independent review returned SHIP: no blockers/issues/nits in the 90-pixel correction,
its native source, reproduction and preservation checks, and prepared immutable
backend PNG. The reviewer decoded native frames independently and confirmed
all eight88x88frames remain80ms and match the output. Four-background inspection
found no clipping or changed shape. Four final font-loaded real-widget captures
(light/dark, bare/cowboy) passed after explicitly waiting for image decoding;
current catalog cowboy transforms were obtained in a bounded read-only art query.
Root inspected final light and dark captures. The screenshot fixture uses actual
HomeCourseTrack and frame renderer, not a full Home screen; device checklist remains.

## Final regression and remote delivery preparation

After native Dart wiring and turtle replacement, the complete Flutter suite passed
**3,277tests, zero failures** (`/tmp/bara-meta-final-flutter-suite.log`). Static
analysis is clean. This supersedes the earlier Flutter run's three corrected Shop
expectations; the separately documented backend baseline failures remain.

Current public manifest inspection also found Hitchhike remote version41ae2b8a805a,
which overrides its new bundle on current clients. Prepared matching immutable
`public/assets/powerups/hitchhike@6fbfe79192cf.png` (128x128, samegeometryasold).
Both asset catalog updates and exact byte verification are in
`meta-batch-production-handoff.md`. No remote version or catalog data has been
changed in production.
