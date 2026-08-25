# Daily Cohort Minimum 30 and Tutorial Reel Inventory Timing

## Summary & user story

As a Daily Challenge participant, I should be placed into the fewest balanced
private cohorts that target at least 30 people, so ordinary Daily fields do not
become unnecessarily small. As a new user completing the race tutorial, I
should see the last box remain a box until its reel finishes; the rolled
powerup must enter the visible inventory only after the reveal lands.

This document covers two independent fixes that can be reviewed and deployed
independently: a backend-only Daily cohort policy change and a frontend/demo
state-timing fix.

## Current state and diagnosis

### Daily/weekly cohort history

- `3c630c0` (`2026-08-24 11:11 ET`) changed seeded Daily/Weekly planning from a
  hard 15-person cap to a 15-person minimum target. Its exact formula is in
  `stepv2-backend/docs/daily-challenge-cohort-minimum-requirements.md`.
- `e02ff7d` (`2026-08-24 11:37 ET`) added a cadence-specific weekly minimum of
  50 while preserving Daily at 15 in
  `stepv2-backend/src/modules/races/services/seededRaceBuckets.js`.
- Both commits are ancestors of the production tag
  `step-sync-queue-prod-20260824` (`2026-08-24 19:58 ET`), so the currently
  deployed weekly minimum is 50, not 100. No history inspected contains a
  weekly-100 implementation.
- The renewal job finalizes the next Daily window during the five minutes
  before its `America/New_York` midnight boundary
  (`stepv2-backend/src/modules/races/jobs/seededRaceRenewal.js:551-564`). A
  policy deployed after that boundary cannot change that already-finalized
  window.

### Tutorial reel

- The regular overlay path already defers
  `RaceDetailScreen._optimisticallyApplyBoxOpen` until `CaseOpeningScreen`'s
  `onRevealed`, after the strip completion callback
  (`lib/screens/case_opening_screen.dart:329-335`,
  `lib/screens/race_detail_screen.dart:6634-6645`).
- The demo path violates that boundary because
  `DemoRaceEngine.openBox()` changes the backing `_inventory` row from
  `MYSTERY_BOX` to `HELD` before returning the roll
  (`lib/demo/demo_race_engine.dart:316-345`). Demo detail polling calls
  `_loadDetails()` every three seconds and rehydrates the visible inventory
  from that engine (`lib/screens/race_detail_screen.dart:1729-1745`).
- Therefore the last tutorial box can appear as the rolled powerup behind the
  non-opaque reel while it is still spinning. The existing reel timing tests
  cover the parent callback, but not this demo-engine/polling path.

## Scope / non-goals

In scope:

- Change only private seeded `DAILY_10K` planning from minimum 15 to minimum
  30, using the same minimum-target semantics and friendship-preserving
  planner already used by the weekly-50 change.
- Apply the new value only when a future Daily window is planned/finalized.
- Keep the tutorial's real `RaceDetailScreen`, `CaseOpeningScreen`, and demo
  service; defer the demo engine's visible inventory transition until the reel
  has revealed the result.
- Add integration/widget coverage through the public paths.

Out of scope:

- Changing the weekly minimum (current deployed behavior remains 50).
- Repacking finalized or active windows, legacy/global seeded races, payouts,
  scoring, eligibility, or API JSON shapes.
- Adding a release flag, kill switch, or temporary runtime control.
- Changing reel duration, animation, or tutorial copy.

## Exact implementation plan

### Backend

1. In `stepv2-backend/src/modules/races/services/seededRaceBuckets.js`, add an
   explicit `DAILY_COHORT_MINIMUM = 30` selected only when
   `seed.kind === "DAILY_10K"`; retain `WEEKLY_COHORT_MINIMUM = 50` and the
   generic planner default separately. This prevents unrelated seeds and
   direct generic `planBuckets()` callers from changing accidentally.
2. Preserve the existing formula: zero users produces no cohorts; a non-zero
   roster smaller than the minimum produces one cohort; otherwise use
   `floor(n / minimum)` cohorts distributed as evenly as possible. Thus Daily
   30 → `[30]`, 31 → `[31]`, 59 → `[59]`, 60 → `[30, 30]`, and 61 → `[31, 30]`.
3. Treat 30 as a minimum lower bound for ordinary cohorts, but preserve whole
   friendship components. If an indivisible component would create a short
   trailing remainder, use the existing deterministic nearest-adjacent merge;
   the merged cohort may exceed its numeric target, and a component is never
   split merely to hit 30. Add explicit large-component and trailing-remainder
   cases and retain permutation independence.
