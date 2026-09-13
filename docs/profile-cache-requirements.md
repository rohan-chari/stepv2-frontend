# Profile page cache requirements

Status: draft for approval

## Summary & user story

As a signed-in user, I want the Profile page to open and refresh quickly without
repeating the same PostgreSQL work, while still seeing my latest steps, streak,
race results, balance, and account changes after the relevant mutation.

This is an internal backend caching change. The Flutter API shapes remain
unchanged.

## Current behavior

The Profile page is assembled from several independent reads:

- `ProfileTab` mounts `StepCalendar` and `_StatsSection`.
- `StepCalendar` calls `GET /steps/calendar?month=YYYY-MM`.
- `_StatsSection` calls `GET /steps/stats?view=profile-v1`.
- Profile identity is normally already held by `MainShell`/`AuthService`; a
  profile refresh calls `GET /auth/me?view=shell-v1`.
- `/auth/me` has a 10-second Redis read-through cache for its assembled payload,
  but still performs an authoritative `users.displayName` query on every
  request for the rename gate.

Evidence:

- Frontend composition: `lib/screens/tabs/profile_tab.dart:486-511`.
- Calendar request: `lib/widgets/step_calendar.dart:40-69`.
- Stats request: `lib/screens/tabs/profile_tab.dart:766-818`.
- Shell refresh: `lib/screens/main_shell.dart:4867-4869` and `:5096-5110`.
- Auth cache: `src/modules/users/services/authMeCache.js:78-105`.
- Rename-gate query: `src/modules/users/routes.js:600-610`.
- Profile stats SQL: `src/modules/steps/queries/getProfileStats.js:19-113`.
- Calendar SQL-backed lookup: `src/modules/steps/queries/getStepCalendar.js:20-24`.

## Scope

### In scope

1. Add Redis read-through caching for the profile calendar response.
2. Add Redis read-through caching for the profile stats response.
3. Increase the `/auth/me` cache TTL for the assembled envelope while retaining
   the authoritative rename-gate database check on every request.
4. Add post-commit invalidation for every write that can change one of these
   cached projections.
5. Add metrics and integration tests proving warm reads avoid the relevant
   PostgreSQL work and that mutations make the next read observe fresh data.

### Non-goals

- No new client endpoint or response-field requirement.
- No database migration or new source-of-truth tables.
- No caching of authorization decisions, balances, race settlement inputs, or
  other correctness-critical writes.
- No new runtime release flag, rollout percentage, kill switch, or temporary
  environment control. These are permanent, fail-open derived caches. This
  follows the repository's release-flag prohibition; any exception would need
  explicit approval before implementation.
- No UI layout or visible-placement changes.
- No frontend behavior change beyond receiving fresher/faster existing payloads.

## Proposed cache contracts

All entries are disposable Redis derived data. Redis misses, malformed entries,
Redis errors, and Redis-disabled operation must execute the existing PostgreSQL
loader and return the same response shape. Because a user can have multiple
month/timezone/date variants, invalidation must use the existing generation
fence pattern (`cacheEfficiencyRead`/`cacheEfficiencyInvalidation`) or an
equivalent per-user marker. It must not scan Redis or attempt to enumerate an
unbounded key family on the request path.

### 1. Profile calendar

Logical key:

```text
v1:user:profile-calendar:{userId}:{timeZoneFingerprint}:{yyyy-mm}:{asOfDate}:{schema}
```

Payload: the existing `{ days, stepGoal }` response from
`GET /steps/calendar`.

Proposed freshness:

- Soft TTL: 15 minutes.
- The `asOfDate` key component changes at the user's next local midnight, so
  `isToday` and `future` cannot remain stale across the day boundary.
- Invalidate after a committed step write using the per-user generation marker;
  no key-family scan is allowed.
- The key must include the request timezone because `isToday` and `future` are
  timezone-dependent.
- Use a bounded normalized timezone fingerprint rather than placing an
  unbounded raw header value in the key.
- The schema suffix allows a safe cache-busting change without scanning Redis.

The loader remains `getStepCalendar(userId, month, timeZone)`. The response must
not be cached under a key that omits timezone or month.

