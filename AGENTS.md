# AGENTS.md — steps-tracker (Flutter app)

This file is the agent contract for this repo. It mirrors `CLAUDE.md` — the two
must stay in sync; if you change a rule in one, change it in the other.

Machine-specific paths (backend repo, Aseprite, etc.) live in `CLAUDE.local.md`
(gitignored). Read it when you need those paths. Do not hardcode `/Users/...`
paths in committed files.

## Repo layout

- `lib/` — all Dart. `screens/`, `screens/tabs/`, `widgets/`, `services/`
  (`backend_api_service.dart` is the single HTTP surface), `models/`,
  `demo/` + `tutorial/` (render the REAL screens against fake services),
  `utils/`, `constants/`.
- `test/` — Flutter widget/integration tests.
- `assets/images/` — art (accessories under `assets/images/accessories/`).
- `docs/` — feature specs (`docs/<feature>-requirements.md`), `docs/economy.md`.
- `ios/`, `android/` — both platforms ship from the same Dart code.
- Backend (Node/Express/Prisma/Postgres, `steptracker-api.org`) is a **separate
  repo** — path in `CLAUDE.local.md`, with its own `AGENTS.md`.

## Build / test / verify commands

- `flutter pub get`
- `flutter analyze` — must be clean before work is called done.
- `flutter test` — full suite. To diagnose a failure, run the single failing
  suite (`flutter test test/foo_test.dart`), not the whole suite repeatedly.
- iOS:     `flutter build ipa       --dart-define=BACKEND_BASE_URL=… [--dart-define=ADMOB_EXTRA_SPIN_AD_UNIT_ID=… --dart-define=ADMOB_BOX_REROLL_AD_UNIT_ID=… --dart-define=ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID=ca-app-pub-4538901002392200/6376353967]`
- Android: `flutter build appbundle --flavor <prod|staging> --dart-define=BACKEND_BASE_URL=… [--dart-define=ADMOB_RACE_PAYOUT_DOUBLE_AD_UNIT_ID_ANDROID=<create in AdMob; omission disables race payout double>]`
- Backend repo: `npm run test:unit` / `npm run test:integration` — **never bare
  `npm test`** (it hangs).

## Production and staging operations

- For managed database CPU investigations, read the DigitalOcean metrics access notes in `CLAUDE.local.md`; direct database metrics access is already configured.

- Production runs with **exactly two PM2 workers** on the production host unless
  the user explicitly authorizes a different capacity change.
- Staging is **shut down by default**. Start or reload the staging service only
  after the user gives explicit, in-the-moment authorization for that use. Do
  not start staging merely to verify a change, and shut it down again when the
  authorized work is complete.
- When the replacement production server is provisioned, configure swap as an
  emergency memory buffer and verify its size and persistence across reboot.
  Swap does not replace capacity planning or application/database optimization.

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
  don't crash on absent/null fields. No bare `!`, no unchecked `as` casts, no
  `fromJson` that throws on a missing server-provided key.
- **Don't make the app depend on a brand-new backend field/endpoint** without
  confirming the backend already returns it in prod (old app versions and the
  current backend must both be satisfied).
- **Backend changes are the bigger risk**: the prod backend serves *all* app
  versions at once. When changing API shape, keep a compat path for older
  clients (see the backend repo's `AGENTS.md`). Additive fields over changed
  fields; no removed/repurposed fields; no new required params on existing
  endpoints.
- **Build-time config is baked in.** `BACKEND_BASE_URL` is injected via
  `--dart-define` at build (see `DEPLOYMENT.md`); a wrong value ships a broken
  binary that can't be hotfixed without a new App Store submission.
- New content that a frozen client can't render (e.g. a PNG it doesn't bundle)
  ships `testOnly:true` and flips to `false` only after the carrying App Store
  build has rolled out.
- **Deploy order is backend first, then app.**

## Backend scalability and performance guidelines

These principles apply to all future backend work. The goal is to support
substantially more users on the same infrastructure before relying on vertical
or horizontal scaling.

### Core scalability principle

**Optimize for doing less work per unit of user activity.** Before adding
infrastructure, look for ways to reduce database queries, writes and round
trips; repeated calculations; duplicate queue jobs; unnecessary object loading,
serialization/deserialization and network calls; and work performed
synchronously during API requests. Prefer designs that reduce total work over
simply moving the same amount of work somewhere else.

### Database round trips

Treat reducing database round trips as a major performance goal. Avoid loops
that repeatedly query or update the database.

Bad pattern:

```text
for each user:
    SELECT user
    UPDATE user
```

Prefer:

```text
SELECT all required users (bounded)
perform calculations in memory where appropriate
bulk update affected users
```

Actively look for N+1 queries, queries inside loops, repeated queries for the
same data, repeated flush/SaveChanges calls (or equivalent ORM operations),
row-by-row inserts and updates, and multiple queries that can safely be
combined. Load required data once and operate on it as a set where possible.
Wrapping individual commands in a transaction does not by itself make them a
bulk operation or eliminate their round trips.

### Bulk reads

