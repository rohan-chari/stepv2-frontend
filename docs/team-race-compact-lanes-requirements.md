# Team race compact lanes — requirements

Status: **approved and implemented** · 2026-08-11 · frontend-only

## Approved visual correction — 2026-08-11

This section supersedes the earlier “cohesive team lanes,” scoreboard-order,
and narrow-fallback language below. The first implementation was rejected on a
real iPhone simulator because it interpreted “color the entire column” as one
full-height enclosing slab and moved the score below the name at normal phone
widths.

The corrected, approved hierarchy is:

1. team chips;
2. two **independent** leader hero cards;
3. the full-width momentum strip;
4. two roster columns made of **individually separated racer cards**.

There is no outer hero-plus-roster lane container and no continuous colored
ground behind a whole column. “Leading/trailing treatment for the entire
column” means every independent hero/racer card in that column receives the
same state treatment while retaining visible gaps between cards.

Every racer uses three horizontal zones: avatar; a flexible identity column
with the username first and `compact multiplier · exact steps` immediately
below it; and, only when effects exist, a one-icon-wide horizontally scrollable
effect rail on the right. This keeps the score from stealing username width.
A racer with no effects does not reserve the right rail. Effect artwork stays
28px but its tooltip hit target is 44×44. Overflow fade, swipe semantics, and
scroll discoverability are derived from actual available width rather than
effect count.

Leading hero and racer cards keep their more vibrant team-tinted surfaces, but
their outlines and restrained glow are gold. Team-color outlines—especially a
green leading outline—are explicitly superseded by this gold treatment.

The final density pass aligns every racer card to a 59px minimum height whether
it has zero, one, or many effects; removes placement-number overlays from the
avatars; narrows the scoreboard shell margin, internal padding, hero/roster
gutters; and limits Team B to a subtle parchment/green accent (7–16% depending
on element/state). Dark-mode Team B scores retain contrast-safe foregrounds.

The final hierarchy separates the matchup summary from the racers: `SCOREBOARD`
contains only team chips, hero cards, and the momentum message. A distinct
`STANDINGS` header and card immediately below own the two racer columns. This
matches the section rhythm used by individual races while preserving the team
columns and their compact effect rails.

> Historical note: the remaining original proposal is retained only as design
> history. Wherever it mentions a continuous lane/slab, momentum above the
> heroes, inline name-and-score rows, or effects beneath the score, the approved
> correction in this section is authoritative.

## Summary and user story

The ACTIVE team-race scoreboard already presents two large team-leader
portraits, team totals, a momentum message, and two roster columns. The roster
cells are currently tall vertical stacks and reserve a narrow vertical effect
rail even when it is empty. This makes the scoreboard long, visually repetitive,
and weaker than the reference design.

As a racer, I want the two sides to read as cohesive competing team lanes, with
the leading lane visibly more energetic and every racer's score, multiplier,
buffs, and debuffs scannable in a compact card, so I can understand the state of
the team race without scrolling through oversized rows.

The agreed visual direction is:

- retain the large current-leader portrait at the top of each team;
- communicate which team leads through the color treatment of that team's
  **entire lane**, not through a `LEADING` banner;
- render each racer in a compact two-row card at normal widths: identity +
  score/multiplier on row one, horizontally scrollable effect icons on row two,
  with an explicit narrow/accessibility fallback;
- use icon-only buff/debuff plates with tap tooltips; and
- render no progress bars.

## Scope

### In scope

- The ACTIVE team-race `SCOREBOARD` branch in
  `lib/screens/race_detail_screen.dart`.
- The team presentation widgets in
  `lib/widgets/team_scoreboard_cards.dart`.
- Compact team roster cells and their active-effect interaction.
- Responsive behavior on both narrow and wide phones, in day and night mode.
- Updating the existing real-screen widget tests to protect the new behavior.

### Non-goals

- No backend, scoring, multiplier, powerup, payout, or economy changes.
- No new artwork or generated scenery.
- No changes to solo/ranked standings (`LeaderboardPlank`).
- No changes to PENDING team lobbies or COMPLETED team results.
- No changes to team race cards on Home or the races tab.
- No changes to the separate POWERUPS active-effects summary below the
  scoreboard.
- No restoration of progress/loading bars on team cards or racer cards.
- No `LEADING` ribbon, label, or banner.

