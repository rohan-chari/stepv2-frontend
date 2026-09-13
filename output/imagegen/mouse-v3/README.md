# Mouse revision 3 — pixel texture, body motion and complete loop

Published version `8e0f2159b0db`, same test-only Mouse item and existing Rohan ownership.

- `mouse_walk_right.png`: final 576×96 sheet, six complete-cycle poses.
- `mouse_walk_right.aseprite`: six editable generated-art layers, six frames, 120 ms/frame for the standard 720 ms preview.
- `mouse-walk-preview.gif`: final published animation on white.
- `contact-sheet-final.png`: final six poses.
- `mouse_walk_right_master24.aseprite` / `.png`: retained full 24-frame animation master.
- `assemble_animation.py`: periodic composition of generated parts; writes the master and source layers. Requires Pillow and NumPy. Creates no drawn artwork.
- `import_layers.lua`: imports the 24-frame master; `import_six_layers.lua` imports the six uniformly sampled layer sheets.
- `prompts.txt`: built-in image generation prompt for the final parts atlas.
- `animation-validation.json`: master periodic-motion checks.
- `compatibility-validation.json`: final six-pose sampling and seam checks.
- `publication-verification.json`: successful live catalog, manifest and ownership checks.

Current race-card and Home-course runner paths use six frame indices, so the published art contains a complete six-pose cycle. This fixes those frozen clients without a carrying release; simply declaring more frames in the manifest cannot fix their shortened playback. Other existing previews respect the declared count and also play the full six-pose loop. The 24-frame source is retained for editing.

The body bobs and pitches; alternating paws follow periodic ground-contact and lifted return paths; the tail sways. Aseprite is the final export authority. Its alpha compositing differs by at most two channel levels from the Pillow assembly. Final baselineOffset is -0.03125. Existing catalog scale, offsets, price, test-only status and ownership were preserved.

## Manual playback checklist

1. Reopen TestFlight and confirm the new mouse loads. Watch five Home and Shop/wardrobe loops for body motion, no abrupt reset, detached joints or double outlines, and a stable ground line.
2. Inspect a race card and the Home course runner: both must play a full loop, without cutting off the leg return.
3. Check existing race/detail/team/podium and leaderboard character positions for clipping or overlap, and any offered accessories at the torso's high/low positions.
4. Demo/tab fixtures do not contain Mouse; the wardrobe tutorial uses the default capybara and profile-photo avatars are independent. Device playback is still a manual check.