### 2. Profile stats

Logical key:

```text
v1:user:profile-stats:{userId}:{timeZone}:{yyyy-mm-dd}:{weekStart}:{monthStart}:{yearStart}:{schema}
```

Payload: the existing `profile-stats-v1` response, including totals, averages,
streak, podium counts, race counts, and win rate.

Proposed freshness:

- Soft TTL: 60 seconds.
- Invalidate after a committed step write for the affected user using the
  per-user generation marker.
- Invalidate after a committed race placement/completion change for every
  affected participant using the same marker.
- The date and period-boundary inputs are part of the key so local day, week,
  month, and year transitions cannot reuse an old projection.
- The schema suffix allows safe payload changes.

The stats query remains the source of truth. Do not cache intermediate SQL
fragments or race settlement inputs.

### 3. Auth envelope and rename gate

Retain the existing `/auth/me` cache family and its compatibility variants:

```text
v1:user:authme:{userId}:{contract}:{fineBucketVariant}
```

The assembled cached payload may contain a validated
`displayNameRequiresRename` value for response reuse, but the route must retain
the extra authoritative `users.displayName` query on every request. This is a
security/remediation decision: Redis invalidation can be delayed or unavailable,
so cache freshness alone cannot decide whether a user is blocked behind a
rename gate.

Proposed TTL:

- Increase the assembled auth envelope from 10 seconds to an initial target of
  5 minutes after the invalidation audit passes. This reduces repeated assembly
  work but does not remove the authoritative rename query.
- Keep immediate invalidation for fields that the client reads directly after a
  mutation. TTL remains a recovery backstop, not the primary freshness method.

The implementation must not make the rename gate dependent on Redis being
available. The route always computes it from authoritative data.

## Invalidation design

Reuse the existing `cacheEfficiencyRead`,
`cacheEfficiencyInvalidation.afterCommit`, `derivedCache`, `cacheKeys`, and
post-commit invalidation patterns. Add allowlisted profile marker domains to
the existing marker layer if needed. Introduce one injected profile-cache
invalidation service that coalesces affected user IDs through
`deferUntilAfterCommitBatch`; it must never issue Redis invalidation inside an
open transaction. Do not introduce a second Redis protocol or write cache
entries from mutation code.

### Step writes

Extend the existing step invalidation seams used by both:

- `src/modules/steps/commands/recordSteps.js`.
- `src/modules/steps/commands/recordStepSyncV2.js`.

Each committed step write advances the user's profile calendar and profile
stats generation markers. A sync that produces no durable change must not
create unbounded invalidation work. A fill that races a committed write must
fail the generation check and return the freshly loaded value without installing
the stale payload.

### Race result writes

Add the profile-stats generation-marker advance to the existing race
presentation invalidation chokepoint rather than adding calls beside every
individual SQL update. Cover the exact inputs used by `getProfileStats`:

| Projection input | Writers/seams to audit |
|---|---|
| `steps.steps`, `steps.date` | Legacy `recordSteps` and canonical `recordStepSyncV2` |
| `race_participants.raw_steps` | Sync/step resolution and race progress writers |
| `race_participants.status` | Join, invite response, forfeiture, and race lifecycle writers |
| `race_participants.placement` | Placement worker and settlement placement writes |
| `race_participants.forfeited_at` | Forfeit command and settlement/repair paths |
| `races.status`, `completedAt` | `raceExpiry` and race resolution completion |
| `races.is_team_race`, `winner_team` | Team settlement and race admin/repair paths |

The implementation must remain behind the race-keyed C0 writer and must not add
a request-path bulk participant writer. The invalidation list is derived from
affected participant user IDs and executes after commit. Same-worker eviction,
cross-worker propagation, failed-invalidation bypass, and retry behavior must
match the existing cache-efficiency protocol.

Relevant existing seam to audit:

- `src/modules/races/services/raceCacheInvalidation.js`.
- Settlement/placement writers under `src/modules/races/jobs/`.

### Auth/profile writes

