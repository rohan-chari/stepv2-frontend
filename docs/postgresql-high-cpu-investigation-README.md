# PostgreSQL Sustained High-CPU Investigation

**System:** Bara / Steps Tracker backend  
**Investigation date:** September 2, 2026  
**Scope:** Static code and schema inspection. No production queries were run.  
**Status:** Diagnostic report only. No code, schema, configuration, or production changes were made.

## 1. Executive summary

### Bottom line

The PostgreSQL-backed durable queue architecture is not inherently unsuitable,
but the current implementation performs substantial avoidable database work
while preserving durable-queue semantics.

The strongest code-confirmed concerns are the combination of:

1. multiple permanent database pollers, including three 250 ms workers;
2. the race-resolution worker executing large-trigger promotion before every
   claim, even while no trigger exists;
3. claim queries containing `OR` branches, eligibility timestamps,
   expression-based priority ordering, and historical terminal rows that are
   not covered well by compact partial indexes;
4. race-resolution scoring that performs participant-specific step/sample
   queries, making full resolution approximately `O(participants)` in SQL calls
   and data volume;
5. repeated race and participant reads for fingerprinting, computation,
   fencing, mystery-box processing, and placement transitions;
6. per-recipient notification projection and per-outbox delivery transactions;
7. mutable queue rows that are updated repeatedly and indexed on frequently
   changing columns, producing MVCC churn and autovacuum work; and
8. recovery/reconciliation loops that scan historical tables for missing
   downstream rows.

The 250 ms pollers alone probably do not explain constant 90% CPU if all active
indexes are small and cached. However, the resolution poller appears capable of
issuing approximately 12 database statements per second while idle:

- two full-trigger promotion statements per tick;
- one race-resolution claim per tick;
- four ticks per second; and
- an operational-switch lookup approximately every two seconds.

Placement and post-task polling add roughly another eight claim transactions
per second. Other one-second workers add more. A plausible lower-bound idle
rate for the queues in scope is approximately **25–40 SQL statements per
second**, before HTTP traffic, telemetry, health checks, and general application
crons.

That rate is not automatically expensive on a healthy database. It becomes
expensive if those statements repeatedly scan large indexes containing mostly
terminal rows, filter future/not-yet-due rows, sort for `LIMIT 1`, update hot
queue tuples, or contend with autovacuum.

### Most important conclusion

The most likely explanation is not “PostgreSQL queues are always expensive.”
It is:

> A high-frequency PostgreSQL queue design is combined with insufficiently
> selective active-state indexes, repeated idle promotion/claim work,
> participant-linear scoring reads, hot-row update churn, and large retained
> terminal histories.

Production `pg_stat_statements`, table statistics, and query plans are required
to determine which component dominates the observed 90% CPU.

### Confidence labels

- **Confirmed:** established directly from repository code.
- **Strong suspicion:** code contains a credible mechanism, but production
  statistics are required to measure its impact.
- **Requires production evidence:** cannot be decided from static code.

## 2. Top likely causes of the 90% database CPU

### CRITICAL — Race-resolution polling promotes full triggers on every idle tick

**Confirmed.**

In `buildRaceResolutionWorkerV2.processOneUnbudgeted`, every untargeted
resolution attempt:

1. checks the operational switch;
2. calls `promoteFullScopeTriggers`; and
3. calls `claimNext`.

The worker runs every 250 ms. `promoteFullScopeTriggers` opens a transaction and
executes:

1. a candidate-race `INSERT ... ON CONFLICT DO NOTHING`; and
2. a multi-CTE promotion/update/delete statement.

This happens before the worker knows whether ordinary resolution work exists.

Relevant functions:

- backend `src/modules/races/jobs/raceResolutionQueueV2.js`:
  `processOneUnbudgeted`, `scheduleRaceResolutionWorkerV2`
- backend `src/modules/races/models/raceResolutionJobV2.js`:
  `promoteFullScopeTriggers`, `claimNext`

Estimated idle load from this worker alone:

- promotion: 2 statements × 4 ticks/s = 8 statements/s;
- claim: 1 statement × 4 ticks/s = 4 statements/s;
- operational-switch read: approximately 0.5 statements/s because enabled
  results are cached for two seconds;
- total: approximately **12.5 statements/s**, excluding transaction protocol
  and telemetry queries.

The code documents that the former uncached switch lookup would have caused
approximately 345,000 reads/day. The two-second cache fixed that particular
read, but the promotion statements still execute every tick.

This is the first query family to locate in `pg_stat_statements`.

### CRITICAL — Full race resolution is participant-linear

**Confirmed.**

A full race resolution does not have constant query cost. Participant scoring
runs concurrently, but each participant can execute several step/sample
queries:

- `sumStepsInWindow`;
- sometimes `findByUserIdAndDate`;
- subsequent-day step/sample aggregation;
- sometimes `hasAnyInWindow`;
- effect-related sample reads; and
- finish-timeline sample reads for finishing participants.

Relevant functions:

- backend `src/modules/races/services/raceStateResolution.js`:
  `calculateBaseAdjusted`, `calculateCurrentTotal`, `determineFinishSnapshot`,
  `resolveRaceState`
- backend `src/modules/races/jobs/raceResolutionQueueV2.js`:
  `processOneUnbudgeted`

`Promise.all` reduces wall-clock latency but does not reduce database work. It
can deliver many participant-specific queries to PostgreSQL simultaneously.

Approximate scoring-query scale:

| Race size | Conservative participant reads | Plausible total resolution statements |
|---:|---:|---:|
| 10 | 30–60 | 50–100 |
| 500 | 1,500–3,000 | 1,550–3,200+ |

Effects, finishing participants, mystery boxes, global events, and fallback
paths can raise these figures. A continuous stream of full-resolution
generations could sustain high CPU without an obvious large-race spike.

