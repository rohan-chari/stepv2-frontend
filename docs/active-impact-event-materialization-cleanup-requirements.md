# Active-impact event materialization cleanup

## Status

Approved and implemented after product interview, two gap passes, architecture
approval, UI-placement review, and post-implementation review. Production
deployment is approved. The retired v1 flag
`apiActiveImpactNoticesV1Enabled` remains tombstoned off.

This document supersedes the active-impact materialization, work-queue, and
delivery portions of `active-race-impact-notifications-requirements.md`. It does
not change that document's separate 2x event-summary requirements.

## Problem

The shipped v1 implementation makes an optional popup part of the hot race
scoring path. With the flag enabled, ordinary race resolutions can:

- load and inspect historical powerup events for the race;
- load expired effects, participants, and all existing impact work;
- recompute counterfactual attribution across many effects;
- query step windows for defense candidates; and
- create/process presentation work inside the authoritative C0 transaction.

Most resolutions produce no notice, so this work scales with race history and
effect history rather than with the number of impacts actually resolving. On
2026-08-19 it materially increased resolution latency, queue lag, memory
pressure, and contributed to the production outage.

The intended product is simpler: an impact is calculated once when the domain
effect resolves, saved as one immutable recipient-private Activity event, and
the popup reads that same event. Popup delivery must never cause scoring or
attribution work.

## User story

When a score-changing powerup resolves while a race is active, each affected
runner gets one private Activity event describing their signed synced-step
impact. On the next eligible open or foreground resume, that same event may be
shown once as a popup. Dismissing the popup records delivery; it does not alter
the Activity event.

## Product behavior

1. The existing centered impact popup, eligibility rules, three-per-open cap,
   active-race-only behavior, and open/foreground timing remain unchanged.
2. The popup copy is the exact server-authored `description` of the associated
   private Activity event. The popup does not independently reconstruct copy
   from `powerupType` and `deltaSteps` in the carrying app version.
3. The private event is durably available as soon as it is committed and is
   rendered on the next defined private-Activity refresh: initial open, genuine
   foreground resume, explicit pull-to-refresh, a local committed powerup
   result, or popup delivery. It remains visible after popup acknowledgement
   while the race is active.
4. A completed race never shows an active-impact popup. Its Activity continues
   to use authoritative settlement impacts, which may differ from an earlier
   synced snapshot after late device uploads.
5. A zero, blocked, voided, or otherwise non-impacting outcome creates no
   private impact event.
6. Immediate caster-side outcome UI remains unchanged. If it already displays
   the exact same impact, dismissing that UI acknowledges popup delivery for
   the actor's event only; the Activity event remains visible.
7. This cleanup does not change powerup math, effect ordering, multipliers,
   transfers, floors, race totals, or settlement attribution.

## Scope

- Replace v1 active-impact work discovery and materialization with write-once
  resolved events.
- Make the private Activity stream and popup read the same canonical event.
- Preserve the existing app-facing routes and defensive downgrade behavior.
- Remove all active-impact historical scans and counterfactual attribution from
  ordinary race resolutions.
- Retire the v1 work pipeline, maintenance job, rollout-fence stamping, metadata
  markers, metrics, tests, and configuration that exist only for that pipeline.
- Safely handle v1 rows already present in production without resurrecting old
  notifications.

## Non-goals

- Any scoring, odds, price, reward, duration, or target-rule change.
- Changing popup placement, artwork, modal style, or delivery timing.
- Making recipient-private amounts visible in the shared race feed.
- Backfilling effects that resolved before the v2 cutover.
- Combining active synced snapshots with completed authoritative settlement
  rows.
- Deploying, enabling a flag, or mutating production data as part of planning.

## Canonical data model

Add `race_impact_events`, a recipient-private, immutable event table.

| field | rule |
|---|---|
| `id` | opaque UUID primary key |
| `raceId`, `recipientUserId` | private ownership and authorization scope |
| `sourceKind`, `sourceId` | stable domain source (`POWERUP_EVENT`, `ACTIVE_EFFECT`, or explicit consequence event) |
| `sourceFeedEventId` | nullable shared Activity row replaced by this recipient's private projection |
| `powerupType` | server-owned canonical type |
| `deltaSteps` | nonzero signed integer synced snapshot |
| `description` | immutable server-authored popup/Activity copy |
| `valueStatus` | `SYNCED_SNAPSHOT` for this version |
| `calculationVersion` | starts at 2; isolates the replacement from v1 rows |
| `resolvedAt` | domain resolution timestamp |
| `popupAcknowledgedAt` | nullable delivery state; does not hide Activity |
| `createdAt` | normal audit timestamp |

