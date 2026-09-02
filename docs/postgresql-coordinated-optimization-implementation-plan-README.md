# PostgreSQL coordinated optimization implementation plan

Status: Draft for engineer review and explicit approval
Date: 2026-09-02
Release shape: one coordinated backend release, no feature flags
Implementation status: specification only; no code, schema, Redis, or production changes have been made

## 1. Summary and user story

Bara's durable PostgreSQL work pipelines are correct but perform avoidable
database work while idle and amplify that work under race and notification
load. The production investigation measured a persistent global-event summary
query storm, terminal-history scans in notification projection, a 610 MB
all-terminal post-task table, and participant-heavy scoring reads. This release
removes that avoidable work without replacing PostgreSQL as the durable source
of truth.

As a Bara user, step syncs, race placement changes, event summaries, and
notifications must remain correct and converge promptly even during large
races or global-event boundaries.

As an operator, idle durable queues should generate very little PostgreSQL
traffic, active work should be claimed from compact indexes, terminal history
should not participate in hot claims, and query costs should be observable
without exposing user data.

This is a backend-only performance and data-lifecycle release. It changes no
public client request or response contract, no scoring formula, no placement
rule, no notification wording or eligibility rule, no economy value, and no
user-facing UI.

## 2. Root-cause recap

### Confirmed from production

The read-only production evidence is recorded in the frontend repository's
`docs/postgresql-production-evidence-README.md`.

| Priority | Finding | Production evidence | Conclusion |
|---|---|---|---|
| Critical | Global-event summary work | 90 active rows caused about 4,505 index scans/s and 13,384 tuple fetches/s; 428k updates were only 0.48% HOT | The current eligibility/readiness lifecycle is the strongest persistent database workload |
| Critical | Notification terminal history | About 359k terminal outbox rows and 360k terminal projections; projection paths fetched about 7,046 tuples/s with no active backlog | Generic claims, ordering checks, health, and reconciliation operate on indexes polluted by terminal history |
| High | Resolution post tasks | 368,431 terminal rows, 0 active rows, 610 MB, worker still polling every 250 ms | The active queue is physically and operationally dominated by terminal payload history |
| High | Race scoring | Sample reads fetched about 781 tuples/s; participant reads about 948 tuples/s; live statements ran for 0.4–0.7 seconds | Large-race source-input loading remains expensive even though a partial prefetch layer exists |
| High | MVCC | Very low HOT rates and high dead-tuple estimates on mutable queue tables | Indexed status/lease churn and retained terminal rows amplify writes and maintenance |
| Medium | Fixed polling | Resolution, placement, and post tasks poll every 250 ms | Not the largest measured cost, but it establishes a permanent floor |
| Medium | Full-trigger promotion | Empty table still incurs two promotion statements on every untargeted resolution claim attempt | Noisy rather than dominant, but entirely removable from the fast idle loop |
| Low / deferred | Placement hydration | Race and accepted roster are loaded twice, but production showed only about 24 placement scans/s | Keep both correctness-preserving hydrations; durable artifact writes are omitted unless a future benchmark proves net benefit |
| Ruled out at capture | Connections, duplicate workers, broad locks, active autovacuum | 20/50 connections, intended PM2 topology, no blockers/long transactions, no active vacuum | Do not optimize these first |

### Confirmed from the current repository

Several optimizations already exist and must be extended rather than
reimplemented:

- `globalStepEventEntitlement.js:720-755` creates summary work atomically at
  the entitlement end boundary. The discovery queries in
  `globalEventSummary.js:413-465` are recovery backstops.
- `raceScoringPrefetch.js:17-254` already loads samples, daily rows, and
  effects in three race-wide calls and wraps the canonical scorer. It does not
  cover finish-timeline reads and can silently fall back to participant-local
  SQL.
- notification schedules and Inbox delivery already publish and consume a
  best-effort Redis wake. PostgreSQL polling remains the recovery mechanism.
- placement already uses a coalescing one-row-per-race queue and a generation
  fence. The redundant cost is its two full canonical context hydrations.
- domain-event retention is bounded by pages, but performs downstream checks
  and deletes one event at a time.

### Architectural conclusion

PostgreSQL-backed durable queues are not inherently too expensive for this
workload. The current implementation performs unnecessary eligibility probes,
retries not-ready rows on a one-second cadence, retains payload-heavy terminal
rows in hot relations, and leaves some participant-specific reads outside its
batch layer. Those costs can be removed while preserving durability, fencing,
idempotency, replay, and crash recovery.

## 3. Scope and non-goals

### In scope

1. Replace repeated global-summary eligibility/readiness probing with explicit
   durable readiness transitions and a slow recovery sweep.
2. Give notification claims compact active-only indexes and add durable
   receipts so payload-heavy terminal history can be removed safely.
3. Split post-task terminal receipts from active payload work and make
   qualification recovery independent of every claim.
4. Complete the existing race-scoring batch layer, including finish timelines,
   with bounded chunks and explicit fallback telemetry.
5. Add one reusable Redis wake coordinator for PostgreSQL-backed queues, plus
   queue-specific recovery intervals and next-due timers.
6. Measure placement hydration but retain the current canonical reload unless
   a production-shaped benchmark proves durable artifact writes are a net
   database win. This release explicitly omits the artifact.
7. Add bounded retention and table-specific PostgreSQL maintenance settings.
8. Add application metrics and a production-measurement runbook, including
   `pg_stat_statements`.

### Non-goals

- No RabbitMQ, BullMQ, SQS, Kafka, or other authoritative queue migration.
- No feature flag, percentage rollout, runtime kill switch, or temporary
  dual-business-logic path.
- No scoring, payout, drop-rate, multiplier, powerup, placement, or notification
  behavior change.
- No client API or Flutter change.
- No table or column drop in this release.
- No removal of old indexes in this release.
- No unbounded delete, backfill, or one-transaction cleanup.
- No dependence on Redis for durability or correctness.
- No weakening of race-generation fences, queue leases, idempotency keys,
  notification dedupe, or replay rules.
- No production deployment or maintenance without separate explicit approval.

## 4. Invariants that every change must preserve

1. The business transaction commits durable PostgreSQL work before any wake is
   published.
2. A missing, delayed, duplicated, or malformed Redis wake changes latency
   only; recovery polling eventually finds every eligible PostgreSQL row.
3. A crash after PostgreSQL commit and before Redis publication loses no work.
4. A worker claims with PostgreSQL ownership semantics. Redis never assigns or
   owns work.
5. Existing `FOR UPDATE SKIP LOCKED`, lease tokens, lease expiration, and
   compare-and-set transitions remain authoritative.
6. A stale race-resolution worker cannot commit participant totals, placement
   jobs, post tasks, or authoritative generation state.
7. A placement transition is emitted only for a current committed resolution
   generation and a winning baseline compare-and-set.
8. A domain event, notification projection, schedule, Inbox delivery, and
   device attempt remain idempotent across retries and after payload cleanup.
9. Cleanup never deletes active, retryable, leased, replayable-failure, or
   client-visible state.
10. The canonical scorer remains the reference implementation. Batching changes
    data access only.
11. Time-zone, DST, sample-overlap, race-boundary, effect, box, finish, and
    settlement semantics remain byte-for-byte equivalent.
12. Existing and frozen mobile clients observe the same endpoints and response
    fields.
13. For every scoped resolution, the ordered participant dependency set is an
    externally pinned optimization invariant. Given the same claimed dirty
    envelope, race graph, effects, event rows, and as-of instant, the optimized
    loader must select exactly the same participant IDs and count as the
    pre-optimization `buildRaceScoringDependencyClosure` path. It may neither
    widen nor narrow that set. A power-up that currently selects actor plus
    target continues to select only those two unless the existing closure
    algorithm itself follows an existing dependency edge or invokes an
    existing FULL-escalation rule.

## 5. Exact global-summary query-storm call path

### 5.1 Durable creation path

```text
global-event end becomes due
  -> globalStepEventEntitlement.processOneEnd
     (globalStepEventEntitlement.js:720-755)
  -> lock due entitlement
  -> load impact race IDs
  -> acquire race write fences
  -> enqueue GLOBAL_EVENT_BOUNDARY resolution work
  -> createSummaryWorkForEntitlement
     (globalEventSummaryLifecycle.js:63-129)
  -> INSERT/UPSERT global_event_summary_work as WAITING_SYNC
  -> stamp entitlement.end_processed_at
```

This is the preferred authoritative creation path. It already makes the work
row durable at the event boundary.

### 5.2 Step-sync capture path

```text
POST sync-v2
  -> recordStepSyncV2.runIntakeInTransaction
     (recordStepSyncV2.js:170-225)
  -> lockEligibleSummaryCaptureDependencies
     (globalEventSummaryCapture.js:301-439)
     -> user/status/expiry lookup for WAITING_SYNC work
     -> impact-vector read
     -> accepted-participant/effect dependency discovery
     -> lock scoring-input rows
     -> lock race C0 fences
     -> lock work rows
     -> verify impact vector
  -> stepInputIntake
  -> claimEligibleSummaryWork
     (globalEventSummaryCapture.js:441-574)
     -> active work lookup by user/status/expiry
     -> reload eligible WAITING_SYNC rows
     -> per-work entitlement lookup
     -> per-work impact list and incompatible count
     -> per-impact artifact build
     -> status transition to QUEUED
```

Frequency is once per sync-v2 transaction, not once per participant. However,
the first indexed lookup runs for every sync, including users with no eligible
summary. For a user with eligible work, the function performs repeated
work/impact reads and artifact construction loops.

### 5.3 One-second worker path

```text
scheduleGlobalEventSummaryTick
  -> tickV2 every 1 second
  -> runV2 (globalEventSummary.js:409-515)
     -> ended-entitlement NOT EXISTS recovery scan
     -> legacy-impact NOT EXISTS recovery scan
     -> reconcileWorkRaceQueues
     -> claimActiveWork
        -> claim every due QUEUED/PROCESSING/WAITING_RACES row, up to 100
        -> one UPDATE and one findUnique per candidate
     -> for each WAITING_RACES row
        -> aggregateReadyWork
        -> lock work row
        -> reread complete impact vector
        -> if any impact remains PENDING, releaseWorkLease
        -> set available_at = now + 1 second
     -> reconcileWorkRaceQueues again
```

The 90 observed active rows were `WAITING_SYNC`, but production also had 597
pending impacts, some nearly 15 days old. Any `WAITING_RACES` work is therefore
eligible to be leased, reread, and released every second until all its races
finish. The worker also executes both recovery discovery scans and both race
reconciliation scans every second even when they return nothing.

### 5.4 Home path

Home response assembly calls
`homeLaunchAuxiliaryBatch.loadGlobalEventSummary`
(`homeLaunchAuxiliaryBatch.js:163-195`) to read
`global_event_user_summaries` and verify at least one final, nonzero impact.
The polling endpoint
`GET /home/global-event-summary-work/:id`
(`home/routes.js:390-425`) reads a work row by primary key and user ID.

These Home reads are request-driven and do not directly use
`global_event_summary_work_user_id_status_expires_at_idx` except Prisma
fallbacks or related sync response handling. They should remain batched and
must not be conflated with the worker storm.

### 5.5 Impact-trigger path

The database trigger
`fence_global_event_summary_impact_vector`
(`20260827023000_global_event_summary_active_input_fence/migration.sql`)
runs before every impact insert/update. It executes a no-op
`UPDATE global_event_summary_work SET updated_at=updated_at` to serialize the
impact vector with capture/aggregation. This correctly supplies a group fence,
but it creates a new tuple version and index maintenance even though the value
does not change. It explains the extremely low HOT percentage during periods
of impact churn, but it cannot by itself explain the 20-second interval that
had 90,109 index scans and zero summary-row updates.

### 5.6 Production attribution of the 4,500 scans/s storm

The Section 30.1 read-only gate was rerun on September 2, 2026 at approximately
11:47 UTC. Production still has no `pg_stat_statements` extension, statement
logging is `1s`, and no setting or extension was changed. A fresh two-session
20-second index-counter delta measured 90,020 scans of
`global_event_summary_work_user_id_status_expires_at_idx`, or **4,501.00 index
searches/second**.

Rapid `pg_stat_activity` sampling identified the normalized recovery statement
executed by `globalEventSummary.runV2` (`globalEventSummary.js:413-439`):

```sql
SELECT e.id
FROM global_step_event_entitlements e
JOIN global_step_events event ON event.id = e.event_id
WHERE e.ends_at <= $1::timestamp
  AND event.summary_attribution_version = 2
  AND NOT EXISTS (
    SELECT 1
    FROM global_event_summary_work work
    WHERE work.event_id = e.event_id
      AND work.user_id = e.user_id
  )
ORDER BY e.ends_at ASC, e.id ASC
LIMIT $2
```

Its live query ID was `-3856809384331555278`. The job invokes it once per
one-second `runV2` tick. A SELECT-only production
`EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` of the equivalent statement measured:

