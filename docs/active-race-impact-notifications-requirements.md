# Active-race impact notifications and 2× summary eligibility

## Status

Draft for product interview. No implementation is approved by this document.

## Summary and user story

When a score-changing powerup finishes while a race is still active, the
affected player should see one private, signed impact notification the next
time they open or resume that race. For example, after a Leech window ends, its
victim may see `−426 steps from Leech` and its beneficiary may see `+426 steps
from Leech`. A historical completed race must never interrupt navigation with
these popups; its private numeric explanations remain in Activity.

The Home `2× STEPS COMPLETE` modal remains a post-event recap, but it is
eligible only if at least one overlapping race made a nonzero contribution for
that user. Merely being enrolled in a race during the event is insufficient.

This corrects two behaviors shipped in 2.3.8:

- `RaceDetailScreen` fetches impact notices only from the `COMPLETED` branch,
  even though the desired experience is an active-race notification.
- the global-event summary worker creates a summary for an all-zero group,
  despite the existing requirements saying at least one contribution must be
  nonzero.

## Current evidence

- Completed race detail calls `_loadCompletedProgressAndImpactNotices`, which
  loads final progress and then fetches up to three unacknowledged notices:
  `lib/screens/race_detail_screen.dart:1011-1125`.
- Active races poll progress but never fetch impact notices:
  `lib/screens/race_detail_screen.dart:1001-1010,1411-1432`.
- Inbox uses the normal race-detail route, so Inbox is not independently
  creating the popups: `lib/screens/main_shell.dart:3190-3208,3266-3286`.
- Exact `RaceEffectImpact` rows are currently written only during whole-race
  settlement: backend `src/modules/races/jobs/raceExpiry.js:529-539`.
- Timed effects are already transitioned to `EXPIRED` during active resolution,
  with a stable effect ID and expiry Activity event: backend
  `src/modules/powerups/commands/expireEffects.js:29-130`.
- The existing impact endpoint returns every unacknowledged row for the user
  and race without considering race status: backend
  `src/modules/races/queries/raceImpactNotices.js:31-38`.
- The 2× summary worker groups all final enrollment rows and upserts even when
  they are all zero: backend
  `src/modules/steps/jobs/globalEventSummary.js:13-47`.
- Existing requirements explicitly say a 2× summary is shown only when any
  per-race contribution is nonzero:
  `docs/feature-batch-2026-08-17-requirements.md:241-259`.

## Product behavior

### Active-race powerup impact notification

1. An effect is eligible only after its scoring window or instantaneous score
   consequence has resolved.
2. The race must still be `ACTIVE` when the client requests notices and again
   when the notice is acknowledged. If the race is `COMPLETED`, `CANCELLED`, or
   otherwise terminal, the modal is suppressed.
3. Delivery is recipient-private. The client supplies no user ID; authorization
   derives the authenticated user and accepted race participation.
4. A nonzero impact creates at most one notification per
   `(raceId, userId, sourceKind, sourceId, calculationVersion)`.
5. The next eligible race open or foreground resume fetches notices after the
   authorized detail/progress load. Normal 30-second polling never interrupts a
   player who is already looking at the race.
6. Show notices one at a time in settled-effect order, at most three per open.
   Dismissal acknowledges that recipient's notice. Remaining notices wait for
   a later open/resume.
7. Completed-race opens never fetch or show the overlay, whether entered from
   Inbox, Races, a push, Home, a tournament, or another deep link.
8. Completed Activity retains the immutable final numeric explanation. Active
   Activity may retain the existing nonnumeric expiry line unless the active
   value is explicitly defined as final under the policy below.
9. Immediate caster-side outcome UI (blocked, reflected, redirected, Coin Flip,
   Mystery Potion, and similar use responses) is unchanged.
10. Demo/tutorial services return no notices and never perform a real network
    request.

### Numeric value policy — immutable synced-step snapshot

An effect's clock expiring does not prove that all HealthKit/Health Connect
samples for its window have reached the backend. The active notification is
therefore an immutable snapshot of the canonical score using the committed
generation's synced baseline plus closed effect-window sample terms. It is not
the immutable whole-race settlement attribution and must not be called `final`
in the API or UI.

The modal uses direct, playful copy such as `Leech drained 426 synced steps` or
`Runner's High added 426 synced steps`. “Synced steps” accurately scopes the
number without the awkward, low-confidence phrase “so far.” Once delivered,
that notification value never changes. Later device uploads may make completed
Activity's authoritative final attribution differ; Activity is explicitly the
final race record.

`uploaderReconciliation = CURRENT` is not treated as proof that no historical
sample can arrive later. A closed `periodEnd` is required for snapshot input,
but no invented ingestion watermark or arbitrary grace delay blocks delivery.
This prioritizes timely game feedback on the next open/resume while keeping the
data claim honest.

### 2× event summary

1. Wait until the event has ended and every enrolled race/user impact row is
   `FINAL`, as today.
2. Create/deliver a summary only if at least one final per-race contribution has
   `deltaSteps != 0`.
3. Preserve legitimate mixed net-zero summaries. For example, `+100` and
   `−100` still shows `net 0`; therefore the frontend must not suppress solely
   on aggregate `extraRaceSteps == 0`.