Constraints and indexes:

- unique `(raceId, recipientUserId, sourceKind, sourceId,
  calculationVersion)` is the retry/idempotency fence;
- index `(raceId, recipientUserId, popupAcknowledgedAt, resolvedAt, id)` backs
  popup reads; use a partial `popupAcknowledgedAt IS NULL` index in the raw
  migration if compatible with the migration/tooling contract;
- index `(raceId, recipientUserId, resolvedAt, id)` backs private Activity;
- nullable `sourceFeedEventId` references `race_powerup_events`; it is the
  deterministic direct-row dedup key, not a client-authored value;
- race and recipient delete cascades match other presentation-only data;
- there is no mutable status, pending work row, generation handoff, Redis
  state, or separate receipt row.

`race_powerup_events` remains the shared race Activity/audit stream. It must not
contain recipient-private signed amounts unless those amounts are already
public under the existing feed contract. `race_impact_events` is the private
stream merged into Activity only for its recipient.

## Write paths

### Direct and consequence effects

When an existing authoritative command already knows the committed signed
delta (for example Protein Shake, Red Card, Shortcut, Pinecone Toss, Trail Mix,
Mystery Potion direct rolls, Trail Mine detonation, or failed Drill Sergeant),
it inserts the private event in the same transaction as the score consequence
and source event.

- The server derives the amount; no client amount is accepted.
- Multi-recipient effects insert one event per affected recipient.
- Conflict-do-nothing on the natural unique key makes retries idempotent.
- The command returns the actor's own event ID as the existing optional
  `activeImpactReceipt.id` only when its immediate UI shows the same result.
- The existing receipt-ack endpoint remains as a compatibility alias that
  stamps `popupAcknowledgedAt` on that actor-owned event.

This requires a concrete command refactor rather than wrapping only the new
insert. `usePowerup.js` and the consequence commands receive a Prisma client
and execute one transaction that:

1. acquires participant locks in ascending `userId` order for every affected
   recipient;
2. revalidates race state, ownership, inventory, target eligibility, and the
   v2 feature fence inside the transaction;
3. conditionally changes the powerup from available to `USED` so a concurrent
   request cannot consume it twice;
4. applies participant bonus/penalty/transfer writes;
5. inserts the shared feed event and recipient-private impact event(s); and
6. commits before returning the result/receipt.

Models used by this path must be tx-aware and must not open nested independent
transactions. Cache invalidation, event-bus publication, push work, and race
resolution enqueue run only after commit from captured outputs. A failed
transaction consumes no powerup and exposes no partial score/feed/impact state.

### Timed effects

Timed modifiers are materialized only when their scoring window actually
resolves: natural expiry, a true early clamp/replacement, participant
finish/forfeit freeze, or another existing authoritative boundary.

The normal scoring calculation must expose an additive per-effect contribution
capture while it is already applying effects. The capture is presentation
output only and cannot alter totals. At the C0 commit boundary:

1. select only effect sources resolving in this generation, using the effect
   IDs already in the resolution input/capture;
2. take each recipient's signed contribution from that same scoring result;
3. insert the immutable private event and commit the effect's resolved state in
   the same transaction; and
4. rely on the unique key for retry safety.

The resolver must not discover candidates by scanning historical feed events,
all expired effects, all participants' prior work, or prior impact rows. It
must not run the settlement attribution vector on an ordinary active
resolution. If exact contribution cannot be obtained from the already-running
score pass for a particular nonlinear effect, a bounded counterfactual may run
only for the concrete effect IDs resolving in that generation, never for all
historical effects.

The v2 timed attribution algorithm is locked as follows:

1. select due, unresolved `RaceActiveEffect` source IDs with an indexed
   `(raceId,status,expiresAt,id)` query, ordered by `(expiresAt,id)`; add the
   corresponding raw Postgres index because the current schema does not cover
   the complete predicate/order;
