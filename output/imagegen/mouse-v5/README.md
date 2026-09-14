# Whole-body mouse revision

Built-in imagegen generated six complete connected mouse poses, using the bundled corgi and capybara sheets as style references. No articulated part rig is used. Full prompt: `prompt.txt`.

Background extraction attempts produced a glow then an opaque checkerboard. A subsequent built-in edit replaced only the background with solid #00FF00, followed by chroma removal. Frames were cropped, uniformly scaled with nearest-neighbor sampling, and aligned at their right edge and foot baseline. No body parts were separately transformed.

Deliverables: `mouse_walk_right.png` (576×96, six frames), `mouse_thumb.png`, `mouse-walk-preview.gif` (120ms/frame), `contact-sheet.png`, and editable Aseprite source.

Published at user request on 2026-09-14: `https://steptracker-api.org/assets/characters/mouse@172584a0659a.png`. Public CDN bytes and TestFlight manifest verified; admin PATCH changed only assetVersion, with successful peer mirroring. Other catalog fields, six-frame geometry, baseline and test-only/remote-only policy are unchanged. Asset-only backend commit: `e7e8c1c`; file copied directly to the production static directory without an application restart. No Dart or backend logic changes; app analysis/tests were not run for this asset publication. Device playback remains a manual check.

Review the GIF for coherent anatomy, planted paws, stable scale, and the last-to-first transition. After publication, check Home, Shop, race detail and leaderboard at actual size on both platforms; existing demo fixtures do not contain Mouse.