- 508.468 ms execution time and 27.698 ms planning time;
- 11,199 ended entitlement rows examined;
- 4,997 qualifying v2 entitlement rows entering the anti-join;
- 4,997 searches of
  `global_event_summary_work_user_id_status_expires_at_idx`;
- 31,282 shared-buffer hits, including 24,786 in that inner work lookup;
- zero result rows.

Dividing the independently measured 4,501 index searches/s by 4,997 searches
per statement gives approximately **0.90 statement calls/s**, consistent with
the intended one-second scheduler after allowing for tick/runtime drift. At
508.468 ms/call, this family accounts for approximately **458 ms of execution
per wall-clock second** during this snapshot, before planning and the other
summary queries. This is high cached-read CPU, not physical-I/O work.

The planner chose the wrong index for the anti-join: it probed by `work.user_id`
and filtered `work.event_id`, removing about two rows per loop, rather than
using the unique `(event_id,user_id)` index. The separate legacy recovery
statement was also observed (query ID `-6759270380661191004`), but its plan
uses `global_event_summary_work_event_id_user_id_key`; it is not the source of
the named-index storm.

This confirms—rather than materially changing—the previous ranking: the
one-second recovery-discovery pass is the measured source. The sync-v2 lookup,
impact trigger, and Home polling are not responsible for this index counter at
the captured rate. The implementation must stop running this recovery query
every second and keep a slow repair path; separately, its anti-join should be
written so the `(event_id,user_id)` unique index is the natural lookup. Exact
historical totals and mean time remain unavailable until an approved future
window provides `pg_stat_statements`; that limitation does not obscure the
source of this specific scan storm.

## 6. Global-summary fix

### 6.1 Durable readiness instead of one-second eligibility replay

Add nullable columns to `global_event_summary_work`:

- `ready_at timestamp null`: all required race impacts are terminal and the
  summary may aggregate;
- `next_recovery_at timestamp not null default now()`: the slow repair sweep
  deadline.

Keep existing statuses for compatibility. Do not introduce a second summary
state machine.

When `persistCapturedSummaryImpactsForRace` changes an impact from PENDING to
FINAL/UNSCORABLE/EXPIRED_UNDELIVERED, update the affected work group in the
same transaction:

```sql
UPDATE global_event_summary_work work
SET final_race_count = counts.final_count,
    ready_at = CASE
      WHEN counts.terminal_count = work.required_race_count
      THEN COALESCE(work.ready_at, $now)
      ELSE NULL
    END,
    available_at = CASE
      WHEN counts.terminal_count = work.required_race_count
      THEN LEAST(work.available_at, $now)
      ELSE work.available_at
    END
FROM (
  SELECT event_id, user_id,
         COUNT(*) FILTER (WHERE status = 'FINAL')::int AS final_count,
         COUNT(*) FILTER (
           WHERE status IN ('FINAL','UNSCORABLE','EXPIRED_UNDELIVERED')
         )::int AS terminal_count
  FROM global_event_race_impacts
  WHERE event_id = ANY($event_ids) AND user_id = ANY($user_ids)
  GROUP BY event_id, user_id
) counts
WHERE work.event_id = counts.event_id
  AND work.user_id = counts.user_id
  AND work.status = 'WAITING_RACES';
```

This is a set-based group update for the impact groups touched by one race
commit. It is not a per-participant query.

Change `claimActiveWork` so:

- `QUEUED` and `PROCESSING` retain their current rules;
- `WAITING_RACES` is claimable only when `ready_at IS NOT NULL`;
- `WAITING_SYNC` is claimable only for expiry;
- not-ready `WAITING_RACES` rows are never leased and released each second.

`aggregateReadyWork` still locks the row and rereads the impact vector before
committing. `ready_at` is an admission hint, not a correctness substitute.
The final vector read and group fence remain.

### 6.2 Recovery

Move both ended-entitlement and legacy-group discovery scans out of the
one-second tick. Run them:

- at cron startup;
- every 60 seconds as a recovery sweep;
- immediately after a global-event end-boundary wake.

Add a second recovery query for `WAITING_RACES` rows whose
`next_recovery_at <= now()`. In pages of 100, recompute terminal counts,
repair `ready_at`, and move `next_recovery_at` forward by 60 seconds.
This covers a crash after an impact commit but before its readiness update and
mixed-version rows from the deploy window.

`reconcileWorkRaceQueues` runs only for rows with
`race_reconciled_at IS NULL`; keep its two-phase C0 lock ordering, but invoke
it from state-transition wakes plus the 60-second recovery sweep, not twice on
every one-second tick.

### 6.3 Step-sync coalescing

In `recordStepSyncV2.runIntakeInTransaction`, keep exactly one initial
`WAITING_SYNC` lookup. Pass the loaded work identity and event fields through
the transaction so `claimEligibleSummaryWork` does not issue:

- the second active-work lookup;
- the second candidate work lookup; or
- one entitlement lookup per work.

Extend the initial select to include the event and entitlement facts required
for capture. Load all impact rows for all eligible work IDs in one query and
group them in memory. The capture fence still rechecks identities and the
complete impact vector under locks.

No eligibility cache crosses transactions. No Redis or process memory result
is authoritative.

### 6.4 One-second worker removal

Replace `setInterval(tickV2, 1000)` with the common wake coordinator described
in section 10:

- wake on summary work creation;
- wake after a sync captures a summary;
- wake after a race finalizes an impact group;
- maintain an exact timer for the next `available_at`, expiry, or recovery;
- use a 60-second PostgreSQL recovery interval.

### 6.5 Summary-specific acceptance criteria

- An idle system with 90 `WAITING_SYNC` rows performs no per-row summary query
  more often than the 60-second recovery sweep.
- A `WAITING_RACES` row with a pending impact is not leased/released every
  second.
- A crash between impact finalization and readiness repair converges within
  60 seconds.
- Step-sync capture performs one work lookup and one batched impact lookup
  before its mandatory fence rechecks.
- The final summary and every terminal outcome match current behavior.

## 7. Notification active/history fix

### 7.1 Queries currently touching terminal history

| File/function | Predicate/order | Current index/problem | Change |
|---|---|---|---|
| `domainEventOutbox.claimEvents` | status PENDING/RETRY/EXPANDING, due availability/lease; order availability, occurrence, ID | full `(status, available_at, occurred_at)` contains every terminal event | use a partial active claim index with full ordering |
| `claimProjections` stranded candidates | outbox PROJECTING and no nonterminal child | scans parent and child history; terminal child anti-join is expensive | use active-child partial index and a parent projection counter |
| `claimProjections` candidates | projection active/due plus no older active aggregate | projection status index contains all 360k rows; correlated aggregate check | partial projection claim index and existing partial active aggregate index |
| `finishEventIfTerminal` | count/find remaining children | repeats completeness checks against all child states | maintain terminal/active projection counts on parent |
| `readHealthSnapshot` | group every projection by status | intentionally scans terminal history every minute | report active statuses from partial indexes; terminal failures from a small receipt/failure table |
| `notificationCompletenessReconciler` | multiple NOT EXISTS checks across terminal schedules/outboxes/attempts | every five minutes, terminal tables dominate | add purpose-built partial repair indexes and retain bounded cadence |
| `findRetentionCandidates` | terminal event, old completion, every child terminal | no completion-time retention index; includes children then performs three downstream counts per event | batch candidates and downstream checks per page |

### 7.2 Parent counters

Add to `domain_event_outbox` in a migration-safe nullable form:

- `projection_count integer null`;
- `terminal_projection_count integer null`;
- `failed_projection_count integer null`;
- `projection_counts_valid_at timestamp null`.

Install a database trigger before counter-aware application code so every
writer—including an overlapping previous binary and raw batch SQL—is covered.
It increments the total on INSERT and adjusts terminal/failed counts only on
real status-class transitions. Backfill one locked parent page at a time and
set all counts plus `projection_counts_valid_at` atomically. While that stamp
is null, claims and completion retain the existing child-existence checks.
Even after validation, final completion performs one authoritative active-child
`NOT EXISTS` fence. Counters are an admission optimization, not the sole
correctness fence. Preserve a bounded 15-minute reconciler and test INSERT,
batch INSERT, every terminal transition, failed-terminal replay, and reset.

This removes the stranded-parent `NOT EXISTS` scan from every projection
claim. The reconciler remains the crash/mixed-version repair path.

### 7.3 Durable event receipts

Add `domain_event_receipts`:

```text
event_key           varchar(255) primary key
domain_event_id     uuid not null unique
event_type          varchar(96) not null
schema_version      integer not null
aggregate_type      varchar(96) not null
aggregate_id        text not null
occurred_at         timestamp not null
available_at        timestamp not null
envelope_digest     char(64) null
receipt_state       varchar(16) not null  -- PROVISIONAL or FINAL
digest_version      smallint not null
terminal_status     varchar(32) null
completed_at        timestamp null
replay_source_type  varchar(64) not null
replay_source_id    text not null
finalized_at        timestamp null
created_at          timestamp not null
updated_at          timestamp not null
check (receipt_state in ('PROVISIONAL','FINAL'))
check ((receipt_state='PROVISIONAL' and envelope_digest is null and finalized_at is null)
    or (receipt_state='FINAL' and envelope_digest is not null and finalized_at is not null))
```

A receipt digest covers the complete canonical immutable envelope: event key,
event type, schema version, aggregate type/ID, UTC occurrence and availability,
canonical JSON payload, and audience ordered by ordinal with recipient ID and
canonical facts. New append code computes it before the transaction, reserves
the receipt, inserts outbox plus ordered audience, and finalizes
`domain_event_id` in the same transaction. A conflict compares the full digest;
any mismatch is an invariant error. A trigger may reserve a provisional receipt
for an old-binary insert, but cannot finalize its audience-dependent digest; a
reconciler does so after audience insertion. On conflict with a PROVISIONAL
receipt, a new writer locks the receipt and still-retained parent, loads the
ordered audience, computes/finalizes digest version 1, and only then compares
its proposed envelope. It waits/retries if the old transaction is not yet
visible; it never compares a complete digest with a provisional value. The
reconciler uses the same locks and transition. Cleanup and the cleanup cutoff
both require `NOT EXISTS (receipt_state='PROVISIONAL')`, and metrics expose the
count and oldest provisional age. Cleanup is forbidden while an old binary
overlaps or any receipt remains provisional.

`domain_event_id` retains the original stable UUID after the payload row is
deleted; it is deliberately not a cascading foreign key. On terminal
transition, update the receipt's terminal status/completion. Keep each receipt
until its identified `(replay_source_type,replay_source_id)` no longer exists.
If a legacy row cannot be mapped to a replay source during backfill, stamp
`replay_source_type='LEGACY_UNMAPPED'` and retain it indefinitely until a later
verified mapping—never substitute a fixed age. Keep payload
outbox/audience/projection rows seven days after
successful terminal completion. Keep `FAILED_TERMINAL` payloads 30 days or
until explicit replay resolution, whichever is later.

Single append returns `{inserted:false, receiptOnly:true, id, eventKey,
terminalStatus}` for a receipt-only replay and never projects it; bulk append
returns the same disposition per input ordinal. Callers cannot require payload
or audience fields from that result. Tests vary every immutable envelope field
independently and require a mismatch. The event receipt—not retained JSON—is
the long-lived dedupe proof. Projection
receipts are not separately required because an event receipt prevents a
cleaned parent from being expanded again. Delivery-key dedupe remains in
notification schedules and Inbox alerts/outboxes while those objects live.

### 7.4 Notification schedule and Inbox history

Add `notification_schedule_receipts`:

```text
recipient_user_id    text not null
delivery_key         text not null
source_kind          varchar(16) not null  -- SOURCE_BACKED or DIRECT
source_type          varchar(64) null
source_id            text null
source_revision      integer null
terminal_status      varchar(32) null
completed_at         timestamp null
direct_retain_until  timestamp null
created_at           timestamp not null
updated_at           timestamp not null
primary key (recipient_user_id, delivery_key)
foreign key (recipient_user_id) references users(id) on delete cascade
check (
  (source_kind='SOURCE_BACKED' and source_type is not null and source_id is not null
    and direct_retain_until is null)
  or
  (source_kind='DIRECT' and source_type is null and source_id is null
    and source_revision is null and direct_retain_until is not null)
)
```

Source-backed rows require `source_type/source_id`, prohibit
`direct_retain_until`, and remain until that source is deleted. Direct rows
require `direct_retain_until = alert_visible_until + maximum producer retry
horizon`; they prohibit source fields and are not eligible for cleanup before
that instant. A CHECK constraint enforces the two shapes.

Schedule creation reserves/upserts the receipt in the same transaction as the
schedule UPSERT. It compares source kind/type/ID/revision for a replay and
rejects a delivery-key collision with different immutable identity. A receipt
without a live schedule returns the existing idempotent/replay disposition and
does not recreate delivery. Terminalization copies terminal status/completion
to the receipt in the same transaction. Inventory and classify every producer
in `notificationDelivery.js`, `notificationAdmission.js`,
`domainEventOutbox.js`, and timezone/global-event reconciliation; an unknown
producer shape fails closed as source-backed/unmapped and is not age-cleaned.

