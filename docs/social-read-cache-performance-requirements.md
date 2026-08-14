# Social Read Cache Performance — Requirements

Status: **IMPLEMENTED — focused verification and combined review SHIP; flags off**

The separately specified API contract/payload cleanup is paused and has not
started implementation. This feature may proceed first. Its raw topology service
must remain response-shape agnostic so the future `friends-summary-v1` and Home
friends assemblers can reuse relationship IDs without changing topology keys or
invalidation semantics. The future compact contract must use its own lean
identity/capability projection rather than the legacy cosmetic presentation
bundle.

## 1. Summary & user story

The Leaderboard and Friends tabs currently wait on repeated Postgres work even
though the backend already has a local, disposable Redis derived-data layer.
Friend search also performs a durable Postgres upsert for every debounced query
before it runs the indexed search.

As a user, I want the leaderboard, my friends roster, and friend search results
to appear quickly. As the operator, I want those reads to reuse Redis without
changing any public API shape, leaking viewer-specific data, weakening frozen
clients, or turning Redis into a source of truth.

This feature uses three deliberately different optimizations:

1. Cache the **raw step-ranking core** for the step leaderboard. Global ranking
   cores are shared by all viewers who resolve to the same date boundary;
   friends ranking cores are viewer-scoped. Mutable presentation is hydrated at
   read time from the existing per-user presentation cache.
2. Cache the **relationship topology** behind `GET /friends`, not its assembled
   presentation. Friendship mutations invalidate the two affected users'
   topology keys; current names, photos, characters, and capability-derived
   fields are hydrated at read time.
3. Do **not** cache friend-search terms or result pages. The search query space is
   high-cardinality and contains private name queries. Keep the existing trigram-
   indexed Postgres result query, but move the 30/minute fixed-window counter to
   Redis when enabled, with the existing Postgres counter as the exact fallback.

### Current implementation evidence

- The shipped Friends tab calls `GET /friends` on entry and after every friend
  mutation, and calls `POST /friends/search` after a 300 ms debounce
  (`lib/screens/tabs/friends_tab.dart:90-221`).
- The shipped Leaderboard tab calls the steps endpoint for four periods and two
  scopes (`lib/screens/tabs/leaderboard_tab.dart:90-207`). The races board is no
  longer reachable from the current app, though the endpoint remains for frozen
  clients (`lib/screens/tabs/leaderboard_tab.dart:61-64`).
- `GET /friends` currently performs the accepted-friend query plus two pending-
  request queries on every request (`stepv2-backend/src/modules/social/routes/friends.js:137-150`,
  `.../queries/getFriends.js:17-73`).
- The step leaderboard performs a grouped step query, a profile/cosmetics query,
  and—when the viewer is outside the top 100—two additional aggregate/rank reads
  (`stepv2-backend/src/modules/leaderboard/getLeaderboard.js:116-227`).
- The modern friend-search path writes `friend_search_rate_windows` once per
  query, then executes the result query (`.../social/models/friendSearchRateWindow.js:7-29`,
  `.../social/services/searchFriendsByIdentity.js:26-54`).
- Search already has exact partial `pg_trgm` GIN indexes and an idempotent
  deployment/verification runbook (`stepv2-backend/scripts/race-experience-identity-search-indexes.sql:1-16`,
  `stepv2-backend/docs/race-experience-identity-search-index-runbook.md:1-100`).
- `userPresentationCache` explicitly anticipated leaderboard hydration, but its
  current cache-on miss path performs one indexed Postgres query per user and
  does not yet carry `clientFeatures` (`.../social/services/userPresentationCache.js:1-17,50-115`).

## 2. Scope / non-goals

### In scope

1. Three surface-specific default-off app-setting flags:
   - `redisCacheLeaderboardEnabled`
   - `redisCacheFriendsEnabled`
   - `redisFriendSearchRateLimitEnabled`
2. One default-off internal prerequisite flag:
   - `redisPresentationGenerationGuardEnabled`
   Generation-advancing invalidators deploy first while this remains false and
   readers retain legacy behavior. It may turn true only after every old worker
   has drained; friends/leaderboard flags require it. This prevents an old
   invalidator from defeating a new reader's generation WATCH during reload.
3. Redis-backed raw ranking cores for **steps** leaderboards only:
   - global: shared by `period + resolved date boundary`;
   - friends: keyed by viewer plus eligibility epoch, accepted-friend-set hash,
     period, and resolved date boundary;
   - soft freshness at snapshot age 15 seconds, with hard expiry exactly 60
     seconds after the snapshot's `asOf` (not 60 seconds after publication);
   - one Redis stampede lock per ranking key;
   - per-process single-flight plus version/`asOf`-guarded publication;
   - viewer-specific `currentUser` and capability-specific presentation are
     always assembled after the cache read.
4. Redis-backed raw friendship topology for `GET /friends`, with a 1-hour TTL
   and generation-guarded cold fills plus immediate invalidation at every
   friendship mutation seam.
5. Batched/pipelined reads for `userPresentationCache.getMany`: one Redis
   multi-get, one Postgres `findMany` for all misses, and pipelined fills. The
   bundle gains internal-only `clientFeatures`, `isReviewAccount`, and
   `hiddenFromLeaderboard` fields so cached friends and leaderboard assembly
   retain current behavior. Every payload is paired with a generation key; cold fills use
   `WATCH/MULTI/EXEC`, and presentation invalidation atomically advances the
   generation and deletes the payload.
6. Missing presentation invalidation seams for profile-photo changes and
   `clientFeatures` changes. Existing display-name, equipment, and account-
   deletion invalidation remains.
7. An atomic Redis fixed-window counter for modern `POST /friends/search`, with
   the existing Postgres `FriendSearchRateWindow.consume` as fallback whenever
   the flag is off, Redis is unset/down, or the Redis command fails.
8. Verification that both friend-search GIN indexes are valid, ready, and used
   by the production query predicates before attributing search latency to the
   result query. Applying or repairing those indexes remains a separately
   approved production operation.
9. Backend integration tests, performance evidence, and runbook updates.
10. A numeric `leaderboardEligibilityEpoch` row in the existing free-form
    `app_settings` table. Both leaderboard scopes fetch it directly from
    Postgres; privacy/review-eligibility/account-deletion mutations advance it
    in the same transaction as the authoritative change. No schema migration is
    needed.

### Non-goals

- No frontend UI, layout, navigation, copy, loading-state, or request-cadence
  change.
