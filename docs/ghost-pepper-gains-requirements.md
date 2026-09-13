# Ghost Pepper: refreshed bonus-step result

Status: architect approved; analyst SOUND after incorporated changes; awaiting
user approval to implement. No production changes authorized.

## User story and decision

After Ghost Pepper ends, show only the extra steps earned during its boost.
The user explicitly does not want burnout loss or net benefit displayed.
For 1,011 ordinary steps credited in an isolated 3× boost, the result is
**+2,022 bonus steps**, not 3,033 total steps and not the hour's net benefit.
The amount must reflect subsequently synced health data. Do not present an
expiry-time snapshot as a final result, or merely relabel the old net value.

Use the existing reveal-card and Activity styling. Suggested text:
“Ghost Pepper added 2,022 bonus steps.” Supporting text: “Based on synced steps.”
No burnout amount or net total appears on either surface. No new artwork.

## Evidence and current paths

Backend `src/modules/races/jobs/raceResolutionQueueV2.js` function
`persistResolvedImpactEventsV2` records nonzero signed net impacts once using
`createMany(skipDuplicates: true)`. `raceImpactEvent.js` exposes those immutable
rows to both `getActiveRaceImpactNotices.js` and `getPrivateImpactFeed.js`.
Rows with net zero are omitted; a gains-only UI cannot rely on these rows.

Frontend `lib/screens/race_detail_screen.dart` `_ActiveImpactNotice.tryParse`
accepts only nonzero `deltaSteps` with `SYNCED_SNAPSHOT`, then displays that
number in `showPowerupRevealModal`. `lib/services/backend_api_service.dart`
owns HTTP; race feed/stream services own Activity delivery and refresh.

Canonical backend multiplier/sample behavior is in
`effectiveStepScoring.js`, `effectMultiplier.js`, `stepSample.js`, and
`raceStateResolution.js`. Reuse it; never calculate a bonus in Dart or multiply
an unfiltered hourly step total. Health sync has no complete-through watermark.

## Scope

Correct Ghost Pepper gain presentation and late-data refresh. Preserve actual
race scoring, burnout behavior, prices, rewards, settlement attribution,
immutable net-impact records, and old-client API fields. No runtime flags.
No production data repair or deployment is authorized by this design.

## Gain definition

`gainedSteps` is the positive extra contribution of Ghost Pepper's boost phase,
before separately attributed deductions/transfers and global event bonuses.
It is not the change in the participant's entire race score.

Instrument the canonical local effect capture, using only the chronological
source prefix through this Ghost Pepper (startsAt then id), never the union of
prefixes for other sources in the batch. Reuse bulk input reads, but keep each
source's partition stable. Clip to boost start/end and actual effect, race and
participant cutoffs. At each canonical segment:

```text
positiveExtra = canonicalSegmentSteps × max(0, multiplierAfterGhost − multiplierBeforeGhost)
gainedSteps = Math.round(sum(positiveExtra over boost segments))
```

Preserve existing per-sample overlap rounding, then round the total once per
source. Exclude burnout segments, negative boost contributions, race-total
floors, Leech transfers, Hitchhike copies and separately attributed global
bonuses. Never use `allocateIntegerTerms`: its net/remainder target includes
burnout and would make a burnout-only sync change a gain-only number.

The analyst verified these canonical fixtures for 1,011 boost steps:

| Earlier overlapping effect | Before → after Ghost | Extra gain |
|---|---|---:|
| None | 1 → 3 | 2,022 |
| Runner's High | 2 → 5 | 3,033 |
| 50% Rainstorm | 0.5 → 1.5 | 1,011 |
| Freeze | 0 → 0 | 0 |
| Wrong Turn | −1 → −3 | 0 |
| Losing Coin Flip | 0.5 → 2.5 | 2,022 |

A boost with 400 ordinary steps followed by 611 reversed steps reports 800
positive bonus steps. Reversal losses are not subtracted from this display.
The same source calculated alone or with later sources must have the identical
result, including 1-step partial buckets. Missing valid sample/metadata inputs
produce PENDING/UNAVAILABLE, never an invented zero or the legacy net amount.
An ended effect can have zero positive gain; retain its lifecycle for late
sync. A computed zero can be displayed as “0 bonus steps”; pending is not zero.

## Data model and work ownership

Add a separate `race_effect_gain_summaries` table; never overwrite
`race_impact_events` or `race_effect_impacts`. Unique `(race_id,user_id,effect_id)`.
Fields: id, race/user/effect IDs, type, boost starts/ends, result availability,
nullable gained_steps, calculation_version, computed_at, required_revision,
result_revision, scoring-input version, source/effect revision,
next_eligibility_at, has_published_ready, popup_acknowledged_at, suppress_popup,
created_at, updated_at.
Revisions are monotonically increasing database-issued tokens, not timestamps.
Index race/user/end/id for feed, race/user/unacknowledged/end/id for delivery,
user/boost-window for invalidation, and dirty/due work for bounded claiming.
Use an additive migration with nullable result fields and checks for
nonnegative integers and coherent ready/pending states. Follow existing
cascade/retention policy for user and race deletion.

