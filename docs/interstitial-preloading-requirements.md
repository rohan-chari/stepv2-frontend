# Interstitial preload readiness

## 1. Summary and user story

The existing capped interstitial system begins loading a Race Detail exit ad
only after a qualifying Race Detail visit reaches its 10-second dwell threshold.
Production telemetry on 2026-08-27 showed an eligible exit skipped as
`not_ready`, followed by `interstitial_load_succeeded` 22 seconds later. The
navigation behaved correctly, but the late load lost a legitimate impression.

Separate AdMob loading from backend eligibility and permit reservation. Warm
the placement-specific ad before a likely exit, then retain the existing
eligibility, permit, navigation, and confirmed-impression rules. A mature,
eligible user who opens the app, waits through the 90-second session grace,
spends at least 10 visible seconds in an active accepted race, and presses Back
should normally have a loaded ad and prepared permit available without delaying
navigation.

As a player, leaving a qualifying race continues immediately and silently
whether or not an ad is available. As the operator, ordinary AdMob load latency
should no longer consume most otherwise-eligible Race Detail exit opportunities.

## 2. Scope

### 2.1 In scope

- Split frontend interstitial state into independently managed, per-placement
  ad-load state and flow-local backend permit state.
- Warm the configured `race_detail_exit` ad after an authenticated `MainShell`
  is bound to an account, the app is foregrounded, onboarding is complete, and
  UMP consent permits ad requests.
- Warm `race_results_exit` when `MainShell` detects unseen completed results,
  before presenting `RaceResultsSummaryScreen`. This avoids an extra ad request
  for sessions with no completed results while giving the ad the whole results
  visit in which to load.
- Preserve placement-specific iOS and Android unit IDs. Never substitute one
  placement's loaded ad for another placement.
- Keep the existing 10-second qualifying Race Detail dwell. At that threshold,
  prepare backend eligibility and a permit against the already-warmed ad.
- Keep Race Results permit preparation before its summary route is presented.
- Refresh a missing, failed, or expired loaded ad using bounded retry behavior
  while the account/session remains eligible to load. Do not reload after a
  confirmed impression in the same session because the session cap makes that
  inventory unusable.
- Preserve the current bounded analytics vocabulary. Continue using
  `not_ready` for an eligible exit lacking either component; correlate the
  existing load events when diagnosing why.
- Account for both iOS and Android code paths. Android remains inert until its
  existing build-time unit defines are supplied.

### 2.2 Non-goals

- No new ad placement, screen, modal, button, copy, or other visible UI.
- No change to the 90-second session grace, 72-hour acquisition grace, 8-hour
  cooldown, two-per-local-day cap, one-per-session cap, or 30-minute local
  full-screen suppression.
- No navigation delay, spinner, toast, placeholder, or wait-for-load behavior.
- No permit reservation at app launch and no backend call solely because an ad
  object was warmed.
- No feature flag, rollout percentage, kill switch, runtime tuning control, or
  remote frequency configuration.
- No change to rewarded, banner, or native-ad loading.
- No production or staging deployment as part of implementation.

## 3. Current behavior and failure

- `InterstitialAdCoordinator.prime()` currently performs pending-impression
  flush, local/full-screen checks, backend eligibility, AdMob loading, and
  permit creation serially in one operation
  (`lib/services/interstitial_ad_service.dart:358-475`).
- Race Detail calls `prime()` only when its route-local eligible dwell reaches
  10 seconds (`lib/services/race_detail_navigation.dart:55-67` and
  `lib/services/interstitial_ad_service.dart:35-146`).
- `presentIfReady()` is intentionally synchronous and terminal at the restored
  prior route. If loading or permit work is unfinished, it records a skip and
  cancels the flow rather than delaying navigation
  (`lib/services/interstitial_ad_service.dart:538-595`).
- The coordinator currently owns only one ad/placement slot
  (`lib/services/interstitial_ad_service.dart:337-350`), so preparing one
  placement can cancel the other.
