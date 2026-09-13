# Home read caching and request-reduction requirements

## Summary & user story

When a signed-in user opens Home, the app should do less repeated PostgreSQL
work and fewer duplicate network round trips while preserving authoritative
behavior for steps, rewards, balances, eligibility, ownership, and inbox state.

This plan applies to the current Home implementation in app version 2.3.13.
It does not add race standings to Home. The backend retains a standings branch
only for frozen clients below app version 2.3.0; current requests set
`X-App-Version: 2.3.13`, and `/home/race-card` skips joined-race cards at
`src/modules/home/routes.js:141-145` and
`src/modules/home/getHomeRaceCard.js:1820-1879`.

## Scope

1. Measure the current Home cold-load and refresh path, including Redis hit/miss
   and PostgreSQL query counts.
2. Remove the duplicate current-client Inbox unread request when the Home
   payload already contains the same count.
3. Verify and preserve the existing read-through Redis caching for Home
   milestone display inputs, and add read-through caching only for the
   rewarded-ad extra-spin display status if measurements justify it.
4. Evaluate, and only implement if measurements justify it, short-lived
   caching for Home suggestions and service-banner resolution.
5. Preserve the existing partial caching of friends, presentation, catalogs,
   giveaway banners, impact summaries, auth envelopes, and race-list fragments.

## Non-goals

- No active-race standings or race-progress snapshot work for current Home.
- No cache of the complete `/home/race-card` response.
- No cache of balances, coin ledgers, purchase eligibility, reward
  authorization, or settlement inputs as authoritative data.
- No database migration.
- No new user-visible UI or layout behavior.
- No release flag, rollout percentage, kill switch, or temporary runtime toggle
  unless an architect review establishes an exceptional compatibility or
  operational requirement and receives explicit approval.

## Current load path

`MainShell._loadHomeAndShowResults` persists steps, then starts
`/home/race-card`, `/home/suggested-races`, and `/races` concurrently; after the
Home response it conditionally requests `/shop/catalog` and `/friends`, then
requests `/auth/me` (`lib/screens/main_shell.dart:2890-2920`). The current
Home-shell contract normally embeds presentation and friends, so the latter
two are fallback requests only.

Before that load, the shell separately requests
`/inbox/alerts?limit=1` for the bell badge
(`lib/screens/main_shell.dart:1868-1871`, `4308-4328`). The current Home
response already contains `inboxUnreadCount`
(`src/modules/home/buildHomeRaceCardResponse.js:216-243`).

## Cache/storage decisions

### Keep as-is

These are already appropriate Redis derived-data surfaces:

- User presentation/equipment fragments.
- Friend topology and presentation fragments.
- Pending invite candidate fragments.
- Global event display data.
- Per-user impact summaries.
- Per-user Home inbox unread count.
- Active giveaway banner.
- The assembled `/auth/me` envelope.
- Stable `/races` list fragments; dynamic per-user/live fields remain rebuilt.
- Catalog item definitions and asset manifests.
- Home milestone display inputs (`currentSteps` and `claimedThresholds`) via
  `ce:v1:milestones:{userId}:{localDate}`, with a 30-second TTL and existing
  invalidation after step-row changes and milestone claims.

Every existing cache remains rebuildable from PostgreSQL and falls back to
PostgreSQL when Redis is unavailable, malformed, stale, or bypassed.

### Change 1: use the Home unread count and remove the duplicate request

The backend already reads the unread count through the Redis-backed
`v1:home:inbox-unread:{userId}` key with a 60-second TTL. The frontend should
defensively parse `data['inboxUnreadCount']` in `_applyHomeCore` and update the
shell badge through `_setInboxUnreadCount`.

The initial standalone `/inbox/alerts?limit=1` request should no longer run on
the normal current-backend path. If Home fails, the response is malformed, or
the field is absent because an older backend is serving the request, the shell
must issue the existing Inbox fallback once. This is additive and preserves
older backend behavior.

The Inbox alert list remains PostgreSQL-backed. Only its unread count is cached;
the alert rows and read state remain authoritative database reads.

### Change 2: verify the existing milestone display cache

Milestone display inputs are already cached in Redis through
`src/modules/steps/services/milestoneDisplayCache.js`, keyed by:

`ce:v1:milestones:{userId}:{localDate}`

The cached value contains only `currentSteps` and `claimedThresholds`. The
existing 30-second TTL and invalidation seam in
`milestoneCacheInvalidation.js` must be integration-tested on the Home path.
No second milestone cache should be created. The fixed milestone thresholds
and coin amounts remain code/config policy, while claim authorization and coin
awarding continue reading PostgreSQL inside the claim command.

### Change 3: cache rewarded-ad extra-spin display status

Add a per-user/per-date Redis derived-data fragment keyed by:

`v1:user:daily-ad-extra-spin:{userId}:{localDate}`

The cached value contains only the display status:

```json
{
  "available": true,
  "pendingGrant": false,
  "used": false
}
```

The extra-spin grant/consume command remains PostgreSQL-authoritative and must
invalidate the key after commit. Use a short TTL, proposed at 30 seconds, as a
backstop. Validate the shape and fail closed to an unavailable display state
if the source response is missing or malformed.

Because this is a new cache surface, the implementation must follow the
backend’s established Redis derived-data contract: versioned/env-prefixed key,
bounded TTL, invalidation-only writers, Redis-error fallback, and tests with
Redis both available and unavailable. The architect review must resolve
whether the project’s permanent-cache policy permits a new permanent surface
without a runtime flag.

### Change 4: suggestions, only if measured necessary

Do not cache the full `/home/suggested-races` response by default. It is
viewer- and capability-dependent and changes with race capacity and membership.

