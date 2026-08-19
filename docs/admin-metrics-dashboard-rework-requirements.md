# Admin metrics dashboard rework — requirements

Status: **DRAFT — interview resolved; reviews pending; not approved for implementation**

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
3. **Provider** — comes from Apple, Google Play, or AdMob and requires a
   credentialed asynchronous import.
4. **Unavailable** — cannot be computed honestly with the current product or
   source granularity.

The dashboard must never render an unavailable or not-yet-instrumented metric
as zero.

### 1.1 Scope and non-goals

**In scope for this feature (Phase A):** rework the statistics UI; add all
selected database-backed metrics; correct invite/onboarding percentages; add
foreground, health-connect, leaderboard-view, and notification-open
instrumentation; expose eight lazy additive admin-stat blocks; and move app
version adoption under Debug.

**Explicitly deferred to a separately approved Phase B:** credentialed imports
from App Store Connect, Google Play, and AdMob. Phase A keeps provider-only
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
- The app has no StoreKit/Google Play Billing/RevenueCat dependency or
  real-money purchase model. Existing shop “purchases” spend virtual coins and
  therefore are not revenue.
- Apple exposes first-time downloads, installations, sessions, active devices,
  and deletions through App Store Connect Analytics, but usage/deletion data is
  opt-in, thresholded, and may include statistical privacy treatment. The
  Analytics Reports API supports ongoing and snapshot bulk reports.
- The AdMob reporting API exposes impressions, estimated earnings, matched
  requests/match rate, and observed eCPM, including mediation dimensions. It
  does not expose an authoritative per-user revenue allocation.
- Google Play provides install/uninstall statistics and programmatic bulk CSV
  exports, but its acquisition/reporting APIs and report semantics differ from
  Apple. Cross-store “installs” must therefore be shown by platform/source,
  not combined without explanation.

External references:

- Apple metric definitions:
  https://developer.apple.com/help/app-store-connect-analytics/reference/metrics-definitions/
- Apple Analytics Reports API overview:
  https://developer.apple.com/help/app-store-connect-analytics/overview/analytics-reports-api
- AdMob reporting overview:
  https://developers.google.com/admob/api/v1/report-overview
- Google Play aggregated install reports:
  https://support.google.com/googleplay/android-developer/answer/6135870

## 3. Product definitions

Unless a row explicitly states otherwise:

- Product/database days use `America/New_York` calendar boundaries.
- Provider rows retain and label the provider's own reporting day/timezone.
  They are not silently rebucketed into ET when only daily aggregates exist.
- “User” means a non-review account. Product-DB v2 metrics exclude
  `users.is_review_account=true` from both numerator and denominator. Provider
  aggregates are the exception: AdMob/Apple/Google do not provide user-level
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
| DAU replacement: box openers | DB now | Distinct non-review `actor_user_id` with `MYSTERY_BOX_OPENED` during current ET day. Label **Engaged box openers today**, never DAU. Historical coverage begins when these events shipped. |
| Observed foreground DAU / WAU | Forward-only, capability-scoped | Distinct capable users with an authenticated foreground fact during today / trailing 7 ET days. Background sync does not emit it. This permanently excludes frozen incapable clients and is never labeled population-wide “true DAU.” |
| Observed D1 / D7 / D30 retention | Forward-only, signup-capability cohort | New accounts stamped telemetry-capable at signup that return via a foreground fact on exact signup+N ET calendar day; mature cohorts only. Summary pools the latest 30 mature eligible signup-date cohorts for each N; drill-down returns each date. All-signup retention remains unavailable. |
| Users in a race | DB now | Distinct accepted non-review users in an `ACTIVE`, non-featured, non-tournament race now. |
| Active races (non daily/weekly) | DB now | `ACTIVE` races with no seed and no tournament. |
| Daily races | DB now | `ACTIVE` races joined to a `DAILY` seed. |
| Races created today (non daily/weekly) | DB now | Non-featured, non-tournament races with `created_at` in current ET day. |
| Revenue today | Provider | AdMob `ESTIMATED_EARNINGS` for latest available provider day. “Today” can lag/intraday and must show `asOf`. |
| Revenue / DAU | Provider + forward | Same estimated earnings divided by true foreground DAU for the exact aligned day. Null if dates cannot be aligned. |