2. on nonterminal resolution ticks, process at most eight source IDs in one
   generation and immediately enqueue a continuation when more remain;
   unprocessed rows retain their current domain status and the scorer continues
   clipping their contribution at `expiresAt`. Finish/forfeit is the explicit
   exception: because the freeze is irreversible, lock and capture every source
   resolving for that participant, compute the complete deterministic marginal
   vector in one scorer evaluation, allocate once across the full vector, and
   atomically commit every event with the freeze—never defer a ninth source;
3. load only the selected sources, their affected recipients, and scoring
   effects whose windows/order are required for those recipients' canonical
   prefixes—never feed events or prior notification rows;
4. instrument the canonical scorer/counterfactual closure to emit the complete
   loaded prefix's **raw, pre-integer marginal terms** in canonical
   chronological order. Do not subtract independently rounded prefix totals;
   that gives different ownership for fractional sequences such as
   `[0.4,0.4,0.4]`;
5. run `allocateIntegerTerms` once across that complete raw vector against the
   canonical integer target, then extract the selected due source entries.
   Allocation truncates toward zero and assigns remaining whole steps by
   fractional magnitude and stable source key exactly as settlement does;
   overlapping-window merge, multiplier order, Leech/Hitchhike transfers, and
   floors remain inside the canonical scorer. Shared prefixes and an
   instrumented single pass may be reused; and
6. perform no more than `2 * selectedSourceCount + 1` canonical scorer calls
   (maximum 17) in one generation. A parity fixture must compare v2 values with
   the same sources' entries from the existing full chronological attribution
   vector across every eligible type and overlap/floor case before v1 is
   deleted.

This is bounded work at a real resolution boundary. A generation with zero due
sources performs none of these loads or scorer calls.

Leech and Hitchhike use the transfer/copy artifacts the scorer already
produces. Defense resolution must emit its concrete avoided-loss delta at the
point the defense is consumed/resolved; it must not rediscover defense windows
from old `race_powerup_events` rows. Overlapping modifiers retain the existing
canonical attribution order and settlement parity.

Umbrella interception is not numerically resolved at Rainstorm cast time
because its avoided loss depends on future synced samples. Replace the hidden
feed-event JSON intent with `race_umbrella_interceptions`, an indexed durable
domain table:

| field | rule |
|---|---|
| `id` | UUID primary key and impact `sourceId` |
| `raceId`, `recipientUserId` | owning race and protected runner |
| `umbrellaEffectId`, `rainstormPowerupId` | stable causal sources |
| `windowStart`, `resolvesAt`, `avoidedMultiplier` | server-owned scoring window |
| `status` | `PENDING` or `RESOLVED` |
| `resolvedAt` | nullable C0 completion timestamp |
| timestamps | normal audit timestamps |

Unique `(rainstormPowerupId,recipientUserId)` prevents duplicate interceptions;
index `(raceId,status,resolvesAt,id)` selects due rows. Cast writes the
interception in the same transaction as Rainstorm use. At storm-window end C0
calculates only that source from closed samples, inserts the private event, and
marks it `RESOLVED` atomically. Race/user deletion cascades it; terminal race
transition suppresses delivery by status/read policy without inventing a
numeric result. Ordinary resolutions do not inspect historical feed rows.

Umbrella v2 uses the existing avoided-loss policy exactly: obtain closed synced
steps `walked` for `[windowStart,resolvesAt]`, compute
`walked - round(walked * avoidedMultiplier)`, and create no event when the
integer result is zero.

Today natural expiry can still occur after the C0 commit through
`raceProgressSideEffects`/`expireEffects`, including a request-path fallback
when the Redis standings path is disabled. Before v2 can be enabled, all
eligible active-impact expiry transitions and their event captures must move
into the C0 write capture for every configuration. The post-commit helper may
retain unrelated best-effort side effects, but it cannot own an effect boundary
that requires an atomic v2 event.

### Failure behavior

The private event is part of the same database transaction as its domain
resolution. A database failure rolls back both, leaving the source eligible for
the existing domain retry. There is no post-commit presentation job to lose or
replay. Optional cache invalidation and push publication happen after commit
and cannot roll back the event.

## Read and acknowledgement contracts

