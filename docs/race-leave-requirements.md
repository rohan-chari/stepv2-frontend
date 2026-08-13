# Leave pending and active races — requirements

## Summary and user story

As a participant, I can exit a race I no longer want to be in, from its real
Race Detail screen. The action is explicit and confirmed because it can affect
the prize pot, standings, and the remaining racers.

This expands the current narrow team-only actions: pending team lobby leave and
active team forfeit. New app-funded races have no participant buy-ins; retained
legacy races do. Leaving adjusts the prize pot, and an active leaver's score
freezes.

## Scope

- Replace the Race Detail header's action cluster with a three-dot vertical
  overflow menu, and add the leave/forfeit affordance there for eligible
  signed-in participants in `PENDING` and `ACTIVE` ordinary races.
- Confirm the effect before the irreversible server mutation, prevent double
  submission, update affected pot state, and return to the
  previous list/shell after a successful pending leave.
- Keep the existing team pending leave and team active forfeit semantics unless
  the decided general contract intentionally supersedes them.
- Normalize a personal-list tournament row to the same card hierarchy, color,
  spacing, typography, avatar scale, trailing status/chevron treatment, and
  responsive height as ordinary race rows, including `COMPLETED`.
- Within each selected personal Races state (`ACTIVE`, `PENDING`, and
  `COMPLETED`), group list rows beneath Home-style section headers: `CLASSIC`
  for ordinary individual races, `TEAMS` for team races, and `TOURNAMENTS` for
  brackets. Omit an empty group and preserve the existing race-before-
  tournament ordering required by tutorial spotlights.
- Make the Races-tab `PUBLIC RACES (n)` count include every joinable public
  individual race, team race, and tournament, and refresh it after creation.

## Non-goals

- No leave action for `COMPLETED`/`CANCELLED`, invite-only nonparticipants,
  spectators, or tournament matchup races.
- No creator cancellation redesign, race deletion, new race-list controls, or
  changes to scoring/payout rules unless the decision below expressly requires
  them.
- No client-side authorization: all eligibility and financial effects remain
  server-enforced.
- No tournament rules, brackets, prizes, or discovery eligibility change—only
  the card presentation and existing discovery count aggregation.

## Added tournament-list and discovery findings

- `RacesTab` intentionally renders tournament entries through a separate
  `_buildTournamentRow` visual system (`races_tab.dart:1085`) rather than the
  standard `_buildRaceRow` card system (`races_tab.dart:1349`), explaining the
  off-format tournament at the bottom of the supplied screenshot. The shared
  row composition must be extracted or parameterized so pending, active, and
  completed tournament entries use standard card chrome without losing their
  bracket-specific metadata.
- The displayed `PUBLIC RACES (n)` is populated only from
  `fetchPublicRaces().length` (`main_shell.dart:1959`); public tournaments are
  loaded by a separate endpoint in `PublicRacesScreen`. A public tournament
  created by Nathan therefore cannot increase your button count. The backend
  discovery summary/count and frontend refresh path must aggregate joinable
  public individual races, team races, and tournaments, excluding the viewer's
  own, joined, full, terminal, or otherwise ineligible entries.

## Existing behavior and constraints

- The frontend already calls `POST /races/:raceId/leave` for only a pending
  non-creator team participant ([backend_api_service.dart](../lib/services/backend_api_service.dart):2371)
  and presents its confirmation in Race Detail ([race_detail_screen.dart](../lib/screens/race_detail_screen.dart):1311).
- Active team participants instead use `POST /races/:raceId/forfeit`, with a
  permanent no-refund, frozen-step warning ([race_detail_screen.dart](../lib/screens/race_detail_screen.dart):1196)
  and a low-priority active-screen button ([race_detail_screen.dart](../lib/screens/race_detail_screen.dart):4839).
- The backend's legacy `leave` command deliberately rejects individual races
  and creators; its held-buy-in release applies only to retained legacy
  buy-in races ([leaveRace.js](/Users/rohan/repos/stepv2-backend/src/modules/races/commands/leaveRace.js):54).
