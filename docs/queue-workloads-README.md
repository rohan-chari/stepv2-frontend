# High-Workload Queue Pipelines

This document explains the five queue workload groups that are expected to do
the most work in production:

1. race resolution;
2. notifications;
3. large-race resolution-trigger intake;
4. placement transitions and race-resolution post-tasks; and
5. global-event summaries.

It describes the implementation as of September 2, 2026. The source of truth
is the backend repository. This file lives in the frontend repository because
the mobile app initiates some of these flows and observes their results.

## First: what “queue” means here

These are not twelve BullMQ, SQS, or RabbitMQ queues. The important queues are
durable PostgreSQL tables. Producers insert or upsert work rows in the same
transaction as the business fact that created the work whenever atomicity is
required. Workers poll indexed eligibility columns, claim bounded batches with
`FOR UPDATE SKIP LOCKED`, and use leases or generation fences to prevent stale
workers from committing.

Redis is used for disposable caches and wake-up hints. Losing a Redis wake-up
must not lose durable work because PostgreSQL polling remains authoritative.

Production separates responsibilities into:

- two HTTP processes, which accept requests and enqueue work;
- a dedicated resolution process, which owns race resolution and its immediate
  downstream race workers; and
- a cron process, which owns scheduled work, notification projection and
  delivery, global-event lifecycle work, and maintenance jobs.

The sections below distinguish four concepts that are easy to conflate:

- **producer:** code that says work is required;
- **durable row:** the database record that survives crashes and restarts;
- **claim:** temporary ownership of a row by a worker;
- **fence:** the final check that prevents an expired or superseded owner from
  writing stale results.

## Shared reliability model

Although each pipeline has specialized state, the main queues follow the same
general lifecycle.

1. A request, cron boundary, or earlier worker commits a business fact.
2. It inserts or upserts a queue row, preferably in that same transaction.
3. A worker polls for due rows.
4. The worker locks candidates with `FOR UPDATE SKIP LOCKED`. Multiple workers
   can poll without selecting the same locked row.
5. The claim records a lease token and lease-expiration time. Some queues also
   snapshot a generation number and move pending inputs into processing fields.
6. Expensive computation is performed outside a long database transaction when
   possible.
7. Before writing, the worker reacquires and validates its durable ownership.
8. The worker commits outputs and the queue transition atomically.
9. If newer work arrived during processing, generation-aware queues return to
   the queued state instead of declaring the newer generation complete.
10. A retryable failure records a bounded error code and a future retry time.
11. If a process dies, another process may reclaim the row after lease expiry.
12. Unique keys, compare-and-set updates, generation checks, and delivery keys
    make replay safe or explicitly suppress duplicate materialization.

“At least once” therefore describes worker execution, while business effects
are designed to be idempotent, fenced, or compare-and-set.

---

## 1. Race resolution

### Why this is the heaviest compute queue

Race resolution is triggered by high-frequency step intake and by most state
changes that can alter a race. One claimed row can require loading a full race,
canonical step inputs, active power-ups, event multipliers, participant state,
box thresholds, and settlement context. It may then update many participant
rows and create downstream work.

The durable unit is one race, stored in `race_resolution_jobs_v2`. A unique
`race_id` means all pending reasons for the same race converge on one row.

### Step-by-step: producing work

1. Something makes the race potentially stale. Examples include:
   - a step sync changes scoring input;
   - a power-up is used, opened, expired, or otherwise mutated;
   - someone joins, leaves, is kicked, or forfeits;
   - a race starts or approaches settlement;
   - a global-event or active-effect boundary is crossed;
   - a progress read discovers that persisted presentation state needs refresh;
   - recovery detects stale or missing output.
2. The producer goes through the centralized enqueue service.
3. The producer supplies a reason envelope. It may contain:
   - dirty reasons;
   - triggering user IDs;
   - participant IDs;
   - relevant power-up types;
   - immediate versus coalescible work; and
   - queue priority.
