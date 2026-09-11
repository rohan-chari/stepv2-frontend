# Approved frontend test disposition

The approved simple-event-recap spec explicitly replaces worker polling and
mixed gain/loss presentation. This manifest records intentional behavior changes;
ordinary race polling, ownership, expiry, and Home concurrency remain protected.

## Retired worker-only widget scenarios

The following `main_shell_nav_order_test.dart` scenarios are replaced by direct
candidate → platform-window read → save-once MainShell tests, failed/unknown sync
deferral, null vs zero, auth/lifecycle cancellation, no polling, and refresh/resume:

- fast device clock cannot suppress work polling or CREATED Home refetch
- slow device clock still lets server CREATED drive Home refetch
- server EXPIRED_UNDELIVERED stops work despite a locally future deadline
- summary work polls past race cadence and CREATED independently refetches Home
- terminal summary work state stops polling without UI
- failed summary work status read stops polling without UI
- backgrounding cancels summary work polling
- paused summary work is retained and polling restarts on resume
- hidden summary work cancels polling and restarts on resume
- later Home pull receipt starts existing WAITING_RACES work
- terminal summary work is not restarted after resume
- sign-out cancels summary work polling

`mixed net-zero 2x summary remains eligible on Home` becomes nonpositive recap
suppression; showing net zero was explicitly removed from product behavior.

## Preserved Home concurrency tests

The summary receipt vs narrow-core test is retargeted to the independent direct
recap response. Tests for newer full response winning over older narrow response,
acknowledged recap not reopening, and independent friends/catalog updates retain
their visible-data assertions; their obsolete receipt-driven refresh trigger is
replaced by the actual Home refresh callback.

## API tests

The two receipt parsing tests now verify historical optional receipts are ignored
without changing CURRENT/DEFERRED sync success or race job metadata. Malformed
receipt test retains successful sync assertion. Retired status reader's all-state
and error tests become GET/POST recap wire-contract and fail-soft response tests.
Existing race-resolution status tests remain unchanged.

## Replacement evidence

- New real MainShell happy-path test was run before implementation and failed
  because only step sync ran: no candidate read, interval aggregate or POST.
- Additional red-to-green overlay test proves pending optional recap work does
  not hide Home and cannot be overtaken by a Home invitation.
- MainShell covers cold-open/resume and refresh coalescing; exact server window;
  failed/ambiguous/unknown/cooldown sync; missing vs zero raw input; successful
  and partially failed legacy sync; saved-result acknowledgment; previous-day
  expiry; malformed/missing fields; no five-minute recap reads; and interruption
  at sync, GET, Health read and POST by account switch, sign-out, backgrounding
  or disposal.
- HealthService adapter tests exercise both native platform branches: unchanged
  UTC bounds, deduplication/manual-entry options, zero vs null, and denied or
  unknown Android permission before reading. These native-plugin-boundary tests
  complement, rather than substitute for, the real MainShell tests.
- Initial focused command: `flutter test --no-pub test/main_shell_nav_order_test.dart
  test/backend_api_service_sync_v2_test.dart test/health_service_test.dart`:
  **208 passing**. `flutter analyze --no-pub`: **clean**.

Final full-suite verification after the additional changelog/background-overlay
regressions: **3,439 passing, 36 failing**. All 36 failure names reproduce
exactly on an isolated, unchanged `587d8cb` baseline: 14 in
`admin_metrics_dashboard_test.dart`, 11 in `admin_system_health_test.dart`,
9 in `batch_2026_08_09_admin_sections_test.dart`, and 2 in
`admin_dau_engagement_test.dart`. No new failing test names remain. These Admin
assertions were not edited or suppressed; the full suite is not claimed green.
Final analysis and `git diff --check` are clean.

The full-suite pass found a real startup ordering regression: while awaiting
optional recap input, a version changelog could overtake it and cover tab taps.
Cold-open now gives the recap its turn inside the overlay sequence while Home
is already rendered; foreground/account guards are rechecked after the wait.
Dedicated red-to-green tests cover the changelog and a delayed background result
opening the next invitation. The ten affected Friends/Home tests pass unchanged.

No artwork, screen placement, native dependencies or demo/tutorial fixtures
changed. The approved manual placement checklist still applies on both devices.