- Keep future and active schedules in the primary table.
- Retain terminal schedule payload rows only until downstream Inbox/provider
  work is terminal and the receipt has been verified. The receipt then owns
  schedule-level dedupe for its source/direct-producer lifetime.
- Allow terminal schedule payload/title/body to be nulled after seven days by
  additive nullable-column migration only after verifying no internal reader
  requires them. In this release, retain columns and delete the whole schedule
  only when its associated Inbox alert has expired and no active delivery row
  exists.
- Keep Inbox delivery rows and device attempts until their parent Inbox alert
  expires (currently 30 days); the existing cascade is the lifecycle owner.
- Add active-only indexes so these terminal rows do not enter claim scans.
- Do not create a parallel delivery system or archive every provider response
  into a second payload-heavy table.

### 7.5 Set-based retention

Rewrite domain-event retention page processing to load 500 candidate events,
their projection delivery keys, and all downstream active counts in one SQL
statement. Delete only eligible IDs in a bounded transaction of at most 500
parents. Cascades remove audience/projection children. Commit between pages,
yield, and cap each scheduled run to 10 pages; continue on the next five-minute
maintenance tick.

Do not loop `event -> three count queries -> delete`.

## 8. Race-resolution post-task fix

### 8.1 Current hot path

Every 250 ms, `raceResolutionPostTaskRunner.tick`:

1. calls `recoverReferralQualificationIntents`;
2. claims one post task;
3. returns empty when all 368k tasks are terminal.

The claim query uses an OR between queued due rows and expired running leases,
then orders by `requested_at`. The nominal `(state, not_before_at)` index
does not satisfy both branches plus ordering, and production recorded zero
uses of it.

Qualification recovery is a separate giveaway pipeline and has no correctness
reason to precede every post-task claim.

### 8.2 Active task and receipt lifecycle

Add `race_resolution_post_task_receipts`:

```text
race_id              text not null
source_generation    integer not null
dedupe_key            text not null
terminal_state        varchar(32) not null
snapshot_state        varchar(32) not null
intent_count          integer not null
failure_count         integer not null
completed_at          timestamp not null
primary key (race_id, source_generation)
unique (dedupe_key)
foreign key (race_id) references races(id) on delete cascade
check (intent_count >= 0 and failure_count >= 0)
```

On task completion, write/update the receipt in the same transaction as the
terminal task state. A create replay first checks the active task unique keys,
then the receipt. It never recreates delivery intents or republishes a snapshot
for a receipted generation.

Add `race_resolution_delivery_intent_receipts`:

```text
delivery_key_hash    char(64) primary key
race_id              text not null
source_generation    integer not null
task_dedupe_key      text not null
intent_kind          varchar(64) not null
terminal_disposition varchar(32) not null
completed_at         timestamp not null
created_at           timestamp not null
foreign key (race_id) references races(id) on delete cascade
```

On each terminal intent transition, insert the intent receipt in the same
transaction before the payload intent becomes cleanup-eligible. A create or
recovery replay checks `delivery_key_hash` first; an identical hash/task/kind
returns the recorded disposition without provider or snapshot work, while a
hash collision with different immutable identity is terminal/alarmed.
Aggregate task counts are diagnostics and cannot replace this per-intent
dedupe. Keep both task and intent receipts until their race is deleted; the
race foreign keys enforce that lifecycle without requiring the task receipt to
exist before a child intent terminalizes. A fixed 30-day period is unsafe because
an old generation can be replayed for the race's lifetime. Keep full terminal
task/intent payload for 24 hours only after the explicit cleanup cutoff in
Section 24.

### 8.3 Claim rewrite

Use two partial indexes and a bounded two-branch candidate. PostgreSQL cannot
lock the UNION result directly; the UNION only supplies IDs:

```sql
WITH candidate_ids AS MATERIALIZED (
  SELECT id, requested_at FROM (
    (SELECT id, requested_at FROM race_resolution_post_tasks
     WHERE state='queued' AND not_before_at <= $1
     ORDER BY not_before_at, requested_at, id LIMIT 16)
    UNION ALL
    (SELECT id, requested_at FROM race_resolution_post_tasks
     WHERE state='running' AND lease_expires_at <= $1
     ORDER BY lease_expires_at, requested_at, id LIMIT 16)
  ) branches ORDER BY requested_at, id LIMIT 16
), claimed AS (
  SELECT task.id FROM race_resolution_post_tasks task
  JOIN candidate_ids candidate ON candidate.id=task.id
  ORDER BY task.requested_at, task.id
  FOR UPDATE OF task SKIP LOCKED LIMIT 1
)
UPDATE race_resolution_post_tasks task
SET state='running', lease_token=$2, lease_expires_at=$3,
    started_at=COALESCE(started_at,$1), updated_at=$1
FROM claimed WHERE task.id=claimed.id RETURNING task.*
```

Sixteen candidates per branch prevents one locked oldest row from hiding all
work. Preserve ambiguity recovery of attempting intents/snapshots. A
two-worker integration test must prove distinct claims and oldest-requested
fairness across branches.

### 8.4 Scheduler changes

- Publish `POST_TASK` wake after the resolution transaction commits its
  durable post task.
- Drain immediately on wake, coalescing duplicate wakes.
- Poll PostgreSQL every 30 seconds for recovery.
- Query/arm the next `not_before_at` or lease-expiry timer after a drain.
- Run referral qualification recovery in its own scheduler every 60 seconds,
  with an immediate wake from its own producer if available.
- Run cleanup every five minutes, at most 500 rows per transaction and at most
  10 pages per invocation. Start with the oldest terminal rows.
- Do not call qualification recovery from `tick`.

## 9. Batched race-scoring implementation

### 9.1 Current SQL map

The canonical functions consume:

| Function | Data needed | Current batch coverage |
|---|---|---|
| `calculateBaseAdjusted` | start-day sample overlap, optional start-day daily row, daily rows and sample windows for later local days, any-sample existence | covered by `raceScoringPrefetch` when prefetch succeeds and range contains all windows |
| `calculateCurrentTotal` | participant effect rows, effect-segment sample windows, global-event entitlement input | effects/samples generally covered; global events loaded race-wide |
| `determineFinishSnapshot` | every sample in effective-start-to-now range and all race powerup events | not covered: one sample query and one race-event query per newly finishing participant |
| `resolveRaceState` | race/accepted roster, active impacts, samples, daily rows, effects, global events, mystery-box and settlement inputs | partly fixed; finish and some unsupported model methods fall back |
| Drill Sergeant / Trail Mine consequences | closed sample window, active shield/mine rows, participant writes | sample can be covered; shield lookup and effect writes remain consequence-specific |

### 9.2 New batch input object

Extend `raceScoringPrefetch.js` into a versioned
`RaceScoringInputBatchV1` object. Do not add a second scoring implementation.
It supplies the same model interface to the existing functions.

The loader receives the exact scored participant set and computes per-user
bounds from:

- effective race start or join time;
- race end/current scoring time;
- local-day boundaries using the canonical timezone helpers;
- effect start/end boundaries;
- global-event entitlement windows;
- finish-timeline range.

It executes bounded queries for:

1. accepted participant IDs and their user IDs are already supplied by the
   race hydration;
2. daily rows for all user/date ranges;
3. sample rows for all user/time ranges;
4. settlement/effect rows for all race/participant/type keys;
5. race powerup events once;
6. global-event entitlement rows once (existing path);
7. scoring-input generations/fingerprints once when the fence requires them.

Use JSON recordsets or `unnest` of `(user_id,start,end)` bounds and join
against `steps`/`step_samples`. Select only scoring columns. Preserve
deterministic ordering by user, time, and stable ID.

### 9.3 Chunking and memory bound

Process at most 25 whole users or 50,000 sample rows per chunk, whichever comes
first. The loader obtains a row count/byte estimate from the first page and
continues with a stable `(user_id, period_start, id)` cursor. It must never
load the entire historical sample table.

For a 500-person, 14-day race:

- daily rows: at most about 7,000 rows;
- hourly samples: about 168,000 rows;
- five-minute samples in the pathological case: about 2,016,000 rows.

The pathological case must not be retained as one in-memory object. Score
base inputs in chunks, retain only compact per-participant calculated entries
and the sample slices required by cross-participant effects/finishers, and
release each chunk before loading the next. Set an application guard of 32 MiB
actual `process.memoryUsage().heapUsed` growth and 50,000 sample rows per page.
If cross-participant semantics require more retained source data than the
guard, continue paged processing; do not fall back to N+1 queries.

The guard includes JavaScript object overhead; serialized byte length is only
telemetry and is not the limiter. Aggregate compact score/effect maps for 500
participants remain resident, while raw samples are released per complete
user. Record actual row and V8 heap high-water metrics.

### 9.4 Finish timeline

Add prefetched methods for:

- `findByUserIdAndTimeRange`;
- `findByRaceAsc` for powerup events.

`determineFinishSnapshot` then filters the in-memory user samples and shared
race-event list. Newly finishing participants no longer issue two statements
each.

### 9.5 Failure behavior

The current broad catch logs and silently reverts the entire generation to
participant-local SQL. Replace it with:

- retry the bounded batch query on recognized transient database errors;
- if the batch cannot be built, fail/retry the queue job before any
  authoritative writes;
- retain per-method fallback only for injected tests and legacy non-worker
  callers;
- emit `race_scoring_batch_fallback_total{reason}` whenever a production
  worker invokes a real-model fallback;
- acceptance requires zero production-worker fallback in load tests.

This preserves correctness while preventing a transient prefetch problem from
turning a 500-person generation into thousands of queries.

### 9.6 SQL statement estimates

These estimates cover scoring source reads, not claim, fence, persistence,
boxes, or notification work.

| Participants | Current best case (prefetch succeeds, no finishers) | Current fallback/worst ordinary case | New bounded batch |
|---:|---:|---:|---:|
| 10 | 4–7 statements | roughly 30–60 | 5–8 |
| 50 | 4–7 | roughly 150–300 | 5–10 |
| 500 | 4–7, but very large reads | roughly 1,500–3,000 plus finish queries | roughly 15–35 depending on sample-page count |

The new count is `O(chunks/pages)`, not `O(participants)`. It may use more
than one statement for 500 participants deliberately to bound memory.

## 10. Redis wake plus PostgreSQL recovery polling

### 10.1 Shared module

Create `src/shared/queues/postgresWakeCoordinator.js` with:

- a queue-kind enum;
- `publishAfterCommit(kind, hint)`;
- `subscribe(kind, requestDrain)`;
- a coalescing drain state: `running`, `pendingWake`, and one scheduled
  due timer;
- exponential reconnect handled by the existing Redis client;
- metrics for received, coalesced, failed, fallback, idle, and productive
  polls;
- no queue row IDs or user data in Redis payloads.

Extend `redisCache.js` to use one environment-prefixed channel with messages
such as `{"kind":"RACE_RESOLUTION"}`. The message is a scan hint only.

### 10.2 After-commit rule

For a transaction owned by application code, collect wake callbacks and invoke
them only after `prisma.$transaction` resolves. If a caller cannot expose an
after-commit hook, omit the wake and rely on fallback polling. Never publish
inside a transaction.

The required producer seams are:

- `enqueueRaceResolution.js` and all outer transaction owners;
- resolution commit -> placement job and post task;
- domain-event append;
- notification schedule creation/materialization;
- Inbox outbox creation;
- global-summary creation/capture/readiness transition.

### 10.3 Queue-specific cadence

| Queue | Immediate wake | Next-due timer | Recovery poll |
|---|---|---|---:|
| Race resolution | every committed enqueue/full-trigger insert | min not-before/retry/lease expiry | 5 seconds |
| Placement | committed current-generation handoff | min not-before/retry/lease expiry | 10 seconds |
| Post tasks | committed task creation | min not-before/lease expiry | 30 seconds |
| Full-trigger promotion | full-trigger insert uses race-resolution wake | none separate | same 5-second resolution recovery tick; no separate poller |
| Domain-event expansion/projection | event/projection creation or retry | min available/lease expiry | 10 seconds |
| Notification schedules | schedule create/update | exact next available/admission deadline, capped 60 seconds | 60 seconds |
| Inbox delivery | outbox create/retry | exact next available/retry/lease expiry, capped 60 seconds | 60 seconds |
| Global summaries | end creation, sync capture, impact readiness | min available/expiry/recovery | 60 seconds |

A due timer is derived from a compact `nextDueAt` query after a drain. It is
always bounded by the fallback interval, so a missed timer is harmless.

Every interval in the final column is recovery-only. With Redis healthy, a
committed wake invokes the queue's coalesced `requestDrain` immediately and the
worker begins claiming eligible work without waiting for that interval.
Existing debounce, not-before, available/retry, lease, and admission boundaries
remain authoritative; a wake never makes future work early.

### 10.4 Drain behavior

