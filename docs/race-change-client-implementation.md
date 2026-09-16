# Race-change client implementation (uncommitted; no deployment)

The backend wire contract is authenticated `GET /races/:raceId/changes`, SSE `event: race-invalidated`, JSON `{"raceId":"uuid"}`. Events are hints; there is no score version or replay promise. The existing progress response remains authoritative.

## Behavior
- `BackendApiService.watchRaceChanges` owns a dedicated cancellable HTTP connection, bearer header, no redirects/token query string, bounded parser, and 45s heartbeat timeout. Malformed/foreign hints are ignored. No dependency added.
- `RaceChangeRefresh` owns the visible race connection, fixed 100ms first-event window, one real progress refresh plus one pending follow-up, exponential 1/2/4/8/16/30s retry with jitter. A healthy 30s connection resets retry history. 401/403/404 stops this subscription until auth changes or the screen is reopened (flag off/on alone does not retry an unsupported endpoint); 503/network failures retry. Polling remains independent.
- Only literal `user.featureFlags.raceEventDrivenRefreshEnabled: true` enables it. Missing/malformed authoritative config defaults OFF, partial mutation envelopes preserve the known answer, logout clears it. The value is intentionally not persisted across cold starts.
- Visible ACTIVE real races only. Cover/background/completion/membership loss/logout/dispose cancels stream/timers. Initial connection/reconnection GET current progress. An existing request that began before a hint is awaited, then a fresh GET is issued so a pre-hint snapshot cannot consume the hint.
- Existing 30s polling, manual pull-to-refresh, foreground refresh, projection ordering, local sync receipt behavior remain. A sync acceptance is never treated as score completion. No new local HealthKit sync callback was invented.
- Demo service explicitly overrides the stream with an empty local stream. Tutorial/demo timing and UI placement are unchanged. Billing-preview structural guard now recognizes Stream return types, preserving every existing assertion.
- Timeline markers: `race_change_received`, `race_change_refetch_start`, `race_change_refetch_complete`; progress markers `race_progress_read_start`, `race_progress_read_complete`, `race_progress_state_applied`, `race_progress_read_failed`, `race_progress_frame`. Progress markers share the local fetch sequence, race identity and monotonic elapsed microseconds. The read span includes waiting for a supplied prefetch when present; it must not be labeled raw HTTP time. Frame markers are emitted only after accepted state reaches a visible post-frame callback, with current-response projection generation only when supplied. Failed, superseded, hidden, changed-account and older-projection responses cannot claim a new frame. Optional diagnostics consumers cannot interrupt the refresh. These support local tracing, not a claimed physical-device render measurement or a durable analytics pipeline; SSE does not provide a server generation or end-to-end correlation token.

## Verification
Tests were created before implementation and initially failed because the new stream interface/controller did not exist. 15 new real RaceDetailScreen widget cases and 5 actual loopback HTTP/SSE cases pass. Combined with demo/preview isolation guards, 30 targeted tests pass. Existing lifecycle/projection tests also pass. Analyze is clean.

Full suite before isolation-guard fixes: 3,537 pass, 38 fail. Two new stream guard failures were fixed by the no-network demo override and mechanical Stream signature recognition; their unchanged assertions pass. Remaining 36 failures reproduce on a separate clean detached HEAD baseline. No Admin assertion/code was changed.

### Existing Admin failure root cause
The old tests assert section keys/order, lazy section expansion, legacy non-iOS branching and `fetchAdminStats` calls. Current AdminScreen (commits 94ee67b/a9c4681) renders `AdminDashboardOverview`, navigates details, and loads `fetchAdminStatsView` via its page-aware controller. `isIosForTesting` no longer selects the old layout. Fixtures do not provide the new view endpoint and selectors expect removed sections. Therefore all 36 are stale tests/contracts unrelated to race freshness. The isolated clean baseline reproduces the same 14 + 11 + 9 + 2 failures. Updating the Admin tests to the intentional new product architecture is separate authorized work; they were not weakened here.