4. Existing all-zero summary rows must be filtered from Home so users do not
   continue receiving the bad modal after the fix. They may be acknowledged by
   a controlled repair only with explicit production approval; read filtering
   is sufficient for correctness and is safer during rollout.
5. The modal remains acknowledgement-gated and appears after a Home refresh,
   not during an active event.

## Scope

- Backend active-effect impact calculation, persistence, private reads, and
  acknowledgement.
- Flutter active-race fetch timing and completed-race suppression.
- Preservation of completed Activity explanations.
- Correct 2× summary eligibility for new and already-created rows.
- iOS and Android behavior through shared Dart code.
- Tests, feature flags, operational metrics, and backward-compatible rollout.

## Non-goals

- Changing any powerup's duration, multiplier, transfer ratio, target rules, or
  scoring math.
- Changing global-event timing or the 2× multiplier.
- Showing another player's private numeric impact.
- Replacing immediate caster-side outcome dialogs.
- Backfilling active notifications for effects that ended before rollout.
- Deploying or modifying production data without separate, in-the-moment
  approval.

## API contract

### Capability and feature gate

Add client capability `active_impact_notices_v1` and backend flag
`apiActiveImpactNoticesV1Enabled`, default false. Keep `impact_notices` and its
private Activity behavior available as a compatibility surface. Add a separate
default-off `apiCompletedImpactPopupEnabled` flag around only the legacy
`GET/POST /impact-notices` popup endpoints. Do not disable
`apiImpactNoticesEnabled`: the completed private Activity feed shares that flag
and must remain readable.

The new capability must be additive in both iOS/ads header branches. Old app
versions omit it and receive no new response fields.

`apiActiveImpactNoticesV1Enabled` gates new work eligibility at the source
resolution boundary as well as GET/ack delivery. While false, resolving effects
create no work (no backfill). If it is disabled after work already exists, those
Postgres rows remain durable but undiscoverable/unprocessed; re-enabling resumes
them only if the race is still active, otherwise terminal cleanup marks them
`SUPPRESSED_TERMINAL`. Tests lock disable → source resolution, enable → new
source, disable with pending work, and re-enable in active/terminal races.

### `GET /races/:raceId/active-impact-notices`

Request body: none. Authentication and `X-Client-Features` are required.

Success:

```json
{
  "notices": [
    {
      "id": "arin_opaque",
      "powerupType": "LEECH",
      "deltaSteps": -426,
      "valueStatus": "SYNCED_SNAPSHOT",
      "resolvedAt": "2026-08-19T16:30:00.000Z"
    }
  ]
}
```

If durable impact work exists but its fenced resolution generation is not yet
complete, return `202`:

```json
{
  "notices": [],
  "resolution": {
    "state": "PENDING",
    "jobId": "rrj_opaque",
    "generation": 42,
    "retryAfterMs": 500
  }
}
```

The GET query atomically ensures/enqueues the race-keyed generation for pending
work and returns its opaque status handle. Flutter uses the existing bounded
`GET /steps/race-resolution/:jobId` handoff, honoring `retryAfterMs`, then calls
the notice GET exactly once more. Timeout, failed resolution, malformed 202,
backgrounding, navigation, or terminal status ends the attempt with no overlay;
the next genuine open/resume may try again. The carrying client capability
gates this 202 contract; frozen clients never call the endpoint.

- Return at most 20 oldest-first; Flutter presents at most three.
- Return `{ "notices": [] }` for an authorized participant if the race is not
  currently `ACTIVE`. This prevents a frozen carrying client from showing
  historical popups after completion.
- Return `403 {error,code}` for a nonparticipant, `404` for an unknown race or
  disabled/missing capability, and no cross-user existence signal.
- Malformed database rows are omitted rather than failing the whole response.

`valueStatus` is mandatory and equals `SYNCED_SNAPSHOT` in v1. Flutter treats a
missing or unknown value as unsupported and skips that row rather than
presenting misleading copy.

### `POST /races/:raceId/active-impact-notices/:noticeId/acknowledge`

Empty JSON body. Success:

```json
{ "acknowledged": true }
```

The mutation predicate includes `noticeId`, `raceId`, authenticated `userId`,
`acknowledgedAt: null`, and an `ACTIVE` race. It is idempotent from the user's
perspective: an already-acknowledged own notice returns `200` with
`acknowledged:true`; absent/foreign returns generic `404` without disclosure.
If the race became terminal between GET and dismissal, return `409
RACE_NOT_ACTIVE`; Flutter closes quietly and does not retry the overlay.

### Inline receipt contract

For `active_impact_notices_v1` clients only, a successful powerup-use response
may add:

```json
{
  "activeImpactReceipt": {
    "id": "air_opaque",
    "raceId": "race_opaque"
  }
}
```

The receipt belongs only to the authenticated actor/recipient whose exact
signed result is in that response; it never identifies or acknowledges a
victim. Missing/malformed receipt changes nothing about the existing outcome
UI.

After the inline result is actually dismissed, Flutter sends an empty-body
`POST /races/:raceId/active-impact-receipts/:id/acknowledge`. The command binds
opaque ID, race, authenticated recipient, and calculation version, and
idempotently stamps `inlineAcknowledgedAt`; absent/foreign is generic 404. It is
allowed while the race is active even if materialization has not run yet. If
the race became terminal, return 409 and rely on terminal suppression/final
Activity. A failed ack may cause an at-least-once duplicate next-open popup but
can never lose the notification; the client does not retry beyond the existing
single network retry policy.

