# API contract and page-payload cleanup requirements

Date: 2026-08-13  
Status: ready for user approval — architecture APPROVE, game/economy SOUND  
Source audit: `docs/api-page-payload-audit.md`

## 1. Summary and user story

The app must keep the same screens, data freshness, actions, game rules, odds,
and error behavior while asking the backend for only the data each page uses.
The highest-impact work is the active race page, which can currently issue
about 32 GETs per foreground minute and repeatedly hydrates every participant's
cosmetics. Tournament detail also blocks first paint on one deep graph that
hydrates participant cosmetics repeatedly even though its bracket uses only
names, photos, IDs, totals, and effect state. Home, Friends, Shop, Get Coins,
Public Races, Ranked V2, auth restore, and Profile contain narrower overfetch or
duplicate-read paths.

The same performance-only rollout also reduces the live race-resolution load
that the production monitor exposed. “Resolution” here means recalculating an
ACTIVE race, not completing it: only two races completed during the monitored
four-hour window while the worker ran 8,056 full-race passes. The optimized
design must eliminate the intentional progress-refresh double pass, classify
dirty work by cause/scope, coalesce sync bursts without starving correctness,
bulk-write participant totals safely, and move already-decided transport/cache work off
the core resolution latency path.

As a user, opening or using these pages should feel faster during traffic
spikes, without any visible feature disappearing and without stale gameplay
state. As an operator, request count, SQL count, response bytes, and p95 latency
must be measurable per optimized contract so the rollout can be evaluated and
rolled back independently.

Current source anchors (line numbers at draft time) include:

- active race entry/progress/poll/inventory orchestration in
  `lib/screens/race_detail_screen.dart:756`, `:850`, `:995`, and `:1898`;
- independent chat and activity pollers in
  `lib/services/race_chat_service.dart:119`/`:175`/`:203` and
  `lib/services/race_feed_service.dart:85`/`:141`/`:166`;
- the matching Flutter calls in `lib/services/backend_api_service.dart:3085`,
  `:3310`, `:3404`, and `:3483`;
- Home loading/catalog work in `lib/screens/main_shell.dart:1826` and `:2481`;
- race reads in backend `src/modules/races/routes.js:836`, `:995`, and `:1411`,
  `queries/getRaceDetails.js`, and `queries/getRaceProgress.js`;
- resolution enqueue/claim/full scoring/post-commit paths in backend
  `src/modules/races/services/enqueueRaceResolution.js:6`,
  `queries/getRaceProgress.js:1356`,
  `jobs/raceResolutionQueueV2.js:191`,
  `services/raceStateResolution.js:633`, and
  `services/raceProgressSideEffects.js:1`;
- message access/serialization in backend
  `src/modules/social/queries/getRaceMessages.js:139`;
- Tournament Detail load/poll/action reuse in
  `lib/screens/tournament_detail_screen.dart:107`/`:168`/`:231`, its bracket
  consumer in `lib/widgets/tournament_bracket_board.dart:487`, and the deep
  backend graph/serializer in `src/modules/tournaments/models/tournament.js:3`
  and `src/modules/tournaments/queries/serializeTournament.js:97`/`:172`;
- friends, auth, shop, ranked, and stats reads in backend
  `src/modules/social/routes/friends.js:112`/`:138`,
  `src/modules/users/routes.js:454`/`:532`, `src/routes/shop.js:155`,
  `src/modules/ranked/routes.js:21`, and `src/modules/steps/routes/steps.js:253`.

## 2. Scope

This spec implements the whole prioritized cleanup from the source audit:

1. one race message/activity poll instead of two, with lean authorization and
   Chat message bodies lazy-loaded only after the user opens Chat;
2. one race-open bootstrap and a lean, response-compatible progress poll;
3. compact shared friends state with no step reads or sync-push fanout;
4. compact Home presentation/friends data and a complete compact auth restore;
5. a compact Get Coins status;
6. one Public Races browser payload;
7. a compact Ranked V2 member projection;
8. one parallel Shop bootstrap and mutation-local state patching;
9. SQL-side Profile aggregates;
10. ETag revalidation for version policy and powerup copy;
11. a lean tournament-detail projection plus mutation-response reuse;
12. reason-aware, coalesced race resolution with a single display computation,
    ordered bulk writes, and durable post-commit tasks;
13. endpoint/worker request, SQL, byte, latency, queue, and CPU evidence.

All phases are performance-only. They may land behind independent server flags,
but the public compact contracts and legacy fallbacks are one versioned design.

## 3. Non-goals

- No UI copy, layout, animation, navigation, empty state, or polling-freshness
  change. The sole intentional loading-state change is that a capable backend
  does not preload hidden Chat bodies: the first Chat-tab tap may show the
  existing Chat loading state while its first network request completes.
- No race scoring, settlement, placement, powerup, mystery-box, odds, reward,
  price, inventory, eligibility, privacy, or notification semantic change.
- No removal or repurposing of an existing field or endpoint.
- No pagination redesign for older race messages. `loadMore` continues to use
  the existing per-kind cursor endpoint.
- No tournament-detail delta/revision protocol. The existing 60-second
  freshness remains; it uses a lean complete snapshot rather than a delta.
- No leaderboard cosmetic cleanup; that UI genuinely renders character
  presentation.
- No process split, infrastructure resize, database-pool increase, destructive
  cleanup, or concurrency increase. This expansion permits only the additive
  queue-metadata, scoring-input-token, and post-delivery-task migration in §6.
- No production deploy under this approval. Backend implementation, tests, and
  commit stop before production and require fresh deploy confirmation under the
  backend repository rules.

## 4. Contract conventions

### 4.1 Versioning and opt-in

- Compact views use a lowercase, immutable contract name ending in `-v1`.
- Existing endpoints default to their byte-compatible legacy behavior when the
  opt-in query is absent or unknown.
- New endpoints are additive. The Flutter client caches only a definite 404 as
  unsupported for the current process and then uses the legacy path.
- Every implementation is gated by one exact AppSetting that is enabled only by
  the literal boolean `true` and otherwise defaults false:
  `apiRaceBootstrapV1Enabled`, `apiRaceProgressCompactV1Enabled`,
  `apiRaceMessageStreamsV1Enabled`, `apiFriendsSummaryV1Enabled`,
  `apiAuthShellV1Enabled`, `apiHomeShellV1Enabled`,
  `apiGetCoinsV1Enabled`, `apiPublicRaceBrowserV1Enabled`,
  `apiRankedV2CompactV1Enabled`, `apiProfileStatsV1Enabled`,
  `apiShopBootstrapV1Enabled`, `apiStaticEtagsV1Enabled`, and
  `apiTournamentDetailV1Enabled`, plus the independent body-free cache flag
  `apiRaceChatWatermarkCacheV1Enabled`, and the five backend-only resolution
  flags `raceResolutionDisplayArtifactReuseV1Enabled`,
  `raceResolutionReasonAwareV1Enabled`,
  `raceResolutionBurstCoalescingV1Enabled`,
  `raceResolutionBulkWriteV1Enabled`, and
  `raceResolutionPostTasksV1Enabled`.
  A disabled new endpoint returns `404`; a disabled compact view dispatches to
  its legacy response with no compact marker. Flag read failure is flag-off.
  All nineteen keys are declared in `src/shared/config/appSettings.js`'s
  `KNOWN_FLAGS` with false defaults and comments; the admin settings surface
  may expose them through its existing generic flag mechanism, but no seed or
  migration enables them.
- A compact response includes a top-level `contract` marker. Every new field is
  parsed defensively. Missing, null, or malformed optional blocks trigger the
  named legacy fallback or retain the last good state; they never crash.
- Existing `X-Client-Features`, `X-Release-Channel`, `X-Timezone`, auth, seeded
  bucket, team-race, remote-asset, and ad gates remain authoritative. A compact
  view cannot broaden what a viewer may see or do.
- Dates remain ISO-8601 strings in the exact format their legacy serializer
  currently emits. JSON numbers, booleans, nullability, ordering, and error
  status codes remain unchanged unless explicitly stated below.

### 4.2 Legacy parity rule

For each compact component, the canonical assertion is deep equality with the
corresponding legacy response after removing only:

- the compact response's `contract` and component wrapper fields; and
- fields explicitly listed as omitted because the current screen does not use
  them.

The comparison uses the same authenticated viewer, capability headers, release
channel, timezone, database snapshot, and clock. Existing serializers and
visibility predicates must be shared rather than copied.

### 4.3 Failure behavior

- Authentication/authorization failures stay `401`/`403`; not-found stays
  `404`; validation stays `400`; unexpected failures stay `500` unless a
  bootstrap explicitly marks an optional component unresolved.
- A timeout, `5xx`, invalid JSON, or malformed compact response does not mark an
  endpoint permanently unsupported.
- A legacy superset returned by an existing endpoint is consumed directly when
  it already contains everything that screen needs; absence of a marker alone
  is not a reason to repeat that request. The frontend calls a legacy fallback
  only for a definite new-endpoint `404`, a required block absent from an
  ignored compact view, or a component whose `resolved` flag is `false`. It does
  not double-load a healthy compact result.

## 5. API contracts

### 5.1 Race-open bootstrap

`GET /races/:raceId/bootstrap`

Request:

```http
Authorization: Bearer <session token>
X-Client-Features: <existing tokens>
X-Release-Channel: <existing channel>
X-Timezone: <existing zone>
```

No body or required query parameters.

Success (`200`):

```json
{
  "contract": "race-bootstrap-v1",
  "race": { "id": "race-id", "...": "exact GET /races/:raceId fields" },
  "progress": { "...": "exact GET /races/:raceId/progress.progress fields" },
  "progressError": null,
  "globalPowerupInventory": {
    "items": [{ "powerupType": "TRAIL_MINE", "quantity": 2 }]
  }
}
```

Rules:

- `race` is exactly the existing race-detail object for this viewer.
- For `ACTIVE`, `progress` is exactly the existing `progress` object. If that
  optional component fails after detail authorization succeeds, the endpoint
  still returns `200`, sets `progress: null`, and returns
  `progressError: {"code":"PROGRESS_UNAVAILABLE"}`. The error is logged; no
  internal message or stack is returned.
- For non-`ACTIVE`, `progress`, `progressError`, and
  `globalPowerupInventory` are `null`, matching the current screen's decision
  not to start active polling/inventory work.
- For `ACTIVE`, inventory is the exact current `GET /powerups/inventory`
  envelope. An inventory-only failure returns `null` and does not fail details.
- Detail authorization runs before optional component work. Decliners,
  nonparticipants, tournament spectators, seeded private buckets, and all
  capability variants retain existing behavior.
- State reconciliation/expiry work currently required by progress still runs
  once. The bootstrap must not run it twice.
- The bootstrap first loads a lean access/status context. For an active race it
  performs the same progress reconciliation once, then builds both detail and
  progress from the resulting post-reconciliation state; for a non-active race
  it skips progress work. This prevents an internally contradictory bootstrap
  such as `race.status=ACTIVE` beside completed progress. Detail and progress
  share one race context and one bulk participant-presentation load rather than
  independently calling the deep `Race.findById` graph. This ordering is pinned
  by a race-completes-during-bootstrap integration test.

Errors are exactly those from current race details: `401`, `403`, `404`, and
`500` with the existing safe `{error, code?}` shape.

Frontend fallback: on a definite bootstrap `404`, perform today's parallel
details/progress prefetch and initial global-inventory load. On a successful
bootstrap with `progress: null` for an active race, render details and the
existing progress error/retry state; do not refetch automatically in the same
frame.

### 5.2 Lean progress view

`GET /races/:raceId/progress?view=compact-v1`

Success adds one capability-scoped top-level block while leaving `progress`
exactly unchanged:

```json
{
  "contract": "race-progress-compact-v1",
  "progress": { "...": "unchanged existing fields" },
  "globalPowerupInventory": {
    "items": [{ "powerupType": "TRAIL_MINE", "quantity": 2 }]
  }
}
```

The optimization is internal: authorize and compute from explicit race,
participant, effect, inventory, step, and presentation projections; bulk-load
presentation; preserve current reconciliation, odds, illusion, team,
tournament, finish, and error behavior. Unknown `view` values use the legacy
implementation. The global inventory block equals the current standalone
endpoint and preserves its 30-second cross-device/background-grant freshness
without another HTTP request. Its read runs beside the progress builder; a
failure returns `null` without failing progress, and Flutter applies the current
standalone-failure behavior. If the marker/block is absent, legacy-mode Flutter
continues its standalone inventory refresh after progress, so independently
rolling the progress flag off cannot stale the UI.

The compact/bootstrap request path is read-only with respect to bulk
`race_participants` totals and placement persistence. It must not clone or add a
request-path bulk writer. Any new bulk persistence is routed through the
existing race-keyed, lease/fence-protected resolution worker; settlement keeps
its existing direct-Postgres writer. The legacy flag-off progress path remains
behavior-compatible even where it retains its historical write-back.

### 5.3 Lazy Chat and combined race message streams

`GET /races/:raceId/message-streams?limit=50&includeUser=false`