### Existing active popup routes

Keep these routes and their current authentication/capability gates so shipped
clients continue working:

- `GET /races/:raceId/active-impact-notices`
- `POST /races/:raceId/active-impact-notices/:noticeId/acknowledge`
- `POST /races/:raceId/active-impact-receipts/:receiptId/acknowledge`

The GET becomes a single indexed read of unacknowledged v2 events for the
authenticated accepted participant while the race is `ACTIVE`. It always
returns `200`; the v1 `202 resolution.state=PENDING` response is retired because
reads never trigger calculation. Existing clients already support the `200`
shape.

Each notice keeps all current fields and additively includes `description`:

```json
{
  "id": "impact:impact_event_opaque",
  "powerupType": "LEECH",
  "deltaSteps": -426,
  "description": "Leech drained 426 synced steps.",
  "sourceFeedEventId": "shared_event_opaque_or_null",
  "impactScope": "ACTIVE_SYNCED_SNAPSHOT",
  "valueStatus": "SYNCED_SNAPSHOT",
  "resolvedAt": "2026-08-19T16:30:00.000Z"
}
```

The notice acknowledgement is recipient/race-bound and idempotently stamps
`popupAcknowledgedAt`. Terminal races return the current terminal behavior.
The receipt endpoint performs the same mutation but only for an event whose
recipient is the authenticated actor represented by the powerup-use response.
Foreign and missing IDs remain nondisclosing.

Exact behavior for the v2 popup routes:

- missing `resolved_impact_events_v2`: `404 FEATURE_DISABLED`;
- unknown race: `404 NOT_FOUND`;
- known race but caller is not an accepted participant, including a tournament
  spectator: `403 FORBIDDEN` with no event existence signal;
- accepted participant in an active race: `200 {notices:[...]}` (possibly
  empty), never `202`;
- accepted participant in a terminal race: `200 {notices:[]}`;
- acknowledge an owned unacknowledged or already-acknowledged event while
  active: `200 {acknowledged:true}`;
- acknowledge after the race becomes terminal: `409 RACE_NOT_ACTIVE`; and
- missing, malformed, or foreign notice/receipt ID: generic `404 NOT_FOUND`.

Both popup and Activity expose the common `impact:<uuid>` presentation ID.
Routes strip and validate the prefix before querying the raw UUID. Malformed
rows are omitted from list responses instead of failing the entire response.

### Private Activity

Keep `GET /races/:raceId/private-impact-feed` compatible. Its response remains
`{events,nextCursor}`. While a race is active and the new capability is
present, it returns v2 `race_impact_events`; without it, it returns no active
rows. When a race is terminal, it returns only authoritative
`race_effect_impacts` under the existing `impact_notices` compatibility gate,
so old clients retain completed Activity and a synced snapshot plus later
settlement value never appear as duplicate history.

V2 private events add `sourceFeedEventId` and
`impactScope:"ACTIVE_SYNCED_SNAPSHOT"`. Ordering is `(resolvedAt DESC,id DESC)`.
`nextCursor` is base64url JSON containing version `2`, `resolvedAt`, and raw
UUID `id`; invalid/version-mismatched cursors return the existing invalid-request
error. Limit remains defensively bounded to 50. Move route-embedded Prisma from
`routes.js` into an injected query/repository so authorization, filtering, and
cursor behavior are integration-testable through HTTP.

The popup consumes the same event ID and `description` returned by private
Activity. Popup acknowledgement never filters that event from Activity.

Private feed projections keep the existing `impact:<opaque-id>` presentation
ID contract. The backend returns a cursor for v2 private events, and
`RaceFeedService` owns independent shared/private cursors, merging pages by
`createdAt` and stable ID. Loading older shared Activity must also advance the
private cursor far enough to avoid gaps; each **Load older** action requests the
next page from both live cursors and merges them before rendering. Neither
stream may append out of order.

When a direct consequence already has an exact visible shared Activity event,
the private event sets `sourceFeedEventId` to that row. A v2 client suppresses
that shared ID from its initial load, top refresh, and every load-more page and
inserts the recipient-private projection in its place. Other viewers retain the
shared row. The server never exposes the private event to another recipient.

## Feature gates and cutover

