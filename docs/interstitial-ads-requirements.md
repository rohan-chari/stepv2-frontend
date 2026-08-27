# Capped interstitial ads at natural exits

## 1. Summary and user story

Add one shared interstitial system, backed by placement-specific AdMob
interstitial units on each platform for separate performance reporting, at two
genuine navigation transitions:

1. after an accepted participant intentionally leaves an **active Race Detail**
   page and the prior races/home/tournament surface has been restored;
2. after the user exits the automatic **completed race results** summary.

As an active player, I may occasionally see a full-screen ad after I have
finished a visit/result, but never while purchasing, targeting, using a
powerup, opening boxes, revealing a reward, resolving a race, or recovering from an error. As
the operator, I can monetize these completed flows without concentrating ads on
shop spenders or tactical powerup users.

Every placement shares the same account-wide policy:

- at least **8 rolling hours** between confirmed interstitial impressions;
- at most **2 confirmed impressions per user-local calendar date**;
- at most **1 confirmed impression per foreground session**;
- no interstitial during the first **90 seconds** of a foreground session;
- no interstitial during an account's first **72 hours** after server-side
  account creation;
- no interstitial within **30 minutes after any rewarded or other full-screen
  ad was presented** in this app process;
- no waiting for an ad: an ineligible, unavailable, unloaded, failed, or
  unconfigured ad is silently skipped and the normal navigation completes.

The caps are permanent product behavior, not feature flags. The platform ad
unit IDs are required build-time configuration, like the existing rewarded ad
units; omission safely disables interstitials for that platform/build.

## 2. Product evidence and intent

The original Open All proposal was rejected after interaction review: Open All
creates inventory that users commonly intend to use immediately, so its overlay
exit is not the end of the larger task. It is also an easily avoided convenience
button and would teach users to open boxes manually. Open All is now explicitly
outside the interstitial trigger set.

The latest 30-complete-day production read-only analysis had found:

- 4,191 Open All proxy sessions, 139.7/day, across 318 users;
- 0.47 proxy sessions per overall step-active DAU-day;
- 3.31 proxy sessions per participating user-day;
- an optimistic completed-race-results opportunity ceiling around 50/day or
  0.17 per step-active DAU-day.

Those figures explain the original estimate but no longer forecast the selected
placement. There is no exact existing event for intentional Race Detail exits,
so this feature adds explicit placement analytics. The goal is low-friction
monetization, not forcing 2–3 impressions onto every DAU.

## 3. Scope

### 3.1 In scope

- iOS and Android interstitial loading and presentation using
  `google_mobile_ads`.
- Two separately reportable AdMob placements, each with required iOS and
  Android IDs:
  `ADMOB_RACE_DETAIL_EXIT_INTERSTITIAL_AD_UNIT_ID`,
  `ADMOB_RACE_RESULTS_EXIT_INTERSTITIAL_AD_UNIT_ID`, and their corresponding
  `_ANDROID` variants. A missing ID disables only that exact
  placement/platform, with no fallback to another unit.
- Initial ad serving is iOS-only. Both Android defines remain omitted until
  Android units are configured; adding them to a later build activates the
  existing paths without a feature flag or code change.
- A shared frontend coordinator that owns preload state, session identity,
  local recent-full-screen suppression, eligibility caching, presentation,
  confirmed-impression reporting, and disposal.
- Durable account-level cooldown/day/session accounting in the backend.
- Placement attribution for `race_detail_exit` and `race_results_exit` in both
  app analytics and separate AdMob reporting, while both placements consume
  the same shared backend cooldown and daily cap.
- Explicit analytics for eligible opportunities, skip reasons, show attempts,
  confirmed impressions, dismissal, and show failure.
- Safe suppression in demos/tutorials, onboarding, unauthenticated contexts,
  non-participant/pending/completed race visits, accidental short visits,
  forward-navigation exits, failure/cancelled flows, and after rewarded ads.

### 3.2 Non-goals

- No interstitial after buying a shop powerup.
- No interstitial after using a shop-sourced or race-earned powerup.
- No interstitial after Open All, a single mystery box, arbitrary navigation, app open,
  tab switching, race join/create, or before/during any reward reveal.
- No reward, coins, powerup, reroll, or gameplay value for watching.
- No new operator flag, rollout percentage, kill switch, remote frequency
  setting, or admin toggle.
- No interstitial SSV: unlike rewarded ads, no value is issued.
- No requirement to show an ad and no navigation delay while loading one.
- No production or staging deployment in the implementation phase.

## 4. Current implementation seams

- `lib/services/ad_service.dart:347-715` centralizes AdMob SDK initialization,
  build-time per-platform unit resolution, and rewarded controllers. Its
  production `FullScreenContentCallback` is at `:974`.
- `lib/screens/race_detail_screen.dart:4111-4159` builds the real Race Detail
  route and currently pops `true` directly from its header arrow. The route has
  no root `PopScope`, so Android back/iOS back-swipe can return differently.
- Race Detail is pushed from Main Shell, Races tab, Public Races, and Tournament
  Detail (`lib/screens/main_shell.dart:443-454,3578-3618`,
  `lib/screens/tabs/races_tab.dart:406-427`,
  `lib/screens/public_races_screen.dart:303-322`, and
  `lib/screens/tournament_detail_screen.dart:609-619`). All production entry
  points must share the same post-pop coordinator behavior.
- `lib/screens/main_shell.dart:2588-2737` detects unseen completed results,
  pushes `RaceResultsSummaryScreen`, and resumes after dismissal.
- `lib/screens/race_results_summary_screen.dart:31-53` accepts the payout-double
  rewarded controller and a durable pre-dismiss callback; it owns the rewarded
  flow and disposes its controller.
- `lib/services/backend_api_service.dart:2631-2650` and
  `lib/services/activation_analytics_service.dart` show the existing defensive,
  best-effort authenticated analytics transport.
- Backend `/ads` routing is mounted at `src/app.js:167-168`; rewarded SSV lives
  in `src/modules/economy/routes/ads.js`. `prisma/schema.prisma:659-693` stores
  rewarded grants and must not be repurposed for client-reported interstitials.

## 5. Behavior and presentation contract

### 5.1 Shared eligibility order

At any eligible exit, the coordinator evaluates in this order and records one
bounded skip reason where analytics is available:

1. authenticated user and token still match the coordinator's bound account;
2. current platform has a non-empty interstitial unit ID;
3. app is not in tutorial/demo/onboarding and is foreground/current-route safe;
4. the account is at least 72 hours old and this foreground session is at least
   90 seconds old;
5. no full-screen ad presentation was recorded in the prior 30 minutes;
6. this foreground session has no confirmed or locally pending interstitial;
7. an interstitial for the same bound account and exact placement-specific
   unit is loaded and ready;
8. an unexpired, placement-bound, single-use backend presentation permit is
   already held for this account/session/ad.

Failure at any step skips synchronously. It never displays an error, spinner,
toast, placeholder, or blank modal.

### 5.2 Active Race Detail exit

An eligible Race Detail visit must satisfy all of these before it primes:

- `demoMode == false` and the route is not a tutorial/preview host;
- the **first authoritative Race Detail load for this route instance** already
  reports race state `ACTIVE` and the authenticated viewer's participant status
  `ACCEPTED`; this eligibility is stamped once for the visit and can only be
  revoked, never upgraded. A route entered as newly created, pending, invited,
  spectator/preview, declined, forfeited, missing, or malformed remains
  ineligible for its entire lifetime even if join/accept/start/reload later
  changes the visible state;
- the injected visit origin is not `newlyCreated`/forced-ineligible. Creation
  entry is stamped before any fetch and always wins over a fast first payload
  that already says `ACTIVE` + `ACCEPTED`;
- the real page has remained foreground/current for at least **10 seconds**,
  preventing an accidental tap-in/tap-out from becoming an ad.

