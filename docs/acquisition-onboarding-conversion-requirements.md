# Acquisition-to-activation conversion tracking and demo-first onboarding

Status: **DRAFT — product interview and architect review pending. Do not implement.**

## Summary and user story

Bara will measure the new-user journey as a durable daily cohort time series and,
only after a baseline measurement release, move the account wall for organic new
installs from app launch to the value moment immediately after the playable demo.

The product questions are:

1. How many fresh installations open Bara and reach each meaningful stage?
2. Where do people leave the sign-in, Health, demo, and first-race journey?
3. Does experiencing the game before account creation improve account creation,
   Health connection, tutorial completion, and arrival at Home?

The target organic journey is:

`first open -> welcome -> demo -> win/skip -> sign in -> identity -> Health -> real race -> Home`

Returning users with a restored session continue directly into the app. Signed-out
returning users retain an explicit sign-in path that does not force the demo.

The work ships in two app releases so the before/after comparison has a real
baseline:

- **Measurement release (flow version 1):** keep today's sign-in-first journey,
  add complete acquisition telemetry, durable daily rollups, and Admin trends.
- **Demo-first release (flow version 2):** change the organic journey, keeping
  the exact same event definitions and comparison UI.

No rollout percentage, feature flag, kill switch, or temporary behavior toggle is
introduced. `flowVersion` is immutable event data describing behavior already in
the binary, not a runtime control.

## Product principles

- The primary acquisition denominator is **first app open**, not “download.” It
  is cross-platform, represents a person who could actually see a screen, and can
  be connected to later in-app stages with a random run identifier.
- App Store first-time downloads are a separate aggregate provider series. They
  cannot be joined one-to-one to app sessions and must never be presented as an
  exact funnel stage.
- Counts and conversion rates are always shown together. Small cohorts must not
  be made to look conclusive by a percentage alone.
- A cohort is anchored on the ET date of its first-open/start event and gets 24
  elapsed hours to reach downstream stages. Incomplete cohorts do not appear as
  final trend points.
- App version, platform, and immutable flow version remain available as
  dimensions so phased store rollout does not mix the old and new experiences.
- Analytics is best-effort observability only. It never grants a reward, advances
  onboarding, authorizes Health, or controls navigation.
- “First open” means first open of the current installed app-data container. A
  reinstall or cleared app data is a new first open; it is not claimed to be a
  globally unique person or Apple first-time download.

## Scope

### In scope

1. Privacy-bounded first-open/acquisition event ingestion that works before auth.
2. A single acquisition run correlation id spanning guest and authenticated UI.
3. Daily cohort time series for the existing authenticated onboarding funnel.
4. Durable daily acquisition/onboarding aggregate rows that survive raw-event
   cleanup.
5. Admin charts/tables for daily counts, conversion, flow version, app version,
   and platform.
6. A measurement-only app release that preserves today's flow.
7. A following demo-first release for organic fresh installs.
8. Guest-safe reuse of the real deterministic demo surfaces and fake services.
9. Post-auth reconciliation of teaching completion and the existing one-time
   100-coin tutorial reward.
10. Returning-user, referral, race-share, tournament-share, offline, cancellation,
    app-kill, and reinstall handling.
11. iOS and Android support from the same Dart implementation.

### Non-goals

- Randomized A/B assignment or a runtime rollout flag.
- Treating App Store downloads as identified users or joining Apple aggregates to
  an acquisition run.
- Advertising identifiers, vendor identifiers, device fingerprinting, step
  values, routes, workouts, location, names, email, provider subject, or raw IP
  storage in acquisition telemetry.
- Replacing the existing authenticated `activation_events` contract or legacy
  Admin payload.
- A server-side demo race or any real race/powerup/settlement write during demo.
- Changing the amount, repeatability, or ledger identity of the tutorial reward.
- Moving the discoverable-identity pages relative to Health in this project;
  after auth they retain their current precedence.