### Existing completed impact endpoints

Do not remove or change response fields on
`GET/POST /races/:raceId/impact-notices...`; older 2.3.8 clients still call
them. Gate those two legacy popup routes with the separate default-off
`apiCompletedImpactPopupEnabled` flag, returning the existing feature-disabled
404 when false. The adjacent private Activity endpoint remains controlled by
`apiImpactNoticesEnabled`, stays enabled/readable, and continues to expose
immutable final impacts. A mixed-version client must therefore get no completed
popup while still receiving its private Activity events.

### Home summary response

No client shape change is required. Both Home response builders must include
`globalEventSummary` only if an unacknowledged summary's `(eventId,userId)` has
at least one corresponding `GlobalEventRaceImpact` with `status=FINAL` and
nonzero `deltaSteps`. The summary worker applies the same predicate before
creating future rows.

The eligibility change bumps the derived-cache key from
`v1:home:impact-summary:<userId>` to `v2:home:impact-summary:<userId>` so a warm
predeploy all-zero value cannot leak through the old 60-second cache. Keep
`redisCacheHomeImpactSummaryEnabled` default-off. Summary creation, ALL_ZERO
processing, acknowledgement, and any final-impact repair invalidate the v2 key.
Every Redis error/unset path falls back to the identical Postgres predicate;
Redis is never authoritative.

## Data model and migration

Add two Postgres-backed tables rather than repurposing immutable final impacts.
Redis is not used for work, delivery, acknowledgement, zero outcomes, or
provenance.

`active_race_impact_work`

| field | rule |
|---|---|
| `id` | UUID primary key |
| `raceId`, `recipientUserId` | owning race and independently resolving recipient |
| `sourceKind`, `sourceId` | stable domain source, defined by the matrix below |
| `powerupType` | canonical snapshot |
| `status` | `PENDING`, `ZERO`, `CREATED`, or `SUPPRESSED_TERMINAL` |
| `resolvedAt` | source resolution timestamp |
| `processedGeneration` | null while pending; committed race-resolution generation once processed |
| `calculationVersion` | non-null integer, default 1 |
| `inlineReceiptId` | nullable unique opaque receipt offered only to that recipient's capable client |
| `inlineAcknowledgedAt` | nullable client-confirmed inline dismissal time |
| timestamps | normal created/updated timestamps |

Unique `(raceId,recipientUserId,sourceKind,sourceId,calculationVersion)` is the
durable retry fence. Each recipient has independent status, generation, and
`resolvedAt`; a Leech caster freezing early cannot finalize its still-active
victim's work. Natural expiry processes only unresolved recipient rows. `ZERO`
is a first-class processed outcome, so a zero recipient effect is not recomputed
forever. Pending work is claimed from Postgres by a later active resolution;
Redis is never a queue. A terminal transition atomically marks any remaining
`PENDING` work `SUPPRESSED_TERMINAL` because it can no longer produce an
active-only modal; final settlement Activity remains independent.

`active_race_effect_impacts`

| field | rule |
|---|---|
| `id` | UUID/opaque primary key |
| `raceId`, `userId`, `workId` | recipient-private identity |
| `sourceKind`, `sourceId` | copied stable source identity |
| `powerupType` | canonical type snapshot |
| `deltaSteps` | signed integer snapshot |
| `valueStatus` | `SYNCED_SNAPSHOT` in v1 |
| `calculationVersion` | non-null integer, default 1 |
| `sourceGeneration` | nullable committed resolution generation; required for timed/derived snapshots |
| `resolvedAt` | effect resolution timestamp |
| `acknowledgedAt` | nullable |
| timestamps | normal created/updated timestamps |

Unique `(raceId,userId,sourceKind,sourceId,calculationVersion)` makes worker
retries and concurrent generations idempotent. Insert with conflict-do-nothing;
an impact is immutable from first insert, whether acknowledged or not. Index
`(raceId,userId,acknowledgedAt,resolvedAt,id)` supports delivery.

These rows are presentation/retry state, not settlement inputs. Use `CASCADE`
from race/work where safe, explicitly delete both tables alongside the existing
private impact rows in `deleteUserAccount`, and cover race deletion, terminal
transition, retention, and the bounded account-delete transaction. Final
`race_effect_impacts` retain their existing restrictive lifecycle.

No backfill. Old rows and old backend binaries continue to function because the
table and endpoints are additive. Final settlement writes the existing
`race_effect_impacts` row independently.

### Eligible source matrix

The v1 notification set is exhaustive. A blocked, reflected-away, voided,
survived, inventory-only, cosmetic, coin-only, or computed-zero outcome creates
no recipient notice (but durable work ends in `ZERO` when applicable).

