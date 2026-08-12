# Team Race Animated Hero Scenes — Requirements

Status: **approved and implemented** · 2026-08-12 · frontend-only

## Summary and user story

In an ACTIVE team race, each team leader should look like they are running on
the same living pixel course used by the Home hero: the animal cycles through
its existing walk frames while the seam-tiled grass moves left beneath it and
clouds drift in parallax. The `@name` plate remains above the animal. The feet
must visually meet the grass line rather than hover over it.

As a racer comparing teams, I want the two leader cards to feel like an active
race at a glance, while the team totals, momentum message, and separate
STANDINGS section remain stable and easy to read.

## Scope

- Replace only the illustrated 148px leader scene inside each ACTIVE team
  scoreboard card with the existing `HomeHeroScene` sky/cloud/scrolling-ground
  composition.
- Reuse the established Home speed of 26 logical pixels/second.
- Reuse the existing animal-specific walk sheets and equipped-accessory frame
  placement at the Home hero's exact 720ms cadence.
- Move the sprite's visual baseline down using the Home hero's established
  transparent-padding correction with a fixed 34px ground strip and
  `bottom = 34 - 4 - size * 0.22`, so the feet touch or enter the grass fringe
  by four pixels.
- Keep the existing responsive containment calculation for wide/rotated
  behind-body accessories, including fractional and fixed-pixel metadata.
- Keep leaders between 48px and 108px. The 48px compatibility floor preserves
  the protected 320px `angel_wings` fixture with fixed -30px offsets and 1.35x
  scale. If other behind-body art cannot fit even with a 48px leader, omit it only from the
  hero scene rather than shrinking the animal below a readable size.
- Preserve the top `@name` plate, lower team summary, gold leader outline,
  momentum message, and separate STANDINGS section.
- Support both light and dark theme assets and both iOS and Android.

## Non-goals

- No changes to race scoring, team membership, placements, powerups, effects,
  standings, polling, navigation, or the Home screen.
- No new artwork, asset generation, API fields, backend endpoints, persistence,
  sound, particles, gestures, or user setting.
- No animation on pending/completed/solo race layouts.
- No duplicated full-width race course above the team scoreboard.

## API contract

No API change. The ACTIVE race screen continues reading the existing
authenticated race progress response and existing participant fields:
`displayName`, `team`, `totalSteps`, `animal`, `accessories`, and `stealthed`.
No new request, response field, endpoint, status, error, header, or feature
token is introduced.

Older app binaries keep rendering their frozen scoreboard. New binaries work
against older/newer servers because all animation inputs are already bundled
and must be normalized before layout/rendering. Invalid or empty `slot` and
`assetKey` rows are omitted. Offset/rotation values must parse to finite
numbers; scale must be finite and positive; `animationFrames` must be at least
1. Huge-but-finite values are not safe: omit rows with fixed offsets beyond
512 logical pixels or scale outside `(0, 8]`, normalize rotation modulo `2π`,
and accept animation frames only in `1..64`. Any non-finite derived bound uses
the same safe omission/default path. Missing/malformed leader, animal,
accessory, or render metadata falls back safely and must not throw.

## Data model and migrations

None. No database, schema, seed, migration, backfill, cache, or local-storage
change.

## Frontend implementation plan

1. In `lib/widgets/team_scoreboard_cards.dart`, keep the private team hero
   scene stateless and compose the existing stateful motion primitives. Wrap
   each keyed 148px team scene, including its fixed nameplate, in one
   `RepaintBoundary` so its perpetual motion does not repaint the surrounding
   scoreboard.
2. Use `HomeHeroScene` from `lib/widgets/home_hero_scene.dart` with:
   - `groundScrollSpeed: 26`;
   - `groundHeight: 34` for the 148px card;
   - Team A/Team B sky alignment differences where visible so the two cards do
     not look like a cloned frame;
   - the existing parchment and subtle team-color washes above the scene art;
   - `ExcludeSemantics` around sky/cloud/ground art so it stays decorative.
3. Replace the static `frameIndex: 0` leader with the existing walk-cycle path.
   Enhance `AnimatedCapybaraWithAccessories` additively with
   `animate = true`, preserving all existing callers. Set its race-card cadence
   to exactly 720ms. When `animate` becomes false initially or at runtime, stop
   and pin the controller to frame 0; `didUpdateWidget` resumes it when true.
4. Anchor every sprite at the fixed Home baseline
   `bottom = 34 - 4 - size * 0.22`. Containment may only shrink `size`; it must
   never lift the baseline or go below 48px. At that fixed baseline, verify the rotated
   axis-aligned bounds from all four transformed accessory corners against the
   horizontal margins, reserved top name band, and scene bottom. Before solving
   size, discard any behind-body row that cannot fit those bounds at 48px, then
   recompute and pass the retained scene-local list to the renderer. The animal
   remains visible at 48–108px even when a cosmetic is omitted. Lock tests to
   the calculated foot line for default capybara and corgi.
