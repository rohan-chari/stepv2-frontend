# Batch 2026-08-10 — auto-enroll off for ghosts, bigger course animals, payout-drop push timing

Three independent items. Items 1 and 3 are backend-only; item 2 is frontend-only.
No API contract changes that a frozen client can observe incorrectly (details per
item). Deploy order: backend anytime for 1+3; item 2 rides the next app release.

---

## Item 1 — Flip `autoJoinFeaturedRaces` off for ghosts who also opened no boxes

### Summary & user story
The seeded-race inactivity prune (commit `f8f5d8b`) removes users from
daily/weekly seeded races when they have 0 steps for the two most recent
completed ET days. But it never touches the `autoJoinFeaturedRaces` flag, so the
renewal cron re-enrolls the same ghosts into every new seeded race and the prune
deletes them again — forever. As the operator, I want users who are step-inactive
**and** haven't engaged with the game loop (no mystery-box opens) in the same
window to have auto-enroll flipped off, so dead accounts stop churning through
seeded races. A user who still opens boxes is engaged (maybe HealthKit is
broken) — keep their flag on even though the prune still removes them from the
race per the existing steps-only predicate.

### Current state (verified)
- Predicate: `stepv2-backend/src/modules/races/services/seededInactivity.js:69`
  `filterInactiveUserIds` — two most recent completed ET days
  (`SEED_TIMEZONE = "America/New_York"`, :22), stepSample ∪ daily-step rows,
  absence = zero; exemptions for review accounts and accounts newer than the
  window/race (:127-140).
- Three hooks, all `deleteMany` of `RaceParticipant`, all fail-open, all behind
  the `seededInactivityPruneEnabled` app setting (default false,
  `src/shared/config/appSettings.js:98-101`):
  1. Enrollment filter `dropInactive` —
     `src/modules/races/commands/autoJoinFeaturedRaces.js:68-85`.
  2. Promotion prune `pruneInactiveParticipants` —
     `src/modules/races/jobs/seededRaceRenewal.js:148-184`.
  3. Weekly mid-race ghost sweep `sweepWeeklyGhosts` — same file :190-271
     (3am-ET gate + `JobRun.claimRun` once/day CAS + entanglement skips).
- Flag: `users.auto_join_featured_races` (`prisma/schema.prisma:55-56`), set
  true at signup (`autoEnrollNewUser.js:112-115`), user-toggled via
  `PUT /users/me/featured-auto-join` (`src/modules/users/routes.js:523-546`),
  exposed in `GET /auth/me` (`routes.js:382`, ≤10s Redis cache).
- Box opens: `race_powerup_events` rows, `event_type = 'MYSTERY_BOX_OPENED'`
  (string, not enum), `actor_user_id`, `created_at` = de-facto opened-at.
  Written at `openMysteryBox.js:271` and the fanny-pack auto-activate branch
  (:239). Rerolls deliberately do NOT write this event (`rerollMysteryBox.js:343`).
  **No index on `actor_user_id`** — only `@@index([raceId, createdAt])`
  (`schema.prisma:1302-1317`).

### Design
New rule, evaluated wherever the prune already identifies an inactive user:

> inactive-by-steps (existing predicate) **AND** zero `MYSTERY_BOX_OPENED`
> events in the same ET window → set `autoJoinFeaturedRaces = false`.

- Window helper: do NOT change `filterInactiveUserIds`'s return shape (three
  call sites + tests would churn). Export a tiny
  `inactivityWindowStart(now, timeZone)` from `seededInactivity.js`
  (= `etDayStart(dayMinus2)`), and have both the steps predicate and the
  box-open query call it — same can-never-disagree guarantee, zero call-site
  churn.
