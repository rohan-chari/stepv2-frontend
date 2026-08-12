# Team race hero scenes — requirements

Status: **approved and implemented** · 2026-08-11 · frontend-only

## Summary and user story

The ACTIVE team-race hero cards currently place each leading racer on a flat
team-tinted field. The information hierarchy is correct, but the upper cards
lack the illustrated sense of place and celebration shown in the visual
reference.

As a team-race participant, I want each team leader to appear inside a small,
festive race scene so the matchup feels like an event rather than a pair of
stat cards, without making names or scores harder to read.

The approved direction is a **shared grassy platformer course viewed through
two card windows**: both hero cards reuse the bundled themed panorama, but use
different horizontal alignments so they do not look duplicated. The leader
sprite stays in the foreground, and a restrained team-tint wash ties the scene
back to the gold/green matchup. The existing course already includes sky,
clouds, flags, grass, and pixel terrain; no new artwork is required.

## Scope

### In scope

- The 148px illustrated leader area of `TeamScoreboardCards` on the ACTIVE
  team-race scoreboard.
- Reuse of `AppThemeAssets.homeCourse` so light and night appearances select
  the existing matching grassy-platformer PNG automatically.
- A soft readability/tint overlay and deliberate left/right panorama crops.
- Responsive crops and leader positioning on narrow and normal phones.
- Real-screen widget coverage and manual placement checks on iOS and Android.

### Non-goals

- No new/generated images, CustomPainter scenery, SVGs, or asset catalog work.
- No changes to team totals, leadership, scoring, effects, roster cards, or
  backend payloads.
- No progress bars, `LEADING` ribbons, or continuous team-column backgrounds.
- No animated course or clouds in this pass; the hero scene remains static to
  avoid visual noise and unnecessary work while scrolling.
- No changes to the solo standings branch, completed results, Home race cards,
  or Races-tab cards.

## API contract

No endpoint, request, response, or backend behavior changes. The scene uses
only local assets and existing participant data already rendered by the hero
card. Older app versions and newer/older backend payloads are unaffected.

## Data model and migrations

None. No local persistence, database table, field, migration, or backfill.

## Visual and interaction specification

### Scene composition

Replace the flat content behind the leader sprite with a clipped `Stack`:

1. `Image.asset(AppThemeAssets.of(context).homeCourse)` fills the full 148px
   hero area with `BoxFit.cover` and `FilterQuality.none` to preserve the pixel
   artwork.
2. Team A and Team B use different `Alignment` values along the panorama so
   their crops feel like neighboring parts of one course, not duplicate cards.
   Start with `Alignment(-0.55, 0)` for Team A and `Alignment(0.55, 0)` for
   Team B; tune only if the real 320px crop obscures a leader or loses terrain.
3. A full-viewport `AppColors.of(context).parchmentLight` wash uses opacity
   `0.24` in light mode and `0.14` in dark mode. Above it, the team-light color
   uses opacity `0.10` in light mode and `0.08` in dark mode. Team B must not
   return to a broad dark-green field.
4. The capybara/accessories render above the washes at the current 108px visual
   size, centered horizontally and anchored 8px above the bottom of the scene
   so its feet meet the grassy terrain rather than floating in the sky. On a
   narrow scene, only a transformed behind-body accessory that would otherwise
   clip may scale the complete sprite down enough to keep the artwork bounded.
5. The existing `atName(leader.displayName)` caption sits 6px from the top of
   the scene, above the sprite; no new username/backend field is introduced. It always
   receives a rounded local scrim using `AppColors.of(context).parchment` at
   `0.92` opacity and `textDark`, targeting at least 4.5:1 contrast. The scrim
   hugs the text rather than spanning the scene.

The lower team-name/total area remains a calm solid surface. Gold outlines and
glow continue to identify whichever team leads.

### Theme behavior

- Light mode selects `assets/images/home_race_course_platformer.png`.
- Night mode selects `assets/images/home_race_course_platformer_night.png`.
- The overlay resolves from `AppColors.of(context)` and must preserve readable
  leader captions in both themes.
- Missing asset behavior follows Flutter's bundled-asset contract; no network
  image or runtime backend field is introduced.

### Responsive behavior

- Keep both hero cards the same height at every supported width.
- The scene must cover the hero viewport without distortion, letterboxing, or
  overflow at 320, 375, 390, and 430 logical pixels.
- The avatar remains fully inside its clipped card and must not obscure the
  team name or total below.
- Long display names retain one-line ellipsis behavior.

### Accessibility and motion

- The background scene is decorative and excluded from semantics.
- Existing leader/avatar/name semantics remain authoritative.
- No new gesture or animation is added, so reduced-motion behavior is
  unchanged.

## Frontend implementation plan

