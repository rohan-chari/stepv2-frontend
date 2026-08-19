# Admin metrics dashboard rework — requirements

Status: **IMPLEMENTED — default-off rollout; production-like performance gate pending**

## 1. Summary and user story

Rework the statistics area of the in-app Admin Tools screen into an operator
dashboard whose labels match what the system actually measures. The dashboard
must lead with a compact product-health summary, then provide drill-down
sections for growth, invite and onboarding funnels, activation, retention,
race engagement, virality, and revenue.

As the product owner, I want every displayed number to have a precise
population, window, timezone, and source so I can make product decisions
without mistaking a background step sync, a client telemetry event, or an
estimated provider report for a true user action.

This spec distinguishes four feasibility states:

1. **DB now** — can be computed from durable rows already collected, subject to
   the retention/deletion caveats in §3.
2. **Forward-only** — needs a new event or durable fact; no honest historical
   backfill exists.
3. **Provider** — comes from App Store Connect or AdMob and requires a
   credentialed asynchronous import.
4. **Unavailable** — cannot be computed honestly with the current product or
   source granularity.

The dashboard must never render an unavailable or not-yet-instrumented metric
as zero.

### 1.1 Scope and non-goals

**In scope for this feature (Phase A):** rework the statistics UI; add all
selected database-backed metrics; correct invite/onboarding percentages; add
foreground, health-connect, leaderboard-view, and notification-open
instrumentation; expose nine lazy additive admin-stat blocks; and move app
version adoption under Debug. The dashboard and all new instrumentation are
iOS-product scoped; no alternate-platform analytics, store provider, series,
dimension, or UI placeholder is added.

**Explicitly deferred to a separately approved Phase B:** credentialed imports
from App Store Connect and AdMob. Phase A keeps provider-only
metrics absent/unavailable and reserves defensive response/UI states, but does
not add provider credentials, import jobs, cache tables, or claim provider
revenue/install numbers are available.

**Non-goals:** adding real-money purchases; calculating ARPPU or user-level LTV;
changing game prices, payouts, odds, or coin awards; changing invite copy or
running an invite-copy experiment; removing legacy admin response keys; and
turning analytics into gameplay/reward authority.

## 2. Evidence from the current implementation

- The current admin hub has collapsible `GROWTH`, `ENGAGEMENT`, and `REVENUE`
  sections, with the base statistics request eager and expensive revenue
  sections lazy (`lib/screens/admin_screen.dart:320-365, 489-523`).
- `GET /admin/stats` is the single current stats endpoint. Optional section
  names are already ignored when unknown, which is the compatibility seam for
  a newer app against an older backend
  (`src/modules/admin/getAdminStats.js:23-42`, backend repo).
- Current “DAU (stepped today)” is distinct users with a `steps` row for the
  current ET date (`src/modules/admin/getAdminStats.js:426-442`; rendered at
  `lib/screens/admin_sections.dart:249-260`). A step row may be produced by a
  sync rather than an intentional foreground visit, so it is not DAU.
- Mystery-box opens are durable server rows (`race_powerup_events` with
  `event_type='MYSTERY_BOX_OPENED'`) and can support exact daily engaged-opener
  counts from the date that event began shipping
  (`src/modules/admin/getAdminStats.js:542-555`; schema
  `prisma/schema.prisma:1748-1769`).
- `users.created_at`, `races.created_at/started_at/completed_at/seed_id`,
  `race_participants.joined_at/finished_at/status`, `race_powerup_events`,
  `coin_transactions`, `daily_reward_claims`, referrals, and friendships
  provide durable sources for most product metrics
  (`prisma/schema.prisma:9-137, 424-445, 682-724, 1104-1235, 1264-1294,
  1404-1519, 1748-1769, 1816-1877`).
- Current activation telemetry is authenticated, allowlisted, best-effort
  client telemetry. It retains bounded context and app/platform dimensions;
  the cleanup window is 90 days (`src/modules/analytics/routes.js:1-145` and
  `src/modules/analytics/activationEventCleanup.js`). It is useful for funnels
  but is not an authoritative server transaction log.
- Visible pushes have a server send audit row, currently pruned after seven
  days, but notification taps are routed locally without a corresponding open
  event (`prisma/schema.prisma:2037-2066`; `lib/services/notification_service.dart:138-145`).
- The app has no StoreKit/RevenueCat dependency or
  real-money purchase model. Existing shop “purchases” spend virtual coins and
  therefore are not revenue.
- Apple exposes first-time downloads, installations, sessions, active devices,
  and deletions through App Store Connect Analytics, but usage/deletion data is
  opt-in, thresholded, and may include statistical privacy treatment. The
  Analytics Reports API supports ongoing and snapshot bulk reports.
- The AdMob reporting API exposes impressions, estimated earnings, matched
  requests/match rate, and observed eCPM, including mediation dimensions. It
  does not expose an authoritative per-user revenue allocation.

External references:

- Apple metric definitions:
  https://developer.apple.com/help/app-store-connect-analytics/reference/metrics-definitions/
- Apple Analytics Reports API overview:
  https://developer.apple.com/help/app-store-connect-analytics/overview/analytics-reports-api
- AdMob reporting overview:
  https://developers.google.com/admob/api/v1/report-overview

## 3. Product definitions

Unless a row explicitly states otherwise:

- Product/database days use `America/New_York` calendar boundaries.
- Provider rows retain and label the provider's own reporting day/timezone.
  They are not silently rebucketed into ET when only daily aggregates exist.
- “iOS user” means every retained `users` row with
  `users.is_review_account=false`, regardless of whether the account used Apple
  or Google Sign-In. The production population is iOS-only; authentication
  provider is not a platform signal. Every v2 user population, eligibility
  stamp, cohort, race membership, ledger/reward fact, referral owner/signup,
  and denominator applies this predicate. Legacy stats queries remain
  unchanged. Provider aggregates are the exception: AdMob/Apple do not provide user-level
  identity with which to remove review accounts. A future provider numerator
  must disclose that it may include review traffic before it is divided by a
  non-review product-DB denominator.
- “Non-featured race” means `races.seed_id IS NULL` and
  `races.tournament_id IS NULL`. This includes public/private and normal/team
  user-created races. Tournaments are reported separately.
- “Featured event” means a race whose joined `race_seeds.cadence` is `DAILY`
  or `WEEKLY`.
- “Participating” means an `ACCEPTED` race participant, not an invited or
  declined row.
- Every user-created-race metric requires an iOS creator and excludes a race
  whose creator is a review account, including Summary counts, daily counts,
  participants, averages, visibility, repeat-race cohorts, and power-up
  denominators. Membership/user numerators also require iOS users. Seeded
  daily/weekly races have no equivalent user-creator exclusion and remain in
  their explicitly featured metrics. Tournament races remain excluded unless
  a row explicitly names tournaments.
- A count is `null` when its source is unavailable/not yet imported. Zero is
  reserved for an available source that returned no qualifying rows.
- Percentages return `{numerator, denominator, percent}`. If denominator is
  zero, `percent` is `null`, never `0`.
- Currency is returned in integer micros plus an ISO 4217 currency code.
- A “mature” cohort excludes users/sessions that have not yet had the complete
  measurement interval. Partial current cohorts never enter a denominator.
- Coin ledger, daily-claim, and SSV-grant history describes **retained
  accounts**, not immutable all-time history. Account deletion removes/cascades
  these rows, so historical rollups may revise downward.
- All account/race-derived historical metrics are survivorship views over rows
  still retained at query time. Deleted accounts and cascaded memberships are
  not reconstructible and must not be labeled immutable all-time totals.

## 4. Dashboard information architecture

The visual direction is a dense, trail-map-style operator console that reuses
the app's `TrailSign`, `ContentBoard`, parchment palette, and `PixelText`
language. It should feel native to Bara rather than like a generic Material
analytics template. The memorable interaction is progressive disclosure: a
single “trailhead” summary shows today's health; tapping a metric opens its
definition/source note, while collapsed route-marker sections expose deeper
trends without making the screen a wall of numbers.

Order:

1. **Summary** (expanded, fetched on screen open)
   - Growth: total accounts; signups today; signups last 7 days; daily engaged
     box openers; observed foreground DAU and WAU with eligibility coverage.
   - Retention: capability-scoped observed D1, D7, D30 retention.
   - Races: unique users in active non-featured races; active non-featured
     races; active daily races; non-featured races created today.
   - Money is omitted in Phase A. Phase B may add AdMob estimated revenue and
     revenue/DAU using provider-latest data with an `as of` badge.
2. **User growth**
3. **Invite funnel** (preserve the useful current funnel, correct labels)
4. **Onboarding funnel** (iOS only, corrected denominator semantics)
5. **Activation**
6. **Retention**
7. **Race + engagement**
8. **Virality**
9. **Revenue**
10. **Release adoption** under `DEBUG`, not in product-health Growth.

Every section shows `asOf`, its window, timezone/source badge, and one of:
loading, data, empty (valid zero), unavailable (missing source), or error with
retry. Stale provider data remains visible with a `STALE · through YYYY-MM-DD`
badge rather than disappearing.

## 5. Metric feasibility and exact definitions

### 5.1 Summary