- No new endpoint, request parameter, response field, response type, or error
  code.
- No caching of search strings or search result arrays. Redis keys must never
  contain raw search text or normalized discoverable names.
- No caching of the legacy races leaderboard. Frozen clients that request
  `type=races` continue down the existing Postgres path unchanged.
- No migration or removal of `friend_search_rate_windows`; it remains the
  fallback and rollback path.
- No Postgres source-of-truth schema migration.
- No settlement, friendship authorization, privacy decision, or mutation reads
  from Redis.
- No production deploy, flag flip, index operation, or production write without
  explicit in-the-moment owner approval.
- No implementation of the paused `api-contract-payload-cleanup-requirements.md`
  contracts. In particular, this work does not add `GET /friends?view=summary-v1`
  or a Home friends block.

## 3. API contract

There are **no public API shape changes**. With unchanged source state, every
cold or fresh cache response must be JSON-deep-equal to the Postgres path for
the same anchored clock. After a step mutation, only ranks and step totals may
come from one coherent cached snapshot: expected freshness is 15 seconds and
the hard maximum snapshot age is 60 seconds. Every friends-scope raw core,
including its top 100 and outside-top-100 viewer rank/total, is computed in one
Postgres snapshot. Friendship membership, account
deletion, names/photos/capabilities, review eligibility, and global-leaderboard
privacy changes do not use that stale allowance and must be reflected on the
first read that begins after their durable commit and invalidation/epoch update.

### `GET /leaderboard`

Existing request:

```http
GET /leaderboard?type=steps&period=today|week|month|allTime&scope=global|friends
Authorization: Bearer <token>
X-Timezone: America/New_York
X-Client-Features: characters,remote_assets
```

Existing success response (representative; unchanged):

```json
{
  "top10": [
    {
      "rank": 1,
      "userId": "user-id",
      "displayName": "River",
      "profilePhotoUrl": null,
      "equippedAccessories": [],
      "totalSteps": 12345
    }
  ],
  "top100": [],
  "currentUser": {
    "rank": 42,
    "displayName": "Me",
    "profilePhotoUrl": null,
    "totalSteps": 123,
    "inTop10": false,
    "inTop100": false
  }
}
```

Existing errors remain:

- `400` for an unsupported `type`, step `period`, or `scope`.
- `401` from existing auth middleware.
- `500 {"error":"Internal server error"}` for an unrecovered backend error.

Compatibility details:

- Missing `scope` continues to default to `global` for frozen clients.
- Both `top10`/`inTop10` and `top100`/`inTop100` aliases remain.
- `type=races` bypasses the new cache and stays byte-compatible.
- A cache key never contains an assembled `currentUser` object or filtered
  character payload; those are viewer overlays.
- If a global viewer is outside the cached top 100, the request executes the
  complete legacy Postgres implementation for that response. It must never mix
  live viewer totals/rank with a stale cached top 100. Likewise, if hydration
  finds a deleted, review-ineligible, or malformed cached top-row user—or a
  hidden user in a global core—the request discards the entire cached core,
  executes the full legacy path, and schedules/retries a guarded rebuild—never
  a placeholder row or a hole. A hidden accepted friend remains eligible for a
  friends-scope board, matching today's behavior.

### `GET /friends`

Existing request and response (unchanged):

```http
GET /friends
Authorization: Bearer <token>
```

```json
{
  "friends": [
    {
      "id": "friend-id",
      "displayName": "River",
      "profilePhotoUrl": null,
      "animal": "capybara",
      "accessories": [],
      "friendshipId": "friendship-id",
      "teamRaceEligible": true
    }
  ],
  "pending": {
    "incoming": [
      {
        "friendshipId": "request-id",
        "user": {
          "id": "requester-id",
          "displayName": "Moss",
          "profilePhotoUrl": null
        }
      }
    ],
    "outgoing": []
  }
}
```

The `animal` field remains capability-dependent exactly as today and may be
absent for an older client. `teamRaceEligible` remains pessimistically false
when no sticky `team_races` capability has been recorded.

Future-contract boundary: the paused API cleanup proposes
`GET /friends?view=summary-v1`, which omits **cosmetic** presentation fields and
adds an incoming count while retaining display name, photo, and capability-
derived `teamRaceEligible`. This cache must live below response assembly: it
stores only friendship IDs/user IDs, and the legacy route continues assembling
its exact current response through the full presentation bundle. A later compact
assembler may reuse only the raw topology load; it must add a lean bulk identity/
capability projection that never joins equipped accessories or shop items on a
cold miss, plus its own contract-parity/query-count tests. No assembled legacy
or compact friends response is stored in Redis.

### `POST /friends/search`

Existing request and success response (unchanged):

```http
POST /friends/search
Authorization: Bearer <token>
Content-Type: application/json

{"q":"river"}
```

```json
{
  "users": [
    {
      "id": "user-id",
      "displayName": "RiverRunner",
      "profilePhotoUrl": null,
      "discoverableName": "River Stone"
    }
  ]
}
```

Existing validation and error behavior remains:

- `400` / `INVALID_SEARCH_QUERY` for a missing/non-string query.
- `400` / `SEARCH_QUERY_TOO_SHORT` after normalization below two characters.
- `429` / `SEARCH_RATE_LIMITED` with the same `Retry-After` calculation after
  30 searches in the current UTC minute.
- `401` and `500` behavior unchanged.
- Legacy `GET /friends/search?q=` stays display-name-only and unchanged.

Transition caveat: any number of enable/disable changes or mixed-worker choices
within one UTC minute, while both counters retain state, can split the minute
between Redis and Postgres and permit at most one Redis allowance plus one
Postgres allowance (60 total). Redis eviction/restart can reset the Redis side;
repeated resets therefore have **no strict per-minute upper bound**.
This is an accepted best-effort, availability-over-abuse-control degradation for
a non-financial search endpoint, not a durable enforcement guarantee. Result
visibility and authorization never depend on the counter or Redis. If a Redis
reply is lost after execution, Postgres fallback may allow requests from the
second allowance; absent a reset, it remains within the same 60-request split-
counter bound but is weaker than one uninterrupted counter. The runbook must
state these limits explicitly.

## 4. Internal Redis contract

All logical keys receive the existing environment prefix (`p:`, `s:`, `t:`).
Values are rebuildable from Postgres. Redis flush or eviction causes only cold-
path latency.