### HIGH — Race-resolution claim indexing does not fully match its query

**Confirmed mismatch; impact requires production evidence.**

The claim combines:

- queued rows constrained by `retry_at` and `not_before_at`;
- expired running rows constrained by `lease_expires_at`;
- expression-based priority ordering;
- `requested_at`;
- `race_id`; and
- `LIMIT 1`.

Existing indexes include:

- `(state, retry_at)`;
- `(lease_expires_at)`;
- `(state, not_before_at)`;
- `(state, queue_priority, requested_at)`; and
- `(requested_at)`.

No index exactly matches:

```sql
ORDER BY CASE queue_priority
  WHEN 'SETTLEMENT' THEN 0
  WHEN 'RECOVERY' THEN 1
  WHEN 'LIVE' THEN 2
  ELSE 3
END,
requested_at,
race_id
LIMIT 1
```

The textual `queue_priority` index cannot directly satisfy the custom `CASE`
order. The `OR` between queued and expired-running branches further complicates
index use. If the table retains one terminal row per historical race,
PostgreSQL may repeatedly traverse/filter a large general index to find a tiny
active subset.

### HIGH — Terminal queue rows and mutable indexed columns create MVCC pressure

**Strong suspicion.**

The race-resolution and placement tables are one-row-per-race state stores,
not ephemeral append-only queues. A hot race repeatedly updates:

- generation;
- state;
- requested/retry/debounce time;
- lease fields;
- processing JSON;
- completion fields; and
- `updated_at`.

Many of these fields are indexed. Updates therefore create new heap tuples and
new index entries rather than qualifying as HOT updates.

`race_resolution_jobs_v2` has no obvious regular cleanup of successful
historical race rows. This may be required for generation receipts or recovery,
but it makes active searches share tables and indexes with terminal history.
Placement rows similarly appear retained per race.

Credible consequences include:

- dead tuples;
- index bloat;
- frequent autovacuum;
- page churn on hot races; and
- reduced claim-index selectivity.

### HIGH — Notification delivery has per-outbox and per-device database work

**Confirmed.**

The notification system contains good set-based paths, but delivery still
claims and prepares each outbox row in its own transaction. One candidate can
execute:

1. conditional outbox lease update;
2. existing device-attempt lookup;
3. global-generation-state lookup;
4. active-device-token lookup;
5. one update per legacy/incomplete existing target;
6. `createMany` for missing target snapshots;
7. later delivery reads;
8. attempt-result updates;
9. outbox completion/retry update; and
10. possible push-delivery attribution updates.

Relevant function: backend
`src/modules/inbox/jobs/inboxDelivery.js`, `buildInboxDelivery`, especially its
candidate claim transaction and `deliverRow`.

The loop updating existing device attempts is an explicit per-target awaited
update.

### HIGH — Notification projection contains recipient-specific work

**Confirmed.**

Audience expansion is paged and projection insertion is set-based. General
projection processing remains per recipient:

1. claim projection;
2. load projection/event/audience context;
3. load recipient;
4. execute event-specific reads;
5. submit notification intent;
6. finish projection; and
7. test whether the parent event is terminal.

Relevant functions:

- backend `src/modules/domainEvents/services/notificationProjector.js`:
  `expandOne`, `processOne`, `run`
- backend `src/modules/domainEvents/models/domainEventOutbox.js`: claim and
  context functions
- backend `src/modules/notifications/services/domainEventV1Projection.js`:
  event-specific materialization

A 500-recipient event can create hundreds of individually claimed and
completed projection transactions even though audience expansion is batched.

### MEDIUM-HIGH — Global-summary work is polled every second while idle

**Confirmed.**

The v2 summary scheduler runs every second. An idle tick performs several
discovery and reconciliation phases:

- ended-entitlement candidate query;
- legacy-group candidate query;
- reconciliation query for unstamped work;
- active-work claim transaction; and
- a second reconciliation pass.

`claimActiveWork` also updates and reloads each claimed row separately.

Relevant functions: backend `src/modules/steps/jobs/globalEventSummary.js`:
`runV2`, `reconcileWorkRaceQueues`, `claimActiveWork`,
`scheduleGlobalEventSummaryTick`.

This likely contributes steady background load. It is more likely to explain
event-boundary spikes than constant 90% CPU unless discovery/reconciliation
indexes have degraded or work remains perpetually waiting.

### MEDIUM — Aggressive recovery jobs scan for absence

**Confirmed mechanism; impact requires production evidence.**

The notification completeness reconciler runs eight repair statements every
five minutes, then reruns immediately if any page is full. Several statements
use `NOT EXISTS` across large historical tables.

The global-event entitlement reconciler searches active entitlements lacking a
matching domain-event key.

Relevant functions:

- backend
  `src/modules/notifications/jobs/notificationCompletenessReconciler.js`:
  `reconcileNotificationCompleteness`
- backend
  `src/modules/steps/jobs/globalEventEntitlementEventReconciler.js`:
  `reconcileEntitlementEvents`

These normally create periodic waves. If they continually return full pages,
they can become continuous drain loops.

## 3. Polling analysis

Production role routing in backend `src/index.js` indicates:

- `resolution` owns race resolution, placement, post-tasks, impact boundaries,
  and race admin commands;
- `cron` owns notification, event, summary, cleanup, and scheduled work;
- HTTP processes should not claim durable resolution work; and
- local/default `all` mode can run both groups and would multiply pollers if
  accidentally used in production.

### Main pollers in scope