Keep the public routes, but add a distinct client capability
`resolved_impact_events_v2` in both iOS and Android capability-header branches.
V2 source writes are always on; there is no backend rollout flag. The new
capability is required for v2 popup responses and active private-Activity
projections. Frozen clients
that send only `active_impact_notices_v1` never receive v2 active rows or the
dedup/pagination contract they cannot implement. Keep
`apiActiveImpactNoticesV1Enabled` off permanently after the incident; do not
make the new path depend on it.

Source/interception/private-event creation never depends on the casting
request's client capability. Capabilities gate response fields, receipts,
popup reads, and active Activity projections only. Therefore a frozen-client
caster still creates the v2-capable victim's durable event.

The rollout sequence is:

1. deploy the additive migration and always-on backend source writer while the
   retired v1 flag remains off;
2. ship both platforms with `resolved_impact_events_v2`, additive description
   parsing, direct-row dedup, and private pagination; v1-only clients stay on
   the inert compatibility path;
3. preserve every v1 table/migration and observe at least seven full days after
   the successful v2 production deployment before even proposing physical v1
   removal; the destructive migration/deploy requires separate explicit
   approval.

No v1 work or impact row is read by the v2 endpoints. Existing unacknowledged
v1 rows remain inert and can never reappear after v2 enablement. No backfill is
performed.

## V1 cleanup map

The implementation removes or rewrites the following responsibilities:

- `processActiveRaceImpacts.js`: delete the scanner/materializer;
- `raceStateResolution.js`: remove broad active-impact attribution and defense
  history scans; retain only bounded contribution capture for sources resolving
  now;
- `raceResolutionQueueV2.js`: remove flag planning, work persistence,
  generation handoff, materializer invocation, and v1 metrics;
- `computeRaceState.js`: remove v1 active-impact dependency plumbing;
- `activeRaceImpact.js`: replace work/impact model methods with the v2 event
  repository, or add a clearly named `raceImpactEvent.js` model and delete the
  old module;
- `activeRaceImpactMaintenance.js` and its startup scheduling: remove after v1
  is inert;
- `activeImpactRolloutFence.js`, enablement timestamp settings, boundary-skip
  markers, event metadata stamps, and v1-only optimization flags: stop runtime
  reads/writes, but preserve already-stored metadata during the rollback window;
- `expireEffects.js`, `usePowerup.js`, `forfeitRace.js`, and consequence paths:
  write v2 events at their authoritative boundaries without standalone scans;
- routes: preserve the wire contract while switching reads/acks to v2;
- Prisma: add v2 table now; keep v1 tables during rollback window, then remove
  them in a separately approved cleanup migration;
- tests: replace v1 work/scanner internals with public-path integration tests;
  do not weaken unrelated scoring or compatibility assertions.

The currently dirty backend capacity/optimization work overlaps these files.
Implementation agents must preserve unrelated local changes and must not
silently revert them. V1-only optimizations should be intentionally superseded,
not accidentally overwritten.

For at least the same seven-day rollback window, keep a tombstoned
`apiActiveImpactNoticesV1Enabled` entry in `KNOWN_FLAGS`, forced/defaulted false,
so an old binary or stored setting cannot accidentally reactivate v1. Do not
rewrite or squash the already-applied v1 migrations. Physical table/index
drops, metadata cleanup, and removal of the tombstoned flag occur only in the
later separately approved deploy after rollback is no longer required.

## Frontend changes

1. Extend defensive notice parsing with optional nonempty `description`.
2. Prefer the server description for popup subtitle; retain the current local
   numeric-copy fallback for older backends.
3. Remove the now-unreachable 202 handoff branch only after the backend no
   longer returns it and the rollback window closes. Keeping it initially is a
   harmless backward-compatible fallback.
4. Keep current overlay serialization, route/lifecycle guards,
   acknowledgement timing, demo/tutorial empty overrides, and three-notice cap.
5. The Activity list uses its existing `RaceFeedEvent`/`FeedBubble` rendering;
   no new component or placement is introduced.
6. On an `ACTIVE` to terminal status transition, clear active snapshot rows
   from the in-memory merged feed before merging authoritative final rows; the
   user must never see both versions together.
7. Advertise `resolved_impact_events_v2` in both platform header branches and
   apply `sourceFeedEventId` suppression consistently in initial, refresh, and
   load-more merges. Missing fields from older backends preserve current feed
   behavior.