Add typed `RaceDetailRouteResult` values that distinguish `backExit` from every
actual state-changing/programmatic root exit. Present Race Detail with a typed
`MaterialPageRoute<RaceDetailRouteResult>` subclass whose `currentResult`
defaults to `backExit`. This preserves Android Back and iOS's interactive
back-swipe—including cancelled gestures—without `canPop:false`; normal platform
completion receives `backExit`, while every explicit root pop supplies its
non-default result. Migrate the current root exits at
`race_detail_screen.dart:1899,2124,2225,2361,4150,4332,7758`. Nested sheets,
dialogs, target pickers, edit routes, box screens, and powerup overlays continue
closing themselves and never create a root candidate. `PopScope` may observe
route coverage but must not disable the native gesture.

Every production caller awaits the route. Only after Race Detail has fully
popped and its prior Home/Races/Public Races/Tournament surface is current does
`backExit` create a `race_detail_exit` candidate. The screen itself never shows
the ad and Open All never directly primes, permits, or triggers one. Thus a user
may open boxes, use one or several powerups, read standings/chat, and finish
their work uninterrupted; the occasional ad belongs to leaving the page.

The header arrow's visual placement is unchanged. If route result, stamped
visit eligibility, dwell completion, restored-route identity, or auth binding
is absent/unknown, fail closed and skip.

### 5.3 Completed race results exit

After `RaceResultsSummaryScreen` has durably queued its existing acknowledgement
and popped back to `MainShell`, the shell creates a `race_results_exit`
candidate. If payout-double presented a rewarded ad during that results visit,
the shared 30-minute full-screen exclusion suppresses the interstitial. The
candidate is also suppressed when the popup was not actually presented, the
route was replaced because auth changed, onboarding is active, the user chose
the existing **Start Next Race** action, or the backend supplied a native-review
opportunity for this result. Those last two branches preserve the user's
explicit forward intent and prevent an interstitial from stacking with the
quick-create sheet or App Store/Play review prompt.

The shell resolves the existing review-opportunity and `startNext` branches
first. Only the plain return-to-shell branch attempts an already-loaded ad;
failure or absence falls straight through to the existing shell.

### 5.4 Full-screen exclusion

Add a device-local full-screen presentation tracker in the common ad layer.
Every production rewarded and interstitial controller records the instant its
SDK `onAdShowedFullScreenContent` callback fires. Interstitial presentation
consults the tracker before every attempt. The tracker persists only one UTC
timestamp in `SharedPreferences`, survives process restart and account changes,
and is pruned after it can no longer affect the 30-minute exclusion. It is not
a release control and contains no account, ad-unit, or creative identifier.

Race Detail and completed-results callers additionally retain whether any
rewarded path presented during the visit so injected test controllers and
callback timing cannot accidentally stack ads. This includes single-box and
Open All rerolls as well as payout double.

### 5.5 Session definition

A foreground session starts when the authenticated `MainShell` first becomes
active and renews after the app has remained backgrounded for at least 30
seconds, matching the existing foreground-session boundary in
`AdminMetricsTelemetryService` (`lib/services/admin_metrics_telemetry_service.dart:24-93`).
It has a cryptographically random UUID-like ID. Signing out destroys the
coordinator, loaded ad, cached eligibility, and session/account binding.

## 6. Backend API contract

These are new authenticated endpoints under the existing `/ads` router. Apply
`requireAuth` to these individual route handlers only—never router-wide—because
Google must continue calling the existing unauthenticated `/ads/ssv` callback.
Old clients never call the new handlers. The SSV callback and all rewarded
endpoints remain byte-for-byte compatible.

### 6.1 `GET /ads/interstitial/eligibility`

Query parameters:

```text
placement=race_detail_exit&sessionId=4b7c1f1e-4a5f-4bc1-a9b8-6bd986112a61&sessionStartedAt=2026-08-26T17:55:00.000Z
```

- `placement`: one of the two pinned placement enums.
- `sessionId`: required UUID.
- `sessionStartedAt`: required ISO timestamp, not in the future and no more
  than 24 hours old; used for the 90-second foreground grace.
- authenticated user identity is always derived from the token.
- cap date and next local midnight are derived from server receipt time using a
  valid raw `X-Timezone`; the client never selects its cap date. Missing or
  invalid timezone fails closed for this feature even though the general
  middleware falls back to `America/New_York` for legacy endpoints.

Eligible response, HTTP 200:

```json
{
  "eligible": true,
  "reason": null,
  "dailyCount": 0,
  "dailyLimit": 2,
  "nextEligibleAt": null,
  "capDate": "2026-08-26",
  "timeZone": "America/New_York",
  "serverTime": "2026-08-26T18:00:00.000Z"
}
```

Ineligible response uses the same shape with `eligible:false`. `reason` is one
of `invalid_timezone`, `acquisition_grace`, `session_grace`, `permit_active`,
`cooldown`, `daily_cap`, or `session_cap`. `invalid_timezone` is ineligible with
`nextEligibleAt:null`. Evaluation otherwise is:

1. account `createdAt` less than 72 hours ago => `acquisition_grace`, next at
   `createdAt + 72h`;
2. server time less than 90 seconds after `sessionStartedAt` =>
   `session_grace`, next at `sessionStartedAt + 90s`;
3. any confirmed impression for `(userId, sessionId)` => `session_cap`, next
   null because session end is client-defined;
4. any reservation-active permit for the account => `permit_active`, next at
   its `reservationUntil`;
5. two confirmed impressions plus reservation-active permits on the server-derived cap
   date => `daily_cap`, next at the next real local midnight converted to UTC;
6. latest confirmed account impression less than 8 hours ago => `cooldown`,
   next at `receivedAt + 8h`;
7. otherwise advisory eligibility is true.

DST gaps/folds use the timezone library's next actual midnight instant.
Timezone changes affect only future permits; an issued permit retains its
stamped cap date/timezone. This GET is a preload optimization, not presentation
authority. Its cache is bound to user, backend URL, session, placement,
timezone, and fetch time and expires after five minutes.

Malformed query returns HTTP 400:

```json
{"error":"Invalid interstitial eligibility request","code":"INVALID_INTERSTITIAL_REQUEST"}
```

Unauthenticated behavior remains the standard 401 contract. Unexpected errors
return the existing generic 500 shape.

### 6.2 `POST /ads/interstitial/permits`

After preload succeeds, request a permit while the approved race/result surface is
still visible:

```json
{
  "placement": "race_detail_exit",
  "sessionId": "4b7c1f1e-4a5f-4bc1-a9b8-6bd986112a61",
  "sessionStartedAt": "2026-08-26T17:55:00.000Z",
  "appVersion": "1.2.3",
  "platform": "ios"
}
```

Only the exact five keys above are accepted. Malformed bodies return HTTP 400:

```json
{"error":"Invalid interstitial permit request","code":"INVALID_INTERSTITIAL_PERMIT_REQUEST"}
```

HTTP 201:

```json
{
  "eligible": true,
  "permit": {
    "id": "72eea3de-e676-40f1-8424-cae47564d311",
    "placement": "race_detail_exit",
    "sessionId": "4b7c1f1e-4a5f-4bc1-a9b8-6bd986112a61",
    "showBy": "2026-08-26T19:03:00.000Z",
    "reservationUntil": "2026-08-27T18:03:00.000Z"
  },
  "capDate": "2026-08-26",
  "timeZone": "America/New_York",
  "serverTime": "2026-08-26T18:03:00.000Z"
}
```

Permits bind to one user/session/placement and carry two deadlines:

- `showBy = createdAt + 1 hour`: aligned with the conservative loaded-ad
  lifetime; the client may begin presentation only
  while at least 15 seconds remain;
- `reservationUntil = createdAt + 24 hours`: until confirmation, explicit
  cancellation, or this deadline, the permit continues reserving session/day
  capacity and blocks another account permit even after `showBy` passes.

The 24-hour reservation matches the confirmation ingestion window and closes
the offline cross-device race. An ineligible request returns HTTP 200 with the
§6.1 shape and `permit:null`.