`includeUser=false` is the race-entry/default-Activity mode for the new app.
Only the exact lowercase query value `false` disables USER message bodies;
absent, empty, or any other value defaults to `true` so the endpoint's original
combined behavior remains the conservative contract.

Success (`200`):

```json
{
  "contract": "race-message-streams-v1",
  "requested": { "USER": false, "SYSTEM": true },
  "resolved": { "USER": false, "SYSTEM": true },
  "streams": {
    "USER": null,
    "SYSTEM": {
      "messages": [{ "id": "event-id", "kind": "SYSTEM", "body": "...", "createdAt": "2026-08-13T12:00:00.000Z" }],
      "nextCursor": null
    }
  },
  "chatWatermark": {
    "latestId": "message-id",
    "latestAt": "2026-08-13T12:00:00.000Z",
    "recentIds": ["message-id"]
  },
  "watermarkError": null,
  "errors": { "USER": null, "SYSTEM": null }
}
```

When `includeUser=true`, `requested.USER` and `resolved.USER` are true and
`streams.USER` has the original combined-contract shape: the exact existing
USER serializer output and independent `nextCursor`. Each message object is
the exact existing per-kind serializer output, including all optional
sender/event/powerup/actor/target fields and current stealth redaction. Each
requested stream is newest-first and capped independently by `limit`.

`chatWatermark` identifies the newest non-deleted USER message using the stable
`(createdAt,id)` ordering. Activity-only mode carries the IDs of the newest 50
USER rows; combined mode carries exactly the IDs already present in its
normalized-limit USER top page. It contains no body or sender presentation.
`recentIds`—not an ID
ordering assumption—is the unread authority: Flutter remembers every ID seen
during the mounted screen and sets unread only when a later watermark contains
an unseen top-page ID. This intentionally matches today's `refreshTop` ID-set
difference semantics, including deletion/page-boundary behavior, while ensuring
equal-timestamp UUIDs cannot be missed. No messages returns
`{latestId:null,latestAt:null,recentIds:[]}`. In `includeUser=false` mode,
the backend must not read USER message bodies, hydrate USER sender
presentation, or join any participant cosmetics. It performs only the shared
lean access check, the SYSTEM work, and a bounded indexed `id,createdAt` lookup.
When `includeUser=true`, the watermark is derived from the already-returned
USER snapshot rather than issuing a duplicate query. A
watermark-only failure leaves SYSTEM usable, returns `chatWatermark:null`, sets
`watermarkError={"code":"STREAM_UNAVAILABLE"}`, and does not turn Chat on.
`limit` keeps the current default `50` and maximum `100` validation. This top
snapshot accepts no cursor; older pagination continues through
`GET /races/:raceId/messages?kind=USER|SYSTEM&cursor=...`.

Exact normalization matches the current effective two-stage legacy route:
absent, empty, nonnumeric/NaN, negative infinity, or numeric zero `limit`
becomes `50`; positive infinity (including parsed `1e999`) and any finite value
over `100` become `100`; a negative finite value becomes `1`; and a positive
fraction is truncated toward zero and clamped to `1..100`. All return `200`, not
a validation error. A supplied `cursor` is ignored by this top-snapshot endpoint;
only the legacy per-kind endpoint paginates. Each stream's `nextCursor` exactly
equals the equivalent legacy top-page cursor.

Activity-only polling must not turn that bounded lookup into a hot Postgres read
every five seconds. Under the independent
`apiRaceChatWatermarkCacheV1Enabled` flag, it uses a separate, body-free Redis
surface. Its exact logical data key is
`v1:race:msgwatermark:{raceId}:USER`; the cache wrapper prepends the existing
environment prefix (`p:`/`s:`/`t:`). The key stores only the newest 50
`{id,createdAt}` USER rows (or the equivalent `latestId`, `latestAt`, and
`recentIds` projection), has the existing message-cache 15-minute TTL as a
backstop, and never stores or reads a body, sender ID, sender presentation, or
access result. It may share the existing race-message version/fence key, but it
must have a distinct data key from the existing full USER-message cache. The
existing post-commit USER send, USER soft-delete, and race-membership/access
mutation invalidation seams atomically advance the version and delete both the
full USER list and body-free watermark data keys. A cold/missed cache rebuilds
from the bounded indexed `id,createdAt` Postgres query using the same
WATCH/version retry discipline as the current message cache so an invalidation
cannot be overwritten by a stale fill. Cache-flag off, Redis unset, timeout,
parse failure, or exhausted retry falls back to that bounded Postgres lookup
without changing the public response. Production must not enable message
streams without also enabling this cache flag; the separate rollback flag is
retained so Redis failures can be isolated safely.

The handler performs one lean access lookup and then starts only the requested
stream work. Cached reads must not hydrate race cosmetics. Authorization/error
behavior is identical to the two legacy reads. After access succeeds, requested
branches are isolated exactly like today's independent services: one failing
branch returns `null`, sets its `resolved` flag false, and sets only its error
to `{"code":"STREAM_UNAVAILABLE"}` while the other branch still succeeds. An
unrequested USER branch is `requested:false`, `resolved:false`, `streams:null`,
and `errors:null`; it is not a failure. Watermark failure is independent through
`watermarkError`. If every requested branch plus the watermark fails, the
endpoint returns the existing safe `500` envelope.

Flutter owns one five-second foreground timer per race screen. On race entry it
initializes Activity only and requests `includeUser=false`; it does not create
`RaceChatService`, load USER rows, or start USER polling. The first successful
initial watermark ID set becomes the no-unread baseline, matching today's
successful hidden Chat load, and the client performs the same non-blocking
`POST /races/:id/chat/read` acknowledgement. If the initial stream attempt
returns no valid watermark, Flutter records an initialized empty baseline and
still sends that acknowledgement, because today's `loadInitial()` swallows its
failure before `markRead`; the first later successful non-empty watermark then
sets unread. After initialization, missing/malformed watermark state retains
the last baseline/dot and never invents or clears unread. A later unseen
watermark ID while Chat remains unopened sets the same unread dot without
downloading messages.

The first Chat-tab tap creates Chat state, immediately calls the same endpoint
with `includeUser=true`, clears/persists the unread state exactly as today, and
keeps using that combined mode for the rest of the mounted screen. Completed
races load Activity once, leave Chat unloaded until its first tap, and never
poll. On a capable backend this tap may briefly show the existing Chat loading
state while the first USER request completes; this is the one accepted visible
tradeoff for eliminating hidden Chat work. The existing composer remains
available to an eligible user during that load; a send uses the current
optimistic path and the arriving initial snapshot must merge without dropping
or duplicating it. An initial error shows the existing retry panel while
preserving composer/post eligibility. Optimistic sends, ordering, retry states,
pagination, lifecycle pause,
and completed-race read-only behavior remain unchanged. Progress success no
longer triggers either message refresh. A failed requested branch keeps its
last good rows (or existing initial error state) until the next interval and
does not immediately create a second request.

A definite new-endpoint `404` is cached as unsupported for this process. An old
backend cannot provide the cheap watermark needed to preserve the existing
hidden-tab unread dot, so fallback deliberately restores today's two legacy
services: it initializes hidden Chat, loads USER and SYSTEM, and polls both.
Lazy Chat is therefore guaranteed on the capable backend deployed before the
new app; compatibility mode prioritizes unchanged UX over request savings. A
`200` without the exact marker/requested/streams shape is a transient malformed
response, preserves last good state, and does not permanently downgrade. The
coordinator coalesces overlapping timer/action/resume refreshes, applies only
the newest mounted-generation result, never lets an in-flight Activity-only
response downgrade a mounted screen that has switched to combined mode, and
never starts a new poll while one is in flight.

### 5.4 Compact friends view

`GET /friends?view=summary-v1`

Success (`200`):

```json
{
  "contract": "friends-summary-v1",
  "incomingFriendRequests": 1,
  "friends": [
    {
      "id": "user-id",
      "displayName": "Ari",
      "profilePhotoUrl": null,
      "friendshipId": "friendship-id",
      "teamRaceEligible": true
    }
  ],
  "pending": {
    "incoming": [{ "friendshipId": "id", "user": { "id": "id", "displayName": "Sam", "profilePhotoUrl": null } }],
    "outgoing": [{ "friendshipId": "id", "user": { "id": "id", "displayName": "Jo", "profilePhotoUrl": null } }]
  }
}
```

Ordering and pending shapes equal `GET /friends`.
`incomingFriendRequests` equals `pending.incoming.length` from the same read and
lets AuthService update its badge without a second `/auth/me`. The compact rows
omit `animal`, `accessories`, `steps`, and `stepGoal`. This path never queries
daily steps and never calls `requestStepSyncForUsers`. An older backend ignores
`view`, returns the legacy superset, and the new parser uses the same five
accepted-friend fields safely.

MainShell owns this snapshot and passes it to Home, Friends, invite pickers, and
request sheets. The repository coalesces concurrent callers and reuses a success
only within a one-second duplicate-trigger window; it is not a background TTL.
Every existing initial-load, tab-reveal, pull-to-refresh, resume/step-sync, and
mutation trigger still asks for fresh state unless it overlaps that window. A
friend mutation invalidates/refetches this snapshot exactly once; it
does not additionally call `/friends/steps` or `/auth/me` unless the mutation
itself changed an own-user field. The snapshot updates AuthService's incoming
count from the explicit count, or defensively from the incoming list length when
the count is absent.

### 5.5 Compact auth restore and refresh

`GET /auth/session?view=shell-v1` and `GET /auth/me?view=shell-v1`

Session success (`200`):

```json
{
  "contract": "auth-shell-v1",
  "sessionToken": "jwt",
  "user": {
    "id": "user-id",
    "email": "ari@example.com",
    "displayName": "Ari",
    "firstName": "Ari",
    "lastName": null,
    "profilePhotoUrl": null,
    "profilePhotoPromptDismissedAt": null,
    "referredByCode": null,
    "nameSetupOnboardingRequired": false,
    "nameSetupCompletedAt": null,
    "renameChipShownCount": 0,
    "renameChipDismissedAt": null,
    "isAdmin": false,
    "coins": 100,
    "heldCoins": 0,
    "firstRaceOnboardingSeen": true,
    "tutorialOnboardingSeen": true,
    "hiddenFromLeaderboard": false,
    "autoJoinFeaturedRaces": false,
    "incomingFriendRequests": 0,
    "characterPowersEnabled": false,
    "featureFlags": {
      "bannerAdsEnabled": false,
      "dualBoxBannersEnabled": false,
      "teamRacesEnabled": true,
      "onboardingV2Enabled": false,
      "onboardingV3Enabled": false,
      "onboardingInviteCodeEnabled": true,
      "openUserRaceDiscoveryEnabled": false,
      "quickCreateRaceCtaEnabled": false,
      "setupInviteCodePromptEnabled": false,
      "racesInviteDecisionGateEnabled": false,
      "quickRaceShareAutoFriendEnabled": false,
      "tutorialMandatoryEnabled": false,
      "stepSampleBucketMinutes": 60
    }
  }
}
```

`GET /auth/me?view=shell-v1` returns the same `contract` and `user`, without
`sessionToken`. `email` remains present because MainShell passes it to the
current Profile screen; this preserves visible account information while still
omitting provider identifiers and unused scalars. `stepSampleBucketMinutes`
follows its existing version gate and may be omitted. All nullable fields remain
present where missing-vs-null is an existing capability signal. No provider ID,
normalized search field, server timestamp/bookkeeping column, legacy
`stepGoal`, or other Prisma scalar is returned.

The compact assembler shares current runtime-flag, admin, held-coin, and
incoming-request logic. It loads one coherent AppSetting snapshot instead of
awaiting one setting read per flag, while preserving every declared default and
app-version omission. Compact auth payloads never share a full-response Redis
key with legacy `/auth/me`: use a `shell-v1` contract variant in the key (or
cache only a raw internal core and serialize per contract after retrieval).
Legacy and compact warm reads therefore cannot cross-serve shapes during mixed
traffic or rolling deploys. Every existing auth invalidation deletes both
variants. After a compact session restore, Home skips its
immediate duplicate `/auth/me`; later explicit own-user refreshes use the
compact view. If the marker is absent, the broad user is still accepted and the
legacy Home refresh remains enabled. Compact `/auth/me` receiving a legacy
broad response uses it directly and does not repeat the same request.

### 5.6 Home shell additions

The existing request adds `view=shell-v1` while retaining all current query
parameters:

`GET /home/race-card?view=shell-v1&homeActiveRaces=1&localDate=YYYY-MM-DD[&homePersistedTotals=1]`

Its existing top-level response is unchanged and gains:

```json
{
  "contract": "home-shell-v1",
  "resolved": { "presentation": true, "friends": true },
  "presentation": {
    "coins": 100,
    "equipped": { "HEAD": { "id": "item-id", "sku": "...", "assetKey": "...", "renderMetadata": {} } },
    "cape": { "id": "cape-id", "sku": "...", "assetKey": "...", "renderMetadata": {}, "bobble": null }
  },
  "friends": { "contract": "friends-summary-v1", "incomingFriendRequests": 0, "friends": [], "pending": { "incoming": [], "outgoing": [] } }
}
```