Prefer bounded, targeted bulk reads when multiple records are needed: users
with `WHERE id IN (...)`, race participants, required power-up state,
leaderboard data, and related entities fetched in a planned query instead of
individual lazy loads. Select only required fields. Do not bulk-load huge
datasets unnecessarily; chunk large input sets into bounded batches.

### Bulk writes

Prefer bulk inserts, updates and deletes, set-based SQL, batched ORM writes,
and database-native update operations when many rows change. Avoid hundreds
or thousands of individual commands when a set-based operation can safely
express the work. Preserve business logic, concurrency behavior, audit
requirements and transactional correctness.

### Batching

Consider processing related events together when it significantly reduces
overhead: step updates, leaderboard recalculations, notifications, race
statistics, activity logs, analytics events and queued jobs. Do not introduce
unacceptable delays or break real-time behavior.

### Reduce write frequency

Treat high-frequency data such as step updates carefully. Do not persist every
tiny intermediate state when only the latest or accumulated result is needed.
Consider accumulating deltas, coalescing updates, debouncing writes, buffering
short bursts, writing only meaningful changes, maintaining aggregate counters,
and persisting the latest state when transient history is not required.
Before changing write semantics, confirm what must be durable and what can
safely be recomputed.

### Write amplification

Watch for one user action producing disproportionate downstream writes. A
step sync should not unnecessarily update user records, race participants,
leaderboards, activity tables, stats, notifications and queue tables.
Estimate the SELECTs, INSERTs, UPDATEs, DELETEs and queue jobs generated by each
common user action, including downstream work, and consolidate excessive work.

### Precomputed aggregates

Avoid repeatedly recalculating expensive values from large raw datasets when
an aggregate can safely be maintained. Candidates include race step totals,
leaderboard totals, daily step totals, user statistics, standings, win counts
and frequently requested summaries. Prefer incremental updates where
appropriate: instead of repeatedly computing `SUM(all_step_records)`, consider
updating a current aggregate as step data arrives. Define a clear source of
truth and a repair/rebuild path for every aggregate.

### Caching

Cache frequently requested data that need not be recalculated or loaded from
PostgreSQL on every request. Possible Redis candidates include live
leaderboards, race state, active race metadata, user summaries, temporary
calculated values and short-lived application state. Do not cache blindly.
For every cache, define:

- Source of truth and cache key.
- TTL, if applicable, and invalidation behavior.
- Behavior on cache miss and when Redis is unavailable.

Redis must not become the only copy of data requiring durability unless the
system is specifically designed that way.

### Queues

Move expensive work out of synchronous API requests when users do not need
its result immediately: leaderboard recalculation, notifications, analytics,
expensive statistics, background race processing and secondary side effects.
Requests should generally do only what is needed to safely accept and validate
the action. Do not queue work merely to hide inefficient database logic;
workers must follow these same scalability guidelines.

### Queue deduplication and coalescing

Avoid duplicate background work. If a user's leaderboard needs updating eight
times before the first job runs, consider one job processing the latest state
where correctness allows it. Look for repeated jobs for the same entity, jobs
superseded by newer jobs, mergeable jobs and race-wide jobs repeatedly created
during bursts. Deduplicate or coalesce only when required effects are preserved.

### Concurrency limits and backpressure

Use bounded concurrency; more workers are not automatically better.
Database-heavy parallel jobs can overload PostgreSQL. When adding consumers or
parallel processing, consider database connection limits, CPU, lock contention,
transaction duration, Redis load, memory and downstream API limits. Absorb
bursts with backpressure instead of spawning unlimited simultaneous database
work.

### Indexes

Evaluate indexes when creating or modifying queries, based on actual access
patterns. For `WHERE race_id = ? AND user_id = ?`, consider an appropriate
composite index. Investigate execution plans, sequential/index scans, rows
examined versus returned, sorts, joins and query frequency. Account for
existing indexes and additional write overhead before adding indexes.

### Pagination and bounded queries

Every potentially growing query must have an intentional limit. Paginate or
otherwise bound activity feeds, race history, notifications, user lists,
public races, leaderboard history and administrative tools. Avoid loading
entire tables unless the dataset is known to be very small.

### Avoid unnecessary work

Before implementing backend functionality, ask:

1. Does this need a database query?
2. Can we reuse data already loaded?
3. Can several reads become one read?
4. Can several writes become one write?
5. Does this need to happen synchronously?
6. Does this need to happen every time?
7. Can it be cached?
8. Can it be incrementally maintained?
9. Can duplicate work be discarded?
10. Can the query be bounded?
11. Are we recalculating something we could maintain as an aggregate?
12. Could concurrency turn this inexpensive operation into a database
    bottleneck at scale?

### Bara-specific considerations

Design frequent paths for high user counts: Apple Health and Android Health
Connect step sync, step ingestion, race participant updates, leaderboard
calculations, race totals, power-up processing, activity feeds, notification
fan-out, scheduled race jobs, queue workers and user statistics.
**Treat step sync as a potentially high-volume operation.** When changing
step-sync-related code, explicitly consider thousands of users syncing at
approximately the same time.

### Performance investigation expectations

When investigating high CPU, database load, queue lag or scalability, do not
stop at calling a calculation expensive. Trace the full execution path:

- How frequently it runs and how many users or races trigger it.
- Database query/write counts, queue job counts and rows scanned per query.
- Queries inside loops and repeated loading of the same data.
- Repeated calculations, duplicate jobs and amplification from concurrency.

Quantify the current path and compare it with the proposed implementation
where possible. For example (illustrative numbers, not measured Bara results):

```text
One step sync before optimization:
27 SELECTs, 11 UPDATEs, 4 INSERTs, 3 queue jobs

After optimization:
4 SELECTs, 2 bulk UPDATEs, 1 bulk INSERT, 1 deduplicated queue job
```

Prefer measurable reductions over vague performance claims. Distinguish
measured results from estimates and include downstream worker work in totals.

### Correctness comes first

Do not sacrifice correctness, transaction safety, race-condition handling,
data durability or compatibility with older app versions to reduce database
usage. Preserve behavior unless a behavior change is explicitly intended.
For significant optimizations, explain current behavior, the scalability
problem, the proposed change, expected reduction in work, correctness and
concurrency risks, migration concerns, and how the change will be tested.

The goal is to increase how many users existing infrastructure can reliably
support by reducing work per user, especially database work, rather than only
making individual requests faster.

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
- **Write tests first**, then the business logic — the new tests must exist and
  fail for the right reason before the logic lands.

## Never run integration tests against the prod database

Integration/e2e tests create, mutate, and delete rows (users, races, coin
transactions, referrals). They must run only against a dedicated local/test
Postgres (a `*_test` database or a disposable container). Confirm
`DATABASE_URL` is the test DB before running. A stray test write or teardown
against prod is unrecoverable.

## Existing tests are protected

Never weaken, `skip`, or delete an existing assertion to make things pass.
Mechanical updates (imports, renames, signature changes) are fine. If an
existing test looks wrong, surface it — don't "fix" it silently.

## Build iOS and Android in lockstep

This repo ships **both** an iOS app (Bara, App Store, native APNs) and an
Android app (Health Connect, Google Sign-In, Firebase/FCM) from the same Dart
code. **Never ship one platform without the other.**

- iOS: NO `--flavor`. The ADMOB defines are PROD-only — they enable the
  iOS-only rewarded-ad extra spin and box reroll; staging builds omit them.
  The reroll unit has NO test-ad fallback: omitting it compiles the reroll
  button out. See `DEPLOYMENT.md` for the full release command.
- Keep flavor (Android), backend URL, and version/build number in sync. The
  platforms are coupled in non-obvious ways: a dependency added for one (e.g.
  `firebase_*`) still links into the other's build. Build and verify **both**
  before considering a build/release change done.
- The phrase **"push to App Store Connect"** explicitly authorizes uploading
  the current verified iOS archive through the Apple account already signed
  into Xcode. Follow `DEPLOYMENT.md` and perform the upload automatically after
  the matching Android artifact is built and verified. Upload does not also
  authorize App Review submission or customer release.

## Workflow routing (skills & subagents)

Project skills live in `.agents/skills/<name>/SKILL.md`; project subagents in
`.codex/agents/<name>.toml`. Load a skill by reading its `SKILL.md` and
following it; delegate to a subagent by spawning it by name.

- **Any new-feature request** (not a bug fix or one-line tweak): load the
  `spec-feature` skill and follow it. Spec first, my approval, then the
  `architect` review, then the `backend-developer` and `frontend-developer`
  subagents implement.
- **Any artwork/sprite/accessory/cosmetic/powerup image task**: load the
  `accessory-art` skill. NEVER hand-draw shippable art (no CustomPainter
  scenes, no SVG art, no PIL sprites). Hand-coding is fine for UI chrome only
  (buttons, cards, shadows, text, layout, motion).
- **Any UI design work**: load the `mobile-design` skill first (personal skill,
  `~/.agents/skills/mobile-design/`) — no default unstyled Material look.
- **Any UI-placement change** (adding, moving, or removing anything a user
  sees on a screen — whether a full feature or a standalone tweak): run the
  `ui-test-planner` subagent and give me its manual checklist before the work
  is presented as done. Many screens are mirrored (demo race tutorial and tab
  tutorial render the real screens; some chrome is hand-forked) — the
  checklist exists so I verify every mirror, e.g. moving the mystery boxes on
  the race detail screen must also be checked inside the tutorial demo.
- **Any odds / game-balance / economy discussion or change** (drop rates, spin
  weights, prices, payout curves, coin sources/sinks, multipliers, scoring
  rules): run the `game-analyst` subagent for an EV + exploit analysis before
  numbers are committed to code or seeds. It maintains `docs/economy.md` and
  may read prod SELECT-only; it never edits code or config.
- **After any non-trivial implementation**: run the `code-reviewer` subagent
  before presenting the work as done.

## Definition of done

A change is done when: `flutter analyze` is clean; the relevant tests are
written first and pass; both platforms are accounted for; version-skew safety
is explicitly reasoned about; the required subagent review(s) above have run;
and any manual UI checklist has been handed to me. Report failures and skipped
steps plainly — never claim done with red tests.
