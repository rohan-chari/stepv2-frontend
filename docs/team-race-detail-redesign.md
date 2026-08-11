# Spec — Team Race detail redesign (scoreboard section)

Status: **implemented** · 2026-08-10 · frontend-only, no backend change

Revised after architect review (10 required items) — the sections below record
what was BUILT, not the first draft. Material corrections are called out inline
as **[rev]**.

## Goal

Rebuild the ACTIVE team-race scoreboard to match the reference mock: two big
head-to-head **team cards** with a LEADING ribbon and a character portrait, a
**momentum banner** ("X steps ahead"), and restyled **roster columns** with
per-member progress bars.

Per direction: the mock's two AI-generated scenic illustrations are **not**
reproduced. Each team card shows that team's **current leading member's
capybara/character portrait**, in the same sprite style already used in the
roster cells.

## Scope

Touches only the ACTIVE branch's SCOREBOARD section of
`lib/screens/race_detail_screen.dart:4541-4578` and the widgets it composes.

**In scope**
- Replace the `TeamH2HBanner` **class** with a new `TeamScoreboardCards` in
  `lib/widgets/team_scoreboard_cards.dart`. **[rev] The file
  `team_h2h_banner.dart` survives**, carrying `TeamTugRope`, which
  `lib/widgets/team_scoreline.dart:5` still imports for the race-list and Home
  rows (explicitly out of scope).
- New `TeamLeadBanner` (momentum strip).
- ~~Restyle roster cells `_teamColumnCell`~~ — **[rev2] dropped, see §4.**
  The cells are untouched; only the shared min-height constant's *comment* is
  updated to record what the floor has to absorb.
- **[rev] Do NOT wire `TeamRace.leadingTeam`** (`lib/utils/team_race.dart:225-230`).
  It sums via `teamTotal`, which coerces a stealthed member's null steps to 0,
  while the cards render `_teamTotalFromProgress` (the backend's honest `teams`
  block). The two disagree exactly when stealth is live, so the ribbon could
  crown the card showing the SMALLER number. The ribbon and the banner are both
  derived from the same `int?` pair the cards display. `leadingTeam` stays
  unused (it is covered by `test/team_race_util_test.dart:119-125`, so it is
  not dead code — leaving it uncalled is the correct outcome).
- Fix the already-failing `test/team_h2h_banner_test.dart` (3 of 4 tests fail
  on the current tree — it still asserts a tug rope, `ALL TIED`, and a
  `SWIFT CAPYS LEAD +440` pill that were removed in an earlier pass).

**Out of scope (unchanged)**
- ~~The race hero / goal track~~ — **[rev3] the course is now REMOVED for team
  races.** See "Course removal" below. Solo/ranked races keep it untouched.
- PENDING lobby (`TeamLobbyBoard`), COMPLETED standings
  (`_buildTeamGroupedRows`), forfeit pill, powerups, activity/chat.
- `TeamScoreline` / `TeamFormatChip` (race list + home rows).
- Backend, API shape, data model.

## Layout — new vertical order inside SCOREBOARD

```
_checkerSectionHeader('SCOREBOARD')            (unchanged)
_sectionCard(padding: 14)
  ├─ TeamVsChips           ← new, small: ●TeamA  vs  ●TeamB
  ├─ TeamScoreboardCards   ← new, replaces TeamH2HBanner
  ├─ TeamLeadBanner        ← new
  └─ _buildTeamTwoColumns  ← [rev2] UNCHANGED
```

### 1. `TeamVsChips`
Two pill chips with a team-color dot and the team name, split by a small `vs`
medallion. Mirrors the mock's sub-title row and gives the color→team legend
that the card grid relies on. `PixelText.title(size: 12)`, chip fill
`parchmentLight`, border `colorDark` @ 1.5px, dot 8px in `TeamRace.color`.

### 2. `TeamScoreboardCards` (new file `lib/widgets/team_scoreboard_cards.dart`)

`Row[Expanded(card A), SizedBox(width: 10), Expanded(card B)]`.

Each card, top→bottom:

| element | spec |
|---|---|
| ~~LEADING ribbon~~ | **[rev4] CUT — replaced by an OUTLINE on the card.** The strip was a real row, so it had to be reserved on the trailing card too (`Visibility(maintainSize)`), which left a visibly empty band above the loser's portrait. The crown is now a halo drawn *outside* the card box (`BoxShadow` spread 3, no blur/offset) plus the team-coloured border — costing zero layout, so nothing needs reserving and nothing can misalign. The word "LEADING" is gone from the screen, so the leading card carries `Semantics(label: '<team> leading')` and a `team-leading-<side>` key to keep it announced and assertable. Historical note: **[rev] the strip was RESERVED on both cards** — visible on the leader, `Visibility(maintainSize: true)` on the trailer. Rendering it only on the leader pushed that card's portrait/total/bar ~21pt down, so the two 30pt totals stopped sharing a baseline; `IntrinsicHeight` equalizes the outer boxes only and cannot fix that. Fill `TeamRace.colorDark`, `star_rounded` + `PixelText.title(size: 11, textLight)`. Hidden on both when tied AND whenever either total is null. |
| portrait panel | height 108. Fill `colorLight` @ 0.28, bottom hairline `colorDark` @ 0.35. Centers `CapybaraSpriteWithAccessories(capybaraSize: 76, frameIndex: 0)` for that team's **top-scoring member**, with the member's `accessories` + `animal`. Empty team → a centred "No one yet", matching the roster column's own empty state. **[rev]** A stealthed member is skipped when picking the top scorer: their sprite and name are hidden on their own plank, so picturing them would leak both. The team TOTAL under the portrait stays honest either way. |
| portrait caption | `@username` of the pictured member, `PixelText.body(size: 10.5, textMid)`, ellipsised. Needed because the mock's illustration was team-generic and a portrait is not. |
| team name | `PixelText.title(size: 15)`, color `TeamRace.textColorOn(team, context)`, max 2 lines. |
| total | `PixelText.number(size: 30)`, `TeamRace.textColorOn(team, context)`, thousands-separated. **Nullable** — renders `—` when a stealthed member makes the total unknowable (carried over from `TeamH2HBanner:27-32`). |
| `TEAM STEPS` | `PixelText.body(size: 10, textMid)`, letter-spaced. |
| ~~progress bar~~ | **[rev2] CUT.** Built, then removed on review of the running build — the bars read as loading spinners under the totals, and the ratio they encoded is already legible from the two numbers side by side plus the LEADING ribbon. No bar on the cards and none in the roster cells (§4). |

Card chrome: fill `colorLight` @ 0.20 (leading) / `parchmentLight` (trailing),
radius 12, hard `BoxShadow(colorDark, offset (0,3))` on the leading card only —
so the leader reads as physically raised, not just tinted.

**[rev] Border width is 2.5 on BOTH cards**, differing only in colour
(`colorDark` vs `parchmentBorder`). The draft's 2.5-vs-1.5 inset the leader's
content by 1px and knocked the two totals off a shared baseline — caught by
`test/team_scoreboard_cards_test.dart`'s baseline assertion. The leader is
distinguished by border colour, fill tint and shadow: none of which move pixels.

**Progress-bar denominator** — *moot after [rev2] cut the bars; retained as the
record of why a target-based denominator was rejected.* **[rev] ratio-to-leader
ONLY**:
`teamTotal / max(teamATotal, teamBTotal)`, so the leader's bar is full and the
trailer's is the honest ratio. This is what the mock shows. The first draft's
"step target" branch is deleted: `race_detail_screen.dart:4339-4340` records
that target-steps races are gone and `targetSteps` is a compat field
"deliberately ignored" — reviving it as a live UI driver would let a legacy row
render bars contradicting the rest of the screen. Either total null (stealth),
or both totals zero → no fill, empty track (never a NaN `widthFactor`).

**Equal heights:** the two cards must match height regardless of name wrap.
Use `IntrinsicHeight` over the `Row` with both children `CrossAxisAlignment.stretch`.

### 3. `TeamLeadBanner` (same new file)

Full-width strip under the cards. `📣` + copy + `SizedBox(height: 14)` after.

| state | copy | color |
|---|---|---|
| viewer's team leads | `Keep it up! **{diff}** steps ahead!` | viewer team's `colorLight` @ 0.22 fill, `colorDark` border |
| viewer's team trails | `Push! **{diff}** steps behind.` | other team's tint |
| tied | `Dead even — **{total}** steps each.` | `parchmentLight`, `parchmentBorder` |
| spectator | `**{leadName}** leads by **{diff}**.` | leading team's tint |
| either total null | banner hidden entirely | — |

