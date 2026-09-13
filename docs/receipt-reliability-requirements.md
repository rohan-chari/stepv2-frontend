# Domain-event receipt reliability requirements

Status: single-deployment revision architect-approved and explicitly approved
by the user for implementation on 2026-09-11. Implementation and verification
are underway. Production deployment still requires separate authorization.

## Summary & user story

As the backend, every committed domain event must have a durable, immutable receipt without relying on a broad nightly scan. This prevents duplicate processing and makes retries/replays safe while reducing database work on the production PostgreSQL cluster.

The long-term design preserves the existing transactional outbox and receipt model, makes receipt creation part of the normal event append transaction, and limits repair to an explicitly bounded recovery path for exceptional historical or failed cases.

## Scope / non-goals

In scope:

- Audit every domain-event creation path and make receipt reservation occur in the same Prisma transaction as the outbox event.
- Preserve receipt immutability, digest validation, idempotency, and old event replay behavior.
- Replace the daily broad receipt backfill scan with a bounded, indexed recovery mechanism for legacy/missed rows.
- Add metrics and operator-visible evidence for created, repaired, failed, and permanently quarantined receipts.
- Safely migrate the existing historical backlog after classifying it.

Out of scope:

- Changing user-facing APIs, Flutter UI, event payload contracts, notification semantics, or product policy.
- Removing the outbox, receipts, retries, or replay support.
- Treating a receipt as proof that every downstream notification was delivered; projection and delivery receipts remain separate.
- Adding a release flag or runtime kill switch.

## Current behavior and evidence

- `appendDomainEvent` reserves receipts when the receipt model is available: backend `src/modules/domainEvents/commands/appendDomainEvent.js:126-149`.
- Bulk append also reads receipts and live events: `appendDomainEvent.js:221-267`.
- `DomainEventReceipt.reserve` creates a FINAL receipt with an envelope digest and rejects immutable-envelope collisions: `src/modules/domainEvents/models/domainEventReceipt.js:53-103`.
- `backfillPage` scans `domain_event_outbox` with a left join for missing/PROVISIONAL receipts and locks up to 500 rows: `domainEventReceipt.js:187-232`.
- `domainEventRetention` calls up to ten receipt-backfill pages once per ET day: `src/modules/domainEvents/jobs/domainEventRetention.js:32-52`; it is scheduled from `src/index.js:344`.
- Production read-only diagnostics found 837,422 outbox events, 380,716 missing receipts, and 253 provisional receipts. The candidate plan scans approximately 850k outbox rows and 460k receipt rows. These counts must be rechecked at implementation time because they are mutable production state.

## Desired behavior

For every new domain event written by the application:

1. Build and canonicalize the event envelope.
2. In the same database transaction, insert the outbox event and its receipt, or atomically reserve the receipt against the existing event when idempotently replaying.
3. If the transaction rolls back, neither the event nor its receipt is visible.
4. If a duplicate event key is retried, return the existing matching receipt; an envelope mismatch remains a hard collision.
5. No new required API parameter or frontend behavior is introduced.

For exceptional failures or legacy rows:

- Write a bounded recovery candidate keyed by `domain_event_id`/`event_key`, with reason, attempt count, next-attempt time, lease, and terminal error fields.
- Candidate transitions are `QUEUED -> PROCESSING -> SUCCEEDED`, `PROCESSING -> RETRY`, or `PROCESSING -> FAILED_TERMINAL`. Claims use a short transaction and `FOR UPDATE SKIP LOCKED`; processing occurs outside it. Success/failure uses lease-token compare-and-set.
- Retry policy: max 8 attempts; backoff 1m, 5m, 30m, 2h, capped at 6h, with bounded jitter. Lease duration is 2m. Missing source events become terminal `SOURCE_DELETED` candidates retained for evidence.
- Recovery must load the original outbox event and audience, then use the same `reserve`/`finalize` invariants; it must not invent payloads or silently overwrite FINAL receipts.
- Permanent failures go to a terminal state with sanitized error metrics and operator evidence; they are never retried indefinitely.

## API contract

No public or authenticated app API changes are required. Existing endpoints retain their request and response JSON. The backend remains compatible with old app versions because receipt creation is server-side and additive; old clients continue sending the same requests and receive the same responses.

Any internal/admin diagnostic endpoint, if needed, must be read-only, authenticated, bounded, and return missing fields safely. It is not required for the first implementation.

## Data model / migrations

Preferred design:

- Add a `domain_event_receipt_recovery` table (exact name to be confirmed against backend conventions) with: id, domain_event_id, event_key, reason, status (`QUEUED`, `PROCESSING`, `SUCCEEDED`, `RETRY`, `FAILED_TERMINAL`), attempt_count, available_at, lease_until, lease_token, last_error_code, last_error_at, created_at, updated_at, completed_at. Add status and nonnegative-attempt CHECK constraints.
- Add unique constraints on `domain_event_id` and `event_key`; unresolved candidates must not cascade-delete with an outbox row. Add partial due `(available_at,id)` and lease `(lease_until,id)` indexes matching claim predicates.
- Do not add a table-wide backfill trigger that scans all outbox rows on every write.
- The normal append transaction must create a FINAL receipt directly. A database trigger is not preferred because it would duplicate canonicalization/digest business logic and may break existing fixture/test paths; architect review must explicitly validate this choice.

Migration and backlog order:

1. Add the recovery table/indexes without changing existing writers.
2. Apply and verify schema before the new binary. Retain the provisional-receipt compatibility trigger from `prisma/migrations/20260902120000_durable_queue_receipts_and_readiness/migration.sql:94` during old/new process overlap.
3. Route every raw/bulk writer—including `globalStepEventEntitlement.js:144` and `globalEventTimezoneReconciliation.js:313`—through one receipt-aware transactional primitive; production receipt unavailability is a hard error.
4. Classify existing rows by an explicit age/status cutoff. Use resumable keyset discovery on `(created_at,id)`, backed by an outbox `(created_at,id)` index, and idempotent candidate insertion; do not repeat the unbounded left join.
5. Drain in bounded batches with set-based event/audience reads and no production `EXPLAIN ANALYZE`; reconstruct and digest-validate every envelope.
6. Verify zero eligible missing/provisional rows for the cutoff and preserve excluded/terminal evidence.
7. In the same deployment, replace the domain-event broad daily backfill with automatic bounded discovery owned by the recovery cron. No later code deployment or runtime release toggle is required to retire the broad scan. Keep notification-schedule receipt backfill unchanged; it is a separate subsystem.
8. During the first 24h after deployment, verify zero newly missing receipts, queue p95 age under 10m, and zero unexplained terminal failures. Repeat complete censuses until the historical cutoff is clean. These are operational acceptance checks, not a prerequisite for a second deployment. Above 30m queue age or on any new missing receipt, investigate and obtain approval for any rollback; do not silently raise concurrency.

### Single-deployment safety design

- Apply all additive migrations, including the deferred compatibility enqueue
  trigger and concurrent outbox index, before starting the new backend. At
  first automatic discovery, atomically save a database-clock cutoff under a
  new immutable `automatic-v1` checkpoint identity in the existing discovery
  table. Never adopt or reset a manual `historical-v1` checkpoint: its cutoff
  may predate trigger installation, even if marked complete. Preserve manual
  progress and revisit history through the automatic sweep; candidate
  uniqueness deduplicates existing jobs. A restart never moves the automatic
  cutoff or resets its cursor. Operator discovery must not run between migrations.
- Coverage is explicit: pre-cutoff committed history is visited once through
  bounded source pages; every insert after compatibility-trigger installation
  is checked at commit, including old binaries and transactions whose
  `created_at` predates the cutoff. Normal appends finalize atomically and
  create no recovery job. A transaction committing after a page passed its
  timestamp must still receive a candidate through the trigger.
- Each cron drain repairs its bounded page first, then may discover at most
  one historical page of 500 source rows. Fresh failures retain their reserved
  claim share. If a discovery page fails or locks time out, its cursor does
  not advance and fresh repair remains eligible on subsequent ticks.
- Historical discovery has fixed backpressure: only enqueue a page when fewer
  than 500 active recovery candidates exist. Determine that using independently
  limited indexed probes of due (`QUEUED`/`RETRY`) and leased (`PROCESSING`)
  states, never a whole-table aggregate. A page adds at most 500; historical
  discovery therefore cannot grow its own backlog without bound. Fresh
  compatibility failures remain accepted even above this discovery threshold.
  Recheck capacity in one statement snapshot while holding the `automatic-v1`
  row lock. Include future RETRY rows and unexpired PROCESSING leases as active.
  Every historical `--apply` page, including manual explicit-cursor pages,
  acquires this same admission lock and capacity check. This lock/automatic
  cutoff is initialized only after all migrations. Explicit/manual cursors
  never advance automatic progress. Refused admission returns `deferred: true`
  without advancing any cursor. Overlapping cron/manual callers cannot admit
  pages independently from a stale capacity result; claim leases still prevent
  duplicate repair.