| Poller | File/function | Interval | Idle DB work | Polls idle? | Ownership/backlog behavior |
|---|---|---:|---:|---|---|
| Race resolution | `raceResolutionQueueV2.js` / `scheduleRaceResolutionWorkerV2` | 250 ms | Promotion transaction + claim + cached setting | Yes | Resolution process; adaptive drain can query continuously |
| Placement | `racePlacementTransitionWorker.js` / scheduler | 250 ms | One claim transaction | Yes | Resolution process; one job per tick |
| Post-tasks | `raceResolutionPostTaskRunner.js` / scheduler | 250 ms | Qualification recovery + claim; setting check | Yes | Resolution process; adaptive drain can query continuously |
| Resolved-impact boundary | `resolvedImpactBoundaryScheduler.js` | 1 s | One due-race query | Yes | Resolution process; enqueues batch when due |
| Domain projection | `domainEventProjection.js` / `notificationProjector.run` | 1 s | Several specialized/general claims | Yes | Cron; loops inside a five-second budget |
| Global summary v2 | `globalEventSummary.js` | 1 s | Discovery, reconciliation, claim | Yes | Cron; bounded batch/tick budget |
| Global-event boundary drain | `globalEventBoundaryDrain.js` | 1 s | Due-ID query | Yes | Cron; drains until idle, max 255 transaction attempts |
| Notification release | `notificationScheduleRelease.js` | 5 s fallback | Two release pipelines + next-due query | Yes | Cron; immediate continuation on full pages |
| Inbox delivery | `inboxDelivery.js` | 15 s fallback | Admission, expiry, candidate, next-due | Yes | Cron; Redis wake + timer + durable poll |
| Notification completeness | `notificationCompletenessReconciler.js` | 5 min | Eight repair statements | Yes | Cron; immediate rerun on full page |
| Domain retention | `domainEventRetention.js` | 5 min | Retention scan/delete | Yes | Cron; bounded cleanup |
| Inbox expiry | `inboxExpiry.js` | 5 min | Expiry cleanup | Yes | Cron; bounded cleanup |
| Entitlement-event repair | `globalEventEntitlementEventReconciler.js` | 60 s | Generation check + absence query | Yes | Cron; immediate rerun on full page |
| Global-event scheduler | `globalStepEventScheduler.js` | 60 s | Boundary/schedule queries | Yes | Cron; event fan-out at boundaries |
| Generation heartbeat | `globalStepEventGeneration.js` | 15 s | DB heartbeat | Yes | Runs in every process intentionally |

### Estimated poll-driven statement rates

These are architecture estimates, not measurements.

#### Completely idle

- Race resolution: approximately 12.5 statements/s.
- Placement: approximately 4/s.
- Post-task: at least approximately 4/s and potentially more because
  qualification recovery precedes every claim.
- Impact boundary: 1/s.
- Domain projection: plausibly 3–8/s depending on empty specialized paths.
- Global summaries: plausibly 4–8/s.
- Boundary drain: 1/s.
- Notification release/delivery amortized: roughly 1–3/s.
- Other reconciliation/maintenance work: below 1/s amortized unless draining.

A credible lower-bound total is **25–40 SQL statements/s while idle**.

#### Normal load

Resolution cost dominates. Ten small resolutions per minute at 50–100
statements each add roughly 8–17 statements/s. Notification events add several
statements per recipient. A plausible normal-load range is **50–200+
statements/s**, depending on active races and notifications.

#### Backlog drain

Adaptive resolution and post-task loops intentionally remove the 250 ms idle
gap. Domain projection loops for up to five seconds. Schedule release continues
immediately on full pages. Boundary drain loops until empty. During backlog
drain, there is effectively no polling ceiling: the limit becomes database
latency, configured work budgets, and worker concurrency. Hundreds or thousands
of statements/s are plausible for participant-heavy resolution or notification
fan-out.

### Redis wake-up behavior

**Confirmed:** Redis wake-ups supplement polling; they do not eliminate it.

- Schedule release still polls every five seconds.
- Inbox delivery still polls every 15 seconds.
- Both also use due timers.
- PostgreSQL is explicitly the durable recovery path.

Redis improves latency but does not remove the permanent polling floor.

## 4. Queue claim queries and index problems

Do not create these indexes without first checking exact production indexes,
sizes, plans, active/terminal row ratios, and write overhead.

### 4.1 Race-resolution claim

Candidate queued-work index:

```sql
CREATE INDEX CONCURRENTLY race_resolution_jobs_v2_queued_priority_order_idx
ON race_resolution_jobs_v2 (
  (CASE queue_priority
     WHEN 'SETTLEMENT' THEN 0
     WHEN 'RECOVERY' THEN 1
     WHEN 'LIVE' THEN 2
     ELSE 3
   END),
  requested_at,
  race_id
)
INCLUDE (id, retry_at, not_before_at)
WHERE state = 'queued';
```

This serves priority/order over active queued rows but still filters future
eligibility timestamps.

Candidate expired-lease index:

```sql
CREATE INDEX CONCURRENTLY race_resolution_jobs_v2_expired_running_idx
ON race_resolution_jobs_v2 (lease_expires_at, requested_at, race_id)
INCLUDE (id)
WHERE state = 'running' AND lease_expires_at IS NOT NULL;
```

The strongest query improvement would split queued and expired-running
selection so each branch can use its own partial index, then choose the proper
candidate while retaining priority and lease-recovery rules.

### 4.2 Full-trigger promotion

The append-only trigger table has useful indexes:

- `(requested_at, id)`;
- `(race_id, requested_at, id)`.

The concern is frequency, not an obvious missing index. Promotion also joins
the mutable resolution row and evaluates JSON array lengths and containment
every 250 ms. Confirm its call count and total time before changing it.

### 4.3 Placement claim

The current index starts with:

```text
(state, not_before_at, retry_at, requested_at, race_id)
```

The query orders by `requested_at, race_id`, joins resolution, and has
queued/retry versus expired-running `OR` branches. Candidate indexes:

```sql
CREATE INDEX CONCURRENTLY race_placement_due_order_idx
ON race_placement_transition_jobs (requested_at, race_id)
INCLUDE (
  id, requested_generation, completed_generation,
  not_before_at, retry_at
)
WHERE state IN ('queued', 'retry');

CREATE INDEX CONCURRENTLY race_placement_expired_running_idx
ON race_placement_transition_jobs (lease_expires_at, requested_at, race_id)
INCLUDE (id, requested_generation)
WHERE state = 'running' AND lease_expires_at IS NOT NULL;
```

Splitting the two claim branches would make these more directly usable.

### 4.4 Post-task claim

Existing `(state, not_before_at)` does not satisfy `ORDER BY requested_at`.

```sql
CREATE INDEX CONCURRENTLY race_resolution_post_tasks_due_order_idx
ON race_resolution_post_tasks (requested_at, id)
INCLUDE (not_before_at)
WHERE state = 'queued';

CREATE INDEX CONCURRENTLY race_resolution_post_tasks_expired_running_idx
ON race_resolution_post_tasks (lease_expires_at, requested_at, id)
WHERE state = 'running' AND lease_expires_at IS NOT NULL;
```

### 4.5 Domain events and projections

General indexes exist, along with an active aggregate-order partial index and a
specialized scheduled-entitlement partial index. General status indexes include
terminal history. Candidate compact indexes:

```sql
CREATE INDEX CONCURRENTLY domain_event_outbox_due_active_idx
ON domain_event_outbox (available_at, occurred_at, id)
INCLUDE (status, lease_until)
WHERE status IN ('PENDING', 'RETRY', 'EXPANDING');

CREATE INDEX CONCURRENTLY domain_event_projection_due_active_idx
ON domain_event_notification_projections (available_at, id)
INCLUDE (status, lease_until, domain_event_id)
WHERE status IN ('PENDING', 'RETRY');
```

The exact active status set must match the claim implementation.

### 4.6 Inbox delivery

Existing `(status, available_at, lease_until)` is not ideal for pending/retry
ordering, expired leases, and expiration sweeps.

```sql
CREATE INDEX CONCURRENTLY inbox_delivery_due_idx
ON inbox_delivery_outbox (available_at, id)
WHERE status IN ('PENDING', 'RETRY');

CREATE INDEX CONCURRENTLY inbox_delivery_expired_lease_idx
ON inbox_delivery_outbox (lease_until, id)
WHERE status = 'LEASED' AND lease_until IS NOT NULL;

CREATE INDEX CONCURRENTLY inbox_delivery_expiry_idx
ON inbox_delivery_outbox (expires_at, id)
WHERE expires_at IS NOT NULL
  AND status IN ('PENDING', 'RETRY', 'LEASED');
```

The expiration scan has no clearly matching `expires_at` index in the Prisma
schema.

### 4.7 Global-event summary work

Existing indexes are broad and include terminal history. Candidate:

```sql
CREATE INDEX CONCURRENTLY global_event_summary_active_due_idx
ON global_event_summary_work (available_at, id)
INCLUDE (status, lease_until, expires_at)
WHERE status IN ('WAITING_SYNC', 'QUEUED', 'PROCESSING', 'WAITING_RACES');
```

This matters most if terminal rows dominate the table.

## 5. Race-resolution query analysis

### Complexity

- claim/planning infrastructure: approximately `O(1)` statements;
- participant scoring: approximately `O(P)` statements;
- participant writes: `O(1)` statements with bulk writes or `O(P)` in fallback;
- box advisory locks: `O(B)`;
- side-effect writes: `O(E)`;
- some active-impact materialization: `O(sources)`;
- placement/post-task handoffs: nominally `O(1)` set-based statements plus
  intent inserts.

### Approximate phases for one full resolution

1. Kill-switch check, sometimes cached.
2. Full-trigger promotion, two statements.
3. Claim, one large CTE update.
4. App-setting reads for reason-aware, bulk-write, coalescing, and post-task
   behavior.
5. Input fingerprint, four concurrent SQL queries:
   - race plus participant JSON aggregate;
   - user input versions plus step/sample existence;
   - active and retained effects;
   - global-event/boundary-cursor state.
6. Closure planning reuses the fingerprint where possible; fallback can load
   race/effects again.
7. Race hydration for scoring.
8. Global-event eligibility query.
9. Per-participant scoring queries.
10. Source fingerprint/fence revalidation.
11. Final transaction:
    - queue-row ownership fence;
    - possible database-clock read;
    - box-candidate read;
    - one advisory-lock statement per due box participant;
    - participant-row lock query;
    - power-up inventory read;
    - participant bulk write or per-row writes;
    - side-effect writes;
    - box synchronization;
    - active-impact writes;
    - placement upsert;
    - post-task/intent insert; and
    - queue success/update.
12. After-commit cache/list work can perform more DB lookups.

### Confirmed N+1 patterns

- `calculateBaseAdjusted`: several reads per scored participant.
- finish snapshot: sample reads per finishing participant.
- mystery-box advisory lock: one statement per selected participant.
- non-bulk participant-write mode: one update per participant.
- effect/side-write loops: individual updates/inserts.
- some umbrella-impact loops: sample query per selected source.

### Estimated 10- versus 500-participant race

Assuming three to six scoring reads per unfrozen participant:

- 10 participants: 30–60 scoring queries;
- 500 participants: 1,500–3,000 scoring queries.

Including fixed work:

- 10-person full resolution: approximately 50–100 statements;
- 500-person full resolution: approximately 1,550–3,200+ statements.

The exact count depends on sample availability, race duration, active effects,
finishing participants, due boxes, bulk-write mode, and scoped versus full
resolution.

### Duplicate/repeated reads

#### Necessary for correctness

