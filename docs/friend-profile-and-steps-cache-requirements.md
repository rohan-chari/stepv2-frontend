# Friend profile and friend-steps cache requirements

**Status:** Revised after architect review — awaiting owner approval

**Owner request:** Reduce avoidable Postgres reads from friend-related surfaces.

**Scope:** Backend only. No Flutter API, response-shape, navigation, layout, or
loading-state change.

## 1. Summary & user story

The main Friends roster already uses Redis for friendship topology and user
presentation. Two related reads still perform avoidable database work:

1. `GET /friends/steps` reloads the accepted friendship/user presentation join
   on every request even though the same topology and presentation caches are
   already used by `GET /friends`.
2. `GET /friends/:userId/profile` reloads user presentation/equipment and runs
   an expensive aggregate statistics query on every profile open.

As a user, opening a friend picker or a friend's profile should reuse the same
fresh, correctly capability-filtered social data as the Friends tab. As the
operator, Redis should only hold rebuildable derived data; Postgres remains the
source of truth and every Redis failure must preserve the existing response.

Current implementation anchors:

- The shipped Friends tab requests `GET /friends?view=summary-v1` through
  `FriendsSummaryRepository`, which only coalesces/reuses results in memory for
  one second: `lib/services/friends_summary_repository.dart:7-65` and
  `lib/services/backend_api_service.dart:2029-2038`.
- `GET /friends/steps` currently calls
  `Friendship.findAcceptedFriendsWithDisplay` before reading the existing
  daily-step cache: `src/modules/social/queries/getFriends.js:147-185`.
- The public profile route currently calls a user/equipment query and then the
  profile statistics SQL query on every request:
  `src/modules/social/queries/getPublicProfile.js:100-130`.
- The existing topology cache is generation-guarded and invalidated after
  friendship mutations: `src/modules/social/services/friendsTopologyCache.js`.
- The existing user presentation cache already carries display name, photo,
  equipment, capability bits, and review-account status:
  `src/modules/social/services/userPresentationCache.js:26-59`.
- The existing lean presentation fragment cache carries identity, capability,
  review/privacy bits, and equipment references for summary-style reads:
  `src/modules/social/services/userPresentationFragments.js:22-82`.

## 2. Scope / non-goals

### In scope

1. Change `getFriendsWithSteps` to obtain accepted friend IDs from the existing
   `friendsTopologyCache` and hydrate users through the existing
   `userPresentationCache`.
2. Preserve the existing per-friend/per-date daily-step cache and its
   invalidation behavior.
3. Change public-profile presentation hydration to reuse the existing
   generation-guarded user presentation cache.
4. Add a versioned Redis derived-data cache for the public-profile statistics
   aggregate, with a 60-second TTL and a safe Postgres fallback.
5. Add invalidation or generation advancement for every application write seam
   that changes public-profile presentation or statistics. Writers invalidate;
   they never write a new profile cache value.
6. Keep all existing HTTP response fields, error codes, capability filtering,
   privacy gates, sorting, and status behavior unchanged.

### Non-goals

- No new endpoint, query parameter, response field, or response contract.
- No Flutter changes and no app release. Existing iOS and Android clients keep
  sending the same requests and receive the same JSON.
- No caching of friend-search strings or result arrays. Search visibility is
  high-cardinality and includes private discoverable-name queries; the existing
  Postgres indexed search remains authoritative.
- No Redis reads for friend authorization, mutation authorization, relationship
  writes, coins, settlement, or other durable decisions.
- No database migration, materialized view, aggregate table, or backfill.
- No production deployment, production cache flush, or production database
  write as part of implementation or verification.
- No new rollout flag unless architect review demonstrates a concrete
  mixed-version or operational-safety requirement that cannot be handled by the
  existing permanent fail-open cache behavior. If that occurs, stop for owner
  approval before adding it.
