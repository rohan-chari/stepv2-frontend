# Race effect expiry: deployment readiness

Status: expiry implementation verified and code-reviewed; **production sign-off remains blocked by unresolved baseline regression failures**.

Scope: [approved architecture](race-effect-expiry-architecture-requirements.md). The user authorized TDD implementation and integration tests simulating load, through verified deployment readiness. No production writes, deployment, staging startup, or app upload are authorized by this report.

## Candidate and final expiry verification

Both repositories use branch `fix/race-effect-expiry`. Backend implementation revision: `2a50c4cdceeda809aed033c917ae5109bc5c47cd` (followed by test-only statistics fix `11c0f61`). Frontend implementation revision: `26f51143ba12122f38292f7a12eebf3032d4397d`. Both branches are pushed; no merge, deployment, staging startup, or app upload occurred.

- Final sequential expiry/load/storage group: **41/41 passed**, zero skips (`/tmp/expiry-final-integration-group.log`). Command: `node --test --test-concurrency=1 --test-force-exit 'test/integration/race-effect-*.test.js' test/integration/race-resolution-post-task-storage.test.js`, with explicit verified local test `DATABASE_URL` and test-only referral HMAC configuration.
- Final load sample: 48 expirations across 12 races, 2,000 future deadlines; dispatch **53.0 ms**, publication **p95/p99 492 ms**, all HTTP confirmations **776 ms**. Locked 100-effect race: **6.774 s**, including deliberately held work and five-second cooldown. The 120-reader Redis-disabled case passes. These are local workload measurements, not million-user capacity estimates or real-device network latency guarantees.
- Backend full unit suite: **3,353/3,353 passed**. The final cleanup SQL change subsequently passed its **13/13** targeted model/migration/handoff checks and the final 41-case integration group.
- Frontend full suite: **2,964/2,964 passed**, analyzer clean, both signed production build artifacts verified below.
- Final reviewer: **SHIP**, no remaining code-review findings, including final error handling, cleanup mismatch safety, fixture DI, and real transaction/statistics test corrections.
- Public/self-profile strict fixtures now include four already-existing stats fields without removing any assertion; **11/11** targeted tests pass (`/tmp/expiry-profile-contract-green.log`), reviewer SHIP.
- Existing repair CLI lock-observation test now refreshes its transaction's PostgreSQL statistics snapshot; filters/timeouts/assertions are unchanged. Its complete suite passes **7/7** (`/tmp/expiry-leech-observer-green.log`), reviewer SHIP.

The broad backend suite is not green. Several baseline problems were corrected with preserved assertions; other existing failures remain, including a query-plan assertion rejecting a valid newer index, conflicting timezone expectations, and older standings/scoring/contract expectations. Isolated C3 standings still reports failures (`/tmp/expiry-c3-isolated.log`). No baseline failures or existing skip are waived by this document. The query-plan assertion remains unchanged pending the user's response to the protected-test question.

## Baseline

- Frontend starting revision: `eefbceb5c430b1d6fee126860dfa46ae2c49ba3f`.
- Backend starting revision: `bf3a85621eae6b4479458345c98b5dd1d76270d8`.
- Existing separate [production traffic audit](production-traffic-audit-2026-09-06.md) reports the same backend revision, two HTTP workers, one resolution process, one cron process, and stopped staging. This is previously collected observational evidence, not a fresh live verification by this implementation.
- That audit observed 629 HTTP requests in its busiest minute; 809 race-progress requests and 162 powerup-use requests over an hour. It did not measure simultaneous expiry throughput.
- Observed resolution core p95 was 1.332 seconds; request-to-start p95 was 9.023 seconds, including intentional five-second debounce. These are not expiry-specific or end-to-end app latencies.
- Local build tooling verified: Flutter 3.44.2 / Dart 3.12.2; Xcode 26.6; configured Temurin JDK 17 and Android SDK through API 36. iOS signing identities and Android signing configuration exist; release artifact signing verified as recorded below.
- Local load environment: Apple M5, 10 logical CPUs, 16 GiB RAM; Node 24.16.0; PostgreSQL 16.14; real local Redis 8.10.0. This is not a hardware-equivalent benchmark of the four-core production host.

## TDD and interim execution record