- Removing the Settings spotlight tutorial.
- Claiming a statistically causal result from a simple before/after percentage.

## Current-state evidence

- Startup routes through `_SessionGate`; valid sessions go to `MainShell` and no
  session goes to `StartScreen` (`lib/main.dart`).
- `StartScreen` owns Apple/Google/reviewer auth and currently creates a separate
  `AuthService` from the root instance used for deep links
  (`lib/screens/start_screen.dart`).
- `MainShell` records `onboarding_started` only after auth and owns Health,
  teaching, first-race, referral, and Home gates (`lib/screens/main_shell.dart`).
- V3 renders Health before `OnboardingDemoRaceStep`, then the inviter/Daily race
  step (`lib/screens/onboarding_flow.dart`).
- The demo renders the real Create, Invite, Race Detail, Case Opening, profile,
  and activity surfaces against `DemoRaceApiService`, protected by a structural
  network-leak test (`lib/demo/`, `test/demo_race_network_guard_test.dart`).
- `DemoAuthService` currently proxies a real account's identity/token, while
  `DemoRaceHost` claims the reward directly from the signed-in account. Neither
  behavior is guest-safe yet (`lib/demo/demo_auth_service.dart`,
  `lib/demo/demo_race_host.dart`).
- `ActivationAnalyticsService` can queue before auth but cannot upload without a
  token. Therefore it cannot observe people who leave before sign-in
  (`lib/services/activation_analytics_service.dart`).
- Raw authenticated activation events include stage, timestamp, platform, app
  version, and onboarding session id, but are deleted after 90 days
  (`prisma/schema.prisma`, `src/modules/analytics/activationEventCleanup.js` in
  the backend repo).
- Admin's v2 onboarding block is an aggregate for one mature 24-hour iOS cohort,
  not a daily series (`src/modules/admin/adminMetricsQueries.js`). App Store
  Connect remains `not_configured` (`src/modules/admin/adminMetricsDashboard.js`).

## Exact journeys

### Restored session

1. `_SessionGate` restores the root `AuthService`.
2. The user goes directly to `MainShell`/legacy identity handling exactly as
   today.
3. No fresh-acquisition run or guest demo is created.

### Measurement release: organic fresh install, flow version 1

1. Create an acquisition run and record `first_open` once for this installed
   app data container.
2. Show today's branded sign-in screen and record `landing_viewed` and
   `sign_in_viewed` once per run.
3. Sign in, then continue through identity, Health, current demo, real race, and
   Home without reordering any screen.
4. Mirror each meaningful stage to the acquisition stream using the same run id,
   while keeping all existing authenticated activation events unchanged.

### Demo-first release: organic fresh install, flow version 2

1. Create/resume the acquisition run and show the branded welcome.
2. Primary CTA starts the offline practice race. Secondary text action says
   `Already have an account? Sign in`.
3. The guest demo uses a coherent fabricated id/name/token visible only to the
   fake services. It performs no production write.
4. Completion shows the existing win celebration and makes sign-in the next
   action. Skip/back also reaches sign-in without coins.
5. Successful auth reconciles guest state:
   - completed: claim the existing idempotent tutorial reward, then mark the
     teaching step seen;
   - skipped: mark the teaching step seen without claiming;
   - neither: leave teaching unseen so the authenticated compatibility path can
     still teach a genuinely new account that chose immediate sign-in.
6. Continue through existing discoverable identity, Health, inviter/Daily race,
   and Home. The demo must not appear a second time after successful
   reconciliation.

### Signed-out returning user

- `Already have an account? Sign in` authenticates immediately.
- A previously completed account follows server truth and goes Home.
- If the provider unexpectedly provisions a new account, teaching remains owed
  unless this acquisition run completed/skipped the guest demo; the existing
  authenticated demo remains the safe fallback.

### Referral/race/tournament intent