| Source types | Resolution boundary and stable source | Recipients / signed snapshot |
|---|---|---|
| `LEG_CRAMP`, `QUICKSAND`, `RUNNERS_HIGH`, `WRONG_TURN`, `CAMPFIRE_REST`, `RAINSTORM`, `UPRISING`, `RALLY_FLAG`, `COIN_FLIP`, `GHOST_PEPPER` | first resolution boundary listed below; `sourceKind=ACTIVE_EFFECT`, `sourceId=RaceActiveEffect.id` | every target with its canonical counterfactual delta |
| `LEECH` | effect expiry; `ACTIVE_EFFECT` ID | victim negative and beneficiary positive actual transfer after floor/order |
| `HITCHHIKE` | link expiry; `ACTIVE_EFFECT` ID | caster's signed copied-step delta; no duplicate target notice |
| `UMBRELLA` | a concrete intercepted score loss; `sourceKind=DEFENSE_RESOLUTION`, stable defending effect/event ID | defender's positive avoided-loss snapshot only when nonzero |
| failed `DRILL_SERGEANT` | expiry judgement; `ACTIVE_EFFECT` ID | target's exact applied negative bonus delta; survived/void is `ZERO` |
| detonated `TRAIL_MINE` | detonation commit; `ACTIVE_EFFECT` mine ID | victim's exact post-floor negative delta; untriggered/expired mine is `ZERO` |
| `RED_CARD`, `PINECONE_TOSS` | successful durable powerup event; `sourceKind=POWERUP_EVENT`, `sourceId=RacePowerupEvent.id` | target's exact post-floor negative delta |
| `SHORTCUT` | successful durable powerup event ID | victim negative and caster positive actual transfer |
| offensive `MYSTERY_POTION` rolls of Pinecone/Shortcut | potion's durable powerup event ID plus rolled type in metadata | same recipient rules as the resolved roll |
| `PROTEIN_SHAKE`, `SECOND_WIND`, `TRAIL_MIX`, positive Mystery Potion rolls | successful durable powerup event ID | caster's exact positive committed delta |

Every nonzero affected recipient is eligible. Deduplication is separate from
eligibility: for a capable client, a successful use response that can show the
same exact recipient and amount (self gains, Shortcut beneficiary, or a potion
reveal) includes that recipient's opaque `activeImpactReceiptId`. Only after the
inline reveal/toast is actually presented and dismissed does Flutter
acknowledge the receipt. Queue materialization copies `inlineAcknowledgedAt` to
the impact's `acknowledgedAt`, so it never becomes a duplicate next-open popup.
A dropped response/app termination leaves the receipt unacknowledged and the
next-open notification available. Victims and asynchronous beneficiaries get
no receipt in another user's response. Control/inventory effects are excluded
because they do not change steps.

The exhaustive timed-effect resolution boundaries are:

- natural `expiresAt` reached;
- Cleanse truncates and expires an opponent effect;
- Wrong Turn truncates/replaces an existing Leg Cramp;
- a recast/reset path creates early work only when it actually clamps the stored
  scoring window. A status-only reset such as `clearActiveLegCramps` does not end
  scoring, so its original stored `expiresAt` remains the resolution boundary;
- participant finish or forfeit freezes that recipient's score while the race
  remains active, resolving every included effect contribution for that frozen
  participant;
- Trail Mine detonation and Drill Sergeant judgement use their explicit domain
  consequence commits;
- whole-race completion/cancellation does **not** create active delivery work;
  any pending work becomes `SUPPRESSED_TERMINAL` and final Activity owns history.

Quick Rinse and Pocket Watch only change a future boundary; they do not resolve
the affected effect at cast time. Their later natural/early boundary creates the
single work item under the same stable effect ID. Defense consumption creates
work only for a nonzero avoided step loss, not merely because a shield expired.

Effect-only commands that truly terminate a window early—Cleanse, the
Wrong-Turn/Leg-Cramp clamp, and Mystery Potion reset paths that write
`expiresAt=now`—remain synchronous. Their effect-row update(s) and durable work
insert(s) share one request transaction, so progress reflects removal
immediately. They do not write participant totals. A status-only reset creates
no early work; the boundary scanner includes eligible `ACTIVE` or `EXPIRED`
rows whose stored `expiresAt` has arrived and which lack work, so that row is not
lost merely because its status flipped earlier.

## Backend implementation plan

1. Add migrations plus model-only Prisma access for work/notices, deletion, and
   retention. Build queries/commands with dependency injection; routes remain
   thin `asyncHandler` adapters with standard `AppError` mappings. Do not copy
   the direct-Prisma/manual-try-catch legacy route pattern.
2. Preserve synchronous effect-only semantics. Natural expiry and request-path
   Cleanse/replacement commands atomically update/clamp effect rows and insert
   `PENDING`/`ZERO` work without writing participant totals. Cleanse must affect
   the next progress read immediately. Status-only resets do not claim early
   resolution; a boundary scanner covers both `ACTIVE` and `EXPIRED` effects at
   their stored `expiresAt`. Detonation/judgement, finish/forfeit, and any
   participant mutation plus notification work replay under the existing
   race-keyed C0 fence and participant lock order. Do not add a new request-path
   multi-participant writer.
3. A timed `PENDING` work row enqueues a later race resolution generation. That
   generation captures/fences all scoring inputs, computes the immutable
   attribution artifact from those captured inputs, and inside its C0 write
   transaction inserts notices and marks work `CREATED`/`ZERO`. Never recompute
   after commit while claiming an older generation.
