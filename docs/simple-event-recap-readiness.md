# Simple event recap — implementation and production-readiness evidence

Status: ready for backend production deployment approval. Implementation and
independent review are complete; recap-specific release checks pass. On
2026-09-11 the user explicitly chose to track the baseline test failures
separately. Nothing deployed. Physical-device checks remain part of the new app
release checklist; this is not an all-green repository claim or authorization
to deploy or upload apps.

Approved behavior and cleanup: [requirements](simple-event-recap-requirements.md).
Backend API contract: backend repository `docs/simple-event-recap-api-contract.md`.

## Baselines and ownership

- Frontend baseline: `587d8cb`. Unrelated documentation and economy edits preserved.
- Backend baseline: `9b08e5f9b50250cae431177e67e73e24dd6b2b34`, verified against production HEAD with a read-only command before implementation.
- Backend implementation is isolated on `feat/simple-event-recap`; no production/staging changes are authorized.
- Contract pinned in backend commit `2f8503d` before frontend implementation began.

## Verification gates

| Requirement | Evidence / status |
| --- | --- |
| Baseline Flutter analysis | Passed, no issues. |
| Baseline MainShell + step-sync API tests | 163 passed before implementation. |
| New tests fail before implementation | Frontend real MainShell sequence, backend contract, retirement source guard, and after-B retention regression recorded red before their implementation fixes. |
| Exact-window read, successful-sync gate, same-day expiry | Implemented; latest 42 recap widget tests passed independent review. |
| Start-time race count, once-only calculation, ownership/concurrency | Real boundary-processing + HTTP tests pass, including late joins/leaves/finishes, zero and ambiguous cohorts; immutable first result and midnight lock delay covered. |
| Old Home, acknowledgment and receipt compatibility | Selected expanded 27-case integration group passes, including old capability headers, stateless work shim, expiry, complete/gapped/overlapping legacy inputs and both account-deletion schema states. |
| All recap worker/poll/capture paths retired | Source audit/structural guard covers all 21 retired-table families. Live local source mutations produce zero old capture work. Post-drop operational snapshot passes. |
| Actual event/race scoring, queues and notifications preserved | Matched traces preserve all scores; real settlement retains 200 steps, winner/placement, payout 10 and coins +10. End/recovery mixed suites pass 26/26 on local PG16; PG18 has one unchanged baseline SQLSTATE assertion failure. |
| Additive migration, stopped-writer cutover, delayed destructive cleanup | Final populated rehearsal passed, including partial-stamp CHECK rejection, copied values, stopped-client gate, source-trigger removal, 1,000-point scratch deletion, retention between releases, midnight-boundary orphan cleanup and final-drop rerun. Post-B four feature suites: 26/26 passed; operational snapshot: 1/1 passed. |
| Before/after work and DB-resource comparison | Three final stable-source candidate traces completed against three baseline traces with identical scores and recaps; see comparison below. |
| Final Flutter analysis and tests | Analysis clean. Full suite: 3,439 passed / 36 failures, exactly matching the 36 unchanged-baseline Admin failures; no new failures. Full suite is not green. |
| Both native platforms build | Final unsigned iOS release app and production Android bundle passed. Packaged iOS config and all three Android ABIs verified; no uploads. |
| Independent code review | Final combined verdict SHIP: no remaining blockers/issues. All retention, initialization, start-cohort, source-retirement and monitoring findings resolved. |
| Manual placement checklist | Delivered with the spec; physical-device checks not yet performed. |

## Production boundary

Readiness means the replacement code, tests, migration artifacts and deployment procedure are prepared and verified locally. It does not mean production migrations have run. Replacement deployment removes worker activity and detaches capture triggers; inert retired tables are dropped in a separately authorized release at least one week later. Their scheduled physical removal remains a tracked deployment obligation, not retained running infrastructure.

Production-wide CPU savings require post-deployment measurement under comparable traffic. Local query reductions or removed triggers are not proof of a particular whole-database CPU percentage.

## Explicit remaining release decisions