- The architect review found that the new profile-statistics cache needs an
  independent fail-closed gate while its validation and invalidation paths are
  introduced. The proposed exception is documented in §4.4 and requires owner
  approval before implementation.

## 3. Existing cache contracts to reuse

The implementation must use the existing Redis wrapper and invalidation
protocol. It must not add a second Redis client or a second generation scheme.

| Data | Logical key/prefix | TTL | Source of truth | Current invalidation |
|---|---|---:|---|---|
| Friendship topology | `v1:user:friends:{userId}` plus `v1:user:friendsver:{userId}` | payload 1h; generation 2h | `friendships` | both affected users after create/status/delete and account deletion |
| Full user presentation | `v1:user:cosmetics:{userId}` plus `v1:user:cosmeticsver:{userId}` | payload 1h; generation 2h | `users`, `user_equipped_accessories`, `shop_items` | display name, photo, capability, equipment, and account-deletion seams |
| Lean presentation fragment | `v1:user:cosmetics:{userId}:ce:v1` plus `ce:v1:g:presentation:{userId}` | payload 1h; marker 48h | `users`, equipment references | cache-efficiency presentation marker advancement |
| Daily friend steps | `v1:user:daily:{userId}:{date}` | 60s | `steps` | legacy and sync-v2 step writers |
| Public-profile statistics | `v1:user:public-profile-stats:{userId}` | 60s | `steps`, completed `races`, and `race_participants` | stats-affecting step/participant/race completion seams; TTL remains the safety bound |

The existing production source has graduated the social cache settings to
permanent behavior (`redisPresentationGenerationGuardEnabled`,
`redisCacheFriendsEnabled`, `redisCacheUserBitsEnabled`, and
`redisFriendSearchRateLimitEnabled`), while test-only legacy overrides remain
available. This feature does not introduce another production rollout control.

## 4. New public-profile statistics cache

### 4.1 Key and payload

Add one logical prefix and key builder to `src/shared/cache/cacheKeys.js`:

```text
v1:user:public-profile-stats:{userId}
```

The prefix is `v1:user:public-profile-stats` and the key builder is the only
caller-facing way to construct this key. Invalidation targets the exact user
key; it must not use Redis `SCAN`.

The payload is an internal-only, versioned representation of the current
statistics query result. It must not be returned directly to clients:

```json
{
  "version": 1,
  "userId": "user-id",
  "firstCount": 1,
  "secondCount": 2,
  "thirdCount": 0,
  "avgStepsPerDay": 8123,
  "racesCompeted": 8,
  "firstPlaceWins": 1,
  "podiumFinishes": 3
}
```

The key is user-scoped and contains no viewer-specific data. The value is
rebuildable from Postgres and is display-only. Redis is never used for profile
authorization or durable state.

### 4.2 Freshness and fallback

- TTL: 60 seconds.
- A cache hit may be up to 60 seconds stale for statistics only.
- Missing, malformed, expired, oversized, unavailable, or Redis-error values
  fall back to the existing statistics SQL query. This cache intentionally
  uses the existing fail-open derived-cache contract without a second
  generation key; its 60-second TTL and explicit writer invalidation are the
  freshness controls.
- The cache reader validates before accepting a hit: `version === 1`, the
  cached `userId` matches the requested ID, all seven counters are finite
  non-negative numbers with integer fields remaining integers, and the JSON
  encoding is no larger than 4 KiB. It rejects unknown top-level keys,
  oversized values, and any non-object/array value, then falls back to the
  existing SQL loader.
- The SQL row is mapped explicitly from snake case to the internal payload:
  `first_count → firstCount`, `second_count → secondCount`,
  `third_count → thirdCount`, `avg_steps_per_day → avgStepsPerDay`,
  `races_competed → racesCompeted`, `first_place_wins → firstPlaceWins`,
  and `podium_finishes → podiumFinishes`. No timestamp is invented or cached.