4. The snapshot scorer reuses canonical baseline, multiplier, Leech/Hitchhike,
   floor, and ordering code. Its policy is precise: the baseline/floor uses the
   full synced daily/sample inputs captured by that generation, while effect
   window terms include only buckets closed as of the captured resolution time.
   “All closed samples” never describes the entire baseline.
5. Exact direct deltas already committed by an existing domain command
   (post-floor penalty/transfer) use their durable `RacePowerupEvent` as source,
   but notification materialization routes through the race-keyed queue. A
   queue scanner claims eligible, unprocessed event IDs and writes work/results
   under C0. Shortcut and every other multi-recipient result must not gain a new
   request-path bulk transaction. Residual single-row source writers retain the
   existing global lock order. The server-owned event metadata/result is the
   source—never a client amount. At source time, the event receives additive
   `activeImpactCalculationVersion:1` metadata only when the flag is enabled;
   the scanner ignores unstamped historical events, preventing backfill after a
   later enable.
   The source creates recipient-scoped work and may return only the actor's
   opaque inline receipt. Materialization acknowledges a recipient only from
   their durable client-confirmed `inlineAcknowledgedAt`, never from response
   construction alone.
6. Use conflict-do-nothing for immutable impact inserts and atomic work status
   changes. Two generations racing the same work produce one outcome. A failed
   calculation or insert leaves `PENDING`; later active resolution retries.
   Terminal transition stops modal delivery but does not affect final Activity.
7. Implement private GET/ack queries and commands, model-only Prisma, capability
   and feature gates, and standard errors. Active notices and work are
   Postgres-only; there is no Redis read/write/cache/queue for this surface.
8. Add and default-off the separate legacy completed-popup flag while leaving
   private Activity enabled. Add the mixed-version contract test.
9. Apply the nonzero-existence predicate in both Home response builders and the
   global summary worker. Preserve mixed net-zero eligibility. For an all-zero
   final group, claim the versioned `job_runs` name with `ALL_ZERO` and create no
   summary. Because groupBy still scans final rows, either exclude already
   claimed groups cheaply or describe/measure this as duplicate-write
   suppression rather than claiming it prevents the scan.
10. Bump the Home summary cache key to v2; enumerate and implement invalidation
    on summary creation, ALL_ZERO processing, acknowledgement, and repair. Keep
    Postgres fallback authoritative with Redis enabled, failing, or unset.
11. Keep final settlement attribution and private completed Activity unchanged.
12. Add counts/latency/failure metrics without effect IDs or user IDs in labels.

## Frontend implementation plan

1. Add defensive service methods for the new GET/ack endpoints. Missing,
   malformed, null, 404, 409, or old-backend responses degrade to no overlay.
2. Remove `_showImpactNotices` from the completed-race load path; completed
   progress and Activity still load normally.
3. After an authorized `ACTIVE` detail/progress load on initial open, and after
   an app foreground resume while the route remains visible, fetch notices
   once. Do not bind fetching to every 30-second progress poll. Distinguish a
   genuine app foreground resume from `didPopNext` route uncover so returning
   from case opening or another child route does not trigger delivery.
   If that open/resume reports an already-enqueued resolution generation, await
   its existing bounded status flow and perform one notice fetch after it
   resolves; do not poll the notice endpoint itself. This prevents a race-open
   request from missing an effect that was due but whose durable snapshot work
   completed milliseconds later.
4. Add generation/route/status/modal guards so stale responses cannot show on a
   different race, after navigation, after completion, or over another modal.
   Coordinate with starter-reward and immediate outcome dialogs through one
   route-level overlay queue/guard; overlays never stack.
5. Defensively parse and filter supported, well-formed `SYNCED_SNAPSHOT` rows
   before applying the three-notice cap, so malformed or future-status rows
   cannot starve valid notices behind them. Present oldest-first using
   `PowerupRevealModal`. Present only an
   explicitly supported `SYNCED_SNAPSHOT` status, say `synced steps` in the
   copy, and acknowledge after dismissal.
6. Leave immediate powerup-use result modals unchanged.
   Defensively read the optional actor-only inline receipt and acknowledge it
   only after that existing result UI is actually dismissed. Ack failure never
   suppresses or blocks the immediate result.
7. Demo and tutorial API subclasses override the new methods with empty values.
8. Both iOS and Android use the same flow; verify lifecycle resume on each.
9. Serialize the Home 2× modal through the shell overlay coordinator and gate
   placement on Home being the current visible tab. A cold-start/resume fetch
   while another tab/result overlay is active queues rather than displaying it
   over the wrong surface.

## Backward compatibility and rollout

1. Deploy additive migration and backend code first with the new flag false.
2. Keep `apiImpactNoticesEnabled` on for private completed Activity. The new
   default-off `apiCompletedImpactPopupEnabled` keeps legacy popup GET/ack routes
   unavailable and stops completed-race popups for 2.3.8 clients without
   disabling Activity. Any production config change requires explicit approval.
3. Home summary filtering is safe for every client because it only omits an
   invalid optional field. Older apps continue parsing the rest of Home.
4. Ship Flutter with `active_impact_notices_v1`; missing endpoint means no
   overlay.
5. Enable the new backend flag for staging/test accounts first. Observe
   calculation errors, duplicate writes, GET/ack rates, and race-resolution
   latency.
