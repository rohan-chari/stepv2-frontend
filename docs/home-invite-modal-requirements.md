# Home Invite Modal Requirements

**Status:** Draft — implementation is blocked pending product answers and review.

## 1. Summary and user story

Outstanding race and tournament invitations must be surfaced on **Home** in a
modal presentation, rather than blocking access to the Races tab. A signed-in
walker should see and safely answer an invitation without having to navigate to
Races, while still being able to use every other tab if the invite fetch or an
answer fails.

The invite modal reuses the overlay/presentation contract already used by
`RaceResultsSummaryScreen`: a transparent `PageRouteBuilder`, blurred backdrop,
fade transition, shell-owned launch, and one interactive card at a time. It is
not a `showDialog` bolted to `HomeTab`, because presentation must survive Home
rebuilds, tab changes, refreshes, and a response route being popped.

Product decision already made: if both unseen race results and one or more
outstanding invites exist, **results always show first**. Only after the user
dismisses the results popup may the invite sequence be presented.

## 2. Scope

### In scope

- A Home-triggered, shell-owned modal sequence for current outstanding race and
  tournament invitations.
- Deterministic handling of multiple invites: tournament invites first, oldest
  `createdAt` first; then race invites by earliest non-null
  `myInviteExpiresAt`, then `scheduledStartAt`, then `createdAt`, then ID.
- Accept/decline using the existing authoritative mutation endpoints, a fresh
  server read after every response, and safe handling of stale/concurrent
  responses.
- Ordering with `RaceResultsSummaryScreen`, including its acknowledgement queue
  and quick-create handoff.
- Removal of the Races-tab blocking gate, its entry interception, and its
  feature-flag branch. Races remains an ordinary, refreshable list with its
  normal inline/deep-link invite paths unless separately redesigned.
- iOS and Android from the same Flutter implementation.

### Non-goals

- No new invite state, buy-in economics, expiry rule, accept/decline endpoint,
  notification, deep-link, tournament detail, or race-detail behavior.
- No change to what the backend considers answerable. The server remains the
  sole authority for participant status, team capacity/auto-assignment,
  affordability, invitation expiry, tournament capacity, and idempotency.
- Keep Home's existing `home-pending-invite` card as a non-modal fallback. It
  is suppressed while a Home invite modal is visible for that invite, then may
  render after X dismissal under its existing `/home/race-card` conditions.
- No results-modal visual or payout-double flow redesign.

## 3. Current implementation and correction to the preflight effort

Current/uncommitted Races-tab gating is implemented by
`lib/widgets/race_invite_decision_gate.dart` and mounted by
`lib/screens/main_shell.dart`. It makes the prebuilt Races child opaque and
non-semantic, disables PageView swipes, increments `_racesGateEpoch` on Races
entry, and calls `GET /races/invite-preflight`. The gate’s queue/order and
server-refresh-after-answer behavior are useful source material, but its
blocking ownership and presentation are not reusable as-is.

The existing preflight query is deliberately small
(`../stepv2-backend/src/modules/races/queries/getRaceInvitePreflight.js`), but
it is **not presently a sufficient Home-modal contract**:

1. It has no explicit response-contract/version marker. The Flutter client
   currently treats a 404 as `GET /races` fallback, which was appropriate for a
   Races-tab compatibility branch but would make Home presentation depend on
   inconsistent payload shapes.
2. It filters tournament rows on the request's `tournaments` client feature.
   The new carrying client must advertise a dedicated Home-invites capability
   and receive an explicit, capability-scoped payload; it must not infer that
   the absence of `tournaments` means there are no tournament invites.
3. Its race projection does not include sufficient team-invite disclosure.
   Home must receive a safe `isTeamRace:true` fact (and any other existing
   client capability/required-update fact needed to avoid implying that a
   one-tap accept will succeed) so a team invitation is never misrepresented
   as a classic race. It must still never expose team rosters or hidden data.