| Logical key | Value | TTL | Mutation/freshness rule |
|---|---|---:|---|
| `v1:leaderboard:steps:global:{eligibilityEpoch}:{period}:{boundary}` | Raw ranked rows `{userId,totalSteps,rank}` for top 100 plus anchored `asOf`/`buildStartedAt` | soft at `asOf + 15s`; hard at `asOf + 60s` | `eligibilityEpoch` is read uncached from Postgres, so hide/unhide, eligibility change, or deletion selects a new key immediately. Step writes do not fan out. Publication uses only the remaining hard-age budget; a fresh hit returns immediately and stale/miss behavior is below. |
| `v1:leaderboard:steps:friends:{viewerId}:{eligibilityEpoch}:{acceptedSetHash}:{period}:{boundary}` | Raw top-100 ranked rows plus raw current-viewer rank/total for the viewer + accepted non-review friends, plus anchored `asOf`/`buildStartedAt` | soft at `asOf + 15s`; hard at `asOf + 60s` | The top 100 and viewer scalars come from one repeatable-read snapshot. `acceptedSetHash` is SHA-256 over the sorted accepted friend IDs from the loaded topology. Membership or review eligibility changes select a new key without scanning/deleting arbitrary date variants; old variants expire at the snapshot hard limit. |
| `v1:lock:leaderboard:{sha256(logicalRankingKey)}` | NX/PX lock token | `max(10s, ceil(5 × measured cold-loader p95))` | Compare-and-delete release through existing `redisCache.withLock`. Hashing keeps lock key length bounded. |
| `v1:user:friends:{userId}` + `v1:user:friendsver:{userId}` | Raw topology payload `{generation, accepted, incoming, outgoing}` plus numeric generation marker; each list item is exactly `{friendshipId,userId}` | 1h payload; 2h generation backstop | Invalidation uses one Lua command to `INCR friendsver` + refresh the generation TTL + `DEL friends`. Both participants advance only after commit. A cold fill watches both keys and installs only if unchanged; the exact missing-marker rules below apply. |
| `v1:user:cosmetics:{userId}` + `v1:user:cosmeticsver:{userId}` | Existing presentation bundle, expanded internally with `generation`, `clientFeatures`, `isReviewAccount`, and `hiddenFromLeaderboard`, plus numeric generation marker | 1h payload; 2h generation backstop | Existing display-name/equipment/delete invalidation plus profile-photo, sticky-client-feature, visibility, and any review-status invalidation. Lua atomically advances generation, refreshes its TTL, and deletes payload; `WATCH/MULTI/EXEC` guards fills. Never serialized directly. |
| `v1:user:friendsearchrate:{userId}:{utcMinuteEpoch}` | Integer query count | 120s | Atomic Lua `INCR`; first increment sets expiry. No invalidation. Eviction/reset only weakens the best-effort search throttle for that minute; it cannot expose data. |

The ranking key uses the **resolved date boundary**, not the raw timezone. Two
timezones that produce the same query predicate share one global key; different
boundaries never share cached totals. `allTime` uses the literal boundary
`all`. Raw ranking keys have no release-channel or capability variants because
they contain no presentation.

The existing daily-step cache cannot be used as the friends/today ranking
source: it intentionally maps both a missing row and a stored zero to the number
`0`, while the current grouped leaderboard includes only users who have a step
row. The ranking cold loader therefore retains the existing grouped-query
semantics; Redis accelerates subsequent reads of that raw result.

`leaderboardEligibilityEpoch` is an authoritative numeric AppSetting, not a
cache flag. A successfully queried missing/malformed value reads as `0`; a
Postgres query error is **not** epoch `0`. On an epoch-read error, both scopes
execute the complete legacy Postgres implementation without reading or writing
a ranking core (and retain the existing 500 if Postgres cannot serve that path).
They never select an epoch-0 key because a lookup was unavailable. The
hide/unhide command and
account deletion advance it inside their existing transaction; any future code
that mutates an existing user's `isReviewAccount` must use the same seam. New
normal/review account creation does not need an advance: an account with no
steps cannot alter the board, and subsequent steps obey the ranking freshness
contract. Both leaderboard scopes pay one indexed AppSetting lookup. Global
uses it for privacy and review eligibility; friends uses it for review
eligibility (hide/unhide causes a harmless extra friends-core miss). Redis
eviction can never ABA back to a stale eligibility generation.

Generation keys for topology/presentation exist to prevent `PG read →
concurrent mutation/invalidation → stale SET`. They are Redis coordination
markers, not durable state. Invalidation atomically modifies the marker and
deletes the payload. Fill watches both generation and payload, bulk-loads from
Postgres, then installs through one `MULTI/EXEC`; any modification/eviction in
the window aborts the install. Exactly these initialization rules apply:

- no marker and no payload means initial generation `0`; the guarded
  transaction creates the marker with its 2-hour TTL and the generation-0
  payload together;
- no marker with any payload is never a hit; a guarded rebuild may atomically
  replace it and create generation `0` only if both watched keys stay unchanged;
- a present marker requires an exactly matching embedded generation.

Invalid/mismatched/versionless values are misses. Failed invalidation opens the
existing key-scoped read bypass until Lua succeeds.

### Cache failure rules

- A disabled new surface creates none of its topology-payload, ranking, lock,
  or search-rate keys and executes that surface's exact existing Postgres path.
  The already-existing presentation cache retains its own legacy flag behavior.
  When Redis is configured, post-commit presentation and topology invalidators
  advance their short-lived generation markers regardless of the four new flags
  so rolling flag propagation cannot miss a concurrent mutation. With
  `REDIS_URL` unset, the wrapper remains fully inert and writes nothing.
- Surface flags are independent after satisfying the generation prerequisite.
  Enabling the friends cache must not activate ranking
  cores or the Redis search counter; enabling the leaderboard cache may read a
  friends topology but must honor the friends flag (Postgres topology when off);
  enabling only the search counter must not create presentation/topology keys.
  If the generation guard is false, friends and leaderboard flags are treated
  as off and dispatch to their complete legacy Postgres paths.
- Redis read/write/lock error: swallow/log through `redisCache`; execute the
  existing Postgres path. Redis never causes a request failure.
- Every surface validates an exact internal allowlist before assembly. Wrong
  types, missing required keys, non-finite/negative step or rank values,
  duplicate IDs, generation mismatch, invalid `asOf`, partial/misaligned MGET
  cardinality, or any extra viewer/presentation field in a raw ranking payload
  makes the whole value a miss. Do not partially salvage poisoned payloads.