- While discovery is incomplete and capacity exists, schedule another paced
  tick even when the previous source page contained only FINAL receipts and
  queued no jobs. On exhaustion, ordinary recovery polling continues but
  historical scanning stops permanently. The checkpoint is durable data
  progress, not a feature flag or deployment toggle.
- Existing retention must remain fail-closed: an outbox source without a FINAL
  receipt cannot be deleted. Prove that rule through the real retention path
  while historical discovery is paused, incomplete, or retrying. Missing or
  malformed source data is quarantined without inventing a receipt; preserve
  the source/evidence for operator investigation.
- A completed discovery sweep is not a completed repair. Report discovery
  progress, active/terminal candidates, and complete bounded censuses
  separately. Two zero-eligible censuses and 24h observation establish success
  after the one deployment, not an automatic claim that all legacy work was
  already finished at deployment time. Resumed operator-audit totals are
  explicitly unverified input, not automatic acceptance evidence; reconcile
  captured page reports independently when a census spans invocations.

## Backend implementation path

1. Add integration tests first under backend `test/integration/` for append success, transaction rollback, duplicate retry, envelope collision, bulk append, and recovery worker claim/backoff/terminal behavior using a dedicated test database.
2. Inventory all domain-event writers and transactions, including `appendDomainEvent`, bulk append, global-step entitlement writers, race/event paths, and test fixtures. Every production writer must route through one receipt-aware command.
3. Refactor the command/repository boundary so event creation and receipt reservation share the same transaction client and cannot silently operate with receipts unavailable in production.
4. Add recovery model/worker and metrics. Register it inside the dedicated `startCrons()` owner at `src/index.js:419`, not HTTP workers or the once-daily `JobRun` gate. Reuse `createPostgresWakeCoordinator`; Postgres polling remains authoritative and Redis is only an optional wake signal.
5. Bound page size, concurrency, timeouts, and total work to `DATABASE_POOL_MAX_CRON=4`; reserve capacity for fresh repairs over historical drain. Bulk-load events/audiences without N+1 queries.
6. Add migration and a read-only/backfill audit script that reports counts before and after; the script must not point integration tests at production.
6. Change `domainEventRetention` to remove only its domain-event broad backfill call. Move historical progress to the recovery cron's bounded discovery/backpressure loop; preserve receipt-aware retention and notification-schedule backfill.
7. Run backend integration/unit commands specified by backend `AGENTS.md` (`npm run test:unit`, `npm run test:integration`), then review query counts, WAL, queue lag, and CPU under comparable traffic.

## Frontend plan

No frontend files, screens, widgets, iOS behavior, Android behavior, or build configuration should change. Existing clients must continue to work unchanged. If a future admin diagnostic UI is requested, it must be separately specified; this feature does not require one.

## Backward compatibility & rollout

- Backend deploys first; no app release is required.
- Old clients send unchanged requests and continue receiving unchanged responses.
- Existing FINAL receipts and their digests are authoritative and immutable.
- Missing/null legacy fields encountered while reading event data must produce a safe recovery failure or unavailable state, never an invented receipt.
- No release flag, rollout toggle, or temporary runtime control is permitted. Use additive schema, the retained compatibility triggers, and durable discovery progress. Application rollback retains schema, receipts, candidates, and cursor; an older binary may temporarily resume its old scan. Never drop the new data as part of rollback, and require explicit approval for production restarts/rollbacks.
- Two production HTTP workers remain in place; recovery concurrency must be bounded below the database connection budget and coordinated with cron/resolution workers.

## Test plan (tests first)

- Integration: normal append creates exactly one outbox event and FINAL receipt in one transaction.
- Integration: forced rollback creates neither durable event nor receipt.
- Integration: retrying the same event is idempotent; mismatched envelope returns the existing collision error.
- Integration: bulk append creates matching receipts without N+1 receipt queries.
- Integration: legacy missing/provisional candidates are claimed once under concurrent workers.
- Integration: successful recovery finalizes the exact canonical envelope; malformed/missing source data becomes a bounded terminal failure.
- Integration: retry backoff, lease expiry, `SKIP LOCKED`, and terminal-attempt limits behave correctly.
- Integration: old event/API request paths remain response-compatible.
- Structural/source tests only where public integration paths cannot prove that every writer uses the shared transactional command.
- Integration: automatic cron discovery progresses through all-FINAL pages, restarts at its saved cursor, stops at exhaustion, and resumes after capacity frees. Query plans prove independently bounded active-state probes.
- Integration: incomplete and completed manual checkpoints whose cutoff predates compatibility-trigger installation cannot hide an intervening missing receipt from the new automatic sweep. Concurrent manual/cron admission obeys the shared threshold and deferral leaves progress unchanged.
- Integration: old-writer and pre-cutoff-timestamp transactions committing after a discovery page remain recoverable through the deferred trigger.
- Integration: the real retention path cannot remove missing/PROVISIONAL-receipt sources while discovery/repair is incomplete.
- Production read-only validation: counts, indexes, queue depth, repair counts, errors, WAL, and CPU before/after. Never run integration tests against production.
- Predeployment gates: schema/index rehearsal, all-writer inventory, concurrency/retention/old-writer coverage, relevant green tests and implementation review. Postdeployment acceptance: no new missing receipts for 24h, queue p95 under 10m, zero unexplained terminal failures, and two complete zero-backlog censuses. No second deployment is required.