### 5.2 User growth

| Requested metric | Feasibility | Definition/source |
|---|---|---|
| Total users | DB now | Same canonical summary value; do not recompute differently. |
| New installs/day | Provider | Apple First Time Downloads and Google Play Daily User Installs shown as separate platform series. They are store/device/account measures, not backend people. |
| New signups/day | DB now | New non-review accounts per ET day. |
| Observed foreground DAU / WAU / MAU | Forward-only | Distinct capable users with foreground facts over 1/7/30 ET days. Always show capable-account coverage; never imply users who stay on frozen clients are observed. |
| Uninstalls | Provider | Apple Deletions and Google Play Daily User Uninstalls shown separately. Apple data is opt-in/thresholded; both are provider events, not a current-user census. |

### 5.3 Invite funnel and virality

Keep current link opens, attributed signups, joined-race, qualified/finished,
and rewarded stages, but add a selected window consistently to every stage.
Do not mix a 7-day top stage with lifetime lower stages.

| Requested metric | Feasibility | Definition/source |
|---|---|---|
| Invites 7d / DAU 7d | Not reliable as written | The current client `invite_flow_sent` is best-effort and a share-sheet completion is not a recipient count. Do not display an “invites sent” metric. A later experiment may add **share completions per WAU** with its limitation stated. |
| Users who join / invites sent | DB now with revised denominator | Display **Attributed signups / unique referral link opens**. Do not use sharing actions as a denominator. |
| Invite conversion | DB now | Attributed referral signups / unique referral landing-page opens for the same window. Unique opens use the privacy-safe rule below. |
| K-factor | Unavailable exactly today | Do not use the proposed division formula or label a proxy “K-factor.” Display **Attributed signups per WAU (7d)** once WAU matures. True invitations-per-user remains unknown. |
| Improve invite wording | Deferred experiment | This feature establishes measurement only. Copy variants, assignment, confidence rules, and copy changes require a separate spec. |

For `unique referral link opens`, partition referral `link_opens` by normalized
`code` and non-null `ip_hash`, order by `created_at`, and count the first row
plus a new session after a gap greater than 24 hours. Rows with a null code are
excluded from conversion; rows with a null hash cannot be deduped and each count
as a unique open. The selected-window predicate applies to opens and attributed
signups alike. The existing raw SHA-derived IP hash is pseudonymous, not
anonymous or “privacy-safe.” Phase A retains `link_opens` for at most the
largest operational dashboard window (90 days) and never returns the hash.
A future secret-keyed, versioned HMAC (`ipHashVersion`) must dual-read the
legacy and v2 values for 48 hours during rotation, then stop reading the legacy
hash; it must not extend retention.

### 5.4 Onboarding and activation

The onboarding funnel is iOS-only in the UI per product direction. Backend may
retain Android data; removing it from the response would break compatibility
and remove future diagnostic value. The corrected funnel selects iOS sessions
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
| Completed one race → another | DB now | Users whose first accepted non-featured race reaches `completed_at` while their participant row is `COMPLETED`, followed by an accepted `joined_at` in a different eligible race strictly after that completion and within 7/30 elapsed days. Cohort date is the first race's `completed_at`; each denominator contains only cohorts mature for its horizon. Cancelled and review-created races are excluded. |

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
| Notification → app-open rate | Forward-only | Provider-accepted visible push sends with durable notification id joined to a new authenticated notification-open receipt. Return distinct opened sends / provider-accepted user sends over 7d by type/platform. This is push-open rate, not proof the process was previously closed and not device-delivery rate. |

### 5.7 Revenue

