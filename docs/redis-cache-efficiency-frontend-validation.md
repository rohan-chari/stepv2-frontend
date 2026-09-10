# Redis cache efficiency: Flutter compatibility validation

Date: 2026-09-10. Scope: the approved backend cache-efficiency work, with no
Flutter product, layout, dependency, native configuration, or capability changes.
The backend implementation owner pinned unchanged endpoint parameters, response
fields, status codes, and capability/channel behavior before this audit.

## Current consumer contract

| Surface | Current behavior preserved |
|---|---|
| Home full shell | `BackendApiService.fetchHomeRaceCard` requests `view=shell-v1`, `homeActiveRaces=1`, and the local date. Persisted totals remain conditional on the existing sync outcome. `MainShell._fetchRaceCard` accepts presentation only with a resolved marker, equipped map, numeric coins, and a present nullable cape. It accepts Friends only with a resolved marker, friend rows, and incoming/outgoing pending lists. Missing/null/malformed optional blocks retain standalone catalog/Friends reads. Missing explicit incoming count falls back to the incoming list length. |
| Home post-resolution refresh | Current code also uses the already-existing `home-sync-refresh-v1` request after resolution. Retaining the prior full-shell presentation/Friends snapshot depends on freshness, account identity, and mutation revisions. Unsupported/malformed retained-section contracts trigger the existing full-shell fallback; transient narrow failures preserve the coherent visible shell. This is recent event-efficiency behavior, additional to the original spec baseline. |
| Friends | A validated full Home summary seeds the shared `FriendsSummaryRepository`. Opening Friends within its existing reuse window renders accepted and pending rows without another friend read. The tab safely handles absent roster lists and nullable optional display fields; successful relationship actions invalidate/refresh existing state. |
| Race list | `fetchRaces` requests `view=compact-v1`. Existing race-list shapes and capability visibility remain required for current and frozen clients; caching cannot remove legacy arrays/fields just because this build opts into compact responses. |
| Race bootstrap | Both `race-bootstrap-v1` and `race-bootstrap-compact-v1` remain accepted. Compact packets must pass the existing mandatory presentation/membership validation. Unsupported or invalid lean bootstrap packets retain standalone details/progress loading. Only definite 404 support negotiation is remembered; transient failures do not permanently disable support. |
| Progress and inventory | Legacy, compact, and paged reads remain implemented. Missing compact inventory remains unavailable rather than being mistaken for authoritative empty inventory. Missing optional pagination retains the existing legacy/full-page interpretation. Viewer slot/queue state and consumable recent-box notices still have their existing response semantics; backend caching must not replay notices. |
| Milestones | `StepMilestonesSection` waits while the Home batch is pending, consumes embedded data when supplied, and calls the standalone milestone endpoint when it is absent after the batch resolves. Existing defaults handle absent/null optional totals and lists. Arbitrary wrong-typed milestone rows are not newly tolerated by this work; the backend contract remains unchanged. |
| Event display | Existing Home/race event widgets omit banners when event data is absent, and retain existing expiry and lifecycle behavior. The backend's longer internal cache retention introduces no new client timer, scoring logic, or eligibility authority. |
| Demo/tutorial | `demo_race_api_service.dart`, `demo_race_engine.dart`, `tutorial_preview_data.dart`, and `tutorial_real_screens.dart` retain their current real-screen fake-service contract. Base bootstrap/progress methods guard subclass services against accidental network escape; the existing explicit fake overrides remain intact. |

There is no dependency on a new backend field. Redis outage/fill-race and
cross-worker invalidation correctness require backend HTTP/database/Redis tests;
Flutter fakes do not establish those properties or prove the current production
deployment returns an unchanged response.

## Added regression coverage

Extended `test/main_shell_friends_and_public_test.dart` with two real-widget
tests, each run under `TargetPlatform.iOS` and `TargetPlatform.android`:

1. Mount MainShell with a valid Home shell and nullable cape, omit optional
   friend photo and explicit incoming count, then navigate to Friends. Assert
   the Home balance and friend data, incoming-count fallback badge, accepted and
   incoming friend names in the actual Friends UI, zero standalone
   catalog/Friends requests, and no exception.
2. Mount MainShell with null presentation/Friends despite true resolved markers.
   Assert both standalone fallbacks run, and navigate to a working Friends page
   with its search field and no exception.

The existing `PackageInfo.setMockInitialValues` setup is retained. Tests use
bounded pumps, not `pumpAndSettle` on MainShell's repeating animations/timers.
No existing assertions were changed or removed. These are regression tests for
already-supported behavior: they passed before any product logic change, and no
product logic change was needed.

Existing suites additionally exercise compact bootstrap rejection, legacy
bootstrap fallback, omitted bootstrap progress, compact inventory absence,
participant paging, Home narrow-refresh revision fencing, summaries, event
expiry, nullable Friends data, relationship refresh, and real tutorial/demo
surfaces. `main_shell_nav_order_test.dart` explicitly covers retained Home after
resolution with both iOS-style and Android Health Connect permission fakes.
`backend_api_timezone_transport_test.dart` covers transport under both platform
variants.

## Commands and results

- `flutter analyze`: PASS, no issues (initial audit and after test additions).
- `flutter test test/main_shell_friends_and_public_test.dart`: PASS, 18 tests,
  including all four new platform cases. The focused file was run again after
  adding the explicit incoming-count badge assertion: all 18 passed.
- `dart format test/main_shell_friends_and_public_test.dart`: completed.
- `dart format --output=none --set-exit-if-changed test/main_shell_friends_and_public_test.dart`:
  PASS, no formatting changes.
- `flutter test`: PASS, 3,251 tests in 2m05s, exit code 0. The full suite preceded
  the final badge assertion; the changed suite was independently rerun afterward.
- `git diff --check -- test/main_shell_friends_and_public_test.dart docs/redis-cache-efficiency-frontend-validation.md`:
  PASS.

Local detailed logs are in `/tmp/redis-cache-flutter-analyze.log`,
`/tmp/redis-cache-flutter-analyze-final.log`,
`/tmp/redis-cache-flutter-focused.log`,
`/tmp/redis-cache-flutter-focused-final.log`, and
`/tmp/redis-cache-flutter-full.log`.

## Platform and release limits

No iOS archive or Android app bundle was built or uploaded for this backend-only
change, consistent with the approved specification's explicit lack of a new
Flutter binary requirement. Native builds are not claimed as verified by this
audit. Both platforms consume the same unchanged Dart API surface; platform
widget/health-path/transport tests account for the relevant client behavior.
TargetPlatform variants are Flutter widget tests, not native device execution
or verification of `dart:io Platform`, APNs, FCM, signing, or native plugin links.

No screens/widgets, artwork, mirrored product surfaces, version numbers,
build-time defines, native dependencies, or application capabilities changed.
No UI placement checklist is required. Production/staging services were not
started, deployed, mutated, or queried by this frontend verification task.
The orchestrator owns the combined code review and backend release readiness.