4. Queue priority is normalized into this order:
   `SETTLEMENT`, `RECOVERY`, `LIVE`, then `MAINTENANCE`.
5. The enqueue upserts by `race_id` rather than inserting an unbounded list of
   duplicate race jobs.
6. Normally it increments `generation`. That generation is the durable proof
   that newer work arrived.
7. Triggering IDs, reasons, and scopes are append-distinct merged, subject to
   explicit bounds.
8. A running row stays running. Enqueueing does not let a second worker process
   the race concurrently; the generation bump requests a follow-up pass.
9. `requested_at` continues to represent the oldest unserved request while a
   row is already pending, making queue-lag measurements meaningful.
10. Enqueue does not normally clear `not_before_at`. New work marks the race
    dirty but does not bypass the debounce floor.
11. When enqueue is part of step-sync intake or another atomic mutation, the
    queue row becomes visible only when that transaction commits.
12. If the transaction rolls back, the enqueue rolls back with it.

### Step-by-step: coalescing and debounce

1. The default debounce window is five seconds.
2. Repeated activity for the same race merges into one mutable row.
3. The row accumulates the union of safe scoped inputs.
4. A continuously active race therefore does not spin through a full resolution
   for every uploader.
5. If scope data is absent, malformed, too large, contains an unknown reason,
   or explicitly requests `FULL`, the worker fails closed to full-race work.
6. The queue retains an `EFFECT_BOUNDARY` marker when falling back to full work
   so time-bound effect materialization is not accidentally omitted.

### Step-by-step: claiming a race

1. The dedicated resolution worker polls every 250 ms.
2. In adaptive-drain mode, it removes idle gaps while work exists, but yields
   after bounded time/job slices so it does not monopolize the event loop.
3. Before claiming normal work after a rolling deploy, it observes the startup
   quiet-period/handoff rules so an old binary cannot still be the bulk writer.
4. The claim query considers:
   - due `QUEUED` rows whose retry and debounce times have passed; and
   - `RUNNING` rows whose lease expired.
5. It orders eligible rows by queue priority, oldest request, then race ID.
6. It takes one candidate using `FOR UPDATE SKIP LOCKED`.
7. It changes the row to `RUNNING`.
8. It snapshots `generation` into `processing_generation`.
9. It mints a fresh UUID lease token and a 30-second lease.
10. It increments the attempt count.
11. It unions abandoned processing inputs with newly queued inputs. This is the
    crash-recovery rule: inputs from a dead worker are not discarded.
12. It moves current pending fields into processing fields and clears the
    pending fields for inputs that arrive during this attempt.

### Step-by-step: planning and computation

1. The worker loads the current operational settings needed by the resolution
   algorithm.
2. It maps the accumulated reasons to either:
   - a scoped dependency-closure plan;
   - artifact reuse when a validated display artifact is safe; or
   - a full-field plan.
3. It captures or validates a fingerprint of canonical scoring inputs.
4. It checks time-sensitive validity boundaries such as race end, sample
   boundaries, active effects, and global events.
5. For scoped work, it builds the participant dependency closure needed to
   calculate the same answer as a full pass.
6. If the closure cannot prove safety—for example, an ambiguous trail-mine
   target—it escalates to full resolution.
7. The expensive score computation occurs outside the final write transaction.
8. The result includes participant total writes, side-effect state changes,
   effective steps for mystery-box thresholds, and any event/impact work that
   must be persisted under the race fence.

### Step-by-step: fenced commit

1. The worker opens the authoritative write transaction.
2. It reacquires the race-resolution job by ID, lease token, processing
   generation, and unexpired lease.
3. This queue-row lock is the global serialization point for bulk writes to the
   race’s participant rows.
4. It revalidates source-input fingerprints where required. A changed input
   causes rejection/replanning rather than a stale commit.
5. It locks affected participant rows in stable user/ID order.
6. It locks mystery-box candidates in the same stable order and rechecks their
   eligibility after locking.
