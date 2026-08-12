---
name: accessory-art
description: Use this skill whenever creating, generating, editing, fixing, or
  adding ANY artwork, sprite, or pictorial asset — accessories, cosmetics, hats,
  powerup icons, backgrounds, scenery, textures, or anything the capybara wears.
  Triggers include "new hat", "add an accessory", "generate a sprite", "make
  art/artwork", "new cosmetic", "powerup image", or any image-creation request.
  Covers the imagegen pipeline, chroma-key transparency, the critique loop, app
  placement math, catalog install, and Aseprite integration. NEVER hand-draw
  shippable art — always use this pipeline instead.
---

# Generating accessory / cosmetic art (`imagegen` pipeline)

Never author shippable artwork by hand: no CustomPainter scene painting, no
SVG art, no PIL-drawn sprites/backgrounds. Anything pictorial is generated with
the `imagegen` pipeline below (or reused/cropped from existing generated
assets). Hand-coding is fine for UI chrome only (buttons, cards, shadows, text,
layout, motion) — not for art.

Full item-adding procedure: `docs/adding-cosmetic-items.md`. This skill is the
art-generation workflow specifically.

**Key locations**
- `imagegen` is a built-in system skill in Codex — invoke it directly. (From
  another agent, shell out with `codex exec` as shown below.)
- Aseprite binary + art sources/scripts: see `CLAUDE.local.md`.
- Frontend PNGs: `assets/images/accessories/<assetKey>.png` (globbed in `pubspec.yaml`)
- Backend catalog: the `shop_items` table (DB is the source of truth,
  peer-mirrored prod ↔ staging; see `docs/adding-cosmetic-items.md`)
- Capybara base: `assets/images/capybara_walk_right.png` — 384×64 sheet,
  6 frames of 64×64, 80ms/frame.

## The house art style (NO written style guide — derived from assets)
1. **SIDE PROFILE facing RIGHT** — to match the capybara. This is the #1 rule;
   front-facing/symmetric art is the most common failure and looks wrong worn.
2. **Bold, solid, continuous BLACK outline** around the whole silhouette (plus
   black keylines separating sub-parts, e.g. feather rows).
3. Chunky retro **pixel art**, visible large pixels, soft internal shading.
4. **Transparent background.** Warm/earthy palette with bright accents.
5. Study existing side-profile items for orientation: `sunglasses`, `beard`,
   `beaver_tail`, `shoes`. Raw sizes are a deliberate mix (`cowboy_hat` 96×54
   low-res; `birthday_hat` hi-res) — the app scales via `renderMetadata.scale`.

## 1. Generate
- Attach reference PNGs: always the **capybara** + 2–3 existing **side-profile**
  accessories. Reference them by index in the prompt ("Image 1 is the capybara
  facing right…").
- Transparency: `gpt-image-2` has no native transparent bg — use the imagegen
  skill's **chroma-key workflow** (generate on flat `#00ff00`, or `#ff00ff` for
  white/green subjects, then run `remove_chroma_key.py`).
- Generate into a **scratch dir first**, never straight into the repo.

When shelling out to Codex from another tool, write the prompt to a **file** and
pipe via **stdin**. Do NOT pass the prompt as a positional arg: `-i` is variadic
(`<FILE>...`) and swallows a trailing positional prompt as if it were another
image.

```bash
cat prompt.txt | codex exec --cd "$SCRATCH" --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  -i capybara_walk_right.png -i accessories/sunglasses.png \
  -i accessories/beard.png -i accessories/beaver_tail.png
```

Prompt skeleton (one accessory per call; run calls in parallel for a batch):
```
Use the imagegen skill to create a game cosmetic sprite for a side-profile character.
ORIENTATION IS CRITICAL: Image 1 is the capybara, SIDE PROFILE facing RIGHT. The
accessory must be drawn in matching side-profile orientation, NOT front-facing.
STYLE: chunky pixel art, bold SOLID BLACK continuous outline, soft shading (match refs).
SUBJECT: <the item, its colors, how it sits on a right-facing capybara>.
TRANSPARENCY: generate on flat solid #00ff00, then run remove_chroma_key.py for clean alpha.
OUTPUT: save the transparent PNG to <n>.png in the cwd; report the final path.
```