8. Split shared-feed polling from private-impact refresh. The existing five-
   second timer refreshes only shared Activity. Private Activity refreshes on
   initial open, genuine foreground resume, explicit pull-to-refresh, after a
   local powerup result commits, and when popup delivery returns a new event.
   Remote private impacts may therefore wait until the next explicit lifecycle
   refresh; this bounded freshness tradeoff avoids a per-viewer Postgres query
   every five seconds. Events and acknowledgements remain PostgreSQL truth and
   no Redis cache is added.

## Performance requirements

- With no source resolving, active-impact-specific database queries and writes
  in a race resolution are zero.
- No-op work is O(0). A due generation is capped at eight sources and 17 scorer
  calls and may load only the scoring context needed for their affected
  recipients/canonical prefixes. It is never proportional to race feed history
  or prior notification work; required scoring-effect context is explicitly
  allowed only on a due generation.
- Popup GET is one indexed, bounded query plus authorization/race-status read;
  it never enqueues or waits for race resolution.
- Ordinary five-second Activity polling performs no private-impact query.
- No query hydrates all `race_powerup_events` for active-impact processing.
- No notification code runs the full settlement attribution vector during an
  ordinary resolution.
- Resolution phase metrics separately record number of resolved impact sources,
  event inserts, and bounded capture time. Labels contain no user/effect IDs.
- Staging acceptance includes a long-lived race fixture with at least 6,000
  feed events and no due sources; enabling v2 must add no measurable query
  count and less than 5 ms p95 active-impact overhead in that no-op case.

## Tests-first plan

### Backend integration tests

- Through real HTTP powerup use, a direct nonzero consequence atomically writes
  one private Activity/popup event per recipient; a retry does not duplicate it.
- Through the real resolution worker, each eligible timed source writes events
  only at its true boundary, with existing attribution/sign/order preserved.
- Timed parity fixtures compare every v2 source value to the legacy full
  chronological vector, including overlapping same/different multipliers,
  fractional rounding allocation, participant floors, and more than eight due
  sources continuing across generations without loss or duplication.
- Leech, Hitchhike, overlapping multipliers, Umbrella, Trail Mine, and Drill
  Sergeant cover their nonlinear or consequence-specific paths.
- A no-due-source resolution in a race with thousands of feed rows performs no
  active-impact history query, attribution pass, work write, or event write.
- Popup GET returns the same ID and description as private Activity and performs
  no enqueue/resolution side effect.
- Popup acknowledgement hides only popup delivery; the event remains in active
  Activity.
- Inline acknowledgement suppresses only the actor's duplicate popup and never
  hides the victim's event or either Activity row.
- Active races expose v2 private events; terminal races expose authoritative
  final impact rows without a duplicate snapshot.
- Disabled v2 creates no events and performs no notification work. Re-enabling
  does not backfill or expose v1 rows.
- Natural expiry is atomic through C0 with Redis standings both enabled and
  disabled; no request/post-commit fallback can transition an eligible source
  without its event.
- Umbrella resolution in a race with at least 6,000 feed events uses only the
  indexed interception source and performs no historical feed query.
- Old clients without the capability and foreign/nonparticipant callers retain
  the documented downgrade/security behavior.
- A frozen-client caster affecting a v2-capable victim still creates the
  victim's durable event; the caster receives no v2 receipt/response field and
  cannot read the victim's event.
- Transaction failure cannot commit a domain consequence without its required
  event, and normal domain retry produces exactly one event.
- Account/race deletion handles v2 rows without weakening final-impact
  retention.
- Finish/forfeit with more than eight resolving sources writes every stable-ID
  event in the same transaction; injected failure rolls back the freeze and all
  events, and retry produces no duplicates. Record terminal source count and
  transaction duration as aggregate operational metrics.

### Frontend widget/integration tests

- Pump the real active race screen: popup subtitle exactly uses a valid server
  description and dismissing it sends one acknowledgement.
- Missing/malformed description falls back to current defensive numeric copy.
- The same private event renders in Activity before and after popup dismissal.
- Direct `sourceFeedEventId` replacement is correct on initial load, top
  refresh, and load-more; other viewers retain the shared event.