7. It writes participant totals, raw totals, penalties, and related state.
8. It applies fire-once effect bookkeeping in the same transaction as the
   totals that caused it.
9. It synchronizes due mystery boxes and advances thresholds atomically with
   the authoritative totals.
10. It persists active-impact work when a relevant boundary was part of the
    claimed reasons.
11. It creates the placement-transition handoff for the successfully resolved
    generation.
12. When enabled and applicable, it creates the durable post-task handoff.
13. It attempts to mark the queue generation successful inside this same
    transaction.
14. Success requires the lease and processing generation still to be current.
15. If nobody enqueued during computation, the row becomes `SUCCEEDED`, clears
    ownership fields, records completion, and advances the debounce floor.
16. If a newer generation exists, the current writes may still be valid for the
    captured generation, but the row returns to `QUEUED` for a follow-up pass.
17. The transaction commits all authoritative race changes and the queue-state
    transition together.

### Step-by-step: after commit

1. The worker publishes/replaces disposable Redis race-progress snapshots from
   the exact totals it committed.
2. It invalidates or refreshes relevant race-list/cache projections.
3. It records recent box mints so the correct user/race poll can show them.
4. It emits structured timing, query-count, scope, escalation, and lag metrics.
5. Clients polling a job generation can now observe success or a newer pending
   generation without recomputing the race in the HTTP process.

### Failure and recovery behavior

1. Retryable failures use backoffs of roughly 1 second, 5 seconds, then 30
   seconds, with a bounded attempt policy in the queue model.
2. A worker that loses its lease cannot pass the final fence and therefore
   cannot write stale participant totals.
3. A dead worker leaves a `RUNNING` row. The expired lease makes it claimable.
4. Its processing inputs are unioned back into the next claim.
5. New work that arrives during a run increments the generation and forces a
   subsequent pass.
6. Queue lag is sampled once per minute for operational visibility.

---

## 2. Notification pipeline

Notifications are not one queue. They are a staged pipeline:

`domain fact -> domain-event outbox -> recipient projection -> notification
schedule -> inbox + delivery outbox -> device attempts -> APNs/FCM`

This pipeline carries the largest row fan-out because one event can produce a
projection, inbox item, outbox record, and several device-attempt rows for each
recipient.

### Stage A: append the domain event

1. Business code reaches a committed fact that may notify users—for example a
   placement change, race message, support reply, or event lifecycle change.
2. It creates a typed event with a stable event key, schema version, aggregate
   identity, occurrence time, availability time, payload, and audience facts.
3. The event is written to `domain_event_outbox`.
4. Recipient facts are captured in `domain_event_audiences` at occurrence time.
   Later profile or relationship changes therefore do not silently rewrite the
   historical audience decision.
5. The unique event key makes producer replay idempotent.
6. When created in an existing transaction, the business fact, event envelope,
   and audience snapshot commit or roll back together.

### Stage B: expand an event into recipient projections

1. The cron-owned projection job ticks every second.
2. It first gives bounded capacity to specialized set-based paths, including
   scheduled entitlement events and high-volume placement/silent cases.
3. General events are claimed with leases and `SKIP LOCKED` semantics.
4. The worker loads the immutable event and verifies that it still owns the
   lease token.
5. It validates the event type and schema version against the producer matrix.
6. It reads the next audience page after the persisted expansion cursor.
7. General audience expansion uses pages of 100 recipients.
8. For each recipient, classification decides whether the projection is:
   - visible;
   - silent refresh; or
   - already suppressed for a durable reason.
9. Classification also derives a stable delivery key.
10. The projection rows and the next expansion cursor are committed together.
11. A crash before that commit leaves the old cursor; replay encounters unique
    keys rather than creating duplicate recipient work.
12. A short page marks expansion complete.
13. The event is terminal only after expansion is complete and all projections
    are terminal.

### Stage C: materialize each projection

1. Projection claims use bounded pages (normally 50) and concurrency (normally
   four workers within the tick), subject to a five-second tick budget.
