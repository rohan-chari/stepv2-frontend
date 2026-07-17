# CLAUDE.md — steps-tracker (Flutter app)

## Core principle: never break users on older app versions

Local Backend is located at: `/Users/rohan/repos/stepv2-backend`

The app talks to a shared backend (`steptracker-api.org`) that is updated
independently of the app. Two facts follow:

1. **A shipped app binary is frozen.** Once a version is on the App Store, those
   users keep it until they choose to update — App Store rollout is **phased
   over ~a week**, and some users **never update**. Code you change today only
   reaches a user when they install a new build.
2. **The backend may be newer (or older) than the running app.** Don't assume
   the app and backend are on the same version.

So **every change — frontend or backend — must keep working for users on
previous app versions.** This is the first thing to check for any change,
before correctness or style.

## Never run integration tests against the prod database

Integration/e2e tests create, mutate, and delete rows (users, races, coin
transactions, referrals). **Never point them at the prod DB.** They must run
only against a dedicated local/test Postgres (a `*_test` database or a
disposable container) — confirm `DATABASE_URL` is the test DB before running,
and never set it to the prod connection string for a test run. The prod DB is
the live source of truth for real users' coins and races; a stray test write or
teardown there is unrecoverable.

### Rules that follow from this
- **Read API responses defensively.** A field may be missing or null because
  the backend is a different version than this build expects. Default safely;
  don't crash on absent/null fields.
- **Don't make the app depend on a brand-new backend field/endpoint** without
  confirming the backend already returns it in prod (old app versions and the
  current backend must both be satisfied).