- Each load-more advances and merges both cursors without ordering gaps.
- The five-second shared poll performs no private-feed request; initial open,
  pull-to-refresh, and foreground resume do refresh private Activity.
- Completed race, route uncover, ordinary polling, stale response, stacked
  overlay, demo, and tutorial protections remain green.
- A new frontend against an old backend and an old carrying frontend against
  the new backend both remain usable.

Tests must be written and observed failing before business logic. Backend
integration tests must use a confirmed dedicated test database, never prod.

## Acceptance criteria

- Deploying v2 cannot cause active-impact work on a resolution with no newly
  resolved source.
- Every eligible nonzero source creates one immutable private event per affected
  recipient at its authoritative resolution boundary.
- Activity and popup use the same event ID and description.
- Popup acknowledgement does not remove Activity history.
- Existing app versions continue to parse and use the unchanged endpoint
  shapes.
- V1 rows remain inert, its flag remains off, and v1 runtime code is removed
  without a rollback-unsafe immediate table drop.
- Scoring results and completed settlement Activity remain unchanged.
- Backend unit/integration suites pass on a test DB; frontend tests and
  `flutter analyze` pass; both mobile platforms are accounted for.
- Architecture, UI-placement, and post-implementation code reviews are complete.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Active-impact event materialization cleanup**

*Elements under test:* Recipient-private resolved impact event — durably
available immediately and added to the existing Activity list on the next
defined private refresh, ordered by resolution time.

*Elements under test:* Existing centered impact popup — unchanged in position;
coexists with the same event in Activity and disappears permanently after
acknowledgement.

*Elements under test:* Completed-race Activity — active snapshot is removed and
replaced by the authoritative final impact row in the same Activity panel.

*Checklist*

1. **Active race detail — real screen, iOS**
   - **Get there:** Join an active staging race with another test runner →
     trigger a nonzero impact against this account → Races → Active → open the
     race.
   - **Verify:** The existing popup is centered in its usual overlay position.
     Dismiss it, scroll to the Activity/Chat panel, and verify the matching
     private event appears once in Activity in newest-first order; it is not
     duplicated in the shared activity position or elsewhere on the screen.

2. **Popup and Activity coexistence — real screen, iOS**
   - **Get there:** Leave Activity visible, create another nonzero impact from
     the other account, then background and foreground the app.
   - **Verify:** The centered popup appears while the same event is already
     present at the correct position in Activity behind it. After dismissal,
     the Activity row remains in place. Background/foreground again and verify
     the popup does not reappear while the Activity row remains.

3. **Activity ordering and paging — real screen, iOS**
   - **Get there:** Use a staging race with more than one page of shared
     Activity, including private impacts interleaved by time → open Activity →
     tap **Load older**.
   - **Verify:** Private and shared rows form one newest-first list, each impact
     appears exactly once, and loading older rows does not move, duplicate, or
     remove private rows. The impact is not appended at the bottom merely
     because it came from the private stream.

4. **Active-to-completed transition — real screen, iOS**
   - **Get there:** Keep the impacted race open until it completes, or reopen it
     after staging completes it → scroll to Activity.
   - **Verify:** The active synced-snapshot row is no longer present. One
     authoritative final impact row occupies the existing Activity list;
     active and final versions are not shown together. No centered
     active-impact popup appears.

5. **Entry routes — real screen**
   - **Get there:** Open an accepted active race through Races → Active; then
     repeat through a Home race card or race notification/deep-link. If staging
     fixtures permit, also enter an accepted race from Public Races and from a
     tournament matchup.
   - **Verify:** Every route lands on the same race-detail Activity panel, with
     the private row in the same list position and no duplicate Activity panel
     or popup. Preview/nonparticipant entry continues to show the locked
     Activity state rather than private impact data.

6. **Android parity**
   - **Get there:** On Android, repeat checklist items 1–2 through Races →
     Active, then background/foreground once.
   - **Verify:** Popup placement, Activity-row placement, dismissal
     persistence, and coexistence match iOS; the row remains after dismissal
     and the popup does not reappear.

