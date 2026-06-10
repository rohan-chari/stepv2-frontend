# Technical Audit: steps-tracker (app + backend)

**Date:** 2026-06-10
**Scope:** `steps-tracker` (Flutter app, HEAD `2d6f751` "1.2.0", shipped 1.1.8) and `steps-tracker-backend` (Express/Prisma, HEAD `45cdab0`).
**Method:** 7 parallel discovery readers → 27 candidate findings adversarially verified by independent skeptic agents (each instructed to refute). No code was modified. Every claim carries `file:line` evidence and a **fact**/**judgment** label.

---

## Executive Summary

**Overall health: C.** This is a real production system with unusually strong design instincts — the frozen-binary compatibility doctrine is genuinely practiced in code, the backend layering is clean, and the economy has idempotency ledgers and advisory locks where someone thought hard — but the verification discipline that should protect all of it has collapsed: the Flutter test suite has been un-runnable for three shipped releases, there is no CI in either repo, the shipped 1.1.8 commit has no tag or branch, and an economy-critical prod fix exists only as an uncommitted local diff. **Top 3 risks:** (1) economy integrity — steps input is completely unvalidated (instant leaderboard/ranked corruption and real coin extraction via race payouts), powerup use is non-transactional, and three coin paths double-mint on double-submit; (2) the new-user funnel is broken in prod — 100% of fresh signups end onboarding on a permanent blank screen, and background step-sync has *never worked in any shipped binary*; (3) every deploy is a gamble — nothing gates it, and one routine deploy can silently revert the seeded-races box fix. **Top 3 opportunities:** (1) ~10 quick wins under 2 hours each retire most of the High findings; (2) restoring the suite to green + adding CI converts an existing 42k-line test investment into an actual safety net; (3) the worst bugs all live on unowned *seams* (Dart↔Swift, app↔backend, display-path↔sync-path, repo↔prod) — a thin layer of contract tests at those seams prevents the whole recurring class.

---

## Repo Map

**Purpose & maturity:** "Bara" — a shipped iOS App Store game (v1.1.8 live): HealthKit step tracking gamified into competitive races with a powerup/mystery-box coin economy, friends, leaderboards, ranked seasons, cosmetics, and push notifications. Solo-operated production service.

| Repo | Stack | Size | Role |
|---|---|---|---|
| `steps-tracker` | Flutter (Dart ^3.10), iOS-first, plain `setState` (no state-mgmt package) | ~33.5k lines lib/ + 66 test files; 843-line `AppDelegate.swift` | Frozen binaries in the field (1.1.4–1.1.8) |
| `steps-tracker-backend` | Express 5 + Prisma 7 (pg adapter) + Postgres | ~16.3k src, ~42k test lines, 62 migrations, 25 ops scripts | One API serving **all** shipped app versions; prod+staging as 2 pm2 processes on one droplet, shared 50-connection managed Postgres |

**Architecture:**

```
App: main.dart → _SessionGate → StartScreen (Apple Sign-In / hidden 6-tap reviewer login)
      → DisplayNameScreen → TutorialScreen
      → MainShell (1,178-line god-widget: all state, session refresh, onboarding gate,
         HealthKit → POST /steps + /steps/samples, 5-min poll, 5-tab PageView)
   lib/services/backend_api_service.dart (1,271 lines, ~70 endpoints, raw Map payloads)
   lib/screens/race_detail_screen.dart (3,659-line monolith, 4 concurrent pollers)
   ios/Runner/AppDelegate.swift — a PARALLEL native background step-sync stack
      (HKObserver + BGAppRefresh + silent push → URLSession POSTs, creds from UserDefaults)

Backend: app.js → cors → express.json → extractTimezone → 13 routers (all behind
   requireAuth: HS256 session JWT w/ Apple identity-token fallback that auto-provisions)
   routes → commands/ (writes) + queries/ (reads) → services/ → models/ (thin Prisma)
   HEARTBEAT: POST /steps → resolveRaceState (totals, finish detection, placements,
   completeRace) → syncRacePowerupState → rollPowerup ($transaction + advisory lock;
   box gate = RAW walked steps, UTC-pinned)
   getRaceProgress: a "query" that WRITES (expires effects, writes totals, mints boxes),
   polled every 30s per viewer; 5 setInterval cron jobs; in-process eventBus → APNs (http2)
```

**Conventions to preserve:** compat shims with version comments (`auth.js:176-195`), opt-in capability flags (`homeActiveRaces=1`, `skipRaceResolution`), additive-only schema with retained deprecated columns, DI factories everywhere, coin ledger keyed `(reason, refId)`, dry-run-by-default ops scripts, defensive `as T?`+`??` reads with "older backend omits this" comments.

**Surprises:** step sync implemented twice in two languages with hand-maintained parity (`AppDelegate.swift:650-651,718-719`); `getRaceProgress` is the system's heaviest writer despite living in `queries/` (and lazily `require()`s the settlement module to break a circular import, `getRaceProgress.js:451-452`); the backend holds a live pool into the *other environment's* database to mirror cosmetics (`peerDb.js`); no app-version header exists anywhere — the backend cannot tell which binary is calling; app `DEPLOYMENT.md:98-110` contains unedited generated text arguing with itself in the deploy-ordering section.

---

## Audit Report

*Verification status: every Critical/High and most Medium findings below survived a dedicated adversarial verification pass. Dimensions marked ⚠ received lighter review (discovery + targeted checks only): performance, code-quality metrics, and deep test-quality analysis. Also lighter: android/macos/windows/linux dirs, tutorial internals, admin screens, `apns.js`/`profilePhotoStorage.js` internals.*

### Critical

**C1 — iOS background step-sync has never worked in any shipped binary.** (fact; double-confirmed by two independent verifiers)
Dart writes `auth_session_token` / `health_authorized` / `background_sync_backend_base_url` via legacy SharedPreferences, which prefixes every key with `flutter.` (`shared_preferences-2.5.4/.../shared_preferences_legacy.dart:22,179`; writers at `auth_service.dart:24,278,341`, `health_service.dart:11,38`, `background_sync_bootstrap_service.dart:10-15`). The native store reads the **unprefixed** keys (`AppDelegate.swift:516-541`), so the guard at `AppDelegate.swift:362-370` always exits `.noData`. All three triggers are dead: BGAppRefresh (which reports `success:true` to iOS at `:211`, so even iOS never notices), HealthKit background delivery (`:254-264`), and the backend's silent-push `STEP_SYNC_REQUEST` protocol (`:136-149`) — which the backend actively pays APNs sends for (`friends.js:77-83`). Present since the feature's introduction (commit `c4085d2`, pre-1.1.6); git history proves the keys never matched. Invisible to tests because `RunnerTests.swift:176-180` injects a `MockStateStore` and Dart tests mock prefs — nothing crosses the Dart-write/Swift-read seam.
**Consequence:** steps sync only while the app is open; days where a user never opens the app are *permanently missing* (multi-day backfill exists only in the dead native path), so multi-day races settle and pay out on wrong data. One verifier held High (foreground masks today's count), the other Critical — adjudicated **Critical**: a marketed core feature silently broken in prod for 100% of users, unfixable server-side, with race-settlement impact.

### High

**H1 — Every new signup ends on a permanent blank screen.** (fact, live in 1.1.8)
All fresh-signup paths make `DisplayNameScreen` the *only* route (`main.dart:84-89`, `start_screen.dart:70-127`); it `pushReplacement`s to `TutorialScreen` with no `onComplete` ever passed (`display_name_screen.dart:200-208`), and `_finish` pops the navigator's sole route (`tutorial_screen.dart:161-167`) — empty navigator, blank screen in release. Recovery requires force-quit (state was saved first, so relaunch works). Cohort: 100% of new signups. Borderline Critical; held High only because force-quit fully recovers.

**H2 — The Flutter test suite has been red across three shipped releases.** (fact)
12 of 66 test files fail to compile (deleted `ChallengeWeekStepSyncService`/`challenges_tab` imports from 1.1.4 commit `82d9e58`, removed `HomeScreen` params, stale `createRace` fakes since 1.1.7), plus 5 stable assertion failures in 3 compiling files (`active_race_card_test.dart` ×3, `race_detail_screen_test.dart`, `onboarding_keyboard_access_test.dart`) — those may mark **already-shipped UI regressions**. Full run: 177 pass / 17 fail. One broken file was even edited in 1.1.8 without fixing its dead import. The regression gate has been non-functional since ~May 21 on an economy-incident-prone codebase. Bonus (fact, Medium): the iOS `RunnerTests` target also doesn't compile (`MockStepReader` missing `fetchHourlyStepCounts`, `RunnerTests.swift:198-213` vs `AppDelegate.swift:312-322`).

**H3 — Lean-select omissions corrupt mid-race-joiner economy, live today.** (fact)
`Race.findActiveForUser`'s participant select omits `joinedAt` (`race.js:146-161`), so on every POST /steps, `getEffectiveStart` (`raceStateResolution.js:20-23`) falls back to race start: invite late-joiners into ACTIVE powerup races **mint mystery boxes for pre-join steps** on first sync (gate armed at absolute interval at `respondToRaceInvite.js:68`, but `boxEffectiveSteps` computed from race start, `raceStateResolution.js:552-565`; catch-up loop `rollPowerup.js:91-97`). DB totals for these joiners flip-flop between the sync path (inflated) and display path (correct, uses full `findById`). **Deploying the uncommitted self-heal (H7) extends pre-join minting to all seeded daily/weekly challenge joiners** — the normal flow (join → race view arms gate on the deflated basis → next sync rolls on the inflated basis) defeats its zero-mint invariant. Also omits `timeBased` (`race.js:139-145` vs `raceStateResolution.js:578`) — latent re-creation of the exact pre-migration instant-finish incident if seeds ever regain display goals (Medium); the unit test that "protects" this only exercises the `findById` path (`raceStateResolution.test.js:372-399`); **zero tests exercise `findActiveForUser`**. This is the third occurrence of the project's known lean-select bug class.

**H4 — `usePowerup` is a long multi-write mutation with no transaction or lock.** (fact)
Only guard is a plain read of HELD status (`usePowerup.js:172,179`); USED flip happens last via unconditional update (`:1122-1127`). Concurrent duplicate requests double-apply: SHORTCUT double-steals (`:636-637`), RED_CARD/PINECONE_TOSS double penalties (`:612-614,:1086`), self-buffs double `bonusSteps` (`:768,:816,:918`), TRAIL_MAGNET double-pulls the box threshold (`:1014-1015`), POCKET_WATCH double-extends buffs (`:1035-1039`). Effect-creating types are accidentally half-protected by the unique `race_active_effects.powerup_id` (`schema.prisma:687`) — but the loser's already-deducted upgrade coins are never refunded (`:444-458` commits in its own transaction). A mid-sequence crash can leave a powerup **applied but still HELD** — replayable for free. Contrast: `rollPowerup` does this correctly (`rollPowerup.js:67-83`).

**H5 — POST /steps accepts any integer; the canonical cheat vector is wide open.** (fact; borders Critical)
Route checks only `steps == null` (`steps.js:29-31`); `recordSteps` writes verbatim (`recordSteps.js:32-45`). Accepted range: any int4 up to ~2.1B/day. No rate limiting, no validation library, no anomaly detection anywhere on the ingest path. Verified blast radius: instant global/ranked leaderboard top (`getLeaderboard.js:114-128` — no clamp), uncapped ranked RP (`rankedPoints.js:53-54`), and **instant goal-race wins paying real coins** (`raceStateResolution.js:578` → `completeRace.js:42-69`). Box minting is slot-bounded (~4/sync, not 50). Held at High (requires a malicious client; negatives clamped on most surfaces).

**H6 — Three coin paths double-mint on double-submit; crashed payouts are permanently lost.** (fact; materially modified by verification)
`awardCoins` is check-then-create with the `findFirst` *outside* the transaction and only a **non-unique** index `(userId, reason, refId)` (`awardCoins.js:16-35`, `schema.prisma:291`, `refId` nullable). The originally-suspected vector (concurrent `completeRace`) is actually safe — the `updateIfActive` CAS gate (`race.js:105-110`) admits exactly one caller — but that same gate means **a crash mid-payout permanently loses payouts** (the retry-dedup comment at `completeRace.js:79` is dead wrong: retries never reach the loop). The *reachable* double-mints: `cancelRace` double-submit double-refunds every held buy-in (status check `cancelRace.js:29-34` is read-only; refund loop `:36-47`), `respondToRaceInvite` double-accept double-charges the buy-in (`:41-43,:85-91`), `claimDailyReward` double-claims mint twice (non-atomic date guard `claimDailyReward.js:72-74`; award at `:89-94` *before* the unique-constrained claim insert at `:124-139`). Contrast the done-right paths: `joinPublicRace` (advisory lock), `claimStepMilestone` (unique insert first).

**H7 — The only copy of an economy-critical prod fix is an uncommitted local diff.** (fact)
The seeded-races box self-heal (+29 lines, `racePowerupStateSync.js:80-107`) exists in **no committed ref** (`git log --all -S` empty; stash empty), companion test untracked — and even if committed, the test sits at `test/` root, *outside every glob in `test:unit`* (`package.json:10`). Without it, `joinPublicRace` never arms `nextBoxAtSteps` (zero references; only `startRace.js:104` and `respondToRaceInvite.js:68` arm it) — every seeded-challenge joiner is stranded at the schema default 0 and earns no boxes. Any deploy materializing `origin/main` reverts the fix. Whether it's even live on prod is unverifiable from the repo. (Interplay with H3: commit it *together with* the `joinedAt` fix, or it opens the wider minting hole.)

### Medium

**M1 — Placement assignment races; wrong standings persisted, rewards silently dropped.** (fact) `resolveRaceState` derives placements from a stale snapshot with `Promise.all` writes, no lock (`raceStateResolution.js:463-468,507-636`); the expiry cron *unconditionally re-assigns* placements 1..N (`raceExpiry.js:117-122`), including on already-COMPLETED races. Verification refuted the double-pay rider: collisions cause **under**-payment — duplicate placements suppress one finisher's reward via refId dedup, the vacated placement's pot share is never paid, and final standings can contradict the payout.

**M2 — Timed-effect gating reads stale status; dead shields eat paid attacks.** (fact) `expireEffects` runs only inside `getRaceProgress` (`getRaceProgress.js:376`); no cron expires effects; all gating reads filter status only (`raceActiveEffect.js:10-28`). Bounded ~30s window for attack/stacking gates (race screen polls), but **unbounded** on sync-only paths: an hours-dead Compression Socks still blocks (and consumes) a Trail Mine during background-sync resolution (`raceStateResolution.js:414-421`); expired STEALTH masks names indefinitely on home card/feed/messages (`getHomeRaceCard.js:296-302`). The IMPOSTER display path already defends against exactly this lag (`getRaceProgress.js:563-571`) — the hazard is known, the defense uneven.

**M3 — Mirror "reflects" Sneaky Swap as a mechanical no-op that still consumes the Mirror.** (fact) Roles swap (`usePowerup.js:546-552`) but `swapHeldPowerups` executes with request-time arguments (`:1102`, symmetric impl `racePowerup.js:82-122`) — the attacker gets exactly the swap they chose, the defender's Mirror is consumed for zero protection, and the feed reports the *defender* as aggressor (`:1107-1115`). The reflect test matrix omits SNEAKY_SWAP (`mirrorPowerup.test.js:364-398`) — untested, not intended.

**M4 — IDOR: `sneaky-swap-targets` leaks rosters + powerup intel for any race.** (fact; downgraded from High) No membership check (`races.js:531-565`); any authed user can harvest `userId`+`displayName`+holds-stealable-powerup for participants of any active race (public race UUIDs are free via `GET /races/public`). Verified to be the **only** unprotected race sub-route (13 siblings all gate). Read-only, low-sensitivity data → Medium.

**M5/M6 — Notification plumbing drops taps.** (fact) All three return-to-StartScreen paths drop the `NotificationService` (`main_shell.dart:243-253`, `profile_tab.dart:777-797`) — after re-sign-in, tap routing is dead and (on the sign-out path) push delivery stops entirely until app restart. Separately, cold-start taps never deep-link: `pendingAction` is set before MainShell mounts and the listener never reads the already-set value (`main_shell.dart:115-119`, `notification_service.dart:101-115`) — the most common push-tap scenario lands on Home. Both are one-line fixes (next binary).

**M7 — The error-shape contract breaks exactly when it matters, on both sides.** (fact) Backend: no error middleware, no JSON 404 (`app.js:20-55`) — malformed JSON returns Express's **HTML 400** app-wide (verified live in-process), unguarded routes (`GET /auth/session` `auth.js:202-213`, `GET /auth/check-display-name` `:364-381`) return HTML 500s. App: `_decodeJsonResponse` runs `jsonDecode` *before* the status check with zero FormatException handlers in the repo (`backend_api_service.dart:1241-1263`) — users see raw `FormatException:` text during every deploy's nginx 502 window (`race_detail_screen.dart:416,632,651,746` surface `e.toString()`), and the ranked tab's 404-based graceful degradation — the project's own flagship version-skew mechanism — is **structurally dead** for HTML 404s. Plus the `DisplayNameTakenError` ReferenceError in a catch block (`auth.js:252`, class never imported), which masks real errors with HTML 500s on the clear-name path.

**M8 — Auth tokens in plaintext NSUserDefaults, 90-day non-revocable JWT.** (judgment) `auth_service.dart:317-347`; no Keychain usage anywhere; session JWT lives 90 days with no revocation store (`sessionToken.js:4`, `requireAuth.js:40-54`) and is re-minted to full life on every open. Exposure is backups/paired-device, not remote → Medium. Migration is cheap and frozen-binary-safe; must move the native reader (`AppDelegate.swift:513-537`) in the same release — conveniently the same code as C1.

**M9 — Native sync omits X-Timezone; fixing C1 without it causes premature race finishes.** (fact) Daily-row bucketing is safe (client-supplied date), but `resolveRaceState` uses `req.timeZone` (default **America/New_York**, `extractTimezone.js:21`) for per-day windows — verified scenario: a PT user's late-evening steps double-count across the ET day boundary, transiently crossing `targetSteps` → **permanent finish + pot payout** for a user who never hit the goal (`raceStateResolution.js:578`, `determineFinishSnapshot` persists at `:509-515`). Box gate immune (UTC-pinned by design). Latent only while C1 keeps the path dead — fix both together.

**M10 — Postgres TLS unauthenticated everywhere.** (fact) `ssl:{rejectUnauthorized:false}` with `sslmode` stripped in both pools (`db.js:14,27`; `peerDb.js:32,40`) and 11 prod scripts; repo `.env` points at the *public* DO endpoint; no CA cert bundled. Cheap fix (DO publishes the CA).

**M11 — Unbounded pre-auth memory growth via X-Timezone memo Sets.** (fact) Raw attacker-controlled header strings (up to ~16KB each) memoized forever, pre-auth, on every request (`extractTimezone.js:1-16`, mounted `app.js:25`). Slow unauthenticated memory-exhaustion vector.

**M12 — Account deletion can permanently 500 for legacy-challenge users.** (fact+judgment) Deletion is atomic and currently covers all FKs (good), but `ChallengeInstance` anonymization ignores the `@@unique([userAId,userBId,weekOf])` (`deleteUserAccount.js:124-139` vs the guarded race-participant path `:94-109`) — a sentinel collision throws P2002 on every retry: App Store 5.1.1(v)/GDPR violation needing manual DB surgery. Zero of 148 test files cover `deleteUserAccount`; any future default-RESTRICT `userId` FK silently breaks **all** deletions.

**M13 — Every routine deploy silently reverts manual powerup-catalog changes.** (fact; original "disables live challenges" refuted — Challenge/Stake are dead tables since 1.1.4) `seed.js:102-113` force-resets IMPOSTER name/price/active/sortOrder on every deploy; an emergency catalog deactivation would quietly un-deactivate. Runbook describes the step as "upserts cosmetics" only (`DEPLOY_RUNBOOK.md:67-68`).

**M14 — Release discipline has collapsed; no hotfix path exists for the live binary.** (fact) No tag or branch marks shipped 1.1.8 in either repo; the app repo has **zero tags ever** despite `DEPLOYMENT.md:139-142` mandating them; 1.1.8 and 1.2.0 committed straight to main (single-parent `8a2c2ef`, `9a6a8df`, `2d6f751`); `pubspec.yaml:19` is `1.2.0` with no `+N`. A 1.1.8 hotfix must today ship unreleased 1.2.0 work or cherry-pick by archaeology. Backend deploys pull main, where unreleased work now lands — every push is implicitly deployable.

**M15 — Docs contradict code in operationally-critical places.** (facts, spot-verified) Backend `ReadMe.md` gives the wrong prod port (3000 vs 3002), wrong branch model, wrong pm2 name; app `DEPLOYMENT.md`'s entire `--flavor staging/prod` build story has no corresponding Xcode scheme/bundle config in the committed project (`project.pbxproj:484,669,694` — the prod/staging-separation guard is not reproducible from the repo) plus the self-contradicting deploy-order section (`DEPLOYMENT.md:98-110`); `POWERUPS.md` describes 8 powerup types incl. one that no longer exists vs 19 rollable in code; `RANKED.md` header says "not yet built" for a shipped feature; README claims a Workmanager background sync that isn't in the dependency list (actual: native BGTaskScheduler) and embeds a personal device UDID (`README.md:122`); runbook's boot health-check expects 3 cron lines, actual is 5.

**M16 — `_race!['status'] as String` in the build path** (`race_detail_screen.dart:1535`, no catch in the build chain; same field read tolerantly at `:1490,:609,:1545`): a null/absent status under version skew bricks the race screen (grey ErrorWidget) on frozen binaries. (fact, latent)

**M17 — `npm run migrate` is `prisma migrate dev`** (`package.json:12`) — directly contradicts the project's own hand-author-and-`migrate resolve` workflow; running the repo's own script can trigger a destructive drift reset. (fact)

### Low (verified, brief)

`expireEffects` full-table seq scan per progress request — one-line fix pushes `raceId` into the WHERE and hits the existing `(race_id,status)` index (`expireEffects.js:18-23`); TRAIL_MAGNET's `grantedBox` computed from the wrong basis but read by no client ever shipped (`usePowerup.js:1018` — dead, lying API field with a test enshrining it); `/auth/review` brute-force yields only a non-admin reviewer session (constant-time concern refuted as impractical); parsing-style inconsistencies (`fetchRaceProgress` cast contained by caller's catch; chat/feed `id` casts are contained poison-pills; shop coin-cast claim **refuted** — backend can't emit fractional coins); `health_authorized` write-once true → posts 0-step days forever after revocation (platform limitation, design judgment); dead code: `requireAppleAuth.js` (zero importers), `src/generated/prisma` (stale Mar-11 artifact), stale `claude/fix-background-polling` branch targeting deleted files, `race_positions.dart:2` comment contradicting `:9`; npm audit: 14 vulns of which the runtime-relevant are `path-to-regexp`/`qs` DoS in Express's chain — all fixable via `npm audit fix`; five Flutter deps multiple majors behind (no known CVEs).

### Strengths (preserve these)

1. **The compat doctrine is real, not aspirational** — verified shims, opt-in flags, additive columns, retained deprecated fields, defensive reads with rationale comments throughout both repos.
2. **Backend layering and DI** — routes→commands/queries→services→models with injectable factories makes nearly everything testable.
3. **Economy safety where it was thought about** — `rollPowerup` ($transaction + advisory lock + in-lock re-read), `joinPublicRace` (advisory lock), `claimStepMilestone` (unique-insert-first), `deductCoinsAtomic`, `updateIfActive` CAS, idempotency-key purchase ledgers. The discipline exists; H4/H6 are about *applying it uniformly*.
4. **JWT handling is correct** (adversarial check refuted the concern): HS256 pinned (`sessionToken.js:32-35`), Apple verification checks iss/aud/exp/nbf/signature with sane JWKS caching.
5. **Secrets hygiene**: `.env`/`certs/` gitignored and never in history.
6. **Ops scripts** are dry-run-by-default with `--apply` gates and per-row assertions.
7. **Test volume and intent**: 42k lines of backend tests incl. a real DB-backed integration suite; app tests assert visible behavior with stable keys.
8. **Friendly-error UX layer** in the app (`ApiException` mapping, `Loadable<T>` stale-data preservation, mounted-checks).

---

## Improvement Strategy

### Theme 1: The seams are unowned — and that's where every worst bug lives
C1 (Dart↔Swift key prefix), M9 (Dart↔Swift header parity), H3 (sync-path↔display-path field parity), M7 (app↔backend error-shape contract), H7/M14 (repo↔prod divergence). Each seam has two sides tested in isolation with fakes that *encode the same wrong assumption* (MockStateStore, `hasInjectedDeps` no-ops, `setMockInitialValues`).
**Target state:** every seam gets one cheap contract test: a Swift test asserting the store reads the literal `flutter.`-prefixed keys; a backend test that calls `resolveRaceState` through the *real* `findActiveForUser` shape (or a lint asserting the lean select is a superset of fields the resolution services read); an app test that feeds `_decodeJsonResponse` an HTML body and asserts a clean `ApiException`. **Principle:** when behavior must match across a boundary, encode the match in a test, not in a comment asking humans to keep them identical.

### Theme 2: Make every economy mutation atomic and idempotent *by construction*
H4, H5, H6, M1, M2, M3 are one root cause: the codebase knows the tools (locks, CAS, unique-first inserts) but applies them per-incident.
**Target state:** (a) a unique partial index on `coin_transactions(userId, reason, refId) WHERE refId IS NOT NULL` and `awardCoins` rewritten create-first-catch-P2002 — double-mint becomes structurally impossible everywhere at once; (b) `usePowerup` wrapped in a transaction with a CAS status flip (`updateMany WHERE status='HELD'` *first*); (c) steps ingest validated with a hard server-side bound. **Principle:** correctness via constraints the database enforces, not via check-then-act sequences that tests can't reliably exercise.

### Theme 3: Put the safety net back up, then never deploy around it
H2, H7, M14, M17, no-CI, M13. The project has excellent tests it cannot run.
**Target state:** `flutter test` and `npm test` exit 0; GitHub Actions on both repos gating merge to main; shipped versions tagged; the self-heal committed; seed.js made deploy-idempotent in the safe direction (create-only for catalog rows). **Principle:** the deploy procedure may stay manual (fine at this scale) but must consume *only* artifacts that passed the gate.

### Theme 4: Stop trusting the client in a competitive coin economy
H5, M11, and (judgment) the absence of any version telemetry.
**Target state:** server-side bounds on steps (e.g. reject >150–200k/day; integers only; valid date), a bounded timezone cache, an `X-App-Version` header logged on ingest (enables future per-version gating and would have surfaced C1 months ago via "zero background-sync requests ever"). **Principle:** the binary is frozen and unfixable — the server is the only place rules can live.

### Explicitly NOT recommending (trade-offs)
- **No state-management framework migration** (provider/riverpod/bloc). The setState architecture is consistent, tested, and shipped; migrating ~33k lines is weeks of risk for polish-grade payoff. Contain MainShell/RaceDetail growth opportunistically instead.
- **No typed-API-model rewrite.** Raw maps + defensive reads are the established culture and mostly work; instead, consolidate the duplicated `_readInt`-style helpers into one util and fix the ~4 reachable hard-casts.
- **No infra changes** (queues, containers, multi-node). One droplet + pm2 is appropriate for the user base.
- **No broad performance program.** The verified perf findings are Low at current scale. Take the one-line `expireEffects` fix; defer the rest. ⚠ lighter-review caveat applies here.
- **Not fixing** TRAIL_MAGNET's `grantedBox` semantics beyond a comment/removal decision, the reviewer-login throttle, or POWERUPS.md beautification — low payoff until the Highs are done.

### "Done" looks like
- CI required-status on main in both repos; `flutter test` and `npm run test:unit` + integration green.
- Zero Critical, zero High open; every coin-mutation path either holds a lock/CAS or relies on a DB unique constraint (greppable checklist).
- A unique index backs `awardCoins`; `POST /steps` rejects out-of-bounds input (with a test).
- Shipped binary versions have annotated tags; prod deploys reference a tag.
- A seam-test exists for: UserDefaults keys, lean-select field coverage, non-JSON HTTP bodies, malformed-JSON requests.
- Backend `ReadMe.md` deleted or rewritten; app `DEPLOYMENT.md` matches the actual Xcode project; runbook matches actual boot output.

---

## Task Plan

### Milestone 0 — Safety net (before touching anything else)

| ID | Task | Files/areas | Acceptance | Effort | Risk | Deps |
|---|---|---|---|---|---|---|
| T0.1 | **Commit & push the box self-heal + its test (moved into `test/services/` so the glob runs it)** — with the H3 caveat documented in the commit message | `racePowerupStateSync.js`, `test/` | `git log origin/main` contains it; `npm run test:unit` runs the test | **S** | Low (code already validated; deploy timing per ask-before-deploy rule) | — |
| T0.2 | Restore `flutter test` to green: delete/rewrite the 12 compile-broken files (they test deleted features — rewrite only where the subject still exists), triage the 5 assertion failures as regression-vs-stale **before** editing them (per "tests are source of truth") | `test/` (12+3 files) | `flutter test` exit 0 | **L** | Medium (must not paper over real regressions — triage step is the point) | — |
| T0.3 | CI: GitHub Actions both repos — app: `flutter analyze` + `flutter test`; backend: `test:unit` + integration vs a postgres service container; required status on main | `.github/workflows/` ×2 | A PR with a failing test cannot merge | **M** | Low | T0.2 |
| T0.4 | Reconstruct release anchors: identify the 1.1.8 App Store commit in both repos, tag (`v1.1.8-released`), tag backend's deployed commit; decide release-branch discipline vs simplifying DEPLOYMENT.md to match reality | git only | Tags exist; doc matches practice | **S** | None | — |
| T0.5 | Fix iOS `RunnerTests` compile (add `fetchHourlyStepCounts` to MockStepReader) + add the **key-parity seam test** (assert store reads `flutter.`-prefixed keys) | `ios/RunnerTests/` | `xcodebuild test` passes; seam test fails on today's code, passes after T1.1 | **M** | Low | — |

### Milestone 1 — Critical & correctness

| ID | Task | Files/areas | Acceptance | Effort | Risk | Deps |
|---|---|---|---|---|---|---|
| T1.1 | **Fix background sync** (C1): Swift reads `flutter.`-prefixed keys; add X-Timezone (M9) + skip-resolution parity + 401 token handling in the native poster; ship in next binary | `AppDelegate.swift:513-541,772-842` | Seam test green; on-device: background sync posts after force-quit | **M** | Medium (touches shipped-binary behavior; phased rollout) | T0.5 |
| T1.2 | **Fix new-signup dead-end** (H1) | `display_name_screen.dart:200-208`, `tutorial_screen.dart:161-167` | Fresh-install signup lands in MainShell | **S** | Low | — |
| T1.3 | **Add `joinedAt`+`timeBased` to the lean select** (H3) + a regression test that runs `resolveRaceState` through the real `findActiveForUser` field shape | `race.js:126-166`, `test/services/` | Mid-race-joiner sync test: zero pre-join boxes; deploy before/with T0.1's fix | **S** | Low–Med (verify on prod after deploy; consider a one-off audit for already-inflated participants) | coordinate w/ T0.1 |
| T1.4 | **Validate POST /steps** (H5): integer, `0 ≤ steps ≤ 200_000` (or chosen cap), valid `date`; same for samples | `steps.js`, `recordSteps.js`, `recordStepSamples.js` | Out-of-bounds → 400 `{error}`; tests | **S** | Low (no legit client sends >200k) | — |
| T1.5 | **Make `usePowerup` atomic** (H4): CAS the status flip first (`updateMany WHERE id AND status='HELD'`, bail on count 0), wrap remaining writes + coin deduct in one transaction (advisory lock on powerupId if interactive-tx limits bite) | `usePowerup.js`, `racePowerup.js` | Concurrent-duplicate test applies exactly once; crash test leaves no partial state | **L** | Medium (1,159-line command; the per-type switch must move inside the tx carefully) | T0.3 |
| T1.6 | **Unique partial index `(userId,reason,refId) WHERE refId IS NOT NULL`** + `awardCoins` create-first-catch-P2002; reorder `claimDailyReward` (claim row before mint); CAS-gate `cancelRace` and `respondToRaceInvite` (H6) | `awardCoins.js`, `claimDailyReward.js`, `cancelRace.js`, `respondToRaceInvite.js`, hand-authored migration | Concurrency tests; **pre-migration duplicate-refId audit query** must be clean first | **M** | Medium (index creation fails if prod already has dupes — audit first; hand-author SQL per project workflow) | — |
| T1.7 | Backend error contract (M7): JSON error middleware + JSON 404 catch-all + `trust proxy` + import `DisplayNameTakenError` | `app.js`, `auth.js:9,252` | Malformed JSON → JSON 400; unguarded-route throw → JSON 500; tests | **S** | Low | — |
| T1.8 | App: guard `jsonDecode`, preserve statusCode in the failure path so 404-degradation works (M7) | `backend_api_service.dart:1241-1263` | HTML-body test → clean ApiException with status | **S** | Low (next binary) | — |
| T1.9 | Membership check on `sneaky-swap-targets` (M4) | `races.js:531-565` | Non-participant → 403; test | **S** | Low | — |
| T1.10 | Serialize finish/placement assignment (M1): per-race advisory lock around finish-detection→placement→complete, and make `raceExpiry` placement writes conditional (never rewrite COMPLETED races) | `raceStateResolution.js:507-656`, `raceExpiry.js:117-122` | Concurrent-finishers test yields unique placements; cron no-ops on completed races | **L** | Medium | T0.3 |
| T1.11 | Effect-expiry correctness (M2): add `expiresAt > now` (or expire-first) to gating reads; push `raceId` into `findExpired`'s WHERE | `raceActiveEffect.js:10-37`, `expireEffects.js`, `usePowerup.js:462-535`, `raceStateResolution.js:408-421` | Dead-shield-blocks-mine test fails before, passes after | **M** | Low–Med | — |
| T1.12 | Decide & fix Mirror-vs-Sneaky-Swap semantics (M3) + add SNEAKY_SWAP to the reflect test matrix | `usePowerup.js:526-571,1101-1115` | Product decision encoded in test | **S–M** | Low | product answer (OQ3) |

### Milestone 2 — High-leverage improvements

| ID | Task | Effort | Notes |
|---|---|---|---|
| T2.1 | Thread `NotificationService` through all 3 StartScreen sites + read `pendingAction.value` once at MainShell mount (M5/M6) | **S** | Two one-liners, next binary |
| T2.2 | Keychain migration for both tokens, incl. the native reader (`kSecAttrAccessibleAfterFirstUnlock`) (M8) | **M** | Bundle with T1.1 — same code region |
| T2.3 | DO CA cert + `rejectUnauthorized:true` in `db.js`/`peerDb.js` + the 11 scripts (M10) | **S–M** | Test against staging first |
| T2.4 | Bound the timezone cache: validate without memoizing invalid values (or LRU cap) (M11) | **S** | |
| T2.5 | `X-App-Version` header in app + log/expose on backend | **S+S** | Cheap observability that would have caught C1 |
| T2.6 | Docs triage (M15): delete backend `ReadMe.md` (point at DEPLOYMENT.md), fix DEPLOYMENT.md contradiction + flavor story (or commit the Xcode flavor config — see OQ6), runbook: true seed.js description + 5-line boot check, strip the UDID, write the missing 1-page backend architecture overview | **M** | Highest-value docs only |
| T2.7 | Make seed.js catalog upserts create-only (manual prod changes survive deploys) (M13) | **S** | |
| T2.8 | Account-deletion hardening (M12): collision-guard ChallengeInstance anonymization (mirror the race-participant pattern) + first-ever `deleteUserAccount` test | **S–M** | |
| T2.9 | `npm audit fix` + delete the `migrate` script (or alias it to `migrate deploy`) (M17, deps) | **S** | |

### Milestone 3 — Quality & polish

T3.1 extract the ×9 loader scaffold into a helper around `Loadable` (**M**); T3.2 decompose `race_detail_screen.dart` (**XL — needs breakdown; only do alongside planned feature work there**); T3.3 consolidate `_readInt`-style parsing into one util + fix the `status`/chat-`id` hard-casts (**S**); T3.4 dead-code sweep: `requireAppleAuth.js`, `src/generated/prisma`, stale fix branch, `race_positions` comment, Challenge/Stake table decision (**S**, see OQ4); T3.5 Flutter dependency major-version catch-up (**M**); T3.6 remove or fix `grantedBox` (**S**); T3.7 scope the 1s countdown rebuild to a `ValueListenableBuilder` (**S**).

### Quick wins (do immediately, all S)
**T0.1** (commit the self-heal — *today*), **T0.4** (tags), **T1.2** (signup dead-end), **T1.3** (lean select), **T1.4** (steps validation), **T1.7** (error middleware), **T1.8** (jsonDecode guard), **T1.9** (IDOR), **T2.1** (notification one-liners), **T2.4** (tz cache), **T2.9** (audit fix).

### Implementation sketches — top 3

**T1.1 Background sync (C1+M9).** In `UserDefaultsBackgroundSyncStateStore`, read `flutter.auth_session_token`, `flutter.health_authorized`, `flutter.background_sync_backend_base_url` (keep unprefixed reads as fallback for safety). Add `X-Timezone: TimeZone.current.identifier` to both native POSTs, and decide `skipRaceResolution` parity with the Dart path (`backend_api_service.dart:140-157`) so the two clients converge. Gotchas: (1) Dart writes via the *legacy* API today — don't "fix" the Dart side to unprefixed writes instead, that breaks every other pref; (2) test on-device with the app force-quit (BGTask via Xcode's `_simulateLaunchForTaskWithIdentifier`); (3) the silent-push path will suddenly go live for updated binaries — confirm backend `STEP_SYNC_REQUEST` volume is acceptable; (4) ship with T2.2 (Keychain) if you want to touch this code only once, but don't let that delay the fix.

**T1.2 Signup dead-end (H1).** Smallest safe fix: in `_finish` (`tutorial_screen.dart:161-167`), if `widget.onComplete == null && !Navigator.of(context).canPop()`, `pushReplacement` to `MainShell(...)` instead of popping. Cleaner: `display_name_screen.dart:200-208` passes `onComplete` that `pushReplacement`s MainShell. Gotchas: TutorialScreen needs the same service params MainShell expects (thread `notificationService` — this is exactly the M5 bug shape, don't recreate it); the profile-tab replay path (`profile_tab.dart:865-870`) must keep pop behavior — `canPop()` distinguishes them. Add a widget test for the fresh-signup route stack.

**T1.3 + T0.1 Lean select & self-heal (H3+H7), shipped together.** Add `timeBased: true` to the race select and `joinedAt: true` to the participants select (`race.js:139-161`). Regression test: build a fake whose race/participant objects contain *only* the lean select's fields (copy the literal field list), run `resolveRaceState({userId})`, assert a mid-race joiner's `boxEffectiveSteps` excludes pre-join steps and a `timeBased+targetSteps>0` race doesn't finish. Then commit the self-heal (its zero-mint invariant now holds on both bases). Gotchas: fakes hide exactly this bug class — the test must mirror the select literally (better: generate the fake from the select object itself); after deploy, run a read-only prod audit for participants whose `nextBoxAtSteps` was ratcheted by pre-join inflation (the `scripts/` remediation pattern exists — dry-run first; never backfill a gate column without simulating the roll); deploy ordering — plain code deploy, but do it *before or with* T0.1's fix going live.

---

## Open Questions

1. **Is the self-heal actually running on prod right now?** `origin/main` lacks it; only a droplet-side check can confirm. Determines T0.1 urgency: if prod doesn't have it, seeded-challenge joiners are earning zero boxes *today*.
2. **Steps cap (T1.4):** what's the legitimate ceiling — 100k? 200k? And should the cap clamp or reject?
3. **Mirror vs Sneaky Swap (T1.12):** should a reflected swap be *voided*, or *reversed* (defender picks from attacker)? Code can't answer intent.
4. **Challenge/Stake tables** are dead since 1.1.4 but seeded and anonymized on deletion. Revive or drop? (Drop simplifies T2.8 and seed.js.)
5. **1.1.8 phased-rollout status & next-binary timing:** H1 and C1 fixes are binary-bound — is 1.2.0 close enough to carry them, or is a 1.1.9 hotfix warranted? (H1 argues for the hotfix.)
6. **Where does the staging Xcode flavor config live?** DEPLOYMENT.md describes `--flavor staging`/`.staging` bundle IDs that aren't in the committed project. If it's local-only Xcode state, it should be committed; if aspirational, the doc should be fixed.
7. **RANKED.md pre-launch checklist** (`RANKED.md:278-279`, TIER_REWARDS coin amounts "to review") — was that ever done? Ranked is live and mints coins.
8. **Scale expectations:** the perf posture (single droplet, sequential N+1s in race resolution) is fine for the current base; at what user count do you want a re-review?

---

*Lighter-review disclosure: performance, code-duplication metrics, and deep test-quality analysis received discovery-level evidence plus targeted verification rather than a dedicated adversarial finder pass; findings there are correspondingly fewer, not necessarily absent. Platform dirs other than iOS, tutorial internals, admin screens, and `apns.js`/`profilePhotoStorage.js` internals were sampled, not exhaustively read.*