## Current implementation and constraints

- `RaceDetailScreen` currently composes `TeamVsChips`,
  `TeamScoreboardCards`, `TeamLeadBanner`, and `_buildTeamTwoColumns` as four
  horizontal bands (`lib/screens/race_detail_screen.dart`, ACTIVE scoreboard
  branch).
- `_teamColumnCell` currently stacks a 46px character, name/multiplier row, and
  steps vertically, then reserves `_kTeamEffectRailWidth == 34` on every row.
- `_teamEffectRail` vertically fits effects into a fixed-height rail and hides
  overflow behind `+N`.
- `_effectDataFor` already reads `powerupData.activeEffects` defensively,
  resolves the source name, and classifies polarity with the shared
  `effectIsBoost` helper.
- `_EffectIconWithTooltip` already provides polarity-framed icon plates and a
  screen-clamped tooltip. It must be adapted/reused, not duplicated with a
  second tooltip implementation.
- `MultiplierChip.multiplierOf` and `MultiplierChip.maybe` already degrade
  safely when `currentMultiplier` is absent or null.
- Team totals must continue to come from `_teamTotalFromProgress`; deriving
  leadership from the visible participant rows is unsafe while Stealth masks a
  participant's steps.

## UX and visual specification

### 1. Scoreboard order

Inside the existing scoreboard section card, render:

1. `TeamVsChips` (unchanged color-to-team legend).
2. `TeamLeadBanner` (unchanged copy and defensive hidden state), moved above
   the team lanes so it does not interrupt either lane.
3. A two-column `Row`, one cohesive lane per team.

The momentum banner remains a neutral status sentence; it is not the visual
leader marker. Leadership is primarily communicated by the lane treatments
below it.

### 2. Cohesive team lanes

Refactor the paired hero-card widget into a reusable single-team lane widget in
`lib/widgets/team_scoreboard_cards.dart`. Each lane receives:

- team enum, name, total, and current visible top-scoring member;
- a `TeamLaneState` value (`leading`, `trailing`, or `neutral`), computed once
  from the same nullable total pair displayed in the heroes; and
- the roster widget for that team as a child.

`neutral` is used for both a tie and either-total-unknown. A boolean
`isLeading` is insufficient because it conflates trailing with neutral. The
caller computes the paired states once and passes one to each lane, ensuring
the two sides cannot independently disagree.

The lane owns one rounded outer container behind both the leader portrait and
all racer cards. Both lanes use the same border width and internal geometry so
lead changes do not move content.

Visual states:

- **Leading:** saturated team tint across the whole lane, team-dark border,
  stronger portrait backdrop, and a restrained team-colored outer shadow.
- **Trailing:** the same team's hue blended substantially toward parchment,
  a parchment-weight border, no outer glow, and softer inner-card tint. It must
  look subdued, not disabled; text and icons remain at full readable opacity.
- **Tie:** both lanes receive the same medium-strength team treatment and no
  glow.
- **Either total unknown:** both lanes use the tie/neutral-strength treatment.
  The UI must not infer a leader.

Use `TeamRace.color*` and `TeamRace.textColorOn` theme-aware values. Create
muted colors by blending toward the active theme's parchment colors rather
than lowering the opacity of the entire lane; whole-widget opacity would also
dim text, icons, and hit targets.

Remove the current leading-only halo from the isolated hero card. The outer
lane is now the sole visual leader treatment. Preserve the semantic label and
test key identifying the leading team even though no visible `LEADING` text is
rendered.

Remove the paired hero widget's current `IntrinsicHeight` wrapper. Horizontal
effect `ListView`s must never sit below an intrinsic-dimension query (Flutter
viewports do not support intrinsic measurement). Use a top-aligned lane row,
fixed/equal hero geometry, and ordinary finite constraints instead. Lane
bottoms may differ when team sizes differ; the colored ground continues only
through the content owned by that lane.

### 3. Team leader hero

Keep the existing large team-leader portrait behavior:

- 148px portrait region and 108px character;
- top visible scorer chosen by `TeamCardMember.topScorerOf`;
- Stealth skip for the portrait;
- team name, nullable honest team total, and `TEAM STEPS`; and
- equal hero geometry between lanes, including wrapped team names.

