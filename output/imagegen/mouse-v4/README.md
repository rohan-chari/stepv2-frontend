# Mouse revision 4 — head motion and front-leg depth

Published CDN version `4278119fd764`; existing test-only Mouse item, Rohan ownership, price and placement metadata unchanged.

- `mouse-walk-preview.gif`: final six-pose loop on white.
- `corgi-mouse-comparison.gif`: corgi and revised mouse at the same 720 ms cycle.
- `mouse_walk_right.png`: final 576×96 RGBA sheet, six 96×96 poses.
- `mouse_walk_right.aseprite`: seven editable layers, six frames at 120 ms each.
- `mouse_walk_right_master24.aseprite`: full periodic animation master.
- `contact-sheet-final.png`: published poses for inspection.
- `prompts.txt`: built-in image generation prompts for separated head/torso/forelegs and neck cleanup.
- `assemble_animation.py`: generated-part compositing and periodic motion; creates no new drawn artwork.
- `animation-validation.json` / `compatibility-validation.json`: motion, frame, bounds and seam checks.
- `publication-verification.json`: live catalog/manifest and ownership checks.

The head now nods independently while the torso rises and pitches, informed by the bundled corgi animation. Darker, slimmer far foreleg sits behind the body; the fuller near leg overlaps the chest. The neck attachment is softly blended over opaque torso pixels. Six published poses retain compatibility with the existing fixed-six race/Home paths; all art is exported through Aseprite.

## Manual playback checklist

1. Reopen TestFlight → Shop → Characters → Mouse. Inspect all six poses for a connected neck, no double outline, and stable near/far foreleg overlap.
2. Watch five Home/Shop loops for the head nod, chest rise and smooth sixth-to-first transition. Check ears/tail stay within the frame.
3. Inspect a race card, race detail and Rohan's leaderboard row; verify front-leg depth still reads at small sizes. Check team board/podium where available. Repeat on both supported platforms where a test-channel build is available.
4. Demo race/tab fixtures omit Mouse; the wardrobe tutorial uses capybara and profile-photo avatars are separate. Those mirrors cannot validate this character revision. Device checks remain manual.