- The backend already exposes additive, old-client-safe routes for pending
  leave and active team forfeit ([routes.js](/Users/rohan/repos/stepv2-backend/src/modules/races/routes.js):875).

## Decided lifecycle policy

- A pending non-creator leaves by having their participant row removed.
- A pending creator uses the existing whole-race cancellation path.
- An active non-creator permanently forfeits: their score freezes at the live
  total at the moment of action and they cannot rejoin.
- An active creator uses the existing whole-race cancellation path.
- A pending leave removes the participant from the projected funded prize-pool
  count, so their app-funded amount is removed from the pot.
- An active forfeit keeps the frozen participant in the funded prize-pool count,
  only when they have positive qualifying steps. The forfeiter is ineligible
  for a payout and the entire settled pool is redistributed through a
  deterministic payout-tier calculation among remaining eligible finishers.
- An active zero-step forfeiter does not preserve a pool entrant; their amount
  is removed under the existing anti-alt/no-show rule.
- Full redistribution is intentional even though coordinated lower-ranked
  forfeits can concentrate the existing pool at the top; it must not mint extra
  coins.

This matches the existing app-funded formula: pre-settlement pool projection is
computed from accepted participants, while settlement stamps the final pool
from racers who walked ([racePrizePool.js](/Users/rohan/repos/stepv2-backend/src/modules/races/racePrizePool.js):14).

Money compatibility cases are explicit: pending legacy releases its held
buy-in and removes the row; pending app-funded removes the row and lowers only
the *projected* pool; active legacy retains committed pot coins but excludes a
forfeiter from payout; active app-funded preserves the active-pool entrant
count only for a positive-step forfeiter, then redistributes across eligible
finishers.

## API contract

Prefer a single additive action endpoint rather than changing an existing
endpoint or response shape:

`POST /races/:raceId/leave`

Request body: `{}`.

Every read payload that can open Race Detail (`GET /races/:raceId` at minimum,
plus its progress/list equivalents where their cards expose the menu state)
adds nullable `leaveAction`: `"LEAVE"`, `"FORFEIT"`, or `null`. The Flutter
client renders the new participant exit action only for the exact supported
string; missing, null, malformed, or unknown values mean no exit action. This
is the version-skew gate: a newly installed binary pointed at an older backend
does not offer an action that backend cannot honor.

Success: `200 { "success": true, "action": "LEFT" | "FORFEITED", "prizePool"?: { ... } }`.
`action` is additive; the current Flutter client must treat a missing value as
success. The server owns all state transitions and must atomically perform the
participant update/removal or active freeze, applicable prize-pool/payout
eligibility update, cache invalidation, and downstream resolution enqueue.

Possible errors must remain stable JSON `{ "error": string, "code"?: string }`:

- `404 RACE_NOT_FOUND`
- `403 NOT_A_PARTICIPANT`
- `400 TOURNAMENT_RACE_LOCKED`
- `400 RACE_CREATOR_CANNOT_LEAVE` (if the final policy keeps cancellation)
- `400 RACE_NOT_LEAVABLE` for terminal/unsupported state
- `409 RACE_ALREADY_STARTED` only if a legacy pending-only contract remains

The existing `/forfeit` endpoint should either remain as a backwards-compatible
alias/implementation path for active team races or continue to be used by the
client; it must never be removed because old app builds call it. Creator
cancellation remains `DELETE /races/:raceId` for both pending and active races.

## Data model and migration

The existing `RaceParticipant` row and (for active forfeits) the existing
frozen/forfeited representation are expected to suffice. Confirm the existing
prize-pool source and atomic update path during implementation. If a new
status/timestamp is needed, add it
additively with nullable/default-safe reads; backfill existing rows only where
their legacy meaning is unambiguous.

## Frontend plan (after policy lock)

1. Update `BackendApiService` only if the final server contract needs a new
   action/method; parse all optional response fields defensively.