Admission is atomic across both production PM2 workers. In one Postgres
transaction the command lazily upserts the user's cap row, locks it `FOR
UPDATE`, ignores reservation-expired permits, evaluates confirmed impressions plus active
reservations, and inserts at most one permit. Redis is not used: caps, permits,
and impressions are correctness state. Concurrent same-account requests
therefore yield at most one permit.

### 6.3 `POST /ads/interstitial/impressions`

Called best-effort only after SDK `onAdImpression`:

```json
{
  "eventId": "dde43b74-a957-4fba-9fe7-1f6bbac35154",
  "permitId": "72eea3de-e676-40f1-8424-cae47564d311",
  "placement": "race_detail_exit",
  "sessionId": "4b7c1f1e-4a5f-4bc1-a9b8-6bd986112a61",
  "occurredAt": "2026-08-26T18:03:12.400Z",
  "appVersion": "1.2.3",
  "platform": "ios"
}
```

Allowed placements are `race_detail_exit` and `race_results_exit`; platforms are
`ios` and `android`; timestamps may be no more than 24 hours old or 2 minutes
in the future; only exact keys are accepted. Reuse the backend's existing
`SAFE_APP_VERSION` bound (1–32 characters), accept canonical RFC 4122 UUID
versions 1–5 with valid variant bits, and reject duplicate query parameters.
The server derives user, cap date, and timezone; validates that the
unconfirmed permit belongs to that user/session/placement and that
`occurredAt` falls between permit creation and `showBy + 30 seconds` (a bounded
SDK impression-callback grace); and uses receipt time for cooldown while
retaining bounded `occurredAt` for analytics. A report may arrive any time up
to `reservationUntil`; `showBy` blocks a late show, not truthful confirmation
of an impression that occurred in time.

First receipt or idempotent replay returns HTTP 202:

```json
{
  "recorded": true,
  "idempotent": false,
  "eligible": false,
  "reason": "session_cap",
  "dailyCount": 1,
  "dailyLimit": 2,
  "nextEligibleAt": null
}
```

Confirmation atomically marks the permit confirmed and inserts the immutable
impression under the same user lock. Replaying the same event/permit for the
same user returns `idempotent:true`; duplicate SDK callbacks consume once. An
event or permit owned by another user returns generic HTTP 409. The same 409 is
returned when the same user reuses an event ID with a different permit or a
permit with a different event ID:

```json
{"error":"Interstitial event conflict","code":"INTERSTITIAL_EVENT_CONFLICT"}
```

Malformed request returns HTTP 400 with
`code: "INVALID_INTERSTITIAL_IMPRESSION"`. The frontend retains a bounded,
account/backend-partitioned retry queue for 24 hours. A 404/405 disables new
loads but never deletes a confirmed local cap tombstone or pending fact.

### 6.4 `POST /ads/interstitial/permits/:permitId/cancel`

Loaded-ad expiry, show failure, a suppressed route branch, backgrounding, or an
account change best-effort cancels an unused permit. The owner-scoped,
idempotent endpoint returns HTTP 202:

```json
{"cancelled":true}
```

Unknown, expired, confirmed, cancelled, and other-user IDs return the same
non-enumerating shape. Correctness never depends on cancellation because expiry
releases capacity.

`permitId` must be a canonical UUID. A malformed path value returns HTTP 400:

```json
{"error":"Invalid interstitial permit id","code":"INVALID_INTERSTITIAL_PERMIT_ID"}
```

## 7. Data model, migration, and backend layering

Add `InterstitialAdCap` (one row per user, used only as the admission lock),
`InterstitialAdPermit` (one-hour `showBy`, 24-hour `reservationUntil`,
stamped `capDate` as Postgres `date`, timezone, cancellation and confirmation timestamps),
and append-only `InterstitialAdImpression` (unique event ID and unique permit
ID; user, placement, cap date, timezone, session, occurred/received time,
version, platform). Add the corresponding relation lists to `User`.

Indexes must cover `(userId, receivedAt)`, `(userId, capDate)`,
`(userId, sessionId)`, `(userId, reservationUntil)`, and
`(placement, receivedAt)`.
The additive migration creates only tables, enum/constraints, FKs, and indexes;
no backfill or seed is required. Existing tables and rewarded grants are
untouched. Retain confirmed impressions for at least 400 days for annual
cohort comparison; expired/cancelled permits may be pruned after 30 days by a
future separately reviewed maintenance change, not this feature.

Backend implementation follows existing module boundaries:

- thin per-route `requireAuth` + `asyncHandler` handlers in
  `src/modules/economy/routes/ads.js`;
- bounded validators and `AppError` subclasses for the pinned 400/409 shapes;
- one file per eligibility query, permit-admission command, confirmation
  command, and cancellation command under `src/modules/economy/queries/` and
  `commands/`;
- database operations isolated in `src/modules/economy/models/`, with injected
  Prisma/timezone/clock collaborators and exports from the economy index;
- Postgres is the only cap authority; Redis is never consulted.

Move the app-version regex/validator from the analytics route into
`src/shared/validation/appVersion.js` and consume that exported helper from both
analytics and interstitial validation; do not duplicate or import a private
route constant.

## 8. Frontend implementation plan

### 8.1 Shared interstitial layer

Create `lib/services/interstitial_ad_service.dart` containing:

- typed `InterstitialPlacement` and eligibility/result models with defensive
  parsing and safe defaults;
- an injectable `InterstitialAdController` interface;
- production Google Mobile Ads loading/presentation handle adapters;
- `InterstitialAdCoordinator`, bound to one authenticated user and owning one
  loaded ad at a time;
- a bounded persistent impression retry queue and local cap tombstones
  partitioned by user and backend base URL;
- lifecycle/session renewal and account-change disposal;
- no static UI context retention.

Add build-time getters to `AdService` for four placement/platform ID slots
(Race Detail and Race Results on both iOS and Android) and a common
device-local persisted full-screen presentation tracker used by existing rewarded ads
and the new interstitial adapter. There is **no test/live fallback**: an absent
ID means unsupported. Tests inject fake loaders/controllers.

The non-blocking priming lifecycle is pinned:

1. at authenticated MainShell/session start, flush pending impression facts
   before any eligibility request but do no ad work during onboarding;
2. after a real accepted-participant active Race Detail page reaches 10 seconds
   of foreground dwell, and immediately before showing the automatic results
   summary, request advisory eligibility for that placement;
3. if eligible, load one ad without delaying either flow;
4. once the ad is ready and while the approved race/result surface remains visible,
   atomically acquire its permit;
5. at exit, show only when both the ad and matching unexpired permit are ready;
   otherwise synchronously skip;
6. refresh only on a later eligible flow entry; never poll or work from demos,
   tutorials, onboarding, unauthenticated hosts, or background execution.

Loaded ads expire using a
conservative one-hour maximum and are disposed on account, session, unit, or
lifecycle invalidation. After show/dismiss/failure, dispose the one-shot SDK
object and cancel any unused permit. Prime again only when the next approved
Race Detail/results surface begins; terminal show outcomes never preload on an
arbitrary route.

Pending confirmed-impression rows create local cap tombstones that count toward
session/day/cooldown checks immediately and after process restart. Tombstones
survive 404/405, sign-out, coordinator disposal, and reauthentication until all
cap relevance has expired; another account can never read or send them. This
closes the window where the SDK confirmed an impression but the backend report
failed. The coordinator never trusts a cached eligible response over a pending
local fact. A 404/405 disables future loads for that backend session but retains
and retries pending facts within their 24-hour ingestion window. Eligibility
cache entries are bound to user ID, backend base URL, session ID, placement,
timezone, and fetch time and expire after five minutes.

### 8.2 API service

Add defensive `BackendApiService` methods for all four endpoints. Missing/null or
unknown response fields default to ineligible. A 404/405 marks interstitial
eligibility unsupported for the current backend session; it must not affect
rewarded ads, banners, native ads, or other endpoint-support caches.

### 8.3 Main shell ownership

`MainShell` creates or accepts an injectable coordinator, binds it only while
authenticated, forwards foreground/background lifecycle transitions, and
disposes it on sign-out/widget disposal. Thread an optional constructor-
injected Race Detail navigation/coordinator collaborator through Main Shell,
Races tab, Public Races, Tournament Detail, and Race Detail's own tournament-
banner push. Do not use an inherited scope: routes pushed by the root Navigator
are sibling overlays and cannot reliably inherit a scope below Main Shell.
Demo, tutorial, and onboarding constructors omit the collaborator.

Create one shared `pushRaceDetailRoute` navigation collaborator used by Main
Shell, Races tab, Public Races, Tournament Detail, and the nested Race Detail →
Tournament Detail → Race Detail chain. It creates a visit token bound
to the current account/session/underlying route, passes the narrow visit into
`RaceDetailScreen`, awaits the typed route result, preserves each caller's
existing refresh/navigation behavior, and only then asks the coordinator to
present `race_detail_exit`. No production caller may push Race Detail directly;
structural tests enforce the closed set at `main_shell.dart:443-454,3583-3596`,
`races_tab.dart:406-426`, `public_races_screen.dart:303-322`,
`tournament_detail_screen.dart:609-619`, and the nested tournament-banner seam
at `race_detail_screen.dart:6247-6258`. Demo/tutorial construction remains
direct and uninjected.

The collaborator requires an explicit entry origin. Main Shell and Races tab
creation/Quick Create seams (`main_shell.dart:367` and `races_tab.dart:367`, plus
their resulting pushes) pass `newlyCreated`, which permanently forces that visit
ineligible before its first load. All other origins are closed enums; unknown
origin fails closed.

After `RaceResultsSummaryScreen` returns and existing acknowledgement is
durable, attempt `race_results_exit` under the rules in §5.3. The results screen
reports whether its rewarded payout controller presented fullscreen so the
shell suppresses stacking even with injected controllers.

Prime this placement before pushing the summary, but do not acquire its permit
until the ad is ready. If Start Next Race, native review, auth change, or a
rewarded presentation wins the branch, cancel the unused permit and skip.

### 8.4 Race Detail route

Add the typed route subclass/result described in §5.2 without changing header
layout. Reuse Race Detail's existing `RouteAware` / `appRouteObserver`
visibility authority (`race_detail_screen.dart:587-612`) for cumulative dwell
rather than creating a competing coverage model. Once a visit stamped eligible
from its first authoritative load accumulates 10 seconds of foreground/current-
route dwell, the injected visit primes `race_detail_exit`. Time spent in
background, under another route, or inside a fullscreen ad does not count.
Coverage loss, eligibility revocation, auth change, or disposal invalidates and
cancels in-flight load/permit work.

The page records if any rewarded ad presents during the visit. Its back arrow
and native root system-back path resolve `backExit`; every explicit root pop
uses a non-default typed result. After pop, the shared collaborator performs
only synchronous result routing, schedules each caller's existing unawaited
refresh work, verifies the underlying route and auth binding are current, and
attempts the already-ready ad in that same post-pop completion turn. No HTTP,
database, refresh, delay, or other future may sit between pop completion and
presentation; otherwise the user could begin interacting before a late ad.
All coordinator/helper errors are swallowed, including inside Quick Create, so
a successfully created race can never be reported as creation failure. Open All,
single-box flows, powerup success, sheets, dialogs, and their dismissals remain
unchanged and have no direct interstitial code.

### 8.5 Analytics

The durable impression table is the source of truth for confirmed impressions.
Extend the privacy-bounded activation analytics allowlists with best-effort
events for funnel diagnosis:

- `interstitial_opportunity`
- `interstitial_skipped`
- `interstitial_show_attempted`
- `interstitial_load_succeeded`
- `interstitial_load_failed`
- `interstitial_dismissed`
- `interstitial_show_failed`
- `race_detail_visit_started`
- `race_detail_visit_ended`
- `race_detail_back_exit`
- `race_detail_exit_eligible`

Context is allowlisted only: `placement` (`race_detail_exit` or
`race_results_exit`) and bounded enums. Race-visit events include only
`entry_surface` (`home`, `races`, `public_races`, `tournament`), `exit_kind`
(`back`, `forward`, `state_change`, `auth_replace`), `scope_result`
(`active_accepted`, `ineligible`), and `dwell_bucket` (`under_5s`, `5_9s`,
`10_59s`, `60_179s`, `180s_plus`). They never include a race ID. Add the new context
keys and values symmetrically to the frontend and backend allowlists. The
reason set is closed over `unauthenticated`, `unconfigured`, `excluded_flow`,
`recent_fullscreen`, `invalid_timezone`, `acquisition_grace`, `session_grace`, `permit_active`,
`session_cap`, `cooldown`, `daily_cap`,
`backend_unsupported`, `backend_unavailable`, `not_ready`, `show_failed`, and
`account_changed`; result is closed over `completed`, `dismissed`, `failed`,
`empty`, `abandoned`, `back_exit`, `forward_exit`, `short_visit`,
`ineligible_race`, and `rewarded_shown`. No AdMob ID, creative
ID, race ID, step/health value, arbitrary SDK error text, or user-supplied text
is sent. Unknown events continue the existing per-event-drop compatibility
behavior on older backends.

Every event passes the coordinator's bound `ownerUserId` and foreground
`sessionId` to `ActivationAnalyticsService.record`; no interstitial event may be
queued unowned. Production reporting must cover opportunity → load → permit →
attempt → impression → dismissal by placement/platform/version, impressions
per DAU and exposed-user p50/p90/p99, cap-violation audits, any rewarded-to-
interstitial interval under 30 minutes, short post-ad foreground exits, D1/D7
retention, Race Detail return rate/dwell, powerup use after box opening,
completed-results continuation, and Start Next Race rate versus
pre-release/version cohorts.

Every qualifying 10-second `backExit` records exactly one
`interstitial_opportunity` **before** checking unit configuration, app/backend
caps, permit, fill, load, or readiness. This is the demand denominator; filters
then record their bounded skip/outcome. `race_detail_visit_started/ended` are
also recorded independently of ad eligibility so short-visit avoidance and the
full dwell/exit distribution remain measurable.

### 8.6 UI and accessibility

No existing pixels, controls, labels, semantics, focus order, or animations
change. The SDK owns the full-screen creative and close affordance. App content
must already be in its stable post-flow state before presentation. Dismissal
returns to the exact route that would be visible without an ad.

## 9. Backward compatibility and rollout

1. Deploy the additive backend migration and endpoints first, after explicit
   production authorization. Old clients ignore them and all existing APIs are
   unchanged.
2. After the backend is live, release the carrying iOS and Android code in
   lockstep with the two approved iOS placement IDs baked in. Configure both
   iOS unit-level caps before the build. Android ships the same code but omits
   both Android IDs, so Android interstitials remain silently off.
3. When the two Android units are later configured, a subsequent build can
   activate them solely by supplying their defines; no flag or code change is
   required. There is no runtime rollout flag.
4. Frozen old clients continue using the new backend exactly as before.
5. A new client on an old/failed backend does not show locally capped ads; it
   skips until a later authenticated session can confirm backend support.
6. No `testOnly` content gate is required because no new bundled content is
   exposed to old clients. Build-time ID absence is configuration, not a
   release flag.

Initial iOS ad-serving release readiness requires the exact production release
commands to carry the two approved IDs:

- `ADMOB_RACE_DETAIL_EXIT_INTERSTITIAL_AD_UNIT_ID=ca-app-pub-4538901002392200/9584444570`;
- `ADMOB_RACE_RESULTS_EXIT_INTERSTITIAL_AD_UNIT_ID=ca-app-pub-4538901002392200/6032212376`.

At handoff, configure each active **interstitial ad unit** in AdMob with a
defense-in-depth frequency cap of **2 impressions per user per day**. Do not use
an app-level cap, which could throttle existing rewarded surfaces. The
app/backend permit policy remains authoritative because network-side caps may
lag or slightly overdeliver. The Android Race Detail and Race Results unit
slots are code-ready but remain unconfigured and omitted from builds until the
later Android activation.

The final release handoff must also pin `BACKEND_BASE_URL`, version/build
number, Android flavor, and all pre-existing platform-specific AdMob defines so
adding the new IDs cannot accidentally omit an existing rewarded surface.

## 10. Tests-first plan

### 10.1 Backend integration tests (write and observe failure first)

Using only a confirmed local `*_test` database and real HTTP routes:

1. new accounts receive acquisition grace and mature accounts receive
   session grace before advisory eligibility;
2. malformed session/timezone/duplicate-query/unexpected keys return pinned
   400 shapes; UUID, app-version, placement, platform, and timestamp bounds hold;
3. server derives cap date from validated timezone across UTC day boundaries,
   DST gaps/folds, and timezone changes; the client cannot choose the date;
4. one permit is issued atomically and reserves session/daily capacity;
5. two concurrent same-user permit HTTP requests across independent app/router
   instances produce exactly one permit under the Postgres lock;
6. active reservation, showBy expiry, 15-second minimum window, 30-second SDK
   callback grace, cancellation, show failure, and background-abandon
   paths release or retain capacity exactly as pinned;
7. confirmed impression returns 202 and immediately enforces session cap;
8. a new session inside 8 hours enforces cooldown;
9. after 8 hours, first and second cap-date permits are admitted while a third
   is daily-capped; next local date does not bypass rolling cooldown;
10. a device-A impression with delayed offline confirmation keeps its 24-hour
    reservation and prevents device B admission after showBy; later confirmation
    remains valid;
11. event replay and concurrent duplicate SDK callbacks are idempotent;
    cross-user event/permit collision is generic;
12. same-user mismatched event/permit reuse and impression without a matching
    owner/session/placement permit are rejected;
13. every `nextEligibleAt` reason follows the null/non-null contract, including
    missing/invalid timezone fail-closed behavior;
14. old rewarded SSV routes and reward consumption still pass unchanged;
15. old clients/authenticated endpoints remain unaffected by the additive
    schema and router changes.

Unit tests are allowed only for pure date/validation helpers whose boundary
matrix is structurally clearer there; they do not replace HTTP integration
coverage.

### 10.2 Frontend widget/integration tests (write and observe failure first)

1. an accepted participant on an active real race for at least 10 foreground
   seconds can exit through the header arrow; the prior route becomes current
   before exactly one `race_detail_exit` candidate;
2. the typed route's default `currentResult` makes Android root back and a
   completed iOS back-swipe return `backExit` without disabling interactive
   gestures; a cancelled swipe stays put; nested
   sheet/dialog/box/powerup backs close only the nested route and make no
   candidate;
3. only the first authoritative load can stamp visit eligibility; visits that
   enter as created/pending/invited/preview remain ineligible even after an
   in-place start/join/accept changes the visible state; visits under 10 seconds,
   background/nested-route-covered dwell, pending/completed races,
   spectators/previews, invitees, declined/forfeited users, demo/tutorial mode,
   and unknown/malformed race state make zero candidates;
   explicit `newlyCreated` origin wins even if its first response is already
   active/accepted;
4. Open All, single-box opens, successful/failed powerup uses, targeting,
   result overlays, and their dismissals never directly trigger; a later real
   Race Detail back exit remains eligible;
5. every actual explicit root pop (decline, team forfeit/leave, cancellation,
   Find it on Races, stamped leave, auth replacement) returns a non-ad typed
   result; in-place join/accept/edit/forfeit actions do not falsely count as
   root exits;
6. Main Shell, Races tab, Public Races, Tournament Detail, and nested Race
   Detail → Tournament Detail propagation all use the constructor-injected
   collaborator, preserve their current return behavior, and produce the same
   eligible post-pop placement; structural tests reject new direct production
   pushes while allowing demo/tutorial constructors;
7. any rewarded presentation during the Race Detail visit, including single or
   batch reroll, suppresses the later exit interstitial;
8. completed results acknowledge first, exit, then make one candidate call;
9. payout-double presentation suppresses the exit interstitial;
10. Start Next Race and native-review-opportunity branches suppress the exit
   interstitial and preserve their current sequencing;
11. post-pop presentation performs no awaited refresh/network/database work;
    existing refreshes remain scheduled, the restored route is current, and
    candidate/helper failure leaves navigation and Quick Create success
    reporting unchanged;
12. acquisition/session grace, permit expiry, one session, 8-hour cooldown,
   local daily cap, account change, and 30-minute fullscreen suppression all
   fail closed;
13. malformed/missing backend fields parse ineligible without throwing;
14. impression callback—not load, show attempt, dismissal, or show failure—is
   the only event that consumes the local cap and queues the durable fact;
15. impression queue/tombstones are bounded and user/backend-partitioned,
    survive restart/sign-out/404/405, retry transient failures, and prevent
    account A analytics or cap facts from being sent as account B;
16. all four placement/platform ID slots resolve correctly and an absent ID
    disables only that surface without borrowing a sibling, rewarded, or test
    unit;
17. existing Open All synchronization, payout-double, tutorial isolation,
    banner/native, and rewarded-ad suites remain unchanged and green;
18. structural release tests pin all four dart-define names in deployment docs
    and keep iOS/Android code releases in lockstep; telemetry tests prove visit start,
    visit end, dwell buckets, and pre-filter opportunity denominators on both
    configured and unconfigured builds.

## 11. Acceptance criteria and definition of done

- Only post-pop `race_detail_exit` and `race_results_exit` can request an
  interstitial.
- Neither placement delays or blocks normal navigation when an ad is absent.
- No purchase, powerup use, Open All/single-box reveal, outcome, nested race
  action, error, demo, tutorial, onboarding, or rewarded-ad sequence is
  interrupted.
- Atomically admitted permits guarantee an account-level 8-hour cooldown,
  2/server-derived-local-day cap, and 1/session cap across concurrent devices;
  acquisition/session grace and the persisted local 30-minute fullscreen
  exclusion also apply.
- Race Detail and Race Results use separate placement-specific IDs on each
  platform for independent AdMob reporting, while one coordinator and one
  backend policy cap them together.
- Backend changes are additive and safe for every frozen client.
- Tests were added first and failed for the intended missing behavior.
- `flutter analyze` is clean; relevant frontend tests and the full Flutter
  suite pass.
- Backend unit/integration suites pass against a confirmed test database.
- Both platform builds are verified through the no-ID compile seam; final
  production commands are not run
  until the IDs and in-the-moment deploy approval are supplied.
- Each unit actually activated in a production build is configured in AdMob
  with the 2/day unit cap first; omitted Android IDs silently disable Android.
- Required architect, game-economy, UI-placement, and post-implementation code
  reviews are complete.

## 12. Manual UI-placement test plan

### Historical rejected Open All checklist — non-authoritative

> **HISTORICAL REJECTED TEXT ONLY:** Everything until the “Authoritative
> current checklist” heading records the rejected Open All proposal. It is not
> an implementation plan, test requirement, or acceptance source.

**Manual UI-Placement Test Plan — Capped interstitial ads at natural exits**

*Elements under test:* Interstitial added after a successfully completed Open All route has fully closed back to Race Detail; it must not appear over the box reels, result bank, reroll offer, or inventory update.

*Elements under test:* Interstitial added after a completed-race results summary has fully closed back to Main Shell; it must not appear over the results summary, payout-double offer, Start Next Race flow, quick-create sheet, or native review prompt.

*Checklist*

1. **Open All — real Race Detail screen (iOS)**
   - **Get there:** Sign in with a test account that has at least two openable mystery boxes in one active race → Races → open that race → tap **OPEN ALL** → complete the reveals without using **REROLL ALL** → dismiss the completed reveal screen.
   - **Verify:** No interstitial appears before or during the reels, on the completed result bank, or before the Open All screen has disappeared. If an eligible preloaded ad is available, it appears only after Race Detail is visibly restored and action cleanup has finished. After dismissal, Race Detail remains the destination; the Open All screen is not duplicated or left underneath as the visible route.

2. **Open All — real Race Detail screen (Android)**
   - **Get there:** Repeat checkpoint 1 on Android, using both the completed screen’s close control and Android system Back after the reels have finished.
   - **Verify:** The same post-pop placement holds: no ad overlays the reveal flow, and any ad appears only after return to Race Detail. Back is still blocked while reels are loading/spinning, and the ad does not create an extra Open All or Race Detail route when dismissed.

3. **Open All — abandonment, empty, and failure exits**
   - **Get there:** Open the Open All screen and leave before tapping **OPEN ALL**; separately exercise a test response with no results and a failed open request.
   - **Verify:** Each path returns directly to Race Detail with no interstitial. The ad is absent from both its approved post-completion position and every earlier reveal/error position.

4. **Open All + rewarded Reroll All collision**
   - **Get there:** On iOS with the rewarded reroll unit configured, complete Open All → tap **REROLL ALL** and present the rewarded ad → finish the replacement reveals → close the screen.
   - **Verify:** The rewarded ad appears only at the existing reroll action. No interstitial appears after the replacement results or after return to Race Detail, and no second full-screen surface stacks behind or in front of the rewarded ad. On Android, verify the unsupported Reroll All affordance remains absent and no blank space or ad placeholder is introduced.

5. **Completed race results — plain return to Main Shell (iOS)**
   - **Get there:** Sign in with an account containing an unseen completed race → allow the automatic results summary to open → do not use payout double or **Start Next Race** → dismiss the summary normally.
   - **Verify:** No interstitial appears while results, payout, or dismissal controls are visible. If an eligible preloaded ad is available, it appears only after the results summary has fully popped and Main Shell is the restored route. Dismissing the ad leaves the user on the expected shell/tab; the results summary is not still visible or presented a second time.

6. **Completed race results — plain return to Main Shell (Android)**
   - **Get there:** Repeat checkpoint 5 on Android, including dismissal via Android system Back where allowed.
   - **Verify:** The same post-pop placement and final route hold. There is no interstitial over the summary and no duplicated summary/shell route after the ad closes.

7. **Completed race results — forward-intent and prompt branches**
   - **Get there:** From a results summary that offers **Start Next Race**, tap it; separately use seeded/test data that supplies a native-review opportunity and dismiss the summary.
   - **Verify:** **Start Next Race** proceeds directly to the quick-create sheet with no interstitial before, over, or behind it. The native App Store/Play review prompt is likewise not preceded, covered, followed immediately, or stacked with an interstitial. Returning from either branch lands on the existing expected surface without a delayed ad.

8. **Completed race results + rewarded payout-double collision**
   - **Get there:** Open an eligible results summary → present the payout-double rewarded ad → finish or dismiss the results visit.
   - **Verify:** The rewarded ad remains attached only to the payout-double action. No interstitial appears over the summary, after the summary closes, or behind the rewarded surface; return-to-shell placement is empty for this visit.

9. **Demo race tutorial**
   - **Get there:** Use a fresh-account onboarding path that launches the demo race, or Profile → Settings → re-run the demo/tutorial → progress through the real Race Detail screen and its scripted mystery-box beats.
   - **Verify:** **OPEN ALL** remains absent in `demoMode`; no interstitial, blank full-screen ad layer, loading placeholder, or post-beat ad appears anywhere in the demo. The coach chrome and scripted navigation remain the only overlays in their existing positions.

10. **Tab tutorial race-detail preview**
    - **Get there:** Profile → Settings → launch the spotlight/tab tutorial → advance to the “Powerups & boxes” race-detail preview and then complete/exit the tutorial.
    - **Verify:** The preview’s real `RaceDetailScreen` remains in `demoMode`, **OPEN ALL** remains absent, and no interstitial appears when entering or leaving the preview or tutorial. The powerups spotlight still rings its existing target, with no ad surface inserted between spotlight beats.

11. **Onboarding outside the demo**
    - **Get there:** Sign in with a fresh account → complete permission/tutorial onboarding through arrival at Main Shell; exercise both completing and skipping the tutorial where the build permits it.
    - **Verify:** No interstitial appears between onboarding pages, over the tutorial intro, on tutorial completion/skip, or on first arrival at Main Shell. No ad placeholder or extra route is visible in the onboarding stack.

12. **Full-screen placement under rotation and accessibility settings**
    - **Get there:** On a supported rotating device/emulator, reach each approved exit once in portrait and once after rotating before dismissal; repeat with large system text/display scaling and screen-reader navigation enabled.
    - **Verify:** Rotation or accessibility focus does not expose the interstitial early over Open All/results, duplicate it, or change the final destination after dismissal. The SDK’s close affordance remains reachable, and focus returns to Race Detail or Main Shell rather than to a hidden reveal/results route.

*Surfaces confirmed unaffected:* Single-box `case_opening_screen.dart` is outside the approved Open All placement; opening or leaving one box must never produce an interstitial.

*Surfaces confirmed unaffected:* Shop purchase and all individual powerup-use surfaces are outside scope; they neither host nor trigger the new full-screen placement.

*Surfaces confirmed unaffected:* Demo race tutorial reuses `RaceDetailScreen` through `demo_race_host.dart` with `demoMode: true`; Open All is already suppressed there, but the new coordinator must also remain uninjected.

*Surfaces confirmed unaffected:* The tab tutorial reuses `RaceDetailScreen` through `tutorial_real_screens.dart` with `demoMode: true`; it has no completed-results flow and must not receive the coordinator.

*Surfaces confirmed unaffected:* `case_opening_screen.dart` and `multi_case_opening_screen.dart` are reused for demo box opens, but only the production parent’s typed successful Open All return may create a candidate; the opening screens themselves must not present an interstitial.

*Surfaces confirmed unaffected:* The five production tabs and their hand-copied tutorial tab bar gain no persistent UI element or reordered chrome; the completed-results candidate belongs to `MainShell` route resumption only.

*Risks found while planning:* `MultiCaseOpeningScreen` currently pops without a typed result on close, empty response, and successful completion. Implementation must add distinct typed outcomes and return the completed outcome only after all reels commit; otherwise abandonment/empty/failure can be mistaken for the approved exit.

*Risks found while planning:* The Open All caller’s current `finally` block performs `_endAction()` and `onBoxOpened` after the route returns. The interstitial attempt must be sequenced after that cleanup, not merely after `Navigator.push` completes, or it can cover unfinished Race Detail state.

*Risks found while planning:* Reroll All needs an explicit “rewarded ad was presented” route outcome. Inferring it from whether rerolled rows exist is insufficient and could stack an interstitial after a rewarded presentation failure/success callback race.

*Risks found while planning:* `MainShell` currently resolves native review and `startNext` after the results route returns. The new candidate must be placed only after those branches are resolved and only on the plain-return branch; inserting it directly after `Navigator.push` would interrupt both forward-intent surfaces.

*Risks found while planning:* Results dismissal can follow an auth/account change. Coordinator ownership and route-current checks must prevent an ad loaded for the prior user from appearing over onboarding, sign-in, or a replacement shell.

*Risks found while planning:* Each placement requires separate iOS and Android AdMob IDs while sharing one backend cap. The unconfigured-placement/platform path must add no visible modal, delay, placeholder, or layout gap.

### Authoritative current checklist

**Manual UI-Placement Test Plan — Interstitials after Race Detail and completed-results exits**

*Elements under test:* Interstitial added only after an eligible active, accepted-participant Race Detail route has fully popped via its fixed header arrow, Android root Back, or iOS back-swipe to the production surface that opened it.

*Elements under test:* Interstitial retained only after a completed-race results summary has fully popped to Main Shell on its plain-dismiss branch.

*Elements under test:* No persistent button, banner, placeholder, or other in-page ad element is added; Open All, single-box, powerup, nested-route, demo, tutorial, onboarding, and forward-intent exits remain direct non-placements.

*Checklist*

1. **Race Detail from Home / Main Shell**
   - **Get there:** Use an account older than 72 hours and a foreground session older than 90 seconds → Home → open an active race card in which the user is accepted → keep the page foreground/current for at least 10 seconds → tap the fixed header back arrow.
   - **Verify:** Race Detail fully disappears and Home is visibly current before any interstitial appears. Dismissing the ad leaves Home current, with no duplicate Race Detail underneath or ad in the old in-page/header position. Repeat through any Home suggestion/card route and after Quick Create opens its newly created race; each must restore its own existing underlying surface and refresh behavior before the ad.

2. **Race Detail from Races tab**
   - **Get there:** Races → open an accepted active race → remain for 10 foreground seconds → exit with the header arrow.
   - **Verify:** The Races tab is restored and visibly refreshed before any interstitial appears. The ad is not shown over Race Detail, during its pop animation, or before the previous route is current; dismissal returns to the same Races shelf/state without a second detail route.

3. **Race Detail from Public Races**
   - **Get there:** Races → Public Races → open a race the user has already joined and is accepted in → remain for 10 foreground seconds → use the header arrow.
   - **Verify:** Public Races is restored before any ad and remains the destination after dismissal. Repeat with an unjoined public preview: leaving the preview must show no interstitial, either over the preview or after return.

4. **Race Detail from Tournament Detail**
   - **Get there:** Races → open a tournament → open an active matchup race in which the user is an accepted participant → remain for 10 foreground seconds → use the header arrow.
   - **Verify:** Tournament Detail, including its bracket/matchup position, is restored before any interstitial appears. Dismissing the ad returns to that same tournament surface; no ad appears over the matchup or during the route transition.

5. **Platform root-back parity**
   - **Get there:** Repeat an eligible accepted-active visit on Android using system Back, and on iOS using the native back-swipe; also repeat the fixed header-arrow exit on both platforms.
   - **Verify:** All three root exits place the interstitial only after the underlying production route is current and leave the same final destination after dismissal. The header arrow remains in its existing position and is not duplicated. A cancelled iOS swipe leaves Race Detail visible and produces no ad.

6. **Dwell, foreground, and route-current boundary**
   - **Get there:** Exit one eligible race before 10 seconds; on another visit, spend part of the 10 seconds with the app backgrounded for over 30 seconds; on another, spend part of it under a nested route and then return; finally keep Race Detail foreground/current for a full 10 seconds and leave normally.
   - **Verify:** Short, background-covered, and nested-route-covered time produces no post-pop ad. Only foreground/current Race Detail dwell counts. Returning from background never places an ad on top of Race Detail, and an eligible ad still waits for the later root back exit.

7. **Nested Race Detail routes and controls**
   - **Get there:** From one active accepted Race Detail visit, open and close representative sheets/dialogs: overflow/actions, standings or chat detail, target picker, powerup confirmation/result overlay, and any edit/share picker available to the account. Use each nested close control and platform Back.
   - **Verify:** Each nested surface closes back to Race Detail with no interstitial and does not pop the root route. No ad appears between nested surfaces, behind a dialog/sheet, or where the nested overlay was. A later eligible root back exit may show exactly one ad only after the original underlying surface is restored.

8. **Box and powerup flows, including Open All**
   - **Get there:** In an eligible Race Detail visit, open and dismiss a single box; complete and dismiss **OPEN ALL**; exercise successful and failed powerup uses plus targeting/cancellation; remain on Race Detail afterward.
   - **Verify:** No interstitial appears on entry to, during, or dismissal from any reveal, reel bank, result overlay, target picker, error, or inventory update. Open All is explicitly not a direct trigger. If the eventual root back exit is otherwise eligible, the only possible ad appears after Race Detail itself has fully popped.

9. **Rewarded-ad collision during Race Detail**
   - **Get there:** During an eligible visit, present each available Race Detail rewarded surface, including single-box reroll and batch **REROLL ALL**, then return to Race Detail and exit through root Back/header.
   - **Verify:** The rewarded ad remains attached to its existing action, with no interstitial stacked before, behind, or immediately after it. The later Race Detail exit produces no interstitial during the 30-minute full-screen suppression window. On a platform where a rewarded action is unsupported, its absent control leaves no gap or placeholder.

10. **Ineligible and forward/state-changing Race Detail exits**
    - **Get there:** Exercise pending and completed races; spectator/public preview; invited, declined, and forfeited states; then separately use **Find it on Races**, join/accept, leave, forfeit, edit/delete, and any action that programmatically leaves or replaces Race Detail.
    - **Verify:** None shows an interstitial on the page, during the transition, or after reaching its destination. **Find it on Races** still opens/selects Races directly; join/accept and destructive exits preserve their existing destinations. No forward exit is mistaken for header/system `backExit`.

11. **Completed race results — plain return**
    - **Get there:** Use an eligible account with an unseen completed race → let the automatic results summary open → do not use payout double or **Start Next Race** → dismiss normally. Repeat with Android Back and the available iOS dismissal gesture/control.
    - **Verify:** Results fully disappear and Main Shell is current before any interstitial appears. No ad covers the outcome, payout, acknowledgement, or dismissal transition. Dismissing the ad leaves the expected shell/tab current and does not reopen or duplicate the results summary.

12. **Completed results — forward and rewarded branches**
    - **Get there:** From separate results visits, tap **Start Next Race**, exercise a seeded native-review opportunity, and present the payout-double rewarded ad before dismissing.
    - **Verify:** **Start Next Race** proceeds directly to quick create with no interstitial before, over, or behind it. The App Store/Play review prompt is not stacked with or followed immediately by an interstitial. Payout double shows only its rewarded ad, and the later results exit shows no interstitial.

13. **Demo race and tutorial mirrors**
    - **Get there:** Fresh account → onboarding demo race; separately Profile → Settings → re-run the demo/tutorial; then run the tab tutorial to its real Race Detail “Powerups & boxes” preview and exit each flow using all provided navigation.
    - **Verify:** No interstitial, blank modal, loading layer, or ad placeholder appears on entering, navigating within, or leaving either real-screen mirror. Demo coach chrome remains the only demo overlay; tutorial spotlights still ring their existing targets. Neither direct `demoMode` Race Detail construction behaves like a production push source.

14. **Onboarding and auth replacement**
    - **Get there:** Complete and, where permitted, skip fresh-account onboarding; while a production Race Detail or results route is open, sign out or otherwise trigger an auth/account replacement using the available test path.
    - **Verify:** No interstitial appears between onboarding pages, on first shell arrival, over sign-in, or after auth replacement. A route/ad prepared for the previous account is never visible in the replacement account’s stack.

15. **Orientation and accessibility**
    - **Get there:** On both platforms, repeat one eligible Race Detail exit and one plain results exit after rotating where supported; repeat with large text/display scaling and VoiceOver/TalkBack enabled.
    - **Verify:** Rotation and accessibility focus do not expose the ad early, duplicate it, move/duplicate the Race Detail header arrow, or change the restored destination. The SDK close affordance is reachable, and focus returns to the restored Home/Races/Public Races/Tournament/Main Shell surface—not a hidden Race Detail or results route.

*Surfaces confirmed unaffected:* `case_opening_screen.dart` and `multi_case_opening_screen.dart` remain nested box surfaces; neither directly primes, requests, or presents an interstitial.

*Surfaces confirmed unaffected:* Powerup sheets, target pickers, result overlays, standings/chat surfaces, and Race Detail dialogs remain nested surfaces; closing them does not constitute a Race Detail exit.

*Surfaces confirmed unaffected:* Demo race tutorial directly constructs `RaceDetailScreen` from `demo_race_host.dart` with `demoMode: true`; it must remain outside the shared production navigation helper and coordinator scope.

*Surfaces confirmed unaffected:* Tab tutorial preview directly constructs `RaceDetailScreen` from `tutorial_real_screens.dart` with `demoMode: true`; its hand-copied tab chrome and spotlight anchors gain no placement.

*Surfaces confirmed unaffected:* Single-box, Open All, shop purchase, and individual powerup-use flows are not direct placements; they may only precede a later independently eligible Race Detail root back exit.

*Surfaces confirmed unaffected:* The five production tabs and tutorial tab-bar copy gain no persistent or reordered ad chrome; presentation occurs only after an approved route has popped.

*Risks found while planning:* Production Race Detail is currently pushed directly from Main Shell/Home, Quick Create, Races tab, Public Races, and Tournament Detail. Every production source must migrate to one shared awaited helper while demo/tutorial constructors stay direct; otherwise timing, typed results, refreshes, or suppression will diverge.

*Risks found while planning:* Existing callers use differing untyped/boolean results, including `true` for **Find it on Races** and state-changing exits. `RaceDetailRouteResult` must preserve each caller’s current navigation/refresh semantics while making only root back paths equal `backExit`.

*Risks found while planning:* The root `PopScope` must normalize Android Back and iOS back-swipe without consuming Back intended for a nested Navigator, sheet, dialog, box route, target picker, or powerup overlay. A cancelled iOS gesture must not emit `backExit`.

*Risks found while planning:* Eligibility depends on defensively parsed `ACTIVE` race state and the authenticated viewer’s `ACCEPTED` participant status. Missing, null, malformed, stale, or version-skewed payloads must leave the visit unprimed rather than visually treating previews/invitees as eligible.

*Risks found while planning:* The 10-second dwell timer must pause whenever Race Detail is backgrounded, not current, or covered by any nested/full-screen route, then resume without double-counting. A lifecycle-only timer would incorrectly count time under box, powerup, and rewarded surfaces.

*Risks found while planning:* The shared helper must restore each caller’s existing refresh/state behavior and verify that exact underlying route is current before presentation. Showing immediately when `push` resolves could cover pop animation, a replacement route, Quick Create cleanup, or stale Home/Races/Public/Tournament state.

*Risks found while planning:* Rewarded presentation state must propagate from every Race Detail rewarded controller—including single and batch rerolls—to the visit/helper. Merely checking the route result or reward grant can miss SDK presentation callbacks and stack a later interstitial.

*Risks found while planning:* Results presentation must remain after durable acknowledgement and after resolving Start Next Race, native review, rewarded payout, auth change, and route-current branches. Acquiring or showing directly on results pop would interrupt those existing forward surfaces.

*Risks found while planning:* The coordinator scope must exist only below authenticated production `MainShell`; onboarding, demo, tutorial, and account-replacement stacks must not inherit a loaded ad or visit token.

*Risks found while planning:* Separate placement-specific iOS and Android AdMob IDs share one backend cap. An absent, unloaded, expired, or unsupported unit must cause no delay, modal, toast, placeholder, layout gap, or borrowed sibling/rewarded/test unit.

Planner terminology resolution: the checklist above is preserved verbatim, but
its references to a coordinator “scope,” a generic shared “helper,” and root
`PopScope` normalization are implemented by the architect-approved constructor-
injected collaborator and typed route `currentResult` contract in §§5.2/8.3–8.4.
No inherited scope or gesture-disabling `PopScope` is permitted.
“Restored/refreshed before the ad” means the underlying route is current and its
existing refresh has been **scheduled**; neither network completion nor visibly
updated data is awaited. In checklist item 1, leaving a newly created Quick
Create race explicitly expects **no interstitial** because its forced-ineligible
origin is stamped before loading.

## 13. Revision log

- Initial draft: selected Open All exit and completed-results exit; excluded
  purchases and powerup uses; separated 8-hour, 2/local-day, 1/session, and
  30-minute fullscreen rules; added durable account-level accounting and
  defensive old-backend behavior.
- Gap pass 1: protected explicit post-results actions by suppressing ads before
  Start Next Race and native-review prompts; pinned per-route authentication so
  the public SSV callback cannot be broken; made delayed impression retries
  compatible with a 24-hour ingestion window; closed the analytics enums.
- Gap pass 2: pinned the five-minute eligibility cache lifetime and its complete
  account/session/date binding; made pending offline impression facts consume
  local caps across restarts; pinned the cross-user idempotency conflict shape.
- Architect review round 1 (`REVISE`): replaced advisory caps with Postgres-
  locked presentation permits; removed client authority over cap dates; added
  backend module boundaries, durable tombstones, pinned priming, owned
  analytics, concurrency tests, and explicit non-Redis correctness state.
- Game-economy review (`SOUND WITH CHANGES`): added 72-hour acquisition and
  90-second session grace, persistent cross-account fullscreen suppression,
  AdMob unit-level 2/day backstop, and load/retention/cap-audit measurement.
- UI-placement review: inserted the checklist verbatim and folded all six risks
  into typed outcomes, post-cleanup ordering, rewarded-return signals,
  forward-intent suppression, auth binding, and platform-empty behavior.
- Post-review gap pass: allowed delayed confirmation only when the recorded
  impression occurred inside its permit window; pinned UUID/app-version/query
  validation so durable retry and permit expiry do not contradict each other.
- Architect final review round 2 (`REVISE`): separated bounded `showBy`
  from a 24-hour reservation window, added minimum-show/callback grace,
  fail-closed raw timezone validation, complete permit/cancel/conflict errors,
  a shared app-version validator, flow-entry-only priming, and the delayed-
  confirmation cross-device integration case.
- Architect final review round 3: `APPROVE`, with no remaining required changes
  or suggestions.
- Placement revision from user interaction review: removed Open All as a direct
  trigger because it begins an open-boxes→use-powerups task rather than ending
  one and is an avoidable convenience action. Replaced it with post-pop exit
  from a real active Race Detail visit; retained completed-results exit.
- Revised gap pass 1: restricted Race Detail to accepted participants in active
  races after 10 foreground seconds; excluded prospects, pending/completed
  visits, forward/state-changing exits, nested routes, tutorials, and demos;
  normalized header and platform back into a typed route result.
- Revised gap pass 2: enumerated every production Race Detail push site and
  required one shared post-pop navigation helper; aligned permit `showBy` with
  the one-hour loaded-ad lifetime; made all box/powerup flows direct non-triggers
  while preserving rewarded-ad suppression for the eventual page exit.
- Revised architect review round 1 (`REVISE`): replaced the inherited scope with
  constructor injection through every production/nested route seam; preserved
  iOS swipe/Android Back via typed route `currentResult`; stamped eligibility
  only from the first authoritative load; pinned synchronous post-pop timing
  with unawaited refreshes and swallowed coordinator errors.
- Revised game-economy review (`SOUND WITH CHANGES`): added independent visit
  start/end denominators, pre-filter opportunity events, and bounded surface/
  exit/scope/dwell dimensions. Its former delayed-activation recommendation
  was later superseded by the user's immediate iOS activation decision.
- Revised UI-placement review: appended its new checklist verbatim and folded
  all route-source, native-back, first-load, dwell, restored-route, rewarded,
  result-sequencing, constructor-injection, and platform-empty risks into the
  implementation contract. Architect-approved terminology overrides are noted
  without altering the verbatim checklist.
- Revised final architect review round 2 (`REVISE`): added explicit
  `newlyCreated`/forced-ineligible origin stamping at Main Shell and Races-tab
  creation seams; clarified that restored-route refresh is scheduled but never
  awaited or required to be visibly complete before presentation.
- Revised final architect review round 3: `APPROVE`, no required changes or
  suggestions.
- Revised final game-economy review: `SOUND`, no remaining required changes.
- User dwell adjustment: reduced Race Detail foreground/current eligibility
  from 20 seconds to 10 seconds everywhere; split analytics buckets at 5/10
  seconds and updated automated/manual test boundaries. Final economy review:
  `SOUND`; no cap or measurement changes required.
- User rollout override: removed the waiting-period gate and approved immediate
  backend-first iOS activation with the two placement-specific production IDs;
  Android remains code-ready but disabled by omitted IDs until later.