7. **Demo race tutorial — real screen with fake service**
   - **Get there:** Sign in with a fresh account → onboarding → demo race; play
     until the race-detail Activity panel is reachable.
   - **Verify:** The existing scripted Activity rows remain in their normal
     panel. No recipient-private impact row or unscripted centered impact popup
     appears, and no duplicate/empty Activity section is introduced.

8. **Tab tutorial race-detail preview**
   - **Get there:** Profile → Admin → re-run tutorial → advance to the
     race-detail preview and scroll to Activity.
   - **Verify:** The seeded Activity rows remain in the existing Activity
     panel. No live private-impact row or popup appears. The powerups spotlight
     still rings its existing target; Activity changes have not shifted or
     obscured it.

*Surfaces confirmed unaffected:* Races-tab effect badges and inventory slots
are separate hand-forked UI; this change adds no element there.

*Surfaces confirmed unaffected:* Demo coach chrome and race-result summary are
separate overlays; popup placement and result-screen placement are unchanged.

*Surfaces confirmed unaffected:* Tutorial tab bar is hand-copied, but no tab
item, order, or index changes.

*Surfaces confirmed unaffected:* Case-opening screens do not render the race
Activity stream or active-impact popup.

*Risks found while planning:* `RaceFeedService` accepts private rows only when
their IDs begin with `impact:`; the new backend IDs must preserve that
presentation contract or the row will be silently absent.

*Risks found while planning:* Private Activity is fetched as a bounded
independent stream while **Load older** paginates only shared Activity. A busy
race can expose ordering gaps or missing older private rows unless the
backend/client contract deliberately handles that boundary.

*Risks found while planning:* Demo and tutorial services explicitly return an
empty private-impact stream and empty popup list. That suppression must remain
intact so fake race IDs never leak into live calls and unscripted overlays never
cover tutorial beats.

*Risks found while planning:* Active and completed Activity use different
server sources. The status transition must replace the active snapshot rather
than merge both rows into the existing in-memory list.

## Product decisions

- The active private Activity event is durable immediately and becomes visible
  on the next defined private-Activity refresh while the race is active. The
  popup and Activity row literally share one canonical event, and popup
  acknowledgement changes delivery state only.

## Revision log

- Initial draft: replaced durable work plus broad rescans with a single
  recipient-private resolved event used by Activity and popup; preserved public
  routes and deferred destructive v1 table removal through a rollback window.
- Gap pass 1: separated private events from shared feed rows to prevent amount
  leakage; made direct writes atomic, bounded timed capture to sources resolving
  now, and preserved settlement-only history for terminal races.
- Gap pass 2: retained the receipt route as a compatibility alias, isolated v2
  rows by calculation version, prevented v1-row resurrection, accounted
  for dirty overlapping backend work, and added an explicit high-history no-op
  performance test.
- User interview: approved immediate visibility of the canonical private event
  in active-race Activity; architecture review refined this to immediate
  durability and rendering on the next defined private refresh so five-second
  polling does not create a hot per-viewer database read.
- UI-placement review: added the manual checklist verbatim and promoted its
  `impact:` ID, dual-stream pagination, demo/tutorial, duplicate-row, and
  active-to-completed replacement risks into implementation requirements.
- Architect review: required a distinct v2 capability, deterministic
  `sourceFeedEventId` replacement, a maximum-17-call timed attribution
  algorithm with legacy parity fixtures, transactional direct-effect commands,
  a concrete indexed Umbrella interception model, all-configuration C0 expiry,
  exact wire/cursor behavior, removal of five-second private polling, and a
  seven-day minimum rollback window before separately approved v1 drops.
- Architect re-review: corrected fractional ownership by requiring raw marginal
  vectors plus one `allocateIntegerTerms` pass, added the exact due-effect
  index and Umbrella rounding formula, made source writes capability-independent,
  and aligned Activity copy with the
  explicit-refresh freshness contract.
- Architect final review: approved with no remaining required changes or
  suggestions.
- Architect implementation adjudication: approved an explicit terminal-freeze
  exception to the eight-source continuation cap so every finish/forfeit event
  remains atomic with the irreversible freeze; required >8 all-or-nothing and
  stable-dedup coverage plus aggregate duration/count metrics.
- Production cutover decision: removed the v2 backend rollout flag entirely.
  Durable source writes are always on; only the additive client capability
  gates popup, receipt, and active private-Activity delivery.