6. Roll out iOS and Android in lockstep. Keep the old endpoint compatibility
   shim while 2.3.8 remains in the wild; do not re-enable its completed popup
   delivery.
7. No production DB mutation or deploy occurs without explicit approval.

## Tests-first plan

### Backend integration tests

- Active expired Leech creates private signed victim and beneficiary notices
  through the real resolution path; another user cannot read either.
- GET returns notices only while the race is active and only after effect
  resolution; terminal race returns an empty list.
- Pending work returns the capability-gated 202 job/generation contract; the
  existing bounded status path followed by one GET returns the created notice.
- Acknowledgement is recipient/race bound and does not alter another row.
- Retry does not duplicate a notice.
- A snapshot write failure does not roll back race resolution; a later active
  resolution retries it, while a terminal race suppresses modal delivery.
- Process loss after expiry/source commit but before notice insert leaves
  durable pending work that the next active resolution completes.
- Concurrent late step sync and notice computation either join a newer fenced
  generation or use the stamped captured generation—never an unfenced mix.
- Two generations processing the same source create one immutable result.
- Instant-effect and timed-expiry writers both derive amounts server-side and
  never alter authoritative race totals.
- Natural expiry, Cleanse, Wrong Turn replacement, same-type reset/recast,
  finish, and forfeit each create exactly one timed-effect work outcome; Quick
  Rinse/Pocket Watch boundary edits do not create early duplicates.
- Cleanse and true early clamps change the very next progress response
  synchronously; their eventual notice matches that clamped scoring window.
- A status-only Leg Cramp reset creates no premature notice, and the original
  stored expiry is later processed even though the row is already `EXPIRED`.
- Every direct-effect recipient gets one impact row; a successfully acknowledged
  actor receipt suppresses only that actor's duplicate, while a dropped response
  leaves their next-open modal available and victims remain unacknowledged.
- One Leech source resolves caster/victim work independently when they freeze at
  different times; natural expiry completes only the still-pending recipient.
- Zero impact creates no notice.
- Late samples do not mutate an already-created snapshot, and final completed
  Activity may safely differ without changing the snapshot's copy/status.
- Completed final Activity still returns immutable numeric impacts.
- A frozen `impact_notices` client gets no completed popup while its private
  Activity request still succeeds.
- Completion between active GET and acknowledgement returns the documented
  terminal response without later popup delivery.
- Terminal transition marks leftover pending active work suppressed and never
  changes the final Activity attribution path.
- Account deletion and race deletion remove active presentation/work rows
  without weakening final-impact retention.
- All-zero global-event group creates no summary.
- All-zero global-event groups are durably marked processed rather than scanned
  and retried every five minutes.
- Existing all-zero summary is omitted from both Home response paths.
- Mixed nonzero contributions summing to zero still produce and return a
  summary.
- Positive and negative summaries and acknowledgement remain unchanged.
- Home v2 summary cache has Redis-db15 warm/cold/invalidation parity; a warm v1
  all-zero entry cannot be served. Repeat with Redis failure and
  `REDIS_URL` unset to prove Postgres fallback.
- Feature flags/capabilities return the documented downgrade behavior.
- Default-off active flag creates no work; disabling hides/preserves pending
  work, and re-enable resumes only active-race work while terminal work is
  suppressed.

### Frontend widget/integration tests

- Pump real `RaceDetailScreen` for an active race with a resolved notice and
  verify one modal appears after initial load.
- Active unresolved effect returns no modal.
- Completed race with legacy notices renders no modal and still renders its
  Activity entry.
- Inbox and Races routes into the same completed race show no modal.
- Foreground resume fetches once; ordinary polling does not repeatedly fetch.
- An open/resume with a pending resolution generation performs one notice fetch
  after the bounded resolution handoff and does not start a notice poller.
- Dismissal acknowledges once; malformed rows are skipped; a 404/409/network
  failure does not crash or block race detail.
- Unsupported/malformed rows are filtered before the three-notice cap and do
  not starve valid rows.
- Three-notice cap and subsequent-open remainder behavior.
- Immediate attacker outcome modals remain unchanged.
- Inline receipt acknowledgement is sent only after the actual result UI
  dismisses; dropped response/app termination cannot pre-acknowledge it.
- Starter reward/immediate outcome and impact notices serialize without stacked
  dialogs; returning from a child route is not mistaken for app resume.
- Home all-zero summary is absent while mixed net-zero remains visible.
- Home summary waits until Home is the visible tab and does not cover another
  tab or race-results overlay.
- Demo/tutorial screens make no real notice request.
- A carrying frontend against an old backend 404 shows no overlay and keeps the
  real race screen usable.

## Acceptance criteria and definition of done

- A user who opens/resumes an active race after an eligible effect resolves sees
  one private signed `synced steps` snapshot notification.
- The same effect does not repeatedly interrupt after acknowledgement.
- No completed-race navigation path shows a powerup impact overlay.
- Completed Activity retains final private numeric explanations.
- All-zero 2× participation never creates or delivers a Home modal; mixed
  nonzero net-zero remains eligible.
- Frozen clients and older backends degrade safely.
- New tests were written and observed failing before business logic.
- Backend unit/integration suites use only a confirmed local/test database;
  frontend tests pass; `flutter analyze` is clean.