- Friends topology invalidation failure: use the existing retry + viewer-key
  bypass behavior until deletion succeeds; the 1-hour physical TTL is the hard
  backstop for a missed cross-worker broadcast.
- Leaderboard needs no correctness-critical step invalidation. Its explicit
  contract is bounded staleness; physical expiry guarantees recovery.
- Search counter Redis failure or ambiguity—including a non-integer,
  non-positive, missing, or malformed Lua reply—synchronously falls back to the
  existing Postgres `consume` before executing search. The same anchored UTC
  clock drives both key selection and `Retry-After`. A response-lost-after-
  execution case may count once in Redis and once in Postgres; this is part of
  the documented split-counter degradation.
- No request may wait while holding a Postgres connection for a Redis lock.
- A missing/deleted presentation row causes assembly to drop the stale topology
  entry. It must never render a deleted account with placeholder identity while
  a topology invalidation retry is in flight.

## 5. Data model / migrations

No Prisma or Postgres migration is required.

- `steps`, `users`, and `friendships` remain authoritative.
- `friend_search_rate_windows` remains deployed and written whenever the Redis
  flag is off or Redis cannot answer.
- Existing friendship indexes (`requester_id,status` and
  `addressee_id,status`) remain the topology cold path
  (`stepv2-backend/prisma/schema.prisma:318-332`).
- Existing unique/indexed step shape remains the ranking source
  (`stepv2-backend/prisma/schema.prisma:356-367`).
- Existing search index companion SQL is reused; this feature creates no third
  search index.
- `leaderboardEligibilityEpoch` is inserted lazily/upserted in the existing
  free-form `app_settings` table and advanced with an atomic numeric JSON update
  inside eligibility-changing transactions. It is not added to the admin flag
  registry and cannot be toggled from the admin UI.

Before implementation performance is called successful, capture:

1. nginx `rt`/`urt` p50/p95 and request volume for the three endpoint families;
2. Postgres query count and `EXPLAIN (ANALYZE, BUFFERS)` for global leaderboard,
   friends leaderboard, friends roster, and both modern search predicates;
3. Redis memory, hit/miss, and key-count baseline;
4. validity/readiness and actual use of both existing GIN indexes.

Do not run `EXPLAIN ANALYZE`, index DDL, or any test against production without
explicit approval and a read-safe statement review.

## 6. Backend implementation plan

Implementation order is contract-first and tests-first.

1. Add failing public integration tests in
   `stepv2-backend/test/integration/redis-social-reads.test.js`. Tests run
   against the dedicated integration Postgres and disposable Redis helper.
2. Add the three surface settings and the default-false
   `redisPresentationGenerationGuardEnabled` prerequisite to
   `src/shared/config/appSettings.js`; update
   `docs/redis-cache-runbook.md` with the two-phase generation-guard rollout,
   independent surface enable/disable order, rollback order, and the search-
   counter transition/reset caveat.
3. Extend `src/shared/cache/cacheKeys.js` with typed builders and prefixes for
   ranking, topology payload/generation pairs, presentation generations, locks,
   and search-rate keys. Add unit guards for boundary normalization and ensure
   no builder accepts raw search text.
4. Add Redis batch helpers to `src/shared/cache/redisCache.js` (multi-get and
   pipelined multi-set) with the same inert/error-swallowing contract as current
   single-key helpers. Helpers return explicit cardinality/status metadata and
   reject partial/misaligned results; reuse `withWatch` for guarded fills rather
   than inventing a non-atomic GET/load/SET helper. Extend the guarded ranking
   publication path to accept millisecond `PX` expiry; do not use the existing
   seconds helper that rounds upward.
5. Refactor `userPresentationCache.getMany` to:
   - read all keys in one Redis operation;
   - bulk-load all misses in one `user.findMany`;
   - cache null/missing values safely;
   - preserve `derivedCache`'s boxed `{v: value}` representation so `null` is a
     hit, and honor its prefix bypass before every batch read;
   - watch every miss's presentation-generation and payload keys, bulk-load
     misses once, and install all payloads only when both corresponding keys
     remain unchanged;
   - carry internal `clientFeatures` and `isReviewAccount`;
   - preserve its flag-off one-query Postgres path;
   - retain the legacy reader/fill behavior while
     `redisPresentationGenerationGuardEnabled` is false, but run the new
     generation-advancing invalidators unconditionally after durable writes;
     when the prerequisite is true, accept only guarded/versioned payloads.
6. Close presentation invalidation gaps:
   - `setProfilePhoto` and `removeProfilePhoto` invalidate post-commit;
   - `User.updateClientFeatures` invalidates presentation after its write;
   - the leaderboard-visibility setter invalidates presentation as part of its
     post-commit work;
   - retain existing rename/equip/delete invalidation;
   - run the atomic generation advance + payload delete whenever Redis is
     configured, independent of all four new flags;
   - add a structural inventory test naming every presentation-mutating seam.
7. Add `src/modules/social/services/friendsTopologyCache.js`:
   - cold loader retains the existing accepted/incoming/outgoing query split and
     each query's returned order, but selects raw IDs without joining users;
   - generation-guarded read-through under `redisCacheFriendsEnabled`;
   - `invalidateUserSafe`, `invalidatePairSafe`, and account-deletion fan-out;
   - no mutation writes a new cache value directly.
   The friends and leaderboard surface caches execute their complete legacy
   Postgres paths unless `redisPresentationGenerationGuardEnabled` is also true;
   this makes the prerequisite enforceable rather than a runbook convention.
8. Change `getFriendsList`/`getPendingRequests` assembly to share one topology
   load and one presentation hydration. Preserve alphabetical friend sorting,
   pending shapes, capability filtering, `teamRaceEligible`, and null handling.
   `GET /friends` must continue showing an accepted review-account friend and
   ignores `hiddenFromLeaderboard`; only leaderboard assembly applies those
   eligibility fields.
   Avoid calling the topology cache twice from the current `Promise.all` route;
   expose one `getFriendsPage` query or pass the loaded topology through.
9. Wire topology invalidation strictly after durable commit at every seam:
   - manual send/reopen/reciprocal accept;
   - accept/decline;
   - remove;
   - automatic friendship from referral record/redeem and quick-share join;
   - account deletion, using counterpart IDs captured before delete.
   Also include the exported `Friendship.create`, `updateStatus`, and `delete`
   methods in the invalidation inventory (or remove/deprecate them and pin zero
   callers). Automatic-friend helpers used inside a caller-owned transaction
   return deferred invalidation metadata; only the owner runs it after commit.
   Account deletion captures counterpart IDs inside the transaction, returns
   them, and performs topology/presentation/auth-me invalidation only after
   `$transaction` resolves. Existing auth-me pair invalidation stays.
   Topology generation advance + payload delete runs whenever Redis is
   configured, independent of the friends surface flag; this is required while
   workers observe a flag change at different times.