- final queue-row ownership fence;
- source fingerprint revalidation immediately before writes;
- locked participant recheck for mystery boxes;
- placement generation/fingerprint revalidation; and
- device ownership revalidation immediately before send.

These should not be removed.

#### Potentially avoidable while retaining correctness

- fingerprint participant aggregate followed by separate scoring hydration;
- placement canonical load outside its transaction followed by another inside
  the fenced transaction;
- placement loading the race/field that resolution just computed;
- notification projection loading event context for each recipient;
- parent-event terminal checks after every projection; and
- global summary repeatedly reading the complete impact vector while waiting.

Possible correctness-preserving techniques:

- compact immutable resolution result/fingerprint handoff to placement;
- keep fenced validation but compare a compact version/fingerprint before a
  second full hydration;
- batch participant step/sample aggregation by user and race window;
- claim/group projections by event and load event/audience facts once;
- durable final-impact counters under the existing summary-group lock.

## 6. Notification pipeline analysis

### Placement notification path

1. Placement compare-and-set updates the baseline.
2. It bulk-appends a domain event.
3. Event expansion loads audience pages of 100.
4. Classification runs in a recipient loop and can perform recipient-specific
   DB work.
5. Projection rows are persisted transactionally.
6. Projection claims use batches of 50 and concurrency four.
7. Each projection reloads context.
8. Each projection loads recipient state.
9. Typed materialization can load race/user/current notification state.
10. Notification submission creates or upserts a schedule.
11. Release creates inbox alert and outbox.
12. Delivery claims each outbox in its own transaction.
13. Delivery loads device targets and creates attempt snapshots.
14. Provider outcomes update attempts and outbox.

### Approximate per-recipient operations

For one visible notification and one device:

- one audience row;
- one projection row;
- approximately 2–5 projection reads;
- one projection terminal update;
- one schedule insert/upsert;
- one inbox row;
- one outbox row;
- one device-attempt row;
- approximately 2–5 delivery claim/preparation queries; and
- one to three outcome updates.

The order-of-magnitude estimate is **10–20 DB statements or mutations per
recipient**, depending on set-based fast paths and event type.

### Hidden per-recipient work

- `expandOne` awaits classification per audience member.
- `processOne` performs recipient/event reads per projection.
- Inbox claim preparation updates existing targets one by one.
- Some typed handlers load actor/user/race facts separately.
- Event terminalization is checked after recipient completion.

### Existing set-based strengths

- Audience expansion is paged.
- Projection insertion is batched.
- Scheduled entitlement projection has a 200-row set-based path.
- Provider attempt results use JSON/set-based updates.
- Missing device attempts use `createMany`.
- Placement/silent events have specialized batch SQL paths.

The architecture already recognizes fan-out; remaining general per-recipient
paths are the production-statistics focus.

## 7. Write amplification

These are ranges for a full resolution caused by one sync, with broad placement
movement. They are not exact production counts.

| Stage | 5-person race | 50-person race | 500-person race |
|---|---:|---:|---:|
| Step/input/version writes | 2–5 | 2–5 | 2–5 |
| Resolution queue updates | 2–4 | 2–4 | 2–4 |
| Resolution participant reads | 15–30 | 150–300 | 1,500–3,000 |
| Participant total rows written | 5 | 50 | 500 |
| Placement handoff | 1 | 1 | 1 |
| Placement canonical rows read | ~6 | ~51 | ~501 |
| Placement baseline writes, worst case | 5 | 50 | 500 |
| Event/audience/projection rows, worst case | 5–15 | 50–150 | 500–1,500 |
| Schedule/inbox/outbox rows | up to 3/recipient | same | same |
| Device attempts | devices/recipient | same | same |

A small step update can cause one hot queue-row update, a full participant read,
one write per participant, placement re-reading the field, baseline/event work
per changed participant, and several notification rows per recipient.

For a 500-person race with broad placement movement, downstream row writes can
reach several thousand. Compare-and-set and suppression should reduce visible
events in common cases, but scoring reads and total writes can still cover the
full field.

## 8. MVCC, autovacuum, and bloat concerns

### Highest-risk tables

#### `race_resolution_jobs_v2`

Generation, state, lease, JSON scopes, timestamps, and priority change
repeatedly. Many are indexed. High dead-tuple/index-churn risk. Terminal rows
appear retained.

#### `race_placement_transition_jobs`

One mutable row per race, changed on generation, claim, retry, supersession,
and completion. Terminal rows appear retained.

#### `domain_event_outbox`

Rows transition through pending, expansion/projection, retry, and terminal
states. Cursor and lease fields change. Retention exists, but production age
and effectiveness need verification.

#### `domain_event_notification_projections`

Every projection is inserted, leased, retried, and completed. Large fan-outs
produce many rows. Terminal history remains until parent-event retention.

#### `notification_schedules`

Rows transition through pending/admission/materialized/canceled/expired states.
Unique/status indexes amplify writes. No general retention path was evident in
the inspected queue path.

#### `inbox_delivery_outbox`

Claim, lease renewal, provider acceptance, retry, and completion update the
row. Status/availability/lease fields are indexed.

#### `inbox_delivery_device_attempts`

Retries update disposition, attempt count, next attempt, provider response, and
timestamps. Several mutable fields are indexed.

#### `global_event_summary_work`

Waiting claims update lease and `attempt_count`. `WAITING_RACES` work can churn
once per second until every impact finalizes.

### Post-task retention

Post-tasks have explicit cleanup:

- every ten minutes;
- terminal tasks older than seven days;
- pages of 500; and
- bounded maximum pages.

Child intents cascade-delete with parent tasks.

### Autovacuum hypothesis

Autovacuum could be a major CPU consumer if queue tables have low effective
thresholds relative to their update rates, large JSON rows are rewritten,
indexes contain obsolete entries, terminal rows make tables large, long
transactions prevent cleanup, or cleanup deletes large batches.