Create the lifecycle in the Ghost Pepper activation transaction; publication
waits until the effect ends, preserving when summaries currently appear.
The race-keyed fenced worker owns computation/publication. Never run scoring
from popup/feed GETs. Reuse prefetched scoring inputs and canonical capture.

Use the summary row's required/result revisions as durable dirty state.
`stepSample.js` must return the union of old and new windows for inserted,
corrected, removed and overlap-replaced scoring rows; changes to metadata alone
must not invalidate gains. `stepInputIntake.js` records invalidation in the
same transaction as samples and the input-generation bump. Intersect this union
with stored boost windows and bump required_revision in a set-based update.
Do the analogous invalidation for old/new relevant effect windows. Select at
most 65 matching sources by boost-start/id; update at most 64 in one command.
If a 65th exists, persist a durable invalidation-range continuation (user,
window union, cause revision, source cursor) in that same transaction. Drain
continuations in 64-source pages and enqueue affected races in bulk. Creation
and backfill always start dirty, covering sources inserted behind a cursor.
Unchanged or burnout-only sync causes no gain recomputation or result write.

Each race-worker attempt selects at most 8 dirty sources. Fetch effects and
samples in shared keyset pages (512 effects/4,096 samples per read), using the
existing prepared-input/capture machinery; never use per-source SQL. Bound
memory, preserve per-source partitioning and carry unfinished source work
forward durably rather than truncating inputs. Gate source publication on the
matching required revision, scoring-input version and race fence; stale work
is discarded. Use conditional bulk upsert and never reset acknowledgement.
Input paging or retries must not partially publish a source's result.

If an overlapping stored bucket is not closed, record its earliest future
period_end as next_eligibility_at. The existing boundary scheduler, started via `startCrons()` under its
single-instance guard, additionally
selects at most 50 due gain races using a partial index, marks sources dirty
and enqueues existing race work in bulk. Closing an already-stored bucket must
refresh the gain even without another phone upload. Recompute the next due
closure until no open overlap remains. This is not a completeness watermark.

For already-running races, bounded resumable discovery creates pending gain
lifecycles from existing Ghost Pepper effects, including net-zero effects.
Select at most 64 effects per discovery page with a stable keyset cursor;
backfilled rows set suppress_popup=true and cannot create a popup backlog.
Both acknowledgement paths update the source's shared delivery state, including
legacy acknowledgement after a gain lifecycle already exists, so upgrading
cannot replay a dismissed source. No production backfill runs without explicit
deployment approval.

Settlement must compute gains afresh from the same accepted input snapshot as
final scoring, during its existing canonical effect traversal. Batch result
writes in groups of at most 64 and commit under the settlement fence before
publishing terminal gain rows. Do not freeze an old live value. Settlement
owns sources missed by live work/backfill and supersedes pending live work;
a subsequent live attempt cannot overwrite a settled result. This adds no
extra whole-race scorer traversal. Terminal gains remain immutable after the
race's accepted inputs are settled.

## API contract and compatibility

Keep every existing field and old-client response contract unchanged.
Advertise a truthful `ghost_pepper_gains_v1` client capability in both inline
ternary header branches and `clientFeaturesHeaderForPlatform` on both platforms
only when the new renderer and acknowledgement support are implemented.
This is contract negotiation, not a rollout switch.

For capable clients, existing `GET /races/:id/active-impact-notices` adds a
separate `gainNotices` array (legacy `notices` still holds other impacts).
Do not send a duplicate legacy Ghost Pepper net popup to a gains renderer.
Example ready row:

```json
{
  "id": "gain:<uuid>",
  "effectId": "<uuid>",
  "powerupType": "GHOST_PEPPER",
  "gainedSteps": 2022,
  "valueStatus": "SYNCED_GAIN",
  "calculationVersion": 1,
  "revision": "42",
  "presentationStage": 1,
  "description": "Ghost Pepper added 2,022 bonus steps.",
  "detail": "Based on synced steps.",
  "resolvedAt": "2026-09-12T19:14:48.478Z",
  "computedAt": "2026-09-12T19:29:28.000Z"
}
```