| Requested metric | Feasibility | Definition/source |
|---|---|---|
| Total users | DB now | Count non-review `users`. This is accounts, not installs. |
| New users today / 7d | DB now | Accounts created during current ET day / trailing 7 ET calendar days including today. Label “signups,” not installs. |
| DAU replacement: box openers | DB now | Distinct non-review `actor_user_id` with `MYSTERY_BOX_OPENED` during current ET day. Label **Engaged box openers today**, never DAU. Historical coverage begins at the operator-confirmed durable-writer instant in §6.0, not the first observed row. |
| Observed foreground DAU / WAU | Forward-only, capability-scoped | Distinct capable users with an authenticated foreground fact during today / trailing 7 ET days. Background sync does not emit it. This permanently excludes frozen incapable clients and is never labeled population-wide “true DAU.” |
| Observed D1 / D7 / D30 retention | Forward-only, signup-capability cohort | New accounts stamped telemetry-capable at signup that return via a foreground fact on exact signup+N ET calendar day; mature cohorts only. Summary pools the latest 30 mature eligible signup-date cohorts for each N; drill-down returns each date. All-signup retention remains unavailable. |
| Users in a race | DB now | Distinct accepted non-review users in an `ACTIVE`, non-featured, non-tournament race now, excluding races created by review accounts. |
| Active races (non daily/weekly) | DB now | `ACTIVE` races with no seed and no tournament, excluding races created by review accounts. |
| Daily races | DB now | `ACTIVE` races joined to a `DAILY` seed. |
| Races created today (non daily/weekly) | DB now | Non-featured, non-tournament races created by non-review accounts with `created_at` in current ET day. |
| Revenue today | Provider | AdMob `ESTIMATED_EARNINGS` for latest available provider day. “Today” can lag/intraday and must show `asOf`. |
| Revenue / DAU | Provider + forward | Same estimated earnings divided by observed foreground DAU for the exact aligned day, with the population mismatch disclosed. Null if dates cannot be aligned. |

### 5.2 User growth

| Requested metric | Feasibility | Definition/source |
|---|---|---|
| Total users | DB now | Same canonical summary value; do not recompute differently. |
| New installs/day | Provider | Apple First Time Downloads. This is a store/account measure, not backend people. |
| New signups/day | DB now | New non-review accounts per ET day. |
| Observed foreground DAU / WAU / MAU | Forward-only | Distinct capable users with foreground facts over 1/7/30 ET days. Always show capable-account coverage; never imply users who stay on frozen clients are observed. |
| Uninstalls | Provider | Apple Deletions. This is opt-in/thresholded provider data, not a current-user census. |

### 5.3 Invite funnel and virality

Keep current link opens, attributed signups, joined-race, qualified/finished,
and rewarded stages, but add a selected window consistently to every stage.
Do not mix a 7-day top stage with lifetime lower stages.

| Requested metric | Feasibility | Definition/source |
|---|---|---|
| Invites 7d / DAU 7d | Not reliable as written | The current client `invite_flow_sent` is best-effort and a share-sheet completion is not a recipient count. Do not display an “invites sent” metric. A later experiment may add **share completions per WAU** with its limitation stated. |
| Users who join / invites sent | DB now with revised denominator | Display **Attributed signups / unique referral link opens**. Do not use sharing actions as a denominator. |
| Invite conversion | DB now | Attributed referral signups / unique referral landing-page opens for the same window. Unique opens use the bounded pseudonymous-dedupe rule below. |
| K-factor | Unavailable exactly today | Do not use the proposed division formula or label a proxy “K-factor.” Display **Attributed signups per WAU (7d)** once WAU matures. True invitations-per-user remains unknown. |
| Improve invite wording | Deferred experiment | This feature establishes measurement only. Copy variants, assignment, confidence rules, and copy changes require a separate spec. |

For `unique referral link opens`, partition referral `link_opens` by normalized
`code`, `ip_hash_version`, and non-null `ip_hash`, order by `created_at`, and count the first row
plus a new session after a gap greater than 24 hours. Rows with a null code are
excluded from conversion; rows with a null hash cannot be deduped and each count
as a unique open. The selected-window predicate applies to opens and attributed
signups alike. The existing unsalted SHA-derived IP hash is pseudonymous and is
not acceptable for new Phase A writes.

The v2 invite/virality blocks include only codes owned by an iOS user and only
attributed signup/downstream users satisfying the iOS-user predicate. A browser
open has no trustworthy device platform, so code ownership is the explicit iOS
boundary for the anonymous top stage; the UI definition discloses this.

Phase A adds nullable `link_opens.ip_hash_version` and
`link_opens.ip_net_hash_version`. It writes
`HMAC-SHA-256(secretForVersion, canonicalIpBytes)` for the exact-address hash
and `HMAC-SHA-256(secretForVersion, canonicalNetworkPrefixBytes)` for the
existing tier-two network-prefix fallback, both with the same integer active
version. No path writes raw IP, a new unsalted `ipHash`, or a new unsalted
`ipNetHash`. Secrets live only in backend secret storage. If the active
secret/version is absent or invalid, the landing request still succeeds but
stores both hashes and versions as null, the row counts as one
non-deduplicable open, and an operational error is logged without IP data.
For the first 48 hours after enabling the HMAC writer, referral attribution may
read both legacy-null-version and active-version hashes, partitioned separately
(cross-version identity is deliberately not inferred). After that deadline all
code paths stop reading both legacy exact-address and legacy network-prefix
hashes. Dashboard unique-open metrics read only active-version rows and show collecting/unavailable until the requested window
lies wholly after that version's `MetricCoverageStart`. Rotation repeats the
same 48-hour current+previous-version read, then drops previous reads. Rows
retain at most 90 days, hashes never leave the backend, and rotation does not
extend retention.

### 5.4 Onboarding and activation

The onboarding funnel and the new v2 dashboard contract are iOS-only. The
legacy stats response remains byte-compatible for frozen clients, but the new
v2 block contains no non-iOS series. The corrected funnel selects iOS sessions
whose `onboarding_started.occurred_at` falls in the selected 7- or 30-day start
cohort, excludes sessions started less than 24 hours ago, and counts each stage
only when it occurred from start through start+24h. Every row therefore comes
from one identical mature cohort. Spine stages show both previous-spine and
start conversion; side exits show start share only and never become sequential
denominators. A global 90-day dashboard selection still uses and labels a
30-day onboarding cohort because activation events retain for only 90 days.

| Requested metric | Feasibility | Definition/source |
|---|---|---|
| % connects health data | Forward-only/current partial | Existing iOS `health_result:granted` covers instrumented onboarding runs, not durable current authorization. For activation, use distinct signup-cohort users with a successful health connection event within 24h / mature signups in that cohort. It is forward-only and best-effort. |
| People in a race that day | DB now | Distinct users accepted into at least one non-featured race whose active interval `[started_at, completed_at)` overlaps the ET day; an active race uses the query `asOf` as its open end and a cancelled race is excluded. This is “race participants active that day,” not app-active users. |
| People who created a race that day | DB now | Distinct non-review `creator_id` for non-featured, non-tournament, non-review-created races created that ET day. |
| New races that day | DB now | Count those non-review-created races. A race created by a review account is excluded even if real users later join it. |
| % use a power in first race | DB now from event-history start | For each user, first non-featured, non-tournament, powerups-enabled race with at least two accepted users; numerator has a `POWERUP_USED` server event by that user in that race. Races before durable event coverage are excluded and coverage is labeled. |
| % join/create a race within 24h | DB now | Mature signup cohort whose first accepted or created non-featured race timestamp is within 24 elapsed hours of `users.created_at`. Return numerator/denominator. |
| Friends per user | DB now | Counts and percentages in buckets 0, 1, 2, 3–5, 6+, accepted friendships only, non-review population. |

### 5.5 Retention

| Requested metric | Feasibility | Definition/source |
|---|---|---|
| D1/D7/D30 “came back” | Forward-only | Exact-day observed return within the immutable signup-capable cohort, as in §5.1. Population-wide retention is unavailable. Do not retain the current friend/no-friend split in Summary. |
| Completed one race → another | DB now | Users whose first accepted non-featured race reaches `completed_at` and whose accepted participant row has non-null `finished_at` and null `forfeited_at`, followed by an accepted `joined_at` in a different eligible race strictly after that completion and within 7/30 elapsed days. Cohort date is the first race's `completed_at`; each denominator contains only cohorts mature for its horizon. Cancelled and review-created races are excluded. |

### 5.6 Race and engagement

| Requested metric | Feasibility | Definition/source |
|---|---|---|
| Races created/day | DB now | Non-featured, non-tournament races created per ET day. |
| Races started/day | DB now | Those races with `started_at` per ET day. |
| Race participants/day | DB now | Show both: **new participants** = distinct users with accepted `joined_at` that ET day; **participants in live races** = distinct accepted users whose non-featured race interval `[started_at, completed_at)` overlaps that day, using `asOf` for active races. Cancelled and review-created races are excluded. |
| Average runners/race | DB now | Mean accepted participants for races started in the window; include completed and active, exclude cancelled, invited and declined. |
| % public vs private | DB now | Non-featured races created in the window grouped by `is_public`; return counts and percentages. |
| Average races/observed active user | DB + forward | Active-overlap non-featured memberships held by observed foreground users / those observed users. Zero-race users remain in the denominator. Capability coverage is returned. |
| Average leaderboard views/capable racer | Forward-only | View events / distinct accepted racers whose telemetry eligibility predates the full window. Retry dedupe uses event id; later intentional views remain countable. API polling is not a view. |
| Power-ups used/day | DB now | Count server `POWERUP_USED` events by event creation ET day. Document that some special/legacy paths that intentionally write other event types are excluded. |
| Power-ups used/race | DB now | `POWERUP_USED` count / non-cancelled, powerups-enabled races started in the selected cohort. Return numerator, denominator, and average; null average for zero races. |
| Coins earned/day | DB now only as a broader ledger measure | Display **Gross coin credits/day**: sum positive `coin_transactions.amount` for retained non-review accounts. It includes issuance, redistribution, refunds, and admin/manual adjustments, so never label it “earned” or “minted.” |
| Coins spent/day | DB now only as a broader ledger measure | Display **Gross coin debits/day**: absolute sum negative ledger amounts for retained non-review accounts. It includes consumption and escrow holds, so never label it “spent” or “sunk.” |
| Coin balance distribution | DB now | Current balance across non-review accounts: population count, total, mean, median, and p90, with snapshot time. Median is mandatory; mean alone is misleading. |
| Daily reward claims | DB now | Count and distinct claimers from retained accounts' `daily_reward_claims.created_at` per ET day. Extra ad-funded spins are separate. Historical values may fall after account deletion. |
| Ranked participation | DB now | Distinct non-review users with a `ranked_cohort_members` row for a `ranked_weeks` window overlapping the selected window. This is assignment/participation in Ranked v2, not proof the user opened the Ranked screen. Legacy `season_scores` are excluded so one person is not double-counted across the old and current systems. |
| Daily/weekly participation | DB now | For each `DAILY|WEEKLY` cadence return (a) distinct accepted users and accepted memberships whose non-cancelled race interval overlaps the selected window and (b) distinct accepted users and accepted memberships whose `joined_at` is in the selected window. Review accounts and review-created races are excluded. |
| Notification → app-open rate | Forward-only | Provider-accepted visible APNs sends with durable notification id joined to a new authenticated notification-open receipt. Return distinct opened sends / provider-accepted user sends over 7d by notification type. This is push-open rate, not proof the process was previously closed and not device-delivery rate. |