| Requested metric | Feasibility | Definition/source |
|---|---|---|
| Ad impressions/day | Provider | AdMob `IMPRESSIONS`, grouped by date/platform/ad unit/format as available. |
| Rewarded ads watched/day | DB now, signed callback | Count retained-account `ad_reward_grants` by callback date and reward kind; return total grants, unique watchers, and per-kind counts/watchers. SSV proves a signed rewarded interaction, but current code does not enforce an ad-unit-to-reward-kind mapping for every kind, so do not claim the recorded kind is independently authenticated. |
| Ads watched / observed foreground DAU | DB + forward | Signed-callback grants / aligned observed foreground DAU. Return total grants and unique watchers; disclose the capability-scoped denominator. |
| Ad completion % | Deferred approximate Phase B metric | Call it **SSV grants per rewarded impression**, never completion rate. Match provider timezone/date, platform, rewarded ad unit, and rewarded format. Callback arrival is not impression time; delayed callbacks can make a daily ratio exceed 100%. Phase A returns no denominator or percent. |
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
`DEBUG → RELEASE ADOPTION`; do not delete its additive API fields. It should
remain explicitly labeled “accounts seen by backend in last 30d,” not install
base. This placement is decided.

## 6. Instrumentation and data model

### 6.0 Capability and cohort eligibility

Add `admin_metrics_v2` to **both** branches of
`BackendApiService.clientFeaturesHeader`. The backend sticky-records the first
capable authenticated request but never treats a missing later header as a
downgrade.

Additive fields:

```prisma
// User
metricsV2EligibleAt     DateTime? @map("metrics_v2_eligible_at")
metricsV2SignupEligible Boolean   @default(false) @map("metrics_v2_signup_eligible")

// DeviceToken
adminMetricsOpenCapable Boolean @default(false) @map("admin_metrics_open_capable")
```

- `metricsV2EligibleAt` is set once on the first authenticated request carrying
  the capability. Existing/frozen users begin null and may become eligible on
  upgrade.
- `metricsV2SignupEligible` is set only in the new-account transaction when the
  creating request carries the capability; it is immutable thereafter. D1/D7/
  D30 and health-within-24h denominators use only this cohort. An older signup
  that later upgrades never enters signup retention retroactively.
- Device-token registration from a capable client sticky-sets
  `adminMetricsOpenCapable=true` for that token. Notification-open denominators
  require a capable token and a capable delivery fact; old tokens remain false.
- Every forward-only response path has a `metricCoverage` entry containing
  `status`, `collectingSince`, `eligible`, `totalPopulation`, and
  `eligibilityPercent`. Status is `collecting|mature|unavailable`; unavailable
  metrics return null values. Coverage maturity never claims frozen clients
  eventually become observable.

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
  platform     String
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
server derives `userId`; validates platform/version and the client event time
with the same bounded approach as activation telemetry; converts `occurredAt`
to ET; and upserts the daily row. Event time is needed so a session queued while
offline is attributed to the day it happened rather than the later flush day.
It remains client telemetry: reject future times and events more than 35 days
old, and label the dashboard source `foreground_telemetry`. This is the
best available definition of intentional use, not a security authority. The
migration performs no historical backfill. `(userId, activityDate)` is the
durable idempotency boundary; `sessionId` is validation/diagnostic input only
and is not stored. Upsert sets `firstSeenAt=LEAST(existing, occurredAt)`,
`lastSeenAt=GREATEST(existing, occurredAt)`, and replaces platform/appVersion/
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

- `race_leaderboard_viewed`: `race_id`; one event each time the leaderboard
  surface becomes visible. Event idempotency prevents retry duplicates, but a
  second intentional view in the same session remains a second view.
- `health_connected`: no health payload; source only. This complements rather
  than repurposes existing onboarding events.
- `notification_opened`: prefer an authoritative dedicated endpoint carrying
  opaque server notification id; do not place arbitrary notification data into
  generic analytics context.
- No invite experiment exposure/share event is added in Phase A; that work is
  explicitly deferred.

For durable “power used in first race,” “race created,” race starts, and coin
flows, use server transaction rows instead of duplicating client events.