2. The worker reloads projection context and verifies its lease token.
3. It locates the matching snapshotted audience record.
4. It suppresses work if the recipient was deleted or the event expired.
5. Some mutable content is refreshed safely. For example, a race message that
   was deleted before projection becomes a terminal suppression.
6. Silent-refresh projections call the silent-delivery path with a deterministic
   transport key.
7. Visible projections run the typed materializer.
8. Event-specific rules may perform additional eligibility, cooldown, or
   deduplication checks under recipient-scoped locks.
9. A visible result is submitted to the notification-intent service with a
   stable delivery key and availability time.
10. The projection becomes `COMPLETED` or `SUPPRESSED` with its reason.
11. The parent event is checked for terminal completion.

### Stage D: retry projection failures

1. Expansion and projection attempts have independent leases and counters.
2. Failures store bounded error codes.
3. Retry delay uses exponential backoff with jitter, starting around one second
   and capped at fifteen minutes.
4. After 12 attempts, a projection or event becomes terminally failed.
5. The one-minute health report includes pending counts, status breakdowns,
   downstream state, oldest ages, and terminal failures.
6. Aged backlog for five consecutive minutes or any terminal failure produces
   an error-level backlog alert.

### Stage E: create or defer the notification intent

1. Submission validates the recipient, type, title/body, payload, delivery key,
   availability, and optional expiry/source reference.
2. The stable `(recipient, delivery key)` identity prevents duplicate visible
   notification materialization.
3. If the item is not yet eligible, it is stored in `notification_schedules` as
   `PENDING`.
4. Admission classes can enforce pacing. The global-event-start lane, for
   example, persists a lane cursor rather than trusting process-local timing.
5. If the notification is eligible now, submission creates the inbox alert and
   delivery-outbox work transactionally.
6. After commit, the service publishes a best-effort Redis wake-up and
   invalidates the recipient’s unread-count cache.
7. When the producer owns an outer transaction, it must wake only after commit;
   PostgreSQL polling covers any missed wake.

### Stage F: release scheduled notifications

1. The schedule-release worker claims due `PENDING` rows ordered by availability
   and ID with `FOR UPDATE SKIP LOCKED`.
2. A normal release page defaults to 100 and is capped at 500.
3. It marks expired rows terminally expired.
4. For global-event notifications, it rechecks entitlement activation,
   event-end time, active-race impact, and cancellation conditions.
5. Work whose activation has not settled is moved forward briefly rather than
   incorrectly sent or canceled.
6. Ineligible work is durably canceled with a reason.
7. Eligible rows are converted into inbox/outbox records using the same
   idempotent notification-intent contract.
8. The schedule row records release only with the durable downstream handoff.

### Stage G: create inbox and delivery-outbox records

1. The notification intent creates the user-visible `inbox_alerts` row.
2. It creates one `inbox_delivery_outbox` row representing provider delivery of
   that alert.
3. The outbox snapshots the payload needed for delivery.
4. Stable keys prevent a replay from creating a second logical alert.
5. Device attempt rows are derived for the recipient’s current registrations.
6. Each target snapshots identity and ownership data, including token hash,
   installation, platform, environment, and ownership generation.
7. The snapshot prevents a delayed attempt from sending to a token that has
   since moved to another account or registration generation.

### Stage H: claim delivery work and enforce admission

1. Redis wake-up can prompt an immediate scan, while a 15-second poll guarantees
   durable recovery.
2. Delivery uses 30-second leases.
3. A default page contains at most 128 outbox items.
4. The worker applies durable admission-lane limits before provider calls.
5. The global-event lane grants approximately one token every 10 ms, equivalent
   to 100 admitted sends per second.
6. Tokens may accumulate for at most about 100 ms so claims normally batch ten
   attempts instead of opening one transaction per token.
7. Claims and lane advancement commit together, preventing independent workers
   from overspending the same admission capacity.

### Stage I: call APNs or FCM

1. Before sending, the worker reloads the current device registration.
2. It compares user, status, ownership generation, installation, platform,
   provider environment, and token fingerprint with the snapshotted target.
