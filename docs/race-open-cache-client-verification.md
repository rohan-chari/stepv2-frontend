# Race-open Redis caching: client verification

## Scope and source

Backend-only caching optimization; the API contract remains unchanged. Audited
frontend source: `587d8cb16163ebdeaafe20e782862e6ec5f5109b` on 2026-09-10.
No Dart, widget, native, dependency, artwork, or placement changes are needed.
Unrelated untracked accessory documentation was left untouched.

## Actual opening requests and compatibility

- `RaceDetailScreen._loadDetailsImpl` requests
  `/races/:id/bootstrap?view=participants-v1&offset=0&limit=15&shape=compact-v1`.
- The API service accepts both `race-bootstrap-v1` and
  `race-bootstrap-compact-v1`. A definite bootstrap 404 remembers unsupported
  support for the service lifetime. Transport/server/malformed-envelope errors
  remain errors; they do not permanently select the legacy path.
- A malformed compact payload falls back to standalone details/progress.
  Compact requires active individual race status, no `race.participants`,
  nonnegative numeric `acceptedCount` and `myTotalSteps`, full string
  `participantUserIds`, nonempty string `myStatus`, valid details/progress
  pagination, and hydrated progress rows (`userId`, `accessories`, and nullable
  `animal`). Cache serialization must preserve these shapes.
- The legacy fallback fetches `/races/:id?view=participants-v1&offset=0&limit=15`
  alongside `/races/:id/progress`. Later individual-race page reads use
  `/races/:id/progress?view=participants-v1&offset=...&limit=15`; compact-progress
  fallback uses `?view=compact-v1`.
- Completed bootstrap responses may omit progress; the real screen performs
  its separate final-progress read. Pending/team, preview, spectator and old
  full-array paths remain supported.
- Activity streams and active impact notices are additional requests. Chat
  loads only when opened. Preview viewers do not start active polling or fetch
  locked chat/activity.

Source: `lib/services/backend_api_service.dart` (`fetchRaceBootstrap`,
`_isValidCompactRaceBootstrap`, `fetchRaceProgressParticipants`) and
`lib/screens/race_detail_screen.dart` (`_loadDetailsImpl`, `_loadProgress`).

## Display and privacy invariants

- Paging summaries determine accepted counts, off-page viewer membership/team,
  viewer total steps and participant IDs. Optional missing summary fields on
  old full-array contracts retain existing roster fallbacks; a compact packet
  cannot omit required summaries.
- Muting checks literal `true`; missing flags are false. Rematch eligibility
  also requires literal `true`. Series controls require a nonempty string ID
  and boolean `enabled`, `subscribed`, and `canManage`; malformed/missing series
  state hides the controls.
- Missing/malformed `powerupData.dropOdds` hides the odds affordance. Missing or
  invalid `trailMix.uniqueTypesIfUsedNow` hides its advisory preview without
  disabling use. No new client economic fallback is introduced.
- `stepsUntilNextPowerup: 0` is authoritative and renders the existing granting
  state. Missing/invalid countdown can reuse the last valid display value;
  initial missing countdown/interval hides the helper.
- `newMysteryBoxes` and `newQueuedBoxes` produce acquisition notifications and
  must remain consume-once state outside cached display fragments.
- Display caches must preserve server privacy filtering and viewer-specific
  effects/placement. The client consumes masked/stealthed rows and cannot
  repair cross-viewer leakage from a shared final-response cache.
- This audit covers the unchanged contract's relevant defensive paths, not a
  claim that every historical response cast is hardened. Existing examples
  such as nullable `scheduledStartAt` string and `newMysteryBoxes` list casts
  still rely on the unchanged server field types.

## Platform accounting

iOS and Android use the same Dart screen, request methods and race capability
tokens (`race_participants_paging`, `race_preview`,
`privacy_safe_display_ranks`, `api_payload_compact_v1`, `recurring_races_v1`,
`team_chat_v1`, and powerup capabilities). Existing ads, payout-double and
iOS-only metrics capability differences remain unchanged and must not be
frozen into shared cached responses.

No native builds, deployment, upload, or staging startup were performed. There
is no client binary or native/configuration change to build in this task; this
verification does not claim fresh iOS/Android artifacts. No manual placement
checklist is required because no placement changes occur.

## Verification

- `flutter analyze`: passed, **No issues found**, exit 0.
- `flutter test --reporter json`: exit 1; **3,400 passed, 36 failed, zero
  skipped** in 144.390 seconds. These are visible test counts; the JSON also
  contains 428 successful hidden suite/setup events.