One wake begins an adaptive drain. Wakes received while running set one boolean;
they do not create concurrent drain loops. A drain processes bounded slices,
yields to the event loop, and continues while claims succeed. On empty claim it
arms the next-due timer and stops. Errors use current retry semantics and a
bounded one-second scheduler backoff.

## 11. Placement handoff implementation

### 11.1 Read classification

Current `RacePlacementBaseline.loadCanonicalContext`
(`racePlacementBaseline.js:96-112`) issues two queries and is called:

1. before planning;
2. again under the resolution/job locks before persistence.

Classification:

- resolution generation/job lock: required correctness revalidation;
- current participant totals/membership: required unless proven by a committed
  generation artifact;
- baseline values: needed for compare-and-set, but stale expected values are
  safely rejected by CAS;
- mute preference: must be current when deciding whether to emit;
- race display/payout facts: needed for event payload, but immutable changes
  must be fenced;
- the first full hydration: potentially redundant but currently cheaper than
  an unproven durable handoff;
- the second full hydration: required as the current fingerprint/fencing read.

### 11.2 Artifact cost re-evaluation and release decision

The normalized artifact proposed during architecture review would replace one
race-row SELECT and one accepted-roster SELECT with durable writes. It is not a
free read optimization. With one header row and one child per participant, the
minimum row/index work per generation is:

| Participants | New heap rows | Minimum new index entries | New SQL statements with bulk child INSERT | Existing reads removed |
|---:|---:|---:|---:|---:|
| 10 | 11 | about 23 (header PK/unique plus two child indexes) | 2 | 2 SELECTs / about 11 rows |
| 50 | 51 | about 103 | 2 | 2 SELECTs / about 51 rows |
| 500 | 501 | about 1,003 | 2 | 2 SELECTs / about 501 rows |

Those writes also generate WAL for every heap tuple and index entry, dirty
pages in the already write-heavy resolution transaction, add FK/index CPU,
create dead tuples when superseded/cleaned, require a cleanup transaction, and
retain storage between creation and cleanup. A conservative pre-benchmark row
width of 160–240 bytes for the child plus approximately 64–120 bytes across
its indexes implies roughly 2–4 KiB, 11–18 KiB, and 110–180 KiB of new durable
heap/index data before WAL/full-page-image overhead for 10, 50, and 500 users.
WAL can exceed those figures materially at checkpoint page boundaries. These
are sizing estimates, not proof.

Production evidence does not currently show placement hydration as a dominant
query family: the placement queue generated about 24 scans/s, versus 4,501/s
from the measured summary statement and thousands/s from notification history.
The read being removed is cached, bounded, and executed only for productive
placement work. Therefore the normalized artifact does **not** have a clear
net database benefit today.

**Release decision:** omit the placement-generation artifact, its schema,
fingerprint function, job foreign keys, write path, retention, and cleanup from
this optimization release. Keep the existing two canonical hydrations and all
generation/fingerprint/CAS fences. This obeys the rule that correctness is not
traded for an unproven optimization.

### 11.3 Benchmark required before reconsideration

A future plan may reconsider the artifact only after a production-shaped
non-production benchmark measures 10-, 50-, and 500-participant generations.
For both current hydration and normalized-artifact variants, capture:

- PostgreSQL execution and CPU time for resolution commit plus placement;
- `pg_stat_statements` calls/total/mean time and blocks for the removed SELECTs
  and added INSERT/load/delete statements;
- WAL bytes from an isolated `pg_stat_wal.wal_bytes` delta;
- relation and index byte growth after at least 1,000 generations per size;
- rows inserted/updated/deleted, dead tuples, HOT percentage, vacuum work, and
  cleanup duration;
- resolution-transaction p95/p99 and placement end-to-end latency.

The artifact may return to scope only if, for each size, total PostgreSQL CPU
and WAL do not regress, resolution-commit p95 does not regress by more than 5%,
and the 500-participant case reduces combined resolution-plus-placement DB
execution time by at least 20%. Any loss in the 10- or 50-person cases requires
a single permanent threshold justified by production race-size distribution;
no runtime feature flag or permanent dual path is allowed.

## 12. Retention matrix

| Table | Active purpose | Terminal/idempotency purpose | Client queried? | Current retention | Proposed retention/action |
|---|---|---|---|---|---|
| `race_resolution_jobs_v2` | one mutable authoritative row per race, generation/lease/fence | latest generation/status and recovery | indirectly through status flows | race lifetime | keep one row per race; delete only by race cascade |
| `race_resolution_full_triggers` | append-only large-race intake | none after promotion | no | deleted on promotion | delete on promotion; recovery prune orphan triggers older than 7d in 500-row pages |
| `race_placement_transition_jobs` | one coalescing job per race | completed generation prevents duplicate transition | no | race lifetime | keep one row per race; terminal row remains compact |
| `race_resolution_post_tasks` | snapshot and intent owner | current 7d replay/dedupe | no | 7d | full payload 24h after cutoff; dedupe moves to race-lifetime task receipt |
| `race_resolution_delivery_intents` | at-most-once delivery children | provider disposition diagnostics | no | cascades with 7d task | payload cascades with 24h task; per-intent dedupe moves to race-lifetime intent receipt |
| `race_resolution_post_task_receipts` | generation/task replay dedupe | compact terminal proof | no | new | retain until owning race deletion; cascade from race |
| `race_resolution_delivery_intent_receipts` | delivery-key/provider replay dedupe | compact terminal disposition | no | new | retain until owning race deletion; cascade from race |
| `domain_event_outbox` | durable expansion parent | replay/debug and event-key dedupe | no | 30d | successful payload 7d, failed 30d; dedupe moves to replay-source-lifetime receipt |
| `domain_event_receipts` | event-key/full-envelope replay dedupe | compact terminal proof | no | new | retain until identified replay source deletion; unmapped legacy receipts retained indefinitely |
| `domain_event_notification_projections` | recipient projection work | replay/debug | no | cascades at 30d | cascade with parent; terminal excluded from active indexes |
| `notification_schedules` | future/due visible notification intent | payload until downstream terminal | no | no explicit terminal cleanup | delete terminal payload only after downstream terminal and verified receipt |
| `notification_schedule_receipts` | `(recipient,delivery_key)` dedupe | compact terminal/source proof | no | new | source-backed: source lifetime; direct: alert visibility plus maximum producer retry horizon |
| `inbox_delivery_outbox` | durable provider delivery | retry/recovery and delivery audit | no direct client query | parent alert expiry | preserve cascade with 30d Inbox alert |
| `inbox_delivery_device_attempts` | per-device retry ownership | at-most-once/provider audit | no | parent outbox cascade | preserve cascade; active-only retry index |
| `global_event_summary_work` | sync capture/readiness/lease | polling receipt and lifecycle proof | yes, by work ID | entitlement cleanup after 30d | active through expiry; terminal 30d to preserve frozen-client polling |
| `global_event_race_impacts` | per-race summary inputs | summary correctness/replay | indirectly via summary | entitlement cleanup after 30d | retain current 30d lifecycle; fix blocked rows and batch cleanup |

Receipt cleanup is also bounded: 500 rows per transaction, ten pages per
maintenance tick.

### 12.1 Receipt implementation completeness matrix

| Receipt | Exact schema/write/replay | Keys/indexes | Backfill/cleanup | Model and integration coverage |
|---|---|---|---|---|
| `domain_event_receipts` | Section 7.3; reserved/finalized with append and terminal event transition; complete-envelope replay comparison | PK `event_key`, unique `domain_event_id`, source and PROVISIONAL indexes in 14.5 | Sections 18.3/18.4 and 30.6; replay-source lifetime, unmapped indefinite | `domainEventReceipt.js`, outbox append/retention paths; Section 22.4 |
| `notification_schedule_receipts` | Section 7.4; reserved with schedule UPSERT and finalized with terminal transition; source-identity replay comparison | PK `(recipient_user_id,delivery_key)`, source and direct-cleanup indexes in 14.5 | Sections 18.3/18.4 and 30.6; source lifetime or direct visibility+retry | `notificationScheduleReceipt.js`, all enumerated schedule producers; Section 22.4 |
| `race_resolution_post_task_receipts` | Section 8.2; written atomically at task completion; generation/dedupe replay short-circuit | PK `(race_id,source_generation)`, unique `dedupe_key`; race FK | Sections 18.3/18.4 and 30.6; race-lifetime cascade only | `raceResolutionPostTaskReceipt.js`, handoff/runner; Section 22.5 |
| `race_resolution_delivery_intent_receipts` | Section 8.2; written atomically at terminal intent transition; disposition replay short-circuit | PK `delivery_key_hash`, race-generation index, race FK | Sections 18.3/18.4 and 30.6; race-lifetime cascade only | `raceResolutionDeliveryIntentReceipt.js`, intent/runner paths; Section 22.5 |

## 13. PostgreSQL maintenance plan

### 13.1 Per-table reloptions

**Proven settings as of this plan revision: none.** No
autovacuum or fillfactor reloption may appear in the final migration until its
specific table/value pair passes the gate below. An untested row is omitted,
not applied with a “reasonable” default.

The benchmark covers `global_event_summary_work`, domain-event parent and
projection tables, post tasks, notification schedules, Inbox outbox/device
attempts, resolution jobs, and placement jobs. It begins with the managed
defaults observed in the sanitized snapshot and chooses candidate values only
inside the disposable benchmark environment. This plan deliberately records
no candidate numeric value, so an unvalidated planning number cannot leak into
a migration.

For every table/value pair, run baseline and candidate trials on the sanitized
production-shaped database at idle, normal, backlog-drain, and cleanup load.
Record update rate, dead-tuple slope, HOT update percentage, autovacuum start/
duration/CPU, foreground DB CPU, WAL bytes/s, query p95/p99, lock waits, and
relation/index growth over at least two autovacuum cycles. A value is proven
only when foreground p95 does not regress more than 5%, total database CPU and
WAL do not materially regress, dead-tuple age/count improves, and no vacuum
overlap causes queue-latency failure. Repeat once to reject checkpoint/cache
noise. The migration PR must contain a table called `Proven reloptions` listing
only successful exact `(table, setting, value)` triples and their evidence;
every other table inherits the managed PostgreSQL default.

### 13.2 HOT-update strategy

Partial active indexes intentionally add/remove entries on state transitions,
so those transitions cannot be HOT. Improve the common case by:

- excluding `updated_at`, attempt counters, and lease tokens from indexes;
- indexing lease expiry only for the `running` partial subset;
- keeping payload JSON out of mutable coalescing rows;
- using fillfactor to leave page space for lease renewals and counters;
- avoiding no-op `updated_at=updated_at` writes where a row lock or advisory
  group lock can provide the fence.

Replace the summary impact trigger's no-op tuple update with a row lock
implemented by selecting the matching work row `FOR UPDATE` inside the trigger
or with a stable advisory-xact lock derived from event/user. Prefer `FOR
UPDATE` because it preserves the current visible lock ordering. Prove with an
integration test that capture and terminal impact mutation still serialize and
raise/retry exactly as today.

### 13.3 One-time maintenance

After the new code is deployed and bounded cleanup has removed enough rows:

1. run `ANALYZE` on changed tables during the approved maintenance window;
2. run ordinary `VACUUM (ANALYZE)` one table at a time if dead tuples remain;
3. measure index bloat with `pgstattuple` if available;
4. use `REINDEX INDEX CONCURRENTLY` only for individually proven bloated
   indexes and only under separate in-the-moment production approval.

Do not use `VACUUM FULL` or `CLUSTER`. Ordinary deletion/vacuum makes space
reusable inside the relation but does not promise immediate filesystem-size
reduction.

## 14. Historical candidate DDL — superseded, do not implement

The SQL in Sections 14.1–14.4 is retained only to show the first gap-pass
candidate set. It is **not implementable migration SQL** because several claim
indexes combine due and expired-lease states. Section 30.2 is the final
query-to-index contract; the implementation PR must replace this entire
historical block with verified branch-specific DDL and SELECT-only plans before
approval. No SQL from this block may be copied into a migration.

All production builds use `CREATE INDEX CONCURRENTLY`. Put concurrent indexes
in dedicated Prisma migration files containing no transaction-dependent data
changes. Additive tables/columns and triggers go in a preceding migration.

### 14.1 Global summaries

```sql
CREATE INDEX CONCURRENTLY global_event_summary_work_capture_active_idx
ON global_event_summary_work (user_id, expires_at, id)
WHERE status = 'WAITING_SYNC';

CREATE INDEX CONCURRENTLY global_event_summary_work_ready_claim_idx
ON global_event_summary_work (available_at, id)
WHERE status IN ('QUEUED','PROCESSING')
   OR (status = 'WAITING_RACES' AND ready_at IS NOT NULL);

CREATE INDEX CONCURRENTLY global_event_summary_work_expired_waiting_sync_idx
ON global_event_summary_work (expires_at, id)
WHERE status = 'WAITING_SYNC';

CREATE INDEX CONCURRENTLY global_event_summary_work_recovery_idx
ON global_event_summary_work (next_recovery_at, id)
WHERE status IN ('WAITING_SYNC','QUEUED','PROCESSING','WAITING_RACES');
```