The hero background participates in the lane's leading/trailing color state.
No scenic art, progress bar, or leading banner is added.

### 4. Compact racer card

Replace the current vertical stack with a compact horizontal composition:

```text
rank/avatar  @displayName             2x · 57,106
             [buff] [buff] [debuff]  →
```

- Target total card height at normal widths/text scale: 64–72 logical pixels
  when effects exist, smaller when no effect row is present. Do not impose the
  current 104px content floor.
- Left: a 34–38px uncropped character/avatar, with the overall-rank badge
  attached. Preserve accessories and animal selection.
- Right, first row: one-line, ellipsized `@displayName` (plus `(you)` for self)
  on the left; an unbreakable trailing score group on the right.
- Score group: current multiplier chip when meaningful, a subtle separator,
  then the exact thousands-separated step total. With no multiplier, render
  only the step total and no orphan separator.
- Score and multiplier win width competition; long names ellipsize before the
  score is clipped.
- Right, second row: active effects, described below. When there are no visible
  effects, omit this row rather than reserving blank height.
- Preserve forfeited opacity, self highlight, Stealth masking, friend-request
  tap behavior, stable `team-cell-<userId>` keys, and authoritative/masked rank
  behavior.
- Stealthed racers render `???`, a masked rank where applicable, no accessories,
  no multiplier, and no effect tray.

The entire racer card inherits its lane state. Inner cards may use a light
parchment surface blended with the team hue, but must not return to two visually
unrelated neutral columns.

#### Explicit narrow/accessibility fallback

The normal two-row composition cannot honestly fit a 34–38px avatar, nonempty
name, meaningful multiplier, and exact seven-digit score inside each lane at a
320px screen width and 1.3 text scale. Use `LayoutBuilder` plus the effective
text scale to select a deterministic fallback when the available racer-card
content width is below 145 logical pixels or text scale is above 1.15:

1. row one: rank/avatar plus the one-line ellipsized name;
2. row two: the complete unbreakable multiplier/separator/exact-score group,
   right-aligned within the text column; and
3. optional row three: the horizontal effects tray.

This exception preserves exact competitive data and touchability instead of
forcing an impossible inline layout. Side-by-side team lanes remain. At normal
widths the agreed name + score/multiplier first row and effects second row
remain the default. Tests must cover a 320px/1.3 case with a long name, a
meaningful multiplier, and at least a seven-digit exact score.

### 5. Horizontal active-effect tray

For every non-stealthed racer with active effects:

- render every effect in the backend-provided order in a single horizontal
  `ListView`/scroll view;
- never replace effects with `+N` and never wrap onto a third row;
- use icon-only 28–30px plates;
- use the existing boost/debuff polarity colors and `PowerupIcon` artwork;
- show a narrow clipped peek or edge fade when additional icons exist offscreen
  so horizontal scrolling is discoverable;
- use platform-appropriate horizontal scroll physics and no nested primary
  scroll controller; and
- give the tray a semantics label that names all effects and announces that it
  can be swiped when overflowing.

Each icon remains individually tappable. Extend the private effect-view data
passed to the team tray to include a defensively read `expiresAt`; a small
private view model/typedef is preferred over growing the repeated inline record
shape. Tooltip copy uses `PowerupCopy.effectRailSubtitleFor`, not only the long
description. It always opens with at least `PowerupCopy.nameFor(type)` (which
falls back to the raw nonempty type) even when an unknown type has no
description. Add `From @name` only when `sourceUserId` is a nonempty string,
resolves to a participant, and differs from `targetUserId`. Reuse
`_expiresInLabel` for a valid `expiresAt`; missing, null, malformed, or expired
timestamps simply omit the remaining-time suffix. Tooltip dismissal and
three-second auto-dismiss behavior remain unchanged.

Tapping an icon, unused tray space, or horizontally dragging the effect tray
must not trigger the parent racer card's friend-request action. Establish an
explicit child gesture boundary/no-op tray tap recognizer rather than relying
incidentally on `ListView` arena behavior. Tapping elsewhere on an eligible
racer card continues to open that sheet.

### 6. Responsive and accessibility behavior

- Verify widths 320, 375, 390, and 430 logical pixels. Neither lane may
  overflow horizontally.
- On narrow widths, preserve exact score and multiplier visibility, use the
  explicit fallback above, and ellipsize the name more aggressively. Do not
  abbreviate scores to `57K`.