4. Preserve deterministic skill ordering, durable window membership, exact
   persisted `Race.maxParticipants`, and immutable finalized-window behavior.
5. Update the existing backend requirements/spec and add tests first in
   `test/services/seededRaceBuckets.test.js`; extend
   `test/integration/seeded-race-buckets.test.js` to assert persisted Daily
   capacities and idempotent finalization. Run only against the dedicated test
   database.

The cadence-specific helper also supplies the fallback `maxParticipants` for
featured cards when no persisted race exists. That display is intentionally
updated to 30 for a new Daily upcoming card; a persisted pending race keeps
its own stored capacity. Tests must cover both the fallback card and the
persisted-race path so the UI never advertises a capacity lower than the plan.

### Frontend/demo

1. Keep `CaseOpeningScreen`'s `onRevealed` contract as the sole visible
   inventory commit point.
2. Add a demo-only pending-roll representation in
   `lib/demo/demo_race_engine.dart` and an explicit reveal callback through
   `DemoRaceHost` → `RaceDetailScreen`. `openBox()` returns the authoritative
   roll but does not mutate the backing inventory, increment the opened-box
   counter, apply drift, or append the activity event. The inventory row
   remains `MYSTERY_BOX` during the reel.
3. Add an injected demo-only commit callback on `RaceDetailScreen` and invoke
   it from `onRevealed` immediately after the local optimistic projection is
   updated; do not use the later `onBoxOpened` callback. The demo callback
   commits the pending row exactly once: inventory transition, opened-box
   counter, drift, activity, and demo event. Use a generation/token barrier or
   pending-overlay merge rule so polling cannot expose the roll early or revert
   a committed roll. Clear pending state on failed roll, route disposal/abort,
   and duplicate reveal. The first and second boxes must retain their existing
   behavior, and the third/Shortcut lesson must still advance only after the
   reel completes.
4. Add a real `DemoRaceHost`/`RaceDetailScreen` widget test that opens the last
   box, pumps midway through the 4,000 ms spin plus 600 ms settle, asserts the
   row is still `MYSTERY_BOX`/no held Shortcut is rendered, then pumps through
   completion and asserts the row becomes the held Shortcut and the tutorial
   advances. Keep the existing generic reel synchronization tests.

## API contract

No endpoint, request, response, or database schema changes. The cohort change
only changes persisted placement and the already-existing `maxParticipants`
value for newly finalized bucket races. Old clients continue to receive the
same fields and legacy clients remain on the legacy stream. The demo fix is
entirely local and never reaches the backend.

## Data model / migrations

No migration or backfill. Existing active/finalized windows are immutable. New
Daily bucket rows use the new planned capacity; existing rows remain unchanged.
Postgres is the source of truth for window modes, cohort membership, bucket
assignments, and `Race.maxParticipants`; no Redis-derived state or new Redis
surface is introduced. Existing post-finalization race-list invalidation stays
in place.

## Frontend states and platform compatibility

The reel must have these externally observable states: unopened box, pending
roll/spinning with the original box still visible behind the overlay, revealed
held powerup, and failed/cancelled roll with no committed transition. This
applies to the shared Dart path on iOS and Android; no platform-specific code
or build flag is needed. Missing/malformed server fields remain handled by the
existing defensive readers.

## Backward compatibility & rollout

Deploy the backend cohort change first, then ship unrelated frontend changes
only through the normal iOS and Android lockstep release process. No old app
binary depends on the new cohort count or a new field. The backend change is
safe to deploy without an app release.

The persisted cohort policy becomes effective at the first Daily
`finalise()` call that runs on the new backend binary and finds no existing
bucket rows for that window. Election before deploy does not matter if
finalization happens after deploy; an already-finalized window is unchanged.
A deploy before 23:55 ET can affect the next midnight window. A deploy during
the five-minute finalization window may race the scheduler and is not a safe
promise; a deploy after finalization or at/after midnight defers to the
following Daily window. Given the current Aug 24 state and the need to
write/tests/review/deploy safely, the recommended commitment is the first
boundary after verification, with Aug 26 00:00 ET as the conservative target
if Aug 25 00:00 ET cannot be met. The final date must be based on the actual
production deploy timestamp.

Operational sequence:

1. Backend tests and review; confirm the production database is not used by
   tests.
