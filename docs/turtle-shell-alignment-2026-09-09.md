# Turtle shell alignment — September 9, 2026

The preceding foot-aligned packing placed shell tops at y=34,31,31,32,31,31,31,34.
Aligning the shell tops at y=31 removes the 3-pixel vertical jump. Frames 0 and 7
move up 3 pixels, frame 3 moves up 1, and the others remain unchanged. All original
cropped drawings are pixel-identical; dimensions remain 704×88, eight 88×88 frames.
Feet retain their pose-dependent movement. No horizontal or rendering-code changes.

The native Aseprite source was translated and exported. The updated ZIP packer
reproduces those pixels exactly. An image-generation attempt did not preserve the
required sheet dimensions and was discarded; the published file uses original art.

Published backend commit `29976e2` adds only the new immutable PNG:
https://steptracker-api.org/assets/characters/turtle@708e4cbf2289.png

SHA-256: `708e4cbf228939c8a850c9d5774c563d8e24f89949674f66b50ee87e5c70e3dd`.
Public HTTP 200, image/png, immutable cache headers, and downloaded bytes verified
before PATCHing the existing turtle through the production admin API. Only
assetVersion changed; all other catalog fields were compared and unchanged.
Peer mirror returned attempted=true, ok=true. Public manifest confirms the new
URL and animationFrames=8. Old immutable PNG retained. No service restart or
staging start. Production retains two HTTP workers.

Validation: a pre-edit pixel check failed on differing shell heights; afterward
all eight heights match and original drawings are preserved without clipping.
Native export and ZIP repacking are pixel-identical. Seven existing turtle widget
tests pass; flutter analyze --no-pub is clean. Independent reviewer: SHIP.

Shared assets cover both platforms. No app build/upload was performed. Existing
remote-first builds can download the correction; older bundled-first walking
renderers retain their frozen artwork. The local bundled fallback is corrected
for the next app builds. Device checks remain manual.

## Manual placement checklist (iOS and Android)

- Online relaunch with Turtle equipped: watch Home, Shop and Inventory loops,
  especially last-to-first; shell stays level, one complete turtle per frame.
- Preview head, face, neck, back and feet accessories; check attachment and
  feet/ground placement after the frame translations.
- Check individual race lanes, participant thumbnails, team top-scorer hero
  cards and Races cards for containment, grounding and stable shell height.
- Check Shell effect/activity/outcome icons for complete single-frame crops.
- Shop tutorial with Turtle equipped: preview containment and spotlight fit.
- After download, repeat Home offline to check cached CDN art. Testing the new
  bundled fallback requires a future carrying build.
- Home/tab and demo-race tutorial fixtures do not select Turtle (even TurtleBot);
  they cannot prove this fix. Tutorial chrome and anchors are unchanged.

## Superseding correction: fixed shell and lower ground placement

The owner still saw shell movement and floating after restarting. Matching only
the top edges was insufficient: the original shell shape/pattern and lower rim
also varied between poses. The final sheet now reuses the sixth original shell
across all eight frames, retaining animated green head/legs/tail. The complete
turtle moves down 3 pixels. No generated drawing is used.

All 1,022 connected shell pixels have identical positions and RGBA values in all
frames. All eight poses remain distinct. Frame bounds end at y=69–72 exclusive,
leaving at least 16 pixels below the feet within unchanged 88×88 cells. Independent
visual review found no gaps, duplicate outlines or clipping. Physical-device
feet/accessory fit still needs the manual checks below.

`scripts/stabilize_turtle_shell.lua` reproduces the final native source and PNG
byte-identically from the saved local `turtle_walk_right_pose_source.aseprite`.
The ZIP packer is explicitly intermediate; final `turtle_walk_right.aseprite`
remains authoritative. Lua uses source/output arguments, without machine paths.

Final URL: https://steptracker-api.org/assets/characters/turtle@dae6df0acbd4.png

SHA-256: `dae6df0acbd48c0d395dd95f5f5fe1027b1bffb4f841563d257dee0291714e85`.
Backend asset-only commit: `2d798aa`. Public bytes verified before admin PATCH;
manifest confirms version and eight frames, peer mirror OK, other catalog fields
unchanged. Prior URLs retained. No restart, staging start or app build/upload.
Seven turtle widget tests pass again and Flutter analysis remains clean.

Updated manual checks, on iOS and Android after online relaunch:

- Home: feet sit against the ground; shell stays fixed across several full loops.
- Shop/Inventory: head and legs join the stationary shell with no gaps or doubled
  outlines; check the last-to-first transition.