1. In `lib/widgets/team_scoreboard_cards.dart`, extract a private hero-scene
   widget/helper receiving team, leader, lane state, and the card palette.
2. Compose the themed `homeCourse` image, overlays, avatar, and caption in a
   clipped stack without changing `TeamScoreboardCards`' public API.
3. Use the same theme-selected `AssetImage` provider for both cards and rely on
   Flutter's image cache. Do not eagerly precache either or both theme variants;
   a cold deep link may not have visited Home, and first-frame decode should be
   measured before adding cache sizing or lifecycle work.
4. Preserve null-leader behavior (`No one yet`) on a calm scene, defensive
   accessory/animal data, equal card geometry, gold leading treatment, and all
   current score formatting.
5. Update the real-screen widget tests first, then implement production code.

Both iOS and Android render the same Flutter composition and themed local PNG;
no platform fork is permitted.

## Backward compatibility and rollout

This is a local frontend-only presentation change using PNGs already bundled
in shipped project assets. The backend deploy order is irrelevant because the
API is untouched. Frozen older clients keep their flat hero cards; the new
client continues to tolerate missing/null team totals, leaders, accessories,
animals, and placements exactly as today.

## Tests-first plan

Before production edits:

1. Pump the real ACTIVE team-race screen and assert both hero areas contain the
   theme-selected course asset.
2. Assert Team A and Team B scenes use distinct horizontal alignments.
3. Pump night mode and assert the night course asset replaces the day asset.
4. Assert the decorative scene is excluded from semantics while leader names
   remain available.
5. Assert hero cards retain equal dimensions at 320/375/390/430 widths and no
   render exceptions occur.
6. Pump missing/empty participant data and assert both local course scenes
   still render, `No one yet` stays visible, and no new backend field is read.
7. Pump a long display name and assert the `atName(...)` caption remains one
   ellipsized line within the hero scene and does not overlap the lower summary.
8. Pump night mode with `AppThemeData.night()` (not a fallback-only theme) and
   verify the night `homeCourse` asset and caption treatment.
9. Preserve all existing leadership, gold outline, null-total, stealth,
   portrait-selection, roster, and effect-rail assertions.

## Acceptance criteria and definition of done

- The two leader areas visibly read as illustrated race scenes, not flat fills.
- The two crops feel related but not duplicated.
- Clouds/course celebration are visible without competing with the capybara.
- Day and night use their matching bundled course assets.
- Team B remains a subtle accent rather than a dark-green block.
- Names, team names, totals, and `TEAM STEPS` remain readable.
- No new assets, API dependencies, progress bars, ribbons, or animations.
- New real-screen tests fail first and then pass; existing tests remain intact.
- Scoped and repository-required analysis/testing are reported honestly.
- iOS and Android builds pass, the UI-placement checklist is delivered, and
  code review returns no blockers.

## Open design decisions

No open design decisions remain. The user approved the grassy platformer
panorama, a static scene, and the leader caption above the grounded avatar
inside the scene.

## Manual UI-placement test plan

### Elements under test

- The flat upper 148px area of both ACTIVE team-race scoreboard cards is
  replaced by a clipped grassy-platformer scene; Team A uses the left panorama
  crop and Team B uses a distinct right crop.
- Each leader sprite, equipped animal/accessories, and one-line username remain
  inside the illustrated scene above the unchanged team-name, total, and
  `TEAM STEPS` area.
- The empty-team `No one yet` state remains inside the illustrated scene instead
  of the old flat field.

### Checklist

1. **ACTIVE team-race detail — normal phone, light mode, Team A ahead**
   - **Get there:** On a 375–390pt iOS or Android phone, go to Profile →
     Settings → Appearance → LIGHT, then Races → open an ACTIVE team race seeded
     with both teams populated, Team A ahead, and equipped accessories on at
     least one displayed leader; scroll to SCOREBOARD.
   - **Verify:** Both upper card areas show static grassy-platformer scenes;
     Team A shows the deliberate left crop and Team B a visibly different right
     crop. Both scenes fully cover their equal-height windows with no
     letterboxing, stretching, overflow, or square corners outside the card
     clip. Each sprite and its accessories are fully inside its own scene, with
     the username in a nameplate above it. Confirm neither upper area retains the
     old flat team-colored field or duplicates the other crop. Confirm the team
     names, totals, and `TEAM STEPS` remain below the scene in their existing
     aligned positions and are not obscured.