This requires `pg_stat_user_tables`, `pg_stat_progress_vacuum`, table/index
sizes, and transaction-age evidence.

## 9. Specific suspicious code

1. `raceResolutionQueueV2.js` / `processOneUnbudgeted` calls
   `promoteFullScopeTriggers` every 250 ms.
2. `raceStateResolution.js` / `resolveRaceState`, `calculateBaseAdjusted`, and
   `calculateCurrentTotal` execute participant-specific queries in
   `Promise.all`.
3. `raceResolutionQueueV2.js` final transaction executes one advisory-lock SQL
   statement per selected mystery-box participant.
4. The same final transaction falls back to one participant update per write
   when bulk mode is disabled.
5. `racePlacementTransitionWorker.js` / `processOne` loads canonical context
   before and again inside its fenced transaction.
6. `raceResolutionPostTaskRunner.js` / `tick` calls
   `recoverQualificationIntents` before every claim.
7. `globalEventSummary.js` / `claimActiveWork` updates and then `findUnique`s
   every claimed candidate.
8. `globalEventSummary.js` / `runV2` calls `globalStepEvent.findUnique` inside
   the legacy-group loop.
9. `inboxDelivery.js` claim preparation updates existing device targets in an
   awaited per-target loop.
10. `notificationCompletenessReconciler.js` runs eight historical repair
    statements every five minutes and immediately repeats full pages.
11. `globalEventSummary.js` / `runV2` performs discovery and reconciliation
    every second.
12. General queue status indexes in `prisma/schema.prisma` include terminal
    history rather than being partial active-state indexes.

## 10. Recommended optimizations, ordered by likely impact

These are recommendations for engineering review, not authorized changes.

1. Measure and then remove full-trigger promotion from every idle 250 ms tick.
   Preserve durability with a lower-frequency promoter, cheap indexed existence
   gate, or wake plus fallback poll. PostgreSQL remains authoritative.
2. Batch participant step/sample computation with race-scoped queries grouped
   by user/window. Preserve exact scoring inputs and fingerprints.
3. Add purpose-built partial active-state claim indexes after confirming plans.
   Prioritize resolution, post-tasks, inbox expiry/claims, placement, domain
   projections, and summaries.
4. Split queued and expired-lease claim branches so each can use an appropriate
   partial index while retaining priority and `SKIP LOCKED` recovery.
5. Audit terminal-row retention and bloat. Do not delete rows required by
   frozen-client polling or recovery; define the retention contract first.
6. Hand compact committed resolution output to placement. Keep generation and
   fingerprint fencing but avoid fully hydrating the same field twice.
7. Batch notification projection by event: load event/audience context once,
   bulk-load recipient facts, and batch terminal outcomes.
8. Replace per-target device repair updates with a set-based JSON/CTE update.
9. Reduce `WAITING_RACES` churn through durable pending/final counters or
   transition wake-up plus a slower recovery poll.
10. Tune per-table autovacuum only after observing update/dead-tuple rates;
    premature tuning can raise CPU.

## 11. Safe diagnostic SQL for production

All statements below are read-only. `pg_stat_statements` must already be
installed. Do not enable or reset it as part of this investigation.

### Top statements by total execution time

```sql
SELECT queryid, calls,
  round(total_exec_time::numeric, 2) AS total_exec_ms,
  round(mean_exec_time::numeric, 3) AS mean_exec_ms,
  round(min_exec_time::numeric, 3) AS min_exec_ms,
  round(max_exec_time::numeric, 3) AS max_exec_ms,
  rows, shared_blks_hit, shared_blks_read, shared_blks_dirtied,
  shared_blks_written, temp_blks_read, temp_blks_written,
  blk_read_time, blk_write_time, wal_records, wal_fpi, wal_bytes,
  left(regexp_replace(query, '\s+', ' ', 'g'), 1000) AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname=current_database())
ORDER BY total_exec_time DESC
LIMIT 50;
```

### Top statements by call count

```sql
SELECT p.queryid, p.calls,
  round((p.calls / GREATEST(EXTRACT(EPOCH FROM now()-d.stats_reset),1))::numeric,3)
    AS calls_per_second_since_reset,
  round(p.total_exec_time::numeric,2) AS total_exec_ms,
  round(p.mean_exec_time::numeric,3) AS mean_exec_ms,
  p.rows, p.shared_blks_hit, p.shared_blks_read,
  p.shared_blks_dirtied, p.wal_bytes,
  left(regexp_replace(p.query, '\s+', ' ', 'g'),1000) AS query
FROM pg_stat_statements p
JOIN pg_stat_database d ON d.datid=p.dbid
WHERE d.datname=current_database()
ORDER BY p.calls DESC
LIMIT 50;
```

### Top statements by mean execution time

```sql
SELECT queryid, calls,
  round(total_exec_time::numeric,2) AS total_exec_ms,
  round(mean_exec_time::numeric,3) AS mean_exec_ms,
  round(max_exec_time::numeric,3) AS max_exec_ms,
  rows, shared_blks_hit, shared_blks_read, temp_blks_read, temp_blks_written,
  left(regexp_replace(query, '\s+', ' ', 'g'),1000) AS query
FROM pg_stat_statements
WHERE calls >= 20
  AND dbid=(SELECT oid FROM pg_database WHERE datname=current_database())
ORDER BY mean_exec_time DESC
LIMIT 50;
```

### Queue-related statements

