# Batch 2026-08-15 — spec

Streamlined workflow per user instruction: single spec → architect review →
minimal targeted tests → implementation → final code review → backend deploy
to staging + prod. No multi-round spec review loop.

Two items from the original ask are **dropped** — already implemented in the
current codebase (confirmed with user):
- Chat/activity loading indicator on race detail (already uses the app's
  standard `LoadingSkeleton` pattern, `race_detail_screen.dart:6904-6912,
  6968-6976`).
- "Waiting" → "Pending" filter label (races_tab.dart already labels this
  `'PENDING'`, `races_tab.dart:100`).

## 1. Night mode: fixed 10pm–7am US-Eastern window

**Problem:** `lib/theme_controller.dart` currently triggers automatic dark
mode using the **device's own local hour** (`nightStartHour = 21`,
`dayStartHour = 7`, `theme_controller.dart:24-25,45-54`). A phone correctly
reporting its own local time zone still means a west-coast user flips to dark
mode at their own local 9pm — three hours later (real-world) than an
east-coast user. The ask is a single fixed real-world trigger point (10pm
Eastern) shared by all users, not "9pm wherever you are."

**Change:**
- No new pub dependency. US-Eastern DST transitions are fixed since the
  Energy Policy Act of 2005 (effective 2007) and stable: 2nd Sunday in March
  at 02:00 EST local (**07:00 UTC**) → jumps to 03:00 EDT (UTC-4); 1st Sunday
  in November at 02:00 EDT local (**06:00 UTC**) → falls back to 01:00 EST
  (UTC-5). Note the two transition UTC-hours differ (07:00 vs 06:00) — don't
  reuse one constant for both. Implement a small (~15 line) pure-Dart helper
  that computes the current America/New_York offset from a UTC instant using
  these two fixed transition rules, rather than bundling the `timezone`
  package's IANA database for one fixed-rule zone. Keeps the "device-only,
  never depends on the API" invariant (`theme_controller.dart:11`) trivially
  true with no init call and no data-load failure mode. Add a one-line
  comment noting this hardcodes current US federal DST law and would need a
  new binary if that law changes (e.g. a "permanent DST" act) — an accepted
  tradeoff given the app is rebuilt regularly anyway.
- `_clock` (`AppClock` typedef) keeps its existing signature — it still
  returns a `DateTime`. Inside `resolve()`, treat that as a UTC instant
  (`_clock().toUtc()`), compute the Eastern offset via the new helper, and
  derive `easternHour` from it. Tests feed UTC instants directly; no seam
  change needed for the timer.
- Change `nightStartHour` from `21` to `22` (10pm) per the ask; keep
  `dayStartHour = 7`.
- **`_scheduleBoundary()` (`theme_controller.dart:78-95`) must move to the
  same Eastern-time basis, not just `resolve()`.** It currently computes the
  next flip as `DateTime(now.year, now.month, now.day, nightStartHour)` in
  device-local time — if only `resolve()` changes, a device left open still
  flips at 22:00/07:00 *device-local*, reintroducing the exact bug for anyone
  who doesn't background/foreground the app across the boundary. Compute the
  next boundary in Eastern wall-clock time using the same helper, then
  convert that instant back to whatever `Timer` duration is needed from
  "now." This applies to **both** candidates the function builds today: the
  same-day 07:00/22:00 candidates and the next-day rollover candidate
  (currently `DateTime(now.year, now.month, now.day + 1, dayStartHour)`,
  line 93) — the next-day one is the candidate that actually spans a DST
  transition, so it needs the same "convert using the offset at that
  candidate instant" treatment, not just the same-day ones.