3. A mismatch terminally suppresses that stale target instead of risking a send
   to the wrong installation or user.
4. Provider work is concurrency-limited; the default provider concurrency is
   16.
5. Each call has a default five-second caller-visible deadline.
6. A timed-out SDK operation still retains its semaphore permit until the real
   promise settles, so hidden in-flight calls cannot exceed the provider cap.
7. APNs/FCM acceptance records provider metadata and acceptance time.
8. Invalid-token responses conditionally invalidate only the matching current
   token generation.
9. Transient errors and timeouts calculate exponential backoff with jitter,
   capped at one hour and honoring longer provider retry guidance.

### Stage J: persist outcomes and finish the outbox

1. Attempt outcomes are accumulated in memory only for the bounded claimed
   page.
2. They are persisted with set-based updates.
3. Every update checks the outbox ID and lease token.
4. Token mutation also checks the attempt relationship and ownership generation.
5. Accepted, invalid, suppressed, and retryable targets are recorded separately.
6. The parent outbox becomes delivered when its required attempts are terminal
   or provider-accepted according to the delivery contract.
7. If retryable targets remain, the outbox returns to a due-at-later state.
8. If ownership was lost, stale result updates affect zero rows and the current
   owner remains authoritative.

---

## 3. Large-race resolution-trigger intake

### Why this queue exists

The normal race-resolution row is unique by race. That is ideal for coalescing,
but thousands of simultaneous upload transactions for one large race would all
contend on the same mutable row. The append-only trigger table moves that
contention away from the upload path.

### Step-by-step

1. Step intake determines that a large race requires full-scope resolution.
2. Instead of every uploader upserting the same `race_resolution_jobs_v2` row,
   each source transaction inserts its own UUID-keyed row in
   `race_resolution_full_triggers`.
3. The trigger records race, optional user and participant, timezone, and
   request time.
4. There is deliberately no foreign key. The source transaction does not take
   a parent-race lock merely to leave the handoff.
5. The first uploader may seed the normal race-resolution destination so the
   resolution process knows there is work.
6. Inserts are append-only, so simultaneous uploaders do not serialize on one
   conflict row.
7. The dedicated resolution process, not HTTP workers, promotes triggers.
8. Promotion reads bounded pages of at most 500 rows.
9. It groups/coalesces triggers by race.
10. It folds their committed information into the one race-keyed resolution
    row as full-scope work.
11. Promotion uses maintenance priority unless a stronger reason has already
    established a higher priority.
12. The promoter deletes/consumes only triggers whose durable destination was
    successfully established.
13. If a race disappeared or no longer has a live destination, the bounded
    promoter can discard the orphan trigger safely.
14. The ordinary race-resolution debounce then absorbs the promoted wave.
15. The final score computation happens once per coalesced race generation,
    not once per uploader.

### Load profile

- **High row count:** potentially one cheap row per simultaneous source.
- **Low per-row cost:** no score calculation occurs in intake.
- **Purpose:** protect request latency and the single race job row from a hot-key
  lock convoy.
- **Downstream cost:** ultimately paid by the race-resolution queue in bounded,
  coalesced form.

---

## 4. Placement transitions and race-resolution post-tasks

These are separate durable queues, but both are downstream of a successful
race-resolution generation. They keep expensive or retryable presentation work
out of the authoritative scoring transaction.

## 4A. Placement transitions

### Step-by-step: handoff and debounce

1. A race-resolution generation commits authoritative participant totals.
2. In that transaction it upserts one `race_placement_transition_jobs` row per
   race.
3. The handoff records the resolved generation and observation time.
4. A unique race ID coalesces repeated generations.
5. Only a strictly newer requested generation replaces the existing request.
6. If the placement row is currently running, it remains running; the newer
   generation is visible as superseding work.
7. A one-second `not_before_at` debounce lets closely spaced score generations
   collapse before placement materialization.

### Step-by-step: claim