- `MainShell` creates the account-bound coordinator after authentication
  (`lib/screens/main_shell.dart:753-800`) and already receives lifecycle and
  consent transitions.
- AdMob unit resolution is already exact by platform and placement
  (`lib/services/ad_service.dart:635-672`).

The lost production opportunity is therefore expected from the implementation:
the Back exit happened before the serial load completed, and the late completion
could no longer be used safely.

## 4. Required frontend design

### 4.1 Coordinator interface

Extend `InterstitialPresentationCoordinator` with explicit load-only methods:

```dart
Future<void> warm(InterstitialPlacement placement);
```

`warm()` may initialize the SDK and request one AdMob interstitial. It must not
fetch backend eligibility, create a permit, emit an opportunity, or consume a
cap. Repeated concurrent calls for the same placement coalesce onto one load.

Keep `prime(placement)` as the flow-local readiness operation so existing route
ownership remains understandable. It must:

1. fail closed if the account/session/consent/platform binding is invalid;
2. ensure a warm is started if the placement is unexpectedly empty;
3. run the existing full-screen, local-cap, timezone, and backend eligibility
   checks;
4. create a permit only if the exact placement has a loaded, unexpired ad;
5. leave the loaded ad cached if eligibility rejects the flow, because loading
   alone is not a reservation and a later valid flow may use it;
6. cancel only the flow's permit when the route invalidates; it must not dispose
   an otherwise valid warmed ad.

`presentIfReady()` remains synchronous. It may show only when the exact
placement has both an unexpired loaded ad and an unexpired matching permit.

### 4.2 Per-placement state

Replace only the coordinator's single AdMob load slot with a map keyed by
`InterstitialPlacement`. Each placement entry owns:

- configured unit ID;
- idle/loading/ready state and one in-flight load future;
- loaded native handle and load timestamp;
- load generation for stale callback disposal;
- last load failure time and retry count;
- last load result.

Backend admission remains account-wide. Keep exactly one flow-local permit
owner containing placement, flow generation, optional grant, grant app version,
and last permit-readiness reason. This matches the backend invariant that an
account may have only one active reservation across both placements and all
devices.

Same-placement duplicate `prime()` calls coalesce onto the current flow
generation. A cross-placement `prime()` must preserve both warmed handles and
must not cancel or displace an existing valid reservation. It records the
backend's existing `permit_active` result for the newer flow. Once the original
flow invalidates or consumes its permit, a later flow may prime normally.

The existing one-hour maximum ad age remains authoritative. Expired handles are
disposed before use and asynchronously replaced while consent and lifecycle
allow requests. A flow whose permit or loaded ad expires before exit skips
synchronously; the refresh benefits the next qualifying flow and never causes a
late ad to appear after the user has left.

Only one interstitial may be presented at a time across all placements. The
coordinator retains one account-wide `_showPending` guard. Once an impression is
confirmed, the session/full-screen caps prevent either placement from showing
again: cancel the unused permit, cancel all retry timers, and dispose every
sibling warmed handle exactly once.

### 4.3 Warm timing

Race Detail:

- `MainShell` owns one `_maybeWarmRaceDetail()` gate. Invoke it after account
  binding, whenever onboarding transitions to complete, when consent changes,
  and on foreground resume. Register and remove the shell's consent listener
  with the shell lifecycle.
- `_maybeWarmRaceDetail()` requires a current matching authenticated identity,
  resumed lifecycle state, completed onboarding, allowed UMP consent, a
  production coordinator, and a configured placement. It schedules
  `warm(raceDetailExit)` without awaiting it.
- The coordinator keeps its own consent listener for fail-closed disposal and
  permit cancellation. The shell listener owns only the decision to start a
  new warm after permission becomes allowed.
- On a genuine foreground resume, retain a still-valid loaded handle. If it is
  missing or expired, warm it again.
- Every background transition invalidates active flow work and best-effort
  cancels the account-wide permit while retaining valid warmed handles. A
  foreground-started load may complete in the background and its exact bound
  handle may be retained, but it must not start retry, eligibility, or permit
  work until foreground resume.