10. Add `src/modules/leaderboard/services/stepLeaderboardCache.js` and split
    `getLeaderboard.js` into raw ranking computation and viewer assembly:
    - when `redisCacheLeaderboardEnabled` is false, dispatch to the existing
      implementation rather than partly using the new cache assembly;
    - raw cache contains no name/photo/cosmetics or assembled `currentUser`
      object; a friends core may contain only the viewer's scalar raw rank/total;
    - global key is shared only by identical
      eligibility-epoch/period/boundary;
    - add `src/shared/config/leaderboardEligibilityEpoch.js`, whose
      `buildLeaderboardEligibilityEpoch` reads the numeric AppSetting directly
      and advances it transactionally with visibility/account-deletion changes;
      inject it into `buildGetLeaderboard`, `buildSetLeaderboardVisibility`,
      and `buildDeleteUserAccount` so the cross-module dependency does not pass
      through the leaderboard router barrel;
    - distinguish a successful missing/malformed row (`0`) from a query error
      (`unavailable`/throw); on the latter, `buildGetLeaderboard` dispatches both
      scopes to the complete legacy path without touching a ranking key;
    - replace the visibility route's bare `User.update` with the built service
      that commits the user change + epoch, then invalidates auth-me and
      presentation after commit; structurally guard the absence of any other
      existing-user review-status writer;
    - friends key is viewer-scoped and carries both the authoritative eligibility
      epoch and accepted-set hash from cached topology, so membership or review-
      eligibility changes cannot reuse the old board;
    - other shapes keep the existing group-by semantics;
    - profiles hydrate through `userPresentationCache.getMany` and
      `characterPresentation` after the cache read;
    - friends cores include raw current-viewer rank/total so the viewer remains
      correct when a roster exceeds 100 users; compute the grouped top 100,
      total participant count, and viewer rank/total inside one short
      `REPEATABLE READ` read-only transaction using the same anchored boundary.
      Do not perform Redis waits or presentation hydration while that transaction
      is open;
    - a global viewer outside the cached top 100 uses the complete legacy path;
      it never combines a live viewer overlay with cached rows;
    - a missing, review-ineligible, deleted, or malformed cached top-row
      presentation invalidates the response candidate and forces the complete
      legacy path plus guarded rebuild; `hiddenFromLeaderboard` does so only for
      global cores because friends scope intentionally retains hidden friends;
    - hidden-global, hidden-friends, review-account, tie-rank, absent-step versus
      stored-zero,
      top10/top100 alias, and outside-top100 current-user behavior remain
      deep-equal—including the legacy quirk where an in-top-100 `currentUser`
      object omits `profilePhotoUrl`.
11. Use soft/physical freshness and `redisCache.withLock`:
    - maintain a per-process, per-key single-flight promise so requests in one
      worker share one cold loader;
    - fresh hit: return raw core;
    - soft-stale: return it immediately and trigger at most one rebuild;
    - physical miss: lock winner rebuilds; a cross-worker loser polls Redis
      without holding a PG connection for a configured budget derived from the
      measured cold-loader p95 plus margin (cap below the HTTP timeout), then
      executes the complete legacy path if no valid core appears;
      pin `LEADERBOARD_CACHE_WAIT_MS` during staging to
      `clamp(ceil(1.5 × p95), 250ms, 5s)` and record the measured value in the
      runbook;
    - set the lock lease to `max(10s, ceil(5 × p95))` from the same baseline;
      publication watches the ranking payload and installs only when its
      `buildStartedAt` is strictly newer than the currently published core
      (equal timestamps keep the existing value), so an expired older lock
      holder can never overwrite a newer rebuild;
    - calculate `remainingMs = asOf + 60s - publishNow` and publish through
      `MULTI` with `PX remainingMs`; refuse publication when `remainingMs <= 0`.
      Cache reads likewise reject a core whose `asOf + 60s` has passed even if
      Redis retained it, so a slow loader cannot restart the freshness clock;
    - background stale rebuilds catch/log their own errors; no unhandled promise
      rejection may escape the request;
    - Redis unavailable: unchanged PG path.
    Inject/anchor the request clock once for boundary selection. Each winning
    cold loader captures `buildStartedAt`/`asOf` immediately before its global
    ranking statement or friends repeatable-read transaction; all components of
    that core reuse it. Cache-age checks use the payload's `asOf`, so awaited
    calls cannot cross midnight or silently restart freshness.
12. Add `src/modules/social/services/friendSearchRateLimiter.js` with atomic
    Lua `INCR` + first-write expiry. `searchFriendsByIdentity` selects Redis only
    when its new flag is true; unsuccessful Redis calls invoke the current
    Postgres model. A flag-read error also means Postgres fallback. Preserve the
    current minute boundary and `Retry-After` math.
13. Keep `searchDiscoverableUsers` result reads uncached. Verify the query text
    still matches the two partial GIN index predicates. If prod indexes are
    absent/invalid, stop and request explicit approval to run the existing
    index runbook; do not hide a missing index behind a result cache.
14. Add bounded observability with no PII: surface name, cache outcome
    (hit/fresh, hit/stale, miss, bypass/error), and duration. Never log search
    text, discoverable names, result IDs, tokens, or full Redis keys containing
    a user ID.
15. Every new service/query uses `buildX(dependencies = {})` with injectable
    Prisma, Redis wrapper/batch helpers, app settings, clock, logger, loaders,
    and invalidators. Keep module boundaries explicit: leaderboard cache code
    lives under `src/modules/leaderboard/services/`, while the eligibility epoch
    dependency lives under shared config; public leaderboard exports remain only
    `createLeaderboardRouter` from `leaderboard/index.js`; social
    cache builders are exported through `social/index.js` only where another
    module needs them. Routers receive built queries through their existing
    dependency objects, so HTTP and Redis interleavings are testable without
    require-cache mutation.

## 7. Frontend plan

No Dart production change is expected. The existing screens already preserve
previous data during refresh and degrade safely on network errors.

The frontend implementation agent must nevertheless verify:

- `BackendApiService.fetchLeaderboard`, `fetchFriends`, and `searchUsers` need
  no signature or decoder change (`lib/services/backend_api_service.dart:1492-1645`).
- Existing defensive friends decoding and loading/error states remain intact
  (`lib/screens/tabs/friends_tab.dart:90-165`).
- Both iOS and Android send the same endpoint requests; no platform-specific
  configuration or build define is introduced.
- Tutorial preview services remain fake/local and require no cache awareness.
- No UI-placement checklist is required because nothing visible is added,
  moved, resized, or removed.

If backend contract parity forces any Dart change, stop and return to spec
review; a client change is not pre-approved by this document.

## 8. Backward compatibility and rollout

1. Deploy backend code with all four new flags **false**. Generation-advancing
   presentation and topology invalidators are active after durable writes, but
   presentation readers/fills remain legacy and all three new surface caches are inert. One
   intentional correctness improvement applies if the already-existing C2
   presentation cache is enabled: photo and sticky-client-feature writes now
   invalidate that key. No response shape changes.
2. Keep the generation guard and dependent surface flags false throughout the
   rolling reload. Wait for every old-binary worker to drain, and verify worker
   build/version telemetry rather than relying on elapsed time alone. This is
   Phase A: an old invalidator may still only delete a payload, so no guarded
   reader is allowed yet.
3. Verify Redis health and the existing search indexes on staging. Enable
   `redisPresentationGenerationGuardEnabled`, wait through the app-setting cache
   propagation interval, and verify every worker reports guarded-reader mode.
   During propagation, guard-false readers may retain the pre-existing freshness
   behavior, while guard-true readers reject versionless payloads; dependent
   friends/leaderboard caches remain off.
4. Only after guard convergence, enable one staging surface flag at a time:
   - friends topology;
   - leaderboard cores;
   - friend-search Redis counter (independent of the guard).
   Exercise mutations between each flip, then soak all three together for 24h.
5. Compare endpoint p50/p95, PG query counts, Redis hit rate/memory, error rate,
   and parity logs against baseline.
6. Production deployment and each production flag flip require explicit,
   in-the-moment owner approval and repeat the same two-phase sequence. A normal
   surface rollback flips only that surface flag. Before a binary rollback that
   could reintroduce old invalidators: disable friends and leaderboard, wait for
   propagation/in-flight reads to drain, disable the generation guard, verify
   all workers are in legacy-reader mode, then roll the binary back. The search
   flag is independent but should also be disabled when returning to a binary
   that does not implement it.
7. No app release is required. Frozen iOS/Android clients continue sending the
   same requests and receiving the same JSON. Backend-first ordering is still
   satisfied trivially because the optimization is server-only.
8. Redis flush/restart causes cold reads only. Postgres remains authoritative.

Version-skew reasoning:

- Old clients omitting `scope` still get global.
- Old clients requesting `type=races` bypass the new cache.
- Clients without character/remote-asset capabilities receive the same filtered
  presentation because filtering occurs after the shared raw cache.
- New internal flags/keys are never serialized; older backends simply remain
  uncached and current clients already handle their responses.
- During the Phase-A `pm2 reload`, every reader remains in legacy mode; new
  workers already issue generation-advancing invalidations, but an overlapping
  old worker may still issue only `DEL`. The guard cannot be enabled until those
  old workers are proven drained. During the subsequent guard-flag propagation,
  guarded readers reject any versionless payload and use Postgres, while
  dependent surface flags remain off. Only after convergence are all fills used
  by the new social caches generation-guarded.

## 9. Test plan (tests first)

### Backend public integration tests

1. **Flag-off parity:** seed users/steps/friendships; call all leaderboard
   periods/scopes, `GET /friends`, and modern search with all four flags off;
   capture responses and query counts; assert zero new topology-payload/ranking/
   lock/rate keys (existing presentation-cache behavior is unchanged). Then
   perform one friendship and one presentation mutation and assert that only
   their expected new generation markers may be created.
2. **Cache-on deep parity:** with unchanged source rows, repeat with flags on and
   assert JSON deep equality for old/no-capability and modern/capability headers.
   Then mutate steps and assert any stale response is one internally coherent
   snapshot; the first read after 15 seconds starts one rebuild, and no stale
   ranking survives `asOf + 60 seconds`, regardless of publication time.
3. **Global sharing/isolation:** two viewers with the same boundary reuse one
   raw global key but receive their own `currentUser`; different date boundaries
   do not share.
4. **Capability isolation:** a warm modern request followed by a frozen-client
   request cannot leak `animal`, remote-only assets, or test-only cosmetics.
5. **Leaderboard semantic matrix:** ties, zero steps, hidden users, review
   accounts, viewer inside/outside top 10/100, no friends, and all four periods
   match the existing route contract. Include a request whose clock is held at
   a timezone/date boundary. An outside-top-100 global viewer must invoke the
   complete legacy path; it may not produce `rank <= 100` while absent.
6. **Friends-board reuse:** a second identical friends-scope ranking request
   avoids the grouped step query and stays response-equal, including the
   absent-row versus stored-zero case. Pause between its grouped top-100 query
   and outside-viewer rank query, commit a step mutation from another
   connection, and assert the result still reflects one `REPEATABLE READ`
   snapshot rather than components from two database states.
7. **Stale/rebuild:** after soft TTL, concurrent reads return a valid stale core
   while exactly one rebuild runs; after physical expiry, no request receives a
   wrong-viewer result and Redis-down uses PG. Run bursts whose loader exceeds
   the measured wait budget and whose first holder exceeds the lock TTL; assert
   per-process single-flight, bounded cross-worker fallback, and that the older
   holder cannot overwrite a newer `buildStartedAt` (including equal-timestamp
   tie behavior). Also make a cold loader run past `asOf + 60 seconds`; it must
   refuse publication and the next request must use/rebuild from Postgres, not
   receive a newly published already-expired snapshot.
8. **Friends roster cache:** the second `GET /friends` avoids friendship reads;
   rename, photo add/remove, equip/unequip, and sticky `team_races` capability
   are visible immediately through presentation invalidation without deleting
   topology.
   Include an accepted review-account friend: `GET /friends` keeps that friend,
   while friends/global leaderboards continue excluding review accounts.
9. **Friendship invalidation matrix:** manual send, reciprocal accept, explicit
   accept, decline/reopen, remove, referral auto-friend, redeemed referral,
   quick-share auto-friend, and account delete immediately update both affected
   users' next `GET /friends`.