```sql
SELECT queryid, calls,
  round(total_exec_time::numeric,2) AS total_exec_ms,
  round(mean_exec_time::numeric,3) AS mean_exec_ms,
  rows, shared_blks_hit, shared_blks_read, shared_blks_dirtied, wal_bytes,
  left(regexp_replace(query, '\s+', ' ', 'g'),1500) AS query
FROM pg_stat_statements
WHERE query ~* ('race_resolution|race_placement_transition|' ||
  'race_resolution_post_task|race_resolution_full_trigger|domain_event_|' ||
  'notification_schedule|inbox_delivery|global_event_summary')
ORDER BY total_exec_time DESC
LIMIT 100;
```

### Current active queries

```sql
SELECT pid, usename, application_name, client_addr, state,
  wait_event_type, wait_event,
  now()-query_start AS query_age,
  now()-xact_start AS transaction_age,
  backend_xid, backend_xmin,
  left(regexp_replace(query, '\s+', ' ', 'g'),1200) AS query
FROM pg_stat_activity
WHERE datname=current_database() AND pid<>pg_backend_pid()
ORDER BY query_start NULLS LAST;
```

### Table sizes, writes, and dead tuples

```sql
SELECT schemaname, relname,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
  pg_size_pretty(pg_relation_size(relid)) AS heap_size,
  pg_size_pretty(pg_indexes_size(relid)) AS index_size,
  n_live_tup, n_dead_tup,
  round(100.0*n_dead_tup/GREATEST(n_live_tup+n_dead_tup,1),2) AS dead_pct,
  n_tup_ins, n_tup_upd, n_tup_hot_upd, n_tup_del,
  autovacuum_count, autoanalyze_count, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

### Queue-table statistics

```sql
SELECT relname, n_live_tup, n_dead_tup,
  n_tup_ins, n_tup_upd, n_tup_hot_upd, n_tup_del,
  seq_scan, seq_tup_read, idx_scan, idx_tup_fetch,
  autovacuum_count, last_autovacuum
FROM pg_stat_user_tables
WHERE relname IN (
  'race_resolution_jobs_v2','race_resolution_full_triggers',
  'race_placement_transition_jobs','race_resolution_post_tasks',
  'race_resolution_delivery_intents','domain_event_outbox',
  'domain_event_notification_projections','notification_schedules',
  'inbox_delivery_outbox','inbox_delivery_device_attempts',
  'global_event_summary_work','global_event_race_impacts'
)
ORDER BY relname;
```

### Queue counts, age, and terminal-history ratio

```sql
SELECT 'race_resolution_jobs_v2' AS queue, state::text, count(*) AS rows,
  min(requested_at) AS oldest, now()-min(requested_at) AS oldest_age
FROM race_resolution_jobs_v2 GROUP BY state
UNION ALL
SELECT 'race_placement_transition_jobs', state::text, count(*),
  min(requested_at), now()-min(requested_at)
FROM race_placement_transition_jobs GROUP BY state
UNION ALL
SELECT 'race_resolution_post_tasks', state, count(*),
  min(requested_at), now()-min(requested_at)
FROM race_resolution_post_tasks GROUP BY state
UNION ALL
SELECT 'domain_event_outbox', status, count(*),
  min(available_at), now()-min(available_at)
FROM domain_event_outbox GROUP BY status
UNION ALL
SELECT 'domain_event_notification_projections', status, count(*),
  min(available_at), now()-min(available_at)
FROM domain_event_notification_projections GROUP BY status
UNION ALL
SELECT 'notification_schedules', status, count(*),
  min(available_at), now()-min(available_at)
FROM notification_schedules GROUP BY status
UNION ALL
SELECT 'inbox_delivery_outbox', status, count(*),
  min(available_at), now()-min(available_at)
FROM inbox_delivery_outbox GROUP BY status
UNION ALL
SELECT 'global_event_summary_work', status, count(*),
  min(available_at), now()-min(available_at)
FROM global_event_summary_work GROUP BY status
ORDER BY queue, state;
```

### Index definitions, size, and usage

```sql
SELECT s.schemaname, s.relname AS table_name,
  s.indexrelname AS index_name,
  pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size,
  s.idx_scan, s.idx_tup_read, s.idx_tup_fetch,
  pg_get_indexdef(s.indexrelid) AS definition
FROM pg_stat_user_indexes s
WHERE s.relname ~ ('race_resolution|race_placement|domain_event|' ||
  'notification_schedule|inbox_delivery|global_event_summary')
ORDER BY pg_relation_size(s.indexrelid) DESC;
```

### Sequential versus index scans

```sql
SELECT relname, seq_scan, seq_tup_read, idx_scan, idx_tup_fetch,
  CASE WHEN seq_scan+idx_scan=0 THEN NULL
       ELSE round(100.0*seq_scan/(seq_scan+idx_scan),2) END AS seq_scan_pct
FROM pg_stat_user_tables
ORDER BY seq_tup_read DESC
LIMIT 50;
```

### Database cache hit rate and temporary I/O

```sql
SELECT datname, blks_read, blks_hit,
  round(100.0*blks_hit/GREATEST(blks_hit+blks_read,1),3)
    AS buffer_cache_hit_pct,
  temp_files, pg_size_pretty(temp_bytes) AS temp_bytes
FROM pg_stat_database
WHERE datname=current_database();
```

### Active autovacuum

```sql
SELECT p.pid, p.datname, p.relid::regclass AS table_name, p.phase,
  p.heap_blks_total, p.heap_blks_scanned, p.heap_blks_vacuumed,
  p.index_vacuum_count, p.num_dead_tuples, p.max_dead_tuples,
  a.query_start, now()-a.query_start AS elapsed
FROM pg_stat_progress_vacuum p
LEFT JOIN pg_stat_activity a USING (pid);
```

### Locks and blockers

```sql
SELECT blocked.pid AS blocked_pid,
  now()-blocked.query_start AS blocked_for,
  blocked.wait_event_type, blocked.wait_event,
  blocker.pid AS blocker_pid,
  now()-blocker.query_start AS blocker_query_age,
  left(blocked.query,800) AS blocked_query,
  left(blocker.query,800) AS blocker_query
