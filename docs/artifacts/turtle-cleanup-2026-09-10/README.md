# Turtle cleanup evidence

The original bundled/source/public immutable sheet had90opaque pale residue
pixels. Aseprite copied adjacent original outline colors over exactly those
pixels. All alpha and all other pixels are unchanged; the eight88x88frames and
80ms source timing remain intact. See `scripts/clean_turtle_fringe.lua` and
`python3 scripts/verify_turtle_cleanup.py` from repository root.

`after-backgrounds.png` displays every frame on white, black, navy and green.
The four light/dark bare/cowboy captures use the real `HomeCourseTrack` and
`CapybaraSpriteWithAccessories` widgets. The latter explicitly displays all eight
frames. The cowboy transform is the current catalog's art-only metadata obtained
with a bounded read-only query; no account data was read. The track fixture is
not a full Home-screen recreation. It demonstrates existing widget placement
and sprite rendering. Runtime device placement still uses the spec checklist.

The archived capture harness loads bundled fonts, waits for actual decoded
images, and advances the track-entry animation before capture. To reproduce,
copy it temporarily to `test/_capture_turtle_cleanup_test.dart`, run that one
Flutter test, then remove the temporary file. Final run passed; the seven existing
turtle widget tests also passed. Initial capture infrastructure required explicit
font loading and image-decode waits; no product code was changed for capture.

Native source is updated in the local art workspace. The prior source is backed
up there. New immutable backend PNG is prepared but not yet published:
`turtle@a87ad177f0a0.png`. The live manifest still advertises `f3410027eade`.