- A foreground-session renewal after at least 30 seconds in background keeps a
  valid loaded handle but clears every old-session permit and flow generation.

Race Results:

- When unseen completed results are known and before pushing
  `RaceResultsSummaryScreen`, call `warm(raceResultsExit)` and then run the
  existing `prime(raceResultsExit)` without awaiting either from navigation.
- `prime()` must safely await/coalesce the same placement's in-flight warm
  internally, so a sufficiently long results visit can become ready. A quick
  dismissal still skips without waiting.

### 4.4 Retry behavior

- Never run overlapping loads for the same placement.
- After an AdMob load failure, retry only while foregrounded, authenticated,
  consented, configured, and not disposed.
- Use fixed bounded delays of 30 seconds after the first failure and 2 minutes
  after the second failure. "Three attempts" means one initial request plus at
  most two retries per foreground session per placement.
- Reset the retry budget when a new foreground session begins or after a
  successful load.
- A qualifying flow may trigger an attempt only when the scheduled retry is
  already due and no request is in flight. It must not cancel a future retry
  delay or bypass the three-attempt session bound.
- Backgrounding cancels retry timers, not valid loaded handles. Resume may
  restart the remaining eligible retry sequence.
- After an SDK-confirmed impression, suppress all further loading until the
  next foreground session. A show failure that never reaches
  `onAdShowedFullScreenContent` may re-enter the bounded retry path; once the
  show callback fires, the existing 30-minute suppression applies even if the
  SDK later reports failure.

### 4.5 Lifecycle, consent, and identity safety

- Never initialize or request an ad before UMP consent allows ad requests.
- Consent withdrawal disposes all loaded interstitial handles, cancels retry
  timers, invalidates in-flight generations, and cancels active permits.
- Sign-out, token change, user change, or backend-base-URL change disposes every
  loaded handle and permit owned by the old coordinator.
- Tutorial/demo/navigation-only coordinators implement the new warm methods as
  no-ops. Onboarding does not start preloads.
- A late load callback from an old identity, unit ID, placement generation, or
  disposed coordinator must dispose its native handle and never become ready.
- Validate the flow generation after every asynchronous boundary in `prime()`:
  pending-impression flush, full-screen preference read, local-cap read,
  timezone lookup, eligibility request, warm completion, app-version lookup,
  and permit creation. If a stale permit response contains a permit, cancel it
  exactly once while preserving any still-valid warmed handle.
- Expiring, replacing, or disposing the exact handle associated with a prepared
  flow invalidates that flow and best-effort cancels its permit. A replacement
  handle belongs only to a later flow and can never be paired with the old
  permit.
- Full-screen suppression is rechecked synchronously immediately before show;
  an early warm never weakens the rewarded-ad exclusion.

### 4.6 Analytics

Retain these existing events and semantics:

- `interstitial_load_succeeded` / `interstitial_load_failed` describe AdMob
  load results;
- `interstitial_opportunity` is emitted only for a genuine eligible exit;
- `interstitial_show_attempted`, `interstitial_dismissed`, and
  `interstitial_show_failed` remain presentation events;
- a confirmed SDK impression is still persisted through the durable local fact
  queue and `POST /ads/interstitial/impressions`.

Keep `interstitial_skipped.reason = not_ready` whenever the exact placement
lacks either a ready loaded handle or a ready permit at exit. The existing
placement-specific `interstitial_load_succeeded` and
`interstitial_load_failed` events provide load-funnel evidence without widening
the mixed-version analytics contract. No ad unit, creative identifier,
free-form error, or load duration is sent.

## 5. API contract

No interstitial endpoint changes are required.

The app continues to use:

- `GET /ads/interstitial/eligibility` with placement, session ID, and session
  start;
- `POST /ads/interstitial/permits` with placement, session fields, app version,
  and platform;
- `POST /ads/interstitial/impressions` only after the SDK confirms an
  impression;
- `POST /ads/interstitial/permits/:permitId/cancel` for unused permits.

