# Race/tournament preview-before-joining — spec

Streamlined workflow (matching the prior batch): single spec → architect
review until approved → minimal targeted tests → implementation → final
code review. Deploy order: backend first, staging then prod; frontend ships
in the next app build.

**Scope, confirmed with user:** previews work for **public races/tournaments
and races/tournaments the user is invited to** — not arbitrary private races
by ID. A private race with no invite stays fully blocked (403), unchanged.
Additionally (architect-required correction): **tournament matchup races**
(`race.tournamentId != null`) are excluded from the new public-preview
carve-out — a legitimate viewer of those is already served by the existing
tournament-spectate path, and letting any non-bracket user preview one would
let them hit a JOIN CTA that 400s (`TOURNAMENT_RACE_LOCKED`).

## Problem

Confirmed by research across four screens:

- **`races_tab.dart`** (personal races list) and **`tournament_detail_screen.dart`**
  (for any viewer) already work correctly today.
- **`home_tab.dart`**'s suggested-race carousel, next-race row, friend-racing
  card, and public-race row, and **`public_races_screen.dart`**'s race and
  tournament cards, all trigger **join directly on tap** with no "view
  first" path for a not-yet-joined race/tournament.
- **`race_detail_screen.dart` is backend-blocked for non-participants on
  THREE separate endpoints, not one** (architect finding — the original
  draft only patched one and the feature would have been dead on arrival):
  - `GET /races/:raceId/bootstrap` → `loadBootstrapAccess`
    (`stepv2-backend/src/modules/races/routes.js:444`) — called FIRST by
    `race_detail_screen.dart:911`; 403s before `getRaceDetails` is ever
    reached.
  - `GET /races/:raceId` → `getRaceDetails.js:125-138`.
  - `GET /races/:raceId/progress` → `getRaceProgress.js:1439-1451` — polled
    every 30s while the screen is open; for an ACTIVE race, standings render
    from this response, so without fixing it the preview has no live board.
  All three currently 403 any non-participant, with the same one carve-out
  (ACCEPTED tournament-bracket spectating).
- The full race-detail payload's `participants[]` array includes
  **`buyInAmount`, `buyInStatus`, `payoutCoins`** per participant — financial
  data the existing public-races listing never exposes. Lifting the 403
  without redacting these would be a new leak.
- **`race_detail_screen.dart` already has a non-participant read-only mode**
  (`_isSpectator`, line 5336, driving `_buildSpectatorBanner()`) — it's how
  ACCEPTED tournament-bracket spectators render today. The architect flagged
  that this spec must **extend** that existing mode with a JOIN CTA rather
  than invent a second, parallel "preview mode" — two ways to do the same
  thing is exactly what this codebase avoids.

## Backend change

**Gate the entire feature behind a capability token — architect-required.**
Add a `race_preview` token to the client-features header
(`lib/services/backend_api_service.dart`'s `clientFeaturesHeader` — **note
it's a ternary with the token list duplicated in both branches; add the
token to both**). Only requests advertising this token get the new
carve-out; every other caller (old app builds, or the new build's own
requests that don't set it — there shouldn't be any) gets the byte-identical
403 they get today. This is the standard mechanism this endpoint already
uses for other capabilities (`supportsBuckets`, `race_leave`,
`team_races` — see `routes.js:1139-1144`) and makes the entire "will an old
client render a 200 sensibly" question moot: old clients never receive one.

**A server-side kill switch is required in addition to the token — round-3
architect-required fix.** A client capability token is a compat gate, not an
off switch: once a build advertising `race_preview` ships to the App Store,
that binary is frozen and there is no way to disable the feature for it
short of a new release. That matters concretely here because (a) the spec's
own cross-timezone note above means a meaningful share of preview
`/progress` hits will fall through to the `loadPersistedState` read path —
a full read of participants + active effects on the system's most expensive
endpoint — and (b) if the financial redaction is ever found incomplete
post-ship, the only remediation without a flag would be an App Store
submission. Add `racePreviewEnabled` to `KNOWN_FLAGS`
(`src/shared/config/appSettings.js:18`), default `false`, following this
repo's standard flag pattern (e.g. `standingsCacheEnabled()` in the progress
path) — cheap to read per request, appSettings already caches it. Ship with
the flag off, flip it on after the backend deploy is verified on staging
then prod.