5. Keep the `@name` plate at the top and reserve its vertical band in the
   containment math. It must never collide with the moving sprite or be part of
   the moving background.
6. Preserve privacy selection: if the highest scorer is stealthed, show the
   next visible teammate; use `No one yet` only when the team is empty or all
   its members are stealthed. Those no-leader states render the moving course
   without an animal or username.
7. Lifecycle/performance: rely on Flutter `TickerMode`/widget disposal for
   routes that are no longer active; do not add timers or viewport machinery.
   Give each `HomeHeroScene` a stable team-based key, never a leader-based key,
   so polling can replace scores/leaders without resetting ground phase. Asset
   loads remain bundled and precached by the existing scene implementation.
8. In `lib/widgets/home_course_track.dart`, add shared defensive accessory
   normalization used before both geometry and rendering. Omit invalid rows;
   sanitize base and per-animal transform metadata to finite offsets/rotation,
   fixed offsets within ±512px, rotation modulo `2π`, scale in `(0, 8]`, and
   `animationFrames` in `1..64`; reject any non-finite derived calculation.
9. Keep shared `HomeHeroScene` behavior unchanged. The team scene reads
   `MediaQuery.disableAnimationsOf(context)` and passes effective ground speed
   `0` instead of `26` when disabled, which renders ground phase 0 locally;
   the shared scene already freezes clouds from the same MediaQuery. Runtime
   toggles rebuild this input, and the additive sprite `animate` flag pins frame
   0. `TickerMode(enabled: false)` must mute both scene and sprite tickers
   without rebuilding layout.
10. Backend/API/DB/cache changes are prohibited; backend review only locks the
    unchanged contract.

## Loading, empty, error, and version-skew behavior

- Before a leader is available, the existing `No one yet` state remains.
- Theme asset selection is local and synchronous after normal asset loading;
  there is no network loading state.
- Unknown animals fall back to the default capybara. Shared normalization omits
  malformed accessory rows and sanitizes invalid, `NaN`, infinite, zero, or
  negative transform/cycle values, plus huge-but-finite values beyond the
  locked bounds, before geometry and rendering.
- If animations are disabled by the platform, background, clouds, and animal
  all freeze deterministically at ground phase 0 / animal frame 0 while
  preserving the exact layout and information. Runtime toggles do the same.
- Poll refreshes may change totals or leader identity without restarting or
  jumping the background phase unnecessarily.

## Backward compatibility and rollout

This is app-only and requires no deploy ordering. Frozen clients are unchanged;
the shared backend sees no new traffic shape or parameter. Both platforms ship
from the same Dart implementation. No new content needs `testOnly` gating.

## Tests-first plan

Before production edits, extend the real `RaceDetailScreen` widget coverage in
`test/race_detail_team_scoreboard_test.dart` so it fails for the current static
scene:

1. Assert both populated team hero scenes contain the reusable moving-ground
   scene configured at speed 26 and animated leader widgets.
2. Pump time and assert the ground transform moves left and the leader's
   rendered animal frame changes at the locked 720ms cadence.
3. Assert the `@name` plate remains above the sprite throughout the sampled
   cycle and the exact fixed-baseline equation grounds capybara, corgi, and
   turtle across their species-specific frames.
4. At 320px, assert the actual transformed bounds of a wide, rotated/fixed-
   offset behind-body accessory remain inside the scene across sampled frames;
   calculate its axis-aligned bounds from all four transformed corners. Cover
   a separate fractional-offset fixture too.
5. With `MediaQuery.disableAnimations: true`, pump time and assert the ground,
   clouds, and sprite frame remain unchanged at deterministic phase/frame 0.
6. Toggle reduced motion at runtime and assert phase/frame reset to the
   deterministic values. Wrap in `TickerMode(enabled: false)` and assert no
   scene or sprite advancement. Do not use `pumpAndSettle` with infinite motion.
7. Simulate a progress poll changing totals and leader identity; assert stable
   team-keyed `HomeHeroScene` states retain their ground phase and no old/new
   duplicate leader appears.
8. Assert a hidden top scorer selects the next visible teammate; separately
   assert empty/all-stealthed teams show no sprite/username and do not throw.
9. Pump malformed accessory payloads containing wrong key types, `NaN`,
   infinity, huge-but-finite offsets/scale/frame counts, zero/negative scale,
   and invalid animation frames through the real screen and assert safe
   omission/fallback without non-finite layout. Assert an uncontainable
   behind-body accessory is absent while its leader remains visible, at least
   48px, finite, and grounded. Preserve the existing fixed-offset
   `angel_wings` fixture rendered and bounded at 320px.
