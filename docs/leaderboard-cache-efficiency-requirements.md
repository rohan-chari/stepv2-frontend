# Leaderboard cache efficiency requirements

## Summary & user story

When a signed-in user opens the leaderboard, changes period or scope, returns
to a recently viewed period, or refreshes the page, the app should avoid
repeating work that is already fresh while preserving the current response
shape and freshness behavior.

The current Flutter page requests `GET /leaderboard` for the steps board. The
backend already caches ranking cores, friend topology, and user presentation,
but one backend path still causes avoidable work:

1. A global-board viewer outside the cached top 100 falls through to the full
   PostgreSQL rank calculation on every request.
The cache-key eligibility epoch is also read from PostgreSQL on every cached
request, but that read is a deliberate correctness fence and will remain.

The page also discards results for previously viewed period/scope combinations
when its widget state is recreated or when the user switches back to a recent
selection.

## Scope / non-goals

### In scope

- Add a short-lived Redis cache for the global viewer-specific rank fallback.
- Keep the eligibility-epoch PostgreSQL read as a correctness fence; do not
  trade visibility correctness for one fewer small query.
- Add a bounded, short-lived in-memory Flutter cache keyed by leaderboard scope
  and period.
- Preserve the current `/leaderboard` request and response contract.
- Preserve the current 15-second soft / 60-second hard ranking freshness model.
- Preserve Redis fail-open behavior and PostgreSQL correctness fallbacks.
- Add tests first at the public/integration or real-widget path wherever the
  behavior is observable.

### Out of scope

- No new endpoint, response field, database table, migration, release flag, or
  rollout percentage.
- No caching of the final capability-shaped HTTP response in Redis.
- No change to step ingestion, ranking rules, visibility policy, friendship
  semantics, or product policy.
- No change to the race leaderboard path; the current Flutter page requests
  `type=steps` only.
- No visible layout, copy, or navigation change.
- No production deployment or upload as part of implementation.

## Existing behavior and touch points

### Flutter

- [`lib/screens/tabs/leaderboard_tab.dart`](../lib/screens/tabs/leaderboard_tab.dart)
  owns the selected period/scope, calls the API on initial load, selection
  changes, and refresh, and retains the previous board while refreshing.
- [`lib/services/backend_api_service.dart`](../lib/services/backend_api_service.dart)
  sends `type=steps`, `period`, `scope`, and `view=compact-v1` to the existing
  endpoint.
- [`lib/screens/main_shell.dart`](../lib/screens/main_shell.dart) owns the
  shared API service and is the natural owner for the app-session cache passed
  into the tab.
- [`lib/screens/leaderboard_screen.dart`](../lib/screens/leaderboard_screen.dart)
  hosts the standalone leaderboard and must receive the same cache when it is
  opened from the main shell.
- `SharedPreferences` currently stores only the selected Global/Friends scope;
  leaderboard response data is not persisted locally.
- Existing real-widget coverage includes scope selection and persistence in
  `test/leaderboard_tab_scope_test.dart` and
  `test/leaderboard_scope_persistence_test.dart`.

### Backend

- [`src/modules/leaderboard/getLeaderboard.js`](../../stepv2-backend/src/modules/leaderboard/getLeaderboard.js)
  selects the Redis ranking path, assembles cached cores with presentation,
  and falls back to the legacy PostgreSQL path.
- [`src/modules/leaderboard/services/stepLeaderboardCache.js`](../../stepv2-backend/src/modules/leaderboard/services/stepLeaderboardCache.js)
  implements the 15-second soft / 60-second hard ranking cache and single-flight
  rebuild behavior.
- [`src/shared/cache/cacheKeys.js`](../../stepv2-backend/src/shared/cache/cacheKeys.js)
  owns logical Redis key construction.
- [`src/shared/config/leaderboardEligibilityEpoch.js`](../../stepv2-backend/src/shared/config/leaderboardEligibilityEpoch.js)
  reads the epoch from `app_settings`; visibility changes and account deletion
  advance it transactionally.