- Text scale must be checked at 1.0 and 1.3. The score group remains readable;
  cards may grow vertically when accessibility text requires it rather than
  clipping.
- Maintain day/night contrast. The trailing lane's dull treatment must not be
  implemented by fading its content.
- Effect icons have descriptive semantic button labels. The scroll container
  announces all applied effects and the swipe affordance.
- With animations disabled, all content and color states render immediately.

## Mirror audit

Both tutorial systems reuse the real `RaceDetailScreen`, so their data and
spotlight wiring must be audited even though the current fixtures cannot enter
this branch:

- `lib/demo/demo_race_host.dart` and `lib/demo/demo_race_api_service.dart` pump
  the real race detail screen against `DemoRaceEngine` data;
- `lib/demo/demo_race_engine.dart` currently produces a solo ACTIVE race with
  no team fields;
- `lib/tutorial/tutorial_real_screens.dart` and
  `lib/tutorial/tutorial_preview_data.dart` likewise seed a solo ACTIVE race;
- `lib/demo/demo_auth_service.dart` affects viewer identity but does not make
  either fixture a team race;
- tutorial tab chrome is outside the scoreboard; and
- `tutorialClockKey` and `tutorialPowerupsKey` anchor the countdown and the
  separate POWERUPS section, not the team scoreboard.

Therefore no demo/tutorial production file changes are expected. Add a
regression check or structural assertion that both fixtures remain solo and
continue taking the solo standings branch. This records the mirror decision so
a future fixture change cannot silently expose the ACTIVE team layout without
placement coverage. The races-tab effect plates, Home team cards, solo/ranked
standings, PENDING team lobby, and COMPLETED results do not compose these lane
widgets and remain unchanged.

## API contract

No endpoint or payload changes.

The screen continues reading the existing race-detail and race-progress
responses. Relevant optional fields remain:

```json
{
  "teams": {
    "teamA": { "name": "Cosmic Yetis", "totalSteps": 252481 },
    "teamB": { "name": "Hasty Hedgehogs", "totalSteps": 241127 }
  },
  "participants": [
    {
      "userId": "user-id",
      "displayName": "Rohan",
      "team": "TEAM_A",
      "totalSteps": 57106,
      "currentMultiplier": 2
    }
  ],
  "powerupData": {
    "activeEffects": [
      {
        "type": "RAINSTORM",
        "targetUserId": "user-id",
        "sourceUserId": "rival-id",
        "expiresAt": "2026-08-11T18:30:00.000Z"
      }
    ]
  }
}
```

All shown fields are optional/mixed-version inputs. Missing `teams` retains the
existing defensive fallback. Missing/null multiplier renders no chip. Missing
or malformed `activeEffects` renders no tray. Unknown effect types must not
crash the screen; they use the existing `PowerupIcon`/copy fallback behavior.
Non-list `activeEffects`, non-map entries, absent/null `type`, non-string IDs,
and malformed `expiresAt` values are ignored or degraded individually without
throwing or discarding otherwise valid effects.

## Data model and migrations

None.

## Backward compatibility and rollout

- Frontend-only and additive in presentation. The shared backend contract does
  not change, so frozen older clients continue working exactly as today.
- The new app does not depend on a new backend field or endpoint.
- No backend-first deployment is required because there is no backend change.
- Build and verify the same Dart implementation for iOS and Android. No
  platform-specific copy or behavior is introduced.
- No feature flag or `testOnly` content is required.

## Implementation plan

1. Write/update the real-screen tests listed below and confirm they fail for
   the intended old vertical-rail/neutral-lane behavior.
2. Refactor `lib/widgets/team_scoreboard_cards.dart` so a single lane owns its
   leader hero, `TeamLaneState` decoration, semantics, and roster child; remove
   the paired `IntrinsicHeight` composition. Keep
   `TeamCardMember`, `formatTeamSteps`, `TeamVsChips`, and `TeamLeadBanner`
   defensive behavior.
3. Recompose the ACTIVE team scoreboard in
   `lib/screens/race_detail_screen.dart`: chips, momentum banner, then the two
   decorated lanes.
4. Rewrite `_teamColumnCell` to the compact two-row composition while
   preserving identity, rank, Stealth, forfeit, self, and friend-sheet logic.