- The root `AuthService` remains the sole owner of pending referral/share state,
  and the same instance is passed into the unauthenticated host and sign-in UI.
- Pending race or tournament share intent makes `Sign in to join` the primary
  CTA; practice remains optional. This preserves destination intent and is no
  worse than today's authenticated onboarding delay.
- A referral-code-only install retains the code across practice and sends it in
  the optional auth provisioning fields exactly as today.
- The post-auth referral welcome, attribution, inviter-race offer, and share
  drain keep their current server authority and ordering.

### Cancellation, offline, and app kill

- Dismissing Apple/Google returns to the post-demo save/sign-in surface without
  an error toast, matching current behavior.
- Auth/network failure preserves the guest completion/skip state and pending
  reward; retry is safe.
- A completed guest run resumes at sign-in after relaunch. An unfinished demo
  restarts deterministically from its intro rather than persisting fake race
  internals.
- Reconciliation flags are cleared only after the backend calls complete or are
  proven idempotently already satisfied.
- The acquisition queue retries independently of account sign-in so abandoners
  remain measurable.

## Event definitions

New acquisition event names are exact and carry no arbitrary context:

| Event | Definition |
|---|---|
| `first_open` | Once per installed app data container, after consent/version bootstrap permits app UI. |
| `landing_viewed` | Branded unauthenticated landing first rendered for the run. |
| `demo_started` | Guest practice route successfully mounted. |
| `demo_box_opened` | First required guest-demo box committed. |
| `demo_powerup_used` | First required guest-demo powerup committed. |
| `demo_won` | Guest engine reached its deterministic win. |
| `demo_completed` | User accepted the win-card continuation. |
| `demo_skipped` | Guest left via explicit skip/back; once per run. |
| `sign_in_viewed` | Provider choices became visible. |
| `sign_in_started` | Apple or Google provider UI was requested. |
| `sign_in_succeeded` | Client received a successful auth response and durably queued the event. |
| `account_created` | Auth route created a new non-review account. Server-authored. |
| `identity_completed` | Required discoverable identity flow completed. |
| `health_cta_tapped` | Existing Health CTA definition. |
| `health_granted` | Existing Health-result granted definition; never carries steps/health payload. |
| `health_not_granted` | The run escaped/denied/failed according to existing gate outcomes. |
| `live_race_intro_viewed` | Existing inviter/Daily real-race intro became visible. |
| `home_reached` | First non-onboarding Home frame for the run. Terminal. |

`first_open`, `sign_in_succeeded`, and `account_created` are distinguished so
Admin can show both install-session conversion and actual new-account conversion.
Provider choice is intentionally not stored in the anonymous table; Apple/Google
account totals remain available from authenticated product data if needed.

The measurement release and demo-first release emit the same names. Their order
changes, and required integer `flowVersion` (`1` or `2`) makes that behavior
immutable and explicit.

The Admin stage rail is flow-specific rather than pretending the order stayed
the same:

- flow 1: first open -> landing -> sign in -> account -> identity -> Health ->
  demo -> live-race intro -> Home;
- flow 2: first open -> landing -> demo -> sign in -> account -> identity ->
  Health -> live-race intro -> Home.

## API contracts

### `POST /analytics/acquisition-events` — new, unauthenticated

Request:

```json
{
  "events": [
    {
      "id": "1724860000000-32-byte-random-suffix",
      "runId": "1724860000000-32-byte-random-suffix",
      "name": "demo_started",
      "flowVersion": 2,
      "appVersion": "2.8.0",
      "platform": "ios",
      "timestamp": "2026-09-14T15:04:05.000Z"
    }
  ]
}
```

Response:

```json
{"accepted": 1, "inserted": 1}
```

Rules:

- Batch size `1..50`, bounded request bytes, strict top-level keys, safe opaque
  ids, `platform=ios|android`, safe app-version syntax, timestamps no more than
  90 days old or five minutes in the future.