`equipped` uses the current shop serializer and channel/characters/remote-assets
visibility. `cape` is the currently visible cape catalog row needed by Home's
renderer, or `null`; it must not require loading every catalog item. Home no
longer fetches `/shop/catalog` or `/friends/steps` when both blocks validate.
The core race-card response remains mandatory. Presentation/friends loads start
in parallel with independent error isolation: a failure returns that block as
`null`, sets its `resolved` value false, and never fails the race card. If a
block is absent/malformed/unresolved, only that legacy request runs.

### 5.7 Get Coins compact status

`GET /daily-reward/status?view=get-coins-v1&localDate=YYYY-MM-DD`

Success (`200`):

```json
{
  "contract": "get-coins-v1",
  "claimedToday": false,
  "adCoinReward": {
    "available": true,
    "pendingGrant": false,
    "remainingToday": 3,
    "coinAmount": 25,
    "dailyCap": 3
  },
  "referralRewards": { "referrerCoins": 100, "refereeCoins": 100 }
}
```

`adCoinReward` remains omitted unless the existing ads capability and server
switch allow it. `referralRewards` comes directly from reward configuration and
must not mint/read a referral code or query referral friends. The compact path
does not build box odds, accessory pools, powerup pools, ladder data, or
extra-spin state. Unknown view retains the full daily reward response. If
`referralRewards` is absent on an older backend, Flutter performs today's
best-effort `/referrals/me` fallback only for those two numbers; it consumes the
full status response directly for `claimedToday`/`adCoinReward`.

### 5.8 Public Races browser view

`GET /races/public?view=browser-v1`

Success (`200`):

```json
{
  "contract": "public-race-browser-v1",
  "races": [],
  "resolved": { "featuredRaces": true, "tournaments": true, "mine": true },
  "featuredRaces": [],
  "tournaments": { "featured": [], "public": [], "mine": [] }
}
```

`races`, `featuredRaces`, and tournament lists use their current endpoint
serializers, ordering, feature gates, seed-window hiding, and featured
auto-reconciliation behavior. `mine` is exactly the `tournaments` bucket from
the current personal `/races` response, built through its tournament-summary
query without building personal race/result buckets.

The public race list is mandatory; its failure retains the existing endpoint's
status. Optional branches run in parallel and isolate failure: a failed branch
sets its `resolved` flag false and returns an empty list. Flutter then calls only
the corresponding legacy endpoint. An older backend returns only `{races}`;
the missing marker causes all three optional legacy reads, preserving behavior.

### 5.9 Ranked V2 compact view

`GET /ranked/v2?view=compact-v1`

The response stays identical except:

- top-level `contract: "ranked-v2-compact-v1"` is added; and
- each `cohort.members[]` omits `equippedAccessories` (and the backend does not
  join equipped accessory/shop-item relations).

All week/currentUser/cohort/reward/tier/lastWeek fields and member
`rank`, `userId`, `displayName`, `profilePhotoUrl`, `weeklySteps`, and `zone`
remain unchanged. Legacy `/ranked` and `/ranked/v2` without the view retain
cosmetics exactly.

An older backend's full V2 response is a valid superset and is rendered
directly; the client does not request it twice merely because the compact marker
is absent.

### 5.10 Profile stats compact view

`GET /steps/stats?view=profile-v1`

Success (`200`):

```json
{
  "contract": "profile-stats-v1",
  "thisWeek": 0,
  "thisMonth": 0,
  "thisYear": 0,
  "allTime": 0,
  "avgPerDayWeek": 0,
  "avgPerDayMonth": 0,
  "avgPerDayYear": 0,
  "streak": 0
}
```

The values are byte-for-byte equal to the corresponding legacy fields for the
same request clock/timezone. The compact query omits legacy ranked lookups,
`rankedTier`, `rankedDivision`, `rankedTierV2`, and `stepGoal`. Totals/counts and
the unbounded exact consecutive-positive-day streak are computed in SQL with a
constant number of statements; JavaScript must not materialize all historical
rows. Unknown view retains the current implementation and fields. An older
backend's full stats response is a valid superset and is rendered directly.

### 5.11 Shop bootstrap and mutation deltas

`GET /shop/bootstrap?localDate=YYYY-MM-DD`

Success (`200`):

```json
{
  "contract": "shop-bootstrap-v1",
  "cosmetics": { "coins": 100, "ownedItemIds": [], "equipped": {}, "items": [], "adUnlock": {} },
  "resolved": { "powerups": true, "inventory": true },
  "powerups": { "coins": 100, "items": [], "adUnlock": {} },
  "inventory": { "items": [{ "powerupType": "TRAIL_MINE", "quantity": 2 }] }
}
```

Each component is exactly its current endpoint response for the same viewer and
headers. The three loads start in parallel. Cosmetics is mandatory; optional
powerup/inventory failure returns `null` for that block and `resolved: false`,
matching the current UI's best-effort hidden powerup sections. A 404 falls back
to all three current endpoints started together, not sequentially. `localDate`
is optional for frozen/request-replay compatibility; when absent it uses the
existing server-date fallback, and when present it follows the current ad-unlock
date validation/error behavior.

After successful mutations, Flutter consumes existing authoritative responses:

- cosmetic purchase/ad unlock: patch `coins`, returned `item`, ownership, and
  ad-unlock remaining values; do not reload powerups;
- equip/unequip: replace `equipped` from the returned map; do not reload any
  catalog;
- powerup purchase/ad unlock: patch `coins`, the returned inventory quantity,
  the matching store item's `ownedQuantity`, and ad-unlock remaining values;
  do not reload cosmetics.

If an otherwise-successful response lacks a required delta, refresh only the
affected legacy component. A response whose existing `purchase.idempotent` or
top-level `idempotent` flag is true may contain historical state stored with the
original request; Flutter must not patch coins, ownership, or inventory from it.
It refreshes only the affected component and then renders the replay as a
success. Non-idempotent results remain authoritative at their commit point.

### 5.12 HTTP validation for static reads

`GET /app-version/policy` and `GET /powerups/catalog` keep their current `200`
JSON and add a strong ETag derived from the exact serialized representation.
With matching `If-None-Match`, they return `304` with no body.
Version policy also returns `Vary: X-App-Version`. Powerup copy returns
`Vary: X-Client-Features` because its exact representation currently varies for
`powerups4` and `hitchhike_effective_steps`; its ETag is computed only after
those capability filters. Existing cache-control headers are not made more
permissive, and the server checks the complete standards-compliant
`If-None-Match` list including weak comparison and `*` rather than comparing one
raw string.

Flutter retains the last validated payload and ETag in memory and persisted
storage. Powerup-copy records are keyed by a canonical sorted capability
fingerprint containing every token that can alter the catalog; an ETag/body
from one fingerprint is never offered or applied for another. It still
revalidates version policy on every existing launch/resume
trigger; no TTL may hide a force-update change. Powerup copy follows its current
launch/resume triggers. A `304` without a locally valid payload is retried once
without `If-None-Match`; any other failure follows today's fail-open/fallback
behavior. A persisted version policy is used only after the current request
validates it with `304`; it is never applied merely because a launch/resume
request failed, preserving today's fail-open gate. The version-policy ETag
varies naturally with the exact `X-App-Version`-dependent response body.

### 5.13 Lean tournament detail and authoritative mutation reuse

`GET /tournaments/:tournamentId?view=detail-v1`

Success (`200`):

```json
{
  "contract": "tournament-detail-v1",
  "tournament": {
    "id": "tournament-id",
    "name": "Daily Dash",
    "status": "ACTIVE",
    "bracketSize": 16,
    "currentRound": 1,
    "participants": [
      {
        "userId": "user-id",
        "displayName": "Ari",
        "status": "ACCEPTED",
        "seed": 3,
        "eliminatedInRound": null,
        "avatar": null
      }
    ],
    "rounds": [
      {
        "round": 1,
        "label": "ROUND OF 16",
        "matchups": [
          {
            "matchIndex": 0,
            "raceId": "race-id",
            "status": "ACTIVE",
            "endsAt": "2026-08-15T12:00:00.000Z",
            "players": [
              {
                "userId": "user-id",
                "totalSteps": 1234,
                "forfeited": false,
                "stealthed": false
              }
            ],
            "winnerUserId": null,
            "tie": false
          }
        ]
      }
    ]
  }
}
```

Every tournament summary/money/status/viewer/action field and the exact
participants/rounds ordering equals the current full response. The only public
participant fields omitted are character/cosmetic presentation fields that the
current Tournament Detail and bracket renderer do not read: exactly the legacy
`animal` and `accessories` keys, including every nested remote/render metadata
field reachable only through those values. `displayName` and `avatar` remain.
Matchup-player shape, tie/forfeit/stealth masking, tournament
spectator visibility, seed prize fallback, and all status/clock behavior remain
byte-compatible.

The optimized query must select only:

- tournament scalars and the minimal seed prize/kind relation;
- tournament-participant status/seed/elimination/order scalars plus user ID,
  display name, and profile photo once in the top-level participant directory;
- matchup-race ID, round/index, status, end, powerup, winner, and required
  tournament fields;
- matchup participant ID/status/total/finish/forfeit/order scalars, with no
  user relation; and
- ACTIVE effect `type`, `targetUserId`, `expiresAt`, and `metadata` needed by
  the existing per-viewer illusion rules.

It must not load creator/champion user relations that the serializer never
reads, any matchup-participant user, `user_equipped_accessories`, `shop_items`,
or unused race/participant columns. The current serializer's repeated linear
race lookup may be replaced by a keyed map but cannot change ordering or tie
identity. Authorization is evaluated from a lean tournament/access row before
building the viewer payload; all current `401`/`403`/`404` privacy behavior is
unchanged.

Unknown/disabled `view` uses the exact legacy query and response with no
contract marker. An older backend may ignore `view` and return the legacy full
superset; Flutter consumes that response directly and does not fetch again.
Live PENDING/ACTIVE screens retain the current complete-snapshot 60-second
poll. This phase deliberately does not introduce a delta, revision, or ETag
protocol: the compact full snapshot preserves current name/photo/bracket/step
freshness with lower risk.

The same optional `view=detail-v1` is accepted on the mutation routes below.
Every compact mutation success uses `contract:"tournament-action-v1"`; a
non-null `tournament` is the exact `tournament-detail-v1` nested tournament
shape above, without a second nested contract marker. Absent/unknown view
retains the exact legacy status and response byte shape for frozen clients.

| Method/path | Branch | Status | Exact compact success keys |
|---|---|---:|---|
| `POST /tournaments/share/:token/join` | join | `201` | `{contract,tournament,projectionError,wallet,walletError}` |
| `POST /tournaments/:id/join` | join | `201` | `{contract,tournament,projectionError,wallet,walletError}` |
| `PUT /tournaments/:id/respond` | `accept:true` | `200` | `{contract,tournament,projectionError,wallet,walletError}` |
| `PUT /tournaments/:id/respond` | `accept:false` | `200` | `{contract,wallet,walletError}` |
| `POST /tournaments/:id/invite` | invite | `200` | `{contract,tournament,projectionError,invited,needsUpdate}` |
| `POST /tournaments/:id/kick` | kick | `200` | `{contract,tournament,projectionError}` |
| `POST /tournaments/:id/start` | start | `200` | `{contract,tournament,projectionError}` |
| `POST /tournaments/:id/forfeit` | forfeit | `200` | `{contract,tournament,projectionError}` |
| `POST /tournaments/:id/leave` | leave | `200` | `{contract,wallet,walletError}` |
| `DELETE /tournaments/:id` | cancel | `200` | `{contract,success,wallet,walletError}`, with `success:true` |

For rows with `tournament`, normal success returns the object and
`projectionError:null`. For rows with `wallet`, normal success returns exact
integers `{coins,heldCoins}` and `walletError:null`. `invited` and
`needsUpdate` retain their exact existing array contents/order. Compact decline
and leave deliberately omit the legacy deep `tournament` key because the
screen navigates away; compact cancel retains `success:true` and likewise
omits tournament state. Share-link generation is unchanged and does not opt
into this contract.

Command validation, authorization, conflict, and every other error that occurs
before commit retain the exact legacy HTTP status and error envelope. The core
mutation commit is separated from optional post-commit enrichment. Once the
mutation commits, a compact projection or wallet read is not allowed to turn
success into `5xx` or invite an unsafe retry:

- projection failure preserves the route's success status/action keys, returns
  `tournament:null` and
  `projectionError:{"code":"DETAIL_UNAVAILABLE"}`, and Flutter performs
  exactly one `GET /tournaments/:id?view=detail-v1` if the screen remains;
- wallet failure independently preserves success, returns `wallet:null` and
  `walletError:{"code":"WALLET_UNAVAILABLE"}`, and Flutter performs exactly
  one existing `/auth/me` wallet refresh; and
- if both enrichments fail, both null/error pairs are returned in the same
  committed-success envelope. Navigate-away rows never run a detail projection.

The post-commit wallet helper reads Postgres directly and matches the current
`/auth/me` values exactly: `coins` is the fresh user coin balance and
`heldCoins` is the existing `User.getHeldCoins` sum of only HELD
`race_participants`. Tournament-held buy-ins are intentionally *not* added to
`heldCoins`; correcting that accounting is a separate behavior/economy change.
The helper does not read Redis, and projection/wallet reads are independently
failure-isolated after the transaction.

