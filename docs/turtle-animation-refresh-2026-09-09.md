# Turtle animation refresh — September 9, 2026

Replaced the bundled turtle walk sheet using the owner's `baraturtle.zip`,
frames `image0.png` through `image7.png` in numeric order. No artwork was drawn
or generated. `scripts/pack_turtle_frames.py` removes border-connected white,
applies one nearest-neighbor scale, centers each pose, and places the feet at
the existing y=69 ground line. Output remains eight 88×88 frames (704×88 RGBA).
An editable eight-frame Aseprite source and export entry were also installed
in the local art workspace; its export was verified pixel-identical.

## Published CDN and grant

- Backend asset commit: `cd46d1a`, pushed and published as a static-file update.
  No application restart, migration, or staging service start was needed.
- URL: https://steptracker-api.org/assets/characters/turtle@279671d5ad64.png
- SHA-256: `279671d5ad64a064877656247bb72d9f41748fbcea4f26790f614c863ca79225`.
- Public GET returned HTTP 200, `image/png`, and
  `public, max-age=31536000, immutable`; downloaded bytes match the repo file.
- Only after verifying the public PNG, the production admin API patched the
  existing turtle's `assetVersion` to `279671d5ad64`. Peer mirror returned OK.
  Existing eight-frame metadata, visibility, price, and placement were retained.
- Public `/assets/manifest` verified the new URL and `animationFrames: 8`.
- Exact display-name lookup uniquely identified Rohan. An idempotent ownership
  insert added the turtle; a transaction verified exactly one ownership row.
  No equip operation or coin mutation was performed.

## App compatibility and validation

The character resolver had remained bundled-first despite the app's existing
remote-art preference. It now uses current cached CDN character art, falls
back to the bundled species when unavailable, and preserves known frame counts
and baseline offsets when manifest metadata is absent. Unknown species retain
the existing capybara fallback. No new feature flag or API requirement.

Frozen binaries retain their compiled walking renderer and therefore still
use their old bundled turtle. CDN-backed shop thumbnails can update separately.
The walking-animation change requires a carrying app update. Shared Dart and
bundled assets cover both iOS and Android; no app build or upload was performed.

Two new regressions were observed failing before their corresponding fixes:
cached turtle art ignored, and omitted geometry incorrectly cropping six frames.
Final verification: 31 tests passed across `remote_asset_rendering_test.dart`
and `turtle_character_test.dart`; `flutter analyze --no-pub` clean. Independent
code review approved the final fix. Full Flutter suite and device checks were
not run for this asset/resolver update.

## Manual placement checklist (iOS and Android)

Repeat key checks online after a fresh launch and offline after download.

1. **Shop / Inventory → Characters:** select Turtle. Check one clean character
   in each tile and preview, with no adjacent-frame bleed or clipping; equip it.
2. **Accessory previews:** check head, face, neck, back, and feet items through
   the walk cycle. Confirm attachment points still fit the changed anatomy.
3. **Home:** feet meet the ground; character and accessories remain clear of
   the HUD throughout the animation.
4. **Individual race containing Rohan:** check lane containment, shadow/feet,
   accessories, and participant thumbnail.
5. **Team race with a turtle-equipped top scorer:** check hero-card containment,
   grass/feet and shadow alignment, and accessory placement.
6. **Shell icons:** inspect both Races inventory/effect rows and race-detail
   power-up inventory/details. Each icon must show exactly one turtle frame.
7. **Shop tutorial:** verify character previews where present and that spotlight
   targets remain aligned.
8. **Tab tutorial / demo race:** verify fixture characters remain correctly
   placed. Existing Home/demo fixtures do not inherit Rohan's equipped turtle;
   inspected race fixtures use capybara/corgi, so these are regression checks,
   not proof of turtle placement. A turtle fixture is needed for turtle-specific
   tutorial coverage.

Matching sheet geometry does not prove accessory fit: the supplied poses have
different head/leg positions, so the manual accessory check remains necessary.