- Box-open read goes through the **powerups model layer**, not raw Prisma in a
  races service: add
  `RacePowerupEvent.findActorIdsWithEventSince({ userIds, eventType, since })`
  to `src/modules/powerups/models/racePowerupEvent.js` and call it from the
  races service (concrete-path import; races⇄powerups is already
  cycle-adjacent). Predicate: ≥1 `MYSTERY_BOX_OPENED` with
  `createdAt >= windowStart` — **deliberately no upper bound**, so a box opened
  *today* (after the steps window closes) also protects the flag; someone who
  opened a box an hour ago is engaged.
- Flag write goes through the **users model chokepoint**, not raw
  `prisma.user.updateMany` from the races module:
  `src/modules/users/models/user.js` is the documented C5 `/auth/me`
  cache-invalidation chokepoint, and `autoJoinFeaturedRaces` is served from the
  cached payload. Add `User.disableAutoJoinFeaturedRaces(userIds)` there —
  updateMany with the `autoJoinFeaturedRaces: true` guard, per-id
  `invalidateAuthMe`, returning the ids actually flipped — export it via
  `src/modules/users/index.js`, and add the row to the classification table at
  the top of `src/modules/users/services/authMeCache.js`. Races-side helper
  `disableAutoEnrollForInactive({ userIds, now })` computes
  `inactive minus boxOpeners` and calls it. Idempotent (guard makes repeats
  no-ops).
- Self-limiting by construction: once flipped, the user drops out of
  `where: { autoJoinFeaturedRaces: true }` (`autoJoinFeaturedRaces.js:55-56`),
  so the ghost set fed to `dropInactive` shrinks monotonically — hook 1 is both
  the necessary and the terminating path.
- Call sites: **all three hooks**. Hook 1 (`dropInactive` at enrollment) is the
  critical one: in steady state, with the prune enabled, a ghost is filtered
  out at enrollment and never becomes a participant — so hooks 2/3 never see
  them. If the flip lived only in the prune/sweep hooks, the enrollment filter
  would keep evaluating the same ghosts against every new seeded race forever
  and the flag would never flip. Hooks 2/3 additionally catch users who went
  ghost mid-race. The write is fail-open in all three places.
- Exemptions: inherit automatically — the input to the flip is the output of
  `filterInactiveUserIds`, which already excludes review accounts and
  new accounts.
- **Kill switch:** new app setting `seededInactivityAutoEnrollOffEnabled`,
  default **false**, declared next to `seededInactivityPruneEnabled` in
  `appSettings.js` and toggleable via `PATCH /admin/settings`. Checked inside
  `disableAutoEnrollForInactive` so both call sites are covered. It is a
  *sub-switch*: the code path only runs when the parent prune switch is also on
  (it lives inside the prune hooks).
- Fail-open — **ordering matters**: each hook's existing outer catch changes
  the prune's *outcome* (`dropInactive`'s catch returns the **unfiltered** list;
  hooks 2/3 return 0), so an exception from the flip must never reach it. In
  all three hooks the flip runs **after** the hook's own work (the filter
  result / the `deleteMany`) and inside its **own nested try/catch that never
  rethrows** — a flip failure can log but can never change what the prune did.
- No user notification on flip (silent). The settings screen toggle simply
  shows OFF next time the client refreshes `/auth/me`; the user can re-enable
  any time via the existing `PUT /users/me/featured-auto-join`, which also
  opts them back into PENDING seeded races (`routes.js:536`).

### Data model / migrations
One migration: `@@index([actorUserId, eventType, createdAt])` on
`RacePowerupEvent` (`race_powerup_events`) — three-column because the predicate
always filters `eventType = 'MYSTERY_BOX_OPENED'` and the table is dominated by
other event types (a partial index would be better but Prisma can't express one
without schema drift). Without it the per-cron predicate is an unindexed scan.
Note: `CREATE INDEX CONCURRENTLY` cannot run inside Prisma's per-migration
transaction, and no existing migration uses it — at current scale (~1k DAU,
capacity memo) a plain `CREATE INDEX` lock is brief; the backend agent should
check the prod row count before deploy and run it off-peak. No column changes,
no backfill.