2. In `RaceDetailScreen`, derive eligibility from status, authenticated
   participant identity, creator identity, team/tournament state, and any
   additive server fields. Missing fields must hide the new action rather than
   imply eligibility.
3. Put a `more_vert` kebab control at the far right of the fixed Race Detail
   header, preserving its existing 24px light icon, 8px touch padding, and
   `AppColors.roofLight` header chrome. Replace the current creator-only
   `more_horiz` trigger at `race_detail_screen.dart:3139`; do not introduce
   default Material popup styling.
4. Opening it presents the existing parchment `RACE OPTIONS` bottom sheet
   style (`race_detail_screen.dart:6073`): 16px rounded top corners, PixelText
   title, 24px side padding, and full-width `PillButton`s. It conditionally
   contains only relevant actions:
   - `NOTIFICATIONS ON/OFF` for an accepted, active, non-spectator participant;
     it invokes the existing combined placement/chat mute implementation.
   - `INVITE FRIENDS`/`INVITE MORE` for the eligible creator.
   - `EDIT SETTINGS` only for a pending eligible creator.
   - `LEAVE RACE` for a pending non-creator participant.
   - `FORFEIT RACE` for an active non-creator participant; its confirmation
     states the frozen score and final pot effect.
   - `CANCEL RACE` for an eligible creator, using the existing confirmation.
   `CANCEL RACE`, `LEAVE RACE`, and `FORFEIT RACE` use the existing accent
   destructive pill and are last in the sheet. No ineligible action is
   rendered; tournament, spectator, demo/tutorial, terminal, and malformed
   payload states show no mutation menu.
5. Keep Share as its dedicated header icon because sharing is a frequent,
   non-destructive primary action. The kebab consolidates only secondary
   settings/actions and removes the separate notification-bell icon.
6. On success, refresh race state and the displayed prize pot. A pending leave
   pops with a truthy result so callers refresh their lists. An active leave
   reloads detail and progress when the participant remains viewable; otherwise
   returns to the caller. Convert API errors to existing user-safe error toast
   copy.
7. Apply identically to iOS and Android through shared Dart. `demoMode` and
   tutorial fixtures must not accidentally expose a destructive live action.

## Backward compatibility and rollout

- Deploy backend first. The endpoint is additive and old binaries neither call
  it nor require a new response field.
- Preserve old `leave` and `forfeit` semantics/paths for shipped clients; do
  not repurpose a former error response into behavior that violates their UI
  assumptions.
- Ship the Flutter build only after the backend is production-verified. The
  new leave/forfeit UI must safely remain absent when pointed at an older
  backend or when the additive `leaveAction` field is missing.
- No `testOnly` asset/content gate is expected.

## Tests-first plan

Backend agent, before command changes:

1. Integration test each final pending/active participant and creator policy
   through HTTP against the dedicated test database.
2. Test that pending departure reduces the projected funded pool; active
   departure freezes score, preserves the active pool, and excludes the
   forfeiter from payout while reallocating it to eligible finishers. Cover
   participant/standings/payout consequences, endpoint idempotency/concurrency,
   terminal/tournament/spectator rejection, and preserved legacy `/leave` and
   `/forfeit` contracts.

Frontend agent, before UI changes:

1. Pump the real Race Detail with final eligible pending and active fixtures;
   verify header/menu placement and styling, conditional menu contents,
   notification toggle relocation, confirmation consequences, request
   invocation, disabled in-flight state, success navigation/reload, pot
   refresh, and API error toast.
2. Assert absence for terminal, spectator/invite, tournament, demo/tutorial,
   creator cases where policy excludes them, and missing/invalid optional
   eligibility fields.

## Acceptance criteria / definition of done

- The final policy is unambiguous and every eligible pending/active case has
  one confirmed exit path.
- Consequences are accurately stated and enforced by the backend.
- Existing clients retain their current behavior; new clients degrade safely
  against version-skewed responses.
- Tests are written first and pass; `flutter analyze` is clean; iOS and Android
  are both accounted for.