### 5.7 Revenue

| Requested metric | Feasibility | Definition/source |
|---|---|---|
| Ad impressions/day | Provider | AdMob `IMPRESSIONS`, grouped by date/ad unit/format as available. |
| Rewarded ads watched/day | DB now, signed callback | Count retained-account `ad_reward_grants` by callback date and reward kind; return total grants, unique watchers, and per-kind counts/watchers. SSV proves a signed rewarded interaction, but current code does not enforce an ad-unit-to-reward-kind mapping for every kind, so do not claim the recorded kind is independently authenticated. |
| Ads watched / observed foreground DAU | DB + forward | Signed-callback grants / aligned observed foreground DAU. Return total grants and unique watchers; disclose the capability-scoped denominator. |
| Ad completion % | Deferred approximate Phase B metric | Call it **SSV grants per rewarded impression**, never completion rate. Match provider timezone/date, rewarded ad unit, and rewarded format. Callback arrival is not impression time; delayed callbacks can make a daily ratio exceed 100%. Phase A returns no denominator or percent. |
| Ad revenue/day | Provider | AdMob estimated earnings, integer micros + currency, with `asOf`. |
| Ad revenue / DAU | Provider + forward | Estimated earnings / aligned observed foreground DAU, with the provider/non-review population mismatch disclosed. |
| eCPM by ad network | Provider | AdMob mediation `OBSERVED_ECPM`, grouped by ad source; null when the network/provider does not report it. |
| Fill rate | Provider | AdMob `MATCH_RATE` (matched requests / requests). Label it **Match rate**; optionally show `SHOW_RATE` separately. |
| Purchases/day | Unavailable as revenue | No real-money purchases exist. Existing coin-shop purchases remain an economy metric and must be labeled **coin purchases**, not revenue. |
| Paying users/day / % pay | Unavailable | No real-money purchase system. Hide until one ships. |
| ARPU / ARPPU | ARPU aggregate only; ARPPU unavailable | Aggregate ad revenue / active users can be shown as ad ARPDAU. There are no paying users, so ARPPU is undefined. |
| LTV | Unavailable exactly | AdMob provides aggregate revenue, not per-user revenue attribution. Do not show a fabricated per-user LTV. A modeled cohort LTV would be a separate forecasting feature with assumptions. |
| Daily revenue / DAU | Same as ad revenue/DAU | Do not duplicate it under two labels. |

### 5.8 App versions

App version adoption is actionable during phased rollout, incident response,
and compatibility debugging even though it is not a growth metric. Move the
existing 30-day active version table out of `GROWTH` into collapsed
`DEBUG → RELEASE ADOPTION`. Serve it through the lazy
`dashboard-release-adoption` block, reusing the canonical existing 30-day
version query with `is_review_account=false`, grouped only by version, rather
than fetching the full legacy payload. Authentication provider must not be used
as a platform filter. Do not delete its
legacy API fields. It should
remain explicitly labeled “accounts seen by backend in last 30d,” not install
base. This placement is decided.

## 6. Instrumentation and data model

### 6.0 Capability and cohort eligibility

Add `admin_metrics_v2` to **both** existing feature-list composition branches
of `BackendApiService.clientFeaturesHeader`, guarded so it is emitted only by
the iOS runtime. Eligibility is scoped to one
uninterrupted collection epoch; a missing header is not a downgrade inside an
epoch, but disabling collection ends that epoch.

Additive fields:

```prisma
// User
metricsV2EligibleAt       DateTime? @map("metrics_v2_eligible_at")
metricsV2EligibleEpochId  String?   @map("metrics_v2_eligible_epoch_id")
metricsV2SignupEligible   Boolean   @default(false) @map("metrics_v2_signup_eligible")
metricsV2SignupEpochId    String?   @map("metrics_v2_signup_epoch_id")

// DeviceToken
adminMetricsOpenCapable Boolean @default(false) @map("admin_metrics_open_capable")
adminMetricsOpenEpochId String? @map("admin_metrics_open_epoch_id")

model AdminMetricsCollectionEpoch {
  id        String    @id @default(uuid())
  startedAt DateTime  @map("started_at")
  endedAt   DateTime? @map("ended_at")
  @@index([startedAt, endedAt])
  @@map("admin_metrics_collection_epochs")
}

model MetricCoverageStart {
  metric          String   @id
  operationalAt  DateTime @map("operational_at")
  confirmedAt    DateTime @default(now()) @map("confirmed_at")
  @@map("metric_coverage_starts")
}
```

- Enabling `adminMetricsV2TelemetryEnabled` transactionally creates a new open
  epoch; disabling it stamps that epoch's `endedAt`. Re-enabling creates a new
  id. There is never more than one open epoch. Queries return a forward-only
  metric only when its entire measurement window lies inside the current open
  epoch; gaps are never bridged.
- During an open epoch, the first authenticated capable request sets/refreshes
  `metricsV2EligibleAt` and `metricsV2EligibleEpochId` to that epoch. Existing
  capable iOS users must reassert capability after a new epoch begins; an
  ineligible account or old epoch stamp never enters the current capable
  denominator.
- `metricsV2SignupEligible=true` and `metricsV2SignupEpochId=currentEpoch.id`
  are written only in the new-account transaction when collection is enabled
  and the creating iOS request carries the capability, regardless of whether
  the account uses Apple or Google Sign-In. The signup flag/epoch is
  immutable. D1/D7/D30 and health-within-24h denominators require the current
  epoch id. An older signup or a signup during a disabled gap never enters
  retroactively.
- Device-token registration during an open epoch from a capable client sets
  `adminMetricsOpenCapable=true` and the current
  `adminMetricsOpenEpochId` only when `DeviceToken.platform='ios'` and its user
  satisfies the iOS-user predicate. Notification-open denominators require
  that epoch id and a capable iOS-token provider acceptance; all other or old
  epoch/token stamps do not qualify.
- Every forward-only response path has a `metricCoverage` entry containing
  `status`, `collectingSince`, `eligible`, `totalPopulation`, and
  `eligibilityPercent`. Use separate keys for `observedForegroundDau`,
  `observedForegroundWau`, `observedForegroundMau`, `retentionD1`,
  `retentionD7`, `retentionD30`, `healthWithin24h`, `leaderboardViews`,
  `notificationOpen`, `boxOpen`, and `firstRacePowerUse`; do not use one status
  for multiple maturity horizons. For capable-account metrics, `eligible` is
  iOS users stamped in the current epoch before the full metric window and
  `totalPopulation` is all retained iOS users. For signup metrics, they are
  current-epoch capable iOS signups and all iOS signups in
  the same mature signup-date cohorts. For notifications, they are non-review
  iOS accounts with a current-epoch capable APNs token and all retained iOS
  accounts. For DB event-coverage metrics, `eligible` is qualifying iOS cohorts
  after `operationalAt` and `totalPopulation` is the same cohort without the
  coverage cutoff. Status is `collecting|mature|unavailable`; a mature subwindow
  may return data while a longer horizon remains collecting. Coverage never
  claims frozen clients eventually become observable.
- Box-open and first-race-power coverage begins at an operator-confirmed
  Postgres `metric_coverage_starts` row written during rollout, not `MIN(event
  timestamp)`. The configured instant is the point after which all production
  writers were verified durable. Missing coverage configuration makes the
  affected metric unavailable; it never guesses a start from sparse data.

### 6.1 Foreground activity fact

Add a purpose-built authenticated activity ingestion path. Do not infer
foreground use from steps, generic authenticated requests, `last_seen_at`, or
`home_reached`.

Preferred durable model:

```prisma
model UserActivityDay {
  userId        String   @map("user_id")
  activityDate DateTime @db.Date @map("activity_date")
  firstSeenAt  DateTime @map("first_seen_at")
  lastSeenAt   DateTime @map("last_seen_at")
  appVersion   String   @map("app_version")
  source       String   @default("foreground")
  metadataOccurredAt DateTime @map("metadata_occurred_at")

  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@id([userId, activityDate])
  @@index([activityDate])
  @@map("user_activity_days")
}
```

The app emits at most once per foreground session after authentication. A
session is an authenticated cold start or a transition to `resumed` after at
least 30 continuous seconds outside resumed state; duplicate lifecycle
callbacks inside that interval coalesce. If authentication completes while the
app is already foregrounded, emit once then. The
server derives `userId`; validates app version and the client event time
with the same bounded approach as activation telemetry; converts `occurredAt`
to ET; and upserts the daily row. Event time is needed so a session queued while
offline is attributed to the day it happened rather than the later flush day.
It remains client telemetry: reject future times and events more than 35 days
old, and label the dashboard source `foreground_telemetry`. This is the
best available definition of intentional use, not a security authority. The
migration performs no historical backfill. `(userId, activityDate)` is the
durable idempotency boundary; `sessionId` is validation/diagnostic input only
and is not stored. Upsert sets `firstSeenAt=LEAST(existing, occurredAt)`,
`lastSeenAt=GREATEST(existing, occurredAt)`, and replaces appVersion/
`metadataOccurredAt` only when the incoming occurrence is later, so offline or
reordered retries cannot regress metadata.

Rows retain for 180 days and cascade on account deletion. That covers the
largest 90-day chart plus D30 maturity without creating indefinite per-user
foreground history. Cleanup is idempotent and never affects app behavior.

The accepted decision is one ET operator day. Store `activityDate` in ET; do
not create a second user-local date axis. The received IANA timezone remains
request metadata for other product behavior and is not a dashboard dimension.

### 6.2 Product interaction events

Add allowlisted, forward-only events with bounded context:

- `race_leaderboard_viewed`: required context exactly
  `{"race_id":"<UUID>"}`; one event each time the leaderboard
  surface becomes visible. Event idempotency prevents retry duplicates, but a
  second intentional view in the same session remains a second view.
- `health_connected`: required context exactly
  `{"source":"healthkit"}` and no health payload. This
  complements rather than repurposes existing onboarding events.
- `notification_opened`: prefer an authoritative dedicated endpoint carrying
  opaque server notification id; do not place arbitrary notification data into
  generic analytics context.
- No invite experiment exposure/share event is added in Phase A; that work is
  explicitly deferred.

Add both names and their exact context validators to the client and server
activation-event allowlists. Existing/unknown event names continue to
soft-drop as they do today; they must not fail a user workflow. The common
event id remains the retry-idempotency key. When
`adminMetricsV2TelemetryEnabled=false` or no collection epoch is open, the
existing activation endpoint soft-drops only `health_connected` and
`race_leaderboard_viewed`; every legacy activation-event name retains its
current behavior. When enabled, those two new names are accepted only when the
authenticated user satisfies the iOS predicate and the existing event envelope
has `platform='ios'`; otherwise those names soft-drop without affecting legacy
event validation or writes.

For durable “power used in first race,” “race created,” race starts, and coin
flows, use server transaction rows instead of duplicating client events.

### 6.3 Provider ingestion constraints (deferred Phase B, not Phase A scope)

Do not call App Store Connect/AdMob synchronously from `GET /admin/stats`; provider
latency or auth failure must not stall the app or the one-vCPU API server.

This is feasibility guidance only. Phase B must receive a separate approved
schema/job/API spec after credentials and report scopes are confirmed. That
spec will need a Postgres daily aggregate cache with a backend-built canonical
dimension key, idempotent imports, bounded retry, mutable-day re-import, and
credentials held only in backend secret storage. Phase A must not create that
schema or jobs.

Provider values preserve provenance and limitations:

- `provider`, report name, source timezone, report date, imported time,
  opt-in/threshold note, and stale state.
- AdMob money stays in micros and source currency; no float dollars in storage.
- AdMob rows retain publisher reporting timezone, rewarded ad unit,
  format, and date dimensions. A future comparison to SSV must use those exact
  dimensions. Phase B should persist the signed SSV event timestamp separately
  from callback `created_at`; until then, callback-day ratios are explicitly
  approximate and may exceed 100%.
- Provider aggregates cannot exclude review accounts. Revenue/DAU must expose
  this population mismatch rather than implying identical populations.

Aggregated provider rows contain no user ids and retain for 400 days. Raw
downloaded report files are processed from temporary storage and removed after
each import attempt; they are never committed or placed in app storage.

### 6.4 Notification attribution

Do not alter or repurpose the existing `notifications` table: it is also cron
dedupe storage and has seven-day cleanup semantics. Add one separate fact per
logical visible iOS user-send:

```prisma
model PushDelivery {
  id                 String    @id @default(uuid())
  publicId           String    @unique @map("public_id")
  deliveryKey        String    @unique @map("delivery_key")
  userId             String    @map("user_id")
  notificationType   String    @map("notification_type")
  openCapable        Boolean   @map("open_capable")
  createdAt          DateTime  @default(now()) @map("created_at")
  providerAcceptedAt DateTime? @map("provider_accepted_at")
  openedAt           DateTime? @map("opened_at")

  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@index([providerAcceptedAt, notificationType])
  @@index([userId, createdAt])
  @@map("push_deliveries")
}
```

For v2 attribution, create facts only for iOS users and APNs tokens satisfying
the predicates above. Before every attempt, upsert by a backend-built deterministic `deliveryKey`
formed from the durable source kind/id and user id; bounded direct
or special sends without a natural source id first persist one. Every retry or
post-crash resume reuses the same row and `publicId`, which is placed in each
visible payload. Target-token results are tracked in memory for that attempt:
`openCapable=true` and `providerAcceptedAt` are stamped only when at least one
token carrying the current epoch's `adminMetricsOpenEpochId` succeeds. Success
to only incapable/stale-epoch tokens does not qualify. Instrument all visible
send paths: direct sends, Inbox outbox delivery, and special-purpose sends.
Inbox-only records and data/silent pushes do not create a denominator fact. A
denominator fact therefore requires `openCapable=true AND providerAcceptedAt
IS NOT NULL`; the seven-day metric windows by `providerAcceptedAt`, not row
creation, and measures provider acceptance rather than device delivery.

On tap, navigation proceeds immediately. The app queues a cold-start receipt
until authentication is available, then POSTs the public id best-effort. The
backend stamps `openedAt` idempotently only for the owning user. A missing id
from an old push or an unknown/expired id is harmless and returns
`attributed:false`; do not expose internal user ids in payloads. Rows retain
for 30 days and cascade on account deletion; the displayed rate is trailing
7 days and returns total accepted sends, distinct opened sends, and
per-notification-type conversion breakdowns.

## 7. API contract

### 7.1 Compatibility strategy

Keep `GET /admin/stats` with no `sections` byte-compatible for every shipped
admin client. Add these opt-in section names; unknown names already
soft-degrade on older backends:

- `dashboard-summary`
- `dashboard-growth`
- `dashboard-funnels`
- `dashboard-activation`
- `dashboard-retention`
- `dashboard-engagement`
- `dashboard-virality`
- `dashboard-revenue`
- `dashboard-release-adoption`

Each name computes only its own block plus the shared `window`, `coverage`,
`sources`, and `schemaVersion` metadata. This preserves the current lazy-query
design instead of running the full dashboard when the user only reads Summary.

Request modes are mutually exclusive and observable in integration tests:

1. No `sections`: execute the exact current legacy queries and return the exact
   current legacy payload.
2. Only recognized legacy optional sections (`economy`, `ads`,
   `extra-spin-funnel`), with or without unknown names: retain exact current
   behavior and payload.
3. Exactly one recognized `dashboard-*` section, with no recognized legacy
   optional section: execute no legacy statistic queries and return only
   `stats.generatedAt` plus `stats.metricsDashboard` metadata and the requested
   v2 blocks. Unknown names alongside v2 names are ignored.
4. Any request mixing a recognized legacy optional section and recognized
   `dashboard-*` section returns `400
   {"error":"Legacy and dashboard sections cannot be mixed","code":"MIXED_STATS_SECTIONS"}`
   before metric queries run.
5. More than one recognized `dashboard-*` section returns `400
   {"error":"Request one dashboard section at a time","code":"MULTIPLE_DASHBOARD_SECTIONS"}`
   before metric queries run. This is a one-vCPU load boundary, not a client
   batching API.

`window` is parsed and validated only in mode 3. Thus an unknown-only request
keeps today's soft-degradation behavior even if it carries an unfamiliar
`window`; it must not become a new error for older/frozen clients.

Request:

```http
GET /admin/stats?sections=dashboard-summary&window=30d
Authorization: Bearer <identity token>
```

- `window`: `7d|30d|90d`, default `30d`; invalid value in mode 3 → `400
  {"error":"Window must be 7d, 30d, or 90d","code":"INVALID_WINDOW"}`.
- Old backends ignore `dashboard-summary` and return the legacy `stats` object
  without `metricsDashboard`.
- New backends return `stats.metricsDashboard` only in dashboard mode. They do
  not remove or restate legacy keys in legacy modes used by frozen clients.
- Admin authorization behavior remains `403` for non-admin and `401` for
  invalid/missing authentication.

Exact union envelope (representative documentation union showing all nine
optional blocks; a real request may contain only one block, and every key shown
is stable):

