# Admin page field and window map

Read-only code audit for `admin-page-memory-requirements.md`. This document uses the revised `stats.view` + `stats.sections` response contract. It does not authorize implementation or deployment. Paths below are repository-relative; backend paths refer to the separate backend repository.

## Request and envelope rules

One request per visible page: `GET /admin/stats?view=<view>&window=<7d|30d>&sections=<compatibility hint>`. A view response contains `stats.view`, `stats.generatedAt`, optional/additive `stats.snapshot`, and `stats.sections[sectionKey]`. Each section value is an existing **inner stats payload**, not another `{stats: ...}` wrapper. Keep its `generatedAt`/`snapshot` equal to the completed page snapshot.

For v2 inner payloads, preserve `metricsDashboard.schemaVersion: 2`, `status: available|disabled|unavailable`, `window: {days,start,end,timeZone: America/New_York}`, and relevant `sources`/`coverage`. `enabled` is not a valid renderer status. Project only the fields listed below. Every listed ratio retains `{numerator,denominator,percent}`; do not replace missing values with zero.

Freshness always needs truthful `sources.productDb.{status,asOf}`. The existing foreground freshness presentation also uses `sources.foregroundActivity.{status,asOf}` on Overview's growth/activity sections and the Growth, Activity and selected-window Retention sections. Provider placeholders do not require provider calls. The remaining displayed coverage requirements are listed per page; they do not justify calculating all coverage metrics.

## Exact visible fields

Paths in this table start below `metricsDashboard`, except where explicitly marked legacy.

| View / first compatibility section | Required section payloads and fields |
|---|---|
| `overview` / `dashboard-summary` | `dashboard-summary`: `summary.growth.{totalSignups,signupsToday,signupsLast7Days,observedForegroundDau}` and `summary.races.usersInActiveNonFeaturedRaces`. `dashboard-growth`: `userGrowth.daily[].{date,signups,observedForegroundUsers}`, `userGrowth.{observedForegroundWau,observedForegroundMau}`. `dashboard-dau-engagement`: `dauEngagement.actionBasedDau.{users,status}`, `dauEngagement.today.date`, `dauEngagement.daily[].{date,actionBasedDau}`. |
| `growth` / `dashboard-growth` | `userGrowth.daily[].{date,signups,observedForegroundUsers}`, `userGrowth.{observedForegroundWau,observedForegroundMau}`. |
| `activity` / `dashboard-dau-engagement` | `dauEngagement.actionBasedDau.{users,status}`, `dauEngagement.today.date`, `dauEngagement.today.actions.<action>.{users,events}` for `boxOpen`, `powerupUse`, `dailyRewardClaim`, `leaderboardView`; `dauEngagement.daily[].{date,actionBasedDau,action_boxOpen,action_powerupUse,action_dailyRewardClaim,action_leaderboardView}`. |
| `retention` / `dashboard-summary` | `dashboard-summary`: `summary.retention.{d1,d7,d30}` ratios. `dashboard-retention`: `retention.cohorts[].{signupDate,eligibleSignups,d1,d7,d30}` (last three are ratios). `dashboard-retention-mature`: `retention.{secondRaceWithin7d,secondRaceWithin30d}` ratios. The mature alias is a response key only; never send it as an old backend section. |
| `races` / `dashboard-summary` | `dashboard-summary`: `summary.races.{usersInActiveNonFeaturedRaces,activeNonFeaturedRaces,activeDailyRaces}`. `dashboard-engagement`: `raceEngagement.daily[].{date,liveRaceParticipants}`, `raceEngagement.visibility.{public,private}` ratios, `raceEngagement.featuredParticipation.<daily|weekly>.{activeOverlapUsers,joinedWindowUsers}`, `raceEngagement.rankedParticipationUsers`. `dashboard-activation`: `activation.friends[].{bucket,ratio}`. |
| `invites` / `dashboard-funnels` | `inviteFunnel.{linkOpens,uniqueLinkOpens,attributedSignups,joinedRace,qualified,rewarded}`; ratios `openToSignup`, `signupToJoinedRace`, `joinedRaceToQualified`, `qualifiedToRewarded`. |
| `onboarding` / `dashboard-funnels` | `onboardingFunnel.cohortWindowDays`, `onboardingFunnel.stages[].{key,count,previousSpineConversion,startConversion}`; last two are ratios. All existing spine/branch keys remain, including health escape/inconclusive and tutorial skip. |
| `ads` / `dashboard-revenue` | `dashboard-revenue`: `revenue.daily[].{date,uniqueSsvWatchers,ssvGrants}`, `revenue.daily[].ssvByRewardKind[].{rewardKind,grants}`. Legacy `ads`: `adRevenue.capUtilization.usersAtCap`. |
| `shop` / `economy` | Legacy `economy`: `coinEconomy.purchasesBySku[].{sku,count}`. Purchase rows continue using separate `/admin/purchases`, with their own fixed 30-day cursor window and current username reads. |