- Fix the stale Settings copy at `settings_screen.dart:842` ("Automatic uses
  dark mode from 7 PM to 7 AM") to say "10 PM to 7 AM Eastern," and the class
  doc comment at `theme_controller.dart:10` ("the local 9 PM–7 AM schedule"),
  which would otherwise be wrong on both the hour and the basis (local vs.
  Eastern) after this change.
- Manual override (`AppThemePreference.light`/`.dark`) is unaffected — it
  already short-circuits `resolve()` before the clock check.

**Compat:** Client-only change, no backend/API involvement. Old app builds
keep their existing (device-local 9pm) behavior until they update — expected
and fine per CLAUDE.md's "frozen binary" rule.

**Test plan:** Unit tests for `AppThemeController.resolve()` (this is exactly
the "pure algorithmic/date/tz math with many cases" carve-out from the
integration-test default) covering: 9pm ET / dark, 10pm ET / dark (new
boundary), 6:59am ET / dark, 7:00am ET / light, and a DST-transition date to
confirm the fixed-rule helper handles the EST/EDT switch correctly using the
two distinct UTC transition hours above. All test inputs must be constructed
with `DateTime.utc(...)` explicitly (not a locally-constructed `DateTime`
run through `.toUtc()`), since the test host's own timezone would otherwise
silently leak into the input. The property under test — proving the actual
fix — is that `resolve()`'s output depends only on the UTC instant passed
in, never on the host/device's own offset: pick one instant that is 22:00 ET
(= 19:00 PT that day) and assert dark, to demonstrate a "west-coast" instant
still resolves correctly without needing to fake a host timezone (Dart tests
can't override `DateTime.now().timeZoneOffset` directly, so this is the
correct way to express that case). Also add a `_scheduleBoundary()` test
asserting the computed next-flip instant lands on the Eastern boundary, not
a device-local one — this is where the bug actually lives if only `resolve()`
is fixed. For `_scheduleBoundary()`'s wall-clock arithmetic near a transition
day: build the candidate 07:00/22:00 Eastern wall-clock times, convert each
to UTC using the offset computed *at that candidate instant*, and take the
earliest strictly-future one — cover this with a test dated on a transition
day.

## 2. Races list card: remove leading first-place avatar

**Problem:** Each card in the "My Races" list (`races_tab.dart`,
`_buildRaceRow()` at line 1456) shows a 52px `RacerAvatar` for the race
**leader** (rank 1) on the left (`races_tab.dart:1625-1633`), fed by
`race['leader']['animal']`/`['accessories']`. This is confusing — it's easy to
mistake for "your" avatar. Remove it, reflow the card, and stop sending the
now-unused data from the backend.

**Frontend change** (`lib/screens/tabs/races_tab.dart`):
- Remove the `RacerAvatar` block (1625-1633) and its leading `SizedBox(12)`.
- The user's own placement chip (`'${formatOrdinal(myPlacement)} PLACE'` /
  `'??? PLACE'`, currently in the trailing right column at 1758-1777) moves
  into a `Row` next to the race name (currently built at 1638-1656), so it
  sits level with the name.
- `timeLabel` (currently duplicated: inline at 1663-1668 for ACTIVE races,
  and again in the trailing column at 1778-1802 for others) is consolidated
  to render directly under the relocated placement chip for all statuses,
  removing the duplication.
- Remaining content (name, chip, time) shifts left to fill the space the
  avatar occupied.
- **Scope correction: this item touches `_buildRaceRow()` only.**
  `_buildTournamentRow()` (line 1192) renders `RacerAvatar(key:
  Key('tournament-identity-avatar-$id'), ...)` at lines 1298-1310, wrapped in
  `Semantics(label: 'Your racer, $identityName')` — that's the **viewer's
  own** avatar, not a race-leader avatar, so the "easy to mistake for your
  avatar" rationale doesn't apply and it should be **left as-is**.
  `_buildTournamentTicket()` (line 511) has no leading avatar at all — its
  `Column` opens directly with a name/status-badge `Row` (lines 558-591), so
  there's nothing to change there either. Only `race['leader']`
  (`races_tab.dart:1477-1495, 1625-1633`, inside `_buildRaceRow()`) is fed by
  the backend `leader` field and is the only avatar in scope for removal.