The first serves the sync eligibility lookup without 4,900 terminal rows. The
second serves the rewritten claim. The third serves expiry. The fourth serves
only the 60-second recovery sweep. Expected cardinality is approximately the
90 active production rows, not all 4,990.

### 14.2 Domain events and projections

```sql
CREATE INDEX CONCURRENTLY domain_event_outbox_active_claim_idx
ON domain_event_outbox (available_at, occurred_at, id)
WHERE status IN ('PENDING','RETRY','EXPANDING');

CREATE INDEX CONCURRENTLY domain_event_outbox_projecting_completion_idx
ON domain_event_outbox (occurred_at, id)
WHERE status = 'PROJECTING' AND expansion_completed_at IS NOT NULL;

CREATE INDEX CONCURRENTLY domain_event_outbox_terminal_retention_idx
ON domain_event_outbox (completed_at, id)
WHERE status IN ('COMPLETED','SUPPRESSED');

CREATE INDEX CONCURRENTLY domain_event_projection_active_claim_idx
ON domain_event_notification_projections (available_at, id)
WHERE status IN ('PENDING','RETRY','PROCESSING');

CREATE INDEX CONCURRENTLY domain_event_projection_active_parent_idx
ON domain_event_notification_projections (domain_event_id, id)
WHERE status NOT IN ('COMPLETED','SUPPRESSED','FAILED_TERMINAL');

CREATE INDEX CONCURRENTLY domain_event_projection_failed_idx
ON domain_event_notification_projections (completed_at, id)
WHERE status = 'FAILED_TERMINAL';
```

The active claim indexes replace full status indexes for hot plans. The parent
index serves active-child existence/reconciliation. The retention index serves
bounded cleanup. Expected idle active cardinality is near zero.

Keep the existing active aggregate-order and scheduled-entitlement partial
indexes. Do not drop the old full indexes in this release.

### 14.3 Post tasks

```sql
CREATE INDEX CONCURRENTLY race_resolution_post_tasks_queued_due_idx
ON race_resolution_post_tasks (not_before_at, requested_at, id)
WHERE state = 'queued';

CREATE INDEX CONCURRENTLY race_resolution_post_tasks_running_lease_idx
ON race_resolution_post_tasks (lease_expires_at, requested_at, id)
WHERE state = 'running';

CREATE INDEX CONCURRENTLY race_resolution_post_tasks_terminal_cleanup_v2_idx
ON race_resolution_post_tasks (completed_at, id)
WHERE state IN ('succeeded','succeeded_with_failures')
  AND snapshot_state NOT IN ('pending','attempting');
```

At the production snapshot the first two indexes would have contained zero
rows. They directly serve each claim branch.

### 14.4 Notification schedules and Inbox

```sql
CREATE INDEX CONCURRENTLY notification_schedules_pending_due_idx
ON notification_schedules (available_at, id)
WHERE status = 'PENDING';

CREATE INDEX CONCURRENTLY notification_schedules_admission_due_idx
ON notification_schedules
  (admission_class, available_at, admission_sequence, id)
WHERE status = 'ADMISSION_PENDING';

CREATE INDEX CONCURRENTLY notification_schedules_terminal_cleanup_idx
ON notification_schedules (updated_at, id)
WHERE status IN ('MATERIALIZED','EXPIRED','CANCELLED','CANCELLED_NO_ACTIVE_RACE');

CREATE INDEX CONCURRENTLY inbox_delivery_outbox_active_due_idx
ON inbox_delivery_outbox (available_at, id)
WHERE status IN ('PENDING','RETRY','LEASED');

CREATE INDEX CONCURRENTLY inbox_delivery_outbox_admission_due_idx
ON inbox_delivery_outbox
  (admission_class, available_at, admission_sequence, id)
WHERE status IN ('ADMISSION_FIRST','ADMISSION_RETRY','ADMISSION_LEASED');

CREATE INDEX CONCURRENTLY inbox_delivery_device_attempts_retry_due_idx
ON inbox_delivery_device_attempts (next_attempt_at, id)
WHERE disposition IN ('PENDING','RETRY','TRANSIENT_FAIL','TIMEOUT');
```

Verify actual status constants in integration tests before finalizing migration
SQL; the listed statuses come from current claim/reconciliation code. An index
whose predicate does not exactly match its consuming query must not ship.

### 14.5 Receipt indexes

Primary/unique indexes are created with the new tables:

```sql
CREATE UNIQUE INDEX race_resolution_post_task_receipts_dedupe_key
ON race_resolution_post_task_receipts (dedupe_key);

-- PK (race_id,source_generation) serves race-lifetime ownership/replay.

CREATE INDEX race_resolution_delivery_intent_receipts_race_generation_idx
ON race_resolution_delivery_intent_receipts
  (race_id, source_generation, delivery_key_hash);

-- PK (delivery_key_hash) serves intent replay; the index above serves FK
-- race cascade and task-generation audit.

CREATE UNIQUE INDEX domain_event_receipts_domain_event_id_key
ON domain_event_receipts (domain_event_id);

CREATE INDEX domain_event_receipts_source_idx
ON domain_event_receipts
  (replay_source_type, replay_source_id, event_key);

CREATE INDEX domain_event_receipts_provisional_idx
ON domain_event_receipts (created_at, event_key)
WHERE receipt_state = 'PROVISIONAL';

CREATE INDEX notification_schedule_receipts_source_idx
ON notification_schedule_receipts
  (source_type, source_id, recipient_user_id, delivery_key)
WHERE source_kind = 'SOURCE_BACKED';

CREATE INDEX notification_schedule_receipts_direct_cleanup_idx
ON notification_schedule_receipts
  (direct_retain_until, recipient_user_id, delivery_key)
WHERE source_kind = 'DIRECT';

-- The notification receipt PK is (recipient_user_id,delivery_key).
```

### 14.6 Resolution queue index decision

Do not add a new resolution claim index in the first migration. Production's
1,174-row queue was small and the claim was not dominant. Wake-driven polling
reduces executions substantially. After deployment, use
`pg_stat_statements` and `EXPLAIN (ANALYZE, BUFFERS)` on a SELECT-only
candidate to decide whether separate queued/running partial indexes are worth
their write amplification.

## 15. Exact source files to modify

### Global summaries

- `src/modules/steps/services/globalEventSummaryCapture.js`
- `src/modules/steps/services/globalEventSummaryLifecycle.js`
- `src/modules/steps/jobs/globalEventSummary.js`
- `src/modules/steps/commands/recordStepSyncV2.js`
- `src/modules/steps/services/globalStepEventEntitlement.js`
- `src/modules/home/services/homeLaunchAuxiliaryBatch.js` (metrics only)
- `src/modules/home/routes.js` (metrics only)

### Race resolution, placement, and post tasks

- `src/modules/races/jobs/raceResolutionQueueV2.js`
- `src/modules/races/models/raceResolutionJobV2.js`
- `src/modules/races/services/enqueueRaceResolution.js`
- `src/modules/races/services/raceStateResolution.js`
- `src/modules/races/services/raceScoringPrefetch.js`
- `src/modules/races/models/racePlacementTransitionJob.js`
- `src/modules/races/models/racePlacementBaseline.js`
- `src/modules/races/jobs/racePlacementTransitionWorker.js`
- `src/modules/races/services/raceResolutionPostTaskHandoff.js`
- `src/modules/races/models/raceResolutionPostTask.js`
- `src/modules/races/models/raceResolutionPostTaskReceipt.js` (new)
- `src/modules/races/models/raceResolutionDeliveryIntentReceipt.js` (new)
- `src/modules/races/jobs/raceResolutionPostTaskRunner.js`
- `src/modules/giveaways/jobs/qualificationIntentRecovery.js`

### Domain events and notifications

- `src/modules/domainEvents/models/domainEventOutbox.js`
- `src/modules/domainEvents/models/domainEventReceipt.js` (new)
- `src/modules/domainEvents/services/notificationProjector.js`
- `src/modules/domainEvents/jobs/domainEventProjection.js`
- `src/modules/domainEvents/jobs/domainEventRetention.js`
- `src/modules/notifications/services/notificationDelivery.js`
- `src/modules/notifications/models/notificationScheduleReceipt.js` (new)
- `src/modules/notifications/services/notificationAdmission.js`
- `src/modules/notifications/jobs/notificationScheduleRelease.js`
- `src/modules/notifications/jobs/notificationCompletenessReconciler.js`
- `src/modules/inbox/jobs/inboxDelivery.js`
- `src/shared/cache/redisCache.js`
- `src/index.js`

### Schema, migrations, tests, and operations

- `prisma/schema.prisma`
- new additive Prisma migrations described in section 19
- integration/unit tests listed in section 21
- `docs/postgresql-coordinated-optimization-runbook.md`
- capacity/load-test scripts and metrics modules

## 16. New modules/helpers

1. `src/shared/queues/postgresWakeCoordinator.js` — coalesced Redis wake,
   next-due timer, and fallback polling.
2. `src/modules/races/services/raceScoringInputBatch.js` — bounded source-row
   pages and model-compatible adapters; scoring math remains elsewhere.
3. `src/modules/races/models/raceResolutionPostTaskReceipt.js` — race-lifetime
   generation/task dedupe and terminal proof.
4. `src/modules/races/models/raceResolutionDeliveryIntentReceipt.js` —
   race-lifetime delivery-key disposition/dedupe.
5. `src/modules/domainEvents/models/domainEventReceipt.js` — replay-source-
   lifetime event-key/full-envelope proof.
6. `src/modules/notifications/models/notificationScheduleReceipt.js` —
   source/direct-lifetime `(recipient,delivery_key)` dedupe.
7. `src/shared/observability/durableQueueMetrics.js` — aggregate counters and
   histograms without IDs, payloads, tokens, or step data.
8. `src/modules/maintenance/jobs/durableQueueRetention.js` — bounded,
   per-table cleanup orchestration. Domain-specific eligibility remains in each
   repository; this module only schedules and budgets pages.

## 17. Public API contract and frontend plan

### API contract

No endpoint, method, request JSON, response JSON, status code, or error code
changes.

Existing relevant contracts remain:

- sync-v2 continues returning its current step and optional summary-work
  receipt fields;
- `GET /home/global-event-summary-work/:id` continues returning
  `{"state": string, "expiresAt": string}` for the owning user;
- Home summary and race endpoints retain all current fields;
- notification and Inbox endpoints retain all current pagination and read
  behavior.

No new required parameter is introduced. No field becomes non-nullable for a
client.

### Frontend plan

None. iOS and Android continue using the existing backend contract. There are
no loading, empty, or error-state changes and no UI placement changes.

### Frozen-client behavior

A frozen client can continue polling a summary work ID for 30 days because the
work row remains. Inbox alerts remain for their current 30-day visibility
period. Internal payload cleanup is never visible through a public endpoint.

## 18. Data migration and cleanup strategy

### 18.1 Receipt migration sequence

1. Additive transactional migration `durable_queue_receipt_tables` creates all
   four exact Section 7/8 tables, CHECK constraints, primary/unique keys, race/
   user foreign keys, and the old-binary-compatible domain-event provisional
   receipt trigger. It changes no existing column or status and deletes no row.
2. Dedicated nontransactional migration `durable_queue_receipt_indexes`
   creates every Section 14.5 secondary index with `CREATE INDEX
   CONCURRENTLY`. It creates no table/data and contains no unrelated DDL.
3. Regenerate Prisma mappings and add the four model helpers in Section 16.
   Existing binaries ignore the additive tables; the domain trigger is the only
   old-writer bridge.
4. Deploy receipt-aware writers/readers with cleanup disabled. Run the four
   backfills below and their verification queries.
5. Only after the seven-day rollback window and explicit cleanup cutoff may the
   bounded payload cleanup migration/job become operational. Receipt lifetime
   rules themselves are permanent and are not shortened at that cutoff.

### 18.2 Backfill principles

- Add nullable/default-safe columns first.
- Backfill in primary-key or completion-time pages of 500.
- Commit every page.
- Sleep/yield when a page exceeds 250 ms or replica/WAL lag crosses the
  maintenance threshold.
- Never hold a transaction across a Redis call or provider call.
- Every backfill is idempotent and restartable.
- Record cursor and counts in `job_runs` or a dedicated maintenance progress
  row.

### 18.3 Receipt backfills

Domain receipts:

1. scan outbox rows in `(created_at,id)` order, 500 at a time;
2. derive replay source identity and compute the versioned digest over the
   complete canonical immutable event envelope plus ordered audience;
3. `INSERT ... ON CONFLICT DO NOTHING`;
4. stamp an unresolvable source `LEGACY_UNMAPPED`, which is never age-cleaned;
5. verify receipt count, FINAL state, source mapping, and digest conflicts;
6. do not delete payload rows until verification passes.