- Backend initial red: two HTTP-activation/deadline integration tests failed because deadline storage/scheduler were absent (`/tmp/expiry-tdd-red.log`).
- Frontend initial red: five expected real-screen failures for missing deadline refresh, retries, extension handling and server-generation protection (`/tmp/expiry-frontend-red.log`). Additional lifecycle/visibility and review regressions are exercised separately.
- Parent load red: simultaneous-expiry tests failed on absent deadline storage (`/tmp/expiry-load-red.log`). Subsequent execution found a real Redis-disabled no-poll expiry gap; all race jobs committed but effects remained active. This led to unconditional durable boundary consequences.
- Index regression red: EXPLAIN on the actual captured scheduler SQL lacked a deadline index range (`/tmp/expiry-index-red.log`). The volatile clock expression was replaced with a stable statement timestamp. Final green query-plan evidence remains pending.
- Interim frontend full suite: 2,962 tests passed (`/tmp/expiry-flutter-full.log`). Reviewer then identified preview/pagination edge cases; final revision must be retested.
- Interim backend unit suite: 3,352 of 3,353 passed; the remaining strict maintenance-command allowlist required the approved additive backfill command. Final source regression run remains pending.
- Interim real-Redis load: 48 due effects across 12 races with 2,000 future deadlines dispatched in 38.9 ms; deadline-to-confirmed-cache-publication p95 487 ms; all serialized HTTP confirmations completed in 864 ms. A 100-effect/participant race plus deliberately locked-job recovery completed all HTTP checks in 6.901 s, including a five-second retry cooldown. The 120-reader Redis-disabled test did not increase an already-covered queued generation. These measurements precede the final index fix/review and are not final release evidence.

Log paths above identify local execution evidence; final reproducible commands and results will be recorded before readiness is claimed.

## Latest verification (backend review still open)

- Frontend after preview/pagination review fixes: **2,964/2,964** full-suite tests passed (`/tmp/expiry-flutter-final-full.log`); analyzer clean (`/tmp/expiry-frontend-review-analyze.log`). Reviewer approved frontend. No frontend changes followed these checks/builds.
- Backend unit checkpoint: **3,353/3,353** passed (`/tmp/expiry-backend-unit-final.log`). Subsequent backend review fixes require another final run.
- Indexed scheduler/load checkpoint: **3/3** passed (`/tmp/expiry-load-final.log`), 48 due effects/12 races plus 2,000 future deadlines, 120 concurrent-reader requests, and a 100-participant locked-race fixture. Actual deadline-to-cache-publication p95 was **696 ms**, dispatch 97.2 ms, all small-fixture HTTP confirmations 1.134 s; locked large-fixture confirmations 6.979 s including deliberate five-second cooldown. EXPLAIN on captured SQL used a deadline index range, three shared buffer hits, zero future rows, 0.019 ms. These precede latest recovery fixes and need final confirmation.
- Both additive migrations applied successfully to a newly created local `steps-tracker-expiry-final_test` database (`/tmp/expiry-final-migrate.log`), including concurrent publication indexes.
- Full backend integration run against the existing test database failed and was interrupted for diagnosis (`/tmp/expiry-backend-integration-full.log`). A separate original-revision worktree with its own generated Prisma client and fresh local database now establishes baseline failures. The fresh current database avoids relying on potentially drifted persistent test schema.
- Baseline diagnosis found an existing undefined-variable exception in competition-limit updates and legacy-disabled dashboard tests relying on now-permanent defaults. These issues were surfaced before a minimal source fix and explicit legacy test fixture adjustment; no assertions were removed. Fresh current targeted run: **75/75** across dashboard contract, funded exposure admission and September 6 feature batch (`/tmp/expiry-final-targeted.log`). Broader regression checks and independent review remain required.

### Verified mobile build artifacts

Verification builds only; no upload or customer release. Both use production backend `https://steptracker-api.org` and version 2.3.12.

| Platform | Artifact | Identity / SHA-256 |
| --- | --- | --- |
| iOS | `build/ios/ipa/Bara.ipa` | `com.rohanchari.steptracker`, build 1; archive passes `codesign --verify --deep --strict`; SHA-256 `fb6551f36928ba4e320976e623696d85aa0bc67ff2b51e6e3b7b916d933dd650` |
| Android | `build/app/outputs/bundle/prodRelease/app-prod-release.aab` | `com.rohanchari.steptracker`, code 203120, debuggable false, release signer CN=Bara; SHA-256 `1de16d271d6700d98114b29714dbc5a13604b39c54f07658101f5a2347dd1658` |

Build logs: `/tmp/expiry-ios-build.log` and `/tmp/expiry-android-build.log`. iOS used the documented production ad and Google client defines; Android used `--flavor prod --build-number=203120`. Existing iOS launch-placeholder/plugin warnings remain; builds succeeded.

### Backfill and clean-database evidence