- [`src/modules/social/services/friendsTopologyCache.js`](../../stepv2-backend/src/modules/social/services/friendsTopologyCache.js)
  and [`src/modules/social/services/userPresentationCache.js`](../../stepv2-backend/src/modules/social/services/userPresentationCache.js)
  already provide the friends/presentation cache layers needed by the page.
- Existing real-HTTP Redis coverage is in
  `test/integration/redis-social-reads.test.js`; cache safety coverage is in
  `test/services/socialReadCacheSafety.test.js`.

## Proposed behavior

### A. Cache global viewer rank outside the top 100

Add a viewer-specific derived cache containing only the global viewer scalar:

```json
{
  "version": 1,
  "scope": "global-viewer",
  "period": "today",
  "boundary": "2026-09-11",
  "rank": 137,
  "totalSteps": 4200,
  "asOf": "2026-09-11T15:00:00.000Z",
  "buildStartedAt": "2026-09-11T15:00:00.000Z"
}
```

Use this exact logical key shape (the existing environment prefix is added by
`redisCache`):

```text
v1:leaderboard:steps:viewer-rank:{viewerId}:{eligibilityEpoch}:{period}:{boundary}
```

The key includes:

- viewer ID;
- eligibility epoch;
- period;
- resolved date boundary (`all` for all-time).

The cache must use the existing 15-second soft / 60-second hard freshness
contract, single-flight rebuild, lock protection, validation, and Redis
fail-open fallback. It must never contain or replace the shared global top-100
core. It is part of the existing permanently-enabled
`redisCacheLeaderboardEnabled` surface; do not add a new release flag.

On a global request where the shared top-100 core does not contain the viewer:

1. Read the viewer-rank cache.
2. On a fresh or stale hit, use its rank/total and the shared top-100 rows.
3. On a miss, calculate the existing aggregate plus users-above query once,
   publish the viewer scalar, and assemble the existing response.
4. On Redis failure, malformed data, or an expired/missing value, use the
   existing PostgreSQL fallback and return the same response shape.

The cached viewer scalar must include the eligibility epoch, so visibility
changes and account deletion move requests to a new key without requiring a
best-effort Redis delete. It must not be keyed only by user and period.

The loader must preserve the legacy semantics exactly: the viewer's own step
aggregate is unfiltered, the `usersAbove` grouping applies the global
`isReviewAccount=false` and `hiddenFromLeaderboard=false` filters, ties use
`usersAbove.length + 1`, and the assembled response sets
`inTop10=false` and `inTop100=false`. Reject malformed or mismatched payloads
instead of serving them.

Step-sync writes do not advance the eligibility epoch. The existing 15-second
soft / 60-second hard ranking freshness window is therefore the accepted
staleness bound for both the shared ranking core and the viewer scalar. Profile
or cosmetic writes do not affect the scalar; presentation invalidation already
handles those fields separately. Friendship mutations do not affect the global
scalar.

### B. Keep the eligibility epoch as a database fence

Do not cache this value. A stale epoch can select an old global ranking key
after `setLeaderboardVisibility` or account deletion commits. PostgreSQL and
Redis cannot update atomically, and Redis invalidation/pub-sub can be lost.
The existing `app_settings` lookup remains the key-generation fence. This is a
deliberate non-optimization; the viewer-rank cache must not weaken it.

### C. Add a bounded Flutter recent-result cache

Add an injectable app-session in-memory cache service, shared by the main-shell
leaderboard tab and standalone leaderboard host. It must outlive tab disposal
but must not be a process-global unscoped singleton in tests. Key entries by:

```text
(backendUserId, scope, period)
```

Each entry stores the defensively parsed `top100`, `currentUser`, and the
timestamp of the accepted response. Use a short client TTL aligned with the
server soft window; the initial proposal is 15 seconds.

Behavior:

- Initial load: use a valid local entry if present; otherwise request the
  backend.