10. Add a shared-widget test proving `AnimatedCapybaraWithAccessories.animate`
    defaults to true so leaderboard/ranked/lobby behavior remains unchanged.
11. Preserve all existing scene, totals, semantics, leadership, layout,
   standings, effect-rail, malformed-data, and responsive assertions.

Run the focused scoreboard/standings suites, scoped analysis, formatter, and
`git diff --check`; then build an Android staging app bundle and iOS simulator
app from the same final source. Report repository-wide pre-existing failures
honestly rather than weakening protected tests.

## Acceptance criteria and definition of done

- Both team leaders visibly walk while the grass moves left and clouds drift,
  matching the Home hero's forward-motion language.
- At the locked 34px ground and Home baseline equation, capybara, corgi, and
  turtle feet visually touch the grass throughout their walk frames.
- Both scenes remain equal at 148px and preserve the name-above-animal layout.
- Wide accessories stay clipped safely inside their own scene, not cut off by
  the card edge or overlapping the name/team summary.
- Reduced motion produces a fully static but equally readable scene.
- Empty, stealth, malformed, long-name, day/night, 320/375/390/430px, and
  either-team-leading states remain safe.
- No backend/API behavior changes and old app versions remain compatible.
- Tests are written and observed failing before production edits; focused tests
  and scoped analysis pass; both platform builds pass; UI placement and code
  reviews return no blockers.

## Revision log

- **Gap pass 1:** Scoped motion to the existing Home primitives; added exact
  speed, reduced-motion behavior, lifecycle/performance boundaries, defensive
  server-metadata handling, and the empty/stealth state.
- **Gap pass 2:** Added frame-sampled grounding and transformed-accessory tests,
  protected the top nameplate band, prevented background phase resets on poll
  refresh, documented distinct team crops, and made both-platform verification
  explicit.
- **Architect review:** Locked the 34px ground and fixed Home baseline, 720ms
  cadence, shared finite metadata normalization, deterministic runtime reduced
  motion, stable team keys, per-scene repaint boundaries, privacy semantics,
  poll-phase preservation, transformed-corner coverage, and default-compatible
  animation API.
- **Architect re-review:** Kept shared Home behavior out of scope by locally
  selecting speed 0 for reduced-motion cards, bounded huge-but-finite metadata,
  added derived-bound guards and turtle automation, and preserved decorative
  scene semantics.
- **Architect final gap:** Added a 48px compatibility floor and scene-local
  omission/recomputation for behind-body art that cannot fit even at that floor,
  preserving the protected 320px wings fixture and a visible grounded leader
  instead of collapsing it toward zero.

## Manual UI-placement test plan

### Elements under test

- Each ACTIVE team leader's static 148px scene becomes a moving
  sky/cloud/scrolling-grass course inside the same card.
- Each leader animal changes from a fixed frame to its existing walk cycle,
  with accessories moving with it.
- Each animal moves slightly lower so its feet touch or enter the grass fringe
  instead of floating.
- Default capybara, corgi, and turtle leaders use their own grounded walk
  frames without changing the card layout.
- A hidden top scorer is skipped and the next-highest visible teammate occupies
  the leader scene.
- An empty/fully stealthed side keeps the course and `No one yet`, with no
  animal or username.
- The `@name` plate, team summary, gold leader outline, momentum banner, and
  separate STANDINGS section remain in their existing positions.

### Checklist

1. **Production ACTIVE team-race detail — responsive/platform matrix**
   - **Get there:** On staging, open a populated ACTIVE team race from Races →
     active race. Test iOS at 320px light and 390px dark; test Android at 375px
     light and 430px dark. Change theme through Profile → Settings → Appearance.
   - **Verify:** Both cards remain side by side and equal-height at every width.
     Each 148px scene contains sky, drifting clouds, scrolling grass, and one
     walking leader below its fixed `@name` plate. No scene, sprite, accessory,
     or name crosses the card boundary or center gap. There is no separate
     full-width animated course above SCOREBOARD and no duplicate/static animal
     left at the former floating position.
2. **Production ACTIVE team-race detail — grounding throughout motion**
   - **Get there:** Stay on the populated race at each tested width and watch
     both leaders through several complete walk cycles.
   - **Verify:** Each animal's visible feet touch or enter the grass fringe by a
     few pixels on every sampled frame; neither animal bobs into a visibly
     floating position. The sprite never sinks into the dirt, crosses the top
     name band, or overlaps the team summary below. The name plate and card
     remain stationary while the sprite and scenery move.
