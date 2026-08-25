# Admin DAU and engagement dashboard

## Summary & user story

As an admin, I want a dedicated DAU and engagement section that tells me how
many users were active today and what those users actually did, so that I can
separate reach, repeat usage, and meaningful product actions.

The dashboard must not collapse these signals into one opaque engagement score.
It should show distinct users and action counts where useful, with no action
percentages or DAU denominator. A today-only count such as “engaged box
openers today” must be available as soon as the event exists; it must not wait
for a 30-day historical coverage window.

## Existing system findings

- The iOS metrics dashboard is requested lazily by section from
  `lib/screens/admin_screen.dart` and rendered by
  `lib/screens/admin_metrics_dashboard.dart`.
- Its defensive wire projection is in
  `lib/models/admin_metrics_dashboard.dart`; missing or malformed server keys
  must remain safe for older/newer backend combinations.
- The backend dashboard contract and section allowlist live in
  `stepv2-backend/src/modules/admin/adminMetricsDashboard.js` and the queries
  live in `stepv2-backend/src/modules/admin/adminMetricsQueries.js`.
- Durable product facts already available include `user_activity_days`,
  `race_powerup_events`, daily reward claims, notification delivery/open facts,
  activation events, race participants, and verified rewarded-ad grants.
- The existing foreground DAU is explicitly an observed/capable iOS metric, not
  a whole-population DAU. The new section must preserve that distinction.
- The legacy Android admin surface uses the no-sections `/admin/stats` payload;
  it must continue working while the new dashboard is iOS-only or until an
  Android-compatible activity source is intentionally added.

## Scope

### In scope

1. Add a lazy `dashboard-dau-engagement` section to the metrics dashboard.
2. Show action-based DAU as distinct users who completed at least one tracked
   product action today; merely opening the app is not enough.
3. Show distinct-user counts for meaningful actions. Do not show percentages or
   DAU denominators in the action rows.
4. Show selected frequency/intensity measures separately from user reach.
5. Make today’s box-opener count directly available from the durable
   `MYSTERY_BOX_OPENED` event query, regardless of historical-window maturity.
6. Keep all reads additive and defensive for mixed backend/app versions.

### Non-goals

- No single composite engagement score or ranking of users.
- No client-side inference from screen views when a durable server fact exists.
- No new release flag or rollout percentage.
- No deletion, renaming, or repurposing of existing admin fields.
- No change to gameplay, economy, rewards, prices, odds, or scoring.
- No attempt to claim Android DAU coverage from iOS-only foreground telemetry.

## Proposed metrics

The section is organized as three groups.

### 1. Action-based DAU: “who meaningfully showed up?”

- Action-based DAU: distinct retained users who performed at least one of the
  tracked actions below during the current ET day.
- The existing observed foreground DAU and step/activity DAU remain available
  as diagnostic context elsewhere, but are not the headline denominator for
  this section and are not used to define action-based DAU.

### 2. Meaningful action adoption: “what did active users do?”

For each row, return distinct users and the raw event/action count where it
provides useful intensity information. The UI shows user counts; it does not
show percentages or a denominator:

- Joined or participated in an eligible non-cancelled non-featured race.
- Opened a mystery box (`MYSTERY_BOX_OPENED`).
- Used a powerup (`POWERUP_USED`).
- Claimed the daily reward.
- Opened a push notification.
- Watched/claimed a verified rewarded ad, split by reward kind where available.
- Viewed the race leaderboard.
- Created a race.
- Completed a race.

Two additional action types are recommended for a later expansion if their
durable facts are confirmed: a meaningful social interaction (friend request,
friend acceptance, or message) and a successful shop purchase. They are not
part of the initial nine because a purchase is an economic conversion rather
than engagement by itself, and social events currently have different privacy
and deduplication semantics.

The backend must define whether each action is “at least one event per user per
ET day” or a raw event count. The primary UI value is always distinct users;
raw counts are secondary.

### 3. Aggregate estimate and depth: “how much and how often?”

- At the bottom of the section, show the arithmetic average of the nine daily
  distinct-user counts. Label it `AVERAGE ACTION REACH` and explain that it is
  an estimate, not a unique-user count, because users may appear in multiple
  action types.
- Also show `USERS WITH ANY ACTION`, the union of users across the nine types;
  this is the more accurate unique-user estimate and should be preferred when
  the backend can compute it without unsafe event joins.
- Show raw action counts separately from distinct-user counts where useful.
- Frequency buckets (1, 2, and 3+ actions) remain a later enhancement.
- D1/D7/D30 retention remains in the existing retention section rather than
  being duplicated.

## Period-over-period comparisons

The bottom of the section also shows change properties for action-based DAU,
each of the nine action-user counts, `AVERAGE ACTION REACH`, and
`USERS WITH ANY ACTION`:

- Day over day: current ET day versus the preceding ET day.
- Week over week: trailing 7 ET days versus the preceding 7 ET days.
- Month over month: trailing 30 ET days versus the preceding 30 ET days.
- Six months over six months: trailing 6 calendar months versus the preceding
  6 calendar months.
- Year over year: trailing 12 calendar months versus the preceding 12 calendar
  months.

For each comparison, return the current value, prior value, absolute change,
and percentage change when both values are present and the prior value is
nonzero. When the comparison cannot be calculated because the required history
is missing, immature, or has a zero prior value, the UI displays `GATHERING
DATA` rather than a misleading zero or infinite percentage.

The API must identify the actual date ranges used for each period. Calendar
month/year periods must use America/New_York boundaries, not a fixed number of
hours.

## Recommended first release

To keep the first version reliable and fast, implement the following first:

1. Observed foreground DAU (existing fact).
2. Step/activity DAU (existing durable fact), clearly labeled.
3. DAU overlap between those two populations.
4. Distinct users and raw events for race participation, box opens, powerup
   use, daily reward claims, push opens, verified rewarded ads, leaderboard
   views, race creation, and race completion.
5. Actions-per-user for box opens, powerups, and race participation.
6. A 30-day daily series for the two DAU definitions and the main action-user
   counts.

Frequency buckets, repeat-activity detection, and richer cohort slicing should
   follow only if the first release proves the underlying facts are complete and
   the admin query remains within its performance budget.

## API contract

Add one optional request section:

`GET /admin/stats?sections=dashboard-dau-engagement&window=7d|30d|90d`

The complete HTTP response remains the existing `{ "stats": ... }` envelope:

```json
{
  "stats": {
  "generatedAt": "2026-08-24T12:00:00.000Z",
  "metricsDashboard": {
    "schemaVersion": 2,
    "status": "available",
    "window": {
      "days": 30,
      "start": "2026-07-26",
      "end": "2026-08-24",
      "timeZone": "America/New_York"
    },
    "sources": {},
    "coverage": {},
    "dauEngagement": {
      "asOf": "2026-08-24T12:00:00.000Z",
      "timeZone": "America/New_York",
      "actionBasedDau": { "users": 74, "status": "available" },
      "today": {
        "date": "2026-08-24",
        "actions": {
          "raceParticipation": { "users": 44, "events": 71 },
          "boxOpen": { "users": 31, "events": 58 },
          "powerupUse": { "users": 19, "events": 26 },
          "dailyRewardClaim": { "users": 62, "events": 62 },
          "notificationOpen": { "users": 12, "events": 12 },
          "rewardedAd": { "users": 17, "events": 24 },
          "leaderboardView": { "users": 36, "events": 102 },
          "raceCreated": { "users": 8, "events": 10 },
          "raceCompleted": { "users": 21, "events": 24 }
        },
        "averageActionReach": 27.8,
        "usersWithAnyAction": 74
      },
      "comparisons": {
        "dayOverDay": { "current": 74, "prior": 68, "absoluteChange": 6, "percentChange": 8.8, "status": "available", "currentStart": "2026-08-24", "currentEnd": "2026-08-24", "priorStart": "2026-08-23", "priorEnd": "2026-08-23" },
        "weekOverWeek": { "current": 70, "prior": null, "absoluteChange": null, "percentChange": null, "status": "gathering_data", "currentStart": "2026-08-18", "currentEnd": "2026-08-24", "priorStart": "2026-08-11", "priorEnd": "2026-08-17" },
        "monthOverMonth": { "current": null, "prior": null, "absoluteChange": null, "percentChange": null, "status": "gathering_data", "currentStart": null, "currentEnd": null, "priorStart": null, "priorEnd": null },
        "sixMonthsOverSixMonths": { "current": null, "prior": null, "absoluteChange": null, "percentChange": null, "status": "gathering_data", "currentStart": null, "currentEnd": null, "priorStart": null, "priorEnd": null },
        "yearOverYear": { "current": null, "prior": null, "absoluteChange": null, "percentChange": null, "status": "gathering_data", "currentStart": null, "currentEnd": null, "priorStart": null, "priorEnd": null }
      },
      "daily": [{ "date": "2026-08-24", "actionBasedDau": 74, "averageActionReach": 27.8, "usersWithAnyAction": 74 }]
    }
  }
}
```

Each comparison value is numeric or null; `status` is either `available` or
`gathering_data`. A successful zero is numeric `0`. Missing, malformed,
disabled, or not-yet-collected blocks render safely without exceptions.

Canonical action identifiers and sources are:

| ID | Distinct-user source and rule | Raw event source/count |
|---|---|---|
| `raceParticipation` | accepted `race_participants` in eligible non-seeded, non-tournament races, one user/day | accepted participant rows first observed that ET day |
| `boxOpen` | non-review `race_powerup_events.actor_user_id` with `MYSTERY_BOX_OPENED`, one user/day | matching event rows |
| `powerupUse` | non-review race-powerup actors with `POWERUP_USED`, one user/day | matching event rows |
| `dailyRewardClaim` | non-review `daily_reward_claims.user_id`, one user/day | claim rows |
| `notificationOpen` | owner of a durable accepted delivery with `opened_at` in the ET day, one user/day | opened delivery facts, never the pruned notifications table |
| `rewardedAd` | non-review users with verified `ad_reward_grants` by ET day, one user/day | verified grant rows |
| `leaderboardView` | non-review users with durable `race_leaderboard_viewed` activation events, one user/day | matching activation events, with platform coverage |
| `raceCreated` | non-review creators of eligible non-seeded, non-tournament races created that day, one user/day | matching races |
| `raceCompleted` | non-review users completing eligible races that day, one user/day | completion facts, one per race |

All sources exclude review accounts and use half-open ET-day ranges converted
to UTC. `averageActionReach` is the sum of the nine distinct-user counts
divided by nine; the example values sum to 250, so it is 27.8.
`usersWithAnyAction` and `actionBasedDau` are the same distinct-user union when
all nine sources are available. If any source is unavailable, both are null
with `gathering_data` rather than a partial union.

The existing `engagedBoxOpenersToday` field remains in place for compatibility,
but its value must be the current ET day’s distinct durable opener count rather
than being nulled solely because the selected historical window is not mature.

## Data model / migrations

The first release uses bounded source-table queries for today, the preceding
day, and the trailing 30-day comparisons. Six-month and year-over-year
comparisons intentionally return `gathering_data` until a separately reviewed
Postgres-owned exact-user rollup is implemented. No unused migration or
unpopulated rollup table ships in this release; Redis is not the source of
truth.

Confirm indexes/query plans for the bounded first-release query:

- `user_activity_days(activity_date, user_id)`;
- `race_powerup_events(event_type, created_at, actor_user_id)`;
- activation/notification/reward tables’ existing date and user indexes;
- race participant and race status/date predicates.

Before implementation is called complete, capture `EXPLAIN (ANALYZE, BUFFERS)`
for 7d, 30d, and 90d requests. Use bounded half-open UTC predicates and one
pass per source where possible; do not multiply correlated per-day subqueries
for every action.

Six-month and year-over-year comparisons remain nullable and report
`gathering_data` until a separately reviewed exact-user rollup is added.

## Frontend plan

- Add the section to the backend allowlist and the frontend section order.
- Add defensive model projection for `dauEngagement`, accepting absent fields.
- Add a lazy Admin section with loading, loaded, empty, unavailable, disabled,
  and retry states matching existing dashboard behavior.
- Render action-based DAU before action rows. Do not render percentages or a
  denominator in action rows; comparison cards may render numeric changes and
  `GATHERING DATA` status.
- Keep the current summary row during compatibility transition; it may link to
  or duplicate the box-opener value but must not disagree.
- Keep the Android/legacy admin path functional. If it does not request the new
  section, no existing Android behavior changes.
- Verify the admin screen on iOS and Android and every admin tutorial/mirror
  that renders the real admin section.

## Backward compatibility & rollout

- Backend first, then app.
- Old app builds do not request the new section and continue receiving the
  existing legacy payload.
- New app builds tolerate an older backend that omits the new section and show
  an unavailable/retry-safe state; they must not crash or cast unchecked data.
- Existing response keys remain additive and unchanged.
- No release flag is proposed.
- No new client-bundled content is involved.

## Test plan (tests first)

### Backend integration tests

1. HTTP admin request returns the new section with exact envelope keys.
2. Unauthorized and non-admin requests preserve existing status codes.
3. Empty successful data returns numeric zero, not unavailable.
4. Missing coverage/source data degrades safely while today’s box-opener count
   still returns when its durable query has data.
5. Multiple events by one user count once in distinct-user fields.
6. ET-midnight events land on the correct calendar day.
7. Review accounts are excluded from every denominator and action count.
8. Window selection changes the daily series bounds without changing today’s
   definition.
9. Query count and plan remain within the admin endpoint budget.

### Frontend integration/widget tests

1. The section is lazy-loaded once and appears in the expected order.
2. Complete responses render action-based DAU, nine action-user counts, the
   average action reach, unique users with any action, comparisons, and daily
   rows.
3. Absent/null/malformed leaves render unavailable without exceptions.
4. A successful zero renders `0`.
5. An older backend response with no new section remains safe.
6. Both iOS dashboard and Android legacy admin paths remain navigable.