**One shared predicate, used by all three endpoints — architect-required.**
Add `canReadRacePreview({ race, myParticipant, clientFeatures })` (e.g. in
`src/modules/races/services/`), returning true only when all of the
following hold. **Order the checks cheapest-first** — `!myParticipant`,
`race.isPublic`, `race.tournamentId == null`, THEN the flag read last —
so the `appSettings` lookup is skipped entirely on the overwhelmingly common
case (an actual participant calling this endpoint):
- `!myParticipant` (a true non-participant — a `DECLINED` row still means
  "has a participant row," so a decliner still gets the real 403, exactly as
  today — declining revokes access, unchanged), AND
- `race.isPublic === true`, AND
- `race.tournamentId == null` (excludes tournament matchups — those viewers
  are served by the existing, separate `canSpectate` path), AND
- `clientFeatures` includes `race_preview`, AND
- `racePreviewEnabled` flag is on.

Wire this into all three gates:
1. `getRaceDetails.js:125-138` — add as a second `||` alongside the existing
   `canSpectate` carve-out.
2. `getRaceProgress.js:1439-1451` — identical carve-out, same predicate.
3. `loadBootstrapAccess` (`routes.js:444` area) — same carve-out. **Verified
   during spec review: its underlying query does not yet select `isPublic`**
   — `src/modules/races/models/race.js:205-229`
   (`findBootstrapAccessContext`) selects `tournamentId` but not `isPublic`;
   add `isPublic` to that select. (`findDetailsCore`, line 255, already
   includes both via `include`, so `getRaceDetails.js` needs no change
   here.)

**Where the token → predicate decision is computed.** `getRaceDetails.js`'s
query function receives no `clientFeatures` today (its own header comment
already warns against exceeding its current 9 positional params). Compute
the `race_preview` token check in `routes.js`, where `req.clientFeatures`
lives, and pass the resulting boolean through the **trailing options
object** each of the three call sites already accepts (e.g.
`{ pagination, previewViewer }`) — do not add a new positional parameter or
thread `clientFeatures` itself into the query layer.