- Architect, UI-placement checklist, and post-implementation code review run.

## Manual UI-placement test plan

*Elements under test:*

- Race Detail header: replace the creator-only horizontal options icon and active-racer notification bell with one far-right vertical kebab; keep Share as its own header icon.
- Race Options sheet: move `NOTIFICATIONS ON/OFF` into it and place relevant secondary actions there: invite, edit, cancel, leave, or forfeit.
- Remove the notification bell and horizontal-options control from their former header positions; do not duplicate their actions elsewhere.

*Checklist*

1. **Surface:** Real Race Detail — active, accepted non-creator ordinary race
   **Get there:** Races tab → open an active race where your account is an accepted participant, not the creator, and notifications are available.
   **Verify:** Share remains a dedicated header icon; a single `more_vert` kebab is at the far right. The notification bell is absent from the header and there is no horizontal-options icon. Open the kebab: `NOTIFICATIONS ON/OFF` and `FORFEIT RACE` appear in the sheet, with `FORFEIT RACE` last; neither appears outside the sheet.

2. **Surface:** Real Race Detail — pending, accepted non-creator ordinary race
   **Get there:** Races tab → open a pending race you joined but did not create.
   **Verify:** The far-right vertical kebab is present; no notification bell or horizontal-options icon remains. Its sheet contains `LEAVE RACE` as the final destructive action, and does not show notification, creator invite/edit/cancel actions.

3. **Surface:** Real Race Detail — pending creator ordinary race
   **Get there:** Races tab → open a pending race created by your account.
   **Verify:** Share remains separate and the vertical kebab replaces the old horizontal icon. The sheet orders `INVITE FRIENDS`, then `EDIT SETTINGS`, then final destructive `CANCEL RACE`; `LEAVE RACE`, `FORFEIT RACE`, and notification controls are absent. No old header actions are duplicated.

4. **Surface:** Real Race Detail — active creator ordinary race
   **Get there:** Races tab → open an active race created by your account.
   **Verify:** The vertical kebab is the only secondary header control. Its sheet shows `INVITE MORE` and final destructive `CANCEL RACE`; notification, leave, and forfeit actions are absent. The old horizontal-options and notification-bell positions are empty.

5. **Surface:** Demo race tutorial
   **Get there:** Sign in with a fresh account → onboarding → continue through the demo until the race-detail beat.
   **Verify:** The shared Race Detail header does not expose a kebab, notification bell, horizontal-options icon, or Race Options sheet. Share/invite/options remain suppressed in this fake race; no destructive action leaks into the tutorial.

6. **Surface:** Tab tutorial race-detail preview
   **Get there:** Profile → admin/tutorial controls → re-run the tab tutorial → advance to “Powerups & boxes.”
   **Verify:** The previewed real Race Detail screen exposes no kebab, notification bell, horizontal-options icon, or mutation sheet despite its active accepted fixture. The `raceDetail.powerups` spotlight still rings the powerups block in its existing position.

7. **Surface:** Tournament matchup Race Detail
   **Get there:** Races tab → open an active tournament → open your matchup.
   **Verify:** No kebab or Race Options sheet appears; no notification, leave, forfeit, invite, edit, or cancel control is exposed. The previous creator-only horizontal-options control also remains absent.

8. **Surface:** Spectator/invite/terminal Race Detail
   **Get there:** Open an invite-only race as a nonparticipant/spectator, then a completed or cancelled race.
   **Verify:** No kebab or Race Options sheet appears, and neither old header control remains. Share may remain where independently eligible, but no secondary mutation control is duplicated in the header.

*Risks found while planning:*

- The tutorial preview is an active accepted non-creator fixture and currently passes no `demoMode`; without an explicit preview-safe suppression signal/fixture capability it can expose the new notification/forfeit menu or attempt fake-service writes.
- The demo race correctly uses `demoMode: true`, but the new vertical kebab condition must retain that guard so its actions never appear.
- The current notification bell is independently eligible while the current sheet is creator-only. Replacing only the old `more_horiz` condition would strand active participants without a way to open notification/forfeit actions.
- The new kebab must be visible for every eligible non-creator participant, not only creators, while tournament, spectator, terminal, malformed, demo, and tutorial states must render no mutation menu.