```json
{
  "stats": {
    "generatedAt": "2026-08-18T15:04:05.000Z",
    "metricsDashboard": {
      "schemaVersion": 2,
      "status": "available",
      "window": {"days": 30, "start": "2026-07-20", "end": "2026-08-18", "timeZone": "America/New_York"},
      "coverage": {
        "foregroundActivitySince": "2026-08-08",
        "boxOpenOperationalSince": "2026-08-01T00:00:00.000Z",
        "metricCoverage": {
          "observedForegroundDau": {"status": "mature", "collectingSince": "2026-08-08", "eligible": 702, "totalPopulation": 1234, "eligibilityPercent": 56.9},
          "observedForegroundWau": {"status": "mature", "collectingSince": "2026-08-08", "eligible": 702, "totalPopulation": 1234, "eligibilityPercent": 56.9},
          "observedForegroundMau": {"status": "collecting", "collectingSince": "2026-08-08", "eligible": 702, "totalPopulation": 1234, "eligibilityPercent": 56.9},
          "retentionD1": {"status": "mature", "collectingSince": "2026-08-08", "eligible": 40, "totalPopulation": 61, "eligibilityPercent": 65.6},
          "retentionD7": {"status": "mature", "collectingSince": "2026-08-08", "eligible": 38, "totalPopulation": 57, "eligibilityPercent": 66.7},
          "retentionD30": {"status": "collecting", "collectingSince": "2026-08-08", "eligible": 0, "totalPopulation": 0, "eligibilityPercent": null},
          "healthWithin24h": {"status": "mature", "collectingSince": "2026-08-08", "eligible": 40, "totalPopulation": 61, "eligibilityPercent": 65.6},
          "leaderboardViews": {"status": "mature", "collectingSince": "2026-08-08", "eligible": 74, "totalPopulation": 112, "eligibilityPercent": 66.1},
          "notificationOpen": {"status": "mature", "collectingSince": "2026-08-08", "eligible": 612, "totalPopulation": 1234, "eligibilityPercent": 49.6},
          "boxOpen": {"status": "mature", "collectingSince": "2026-08-01", "eligible": null, "totalPopulation": null, "eligibilityPercent": null},
          "firstRacePowerUse": {"status": "mature", "collectingSince": "2026-08-01", "eligible": 28, "totalPopulation": 31, "eligibilityPercent": 90.3}
        },
        "providerThrough": {"appStoreConnect": null, "admob": null}
      },
      "summary": {
        "growth": {
          "totalSignups": 1234,
          "signupsToday": 9,
          "signupsLast7Days": 61,
          "engagedBoxOpenersToday": 117,
          "observedForegroundDau": 112,
          "observedForegroundWau": 310
        },
        "retention": {
          "d1": {"numerator": 18, "denominator": 40, "percent": 45.0},
          "d7": {"numerator": 10, "denominator": 38, "percent": 26.3},
          "d30": {"numerator": null, "denominator": null, "percent": null}
        },
        "races": {
          "usersInActiveNonFeaturedRaces": 88,
          "activeNonFeaturedRaces": 21,
          "activeDailyRaces": 4,
          "nonFeaturedRacesCreatedToday": 7
        }
      },
      "userGrowth": {
        "daily": [{"date": "2026-08-17", "signups": 8, "observedForegroundUsers": 112, "appleFirstTimeDownloads": null, "appleDeletions": null}],
        "observedForegroundWau": 310,
        "observedForegroundMau": null
      },
      "inviteFunnel": {
        "linkOpens": 200,
        "uniqueLinkOpens": 151,
        "attributedSignups": 32,
        "joinedRace": 21,
        "qualified": 14,
        "rewarded": 13,
        "openToSignup": {"numerator": 32, "denominator": 151, "percent": 21.2},
        "signupToJoinedRace": {"numerator": 21, "denominator": 32, "percent": 65.6},
        "joinedRaceToQualified": {"numerator": 14, "denominator": 21, "percent": 66.7},
        "qualifiedToRewarded": {"numerator": 13, "denominator": 14, "percent": 92.9}
      },
      "onboardingFunnel": {
        "cohortWindowDays": 30,
        "stages": [{"key": "onboarding_started", "count": 80, "previousSpineConversion": {"numerator": null, "denominator": null, "percent": null}, "startConversion": {"numerator": 80, "denominator": 80, "percent": 100.0}}]
      },
      "activation": {
        "daily": [{"date": "2026-08-17", "liveRaceParticipants": 44, "raceCreators": 6, "racesCreated": 7}],
        "healthWithin24h": {"numerator": 21, "denominator": 40, "percent": 52.5},
        "raceWithin24h": {"numerator": 18, "denominator": 40, "percent": 45.0},
        "firstRacePowerUse": {"numerator": 11, "denominator": 28, "percent": 39.3},
        "friends": [{"bucket": "0", "ratio": {"numerator": 520, "denominator": 1234, "percent": 42.1}}]
      },
      "retention": {
        "d1": {"numerator": 18, "denominator": 40, "percent": 45.0},
        "d7": {"numerator": 10, "denominator": 38, "percent": 26.3},
        "d30": {"numerator": null, "denominator": null, "percent": null},
        "cohorts": [{"signupDate": "2026-08-10", "eligibleSignups": 9, "d1": {"numerator": 4, "denominator": 9, "percent": 44.4}, "d7": {"numerator": 2, "denominator": 9, "percent": 22.2}, "d30": {"numerator": null, "denominator": null, "percent": null}}],
        "secondRaceWithin7d": {"numerator": 17, "denominator": 31, "percent": 54.8},
        "secondRaceWithin30d": {"numerator": 22, "denominator": 31, "percent": 71.0}
      },
      "raceEngagement": {
        "daily": [{"date": "2026-08-17", "racesCreated": 7, "racesStarted": 5, "newParticipants": 29, "liveRaceParticipants": 44, "powerupsUsed": 61, "grossCoinCredits": 25000, "grossCoinDebits": 17000, "dailyRewardClaims": 93, "distinctDailyRewardClaimers": 76}],
        "averageRunnersPerStartedRace": 4.2,
        "visibility": {"public": {"numerator": 12, "denominator": 31, "percent": 38.7}, "private": {"numerator": 19, "denominator": 31, "percent": 61.3}},
        "racesPerObservedActiveUser": {"numerator": 146, "denominator": 112, "average": 1.3},
        "leaderboardViewsPerCapableRacer": {"numerator": 181, "denominator": 74, "average": 2.4},
        "powerupsPerRace": {"numerator": 61, "denominator": 18, "average": 3.4},
        "coinBalance": {"populationCount": 722, "total": 208640, "average": 289.0, "median": 127.5, "p90": 672.8, "asOf": "2026-08-18T15:04:05.000Z"},
        "featuredParticipation": {"daily": {"activeOverlapUsers": 210, "activeOverlapMemberships": 294, "joinedWindowUsers": 98, "joinedWindowMemberships": 121}, "weekly": {"activeOverlapUsers": 155, "activeOverlapMemberships": 168, "joinedWindowUsers": 67, "joinedWindowMemberships": 72}},
        "rankedParticipationUsers": 74,
        "notificationOpenRate": {"windowDays": 7, "numerator": 23, "denominator": 140, "percent": 16.4, "breakdown": [{"notificationType": "race_started", "ratio": {"numerator": 14, "denominator": 70, "percent": 20.0}}]}
      },
      "virality": {
        "shareCompletions": null,
        "sharingUsers": null,
        "attributedSignups": 32,
        "attributedSignupsPerWau": null,
        "linkOpenToSignup": {"numerator": 32, "denominator": 151, "percent": 21.2}
      },
      "revenue": {
        "daily": [{"date": "2026-08-17", "impressions": null, "ssvGrants": 423, "uniqueSsvWatchers": 116, "ssvByRewardKind": [{"rewardKind": "coin_reward", "grants": 102, "uniqueWatchers": 29}, {"rewardKind": "extra_daily_spin", "grants": 124, "uniqueWatchers": 47}, {"rewardKind": "box_reroll", "grants": 171, "uniqueWatchers": 58}, {"rewardKind": "race_payout_double", "grants": 21, "uniqueWatchers": 16}, {"rewardKind": "powerup_unlock", "grants": 5, "uniqueWatchers": 4}], "estimatedEarnings": null, "matchRate": null, "showRate": null}],
        "adRevenuePerDau": null,
        "ssvGrantsPerRewardedImpression": {"numerator": 423, "denominator": null, "percent": null},
        "byNetwork": [],
        "realMoneyPurchases": {"available": false, "reason": "NO_IAP_PRODUCT"}
      },
      "releaseAdoption": {
        "windowDays": 30,
        "versions": [{"version": "2.4.0", "accountsSeen": 412}]
      },
      "sources": {
        "productDb": {"status": "available", "asOf": "2026-08-18T15:04:05.000Z"},
        "foregroundActivity": {"status": "collecting", "asOf": "2026-08-18T15:04:05.000Z"},
        "appStoreConnect": {"status": "not_configured", "asOf": null},
        "admob": {"status": "not_configured", "asOf": null}
      }
    }
  }
}
```

Only the requested block is present; unknown names alongside it are ignored.
The frontend checks every block
and leaf defensively; missing/null renders unavailable, not zero. Unknown
enum/source statuses render as unavailable with the raw label omitted.

#### 7.1.1 Normative wire rules

- The union example above is the Phase A field allowlist. A requested Phase A
  block includes every shown Phase A key. Provider leaves shown in User growth
  and Revenue are nullable; `summary.money` is not a Phase A key. Unrequested
  blocks are omitted. Missing additive keys from an older server are accepted
  by the client and render unavailable.
- `metricsDashboard.status` is `available|disabled`. Source status is
  `available|collecting|disabled|not_configured|stale|error`; the client treats
  any unknown value as unavailable. `asOf` is required only when a source has
  available/stale data.
- Scalars sourced from an available DB query are non-null and use `0` for a
  valid empty result. Forward/provider scalars are null while their coverage
  key for that exact horizon is `collecting|unavailable` or source is
  `not_configured`; one mature horizon may be numeric while a longer horizon is
  collecting. A product ratio object is always
  `{numerator,denominator,percent}`; its counts are null only when the source or
  horizon is unavailable, and `percent` is null whenever either count is null
  or the denominator is zero. Coverage's diagnostic `eligibilityPercent` and
  future provider-native rates are explicitly nullable scalar exceptions.
  Averages always return `{numerator,denominator,average}`, with null average
  for a null or zero denominator.
- Every `daily` and retention `cohorts` array is ordered oldest to newest.
  Daily arrays include every ET date in the requested inclusive calendar
  window; DB counts zero-fill missing dates, while unavailable forward/provider
  leaves remain null. `friends` always returns buckets in the fixed order
  `0,1,2,3-5,6+`, including zero-count buckets. SSV reward kinds use the fixed
  order `coin_reward,extra_daily_spin,box_reroll,race_payout_double,powerup_unlock`.
- Counts and coin amounts are JSON integers. Currency values are integer micros.
  Percentages, averages, median, and p90 are decimal numbers rounded once to
  one decimal using half-up rounding after aggregation. Dates are `YYYY-MM-DD`;
  instants are UTC ISO-8601 strings.
- Summary D1/D7/D30 pool numerator and denominator across the latest 30 mature
  immutable eligible signup-date cohorts for that horizon. The retention
  `cohorts` array emits each ET signup date in the requested range; an immature
  horizon has all three ratio leaves null rather than a partial denominator.
- Invite counts use normalized-code attribution. `linkOpens` and
  `uniqueLinkOpens` are open events/sessions occurring in the selected window.
  `attributedSignups` is non-review users whose `users.created_at` is in that
  same window and whose signup retained the code. `joinedRace`, `qualified`,
  and `rewarded` are nested subsets of those signup users that reached the
  existing canonical referral stage by `generatedAt`; their stage timestamps
  are returned only from durable server facts. Conversion triples use the
  immediately preceding displayed count, except `openToSignup`, which uses
  unique opens. This is a signup-cohort funnel, not a recipient-level invite
  funnel.
- `activation.daily` uses each ET date in the requested window. Race
  participant, creator, and created-race populations are exactly §5.4.
  `healthWithin24h` and `raceWithin24h` use mature immutable capable signups
  created in the selected window. `firstRacePowerUse` returns the exact
  numerator/denominator in §5.4 and never infers the denominator from races
  before the operational event-coverage instant.