- Unknown event names soft-drop per event. Malformed known events return `400`
  without a partial write.
- `id` is the retry-idempotency key.
- The backend HMACs `runId` with a versioned server secret before persistence;
  the raw value is never stored or logged.
- Maximum accepted stages per run and ingress/IP throttling bound public abuse.
  No IP is persisted. Metrics and UI label the source best-effort/unattested.
- A missing/invalid HMAC secret returns `202 {"accepted":0,"inserted":0,
  "reason":"unavailable"}` and logs no request identifier. App behavior never
  fails because telemetry is unavailable.
- Old app versions never call the route. Old backends return 404 to a new app;
  the client retains a bounded queue and gameplay continues.

### `POST /auth/apple` and `POST /auth/google` — optional additive fields

New clients may include:

```json
{
  "acquisitionRunId": "1724860000000-32-byte-random-suffix",
  "acquisitionFlowVersion": 2
}
```

Existing auth fields and response JSON remain unchanged. Both new fields are
optional and ignored safely when absent. After successful provider verification,
the backend best-effort writes only `account_created` in the create branch under
the HMAC of this run id. Analytics failure must never fail authentication. The
write is caught independently of provisioning and has a strict bounded timeout;
no user id is stored on the acquisition row. The client queues
`sign_in_succeeded` only after receiving a success response, using a
deterministic event id, so retries cannot double-count. `account_created`
remains server-authored because only the provisioning transaction knows whether
the account was new.

A new app against an older backend still authenticates because the current auth
routes tolerate additive optional request fields. The client also records no
success itself until the auth response succeeds, so a provider cancellation is
not mislabeled.

### `GET /admin/stats?sections=dashboard-funnels&window=7d|30d|90d`

Keep every existing v2 field unchanged. Add to `onboardingFunnel`:

```json
{
  "observationHours": 24,
  "completeThroughDate": "2026-09-12",
  "finalThroughDate": null,
  "timeZone": "America/New_York",
  "seriesStatus": "available",
  "dailyCohorts": [
    {
      "date": "2026-09-12",
      "appVersion": "2.8.0",
      "platform": "ios",
      "starts": 20,
      "stages": [
        {
          "key": "health_granted",
          "count": 15,
          "startConversion": {
            "numerator": 15,
            "denominator": 20,
            "percent": 75.0
          }
        }
      ]
    }
  ]
}
```

Add recognized lazy section `dashboard-acquisition` returning:

```json
{
  "acquisitionFunnel": {
    "observationHours": 24,
    "completeThroughDate": "2026-09-12",
    "finalThroughDate": null,
    "timeZone": "America/New_York",
    "source": {"status": "collecting", "attestation": "none"},
    "dailyCohorts": [
      {
        "date": "2026-09-12",
        "platform": "ios",
        "appVersion": "2.8.0",
        "flowVersion": 2,
        "starts": 30,
        "stages": [
          {"key": "demo_completed", "count": 22,
           "startConversion": {"numerator": 22,"denominator": 30,"percent": 73.3}},
          {"key": "account_created", "count": 18,
           "startConversion": {"numerator": 18,"denominator": 30,"percent": 60.0}},
          {"key": "home_reached", "count": 14,
           "startConversion": {"numerator": 14,"denominator": 30,"percent": 46.7}}
        ]
      }
    ],
    "storeDownloads": {
      "source": {"status": "not_configured", "asOf": null},
      "daily": []
    }
  }
}
```

Rules:

- Arrays are oldest-to-newest and zero-fill complete dates/dimensions.
- Missing additive blocks/keys parse as unavailable, never zero.
- `starts` is distinct run hashes with `first_open`; every stage is distinct run
  hashes occurring from start through start+24h.
- Complete daily cohorts use full ET start dates and exclude dates whose entire
  24-hour observation window has not closed. No partial “today” point is drawn.