- A loader error is not cached.
- A Redis flush only causes a cold Postgres rebuild.
- Profile existence and public eligibility must still be checked through the
  existing safe presentation contract. A cached row with missing display name,
  `isReviewAccount === true`, invalid ID, or invalid shape is treated as not
  usable; it must never create a new profile visibility path.

### 4.3 Implementation path

1. Add `publicProfileStats` to `cacheKeys.js` and export it through the existing
   key-builder export.
2. Add a small `publicProfileStatsCache` service under
   `src/modules/social/services/` using `derivedCache.cachedRead` and the
   existing Redis wrapper. Follow the established `buildX(dependencies = {})`
   injection pattern.
3. Keep `buildPublicProfileStatsQuery` as the only Postgres loader and keep its
   current safe numeric serialization.
4. In `getPublicProfile`, load the target's presentation through
   `userPresentationCache.getMany([userId], true)` (or the exact existing
   equivalent approved by the architect), then apply the current public gate
   and `characterPresentation` filtering after the cache read.
5. Read statistics through the new cache service. Assemble the exact current
   `public-profile-v1` response after both reads.
6. Preserve the current 404 behavior for missing display name, deleted users,
   review accounts, and malformed presentation.
7. Enumerate and wire post-commit stats invalidation at the existing write
   seams that change the query inputs:
   - `recordSteps` and `recordStepSyncV2` after a durable `steps` write, for
     the affected user;
   - race-participant display/stat writes that change `status`, `rawSteps`,
     `placement`, or `forfeitedAt`, for each affected participant user; and
   - race completion or correction paths that change a completed race's
     status, winner/team placement inputs, seeded-race classification, or
     participant result rows, for the race's participant users.

   Invalidation is post-commit and best-effort, matching the existing derived
   cache policy. A missed invalidation may therefore serve stale statistics for
   at most the 60-second TTL; it cannot make Redis authoritative. The
   implementation review must map each identified writer to one of these
   seams and call out any exceptional path that remains TTL-only.

### 4.4 Required rollout gate exception

The architect review requires a dedicated setting named
`redisCachePublicProfileStatsEnabled` so the new aggregate cache is fail-closed
until its validation and invalidation behavior has been verified. This is an
exception to the repository's default prohibition on new release flags:

- Safe default: `false` when the setting is absent or cannot be read.
- Owner: the backend maintainer, with explicit approval from the product owner
  before implementation.
- Rollout: add it to `KNOWN_FLAGS` as `false`, test the disabled path, then
  graduate it to the permanent production settings only after the focused
  integration suite passes. The permanent setting remains `true` so this does
  not become a long-lived runtime rollout control.
- Removal condition: after one successful production release and worker
  convergence, remove the temporary mutable declaration/test seam in the next
  backend maintenance pass; retaining the permanent cache behavior is the
  desired end state.

The existing Friends topology/presentation gates remain unchanged. For
`/friends/steps`, the implementation must read both existing settings and use
the cached path only when both are true; if either is false, it must call the
old Postgres path exactly.

## 5. `/friends/steps` implementation

### 5.1 Existing contract

The request remains:

```http
GET /friends/steps?date=YYYY-MM-DD
Authorization: Bearer <token>
```

The successful response remains:

```json
{
  "friends": [
    {
      "id": "friend-id",
      "displayName": "River",
      "profilePhotoUrl": null,
      "animal": "capybara",
      "accessories": [],
      "teamRaceEligible": true,
      "steps": 12345,
      "stepGoal": 5000
    }
  ]
}
```

`animal`, `accessories`, `teamRaceEligible`, and any capability filtering keep
their current behavior. Missing server-side optional fields continue to use
the current safe defaults in older clients.

### 5.2 Warm path

Change only the data-loading path in `getFriendsWithSteps`. Inject the
topology cache, presentation cache, settings, and step source/cache
dependencies so the route is testable without global mocks.

