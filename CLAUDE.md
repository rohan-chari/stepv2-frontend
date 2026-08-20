# CLAUDE.md — steps-tracker (Flutter app)

Machine-specific paths (backend repo, Aseprite, etc.) live in `CLAUDE.local.md`
(gitignored). Do not hardcode `/Users/...` paths in committed files.

## Release flags are prohibited by default

Ship permanent, version-compatible behavior by default. Do **not** add a
feature flag, rollout percentage, kill switch, runtime toggle, or temporary
environment control merely to make a normal release feel safer.

If a flag appears absolutely necessary for mixed-version compatibility,
irreversible migration safety, or an exceptional operational risk, stop before
implementing it and get the user's explicit approval. Explain why permanent
behavior, additive compatibility, or version/data stamping is insufficient.
Every approved exception must document its owner, safe default, rollout plan,
and concrete removal deadline or condition. Remove the control promptly when
that condition is met; a flag must never become permanent infrastructure by
inertia.

## Core principle: never break users on older app versions

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

### Rules that follow from this
- **Read API responses defensively.** A field may be missing or null because
  the backend is a different version than this build expects. Default safely;
  don't crash on absent/null fields.
- **Don't make the app depend on a brand-new backend field/endpoint** without
  confirming the backend already returns it in prod (old app versions and the
  current backend must both be satisfied).
- **Backend changes are the bigger risk**: the prod backend serves *all* app
  versions at once. When changing API shape, keep a compat path for older
  clients (see the backend repo's `CLAUDE.md`).
- **Build-time config is baked in.** `BACKEND_BASE_URL` is injected via
  `--dart-define` at build (see `DEPLOYMENT.md`); a wrong value ships a broken
  binary that can't be hotfixed without a new App Store submission.
- New content that a frozen client can't render (e.g. a PNG it doesn't bundle)
  ships `testOnly:true` and flips to `false` only after the carrying App Store
  build has rolled out.

## Integration tests over unit tests — always

**If a behavior is worth testing, test it end-to-end.** Default to an
integration test; reach for a unit test only when an integration test
*structurally cannot* express the property (pure algorithmic/date/tz math with
many cases; structural guards over source; properties unreachable through the
public path). A green unit suite over mocked collaborators proves the pieces
agree with your mocks — not that the feature works.

- **Backend:** `test/integration/` — real HTTP request, real DB, real handler
  chain. Assert on the response a client actually receives. Never
  `require()`/import an internal utility inside an integration test to shortcut
  the public path.
- **Frontend:** pump the real screen/widget and assert what renders.
- "Covered by the unit parity suite" is not sufficient when the risk is that
  two code paths diverge.

## Never run integration tests against the prod database

Integration/e2e tests create, mutate, and delete rows (users, races, coin
transactions, referrals). They must run only against a dedicated local/test
Postgres (a `*_test` database or a disposable container). Confirm
`DATABASE_URL` is the test DB before running. A stray test write or teardown
against prod is unrecoverable.

## Existing tests are protected

Never weaken or delete an existing assertion to make things pass. Mechanical
updates (imports, renames, signature changes) are fine. If an existing test
looks wrong, surface it — don't "fix" it silently.

## Build iOS and Android in lockstep

This repo ships **both** an iOS app (Bara, App Store, native APNs) and an
Android app (Health Connect, Google Sign-In, Firebase/FCM) from the same Dart
code. **Never ship one platform without the other.**

- iOS:     `flutter build ipa       --dart-define=BACKEND_BASE_URL=… [--dart-define=ADMOB_EXTRA_SPIN_AD_UNIT_ID=… --dart-define=ADMOB_BOX_REROLL_AD_UNIT_ID=… --dart-define=ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID=ca-app-pub-4538901002392200/6376353967]`
  (NO `--flavor` on iOS. The ADMOB defines are PROD-only — they enable the
  iOS-only rewarded-ad extra spin and box reroll; staging builds omit them.
  The reroll unit has NO test-ad fallback: omitting it compiles the reroll
  button out. See `DEPLOYMENT.md` for the full release command.)
- Android: `flutter build appbundle --flavor <prod|staging> --dart-define=BACKEND_BASE_URL=… [--dart-define=ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID_ANDROID=<create in AdMob; omission disables race payout double>]`

Keep flavor (Android), backend URL, and version/build number in sync. The
platforms are coupled in non-obvious ways: a dependency added for one (e.g.
`firebase_*`) still links into the other's build. Build and verify **both**
before considering a build/release change done. See `DEPLOYMENT.md`.

## Workflow routing (skills & agents)

- **Any new-feature request** (not a bug fix or one-line tweak): load the
  `spec-feature` skill and follow it. Spec first, my approval, then the
  `architect` review, then the `backend-developer` and `frontend-developer`
  agents implement.
- **Any artwork/sprite/accessory/cosmetic/powerup image task**: load the
  `accessory-art` skill. NEVER hand-draw shippable art (no CustomPainter
  scenes, no SVG art, no PIL sprites). Hand-coding is fine for UI chrome only
  (buttons, cards, shadows, text, layout, motion).
- **Any UI-placement change** (adding, moving, or removing anything a user
  sees on a screen — whether a full feature or a standalone tweak): run the
  `ui-test-planner` agent and give me its manual checklist before the work is
  presented as done. Many screens are mirrored (demo race tutorial and tab
  tutorial render the real screens; some chrome is hand-forked) — the
  checklist exists so I verify every mirror, e.g. moving the mystery boxes on
  the race detail screen must also be checked inside the tutorial demo.
- **Any odds / game-balance / economy discussion or change** (drop rates, spin
  weights, prices, payout curves, coin sources/sinks, multipliers, scoring
  rules): run the `game-analyst` agent for an EV + exploit analysis before
  numbers are committed to code or seeds. It maintains `docs/economy.md` and
  may read prod SELECT-only; it never edits code or config.
- **Any k6/capacity/load-run request**, including simply "do a k6 run": load
  the `k6-operator` skill and delegate execution to the named `k6-operator`
  agent. `k6/operator.zsh` is the only public workflow; never reconstruct the
  old fixture workbook or bypass its fresh per-run confirmation gate.
- **After any non-trivial implementation**: run the `code-reviewer` agent
  before presenting the work as done.
