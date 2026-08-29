# Pinned races section requirements

## Summary & user story

As a player with important races across multiple shelves, I want one `PINNED`
section at the top of the Races tab so my favorited classic races, team races,
and tournaments are immediately reachable without switching status shelves.

The section is a cross-shelf view of the player's existing server-persisted
favorites. It does not change race eligibility, status filters, tournament
behavior, notifications, scoring, or ordering inside the existing shelves.

## Scope / non-goals

In scope:

- A top-level `PINNED` section above the status pills and ordinary race shelves.
- Pinned classic races, team races, and tournaments in one mixed list.
- Pin/unpin controls for accepted ordinary races and tournaments.
- Server persistence across refresh, reinstall, logout/login, and devices.
- Loading, empty, malformed-response, mutation-failure, and old-backend states.

Out of scope:

- Pinning invitations before acceptance.
- Pinning public/featured discovery cards that the user has not joined.
- Changing the existing ACTIVE/PENDING/COMPLETED shelf ordering.
- A local-only fallback that pretends a pin persisted when the server rejected it.
- Any release flag or rollout toggle.

## Product behavior

1. The `PINNED` section appears first when at least one pinned item exists.
2. Its entries are grouped visually as `CLASSIC`, `TEAMS`, and `TOURNAMENTS`,
   omitting empty groups. The groups retain the existing row/card styles.
3. Mixed pinned ordering is deterministic: classic races, team races, then
   tournaments; within each group retain the existing type-specific secondary
   ordering (active soonest-ending first, then existing status/date ordering).
4. A pinned item opens its normal destination: race detail for ordinary races,
   tournament detail/bracket for tournaments.
5. The existing star control remains the source of truth. Tapping it updates the
   pinned section and the originating shelf optimistically; repeated taps for
   the same item are coalesced/disabled. Failure restores the prior state and
   shows an error toast.
6. Unpinning the last item removes the entire section without leaving spacer
   slivers. Pull-to-refresh and tab re-entry rebuild it from server state.
7. Pinned section and existing shelves must work in light/night themes, narrow
   phones, large text, iOS, and Android.

## API contract

### `GET /races`

Extend the existing ordinary race summaries with the already-supported
caller-specific fields:

```json
{
  "races": [
    {
      "id": "race-id",
      "name": "Tuesday Steps",
      "status": "ACTIVE",
      "isTeamRace": true,
      "isFavorite": true,
      "favoritedAt": "2026-08-29T14:00:00.000Z"
    }
  ],
  "tournaments": [
    {
      "id": "tournament-id",
      "name": "Weekend Knockout",
      "status": "ACTIVE",
      "isFavorite": true,
      "favoritedAt": "2026-08-29T14:01:00.000Z"
    }
  ]
}
```

The tournament fields are additive. Existing clients ignore them. Missing,
null, malformed, or absent favorite fields mean not pinned on the frontend.
The endpoint must return only races/tournaments the caller is already eligible
to see; pinning never expands visibility.

### Favorite mutation

Use the existing ordinary-race favorite endpoint:

`PUT /races/:raceId/favorite`

It accepts `{ "favorite": true }` and returns HTTP `200` with `raceId`,
`isFavorite`, and nullable `favoritedAt`. Add the exact tournament equivalent:

`PUT /tournaments/:tournamentId/favorite`

Request:

```json
{ "favorite": true }
```

Response:

```json
{
  "tournamentId": "tournament-id",
  "isFavorite": true,
  "favoritedAt": "2026-08-29T14:01:00.000Z"
}
```

The tournament endpoint returns HTTP `200` with the same shape, replacing
`raceId` with `tournamentId`. It is idempotent and membership-protected. A
non-boolean request returns HTTP `400` with `{ "error": "...", "code":
"INVALID_FAVORITE" }`; unauthenticated requests return `401`; non-member or
unavailable resources return coded `403`/`404` domain errors. Plain `404` is
reserved for route absence on an older backend. Timeouts and `5xx` responses
remain retryable. No existing endpoint gains a required parameter.

## Data model / migrations

Ordinary race favorites use the existing caller-specific `RaceParticipant`
favorite fields (`favoritedAt` / equivalent current implementation).

Add nullable `favoritedAt DateTime?` to `TournamentParticipant`, reusing its
existing `(tournamentId,userId)` uniqueness. Add an index supporting
`(userId,favoritedAt)` lookups. The migration is additive and nullable; no
backfill is required. Existing memberships default to unpinned. Accepted-only
writes are allowed; declined/non-member writes are rejected. Existing leave,
rejoin, and cancellation eligibility rules remain authoritative.

Do not store a global `Race.isPinned` value: pinning is caller-specific.

## Frontend implementation plan

Primary file: `lib/screens/tabs/races_tab.dart`.

- Extend the safe parsing/list-entry model to carry favorite state for both
  ordinary races and tournament entries.