### 6.3 Provider daily cache (deferred Phase B design, not Phase A scope)

Do not call Apple/Google/AdMob synchronously from `GET /admin/stats`; provider
latency or auth failure must not stall the app or the one-vCPU API server.

The following is feasibility guidance for the separately approved provider
phase, not an instruction to create this table in Phase A. Add a generic daily
aggregate cache only after provider credentials/scope are confirmed:

```prisma
model ExternalMetricDaily {
  id           String   @id @default(uuid())
  provider     String
  metric       String
  metricDate   DateTime @db.Date @map("metric_date")
  dimensionKey String   @map("dimension_key")
  dimensions   Json     @default("{}")
  valueMicros  BigInt?  @map("value_micros")
  valueCount   BigInt?  @map("value_count")
  valueRatio   Float?   @map("value_ratio")
  currency     String?
  importedAt   DateTime @map("imported_at")

  @@unique([provider, metric, metricDate, dimensionKey])
  @@index([provider, metric, metricDate])
  @@map("external_metric_daily")
}
```

`dimensionKey` is a backend-built, length-bounded canonical serialization of
an allowlisted, sorted dimension map; callers never supply it. JSON remains the
readable source description. Provider import jobs are idempotent upserts, retry
with bounded backoff, and re-import the most recent mutable days to absorb
reporting lag. Credentials live only in backend environment/secret storage.

Provider values preserve provenance and limitations:

- `provider`, report name, source timezone, report date, imported time,
  opt-in/threshold note, and stale state.
- Apple and Google values remain platform-separated.
- AdMob money stays in micros and source currency; no float dollars in storage.
- AdMob rows retain publisher reporting timezone, platform, rewarded ad unit,
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

Add a non-PII opaque public id plus `providerAcceptedAt`, `failedAt`, and
`openedAt` to the per-user visible notification record and payload. A
notification is in the denominator only when at least one device-token send
was accepted by FCM/APNs; this is **provider-accepted**, not guaranteed device
delivery. Inbox-only alerts and users with no accepted push are excluded. On
notification tap, the authenticated app POSTs the id. The backend records an
idempotent opened timestamp only when the id belongs to that user.
Unknown/expired ids return success with `attributed:false` so stale frozen
clients or delayed taps never break navigation. Do not expose internal user ids
in push payloads. Because the current notification table also acts as cron
dedupe storage, its existing rows and cleanup semantics must not be repurposed;
the implementation may use additive columns only if every writer can maintain
them safely, otherwise create a separate bounded `push_deliveries` table.
Attribution rows retain for 30 days to allow delayed taps; the displayed rate
remains a trailing 7-day metric.

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

Each name computes only its own block plus the shared `window`, `coverage`,
`sources`, and `schemaVersion` metadata. This preserves the current lazy-query
design instead of running the full dashboard when the user only reads Summary.

Request:

```http
GET /admin/stats?sections=dashboard-summary&window=30d
Authorization: Bearer <identity token>
```

- `window`: `7d|30d|90d`, default `30d`; invalid value → `400
  {"error":"INVALID_WINDOW"}`.
- Old backends ignore `dashboard-summary` and return the legacy `stats` object
  without `metricsDashboard`.
- New backends append `stats.metricsDashboard`; they do not remove or restate
  legacy keys used by frozen clients.
- Admin authorization behavior remains `403` for non-admin and `401` for
  invalid/missing authentication.

Exact union envelope (representative values; this example combines all eight
recognized sections to show every optional block, and every key shown is
stable):