First read the existing `redisPresentationGenerationGuardEnabled` and
`redisCacheFriendsEnabled` settings. If either is false or unavailable, call
the current `Friendship.findAcceptedFriendsWithDisplay` path and the existing
step behavior exactly. Do not pass `true` to a presentation cache merely to
force caching when the Friends surface is disabled.

When both existing settings are enabled:

1. `friendsTopologyCache.get(userId)` returns accepted friend IDs and
   friendship topology. It falls back to the existing Postgres topology loader
   on any cache doubt.
2. `userPresentationCache.getMany(friendIds, true)` returns the presentation
   rows needed by `characterPresentation`, including capability bits and
   equipped accessories. It performs one Redis multi-read and one bounded,
   batched Postgres load for misses.
3. `dailyStepsCache.getMany(friendIds, date, cacheEnabled)` uses one bounded
   bulk source query for all cold friend/date entries, rather than one SQL
   round trip per friend. Warm entries still perform Redis reads only; missing
   values are filled from the bulk `userId IN (...) AND date = ...` query.
4. The existing response assembly, step-sync trigger for today's date, and
   alphabetical ordering remain unchanged.

On a warm path, the friends/steps data read performs Redis reads only. On a
cold path, it remains correct and bounded: topology load, one batched
presentation load for misses, and one bounded bulk step load for all
friend/date misses. There is no per-friend presentation or step query loop.

### 5.3 Compatibility

The route remains available to frozen clients and is not gated on a new client
capability. The old implementation remains the Postgres fallback, so an older
backend, absent Redis, Redis outage, cache invalidation failure, or malformed
payload cannot change the API result or cause a new failure mode.

## 6. API contract

There are no public API shape changes.

### `GET /friends/:userId/profile`

Existing success response remains byte/semantic compatible:

```json
{
  "contract": "public-profile-v1",
  "user": {
    "id": "user-id",
    "displayName": "River",
    "profilePhotoUrl": null,
    "equippedAnimal": "capybara",
    "equippedAccessories": []
  },
  "stats": {
    "racePodiums": { "first": 1, "second": 2, "third": 0 },
    "avgStepsPerDay": 8123,
    "racesCompeted": 8,
    "firstPlaceWins": 1,
    "podiumFinishes": 3,
    "winRate": 0.125
  }
}
```

Existing errors remain:

- `401` from authentication middleware.
- `404 {"error":"Profile not found"}` for missing, undiscoverable, deleted,
  review-account, or invalid public identity.
- `500 {"error":"Internal server error"}` for an unrecovered Postgres or
  application error.

### `GET /friends/steps`

Request, response, status codes, and side-effect behavior remain unchanged.
The cache is below response assembly and is invisible to the client.

## 7. Data model / migrations

No schema migration is required. Redis values are disposable derived data.

Postgres remains authoritative for:

- friendship membership and pending state;
- user display/public eligibility fields;
- equipment ownership/equipped state;
- steps;
- completed race participation and placements.

No cache value may authorize a friendship mutation or profile access. Every
cache value must be reconstructible after Redis eviction.

## 8. Frontend plan

No frontend implementation is expected. The existing Flutter clients already
consume both endpoints and require no new fields.

The implementation must nevertheless verify both platform contracts:

- iOS and Android continue to receive the same JSON and status codes.
- Older clients that do not send modern capability headers continue to receive
  the same filtered `animal`/`accessories` response.
- Missing or malformed cache data is invisible to Flutter because the backend
  falls back before serializing the response.
- No tutorial, demo, widget, or manual UI-placement checklist is needed because
  no screen or placement changes.

## 9. Backward compatibility & rollout

1. Deploy backend code first. No app update is required.
2. Add the architect-required `redisCachePublicProfileStatsEnabled` gate with
   a safe default of false, test it disabled, and graduate it to permanent
   true only after the focused suite passes. The existing Friends gates remain
   unchanged and the old Postgres loaders remain in-process fallback paths.
3. Old clients calling `/friends`, `/friends/steps`, or profile endpoints keep
   their existing requests and responses.
