# Mouse — attached tail wave

Built-in imagegen edited the six complete mouse poses from revision 5. The prompt preserves the approved body design and requests a larger up/down tail wave with changing curvature and a connected root. No isolated tail was generated or separately animated.

`prompt.txt` records the exact prompt. `assemble.py` removes the green background and packs whole poses at a common scale and foot baseline. `mouse_walk_right.png` is six 96×96 frames; `mouse-walk-preview.gif` plays at 120 ms/frame. `mouse_walk_right.aseprite` retains complete editable frames.

Checked the white contact sheet, distinct frames, transparent borders, and unchanged 78-pixel foot boundary. Published at user request on 2026-09-14: `https://steptracker-api.org/assets/characters/mouse@43753919ad60.png`. Public bytes and TestFlight manifest verified. Admin PATCH changed only assetVersion; peer mirroring succeeded, with other catalog fields and test-only/remote-only policy preserved. Asset-only backend commit: `55fa97f`; copied to the production static directory without restarting services. No app code changed; no app builds or tests run. Device playback remains a manual check.