10. **Failed invalidation:** force topology DEL failure; affected reads bypass
    stale topology until retry succeeds; the friendship mutation still succeeds.
    Repeat for a presentation DEL failure and assert batched reads use Postgres
    until the bypass closes.
11. **Cold-fill interleavings:** pause topology/presentation between PG read and
    Redis install; commit a friendship change, rename, photo change, or sticky
    capability change; assert generation WATCH aborts stale installation and
    the first post-commit read is current. Add a mixed-binary simulation where
    an old invalidator only deletes and an old fill can write versionless data:
    while the guard is false, dependent surface flags must take complete legacy
    paths; after old workers drain and the guard is observed true, versionless
    data is a miss and a new invalidation aborts the guarded fill.
12. **Leaderboard eligibility epoch:** warm both scopes, then hide/unhide a user and
    delete an account. The transaction advances the epoch and the first
    post-commit request cannot reuse the old key. A poisoned cached global row
    that is deleted/hidden/review-ineligible forces a complete PG fallback,
    never a hole; a hidden accepted friend remains present in friends scope.
    With an old epoch-0 core warm, force the epoch Postgres read to fail and
    assert neither scope reads or writes an epoch-0 ranking key: it executes the
    full legacy path or returns the existing 500 if that path also fails.
13. **Search Redis counter:** queries 1-30 succeed, 31 returns the unchanged 429
    code/header; keys contain only user ID + minute, expire, and never contain q.
14. **Search fallback:** flag off, `REDIS_URL` unset, and Redis unreachable each
    use the Postgres counter and preserve validation/rate behavior.
    Also test repeated mid-minute flag/mixed-worker transitions and a response-
    lost-after-execution fallback, without resets, against the documented
    60-request split-counter bound. Separately test eviction, repeated restart/
    reset, and malformed/non-integer/non-positive Lua replies: verify safe PG
    fallback and unchanged visibility, while explicitly making no strict
    request-count assertion for repeated resets.
15. **Poisoned Redis payloads:** wrong schemas/types, versionless/mismatched
    generations, every missing-marker/payload permutation, invalid `asOf`,
    duplicate ranking IDs, and partial/misaligned batch results all produce a
    full PG fallback and no partial assembly. The empty initial state alone may
    install generation `0`, and it creates marker + payload atomically.
16. **Search result freshness:** rename/discoverability/photo changes are visible
    on the next search because result pages are not cached.
17. **Race leaderboard compat:** `type=races` writes no new ranking keys and is
    deep-equal with cache flags on/off.

### Backend performance/structural tests

1. Warm global leaderboard: no grouped step query and no user-presentation PG
   query when presentation keys are warm.
2. Warm friends page: no friendship or user-presentation PG query.
3. Cold presentation hydration: one bulk user query, not N queries.
4. Modern friend search with Redis counter: no
   `friend_search_rate_windows` write. Automated tests verify index definitions
   and predicate compatibility; actual planner choice is captured on
   production-like staging for representative two-character and longer queries
   because a small test DB may rationally choose a sequential scan.
5. Cache key tests reject raw search text and keep all env prefixes isolated.
6. Structural guard enumerates every friendship and presentation mutation seam,
   including exported Friendship model writers and the only review-status seam.
7. A 16-combination flag matrix covers the three surface flags plus generation
   guard. Search remains independent; friends/leaderboard create no new surface
   keys and use complete legacy paths whenever the prerequisite guard is off.
   Flag-off mutations may create topology/presentation generation markers;
   flag-off reads never create topology-payload/ranking/lock/rate keys, while
   the pre-existing presentation flag retains its prior behavior.

### Frontend verification

- Run existing widget suites for LeaderboardTab, FriendsTab, identity search,
  refresh, and legacy fallback unchanged. No new unit-only behavior test is
  warranted because no frontend behavior changes.

### Commands

- Backend: confirm `DATABASE_URL` names the dedicated local test DB, then run
  the single new integration suite first; later `npm run test:unit` and
  `npm run test:integration`. Never run bare `npm test`.
- Frontend: `flutter analyze`, relevant widget suites, then `flutter test`.

## 10. Acceptance criteria / definition of done

- [ ] All new tests exist and fail for the intended reason before business logic.
- [ ] New flags off: response parity and no topology-payload/ranking/lock/rate
      keys; pre-existing presentation behavior is unchanged, and post-commit
      mutations may create topology/presentation generation markers. Redis
      absent: the wrapper writes no keys at all.
- [ ] With unchanged source state, cache-on responses are deep-equal across
      viewer, timezone, privacy, and capability variants; after a step write,
      any stale ranking is one coherent snapshot within the 60-second hard bound
      measured from `asOf`, never publication.
- [ ] Warm `GET /friends` performs no friendship/user presentation query.
- [ ] Warm global and friends leaderboards avoid grouped ranking work; the cold
      friends board preserves absent-row versus stored-zero semantics.
- [ ] Modern search no longer writes Postgres for rate limiting while Redis is
      healthy, and never caches/logs query text; the throttle is documented as
      best-effort with no strict bound under repeated Redis resets.
- [ ] Every friendship mutation is visible immediately on the next friends read.
- [ ] Names/photos/cosmetics/client capability changes are visible immediately
      through presentation invalidation.
- [ ] Privacy/eligibility/account deletion advances the durable leaderboard epoch in
      the same transaction and cannot expose a stale cached row post-commit.
- [ ] An eligibility-epoch Postgres read error never falls back to epoch `0` or
      reuses a warm ranking key; both scopes take the complete legacy path.
- [ ] Cold-fill mutation races cannot reinstall stale topology/presentation, and
      an expired old leaderboard lock holder cannot overwrite a newer snapshot.
- [ ] Friends top-100 rows and viewer rank/total come from one repeatable-read
      Postgres snapshot, including under a concurrent step commit.
- [ ] Old invalidators and guarded readers never overlap: dependent caches stay
      on complete legacy paths until the generation guard has converged on every
      new-binary worker; binary rollback follows the reverse safe order.
- [ ] Redis down/flush/eviction causes only cold latency, never incorrect auth,
      privacy, settlement, or mutation behavior.
- [ ] Search GIN indexes are verified before rollout; missing/invalid prod
      indexes are reported, not silently worked around.
- [ ] Staging shows a material p95 improvement for each named surface and no
      increased 5xx/429 anomaly over a 24h soak.