4. It must defensively exclude tournament-managed races (`tournamentId !=
   null`) even if a malformed legacy participant row says `INVITED`; those are
   answered only through the tournament endpoint and must never generate a
   duplicate race decision.
5. It selects all `INVITED` race participants whose race is PENDING/ACTIVE;
   implementation must use the canonical expiry predicate: an invitation is
   answerable only while `now < inviteExpiresAt` when that timestamp is set.
   At the exact expiry instant it is excluded from preflight and mutation must
   return the additive `INVITE_EXPIRED` code. An expired row must never create
   an unanswerable modal loop. This is a backend rule, not a client-side expiry
   decision.
6. The existing query's response is shaped as partial `active`/`pending` list
   buckets for the old gate. Home needs a purpose-named array and an explicit
   `resolved` bit so missing/malformed/old-server data means “do not show,” not
   “there are definitely zero invites.”

## 4. User experience and state machine

### 4.1 Trigger and ordering

`MainShell`, not `HomeTab`, owns the presentation coordinator. It runs after a
successful authenticated core-races refresh and on app resume, never during
onboarding/tutorial preview, signed-out state, or while another shell overlay
is current.

Authoritative priority for automatic shell overlays is:

```text
onboarding/tutorial (exclusive)
  → daily reward / an already-current route (defer)
  → unseen race results, including payout-double completion (show and await)
  → Home invite sequence (show and await)
  → existing lower-priority What's New/review/other optional prompts
```

The implementation must make this a single coordinator rather than launching
`_maybeShowRaceResults` and an invite check independently. `RaceResultsSummaryScreen`
must finish its `onBeforeDismiss` acknowledgement enqueue and route pop before
the coordinator reads/presents invitations. If results returns `startNext ==
true`, the already-approved quick-create sheet is shown first; invite sequence
is deferred until that sheet and any creation route it launches have closed,
then rechecked. Never stack an invite blur over results, payout ad, quick-create,
or a detail route.

### 4.2 Invite sequence behavior

- Fetch fresh invite data only when Home is the current tab and the coordinator
  is eligible to present. Do not block Home's first paint or render a Home
  loading/error panel for invite checking.
- If the response is supported, resolved, and contains no live invites, finish
  silently for that refresh generation.
- Display one card at a time. It contains type (`RACE INVITE` / `BRACKET
  INVITE`), name, inviter display name with safe fallback `A runner`, duration,
  active/underway state where meaningful, team auto-assignment fact where
  applicable, and buy-in amount where positive. A paid accept label includes
  the quoted amount but is never a promise that the amount/capacity remains
  valid.
- Each card has **Accept**, **Decline**, and a visible **X** close affordance.
  X dismisses the modal without answering: it does not decline, mark seen, or
  mutate local invite state. It ends the current modal sequence rather than
  immediately cycling to another queued card, restores the eligible inline
  Home fallback, and permits a fresh recheck on a later launch/resume while
  the invitation remains valid. The inline card is suppressed while the modal
  is visible, so the same invite is never presented twice at once.
- A race invitation whose race is already ACTIVE is still presented when it is
  server-authoritatively answerable. Its card displays an **UNDERWAY** fact;
  it is not hidden merely because the user has another active race.
- On Accept or Decline, disable both buttons, call the existing endpoint, then
  fetch the fresh preflight. Do not optimistically remove or mutate the card.
  Show the next live invite from that read; close when none remains.
- `ALREADY_RESPONDED` (400/409) and `NOT_INVITED`/not-found caused by a
  concurrent answer/withdrawal are reconciliation outcomes: refetch once and
  close/advance from the authoritative result. All other failures retain the
  current card, re-enable actions, and show concise mapped error copy plus
  Retry/Dismiss. No automatic retry loop.
- If the fetch fails, is unsupported, says `resolved:false`, or has malformed
  records, show no automatic modal and leave Home usable. Retain last known
  server data only for the current card while an answer is in flight; never use
  it to initiate a new prompt.

### 4.3 Races tab removal