- Toolchain: Flutter 3.44.2 (`c9a6c48423`), Dart 3.12.2.
- Relevant real-screen and wire tests passed within the full suite (no need to
  rerun passing tests): `race_detail_screen_test.dart`,
  `race_details_participants_pagination_test.dart`,
  `weekly_race_page_projection_frontend_test.dart`,
  `race_detail_effect_expiry_refresh_test.dart`,
  `api_contract_payload_cleanup_frontend_test.dart`,
  `race_preview_before_join_test.dart`, and
  `race_detail_spectate_readonly_test.dart`.
- No tests or existing assertions were changed, weakened, skipped or deleted.

The backend readiness decision additionally requires the backend real-HTTP
cache/invalidation tests, full baseline/final suite comparison and independent
code review. Client widget tests alone do not prove Redis freshness or query
elimination.

## Existing baseline failures

All failures below occurred on the source SHA above before any frontend runtime
or test changes. The only task-owned frontend file is this document. The full
run is therefore the frontend baseline and final unchanged-source verification;
backend cache behavior must be established separately through HTTP tests.

Individual diagnostic reruns reproduced all 36 failures: metrics 1 pass / 14
fail, system health 5 pass / 11 fail, DAU 3 pass / 2 fail, sections 19 pass / 9
fail. All four commands exited 1. Commands (all preserve assertions):

```sh
flutter test test/admin_metrics_dashboard_test.dart --reporter json
flutter test test/admin_system_health_test.dart --reporter json
flutter test test/admin_dau_engagement_test.dart --reporter json
flutter test test/batch_2026_08_09_admin_sections_test.dart --reporter json
```

The admin tests expect the previous accordion keys/labels (for example
`admin-section-SUMMARY`, `admin-section-SYSTEM HEALTH`,
`admin-section-DAU + ENGAGEMENT`, and `GROWTH`), which the current admin overview
does not render. Missing finders also cause `Bad state: No element` errors.
The metrics suite additionally reports the framework assertion
`ListTile background color or ink splashes may be invisible` under a colored
`DecoratedBox`. These are recorded as existing failures, not silently corrected
or removed; a separate admin behavior/expectation decision is needed.

### `admin_metrics_dashboard_test.dart` (14 failures)

- iOS shows expanded Summary then ordered lazy boards
- provider-only Phase A rows are hidden, DB revenue remains
- Admin onboarding shows tutorial skip as a start-share exit
- disabled and old-backend states preserve Config Inbox Debug
- section error stays inside its board and retry succeeds
- rapid refresh coalesces and reloads only opened blocks serially
- malformed leaves render unavailable and never zero or crash
- valid empty DB results render zero while null stays unavailable
- stale source stays visible with as-of provenance
- metric info affordance opens its definition and source note
- nested and onboarding metrics show exact provenance
- missing section-specific windows render unavailable
- compact and wide iPhones keep long rows inside their boards
- non-iOS keeps the legacy Admin surface and emits no v2 request

### `admin_system_health_test.dart` (11 failures)

- both branches place one lazy section immediately before CONFIG
- renders process rows and exact complete/collecting failure cards
- first expansion shows an in-section loader until data arrives
- status plate distinguishes pressure, degraded, and pool collection
- partial pool keeps four fixed positions and marks the missing row
- valid pool remains visible when failure history is unavailable
- old route, malformed data, and transport errors remain retryable
- refresh failure retains good data and marks it stale
- screen refresh fetches health only after it has been opened
- zero requests and independent pool/history availability render honestly
- narrow large-text layout has no overflow or horizontal scroll

### `admin_dau_engagement_test.dart` (2 failures)

- DAU + engagement dashboard section appears after SUMMARY and requests its section lazily
- DAU + engagement dashboard section Android legacy admin does not request or render the new section

### `batch_2026_08_09_admin_sections_test.dart` (9 failures)

- hub layout renders the six sections in order
- hub layout DEBUG starts collapsed and its toys live inside it
- hub layout CONFIG retains service-banner ops and every sub-screen link
- hub layout no card appears twice across the hub
- lazy section fetching the base payload is fetched once, with no sections
- lazy section fetching REVENUE fetches economy+ads only when first expanded
- lazy section fetching refresh re-pulls REVENUE once it has been opened
- lazy section fetching refresh does NOT fetch REVENUE that was never opened
- lazy section fetching INBOX fetches threads only when first expanded