- `completeThroughDate` means the 24-hour outcome window has closed;
  `finalThroughDate` means the 90-day late-delivery/revision window has also
  closed. Mature-but-revisable points are visibly marked, not silently treated
  as immutable.
- The UI can pool raw numerators/denominators for a seven-day rolling line but
  must not average daily percentages.
- Existing `onboardingFunnel.stages`, legacy `/admin/stats`, schema version, and
  frozen admin-client behavior remain unchanged.

### Store-provider import (product decision pending)

If approved in this project, a backend-only scheduled importer consumes App
Store Connect Analytics Reports into daily aggregate rows. It never calls Apple
synchronously from an Admin request. Imported facts preserve provider, metric,
source date/timezone, dimensions, report/checksum identity, imported time,
completeness, and `asOf`. Corrected/mutable reports upsert idempotently. Secrets
remain in backend secret storage and raw report files are deleted after parsing.

Apple First Time Downloads/App Units appear adjacent to first-open telemetry and
are labeled as a store/account aggregate. They are never used as the exact
denominator for demo or sign-in conversion. Android store-download ingestion is
out until an equivalent approved Play reporting contract exists; Android first
open remains fully measured in-app.

## Data model and migrations

### Backend: `AcquisitionEvent`

Add a separate table; do not make authenticated `ActivationEvent.userId`
nullable.

- `id String @id` — client/server event id
- `runHash String` and `runHashVersion Int`
- `name String`
- `flowVersion Int`
- `appVersion String`
- `platform String`
- `occurredAt DateTime`
- `createdAt DateTime @default(now())`
- no user/account/provider/device/ad id and no free-form JSON context
- indexes on `(name, platform, occurredAt)`,
  `(runHashVersion, runHash, occurredAt)`, and
  `(flowVersion, appVersion, platform, occurredAt)`

Raw rows retain for 90 days. Cleanup is bounded and must not run past the last
successfully rolled-up watermark.

### Backend: durable daily rollups

Add `AcquisitionCohortDaily` and `OnboardingCohortDaily` keyed by cohort date,
platform, app version, and flow/schema version. Store:

- cohort date and timezone contract
- observation hours (`24`)
- integer start count
- fixed allowlisted stage-count JSON plus aggregate schema version
- computed time and source-complete-through time
- final/revisable status

The nightly job recomputes/upserts every cohort still represented by raw facts,
so late/offline events revise recent rows. It runs before raw cleanup. A failed
rollup prevents cleanup beyond its watermark. Once raw facts expire, older
anonymous aggregate rows remain immutable and contain no run/user identifier.

Use the backend's fenced analytics-job lease pattern rather than the older
claim-before-work cleanup pattern. Daily aggregates survive account deletion;
raw authenticated events continue cascading with the user, while anonymous raw
events have no user relationship.

On first deployment, backfill `OnboardingCohortDaily` from every retained
authenticated activation run before the normal rollup/cleanup schedule begins.
Recent authenticated rollups may revise downward after account deletion while
raw rows still exist; aggregates already final after raw expiry are anonymous
historical totals and are not restated.

Reuse the existing metric-coverage start authority with new acquisition and
onboarding-series keys. Its immutable collection-start instant determines
`collecting` versus `available`; it is not a runtime release control.

### Optional provider facts

If store import is approved, add an aggregate-only `ExternalMetricDaily` keyed
by provider, metric, source date, and canonical dimension hash. Retain at least
400 days. Store no Apple credential or raw report body.

### Frontend local state

Add an `AcquisitionStateService` rather than expanding auth-pref ownership:

- per-install `firstOpenRecorded`
- active acquisition run id and immutable flow version
- bounded anonymous event queue
- guest teaching result: `none|completed|skipped`
- tutorial reward owed boolean
- reconciliation status/attempt metadata
- terminal `homeReached`/run-closed state

