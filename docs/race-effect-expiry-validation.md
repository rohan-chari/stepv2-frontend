# Race effect expiry: deployment and validation

Status: **backend deployed and post-deploy checks passed**, 2026-09-07 UTC. The user explicitly authorized production deployment after confirming remaining regression failures also reproduce on the production baseline. Those failures remain visible and are not represented as passing tests.

## Shipped revision and authorization

- Backend production/main: `2679cb61be3c62dcd6cf070f145d5959f6596892`.
- Previous production revision and comparison baseline: `bf3a85621eae6b4479458345c98b5dd1d76270d8`.
- Frontend implementation: `26f51143ba12122f38292f7a12eebf3032d4397d`, on `fix/race-effect-expiry`; subsequent commits only record validation. App artifacts are verified below. No App Store/Play upload or customer app release occurred.
- Scope and invariants: [approved architecture](race-effect-expiry-architecture-requirements.md). Backend deployment procedure: the backend repository's `docs/race-effect-expiry-deployment.md` and guarded PM2 runbook.
- Final independent reviewer: **SHIP**. All 28 remaining full-suite failures have matching baseline evidence; no current-only failure remains unproven. The user accepted deployment under this condition. Existing assertions and the existing skip were not removed or weakened.

## Production execution

Production revision, dirty files, process topology and migration state were inspected first. The only existing checkout modification was npm peer metadata in `package-lock.json`; its patch was preserved on the host before the fast-forward. No unrelated local untracked files were deployed.

1. Fast-forwarded backend main and the production checkout to the reviewed revision; installed dependencies.
2. Applied `20260906210000_race_effect_deadlines` and `20260906220000_race_expiry_publication_indexes`. Both completed. All three concurrent indexes are valid and ready.
3. Generated Prisma Client. Ran the audited production maintenance command `npm run race-effects:backfill-deadlines`: **147 scanned, 147 deadlines, 0 missing**.
4. Ran the guarded `pm2-safe-prod-reload.sh`. It completed successfully and saved the verified topology: **two HTTP workers, one resolution worker, one cron worker; staging stopped**. Pool ceilings remain **10 + 10 + 8 + 4 = 32**. No capacity change or release flag was introduced.
5. Powerup-copy audit found no changes; referral-contest audit returned zero missing race activities and zero missing review ownership. No repair apply was needed for either audit.
6. Public API health and Redis returned `ok`; marketing, privacy and support endpoints returned HTTP 200.

Final read-only observation at **02:36:20 UTC**:

- Zero overdue effects in active races; zero active-race effects missing deadlines; zero undispatched due deadlines; zero deferred viewer intents.
- All **1,413** retained race jobs were succeeded at that observation. The startup queue alarm cleared as the backlog settled.
- The new resolution PID had recorded **210 commits**, including a live `EFFECT_BOUNDARY` commit. PIDs/restart counts were stable across observations.
- Snapshot repair recovery had made **295 intents terminal**, with 3 pending; recovery remains bounded background work, not a requirement to erase all historical records before release.
- Four old active-effect rows in terminal races had no deadline after scheduler cleanup. They are outside active-race eligibility; the backfill's initial global missing count was zero before that cleanup.
- No new database exception or deadline-tick failure was observed. Initial overdue warning reflected old terminal-race deadlines and disappeared after cleanup. Existing scheduled-race eligibility warnings and a pg deprecation warning remained.

These are immediate deployment observations, not a peak-window capacity guarantee. No synthetic integration/load tests were run against production, and no player powerups were created for verification.

Execution logs: `/tmp/expiry-prod-stage.log`, `/tmp/expiry-prod-migrate-backfill.log`, `/tmp/expiry-prod-reload.log`, `/tmp/expiry-prod-final-observation.log`, `/tmp/expiry-prod-runtime-final.log`, `/tmp/expiry-prod-copy-audit.log`, `/tmp/expiry-prod-referral-audit.log`.

## Final test evidence

| Check | Result |
| --- | --- |
| Complete new expiry/load/storage group | **41/41**, zero skips; `/tmp/expiry-production-path-final-group.log` |
| Backend full unit suite | **3,353/3,353**, zero skips; `/tmp/expiry-backend-unit-final-candidate.log` |
| Final cleanup SQL correction | **13/13** targeted unit checks plus the complete expiry/storage integration group; `/tmp/expiry-cleanup-unit-green.log` |
| Exact backend `npm run test:integration` | **2,820 passed, 28 failed, 1 existing skip**, 2,849 total, zero cancellations; `/tmp/expiry-regression-current-full.log` |
| Baseline comparison | 27 matching failures in `/tmp/expiry-baseline-full.log`; remaining Uprising cast failure reproduced on unchanged baseline in `/tmp/expiry-baseline-duration-recheck.log` |
| C3 cache suite | **25/25**; included in final full run. Existing cache/HTTP/worker assertions preserved |
| Scheduled-race suite | **3/3**; included in final full run. Rewound fixture's outbox and immutable start receipt consistently |
| Frontend full suite | **2,964/2,964**; `/tmp/expiry-flutter-final-full.log` |
| Flutter analyzer | Clean; `/tmp/expiry-frontend-review-analyze.log` |
| Frontend focused expiry coverage | 22 real-screen cases, 57 relevant tests; subsequent full suite passed |