Post-task and delivery-intent receipts:

1. scan terminal tasks in `(completed_at,id)` order;
2. insert one task receipt per `(race_id,source_generation)` and aggregate
   counts set-wise for diagnostics;
3. insert one intent receipt per terminal `delivery_key_hash`, preserving task,
   kind, and disposition;
4. insert idempotently and reject any immutable-key mismatch;
5. verify every task and every child intent eligible for deletion has its own
   receipt and a live owning race.

Notification schedule receipts:

1. inventory every schedule producer and classify each row SOURCE_BACKED or
   DIRECT using stable source columns—not payload inspection;
2. scan schedules in `(created_at,id)` pages and insert the composite
   `(recipient_user_id,delivery_key)` receipt;
3. for source-backed rows, persist exact source type/ID/revision; for direct
   rows, calculate visibility end plus that producer's maximum retry horizon;
4. mark unclassifiable legacy rows SOURCE_BACKED with an unmapped source and
   retain indefinitely;
5. verify immutable collisions, terminal status, downstream completion, and
   one receipt per schedule before any schedule payload cleanup.

Placement artifacts require no backfill because they are omitted. Existing and
new placement jobs keep the current canonical hydration path.

### 18.4 Cleanup worker

Each five-minute run has a global budget:

- maximum 10 pages;
- maximum 500 parent rows per page;
- maximum 2 seconds of database execution before yielding/stopping;
- stop if lock timeout, statement timeout, replica lag, or WAL budget is
  exceeded;
- log aggregate deleted rows/bytes and oldest retained age.

Initial cleanup order:

1. post-task terminal payload older than 24h with verified task receipt and a
   verified receipt for every child intent;
2. successful domain-event payload older than 7d with a FINAL, source-mapped
   verified receipt and no
   active downstream;
3. terminal schedules whose downstream lifecycle is complete and whose
   verified receipt owns dedupe; receipt deletion itself follows source
   deletion or direct `direct_retain_until`, never schedule age alone;
4. orphan full triggers;
5. ordinary recurring retention.

Deletion frees reusable table space. Do not promise immediate disk shrink.

## 19. Single-release deployment order

This is one coordinated release effort, with multiple internal migrations and
commits.

### Phase A — pre-release verification

1. Enable `pg_stat_statements` in the approved maintenance window if
   supported and capture a pre-change baseline.
2. Restore a recent sanitized production snapshot into a non-production DB.
3. Run receipt/backfill/cleanup dry-run queries and record expected counts.
4. Run all tests and load scenarios in section 22.
5. Confirm no migration targets production during tests.

### Phase B — additive schema migrations

1. Add summary readiness columns.
2. Add parent projection counters.
3. Add all four receipt tables: domain event, notification schedule, post task,
   and delivery intent, including checks, keys, FKs, and indexes from Sections
   7, 8, and 14.5.
4. Replace the summary fence trigger only after serialization tests pass.
5. Create only the concurrent indexes proven by the plan/benchmark gates.
6. Apply only table reloptions proven by the production-shaped load test.
7. Do not drop any column, table, constraint, or old index.

These migrations are compatible with the currently deployed binary.

### Phase C — application deployment

Deploy the one new binary. PM2 retains exactly:

- two HTTP processes;
- one resolution process;
- one cron process;
- no `all` production role.

The application permanently uses wake-first schedulers, readiness transitions,
batch scoring and receipt-aware dedupe. No feature flag
or percentage gate exists.

### Phase D — bounded backfill and cleanup

After all old PM2 processes have exited:

1. start/retry receipt backfills;
2. verify counts and digest conflicts;
3. let the bounded cleanup worker remove eligible historical payloads;
4. observe WAL, locks, replication/backups, queue lag, and DB CPU;
5. pause by stopping the deployment-level maintenance process if safety limits
   are exceeded; this is operational control of a bounded job, not a feature
   flag.

### Phase E — maintenance and validation

1. run approved per-table `ANALYZE`;
2. run approved ordinary `VACUUM (ANALYZE)` only where dead tuples justify it;
3. capture post-change query, tuple, WAL, and CPU metrics;
4. retain old indexes and schema for rollback;
5. defer destructive schema/index drops to a later reviewed cleanup release.

## 20. PostgreSQL observability