All account-sensitive guest/reconciliation keys clear on successful terminal
reconciliation, explicit sign-out/account deletion, or a bounded expiry. The
per-install first-open fact does not reset on sign-out; reinstall naturally
creates a new app-data container and first-open.

Queue the deterministic `first_open` event before marking the local once-only
state. If the process dies between those writes, retry uses the same persisted
event id, so the backend primary key makes the race harmless.

## Backend implementation order

1. Write integration tests for public ingestion and strict validation.
2. Add the acquisition-event migration, HMAC helper/config validation, public
   ingestion route, bounded queue acceptance, and auth-route server events.
3. Write daily cohort query/contract tests, including ET/DST and version split.
4. Add the two daily aggregate models, fenced rollup job, cleanup watermark, and
   representative indexes only after local test `EXPLAIN (ANALYZE, BUFFERS)`.
   Register rollup ahead of the existing 2am activation cleanup and make cleanup
   verify the durable watermark before deleting covered raw facts.
5. Extend dashboard section classification with `dashboard-acquisition`; keep
   the one-dashboard-section-per-request load boundary.
6. Add optional provider import only if the owner resolves it in scope and
   supplies the required App Store Connect report credentials/permissions.
7. Run backend unit plus integration suites against a confirmed local/test DB,
   never production and never bare `npm test`.

## Frontend implementation order

### Measurement release

1. Write real-widget/integration tests for root routing and acquisition event
   emission before changing logic.
2. Make the root `AuthService` the single instance used by `_SessionGate`,
   `StartScreen`, deep links, and the later shell.
3. Add `AcquisitionStateService` and a best-effort public analytics sender that
   flushes on launch/resume without needing auth.
4. Emit flow-version-1 stages across the unchanged existing journey. Keep the
   existing authenticated activation stream byte-for-byte.
5. Add defensive acquisition/time-series DTO parsing and the new Admin section.
6. Verify both platforms, release, then collect a recommended 2–4 weeks or a
   pre-agreed minimum mature-run count before the flow release.

### Demo-first release

1. Write guest-demo and end-to-end navigation tests first.
2. Add a root `GuestOnboardingHost` above `MainShell` for unauthenticated
   acquisition state.
3. Recompose `StartScreen` into the welcome/demo entry plus an immediate sign-in
   route; preserve Apple/Google brand geometry, privacy copy, loading/error, and
   hidden reviewer access.
4. Extend `DemoAuthService` with an explicit guest identity and non-empty
   demo-only token. Keep all writes no-op and all fake-service/network-leak
   guards.
5. Add guest mode to `DemoRaceHost`: defer reward/seen writes, persist outcome,
   and route to the save/sign-in surface.
6. Reconcile reward and teaching state after auth, then enter existing identity
   and Health onboarding without replaying the demo.
7. Preserve the authenticated demo fallback for a new account that chose
   immediate sign-in and has no reconciled guest teaching result.
8. Emit flow-version-2 acquisition stages; no runtime branch can select flow 1
   in this binary.

## Admin UX

Add an `ACQUISITION → ACTIVATION` section beside the existing Onboarding Funnel.
Follow Bara's flat, dense operator style rather than generic Material charts.

- Window chips: 7D, 30D, 90D.
- Platform chips: iOS, Android, with no misleading combined store-download row.
- Flow/app-version comparison: `SIGN-IN FIRST` versus `DEMO FIRST`, showing exact
  version coverage and sample size.
- KPI row: first opens, account created, Health granted, demo completed, Home.
- Trend chart: one selected stage at a time, raw daily points plus a pooled
  seven-day conversion line; default to Home reached / first open.
- Stage rail: counts and start conversion for every stage, with skips/Health
  non-grants styled as side exits and stage order selected from the flow version.
- Daily drill-down table: date, numerator, denominator, conversion, app version.
- Data-status copy: source, complete-through date, 24h observation window,
  collecting/unavailable, and unauthenticated/unattested limitation.