```json
{
  "stats": {
    "generatedAt": "2026-08-18T15:04:05.000Z",
    "metricsDashboard": {
      "schemaVersion": 2,
      "window": {"days": 30, "start": "2026-07-20", "end": "2026-08-18", "timeZone": "America/New_York"},
      "coverage": {
        "foregroundActivitySince": "2026-08-08",
        "firstObservedBoxOpenAt": "2026-08-01T14:12:01.000Z",
        "providerThrough": {"appStoreConnect": null, "googlePlay": null, "admob": null}
      },
      "summary": {
        "growth": {
          "totalSignups": 1234,
          "signupsToday": 9,
          "signupsLast7Days": 61,
          "engagedBoxOpenersToday": 117,
          "dau": null,
          "wau": null
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
        },
        "money": {
          "estimatedRevenueToday": null,
          "estimatedRevenuePerDau": null
        }
      },
      "userGrowth": {
        "daily": [{"date": "2026-08-17", "signups": 8, "dau": 112, "installs": null, "uninstalls": null}],
        "wau": 310,
        "mau": 702
      },
      "inviteFunnel": {
        "linkOpens": 200,
        "uniqueLinkOpens": null,
        "attributedSignups": 32,
        "joinedRace": 21,
        "qualified": 14,
        "rewarded": 13
      },
      "onboardingFunnel": {
        "platform": "ios",
        "stages": [{"key": "onboarding_started", "count": 80, "previousSpineCount": null, "stepPercent": null, "startPercent": 100.0}]
      },
      "activation": {
        "healthWithin24h": {"numerator": 21, "denominator": 40, "percent": 52.5},
        "raceWithin24h": {"numerator": 18, "denominator": 40, "percent": 45.0},
        "firstRacePowerUse": {"numerator": 11, "denominator": 28, "percent": 39.3},
        "friends": [{"bucket": "0", "users": 520, "percent": 42.1}]
      },
      "retention": {
        "d1": {"numerator": 18, "denominator": 40, "percent": 45.0},
        "d7": {"numerator": 10, "denominator": 38, "percent": 26.3},
        "d30": {"numerator": null, "denominator": null, "percent": null},
        "secondRaceWithin7d": {"numerator": 17, "denominator": 31, "percent": 54.8},
        "secondRaceWithin30d": {"numerator": 22, "denominator": 31, "percent": 71.0}
      },
      "raceEngagement": {
        "daily": [{"date": "2026-08-17", "racesCreated": 7, "racesStarted": 5, "newParticipants": 29, "liveRaceParticipants": 44, "powerupsUsed": 61, "grossCoinCredits": 25000, "grossCoinDebits": 17000, "dailyRewardClaims": 93}],
        "averageRunnersPerStartedRace": 4.2,
        "visibility": {"public": 12, "private": 19, "publicPercent": 38.7},
        "averageRacesPerActiveUser": 1.3,
        "averageLeaderboardViewsPerRacer": null,
        "averagePowerupsPerRace": 3.4,
        "coinBalance": {"populationCount": 722, "total": 208640, "average": 289.0, "median": 127.5, "p90": 672.8, "asOf": "2026-08-18T15:04:05.000Z"},
        "featuredParticipation": {"dailyUsers": 210, "weeklyUsers": 155},
        "rankedParticipationUsers": 74,
        "notificationOpenRate": null
      },
      "virality": {
        "shareCompletions": null,
        "sharingUsers": null,
        "attributedSignups": 32,
        "attributedSignupsPerWau": null,
        "linkOpenToSignup": {"numerator": null, "denominator": null, "percent": null}
      },
      "revenue": {
        "daily": [{"date": "2026-08-17", "impressions": null, "ssvGrants": 423, "uniqueSsvWatchers": 116, "ssvByRewardKind": [{"rewardKind": "coin_reward", "grants": 102, "uniqueWatchers": 29}, {"rewardKind": "extra_daily_spin", "grants": 124, "uniqueWatchers": 47}, {"rewardKind": "box_reroll", "grants": 171, "uniqueWatchers": 58}, {"rewardKind": "race_payout_double", "grants": 21, "uniqueWatchers": 16}, {"rewardKind": "powerup_unlock", "grants": 5, "uniqueWatchers": 4}], "estimatedEarnings": null, "matchRate": null, "showRate": null}],
        "adRevenuePerDau": null,
        "ssvGrantsPerRewardedImpression": {"numerator": 423, "denominator": null, "percent": null},
        "byNetwork": [],
        "realMoneyPurchases": {"available": false, "reason": "NO_IAP_PRODUCT"}
      },
      "sources": {
        "productDb": {"status": "available", "asOf": "2026-08-18T15:04:05.000Z"},
        "foregroundActivity": {"status": "collecting", "asOf": "2026-08-18T15:04:05.000Z"},
        "appStoreConnect": {"status": "not_configured", "asOf": null},
        "googlePlay": {"status": "not_configured", "asOf": null},
        "admob": {"status": "not_configured", "asOf": null}
      }
    }
  }
}
```