3. **Production ACTIVE team-race detail — animal variants and fallback**
   - **Get there:** Use staging fixtures that place a default capybara, corgi,
     and turtle as team leaders in turn; also use an unknown or missing animal
     value to exercise the default capybara fallback. Check at least the turtle
     and corgi at 320px.
   - **Verify:** Every species walks within the same reserved scene band and
     remains grounded across all of its frames. The shorter/wider turtle and
     differently padded corgi do not float, sink, touch the name plate, or
     overlap the summary. The missing/unknown animal renders one grounded
     default capybara in the new position, with no blank scene or duplicate
     sprite at the old position.
4. **Production ACTIVE team-race detail — either side leading**
   - **Get there:** Open or seed two ACTIVE team races: one with Team A ahead
     and one with Team B ahead.
   - **Verify:** The gold outline surrounds only the leading card in either
     state without shifting or resizing its scene. The two animated scenes
     remain aligned, followed by the unchanged team summaries, then the
     momentum banner, then the separate STANDINGS section. No old leader ribbon
     or duplicated leader treatment appears.
5. **Production ACTIVE team-race detail — wide/rotated accessories and long names**
   - **Get there:** On the 320px iOS case and 375px Android case, use leaders
     equipped with a wide behind-body accessory such as wings, including one
     with rotated or fixed-pixel offsets, and a long display name.
   - **Verify:** Across the walk cycle, the animal scales down enough that the
     complete transformed accessory stays inside its own scene. It is not
     clipped by the outer card, center gap, grass edge, or top reserved name
     band. The `@name` plate stays above the art, truncates within the card, and
     does not move with the background. No second uncontained accessory remains
     at the old static placement.
6. **Production ACTIVE team-race detail — hidden top scorer**
   - **Get there:** Seed one team whose highest-step member is stealthed and
     whose second-highest member is visible.
   - **Verify:** The visible second-highest member is the sole animal and
     `@name` shown in that team's hero scene, grounded in the new position. The
     stealthed top scorer has no sprite, accessory, username, placeholder, or
     duplicate at the old position. The visible substitute remains contained
     while the team total and card placement stay unchanged.
7. **Production ACTIVE team-race detail — empty and fully stealthed states**
   - **Get there:** On staging, open an ACTIVE team race with one empty side;
     then use a fixture where every member on one side is stealthed.
   - **Verify:** The affected 148px card still shows the themed moving course
     and centered `No one yet`, but no animal, accessory, or username appears
     anywhere in that scene. The opposite populated card remains normally
     animated. No hidden sprite or old `@name` plate remains in the former
     leader position.
8. **Production ACTIVE team-race detail — reduced motion**
   - **Get there:** Enable iOS Reduce Motion and Android Remove animations,
     relaunch the same populated ACTIVE team race, and check light and dark.
   - **Verify:** Grass, clouds, and animal are frozen on a stable frame with the
     same placement: feet grounded, name above animal, accessories contained,
     cards equal at 148px. No layer disappears, jumps, or duplicates.
9. **Production ACTIVE team-race detail — scrolling, refresh, and navigation**
   - **Get there:** Watch the cards, scroll SCOREBOARD fully offscreen and back,
     trigger a normal refresh, navigate back and reopen, and use a
     Tournament/Public Races entry if available.
   - **Verify:** Returning onscreen never relocates feet, name, background, or
     accessories. Refresh/leader swap does not briefly show both leaders or
     restart the course. Leaving does not paint over the prior route.
     SCOREBOARD, momentum, and STANDINGS retain their order.
10. **Production non-target race layouts**
   - **Get there:** Open a solo ACTIVE race, PENDING team race, and COMPLETED
     team race.
   - **Verify:** None gains the new animated card pair. Existing layouts remain
     unchanged with no duplicated scene.

### Surfaces confirmed unaffected

- Home already owns the shared motion language; its hero is not moved/resized.
- Demo and tab tutorial race-detail fixtures are solo, so the team-only cards
  are absent; this is expected fixture behavior, not visual feature coverage.
- No tutorial spotlight key is attached to these cards.
- Races-tab effect/inventory copies and case-opening screens do not render this
  team hero.

### Risks found while planning

- `AnimatedCapybaraWithAccessories` currently ignores reduced motion; the new
  additive control is required or the animal walks over a frozen course.
- Animal sprite sheets have species-specific dimensions, baselines, and frame
  counts; one capybara check cannot validate corgi or turtle grounding.
- Hidden-leader selection must continue skipping stealthed racers before
  constructing the hero, or animation could expose a hidden identity.
- The fixed baseline correction must happen after containment without lifting
  wide wings into the name band.
- Two compact scenes own motion state; offscreen scroll, route changes, refresh,
  and leader swaps are the highest-risk phase-reset/painting moments.
- The scene must remain exactly 148px or downstream content shifts.
