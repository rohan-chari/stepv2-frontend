# Admin dashboard redesign

Status: implemented and code-reviewed; static/existing-control checks passed. Manual device placement checks remain pending.

Release follow-up: [TestFlight 2.3.13 (17)](admin-redesign-testflight-17.md) is verified and available to internal testers; matching Android artifact built and verified.

## Summary and user story
As the administrator, I want a readable overview and focused detail pages so I can understand app activity without scrolling through technical tables. User selected clean typography, overview/detail navigation, charts, four headline metrics, and a default seven-day range. User explicitly waived adding automated tests for this redesign.

## Approved content
- Keep accounts, signups, app opens, action-based active users, D1/D7/D30 retention, current race participants and running races.
- Keep invite opens/signups and signup-to-race-to-reward progression, onboarding drop-off, repeat racers, public/private participation, friend distribution, box/powerup/daily-reward/leaderboard usage.
- Keep rewarded ads by type, unique ad viewers, ad-limit hits, top shop items and system health.
- Remove standalone first-24-hour Health/race activation metrics, coin inflow/outflow, reroll conversion, notification-open breakdowns, and version/platform breakdowns. Do not remove Health steps from the approved onboarding funnel. Platform coverage labels remain necessary even though platform breakdown tables are removed.
- Remove duplicate union-users and arithmetic-average estimates from presentation. Do not alter backend activity definitions, including notification events that contribute to existing totals.
- Preserve all existing admin tools and access controls. No game balance, pricing, telemetry collection, backend behavior or release changes.

## Visual and navigation plan
Use a warm neutral background, near-black sans-serif text, restrained green accents, thin dividers and rounded cards. No game scenery, wooden signs or pixel typography in the new analytics shell. Respect light/dark theme, safe areas and large text on iOS and Android. Use existing font assets; no art generation needed.

Overview order: compact Admin title with Tools and refresh; small total-account count and coverage note; Today / 7 days / 30 days control (7 days initially); two-by-two headline cards for New signups, App opens, Active users, People racing; one compact trend chart with selectable signup/app-open/action series; compact detail links. At narrow widths/large text, reflow cards instead of clipping. Target headline cards within the first typical phone viewport, with at most a short scroll for detail links; no expanded metrics sections.

Headline cards show supported scope explicitly: selected-period signups when derivable, app-open counts from DAU/WAU/MAU for Today/7d/30d respectively; action-based users remain marked Today with selected-range daily trends, and race participants marked Now. Never imply a seven-day unique count by summing daily unique users. App-open values mean people, not sessions. Preserve tracked-iOS scope and race exclusions in visible short subtitles. Total accounts retains its actual population definition.

Detail pages:
1. Growth: signup trend and observed app-open trend.
2. Activity: action-based daily users; compact usage rows for boxes, powerups, daily rewards and leaderboard views, with chart on selection only where the existing payload contains daily values (otherwise numeric detail).
3. Retention: exact-day D1/D7/D30 returns from summary's pooled mature cohorts, eligible cohort counts, and repeat racing within 7/30 days from a fixed 90-day retention cohort request. Display both fixed scopes explicitly. Selected-window signup cohort detail remains separate: a 7-day signup window cannot yield mature D7, and neither selectable window can yield mature D30. Do not incorrectly present these as broken metrics or zero returns.
4. Races & friends: current participants/races, public/private race counts, friend distribution. Contract verification found the available public/private breakdown counts races created, not distinct participating users: label it Public/private races created, and keep actual participant counts separate. Retain separate race types where totals cannot safely be combined.
5. Invites & onboarding: two local tabs with compact funnel steps and counts/conversions. Preserve onboarding branches, skips, Health escape and inconclusive side exits; do not treat every row as a sequential conversion.
6. Ads & shop: two local tabs; ads by reward type and daily unique viewers; fixed-scope ad-limit statistic; shop items ranked by purchase count (coin purchases in existing two shops, not cash revenue or IAP sales).
7. System health: dedicated page using existing health data, short overview followed by operational details.

Tools opens a separate page containing existing configuration, inbox and debugging actions; omit release-adoption analytics. Keep operational controls behavior intact. Back navigation preserves overview range, chart selection and scroll. Detail pages inherit range; changes update the session selection. No persisted preferences or feature flags.

Metric cards show number, concise label and period; info opens definitions, provenance and denominator. Partial coverage/collecting badges remain visible. Charts use honest axes, accessible numeric equivalents and date/value selection; gaps remain gaps, not zeros. No fabricated trends or comparisons. Daily history becomes a chart rather than a long table; optional bounded rows on demand. Snapshot metrics have no invented chart.