- App Store downloads, if configured, appear as an adjacent dashed provider
  series with their own timezone/as-of and an explicit “not directly joinable”
  definition.

No chart draws a missing/null leaf as zero. Empty valid cohorts show zero; absent
or collecting sources show `UNAVAILABLE`/`COLLECTING`.

Implement the small chart locally with semantic labels and a table-equivalent;
do not add a chart dependency for one operator surface. Line style/point shape
and text labels must distinguish series without relying on color alone, and the
layout must remain readable at large text scale and compact phone heights.

## Backward compatibility and rollout

1. Deploy additive backend migrations/routes/contracts first.
2. Old clients never call public acquisition ingestion and continue their exact
   auth/onboarding behavior.
3. New measurement clients against an old backend lose only acquisition
   telemetry/Admin blocks; auth and onboarding continue.
4. New auth request fields are optional; old clients omit them. Existing auth
   responses are unchanged.
5. Existing authenticated activation names, validation, retention, and Admin
   aggregate fields remain intact.
6. Release iOS and Android measurement builds in lockstep with matching backend
   URL/version/build metadata.
7. Wait for the baseline maturity threshold, then ship the permanent demo-first
   binary on both platforms. There is no flag flip.
8. Compare cohorts by immutable flow version/app version and platform. Report
   phased-rollout overlap and seasonality as limitations; do not pool versions.

## Test plan — tests first

### Backend integration

- Public ingestion over real HTTP/DB: valid insert, duplicate id, mixed unknown
  name soft-drop, malformed known event rejection, exact-key checks, old/future
  timestamps, batch/body caps, HMAC raw-id absence, per-run cap, and no auth.
- Auth bridge: optional fields absent preserve old behavior; valid run writes
  server-authored success/create events; provider failure writes neither;
  analytics failure never fails auth; existing-account sign-in is not signup.
- Daily cohorts: ET/DST edges, complete dates, 24h boundary, distinct retries,
  orphan stages, replay exclusion, zero-fill, flow/app/platform split, pooled
  ratios, and 7/30/90 windows.
- Existing onboarding daily series: same mature start cohort for every stage and
  exact preservation of existing aggregate keys.
- Rollups: idempotent rerun, late event revision, lease fencing, rollup failure
  blocking cleanup, raw expiry preserving aggregates, and deletion policy.
- Query-plan fixture at representative scale for new indexes.
- Optional App Store importer: fixture parser, corrected report upsert, checksum,
  missing versus zero day, stale/completeness, timezone, and secret redaction.

### Frontend integration/widget

- `_SessionGate` real routing: restored users bypass guest; no-session users get
  the correct welcome; root/deep-link/start/shell share one `AuthService`.
- Measurement release emits flow 1 without moving any screen.
- Guest demo pumps real demo/create/invite/race/case surfaces with fabricated
  coherent identity and never reaches a production API or wallet write.
- Organic demo win/skip -> sign-in -> identity -> Health -> live race -> Home.
- Reward: complete claims once after auth; skip claims none; retry/offline and
  existing-account idempotency; Settings replay cannot double grant.
- Sign-in cancel/failure/retry and app-kill resume.
- Immediate existing-user sign-in; accidentally new account retains teaching.
- Referral, race share, and tournament share survive and preserve intended CTA.
- Apple, iOS Google availability, and Android Google-only behavior.
- Anonymous event queue flushes before auth, stays bounded, retries offline, and
  never crosses a replaced run/account.
- Defensive Admin parsing for missing, null, malformed, old, and future fields;
  chart/table empty/loading/error/collecting states.
- Existing protected tests remain; no assertion is weakened/skipped/deleted.

### Verification

- `flutter analyze`
- relevant Flutter suites first, then `flutter test`
- backend `npm run test:unit` and `npm run test:integration` against confirmed
  test Postgres only
- iOS and Android builds in lockstep for each release
- code-reviewer subagent after implementation