## Acceptance criteria / definition of done

- Every production domain-event append path creates or validates its receipt in the same transaction.
- No normal event relies on the nightly broad scan to obtain a receipt.
- Recovery is bounded, indexed, observable, idempotent, and safe under concurrent workers.
- The legacy backlog is classified and drained or explicitly quarantined with evidence.
- The broad domain-event scan is removed in the same deployment that installs automatic bounded discovery and recovery; backlog draining and observation continue afterward without a second deployment.
- Existing clients and API responses remain compatible.
- Backend tests are written first and pass; `flutter analyze` remains clean if frontend files are touched; backend unit/integration commands pass against dedicated test infrastructure.
- Architect review, implementation review, and production read-only validation are complete.

## Revision log

- Draft 1: established transactional receipt creation plus bounded recovery instead of repeated full-history scanning.
- Gap pass 1: added legacy-backlog classification, immutable digest validation, transaction rollback behavior, explicit terminal failures, and no-frontend/API scope.
- Gap pass 2: added concurrency/lease limits, old-client compatibility, migration order, no-feature-flag rule, production/test database separation, and query/WAL/CPU validation.
- Architect review: required changes incorporated: enforce one transactional primitive; retain the old-client trigger; specify state transitions, CAS leases, retry policy, source deletion, keyset discovery, cron ownership, partial indexes, fairness budgets, quarantine evidence, and numeric rollout/rollback gates.
- Implementation review (2026-09-11): source paging now limits rows before joining receipts, with an atomic persisted cutoff/cursor; the existing-table discovery index is a separate concurrent migration. A deferred point-lookup compatibility trigger enqueues only committed gaps and does not canonicalize payloads or write jobs for normal FINAL appends. Recovery revalidates source lifecycle under lock before finalization, and entitlement restoration preserves the original receipt identity/timestamps. Local tests do not satisfy the production drain/observation gates; the requested all-at-once deployment preference remains to be reconciled with the later scan-removal requirement above. Backend verification evidence is recorded in `docs/domain-event-receipt-reliability-release.md` in the backend repository.
- Single-deployment revision requested (2026-09-11): supersedes the prior later-deployment scan-removal plan. Add automatic, checkpointed, backpressured historical discovery to the existing recovery cron and remove only the domain-event broad scan in that same release. Keep live observation as postdeployment acceptance, not as a second code-release gate.
- Revision gap pass 1: made late-committing old-writer coverage explicit, required database-clock cutoff after all migrations, protected receipt-incomplete sources from retention, and separated discovery completion from repair completion.
- Revision gap pass 2: added independently indexed bounded capacity probes, serialized admission under the checkpoint lock, all-FINAL-page timer progress, crash/restart behavior, and required integration tests. No frontend/API/product-policy changes or release controls are added.
- Single-deployment architect review: adopted required independent `automatic-v1` sweep identity to prevent unsafe reuse of old manual cutoffs; all historical apply paths share its admission lock/capacity contract, while manual cursors never alter automatic progress. Capacity probes use one statement snapshot and include future retries/unexpired leases. Operator instructions must explicitly state that stopping manual commands does not pause automatic discovery; incident response is investigation and an explicitly approved application rollback, not a new toggle.
- Architect re-review: APPROVE, no remaining required changes or suggestions. This approves the design only; revised-behavior implementation and production deployment approval remain separate.
- User approved revised implementation. The old staged-rollout test expectations (broad scan still called) are intentionally updated to assert its absence and preserve notification-schedule backfill under the new approved behavior, not weakened or skipped to mask failures. New real-database scheduler and retention tests were added and reproduced the missing automatic workflow before implementation.