Flutter consumes a valid compact or legacy tournament returned by a successful
screen-remains mutation instead of immediately reloading detail. An absent,
null, malformed, or explicitly unavailable tournament triggers the one detail
refresh above. It applies a valid wallet and otherwise uses the one `/auth/me`
fallback; it never interprets an enrichment failure as failure of the already
committed action. Existing buy-in/refund behavior remains unchanged.

Route coverage must not leave hidden pollers consuming capacity. Race Detail
and Tournament Detail use one real route-visibility mechanism (for example,
`RouteAware` through the app's observer), not hand-written Race↔Tournament
callbacks. Whenever either route loses top-route visibility to any pushed
full-screen, dialog, sheet, or picker route, all of that screen's progress,
Activity/Chat, inventory, detail, and countdown timers stop. When it becomes
topmost again, it performs exactly one coalesced refresh and restarts only
eligible timers. This covers Race→Tournament, Tournament→Race,
Tournament→Friend Picker, and Race→other full-screen actions. App
background/resume behavior and visible freshness remain unchanged. Timer
eligibility is the conjunction of mounted, route-visible, app-resumed, and
live-state; overlapping navigation/app lifecycle resumes coalesce and cannot
restart a timer beneath a covered route.

### 5.14 Reason-aware race resolution and bounded post-processing

This section changes no HTTP request/response shape and no game rule. It
optimizes the backend-only live-state machinery behind progress, step sync,
powerups, boxes, placement recovery, and timed effects.

The earlier deployed fixes removed race-open-triggered global step sync and
duplicate full-race hydration from Mystery Box, Trail Mine, and shared cast
tails. They did **not** remove a different double computation that remains in
`getRaceProgress`: on a natural 15-second shared-snapshot expiry, the winning
request calls `computeSharedState(...persist:false)`, writes the fresh Redis
snapshot, and then enqueues the race-keyed worker, which calls the canonical
full-race resolver again. The changes below target that remaining path.

#### 5.14.1 Reuse the display computation instead of scoring twice

With `raceResolutionDisplayArtifactReuseV1Enabled=true`, the one request that
wins a cold/soft-expired progress-snapshot rebuild produces both today's exact
allowlisted Redis snapshot and a bounded, internal write-capture/result artifact
from that **same** canonical full scoring pass. Before enqueueing the existing
viewer-triggered `DISPLAY_REFRESH` generation, it writes the artifact to a
versioned environment-scoped Redis key with a random opaque ID, SHA-256 digest,
and 120-second TTL; the atomic DB enqueue stores only that opaque reference,
digest, scoring time zone, and viewer trigger. No artifact key or payload is
logged. If Redis is disabled/unhealthy, encoding exceeds 1 MiB/1,000
participants, the write/enqueue fails, or the flag read fails, the request uses
the deployed ordinary enqueue with no artifact.

The worker may skip its second full scorer only when all of these hold at claim
and again under the existing race/job write fence: the artifact exists and its
digest/schema/race/time-zone match; the claimed generation contains only
`DISPLAY_REFRESH`; its triggering-user set matches the artifact; no later
generation or immediate mutation is pending; and every captured row still
matches the input version/scalar recorded by the computation. The artifact also
stores the balance/config version and an exclusive reuse deadline equal to the
earliest of `asOf + 5 seconds`, race end, scoring-time-zone day rollover, active
effect expiry, relevant global-event start/end, the earliest relevant
`step_samples.periodEnd` that changes closed-bucket eligibility, or the next
top-of-hour boundary used by legacy Hitchhike; the fence must occur before that
deadline and the config version must still match. Every time-sensitive scoring
primitive registers its next boundary in one exhaustive registry; an
unregistered/unknown boundary disables artifact emission. Any mismatch,
missing key, malformed field, expired TTL, concurrent mutation, mixed reason,
or uncertain input discards the artifact and runs the deployed full resolver.
The artifact is optimization-only, single-use after a successful fenced commit,
and safe to lose during a restart/rolling deploy.

On a valid artifact, the worker applies the captured participant/effect/event
writes under the same fence and ordered-write rules, then runs the exact existing
expiry → alert → snapshot, all-user box, and all-user nudge sequence with the
captured result. The HTTP request remains read-only with respect to
`race_participants`; the worker remains their writer. This preserves current
raw-step healing, box-gate arming/minting, viewer-triggered recovery, alerts,
nudges, and the five-minute due-effect/recovery backstop. It changes neither the
population nor timing source for effect/global-event notifications and creates
no independent whole-base boundary fan-out.

Trail Mine preserves two views from the one canonical pass. Immediately before
`triggerTrailMines`, the scorer freezes the exact legacy pre-detonation snapshot
used by the HTTP response; it then continues in memory through mine candidate/
shield/team/tie selection to produce the post-detonation totals and captured
effect/event writes used only by the worker artifact. The request never exposes
a penalty/feed event before that worker transaction commits, and the second
phase does not repeat base/effect scoring.

Thus the healthy path still records the same lightweight race generation and
side effects but performs only one canonical scoring pass rather than the
request pass followed by a worker pass. Flag-off is the deployed behavior.
Telemetry distinguishes artifact hit, fallback reason, and coincidental overlap
without exposing the opaque reference or participant/user IDs.

The artifact never treats presentation/copy as scoring input. Under the fence,
one bounded bulk projection reloads the current display name, profile photo,
equipped presentation, and every other non-scoring field used by a captured
feed/push/box string or the shared snapshot. The worker rebinds those fields by
stable user/participant ID before constructing captured event text or delivery
intents; the post-commit snapshot assembler uses the same fresh projection. If
any opaque captured value cannot be safely rebound, artifact reuse falls back
to `FULL`. Thus a profile/equipment mutation needs no scoring generation but
cannot replay stale copy/presentation.

“Input version” is a complete bounded scorer-input fingerprint, not merely the
rows the scorer happened to return. It hashes the ordered race/membership set
and every scoring scalar, the ordered active/relevant effect set (IDs, status,
type, source/target, start/expiry, scoring payload/version), the relevant
global-event set/boundaries, the balance-config version, and a bulk monotonic
step-input token for every accepted user. Every daily-step/sample create,
update, reconcile, or delete bumps that user's token in the same DB transaction
as the source write. The worker rebuilds the fingerprint with constant-count
set/bulk queries under the fence. A new/deleted participant, effect, event, step
row/sample, or changed scalar therefore differs even when it is a phantom absent
from the original captured write set. Unknown/unversioned input and rolling
overlap with a binary that does not bump tokens force `FULL`; artifact reuse is
not enabled until all old binaries have exited.

The artifact's score and fingerprint must also describe one coherent input
window. The request reads fingerprint A, runs the canonical scoring/capture,
then reads fingerprint B; it emits an artifact only when A and B are byte-equal
and no reuse deadline crossed during the pass. A mismatch still returns the
normally computed HTTP snapshot but performs the ordinary enqueue with no
artifact, so the worker recomputes. Implementations may instead share one
read-only `REPEATABLE READ` transaction between fingerprint and canonical
scoring if every model read is transaction-injected; mixing transactional and
nontransactional reads is forbidden.

#### 5.14.2 Dirty reasons and affected scope

Every enqueue carries one closed reason plus a bounded affected set:

```json
{
  "reason": "STEP_SYNC",
  "dirtyUserIds": ["user-id"],
  "dirtyParticipantIds": ["participant-id"],
  "powerupTypes": [],
  "priority": "COALESCE",
  "requestedAt": "2026-08-13T12:00:00.000Z"
}
```

The envelope is internal only and never serialized to an app. Enqueue upserts
append-distinct reason/user/participant/type sets in stable order. A missing,
unknown, malformed, or oversized reason/scope always falls back to `FULL`; it
never silently selects a narrower computation. IDs are capped to the race's
accepted membership, and logs expose counts/reason classes only—never IDs.
The merged envelope permits at most 1,000 distinct user IDs, 1,000 distinct
participant IDs, and 64 powerup/effect types. Crossing a cap atomically replaces
the narrow scope with `FULL` and clears the ID/type lists; it never truncates a
dependency set.

| Reason | Required work |
|---|---|
| `DISPLAY_REFRESH` | Existing generation and side effects; reuse the validated full artifact under §5.14.1 or fall back to one ordinary `FULL` worker pass. Never use partial scope. |
| `STEP_SYNC` | A narrow generation becomes claimable only after the uploader reconcile has committed and carries that participant row's monotonic input token. Recompute the uploader's dependency closure: Leech counterpart(s), Hitchhike caster(s), and any other registry-declared cross-participant dependency. Any active untriggered Trail Mine, missing/stale token, skipped/failed reconcile, or mechanic without a provably closed set escalates to `FULL`. |
| `POWERUP_MUTATION` | A single exhaustive registry classifies every known powerup as self, target, dependency-closure, team, or race-wide. Use the canonical scoring primitives for that scope. Unknown/new types default to `FULL`; a structural test fails when a catalog type lacks an explicit registry entry. |
| `BOX_OPEN` | Inventory/slot repair only; no scoring run unless the roll actually creates/changes an auto-active scoring effect, in which case it enqueues that effect's `POWERUP_MUTATION` scope. |
| `JOIN_LEAVE_KICK`, `FORFEIT_TEAM`, `RACE_START` | `FULL`, because membership/team/placement context changes. |
| `EFFECT_BOUNDARY` | The existing five-minute due-effect selector enqueues this reason. Preserve its current claim-time/as-of behavior; use `FULL` for every snapshot-at-expiry/Drill Sergeant/race-wide/unknown effect, and only use a target closure when parity is proven. |
| `GLOBAL_EVENT_BOUNDARY`, `RECOVERY` | `FULL`. Do not add a new global-boundary fan-out; existing viewer/mutation/recovery triggers remain authoritative. Settlement remains a separate direct caller of the full canonical scorer under `raceExpiry`; it is not a live-queue reason. |
| `DAILY_MOVER` | Preserve the current persisted worker-cycle source and one-race selection exactly; do not substitute a fresher display snapshot. |

Incremental resolution is not a second scoring implementation. It calls the
same base/effect/Hitchhike/Leech/Trail-Mine primitives as full resolution and
only changes the participant set assembled around them. Cross-participant
dependency expansion is transitive and cycle-safe. The registry lives beside
the canonical powerup/effect definitions, not in routes. Full resolution remains
the safe fallback and the settlement authority remains unchanged.

For `STEP_SYNC`, the worker consumes the uploader row/result that
`reconcileUploaderRaces` already persisted in the sync request; it does not
repeat that user's base/day/sample calculation. It computes only missing
cross-participant consequences (for example Leech attacker credit/victim
availability and a newly crossed Trail Mine) against the canonical stored/input
snapshot. If the existing uploader result lacks any scalar needed to compose an
exact outcome, the registry escalates the race to `FULL` rather than guessing.
The sync response keeps today's immediate uploader total/box state; cross-participant
side effects retain the same healthy-worker behavior, with a coalescing wait of
at most five seconds only for sync bursts.

The live legacy `/steps` and `/steps/samples` commands therefore reverse their
current enqueue-before-reconcile order only under the reason-aware flag:
successful reconciliation returns, per race, the committed participant ID,
`totalsUpdatedAt` input token, and exact uploader result, and only then enqueues
claimable `STEP_SYNC`. A skipped reconcile (`skipRaceResolution`), caught
reconcile failure, absent token/result, or enqueue/reconcile ordering from an
older binary writes/merges `FULL` instead. Sync-v2 retains its existing atomic
transaction and stamps the same token. At claim and immediately before the
write fence, a narrow worker compares the stored participant token; mismatch
unions its triggers into `FULL` and recomputes rather than overwriting a fresher
uploader row.

Trail Mine is conservative: while any untriggered mine is active, `STEP_SYNC`
and mine planting resolve `FULL` unless the canonical registry proves a scope
containing the mine owner/team context and **every** simultaneously eligible
crosser after transitive Leech/Hitchhike expansion. Same-tick ties, team allies,
shields, and multiple mines never use a one-uploader shortcut.

After a scoped commit, snapshot publication never invokes the scorer again and
never treats a partial base-adjusted map as complete. A byte-equivalent
assembler reads the fenced committed participant totals/raw/finish/team rows,
the allowlisted race scalars, and the bounded active-effect/global-event rows in
constant SQL statements, then builds the same public snapshot shape. It may use
the scoped generation's exact base-adjusted values only for those participant
IDs and leaves other internal base values absent; the existing viewer builder
performs its current one-user fallback when that private optimization scalar is
needed. This can add O(N) in-memory serialization but no O(N) scoring, SQL, or
cosmetic hydration. If public bytes or eligibility cannot be proven identical,
the reason escalates to `FULL` before commit.

#### 5.14.3 Burst coalescing without starvation

`raceResolutionBurstCoalescingV1Enabled` changes only queue scheduling; it does
not raise worker concurrency. `STEP_SYNC` and other `COALESCE` reasons use a
fixed window ending no later than five seconds after the first queued request,
matching the existing debounce magnitude. Later enqueues merge into that window
but never push its deadline forward, so a continuously active 350-person race
cannot starve. Interactive correctness reasons such as a newly cast scoring
powerup, membership change, forfeit, or due boundary remain `IMMEDIATE` and do
not wait behind the sync window.

Claim atomically snapshots the merged dirty sets into processing columns while
new arrivals accumulate for the next generation. Immediately before the write
fence, a generation recheck may discard a superseded computation *without
writing totals or creating post-tasks* only when:

- the newer generation remains durably queued with every processing trigger
  unioned back into it;
- the last successful authoritative commit is at most 15 seconds old; and
- neither generation contains an `IMMEDIATE`/non-discardable reason.

Otherwise the current run commits and the newer generation follows, preserving
bounded convergence. This prevents continuous supersession from starving
Trail Mines, due effects, boxes, or notifications. The existing five-second
flag-off behavior remains available verbatim.

#### 5.14.4 Ordered bulk participant writes

`raceResolutionBulkWriteV1Enabled` preserves the existing fence-first
transaction and changed-row filter, but replaces N Prisma updates with a
bounded two-step write:

1. select and lock every changed participant row in ascending `userId` order;
2. perform one parameterized `UPDATE ... FROM` over a typed `VALUES`/JSONB
   recordset containing participant ID, total, optional raw total, bonus
   decrement, and the run's single `totalsUpdatedAt` value.

The bulk statement must preserve today's semantics exactly: omitted raw totals
never null/overwrite healed values, bonuses decrement rather than replace,
frozen participants are absent, team heartbeat behavior is retained, and only
materially changed rows update. A locked-row/update-count mismatch rolls the
transaction back. Trail-Mine effect/event writes and the job-generation update
remain inside the same transaction after participant totals. Flag-off uses the
existing ordered row loop. SQL statement count for participant persistence is
bounded as race size grows.

Captured writes are normalized to exactly one record per participant before
locking: multiple bonus decrements sum in capture order, a participant's total
and bonus delta share one record, and conflicting duplicate total/raw writes are
a hard rollback rather than last-write-wins. Lock/update-count validation is
against the distinct normalized participant IDs, including the unchanged team
heartbeat row when current behavior requires it.

#### 5.14.5 Durable delivery/publication tasks

`raceResolutionPostTasksV1Enabled` moves only work whose gameplay decision is
fully made and durably claimed before handoff. Stateful or RNG-sensitive work
stays in the current worker order after the fenced scoring commit:

1. run `expireEffects`, including Fanny Pack, Drill Sergeant, Piggy Bank, and
   effect-state/economy mutations;
2. evaluate high-multiplier crossings/re-arms and atomically claim any exact
   notification delivery intent;
3. compute the snapshot-publication command for this generation;
4. run `syncRacePowerupState` for **all** triggering users in today's stable
   sorted order, including box RNG/mints, queue promotion, repair, and recent
   mint recording; and
5. decide overtaken-rival recipients only after the complete box loop and
   atomically claim exact step-sync/nudge delivery intents **and their current
   cooldown reservations** in the immutable triggering-user order. A later
   generation observes that reservation before selecting recipients.

Every current catch/log/continue boundary remains: expiry failure still permits
alert/snapshot/boxes/nudges; one box failure does not stop later boxes; alert or
nudge decision failure is not re-evaluated after a newer generation. This
performance phase deliberately does **not** retry failed gameplay/RNG/recipient
decisions, because doing so later could change boxes, re-arm state, or rivals.
It defers only these already-decided operations:

- one generation-level `POSTCOMMIT_DELIVERY` task containing the ordered,
  already-claimed alert/effect/nudge/step-sync push intent IDs and the
  snapshot-publication command. Each intent row contains the original
  recipient, payload, delivery/idempotency claim, cooldown reservation, and
  source generation. Transport gets exactly one application-level attempt and
  never calls multiplier, standings, box, effect, or recipient-selection logic again.

The primary handler attempts the immutable intents in deployed order: state/
effect notification deliveries, snapshot publication unless the generation is
superseded, then nudge/step-sync deliveries. A failed delivery is logged/recorded
as terminal with no resend and later intents are still attempted. If a newer generation has
committed before snapshot publication, the snapshot substep skips rather than
overwriting the newer invalidation.

Each intent has its own durable ordinal/state; the group row is never the unit
of send acknowledgement. Immediately before provider I/O, one transaction
changes only that intent from `pending` to `attempting` and records
an attempt ID/time. Provider-confirmed acceptance becomes `accepted`;
provider-confirmed non-acceptance becomes terminal `rejected_no_retry`. A timeout, thrown I/O,
or process death after `attempting` is **ambiguous** and becomes
`ambiguous_at_most_once` after lease recovery: it is alerted and never resent.
This may lose a push the provider did not actually accept, matching the deployed
best-effort failure envelope, but it can never duplicate a push the provider did
accept. A crash before the `attempting` transaction leaves the intent pending;
a crash between intents resumes at the next nonterminal ordinal. Snapshot SET is
also single-attempt: its marker uses `pending`, `attempting`, `succeeded`,
`failed_no_retry`, `ambiguous_at_most_once`, or `skipped_superseded` with the same crash policy and
is never retried by this feature. The next normal reader retains today's
15-second recovery. The group completes only when every intent and the snapshot
marker are terminal; later intents still run after an earlier failure.

The task/intent payload is allowlisted, contains no full race graph or device token,
and is capped at 256 KiB and 1,000 decided intents. Exceeding either cap or an
encoding/DB task-write failure executes the same deliveries/publication inline;
it never truncates. One task is loaded once per generation, so trigger count
cannot cause N race hydrations or N standings scans. Keys are
`v1:post-delivery:{raceId}:{sourceGeneration}` plus the existing claimed
delivery key represented only by a keyed one-way hash; no key, payload, user ID,
race ID, or token is logged.

One process-wide fair semaphore caps combined core-resolution plus post-task
handlers at the already configured total of two; the task runner adds no third
DB/CPU lane. Core work receives the next slot after at most one delivery claim.
Readiness requires a successful claim probe within 60 seconds, oldest pending
lag below 30 seconds, and no expired `attempting` row awaiting ambiguity
classification. If readiness is false when a generation reaches handoff,
it atomically claims and executes its just-created delivery task inline. With
`redisStandingsEnabled=false`, the current no-op relocated hook remains the
authority and no new task runs that behavior.

The flag gates creation, never draining: flag-off performs new deliveries/
publication inline while the runner drains old tasks. Shutdown leaves leases
recoverable. A cleanup disabled by
`RACE_RESOLUTION_POST_TASK_CLEANUP_DISABLED=true` keyset-deletes at most 500
fully terminal group/intent rows per run after seven days and never deletes a
pending/running/unclassified-attempt row. This is latency isolation,
not eliminated CPU; evidence reports decision time, deferred delivery time, and
combined resources separately.

`RACE_RESOLUTION_POST_TASK_WORKER_DISABLED=true` is the whole-runner scheduling
kill switch, checked in `src/index.js` before timer registration and again at
each tick. It stops new group/intent claims and ambiguity classification without
changing/deleting queued rows or stopping the core resolver. Readiness is false
while it is set, so new generations use the inline fallback. Normal rollback
keeps it false until the §9 drain proof is zero, then sets it true; emergency use
may intentionally leave old intents queued for later recovery.

## 6. Data model and migrations

One additive migration supports §5.14; every API projection otherwise uses
existing indexed relations and caches.

New table `user_scoring_input_versions` contains unique `userId`, monotonic
`generation`, and `updatedAt`; user deletion cascades. Every scoring-source
step/sample writer upserts/increments it atomically with that source mutation.
Missing rows are a valid initial version only when the fingerprint also proves
the user has no scoring-source rows; otherwise they make an artifact unsafe.
This token is internal and never serialized.

`race_resolution_jobs_v2` adds default-safe queue metadata:

- `dirty_reasons JSONB NOT NULL DEFAULT '[]'`;
- `dirty_participant_ids JSONB NOT NULL DEFAULT '[]'`;
- `dirty_powerup_types JSONB NOT NULL DEFAULT '[]'`;
- `dirty_priority VARCHAR NOT NULL DEFAULT 'IMMEDIATE'`;
- nullable `display_artifact_id`, `display_artifact_digest`, and
  `display_artifact_schema` plus matching processing-snapshot columns;
- matching `processing_dirty_*` snapshot columns; and
- no replacement for the existing generation, requested/not-before,
  triggering-user, lease, or completion fields.

Empty/malformed metadata means `FULL`, so an old enqueue/new worker combination
is conservative. An old worker ignores the additive columns and still performs
a full resolve. Enqueue/claim SQL moves and unions metadata atomically with the
existing triggering-user arrays.

New table `race_resolution_post_tasks` contains `id`, `raceId`,
`sourceGeneration`, unique deterministic `dedupeKey`, `state`, `requestedAt`,
`notBeforeAt`, `snapshotState`, `snapshotAttemptId`, `snapshotAttemptedAt`,
`snapshotCompletedAt`, `snapshotErrorCode`, `snapshotCommand JSONB`,
`payloadBytes`, `intentCount`, `startedAt`, `completedAt`, `leaseExpiresAt`,
`leaseToken`, and created/updated timestamps. `raceId` and `sourceGeneration`
are non-null; group states are `queued`, `running`, `succeeded`,
and `succeeded_with_failures`; snapshot states are the closed set in
§5.14.5. It has indexes on `(state,notBeforeAt)`, `leaseExpiresAt`, and
`(raceId,sourceGeneration)`; unique `(raceId,sourceGeneration)` prevents a
second group. Deleting a race cascades its task.
There is no parent `obsolete` transition: a newer generation may mark only the
older snapshot `skipped_superseded`; every older pending child intent still
receives its one attempt before the group becomes terminal/cleanable.

New child table `race_resolution_delivery_intents` contains `id`, non-null
`taskId`, `ordinal`, closed `kind`, nullable internal `recipientUserId`, `payload JSONB`,
`payloadBytes`, the unique keyed `deliveryKeyHash`, the synchronously reserved
`cooldownClaimId`, `state`, `attemptId`, `attemptedAt`, `completedAt`,
`providerDisposition`, `lastErrorCode`, and timestamps. States are `pending`,
`attempting`, `accepted`, `rejected_no_retry`, and
`ambiguous_at_most_once`; there is no retry state. Unique `(taskId,ordinal)`
pins order, unique `deliveryKeyHash` pins the idempotency boundary, indexes on
`(taskId,state,ordinal)` and `(state,attemptedAt)` support resume/ambiguity
classification, and deleting the parent/race cascades. Parent plus child CHECKs
cap the parent's declared aggregate at 256 KiB/count at 1,000 and each intent at
16 KiB; the one creating transaction computes/validates the exact aggregate and
intent rows are immutable after insert except for attempt-state fields. The
recipient FK uses `ON DELETE SET NULL`; delivery then records
`rejected_no_retry` and continues rather than deleting/reordering the group.
Payloads may contain an internal recipient ID/copy but never a device token,
full race graph, cosmetics, or raw scoring inputs. No API can read either table.

Display artifacts use only Redis key
`v1:race:resolution-artifact:{opaqueArtifactId}` beneath the existing
environment/version prefix, TTL 120 seconds, and the §5.14.1 digest/schema
envelope. Add the builder to `cacheKeys.js`, the canonical Redis key table, and
the operations runbook. It is not included in broad invalidation enumeration:
successful consumption deletes its exact opaque key and otherwise TTL is the
only cleanup. No DB row stores its payload.

No destructive rewrite, seed, or new required application input exists. Deploy
the migration and token-bumping writers with flags dark, wait until every old
backend process has exited, then keyset-scan distinct user IDs from historical
daily-step/sample sources in bounded batches of 500 and `INSERT ... ON CONFLICT
DO NOTHING` a baseline token. A concurrent new-code writer either increments
the inserted baseline or wins the insert and makes the baseline a no-op, so no
write is lost. Artifact reuse cannot enable until a set-based proof returns zero
source-bearing users—and zero accepted ACTIVE-race users with sources—without a
token. The baseline is idempotent, resumable, disabled by
`RACE_SCORING_INPUT_BASELINE_DISABLED=true`, and never reads/writes production
from a test command. Post tasks may enable after old binaries exit; artifact
reuse additionally waits for the completed baseline/proof. Rollback flips flags
off; additive columns/tables remain inert and may be removed only in a separate
future cleanup.

Before implementation is called done, real-test-DB `EXPLAIN (ANALYZE, BUFFERS)`
must cover the new friend summary, compact Ranked profile lookup, Profile stats
aggregate, race access/progress/message-watermark projections, and tournament
detail at 4/8/16 participants with both first-round and full 15-race histories.
Resolution evidence covers the reason-aware lookup/dependency queries, ordered
bulk lock/update plan at 10/100/350 participants, display-artifact fallback,
post-delivery/intent claim, crash ambiguity, and task dedupe/upsert/retention paths.
If a required production-like query lacks a usable existing index—including
the USER watermark's race/kind/created ordering—stop and revise this spec with
an additive concurrent-index migration; do not hide a scan behind a cache.

This plan evidence is the one explicit exception to the public-HTTP integration
boundary: a dedicated non-production query-plan test/tool may call the exact
production query builder only to capture/assert raw planner output. It must
first verify the Postgres database name ends in `_test` (or is a disposable
container), rolls back any fixture transaction, and cannot import mutation
commands. Contract, behavior, authorization, and parity evidence still runs
through real HTTP; the query-plan tool is not accepted as behavior coverage.

## 7. Backend implementation plan

1. Add tests first for every contract and old-client path.
2. Add small shared serializers/projections rather than copying route JSON:
   compact authenticated user, friend summary, own presentation, and compact
   ranked profile.
   Auth response caches must key by contract and preserve the existing
   app-version variant; all current invalidation seams delete legacy and compact
   variants.
3. Split race deep loading into explicit access, static detail, live scoring,
   and presentation projections. Allow detail/progress builders to consume one
   preloaded context while keeping their legacy exported call paths.
4. Add the race bootstrap and lazy/combined message stream handlers before
   `/:raceId` catch-all routes. Give legacy and combined message reads the same
   lean access projection so frozen clients also stop hydrating cosmetics. Add
   the separately flagged body-free watermark cache key/rebuild/invalidation
   path without reading the existing full USER-message cache in Activity-only
   mode. Add a `raceMessageWatermark(raceId)` builder, include its key in
   `raceMessagesAllKeys(raceId)`, document it in the canonical Redis key table,
   and add the new flag to the Redis runbook.
5. Add the lean tournament access/detail projection and opt-in detail branch;
   reuse it for compact mutation responses while leaving every legacy command
   result unchanged. Separate transaction success from post-commit projection
   and direct-Postgres wallet enrichment so enrichment failure cannot become a
   false mutation failure.
6. Add the §6 migration, then extend the single enqueue/claim seam with closed
   dirty reasons, dependency-scope registry, fixed-window coalescing, and
   superseded-discard safety. Add the optional Redis display artifact while
   retaining the current display/mutation/due/recovery generations and their
   side effects. Implement the ordered lock + bulk update, byte-equivalent lean
   committed-row snapshot assembler, shared two-lane budget, and durable
   generation-level post-task model/runner, reusing current scoring and
   side-effect services rather than copying them.
7. Add opt-in branches to friends, auth, Home, daily reward, public races,
   Ranked V2, and stats. Unknown/absent views dispatch to the existing code.
8. Add Shop bootstrap in a proper injected module under `src/modules/shop/`:
   a query/service composes the existing catalog services concurrently, a thin
   `routes.js` owns HTTP only, `index.js` exports it, and `src/app.js` mounts it
   before/alongside the legacy `/shop` router. Do not add composition/business
   logic to `src/routes/shop.js`; keep every legacy route there unchanged.
9. Add static ETag generation after representation/capability selection.
10. Add structured performance telemetry with endpoint/contract, outcome,
   duration, SQL count when instrumentation is enabled, response byte count,
   and result counts. Include message mode (`activity_only|combined`) and
   tournament bracket/race counts. Resolution events include reason classes,
   dirty/expanded/full participant counts, coalesced generations, superseded
   discard/commit outcome, compute/lock/write/core/post-task durations, SQL
   count, changed rows, queue lag, and active lanes. Each event is one complete single-line JSON
   record so a line-oriented production monitor cannot retain only the opening
   brace. Logs contain no token, message body, name, user ID, race ID,
   tournament ID, search text, or other PII.
11. Run focused integration suites against a verified disposable `*_test`
   database, then full backend unit/integration commands. Never use bare
   `npm test` and never point tests at production.

Expected backend files include the route/query files named in §1,
`src/modules/shop/{index,routes,queries/getShopBootstrap}.js`, a narrow
`src/app.js` mount, new services under the other corresponding modules,
`src/modules/tournaments/{routes.js,models/tournament.js,queries/getTournament.js,queries/serializeTournament.js}`
plus a lean tournament projection/query,
`src/modules/social/services/raceMessagesCache.js` plus the body-free watermark
cache surface,
`src/modules/races/{services/enqueueRaceResolution.js,services/raceStateResolution.js,services/raceProgressSideEffects.js,jobs/raceResolutionQueueV2.js,jobs/placementRecompute.js,models/raceResolutionJobV2.js}`,
new display-artifact/reason-registry/post-task model and runner modules, the Prisma schema plus
one additive migration,
`src/shared/cache/cacheKeys.js`, the auth cache's documented key table,
`src/shared/config/appSettings.js`, `src/db.js` only for the existing test
query-event seam, and integration/query-plan tests. No production flag is
enabled and no deploy occurs during implementation.

## 8. Frontend implementation plan

1. Add tests first around `BackendApiService` parsing/fallback and real screen
   request counts.
2. Add defensive API methods for race/shop bootstraps and compact view params;
   use per-process definite-404 capability caches for all three new endpoints:
   race bootstrap, message streams, and Shop bootstrap.
3. Replace race entry with bootstrap-first loading. Add one race-stream
   coordinator that starts Activity plus a Chat watermark, creates Chat only on
   its first tab tap, and then switches to combined mode; keep pagination,
   optimistic-send, unread, and notifier interfaces.
4. Keep progress and global-inventory freshness at 30 seconds and message
   freshness at five seconds. Remove duplicate progress-triggered chat/feed
   refreshes and the separate per-progress inventory HTTP call by consuming the
   compact progress block. Patch inventory immediately from action responses;
   explicit retry may refresh it.
5. Make MainShell own compact friends and presentation state. Pass the friends
   snapshot into FriendsTab/sheets and invalidate it once per mutation. Use the
   complete compact session marker to skip only the redundant initial `/auth/me`.
6. Move Get Coins, Public Races, Ranked V2, and Profile to their opt-in views,
   retaining the fallbacks in §5.
7. Load Shop through bootstrap, or all three legacy endpoints in parallel.
   Apply authoritative mutation deltas with affected-component fallback.
8. Move Tournament Detail to `detail-v1`, consume valid mutation-returned
   tournaments/wallet deltas, retain legacy/malformed fallbacks, and use a
   shared route-visibility observer to suspend covered Race/Tournament pollers
   with one coalesced return refresh.
9. Add conditional GET storage for static reads without changing launch/resume
   trigger frequency.
10. Run relevant widget/integration tests first, then `flutter analyze` and
   `flutter test`. Account for both iOS and Android; this is shared Dart and
   requires no platform-specific API or release define.

Expected frontend files include `lib/services/backend_api_service.dart`,
`auth_service.dart`, `race_chat_service.dart`, `race_feed_service.dart`, a new
race-stream coordinator, `lib/screens/race_detail_screen.dart`,
`lib/screens/tournament_detail_screen.dart`, `lib/utils/tournament.dart`,
`main_shell.dart`, `public_races_screen.dart`, `get_coins_screen.dart`, and the
Friends, Shop, Ranked, and Profile tab/widgets plus their tests. The real race
screen is also rendered by fake/demo services, so implementation must add safe
overrides for every new API method in `lib/demo/demo_race_api_service.dart`, add
the required compact fixtures/fields in `lib/tutorial/tutorial_preview_data.dart`,
and update any tutorial fake override whose inherited signature gains a `view`
parameter. Extend `test/demo_race_network_guard_test.dart` to scan the new
coordinator and all new race API call sites; an unoverridden fake must fail the
guard rather than reaching the configured backend (including production).

## 9. Backward compatibility and rollout

1. Apply the additive §6 migration, then deploy backend code with all nineteen
   flags false. Every frozen client continues calling legacy routes
   without compact views and receives its current response shape.
2. Verify all new endpoints/views with flags dark or only explicit requests.
3. Enable server-side compact implementations independently only after contract
   parity/query evidence passes. Disabling a new-endpoint flag returns `404` and
   activates the client's cached legacy fallback; disabling a compact-view flag
   returns the existing legacy response with no compact marker. There is no
   second undeclared availability/assembler flag.
4. Ship the same Flutter code to iOS and Android. New app binaries opt in and
   safely accept old-backend supersets or 404 fallbacks.
5. Resolution flags roll out independently in this order: bulk writes;
   reason-registry instrumentation while still forcing `FULL`; reason-aware
   scope only after disposable-DB/staging full-vs-incremental parity; burst coalescing; durable
   post tasks; and display-artifact reuse last, only after artifact fallback,
   existing side-effect parity, and the five-minute insurance backstop are proven.
   Before the last flag, prove all old writers exited, complete/resume the §6
   scoring-input-token baseline, and require both missing-token queries to be
   zero.
   Any mismatch flips only that flag off. Do not raise resolution or post-task
   concurrency during the experiment.
   Production never runs a second full shadow scorer merely for comparison;
   that would recreate the load this phase removes.
6. Observe at least six five-minute placement intervals plus one hour of mixed
   traffic before judging the race changes; continue the existing monitor for
   CPU, health latency, endpoint p50/p95, RSS, DB activity/waits, and errors.
   Before rollout, verify the collector parses a synthetic single-line event
   and retains its duration/contract/count fields. The prior multiline monitor
   retained only `[PERF] ... {`, so it is not accepted as endpoint-latency
   evidence. Track the already-observed resolution queue lag, step-write
   uniqueness/deadlock errors, Redis WATCH warnings, and RSS separately as
   baseline anomalies rather than attributing them to this feature.
7. Rollback order for §5.14 is display-artifact reuse → stop **creating** new post
   chains → coalescing → reason-aware scope → bulk writes, restoring the current
   full resolver without rolling back the additive migration. The post runner
   continues draining every pre-rollback unfinished `queued`/`running` group
   and `pending`/`attempting` intent; the synchronous hook is used only for new
   generations that have no chain.
   Disable the runner only after the DB proves zero unfinished tasks and every
   old lease is expired/recovered. Then set
   `RACE_RESOLUTION_POST_TASK_WORKER_DISABLED=true`; the core resolution worker
   remains enabled. After that, disable individual API assemblers and roll
   back the app if necessary. Never remove legacy endpoints during the phased
   App Store window or while frozen builds remain in the wild.

No `testOnly` content gate is needed because no new visible content or asset is
introduced. Production deployment still requires explicit in-the-moment user
approval after implementation/review.

## 10. Tests-first plan

### 10.1 Backend real-HTTP/real-Postgres integration tests

- Frozen client: every legacy endpoint response stays deep-equal with no
  compact marker and all legacy fields/capability gating intact.
- Race bootstrap: pending/active/completed, participant/decliner/nonparticipant,
  tournament spectator, private seeded bucket, team race, release channel,
  remote assets, powerups enabled/disabled, progress optional failure, and
  inventory optional failure.
- Race bootstrap parity: race/progress/inventory components equal the three
  legacy calls from the same fixed snapshot/clock.
- Race query scaling: query-event counts remain bounded from 10 to 300
  participants; bootstrap does not duplicate the deep participant cosmetic
  query; progress compact does not issue per-participant queries. Query-event
  and concurrent-request assertions prove bootstrap/compact progress perform no
  request-path bulk `race_participants` write and do not compete with the fenced
  worker or settlement writer.
- Resolution display refresh: with only the display-artifact flag on, a real
  authenticated progress request at cold miss and 15-second soft expiry returns
  byte-equal live standings, writes the same Redis snapshot, and gives the
  worker one valid artifact so exactly one canonical scorer invocation occurs
  across request plus worker. The worker still performs the same fenced writes,
  raw/box healing, expiry/alert/snapshot, all-user box, and all-user nudge work.
  Redis-unset/outage, TTL expiry, digest/schema/time-zone/trigger mismatch,
  1-MiB/1,000-participant overflow, mixed dirty reason, later generation, and a
  mutation between compute/enqueue/fence all discard the artifact and perform
  the deployed full worker computation without a lost update. Flag-off proves
  the exact current two-pass behavior. Successful/expired artifact keys are
  deleted/TTL-expired and never appear in logs.
  Fixed-clock cases crossing an effect expiry, global-event start/end, race end,
  scoring-zone midnight, closed-sample `periodEnd`, Hitchhike top-of-hour,
  five-second deadline, or balance-config version also prove mandatory full
  fallback immediately before/at/after each boundary.
  Paused interleavings insert/delete/update a participant, team/status scalar,
  daily step, step sample, effect, and global event between artifact compute and
  the fence; the rebuilt fingerprint rejects every phantom/change. A structural
  guard enumerates every step/sample scoring-source writer and fails unless its
  mutation and user-token bump share one transaction. Mixed old/new workers
  cannot enable artifact reuse.
  Name, photo, and equipped-presentation mutations between compute and fence
  prove the worker bulk-rebinds current feed/push/box copy and snapshot
  presentation without a second scorer; an unbindable opaque field forces FULL.
  The same mutations are paused between fingerprint A, an early scorer read,
  and fingerprint B inside the request computation; A/B mismatch emits no
  artifact and the worker performs one full fallback computation.
  Artifact-hit Trail Mine cases prove HTTP bytes remain the legacy pre-mine
  snapshot while the fenced writes/feed use the post-mine result for crossing,
  shielded/blocked, team ally, tied simultaneous crossers, and multiple mines.
- Resolution reason matrix: public step-sync, every powerup cast/auto-activation,
  box open, join/leave/kick/forfeit/start, due-effect, global-boundary, recovery,
  and settlement paths assert the exact internal reason/scope written to the
  real DB and the exact client-visible result. Every catalog/effect type has one
  registry classification; an unknown injected type escalates to `FULL`.
  Targeted-vs-full shadow runs at 1/10/100/350 participants compare totals,
  raw totals, bonuses, placements, teams, Trail Mine outcome/feed, Leech and
  Hitchhike transfers, effect states, boxes, alerts, and notification delivery
  keys from one fixed clock/input snapshot.
  Merging at exactly/above each 1,000-ID and 64-type cap proves that overflow
  becomes one untruncated `FULL` scope and logs counts only.
  Legacy steps/samples claim-race tests pause between source write,
  reconciliation, and enqueue: narrow work is never visible before the uploader
  token commits, a skipped/failed reconcile becomes `FULL`, and a token change
  before the fence recomputes instead of overwriting. Active Trail Mine tests
  cover same-tick multi-crossers/ties, owner/team allies, shields, multiple
  mines, and the required `FULL` fallback. Daily Mover remains byte-/recipient-
  equal to the persisted-source legacy path.
  At 10/100/350 participants, a scoped STEP_SYNC publishes byte-equal progress
  from committed rows with constant SQL statements, one scoped canonical
  calculation, zero full-resolver invocation, and no per-participant scoring or
  cosmetic query.
- Resolution burst/coalescing: 100 concurrent step syncs into the same large
  race produce one bounded first-window claim with unioned trigger IDs and no
  deadline extension; continuous syncs cannot starve a commit. Immediate
  powerup/membership/effect reasons bypass the coalescing wait. Superseded
  discard preserves/merges every dirty reason and trigger, never writes stale
  totals/tasks, and switches to bounded commit when the 15-second guard or a
  non-discardable reason applies. Crash/lease recovery retains the same sets.
- Resolution bulk writes: public sync/powerup flows with 10/100/350 changed
  participants show constant participant-persistence SQL count, exact row
  values/timestamps, omitted-raw and bonus-decrement semantics, frozen/team
  behavior, same-participant total-plus-multiple-bonus normalization, and
  rollback on conflicting duplicate totals or count mismatch. Concurrent uploader reconcile,
  settlement, forfeit, Trail Mine, and two worker claims prove fence-first plus
  ascending lock order has no lost update/deadlock; flag-off row-loop parity is
  exact.
- Resolution post tasks: a separately spawned real test server/worker process
  receives only public mutations and drains the production scheduler against
  the disposable DB. It proves expiry, multiplier/re-arm decisions, box RNG/
  mint/promotion, recent-mint recording, and exact nudge-recipient selection all
  remain in the synchronous deployed order with the same catch/continue
  boundaries. Only already-claimed immutable delivery intents and snapshot
  publication appear in `POSTCOMMIT_DELIVERY`.
  Delayed generation A after generation B proves an unattempted A intent gets
  only its one stored recipient/payload/delivery-key attempt, while a terminal/
  ambiguous A intent is never resent; neither path re-evaluates multiplier/
  standings/boxes, alters re-arm/game state, or publishes A's stale snapshot. Transport
  Generation B never obsoletes A's parent or drops an unattempted A child.
  failures still attempt later intents, never resend a terminal/ambiguous
  intent, classify expired attempts, recover shutdown, and trigger the
  unhealthy inline-claim fallback.
  Crashes before `attempting`, after provider acceptance/before DB
  acknowledgement, before snapshot SET, after SET, and between two intent
  ordinals prove pending resume versus terminal at-most-once behavior. Explicit
  provider rejection/timeout/throw and Redis SET failure each receive one
  application attempt, no retry, while later ordinals still run. Synchronous
  cooldown reservation prevents generation B from selecting A's recipient.
  Payloads at/above 256 KiB and 1,000 intents prove inline fallback with no
  truncation/partial task. Query events at 10/100/350 triggering users prove no
  deferred race hydration or standings scan and a shared total in-flight
  maximum of two. Seven-day cleanup is keyset-batched, kill-switchable, and
  cannot select recoverable/leased rows. Expiry remains driven by the existing
  generation/due-effect scan; no global all-race boundary/notification
  population is added.
- Resolution mixed-version migration: pre-migration-shaped enqueues/default-empty
  metadata resolve `FULL` on the new worker; an old-worker fixture ignores the
  additive fields and still converges; no flag-on claim occurs during rolling
  overlap; rollback leaves additive metadata harmless while the new runner
  drains/classifies every pre-existing delivery/intent row and the legacy full path handles
  every new generation.
  A source write by an old binary immediately before cutover and a new-code
  atomic source-write/token bump during each 500-user baseline batch prove the
  idempotent `ON CONFLICT DO NOTHING` initialization loses no version. Artifact
  enablement remains blocked until the set-based missing-token proofs are zero;
  killing/resuming the baseline yields the same rows.
  Rollback coverage turns task creation off with queued/running/pending/
  attempting rows,
  proves old chains drain before the runner stops, and proves new generations
  use only the synchronous hook with no double execution.
  With `RACE_RESOLUTION_POST_TASK_WORKER_DISABLED=true`, startup registers no
  post timer, a live tick stops new claims, queued rows remain byte-identical,
  readiness forces new inline delivery, and the core resolver continues; unset
  resumes the old queue.
- Message streams: `includeUser` absent/true/false/malformed semantics;
  USER/SYSTEM parity when combined; Activity-only SYSTEM parity; exact
  watermark empty/tie/new-message/deleted-message parity; exact absent/
  malformed/zero/negative/fractional/over-100/positive-infinity/
  negative-infinity limit normalization; per-requested-stream top-page
  `nextCursor` parity; ignored cursor on the new endpoint; separate legacy
  cursor-pagination coverage; cache cold and warm; sender deletion, stealth
  redaction for owner/opponent, tournament spectator, declined access, and a
  message committed between polls. Activity-only mode executes no USER-body or
  sender-presentation query. Body-free watermark cache cold/warm parity,
  15-minute TTL, environment/version key isolation, WATCH-race retry, and
  send/delete/membership invalidation are exercised without ever materializing
  a body/sender field. Cache flag-off, Redis unset/failure, and direct-Postgres
  fallback return the same response. Warm legacy and combined polls issue no
  cosmetic graph query and have bounded SQL counts from 10 to 750 members.
- Friends summary: exact order/pending parity at 0/1/750 friends, no cosmetic or
  step query, and no `requestStepSyncForUsers` call through the public route.
- Compact auth: explicit allowlist, null capability fields, every runtime flag,
  app-version-gated step bucket, held coins/incoming count, and proof that a new
  Prisma scalar cannot leak. Legacy auth remains unchanged. Alternate compact
  and legacy cold/warm requests under mixed workers and prove their Redis keys,
  values, and invalidations cannot cross-serve response shapes.
- Home shell: existing race-card deep equality; presentation/equipped/cape
  parity across channel/capability variants; friend-summary parity; component
  fallback/error isolation.
- Get Coins: status/ad/referral values equal legacy sources while query events
  prove no box odds, accessory pool, powerup pool, referral-code, or referral
  friends query.
- Public browser: all list parity, seed/capability hiding, featured
  reconciliation, mine summary, partial optional failure, and no personal
  race/result query.
- Ranked V2: compact visible-field parity and query proof that equipped
  accessories/shop items are not joined; legacy V2 and legacy Ranked retain
  cosmetics.
- Profile stats: timezone/date-boundary, zero/missing today, zero day breaking a
  streak, multi-year and empty history parity; constant SQL statement count and
  no legacy ranked lookup.
- Shop bootstrap: exact component parity, true parallel start through an
  injectable barrier, optional component failure, and all existing feature and
  release gates.
- Tournament detail: public HTTP parity for PENDING/ACTIVE/COMPLETED and
  4/8/16 brackets; first-round and complete 15-race histories; participant,
  invitee, declined user in public and private pending tournaments, eliminated
  spectator, outsider/privacy, seed-prize fallback,
  tie/forfeit, Stealth/Detour owner/opponent, photo/name, current matchup, and
  exact ordering. Query events prove compact detail never touches matchup-user,
  equipped-accessory, or shop-item relations and stays bounded as race history
  grows. Every legacy GET/mutation stays deep-equal. Every route/branch in the
  §5.13 table asserts its exact compact status, key set, and nullability.
  Compact and ignored-view mutation responses preserve action keys and wallet
  commit state; concurrent join/accept/refund cases prove the wallet is
  post-commit and tournament state is not stale. Forced post-commit projection,
  wallet, and combined failures remain committed `2xx`/`201` successes and
  expose only their named null/error pairs. Wallet parity proves direct
  Postgres values equal current `/auth/me`, including the existing race-only
  `heldCoins` definition.
- Mutation results: purchase/equip/ad-unlock/idempotent replay already return
  every delta the frontend needs; add public-path assertions where a field is
  currently implicit.
- ETag: first `200`, matching `304` empty body, changed representation/new ETag,
  `If-None-Match` list/weak/`*` behavior, `Vary: X-App-Version`, capability
  fingerprint persistence, `Vary: X-Client-Features`, capability variant safety,
  and no auth/cache leak.
- Performance logs: required aggregate fields exist as parseable single-line
  JSON, the line-oriented monitor retains every field, and forbidden PII does
  not.
- Flags: all nineteen off, all nineteen on, each flag independently on with every
  other flag off, flag-read errors, Home/friends independence, and
  race-bootstrap/progress independence. A flag-off view is legacy and a
  flag-off new endpoint is `404` with no optimized-path side effect.

Redis-backed tests use only a verified local test Redis URL selecting database
`15`; they must flush only db15 before/after their cases. Production/staging
Redis URLs are forbidden. Run the relevant suites once with that test Redis and
again with `REDIS_URL` unset to prove complete Postgres/legacy fallback. Update
the documented auth key table and `src/shared/cache/cacheKeys.js` enumeration
to include the `legacy|shell-v1` contract axis in addition to the existing
fine-bucket axis, and assert invalidation deletes every Cartesian variant. The
same db15/unset matrix covers the body-free watermark key, including proof that
no full USER cache value is fetched to answer Activity-only mode.

Integration tests import only shared test setup, call public HTTP boundaries,
and verify `DATABASE_URL` names a disposable test database before any write.
Unit tests are reserved for pure ETag hashing, date aggregate SQL-result mapping,
closed reason/powerup-registry exhaustiveness, dependency-closure and queue-set
algebra, or structural source guards that cannot be expressed through HTTP.

### 10.2 Frontend widget/integration tests

- Race detail renders identical pending/active/completed/spectator states from
  bootstrap; 404 fallback uses the current parallel calls.
- Race open constructs Activity but not Chat, makes one Activity-only stream
  read, and keeps at most one stream read per five-second foreground interval.
  A successful initial watermark is a no-unread baseline; an initial failure
  establishes the current empty baseline/mark-read behavior so a later
  successful non-empty watermark raises unread. Later malformed/missing
  watermarks retain state. The first Chat tap makes one immediate combined read,
  shows the existing loading/error/retry UI while pending or failed, preserves
  optimistic send/merge behavior during the initial load for eligible users,
  and then keeps combined mode. Completed
  races leave Chat unloaded until tap and never poll. New-endpoint 404 fallback restores
  the exact legacy eager/two-poller unread behavior and caches unsupported.
  An Activity response already in flight cannot overwrite the combined mode
  chosen by a Chat tap. No progress-triggered duplicate;
  pause/resume/dispose, pagination, optimistic send, retry, and mark-read remain
  correct.
- Active progress and global inventory remain 30-second fresh through one
  compact response; action deltas update immediately; missing compact inventory
  preserves the standalone legacy refresh and malformed deltas trigger one
  affected refresh.
- MainShell compact Home path performs no `/shop/catalog`, `/friends/steps`, or
  duplicate `/auth/me`; each missing compact block triggers only its fallback.
- Friends tab, request sheets, invite picker, mutation invalidation, badges,
  empty state, ordering, and eligibility render exactly from shared state.
- Get Coins uses the compact block, retains full Daily Reward navigation, and
  falls back only for missing referral rewards.
- Public Races uses one browser request; partial `resolved:false` triggers only
  the missing legacy branch; all existing sections/actions render unchanged.
- Ranked V2 rows render without cosmetics and legacy 404 fallback remains.
- Profile totals/averages/streak render unchanged with omitted legacy fields.
- Shop bootstrap, optional powerup failure, all mutations, idempotent replay,
  and affected-component fallback preserve existing loading/error/toast state.
- Tournament Detail renders the same lobby/live/completed bracket from compact
  and legacy supersets; initial open and each visible 60-second tick make one
  request; valid action-returned state causes no detail refetch; malformed or
  post-commit-unavailable state causes exactly one fallback; wallet delta avoids
  `/auth/me` and absent/unavailable wallet preserves it. Route visibility stops
  hidden timers and performs one return refresh even across background/resume;
  cover Race→Tournament, Tournament→Race, Tournament→Friend Picker, one
  Race→non-Tournament full-screen route, and a representative modal route.
- Static reads reuse a validated body on `304`, retry a cacheless `304`, and
  preserve existing failure behavior.
- Every new server field is absent/null/wrong-type tested. No unchecked cast or
  bare null assertion is introduced for server data.
- Demo/tutorial tests render the real race screen with all new fake overrides;
  the network guard scans the new coordinator/API methods and fails if any path
  can escape to the configured backend.

## 11. Acceptance criteria

- [ ] No gameplay, economy, odds, privacy, notification, or freshness behavior
      differs from the legacy paths. The only approved visible difference is
      the existing Chat loading/error UI on the first Chat tap because hidden
      USER bodies are no longer prefetched.
- [ ] On a capable backend, a foreground active race makes one message-stream request per five-second
      interval, one progress request per 30 seconds, and no periodic global
      inventory request: approximately 14 steady-state GETs/minute rather than
      about 32. Until Chat is first opened, the stream contains Activity plus a
      Chat watermark and performs no USER body/presentation read.
- [ ] Race entry uses at most one bootstrap plus one Activity-only stream
      request on a capable backend; Chat state is not constructed and no
      duplicate full participant/cosmetic hydration occurs.
- [ ] Warm message polling never executes the deep race cosmetic graph query.
- [ ] Progress/bootstrap SQL statement counts are bounded as participants grow;
      no per-participant query path exists.
- [ ] A pure cold/soft-expired progress display refresh performs exactly one
      canonical scoring computation across request plus worker while preserving
      the existing generation, fenced participant healing/writes, and complete
      post-commit behavior; unsafe/missing artifacts fall back to the current
      worker computation.
- [ ] Step sync and every state mutation still converge to byte-/row-equivalent
      full-resolution totals and side effects. Unknown scope always escalates to
      `FULL`; no scoring, box, effect, Trail Mine, Leech, Hitchhike, placement,
      team, alert, or notification behavior changes.
- [ ] Sync bursts coalesce within the existing five-second magnitude without
      deadline extension or starvation; immediate reasons remain immediate.
      Superseded discarded work creates zero writes/tasks and loses zero dirty
      reasons/users.
- [ ] Participant persistence uses bounded SQL statements at 10/100/350 rows,
      retains fence-first/ascending locks, and has no lost update/deadlock under
      uploader/worker/settlement contention.
- [ ] Core scoring preserves synchronous expiry, alert/re-arm decisions, box
      RNG/mints/repairs, and nudge-recipient selection, but no longer waits for
      snapshot cache publication or already-decided push/step-sync transport.
      Durable tasks give each immutable delivery/snapshot operation the same
      single application attempt as today and never re-evaluate old gameplay;
      only a superseded snapshot is omitted as it is today.
- [ ] With all resolution flags enabled, production-safe evidence reports runs
      by reason/race-size, superseded compute/write rates, core and post-task
      p50/p95, queue lag, API health latency, CPU, and DB waits. It specifically
      compares the two 350-member seeded-race cohort against the 8,056-run/
      62%-worker-time four-hour baseline without exposing race or user IDs.
- [ ] Home's capable path does not call `/shop/catalog`, `/friends/steps`, or a
      duplicate cold-start `/auth/me`.
- [ ] Compact friends performs no step reads and sends no sync push.
- [ ] Get Coins performs no reward-pool/referral-dashboard construction.
- [ ] Public Races does not fetch the full personal `/races` payload.
- [ ] Ranked V2 compact does not query cosmetic relations.
- [ ] Profile compact does not materialize all daily history in JavaScript or
      perform a legacy ranked lookup.
- [ ] Shop starts its three reads together and successful mutations never
      refresh an unrelated catalog.
- [ ] Tournament Detail first paint and 60-second polling use the compact graph,
      never query participant cosmetics/shop items, and preserve every rendered
      bracket/action/privacy state. A valid mutation response produces zero
      redundant tournament GETs and an authoritative wallet avoids `/auth/me`.
- [ ] A Race or Tournament route covered by any pushed route/modal performs no
      hidden polling and catches
      up exactly once when visible again.
- [ ] Static `304` responses preserve launch/resume force-update correctness.
- [ ] Old apps against the new backend and the new app against an older backend
      pass explicit integration/widget coverage.
- [ ] Staging or production-safe evidence records request count, SQL count,
      response bytes, and p50/p95 before and after for every named surface.
- [ ] Production performance events are complete parseable single-line records;
      monitor evidence that captured only an opening brace is rejected rather
      than reported as an endpoint latency result.
- [ ] No new endpoint logs PII; no tests touch production data.
- [ ] Backend focused/full tests and Flutter focused/full tests pass, or every
      unrelated pre-existing failure is isolated and reported without weakening
      an assertion. `flutter analyze` is clean before this work is called done.
- [ ] iOS and Android are both accounted for, architect approves the spec, and
      the combined implementation receives a code-reviewer `SHIP` verdict.
- [ ] Production remains untouched until a new explicit deploy approval.

## 12. Open questions

None currently. The audit already fixed the product constraint: this is the
entire cleanup, performance-only, with unchanged visible freshness and additive
compatibility paths.

## 13. Revision log

- **Draft v1:** Converted the source audit into versioned, additive contracts;
  chose opt-in views on existing endpoints where an older backend can safely
  return a usable superset; limited new endpoints to race and Shop bootstraps;
  preserved five-second chat/activity and 30-second progress freshness; pinned
  old-app/new-backend and new-app/old-backend fallbacks; and added query/byte/
  latency evidence gates.
- **Gap pass 1:** Distinguished usable legacy supersets from responses that
  truly require a fallback so ignored views never cause duplicate reads; gave
  combined USER/SYSTEM polling independent failure isolation plus overlap and
  generation guards; carried the incoming-friend count in the shared snapshot
  so removing `/auth/me` cannot stale the badge; made persisted version policy
  fail open until revalidated; and pinned twelve exact default-false rollback
  flags with flag-read-failure behavior.
- **Gap pass 2:** Made race bootstrap reconcile once before emitting a coherent
  detail/progress state; gave Home optional blocks independent failure isolation;
  replaced an undefined friends “fresh” period with a one-second duplicate
  coalescing window while retaining every existing refresh trigger; required one
  coherent runtime-flag snapshot; kept global inventory 30-second fresh by
  embedding it in compact progress instead of silently accepting cross-device
  staleness; made Shop `localDate` optional/compatible; and pinned conditional
  request list semantics plus `Vary: X-App-Version`.
- **Architect review round 1 — REVISE:** Replaced the ignored
  message view with an additive `/message-streams` endpoint so old backends
  downgrade once on a definite `404` instead of doing three polls; retained
  Profile's visible email in compact auth; separated legacy/shell auth cache
  variants and their invalidation; varied powerup-copy validation on client
  features; and prevented historical idempotency replay JSON from regressing
  local wallet/inventory state by refreshing only the affected component. Also
  enumerated demo/tutorial fake and network-guard work; moved Shop bootstrap
  composition into an injected feature module; pinned exact top-snapshot limit
  and cursor behavior; corrected the capability-cache count to three; required
  isolated local Redis db15 plus Redis-unset coverage and cache-key enumeration;
  prohibited a second request-path participant writer; and carved out a safe
  non-production query-plan tool while retaining real-HTTP behavior coverage.
  Adopted the optional suggestion to key persisted powerup body/ETag state by a
  capability fingerprint.
- **Architect review round 2 — REVISE:** Corrected exact two-stage legacy limit
  parity so positive infinity/`1e999` clamps to `100` while negative infinity
  and NaN default to `50`; added those HTTP cases; and removed an ambiguous
  rollout sentence that implied an undeclared second flag. New-endpoint flag-off
  is now unambiguously `404` plus cached client fallback, while compact-view
  flag-off is the legacy response.
- **Architect review round 3 — APPROVE:** No required or optional findings.
- **Scope expansion — lazy Chat and Tournament Detail:** Replaced race-entry
  USER hydration with Activity plus a stable Chat watermark, kept old-backend
  fallback lazy, and pinned first-tab activation/completed-race/read-ack
  semantics. Added an opt-in tournament detail projection that removes unused
  creator/champion, matchup-user, cosmetic, shop-item, and broad scalar loads;
  retained complete 60-second snapshots; consumed authoritative mutation
  responses/wallet deltas; and suspended pollers behind covered routes. Added
  max-bracket query evidence and single-line telemetry requirements after the
  production monitor proved multiline endpoint events were truncated. This
  expansion invalidates the earlier architect approval until fresh gap passes
  and a new architect review complete.
- **Expansion gap pass 1:** Replaced an unsafe scalar watermark comparison with
  the bounded recent-ID set used only for unread detection, so equal-timestamp
  UUIDs and current top-page/deletion semantics are preserved; required
  combined mode to derive that metadata from its existing USER page. Split
  tournament mutations into screen-remains compact-detail responses versus
  navigate-away action/wallet responses so leave/decline/cancel do not rebuild
  a discarded bracket. Made timer eligibility explicitly depend on both route
  visibility and app lifecycle, and made monitor telemetry single-line and
  parser-tested.
- **Expansion gap pass 2:** Restored the exact eager two-poller behavior only
  when a new app receives a definite message-stream `404`, because an old
  backend cannot preserve the unread dot without reading USER rows; the capable
  backend remains lazy. Prevented an in-flight Activity response from
  downgrading combined mode after a Chat tap, pinned watermark behavior to the
  existing top-page ID-difference semantics, and made post-commit wallet fields
  required on compact money-changing tournament actions with defensive
  `/auth/me` fallback only for old/disabled/malformed responses.
- **Expansion architect review round 1 — REVISE:** Added a separately flagged,
  body-free, version-fenced Chat watermark cache so lazy polling neither reads
  message bodies nor hits Postgres every five seconds; restored current unread
  recovery after an initial failed load; and declared the first-tap loading
  interval as the one approved visible tradeoff, including optimistic-send and
  retry parity. Corrected Tournament's cosmetic omission allowlist to the real
  `animal`/`accessories` serializer keys; pinned every compact mutation's
  status/key envelope; made post-commit projection/wallet failures committed
  successes with one narrow fallback; preserved the existing race-only
  `heldCoins` definition; and generalized hidden-poller suspension to real
  route visibility, including non-Race/Tournament covering routes. Added the
  declined-user privacy cases suggested by review.
- **Expansion architect review round 2 — REVISE:** Pinned the exact logical
  watermark key `v1:race:msgwatermark:{raceId}:USER`, its environment prefix,
  key builder/all-keys enumeration, canonical Redis key-table entry, and
  operational runbook flag entry.
- **Expansion architect review round 3 — APPROVE:** No required findings or
  suggestions remained for lazy Chat/Tournament Detail.
- **Scope expansion — reason-aware race resolution:** Distinguished the already
  fixed Mystery Box/Trail Mine hydration duplication from the remaining
  15-second display-recompute → full-worker double pass. Added five independent
  default-false backend flags for display-artifact reuse, closed dirty scopes,
  burst coalescing, ordered bulk writes, and durable post-commit tasks; added
  one additive queue/task migration and the 8,056-run production baseline. This
  expansion invalidates the preceding approval until fresh architecture and
  scoring-safety reviews complete.
- **Resolution gap pass 1:** The initial no-enqueue design failed parity because
  a display generation also heals raw/box state and drives alert/nudge hooks.
  Replaced it with a bounded single-use Redis artifact: the worker keeps the
  generation, fence, writes, and side effects but reuses the request's canonical
  result instead of scoring twice; every uncertainty falls back to full.
- **Resolution gap pass 2:** Required incremental sync work to consume the
  version-fenced already-persisted uploader result and reuse canonical scoring primitives,
  with transitive dependency closure and `FULL` fallback whenever composition
  is not exact. Pinned starvation/supersession guards, ascending row-lock plus
  bounded bulk-update semantics, deterministic task keys/dependencies, mixed
  old/new worker safety, and separate core-versus-total resource evidence so
  moving post work cannot masquerade as eliminating it.
- **Resolution architecture/game review round 1 — REVISE/UNSOUND:** Removed the
  proposed independent effect/global boundary fan-out and fresh Daily Mover
  source; made active Trail Mines conservative `FULL`; closed enqueue-before-
  reconcile causality; preserved whole-box-then-nudge decision ordering; narrowed
  deferred work to immutable, already-claimed transport/publication intents so
  old gameplay is never re-evaluated; added unhealthy inline fallback, shared
  two-lane concurrency, bounded task payloads/retention, and an exact committed-
  row snapshot assembler. Artifact review also added complete pre/post input
  fingerprints, time-boundary fencing, pre-mine HTTP/post-mine write views, and
  safe scoring-token baseline requirements. These corrections require a fresh
  re-review.
- **Resolution architecture/game review round 2 — APPROVE/SOUND:** Added the
  final phantom/coherent-input fingerprint and token-baseline gates, sample/
  Hitchhike time boundaries, Trail Mine pre-/post-detonation split, fresh
  presentation rebinding, single-attempt per-intent delivery crash semantics,
  exact normalized intent storage, and an independent post-runner kill switch.
  No required findings or suggestions remain; game/economy EV and daily source/
  sink deltas are zero.