First measure its query cost. If it is a material Home-load contributor, prefer
caching shared discovery candidates briefly and applying the user’s membership,
capacity, and capability filters from authoritative data. If a full response
cache is still chosen, its key must include user identity and every capability
variant that changes eligibility, and invalidation must cover race creation,
start, join, leave, retirement, and relevant friendship/membership changes.

### Change 5: service banner, only if measured necessary

App settings are already cached through the shared settings cache. Keep
contest-linked validation PostgreSQL-backed unless measurements show it is a
meaningful Home cost. If cached, use a short-lived derived banner view and
invalidate on service-banner or contest updates; never cache a stale banner in
a way that bypasses capability or eligibility checks.

## API contract

No public response fields are removed or repurposed.

The existing additive `inboxUnreadCount` field remains optional and defensive:

- valid non-negative integer: use it for the Home badge;
- missing/null/malformed: preserve the prior badge and issue the existing Inbox
  fallback once;
- Redis unavailable: backend computes the count from PostgreSQL and returns the
  same response shape.

Milestone and ad-status changes are internal read-path changes. Their existing
HTTP response shapes remain unchanged. Redis is never a source of truth.

## Backend implementation path

1. Add or extend integration fixtures using a dedicated local/test PostgreSQL
   database and local Redis DB 15. Confirm `DATABASE_URL` is not production.
2. Add failing endpoint-level tests for Home unread-count consumption and
   fallback behavior, then implement the frontend contract handling.
3. Add failing backend integration tests for existing milestone cache parity,
   post-sync/claim invalidation, ad-status cache parity, invalidation, shape
   validation, Redis miss, and Redis outage.
4. Verify the existing milestone cache and invalidation seam through the public
   Home endpoint; do not modify it unless a failing test identifies a real
   defect.
5. Implement the ad-status cache with a dedicated key builder and cache helper
   only if architect review approves the new surface.
6. Instrument Home phases with cache source, hit/miss, fallback, query count,
   and round-trip timing. Record measured before/after values; do not claim a
   scalability improvement from TTLs alone.
7. Review suggestion and service-banner query measurements. Implement only a
   justified optimization, with its key, TTL, source of truth, invalidations,
   and Redis outage behavior documented before coding.

## Frontend plan

- Update `MainShell._applyHomeCore` to consume `inboxUnreadCount` defensively.
- Move the standalone Inbox request behind a one-shot compatibility/error
  fallback instead of firing it unconditionally before Home.
- Do not add UI states or change layout.
- Keep `Loadable` behavior unchanged for Home sections.
- Keep tutorial/demo paths unchanged because no new network call or visible
  surface is introduced.
- Verify iOS and Android use the same behavior; no platform-specific code is
  needed.

## Backward compatibility and deployment

- Deploy backend changes first. Existing app versions continue receiving their
  existing Home contracts.
- New cache reads always fall back to the pre-cache PostgreSQL query.
- Older backends that omit `inboxUnreadCount` trigger the existing Inbox
  fallback in the new app.
- Older app versions ignore any additive fields and retain their legacy Home
  behavior; the retired standings cache remains only for those compatibility
  requests.
- No production deployment is authorized by this document. Deployment requires
  separate, in-the-moment approval.

## Tests-first plan

### Frontend

- Pump the real `MainShell` with a Home response containing a valid unread
  count; assert the badge uses it and no eager Inbox request occurs.
- Assert missing, null, malformed, and negative counts trigger at most one
  fallback request and preserve the prior badge on fallback failure.
- Assert an older backend response without the field still renders Home safely.
- Assert the current Home path does not depend on race standings data.

### Backend

- Real HTTP Home request with warm and cold inbox-count cache; assert identical
  client-visible JSON.
- Real HTTP Home request with Redis unset/down; assert PostgreSQL fallback and
  no 500.
- Real milestone endpoint/Home embedding tests for cold read, warm read,
  step-sync invalidation, claim invalidation, and explicit zero/empty values.
- Real ad-status endpoint/Home embedding tests for available, pending, used,
  invalidated, missing, and Redis-outage states.
- Existing compatibility tests for app versions below and above 2.3.0,
  proving current Home does not enter the standings path while legacy clients
  retain it.
- Structural tests proving no claim or reward authorization reads Redis.

## Acceptance criteria

- Current Home has no active-race standings cache dependency.
- The normal current Home open removes one duplicate Inbox network request while
  preserving an older-backend/error fallback.
- Milestone display reads remain cached and invalidated without changing claim
  authorization or coin behavior; existing coverage proves this through Home.
- Ad display status is cached only if the architect approves the new cache
  surface and all invalidation/fail-open tests pass.
- No complete Home response, balance, ownership, reward authorization, or
  settlement input is cached in Redis.
- `flutter analyze`, relevant Flutter tests, backend unit tests, and backend
  integration tests pass; no integration test touches production PostgreSQL.
- Measured request/query/cache metrics are reported before the change is called
  complete.

## Revision log

- Draft 1: separated current Home behavior from the legacy standings branch;
  removed standings from the current-scope cache inventory.
- Gap pass 1: added the older-backend fallback for the optional unread-count
  field, explicit Redis outage behavior, and the requirement not to cache claim
  authorization or coin data.
- Gap pass 2: added tests-first ordering, dedicated local Redis/test DB rules,
  invalidation timing after step sync and claims, no UI/tutorial impact, and a
  measurement gate before caching suggestions or service-banner resolution.
- Architect review: invoked against the finished draft; the review agent did
  not return findings before it was stopped. No implementation approval is
  implied; the open review concern remains the policy treatment of any new
  ad-status cache surface or runtime control.