- Production deployment requires fresh approval, backup/restore evidence,
  current process/catalog audit, a stopped-writer cutover and backend-first order.
  No capacity change is authorized. A read-only connection inventory observed
  only application sessions, not provider monitoring clients; repeat it at deploy.
- Physical-device checklist in the approved spec is handed off but not run on
  real iOS/Android devices. Verification builds are not uploaded release builds.
- Full Flutter suite retains 36 pre-existing Admin failures. Backend broader
  suites retain four independently reproduced baseline failures (dependency
  closure, display artifact claim, Drill Sergeant impact and enrollment timezone),
  plus a protected PG18 foreign-key SQLSTATE expectation. No assertion was
  weakened or skipped. The user explicitly chose separate tracking on
  2026-09-11; see [the follow-up register](existing-test-failures-2026-09-11.md).
  These specific existing failures no longer block this recap release. Do not
  describe the entire repository as green or extend this decision to new failures.
- Backend full units: 3,361 passed. Dedicated replacement/migration/cache group:
  27 passed. Broader shared group: 122/125 passed, with the three baseline failures
  above (enrollment and PG18 check were separate runs).

SQL rehearsal evidence: [populated rehearsal](artifacts/simple-event-recap/sql-rehearsal.json).

## Local matched-workload comparison

Six synthetic users, three shared races, six contiguous samples per user, 60
raw event steps each. Actual event-start/end processing, HTTP step sync, real
resolution/post/placement workers, recap retrieval/acknowledgment and all 18
HTTP race-progress reads; then 65 seconds idle. Both variants produced six
recaps of 180 extra steps and all 18 race scores of 120. Queues drained.

| Measurement | Old baseline (3 runs) | Replacement (3 stable-source runs) |
| --- | --- | --- |
| Sync-through-recap SQL commands | 3,064 / 3,047 / 3,052 | 509 / 513 / 510 |
| All observed application SQL commands | 5,266 / 5,267 / 5,270 | 2,649 / 2,652 / 2,650 |
| PostgreSQL process CPU seconds | 0.99 / 1.09 / 1.11 | 0.69 / 0.88 / 0.93 |
| WAL bytes during trace | 1,595,672 / 2,423,776 / 1,739,832 | 1,085,744 / 583,048 / 457,456 |
| Time through recap and drained work (ms) | 6,095 / 6,124 / 6,124 | 6,091 / 6,088 / 6,095 |

Median sync/recap SQL fell approximately 83%; whole-trace SQL approximately
50%. Idle SQL remains because ordinary resolution workers still run. This
small no-powerup workload is evidence of less work, not a capacity benchmark
or a production-wide CPU guarantee. CPU sampling uses cumulative process time
at 10ms precision and can miss short-lived processes between samples. WAL
includes background PostgreSQL activity; SQL elapsed time is not CPU time.
Table-stat deltas are deliberately not reported as exact workload writes:
asynchronous statistics flushing allowed fixture-cleanup counts to bleed into
later snapshots. Separate direct source-mutation checks prove zero retired
journal/revision/work changes after cutover.

The three replacement traces used the same source fingerprint
`97588129be335bc6c143ec7fa07c7406d8dd397b7440215ca6dab6d57c39789e`, unchanged
within each run. The only subsequent runtime delta is a monitoring query now
counting `event_recaps` rather than the dropped old table, plus a stale startup
comment. The monitoring path passed independently after physical table removal;
no measured step/recap/scoring path changed.

Compact evidence and original trace hashes: [matched workload](artifacts/simple-event-recap/matched-workload.json).

## Mobile artifact verification

Verification version: 2.3.13+23; Android version code 203153. Not a new uploaded
release. Final Android SHA-256:
`cbb38686fc4f9756153c9ba46b1e41962928307ef06c46eb9188fad37f9ec816`.
The known stale Gradle native-packaging cache was refreshed and all three
packaged ABIs contain the new recap route/capability, not the retired polling
URL. iOS production backend/OAuth/RevenueCat and seven retained ad-unit values
were checked in the compiled app without exposing credentials.