Diff number in `PixelText.number(size: 15, textColorOn(leadingTeam))`, rest in
`PixelText.body(size: 12.5, textDark)`. **[rev]** The leader is derived from the
same `int?` totals the cards render — never `TeamRace.leadingTeam`.

**[rev] The banner owns its own bottom gap** (`margin: bottom 14`) rather than
the caller adding a `SizedBox` after it. When the banner hides itself on
unknown totals, a caller-owned spacer would survive as a stray 14pt hole
between the cards and the rosters.

**[rev] Viewer-team source:** `_myTeam(participants)` returns null both for a
spectator and for a participant whose `team` field doesn't parse
(`parseRaceTeam` returns null by design). Both get the neutral third-person
copy.

### 4. Roster cell restyle — `_teamColumnCell`

**[rev] The mock's horizontal row does not fit and was not built.** On a 375pt
device the cell's content box is ~106pt wide after the screen padding, the
`_sectionCard` padding, the column gutter, the cell padding and the reserved
34pt effect rail. The mock's `avatar 32 + @name + steps` row needs ~50pt for
"6,200" and ~38pt for the avatar, leaving ~15pt of name — every row would read
`@T…`, worse on a 320pt SE, and the multiplier chip still has to fit. The
existing centred vertical stack (avatar → name + chip → steps) is retained.

**[rev] The avatar is NOT swapped to a 32px ringed `RacerAvatar`.** That widget
renders `capybaraSize: size - 12` inside a `ClipOval`; at size 32 it would be a
20px circularly-cropped sprite, clipping away the hats and accessories that the
current un-clipped 46px sprite shows, and the retained 21×21 rank shield would
cover ~43% of the circle. The 46px sprite and corner shield are unchanged.

**[rev2] The per-member progress bar was built, then cut on review of the
running build** — like the card bars, they read as loading spinners rather than
progress, under a sprite that already carries a rank shield and a step count. **The roster
cells are therefore UNCHANGED by this redesign.** The `@` prefix was already
there (`atName`, `:7574`) and was not re-added.

The bar's brief life is worth recording, because it moved a shared constant:
it added 12pt to every non-stealthed cell, pushing content from 92.25 to
104.25 against a `_kTeamCellContentMinHeight` of 104 — so the floor stopped
absorbing anything and two dormant variance sources became visible (a stealthed
cell drew no bar; a frozen racer's icon-only multiplier chip makes its name row
23pt instead of 20.25pt). The floor was raised to 116, then returned to 104
when the bar was cut. **The equal-height guard added for it was kept** — see
Tests.

**Preserved, non-negotiable:** `_kTeamCellContentMinHeight` is **104**
(the rail's overflow math is `floor(available / 32)` and
`race_detail_team_effect_rail_test.dart` asserts exactly `+3` for 5 effects,
true only while the height is 96–127), the 34px rail, `???` stealth masking,
forfeit `Opacity(0.5)`, multiplier chip, `ValueKey('team-cell-$userId')`, and
the tap → `showFriendRequestSheet` affordance. `_teamColumnCell` is NOT
extracted to a top-level widget — it closes over `_effectDataFor`, `_myUserId`,
`_api` and `widget.authService`, and extracting it is the one refactor that
could plausibly drop the rail invariant.

## [rev3] Course removal (team races only)

`_buildRaceHero` gains `showCourse`. For an ACTIVE team race it renders the HUD
chips (ENDS IN, PRIZE POOL) on the parchment and drops the ~286pt
`HomeCourseTrack` entirely. Only two capys ever ran on that course — one leader
per side — so it spent a screenful saying less than the scoreboard cards
directly beneath it.

**This retires TR-804** (team glow/pennant chrome on course capys). That is a
genuine feature removal, not a refactor: the ACTIVE runner list was
`teamColor`'s only producer anywhere in the screen, and the PENDING and
COMPLETED heroes never set it. `_twoTeamLeaders` went with it — it had exactly
one call site. The corresponding assertion in
`test/race_detail_team_active_test.dart` was replaced with "an ACTIVE team race
renders no course at all" plus a check that the HUD chips survive; it was not
weakened, its premise no longer exists.

PENDING (lobby start-line) and COMPLETED (final positions) heroes still render
their courses for team races — only the ACTIVE branch changed.