Audit and test every display-name, profile-photo, user-account, and admin
remediation writer. Existing auth-me invalidation must remain additive. No
direct Redis writes from those commands. The authoritative rename-gate query
remains even if an invalidation is missed.

## API and compatibility contract

No endpoint path, request parameter, or response field changes are required.
Older app versions continue to receive the same `/auth/me`, `/steps/calendar`,
and `/steps/stats` shapes. Cache use is entirely server-side.

The backend must preserve these behaviors:

- Redis unavailable: execute the existing PostgreSQL path.
- Redis disabled or bypassed: execute the existing PostgreSQL path.
- Cache miss/expired/malformed: execute the existing PostgreSQL path.
- Explicit zero, empty lists, and null-compatible fields remain authoritative;
  cache boxing must not turn them into misses.
- Do not serve a cached response across users, timezones, months, period
  boundaries, client contracts, or schema versions.
- The stats cache must store an unfiltered internal projection, then apply the
  existing `profile_podiums` capability filtering after the cache read. A
  capability-filtered response must never be stored under a shared stats key.
- The physical environment prefix is supplied by the existing Redis wrapper;
  cache-key builders must not hardcode production/staging prefixes. Concrete
  schema values are `profile-calendar-v1`, `profile-stats-v1`, and an
  auth-envelope schema version distinct from the legacy auth payload. Payload
  validators must reject any other schema.

Deploy backend changes before any future client change. No client release is
required for this work.

## Implementation order

1. Add cache-key builders, schema validators, generation markers, and
   cache-loader wrappers with tests for key isolation, TTLs, malformed payloads,
   Redis-off behavior, and fallback. Add bounded per-process in-flight
   coalescing so concurrent cold reads do not repeat the same PostgreSQL work.
2. Add the profile calendar cache around the existing loader.
3. Add the profile stats cache around the existing loader.
4. Add step-write invalidation for both legacy and sync-v2 paths.
5. Audit race placement/completion writers and add post-commit profile-stats
   invalidation at the shared presentation invalidation seam.
6. Audit all display-name and remediation writers and preserve/verify auth-me
   invalidation coverage. Keep the per-request rename query.
7. Add bounded hit/miss/fallback metrics and dashboard/runbook notes.
8. Run focused backend integration tests, the backend unit suite, and the
   existing Flutter analysis/tests. No production or staging service is started
   for local verification.

## Test-first plan

Tests must be written before the corresponding implementation and must use real
HTTP, real test PostgreSQL, and isolated Redis where the behavior crosses the
public request path.

### Backend integration tests

- Cold calendar read queries PostgreSQL; warm read returns the same payload
  without repeating the calendar query.
- Calendar cache is isolated by user, month, timezone, and schema.
- Calendar cache changes `asOfDate` at local midnight, including DST boundary
  cases.
- A committed legacy step write invalidates calendar and stats caches.
- A committed sync-v2 step write invalidates calendar and stats caches.
- A completed/placed race invalidates stats for every affected participant.
- Forfeits, participant status changes, raw race-step changes, and team winner
  changes invalidate stats for every affected participant.
- Warm stats include fresh step totals, streak, and race results after the
  corresponding mutation.
- Local day/week/month/year boundary inputs do not reuse an incompatible cache.
- Redis outage, malformed payload, disabled cache, and invalidation failure all
  fall back safely to PostgreSQL.
- `/auth/me` warm reads retain the rename-gate query and still return the
  authoritative result after Redis hits, misses, outages, or invalidation
  failures.
- Older `/auth/me` contract and old-client capability behavior remain unchanged.
- Two-worker tests cover same-worker eviction, pub/sub propagation, failed
  invalidation bypass, retry, commit-vs-rollback ordering, and isolated Redis
  DB15 operation.
- Wrong-shaped calendar, stats, and auth payloads fall back through the public
  HTTP path instead of reaching the client.

### Unit/structural tests where integration cannot express the property

- Key builders reject invalid identity/date/timezone inputs and produce stable
  versioned keys.
- Every supported display-name/remediation writer is structurally connected to
  auth-me invalidation.
- Cache payload validation rejects wrong shapes without throwing.