## Windows and cohort semantics

- `AdminRange.today` and `AdminRange.week` both request **7d**; `AdminRange.month` requests **30d** (`admin_dashboard_controller.dart`). Today uses one daily bucket ending at the server's `window.end`; it does not use the phone's current date (`adminDailyPoints` in `admin_metric_widgets.dart`). Today/7d may share one page cache safely because they have the same source payload.
- Overview Today uses `signupsToday` and `observedForegroundDau`; 7 days uses `signupsLast7Days` and `observedForegroundWau`; 30 days sums complete daily signup buckets and uses `observedForegroundMau`. The Active users card is always today's value and People racing is always current, regardless of the chart range.
- Growth always displays both WAU and MAU, even with Today/7d selected. Therefore its distinct foreground input must cover the trailing **30 ET days**, while its daily chart output uses the requested window. Do not reproduce the old SQL defect where a 7d base filter can incorrectly truncate the MAU calculation.
- Activity's headline and four feature rows always describe today. Its chart uses the selected window. All **nine** existing qualifying action categories are required to form the exact union, even though only four per-feature series are displayed. Neither Overview nor Activity displays comparisons; no 61-day comparison history is needed.
- Retention's summary ratios pool the **latest 30 mature eligible signup dates separately for each horizon**, not the selected 7/30-day chart window. Current maturity cutoffs are D1 `end-2`, D7 `end-8`, D30 `end-31`, from `pooledRetention()` in backend `adminMetricsQueries.js`. Each ratio counts exact signup-day-plus-horizon returns. Preserve existing coverage denominators, which can include ineligible users born on those selected cohort dates.
- Retention's daily cohort section uses the selected 7/30-day window, including unavailable immature returns. Its repeat-race section always uses a **90-day first-completion window** and stamps the alias envelope `window.days=90`. Determine the historical first qualifying race before filtering its completion into that window; an earlier race outside the window must not disappear. Do not calculate 90-day signup cohorts or selected-window repeat ratios just to fill unused fields.
- Races and Invites use the selected 7/30-day window. Current counts and friendship distribution stay current. Featured overlap, featured joining and ranked overlap retain their distinct definitions. Onboarding uses a selected 7/30-day start cohort with the existing 24-hour maturity/observation rule.
- Ads' daily series uses the selected window, but the cap metric retains the existing trailing 30-day grant scan and **latest recorded grant date across that population**. The existing backend uses `MAX(granted_date)` globally, not a separate latest date per user; UI wording has drifted and must not silently redefine the metric during this optimization.
- Shop popularity is fixed trailing **30 days**, independent of the shared range. The new page request should normalize Shop to `window=30d` so switching another page's range does not duplicate identical Shop snapshots.
- System health remains its own `/admin/system-health?window=60m` route and freshness policy. No page-analytics timer or 15-minute cache should replace it.

## Truthful coverage versus unused contracts

Coverage nodes retain `{status,collectingSince,eligible,totalPopulation,eligibilityPercent}` when rendered. Required coverage is narrower than the universal legacy coverage query:

| View | Required displayed coverage and supporting eligibility |
|---|---|
| Overview | Summary `observedForegroundDau`; Growth `observedForegroundDau`, `observedForegroundWau`, `observedForegroundMau`. Epoch timing and eligible/current retained users are necessary. Nine-action source eligibility remains necessary for correct counts, even without nine coverage badges. |
| Growth | `observedForegroundDau`, `observedForegroundWau`, `observedForegroundMau`; epoch and foreground eligibility. |
| Activity | `boxOpen` operational coverage and `leaderboardViews` selected-window coverage. Leaderboard coverage includes its capable-racer numerator/population, so a narrow eligible-racer probe is legitimate; it does not justify the complete Races page or first-race-power calculation. Source-level notification/open capability is still necessary for exact action inputs. |
| Retention | Summary `retentionD1`, `retentionD7`, `retentionD30`, including eligible/total counts for the actual pooled cohort dates; signup epoch and exact-return eligibility. |
| Races / Invites / Onboarding / Ads / Shop | No additional metric-coverage badge is directly rendered. Preserve actual source eligibility and availability needed to calculate their fields (for example referral HMAC readiness, onboarding capability and retained/review exclusions). Do not populate unrelated coverage merely because older full sections contained it. |