Presentation ordering is the tuple `(revision, presentationStage)`: revision
is the required/result input token encoded as a decimal string; stage 0 is
pending, stage 1 is ready/unavailable, and stage 2 is settled. Thus pending 42
can be replaced by ready 42, and live ready 42 by settled 42; an old ready 41
cannot overwrite pending 42. The backend increments revision for a new input
or metadata correction. Clients validate both components and compare the tuple.

The popup response returns only ready eligible rows in `gainNotices` and
adds `gainNoticesSupported: true`; pending/unsupported rows never enter a
new numeric popup. Never-ready rows are not acknowledged; a previously shown
ready popup may still be acknowledged during invalidation, as specified below. Reads are bounded at 20, ordered by
source end/id; preserve account/race access and resolvedAfter baseline.
Revisions update Activity, never repeat acknowledged popups. Superseded rows
(required_revision > result_revision) are pending until refreshed.

Add `POST /races/:id/gain-notices/:id/acknowledge`, recipient-scoped/idempotent:
200 `{ "acknowledged": true }` for an owned row with
`has_published_ready=true`, including an already acknowledged row or one whose
newer revision is now pending; 404 for nonexistent/wrong-recipient IDs; 403 for a
nonparticipant; 401 unauthenticated. For an inactive race return 409 with code
`RACE_NOT_ACTIVE` and leave acknowledgement unchanged. Never acknowledge a
source that has never published a ready result (409 `GAIN_NOT_READY`). The
durable has_published_ready marker is set by the first ready materialization
and never reset by invalidation; dismissing a fetched ready result during a
concurrent sync therefore cannot cause a later replay. Delivery writes update both
corresponding gain and legacy-source acknowledgements without changing values.

For capable clients, `GET /races/:id/private-impact-feed` merges gain rows with
other impacts. Ready gain payload is exactly the popup row above plus
`eventType: EFFECT_GAIN` and `createdAt` equal to source end time; settled rows
use `valueStatus: SETTLED_GAIN`. Pending Activity carries the same ID/type/end
and required revision, `valueStatus: PENDING`, `gainedSteps: null`,
`description: "Ghost Pepper ended. Updating bonus steps…"`, and no computedAt.
Unavailable metadata uses `UNAVAILABLE`, null amount and
“Ghost Pepper ended. Bonus steps unavailable.” No stale net fallback.

Omit duplicate legacy Ghost Pepper net rows while retaining other families.
Backend merge ordering is `(sourceEnd DESC, sourceKind DESC, sourceId DESC)`;
sourceKind is the literal GAIN or IMPACT. Hard page limit 50. The opaque cursor
is base64url JSON `{ version: 3, phase: ACTIVE|TERMINAL, sourceEnd, sourceKind,
sourceId }`. Validate all fields and reject unknown/mismatched phase/cursor
with 400 `INVALID_CURSOR`; client discards cursor and reloads when phase changes.
Query each indexed family with the cursor and at most limit+1, merge in memory
and emit a cursor for the last returned row. An amount/revision change never
changes sort time or ID. Preserve old clients' existing cursor families.
Terminal capable Activity uses freshly settled gains, never legacy net values.
Do not expose another user's gain or sync metadata.

On old backend/new app: no invented bonus. The UI may show “Ghost Pepper ended”
without the legacy snapshot number. Other powerup summaries continue normally.
On new backend/old app: preserve frozen numeric contract; clarify historical
Ghost Pepper net descriptions at projection time so they do not imply final
gain. This optional old-client wording is not the gains-only implementation.

## Frontend implementation

Use an independently parsed gain-notice model; accept finite nonnegative
integers, known status/version, valid dates, valid nonempty IDs/type. Missing,
null, malformed and unknown states never become zero or fall back to net.
Render the bonus as the sole main number in the existing reveal modal. Place
“Based on synced steps” in the existing subtitle area. Do not add burnout or
net lines. Use server-authored amounts/copy and preserve the current art.

After resume/manual refresh/step-sync completion, refresh private Activity and
available notices. Upsert the same gain event ID with its greater `(revision, presentationStage)` tuple
rather than treating duplicate IDs as immutable. Fence out stale HTTP/stream
responses and account/race switches. Dismissal remains exactly once and is
independent of amount revisions. No overlay while pending, behind another
overlay, off-route, in demo mode or for a nonparticipant.

Demo and tab tutorial APIs currently return empty private notices. Keep that
behavior; use real-screen widget fixtures to cover gains. Both iOS and Android
share this Dart behavior and capability header; no platform-specific policy.

## Implementation order and tests first

1. Analyst locks positive contribution semantics and overlap examples;
   architect approves contract, data lifecycle and bounded work mechanism.
2. Backend agent writes failing real HTTP/real local Postgres integration tests,
   then lands additive schema/API contract. Test DB name must end in `_test`.
3. Backend implements canonical capture instrumentation, durable invalidation,
   fenced conditional bulk materialization, migration/backfill and projections.