## 2. Critique / iterate (human-in-the-loop — do not skip)
- **Composite onto WHITE before judging** (`Image.alpha_composite(white_bg, img)`).
  Viewers composite transparency onto black, which hides the black outline and
  makes clean alpha look like a solid black background.
- Check in order: **(a) orientation** — side profile facing right (most common
  miss); **(b)** bold black outline around the whole silhouette; **(c)** reads
  as the intended object at a glance; **(d)** clean alpha (transparent corners,
  no chroma fringe — verify with PIL).
- Fix with **one targeted re-gen**: rewrite the prompt emphasizing the single
  miss. Converges in 1–2 rounds. Real examples from the first batch:
  - wings → "add the bold black keyline outline";
  - bowtie / wings / monocle → "side-profile facing RIGHT, not flat front-facing";
  - monocle → "thin floppy dangling cord, NOT a rigid beaded handle" (else it
    reads as a hand mirror / magnifying glass).
- **Preview fit on the capy** before finalizing — PIL composite or the Aseprite
  on-capy preview (below), using the app's real placement math.

## 3. App placement math (for faithful previews / starting `renderMetadata`)
From `lib/widgets/home_course_track.dart` `_rectForSlot(slot, S)` where `S` = frame size:
- `HEAD (0.37,0.04,0.46,0.26)  FACE (0.60,0.28,0.22,0.14)  NECK (0.46,0.44,0.32,0.16)`
- `BACK (0.16,0.30,0.28,0.26)  FEET (0.41,0.72,0.40,0.16)` — LTWH × S.
- center = rect-center + `(offsetX·S, offsetY·S)`; box = rect W/H × `scale`;
  rotate by `rotation` (radians) about center. Offsets: `|v|≤1` → fraction of
  S, else raw px.
- `renderLayer:"behind"` draws the accessory UNDER the capybara (tails/capes/wings).

## 4. Install
1. Copy approved PNG → `assets/images/accessories/<assetKey>.png`.
2. Create the catalog row via `POST /admin/shop/items` (staging; mirrors to the
   peer DB by sku): `sku,name,description,slot,priceCoins,assetKey,bobble,
   sortOrder,renderMetadata` (`renderLayer:"behind"` for BACK items). The DB is
   the source of truth — there is no cosmetics.json. **`testOnly` defaults to
   `true`; keep it** — flip to `false` only after an App Store build carrying
   the PNG has rolled out (frozen old clients don't bundle the new PNG).
3. Placement: create with rough `renderMetadata`; fine-tune in **Admin →
   Accessory Tuner** (saves mirror prod ↔ staging automatically). Drift safety
   net: `npm run cosmetics:sync-peer` (backend repo; `-- --repair` to fix).

## 5. Aseprite integration (source of truth for art edits)
- Create editable hi-res source:
  `aseprite -b <frontend png> --save-as art/aseprite/<key>.aseprite`.
- Layered on-capy preview (88×88, 6 walk frames, capy at (12,12)):
  - FRONT items (HEAD/FACE/NECK/FEET): `art/scripts/build_hat_preview.lua`
    (accessory layer on top; pass `hatname`).
  - BEHIND items (BACK): `art/scripts/build_behind_preview.lua`.
  - Pre-scale + rotate the accessory to display size in PIL using the placement
    math above, save that as the `hat=`/`acc=` PNG, pass `hatx`/`haty` = top-left.
- Wire into `art/scripts/export.sh`: add the key to `ALL` + a `case` branch
  (`--save-as` for a single frame, `--sheet ... --sheet-columns N` for
  animation). **Only export what changed** — re-exporting an unchanged asset
  rewrites PNG bytes and shows a spurious git "modified".
- Flip a mirrored asset: PIL `FLIP_LEFT_RIGHT` the PNG → re-derive the source →
  rebuild the on-capy preview.

## Guardrails
- Everything `testOnly:true` until the carrying App Store build has rolled out.
- Never point `cosmetics:clone` or integration tests at the **prod DB**.
- Generate into scratch first; copy into the repo only after critique passes.
- The release that ships new art must still build **iOS + Android in lockstep**.