## Acceptance criteria / definition of done

- Admin can see a dedicated DAU and engagement section with the recommended
  first-release metrics.
- “Engaged box openers today” shows the durable distinct-user count whenever
  today’s query has data, even if the 7/30/90-day historical coverage is still
  collecting.
- Every comparison identifies its period ranges; action rows show counts only.
- Review accounts, duplicate events, ET boundaries, empty results, and missing
  fields are covered by tests.
- `flutter analyze`, relevant Flutter tests, backend unit tests, and dedicated
  integration tests pass.
- Both platforms are accounted for, version skew is documented, the architect
  review is complete, the manual UI checklist is handed to the owner, and the
  code review is complete.

## Open decisions for owner interview

1. Owner decision: action-based DAU is the headline; app-open-only users do
   not count.
2. Owner decision: show raw user counts, not action percentages or DAU
   denominators.
3. Owner decision: keep the nine proposed action types for the first release;
   social interaction and successful shop purchase are candidates for a later
   expansion.
4. Owner decision: add an average across all nine action-user counts and a
   union count of users with any action, clearly labeling the average as an
   estimate.
5. Owner decision: add day-over-day, week-over-week, month-over-month,
   six-month-over-six-month, and year-over-year comparisons; unavailable
   percentage changes display `GATHERING DATA`.

## Manual UI-placement test plan

1. **iOS Admin Tools metrics dashboard:** Sign in with an admin account →
   Profile → Settings → ADMIN TOOLS. Verify the new `DAU + ENGAGEMENT`
   section appears once in the fixed metrics order alongside SUMMARY, USER
   GROWTH, and the other metrics sections.
2. **Lazy behavior:** Open Admin Tools with a fresh launch, leave the section
   collapsed, then expand it. Verify the body appears only inside that section;
   collapse/reopen does not move or duplicate it.
3. **Complete data:** Verify action-based DAU appears before the nine action
   rows, followed by `AVERAGE ACTION REACH`, `USERS WITH ANY ACTION`, daily
   rows, and comparisons. Confirm no action percentages or unexplained
   denominator are inserted.
4. **Action rows:** Verify each appears once and remains grouped: race
   participation, mystery-box opens, powerup use, daily reward claims,
   notification opens, verified rewarded ads, leaderboard views, race creation,
   and race completion.
5. **Summary compatibility:** Expand SUMMARY and `DAU + ENGAGEMENT` with
   today’s box-opener data. Verify both box-opener values agree and neither is
   displaced or duplicated.
6. **Unavailable/collecting states:** Test older-backend, missing/null/
   malformed, disabled, and immature-history responses. Verify neighboring
   sections do not move; missing comparisons say `GATHERING DATA`, while a
   successful zero says `0`.
7. **Legacy fallback:** Against a backend without the metrics envelope, verify
   the existing server-update state remains in SUMMARY and CONFIG, INBOX, and
   DEBUG remain reachable. No empty DAU section leaks in.
8. **Android legacy Admin Tools:** Verify the legacy layout remains navigable
   and the iOS-only DAU section does not appear empty, duplicated, or misplaced.
9. **Route entry point:** Reach Admin Tools through Settings → ADMIN TOOLS and
   verify existing back navigation, ordering, CONFIG, INBOX, and DEBUG surfaces.

Confirmed unaffected: `lib/tutorial/tutorial_real_screens.dart`,
`lib/demo/demo_race_host.dart`, and tab tutorial surfaces do not render Admin
Tools. No admin spotlight anchors exist. Android uses the separate no-sections
legacy path and must be checked independently.

## Revision log

- Initial Phase 1 draft: separated reach, action adoption, and depth instead of
  proposing an opaque engagement score; preserved the current iOS-only observed
  DAU caveat and legacy Android compatibility.
- Gap pass 1: added ET-day semantics, review-account exclusion, duplicate-user
  counting rules, zero-vs-unavailable behavior, query/index budget, and the
  immediate box-opener compatibility requirement.
- Gap pass 2: added exact section request shape, old-client behavior, malformed
  field handling, frontend loading/empty/error states, tests-first coverage, and
  explicit owner decisions before implementation.
- Owner interview round 1: made action-based DAU the headline, removed action
  percentages and denominator display, added the nine-action average and union
  estimate, added five period-over-period comparisons, and defined
  `GATHERING DATA` for unavailable comparisons.
- Architect review: required contract, math, source-definition, bounded-query,
  performance, and compatibility changes folded in; concise review verdict was
  REVISE before these changes.
- Manual UI-placement test plan: added verbatim from the UI review; no admin
  tutorial mirror or spotlight anchor was found.