- `raceEngagement.daily` contains both participant views and both daily-reward
  totals. `powerupsPerRace` is the required numerator/denominator/average
  object; races-per-observed-active-user and leaderboard-views-per-capable-racer
  use the same average-object shape. Featured participation always includes users and memberships for
  both active-overlap and joined-window views. Notification rate always
  includes totals and notification-type breakdown; it is null only until the
  capable delivery source exists.
- Phase B, if separately approved, may populate Apple first-time-download/
  deletion and AdMob leaves. No other store/provider is part of this feature.

### 7.2 Foreground ingestion

```http
POST /analytics/foreground
Authorization: Bearer <identity token>
X-Timezone: America/New_York
Content-Type: application/json

{"sessionId":"01J...","occurredAt":"2026-08-18T14:58:00.000Z","appVersion":"2.4.0"}
```

- `sessionId`: client-generated opaque ULID/UUID, max 64 safe characters,
  validation/diagnostic input only; daily idempotency is `(userId,
  activityDate)` and the value is never stored or returned in admin stats.
- `occurredAt`: UTC ISO-8601 instant, no more than five minutes in the future
  and no more than 35 days old.
- `appVersion` uses the existing activation telemetry validator.
- `202 {"recorded":true}` on a valid request; idempotent repeat returns the same.
- While telemetry is disabled/no epoch is open, a valid request returns
  `202 {"recorded":false,"reason":"disabled"}` with no activity write.
- A request from an authenticated account outside the iOS population returns
  `202 {"recorded":false,"reason":"unsupported_platform"}` with no capability
  or activity write.
- Invalid bounded fields → `400
  {"error":"Invalid foreground analytics event","code":"INVALID_ANALYTICS_EVENT"}`.
- Old app versions never call it and are unaffected. A new app against an old
  backend treats 404/405 as best-effort loss and continues normally.

### 7.3 Notification open receipt

```http
POST /analytics/notification-open
Authorization: Bearer <identity token>
Content-Type: application/json

{"notificationId":"01J..."}
```

Responses:

- `202 {"attributed":true}` when id belongs to caller and is newly or already
  opened.
- `202 {"attributed":false}` for unknown, expired, or other-user id (no oracle).
- While telemetry is disabled/no epoch is open, a valid request returns
  `202 {"attributed":false,"reason":"disabled"}` with no attribution write.
- `400 {"error":"Invalid notification id","code":"INVALID_NOTIFICATION_ID"}`
  for malformed input.
- Navigation never waits for this request.

## 8. Backend implementation path

1. Implement the resolved product definitions in §12 without reinterpretation.
2. Preserve the no-section legacy query and payload exactly.
3. Add one reviewed additive migration covering all Phase A storage:
   `User.metricsV2EligibleAt`, `metricsV2EligibleEpochId`,
   `metricsV2SignupEligible`, `metricsV2SignupEpochId`;
   `DeviceToken.adminMetricsOpenCapable`, `adminMetricsOpenEpochId`;
   `user_activity_days`, `admin_metrics_collection_epochs`,
   `metric_coverage_starts`, `push_deliveries`,
   `analytics_cleanup_runs`; and nullable `link_opens.ip_hash_version` plus
   `link_opens.ip_net_hash_version`, with the
   relations/uniques/indexes in §§6 and 8.1. No destructive changes or telemetry
   backfill. Do not add the deferred provider cache in Phase A. Explicitly
   allowlist the public authenticated-user response in
   `serializeAuthenticatedUser`; none of the server-only eligibility, epoch,
   or capability fields may serialize to clients.
4. Add authenticated foreground and notification-open ingestion with bounded
   validation and idempotency.
5. Add server-side query modules per dashboard block. Keep heavy/provider
   blocks opt-in and bounded; run `EXPLAIN (ANALYZE, BUFFERS)` on production-like
   row counts and add indexes only where justified.
6. Return explicit `not_configured` source status and null provider leaves in
   Phase A; no external credentials or network calls.
7. Extend `getAdminStats({sections, window})` with the nine lazy dashboard
   section names in §7.1; unknown sections remain ignored. Share canonical
   query helpers between Summary and drill-down blocks. Return explicit
   coverage/source statuses.
8. Deploy backend migrations and endpoint before the app.

Dashboard-mode integration tests capture Prisma query events and enforce these
per-request statement ceilings, including shared metadata: Summary 12; Growth
6; Funnels 10; Activation 10; Retention 8; Engagement 16; Virality 6; Revenue
8; Release Adoption 3. The API rejects multi-dashboard-section requests, and
the app permits only one in-flight dashboard request, so these are also the
concurrency ceiling. Legacy-mode query count must remain at its pre-change baseline, and
dashboard mode must execute zero legacy-stat statements. On production-like
data, record `EXPLAIN (ANALYZE, BUFFERS)` and require Summary p95 backend handler
time under 750 ms and each lazy block under 1.5 s on the production one-vCPU
class before enabling the dashboard flag; exceeding a budget blocks rollout
rather than silently making the endpoint eager.

### 8.1 Rollout controls, cleanup, and storage authority

Declare `adminMetricsV2DashboardEnabled` and
`adminMetricsV2TelemetryEnabled` in `KNOWN_FLAGS`, both default `false`, using
the existing settings cache/invalidation path. Do not create a new Redis key or
make Redis authoritative for eligibility, telemetry, delivery facts, cleanup,
or dashboard values; Postgres is the source of truth and the feature must work
when Redis is unavailable.

- Dashboard flag off: a recognized dashboard-mode request returns `200` with
  only `stats.generatedAt` and
  `stats.metricsDashboard:{schemaVersion:2,status:"disabled",window,
  sources:{productDb:{status:"available",asOf:<generatedAt>},
  foregroundActivity:{status:"disabled",asOf:null},
  appStoreConnect:{status:"not_configured",asOf:null},
  admob:{status:"not_configured",asOf:null}}}`; no `coverage` or metric block is
  present and it runs no metric query. The app shows “Dashboard temporarily disabled”
  while leaving Config, Inbox, and Debug reachable.
- Telemetry flag off: the two dedicated endpoints return their exact disabled
  envelopes in §§7.2–7.3 without writes. The existing activation endpoint
  soft-drops only the two v2 names with its unchanged success envelope; legacy
  events continue writing. No eligibility/capability epoch stamp is made while
  disabled. Gameplay/navigation never changes.
- Runtime rollback flips either flag false. Environment kill switch
  `ADMIN_METRICS_V2_CLEANUP_DISABLED=true` independently prevents all three
  destructive retention jobs even if scheduled.

Implement dependency-injected `buildAdminMetricsActivityCleanup`,
`buildPushDeliveryCleanup`, and `buildReferralLinkOpenCleanup` functions plus
their `schedule*` wrappers, following the existing ET scheduler conventions.
Cleanup must not use `JobRun.claimRun`, which marks a day before work completes.
Add a Postgres `analytics_cleanup_runs` lease row unique on `(job_key, day_key)`
with `state=running|complete`, monotonic `fence`, `lease_owner`,
`lease_expires_at`, nullable bounded-batch cursor, and `completed_at`. Claim is
an atomic insert or CAS takeover of an expired `running` lease that increments
the fence. Each bounded delete and cursor update is conditional on owner/fence;
the worker renews the lease between batches. Only observing no remaining rows
for the fixed cutoff may CAS `state=complete`. A crash/failure leaves an
expiring running lease, so another process retries; a stale owner cannot delete
or complete after takeover. Completed same-day rows no-op.

The jobs delete activity rows older than 180 days, push deliveries older than
30 days, and referral link opens older than 90 days. Register injected
scheduler defaults in `startServer` and invoke them from `startCrons` only when
the environment kill switch is not true; startup tests must assert each
scheduler is called at index 0/its first tick just like the existing injected
cron probes. First production cleanup deploys with the kill switch true;
observe dry-run cutoff/count logs, then enable one job at a time.

Enable order is exact: migrate tables/columns → deploy backend with both flags
off and cleanup disabled → verify legacy query parity → release the iOS build
carrying capability/parsers → enable telemetry → observe eligibility
and collecting coverage → enable dashboard for admins → after 30-day telemetry
maturity, enable cleanup as above. Provider Phase B has separate flags and is
not part of this sequence.

Client telemetry cohort math uses `occurred_at`; durable transaction metrics
use server timestamps such as `created_at`, `joined_at`, and `started_at`. One
funnel must never mix event receipt time with event occurrence time.

## 9. Frontend implementation path

1. Add defensive DTO/parser helpers for v2 while leaving legacy admin parsing
   intact. No unchecked casts/non-null assertions on server fields.
2. Recompose only the statistics portion of `AdminScreen`; keep Config, Inbox,
   and Debug tools intact.
3. Add the expanded Summary board and collapsed drill-down boards in §4.
4. Fetch `dashboard-summary` once. Fetch each drill-down section lazily on its
   first expansion using the exact section name in §7.1; Invite and Onboarding
   share one cached `dashboard-funnels` response. Release Adoption uses
   `dashboard-release-adoption`. A single request queue permits only one
   dashboard fetch at a time. Refresh serially updates Summary then every
   previously opened block without auto-opening them; rapid repeated refreshes
   coalesce rather than queue another full cycle.
5. Add metric info affordances for definition, window, source, and coverage.
   Hide provider-only Summary money tiles and provider-only Revenue rows while
   their source status is `not_configured`; do not fill the dashboard with
   permanent unavailable placeholders. Keep parsing support for future fields.
   Replace the legacy “minted/sunk” presentation in the new v2 dashboard with
   “gross credits/debits,” always show median beside mean balance, and label
   ledger/claims/SSV trends as retained-account history.
6. Render only the iOS Onboarding Funnel series; the v2 parser and UI contain
   no alternate-platform series or placeholders.
7. Move Versions to `DEBUG → RELEASE ADOPTION`; keep older-backend behavior
   graceful.
8. Emit foreground once per authenticated foreground session from a lifecycle
   owner that does not run for background step sync. Queue best-effort offline
   using the bounded analytics mechanism; never block app entry.
9. Emit leaderboard and notification-open events at the true user interaction
   boundaries. Notification navigation proceeds even if analytics fails.