4. New backend + old client works because the cache is below unchanged response
   assembly.
5. If Redis is unset/down, all routes behave as the current Postgres paths.
6. No production deployment or production write is authorized by this spec.

## 10. Test plan — tests first

Backend tests must be written before implementation and run only against the
dedicated local/test Postgres and isolated Redis test database. Tests must use
real HTTP routes and the real handler chain for endpoint behavior.

### `/friends/steps`

1. First public request returns the existing response and cold-fills topology,
   presentation, and step caches.
2. A second request with the same date returns deep-equal JSON and avoids the
   accepted-friendship/user source reads and step source reads for warm entries.
3. A date change uses a distinct daily-step key and does not reuse the prior
   date's total.
4. A step sync invalidates the affected daily key and the next request reflects
   the durable new value.
5. A friendship mutation invalidates both users' topology and the next
   `/friends/steps` response reflects membership immediately.
6. Rename, photo, equipment, and sticky-capability mutations invalidate
   presentation and the next response reflects them.
7. Redis unset, Redis unavailable, malformed values, and generation mismatch
   all return the old Postgres-backed response without a 500.
8. A client without `characters` or `remote_assets` receives the same filtered
   response as before; a capable client receives the same rendered fields.

### Public profile

1. First profile request returns the exact existing `public-profile-v1`
   response and cold-fills presentation/statistics cache entries.
2. A second request returns deep-equal JSON without the user/equipment or
   statistics source queries when entries are warm.
3. Capability and release-channel variants produce the same per-client
   presentation semantics as the Postgres path and cannot leak unsupported
   character/accessory data.
4. Missing display name, review account, deleted user, malformed cached
   presentation, and malformed stats payload preserve the existing 404 or safe
   fallback behavior.
5. Presentation mutations and account deletion invalidate the profile's
   presentation cache; the next request reflects the change.
6. A stats-affecting durable write invalidates the profile-stats cache; the
   next request reflects the change. Any writer that cannot participate in
   post-commit invalidation is explicitly documented and tested as a bounded
   60-second-staleness exception; the cache never becomes authoritative.
7. Redis unset, unavailable, malformed, expired, and oversized entries fall
   back to Postgres without changing the response.
8. Old capability headers and current capability headers both remain
   byte/semantic compatible with the pre-cache path.
9. With `redisCachePublicProfileStatsEnabled` false or unavailable, profile
   requests use the pre-cache statistics path and no stats key is served.

The warm-read tests must enable Prisma query capture before importing the DB
module, clear captured queries after the cold request, then assert that the
warm request emits no friendship, user/equipment, daily-step, or profile-stats
SQL. Repeat those assertions for Redis-unset/down, flags-off, malformed
payloads, and old capability headers.

### 10.1 Writer inventory for profile statistics

The implementation must audit and either wire or explicitly exclude these
known writers before the cache is enabled:

- `src/modules/steps/commands/recordSteps.js` and
  `recordStepSyncV2.js`: durable daily-step writes; invalidate the affected
  user's stats key post-commit.
- `src/modules/races/models/raceParticipant.js`: participant result writes
  exposed through `participantDisplayChanged`, including raw steps, status,
  placement, forfeiture, and result corrections; invalidate affected user IDs
  after commit.
- `src/modules/races/commands/completeRace.js`,
  `src/modules/races/jobs/raceResolutionQueueV2.js`, and
  `src/modules/races/jobs/raceExpiry.js`: direct completion/settlement and
  expiry/correction writes that bypass the model helper; collect affected
  participant user IDs and invalidate them after the transaction commits.
- `src/modules/users/commands/deleteUserAccount.js`: invalidate the deleted
  user's stats key and any participant users whose durable rows are changed by
  the deletion path, if applicable.