- `_RacesLoadingSkeleton` (line 1981, the shimmer placeholder) must be updated
  to match the new card shape (no leading-avatar placeholder box) so the
  loading state doesn't visually jump when real data arrives; delete the now
  -dead `striped:` parameter on its `_row` (lines 2073-2084) rather than
  leaving an unused flag once item 3's striping removal also lands.
- **Tutorial mirror:** `lib/tutorial/tutorial_preview_data.dart:639-644`
  ships a `'leader'` fixture consumed by `tutorial_real_screens.dart`
  rendering the real `RacesTab` inside the tutorial. Remove that now-unused
  fixture key in this same change so the tutorial preview data doesn't drift
  from the real API shape.
- **Protected-test conflicts (CLAUDE.md "existing tests are protected" —
  enumerate explicitly, don't silently delete):**
  `test/races_tab_card_redesign_test.dart` lines 98-128, 147-158, 160-190
  assert the leader avatar's existence and geometry (including the
  `avatarRect.right < titleRect.left` ordering assertion) — these three are
  **intentionally superseded** by this change and should be replaced with
  assertions on the new layout (placement chip level with name, time
  underneath, no leading avatar element). Any narrow-width /
  large-text-scale overflow guard in that file that isn't specifically about
  avatar geometry must be kept and re-pointed at the new leading widget, not
  deleted. `test/races_tab_test.dart:116` reads the
  `race-card-header-$raceId` key — keep that key stable so this test needs no
  change beyond whatever content assertions move. Also check line 130's
  assertion ("time, boxes, powerups, and effects use the larger card scale")
  in the same file — consolidating the duplicated `timeLabel` rendering
  likely touches it even though it isn't about avatar geometry.

**Backend change** (leaner `GET /races` response,
`stepv2-backend/src/modules/races/queries/getRaces.js`) — **deploy AFTER the
app build ships, not before:**
- Remove the `leader` field assembly (lines 386-399) and its supporting
  `getFirstPlaceRacer()` helper (lines 29-68) and batched `leaderUserById`
  lookup (lines 158-170, the `findPresentationsByUserIds` bulk query) from the
  response — confirmed unused anywhere else in the frontend (only
  `races_tab.dart` reads `leader`/`leaderAnimal`/`leaderAccessories`).
  `getRaces.js` has no Redis/`derivedCache` involvement, so there's no
  cache-shape or version-variant-keying concern — this is a plain query
  change.
- `winner` (line 381, completed races only) and `myPlacement`/
  `myPlacementHidden` are untouched — `race_results_summary_screen.dart` still
  reads `winner`, and the placement chip still needs `myPlacement`.

**Compat — verified, not assumed:** `races_tab.dart:1477-1495`'s existing
fallback chain (`race['leader'] is Map` → `race['winner'] is Map` → `const
{}`) is confirmed fully defensive — a missing `leader` key will **not**
crash any client. But the degradation is visible, not free: with `leader`
absent, every ACTIVE row on a frozen (not-yet-updated) binary renders
`RacerAvatar(rank: 1, animal: null, accessories: [])` — a generic undressed
capybara in the leader slot (confirmed by
`test/races_tab_card_redesign_test.dart:147-158`'s existing fallback-path
assertion). That's a real, visible regression for every user still on the
old build — which, per CLAUDE.md, is the majority of users for most of a
week of phased rollout, plus anyone who never updates. **Therefore the
backend field removal must not ship until the reflowed app build (which no
longer reads or needs `leader` at all) has rolled out**, exactly like this
repo's other rollout-gated changes (e.g. `testOnly` flips). Ship order:
(1) frontend reflow ships in the next app release; (2) wait for that build's
phased rollout to substantially complete (~1 week, per CLAUDE.md's rollout
timing); (3) only then remove the backend `leader` field in a separate,
later backend deploy. Do not combine steps 1 and 3 into one deploy.