10. Emit all new capability, lifecycle, health, leaderboard, and notification
    instrumentation only from iOS. Shared Flutter code must remain compile-safe
    for the repo's other build target, but that target adds no dashboard data,
    UI series, provider plan, or feature-specific behavior.
11. Extract `OnboardingFunnelSection` from `AdminGrowthStatsBody`, keep only its
    iOS presentation, and remove the old embedding so it cannot render twice.
    Extract the existing Versions body into collapsed `Debug → Release
    Adoption`, defensively hiding it when a legacy payload omits versions.
12. Preserve a single vertical order on compact and wide phones. The current
    board width is screen width minus 48, so badges, definition affordances,
    chart rows, and long version strings must wrap by increasing row height,
    never reorder or overflow horizontally. Do not create an Admin demo/tutorial
    mirror: none exists today.

## 10. Backward compatibility and rollout

- **Backend first, app second.** New backend continues returning the full
  legacy `/admin/stats` response for frozen clients.
- New fields/tables/endpoints are additive. No existing field is removed,
  renamed, repurposed, or made required.
- New app + old backend: dashboard section names are ignored and `metricsDashboard` is
  absent; show “Dashboard requires a server update” and retain access to
  non-stat Admin tools. New analytics POST 404s are swallowed as best-effort.
- Old app + new backend: old no-section request and legacy screen behave exactly
  as before. Provider work is never executed for that request.
- Foreground DAU/retention shows `COLLECTING SINCE <date>` until coverage is
  mature. Do not combine step-based historical values with foreground values.
- D1 can become mature after carrying-build rollout + 1 full day, D7 after 7,
  D30 after 30. The dashboard exposes coverage dates so partial cohorts are not
  silently compared with mature ones.
- Phase A contains no external credentials, cache, or import job. Provider
  leaves are null and source status is `not_configured`; the UI hides those
  rows. Phase B will define independent provider kill switches.
- No `testOnly` content/art gate is needed; this adds no remotely toggled asset.

## 11. Test and verification plan

The product request asked for no tests. That cannot be made part of an approved
implementation plan because the repository contract and `spec-feature`
workflow require tests-first for both implementation agents and protect
existing tests. No tests are written during this spec-only phase. If approved,
the minimum required plan is:

Backend integration tests, written first:

- Legacy `GET /admin/stats` with no sections retains its exact established
  contract and does not execute v2/provider queries.
- Exercise all four request modes, including unknown-only window soft
  degradation, mixed-section `400`, exact disabled envelopes, requested-block
  omission, query ceilings, and proof that dashboard-only requests execute no
  legacy query family.
- Each dashboard section computes only its intended block; together they cover
  seeded/non-featured boundaries, review-account
  exclusion, ET boundaries, mature denominators, null percentage semantics,
  and every DB-native metric through real HTTP + test Postgres.
- Seed mixed Apple/Google identities, mixed-platform activation events and
  device tokens, and version rows. Prove every v2 numerator/denominator includes
  non-review iOS users across both sign-in providers, the two new events accept
  only `platform='ios'`, push attribution accepts only current-epoch iOS tokens,
  Release Adoption is iOS-only before its platform leaf is removed, and every
  legacy aggregate is unchanged.
- Seed frozen, upgraded, and signup-capable clients and prove immutable signup
  eligibility, capable-only DAU/retention denominators, per-metric collecting
  states, exact-day maturity, collection disable/re-enable epoch gaps, and no
  backfill from steps, disabled periods, or later upgrades. Prove the two v2
  generic events soft-drop while disabled while every legacy event still writes.
- Seed cancelled/review-created races, boundary timestamps, deleted-account
  cascades, referral cohorts, and first-power coverage edges to lock the exact
  populations in §§5 and 7.1.1.
- Foreground ingestion is authenticated, idempotent, background-independent,
  handles offline/reordered occurrences with min/max timestamps, and supports
  version skew.
- Notification opens attribute only to the owning user and do not create an id
  oracle. Direct, Inbox-outbox, and special visible sends create one logical
  delivery fact; silent/failed/incapable sends do not enter the denominator;
  retries/crash resumes reuse `deliveryKey`/`publicId`; success only to an
  incapable token does not qualify; cold-start delayed receipts remain attributable.
- Phase A returns `not_configured` plus null provider leaves, never zero, and
  performs no external call.
- Each retention cleanup job proves cutoff boundaries, bounded batches,
  account cascade, lease expiry/fencing, crash retry, stale-worker rejection,
  completion-after-all-batches, and environment kill-switch behavior.
- Referral integration tests cover active HMAC writes, missing-secret null
  fallback, 48-hour legacy/current and current/previous dual-read boundaries,
  stop-reading-old-version behavior, rotation, coverage collection, and 90-day
  deletion for both exact-address and network-prefix hashes without
  logging/returning IP material.
- Run dashboard/telemetry integration coverage once with Redis unavailable to
  prove Postgres authority. Tests that exercise the existing settings cache
  use only the dedicated local Redis DB 15 and flush only that DB before/after;
  they never target a shared/prod Redis instance.

Frontend widget/integration tests, written first:

- Pump the real Admin screen with complete, partial, null, malformed, legacy,
  stale, empty, and failed responses.
- Summary and section ordering, state labels, iOS-only onboarding rendering,
  release-adoption move, definition affordance, refresh/lazy-fetch behavior,
  and both compact/wide phone constraints.
- Foreground and notification open telemetry are best-effort and never block
  navigation or startup.
- Cold-start notification ids queue until authentication and then flush once;
  404/405 from older servers is swallowed for foreground and open receipts.
- Frozen/new backend permutations cover missing capability flags, a disabled
  dashboard, absent blocks/leaves, unknown enum values, and old pushes without
  a notification id.
- Verify both existing `clientFeaturesHeader` composition branches emit
  `admin_metrics_v2` on iOS. The Android build must compile for repository
  safety but must not emit the capability, foreground facts, health/leaderboard
  v2 events, or notification-open receipts; it receives no dashboard feature.
- Existing Admin Config/Inbox/Debug behavior remains reachable.

Verification:

- Backend integration DB URL must be confirmed as a dedicated `*_test`
  database before running; never production. Run relevant integration suites,
  then `npm run test:unit` and `npm run test:integration`, never bare
  `npm test`.
- Frontend: targeted widget suites, then `flutter analyze` and `flutter test`.
- Verify the iOS feature behavior. Preserve shared-project build compatibility
  as required by the repository contract without adding non-iOS dashboard work.
- Execute the manual UI-placement checklist produced in Phase 4.

## 12. Resolved product decisions

The owner accepted all recommended defaults on 2026-08-18:

1. Summary shows engaged box openers and capability-scoped observed foreground
   DAU/WAU together once coverage exists; collecting states remain visible
   until mature and the values are never presented as whole-population DAU.
2. All product/operator aggregation uses `America/New_York` calendar days.
3. App Store Connect and AdMob imports are deferred to separately approved
   Phase B. Phase A ships database metrics and instrumentation.
4. Race engagement shows both new participants that day and participants in
   live races that day.
5. First-race power activation uses the first non-featured, non-tournament,
   powerups-enabled race with at least two accepted users.
6. Repeat-race retention shows both 7-day and 30-day conversion.
7. Invite conversion uses attributed signups / pseudonymously deduped referral
   link opens with bounded retention; it does not use share-sheet actions as
   “invites sent.”
8. Invite copy testing is a later experiment, not part of this feature.
9. Versions remain available under collapsed Debug → Release Adoption.
10. When Phase B exists, provider-latest revenue may display with a clear
    `as of` badge. Phase A hides provider-only money tiles.
11. D1/D7/D30 use exact calendar-day return, not rolling return-on-or-after.

There are no unresolved product questions in this draft.

## 13. Acceptance criteria / definition of done

- Every displayed metric maps to one definition in §5 and visibly communicates
  its source/window/coverage.
- Step-sync users are never labeled DAU. Box openers are labeled as engaged box
  openers. Observed foreground DAU/WAU/MAU and retention use capable-client
  foreground facts only and disclose immutable eligibility coverage.
- Summary and drill-down values share canonical backend computations and cannot
  disagree due to duplicate client math.
- All DB-now metrics selected in §12 are present and exclude review accounts.
- Forward-only metrics show collecting/unavailable until mature; no fabricated
  historical backfill.
- Phase A never calls providers and hides provider-only rows; Phase B remains a
  separate approval item documented for feasibility in §6.3.
- Purchase, ARPPU, and LTV rows do not imply real-money/user-level data the
  product does not have.
- Coin rows say gross credits/debits rather than earned/spent or minted/sunk;
  balance includes population, mean, median, and p90; SSV rows include totals,
  unique watchers, per-kind breakdown, and the reward-kind trust caveat.
- Onboarding funnel renders the iOS series only and uses correct
  numerator/denominator pairs; the v2 contract contains no other platform series.
- Invite funnel uses one consistent selected window and does not call share
  actions “invites sent” without a recipient count.
- Frozen old clients work against the new backend; the new client degrades
  safely against old/missing fields and endpoints.
- Disabling/re-enabling telemetry creates explicit collection epochs; metrics
  never bridge disabled gaps. Push retries remain one logical delivery, HMAC
  referral dedupe writes no unsalted hash, and cleanup is crash-retryable with
  fenced Postgres leases.
- The iOS product path is complete, shared-project compilation remains intact,
  and the required automated checks, architect, game/economy review, code
  review, and manual UI checklist are complete.

## 14. Manual UI-placement test plan

**Manual UI-Placement Test Plan — Admin metrics dashboard rework (iOS)**

*Elements under test:*
- Expanded Summary board added at the top of Admin statistics, before every drill-down.
- Existing statistics reorganized into collapsed User growth, Invite funnel, Onboarding funnel, Activation, Retention, Race + engagement, Virality, and Revenue boards in that order; old top-level Growth and Engagement boards removed.
- Definition/info affordances plus window, source/timezone, coverage/as-of, and loading/empty/unavailable/error states placed within the metric or section they describe.
- Onboarding funnel moved out of the old Growth body into its own iOS-only drill-down.
- Release Adoption moved from Growth’s Versions block to collapsed Debug → Release Adoption.
- Phase A unavailable external-source money and revenue rows hidden, while database-backed Revenue content remains.
- Existing Config, Inbox, and Debug tools retained below the dashboard.