## Existing code and implementation path
- `lib/screens/admin_screen.dart:531`: existing state and request ownership; requests currently hardcode 30d at line 601. Replace dashboard composition at line 1145, preserving injected API/auth and all tools. Remove the platform split at line 567 so iOS and Android use the same new shell and dashboard reads; this does not expand the backend metric population beyond tracked iOS. Preserve the public test injection parameter for source compatibility.
- `lib/screens/admin_metrics_dashboard.dart:155`: summary and existing definitions; use as provenance for compact projections. Activity implementation at line 786 currently duplicates action counts and estimates.
- `lib/screens/admin_sections.dart:329`: legacy engagement; revenue at line 448 includes shop and cap data needed by new detail pages.
- `lib/screens/admin_onboarding_funnel.dart`: preserve real funnel data/coverage in new styling.
- `lib/screens/admin_system_health.dart`: existing operational health body and retry states.
- `lib/models/admin_metrics_dashboard.dart`: defensive envelope and daily activity series; extend display projections only when needed.
- `lib/services/backend_api_service.dart:2773`: existing stats transport; no second HTTP surface.
- `lib/screens/settings_screen.dart:427`: existing admin entry. Search found no demo/tutorial AdminScreen mount; planner must verify mirrors.

Implementation sequence: backend agent verifies the existing contract only and reports no server changes; frontend agent extracts reusable admin navigation/data state, adds compact presentation widgets and routes, wires range-aware requests and charts, moves tools, removes rejected metric presentation, then validates compatibility and analysis. Suggested new files: `lib/screens/admin_dashboard_overview.dart`, `lib/screens/admin_dashboard_detail.dart`, `lib/widgets/admin_metric_widgets.dart`. Agents must preserve unrelated workspace modifications.

## API contract and data model
No new or changed endpoints, JSON fields, required parameters, migrations or backfills. Existing authenticated GET `/admin/stats?sections=<one-section>&window=7d|30d` returns `{ "stats": { ...existing payload... } }`. Existing parser remains authoritative. Sections: dashboard-summary, dashboard-growth, dashboard-dau-engagement, dashboard-retention, dashboard-engagement, dashboard-activation (friends), dashboard-funnels, dashboard-revenue. Legacy economy/ads sections supply purchasesBySku and capUtilization only when Ads & shop opens. System health retains GET `/admin/system-health?window=60m`.

Backend evidence: `src/modules/admin/adminMetricsDashboard.js:63` accepts 7d/30d/90d, not Today. Retention detail may make one lazy existing `dashboard-retention&window=90d` request for mature repeat-racing cohorts, cached separately from selectable ranges; this is not an additional user range control. Today requests reuse 7d and select the current ET daily bucket only for daily series; anchor dates to response window.end / activity todayDate, not the device local date, and show freshness; aggregates without daily data cannot be filtered to Today. Such panels display their fixed supported range and omit an inapplicable selector. Retention horizons are not date-range choices. Current snapshot panels retain Now. Never relabel rolling 30-day legacy purchases as seven-day data.

`src/modules/admin/getAdminStats.js:142` supplies fixed trailing-30-day shop purchases. Its capUtilization is coin-ad users reaching cap on the latest recorded user-local grant day within 30 days, not necessarily today; the date itself is not returned. Explicitly label this limitation in the card and info. No general all-ad cap claim. Do not change prices/caps or require new fields to improve this label.

Load summary/growth/action data for overview with the existing serial request queue; lazy-load other sections only upon navigation. Use the existing serial queue (concurrency one) rather than introducing parallel database work. Cache by section and API range, deduplicate overlapping requests, and ignore stale completions after range changes/disposal. Today and 7d can reuse the same source response. Refresh only currently visible dependencies. Do not call every detail endpoint on refresh. Legacy expensive economy reads run only when Shop is opened. Do not introduce auto-polling.

## States and compatibility
Per-card loading placeholders; valid zero stays zero; absent/malformed data shows Unavailable; incomplete history shows Gathering data. A failed section has local retry without blanking working cards. Retain stale values only with explicit stale timestamp/status. Preserve 401/403 behavior and safe 404/older-server handling; do not restore the cluttered legacy overview as fallback. Legacy data can populate compatible compact cards with its own correct definitions, otherwise unavailable. No casts/assertions on unchecked server values. Coverage limitations cannot hide inside an info sheet alone.