2. Deploy backend and verify `startCrons()` remains owned by
   `NODE_APP_INSTANCE === "0"`: worker 0 runs the scheduler and worker 1 is
   HTTP-only, while production remains exactly two PM2 workers. Do not start
   staging for verification.
3. Confirm the first newly finalized Daily window with a read-only production
   query of seed kind, window start, bucket count, ordered `maxParticipants`,
   and assignment counts; compare it with the immediately preceding window and
   confirm prior windows were not rewritten.
4. Implement/test the frontend demo fix, then run `flutter analyze` and the
   relevant widget/integration suites. Build iOS and Android in lockstep for a
   release; no feature flag is required.

## Test-first plan

- Backend unit cases: 0, 1, 29, 30, 31, 59, 60, 61, 89, 90, 91, a large
  roster, deterministic permutation independence, friendship components, and
  Daily/weekly separation.
- Backend integration cases: pure planner cases stay in unit tests; public HTTP
  reads of featured/seeded races verify the persisted result and compatibility.
  The renewal lifecycle test uses the approved injected-clock job seam only
  where no public endpoint invokes finalization, and proves Daily 61-person
  finalization persists 31/30 capacities, repeat finalization is idempotent,
  an existing finalized window is unchanged, and legacy-stream isolation
  remains intact. Boundary tests cover before/during/after the five-minute
  finalization window.
- Frontend integration/widget path: real demo host → real race detail → real
  case opening reel, asserting no mid-spin inventory mutation and one
  post-settle mutation for the final Shortcut box.
- Regression: existing `test/case_reveal_sync_test.dart` and demo off-script
  gating tests remain unchanged and pass.
- Existing engine/host tests that currently assume `openBox()` commits
  immediately must be updated first to drive `commitBoxOpen()` explicitly;
  their existing assertions remain protected. Add first/second/third-box,
  polling, failed-roll, duplicate-reveal, and mid-spin lifecycle cases.

## Acceptance criteria / definition of done

- Newly finalized Daily rosters use minimum-target 30 behavior, with no
  newly planned cohort below 30 when at least 30 eligible users exist.
- Weekly remains 50; existing windows are untouched.
- The tutorial's last box remains visibly unopened until the reel lands, then
  becomes the held Shortcut exactly once and the next tutorial beat appears.
- No API/schema/flag changes; old clients remain compatible.
- Required tests are written before implementation and pass, backend tests use
  a non-production database, `flutter analyze` is clean, both platforms are
  accounted for, and code review passes.

## Manual UI-placement test plan

- Run the onboarding demo and advance through all three boxes. On the third
  box, confirm the visible tray still shows the unopened box throughout the
  spin; confirm the Shortcut appears only after the reel lands.
- Repeat by letting the demo polling interval elapse during the spin; the
  result must not appear early.
- Confirm the first Protein Shake and second Compression Socks lessons still
  open, reveal, and advance normally.
- Replay the tutorial from its alternate entry point/settings path if enabled;
  confirm the same real demo race surface and no duplicate inventory commit.
- Confirm normal live race mystery-box opening still commits only after reveal.
- Review unchanged mirror/fixture surfaces explicitly:
  `demo_race_api_service.dart`, `demo_race_engine.dart`,
  `tutorial_preview_data.dart`, `demo_auth_service.dart`,
  `tutorial_real_screens.dart`, and the `raceDetail.powerups` spotlight key.
  `tutorial_preview_data.dart` has only one preview box and cannot exercise the
  three-box timing case; that case must remain on `DemoRaceHost` fixtures.
- Confirm `demo_race_network_guard_test.dart` still covers every
  `RaceDetailScreen` API call and that no spotlight anchor moved.

## Revision log

- Gap pass 1: separated the deployed weekly-50 state from the requested Daily
  change; documented finalized-window immutability and the five-minute
  finalization boundary.
- Gap pass 2: traced the tutorial regression through demo engine mutation and
  three-second detail polling; added pending/commit/rollback states, direct
  real-screen coverage, and the conditional effectiveness-date rule.
- Architect review: scoped the Daily constant to `DAILY_10K`, defined friendship
  oversize/merge behavior, separated finalization from election timing, made
  Postgres ownership and two-worker scheduler ownership explicit, required a
  demo callback/token barrier, protected existing engine tests, and added the
  public-path/lifecycle test distinction.
- UI test-planner review: added the manual checklist for the playable demo,
  polling during spin, first/second-box regressions, settings replay, live
  race regression, the preview-fixture limitation, and spotlight/network
  guard checks.