Responses, status codes, idempotency, permit placement binding, show windows,
impression validation, and activation-analytics vocabulary stay byte-for-byte
compatible. Older clients and independently deployed backend versions behave
exactly as before.

## 6. Data model and migrations

No schema migration, table, column, or backfill is required.

`interstitial_ad_permits`, `interstitial_ad_impressions`, and
`interstitial_ad_caps` retain their current meaning. Warming an AdMob object
never creates a database row. A permit remains a backend admission reservation,
and only a confirmed impression creates an impression row.

## 7. Backward compatibility and rollout

1. No backend deployment is required. Before app release, verify production
   still exposes the existing eligibility, permit, impression, and cancellation
   endpoints used by app version 2.3.8.
2. Build and verify both iOS and Android from the same Dart revision. The iOS
   production build retains both real interstitial defines. Android remains
   safely disabled while its defines are omitted.
3. Submit both platform builds in lockstep. No content `testOnly` gate is
   needed because this changes invisible readiness behavior and old binaries
   continue using the unchanged endpoints.

Version combinations:

- Old app + current backend: unchanged current loading and permit behavior.
- New app + current backend: early load and unchanged flow-local permit
  preparation.
- New app + temporarily old/rolled-back backend: all ad endpoints retain their
  existing shape; presentation and analytics still use the old vocabulary.
- Missing placement define: that placement performs no load or backend work and
  exits normally.

No release flag is introduced. The behavior is permanent for builds carrying
the code.

Release verification uses the production commands and four placement-specific
define slots documented in `DEPLOYMENT.md:189-206,354-367`. Before release,
produce both `flutter build ipa` for iOS and `flutter build appbundle --flavor
prod` for Android with the same version/build number and production backend
URL. Omitted Android interstitial defines must be verified to leave both
Android placements disabled without fallback.

## 8. Tests-first implementation plan

### 8.1 Backend developer

No backend code or test edits are expected. Review the locked existing API
contract against the frontend plan and report any incompatibility before the
frontend implementation starts. If verification is run, confirm `DATABASE_URL`
names the dedicated local `*_test` database before running the existing
interstitial integration suite; never run bare `npm test` and never run tests
against production.

### 8.2 Frontend developer

Before changing production code, add failing tests that prove:

1. account binding plus consent warms Race Detail before any route visit;
2. unresolved/denied consent, onboarding, missing defines, web/other platform,
   background state, and unauthenticated contexts never start a load;
3. denied-to-allowed consent during onboarding does not warm until onboarding
   completes; the same transition after onboarding warms immediately when
   foregrounded; a transition while backgrounded waits for resume;
4. two calls for one placement coalesce, while two placements maintain distinct
   handles and unit IDs;
5. warming performs no eligibility, permit, cancellation, or impression API
   call;
6. Race Detail `prime()` uses a preloaded handle and creates its permit only
   after the existing qualifying dwell;
7. Race Results begins its separate warm before/during summary presentation;
8. a quick exit skips synchronously and never presents a late ad;
9. cancelling a visit cancels its permit but preserves a valid warmed handle;
10. an ineligible backend response preserves the warmed handle without creating
   a permit;
11. expired, consumed, show-failed, and consent-revoked handles are disposed
    exactly once;
12. stale load callbacks after auth/session/unit/generation changes are disposed
    and cannot become ready;
13. retry delays, exact three-attempt bound, background cancellation, resume,
    foreground-started load completion while backgrounded, and
    successful-reset behavior are deterministic under fake time;
14. same-placement duplicate primes coalesce; a cross-placement prime preserves
    both handles and cannot displace the singular active permit;
15. cancellation during warm, eligibility, app-version lookup, and permit
    creation is controlled with completers; every stale permit is cancelled
    exactly once without disposing an unrelated valid handle;
16. expiring/replacing the bound handle invalidates and cancels its permit, and
    the replacement cannot show under the old flow;
17. repeated paused/hidden callbacks, cancellation API failure, short resume,
    and a 30-second session renewal never strand or reuse an old permit;
18. pumped Race Detail and Race Results routes complete without awaiting warm,
    eligibility, app-version, or permit futures;