4. Once API contract is locked, frontend agent writes failing real-screen tests
   and implements parsing, delivery and feed replacement. No mocked backend
   arithmetic parity tests as a substitute for HTTP scoring/refresh evidence.
5. Independent code review; relevant suites and clean `flutter analyze`.
   Backend first deployment, then both-platform app verification/release as a
   separately authorized operation. No production changes in the coding phase.

Required end-to-end cases:
- 1,011 boost steps => 2,022 extra; 545 burnout steps never appear in gain UI.
- Expire with sparse samples; upload late boost samples through HTTP; drain
  real work and prove popup/Activity revised gain, same source identity and
  unchanged original net snapshot. Bonus is not derived from snapshot delta.
- Late burnout-only sync does not change gain or schedule gain recomputation.
- Initially zero/unknown, net-zero cancellation, positive gain with negative
  net, pending, true zero, sample correction downward and repeated identical
  sync; all explicit, no replay of an acknowledged popup.
- Overlapping buffs, freeze, rain/umbrella, reversal, early end, partial bucket,
  race/participant cutoff, legacy metadata, global events and transfer sources.
- Pending 42 → ready 42 and live 42 → settled 42 replace correctly; fetch
  ready → sync invalidates → dismiss → recompute never replays the popup.
- More than 8 due/dirty sources, retries, stale fence, concurrent sync/ack,
  incomplete work continuation, deleted account, terminal settlement.
- Old/new headers, missing backend fields, unauthorized reads/acks, paginated
  mixed Activity without duplicates/skips, stale response cannot overwrite a
  newer amount, old backfill acknowledgements/baseline suppress backlog.
- Measure sample/effect SELECTs and result writes, including downstream work;
  no per-source DB loops and zero recompute for unchanged or burnout-only sync.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Ghost Pepper bonus steps**

*Elements under test:* Bonus amount occupies the existing result modal’s main-number position; supporting text occupies its subtitle area. Activity uses the existing result bubble.

*Checklist*

1. **Real race — result modal**
   - **Get there:** Races → active race with an unseen, completed Ghost Pepper gain notice.
   - **Verify:** One bonus number appears in the main-number position, with supporting text beneath it. No separate burnout/net rows or duplicate result block appear. Dismissal control remains visible.

2. **Real race — Activity**
   - **Get there:** Dismiss the modal → Activity → Ghost Pepper result.
   - **Verify:** The result occupies one existing feed bubble; no additional burnout/net block appears. After refreshing, the result remains in that position without a duplicate row. Timestamp and neighboring entries remain unobstructed.

3. **Narrow screen and enlarged text — both platforms**
   - **Get there:** Repeat modal and Activity checks on iOS and Android with enlarged system text. Prepare another unseen notice for the modal.
   - **Verify:** Main number, subtitle and dismissal control remain separated and reachable. Activity text stays inside its bubble without overlapping adjacent entries.

*Surfaces confirmed unaffected:*

- Demo race tutorial: reuses `RaceDetailScreen`; its fake API returns empty private impact feed and active notices, intentionally retained.
- Tab tutorial race preview: reuses `RaceDetailScreen`; its fake API also returns empty private impact feed and active notices.
- Races tab inventory/effect plates: separate widgets; no placement change proposed.
- Tutorial spotlights and coach chrome: no anchor or widget moves.

*Risks found while planning:*

- Demo/tutorial cannot demonstrate the new result because their fixtures intentionally omit it; real-screen fixtures must cover placement.
- Enlarged text may crowd the existing modal.
- Prepare unseen notices before device checks; dismissed notices cannot reopen the modal.

## Revision log

- Gap pass 1: separated positive boost contribution from net and total steps;
  covered existing omitted net-zero rows, stale sync and acknowledgement reuse.
- Gap pass 2: added old-backend safe behavior, feed replacement, source revision
  fences, stable pagination, bounded backfill/overflow and terminal cutoffs.
- User clarified: show gains only; no burnout or net breakdown.

- Architect pass 1: specified durable invalidation for deleted/replaced windows,
  bucket closure scheduling, discovery/input bounds, monotonic revision ordering,
  exact pending/error/cursor contracts and fresh settlement computation.
- Analyst: locked per-segment positive clipping, per-source final rounding and
  batch-invariant chronological partitioning; overlap examples verified against
  canonical multipliers. No race score/economy change.
- Architect pass 2: added input-revision/stage ordering for pending→ready and
  live→settled transitions, durable ever-ready acknowledgement across invalidation,
  and explicit single-instance scheduler ownership.
- Architect final review: APPROVE, no required changes. Clarified that the
  pending acknowledgement restriction applies only to never-ready sources.
