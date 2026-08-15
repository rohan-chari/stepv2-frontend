# Race Participants Pagination and Powerup-Use Context — Requirements & Implementation Spec

**Repos:** `stepv2-frontend` (Flutter iOS+Android) and `stepv2-backend` (Node/Express/Prisma/Postgres).  
**Date:** 2026-08-14  
**Status:** Draft ready for Architect/Checklist review + user approval.

## 1. Summary and user story

Race detail participant rendering is currently tied to `GET /races/:raceId/progress`, which returns full participant data every poll. For 300+ entrants this makes initial render and periodic polls slow. We will split read paths:

- `GET /races/:raceId/progress?view=participants-v1&offset=...&limit=...` for the race board UI, returning only the next page of participants and no powerup inventory in each poll payload.
- `GET /races/:raceId/powerups/use-context` for action-time powerup targeting, returning full participant targeting context plus inventory so the picker is always correct.

## 2. Confirmed current behavior and evidence

- `RaceDetailScreen` currently calls `fetchRaceProgressCompact()` on load + 30s poll (`lib/screens/race_detail_screen.dart` lines 920-975, 964-967) and uses `_progress['participants']` as the live source for ranking + targeting.
- `_usePowerup` builds candidates from `_progress['participants']` (lines 1714-1725) and applies `TeamRace.offensiveTargets` / `targetsAheadOf`.
- The backend currently returns full participant set on `/races/:raceId/progress` and only conditionally switches to compact response contract for `view=compact-v1` (`stepv2-backend/src/modules/races/routes.js` lines 1218-1244).
- Sneaky Swap already has a dedicated endpoint at `/races/:raceId/powerups/sneaky-swap-targets` (backend lines 1606-1633), with fallback logic in front-end (`lib/screens/race_detail_screen.dart` lines 2274-2317).
- `TeamRace.offensiveTargets` and `TeamRace.targetsAheadOf` already enforce self/stealth/forfeit/team constraints (`lib/utils/team_race.dart` lines 296-344).
- Demo/tutorial and preview services mirror race detail calls via explicit overrides (`lib/demo/demo_race_api_service.dart` lines 27-58, 340-355 and `lib/tutorial/tutorial_preview_data.dart` lines 325-355), so they must be updated for new pagination contract.

## 3. Scope / non-goals

### In scope
- Race detail participant pagination for race listing and rendering.
- Action-time powerup targeting correctness with deferred full-context endpoint.
- Backend + frontend contracts + tests.
- Demo + tutorial fixture/API service updates as needed.

### Not in scope
- Pagination on `/races` list.
- Powerup rules / balance changes.
- Database schema changes for scoring, effects, eligibility, or powerups.

## 4. Functional requirements

1. Initial detail open renders quickly by loading only the first page (default 10) of participants.
2. A “Show X more” action appends the next participant page.
3. Powerup targeting remains correct even when a target isn’t in the loaded page.
4. No hard dependency on new backend fields for old app binaries.
5. Zero required-field assumptions in frontend (defensive reads).

## 5. API contract (additive)

### 5.1 Existing endpoint (unchanged)
`GET /races/:raceId/progress`

- Behavior unchanged for classic requests without `view=participants-v1`.
- `view=compact-v1` remains unchanged (currently no participants slimming).

### 5.2 New participants-only view
`GET /races/:raceId/progress?view=participants-v1&offset=<int>&limit=<int>`

- If no values provided: default `offset=0`, `limit=10`.
- Clamp:
  - `offset >= 0`
  - `limit` min 1 max 50; default 10.
- Invalid/absent values fall back to defaults.
- Returned shape:

```json
{
  "contract": "race-progress-participants-v1",
  "progress": {
    "status": "ACTIVE",
    "participants": [
      { "userId": "string", "displayName": "string", "profilePhotoUrl": "string|null", "team": "TEAM_A|TEAM_B|null", "status": "ACCEPTED|DECLINED|...", "finishedAt": "2026-...Z|null", "forfeitedAt": "2026-...Z|null", "placement": 1, "totalSteps": 1234, "currentMultiplier": 2, "stealthed": false, "presentation": {"prod": {"animal": "string|null", "accessories": []}} }
    ],
    "powerupData": null,
    "globalEvent": null,
    "myPlacement": 5,
    "myPlacementHidden": false,
    "pagination": {
      "offset": 0,
      "limit": 10,
      "total": 312,
      "hasMore": true,
      "nextOffset": 10
    }
  }
}
```

- `participants` must be an accepted-only, leaderboard-ordered page for ACTIVE races (same filter order as current ACTIVE progress).
- For non-ACTIVE status, server MAY return the full participant list in one response to avoid regressions; this endpoint is additive and explicitly opt-in.
- `powerupData` and `globalEvent` are omitted/null as before to keep payload lean and avoid touching existing powerup/box state.

### 5.3 New action-time context
`GET /races/:raceId/powerups/use-context`

Response:

```json
{
  "contract": "race-powerup-use-context-v1",
  "participants": [
    { "userId": "string", "displayName": "string", "profilePhotoUrl": "string|null", "team": "TEAM_A|TEAM_B|null", "status": "ACCEPTED", "placement": 1, "totalSteps": 1500, "finishedAt": null, "forfeitedAt": null, "stealthed": false }
  ],
  "powerupData": {
    "powerupSlots": 3,
    "inventory": [ {"id":"uuid","type":"SHORTCUT","status":"HELD"} ],
    "queuedBoxCount": 0,
    "myPlacement": 1
  }
}
```

Notes:

- Full active participants only (accepted, non-deleted states).
- `participants` includes the fields needed for picker rendering and server-side parity.
- `powerupData` provides request-scope inventory needed for use flow parity with existing full-progress path.
- Errors: `404`/`403` same contract pattern as existing powerup paths.

### 5.4 Contract behavior matrix

| Request | Participants | Inventory in-response | Backward compatibility |
|---|---|---|---|
| `/races/:id/progress` | full | full | unchanged |
| `/races/:id/progress?view=compact-v1` | full | compact global inventory | unchanged |
| `/races/:id/progress?view=participants-v1` | paged page | omitted | additive |
| `/races/:id/powerups/use-context` | full active participant set | includes viewer + slot/queued context | additive |

## 6. Backend implementation plan

### 6.1 Query/service additions
- Extend `getRaceProgress` query (`stepv2-backend/src/modules/races/queries/getRaceProgress.js`) with optional pagination args (`participantsView`, `participantsOffset`, `participantsLimit`) and additive behavior:
  - when `participantsView==='paged'`, return only requested page rows for ACTIVE state.
  - keep existing leaderboard semantics for sort order and masking.
- Route parser in `stepv2-backend/src/modules/races/routes.js` parses view/offset/limit in `loadRaceProgress(req)` and passes to query.
- Add new route `/races/:raceId/powerups/use-context` in `routes.js`:
  - resolves accepted participant context + viewer inventory in one handler.
  - reuses existing model query paths where possible (`findPowerupUseContext` or explicit dedicated query if needed).
  - always returns a stable contract with additive inventory summary.

### 6.2 Data integrity / compatibility
- No schema migration required in phase 1.
- If/when adding new DB support index, keep additive: verify existing index coverage first, then add non-blocking index only if perf tests show regression.
- Old clients never call `view=participants-v1` or `/powerups/use-context`; therefore all old binary behavior remains via unmodified `/progress` path.
- Response parsing remains defensive (no required response fields assumed).

### 6.3 Performance
- Pagination reduces payload size on large ACTIVE races and 30-second polls.
- Keep snapshot/mask semantics untouched so ranking + detour/stealth behavior stays server-authoritative.

## 7. Frontend implementation plan

### 7.1 Service additions
In `lib/services/backend_api_service.dart`:

- add
  - `fetchRaceProgressParticipants` (GET `/races/:id/progress?view=participants-v1&offset&limit`)
  - `fetchRacePowerupUseContext` (GET `/races/:id/powerups/use-context`)
- both methods parse defensively and return `globalPowerupInventory == null` style safe defaults when missing.

### 7.2 `RaceDetailScreen` state and flow (`lib/screens/race_detail_screen.dart`)

- On open/poll:
  - initialize `offset=0`, request paged progress first.
  - display list from `_progress['participants']`.
  - preserve existing full payload fields from non-participant sections (status, myPlacement, events).
- “Show X more”:
  - request next page and append in-place.
  - disable while loading; show inline loading row; disable at `hasMore == false`.
- Powerup action:
  - precompute candidates from loaded participants.
  - for targeted powerups, if `participants.length < pagination.total`, call `fetchRacePowerupUseContext` before opening picker.
  - merge/swap candidate source before picker.
- Fallback safety:
  - if `fetchRacePowerupUseContext` fails (404/network), fall back to already-loaded candidates and keep existing toast/empty behavior.
  - preserve all existing `TeamRace.offensiveTargets`, `TeamRace.targetsAheadOf`, and server-side validation paths unchanged.

### 7.3 Demo/tutorial surface updates
- `lib/demo/demo_race_api_service.dart` and `lib/tutorial/tutorial_preview_data.dart` must override both new endpoints:
  - paged endpoint: return first 10 + no pagination metadata edge-case semantics in fixtures.
  - use-context endpoint: return the full fabricated participant list + inventory summary used by demos.
- Because race detail in tutorial is the real screen fed by fixture services (`lib/tutorial/tutorial_real_screens.dart` lines 136-145), stale calls must remain fully mocked.

### 7.4 Invariant behavior
- no crashes on missing fields.
- no new nullable assumptions in target picker paths.
- page state must survive poll refresh and continue appended ordering without reset unless explicit refresh/filters are needed.

## 8. Backward compatibility and rollout

- Backend-first rollout.
- New fields are additive; no required fields on old contracts.
- If backend does not yet support paged view, frontend must detect and degrade to legacy compact path + existing target logic.
- If powerup-use-context is unavailable, fallback to existing loaded-only candidates.

## 9. Test plan (tests first)

### Backend (`stepv2-backend`)
1. Extend `test/integration/api-contract-payload-cleanup-contracts.test.js`:
   - add assertions for `?view=participants-v1` payload and pagination metadata.
2. Add tests for endpoint `/races/:id/powerups/use-context`:
   - includes full accepted participants, my participant inventory summary, and 403 for non-active participant.
3. Add perf/regression test for 300 participants:
   - paged endpoint returns exactly one page by default and `hasMore` flag.
   - use-context path still returns all participants and target context.
4. Add unit test for pagination parser/normalization (default/clamp/sanitize values).

### Frontend (`stepv2-frontend`)
1. Add/expand API contract test for new methods (`test/api_contract_payload_cleanup_frontend_test.dart` or dedicated service test).
2. `test/race_detail_standings_scroll_test.dart`: add pagination behavior and appended rows.
3. `test/race_detail_target_*` (team/bounty/sneaky) and `_target_steps_sanitization_test.dart`:
   - when target is outside loaded page, use-context fetch is triggered and picker receives full set.
4. `test/demo_race_network_guard_test.dart` and `test/demo_race_engine_test.dart`: assert new methods are overridden so demo does not leak to live backend.

## 10. Risks and edge cases

- Targeting accuracy if first page excludes targets:
  - mitigated by action-time fetch.
- Poll refresh may append duplicate rows when page state and poll state race:
  - guard with dedupe (`userId`-keyed append) and stable ordering.
- Offset/limit abuse:
  - sanitize server-side and client-side.
- Open inventory for powerup action should never depend on stale page participants.

## 11. Open questions (resolved)