Only requested blocks are present. Multiple recognized section names may be
combined in one request and append their respective blocks under the same
`metricsDashboard`; unknown names are ignored. The frontend checks every block
and leaf defensively; missing/null renders unavailable, not zero. Unknown
enum/source statuses render as unavailable with the raw label omitted.

### 7.2 Foreground ingestion

```http
POST /analytics/foreground
Authorization: Bearer <identity token>
X-Timezone: America/New_York
Content-Type: application/json

{"sessionId":"01J...","occurredAt":"2026-08-18T14:58:00.000Z","appVersion":"2.4.0","platform":"ios"}
```

- `sessionId`: client-generated opaque ULID/UUID, max 64 safe characters, used
  for event dedupe only; never returned in admin stats.
- `occurredAt`: UTC ISO-8601 instant, no more than five minutes in the future
  and no more than 35 days old.
- `appVersion` and `platform` use the existing activation telemetry validators.
- `202 {"recorded":true}` on a valid request; idempotent repeat returns the same.
- Invalid bounded fields → `400 {"error":"INVALID_ANALYTICS_EVENT"}`.
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
- `400 {"error":"INVALID_NOTIFICATION_ID"}` for malformed input.
- Navigation never waits for this request.

## 8. Backend implementation path

1. Implement the resolved product definitions in §12 without reinterpretation.
2. Preserve the no-section legacy query and payload exactly.
3. Add additive migrations for `user_activity_days` and notification-open
   attribution. No destructive changes/backfill. Do not add the deferred
   provider cache in Phase A.
4. Add authenticated foreground and notification-open ingestion with bounded
   validation and idempotency.
5. Add server-side query modules per dashboard block. Keep heavy/provider
   blocks opt-in and bounded; run `EXPLAIN (ANALYZE, BUFFERS)` on production-like
   row counts and add indexes only where justified.
6. Return explicit `not_configured` source status and null provider leaves in
   Phase A; no external credentials or network calls.
7. Extend `getAdminStats({sections, window})` with the eight lazy dashboard
   section names in §7.1; unknown sections remain ignored. Share canonical
   query helpers between Summary and drill-down blocks. Return explicit
   coverage/source statuses.
8. Deploy backend migrations and endpoint before the app.

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
   first expansion using the exact section name in §7.1. Refresh updates Summary
   plus all blocks that have previously been opened without auto-opening them.
5. Add metric info affordances for definition, window, source, and coverage.
   Hide provider-only Summary money tiles and provider-only Revenue rows while
   their source status is `not_configured`; do not fill the dashboard with
   permanent unavailable placeholders. Keep parsing support for future fields.
   Replace the legacy “minted/sunk” presentation in the new v2 dashboard with
   “gross credits/debits,” always show median beside mean balance, and label
   ledger/claims/SSV trends as retained-account history.
6. Remove Android rendering from Onboarding Funnel only; retain platform-safe
   parsing and the underlying backend data.
7. Move Versions to `DEBUG → RELEASE ADOPTION`; keep older-backend behavior
   graceful.
8. Emit foreground once per authenticated foreground session from a lifecycle
   owner that does not run for background step sync. Queue best-effort offline
   using the bounded analytics mechanism; never block app entry.
9. Emit leaderboard and notification-open events at the true user interaction
   boundaries. Notification navigation proceeds even if analytics fails.