FROM pg_stat_activity blocked
JOIN pg_locks bl ON bl.pid=blocked.pid AND NOT bl.granted
JOIN pg_locks kl ON kl.locktype=bl.locktype
 AND kl.database IS NOT DISTINCT FROM bl.database
 AND kl.relation IS NOT DISTINCT FROM bl.relation
 AND kl.page IS NOT DISTINCT FROM bl.page
 AND kl.tuple IS NOT DISTINCT FROM bl.tuple
 AND kl.virtualxid IS NOT DISTINCT FROM bl.virtualxid
 AND kl.transactionid IS NOT DISTINCT FROM bl.transactionid
 AND kl.classid IS NOT DISTINCT FROM bl.classid
 AND kl.objid IS NOT DISTINCT FROM bl.objid
 AND kl.objsubid IS NOT DISTINCT FROM bl.objsubid
 AND kl.pid<>bl.pid AND kl.granted
JOIN pg_stat_activity blocker ON blocker.pid=kl.pid
ORDER BY blocked_for DESC;
```

### Long transactions

```sql
SELECT pid, usename, application_name, state,
  now()-xact_start AS transaction_age,
  now()-query_start AS query_age,
  wait_event_type, wait_event, backend_xmin,
  left(regexp_replace(query, '\s+', ' ', 'g'),1000) AS query
FROM pg_stat_activity
WHERE datname=current_database() AND xact_start IS NOT NULL
ORDER BY xact_start;
```

### Database connections

```sql
SELECT application_name, usename, state, wait_event_type,
  count(*) AS connections
FROM pg_stat_activity
WHERE datname=current_database()
GROUP BY application_name, usename, state, wait_event_type
ORDER BY connections DESC;
```

### Exact production queue indexes

```sql
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname='public'
  AND tablename IN (
    'race_resolution_jobs_v2','race_resolution_full_triggers',
    'race_placement_transition_jobs','race_resolution_post_tasks',
    'domain_event_outbox','domain_event_notification_projections',
    'notification_schedules','inbox_delivery_outbox',
    'inbox_delivery_device_attempts','global_event_summary_work'
  )
ORDER BY tablename,indexname;
```

Do not run `EXPLAIN ANALYZE` on mutating queue claim statements in production.
Use plain `EXPLAIN (COSTS, VERBOSE)` on a safely rewritten candidate `SELECT`,
or reproduce `EXPLAIN (ANALYZE, BUFFERS)` on a production-like snapshot.

## 12. Production information still needed

1. PostgreSQL version and instance CPU/memory/storage class.
2. All three `pg_stat_statements` reports.
3. The statistics reset timestamp.
4. Queue-table live/dead tuples, sizes, update counts, and vacuum history.
5. Exact production indexes, because migrations may not reflect drift.
6. Queue counts grouped by status.
7. Whether `STEPS_PROCESS_ROLE` is correct on every process.
8. Actual count of resolution, cron, and HTTP processes.
9. Whether adaptive resolution and post-task drain are enabled.
10. Whether reason-aware/scoped resolution and bulk participant writes are
    enabled.
11. Full-versus-scoped resolution rates from worker logs.
12. Average and p95 active participant count per resolved race.
13. Autovacuum activity during the 90% periods.
14. CPU timeline correlated with step syncs, resolution completions,
    global-event boundaries, notification fan-out, and cleanup runs.
15. Query plans for the top five queue statements by total time.
16. Buffer-cache hit rate, temporary files, and storage I/O latency.
17. Long-transaction and lock-blocker snapshots.
18. Whether terminal schedules, outboxes, projections, and race queue rows grow
    without bound.

The first artifact to collect is `pg_stat_statements`. It will quickly
distinguish frequent cheap polling from expensive participant scoring, claim
scans/sorts, autovacuum/bloat, notification fan-out, or unrelated queries.

## 13. Backend source map

- `src/index.js`
- `src/modules/races/services/enqueueRaceResolution.js`
- `src/modules/races/models/raceResolutionJobV2.js`
- `src/modules/races/jobs/raceResolutionQueueV2.js`
- `src/modules/races/services/raceStateResolution.js`
- `src/modules/races/services/raceResolutionInputFingerprint.js`
- `src/modules/races/services/raceScoringDependencyClosure.js`
- `src/modules/races/models/racePlacementTransitionJob.js`
- `src/modules/races/models/racePlacementBaseline.js`
- `src/modules/races/jobs/racePlacementTransitionWorker.js`
- `src/modules/races/models/raceResolutionPostTask.js`
- `src/modules/races/jobs/raceResolutionPostTaskRunner.js`
- `src/modules/races/jobs/resolvedImpactBoundaryScheduler.js`
- `src/modules/domainEvents/models/domainEventOutbox.js`
- `src/modules/domainEvents/services/notificationProjector.js`
- `src/modules/domainEvents/jobs/domainEventProjection.js`
- `src/modules/notifications/services/domainEventV1Projection.js`
- `src/modules/notifications/services/notificationDelivery.js`
- `src/modules/notifications/services/notificationAdmission.js`
- `src/modules/notifications/jobs/notificationScheduleRelease.js`
- `src/modules/notifications/jobs/notificationCompletenessReconciler.js`
- `src/modules/inbox/jobs/inboxDelivery.js`
- `src/modules/steps/jobs/globalEventSummary.js`
- `src/modules/steps/jobs/globalEventBoundaryDrain.js`
- `src/modules/steps/jobs/globalEventEntitlementEventReconciler.js`
- `src/modules/steps/jobs/globalStepEventScheduler.js`
- `prisma/schema.prisma`
- relevant files under `prisma/migrations/`