- Period/scope switch: use a valid matching entry immediately and optionally
  refresh it only after it is stale.
- Pull-to-refresh: bypass the local entry and request the backend.
- A failed request must preserve the existing visible data and must not replace
  a valid cached entry with an error.
- Cache is process-memory only and is never written to `SharedPreferences`.
- If `authService.userId` is missing, do not read or write the recent-result
  cache. The account ID must be the backend user ID, not a display name or
  provider subject.
- Account identity is part of every key, so a sign-out/sign-in transition
  cannot display another account's result. The owning session may also clear
  all entries on sign-out as a bounded-memory cleanup.
- Keep at most the eight combinations for the current backend user (two
  scopes × four periods); evict older-account entries and any unexpected
  overflow. Do not persist these entries across launches.

The cache must not alter loading, empty, error, or refresh UI semantics. It only
changes whether a recent result is immediately available.

## API contract

No endpoint or JSON contract changes are required.

The backend continues to support older clients that omit `scope`, send the
legacy response aliases, or do not send `view=compact-v1`. The new caches are
internal implementation details. The existing `/leaderboard` response remains
compatible:

```json
{
  "top10": [],
  "top100": [],
  "currentUser": {}
}
```

The frontend must continue defensive parsing for missing/null fields. A cache
miss or cache failure must be indistinguishable from the existing PostgreSQL
path at the HTTP boundary.

The Flutter recent-result cache must only store a response after the existing
parser accepts a usable `top100`/`currentUser` result. A legacy or malformed
response that contains only `top10` must not poison a cache entry with an
empty board; the app retains its current safe parsing behavior and can request
again.

## Data model / migrations

No database schema change or migration is planned.

The source of truth remains the `steps`, `users`, `friendships`, and
`app_settings` data already used by the endpoint. Redis entries are rebuildable
derived data only.

New logical Redis key(s) must be versioned and namespaced through the existing
`redisCache` wrapper. Define TTL, source of truth, invalidation, malformed-value
handling, and Redis-unavailable behavior in the cache module and tests.

## Exact implementation path

### Backend, contract and tests first

1. Add the viewer-rank cache key builder and cache service alongside
   `stepLeaderboardCache`, reusing validation, single-flight, locks, and the
   existing freshness constants where appropriate.
2. Extend `getLeaderboard` only for the global steps path. Keep friends and
   race behavior unchanged unless shared helper extraction is behaviorally
   neutral.
3. Ensure the existing global top-100 cache remains shared and does not acquire
   viewer-specific fields.
4. Do not add an epoch cache or release flag. Keep the existing epoch database
   read as the correctness fence.
5. Emit the existing social-cache style outcomes for viewer-rank fresh hit,
   stale hit, miss/rebuild, malformed value, and PostgreSQL fallback so the
   optimization can be measured after deployment.
6. Add backend tests before implementation logic:
   - real HTTP warm global request for a viewer outside the top 100 avoids a
     second rank fallback query, with query counts asserted;
   - viewer-rank cache keys vary by viewer, period, boundary, and epoch;
   - stale values are served within the soft window and rebuilt in the
     background;
   - hard-expired, malformed, disabled, and Redis-error cases use PostgreSQL;
   - visibility changes cannot reuse a pre-change viewer/ranking result because
     the epoch is part of the key;
   - step-sync changes are reflected within the existing 15s/60s freshness
     contract rather than relying on unbounded viewer-rank data;
   - old-client request shapes and response aliases remain unchanged;
   - the friends and race paths retain their existing query/cache behavior.
7. Run the focused backend integration suite against dedicated local/test
   Postgres and disposable Redis only. Include two independently configured
   HTTP workers sharing that test Redis/Postgres for the warm-cache case. Never
   use production data.

### Frontend

1. Add a small testable `LeaderboardResultCache` service and inject one
   app-session instance from `MainShell` into both the tab and standalone
   leaderboard hosts. Tutorial/demo hosts may use their own injected test
   instance. Avoid adding networking outside `BackendApiService`.