No production endpoint verification performed during planning; implementation relies solely on already-consumed fields and tolerates their absence. Frozen clients are unaffected because backend contract and data collection remain unchanged. No deployment required; shared Flutter implementation serves both platforms. Any later server change needs a revised additive contract before implementation. No build/upload requested.

## Validation and acceptance
User waiver overrides the skill's new-tests-first requirement for this redesign. Do not add automated tests solely for this task. Never weaken/remove existing assertions to silence failures; surface any obsolete layout expectations for explicit disposition. Run flutter analyze after implementation; run relevant existing tests where useful and report outcomes honestly. No tests or builds required for this planning-only document. Required architect/UI planning reviews precede approval; code reviewer follows implementation.

Accepted when selected metrics exist on the assigned pages, rejected analytics are absent, overview is compact, definitions/time scopes are truthful, range navigation and retry work, no backend workload expansion beyond bounded on-demand reads, both platforms and mirrored surfaces are covered by manual checklist, and required review findings are addressed.

## Manual UI-placement test plan
- **iOS and Android:** Sign in as admin → Profile → Settings → Admin Tools. Confirm both show the same overview structure.
- **Overview:** Confirm total accounts, range control, four headline cards, chart, then detail links. Headlines fit the initial viewport; old expanded sections are absent.
- **Growth / Activity:** Open each detail page. Confirm trends and usage rows appear there, without duplicate activity estimates or long default tables.
- **Retention / Races & friends:** Confirm retention, repeat racing, race participation, and friend distribution appear on their assigned pages.
- **Invites & onboarding / Ads & shop:** Visit all four local tabs. Confirm funnels, ad stats, and purchases occupy their assigned tabs; rejected panels are absent.
- **System health / Tools:** Confirm separate destinations; configuration, inbox, debugging, and existing tool links appear only under Tools.
- **Both devices, large text:** Check cards reflow, controls and overlays remain reachable, coverage labels remain visible, and Back restores overview position.
- **Mirrors verified in code:** Demo race, tutorial previews, copied tutorial tab bar, and spotlights contain no admin surface or anchor; no mirrored placement changes are needed.

Planner risks incorporated: unify legacy/dashboard compositions so fallback cannot restore the long page; inventory all existing Tools entries to avoid duplication or omission; extract only selected legacy shop/cap fields rather than mounting entire rejected sections; check fixed-range badges at large text.

## Revision log
- Gap pass 1: identified unsupported Today API token; defined client daily-bucket filtering, fixed-scope exceptions and no summing daily unique users.
- Gap pass 2: retained friends despite removing activation panel; distinguished latest-recorded-day coin-ad cap and fixed-30-day coin shop purchases; kept coverage badges visible and preserved unrelated working changes.
- Architect review: required removal of iOS-only shell gate incorporated; also incorporated genuine app-open DAU/WAU/MAU selection, response-anchored ET dates and onboarding branch/skip semantics.

- Final architect disposition: APPROVE; no required changes outstanding. UI planner completed and checklist incorporated.
- Implementation authorized by user. Backend agent locked the existing API contract without server changes. Unique ad viewers remain daily; daily distinct viewer counts cannot become a period unique total.
- Early implementation review requested a persistent date/time freshness label for cached Today/Now data, even after a successful request. Final combined review remains pending.
- Detail review found retention cohort maturity limitations: use existing pooled summary returns and fixed90d mature repeat-racing cohorts. Ad totals must check every selected date before presenting a complete period sum.

## Implementation validation
- Shared overview, seven detail destinations and separate Tools implemented in the admin screen, controller, overview, detail and metric-widget files. Existing health view restyled and daily action projection extended defensively.
- Final code-reviewer verdict: SHIP, no outstanding findings. Review fixes include pooled mature retention, first-completion-date repeat-racer cohorts, incomplete ad-history handling, deferred detail loading, source freshness and bounded definition sheets.
- Full `flutter analyze --no-pub`: clean after final edits. `git diff --check`: clean.
- Existing `admin_api_wire_contract_test.dart` and `banner_ads_admin_toggle_test.dart`: 45 passed after implementation. No new tests or existing assertion changes. Full suite and old stacked-layout suites were not run; several existing layout assertions intentionally describe the replaced UI and remain untouched under the user's test waiver.
- iOS and Android share the new Dart shell. No simulator/device placement pass, platform build, upload, deployment or production API call performed. Use the manual checklist above for device verification.
- No backend, migration, dependency, game-balance or unrelated native changes made by this task. Older clients retain the same backend contracts; missing data remains unavailable.