Delete the Races-tab interception as one coherent change: `RaceInviteDecisionGate`,
`_racesGateEpoch`, `_racesGateBlocking`, `NeverScrollableScrollPhysics` tied to
the gate, `racesInviteDecisionGateEnabled`, `fetchRaceInvitePreflight` fallback
semantics exclusive to the old gate, and the gate-only RacesTab constructor
branch. A Races tab entry must refresh normally and must never lock users out
on an offline/error preflight.

Preserve the existing Races inline invite strip/responders until an explicitly
approved follow-up removes or changes it. Race and tournament detail direct
links keep their existing decision behavior. This feature moves *automatic
attention* to Home; it must not reduce available ways to answer an invite.

## 5. API contract

### 5.1 New additive capability-scoped preflight

Adapt the existing lightweight endpoint, rather than shipping a second
standalone preflight: `GET /races/invite-preflight` becomes the Home modal's
data source as part of this combined feature. It is authenticated and requested
only by clients advertising `home_invite_modal`. The old gate is removed in the
same Flutter release; do **not** deploy the old Races-tab gate/preflight as an
independent feature. The backend returns HTTP 200 with exactly:

```json
{
  "resolved": true,
  "invites": [
    {
      "kind": "TOURNAMENT",
      "id": "tournament-id",
      "name": "Weekend Cup",
      "status": "PENDING",
      "createdAt": "2026-08-12T12:00:00.000Z",
      "matchupDurationDays": 1,
      "buyInAmount": 50,
      "creator": { "id": "user-id", "displayName": "Host" }
    },
    {
      "kind": "RACE",
      "id": "race-id",
      "name": "Lunch Loop",
      "status": "PENDING",
      "createdAt": "2026-08-12T12:00:00.000Z",
      "scheduledStartAt": null,
      "myInviteExpiresAt": "2026-08-13T12:00:00.000Z",
      "maxDurationDays": 3,
      "isTeamRace": false,
      "requiresTeamRaceSupport": false,
      "buyInAmount": 0,
      "creator": { "id": "user-id", "displayName": "Host" }
    }
  ]
}
```

`invites` may be empty. The fields are additive and nullable except `resolved`.
Records must be restricted to the caller's currently live `INVITED`
participant rows; never expose another user's invite, participant list,
profile-photo URL, inventory, standings, or hidden character data. The backend
sorts canonically using §4.2's order; the client repeats a defensive stable
sort only to tolerate intermediary ordering changes.

The backend returns a normal existing auth error for unauthenticated requests.
Unexpected query failure is 500 with `{ "error": "Internal server error" }`;
the client treats it as no presentation. Mutations remain unchanged:

```text
PUT /races/:raceId/respond       { "accept": true|false }
PUT /tournaments/:id/respond     { "accept": true|false }
```

Their current success bodies remain additive/unchanged. Error bodies continue
to use `{error, code?}`. The client must map structured code when present,
otherwise safe generic copy.

### 5.2 Backend compatibility

- Adapt `/races/invite-preflight` for the combined Home feature; do not create
  a competing endpoint or change `GET /races` bytes for old clients. The
  backend may select its legacy bucket response for legacy gate-capability
  callers during the frozen-client compatibility window and the named Home
  response for `home_invite_modal` callers; this is a server serializer branch,
  never a client guess based on missing fields.
- `home_invite_modal` must be advertised by the carrying Flutter build in the
  existing client-feature transport. A server that does not recognize it still
  serves all old routes unchanged.
- Add a default-off `homeInviteModalEnabled` setting to the server's known
  settings. Only when it is enabled *and* the caller advertises
  `home_invite_modal` may the Home serializer/behavior be emitted. Disabled is
  a clean no-modal response; existing inline/detail invitation paths remain.
- New app + old backend: endpoint 404/unsupported/missing `resolved` produces
  no Home modal and never crashes or blocks navigation. Inline Races/detail
  invite flows remain available.