- [ ] Redis memory remains below the existing 75 MB alert threshold.
- [ ] `flutter analyze`, frontend tests, backend unit tests, and backend
      integration tests are green.
- [ ] Both iOS and Android are explicitly accounted for; no app build change is
      needed.
- [ ] Architect and combined-diff code reviewer report no required findings.
- [ ] No production action occurs without separate explicit approval.

## 11. Open questions

None. The paused API cleanup is additive and response-level; this feature's raw
topology boundary deliberately supports either future assembler.

## 12. Revision log

- **Draft v1:** Explored the Flutter request paths, leaderboard/friend/search
  handlers and queries, friendship mutation seams, existing Redis wrapper and
  key schema, per-user presentation cache, app-setting flags, Prisma indexes,
  identity-search GIN index runbook, and Redis operations runbook. Chose raw-
  core/topology caching with read-time overlays to avoid viewer/capability leaks.
- **Gap pass 1:** Removed the proposed friends/today reuse of the existing
  daily-step integer cache after finding that it collapses “no row” and “stored
  zero,” which would change leaderboard membership. Pinned an accepted-friend-
  set hash in friends-board keys so membership changes never require SCAN or an
  unbounded invalidation list. Added raw current-viewer stats for >100-friend
  boards, the existing in-top-100 current-user shape quirk, deleted-presentation
  filtering, bounded cold-lock loser polling, background-rebuild error handling,
  and the one flag-off exception caused by fixing existing presentation-key
  invalidation.
- **Gap pass 2:** Pinned independent flag behavior and an eight-combination
  integration matrix; required the friends cold loader to preserve the current
  accepted/incoming/outgoing query split and result order; required batched
  presentation reads to preserve boxed-null values and prefix bypass; added
  presentation-invalidation failure coverage; forced the leaderboard flag-off
  path to dispatch to the existing implementation; and anchored the request
  clock so awaited calls cannot mix date boundaries or freshness ages.
- **Architect review round 1 — REVISE:** Required race-safe generation-guarded
  topology/presentation fills; coherent global current-user handling and a
  durable privacy/eligibility generation; an executable stale-ranking parity
  contract; real stampede/result-order protection; a complete friendship-writer
  inventory; strict malformed-Redis fallback; and injectable services under the
  repo's module layout. All required items were folded into §§3–10. Suggestions
  on split search-counter windows, staging planner evidence, and accepted review
  friends were also adopted.
- **Post-review gap pass 1:** Replaced Redis-only global eligibility versioning
  with an uncached authoritative numeric AppSetting advanced in the same
  transaction as hide/unhide/deletion, avoiding an eviction ABA privacy leak.
  Added 2-hour generation backstops, exact wait/lease formulas from measured
  cold p95, accepted-review-friend parity, full legacy fallback outside cached
  global top 100, and the transactional visibility setter path.
- **Post-review gap pass 2:** Tightened leaderboard publication to strictly
  newer `buildStartedAt` with equal-time no-replace behavior; added flag-read
  failure fallback for search; documented mixed old/new worker handling of
  generation-less presentation payloads; and aligned the long-lock test with
  the publication token.
- **Architect review round 2 — REVISE:** Required one-snapshot friends cores;
  hard freshness measured from `asOf`; an honest unbounded-reset caveat for the
  Redis search throttle; a two-phase mixed-binary generation-guard rollout; and
  moving the eligibility epoch out of the leaderboard router module. Also
  suggested explicit initial-generation rules. All findings were incorporated.
- **Post-review gap pass 3:** Put top-100 and viewer scalars in one short
  repeatable-read transaction; made publication TTL consume loader time and
  reject exhausted snapshots; separated the single-transition search bound from
  repeated-reset behavior; added the default-off generation prerequisite and
  reverse-order binary rollback; and moved the eligibility service to shared
  config with explicit builder injection.
- **Post-review gap pass 4:** Added the durable eligibility epoch to friends-
  ranking keys so an existing user becoming review-eligible cannot remain
  absent until TTL. Specified every missing marker/payload state, expanded the
  flag matrix to 16 combinations, limited hidden-user rejection to global
  cores, and added mixed-binary, concurrent-step, and over-60-second-loader
  integration cases.
- **Architect review round 3 — REVISE:** Required fail-safe epoch-read errors;
  reconciliation of flag-off key rules with unconditional rollout invalidators;
  and correction of response-lost search-counter semantics. Suggested literal
  millisecond ranking expiry and distinguishing repeated flag toggles from
  Redis resets. All findings and suggestions were incorporated.
- **Post-review gap pass 5:** Made epoch lookup failure bypass ranking keys for
  both scopes and added a warm-epoch-0 failure test. Limited flag-off reads to
  zero payload/ranking/lock/rate writes while requiring post-commit presentation
  and topology generation advances whenever Redis is configured; aligned the
  rollout, flag matrix, and acceptance criteria.
- **Post-review gap pass 6:** Corrected lost-reply behavior to the 60-request
  split-counter allowance without resets, reserved the unbounded caveat for
  repeated Redis resets/evictions, required `PX remainingMs`, and added exact
  response-lost/reset tests.
- **Architect review round 4 — APPROVE:** No required or optional findings.
- **Owner sequencing hold:** Implementation deferred until the separate API-
  contract cleanup completes. The final contract must be re-explored and this
  spec re-reviewed before fresh owner approval.
- **API-cleanup reconciliation:** Owner confirmed the cleanup implementation had
  not started and paused it in favor of this work. Reviewed
  `api-contract-payload-cleanup-requirements.md`; its only direct overlap is the
  additive future friends summary/Home friends response. Kept caching below
  response assembly, explicitly excluded those contracts here, and restored
  implementation approval.
- **Focused reconciliation review — REVISE:** The architect found that the
  future compact friends contract still needs identity/capability fields but
  forbids cosmetic joins. Reuse is now limited to raw topology; legacy assembly
  keeps full presentation hydration and the future cleanup owns a separate lean
  projection. No remaining cache-contract change was required.
- **Focused reconciliation review round 2 — APPROVE:** No required or optional
  findings remained; owner approval authorizes implementation.
- **Implementation review:** Backend and frontend agents completed the approved
  work. Final combined review found and then verified fixes for outside-top-100
  rebuild discrimination, cross-list topology poisoning, Redis outage versus
  lock-contention fallback, and missing large/tie/zero/hidden parity fixtures.
  Final verdict: **SHIP** with no blockers, issues, or nits. Focused feature
  suites are green; broader repo suites retain unrelated pre-existing failures.