**Redaction — `getRaceDetails.js`'s `participants[]` map (~lines 250-270):**
when serving via the new preview carve-out, set `buyInAmount`,
`buyInStatus`, and `payoutCoins` to `null` for every row (there's no "my own
row" to exempt — a preview viewer has none). All other race-level fields
were audited (architect) and are clean: `creator`/`winner` are already
PII-minimal `{id, displayName, profilePhotoUrl}` selects; `potCoins`/
`heldPotCoins`/`prizePool`/`payoutTiers`/`finishReward` are aggregates
already shown on the public listing card; `myStatus`/`myTeam`/
`myTotalSteps`/`leaveAction` already null-degrade safely (this is the exact
mechanism the tournament-spectate carve-out already relies on in
production).

**Two explicit, stated decisions (architect-required — these must be
decisions, not oversights):**
- `participantUserIds` (the paged-response id-roster field,
  `getRaceDetails.js:325`) is **kept as-is** for preview viewers — it's a
  bare id list, already present in full within `participants[]`, so it adds
  no new exposure.
- The `/progress` payload requires no financial redaction (audited: no
  `buyIn*`/`payoutCoins`/pot fields there), but it does expose every
  participant's **active effects and bonus steps** to a non-participant.
  Accepted as part of "preview the race board" — not redacted.

**No new poller — architect-required, cost concern.** `/races/:id/progress`
is the most expensive read in the system (the entire C3 shared-standings
cache exists for it, protecting the hottest keys — 477-participant seeded
Daily/Weekly races). Preview mode must do a **single fetch plus
pull-to-refresh only** — it must never call `_startPolling()`. Opening this
endpoint to every non-participant browsing the public list, on a 30s poll,
would add unbounded load to exactly the races that can least afford it.

**A preview `/progress` fetch must also be strictly read-only — second
architect-required fix, this is not just about request volume.** As written,
a single non-participant hit to `getRaceProgress.js` can still (a) win
`snapshotStore.withRebuildLock` and run a full scoring replay for a
477-participant seeded race (lines 1531-1610), (b) fire
`enqueueRaceResolutionFn({ reason: "DISPLAY_REFRESH", priority: "IMMEDIATE" })`
(line 1618), and (c) on the flag-off/`REDIS_URL`-unset path, run
`computeSharedState({ persist: true })` (line 1511) — which writes back
`totalSteps`, expires effects, and processes high-multiplier claims. That
means a stranger's preview tap could mutate `race_participants`/effect rows
for a race they have no relationship to. Fix: thread a `previewViewer: true`
option into the progress query, computed and passed from `routes.js` (see
below) through the **trailing options object** already used here
(`{ pagination, previewViewer }` — not a new positional param;
`getRaceDetails`'s own header comment already warns against exceeding its
current 9 positional params). When `previewViewer` is true: never take
`withRebuildLock`, never call with `persist: true`, never call
`enqueueRaceResolutionFn` — serve whatever cached snapshot is available
regardless of staleness, and if there is none, fall back to
`loadPersistedState({ race, raceId, scoringTimeZone })` (read-only) instead
of triggering a rebuild. Add a backend integration test asserting a preview
`/progress` request performs **zero** `race_participants` writes and
enqueues no resolution job.

**Known, accepted degradation: cross-timezone preview snapshot misses.**
User-created public races have `timezone = NULL` and score in the
*requester's own* timezone (`getRaceProgress.js:1519-1522`), so a preview
viewer in a different timezone than the race's usual viewers will often miss
the cached C3 snapshot and fall through to the read-only
`loadPersistedState` path above. This is the correct, intended behavior —
do **not** "fix" this later by adding timezone to the C3 cache key, which
would make the cache's invalidation set unenumerable (see
`cacheKeys.js:195-211`). Stated here so it isn't rediscovered as a bug.