- Old app + new backend: it neither sends the new token nor calls the new
  endpoint; its current `GET /races`, old gate flag behavior, and response
  endpoints retain compatible semantics until the old gate rollout is retired.
- The backend must only emit tournament records when the caller supports the
  tournament renderer. The carrying build does. If a client claims
  `home_invite_modal` without `tournaments`, response must omit tournament
  records rather than expose a UI it cannot render; this is why capability
  checks must be explicit and independently tested.

## 6. Data model and migrations

No schema migration is intended. Existing race/tournament participant status,
invite-expiry, creator, duration, and buy-in fields are read only.

Before implementation, backend work must locate and reuse the canonical
live-race-invite predicate. If no shared predicate exists, add a query-local,
tested predicate that excludes cancelled/settled/non-answerable races and
expired invitations according to existing product policy. Do not backfill or
rewrite participant statuses merely to make the modal disappear. Tournament
query semantics must likewise only select answerable `INVITED` participants.

## 7. Frontend implementation plan

1. Add a small defensive Home-invite DTO/parser (not unchecked `as` casts).
   Require literal `resolved == true`, a nonempty string `id`, supported
   `kind`, and string-safe map keys. Skip an invalid row, never fail all Home
   rendering; unknown/missing fields use generic copy or hide optional facts.
2. Adapt `BackendApiService.fetchRaceInvitePreflight` into a purpose-named
   `fetchHomeInvitePreflight` wrapper over the same lightweight endpoint,
   returning an explicitly unsupported result on 404/absent contract rather
   than calling `fetchRaces`. Remove the old gate-only fallback-to-`fetchRaces`
   behavior together with its callers/tests; do not retain it as a parallel
   ship path.
3. Extract the reusable visual card/overlay from the Races gate only where it
   improves reuse; make the new modal a public, focused widget with injected
   data/callbacks and no API state. `MainShell` owns fetch, sequence, response,
   and route lifetime.
4. Add a shell overlay coordinator with one in-flight guard and a refresh
   generation/session-dismiss guard. Integrate it with `_maybeShowRaceResults`
   so results → quick-create (if chosen) → fresh invite check is serial.
5. Trigger recheck after core-races refresh/resume only when eligible. Use a
   stale-while-revalidate policy: never delay Home paint for a preflight; only
   a fresh supported response can launch a new modal; retain a displayed card
   while its answer is in flight; and drop stale generations/auth contexts.
   After an answer, refresh the preflight and core list/home card so Races and
   Home do not remain stale. Check `mounted`, auth identity/token context, and
   current route before every post-await presentation.
6. Remove the Races gate plumbing described in §4.3 without altering the
   continuing inline strip/detail affordances. Update tests and tutorial/demo
   fixtures that construct `RacesTab` or expect a locked tab.
7. Suppress automatic Home invites in `TutorialRealScreens`, demo hosts, and
   onboarding. Do not depend only on empty fake payloads; pass an explicit
   tutorial/preview suppression input through the shell coordinator.
8. Account for large text, small phones, keyboard/back gesture, dark mode,
   accessibility semantics/focus trapping, Android back, and iOS swipe/back
   behavior. A dismissible modal must return focus to Home and expose clear
   button labels.

## 8. Test plan (tests first)

### Backend integration tests (dedicated test database only)

1. Create race and tournament invitations, request the new endpoint with the
   carrying capability set, and assert its exact public contract, sorting,
   correct inviter/buy-in/duration, and no surplus participant/private fields.
2. Prove empty results are `{resolved:true, invites:[]}`.
3. Prove expired, declined, accepted, withdrawn/cancelled, completed,
   tournament-managed race, and
   otherwise non-answerable invitations are excluded according to the canonical
   predicate. This is the required correction regression test for the current
   preflight effort.
4. Prove team invite rows include only the required safe disclosure facts;
   tournament records obey capability gating; and the legacy
   `/races/invite-preflight` serializer remains contract-compatible for frozen
   gate clients for the agreed window.