## [rev3] Card sizing and ground

- The team tint is the **whole card's** background (`colorLight` @ 0.30
  leading / 0.18 trailing), not a band behind the portrait. The portrait panel
  therefore carries no fill of its own — a second wash there banded the card in
  two shades.
- Portrait panel 108 → **148** tall, sprite 76 → **108**, caption 10.5 → 11.5.
  With the course gone there is room to make the character the hero of the card.

## Mirrors

**None.** `TeamRace.isTeamRace` requires `race['isTeamRace'] == true`; the demo
race payload never sets it (`lib/demo/`) and `lib/tutorial/` contains no team
race at all, so both tutorial mirrors take the solo STANDINGS branch and cannot
render this section. The only tutorial spotlight anchors on this screen
(`tutorialClockKey :3362`, `tutorialPowerupsKey :5614`) sit outside the
scoreboard, so its height change cannot shift them.

## Things in the mock deliberately not built

| mock element | why not |
|---|---|
| dark-green quote strip ("Every step counts…") | no such copy source; the powerup helper already occupies that slot |
| "Step data is synced from Apple Health" footer | this repo ships Android/Health Connect too; a hardcoded Apple string would be wrong on Android |
| scenic hills background behind the hero | our hero already has themed sky/ground art via `AppThemeAssets` |
| generated team illustrations | replaced by leading-member portraits, per direction |

## Compat & theming

- **Frontend-only.** No new API fields; every value already comes from the
  participants list the screen holds. Nothing here can break older clients.
- **Night mode:** all team color used as *text* must go through
  `TeamRace.textColorOn(team, context)` — raw `colorDark` is 1.09:1 on the
  night parchment. All fills/borders through `TeamRace.color*(team, context)`,
  never the bare constants.
- **Stealth:** totals are `int?` end-to-end; every derived value (bars, diff,
  banner) must tolerate null rather than defaulting to 0.

## Tests

- `test/team_h2h_banner_test.dart` → `test/team_scoreboard_cards_test.dart`
  (14 tests): ribbon on the higher total only, absent when tied or when a
  total is null, `—` on null totals, equal card heights on a wrapping name,
  shared total baseline, all four banner copy states, banner self-hiding, and
  `topScorerOf` incl. its stealth skip.
- **[rev] `test/team_scoreline_test.dart` is NEW and carries the two rope
  assertions** ("knot slides toward the leading side", "tie centers the knot")
  out of the deleted banner test. `TeamTugRope` is still live in
  `TeamScoreline`, and there was no scoreline test file, so deleting them
  would have dropped real coverage. Only the `ALL TIED` and
  `SWIFT CAPYS LEAD +440` assertions are genuinely obsolete — those strings no
  longer exist in `lib/` and had been failing on the tree already.
- **[rev] `test/batch_2026_07_26_dark_mode_contrast_test.dart:168-199` is a
  protected P1 night-contrast guard** that pumped `TeamH2HBanner`. Ported to
  `TeamScoreboardCards` with its assertions byte-for-byte unchanged.
- New `test/race_detail_team_scoreboard_test.dart` (9 tests, integration —
  pumps the real screen, per CLAUDE.md): cards/chips/banner render on an ACTIVE
  team race; the ribbon follows the BACKEND team block rather than the visible
  plank sum; the portrait is the top scorer (and skips a stealthed one); banner
  copy flips lead/trail/spectator/tie; and the dash + no-ribbon + no-banner
  degradation when a total is unknowable.
- **[rev2] `test/race_detail_team_effect_rail_test.dart`'s equal-height case
  gained a frozen-chip cell and a stealthed cell.** The guard named an
  invariant it wasn't actually testing: every cell it compared had identical
  content, so only the *rail* was under test. Verified falsifiable — at a
  104 floor with the progress bar present, the frozen cell measured 130 against
  a 127 baseline. Kept after the bar was cut, since the variance sources are
  permanent features of the cell.
- `test/race_detail_team_active_test.dart` (5 tests) references
  `TeamH2HBanner` by type — mechanical update to the new widget, assertions
  unchanged.
- `race_detail_team_effect_rail_test.dart` (5 tests) must stay green untouched
  — it is the guard that the restyle didn't drop the effect rail.

## Rollout

No flag. Pure presentation change on a screen that already ships; a bad render
is visible in the manual checklist before release.