**Test plan:** Integration test pumping the races list screen with a fixture
race and asserting: no `RacerAvatar` renders in `_buildRaceRow()`, placement
chip renders next to the race name, time label renders once (not duplicated)
beneath it. **This round's backend test suite is unchanged** — do not write a
"`GET /races` omits `leader`" test now, since `getRaces.js:386-399` is
deliberately kept intact this round and such a test would be red from the
moment it's committed. That assertion belongs with the later, separate
field-removal deploy (step 2 of the rollout order below), authored together
with that change.

## 3. Races list: remove alternating row color (races page only)

**Change:** In `lib/screens/tabs/races_tab.dart`, remove the three/four
`index.isOdd ? parchmentLight : parchment` striping sites (lines 522-524,
1212-1214, 1552-1554, and the `striped:` flag at 2081) — all race cards render
`AppColors.of(context).parchment` regardless of index. Scoped to
`races_tab.dart` only; `leaderboard_tab.dart`, `friends_tab.dart`, and
`profile_tab.dart` keep their existing striping (confirmed with user — those
lists aren't separated into boxed cards the way races are).

**Test plan:** Widget test rendering ≥3 race cards and asserting all share
the same background color (no dependency on list index).

## 4. Consistent kebab menu for leaving/forfeiting a tournament (presentation-only)

**Corrected problem statement:** active-tournament forfeit is **not**
missing — `tournament_detail_screen.dart:1141-1148` already renders a
`FORFEIT` `PillButton` (next to `GO TO MY MATCHUP`) wired to `_forfeit()`
(line 427) → `_api.forfeitTournament()` (line 440), behind a confirm dialog
that already says "Your opponent advances. No refunds." (lines 430-437). The
eliminated case is already handled (lines 1153-1174). The only real gap is
**presentation**: `race_detail_screen.dart` exposes leave/forfeit through a
kebab menu (`_showRaceOptionsSheet`); `tournament_detail_screen.dart` exposes
the equivalent actions as plain inline `PillButton`s. This item is a UI
consistency pass, not a new capability — the "leave a race no matter what"
ask is already satisfied functionally for tournaments; it just doesn't look
like the race screens.

`tournament_detail_screen.dart` has four branches in `_pendingActionButtons`
(line 1179) and a separate `_activeActionButtons`:
- **Creator, PENDING** (lines 1187-1244): `START` / `INVITE` / `SHARE LINK` /
  `CANCEL`. `leaveTournament.js` blocks the creator from leaving — a kebab
  offering "leave" here would error. Leave this branch's buttons as-is;
  do **not** add a leave/forfeit kebab option for the creator.
- **Participant, PENDING** (`Tournament.amIn`, lines 1280-1314): has `LEAVE`.
  This is the one that changes.
- **Invited, PENDING**: `DECLINE`/`ACCEPT` — untouched.
- **Non-member, PENDING**: `JOIN` — untouched.
- **ACTIVE, has live matchup** (lines 1141-1148): `GO TO MY MATCHUP` /
  `FORFEIT` — the `FORFEIT` button changes.
- **ACTIVE, eliminated** (lines 1153-1174): untouched.

**Change (frontend-only, presentation change, reuses existing logic —
confirmed with user to cover both PENDING and ACTIVE):**
- Add a kebab menu (`Icons.more_vert`) to this screen's hand-built header
  `Row` (lines 645-688 — there's no `AppBar` here), mirroring
  `race_detail_screen.dart:3547-3555`'s icon and bottom-sheet structure.
- Move the participant-PENDING `LEAVE` button (line ~1280-1314) into the
  kebab sheet, calling the same existing `_leave()`/`leaveTournament()` path
  and the same confirmation copy — no new dialog, just relocated.
- Move the ACTIVE `FORFEIT` button into the kebab sheet, calling the same
  existing `_forfeit()`/`forfeitTournament()` path and its existing
  "opponent advances, no refunds" confirmation copy — no new dialog, just
  relocated. The surviving `GO TO MY MATCHUP` button, no longer sharing a Row
  with `FORFEIT` (previously `flex: 3` / `flex: 2`), becomes a full-width
  primary button.
- The existing `409 NO_LIVE_MATCHUP` handling on `_forfeit()` (a matchup can
  complete between render and tap) carries over unchanged with the
  relocation — verify it still surfaces a friendly message rather than a raw
  error after the move, since this is exactly the kind of thing a copy/paste
  relocation can silently drop.

**Compat:** Frontend-only, no backend deploy for this item — both endpoints
were already live and already called from this screen before this change.
Old app builds keep their current plain-button presentation until they
update; nothing about their behavior changes.

**Test plan:** Frontend integration test: pump `tournament_detail_screen.dart`
in participant-PENDING state, tap kebab → LEAVE, confirm, assert
`leaveTournament()` fires (this test already exists in some form for the
`PillButton` — re-point it at the kebab, don't duplicate). Second test: pump
in ACTIVE-with-live-matchup state, tap kebab → FORFEIT, confirm, assert
`forfeitTournament()` fires and the confirmation copy still mentions no
refund. Third test: creator-PENDING state shows no leave option in the
kebab (or no kebab at all, per implementation choice). Fourth test: ACTIVE
with no live matchup (eliminated) shows no forfeit action. No backend test
needed for this item — no backend logic changed.

## 5. Leaderboard friends-only toggle persists as default

**Problem:** `_selectedScope` in `leaderboard_tab.dart:93` is plain ephemeral
`State`, defaulting to `_LeaderboardScope.global` on every `initState()`. The
`LeaderboardTab` page inside `main_shell.dart`'s `PageView` isn't kept alive
across tab switches (no `AutomaticKeepAliveClientMixin`), so switching tabs
and back fully disposes and recreates the state, losing the selection. There
is no persistence layer today, so even a real app restart would reset it too.

**Change:** Persist the scope choice via `SharedPreferences`, mirroring the
existing `AppThemeController` pattern (`theme_controller.dart`'s
`preferenceKey` / `loadPreference()` / `setPreference()` idiom used
app-wide, e.g. `notification_service.dart`, `review_prompt_service.dart`):
- Add a `leaderboard_scope_pref` preference key — not `leaderboard_scope`,
  which already exists as an element inside `coach_tip.dart:29`'s
  `keyCoachTipsSeen` string list (no actual collision since that's a list
  entry not a top-level key, but the more specific name avoids future
  confusion).
- **Read the preference before the first fetch, not after, to avoid a
  double-fetch and a visible flash of the wrong board.** `initState()`
  currently calls `_loadLeaderboard()` synchronously with
  `_selectedScope = global` (`leaderboard_tab.dart:112-118`); an async
  `SharedPreferences` read completing after that first fetch would trigger a
  second `fetchLeaderboard` on every tab open. Instead: await the stored
  value first (default `global` if unset/invalid), guard with `mounted`,
  set `_selectedScope`, then call `_loadLeaderboard()` exactly once. The
  existing stale-response guard at lines 171-175 is a safety net, not a
  substitute for avoiding the extra request.
- On toggle (`leaderboard_tab.dart:205`), write the new value back
  immediately.
- This makes the choice survive both tab-switch disposal and app restarts,
  which is the stronger, more consistent fix versus only adding
  `AutomaticKeepAliveClientMixin` (which would survive tab switches but not
  restarts, and diverges from how every other sticky preference in this app
  is implemented).
- Sign-out behavior: `AuthService.signOut()`
  (`lib/services/auth_service.dart:1010-1099`) is an explicit per-key remove
  list, not a blanket `prefs.clear()`/`getKeys()` wipe — so surviving
  sign-out is the default outcome and costs nothing; just don't add
  `leaderboard_scope_pref` to that removal list. This is a low-stakes UI
  preference (not account-specific data), so a user who signs out and back
  in keeping their scope choice is the intended behavior.
- **Tutorial mirror — resolved, no pinning needed:**
  `tutorial_real_screens.dart:156` pumps the real `LeaderboardTab` against
  `tutorial_preview_data.dart:129-134`'s fake `fetchLeaderboard`, which
  already accepts a `scope` parameter and **ignores it**, always returning
  the same populated rows regardless. So a persisted `friends` preference
  renders a fully populated tutorial leaderboard with the FRIENDS pill
  pre-selected — no special-casing needed. Toggling scope inside the
  tutorial does write the real preference, which is harmless.

**Compat:** Client-only, additive `SharedPreferences` key; old builds simply
never read/write it and keep today's per-session-reset behavior until they
update.

**Test plan:** Widget/integration test: set scope to Friends, simulate
navigating away and back (rebuild the widget tree, as the real disposal does),
assert scope is still Friends and only one fetch occurred. Second test: fresh
app start with a pre-seeded `leaderboard_scope_pref=friends` preference
asserts the tab opens on Friends with a single fetch call. Third test: sign
out and back in with a persisted `friends` preference still shows Friends.

## 6. Cleanse should be able to clear Power Outage (reverted — see below)

**Status: REVERTED 2026-08-16.** An earlier draft of this item added
`POWER_OUTAGE` to `NON_CLEANSABLE_TYPES` in
`usePowerup.js` so Cleanse/Quick Rinse could no longer clear it. The owner
has since corrected the direction: Cleanse and Quick Rinse **should** be able
to clear Power Outage, i.e. keep today's (pre-batch) behavior. The exclusion
has been reverted in both `usePowerup.js` (`NON_CLEANSABLE_TYPES` back to
`["BOUNTY", "RALLY_FLAG", "UPRISING"]`) and the Cleanse/Quick Rinse copy
(backend `powerupCopySeed.js` and the frontend bundled fallback in
`powerup_copy.dart`, both back to not mentioning Power Outage). The
`powerups-power-outage-not-cleansable.test.js` integration test added for
the reverted direction has been deleted (it asserted the opposite of the
now-correct behavior; it was net-new, unmerged coverage, not a protected
existing test).

Note this doesn't touch the separate, pre-existing **jam guard**
(`usePowerup.js` ~line 1043): a participant with a **LIVE** Power Outage on
them still cannot fire Cleanse/Quick Rinse at all (409), unrelated to
`NON_CLEANSABLE_TYPES`. The only thing this item ever affected either way is
a lapsed-but-still-`ACTIVE` Power Outage row that lazy expiry hasn't swept —
that row is cleansable again, matching pre-batch behavior.

No code change needed for this item beyond the revert above — this is now a
no-op relative to current prod/staging behavior, so it drops out of this
round's deploy.

## Rollout / deploy order

Item 6 is reverted (no-op vs. current prod/staging behavior) and has been
dropped from this round's backend deploy — there is nothing to ship for it.
Item 2's backend field removal is explicitly **not** part of this round's
backend deploy either — see its compat section for why.

1. **Frontend (next app build):** items 1, 2 (reflow only — `leader` field
   still served), 3, 4, 5. Ships via normal App Store review + phased
   rollout, per CLAUDE.md — old builds keep current behavior until users
   update.
2. **Backend (later, separate deploy):** item 2's `leader` field removal,
   only after step 1's build has substantially completed its phased rollout
   (~1 week per CLAUDE.md). Tracked as a follow-up, not part of this batch's
   "final deploy" step.

## Acceptance criteria

- [ ] Night mode auto-triggers at 10pm–7am America/New_York for all devices
      regardless of device timezone (including the recurring boundary
      timer, not just the initial resolve); manual override still works.
- [ ] `_buildRaceRow()` shows no leading leader avatar
      (`race-leader-avatar-$raceId` removed); placement chip is level with
      the race name; time sits under it. `_buildTournamentRow()`'s own
      -identity avatar and `_buildTournamentTicket()` are unchanged.
      `GET /races` still returns `leader` this round (field removal is a
      later, separate deploy).
- [ ] Races list cards render with uniform (non-alternating) background.
- [ ] Participant-PENDING LEAVE and ACTIVE-with-live-matchup FORFEIT are
      reachable via the kebab on `tournament_detail_screen.dart`, calling the
      existing `_leave()`/`_forfeit()` paths with unchanged copy;
      creator-PENDING, invited, non-member, and eliminated branches are
      unchanged. No backend change for this item.
- [ ] Leaderboard Friends/Global selection persists across tab switches, app
      restarts, and sign-out/sign-in, with only one fetch per tab open.
- [x] Cleanse and Quick Rinse still clear Power Outage (item 6 reverted;
      matches pre-batch/current prod-staging behavior — no deploy needed).
- [ ] All new/changed tests pass; no existing assertion weakened; protected
      test conflicts in `races_tab_card_redesign_test.dart` explicitly
      resolved (superseded assertions replaced, not silently deleted).
- [ ] `ui-test-planner` manual checklist obtained and provided before this
      batch (items 2, 3, 4 all change on-screen placement) is presented as
      done, per CLAUDE.md's UI-placement workflow rule.

## Revision log

- Initial draft folded in all 6 in-scope items (2 of the original 8 dropped
  as already-implemented, confirmed with user via AskUserQuestion) plus
  research-driven scoping decisions: item 3 reframed from race-detail hero to
  races-list card avatar (per user correction), item 4 (active-tournament
  forfeit) included per user's explicit choice, item 3's striping scoped to
  races page only per user's explicit choice.
- Architect review (REVISE): inverted item 2's rollout order (field removal
  must follow the app build, not precede it — old clients degrade visibly,
  not safely, without it); replaced item 4's backend delegation with a
  frontend-only design calling the two existing endpoints directly (avoids a
  lock/transaction-nesting risk matching a prior outage class, a
  creator-forfeit semantics change, and a response-shape mismatch); added
  the missing `_scheduleBoundary()` fix and DST-rule/dependency decision to
  item 1; enumerated protected-test conflicts and tutorial-mirror fixtures
  for items 2 and 5; fixed item 5's double-fetch-on-load bug and sign-out
  persistence; added item 6's required copy fix (DB seed + bundled fallback,
  reaches frozen clients); added item 4's 409 NO_LIVE_MATCHUP handling;
  removed dead `striped:` skeleton flag alongside item 3.
- Second architect re-review (REVISE): corrected item 4's problem statement
  — active-tournament forfeit already ships today as a plain `PillButton`;
  this item is a presentation-only kebab-menu consolidation reusing existing
  `_leave()`/`_forfeit()` logic, not new capability — and scoped it to skip
  the creator branch (blocked server-side) while leaving DECLINE/ACCEPT/JOIN
  untouched; corrected item 2 to scope avatar removal to `_buildRaceRow()`
  only (`_buildTournamentRow()`'s avatar is the viewer's own, not the
  leader's, and `_buildTournamentTicket()` has no avatar at all); removed a
  backend test from this round's item-2 plan that would land red before the
  later field-removal deploy; documented item 6's guard-path behavior change
  (Cleanse/Quick Rinse now error via the existing "nothing to cleanse" guard
  when Power Outage is the only active effect) and added its test; pinned
  the exact UTC DST transition hours (07:00 March / 06:00 November) and
  fixed the test-construction guidance for item 1; closed item 5's tutorial
  and sign-out open questions; added the `ui-test-planner` checklist to
  acceptance criteria.
- 2026-08-16: owner corrected item 6's direction — Cleanse/Quick Rinse should
  keep clearing Power Outage, not exclude it. Reverted the `usePowerup.js`
  `NON_CLEANSABLE_TYPES` addition, the backend + frontend copy changes, and
  deleted the now-wrong-direction `powerups-power-outage-not-cleansable.test.js`.
  Item 6 is now a no-op and dropped from this round's deploy.