All integration runs used explicitly selected local `*_test` databases. Baseline comparison used an isolated checkout of the actual production revision, its own generated Prisma client and test database. Legacy Redis suites were run sequentially because they share a test namespace. The final backend source correction was the cleanup SQL visibility fix; subsequent candidate changes only corrected test fixtures.

## TDD and behavior coverage

Initial backend red tests failed on absent deadline storage and scheduler behavior (`/tmp/expiry-tdd-red.log`, `/tmp/expiry-load-red.log`). Initial frontend tests failed for absent deadline refresh/retries/extension guards (`/tmp/expiry-frontend-red.log`). Captured scheduler SQL initially lacked an indexed deadline bound (`/tmp/expiry-index-red.log`); the stable database statement timestamp fixes that access path. Existing storage regression caught same-statement receipt visibility before the cleanup correction.

The final integration group exercises public timed boost/defense/attack activation, actual scheduler/worker/publication, post-expiry sample intake without expired modifiers, non-UTC scoring, extension after dispatch, duplicate dispatch, failed/lost work, concurrent backfill/source mutation, raw SQL source changes, invalid viewer gates, lock-timeout intake, fair recovery, Redis outage/restoration, full/lean/paged/team progress, old snapshot generation rejection, delayed notification providers, notification non-replay and durable repair after compaction. The final cleanup test preserves exact receipt mismatch rejection.

Frontend real-screen tests cover shared retry budget, multiple effects, lifecycle/visibility, pagination races, malformed timestamps, demo/tutorial clocks and old/missing metadata. There is no optimistic settlement or effect removal based only on the device clock.

## Load evidence and limits

The final load harness explicitly selects the production HTTP branch and a resolution-role worker after bootstrapping the instrumented local test database. The SQL instrumentation pool is local test infrastructure, not a claim to reproduce production hardware.

Isolated final production-path load: **3/3 passed**, zero skips (`/tmp/expiry-production-path-load.log`):

- 48 simultaneous effects across 12 races, with 2,000 future deadlines: dispatch **39.2 ms**, deadline-to-publication **p95/p99 459 ms**, all serialized HTTP confirmations **667 ms**.
- One 100-participant/100-effect race with deliberately held work: all HTTP confirmations **6.661 s**, including the five-second contention cooldown.
- 120 concurrent readers with Redis unavailable did not churn an already-covered generation.

Only 12 race-publication samples underpin the percentile figures. This demonstrates the specified fixtures and indexed bounded work; it does not establish million-user capacity or real-device network latency. Earlier load samples that did not explicitly select the production HTTP branch are superseded by this run.

Hardware: Apple M5, 10 logical CPUs, 16 GiB RAM; Node 24.16.0; PostgreSQL 16.14; Redis 8.10.0. Production is a different host. The scheduler does work proportional to due bounded batches, not all registered users each second.

## Matching mobile artifacts

Both signed production artifacts were built and verified; hashes were rechecked after backend deployment. They are verification artifacts for **2.3.12+1**, not uploaded releases. Frontend application code has not changed since those builds.

- iOS: `build/ios/ipa/Bara.ipa`, bundle `com.rohanchari.steptracker`, version 2.3.12/build 1; strict deep codesign check passed. SHA-256: `fb6551f36928ba4e320976e623696d85aa0bc67ff2b51e6e3b7b916d933dd650`.
- Android: `build/app/outputs/bundle/prodRelease/app-prod-release.aab`, prod flavor, version 2.3.12/code 203120; debuggable false, release signer CN=Bara. SHA-256: `1de16d271d6700d98114b29714dbc5a13604b39c54f07658101f5a2347dd1658`.
- Build logs: `/tmp/expiry-ios-build.log`, `/tmp/expiry-android-build.log`. Existing launch-placeholder/plugin warnings were recorded; signing/artifact verification passed.

Older app binaries benefit from server-side deadline processing through their existing polling. The accelerated client refresh arrives only in a subsequent paired mobile release. Backend API fields, required parameters and endpoint behavior remain compatible; no new client field is required. Rollback retains the additive schema and durable work, using the established guarded procedure.