1. The placement worker polls every 250 ms in the resolution process.
2. It considers due queued/retry rows and expired running leases.
3. It joins the race-resolution row and claims placement only when:
   - resolution succeeded;
   - its processing generation equals its current generation;
   - placement requests exactly that generation; and
   - the resolution has a completion timestamp.
4. This prevents placement from describing a score generation that is still
   running or already superseded.
5. It claims one row with `FOR UPDATE SKIP LOCKED`.
6. It snapshots the generation and observation time, creates a lease token,
   increments attempts, and grants a 30-second lease.

### Step-by-step: plan and commit

1. Outside the write transaction, the worker loads the canonical race,
   participants, and existing placement baselines.
2. An incomplete roster is retryable rather than being interpreted as a real
   placement change.
3. Terminal races need no new live placement notifications.
4. The planner compares canonical current placement with the prior baseline.
5. It produces baseline compare-and-set changes and typed domain events.
6. All proposed events are normalized/validated before the first write.
7. The worker opens a transaction and locks in the global order: resolution row
   first, placement row second.
8. It verifies that the exact resolution generation remains current.
9. It reloads fenced canonical context and compares fingerprints with the plan.
10. If generation or context changed, it requeues as superseded without
    persisting the stale plan.
11. Baseline changes are processed in pages of at most 250.
12. Each page uses compare-and-set writes. Only winners are allowed to emit an
    event, preventing duplicate transitions under replay.
13. Silent winners update baselines without visible notification events.
14. Non-silent individual changes append domain events in bulk.
15. Team-placement transitions additionally use a durable `job_runs`
    compare-and-set claim so only one worker emits the team event.
16. Domain events and baseline changes commit in the same transaction.
17. The placement row becomes succeeded only if the lease, processing
    generation, and requested generation still match.
18. Emitted domain events then enter the notification pipeline described above.

### Failure and repair

1. Failures transition to retry with backoffs of approximately 1 second, 5
   seconds, 30 seconds, then 5 minutes.
2. Expired leases are reclaimable.
3. Focused repair can recreate missing placement handoffs from successful race
   generations.
4. A bounded active-race sweep can catch up successful generations that lack a
   current placement job.

## 4B. Race-resolution post-tasks

### What the post-task represents

`race_resolution_post_tasks` is a durable, independently retryable handoff for
work that should not extend or roll back authoritative score persistence. One
row is unique by race and source generation. It carries a snapshot command and
bounded child delivery intents.

### Step-by-step

1. During the fenced race-resolution transaction, the worker prepares the
   post-commit outputs.
2. It serializes a bounded snapshot/publication command.
3. It creates a post-task keyed by race and source generation.
4. It inserts child `race_resolution_delivery_intents` with deterministic
   ordinals and unique delivery-key hashes.
5. Task creation, child intents, authoritative scores, and successful generation
   completion commit atomically when the atomic handoff is enabled.
6. A replay of the same generation finds the existing unique task/intents.
7. The runner polls due tasks and claims one with `FOR UPDATE SKIP LOCKED`.
8. The claim records a lease token and expiry.
9. Snapshot publication has its own attempt markers and completion fields.
10. The worker runs the stored snapshot command idempotently.
11. It walks bounded child intents in ordinal order.
12. An intent records an attempt ID before an externally visible action.
13. Intent kind determines the delivery/publication handler.
14. Provider disposition, error code, and completion time are persisted per
    intent.
15. Completed intents are not repeated on task retry.
16. The parent task becomes complete only when snapshot work and all required
    intents reach their terminal state.
17. A crash leaves the lease to expire; a later claim resumes from persisted
    snapshot/intent state.
18. Cleanup removes terminal historical work in bounded pages of at most 500.

### Why this is separate from resolution

If cache publication or a downstream delivery fails, the app should retain the
already-committed authoritative score. This queue makes the downstream work
retryable without rerunning or rolling back that score transaction.

---

## 5. Global-event summaries

### Why this workload is bursty