- iOS and Android are accounted for and the required reviews complete.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — active-race impact notifications and 2× summary eligibility**

*Elements under test:* Active impact notification overlay — removed from completed-race open and added as a centered, full-screen overlay after an active race’s initial detail/progress load.

*Elements under test:* Foreground-resume impact notification — added over the still-visible active race detail screen; never added by the screen’s ordinary 30-second refresh.

*Elements under test:* Home `2× STEPS COMPLETE` overlay — remains centered over Home for eligible summaries, is absent for all-zero summaries, and remains present for mixed contributions whose net is zero.

*Elements under test:* Immediate powerup outcome overlays — remain in their existing centered, full-screen position and never share the screen with an impact notification.

*Checklist*

1. **Active race detail — initial open (real screen)**
   - **Get there:** On staging, use an account/race fixture with one resolved, unacknowledged impact notice → Races → Active → open that race.
   - **Verify:** The race detail screen loads first, then one impact notification appears centered as a full-screen overlay above that race. It is not embedded in Activity, the scoreboard, or the effect tray, and no copy remains in the old completed-race-popup location. If the fixture has multiple notices, only one overlay is visible at a time.

2. **Active race detail — iOS foreground resume**
   - **Get there:** On iPhone, open the seeded active race before its notice is eligible → background the app → let the fixture resolve the notice → return directly to Bara.
   - **Verify:** Bara returns to the same race detail screen and places the notification as the centered full-screen overlay above it. Leave the race visible through an ordinary refresh interval first and verify no overlay appears before the foreground resume.

3. **Active race detail — Android foreground resume**
   - **Get there:** On Android, repeat the seeded flow via Recents or device lock/unlock: keep the active race visible, background Bara, resolve the notice, then resume Bara.
   - **Verify:** Bara returns to that same race detail screen and places the notification as the centered full-screen overlay above it. It does not appear on Recents, over another route, or during an ordinary in-screen refresh.

4. **Completed race detail — every production entry path**
   - **Get there:** With one seeded completed race carrying a legacy/unacknowledged notice, open that same race in turn from: Races → Completed; Inbox alert; notification push; a Home race destination; a tournament matchup; Public Races/discovery; and a supplied direct/deep link.
   - **Verify:** Every path lands on the normal completed race detail screen with no impact overlay anywhere. Open Activity and verify the existing final numeric impact remains inside the Activity panel only; it is not duplicated as a popup.

5. **Immediate caster outcome modal — active race non-regression**
   - **Get there:** In an active race with a queued impact notice, use a powerup that produces an immediate reveal, such as a blocked/reflected attack, Coin Flip, or Mystery Potion. For the resume guard, background and resume once while that reveal is open.
   - **Verify:** The immediate outcome remains the sole centered, full-screen overlay in its existing position. The impact notification is not above, below, or simultaneously visible with it; after dismissal, overlays still appear one at a time rather than duplicated or stacked.

6. **Home — eligible nonzero 2× summary**
   - **Get there:** Use the staging fixture for an ended 2× event with at least one nonzero final per-race contribution → Home → pull to refresh.
   - **Verify:** `2× STEPS COMPLETE` appears as one centered modal over Home after the refresh. It does not appear embedded in a Home card or on another tab.

7. **Home — all-zero 2× summary**
   - **Get there:** Switch to the fixture whose final per-race contributions are all zero → Home → pull to refresh; also leave and re-enter Home once.
   - **Verify:** No `2× STEPS COMPLETE` modal appears anywhere on Home or another tab. There is no empty placeholder, card, or duplicate modal where the eligible summary appeared.

8. **Home — mixed contributions with net zero**
   - **Get there:** Switch to the fixture with nonzero positive and negative per-race contributions that balance to net zero → Home → pull to refresh.
   - **Verify:** The same single centered `2× STEPS COMPLETE` modal appears over Home. It is not suppressed or replaced by an empty Home position merely because the net is zero.

9. **Onboarding demo race mirror**
   - **Get there:** Sign in with a fresh onboarding-v3 account → reach “Learn how to race” → start the 90-second practice race.
   - **Verify:** The real race detail screen remains visible inside the demo with its coach chrome in the normal place and no unscripted impact notification covering it at open, during play, after a background/resume, or at the finish.

10. **Tab tutorial race-detail preview mirror**
    - **Get there:** Profile → Settings → View Tutorial → advance to the race-detail/powerups preview beat.
    - **Verify:** The reused race detail preview contains no impact overlay. The tutorial spotlight still rings the intended powerups element and is not covered or displaced by notification UI.

*Surfaces confirmed unaffected:* `RacesTab`’s hand-forked effect plates and inventory row are unchanged; the notification is a route-level overlay in `RaceDetailScreen`, not tray content.

*Surfaces confirmed unaffected:* `case_opening_screen.dart` and `multi_case_opening_screen.dart` remain separate pushed routes; no element is added to either screen.

*Surfaces confirmed unaffected:* Public Races, Home/Inbox/push routing, and tournament matchup screens do not copy the notification UI; each navigates to the shared production `RaceDetailScreen` and is covered as an entry-path checkpoint above.