Exact failures:
- `admin_metrics_dashboard_test.dart: iOS shows expanded Summary then ordered lazy boards`
- `admin_metrics_dashboard_test.dart: provider-only Phase A rows are hidden, DB revenue remains`
- `admin_metrics_dashboard_test.dart: Admin onboarding shows tutorial skip as a start-share exit`
- `admin_metrics_dashboard_test.dart: disabled and old-backend states preserve Config Inbox Debug`
- `admin_metrics_dashboard_test.dart: section error stays inside its board and retry succeeds`
- `admin_metrics_dashboard_test.dart: rapid refresh coalesces and reloads only opened blocks serially`
- `admin_metrics_dashboard_test.dart: malformed leaves render unavailable and never zero or crash`
- `admin_metrics_dashboard_test.dart: valid empty DB results render zero while null stays unavailable`
- `admin_metrics_dashboard_test.dart: stale source stays visible with as-of provenance`
- `admin_metrics_dashboard_test.dart: metric info affordance opens its definition and source note`
- `admin_metrics_dashboard_test.dart: nested and onboarding metrics show exact provenance`
- `admin_metrics_dashboard_test.dart: missing section-specific windows render unavailable`
- `admin_metrics_dashboard_test.dart: compact and wide iPhones keep long rows inside their boards`
- `admin_metrics_dashboard_test.dart: non-iOS keeps the legacy Admin surface and emits no v2 request`
- `admin_system_health_test.dart: both branches place one lazy section immediately before CONFIG`
- `admin_system_health_test.dart: renders process rows and exact complete/collecting failure cards`
- `admin_system_health_test.dart: first expansion shows an in-section loader until data arrives`
- `admin_system_health_test.dart: status plate distinguishes pressure, degraded, and pool collection`
- `admin_system_health_test.dart: partial pool keeps four fixed positions and marks the missing row`
- `admin_system_health_test.dart: valid pool remains visible when failure history is unavailable`
- `admin_system_health_test.dart: old route, malformed data, and transport errors remain retryable`
- `admin_system_health_test.dart: refresh failure retains good data and marks it stale`
- `admin_system_health_test.dart: screen refresh fetches health only after it has been opened`
- `admin_system_health_test.dart: zero requests and independent pool/history availability render honestly`
- `admin_system_health_test.dart: narrow large-text layout has no overflow or horizontal scroll`
- `admin_dau_engagement_test.dart: DAU + engagement dashboard section appears after SUMMARY and requests its section lazily`
- `admin_dau_engagement_test.dart: DAU + engagement dashboard section Android legacy admin does not request or render the new section`
- `batch_2026_08_09_admin_sections_test.dart: hub layout renders the six sections in order`
- `batch_2026_08_09_admin_sections_test.dart: hub layout DEBUG starts collapsed and its toys live inside it`
- `batch_2026_08_09_admin_sections_test.dart: hub layout CONFIG retains service-banner ops and every sub-screen link`
- `batch_2026_08_09_admin_sections_test.dart: hub layout no card appears twice across the hub`
- `batch_2026_08_09_admin_sections_test.dart: lazy section fetching the base payload is fetched once, with no sections`
- `batch_2026_08_09_admin_sections_test.dart: lazy section fetching REVENUE fetches economy+ads only when first expanded`
- `batch_2026_08_09_admin_sections_test.dart: lazy section fetching refresh re-pulls REVENUE once it has been opened`
- `batch_2026_08_09_admin_sections_test.dart: lazy section fetching refresh does NOT fetch REVENUE that was never opened`
- `batch_2026_08_09_admin_sections_test.dart: lazy section fetching INBOX fetches threads only when first expanded`

## Platform compilation
Both platforms compiled locally: iOS simulator debug Runner.app and Android prod-flavor debug APK, using README-aligned configuration. These are compile checks, not signed release verification or physical-device tests.

## Rollback and activation
Owner: Bara mobile/backend maintainers. Default OFF. Disable `raceEventDrivenRefreshEnabled` in authoritative user config to cancel streams on config refresh; disable backend notifications independently. Existing GET/poll/foreground/manual behavior works on old or new apps/backends. No schema or binary rollback is needed to preserve score correctness. Remove the temporary control only after the parent migration plan's two app release cycles + 14 clean days and rollback drill; do not silently leave it as permanent infrastructure.

Backend endpoint/cache publication must be deployed and verified before enabling the client flag. Both platform builds are required before distributing a binary. Nothing was uploaded or deployed. Physical iPhone, poor-network propagation and actual render freshness remain unmeasured. No p95/p99 physical-device result is claimed.

## Production wiring follow-up — September 14

The authority/native enrollment portion is paused independently: legacy daily/sample disagreement cannot be repaired by inventing step placement, and extending an open sample can reduce prorated race-window credit even when its total increases. No enrollment UI or native authority writer was enabled. See the provider-authority review and backend architecture decision. Existing v2 behavior was preserved.

The race SSE path was already wired in the isolated implementation. This follow-up makes its diagnostic markers truthful: only a current response that is actually applied can reach `race_progress_frame`, and an unversioned response never borrows a previous generation. Three added real-screen tests cover success-to-frame correlation, a failed refresh retaining old data without a new-frame claim, and versioned-to-unversioned response metadata. The tests were written first and exposed the missing sink / stale-generation issue before their fixes.

Final targeted checks: **50 passed**, including SSE transport, real race screen, lifecycle, paginated projections and demo/preview isolation. `flutter analyze` is clean. Independent reviewer approved the instrumentation delta after fixes. Both final debug compile checks passed: iOS simulator `Runner.app` and Android prod-flavor `app-prod-debug.apk`, using README-aligned configuration. These are not signed distribution artifacts. The [device checklist](step-sync-testflight-validation-20260914.md) records unmeasured physical results and the future blocked authority checks explicitly.

The final full Flutter run still has the same **36 pre-existing Admin failures** documented above (14 metrics dashboard, 11 system health, 2 DAU, 9 old Admin sections), with no remaining new-feature failure. Their clean-baseline root cause remains the old Admin API/layout fixtures; no assertions were weakened. The intermediate full run additionally observed the newly introduced metadata regression before its fix; its final focused and full-suite executions pass.