## Success criteria

Predeclare one primary and supporting outcomes before the demo-first release:

- **Primary:** mature first-open cohort reaching `account_created` within 24h.
- **Guardrail:** mature first-open cohort reaching `home_reached` within 24h.
- **Supporting:** demo start/completion/skip, Health grant, and post-account Home
  conversion; time to account creation and time to Home.

Read results only after both cohorts meet the agreed minimum mature-run count.
Show absolute percentage-point change, relative change, numerator/denominator,
app-version/platform coverage, and a 95% Wilson interval for the primary and
guardrail proportions. Compare full ET weeks and report rollout/seasonality;
do not compare a partial release week to a complete baseline week. A seven-day
pooled trend is descriptive, not a randomized causal estimate.

## Acceptance criteria / definition of done

- A non-signing abandoner appears in first-open and reached-stage counts without
  any account or durable device identifier; the bounded raw table contains only
  a server-HMACed random run pseudonym and expires it after 90 days.
- The Admin tab shows durable daily conversion trends and complete-through/data
  provenance, not only a rolling aggregate.
- The measurement release preserves screen order and establishes the baseline.
- The demo-first release lets an organic new user experience the deterministic
  core loop before account creation.
- Returning sessions and signed-out existing users are not forced through demo.
- No guest demo call can reach production race/economy APIs.
- The one-time 100-coin ceiling and ledger identity are unchanged.
- Referral/share intent and old app clients remain functional.
- No new release flag/runtime toggle exists.
- Raw identifiers expire; durable history contains aggregate counts only.
- Tests are written first and pass; `flutter analyze` is clean; both platforms
  are verified; required reviews/checklists are complete.

## Open product decisions for interview

1. **Baseline delay:** approve a separate measurement release and wait for a
   minimum cohort before moving sign-in, or ship measurement and flow together
   with no complete pre-auth baseline? Recommendation: separate release and
   wait for at least 100 mature first-open runs per platform or 2–4 weeks,
   whichever is later.
2. **Guest demo length:** reuse the current 12-beat Create + Invite + race demo,
   or start at the race's core box/powerup/win sequence? Recommendation: core
   race only before sign-in; creation/inviting can be taught contextually later.
3. **Intent traffic:** should race/tournament/referral links lead with immediate
   sign-in, or should every fresh install lead with practice? Recommendation:
   immediate sign-in for race/tournament destinations; referral-code-only keeps
   demo primary while preserving attribution.
4. **Download series:** include App Store Connect credentialed import in this
   project, or use first app open as the primary denominator and schedule store
   downloads separately? Recommendation: first open now; provider import as a
   separate credentialed follow-up because it is aggregate and not joinable.
5. **Guest reward presentation:** show `+100` before auth even though an
   existing account may already have claimed it, or celebrate the win first and
   show `+100` only after auth confirms a grant? Recommendation: do not promise
   coins pre-auth; use `SAVE MY WIN`, then show the existing +100 celebration
   only when the idempotent claim returns `granted:true`.

## Revision log

- **Initial draft:** combined the measurement foundation and flow change into a
  two-release, no-flag plan; separated exact first-open telemetry from aggregate
  store downloads; added guest reward reconciliation and intent-aware routing.
- **Gap pass 1:** corrected first-open semantics for reinstalls, made the two
  flow orders explicit, removed the impossible promise that analytics would add
  zero auth latency while keeping auth fail-open, added deterministic success
  retry, historical rollup backfill, deletion semantics, coverage authority,
  first-open crash idempotency, and the rollup-before-cleanup requirement.
- **Gap pass 2:** removed duplicate client/server sign-in-success ownership,
  distinguished 24-hour cohort maturity from 90-day data finality, required an
  accessible dependency-free chart, tightened full-week/Wilson comparison
  reporting, and surfaced the pre-auth reward-promise ambiguity.