1. **Scope:** participants in race detail only, not race list. ✅
2. **Pagination size:** fixed server cap `limit <= 50`, default 10. ✅
3. **Powerup context payload:** include active inventory summary in `/powerups/use-context` for picker parity. ✅

## 12. Gap pass log

- **Pass 1:** mapped current slow path, identified participants-only loading and action-time context fallback.
- **Pass 2:** validated compat constraints from AGENTS (`no required-field client assumptions`, frozen-client safety).
- **Pass 3:** added explicit pagination request/metadata contract and mandatory fallback behavior when new endpoint is unavailable.

## 13. Architect/technical review (required)

### REQUIRED
- Keep `loadRaceProgress` argument list additive to preserve route dependency injection tests.
  - In `routes.js`, avoid changing existing argument count in existing call sites; thread pagination in an options object.
  - Additive defaults for new query args are mandatory so old call sites remain identical.
- In `getRaceProgress`, preserve existing ACTIVE progress masking (stealth/detour/matching placement rules) in paged mode.
  - Returning a slice before masking would introduce visible discrepancies.
- On `/races/:raceId/powerups/use-context`, enforce `ACCEPTED`-only participants.
  - Never include `INVITED`/`DECLINED` rows as selectable targets.

### SUGGESTIONS
- Add a dedicated lean DB index for paged reads only after a measured perf test indicates a win (e.g., `(race_id, status, joined_at)` or query-appropriate equivalent).
- Consider caching pagination response metadata (`total` and `hasMore`) with a short TTL only if real-user profiling shows poll cost still high after page slicing.

## 14. UI-placement test plan (manual)

**Manual UI-Placement Test Plan — Race detail participant pagination + deferred powerup context**

**Elements under test:**
- Race detail participants list / standings table expansion behavior.
- Powerup target picker launch path for targeted powerups.

**Checklist**

1. **Surface: Real race detail list (main app)**
   - **Get there:** Open any active race.
   - **Verify:** first render shows only first page (10).
   - **Verify:** tapping “Show X more” appends next page and does not jump/rewind.
   - **Verify:** once total loaded, CTA disables (or says no more participants).

2. **Surface: Real race detail target picker**
   - **Get there:** In the same race, open a targeted powerup that depends on participant filtering (Bounty/Quicksand/Trail Mine/etc.).
   - **Verify:** if a valid target is outside first page, picker still shows it.
   - **Verify:** if no targets exist globally, shows the same empty-state path as before.
   - **Verify:** old behavior preserved on older path fallback (simulate with offline backend flag or endpoint failure in dev proxy if available).

3. **Surface: Demo race tutorial (`RaceDetailScreen` in `TutorialRealHost`)**
   - **Get there:** Enter tutorial race detail flow that renders real screen with preview API.
   - **Verify:** same list paging behavior appears with deterministic fixture data.
   - **Verify:** no live network call for new endpoints (service methods overridden in `DemoRaceApiService`/`TutorialPreviewBackendApiService`).

4. **Surface: Tutorial race preview card**
   - **Get there:** Open race detail preview path from tutorial host.
   - **Verify:** preview participants and powerup picker source appears correctly with same semantics as real race detail.

**Surfaces confirmed unaffected:**
- Home/leaderboard/friends/profile screens are out of scope and should be visually unchanged.
- Team race scoreboard placement rendering is unchanged except for the source list now arriving in pages.

**Risks found while planning:**
- Powerup picker list anchors and spotlight placement can drift if target-sheet structure changes while adding page controls; keep old/new structure identical except list container data source.
- Demo/tutorial fixtures must implement both paged endpoint and use-context endpoint, otherwise fresh dev/probe builds may leak live network calls.

## 15. Definition of done

- `flutter analyze` clean.
- Backend contract/logic tests and frontend tests added and passing.
- Old client compatibility preserved (no required fields in old contracts).
- Performance win measured in synthetic 300+ participant active-race scenario (initial payload smaller, first paint faster).
- Manual ui-placement checklist completed before implementation done.