*Surfaces confirmed unaffected:* The tutorial Home preview reuses `HomeTab`, but the 2× summary modal is owned by `MainShell`; the preview neither hosts that modal nor seeds `globalEventSummary`.

*Surfaces confirmed unaffected:* No tutorial `GlobalKey` anchor is moved by this feature; only an accidental overlay could obscure a spotlight, covered by the tutorial checkpoint.

*Risks found while planning:* The new active-notice service methods need explicit empty overrides in both `DemoRaceApiService` and `TutorialPreviewBackendApiService`; otherwise the shared production screen can leak a real request or an unscripted modal into demo/tutorial.

*Risks found while planning:* `RaceDetailScreen.didPopNext` and app foreground resume currently converge on `_refreshAfterCoverage`. Fetching notices from that shared path could incorrectly show them after returning from case opening or another child route; delivery must distinguish true foreground resume from route uncover.

*Risks found while planning:* Starter-reward and immediate powerup outcome dialogs already originate from race detail. The current impact guard tracks only impact notices, so implementation needs a shared modal/route guard to prevent stacking when an open or resume coincides with another dialog.

*Risks found while planning:* A notice response can return after navigation or after an active race becomes completed. Route visibility, race identity, current status, and generation must be rechecked immediately before placing each overlay.

*Risks found while planning:* `_fetchRaceCard` currently invokes the 2× summary directly from `MainShell`, including cold-start/resume loads, without an obvious current-Home-tab guard and outside the main Home overlay coordinator. That can place the Home modal over another tab or race-results overlay unless implementation serializes and Home-gates it.

*Risks found while planning:* iOS lifecycle can emit `inactive` around system overlays, while Android commonly uses `paused`/`hidden`. Only a genuine visible `resumed` transition should place the notice, once, on the still-current race route.

## Open questions

None.

## Revision log

- **Gap pass 1:** separated active snapshots from immutable final impact rows;
  added terminal-race recheck, stale-response/modal guards, old-client flag
  mitigation, account deletion, and explicit preservation of Activity.
- **Gap pass 2:** prevented the tempting but incorrect `aggregate != 0` Home
  filter by specifying a per-race nonzero-existence predicate; added existing
  bad-row filtering, mixed net-zero coverage, deep-link parity, retry isolation,
  lifecycle resume behavior, and a numeric-finality interview gate.
- **User interview 1:** selected guaranteed-final numbers, open/foreground
  delivery only (never ordinary polling), and every nonzero score-changing
  recipient. Follow-up evidence found that the current ingestion contract
  cannot guarantee expiry-time sample finality, so the remaining feasible
  finality choice is recorded above.
- **User delegation:** delegated the remaining UX choice. Selected immediate,
  immutable `SYNCED_SNAPSHOT` feedback on the next open/resume with honest
  `synced steps` copy; completed Activity remains the authoritative final record.
- **Post-interview gap pass 1:** added instant-effect coverage, committed
  resolution-generation/version provenance, retry isolation, and an explicit
  rule that notification calculation never mutates authoritative scores.
- **Post-interview gap pass 2:** required a durable `ALL_ZERO` job-run outcome
  plus an already-processed exclusion/metric so ineligible groups neither mint
  summaries nor cause repeated duplicate processing; preserved mixed net-zero
  summaries and existing-row read filtering.
- **Architect review:** separated legacy popup gating from the shared private
  Activity flag; replaced unfenced post-commit computation with durable work
  processed inside a stamped resolution generation; added an exhaustive source
  matrix, immutable provenance columns, concurrent/crash handling, Postgres-only
  delivery state, Home cache-key v2/invalidation/Redis fallback, concrete
  query-command-route ownership, and cascade/account-delete lifecycle rules.
- **Architect suggestions:** filter valid notices before the three-row cap and
  added crash, concurrent-sync, terminal-between-GET/ack, mixed-version, and
  old-backend tests.
- **UI-placement review:** added the verbatim manual checklist and made its
  risks implementation requirements: distinguish foreground resume from route
  uncover, serialize race overlays, recheck stale responses, Home-gate the 2×
  modal, and override demo/tutorial API calls.
- **Post-review gap pass 1:** removed unnecessary source IDs from the public
  response, added a durable `SUPPRESSED_TERMINAL` work outcome, and required
  terminal transition cleanup without touching final Activity.
- **Post-review gap pass 2:** closed the race between “next open” and async
  resolution by requiring one notice fetch after the existing bounded
  generation handoff, without adding a notice poller or ordinary-refresh
  interruption.
- **Architect re-review:** defined the capability-gated 202 resolution handoff,
  moved transition/work processing under the existing C0 race fence, routed
  direct multi-recipient notification materialization through the queue,
  enumerated every early effect-resolution boundary, clarified the delegated
  no-duplicate recipient policy, and specified default-off/disable/re-enable
  work semantics.
- **Architect re-review 2:** kept every affected recipient eligible while
  tracking exact inline outcomes separately, preserved synchronous
  Cleanse/true clamp behavior with atomic effect+work writes, and distinguished
  status-only resets from actual scoring-window termination.
- **Architect re-review 3:** made work recipient-scoped for independently frozen
  Leech participants and replaced unsafe server-assumed inline delivery with an
  opaque receipt acknowledged by the client only after actual UI dismissal.