**Compat:** Purely additive, and now capability-gated — old app builds never
see the new carve-out fire (they don't send the token), so their existing
403/dead-end behavior is provably unchanged, not just "probably fine."

## Frontend change — extend `_isSpectator`, don't add a parallel mode

`race_detail_screen.dart` already has `_isSpectator` (line 5336) driving
`_buildSpectatorBanner()` — this is the correct hook to extend, not a new
state alongside it. Required changes, all in this file:

1. **JOIN CTA on the spectator banner — discriminator corrected
   (architect-required, round 2).** `myStatus == null` is **not** a valid
   way to distinguish a public-preview viewer from a tournament-bracket
   spectator — `getRaceDetails.js:246` returns `myParticipant?.status ??
   null` for *both* cases, so gating on `myStatus == null` alone would
   render a JOIN CTA for bracket spectators too, which then 400s
   (`TOURNAMENT_RACE_LOCKED`) — exactly the case this spec's scope section
   says must be excluded. Use the same shape the backend predicate and this
   file's other guards already use: `race['tournamentId'] == null &&
   race['isPublic'] == true` (plus a joinable `status`), mirroring
   `_canShowCreatorOptions` (line 6526) and `_stampedLeaveAction`
   (line 6501)'s existing pattern in this same file — not a `myStatus`
   check. When `_isSpectator` is true AND that condition holds, add a
   prominent JOIN CTA to the existing spectator banner UI (reuse the
   existing join flow/dialogs — buy-in confirm, team-side picker for team
   races — rather than a new one). Tournament-bracket spectators
   (`tournamentId != null`) get no JOIN CTA — they can't join a matchup
   they're not in. **Required test:** tournament-matchup fixture with
   `myStatus: null` → spectator banner renders, JOIN CTA does **not**.
2. **Suppress chat/feed calls for a non-participant.** `_ensureFeedInitialized()`
   (called unconditionally for ACTIVE at line ~982 and COMPLETED at ~987)
   and `_ensureChatInitialized()` (via `_onTabChanged`, line ~874) must not
   fire for a non-participant — those endpoints still 403 (out of scope,
   below) and would otherwise surface a spurious error. Render the chat/
   activity tabs in a locked "join to see this" state instead of calling
   them.
3. **No polling in preview.** Per the backend section, preview mode does a
   single fetch and supports pull-to-refresh; `_startPolling()` must not be
   invoked for a non-participant viewer.
4. **Hide the share button and kebab.** The share button
   (`~line 3530`, calls `createRaceShareLink`, which still 403s
   non-participants — out of scope, unchanged) and `_hasRaceOptions()`
   -gated kebab (nothing to leave) must both be hidden for a non
   -participant viewer.
5. **Team races render read-only in preview** — team split/rosters visible,
   no team-side picker inside the board; team selection happens as part of
   the JOIN flow (existing `showTeamSidePicker`), not before it. The team
   -lobby block (`~lines 4286-4537`) needs an explicit read-only branch.
6. **Audit, don't just trust, the existing `myStatus`-reading sites** at
   (approximately) lines 1454, 3690, 4286, 4414-4482, 6411, 6491, 6502,
   6817, 7062 — most already use `as String? ?? ''` and fail safe, but each
   must be checked against preview mode specifically during implementation,
   not assumed clean by pattern-matching.
7. **State the progress-poll-403 edge case explicitly:** after the backend
   fix, a preview viewer's (single, non-polled) progress fetch should not
   403. If it somehow does (e.g. a race transitions from public to private
   mid-view), fall back to the existing `_enterNotAParticipant()` path —
   same as today's genuine-403 handling, no new state needed for this edge.

## Frontend change — wire "tap card to preview" at every join-only entry point

For each entry point, the **card body** navigates to preview; the
**existing JOIN button/pill** keeps its current direct-join behavior
unchanged. Corrected/expanded per architect review:

1. **`home_tab.dart` suggested-race carousel (`_HomeSuggestionTicket`,
   line 1984).** Add a tap handler navigating to `RaceDetailScreen`/
   `TournamentDetailScreen` via the same navigation `main_shell.dart`
   already uses post-join. **Also update its `Semantics(button: true,
   label: '…, Join {name}')` (lines ~2070-2073)** — with the card body now
   tappable-to-preview, that label/role is no longer accurate; update the
   semantics to reflect a card that both previews (default tap) and joins
   (explicit button).
2. **`home_tab.dart`'s "next race" open-races row (`_NextRaceSection`,
   lines 1739-1850).** Add a tap handler on the row navigating to preview;
   the JOIN icon button stays.
3. **`home_tab.dart`'s friend-racing card (lines 734-756) — SCOPE
   CORRECTION.** This card renders for *any* friend race, not only public
   ones. **Gate the new card-tap-to-preview on `isPublicJoinable == true`
   only** — for a private friend race (`primaryLabel: 'OPEN'` →
   `onOpenRacesTab`), do not add a preview tap target, since that would
   route to a private race the viewer has no access to (still a 403 dead
   -end, since private races are out of this spec's scope).
4. **`home_tab.dart`'s public-race row (`RaceCardState.publicRace`, lines
   772-789) — MISSING FROM ORIGINAL DRAFT, added per architect finding.**
   `primaryLabel: 'JOIN'` → `onJoinRaceFromCard`, currently join-only. Add
   the same card-tap-to-preview treatment as the other public entry points.
5. **`public_races_screen.dart`'s race cards** (`_buildRaceCard`, line
   948). Add a tap handler on the card body (not the JOIN button) pushing
   `RaceDetailScreen`. JOIN button unchanged.
6. **`public_races_screen.dart`'s tournament cards — REQUIRES A NEW WIDGET
   PARAM, not just a call-site change (architect finding).**
   `TournamentGameCard` (`lib/widgets/tournament_game_card.dart:27,49`)
   currently exposes only `onPressed` — there is no existing card-body tap
   target to redirect. Add a new `onCardTap` parameter to
   `TournamentGameCard` (contained change: only 2 call sites,
   `public_races_screen.dart:880,927`, both in
   `_buildFeaturedTournamentCard`/`_buildUserTournamentCard`). Wire
   `onCardTap` to `_openTournament(id)` (same navigation already used for
   the joined branch); the JOIN button keeps calling `_joinTournament`
   directly. State explicitly what the card body does when the tournament
   is `FULL` or the viewer is `IN A BRACKET` already (see item 7 below).
7. **Disabled-button fallthrough — state as an intended behavior, add a
   test (architect suggestion, adopted as a stated rule).** When a card's
   JOIN button is disabled (`JOINING...`, `FULL`, `IN A BRACKET`), Flutter's
   gesture arena means the tap falls through to the card body and navigates
   to preview instead of doing nothing. This is desirable — a full/locked
   race should still be viewable — and must be covered by a test rather
   than left as an accidental discovery.

None of these changes touch `races_tab.dart` or `tournament_detail_screen.dart`
(already correct).

## Team races

No separate work item — team races render through `race_detail_screen.dart`
and `getRaceDetails.js`/`getRaceProgress.js` exactly like individual races.
Covered by the "Frontend change — extend `_isSpectator`" section, point 5.

## Mirror surfaces (architect-required — not in the original draft)

This spec touches `race_detail_screen.dart` and `home_tab.dart`, both
re-rendered by the tutorial system:

- `lib/tutorial/tutorial_real_screens.dart:97` renders the real `HomeTab`
  but passes no `onOpenRace`-style callback for the new tap handlers — every
  new card tap handler must be written null-safely (`?.call(...)`) so the
  tutorial's fake home doesn't crash or, worse, fire a live navigation out
  of the tutorial. `HomeTab` already accepts an explicit
  `isTutorialPreview: true` flag (`tutorial_real_screens.dart:97-98`) —
  prefer gating the new tap handlers on that flag directly rather than
  relying solely on the callback being null, since an explicit flag is
  safer than an absence-based check.
- `tutorial_real_screens.dart:138` feeds the real `RaceDetailScreen` from
  `demo_race_api_service.dart` — any new API method this spec's frontend
  code calls needs a guard test asserting the demo service either overrides
  it or the screen never calls it in demo context.
- `lib/tutorial/tutorial_preview_data.dart` fixtures currently have **no
  guard test** — a preview-mode branch that self-fetches (e.g. a
  pull-to-refresh) inside the tutorial could become a **live production
  request** fired from a demo screen. Add one.
- `demo_race_engine.dart`'s fabricated payloads must keep `myStatus`
  non-null, so the tutorial/demo race never itself enters preview mode.

## Test plan

**Backend integration tests** (new, per corrected scope):
1. Non-participant + `race_preview` token, public non-tournament race, no
   prior participant row → 200 on all three endpoints (`GET /races/:id`,
   `/bootstrap`, `/progress`); financial fields null in `participants[]`;
   `myStatus: null`.
2. Same request WITHOUT the `race_preview` token → still 403 on all three
   (capability-gate regression guard — the core compat guarantee).
3. Non-participant + token, **private** race → still 403 on all three
   (unchanged — regression guard).
4. Non-participant + token, **tournament matchup race** (`tournamentId !=
   null`) → still 403 via this new path (excluded from the carve-out;
   legitimate spectators still work via the existing, separate
   `canSpectate` path — regression guard on that path too).
5. `DECLINED` participant on a public race + token → still 403 (declining
   still revokes access — regression guard on the exact predicate).
6. INVITED participant, public or private, with or without the token → 200
   with real `myStatus: 'INVITED'`, unchanged, no redaction (already-working
   path, regression guard).
7. Existing tournament-spectate 200 case (`canSpectate`) → unaffected, no
   financial redaction applied there (regression guard — this is a
   different, already-shipped branch from the new one).
8. `racePreviewEnabled` flag OFF + token present + public race → still the
   byte-identical 403 on all three endpoints (round-3 architect-required —
   the kill switch must actually gate, not just exist).
9. Preview `/progress` request → zero `race_participants` writes, no
   enqueued resolution job, AND (per architect suggestion) the
   `snapshotStore` request-replay counter (`requestReplays`) is unchanged —
   pins the "never takes `withRebuildLock`" half of the read-only contract
   directly rather than only by absence of side effects. Run this test in
   **both** configurations (test Redis `db15` and `REDIS_URL` unset), since
   the unset path is exactly the `computeSharedState({ persist: true })`
   branch `previewViewer` must divert.
10. Preview fixture with **zero participants** (`participants: []`,
    freshly seeded public race with no joiners yet) → spectator banner +
    JOIN CTA render correctly, and `participantsPagination` is present on
    all three preview responses (per architect suggestion —
    `_isSpectator`'s unpaged branch returns `false` on an empty list, so the
    paged `myStatus == null` branch must reliably win for this to work; a
    missing `participantsPagination` key would silently regress a fresh
    public race back to participant-chrome rendering with no JOIN CTA).

**Frontend tests:**
1. Widget test: pump `RaceDetailScreen` with a fixture 200 response,
   `myStatus: null`, `isPublic: true`, `tournamentId: null` → race name/
   target/prize/standings render, no POWERUPS section, chat/activity tabs
   locked (not fetched), no kebab, no share button, JOIN CTA present on the
   spectator banner, no crash/"null" literal from redacted financial
   fields.
2. Widget test: fake API asserts **zero** calls to chat/feed/progress-poll
   endpoints from a preview-mode pump (architect-required — proves the
   suppression, not just the UI state).
3. Widget test: 403 (unchanged path, private race or no token) → existing
   `_buildNotAParticipantState()` still renders; existing test(s) re
   -pointed only if the state-detection conditional itself changed under
   them, not the rendered content.
4. Per entry point (home suggestion card, next-race row, public-race row,
   gated friend-racing card, public_races_screen race card,
   public_races_screen tournament card via new `onCardTap`): tapping the
   card body navigates to preview without a join call; tapping the existing
   JOIN affordance still joins directly (regression guard); tapping a
   *disabled* JOIN affordance falls through to preview navigation
   (architect-required new case).
5. Friend-racing card: private (non-public-joinable) friend race → card tap
   does NOT navigate to a preview it can't access (scope-correction guard).
6. Team race preview: fixture with `isTeamRace: true` renders team split
   read-only, no team-side picker inside the board.
7. Tutorial guard tests per "Mirror surfaces" above.

Never weaken or delete an existing assertion; if any existing test currently
asserts a home/public-races card triggers join on any tap where the intent
was specifically "the whole card joins" (not incidental JOIN-button
coverage), surface it before changing rather than silently rewriting.

## Rollout note

Three explicit steps, in order (not two — the flag makes this a three-stage
rollout, not a simple backend-then-frontend one):
1. Deploy backend to staging then prod with `racePreviewEnabled = false`.
   Production is never at risk of a version mismatch at this stage.
2. Ship the app build advertising the `race_preview` token through normal
   App Store phased rollout. During this gap, the flag being off means the
   token has no observable effect yet — a frontend build that already sends
   it against a backend where the flag is still off routes card taps into
   the existing `_enterNotAParticipantState()` (403), same as before this
   spec. **Expected, not a bug — tell testers explicitly** so it isn't
   reported as a regression during this window (this applies on
   staging/TestFlight too, ahead of the flag flip there).
3. Only after the carrying build has substantially rolled out, flip
   `racePreviewEnabled` to `true`.

## Acceptance criteria

- [ ] A non-participant, on a build advertising the `race_preview`
      capability token, can tap through to view a public, non-tournament
      -matchup race/team race, or a public tournament (or one they're
      invited to), from every listed entry point, without joining first —
      via a single fetch, no polling.
- [ ] Requests without the `race_preview` token get the exact same 403 as
      today on all three endpoints — old app builds are provably unaffected.
- [ ] `racePreviewEnabled` defaults off; the feature is fully inert until
      explicitly flipped on after staging/prod verification.
- [ ] A preview `/progress` request never takes the rebuild lock, never
      persists shared state, and never enqueues a resolution job.
- [ ] Private races/tournaments and tournament-matchup races the user has no
      connection to remain fully blocked (403) — no new access beyond the
      stated scope.
- [ ] A preview viewer never sees another participant's `buyInAmount`,
      `buyInStatus`, or `payoutCoins`.
- [ ] A preview viewer never triggers a chat, activity-feed, share-link, or
      progress-polling request.
- [ ] JOIN buttons/pills at every entry point still join directly, exactly
      as before; disabled JOIN buttons fall through to preview navigation.
- [ ] `races_tab.dart` and `tournament_detail_screen.dart` behavior is
      unchanged.
- [ ] Preview mode reuses `_isSpectator`/`_buildSpectatorBanner()` — no
      parallel "preview state" was introduced.
- [ ] Tutorial/demo surfaces (`tutorial_real_screens.dart`,
      `tutorial_preview_data.dart`, `demo_race_engine.dart`) are unaffected
      and guarded by tests.
- [ ] All new/changed tests pass; no existing assertion weakened.
- [ ] Backend changes deployed to staging then prod; frontend ships in the
      next app build.
- [ ] `ui-test-planner` manual checklist obtained before this is presented
      as done.

## Revision log

- Initial draft, scoped per user's explicit choice (public + invited races
  only) and streamlined-workflow choice.
- Architect review (REVISE, 8 required items): fixed the feature being dead
  on arrival (only 1 of 3 access-gating endpoints was patched); added a
  `race_preview` capability-token gate replacing the "verify old client
  degrades gracefully" approach (which was under-scoped — `_isSpectator`
  exists today and would silently drop the JOIN CTA for old builds without
  a token gate); excluded tournament-matchup races from the public-preview
  predicate (JOIN CTA would otherwise 400); consolidated preview mode into
  the existing `_isSpectator` mechanism instead of a new parallel state;
  added explicit decisions on `participantUserIds` and `/progress`'s
  effects/bonus-steps exposure; added the no-new-poller requirement (cost/
  cache-pressure concern on the hottest race keys); corrected the
  entry-point list (gated the friend-racing card on `isPublicJoinable`,
  added the missing `RaceCardState.publicRace` row, added the required
  `onCardTap` param to `TournamentGameCard`); added the mirror-surfaces
  section for tutorial/demo screens; added the disabled-button-fallthrough
  rule and its test.
- Second architect re-review (REVISE, 2 remaining required items): made
  preview `/progress` reads strictly read-only (`previewViewer` option —
  never `withRebuildLock`, never `persist: true`, never
  `enqueueRaceResolutionFn`; falls back to read-only `loadPersistedState`),
  since the "no new poller" fix alone still let a single preview tap trigger
  a full rebuild/mutation/resolution-enqueue for a race the viewer has no
  relationship to; corrected the frontend JOIN-CTA discriminator from
  `myStatus == null` (which also matches tournament-bracket spectators,
  wrongly) to `tournamentId == null && isPublic == true`, mirroring the
  backend predicate and this file's own existing guard pattern; confirmed
  and fixed `findBootstrapAccessContext` not selecting `isPublic`;
  clarified the token-check computation lives in `routes.js` and passes
  through the existing trailing options object, not a new positional param;
  adopted the `isTutorialPreview` explicit-flag gating suggestion and the
  cross-timezone-snapshot-miss and staging-deploy-lag notes.
- Third architect re-review (REVISE, 1 remaining required item): added a
  server-side `racePreviewEnabled` kill switch (default off) as a fourth
  conjunct in `canReadRacePreview`, since the client capability token alone
  is a compat gate, not an off switch, and this feature's expensive-read
  fallback path plus financial-redaction risk both warrant a way to disable
  it without an App Store release; added the flag-off regression test and
  the suggested zero-participant-fixture and snapshot-counter test cases.