- Individual race lanes and team top-scorer cards: feet/grass/shadow placement,
  bottom clearance and full thumbnails.
- Head/face/neck/back/feet accessories and Shop tutorial: attachment, containment
  and spotlight fit after the three-pixel downward shift.
- Shell block/activity/outcome icons: complete single-frame crop.
- Offline after download: cached CDN version. Existing non-turtle tutorial
  fixtures cannot prove this change; corrected bundle needs a future build.

## Final correction: connected tail with gentle whole-body bounce

The owner correctly identified that the frozen shell overcorrected the motion
and that its original independently animated tail no longer looked attached.
The native reconstruction now reuses the original sixth pose's tail together
with its shell. A restricted flood selects the tail without taking the raised
rear foot from the eighth pose. Both pieces retain their original pixels; no
new art is drawn. The moving neck and legs remain from each original pose.

Whole-frame offsets are 3+[0,-1,-1,0,0,-1,-1,0] pixels: one-pixel gait bounce,
retaining the lowered placement. Top positions are34,33,33,34,34,33,33,34.
A bounded adjacent-pixel pass replaces pale upper-shell fringe with the canonical
source fringe too, preventing leftover white specks from the previous outlines.

Checks failed on the preceding frozen-shell asset, then passed on final exported
AND publicly downloaded PNG: nonzero1px bounce, stable tail/body pixels after
normalizing for that bounce, at least3 opaque tail-root/shell contacts in each
frame, and no clipping. Reviewer additionally confirmed each frame is one opaque
connected component; all eight tail/neck/leg joins reviewed. Seven turtle widget
tests pass; flutter analyze --no-pub clean. Source reconstruction is in
`scripts/stabilize_turtle_shell.lua`. Native source and bundled PNG updated.

Final CDN version superseding all above: `d931d8420a70`, backend commit `12b4971`.
URL: https://steptracker-api.org/assets/characters/turtle@d931d8420a70.png
SHA-256: `d931d8420a7078c5d689ab437286b6a38ad8188a4cdad4ba43d79310790429ab`.
Downloaded bytes and manifest geometry verified. Production admin PATCH changed
only assetVersion; peer mirror OK; prior immutable files retained. No app upload,
restart or staging start. Existing older bundled-only clients retain frozen art.

[Animation preview](evidence/turtle-bounce-preview.gif)

Final manual checklist on iOS and Android after online relaunch:

- Home, Shop and Inventory: watch3 loops including last-to-first; subtle bounce,
  tail stays joined, no second tail edge, feet close to ground.
- Individual race lanes and team leader/Races cards: tail junction intact,
  feet/shadow/grass aligned, no clipped body or accessories.
- Accessory previews and Shop tutorial: attachment through both bounce positions,
  contained preview and correctly placed spotlights.
- Shell activity/outcome icons: one complete turtle with attached tail.
- Repeat Home offline after download for cached CDN verification. Tutorial fixtures
  without Turtle cannot establish this fix; new bundled fallback needs a build.

## Approved body retained; independent tail-tip motion

The owner approved the body animation and requested up/down movement of the tail
itself. Tip columns x<10 now move by [0,0,1,1,0,0,-1,-1] relative to the body.
The root stays fixed under the shell. Every pixel at x>=10 in every frame is
identical to the approved previous sheet. No body, neck, leg, bounce or grounding
changes. The original tail pixels are translated by column without resampling.

A pre-edit check failed on the static tail, then passed on the exported and
publicly downloaded update: tip motion spans2px relative to body, root/body
unchanged, and all8 frames remain one4-connected opaque silhouette. Independent
review SHIP;7 turtle widget tests pass; Flutter analysis clean. Native source,
bundled fallback and animated preview updated.

Current CDN version: `f3410027eade`, backend asset-only commit `3292872`.
URL: https://steptracker-api.org/assets/characters/turtle@f3410027eade.png
SHA-256: `f3410027eadee6881445331d2e5d4e80ab376e2b2c180f52de178ef081d34911`.
Public bytes verified before admin PATCH; manifest confirms8frames; peer mirror
OK; all other catalog fields unchanged. Prior immutable assets retained. No app
release, process restart or staging start; older bundled-only clients unaffected.

Tail-specific manual checklist (both platforms): after online relaunch watch3
Shop/Inventory and Home loops, including last-to-first. Tip should rise/fall while
root stays attached with no gap or doubled edge. Confirm unchanged ground fit,
then check individual/team race lanes/cards and static Shell icons for clipping.
Repeat Home offline after download. Shop tutorial shares its preview; other
existing demo/tab tutorial fixtures do not select Turtle.