### Frontend verification

- Existing real Profile widget tests continue to render calendar, stats,
  podiums, and loading/error states.
- No client API changes are expected; verify both iOS and Android code paths
  through the shared Flutter suite and `flutter analyze`.

## Observability and rollout

Record bounded counters/timers for each profile cache family:

- hit, miss, bypass, malformed, Redis error, loader success/error;
- loader PostgreSQL query count where existing instrumentation supports it;
- invalidation success/failure and affected-user count.

Review warm/cold behavior and invalidation failures before increasing the auth
TTL. Redis remains fail-open and PostgreSQL remains authoritative. Production
capacity remains exactly two PM2 HTTP workers; staging stays stopped unless
explicitly authorized.

The architect suggested separate default-off cache flags for the new surfaces.
That conflicts with this repository's explicit prohibition on adding release
flags for ordinary releases, so this plan does not add them. If implementation
evidence shows a flag is genuinely required for mixed-version compatibility,
irreversible migration safety, or exceptional operational risk, stop and seek
explicit approval with an owner, safe default, rollout plan, and removal
condition.

## Acceptance criteria

- Warm profile calendar and stats reads avoid their repeated PostgreSQL loaders.
- A user sees new steps and race results after the committed write path
  invalidates the relevant cache.
- Auth/profile mutations are visible on the next read without relying solely on
  TTL expiry.
- The rename gate remains correct after user and admin display-name changes,
  including Redis outage and missed invalidation scenarios.
- Redis failure, eviction, malformed entries, and disabled operation preserve
  successful existing behavior.
- No endpoint/API compatibility break for frozen app versions.
- Backend integration tests pass against a dedicated test database and Redis;
  `npm run test:unit` passes; `flutter analyze` and relevant Flutter tests pass.
- Code review confirms no unbounded query, invalidation, Redis-key, or
  cross-user/timezone leakage risk.

## Revision log

### Draft revision 1 — initial exploration

- Identified that the profile page is composed from `/auth/me`,
  `/steps/calendar`, and `/steps/stats`, not one endpoint.
- Kept API shapes unchanged because caching is an internal backend concern.
- Added timezone/month/date-boundary dimensions to prevent stale calendar and
  stats projections.
- Required both legacy and sync-v2 step invalidation paths.
- Required race placement/completion invalidation because stats include podiums
  and race outcomes.
- Preserved the authoritative rename-gate requirement until all writers are
  covered.

### Gap pass 1

- Added explicit Redis-off, malformed-cache, and invalidation-failure fallback.
- Added old-client compatibility and no-client-release requirement.
- Added local-midnight handling for calendar `isToday`/`future` fields.
- Added post-commit ordering and no-op step-write constraints.

### Gap pass 2

- Added auth contract/fine-bucket compatibility dimensions.
- Added race forfeiture/team-result invalidation coverage.
- Added observability requirements and production/staging operational limits.
- Added tests for cross-user, timezone, period-boundary, and schema isolation.

### Gap pass 3 — post-architect revision

- Replaced broad family deletion with generation-fenced markers and one
  post-commit/coalescing invalidation service; Redis scans are prohibited.
- Added the calendar `asOfDate` boundary and DST coverage.
- Added capability-safe stats caching: cache the internal projection before
  `profile_podiums` response filtering.
- Retained the authoritative rename-gate DB query; Redis freshness cannot make
  a security/remediation decision.
- Added the exact step/race input and writer matrix, two-worker behavior,
  commit/rollback ordering, payload validators, and stampede protection.
- Rejected the architect's new default-off cache flags because the repository
  contract prohibits new release flags for ordinary releases; any exception
  now requires explicit user approval.

## Architect review

The architect review completed before approval. Required changes were folded
into Gap pass 3. The only review recommendation not adopted is adding separate
default-off cache flags, because that conflicts with the repository's explicit
release-flag rule; the conflict and escalation path are documented above.

## Approval gate

This document is a plan only. Do not implement until the user explicitly
approves the scope, proposed TTLs, and invalidation strategy. After approval,
run architect review again if any material requirement changes.