5. Race/tournament accept and decline concurrently with a preflight read;
   assert no unauthorized/other-user invite is returned and mutation errors
   retain their established code/body.

### Flutter widget/integration tests

1. Pump the real `MainShell` with fake services: unseen results plus invite
   proves results appears first, no invite is visible underneath, and invite
   appears only after results dismissal.
2. Results → Start Your Next Race → sheet/route completion proves the invite
   is deferred then freshly rechecked, not stacked or lost.
3. Single race, single tournament, active/underway race, and mixed multi-invite queues prove order,
   data facts, accept/decline call, disabled duplicate taps, fresh re-read, and
   close on empty.
4. X dismissal leaves Home usable, makes no mutation, suppresses the inline
   card only while the modal is visible, restores the eligible inline fallback
   after dismissal, and permits a later launch/resume recheck.
5. Offline/500/404/unsupported/missing `resolved`/malformed row shows no modal,
   does not crash, and never blocks Home or Races.
   Explicitly cover SWR: cached/previous data never launches a new invitation,
   a slow older response cannot overwrite a newer empty/answered response, and
   a displayed card remains stable only while its own action is pending.
6. `ALREADY_RESPONDED`, `NOT_INVITED`, and missing race reconciliation refresh;
   `TEAM_FULL`, insufficient coins, and other action failures keep the current
   card with retry/dismiss and do not optimistically remove it.
7. Races-tab tests prove a tab tap, swipe, pull-to-refresh, and initial fetch
   error all leave the list/navigation usable; no gate keys/classes/flag branch
   remain. Existing inline invite and deep-link detail tests remain intact.
8. Tutorial/onboarding/demo tests prove automatic modal suppression even when
   fake data contains an invite. Run the Home mirror and Races tutorial preview.

Run `flutter analyze` clean and the focused new/failing suites first, then the
full `flutter test`; account for iOS and Android together. Backend integration
tests must confirm `DATABASE_URL` is a test database and use `npm run
test:integration`, never bare `npm test`.

## 9. Rollout and observability

1. Land and verify the backend adaptation and capability serializer first, but
   do not expose/market it as a standalone Races-tab preflight/gate release.
   Verify staging with classic/team, live/expired, tournament-managed-race,
   tournament, paid, SWR, and concurrent-response cases.
2. Ship the Flutter removal of the gate and Home presentation for iOS and
   Android together. A 404 from an older backend is a safe no-modal
   degradation, so there is no client-side blocking flag required for basic
   safety.
3. Retire the old Races blocking flag/legacy endpoint serializer only after confirming old app
   versions are still safe: the backend must continue serving their supported
   old route/flag semantics for the agreed compatibility window. Do not remove
   an old server contract merely because the new app no longer references it.
4. Instrument only aggregate presentation/action/error events with surface and
   invite kind; never log invite names, IDs, creator names, balances, or tokens.
   Proposed names: `home_invite_check_resolved`, `home_invite_modal_shown`,
   `home_invite_answered`, `home_invite_dismissed`, and
   `home_invite_action_failed`.

## 10. Acceptance criteria / definition of done

- A supported, signed-in user with a live outstanding invite sees a Home modal
  after—not over—any unseen results popup, one invite at a time.
- Accept/decline only proceeds through existing authoritative endpoints and a
  fresh server read; stale/concurrent/error conditions neither lie nor trap the
  user.
- The modal offers Accept, Decline, and X. X performs no mutation, ends the
  current sequence, restores the eligible inline Home fallback, and a later
  launch/resume may re-present a still-live invite. Failed/unsupported
  preflight leaves Home and Races usable.
- An answerable invite to an ACTIVE race is shown with an UNDERWAY label.
- Races-tab blocking mechanics are removed, while current inline and detail
  response paths remain functional.
- New/old app-backend pairings degrade safely as §5.2 states. All server fields
  are parsed defensively; no absent/null/malformed server field crashes UI.
- Tests are written first and pass, `flutter analyze` is clean, iOS and Android
  are accounted for, required review and manual placement validation have run,
  and no production migration/flag/deploy occurs without explicit approval.