2. Write real-widget tests first:
   - switching back to a fresh previously loaded period/scope does not issue a
     second API call;
   - disposing and recreating the leaderboard host with the same cache instance
     can reuse a fresh result;
   - a stale entry triggers one backend refresh and keeps old data visible while
     loading;
   - pull-to-refresh bypasses the local cache;
   - request failure preserves the prior board and cached result;
   - the cache is cleared or isolated when the authenticated user changes;
   - an older/malformed response does not poison the local cache and missing or
     null backend fields still follow the existing defensive parser;
   - an in-flight response captured for account A is discarded after the
     mounted auth state changes to account B.
3. Keep the existing scope-persistence tests and add coverage without weakening
   any existing assertion.
4. Run `flutter analyze` and the focused leaderboard widget tests before the
   full Flutter suite.

## Backward compatibility and rollout

- Backend first, then app, as required by the repository contract.
- Older app versions continue calling the same endpoint and receive the same
  response shape; they benefit from the backend cache changes automatically.
- Newer app versions continue working against an older backend because the
  Flutter recent-result cache is entirely local and does not require new
  fields or endpoints.
- Redis remains an accelerator only. A disabled, unavailable, malformed, or
  stale cache always has a PostgreSQL fallback.
- No runtime feature flag or rollout percentage is introduced.
- No production deployment is included in implementation approval; production
  deployment requires a separate explicit confirmation.

## Acceptance criteria / definition of done

- Repeated global requests from a viewer outside the top 100 do not repeat the
  expensive viewer-rank PostgreSQL work within the cache freshness window.
- Eligibility changes cannot serve a result from the previous eligibility
  epoch; the epoch remains a PostgreSQL key-generation fence.
- Re-selecting a recently viewed period/scope can render from the local cache
  within its TTL, while pull-to-refresh still forces a request.
- The local cache never exceeds the defined per-account bound and never serves
  data under a different backend user ID.
- HTTP response JSON is unchanged for old and new clients.
- Redis failure and cache corruption preserve successful PostgreSQL behavior.
- All new tests are written first and pass.
- Backend integration tests use only dedicated local/test Postgres and
  disposable Redis.
- `flutter analyze` is clean; relevant Flutter tests and the full Flutter suite
  pass.
- Both iOS and Android remain covered because the change is shared Dart logic;
  no platform-specific release configuration is changed.
- The post-implementation `code-reviewer` review reports no blockers.

## Manual UI-placement test plan

Not applicable. This plan changes only data loading/caching behavior; it does
not add, move, remove, or restyle anything visible on the leaderboard or its
mirrored tutorial/demo surfaces. Manual checks should still confirm that the
existing loading, refresh, empty, error, Global, and Friends states render as
before.

## Revision log

- Initial draft: captured the backend viewer-rank gap and the approved optional
  Flutter recent-result cache.
- Gap pass 1: added account isolation, pull-to-refresh bypass, Redis failure
  behavior, older-client compatibility, and the explicit race-path non-goal.
- Gap pass 2: added the eligibility-epoch correctness gate, transaction-commit
  ordering, no-flag rule, test-first requirements, and the distinction between
  shared global ranking data and viewer-specific rank data.
- Gap pass 3: changed the Flutter cache from widget-local state to an injected
  app-session cache so it survives tab disposal without becoming an unscoped
  process-global cache; added backend-user-ID keying and a no-cache path when
  identity is unavailable.
- Architect review: rejected the eligibility-epoch cache as unsafe because
  Postgres and Redis cannot update atomically; retained the database read as a
  correctness fence. Required exact viewer-rank key/validation semantics,
  explicit step-sync staleness bounds, account-switch late-response handling,
  legacy-response cache protection, and query-count/two-worker integration
  coverage. No new release flag will be added; the viewer scalar uses the
  existing permanent leaderboard cache surface.