The audited `NODE_ENV=production npm run race-effects:backfill-deadlines` command was exercised with `DATABASE_URL` explicitly set to a verified loopback dedicated `*_test` database. After the real activation/deadline integration suite created 101 eligible effects, their derived deadline rows were deliberately removed in that disposable database. The CLI restored **101 deadlines with zero missing**; a second run retained **101 with zero missing**. Logs: `/tmp/expiry-backfill-first.log`, `/tmp/expiry-backfill-second.log`. Source extension/concurrent bounded backfill tests also pass in the seven-case suite (`/tmp/expiry-backfill-fixture-tests.log`).

Schema drift was confirmed directly: the preserved database incorrectly required `race_rematch_receipts.new_race_id`, `response`, and `completed_at`; all three are nullable in a database freshly built from migrations. This explains the earlier rematch null-constraint failures without changing rematch code.

The former canonical local database had zero active connections and was preserved by renaming it to `steps-tracker-expiry-preserved_test`. The exact `npm run test:integration` command is now running against a newly created/migrated canonical database. No production or staging database was used. Baseline and fresh alternate databases are diagnostic only: a legacy CLI suite explicitly requires the canonical database name and consequently fails its unchanged safety assertion in alternate databases.

Root's competition-limit and dashboard-fixture fixes received independent reviewer **SHIP**. Three further mechanical strict-contract updates add already-existing notification/feedback/friend fields without removing prior assertions; feedback also asserts the new values. Their targeted run passed **50/50** (`/tmp/expiry-contract-additive-green.log`), and independent review found no test-integrity issues. The pre-update red log is `/tmp/expiry-contract-failures-diagnosis.log`. Expiry review remains open; the old five-minute recovery sweep's interaction with covered generations is being tested/fixed. Query-plan assertion mismatch is surfaced to the user and remains unchanged pending explicit permission under protected-test rules.

### Existing clock-fixture regression

Both baseline and fresh full diagnostic runners reached the same unbounded wait in the existing placement old/new producer test. Its race ends September 3 but the injected clocks used today's date, leaving the legacy callback unreachable. After confirming the live child processes, only those stuck diagnostic children were terminated so the parent runners could continue; those diagnostic suite results are incomplete, not passes. The test now uses a consistent clock inside its fixture window and has a 15-second timeout. All lock/CAS/dedupe assertions remain. The complete corrected suite passed **22/22** (`/tmp/expiry-placement-clock-green.log`) and received reviewer **SHIP**. The canonical full run loaded the corrected test.

### Full backend diagnostic results

All three broad runners reached terminal exit 1; none is reported as green:

| Run | Passed | Failed | Existing skipped | Log |
| --- | ---: | ---: | ---: | --- |
| Original revision, independent client/database | 2,645 | 163 | 1 | `/tmp/expiry-baseline-full.log` |
| Fresh alternate current database | 2,728 | 106 | 1 | `/tmp/expiry-fresh-integration-full.log` |
| Exact canonical `npm run test:integration` | 2,739 | 99 | 1 | `/tmp/expiry-canonical-integration-full.log` |

These are diagnostic checkpoints taken while fixes were being developed, not final-revision release passes. Original/fresh alternate runs include the deliberately terminated hanging placement child and canonical-name safety failures. The canonical run loaded some strict-field tests before their corrections. Concurrent legacy Redis suites share a test key prefix even with separate Postgres databases; their five additional canonical-only cache failures disappear when run alone: **25/25** C1/C2 tests pass (`/tmp/expiry-redis-regression-isolated.log`). Future broad runs must be sequential or have isolated Redis namespaces.

Another baseline test replaces the Prisma transaction proxy and recurses, contaminating later single-writer cases. It was corrected to pause a real scoped transaction while preserving all concurrency/cursor/duplicate-award assertions. The complete targeted suite now passes **49/49** including the real watchdog test (`/tmp/expiry-single-writer-transaction-green.log`) and received reviewer **SHIP**. Remaining baseline failures still require diagnosis; this report does not waive them.

### Reviewed expiry candidate

Independent code review now reports **SHIP**, with no remaining implementation blockers. The complete new deadline/cache/publication/index group passes **28/28**, zero skips (`/tmp/expiry-backend-reviewed-final2.log`). It executes non-UTC creator fallback, both old-sweep queue states, invalid-gate viewer polls through committed repair, lock-timeout intake, recovery after removed source deadlines, old-worker boundary adoption, real Redis outage restoration, extension through worker delivery, and full-snapshot Lua generation rejection. Additional representative timed powerup types are being exercised before final packaging.