### API contract
Unchanged. `autoJoinFeaturedRaces` already exists in `GET /auth/me` and the PUT
toggle; old clients already render both. A frozen client whose flag is flipped
off sees exactly what it sees today when a user toggles it off manually.

### Backward-compat & rollout
Backend-only. Ship with the new setting **false**; flip on in staging, observe
one renewal-cron day, then prod.
- **Known limitation (accepted):** a user who manually re-enables auto-join
  while still step-inactive with no box opens will be re-flipped at the next
  seeded-race creation — the predicate has no memory of the manual toggle
  (no `auto_join_toggled_at` column exists). Acceptable for v1: the population
  is dead accounts; a user who re-enables *and* walks or opens a box stays
  enrolled. Revisit with a toggle-timestamp column if support reports surface. No app release involved. Rollback = toggle the
setting off (already-flipped users stay off — acceptable; they can re-enable,
and we can bulk-restore via SQL if we ever regret it, using the audit trail
below).
- **Observability:** log each flip batch at info level (count + first N ids,
  capped — pm2 logs rotate, so don't rely on full id lists). No new table.
  *(Implementation correction: the originally proposed SQL restore fallback via
  `users.updated_at` doesn't exist — the users table has no `updated_at`
  column. The capped log line is the only restore trail; if a durable restore
  list is ever needed, that's a follow-up audit column/row.)*

### Test plan (backend, tests first — `test:unit` / `test:integration`, test DB only)
Integration (extend `test/.../seeded-challenge-payouts-inactivity.test.js` /
sibling):
1. User with 0 steps for 2 ET days and no box-open events → after
   `promoteSeededRace`, participant row deleted AND `autoJoinFeaturedRaces`
   false.
1b. Enrollment path: same ghost, not yet a participant → `enrollAutoJoinUsers`
   for a new seeded race skips them AND flips the flag (the steady-state path).
2. Same user but with one `MYSTERY_BOX_OPENED` event inside the window →
   participant row still deleted, flag stays **true**.
3. Box open *before* the window (createdAt < windowStart) → flag flips.
3b. Box open *today* (createdAt after the steps window closes) → flag stays
   **true** (the open-ended upper bound is deliberate).
4. `seededInactivityAutoEnrollOffEnabled=false` (default) → prune runs, flag
   untouched.
5. Weekly sweep path (`sweepWeeklyGhosts`) flips the flag under the same rule.
6. Review-account / new-account exemptions: flag untouched.
7. Idempotency: second cron pass over the same user is a no-op (updateMany
   count 0).
8. Reroll event (`MYSTERY_BOX_REROLLED`-style rows) does NOT count as an open.
Unit: window arithmetic already covered in `seededInactivity.test.js`; add a
case for the shared-window reuse if the return shape changes.

### Acceptance criteria
- With both settings on, a 2-day ghost with no box opens is out of the race and
  out of future auto-enrollment after one renewal cycle.
- A 2-day ghost who opened a box is out of the race but still auto-enrolls next
  race.
- Default-off setting means zero behavior change at deploy time.

---

## Item 2 — Race detail: slightly bigger course animals

### Summary
On the race-detail course (`HomeCourseTrack`), the runner sprites read small.
Make them ~10% bigger. Frontend-only; no backend involvement.

### Current state (verified)
- One production call site: `lib/screens/race_detail_screen.dart:3229`
  (`_buildRaceHero`, `height: 286`) serving pre-start, live, and finished
  states. Not used on the home tab.
- Size math: `lib/widgets/home_course_track.dart:337-338` —
  `sizeScale = (height / 236).clamp(1.0, 1.16)`;
  `capybaraSize = (isUser ? 50.0 : 44.0) * sizeScale`. At height 286 the clamp
  is **saturated** (286/236 = 1.212 → 1.16), so today: user 58.0, others 51.04.
  Raising the track height does nothing; the base sizes (or clamp ceiling) must
  change.
- Mirrors: none. Demo race tutorial (`lib/demo/demo_race_host.dart:434`) and tab
  tutorial (`lib/tutorial/tutorial_real_screens.dart:134`) instantiate the real
  `RaceDetailScreen`, so they inherit the change — they still must be eyeballed
  (fake-data rosters differ).
- Sharp edges (all `home_course_track.dart`):
  - Marker box fixed `markerWidth => 96` (:1531, and the SizedBox :504-506);
    height is `capybaraSize + 38`. Sprite must stay < 96 wide.
  - Shadow height hardcoded 8/7 px (:346-361) while shadow width scales — a
    small size bump is fine; a big one makes shadows look thin.
  - `_metadataOffset` (:905-913 and duplicate :1048-1056): accessory offsets
    with `abs() > 1` are absolute pixels and do NOT scale — any accessory tuned
    with raw-pixel offsets drifts when sprites grow. Fractional offsets scale
    cleanly.
  - `_headBobOffset` (:885-888) references 58: `(size/58).clamp(0.85, 1.2)` —
    still inside the clamp at the proposed sizes.
  - `_friendClusterOffsets` / `_friendOffsetsNearUser` (:367-382): absolute-
    pixel fan-out offsets tuned against 44px sprites — clustered friends
    overlap ~12% more at 55.7px. Expected fine; covered by manual checkpoint 1.
  - Per-animal `baselineOffset` (`lib/config/animals.dart:13-64`) is a fraction
    of frame size, so ground-line alignment scales automatically (corgi -6/64,
    turtle 0).

### Change
In `home_course_track.dart:338`, raise the base sizes:
`(isUser ? 55.0 : 48.0)` — rendered on race detail: user **63.8** (was 58.0,
+10%), others **55.7** (was 51.04, +9%). Leave `sizeScale`, clamp, and
`height: 286` untouched. 63.8 < 96 marker width with room for accessories.
No other constants change; shadows/markers/bob remain acceptable at +10%.

### Degradation / states
Pure rendering constant; loading/empty/error states unaffected. iOS and Android
share the widget. No missing-field concerns.

### Test plan
- Existing suites are size-agnostic by construction and must stay green
  untouched: `test/character_baseline_alignment_test.dart` (ground-line
  parity — this is the canary for a broken baseline),
  `test/home_course_track_test.dart`, `test/turtle_character_test.dart`.
- No new automated test asserts the literal sizes (that would be a
  change-detector test). Verification is the manual UI checklist below.
- Mechanical touch-up: `test/character_baseline_alignment_test.dart:94` uses
  `const bigger = 50.0 * 1.4` commented as "the larger home-course user size" —
  update the constant to track 55 so the comment stays true (assertion
  unchanged).
- Sanity: re-run `test/home_course_track_test.dart` at its existing pumped
  heights — the marker box (`capybaraSize + 38`) grows to ~102px; confirm no
  overflow errors.

### Manual UI-placement test plan
(ui-test-planner output, verbatim.)

*Elements under test:* Runner sprites inside `HomeCourseTrack` grow from 58→63.8px (user) and 51→55.7px (others) at race detail's height 286. Single production call site confirmed: `lib/screens/race_detail_screen.dart:3229` (`_buildRaceHero`). Change propagates automatically to demo race tutorial and tab tutorial (both render the real `RaceDetailScreen` — confirmed at `lib/demo/demo_race_host.dart:434` and `lib/tutorial/tutorial_real_screens.dart:134`).

**A. Real race detail screen (shared — change propagates)**

1. **Live race, crowded.** Get there: Races tab → open an active race with 4+ participants, ideally with a cluster near the leader. Verify: sprites visibly larger; user sprite larger than friends'; clustered friends' overlay offsets still keep sprites distinguishable (they fan out, don't fully stack); no sprite clips off the top of the hero or behind the HUD chips (countdown/pot chips at top).
2. **Name tags at new width.** Same screen. Verify: name tags (fixed 96px marker width, `home_course_track.dart:1531`) still center over each sprite and don't collide worse in clusters; tag doesn't overlap the sprite's head at the taller 63.8px.
3. **Shadows and ground line.** Same screen. Verify: each sprite's feet touch the track ground line (no floating/sunken runners); the ellipse shadow (hardcoded 8/7px tall — does NOT scale) still sits directly under the feet, not behind or above them.
4. **2-runner race.** Get there: open (or create on staging) a race with just you + one friend. Verify: both sprites placed on track correctly with no cluster-offset artifacts; user sprite at start line (0%) and near finish (if available) stays inside the hero bounds.
5. **Pre-start race.** Get there: Races tab → an upcoming/scheduled race you've joined. Verify: runners parked at the start render at new size, feet on ground, tags aligned; countdown chip does not overlap sprites.
6. **Finished race.** Get there: Races tab → history → a completed race. Verify: final-position sprites at new size, especially runners bunched at/near the finish; nothing clips the right edge.
7. **Heavily accessorized user.** Get there: Profile → customization → equip hat + glasses + shoes + held item (max out slots) → open any active race. Verify: hat sits ON the head (not floating above or sunk in), shoes on the FEET per walk frame, held items in the paw — accessory offsets with abs()>1 are absolute pixels (`_metadataOffset`, :905-913) and were tuned at 58px, so misalignment here is the top regression risk. Watch a full walk cycle.
8. **Each animal type.** Get there: switch your character to corgi_puppy, reopen the race; then turtle; then capybara. (Or find a race containing friends on each animal.) Verify: per-animal baselineOffset ground alignment holds at the new size — corgi and turtle feet on the ground line, turtle 8-frame walk not jittering vertically.
9. **Head-bob sanity.** Any live race, watch the user sprite walk for ~10s. Verify: bob amplitude looks normal, no clipping at the top of the bob (clamp logic references size 58).
10. **Dark mode.** Get there: Settings → force dark (or after 21:00) → any active race. Verify: night backdrop; sprites/shadows still sit on the night course's ground line.

**B. Demo race tutorial (real screen, `demoMode: true` — propagates, but fixture-fed)**

11. **Demo pre-start + live beats.** Get there: sign in with a fresh account → onboarding → demo race. Verify: on every beat that shows the course (countdown, step-progress beats, powerup beats), sprites render at the new size, feet grounded, tags aligned. Note: `demo_race_engine.dart` fabricates NO `animal` field — all demo runners should be capybaras; a missing/blank sprite here is a finding.
12. **Coach ring vs bigger sprites.** During the beat where `_CoachRing` circles the countdown clock chip (`demo_race_host.dart:443` → `tutorialClockKey` on the hero chip at `race_detail_screen.dart:3286`). Verify: the ring still rings the chip, and a runner near the top of the course does not walk through/behind the ringed chip.
13. **Demo win/finish beat.** Verify: finish-line sprite placement at new size; the hand-forked `_WinCard` chrome doesn't overlap sprites.

**C. Tab tutorial (real screen, seeded preview data — propagates)**

14. **Race-detail preview beat.** Get there: Profile → admin → re-run tutorial → advance to the race-detail page. Verify: seeded runners (fixture race `tutorialPreviewRaceId`) render at new size on the course; the spotlight for `raceDetail.powerups` still rings the powerup tray, not a runner. Note: `tutorial_preview_data.dart` seeds `equippedAccessories: []` — bare capybaras expected; any accessory here is a finding.

**D. Negative checks — surfaces that must NOT change**

15. **Race-detail participant rows.** Same race screen, scroll to the standings list. Verify: row sprites unchanged (explicit `capybaraSize: 46`, `race_detail_screen.dart:7325`).
16. **Races-tab card top-3 row.** Races tab, any card. Verify: mini sprites unchanged (default 34, `lib/widgets/race_card_capybara_row.dart:23`).
17. **Customization preview + home hero.** Profile → customization, and Home tab hero. Verify: preview capybara unchanged (`CapybaraCustomizationPreview` default 118, `home_course_track.dart:564` — same file as the change, so eyeball it deliberately).

*Surfaces confirmed unaffected (verified in code):* Home tab (no `HomeCourseTrack`; hero uses `CapybaraCustomizationPreview`); start screen and admin accessory tuner (own sizes); `race_ui.dart:215` (own `size` param); demo prologue beats (no course); tab-tutorial tab bar and races-tab effect plates (no runner sprites).

*Risks found while planning* (become implementation-agent checks):
- **Absolute-pixel accessory offsets** (abs()>1) were tuned against the old rendered sizes; hats/shoes/held items may be visibly misplaced at 63.8/55.7px. Checkpoint 7 is the most likely failure. If it fails, the fix is per-accessory retuning (admin tuner), not a revert.
- **Hardcoded shadow heights 8/7** now proportionally smaller; if runners read as "floating," scale shadow heights in the same change.
- **96px marker width** gives less horizontal slack around a wider sprite — check crowded races for tag collisions.
- **Head-bob clamp references literal 58** — verify the bob math keys off `capybaraSize`, or the bob will be off for the user sprite only.
- **`tutorialClockKey` chip floats over the hero** — sprite growth can push a lead runner into the chip/coach-ring zone in the demo (checkpoint 12).
- **Demo/tutorial fixtures carry no `animal` and empty accessories** — turtle/corgi and accessory alignment are only testable on real races; "capybara-only in demo" is expected, not a pass for the animal checks.

### Acceptance criteria
- Runners visibly larger on race detail in all three race states; ground line
  intact for capybara, corgi, turtle; accessories (hats/face/feet) still seated
  correctly on all animals; no name-tag clipping at 96px marker width; demo
  tutorial and tab tutorial course renders verified.

---

## Item 3 — Payout drop-out push: gate on time-to-end + durable anti-spam

### Summary & user story
The "Out of the payout" push currently fires whenever the 5-minute placement
cron sees a user cross below `paidPlaces` — including 7am on a daily challenge
with 17 hours left, when totals churn wildly off tiny step counts as devices
sync. As a user, a "you dropped out of the prize places" alert is only
actionable near the end of the race; earlier it's noise. Gate it to the final
hours and make the anti-spam brake durable.

### Current state (verified)
- Trigger: `stepv2-backend/src/modules/notifications/notificationHandlers.js:987-993`
  (`droppedOutOfPaid`); copy at :1010-1011; collapse id `placement_${raceId}`
  (:1033). Emitted from the placement cron
  `src/modules/races/jobs/placementRecompute.js:421` every
  `RECOMPUTE_INTERVAL_MS = 5 min`; `paidPlaces` computed at :336-365.
- **No time-of-day / time-remaining / cadence condition exists on this path.**
- Cooldown today: in-memory `lastPlacementAlertAt` Map, 10 min
  (`notificationHandlers.js:960-1001`) — lost on restart, not shared across the
  pm2 cluster. Non-"meaningful" changes still send a silent push every tick
  (:1035-1038).
- Per-race mute: `RaceParticipant.placementAlertsMuted` honored in the job
  (:401-408).
- `race.endsAt`, `seedId`, and `timezone` are already selected by
  `Race.findActiveInProgress` and in scope in the job (placementRecompute.js:308,
  :297) but **not** included in the emitted change payload (:412-420).
- Kill switch: `LIVE_PLACEMENT_DISABLED` env (whole job).
- Durable dedup infra to reuse: `Notification.deliveryKey` unique column,
  insert-before-send (`prisma/schema.prisma:1591-1599`); audit rows pruned
  nightly after ~a week (`notificationCleanup.js`).

### Design
Two changes, both backend, both scoped to the `droppedOutOfPaid` variant only —
`tookFirst` / `lostFirst` behavior is explicitly unchanged.

**(a) Time gate.** Add `endsAt` to the change payload built at
`placementRecompute.js:412-420` (it's already in scope; pass it through rather
than re-querying in the handler). In `notificationHandlers.js`, suppress the
payout-drop push unless `endsAt - now <= PAYOUT_DROP_WINDOW_MS`.
- `PAYOUT_DROP_WINDOW_MS = 3h` (env-tunable `PAYOUT_DROP_WINDOW_HOURS`,
  default 3). One window for all cadences: for the midnight-ET daily seeded
  race this means pushes only from 9pm ET; for a weekly race, only in the final
  3 hours of Sunday evening. "Closer to the race end" as requested, and a
  single knob.
- **`endsAt == null` (step-target races) → skip the time gate**, keep today's
  behavior (meaningful crossing + shared cooldown) while still applying the
  durable once-per-race key. `Race.findActiveInProgress` deliberately includes
  null-`endsAt` races (`race.js:438`) and they can carry a pot, so
  suppress-on-null would silently remove their payout-drop push — an
  unacknowledged feature removal. (Emitter and handler deploy together, so
  `endsAt` can only be absent for target races, never "missing" for timed
  ones.)
- The gate suppresses only the **visible** payout-drop alert; the silent
  placement-sync push (`:1035-1038`) keeps firing on every change so clients
  quietly refresh, and `lastNotifiedPlacement` still advances
  (`placementRecompute.js:424`). A **suppressed** payout-drop does NOT stamp
  the shared in-memory Map (otherwise the gate would start blocking
  `tookFirst`/`lostFirst`, which this item promises are unchanged).

**(b) Durable once-per-race cap.** Add an insert-first `deliveryKey` claim,
`payout-drop:<raceId>:<userId>`, written **before** send.
- **Not via `recordNotification`** — that wrapper swallows every create error
  by design (`notificationHandlers.js:26-44`), so a unique violation would be
  invisible and the push would re-send every tick. Instead: a direct
  `notificationModel.create({ userId, type: "PLACEMENT_CHANGED", title, body,
  raceId, deliveryKey })` in its own try/catch treating
  `error.code === "P2002"` as "already sent → skip", mirroring
  `dailyRewardReminder.js:156-167`.
- The claim row **is** the audit row: the payout-drop variant skips the
  trailing `recordNotification` at `:1066-1074` (the `skipAudit` pattern at
  `:80-83`) so it doesn't write two rows.
- **Evaluation order in the handler** (two orderings are wrong, so it's pinned
  here): `droppedOutOfPaid` → time gate → shared 10-min cooldown check →
  insert-first deliveryKey claim (**last** gate before send; P2002 ⇒ downgrade
  to the silent push) → send → stamp the Map. Claiming before the cooldown
  check would let a `lostFirst` three minutes earlier burn the user's
  one-and-only payout-drop claim on a push that never sends. A
  claimed-but-failed send is an accepted permanent loss of that one alert.
- The in-memory 10-min Map stays as-is for the other placement alerts
  (tookFirst/lostFirst) — out of scope to migrate them here. A **sent**
  payout-drop still stamps the Map, so cross-variant spacing behaves exactly
  as today.
- Result: at most **one** payout-drop push per user per race, cluster-safe,
  restart-safe.
- Notification rows are pruned after ~a week; with the 3h gate the key only
  needs to survive hours, so pruning cannot resurrect a dup.

### API contract
No client-visible change. Payload type `PLACEMENT_CHANGED` and its params are
unchanged; the only change is *when/whether* the push is sent. Frozen clients
unaffected. The internal event-emitter payload gains `endsAt` — internal only.

### Backward-compat & rollout
Backend-only deploy, effective immediately for all app versions. Kill switch:
existing `LIVE_PLACEMENT_DISABLED` still covers the whole job; the new window
env gives a tuning knob without deploy (pm2 restart to pick up env). No app
release needed.

### Test plan (backend, tests first)
Integration (placement-recompute → notification path, test DB):
1. Daily seeded race, user drops below `paidPlaces` with 17h remaining → **no**
   visible push (silent sync still sent).
2. Same drop with 2h remaining → push sent, deliveryKey
   `payout-drop:<raceId>:<userId>` row exists.
3. Second drop (recover then drop again) inside the window → **no** second
   push (unique key).
4. Same user, different race → push sends independently.
5. `placementAlertsMuted` still suppresses inside the window.
6. Payload missing `endsAt` → suppressed (defensive default).
7. `tookFirst` / `lostFirst` pushes still fire outside the window (unchanged
   behavior guard), including right after a *suppressed* payout-drop (the
   suppressed alert must not stamp the shared cooldown Map).
8. Env override `PAYOUT_DROP_WINDOW_HOURS=6` widens the gate.
9. Step-target race (`endsAt` null) with a pot → payout-drop still sends
   (time gate skipped), and the once-per-race key still applies.
10. Cluster-safety: two workers process the same drop concurrently (both past
   the in-memory Map) → exactly one push, one notification row (mirror
   `test/jobs/dailyRewardReminder.test.js:186-199`).
11. Audit: a sent payout-drop writes exactly one `Notification` row (the
   deliveryKey claim row; no duplicate from `recordNotification`).

### Acceptance criteria
- No payout-drop push can be produced more than 3h (default) before `endsAt`
  on a timed race; step-target races (`endsAt` null) keep today's timing but
  gain the once-per-race cap.
- At most one payout-drop push per user per race, across restarts and cluster
  workers.
- First-place and lost-first-place alerts behave exactly as before.

---

## Revision log
- v1 — initial draft from codebase exploration (backend + frontend agents).
- Gap pass 1 — **Item 1 logic hole fixed**: with the prune enabled, ghosts are
  filtered at enrollment (hook 1) and never become participants, so a flip
  living only in hooks 2/3 would never fire in steady state; flip now runs in
  all three hooks, with hook 1 as the primary path (+ test 1b). Item 3: payout-
  drop keeps stamping the shared in-memory Map so cross-variant spacing is
  unchanged.
- User interview 2026-08-10 — confirmed: silent flip (no re-engagement push);
  3h window uniform across cadences; one payout-drop push per user per race;
  ~10% animal size bump.
- Gap pass 2 — Item 1 migration: `CREATE INDEX CONCURRENTLY` can't run inside
  Prisma's migration transaction; plain `CREATE INDEX` accepted at current
  scale, deploy off-peak. Item 3: confirmed silent placement-sync pushes and
  `RACE_ENDING_SOON` are untouched; defensive suppress-on-missing-`endsAt`
  retained. Item 2: confirmed head-bob clamp (63.8/58 = 1.10 < 1.2) and marker
  width headroom at the proposed sizes.
- Architect review (verdict REVISE) — all 7 REQUIRED folded in: (1) flag write
  via `User.disableAutoJoinFeaturedRaces` chokepoint + `invalidateAuthMe` +
  authMeCache classification row (raw `updateMany` would leave stale `/auth/me`
  for the cache TTL); (2) box-open read via new
  `RacePowerupEvent.findActorIdsWithEventSince` model method, not raw Prisma in
  a races service; (3) flip runs after each hook's own work in a nested
  never-rethrow try/catch (hook outer catches change prune outcomes); (4)
  box-open predicate has deliberately no upper bound + test 3b; (5) dedup claim
  is a direct `notificationModel.create` treating P2002 as already-sent —
  `recordNotification` swallows errors — and the claim row is the audit row
  (`skipAudit`); (6) `endsAt == null` (step-target races with pots) skips the
  time gate instead of suppressing forever + test 9; (7) handler evaluation
  order pinned (gate → cooldown → claim-last → send → stamp Map; suppressed
  alerts don't stamp). Suggestions adopted: 3-column index incl. `eventType`;
  `inactivityWindowStart` helper instead of return-shape churn; capped
  observability logging + SQL restore fallback; self-limiting note; cluster
  concurrency test 10; friend-cluster-offset sharp edge; baseline-test comment
  constant; marker-height overflow sanity.