The new service should expose a bounded `invalidateMany(userIds)` that
deduplicates IDs and deletes exact keys through `derivedCache.invalidate`; it
must not issue one unbounded invalidation job per participant or scan Redis.
The review must also search for any additional direct `race`,
`race_participant`, or `steps` writers and add them to this inventory before
implementation.

### Verification commands

- Backend focused integration suites against a confirmed test database and
 isolated Redis db15. Extend the existing
  `test/integration/redis-cache-c4-user-bits.test.js` and
  `test/integration/public-profile.test.js`; add a dedicated cache-focused
  integration suite only if their fixtures cannot isolate the warm/cold query
  assertions.
- Backend unit suite with `npm run test:unit`.
- Backend integration suite with `npm run test:integration`.
- No bare `npm test`.
- No production database, production Redis, production deployment, or staging
  start solely for verification.
- Frontend tests are unchanged because no Dart code changes; run `flutter
  analyze` only if the implementation unexpectedly touches Dart.

## 11. Implementation order

1. Add failing integration coverage for both public endpoints and warm/cold,
   invalidation, capability, and Redis-fallback cases.
2. Lock the unchanged response contract and key table in the backend review.
3. Add the public-profile statistics key builder and injected cache service.
4. Refactor public-profile presentation hydration to the existing presentation
   cache; keep the existing Postgres loader as fallback.
5. Add the centralized profile-statistics invalidation service, wire every
   confirmed writer from §10.1, and add the bounded bulk daily-step miss query.
6. Refactor `/friends/steps` to use topology and presentation caches, retaining
   the daily-step cache and response assembly.
7. Run focused integration suites, then the backend unit and integration suites.
8. Run the architect/code review required by the feature workflow.
9. Commit the backend change and stop for explicit production-deploy approval.

## 12. Acceptance criteria / definition of done

- Warm `/friends/steps` performs no friendship/user/step Postgres reads for
  cached entries and returns the exact existing response.
- Warm public-profile requests avoid the user/equipment and statistics source
  queries while preserving public visibility and capability behavior.
- Cache misses, invalidations, Redis errors, malformed entries, and Redis
  absence fall back safely to Postgres.
- Search remains uncached except for its existing Redis rate counter.
- No new API fields, endpoint parameters, or migrations are introduced. The
  architect-approved cache setting is the only new control, with its removal
  condition documented in §4.4.
- Integration tests were written first, use real HTTP/test infrastructure, and
  pass without touching production data.
- The architect review has no unresolved REQUIRED items.
- No production deployment is claimed or performed without fresh explicit
  authorization.

## Revision log

- Draft: separated the two candidates into (a) reuse of existing caches for
  `/friends/steps` and (b) a new bounded profile-statistics cache.
- Draft: kept public-profile presentation and profile statistics separate so
  capability filtering occurs after cache reads and statistics staleness cannot
  affect identity/privacy decisions.
- Draft: explicitly excluded search-result caching, schema migrations, frontend
  changes, release flags, and production operations.
- Gap pass 1: added the concrete public-profile-stats key/prefix contract and
  removed the unsupported generation-mismatch behavior from the new cache.
- Gap pass 1: mapped statistics invalidation to step, participant, and race
  completion/correction write seams, with the 60-second TTL as the bounded
  fallback for any exceptional writer.
- Gap pass 2: tied the test plan to the existing real-HTTP integration suites
  and required query-efficiency assertions to prove warm reads avoid the
  source queries rather than only proving Redis contains keys.
- Architect review: required a dedicated fail-closed profile-stats gate,
  strict payload validation, a concrete direct-writer inventory, existing-flag
  parity for `/friends/steps`, bulk daily-step misses, and query-event-based
  warm-read assertions.
- Revision after architect review: added those safeguards and recorded the
  new-cache flag as an explicit owner-approval exception; implementation is
  not authorized until that exception and the overall spec are approved.
- Gap pass 2: clarified that capability/release-channel shaping and public
  eligibility remain outside the statistics cache, while the full presentation
  cache remains validated before it can influence the 404/public gate.