19. one placement showing enforces the account-wide session/full-screen cap,
    cancels retry timers, and disposes sibling inventory exactly once;
20. durable confirmed-impression replay is unchanged;
21. skip analytics retains `not_ready` and existing backend-compatible context;
22. the navigation-only coordinator remains a complete no-op implementation;
23. both iOS and Android placement-unit resolution remain exact with no
    fallback.

Prefer integration-style widget tests that pump `MainShell` and real navigation
for account binding, Race Detail, and Race Results behavior. Use focused service
tests only for native-handle lifetime, concurrency, retry clock, and source
structural properties that cannot be expressed through a widget route.

Then implement in this order:

1. extend the coordinator interface and test no-op implementation;
2. introduce per-placement load state and load coalescing;
3. separate `warm()` from `prime()` and permit cancellation from ad disposal;
4. wire account/consent/lifecycle warming in `MainShell`;
5. wire targeted Race Results warming;
6. add retry and expiry refresh behavior;
7. update existing interstitial tests mechanically for the new interface;
8. run focused tests, `flutter analyze`, and the full `flutter test` suite.

## 9. Acceptance criteria

- With a configured placement, authenticated mature account, allowed consent,
  and foreground `MainShell`, Race Detail begins loading before a race is
  opened.
- After session grace and qualifying race dwell, pressing Back shows an already
  loaded/ permitted ad without waiting for load or network work at the tap.
- If either component is not ready, navigation remains immediate and silent.
- No preload creates a permit, impression, cap, or analytics opportunity.
- Each placement owns only its configured platform-specific native handle.
- One confirmed impression still enforces all shared caps and persists exactly
  once in `interstitial_ad_impressions`.
- Consent, auth, lifecycle, expiration, and stale callbacks fail closed without
  leaked handles or permits.
- At most one account-wide permit can exist locally; cross-placement prime
  races preserve warmed inventory without displacing the active reservation.
- No existing tests are weakened, skipped, or deleted.
- `flutter analyze`, `flutter test`, backend unit tests, and backend integration
  tests are green; both platforms are accounted for; version-skew behavior is
  explicitly verified.
- The required architect and post-implementation code-reviewer reviews are
  complete before work is called done.

## 10. Manual UI-placement test plan

Not applicable. This feature adds, moves, or removes no visible UI. Existing
interstitials appear only at the same two natural exits and retain the same
presentation and navigation behavior.

## 11. Revision log

- Initial draft: separated early AdMob warming from flow-local eligibility and
  permit preparation; selected app-open Race Detail warming and demand-driven
  Race Results warming; preserved synchronous no-wait exits.
- Fresh-eyes pass 1: rejected app-open permit creation because its 24-hour
  reservation can block unrelated placement opportunities; required per-
  placement load state so one warm cannot cancel another; retained one global
  presentation guard; removed the unnecessary `warmConfiguredPlacements()`
  API because Race Results warming is intentionally demand-driven.
- Fresh-eyes pass 2: added consent-withdrawal and stale-callback disposal,
  bounded retries, session-renewal behavior, Android-disabled behavior, and
  explicit proof that preload creates no DB state. Kept the existing
  `not_ready` analytics reason after finding that finer reasons would create an
  avoidable backend rollout and rollback compatibility problem. Clarified that
  confirmed impressions suppress same-session reloads and that expired flow
  inventory never produces a late presentation.
- Architect review: changed the design from per-placement permits to
  per-placement loaded handles plus one account-wide permit owner; assigned
  consent-triggered warm ownership to a single guarded `MainShell` method;
  required permit cancellation on every background transition and after every
  stale async boundary; specified background load completion, exact retry
  counts, sibling-handle disposal after impression, no-wait route tests, and
  lockstep IPA/app-bundle verification.
- Post-architect fresh-eyes pass: verified that every architect-required race
  has a tests-first case, removed the misleading implication of a new backend
  version from the rollout matrix, and confirmed that the singular permit owner
  does not alter any endpoint or database contract.