5. Replace `_teamEffectRail` and its fixed geometry constants with the
   horizontal per-racer tray. Reuse/adapt the existing effect plate, tooltip,
   polarity, expiry formatter, and clamping code; delete only rail/overflow
   code that has no remaining caller. Establish an explicit tray gesture
   boundary from the enclosing friend-request card tap.
6. Verify day/night themes, narrow widths, text scaling, and both platform
   interaction conventions.
7. Run formatter, targeted tests, full `flutter test`, and `flutter analyze`.

## Tests-first plan

Update or add frontend widget/integration tests before changing business UI:

1. Real ACTIVE team race renders the momentum banner above two lane containers;
   each lane contains its own hero and roster.
2. Backend team totals—not the visible participant sum—select the vibrant lane
   and semantic leading key.
3. Trailing lane uses a muted blended surface without applying `Opacity` to
   the whole lane; tie and unknown-total states treat both lanes equally.
4. Large team-leader portraits and Stealth-safe top-scorer selection survive.
5. A compact card renders name, exact steps, and multiplier on the first row at
   normal widths; long names ellipsize without hiding the score.
6. At 320px and text scale 1.3, a long name + meaningful multiplier +
   seven-digit exact score selects the specified narrow fallback without
   overflow or abbreviation.
7. Zero effects omit the second row and produce a shorter card. One- and
   five-effect cards have equal height; five effects render five plates in a
   horizontal scroll view, no `+N`, and never add a third effect row.
8. Horizontal dragging reveals later effect icons and does not open the friend
   sheet. Tapping an icon and tapping unused tray space also do not open it;
   tapping ordinary eligible card space still does.
9. Tapping an individual right-edge icon opens a fully on-screen tooltip with
   fallback-safe name, effect-rail description, eligible source, and valid
   remaining time; malformed/missing expiry is safe.
10. Mixed-version cases cover non-list `activeEffects`, malformed/non-map
    entries, absent/null fields, unknown effect type, non-string IDs, and
    malformed expiry without a throw.
11. Boost and debuff plates use different polarity treatments.
12. Stealthed cells expose no multiplier or effects and preserve masked rank.
13. Forfeited and self states retain their existing presentation/interaction.
14. No overflow at 320/375/390/430 widths and at text scales 1.0/1.3.
15. Existing solo/ranked standings, PENDING team lobby, and COMPLETED team
    result tests remain unchanged and green.
16. Demo and tab-tutorial fixtures remain solo and continue rendering the solo
    standings branch.

The protected `test/race_detail_team_effect_rail_test.dart` is intentionally
migrated to the new behavior rather than silently weakened: the old `+N`
assertion is replaced by the stronger requirement that all five effects exist
and can be scrolled to. The old equality across zero/one/five effects is
deliberately replaced because zero-effect cards are now required to omit their
second row and be shorter; equality is retained between one- and five-effect
cards to prove overflow never grows the card. Polarity, tooltip-clamping,
Stealth, and interaction coverage remain. Rename the file to
`race_detail_team_effect_tray_test.dart` only if test history remains clear.

Stable keys added for testability:

- `team-lane-TEAM_A` / `team-lane-TEAM_B` on the outer lanes;
- preserve `team-leading-TEAM_A` / `team-leading-TEAM_B` semantics keys;
- preserve `team-cell-<userId>` on racer cards; and
- `team-effect-tray-<userId>` on each horizontal tray.

## Acceptance criteria and definition of done

- The leading team's complete lane is visibly more vibrant than the trailing
  lane; the trailing lane remains readable and interactive.
- Ties and unknowable totals make no false leadership claim.
- Large team-leader portraits remain.
- Racer cards use the compact two-row inline name/score composition at normal
  widths and the specified exact-data-preserving fallback at narrow or enlarged
  text layouts.
- Every active buff/debuff is reachable in a horizontal icon tray and has an
  individual tooltip.
- No team or racer progress bars appear.
- No effect is hidden behind `+N`.
- Stealth, forfeit, friend-sheet, rank, multiplier, night-mode, and defensive
  mixed-version behavior are preserved.
- Tests were written/updated first and pass without weakening unrelated
  protected assertions.
- `flutter analyze` is clean and the relevant targeted suite plus full
  `flutter test` pass.