DigitalOcean's current official documentation lists
`pg_stat_statements` as supported on PostgreSQL 18 Standard Edition and
pre-installed on Advanced Edition. Standard Edition supports
`CREATE EXTENSION pg_stat_statements`; the cluster API exposes
`pg_stat_statements.track` with default `top`.
See [DigitalOcean supported PostgreSQL extensions](https://docs.digitalocean.com/products/databases/postgresql/details/supported-extensions/)
and [DigitalOcean PostgreSQL API configuration](https://docs.digitalocean.com/products/databases/postgresql/reference/api/).

Preflight commands:

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name = 'pg_stat_statements';

SHOW shared_preload_libraries;
SHOW pg_stat_statements.track;
```

If `shared_preload_libraries` already contains it, create the extension in the
application database during the approved window:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Do not reset statistics. Set `pg_stat_statements.track = 'all'` only if nested
trigger/function statements must be attributed; otherwise retain `top` to
limit overhead. Expected overhead is low but nonzero and must be measured.
Whether a DigitalOcean restart is required depends on the cluster's current
preload setting and edition; schedule one only if the control panel/API reports
a restart-required configuration change.

Retain at least seven days of exported daily snapshots containing query ID,
calls, total/mean/max execution time, rows, shared/temp blocks, WAL bytes, and
stats reset time. Do not export bind values or raw query parameters.

## 21. Application metrics

Add aggregate-only metrics:

- `global_summary_capture_lookup_total`;
- `global_summary_capture_lookup_per_sync`;
- `global_summary_waiting_races_ready_total`;
- `global_summary_recovery_repair_total`;
- `global_summary_worker_claim_total{state}`;
- `race_resolution_total{plan,outcome}`;
- `race_resolution_participants`;
- `race_resolution_sql_calls`;
- `race_resolution_batch_rows{kind}`;
- `race_resolution_batch_bytes`;
- `race_scoring_batch_fallback_total{reason}`;
- `race_resolution_query_seconds`;
- `race_resolution_compute_seconds`;
- `durable_queue_wake_received_total{queue}`;
- `durable_queue_wake_coalesced_total{queue}`;
- `durable_queue_wake_publish_failure_total{queue}`;
- `durable_queue_fallback_poll_total{queue,found_work}`;
- `durable_queue_idle_poll_total{queue}`;
- `durable_queue_oldest_eligible_seconds{queue}`;
- `placement_hydration_rows` and `placement_hydration_ms`;
- `placement_canonical_rows_read`;
- `domain_projection_claim_examined_rows`;
- `domain_projection_completed_total`;
- `durable_queue_rows{queue,state_class}`;
- `durable_queue_cleanup_rows_total{table}`;
- `durable_queue_cleanup_seconds{table}`.

Logs and metrics must not contain user IDs, race IDs, device tokens, payloads,
step totals, or connection strings.

## 22. Full testing strategy

Tests are written first. Integration tests use a dedicated local/test database
whose `DATABASE_URL` is explicitly verified as non-production. Never run
bare `npm test`; use `npm run test:unit` and
`npm run test:integration`.

### 22.1 Scoring equivalence

Build a differential integration harness that invokes the current canonical
model interface and the new batch adapter over identical persisted fixtures.
Assert identical participant totals, bonuses, finishes, effects, boxes,
settlement writes, fingerprints, and emitted commands.

Required cases:

- 3-, 5-, 7-, and 14-day races;
- midnight start/end and mid-day join;
- multiple user time zones;
- spring-forward and fall-back DST boundaries;
- active and ended global events;
- Runner's High and all multiplier stacking;
- penalties and every settlement effect type;
- Leech and Hitchhike dependency chains;
- Trail Mine candidate ordering and shield;
- mystery-box thresholds;
- missing, zero, overlapping, open, stale, and delayed samples;
- daily/sample max behavior;
- stale input generations and fingerprint rejection;
- join, leave, kick, forfeit, and team membership;
- finish snapshots with multiple finishers;
- scoped/closure and FULL resolution;
- settlement at exact boundary.

Add deterministic randomized/property tests. Persist the seed for any failure.
For every generated input, old and new authoritative outputs must match.

#### Scoped dependency-set identity (hard gate)

Before changing the loader, add a test-only selection trace at the existing
boundary immediately after `buildRaceScoringDependencyClosure` and before
`resolveRaceState`. It records only sorted participant IDs, count, selected
plan, and fallback reason. Generate and check in baseline fixtures from the
unchanged implementation; do not regenerate them as part of the optimization.
The optimized run consumes the identical database fixture, claimed envelope,
as-of timestamp, fingerprint, and effect/event graph and must deep-equal both:

```text
before.participantIds === after.participantIds
before.participantCount === after.participantCount
before.plan === after.plan
before.fallbackReason === after.fallbackReason
```

Final-score parity is insufficient and is asserted separately. The matrix
iterates every key in `DIRTY_REASONS` and every key in
`POWERUP_SCOPE_BY_TYPE`, with SELF, TARGET, DEPENDENCY, RACE_WIDE, TEAM,
SCORING_INERT, unsupported, expired-history, due-expiry, malformed-metadata,
and unknown-type cases. Each named case explicitly asserts the expected sorted
participant ID array and numeric count; no assertion may use only a set size or
only final totals. A structural test requires matrix keys to equal the exported
registry keys so a newly added reason/power-up fails CI until classified.

Fixtures include isolated actor/target plus unrelated participants, chained
Hitchhike/Leech edges, Sneaky Swap, Pocket Watch, Trail Mine candidate
escalation, team and race-wide escalation, mixed coalesced reasons, invalid
dirty IDs, scope caps, and fingerprint/fence changes. For an isolated
actor-target mechanic whose current closure selects `[actorParticipantId,
targetParticipantId]`, assert exactly those two IDs and `count === 2`; the
optimized loader may include another participant only when the unchanged
closure baseline already follows an existing edge or escalates to FULL.

Run the identity assertion twice: once at initial plan selection and once after
the fenced dependency recheck immediately before authoritative writes. Add a
public-path integration case beginning with the real step-sync/power-up HTTP
path, claiming the durable job and observing the worker's selection trace. The
test must fail before any scoring-output assertion if the dependency set
differs. These tests are mandatory before implementation and remain permanent
regression coverage.

### 22.2 Wake and queue recovery

For every queue kind:

- Redis unavailable before enqueue;
- Redis unavailable after commit;
- Redis restart and resubscribe;
- dropped wake;
- duplicate wake;
- 100 wakes for one race/item;
- crash after DB commit before wake;
- worker crash after claim;
- crash during compute;
- crash before fenced commit;
- expired lease;
- multiple workers with SKIP LOCKED;
- future not-before/available/retry;
- next-due timer cancellation/rearm;
- recovery poll finds lost-wake work;
- no concurrent drains in one process.

With healthy Redis, each test commits newly eligible work and asserts that the
matching subscriber requests a drain and begins its first PostgreSQL claim
without advancing the fallback/recovery timer. Future debounce,
`not_before_at`, `available_at`, retry, and admission boundaries remain
authoritative; the wake may arm their exact due timer but must not claim early.
The 5/10/30/60-second PostgreSQL intervals are exercised only in lost-wake or
Redis-unavailable cases and must never appear in the healthy-wake latency path.

No durable work may be lost or processed outside its existing idempotency
contract.

### 22.3 Global summaries

- end boundary creates exactly one work row;
- recovery creates a missing work row;
- one sync performs one eligibility lookup;
- capture closure changes force retry;
- impact finalization sets readiness atomically;
- pending impacts do not cause one-second lease churn;
- lost readiness update is repaired within recovery interval;
- expiry and unscorable terminalization;
- v1 legacy compatibility;
- old trigger/worker overlap serialization;
- Home receipt polling for active and terminal states.

### 22.4 Notifications

- duplicate event before and after payload cleanup;
- domain-event receipt full-envelope collision, provisional finalization,
  replay-source deletion cleanup, and indefinite legacy-unmapped retention;
- same key/different digest is rejected and alarmed;
- duplicate audience/projection/schedule release;
- failed projection replay within retention;
- retry and provider ambiguity;
- deleted recipient;
- stale device ownership;
- schedule dedupe after source payload cleanup;
- notification-schedule receipt collision; source-backed retention through
  source deletion; direct retention through alert visibility plus maximum
  producer retry; and one integration case for every producer classification;
- parent projection counters under concurrent completion;
- counter reconciliation after simulated crash;
- bounded retention with active downstream;
- full-terminal page deletion;
- no terminal-history rows in active claim plans.

### 22.5 Post tasks

- duplicate generation before and after task cleanup;
- receipt prevents snapshot or intent replay;
- task receipt survives beyond 30 days and remains until race deletion;
- per-intent `delivery_key_hash` receipt returns the recorded disposition and
  prevents provider replay after payload cleanup;
- task and intent receipts cascade only when the owning race is deleted;
- backfill refuses task cleanup when any child intent lacks its own receipt;
- ambiguous-at-most-once recovery;
- queued and expired-running claim branches;
- next-due timer;
- qualification recovery is independent;
- cleanup skips active child/snapshot state;
- bounded pages and crash resume.

### 22.6 Placement

- newer generation while older placement runs;
- canonical fingerprint mismatch requeues with no event;
- current mute value suppresses event;
- baseline CAS loser emits nothing;
- individual/team/tie/finished/forfeited parity;
- current canonical pre-plan and fenced hydrations remain unchanged;
- the optional artifact benchmark records 10/50/500-person CPU, WAL, storage,
  index, cleanup, dead-tuple, and latency measurements but creates no release
  schema unless the Section 11.3 gate is separately approved.

### 22.7 Retention and frozen clients

- old summary work polling remains valid;
- Inbox client visibility remains 30 days;
- job status/generation readers remain valid;
- receipts preserve dedupe and replay safety;
- cleanup cannot select active/retry/leased rows;
- migration works with the previous application binary;
- no destructive down migration is required for application rollback.

## 23. Load-test plan

Use a non-production database restored from sanitized production shape and the
existing capacity harness.

### Scenarios

1. Idle: all queues empty for ten minutes.
2. Normal: many small races and production-shaped step-sync traffic.
3. Large race: 500 participants sync in a concentrated window.
4. Notification fan-out: several events with 100–500 recipients.
5. Global-event boundary: production-shaped entitlement and race counts.
6. Recovery: disable Redis, enqueue work, restore Redis, and verify fallback.
7. Cleanup: production-sized terminal tables with bounded deletion active.

### Measure before and after

- SQL statements/s and transactions/s;
- tuples fetched/s and returned/s;
- shared blocks hit/read/s;
- WAL bytes/s;
- dead tuples and autovacuum activity;
- Node CPU/RSS by process role;
- DB CPU from DigitalOcean metrics;
- queue claim calls and empty claims;
- queue lag and end-to-end latency;
- resolution SQL calls/participants;
- notification projection examined/completed ratio;
- cleanup transaction duration and rows;
- Redis wake latency and fallback productivity.

### Acceptance thresholds

- idle queue-generated PostgreSQL statements fall by at least 90%;
- global-summary work index scans fall by at least 90%;
- not-ready `WAITING_RACES` rows are not updated between recovery sweeps;
- terminal projection tuple fetches fall by at least 90% when backlog is zero;
- empty post-task claim frequency falls from 4/s to no more than 1/30s;
- a 500-participant resolution has no participant-linear SQL fallback;
- batch V8 heap growth remains within the 32 MiB per-page guard and process memory
  does not grow across repeated runs;
- p95 race-resolution, placement, and notification latency do not regress;
- every lost-wake scenario converges within its documented recovery interval;
- with healthy Redis, commit-to-drain-request and commit-to-first-claim p50,
  p95, and p99 are not statistically slower than the pre-change healthy
  baseline at the load generator's 10 ms measurement resolution; no eligible
  item waits for a 5/10/30/60-second recovery poll, and any delay is explained
  solely by its pre-existing debounce/not-before/available/retry/admission
  boundary;
- no duplicate user-visible event or notification is produced.

## 24. Rollback strategy

Rollback is deployment-level, not flag-based.

### Safe rollback assets

- all columns are additive/default-safe;
- new tables and indexes may remain unused by the previous binary;
- old full indexes remain;
- old statuses and API fields remain;
- receipt triggers accept inserts from the previous binary;
- placement jobs retain their existing canonical hydration path.

### Application rollback

Deploy the previous binary. It will resume fixed polling and current hydration.
New nullable columns/tables are ignored. Do not reverse migrations during an
incident.

### Cleanup irreversibility

Deleting payload history is irreversible. It is safe only after:

- receipts are fully backfilled and verified;
- no active downstream exists;
- the row is past its documented full-payload retention;
- frozen clients do not query it;
- replay requirements are satisfied by the receipt or retained failed row.

Delay destructive table/column/index drops to a later cleanup release. More
importantly, do not begin shortened payload cleanup until the explicit cutoff
in Section 30.6. Before that cutoff, the unchanged previous binary remains a
valid rollback target. After the first deletion, rollback is intentionally
limited to the last receipt-aware compatibility build; a pre-receipt binary
cannot validate a replay after its outbox/audience rows have been removed.

## 25. Expected performance improvement

| Workload | Expected result |
|---|---|
| Global-summary index scans | greater than 90% reduction by removing per-second discovery/readiness churn and using active-only indexes |
| Notification projection tuple fetches while idle | greater than 90% reduction; active claims should touch near-zero rows when backlog is zero |
| Post-task empty polling | about 99% lower claim frequency: 4/s to one 30-second fallback, with immediate wake for real work |
| Full-trigger empty promotion | about 95% lower idle promotion frequency: every 250 ms to the shared five-second resolution recovery tick |
| Race scoring SQL calls | order-of-magnitude reduction for fallback/N+1 cases; bounded 15–35 source statements for a 500-person pathological race instead of thousands |
| Placement hydration | unchanged in this release; avoids unproven write/WAL amplification |
| Transactions/s | substantial idle reduction and moderate loaded reduction |
| Tuple fetches/s | substantial reduction from summary and projection paths; scoring reduction depends on sample volume |
| DB CPU | expected substantial reduction; do not assign a precise percentage before post-release measurement |
| Resolution Node CPU | potentially moderate increase in in-memory calculation efficiency but bounded RSS; likely lower total wall time from fewer awaits |
| Storage | large reduction after 24h post-task and 7d successful event retention; filesystem size may not shrink until later reindex/repack, but reusable space increases |

## 26. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Readiness hint becomes stale | final impact-vector read remains authoritative; 60-second repair sweep |
| Wake published before commit | central after-commit callback contract and tests |
| Lost wake delays work | queue-specific PostgreSQL fallback and due timer |
| Receipt collision hides changed payload | canonical digest mismatch is terminal/alarmed |
| Cleanup breaks replay | keep failures longer; verified receipt before delete; integration tests |
| Batch memory spike | 25-whole-user/50k-row pages, actual 32 MiB V8 heap-growth guard, and single-user streaming |
| Batch behavior drifts from canonical math | same model interface and differential/property tests |
| Participant mutation bypasses generation | structural writer audit/test and existing generation/fingerprint fences |
| Concurrent index creation stresses managed DB | one index at a time in maintenance window; monitor locks/WAL |
| Lower autovacuum thresholds raise maintenance CPU | stage with measured churn; table-specific thresholds; observe before further tuning |
| Old worker overlap | additive schema, DB trigger compatibility, existing locks, startup quiet period |
| One-release blast radius | multiple reviewed commits and migrations, but one tested/deployed binary; deployment rollback remains available |

## 27. Deliberately not changing

- PostgreSQL remains authoritative.
- Redis stores no durable queue state.
- Resolution generation, lease, and fingerprint fences remain.
- Placement compare-and-set remains.
- Notification delivery keys and at-most-once ambiguous outcomes remain.
- `SKIP LOCKED` remains for competing workers.
- Race scoring formulas and canonical helpers remain.
- Existing full indexes are not dropped yet.
- Resolution claim ordering/index is not changed without post-release query
  evidence.
- Inbox alert retention is not shortened.
- Global-event impact retention is not shortened until blocked lifecycle rows
  are repaired.
- No DB capacity resize is proposed as a substitute for removing avoidable
  work.
- No exact DB CPU percentage reduction is promised.

## 28. Acceptance criteria and definition of done

The implementation is complete only when:

1. all code and migrations above ship together in one release without feature
   flags;
2. all new tests are written first and pass;
3. `npm run test:unit` and `npm run test:integration` pass against a verified
   non-production database;
4. scoring differential tests show identical results, and the permanent
   dependency-set matrix proves identical sorted participant IDs and count for
   every scoped dirty reason and every registered power-up before and after;
5. wake-loss tests show no lost work;
6. old-client/API contract tests pass unchanged;
7. migration compatibility with the previous binary is proven;
8. idle load meets the 90% query-reduction criteria;
9. 500-participant load has bounded memory and no N+1 fallback;
10. domain-event, notification-schedule, post-task, and delivery-intent
    receipts are each backfilled and verified before cleanup;
11. the architect and another engineer approve the plan;
12. a code-reviewer subagent reviews the combined implementation;
13. no production deployment or maintenance occurs without explicit,
    in-the-moment user approval;
14. post-deployment `pg_stat_statements`, table stats, queue lag, Redis wake,
    and DigitalOcean CPU evidence are captured;
15. no placement artifact schema/code ships; current hydration remains unless
    a separately approved benchmark satisfies Section 11.3;
16. the migration contains a `Proven reloptions` evidence table and includes
    no autovacuum/fillfactor setting absent from it; when no candidate passes,
    no reloption migration is generated;
17. healthy-Redis wake tests and production-shaped load prove that newly
    committed eligible work begins draining immediately, never waits for a
    PostgreSQL recovery interval, and has no commit-to-first-claim latency
    regression versus the pre-change healthy baseline, except for unchanged
    debounce/not-before/available/retry/admission eligibility rules.

## 29. Implementation commit sequence

These commits are reviewed and tested separately but deployed as one release:

1. observability and query-count test harnesses;
2. additive schema: readiness, counters, and receipts;
3. concurrent active-state indexes;
4. shared wake coordinator and queue scheduler conversions;
5. global-summary durable readiness/coalesced capture;
6. notification parent counters, receipts, active claims, and set-based
   retention;
7. post-task receipts, split recovery scheduler, and claim rewrite;
8. complete bounded race-scoring batch adapter;
9. bounded backfills/cleanup and maintenance runbook;
10. full integration/property/load verification.

## 30. Architect-reviewed implementation contract

This section records the final constraints produced by architecture review. It
is authoritative anywhere an earlier illustrative example is less specific.
No implementation PR may defer one of these items without revising and
re-approving this plan.

### 30.1 Pre-implementation attribution gate

**Gate status: summary-storm attribution complete; full workload attribution
still blocked by the absent extension.** Section 5.6 records the fresh
production measurement: normalized live query ID, 0.90 inferred calls/s,
508.468 ms execution time, 4,997 target-index searches/call, 4,501 searches/s,
31,282 buffer hits, and the exact nested-loop anti-join source. It confirms the
ranking and is sufficient to authorize planning the summary fix. No code is
authorized by this document alone.

Production still lacks `pg_stat_statements`; it was not enabled because doing
so changes production state and the measurement brief prohibits that action.
Consequently total historical execution time, WAL by normalized statement, and
the complete top-query ranking remain unavailable. Before coding any other
query family, capture a fresh high-CPU `pg_stat_statements` window if an
operator separately enables it, plus SELECT-only `EXPLAIN (COSTS, VERBOSE)`
plans for every claim and `nextDueAt` query. Record query ID, calls/second,
total/mean time, rows, blocks, and WAL in the implementation PR. If production
differs from this plan, revise the query/index pair before migration work.

### 30.2 Exact claim-query/index contract

Every active queue uses separate due and expired-lease branches. Combining
them with an OR defeats timestamp ordering and cannot be described as served
by one index. The implementation must include the final claim SQL, matching
`nextDueAt` SQL, SELECT-only expected plan, and these branch indexes:

| Queue/branch | Exact active predicate | Leading order/index columns |
|---|---|---|
| domain event due | `status IN ('PENDING','RETRY') AND available_at <= now` | `(available_at, occurred_at, id)` |
| domain event expired | `status='EXPANDING' AND lease_until <= now` | `(lease_until, occurred_at, id)` |
| projection due | `status IN ('PENDING','RETRY') AND available_at <= now` | `(available_at, id)` plus the existing active aggregate-order index |
| projection expired | `status='PROCESSING' AND lease_until <= now` | `(lease_until, available_at, id)` |
| summary queued | `status='QUEUED' AND available_at <= now` | `(available_at, id)` |
| summary processing recovery | `status='PROCESSING' AND lease_until <= now` | `(lease_until, available_at, id)` |
| summary ready | `status='WAITING_RACES' AND ready_at IS NOT NULL AND available_at <= now` | `(available_at, id)` |
| summary sync expiry | `status='WAITING_SYNC' AND expires_at <= now` | `(expires_at, id)` |
| post task due | `state='queued' AND not_before_at <= now` | `(not_before_at, requested_at, id)` |
| post task recovery | `state='running' AND lease_expires_at <= now` | `(lease_expires_at, requested_at, id)` |
| schedule normal | `status='PENDING' AND available_at <= now` | `(available_at, id)` |
| schedule admission | `status='ADMISSION_PENDING' AND available_at <= now` | `(admission_class, available_at, admission_sequence, id)` |
| Inbox normal due | `status IN ('PENDING','RETRY') AND available_at <= now` | `(available_at, id)` |
| Inbox normal recovery | `status='LEASED' AND lease_until <= now` | `(lease_until, available_at, id)` |
| Inbox admission first | `status='ADMISSION_FIRST' AND available_at <= now` | `(admission_class, available_at, admission_sequence, id)` |
| Inbox admission retry | `status='ADMISSION_RETRY' AND available_at <= now` | `(admission_class, available_at, admission_sequence, id)` |
| Inbox admission recovery | `status='ADMISSION_LEASED' AND lease_until <= now` | `(admission_class, lease_until, admission_sequence, id)` |

`nextDueAt` takes `LEAST(MIN(due timestamp))` across those branch-specific
queries; it never scans terminal rows. Include expiry predicates from the
consumer query verbatim. Schedule terminal states are only `MATERIALIZED`,
`EXPIRED`, `CANCELLED`, and `CANCELLED_NO_ACTIVE_RACE`; delivery states belong
to Inbox rows. No migration ships on the basis of a generic status list.

### 30.3 Transaction-safe wake ownership and process lifecycle

Reuse `runInPrismaTransaction` and `deferUntilAfterCommit` from `src/db.js`.
Model functions accept a transaction client and return/coalesce wake kinds;
they never import Redis or publish. A root owner either runs through
`runInPrismaTransaction` and registers `deferUntilAfterCommit` while that scope
is active, or awaits an ordinary outer Prisma transaction and publishes only
after its promise resolves. Calling `deferUntilAfterCommit` inside an ordinary
root Prisma transaction is forbidden because it executes immediately outside
the helper's async context.

Enumerate and convert every producer, including the raw domain-event insert in
`globalEventTimezoneReconciliation.js` and all resolution, placement,
post-task, schedule, Inbox, and summary writers. A structural test rejects
Redis imports/calls in model transaction functions and unapproved raw outbox
inserts.

Queue subscribers live in public module indexes and are registered by
`startCrons` in `src/index.js`, with retained stop handles, unsubscribe on
shutdown, and the existing `NODE_APP_INSTANCE` single-cron-owner guard.
Resolution-role processes own resolution, placement, and post-task consumers;
the cron owner owns domain events, schedules, Inbox, summaries, referral
recovery, and retention. HTTP-only workers own none. Full-trigger promotion is
part of the resolution consumer and uses the same five-second recovery tick;
there is no contradictory 30-second full-trigger poller.

### 30.4 Executable bounded scoring and expiry path

`raceScoringPrefetch.js` becomes the sole production-worker data source for
both resolution and `raceExpiry.js`; silent per-participant fallback is
removed. Construct the exact set of `(user_id, range_start, range_end,
ordinal)` rows with `jsonb_to_recordset`, then join samples to those ranges.
Do not use independent `ANY(user_ids)` and range arrays, which form a
cross-product. Select only user ID, sample ID, period start/end, and steps,
ordered by ordinal, period start, sample ID. Daily totals and effect/event data
use the same requested-user set and only required columns.

Process whole users in stable participant order, initially 25 users per chunk.
For an exceptional user exceeding 50,000 sample rows, cursor on
`(ordinal, period_start, sample_id)` and feed the canonical streaming
accumulator; never discard half of a user's timeline. Before discarding that
user's samples, compute base interval sums, every effect-window sum, and the
ordered finish crossing. Cross-participant Hitchhike/Leech phases consume
these compact per-user aggregates after all chunks, so their semantics and
participant order remain unchanged. Load race-level power-up events once, not
once per finisher.

Bound both fetched rows and actual `process.memoryUsage().heapUsed`: target no
more than 50,000 rows and 32 MiB heap growth per chunk, halve the user chunk on
breach, and retry the generation without authoritative writes if one-user
streaming cannot remain within the bound. Record statements, rows, and peak
heap separately for resolution and expiry. Acceptance requires no production
fallback and SQL growth by chunks/pages rather than participants.

### 30.5 Placement artifact decision

Do not implement a placement artifact in this release. Section 11.2 quantifies
the minimum cost: 11/51/501 new heap rows and roughly 23/103/1,003 index entries
for 10/50/500 participants, plus WAL, resolution-transaction latency, retained
storage, dead tuples, and cleanup, to remove only two cached SELECTs. Production
does not rank placement hydration near the measured summary/notification hot
paths. The existing canonical hydration, generation fence, fingerprint check,
and baseline CAS remain unchanged.

The artifact is a separate future optimization requiring the Section 11.3
production-shaped benchmark and explicit plan approval. Until it proves lower
combined database CPU/time without WAL or commit-latency regression, schema,
job references, fingerprint functions, dual paths, and cleanup for artifacts
are all out of scope.

### 30.6 Retention, receipts, and the rollback cutoff

Notification schedule dedupe also needs a compact
`notification_schedule_receipts` row keyed by `(recipient_user_id,
delivery_key)`. Source-backed receipts live until the source is deleted;
direct-producer receipts live through the alert's 30-day visibility plus the
maximum producer retry horizon. The implementation inventory must enumerate
every direct schedule producer. Post-task receipts are keyed by
`(race_id,source_generation)`, intent receipts are individually keyed by
`delivery_key_hash`, and both live until race deletion. Event receipts live
until their identified replay source is deleted; unmapped legacy event sources
are retained indefinitely. Aggregate receipt counts are never dedupe.

Periodic receipt cleanup follows four exact rules:

1. `race_resolution_post_task_receipts` are never selected by age; the owning
   race FK deletes them.
2. `race_resolution_delivery_intent_receipts` are never selected by age; the
   owning race FK deletes them.
3. `domain_event_receipts` are selected only after a locked, source-type-
   specific `NOT EXISTS` proves the replay source was deleted; PROVISIONAL and
   `LEGACY_UNMAPPED` rows are never selected.
4. SOURCE_BACKED `notification_schedule_receipts` require the corresponding
   source-type-specific locked `NOT EXISTS`; DIRECT rows require
   `direct_retain_until <= now`. Both require no live schedule/downstream row.

All four paths use bounded pages and recheck eligibility in the deletion
transaction. There is no fixed 30- or 90-day receipt cleanup.

No shortened payload deletion starts automatically with deployment. There is
a seven-day rollback observation window, followed by explicit operator
acceptance of a roll-forward-only cleanup cutoff after receipt/backfill,
provisional-receipt, active-child, and replay checks are all zero. Before that
cutoff the unchanged previous binary must pass replay tests. After the first
new cleanup deletion, that previous binary is not a valid rollback target;
rollback means redeploying the last receipt-aware compatibility build. Test
both sides of this cutoff and make the runbook state the irreversibility before
the operator command. This is an operational gate, not a runtime feature flag.

Every cleanup query has an exact eligibility predicate and a lock recheck.
Orphan full triggers are deletable only when the race is missing or terminal
and no live resolution job/destination exists; age alone can never discard
work for an active race. Other parents require terminal status, cutoff age,
verified receipt, and `NOT EXISTS` active descendants in the deletion
transaction. Use `FOR UPDATE SKIP LOCKED`, 500 parents/page, at most ten pages,
`lock_timeout=100ms`, `statement_timeout=2s`, and stop a run if a page exceeds
500ms, WAL delta exceeds 16 MiB, total run WAL exceeds 64 MiB, or any replica
replay lag exceeds five seconds. Resume next maintenance tick.

No autovacuum/fillfactor value is currently proven. Section 13.1's table is a
benchmark candidate matrix only. The final migration contains only exact
table/value triples that pass two production-shaped trials and are listed with
their CPU, WAL, latency, HOT/dead-tuple, and vacuum evidence; all unproven
tables keep managed defaults. Fillfactor changes are reversible with `ALTER
TABLE ... SET (fillfactor=100)` but do not rewrite existing pages immediately;
document that limitation and exact rollback SQL. Never imply that ordinary
VACUUM shrinks the files.

### 30.7 Public-path and compatibility proof

The primary acceptance test starts at the real step-sync HTTP handler against
the test PostgreSQL database, runs the durable resolution, placement,
post-task, domain-event, projection, schedule, Inbox, summary, and expiry
workers, and asserts participant totals/finish state, placement baselines,
events, summaries, notifications, and retry idempotency through public output.
Pure differential scoring tests remain useful unit tests but cannot replace
this path. Run the previous production binary's replay suite against the
additive schema before cleanup authorization, and run an explicit post-cutoff
compatibility test proving only the receipt-aware rollback build is accepted.
Never run these tests against production.

## 31. Revision log

### Initial draft

- Traced the current repository rather than assuming the earlier static model.
- Corrected the scoring plan to extend the existing
  `raceScoringPrefetch` adapter.
- Distinguished authoritative global-summary creation at event end from the
  one-second recovery scans.
- Designed queue-specific wakes and fallback intervals.
- Added exact schema, index, retention, cleanup, maintenance, testing, rollback,
  and observability plans.

### Gap pass 1

- Added explicit handling for `WAITING_RACES` readiness instead of merely
  slowing its poll.
- Preserved the final impact-vector reread and summary group fence.
- Added domain-event receipts so deleting terminal payload does not weaken
  event-key idempotency.
- Added post-task receipts so 24-hour payload cleanup is safer than the current
  seven-day dedupe window.
- Added chunk and memory limits for pathological five-minute sample histories.
- Added current-mute validation to placement CAS.
- Kept failed notification payloads longer than successful payloads.

### Gap pass 2

- Added mixed-version trigger compatibility for receipt creation.
- Separated qualification recovery from post-task claims.
- Kept old indexes and deferred destructive drops for rollback.
- Added exact no-work/load acceptance thresholds.
- Added write-path structural tests for placement artifact validity.
- Clarified that table cleanup does not immediately shrink filesystem size.
- Added DigitalOcean-specific `pg_stat_statements` preflight and restart
  qualification.
- Added a deployment-level rollback path with no feature flags.

### Architect review

- Replaced unsafe default-zero projection counters with nullable, validity-
  stamped counters maintained across every writer and backed by a final child
  fence.
- Expanded event receipts to cover the complete canonical envelope and added
  intent- and schedule-level dedupe receipts with source-lifetime retention.
- Added an explicit pre-cleanup rollback window and irreversible cleanup
  cutoff; removed the false claim that an unchanged old binary can replay
  after payload deletion.
- Corrected notification states and split due/expired-lease query-index pairs.
- Replaced the invalid lock-on-UNION post-task example with executable base-row
  locking and multi-worker fairness tests.
- Bound wake ownership to the repository's transaction helper and specified
  process ownership, shutdown, raw-writer guards, and full-trigger cadence.
- Specified whole-user scoring pages, exact requested ranges, streaming finish
  accumulation, real heap limits, and the race-expiry path.
- Initially replaced the capped JSON placement artifact with a normalized
  design; the later user-review gate below supersedes that decision and omits
  artifacts entirely because their net database benefit is unproven.
- Added exact cleanup eligibility/recheck rules and public-path compatibility
  tests.

### User review: attribution and optimization proof gates

- Added a hard invariant and permanent pre/post optimization matrix asserting
  exact sorted dependency participant IDs and count for every dirty reason and
  registered power-up, independently of final scoring parity.
- Completed fresh read-only production attribution of the summary index storm:
  the one-second ended-entitlement recovery statement runs about 0.90/s,
  measured 508.468 ms, and performs 4,997 wrong-index probes per call.
- Re-ranked the exact Section 5.6 source from static likelihood to measured
  confirmation.
- Quantified normalized placement artifacts at 11/51/501 new heap rows and
  roughly 23/103/1,003 index entries for 10/50/500 participants; removed the
  artifact from release scope because no net database benefit is proven.
- Removed all numeric autovacuum/fillfactor candidates. No reloption ships
  unless two production-shaped trials prove that exact table/value pair and
  the migration lists its evidence.
- Moved this README into the frontend repository's `docs/` directory so it is
  visible in the active changeset beside the static and production evidence
  reports.

Fresh-eyes pass 1 removed remaining artifact schema/backfill/deployment/test
references and changed placement from a committed optimization to an omitted,
separately benchmarked future proposal. It also removed every numeric reloption
candidate rather than relying on “benchmark only” labeling.

Fresh-eyes pass 2 separated measured facts from inference: index scans/s came
from independent statistics snapshots, execution time/loops/buffers came from
a SELECT-only equivalent plan, and statement calls/s is explicitly derived
from those two measurements because `pg_stat_statements` is absent. It also
made dependency identity a pre-scoring failure with both initial-selection and
post-fence assertions, a registry completeness guard, and public-path coverage.

### Final receipt and wake consistency pass

Fresh-eyes pass 1 removed the remaining fixed 30/90-day receipt statements and
made the retention matrix agree directly with Section 30.6: task and intent
receipts live through race deletion, event receipts through replay-source
deletion, and schedule receipts through source deletion or the direct producer
visibility/retry horizon.

Fresh-eyes pass 2 traced all four receipt types across schema, keys/indexes,
transactional creation, replay behavior, backfill, retention, cleanup,
migration ordering, model helpers, and integration tests. It added missing
schedule/intent coverage and an acceptance gate proving healthy Redis begins a
drain immediately rather than waiting for fallback polling.