10. Account for iOS and Android in lifecycle/event instrumentation and dashboard
    parsing. The admin onboarding chart is the only intentionally iOS-only UI.

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
- Each dashboard section computes only its intended block; together they cover
  seeded/non-featured boundaries, review-account
  exclusion, ET boundaries, mature denominators, null percentage semantics,
  and every DB-native metric through real HTTP + test Postgres.
- Foreground ingestion is authenticated, idempotent, background-independent,
  and supports version skew.
- Notification opens attribute only to the owning user and do not create an id
  oracle.
- Phase A returns `not_configured` plus null provider leaves, never zero, and
  performs no external call.

Frontend widget/integration tests, written first:

- Pump the real Admin screen with complete, partial, null, malformed, legacy,
  stale, empty, and failed responses.
- Summary and section ordering, state labels, iOS-only onboarding rendering,
  release-adoption move, definition affordance, refresh/lazy-fetch behavior,
  and both compact/wide phone constraints.
- Foreground and notification open telemetry are best-effort and never block
  navigation or startup.
- Existing Admin Config/Inbox/Debug behavior remains reachable.

Verification:

- Backend integration DB URL must be confirmed as a dedicated `*_test`
  database before running; never production. Run relevant integration suites,
  then `npm run test:unit` and `npm run test:integration`, never bare
  `npm test`.
- Frontend: targeted widget suites, then `flutter analyze` and `flutter test`.
- Verify iOS and Android lifecycle behavior/build compatibility in lockstep.
- Execute the manual UI-placement checklist produced in Phase 4.

## 12. Resolved product decisions

The owner accepted all recommended defaults on 2026-08-18:

1. Summary shows engaged box openers and true DAU/WAU together once foreground
   coverage exists; collecting states remain visible until mature.
2. All product/operator aggregation uses `America/New_York` calendar days.
3. Apple, Google Play, and AdMob imports are deferred to separately approved
   Phase B. Phase A ships database metrics and instrumentation.
4. Race engagement shows both new participants that day and participants in
   live races that day.
5. First-race power activation uses the first non-featured, non-tournament,
   powerups-enabled race with at least two accepted users.
6. Repeat-race retention shows both 7-day and 30-day conversion.
7. Invite conversion uses attributed signups / privacy-deduped referral link
   opens; it does not use share-sheet actions as “invites sent.”
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
  openers. True DAU/WAU/MAU and retention use foreground facts only.
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
- Onboarding funnel renders iOS only and uses correct numerator/denominator
  pairs; Android data remains compatible server-side.
- Invite funnel uses one consistent selected window and does not call share
  actions “invites sent” without a recipient count.
- Frozen old clients work against the new backend; the new client degrades
  safely against old/missing fields and endpoints.
- Both platforms are accounted for; the required automated checks, architect,
  game/economy review, code review, and manual UI checklist are complete.

## 14. Manual UI-placement test plan

Pending `ui-test-planner` review after the product interview and before the
approval gate.

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
  privacy-deduped link-open conversion, later invite-copy experimentation,
  release-adoption placement, ET/exact-day activity semantics, and Phase A
  hiding of provider-only rows.
- **Post-interview gap pass (2026-08-18):** Removed the remaining local-day and
  invite-experiment ambiguity; removed Phase A's Summary money placeholder;
  made provider response examples consistently `not_configured`; removed
  provider cache/import steps from Phase A; and replaced the obsolete “pin open
  definitions” step with the resolved §12 contract. Zero product questions
  remain.
- **Architect review:** Pending.
- **Game/economy review (2026-08-18, SOUND WITH CHANGES):** Required and
  applied: renamed coin earned/spent and minted/sunk claims to gross
  credits/debits; made population/median/p90 balance mandatory; disclosed
  account-deletion revision of ledger/claim/SSV history; added total, unique,
  and per-kind SSV counts; nulled Phase A's provider denominator; specified
  Phase B timezone/date/platform/unit/format alignment and signed timestamp;
  disclosed provider/non-review population mismatch; and removed the false
  implication that SSV authenticates every client-routed reward kind. The
  reviewer added the deletion-retention caveat to `docs/economy.md`.
- **UI test planner:** Pending.