- iOS and Android are explicitly accounted for.
- Architect review, UI-placement checklist, and post-implementation code review
  have completed.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Team race compact lanes**

*Elements under test:* Momentum banner moved from between the leader cards and rosters to above both team lanes.  
*Elements under test:* Each team’s leader hero and roster moved into one cohesive side-by-side lane.  
*Elements under test:* Racer identity, multiplier, and exact score moved from a tall vertical stack into the first row of a compact card.  
*Elements under test:* Per-racer effects moved from a fixed right-side vertical rail with `+N` overflow into an optional second-row horizontal tray.  
*Elements under test:* The isolated leading-card halo is removed; no visible `LEADING` banner or progress bar is added.

*Checklist*

1. **ACTIVE team-race scoreboard — real screen**
   - **Get there:** On staging, open **Races → an ACTIVE team race** seeded with two populated teams, honest team totals, and a clear leader; scroll to **SCOREBOARD**.
   - **Verify:** The order is team legend → momentum sentence → two side-by-side lanes. Each lane contains its large leader hero at the top and that team’s racer cards directly beneath it inside the same outer container. The leader and roster are not still split into separate bands, the momentum sentence is not still between them, and no visible `LEADING` banner or progress bar appears.

2. **Leader heroes and lane ownership — real screen**
   - **Get there:** In the same race, use data where each team has multiple racers and one team’s nominal top row is Stealthed.
   - **Verify:** Both lanes retain equal hero geometry, with a large portrait above the team name, total, and `TEAM STEPS`; wrapped team names do not shift the opposing roster’s start unexpectedly. The top visible scorer appears in each hero, while the Stealthed racer is not used as the portrait. The leading treatment surrounds the complete hero-and-roster lane, not only the hero, and no old isolated hero halo remains.

3. **Compact racer cards — real screen**
   - **Get there:** Use an ACTIVE team race containing the viewer, a long display name, a meaningful multiplier, a racer without a multiplier, a Stealthed racer, and a forfeited racer.
   - **Verify:** Every normal card places rank/avatar at left; one-line name at upper center-left; and the unbroken multiplier · exact-step group at upper right. A racer without a multiplier shows only the exact step total with no empty separator. Effects, when present, occupy a second row beneath the name/score row; racers without effects have no blank second-row reservation and visibly shorter cards. Stealthed cards show the masked identity/rank arrangement with no multiplier or effect row. No card retains the old centered avatar → name → steps stack or empty right-side rail.

4. **Horizontal effect tray and tooltip — real screen**
   - **Get there:** Use a non-Stealthed racer seeded with at least five ordered effects, another with one effect, and another with none; scroll to their cards.
   - **Verify:** All effects occupy one icon-only horizontal row in backend order. The five-effect tray shows a clipped peek or edge affordance and can be swiped to reveal later icons without wrapping or growing into a third row. There is no vertical effect rail and no `+N` replacement. Tap the first and rightmost effects: one tooltip appears adjacent to the selected icon and remains fully within the screen; dismissing it leaves no duplicate tooltip behind.

5. **Narrow widths and text scaling — real screen**
   - **Get there:** Open the same seeded race in simulator/emulator widths **320, 375, 390, and 430 logical pixels**. Check once at text scale **1.0**, then repeat the 320px case at **1.3**.
   - **Verify:** At every width, the two lanes remain side by side within the scoreboard with no horizontal page overflow. Exact scores and multiplier chips remain present at the right edge while long names ellipsize first. Rank/avatar remains at left, the effect tray remains below the first row, and neither lane overlaps the other. At 1.3, cards may become taller, but text, hero content, and trays do not clip or move outside their owning lane.

6. **Night appearance and both platforms — real screen**
   - **Get there:** Go to **Profile → Settings → Appearance → Night**, reopen the seeded ACTIVE team race on one iOS device/simulator and one Android device/emulator.
   - **Verify:** The same legend → momentum → lanes order and hero → compact rows order remain intact in Night appearance. Both platforms keep the two lanes within the scoreboard, preserve the optional second effect row, and reveal later effects horizontally. Nothing reappears in the old separate hero band or right-side rail.