Most summary work becomes eligible near a global-event end boundary. The queue
is keyed by event and user, but each summary depends on all affected races for
that pair. A large event can therefore create many user work rows and enqueue
resolution across many races in a short period.

The v2 durable row is `global_event_summary_work`. Important states include
`WAITING_SYNC`, `QUEUED`, `PROCESSING`, `WAITING_RACES`, and terminal outcomes
such as `CREATED`, `ALL_ZERO`, `UNSCORABLE`, or expiry.

### Step-by-step: discover and create work

1. The summary scheduler finds ended local entitlements whose parent event uses
   attribution version 2 and has no work row yet.
2. It also discovers eligible legacy-global event/user groups for compatibility.
3. Candidate discovery is bounded; the default v2 batch size is 100.
4. It creates one durable work row per event/user pair.
5. Creation determines the exact required race count from durable event-impact
   membership.
6. Capture artifacts preserve the replayable inputs required to explain and
   rebuild attribution after the live event has ended.
7. Expiry is stored on the work so a recap cannot appear indefinitely late.

### Step-by-step: reconcile race-resolution handoffs

1. Before claiming summary work, the scheduler repairs any missing durable
   handoff to affected races.
2. It never holds a summary-work row lock while acquiring race-resolution rows;
   this preserves the global lock order.
3. Each required race is enqueued through the normal race-keyed queue.
4. Summary-specific enqueues are idempotent, so a crash after enqueue but before
   recording reconciliation can safely repeat them.
5. Race resolution calculates and finalizes each event/user/race impact.
6. Impact writes coordinate on the matching summary group so readiness cannot
   race the last impact update.

### Step-by-step: claim summary work

1. The worker selects active states whose availability time is due and whose
   lease is absent or expired.
2. `WAITING_SYNC` is not claimed early merely because a timer tick occurred; its
   synchronization/expiry conditions must be satisfied.
3. Candidates are ordered by availability and ID.
4. It uses `FOR UPDATE SKIP LOCKED` and a bounded batch.
5. Each row receives an independent UUID lease token, lease deadline, and
   incremented attempt count.
6. A newly queued row moves to `PROCESSING`; waiting states retain their semantic
   state while leased.
7. The whole tick has a time budget. Unprocessed claimed work releases its lease
   and moves its next availability forward.

### Step-by-step: validate retained artifacts

1. `PROCESSING` work verifies that the number of impact rows equals the required
   race count.
2. Every impact must use attribution version 2.
3. It loads capture artifacts ordered by race.
4. Artifact count must equal the required race count.
5. Each canonical payload is SHA-256 hashed and compared with its stored digest.
6. Each artifact must use the supported schema version.
7. Missing, corrupt, or incompatible inputs terminalize the summary as
   `UNSCORABLE`; the worker does not invent a recap from incomplete evidence.
8. Valid work transitions to `WAITING_RACES` and releases its lease.
9. User-facing cached summary state is invalidated after a committed transition.

### Step-by-step: wait for every race

1. `WAITING_RACES` work can be revisited repeatedly.
2. The worker locks the exact event/user summary row before reading impacts.
3. Impact insertion/update uses the same group lock, so the final impact cannot
   cross between the readiness check and terminal summary commit.
4. It reads all impacts ordered by race.
5. Every required impact must exist and be version-compatible.
6. If any impact is still `PENDING`, the work is not ready.
7. The worker releases the lease and schedules a later retry.
8. If the impact vector is structurally incompatible, work becomes
   `UNSCORABLE` with a durable error reason.

### Step-by-step: aggregate and publish

1. Once all required impacts are `FINAL`, the worker sums their `delta_steps`.
2. If every delta is zero, it records terminal `ALL_ZERO` and deliberately does
   not manufacture an empty recap.
3. If any delta is nonzero, it upserts one `global_event_user_summaries` row.
4. The summary records total extra race steps, race count, attribution version,
   settlement time, and expiry.
5. It writes a unique `job_runs` completion fence for the event/user/version.
6. Summary creation, terminal work status, and the completion fence commit in
   one transaction.