2. **ACTIVE team-race detail — normal phone, dark mode, Team B ahead**
   - **Get there:** Profile → Settings → Appearance → DARK, then Races → open an
     ACTIVE team race seeded with Team B ahead; scroll to SCOREBOARD.
   - **Verify:** Both cards use the night grassy-platformer scene in the same
     upper windows, with distinct left/right crops and no daytime image
     remaining. The Team B scene is a lightly accented panorama, not the old
     broad dark-green field. Team B's leading outline/glow surrounds its whole
     card without moving or clipping its scene; Team A's card has no duplicate
     leading treatment. Sprites and usernames remain within the scene and the
     unchanged lower stats stay aligned beneath it.

3. **ACTIVE team-race detail — narrow phone and long leader name**
   - **Get there:** On a 320pt-wide device or simulator, use an ACTIVE team race
     whose displayed leader has a long username and a large/wide accessory or
     non-default animal; check once in LIGHT and once in DARK.
   - **Verify:** The two cards remain side by side and equal in height. Both
     images cover their 148px viewports without gaps, distortion, horizontal
     overflow, or leaking beyond rounded corners. The avatar, animal, and every
     accessory remain fully inside the clipped card and do not overlap the team
     name or total below. The long username stays on one line with an ellipsis
     inside its own scene; it does not wrap, escape the card, or appear again in
     the former flat layout.

4. **ACTIVE team-race detail — widest supported phone and opposite leader
   treatment**
   - **Get there:** On a 430pt-wide device, open populated ACTIVE team races
     with Team A ahead and Team B ahead, or use staging fixtures exposing both
     score states.
   - **Verify:** At the wider width, each scene still fills its window and the
     left/right panorama crops remain intentionally different rather than
     converging on the same center crop. The correct team's leader remains
     centered within its own scene and the gold leading treatment does not
     change scene height, lower-stat placement, or card-to-card alignment. No
     old flat hero field appears in either score state.

5. **ACTIVE team-race detail — null leader**
   - **Get there:** On staging, open an ACTIVE team race with one empty team, or
     with no non-stealthed participant available for one side; scroll to
     SCOREBOARD.
   - **Verify:** The empty side still has the same illustrated 148px scene and
     shows `No one yet` within that scene. It must not collapse, revert to the
     old flat fill, leave a blank hole, or duplicate a sprite from the other
     team. Both cards and all lower stats remain aligned and equal in height.

6. **Cross-platform placement parity**
   - **Get there:** Repeat checkpoint 1 on one iOS device and one Android device
     at comparable normal widths.
   - **Verify:** Both platforms place the course crop, overlays, sprite,
     username, and lower stats in the same order and within the same clipped
     bounds; neither platform shows overflow, letterboxing, or an element left
     in the old flat-field position.

### Mirrored-surface audit

- Demo race tutorial (`DemoRaceHost`, `demo_race_api_service.dart`,
  `demo_race_engine.dart`, and `demo_auth_service.dart`) uses a solo race and
  never reaches `TeamScoreboardCards`; no code change is required.
- The tab tutorial race-detail preview (`tutorial_preview_data.dart` and
  `tutorial_real_screens.dart`) also seeds a solo ACTIVE race without team
  assignments; no code change is required.
- No tutorial spotlight key is attached to or adjacent to
  `TeamScoreboardCards`; no spotlight anchor moves.
- PENDING team detail uses the lobby board and COMPLETED team detail uses the
  results presentation; neither instantiates this widget.
- Solo ACTIVE race detail, Home/Races cards, solo standings, and tournament
  surfaces do not reference `TeamScoreboardCards` and remain unchanged.

### Risks found while planning

- Demo and tutorial fixtures are explicitly solo, so this team-only placement
  receives no tutorial visual coverage. A future team-race tutorial would
  inherit the real widget automatically.
- Both crops must remain explicitly different and responsive; a shared
  `Alignment.center` would look duplicated at 320pt and 430pt.
- The existing card-level `ClipRRect` must contain the image and overlays
  entirely within the 148px upper area so they never tint the lower summary.

## Revision log

- **Initial draft:** Scoped the enhancement to the existing hero viewport and
  selected bundled themed assets rather than introducing new artwork.
- **Gap pass 1:** Added null-leader, long-name, narrow-width, semantics, and
  explicit Team B dark-surface safeguards.
- **Gap pass 2:** Made the image decorative, ruled out motion for this pass,
  locked iOS/Android parity, and added explicit tests for theme asset switching
  and distinct panorama crops.
- **User interview:** Selected `home_race_course_platformer` over the stadium
  panorama and approved both the static treatment and in-scene leader caption.
- **Architect review:** Locked `homeCourse`, exact crop alignments,
  `FilterQuality.none`, overlay/scrim tokens and opacity, `atName` compatibility,
  cold-start image-cache behavior, explicit empty/long-name/night tests, and
  the demo/tutorial audit.
- **UI-placement review:** Added the required six-scenario manual checklist and
  recorded every mirrored surface plus the lack of team tutorial fixtures.