*Checklist*

1. **Admin Tools — initial dashboard (real iOS screen)**
   - **Get there:** On an iPhone, sign in with an admin account → Profile → Settings → ADMIN → ADMIN TOOLS.
   - **Verify:** ADMIN TOOLS remains the heading; Summary is first and expanded. Below it, collapsed headers appear exactly: User growth → Invite funnel → Onboarding funnel → Activation → Retention → Race + engagement → Virality → Revenue → Config → Inbox → Debug. Summary is not duplicated, and old top-level Growth and Engagement boards are absent.

2. **Admin Tools — lazy drill-down placement and states (real iOS screen)**
   - **Get there:** Open each dashboard drill-down once; collapse and reopen two. Use staging data with an immature metric, then enable airplane mode before first opening another section.
   - **Verify:** Each drill-down starts collapsed and expands directly below its own header, pushing later boards down without overlap. Its loading, data, empty, collecting/unavailable, or error/retry treatment remains inside that board, alongside its window/source/coverage markers and metric info affordances. Collapsing removes the body; reopening restores it only there, with no duplicate or body left at the old position.

3. **Onboarding funnel — iOS-only placement (real iOS screen)**
   - **Get there:** Admin Tools → expand Onboarding funnel.
   - **Verify:** The chart appears only inside the Onboarding funnel board and contains one iOS series. No second platform series or duplicate chart appears in User growth, Invite funnel, or the former Growth position. Collapsing removes the chart from view.

4. **Debug → Release Adoption move (real iOS screen)**
   - **Get there:** Scan Summary and User growth, then scroll to Debug → Release Adoption.
   - **Verify:** Release Adoption is nested under Debug and starts collapsed; its version table appears directly beneath that nested header when expanded. It is absent from Summary, User growth, and the top-level board list. Existing Debug tools remain reachable alongside it.

5. **Phase A hidden-row layout (real iOS screen)**
   - **Get there:** Use the Phase A staging backend and inspect Summary, User growth, and Revenue.
   - **Verify:** Summary contains no empty money tile or reserved money gap. Rows whose external source is unavailable in Phase A are absent rather than shown as zero or permanent placeholders. Database-backed Revenue rows remain under Revenue, and hidden rows leave no copies or gaps in old positions.

6. **Old-backend fallback (real iOS screen)**
   - **Get there:** Launch the new iOS build against an older/stub backend that does not return the dashboard block; sign in as admin and open Admin Tools.
   - **Verify:** “Dashboard requires a server update” occupies the dashboard area near the top. No empty Summary grid, legacy Growth/Engagement dashboard, or rows of misleading dashes appear with it. Config, Inbox, and Debug remain below and reachable. Release Adoption appears only under Debug when legacy version data exists, never back under Growth.

7. **Compact iPhone placement (real iOS screen)**
   - **Get there:** On the smallest supported iPhone in portrait, expand Summary, Onboarding funnel, Race + engagement, Revenue, and Debug → Release Adoption.
   - **Verify:** Boards remain in one ordered vertical scroll. Headers, metric/value rows, info affordances, badges, chart rows, and version strings stay inside their host boards without overlap, clipping, or horizontal off-screen placement. Wrapping increases row height rather than moving content into an adjacent row; nothing remains at an old location after reflow.

8. **Wide iPhone placement (real iOS screen)**
   - **Get there:** Repeat checkpoint 7 on a wide/large iPhone in portrait.
   - **Verify:** The same single-column order and host-board placement are preserved; extra width does not create columns, reorder sections, separate affordances from their metrics, or duplicate moved content.

*Surfaces confirmed unaffected:*
- Settings ADMIN entry point — code pushes the single production `AdminScreen`; ADMIN → ADMIN TOOLS remains unchanged.
- Demo race tutorial — grep found no Admin screen or dashboard reuse under `lib/demo/`.
- Tab tutorial/tutorial previews — grep found no Admin reuse under `lib/tutorial/`; Admin is not a mirrored tab surface.
- Onboarding flow — it supplies analytics events but never renders Admin Tools.
- Tutorial spotlight anchors — Admin files expose no tutorial `GlobalKey` or target key.
- Config, Inbox, and existing Debug tool bodies — outside the statistics rework; only Debug gains nested Release Adoption.

*Risks found while planning:*
- `OnboardingFunnelSection` is currently embedded in `AdminGrowthStatsBody`; it must be extracted into one iOS-only board and removed from the old body or it can render twice.
- Versions currently render inside `AdminGrowthStatsBody`; Release Adoption needs a separate nested Debug section while retaining defensive hiding when legacy data is absent.
- The current shell has six top-level sections and expands Growth by default; implementation must make Summary the expanded default and explicitly preserve the new dashboard/non-stat order.
- Phase A must not hide the whole Revenue board: database-backed rewarded-ad/economy content still belongs there.
- No Admin demo/tutorial mirror or spotlight key exists, so a new hand-copied Admin dashboard would create an untracked mirror.
- Current board width is `screen width - 48`; dense badges, chart rows, affordances, and version strings need compact/wide iPhone handling.

## 15. Revision log

- **Initial draft (2026-08-18):** Audited current frontend, backend aggregate,
  schema, analytics, notification, and external provider capabilities. Replaced
  stepped-today “DAU” with explicit box-opener and future foreground concepts;
  separated real revenue from virtual-coin purchases; added feasibility matrix,
  additive API/migration plan, provider cache, and open decision list.
- **Gap pass 1 (2026-08-18):** Split the monolithic v2 request into eight lazy
  section contracts to protect the one-vCPU backend; corrected offline
  foreground attribution to use bounded event time and labeled it telemetry;
  replaced an unsafe JSON unique key with canonical `dimensionKey`; pinned
  Ranked v2 participation; defined notification rate as opens over
  provider-accepted user sends rather than presumed delivery; and renamed the
  box coverage field to first-observed time rather than claiming unknowable
  rollout coverage.
- **Gap pass 2 (2026-08-18):** Reframed onboarding as one mature start cohort
  with a fixed 24-hour completion window; pinned 30-cohort exact-day retention;
  corrected leaderboard-view, races-per-active-user, and powerups-per-race
  denominators; defined notification rate as provider-accepted push opens;
  added telemetry/provider/push retention policies and account-delete cascade;
  removed duplicate platform/version headers; clarified the union response
  example; and required occurrence-time vs transaction-time consistency.
- **Interview resolution (2026-08-18):** Owner accepted all recommended
  defaults. Split provider ingestion into a separately approved Phase B; pinned
  both race-participant views, first eligible race, 7d/30d repeat retention,
  pseudonymously deduped link-open conversion, later invite-copy experimentation,
  release-adoption placement, ET/exact-day activity semantics, and Phase A
  hiding of provider-only rows.
- **Post-interview gap pass (2026-08-18):** Removed the remaining local-day and
  invite-experiment ambiguity; removed Phase A's Summary money placeholder;
  made provider response examples consistently `not_configured`; removed
  provider cache/import steps from Phase A; and replaced the obsolete “pin open
  definitions” step with the resolved §12 contract. Zero product questions
  remain.
- **Architect review (2026-08-18, APPROVE):** Required changes were applied in
  two revision rounds: epoch-scoped capability cohorts and per-horizon coverage;
  exact single-section wire/query contracts; deterministic capable-token push
  delivery facts; fenced cleanup leases; Phase A versioned HMAC for both exact
  IP and network-prefix referral hashes; a dedicated Release Adoption block;
  schema-accurate/global race exclusions; complete migration/serializer rules;
  and the high-risk integration matrix. Final confirmation returned no required
  changes or suggestions.
- **Game/economy review (2026-08-18, SOUND WITH CHANGES):** Required and
  applied: renamed coin earned/spent and minted/sunk claims to gross
  credits/debits; made population/median/p90 balance mandatory; disclosed
  account-deletion revision of ledger/claim/SSV history; added total, unique,
  and per-kind SSV counts; nulled Phase A's provider denominator; specified
  Phase B timezone/date/platform/unit/format alignment and signed timestamp;
  disclosed provider/non-review population mismatch; and removed the false
  implication that SSV authenticates every client-routed reward kind. The
  reviewer added the deletion-retention caveat to `docs/economy.md`.
- **UI test planner (2026-08-18, complete):** Supplied the verbatim iOS-only
  eight-scenario manual placement checklist in §14, confirmed there are no Admin demo/tutorial
  mirrors or spotlight anchors, and identified extraction, ordering, provider-
  hidden, and compact-width risks now pinned in §9.
- **Final gap pass (2026-08-18):** Reconciled the three reviews; validated the
  normative JSON example; removed whole-population DAU claims and provider-only
  Summary placeholders; added collection-gap, retry, privacy-rotation, and
  old-server fallbacks; and confirmed zero unresolved product or architecture
  questions. `git diff --check` is clean.
- **iOS-only scope revision (2026-08-18; corrected 2026-08-19):** At owner
  direction, removed Google Play, alternate-platform UI/data series, provider dimensions, and all
  non-iOS feature instrumentation. The original `apple_id IS NOT NULL` scope
  incorrectly excluded iOS users of Google Sign-In; retained non-review users
  across both authentication providers are the authoritative v2 population.
  Restricted activation facts,
  APNs delivery attribution, referral ownership, capability epochs, and Release
  Adoption accordingly. Retained only the mandatory negative compile/no-emit
  guard for the shared project. Architect reconfirmed **APPROVE** with no
  required changes or suggestions; UI planner replaced §14 with the focused
  iPhone checklist.
- **Owner approval (2026-08-18):** Owner explicitly approved implementation of
  the reviewed iOS-only specification.
- **Implementation (2026-08-19):** Backend and Flutter implementations landed
  tests-first. Required combined review findings were resolved through three
  focused passes; final verdict was **SHIP** with no blockers, issues, or nits.
  Feature flags remain default-off until the production-like one-vCPU
  `EXPLAIN (ANALYZE, BUFFERS)` and p95 rollout gate is completed.