7. A uniqueness collision means another worker already completed the same
   logical summary; it is treated as an idempotent conflict, not a duplicate.
8. The user’s cached Home summary state is invalidated.
9. The frontend can fetch the server-authored recap and apply its own supplied
   lifetime/expiry checks before displaying it.

### Failure, expiry, and compatibility

1. Retryable errors release the lease, persist a bounded error code, and set a
   future availability time.
2. A dead worker’s expired lease is reclaimable.
3. Work that reaches its expiry terminalizes without creating a late summary.
4. Missing retained evidence becomes `UNSCORABLE`, not a guessed result.
5. The v1 aggregation path remains alongside v2 for older attribution rows. It
   groups only fully final version-1 impacts and uses `job_runs` as its durable
   idempotency fence.
6. The scheduler runs both paths, preserving mixed-version data compatibility.

---

## Relative workload characteristics

| Pipeline | Primary pressure | Shape | Main bounding mechanism |
|---|---|---|---|
| Race resolution | CPU and database reads/writes | Continuous, step-driven | One row per race, debounce, scoped closure, dedicated process |
| Notification pipeline | Row fan-out and external I/O | Continuous with large bursts | Paged expansion, durable admission lanes, bounded provider concurrency |
| Large-race triggers | Insert rate and hot-key contention | Short intense upload waves | Append-only rows, 500-row promotion pages, race coalescing |
| Placement transitions | Database compare-and-set and event creation | Proportional to successful resolutions | One row per race, 1-second debounce, 250-change pages |
| Resolution post-tasks | Cache/publication and delivery retries | Proportional to successful resolutions | One task per race/generation, intent dedupe, leases |
| Global-event summaries | Cross-race coordination | Large boundary-time bursts | 100-work batches, leases, tick budget, exact required-race vector |

This table describes architectural pressure, not measured production rankings.
Actual ranking requires a representative time window of queue depth, oldest-row
age, enqueue/complete rates, processing duration, retry counts, and resource
usage.

## Operational signals that matter

For each queue, raw depth alone is insufficient. Operators should correlate:

- oldest eligible row age;
- enqueue rate and completion rate;
- number of queued, running, retrying, and terminally failed rows;
- lease-expiry/reclaim frequency;
- p50/p95/p99 processing and transaction time;
- attempts per completed logical item;
- superseded/coalesced generations;
- database pool wait and transaction errors;
- event-loop delay in the owning process;
- downstream queue depth; and
- provider latency and acceptance/error distribution for notifications.

The most important dependency chain to remember is:

`step/event input -> race resolution -> placement/post-task work -> domain
events -> notification projection -> schedule/admission -> inbox delivery`

A downstream backlog does not necessarily mean its own worker is the original
bottleneck. For example, a placement backlog can be caused by slow resolution,
and an inbox-delivery backlog can be an intentional admission-rate consequence
of a global-event notification surge.

## Source map

The principal backend implementation files are:

- `src/modules/races/services/enqueueRaceResolution.js`
- `src/modules/races/models/raceResolutionJobV2.js`
- `src/modules/races/jobs/raceResolutionQueueV2.js`
- `src/modules/races/models/racePlacementTransitionJob.js`
- `src/modules/races/jobs/racePlacementTransitionWorker.js`
- `src/modules/races/models/raceResolutionPostTask.js`
- `src/modules/races/jobs/raceResolutionPostTaskRunner.js`
- `src/modules/domainEvents/models/domainEventOutbox.js`
- `src/modules/domainEvents/services/notificationProjector.js`
- `src/modules/domainEvents/jobs/domainEventProjection.js`
- `src/modules/notifications/services/notificationDelivery.js`
- `src/modules/notifications/services/notificationAdmission.js`
- `src/modules/inbox/jobs/inboxDelivery.js`
- `src/modules/steps/jobs/globalEventSummary.js`
- `prisma/schema.prisma`
- `src/index.js`