- Add `_pinnedEntries` as a derived view over all loaded eligible entries.
- Render a `PINNED` sliver before the existing invite strip/state pills, with
  keyed group headers and lazy rows.
- Reuse `_buildRaceRow` and `_buildTournamentRow`; do not create divergent
  pinned card implementations.
- Reuse the existing favorite mutation/optimistic rollback path for ordinary
  races and add the tournament equivalent.
- Namespace optimistic keys as `race:<id>` and `tournament:<id>` across all
  loaded buckets, and reconcile only against authoritative mutation responses
  or refreshes; rollback on failure.
- Ensure the tutorial keys remain attached to the original shelf's first card,
  not silently moved to a pinned duplicate.
- If an old backend omits tournament favorite data or the endpoint is absent,
  tournaments remain in their normal shelves and the pinned section still works
  for ordinary races.

Pinned ordering is deterministic: group order `CLASSIC`, `TEAMS`,
`TOURNAMENTS`; within each group status order `ACTIVE`, `PENDING`,
`COMPLETED`; active sorts by parsed `endsAt` ascending, pending by existing
pending date ascending, completed by existing completed date descending; null
or malformed dates sort last, then stable ID ascending. If `tournaments` is
absent, its group is empty.

The backend/API service changes belong in
`lib/services/backend_api_service.dart`. The feature must be represented in
the same Dart code path for iOS and Android; no platform-specific behavior is
needed.

## Backward compatibility & rollout

- Deploy backend API/schema support before shipping the app change.
- Old app versions ignore additive tournament favorite fields and continue to
  use existing race shelves.
- New app versions default missing favorite fields to false and do not crash on
  an older backend.
- A plain route-absence `404` disables only tournament pin/unpin for the session;
  coded domain `404`s, timeouts, and `5xx`s remain retryable errors.
- Postgres is the favorite source of truth. Redis is not used for mutation or
  settlement; any cache extension must document key variant, TTL,
  invalidation, and Postgres fallback.
- No feature flag, rollout percentage, or runtime toggle is permitted.

## Test-first plan

Backend, against a dedicated test database only:

1. Tournament favorite/unfavorite integration through the public HTTP route.
2. Idempotent repeated writes and membership/authorization failures.
3. `GET /races` returns caller-specific tournament favorite fields and omits
   other users' state.
4. Old request shapes and old clients' existing race responses remain valid.

Frontend, pumping the real `RacesTab`:

1. Pinned section appears above pills and contains mixed classic/team/
   tournament entries.
2. Empty groups and empty section disappear without spacer content.
3. Pinned ordering and existing shelf ordering remain deterministic.
4. Pin/unpin moves cards optimistically in both locations and rolls back on
   failure.
5. Missing/null/malformed favorite fields degrade to unpinned without throws.
6. Tournament and ordinary cards navigate to their normal destinations.
7. Large text, narrow width, night mode, and tutorial preview data render
   without overflow or misplaced tutorial anchors.

## Manual UI-placement test plan

- Races tab with one pinned classic race, one pinned team race, and one pinned
  tournament: verify `PINNED` is first and each card opens the correct screen.
- Verify empty groups are omitted and the whole section disappears after the
  final unpin.
- Verify pinning/unpinning from both the pinned section and the original shelf
  updates both locations immediately.
- Verify ACTIVE, PENDING, and COMPLETED shelves retain their current ordering.
- Verify unanswered race/tournament invites remain above the status pills and
  cannot be pinned before acceptance.
- Verify the existing races tutorial/demo preview keeps its spotlight targets
  on the intended original card.
- Verify iOS/Android, light/night themes, narrow devices, and large text.

## Acceptance criteria / definition of done

- Pinned classic, team, and tournament entries are server-persisted and shown
  together at the top of Races.
- Existing clients and old/malformed payloads remain safe.
- Backend integration tests and frontend real-screen tests are written first
  and pass; no existing assertion is weakened or removed.
- `flutter analyze` is clean; backend tests use the dedicated test database.
- Both platforms are accounted for and the UI checklist above is manually
  verified.
- Architect, UI test planner, backend developer, frontend developer, and
  code-reviewer workflow requirements are satisfied before presenting done.

## Revision log

- Draft 1: separated ordinary race favorites from tournament favorites,
  required caller-specific persistence, defined additive old-client behavior,
  and preserved existing shelf ordering.
- Gap pass 1: added explicit invite/public eligibility rules, missing-route
  degradation, tutorial key placement, and no-flag requirement.
- Gap pass 2: added idempotency, authorization, malformed-field handling,
  dedicated test-database requirement, and cross-platform/manual checks.
- Architect pass: fixed the exact `PUT` contract, selected
  `TournamentParticipant.favoritedAt`, distinguished route-absence from coded
  `404`s, defined namespaced optimistic state and deterministic ordering, and
  documented cache and old-client compatibility requirements.