## Revision log

- Gap pass 1: identified that “leave active races” conflicts with the existing
  permanent team-only forfeit model; added explicit decisions for frozen score,
  prize pot, creator cancellation, and individual-race behavior.
- Gap pass 2: removed the incorrect buy-in/refund assumption; added
  server-authoritative prize-pot adjustment, legacy endpoint preservation,
  tournament/spectator exclusions, navigation/reload behavior, version-skew
  fallbacks, and financial/concurrency test coverage.
- Revision after menu direction: moved secondary race actions into the existing
  parchment `RACE OPTIONS` bottom-sheet pattern, changed the header control to
  a vertical kebab, retained Share as a direct action, and moved the existing
  active-race notification toggle into the menu.
- Revision after lifecycle clarification: a pending leave decreases the
  app-funded projected pool; an active forfeit retains that pool and
  redistributes it through existing eligible-finisher payouts.
- Architect review: requires endpoint-specific backward-compatible responses,
  token-gated `exitAction`, a default-off stamped per-race policy, explicit
  legacy/funded settlement and payout eligibility, transaction serialization,
  and demo/tutorial test coverage. These are mandatory implementation steps.
- Economy review: zero-step forfeits do not count toward the active funded pool;
  all otherwise eligible settled pool coins are conserved and redistributed.

## Additional manual UI-placement test plan — tournament-row parity

*Elements under test:*

- Tournament rows in the Races tab: align their card placement, outer bounds, row rhythm, and trailing content placement with standard race cards in pending/active and completed lists.

*Checklist*

1. **Surface:** Real Races tab — active list
   **Get there:** Sign in to an account with both an active ordinary race and active tournament → Races → select `ACTIVE`.
   **Verify:** The tournament row follows the ordinary race card with matching side margins, card width, vertical spacing, border/shadow footprint, avatar-to-content alignment, and trailing-column/chevron position. It is not offset, taller, inset, or visually detached from the standard race-card sequence.

2. **Surface:** Real Races tab — pending list
   **Get there:** Use an account with both a pending ordinary race and pending tournament → Races → select `PENDING`.
   **Verify:** The tournament row occupies the same card slot and list rhythm as the ordinary pending-race card; it is not rendered as a legacy ticket, separate block, or differently inset row.

3. **Surface:** Real Races tab — completed list
   **Get there:** Use an account with both a completed ordinary race and completed tournament → Races → select `COMPLETED`.
   **Verify:** Completed tournament rows match completed race cards’ horizontal bounds, vertical spacing, and trailing alignment; no old standalone tournament-card treatment remains.

4. **Surface:** Compact-device/list screenshot check
   **Get there:** Repeat one populated state above on the smallest supported phone, with enough rows to require scrolling; capture a full-width screenshot of adjacent ordinary-race and tournament rows.
   **Verify:** The tournament card remains aligned with the list edges and adjacent card cadence without clipping, unexpected extra whitespace, or a visibly different card footprint in the compact screenshot.

5. **Surface:** Tab tutorial preview
   **Get there:** Profile → admin/tutorial controls → re-run the tab tutorial → inspect Races `ACTIVE`, `PENDING`, and `COMPLETED` states as available.
   **Verify:** Preview tournament rows use the same updated card placement as production for active, pending, and completed fixtures. The first ordinary active race remains before the tournament rows so `races.card` and `races.box` spotlights still ring the intended standard race card and box.

*Risks found while planning:*

- `tutorialPreviewRacesData` has explicit active, pending, and completed tournament fixtures, so a mismatch there is a real mirror failure, not an unavailable test state.
- The personal list deliberately renders ordinary races before tournaments; preserve that order or tutorial spotlights can target the wrong row.