Unneeded work includes first-race-power and notification-population coverage on Overview/Growth/Ads; summary retention on Overview/Races; activation health/race24h/first-power and race time series when only friend buckets are used; engagement coin balances/quantiles, ledger, powerups, daily rewards, notification rates and foreground/leaderboard averages; the other funnel tab; legacy base analytics for Ads/Shop; legacy Ads daily/reroll metrics; Shop coin-ledger/box-open series.

## Client implementation proposal (pending contract lock)

1. Define a stable view descriptor with its result section keys, first compatible old section, and normalized page window. Use one `fetchAdminStatsView` API call per page visit/refresh. Keep all HTTP in `backend_api_service.dart`.
2. Cache page state by `(view, apiWindow)`; each page owns its section-state map, pending operation and freshness. Renderer reads must include the view identity. Do not infer view from section, because summary and funnels are deliberately shared names with different projections.
3. Capture view/window before awaiting. Distribute a validated `stats.sections` result only into that captured page's section map. Preserve the mature alias's 90-day inner envelope; do not create a global 90d retention entry that bypasses page identity.
4. Absence of both `stats.view` and `stats.sections` indicates an old backend. Reuse that reply for the first compatible section, then request only that page's remaining old sections, serially, once per fallback load. A session-level known-old-server state can avoid repeating the unsupported view probe. An advertised malformed/mismatched page response is an error, not permission to fan out more requests.
5. Keep valid supplied false/zero/empty values; missing section fields remain unavailable. Preserve old data on transport/503 failure with stale/checking presentation. Explicit disabled envelopes evict enabled cached page data. Authentication errors do not trigger fallback or completion retries.
6. Bind the existing one-session visible-route timer and bounded 50-second completion checks to page loads, not individual sections. A stale/503 page requires one page follow-up, at most twice per 15-minute cycle. Hidden/background/disposed views make no requests. Purchase pagination remains independent, and automatic analytics completion checks do not reload purchases.
7. New tests first: one request and no unopened-page requests; overlapping section names isolated by view; Today/7d reuse and 30d switch; late range/route responses; mature90d metadata; old backend fallback once with first reply reused; malformed advertised contract never fans out; lifecycle and stale/503 completion; existing purchase username behavior.

## Code references and conditional projection notes

- [Overview renderer](../lib/screens/admin_dashboard_overview.dart): section list at line 7; cards/chart field selection at lines 30–167; coverage and freshness at lines 66–114 and 274–281.
- [Detail renderer](../lib/screens/admin_dashboard_detail.dart): page dependencies at line 29; Growth at 267; Activity at 313; Retention at 387; Races at 453; Invites at 558; Onboarding at 616; Ads at 693; Shop at 803. These are real renderer reads, not the older unused `admin_metrics_dashboard.dart` accordion renderer.
- [Range mapping and controller](../lib/screens/admin_dashboard_controller.dart): `AdminRange` at line 10. [Daily bucket selection and freshness](../lib/widgets/admin_metric_widgets.dart): `adminDailyPoints` at 392; `AdminFreshness` at 621. [Defensive envelope models](../lib/models/admin_metrics_dashboard.dart): `AdminCoverage` at 210; `AdminDauEngagement` at 388; envelope parsing at 508.
- Backend implementation evidence: `src/modules/admin/getAdminStats.js:117` (economy), `:197` (Ads), `:428` (13-query legacy base); `src/modules/admin/adminMetricsQueries.js:56` (universal coverage), `:279` (foreground), `:318` and `:339` (observed/pooled retention), `:664` (repeat-race semantics), `:868` (unused DAU comparison history).

Overview's MAU is only displayed for the 30-day selection; its 7d payload serves Today and 7 days and needs DAU/WAU plus the 7d charts. It does not require a 30-day foreground scan solely to fill an unused MAU leaf. Growth differs: it always displays both WAU and MAU, so its 7d request genuinely needs 30 days of foreground input. The table lists the union of each view's renderer paths across supported windows; implementations may omit a leaf when that window cannot render it, without starting work for another window.

Expected page error states: a cold 503 is loading/checking and eligible for bounded follow-up, without inventing zero metrics; a transport/build error retains any last usable page visibly stale; a plain old-backend response permits the single compatibility fallback; an advertised malformed view payload stays an error; 401/403 remains an authentication/authorization error; a valid disabled envelope removes enabled cached numbers. A missing individual metric or malformed row is unavailable within that page and never triggers another page's loader.