*Surfaces confirmed unaffected:* **Onboarding demo race** — `demo_race_host.dart` reuses the real `RaceDetailScreen`, but `DemoRaceEngine` supplies a solo ACTIVE race with no team fields, so the team-scoreboard branch is not reachable there.  
*Surfaces confirmed unaffected:* **Tab tutorial race-detail preview** — `tutorial_real_screens.dart` reuses `RaceDetailScreen`, but `tutorial_preview_data.dart` seeds a solo ACTIVE race; its `raceDetail.powerups` spotlight targets the separate POWERUPS section, not a team lane or racer tray.  
*Surfaces confirmed unaffected:* **Races-tab effect plates and inventory row** — their hand-forked widgets summarize race-level effects/inventory; this change is limited to per-racer effects inside the ACTIVE team scoreboard.  
*Surfaces confirmed unaffected:* **Solo/ranked standings, PENDING team lobby, and COMPLETED team results** — code routes these states around the scoped ACTIVE team-scoreboard branch.  
*Surfaces confirmed unaffected:* **Home and Races team-race cards** — they do not render `TeamScoreboardCards`, `_teamColumnCell`, or the per-racer team effect tray.  
*Surfaces confirmed unaffected:* **Case-opening screens** — they are pushed from race detail but do not render the scoreboard or team roster.

*Risks found while planning:* The demo and tab-tutorial fixtures are both solo races, so neither mirrored surface can manually expose regressions in the new team-lane branch; real-screen seeded staging data is the only current device path.  
*Risks found while planning:* The existing tutorial and demo spotlight keys are attached to the separate POWERUPS section, not the team scoreboard. Compacting the scoreboard changes that section’s vertical position in a future team fixture, but no spotlight key needs to move in the current solo fixtures.  
*Risks found while planning:* A useful manual fixture must explicitly include long names, null and meaningful multipliers, zero/one/five effects, Stealth, forfeit, and honest backend team totals; ordinary live race data may not expose every old-position regression.  
*Risks found while planning:* The existing per-racer effect rail and `+N` behavior are implemented directly in `race_detail_screen.dart`; removal must not accidentally alter the separate race-level active-effects summary below the scoreboard or the races-tab fork.

## Revision log

- **2026-08-11 — initial draft:** Recorded the agreed two-lane visual model,
  compact two-row racer card, icon-only horizontal effect tray, retained leader
  portraits, and whole-lane vibrant-versus-muted leadership treatment.
- **2026-08-11 — gap pass 1:** Added tie/unknown leadership states, required
  theme-aware color blending instead of whole-lane opacity, preserved semantic
  leadership, defined gesture arbitration between icon scrolling/tooltips and
  the friend-sheet tap, and added narrow-width/text-scale cases.
- **2026-08-11 — gap pass 2:** Made mixed-version reads explicit, preserved
  backend-total/Stealth correctness, specified removal of the obsolete fixed
  rail geometry, protected existing test intent while replacing the obsolete
  `+N` assertion, and documented unchanged iOS/Android and rollout behavior.
- **2026-08-11 — architect review:** Added an explicit 320px/1.3 responsive
  fallback, replaced the contradictory zero/one/five height contract, defined
  a three-state lane enum and removal of `IntrinsicHeight`, strengthened tray
  gesture isolation, carried defensive expiry/source data into tooltip copy,
  added mixed-version cases and stable keys, and recorded the required tutorial
  mirror audit.
- **2026-08-11 — UI-placement review:** Added the verbatim manual checklist,
  confirmed current demo/tutorial fixtures cannot enter the team branch, and
  required a deliberately seeded staging race to expose every placement state.
- **2026-08-11 — post-review gap pass 1:** Reconciled the normal two-row
  acceptance criterion with the architect-required narrow/accessibility
  fallback and confirmed the verbatim manual checklist still tests exact score
  preservation without prohibiting the fallback's additional line.
- **2026-08-11 — post-review gap pass 2:** Rechecked lane-state ownership,
  nullable-total behavior, viewport constraints, protected-test migrations,
  gesture boundaries, mixed-version effect parsing, mirrors, and rollout; no
  further unresolved product decisions remained.
- **2026-08-11 — simulator visual correction:** Rejected the continuous
  hero-plus-roster lane slabs, restored independent hero cards and the momentum
  strip above separate roster columns, required name/multiplier/exact steps to
  remain inline at every tested width, kept zero-effect cards shorter, and
  hardened effect overflow detection plus 44px tooltip targets.