- **Backend changes are the bigger risk** here: the prod backend serves *all*
  app versions at once. When changing API shape, ensure the backend keeps a
  compat path for older clients (see the backend repo's `CLAUDE.md`).
- **Build-time config is baked in.** `BACKEND_BASE_URL` is injected via
  `--dart-define` at build (see `DEPLOYMENT.md`); a wrong value ships a broken
  binary that can't be hotfixed without a new App Store submission.

## Build iOS and Android in lockstep

This repo ships **both** an iOS app (Bara, App Store, native APNs) and an
Android app (Health Connect, Google Sign-In, Firebase/FCM) from the same Dart
code. **Whenever you build or release an Apple/iOS build, do the matching
Android build too — never ship one platform without the other.**

- iOS:     `flutter build ipa       --dart-define=BACKEND_BASE_URL=… [--dart-define=ADMOB_EXTRA_SPIN_AD_UNIT_ID=…]`
  (NO `--flavor` on iOS — the Xcode project has no flavor schemes. The ADMOB
  define is required for PROD releases only: it enables the iOS-only
  rewarded-ad extra spin; staging builds omit it. See `DEPLOYMENT.md`.)
- Android: `flutter build appbundle --flavor <prod|staging> --dart-define=BACKEND_BASE_URL=…`

Keep the flavor (Android), `--dart-define` backend URL, and version/build number in sync
across both. The platforms are coupled in non-obvious ways: a dependency added
for one (e.g. `firebase_*` for Android FCM) still links into the other's build,
so a change "for Android" can break the iOS build (and vice-versa). Build and
verify **both** platforms before considering a build/release change done.

See `DEPLOYMENT.md` for build/release flow.

## New feature requests: PM/BA spec-first workflow (DEFAULT for any "add a feature" ask)

When I ask for a **new feature** (not a bug fix, not a one-line tweak), do NOT
jump to code. This pipeline runs **automatically** for any request that reads as
a new feature. Put on a **PM/BA hat** and produce a written spec first; only
after I approve it do you write code.

### Phase 1 — Explore & draft the spec
1. Explore the codebase for everything this feature touches (models, endpoints,
   screens, existing similar features, DB shape). Cite real files/lines.
2. Write a spec to `docs/<feature-kebab>-requirements.md` using the template
   below. It must describe both **what** the feature is and **the exact path a
   developer takes to implement it** (files, endpoints, migrations, order of ops).

### Phase 2 — Two fresh-eyes gap passes
3. Re-read the spec from scratch as if you didn't write it. Find gaps, ambiguity,
   unhandled edge cases, and violations of this file's hard rules. Fix them.
4. Do it **again** — a second independent pass. Log what each pass changed in a
   "Revision log" section at the bottom so the tightening is visible.

### Phase 3 — Interview me on anything unresolved
5. Any requirement that's still ambiguous → **interview me** (batch related
   questions with AskUserQuestion; don't dribble one at a time). Fold answers
   back into the spec. Repeat Phase 2→3 until there are zero open questions.

### Phase 4 — Approval gate
6. Present the finished spec and **wait for my explicit approval.** Do not spawn
   implementation agents before I say go.

### Phase 5 — Two Opus 4.8 implementation agents (medium effort)
Spawn exactly two agents, model `claude-opus-4-8`, medium reasoning effort, told
to follow the spec's steps **in order**:
- **Backend developer** — owns the API contract (request/response shapes,
  status codes, new/changed endpoints, DB migrations). The contract is the
  interface between the two agents; it must be pinned in the spec BEFORE either
  agent implements. Backend also owns backend-compat for old clients.
- **Frontend developer** — consumes the backend's contract exactly as written;
  never invents fields the contract doesn't define. Owns iOS + Android in
  lockstep and loads the design skills before any UI work.

**Sequencing:** contract first, then parallel. The backend agent pins and lands
the API contract first; once the contract is locked, both agents implement in
parallel against it. The frontend agent never codes against a moving contract.

Both agents, without exception:
- **Write tests FIRST**, then the business logic. (Backend: use
  `test:unit` / `test:integration`, never bare `npm test`. Never point tests at
  the prod DB.)
- **Never modify or delete existing tests.** If an existing test seems wrong,
  surface it to me — do not "fix" it to make things pass.
- Implement business logic only after the new tests exist and fail for the right
  reason.

### The spec document MUST contain
- **Summary & user story** — what, for whom, why.
- **Scope / non-goals** — explicitly what's out.
- **API contract** — every new/changed endpoint with exact request & response
  JSON, error cases, and how the *backend* stays compatible with **older app
  versions still in the wild** (the #1 rule in this file).
- **Data model / migrations** — tables/columns, backfill, default-safe reads.
- **Frontend plan** — screens/widgets, states (loading/empty/error), and how the
  UI **degrades safely when a field is missing** (backend may be a different
  version). iOS + Android both covered.
- **Backward-compat & rollout** — deploy order (backend first, then app), what a
  frozen old client does when it hits the new backend, and any `testOnly`/feature
  gating needed until the App Store build rolls out (~a week, phased).
- **Test plan** — the tests-first list each agent writes before coding.
- **Acceptance criteria / definition of done** — checklist to call it complete.
- **Revision log** — what Phase 2's two gap passes changed.

## NEVER hand-draw artwork — always use the Codex imagegen pipeline

Claude must not author shippable artwork by hand: no CustomPainter scene
painting, no SVG art, no PIL-drawn sprites/backgrounds. Anything pictorial
(backgrounds, scenery, sprites, decorative textures) is generated with the
Codex `imagegen` pipeline below (or reused/cropped from existing generated
assets). Hand-coding is fine for UI chrome only (buttons, cards, shadows,
text, layout, motion) — not for art.

## Generating new accessory art (Codex `imagegen` pipeline)

How we produce new cosmetic accessory sprites. The app can't draw — we drive the
**Codex CLI's built-in `imagegen` skill** (no OpenAI API key needed) to generate
the art, then a **human critique/iterate loop**, then install + Aseprite wiring.
Full item-adding procedure is in `docs/adding-cosmetic-items.md`; this section is
specifically the art-generation workflow.

**Key locations**
- Codex CLI: `codex exec` (installed). `imagegen` is a built-in system skill.
- Aseprite binary: `/Users/rohan/repos/aesprite/build/bin/aseprite`
- Art sources + scripts: `/Users/rohan/repos/aesprite/art/aseprite/`, `.../art/scripts/`
- Frontend PNGs: `assets/images/accessories/<assetKey>.png` (globbed in `pubspec.yaml`)
- Backend catalog: `/Users/rohan/repos/stepv2-backend/data/cosmetics.json`
- Capybara base: `assets/images/capybara_walk_right.png` — 384×64 sheet, 6 frames of 64×64, 80ms/frame.

### The house art style (there is NO written style guide — derived from assets)
1. **SIDE PROFILE facing RIGHT** — to match the capybara. This is the #1 rule;
   front-facing/symmetric art is the most common failure and looks wrong worn.
2. **Bold, solid, continuous BLACK outline** around the whole silhouette (plus
   black keylines separating sub-parts, e.g. feather rows).
3. Chunky retro **pixel art**, visible large pixels, soft internal shading.
4. **Transparent background.** Warm/earthy palette with bright accents where they fit.
5. Study existing side-profile items for orientation: `sunglasses`, `beard`,
   `beaver_tail`, `shoes`. Sizes are a deliberate mix (low-res like `cowboy_hat`
   96×54, and hi-res like `birthday_hat`/generated art scaled at render) — raw
   size need not match; the app scales via `renderMetadata.scale`.

### 1. Generate with Codex
- Write the prompt to a **file** and pipe it via **stdin**. Do NOT pass the prompt
  as a positional arg: `-i` is variadic (`<FILE>...`) and swallows a trailing
  positional prompt as if it were another image.
- Attach reference PNGs with repeated `-i`: always the **capybara** + 2–3 existing
  **side-profile** accessories so Codex sees the orientation + style. Reference by
  index ("Image 1 is the capybara facing right…") in the prompt.
- Transparency: `gpt-image-2` has no native transparent bg, so tell Codex to use
  the skill's **chroma-key workflow** — generate on flat `#00ff00` (or `#ff00ff`
  for white/green subjects), then run `remove_chroma_key.py`. Codex does this itself.
- Generate into a **scratch dir first**, never straight into the repo.

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
OUTPUT: save the transparent PNG to <name>.png in the cwd; report the final path.
```

### 2. Critique / iterate (the human-in-the-loop part — do not skip)
- **Composite onto WHITE before judging** (`Image.alpha_composite(white_bg, img)`).
  Image viewers composite transparency onto black, which hides the black outline
  and makes clean alpha look like a solid black background.
- Check in order: **(a) orientation** — side profile facing right, not front-on
  (most common miss); **(b)** bold black outline around the whole silhouette;
  **(c)** reads as the intended object at a glance; **(d)** clean alpha (transparent
  corners, no chroma fringe — verify with PIL).
- Fix with **one targeted re-gen**: rewrite the prompt emphasizing the single miss,
  regenerate. Converges in 1–2 rounds. Real examples from the first batch:
  - wings → "add the bold black keyline outline";
  - bowtie / wings / monocle → "side-profile facing RIGHT, not flat front-facing";
  - monocle → "thin floppy dangling cord, NOT a rigid beaded handle" (else it reads
    as a hand mirror / magnifying glass).
- **Preview fit on the capy** before finalizing — either the PIL composite or the
  Aseprite on-capy preview (below), using the app's real placement math.

### 3. App placement math (for faithful previews / starting `renderMetadata`)
From `lib/widgets/home_course_track.dart` `_rectForSlot(slot, S)` where `S` = frame size:
- `HEAD (0.37,0.04,0.46,0.26)  FACE (0.60,0.28,0.22,0.14)  NECK (0.46,0.44,0.32,0.16)`
- `BACK (0.16,0.30,0.28,0.26)  FEET (0.41,0.72,0.40,0.16)` — LTWH × S.
- center = rect-center + `(offsetX·S, offsetY·S)`; box = rect W/H × `scale`; rotate
  by `rotation` (radians) about center. Offsets: `|v|≤1` → fraction of S, else raw px.
- `renderLayer:"behind"` draws the accessory UNDER the capybara (tails/capes/wings).

### 4. Install
1. Copy approved PNG → `assets/images/accessories/<assetKey>.png`.
2. Add a `cosmetics.json` entry: `sku,name,description,slot,priceCoins,assetKey,
   active:true, testOnly:true, earnOnly:false, bobble, sortOrder, renderMetadata`
   (`renderLayer:"behind"` for BACK items). **Ship `testOnly:true`** — flip to
   `false` only after an App Store build carrying the PNG has rolled out (frozen
   old clients don't bundle the new PNG).
3. Placement: ship a rough `renderMetadata`; fine-tune in **Admin → Accessory
   Tuner**, then `npm run cosmetics:pull`. Apply to DB with `npm run cosmetics:apply`
   against **local/staging only — never prod**.

### 5. Aseprite integration (source of truth for art edits)
- Create editable hi-res source:
  `aseprite -b <frontend png> --save-as art/aseprite/<key>.aseprite`.
- Build a layered on-capy preview (88×88, 6 walk frames, capy at (12,12)):
  - FRONT items (HEAD/FACE/NECK/FEET): `art/scripts/build_hat_preview.lua`
    (accessory layer on top; pass `hatname`).
  - BEHIND items (BACK): `art/scripts/build_behind_preview.lua` (accessory under capy).
  - Pre-scale + rotate the accessory to display size in PIL using the placement math
    above, save that as the `hat=`/`acc=` PNG, and pass `hatx`/`haty` = its top-left.
- Wire into `art/scripts/export.sh`: add the key to `ALL` + a `case` branch
  (`--save-as` for a single frame, `--sheet ... --sheet-columns N` for an animation).
  **Only export what changed** — re-exporting an unchanged asset rewrites PNG bytes
  and shows a spurious git "modified".
- Flip a mirrored asset: `PIL FLIP_LEFT_RIGHT` the PNG → re-derive the source →
  rebuild the on-capy preview.

### Guardrails
- Everything `testOnly:true` until the carrying App Store build has rolled out.
- Never point `cosmetics:apply` or integration tests at the **prod DB**.
- Generate into scratch first; copy into the repo only after critique passes.
- The release that ships new art must still build **iOS + Android in lockstep**.