After the implementation agent confirmed its tests had exited, the load suite was rerun alone: **3/3**, zero skips (`/tmp/expiry-load-reviewed-isolated.log`). For 48 effects across 12 races with 2,000 future deadlines, dispatch was **37.7 ms**, observed publication **p95/p99 461 ms**, and all serialized HTTP confirmations completed in **779 ms**. With only 12 race-publication observations, these percentiles are fixture summaries, not population estimates. The 100-participant locked-race fixture completed HTTP confirmations in **6.749 s**, including deliberate five-second backoff. The concurrent 120-reader/Redis-disabled case also passed. An overlapping preliminary timing run is not used as final performance evidence.

### Expanded expiry and final unit checkpoint

The final unit run passes **3,353/3,353**, zero skips (`/tmp/expiry-backend-unit-final-candidate.log`). Four older isolated query fixtures now explicitly inject their existing enqueue dependency; assertions are unchanged. A real PostgreSQL relation outage test additionally verifies that nontransactional progress reads preserve their established best-effort behavior, while transactional errors still propagate. Its initial Prisma monkeypatch contaminated later proxy calls; replacing it with a real local relation rename/restore restored all strict recovery assertions.

The expanded expiry group passes **32/32**, zero skips (`/tmp/expiry-backend-final32b.log`). Beyond the reviewed 28 cases, it covers real timed boost/defense/attack activation and post-expiry step uploads without an expired modifier. Cleanup receipt visibility is undergoing a bounded correction with its existing failing integration test; subsequent verification will cover that final change.

## Completion evidence

Every row must be supported by current code and recorded test output before this report can claim readiness. A green helper test alone is not proof of the HTTP/worker path.

| Requirement | Evidence / status |
| --- | --- |
| Unchanged old-client API across full/compact/paged/team progress | Real HTTP coverage in final 41-case group; unit hidden-effect/capability checks and full Flutter suite pass |
| Failing integration tests precede backend business logic | Red/green logs recorded above; final reviewed group 28/28 |
| Failing real-screen tests precede frontend logic | Initial and reviewer red/green logs above; final full suite 2,964/2,964 |
| Durable deadline trigger, safe backfill, bounded indexed scheduler | Reviewed deadline/index suites, actual captured SQL EXPLAIN, audited CLI restores 101 missing rows and reruns with missing=0 |
| Duplicate schedulers, lost wake, crash boundaries, extension/cancellation safety | Final 41-case group exercises atomic rollback, duplicate dispatch, executed extension, terminal-race ownership, failed/lost work and fair recovery |
| Source-window scoring and late-sync behavior preserved | New representative boost/defense/attack and non-UTC public-path tests pass; broader historical scoring baseline failures remain unwaived |
| No poll-induced generation starvation; viewer scope retained | Real locked/running worker + distinct viewers + invalid gate + old sweep cases pass; 120 concurrent reads do not advance covered generation |
| Consequences and publication independent of notification delay | Current-task and preceding-task provider delays tested; independent snapshot lane and exact-once load outcomes pass |
| Durable snapshot repair and supersession guards | Final 41-case group covers real restored Redis publication, old full-write rejection, missing/queued jobs, and retained repair after cleanup |
| Full/lean/paged/team/Redis-unavailable freshness | Real HTTP/worker/Redis cases pass in reviewed 28-test group |
| Client budget, lifecycle, concurrent requests, malformed timestamps, demo/tutorial | 22 expiry real-screen cases, 57 relevant tests, final 2,964 full-suite passes |
| Measured simultaneous expiry and idle-race load | Final isolated/sequential observations and captured SQL EXPLAIN recorded above; 48-effect multi-race, 100-effect locked race, and 120-reader cases |
| Backend required regression suites | Full unit + final targeted integration green; broad integration baseline failures remain a sign-off blocker |
| Flutter analyze and full Flutter suite | Analyzer clean; final full suite 2,964/2,964 |
| Matching iOS and Android artifacts verified | Signed release builds and identities recorded above; no upload |
| Additive migration exercised locally; backfill rerun tested | Both migrations applied fresh; audited maintenance command twice succeeds, 101 deadlines/missing=0 |
| Code-reviewer findings addressed | Final implementation, expanded type tests, and all root corrections reviewed SHIP |
| Deployment commands, maintenance-role admission and rollback verified | Backend deployment runbook, fresh migrations, audited production-mode CLI against local test DB, invalid-index retry and additive rollback documented; no live deployment executed |

## Production boundary

The final package must identify exact revisions/artifacts, migrations and backfill commands, supported test load, and observed limitations. Preserve the existing production topology and use the repository's safe reload procedure. Old mobile clients continue their existing polling behavior; the new client refresh does not require a new backend field. Release backend first.

No production step has been executed as part of this implementation.