## 11. Manual UI-placement test plan

1. **Home with results and invite:** finish an accepted race and seed one race
   plus one tournament invite; cold-launch to Home. Verify the results overlay
   is the only overlay, dismiss it, then verify the tournament card appears
   before the race card with no page jump or visible Races-tab gate.
2. **Home only:** use a user with a paid tournament invite, a team-race invite,
   and no result. Verify safe labels, buy-in, duration, team fact, focus, large
   text wrapping, and one card at a time on a smallest supported phone in light
   and dark modes.
3. **Dismiss/re-enter:** tap the visible X. Verify Home remains interactive,
   no accept/decline request is made, and the eligible inline pending-invite
   fallback is visible only after the modal closes—not behind it. Relaunch or
   resume and verify a fresh check may present the still-live invite.
4. **Answer/failure:** accept/decline each type; induce insufficient coins,
   full team, and network error. Verify button locking, inline error/retry,
   no stale card removal, and no modal stack after recovery.
5. **Races surface:** while an invite exists, tap and swipe to Races, pull to
   refresh with network disabled, and open an invite directly. Verify no
   opaque lock/checker screen, normal navigation, and existing rows/detail
   affordances still work.
6. **Mirrors:** replay onboarding/tutorial and DemoRaceHost/TutorialRealScreens
   with invite-like fixtures. Verify no production Home modal appears and all
   existing spotlight anchors/layout remain in position.
7. **Platforms:** repeat items 1–5 once on iOS and once on Android, including
   back behavior and accessibility screen-reader traversal.

## 12. Unresolved questions for product/architecture review

1. **Resolved (2026-08-12):** The existing inline Home pending-invite card
   remains as a fallback. It is suppressed while the modal is visible, then may
   render after X dismissal under its ordinary Home-card conditions.
2. **Resolved (2026-08-12):** X makes no mutation, ends the current modal
   sequence, and permits a fresh later launch/resume recheck while the invite
   remains valid.
3. **Resolved (2026-08-12):** An outstanding server-answerable invitation may
   coexist with an ACTIVE race. The Home modal surfaces it and labels its race
   **UNDERWAY**.
4. What exact compatibility-retirement window applies to
   `/races/invite-preflight` and `racesInviteDecisionGateEnabled` for frozen
   builds? This spec requires preserving them until explicitly approved, but
   does not set a date.

## 13. Revision log

- **Initial draft (2026-08-12):** traced `MainShell` results presentation,
  existing Races gate, Home pending card, `BackendApiService`, and backend
  preflight/query/response routes. Defined shell-owned results-first sequencing
  and preserved non-blocking Races behavior.
- **Gap pass 1 (2026-08-12):** added the explicit no-stack relationship with
  payout-double and quick-create, route/auth/generation guards, dismiss
  semantics, and continued inline/deep-link response paths.
- **Scope correction (2026-08-12):** superseded the uncommitted standalone
  Races-tab gate/preflight rollout. The existing lightweight endpoint is now
  adapted solely for the combined Home modal release; added team disclosure,
  tournament-managed-race filtering, real SWR/fallback coverage, and explicit
  gate/nav-lock removal.
- **Product decisions folded in (2026-08-12):** locked Accept/Decline/X; X
  retains the Home inline pending-invite card as a post-dismiss fallback while
  suppressing it during the modal, and
  requires answerable active-race invitations to show as UNDERWAY.
- **Gap pass 2 (2026-08-12):** added the preflight-contract correction,
  expiry/capability privacy requirements, old-client coexistence, malformed
  response behavior, test-first coverage, mirrors, and unresolved decisions
  rather than silently choosing product policy.
- **Architecture lock (2026-08-12):** canonicalized expiry to `now <
  inviteExpiresAt` with an `INVITE_EXPIRED` mutation result at/after expiry,
  and made the capability serializer opt-in behind default-off
  `homeInviteModalEnabled`.
