# Immediate daily/weekly Join and earlier cohort preparation

Status: DRAFT — joining and step-proration decisions resolved; awaiting spec
approval. No implementation or
deployment is authorized by this document. User approval precedes architect
review under this repository's AGENTS.md workflow; required architect changes
must be resolved before implementation.

Prepared: 2026-09-09. Source baseline: frontend `648e4fe`, backend `cd46d1a`.
Backend paths refer to the separate backend repository. Supporting research:
[findings](daily-weekly-immediate-join-findings.md).

## 1. Summary and user story

As a player, I can tap Join on the daily or weekly challenge and immediately
enter the currently running challenge. My scoring begins when I join. Preparing
groups before midnight never removes this ability.

As an operator, I can prepare weekly groups at 11:15 PM Sunday ET and daily
groups at 11:30 PM ET, leaving less bulk database work for midnight activation.
Late arrivals use incremental admission rather than rebuilding existing groups.

### Confirmed by the user

- Join means current challenge, immediately, for BOTH daily and weekly.
- Only post-join steps count; do not add earlier day/week totals.
- Earlier preparation cannot create an enrollment blackout.

### Resolved product decisions

**Group placement:** fill existing groups with room first; create overflow only
when all existing groups are full. The user accepted that the first entrant in
an overflow group can initially be alone. Later entrants reuse its available
space; do not create a separate group for each arrival. Preserve the current
hard caps rather than overfilling existing groups. Users already racing keep
their groups and scores. Late joiners do not receive a fresh 24-hour/seven-day
race; they share the current ET deadline.

**Step precision:** the user selected proportional scoring for a health sample
that crosses the join instant. Count only the estimated post-join overlap, not
the entire earlier interval. Retain the existing proportional scoring policy;
no sample-exclusion branch or new scoring-version stamp is required.

Automatic enrollment remains unchanged for users with that setting on. This
preserves existing behavior; the manual Join choice does not change the setting.

Other recommended defaults for approval with the spec:

- A successful Join changes the existing button to View; it does not force
  navigation away from the browser. View opens the assigned race.
- Preserve existing prize policy, hard group caps, and powerup rules.
- Manual Join does not toggle future automatic enrollment or award signup gifts.
- A deliberate forfeit remains terminal for that challenge window. A system
  inactivity prune does not permanently prevent an explicit return.
- Keep ET day/week boundaries, including DST, regardless of device timezone.

## 2. Scope and non-goals

In scope: shared current-window admission; incremental upcoming enrollment
after preparation; durable bounded preparation/recovery; separating activation
from future preparation; truthful current Join UI; compatibility; concurrency,
scoring, and performance validation on both platforms.

Non-goals: change group size targets/caps, prize amounts/formulas, friendship
matching policy for the initial batch, race deadlines, private-race join rules,
team/tournament admission, infrastructure capacity, system log rotation,
unrelated retention jobs, or add release flags/runtime controls. No artwork or
new screen is required.

The global-event scheduler, step intake, race expiry, and settlement retain
their actual deadlines. This feature does not impose a blanket pause on all
background jobs between 11:50 PM and 12:10 AM.

## 3. Existing implementation and the change required

| Source | Current behavior | Required change |
| --- | --- | --- |
| Frontend `lib/services/backend_api_service.dart:3787` | `/assign` always sends UPCOMING | Add a distinct current Join method; retain the old method. |
| Frontend `lib/screens/public_races_screen.dart:262,886` | Join elects into upcoming; ELECTED hides current Join | Use additive current-window projection independently of future election. |
| Backend `src/modules/races/routes.js:1281` | `/assign` returns 202 and null race ID | Retain upcoming contract; add current Join route. |
| `src/modules/races/services/seededRaceBuckets.js:574,936` | Elections close when groups exist; current/future card states mixed | Separate admission, preparation, and projection; allow late upcoming assignment. |
| `src/modules/races/commands/autoEnrollNewUser.js:76,172,475` | Signup fills ACTIVE cohorts or overflow | Extract admission mechanics; preserve signup-specific gifts/settings. |
| `src/modules/races/jobs/seededRaceRenewal.js:552–715` | One minute pass finalizes, promotes, then prepares future races | Split due lifecycle work from durable future preparation. |
| `src/modules/races/queries/getRaceProgress.js:444` and `services/raceStateResolution.js:83` | Score from max(joinedAt, startedAt) | Preserve and verify through HTTP/display/settlement. |
| `src/modules/steps/models/stepSample.js:587` | Proportional interval overlap | Preserve, as selected by the user. |

Private groups remain private: `joinPublicRace.js:68` must continue rejecting
unassigned private race IDs. Do not turn private groups into public races.

## 4. Product behavior and invariants

### 4.1 Current manual admission

1. The server resolves `DAILY_10K` or `WEEKLY_50K` to the current ET window.
2. An existing accepted membership returns the SAME race and original join
   instant, regardless of retries or client version. No second reward or join.
3. Otherwise assign available capacity using the server-controlled policy in
   section 7. A full individual group is not a reason to reject challenge Join.
4. If all eligible groups are full, create or reuse capped overflow. If a
   current window has no materialized groups, bootstrap bounded capacity using
   the seed's policy; never wait for the next daily/weekly window.
5. Return success only after membership is durable and the assigned race is
   active and accessible. Infrastructure failure gets a retryable error, not
   a fake enrollment success.

The effective join instant is server time re-read inside the admission
transaction after lifecycle/membership locks. A request that waits across the
boundary resolves against the new window; if its transaction can no longer
commit inside the selected window, roll back and retry selection. Clamp score
end to that race's stored deadline.

A returning player with an upcoming election still sees Join for the current
window. Joining now does not change their upcoming election.

### 4.2 Late upcoming and automatic enrollment

- The existing `/assign` UPCOMING request retains its meaning and response.
  Before preparation it durably elects; after preparation it durably allocates
  to an upcoming PENDING group or records a bounded materialization task.
  Finalized groups are no longer an enrollment rejection condition.
- Preparation does not change the auto-join setting. Turning auto-join on
  still takes effect for the next challenge; manual Join is how an existing
  user enters the current challenge. Turning it off stops future elections;
  it does not silently revoke already accepted/elected entries.
- Retain eligibility/inactivity filtering for automatic enrollment. Explicit
  current Join is affirmative participation and bypasses the automatic
  inactivity filter for that current membership only.
- Late pre-boundary elections must not be lost if materialization retries
  after midnight. Their scoring start remains the scheduled start, not the
  later recovery time. Users first requesting current Join after the boundary
  start at their actual admission time.
- Signup retains its current preference default, both-cadence attempts,
  review-account exclusion, welcome-box ledger, and best-effort auth behavior.
  A manual Join never invokes those unrelated effects.

### 4.3 Pruning, leaving, and privacy

Keep existing cohort identities and accepted members stable. No global
repacking when someone joins. Preserve both unique seed/window/user constraints
in membership and assignment, including legacy stream coexistence.

An explicit current admission receives source `MANUAL_CURRENT`; skip subsequent
automatic inactivity pruning for that membership during this window. This does
not exempt the account from future automatic eligibility checks.
Recheck that exemption inside BOTH promotion-prune and active weekly-sweep
transactions after the race/user locks; filtering an earlier candidate list
alone races with manual reactivation.

For a system-PRUNED assignment with no scored/finished/forfeited participation,
manual Join may reactivate the original cohort if it has room. Use a fresh
join instant and reset only empty/pruned initialization state. If the cohort
is full, admission may transfer this inactive slot to another cohort with an
immutable audit event recording old/new participant and assignment identity.
The old participant remains DECLINED. Change assignment and membership
atomically under both race locks. Never use this exception for forfeits,
completed races, or accepted members; no score/effect/box transfer or repeat
welcome award. Tests must prove the prune classification cannot be forged.
Determine empty/pruned from authoritative raw activity AND the existing
caster/target powerup, event, and box guards, not `totalSteps == 0` alone:
scoring can lag. Unexpected entangled PRUNED state gets a durable membership
repair task and retryable CHALLENGE_JOIN_BUSY, not silent erasure/transfer or
a permanent eligibility rejection. Repair revalidates the original prune via
the existing resolution path before admission retries. This is a corrupt/stale
state recovery, not an ordinary restriction on joining.
Reconcile old/new funded-exposure reservations through the existing helpers
under both race fences and user guards; no duplicate reservation or carried
participation reward. All monetary stamps continue to come from the assigned
race, never copied from a client request.

Membership disclosure remains viewer-scoped. Current Join accepts no race ID,
group ID, opponent list, history override, score, timestamp, or reward input.

## 5. API contract

### 5.1 Add POST `/races/seeded/:seedKind/join-current`

Authenticated; same account/review protections as existing challenge routes.
New endpoint only. Body:

```json
{ "requestId": "a-client-generated-uuid" }
```

The client generates one ID per deliberate Join attempt and reuses it on
network retry. A committed receipt pins seed, window, membership, and join
instant. Reusing the ID for another seed is 409. A retry after midnight must
not create a second entry in the new day. A separate tap for a newly displayed
window gets a new request ID. Natural membership uniqueness protects callers
that generate multiple IDs within the same window.

HTTP 200 for newly joined, already joined, and receipt replay:

```json
{
  "joined": true,
  "alreadyJoined": false,
  "seedKind": "DAILY_10K",
  "raceId": "assigned-race-id",
  "participantId": "assigned-participant-id",
  "windowStart": "2026-09-10T04:00:00.000Z",
  "windowEnd": "2026-09-11T04:00:00.000Z",
  "joinedAt": "2026-09-10T18:05:00.000Z",
  "scoringStartsAt": "2026-09-10T18:05:00.000Z",
  "raceStatus": "ACTIVE"
}
```

`alreadyJoined` is true for existing membership or receipt replay. An expired
receipt replay returns the original race/instants and its current lifecycle
status (`ACTIVE` or `COMPLETED`), never claims membership in a new window. If
the race has been administratively cancelled, use `CANCELLED`; the UI refreshes
the current card and gives factual feedback rather than claiming current entry.

Error shape:

```json
{ "error": "Could not join right now. Try again.", "code": "CHALLENGE_JOIN_BUSY", "retryable": true }
```

| HTTP | Code | Meaning |
| --- | --- | --- |
| 400 | INVALID_SEED_KIND | Unsupported challenge kind. |
| 400 | INVALID_REQUEST | Missing/malformed UUID or forbidden placement input. |
| 400 | UPDATE_REQUIRED | Caller lacks existing private-cohort support. |
| 401 | existing auth error | Preserve current authentication contract. |
| 403 | CHALLENGE_NOT_ELIGIBLE | Existing account restrictions, not inactivity. |
| 404 | SEED_NOT_FOUND_OR_DISABLED | Seed absent/disabled. |
| 409 | IDEMPOTENCY_CONFLICT | Request ID already bound to a different seed. |
| 409 | CHALLENGE_FORFEITED | Intentional forfeit in this current window; no group shopping. |
| 503 | CHALLENGE_JOIN_BUSY | Bounded contention/retry budget exhausted; Retry-After: 1. |
| 500 | INTERNAL_ERROR | Unexpected failure, no false success; request ID safe to retry. |

Capacity exhaustion, prior group preparation, and automatic inactivity status
are NOT error conditions for an otherwise eligible manual Join.

### 5.2 Additive current projection on featured cards

Add `currentJoin` to private challenge cards in `/races/featured`, compact
`/races/public?view=browser-v1`, and the shared discovery-summary representation
where cards are returned. Keep all existing fields, including `myStatus`,
`upcoming`, `raceId`, and old `ELECTED` semantics unchanged for frozen clients.

```json
{
  "seedKind": "DAILY_10K",
  "bucketPrivate": true,
  "myStatus": "ELECTED",
  "currentJoin": {
    "version": 1,
    "state": "JOINABLE",
    "windowStart": "2026-09-10T04:00:00.000Z",
    "windowEnd": "2026-09-11T04:00:00.000Z",
    "raceId": null,
    "participantCount": null,
    "scoringStartsAt": null,
    "reason": null
  }
}
```

States: `JOINABLE`, `JOINED`, `FORFEITED`, `UNAVAILABLE`.
JOINED includes the viewer's nonempty raceId, accepted participantCount, and
scoringStartsAt. FORFEITED may link only the viewer's race. UNAVAILABLE has a
stable reason such as `SEED_DISABLED` or `ACCOUNT_INELIGIBLE`; lack of a prepared
cohort is not UNAVAILABLE. No other cohort's count/ID/opponents are disclosed.
Unknown version/state/null/malformed fields degrade safely as section 9 states.

### 5.3 Retained contracts

- `/assign`: unchanged body default UPCOMING and successful 202 shape
  `{ "elected": true, "raceId": null, "finalizesAt": "..." }`.
  Its old success contract applies after preparation too; repeated elections
  are idempotent. No implicit CURRENT reinterpretation.
- `/me/featured-auto-join`: unchanged request/response; preserve preference
  durability and add durable late-election recovery in the write path.
- Legacy public Join/access remain compatible. Existing accepted LEGACY
  membership returns that race, never a second BUCKET membership. For an
  unassigned current-capable caller in a LEGACY-stamped window, the new endpoint
  may create/use a private CURRENT_JOIN_V1 group and claim BUCKET for that user.
  This is a separate per-user current-admission policy: do not rewrite the
  window's immutable legacy preparation mode or migrate accepted legacy users.
  It uses the same caps and stamped seed prizes as normal current admission.
  Such groups carry admissionVersion=1 and are discoverable only to members;
  old public/legacy callers continue on their historical public path.
  A preexisting legacy election without a participant is reconciled by the
  existing ledger policy before admission, never overwritten optimistically.
  Test simultaneous generic legacy Join versus current Join: exactly one
  ledger stream wins and the loser returns that accepted membership.

The new endpoint requires existing `seeded_race_buckets` support; an incapable
client receives 400 UPDATE_REQUIRED and continues using its existing endpoints.
No new client feature flag is introduced. For bucket-capable old clients, an
owned CURRENT_JOIN_V1 group uses the existing private-card shape/View behavior
even in a LEGACY window. Incapable clients retain the existing private-stream
visibility rules. Shared discovery must filter by ownership, not mode alone.

## 6. Data model and migration plan

Additive migration in the backend; no rewrite of historical races/prize stamps.

1. `SeededChallengeJoinReceipt`: userId + requestId unique; seedId, windowStart,
   windowEnd, raceId, participantId, joinedAt, createdAt. Membership/receipt
   commit together. Retain at least through windowEnd + 30 days; cleanup in the
   existing off-peak retention framework, bounded by indexed date/id pages.
   Cascades follow account erasure policy; never store health data in receipts.
2. Add nullable `admissionSource` and `manualJoinedAt` to window membership.
   Historical null preserves existing behavior. Accepted manual entries stamp
   MANUAL_CURRENT. Preserve original election `createdAt` for recovery.
3. `SeededChallengePreparation`: unique seedId/windowStart, windowEnd,
   preparationVersion=1, state, startedAt, planCommittedAt, completedAt,
   leaseToken, leaseExpiresAt, notBeforeAt, lastErrorCode, updatedAt. This is
   durable job/data state, not an environment control or release flag.
4. `SeededChallengePreparationGroup`: unique preparationId/ordinal,
   reservedRaceId/reservedBucketId, bounded group members with userId and
   matchSteps, state, materializedAt, createdAt. Daily payload <=35 users,
   weekly <=100; initial plan retains existing matching outputs. Store JSON
   with validation or a child membership table; final migration must select
   one representation, not support both. Proposed representation: validated
   JSONB members plus membership pointer below.
5. Nullable preparationGroupId on window membership, indexed with stream and
   raceId. Each elected user is reserved to at most one initial group; a current
   Join can materialize its reserved group without duplicating its membership.
6. Add monotonically assigned electionSequence to window membership and
   snapshotSequence to preparation. The window lock captures a high-water mark
   for the initial roster. UUID ordering or timestamps alone cannot distinguish
   pre-snapshot elections from concurrently arriving elections. Backfill the
   sequence additively, preserving membership createdAt and existing streams.
7. Nullable admissionVersion on SeededRaceBucket; new current-admission groups
   use 1. It records permanent creation semantics and has no environment switch.
   Historical null follows existing batch ownership rules. New preparation
   recognizes these groups and excludes already assigned users without
   treating their existence as proof that all elections are materialized.
8. `SeededChallengeEnrollmentRequest`: unique userId/seedId/windowStart; source,
   requestedAt, windowEnd, state, availableAt, leaseToken/leaseExpiresAt,
   attempts, lastErrorCode. Written transactionally with a relevant preference
   or durable capability/signup change. It contains the intended next window,
   so a pre-midnight accepted intent cannot become an election for the wrong
   day after a worker delay. Its worker claims bounded pages and creates or
   reconciles membership idempotently. Terminal rows use bounded off-peak
   retention after windowEnd + 30 days; failed current requests stay repairable.

Index receipt identity and expiry; index preparation state/notBeforeAt and
group preparationId/state/ordinal; reuse bucket seed/window/status and
assignment/membership uniqueness. Add a targeted membership-unassigned partial
index if its EXPLAIN plan shows a benefit. Migration requires local old-code /
new-schema validation; no destructive enum changes or required old-client data.

No authoritative capacity counter or Redis dependency is added initially.
Capacity is accepted RaceParticipant rows under the race write fence. New
indexes and bounded queries must meet section 11 load gates before rollout.
Enrollment request indexes cover state/availableAt/id and lease expiry. The
request row is the retry mechanism named in section 7.3; do not persist the
preference first and attempt to add its only recovery record afterward.

## 7. Backend implementation design

### 7.1 Shared admission service

New `src/modules/races/services/seededChallengeAdmission.js`, wired from a new
`commands/joinCurrentSeededChallenge.js`, signup, and late upcoming admission.

- Read seed/window policy and existing membership/receipt first. A read-only
  common retry avoids matching/history work. Validate lifecycle before response.
- Current-window selection is server-controlled. Prefer existing capacity;
  rank a bounded shortlist by historical skill proximity, then available
  capacity, then stable race ID. Initial batch friendships remain unchanged;
  late Join does not rebuild friend components or promise friend placement.
- Compute only the joining user's historical match value outside locks using
  the existing matching window. Store it with the assignment; do not stamp
  returning users as zero-history signups. No scan of all users' step history.
- Candidate query is one parameterized, window-scoped SQL statement returning
  at most 8 eligible groups with accepted counts and an aggregate match value.
  Use existing indexes and a set-based/LATERAL bounded-per-cohort count; do not
  fetch every race/participant into Node. SQL may still examine several groups;
  EXPLAIN/load measurement must include that cost, especially all-full windows.
  The match value is derived from stored assignment matchSteps, not fresh
  population-wide health reads. Include reserved-but-unmaterialized capacity
  in overflow arbitration; materialize a chosen eligible reserved group rather
  than create redundant overflow beside it.
- Up to three candidate/transaction retries per request. Each failed candidate
  attempt rolls back before selecting another. Busy never means falsely full.
- Under universal order: sorted race write fences → global-event enrollment
  lock → sorted user guards → sorted competition rows → seeded window lock.
  Re-read window, membership, accepted count, and seed/policy; create membership,
  assignment, participant, and receipt atomically. Do not acquire these locks
  in reverse from a new window-first admission transaction.
- For a new overflow group, provision its IDs/empty race in the transaction,
  take universal locks, then the window lock, and recheck available capacity
  including concurrent materialization before committing. If capacity appeared,
  roll back and reuse it. Never create a new group merely because the shortlist
  raced with another Join. Await only database work while holding these locks.
- Initialize the participant's box threshold in the insert. Use existing
  seeded prize/exposure policy, not user-created limits. Preserve global-event
  eligibility using the actual admission instant; enqueue one race-resolution
  request within the transaction. Perform existing list/Home/progress cache
  invalidation and notification side effects after commit, with durable retry
  where already supported. Receipt replay does not duplicate them.
- If a user's membership is reserved to an unmaterialized preparation group,
  materialize only that bounded group and activate if due. Pre-elected members
  retain start-of-window scoring; a new current joiner starts now.

### 7.2 Durable preparation without a midnight full rebuild

New `services/seededChallengePreparation.js` and
`jobs/seededChallengePreparation.js`.

The initial plan is built outside membership locks from a stable election
snapshot using existing `planBuckets` and match history. Under a short
window-only transaction, claim the preparation lease and record the maximum
electionSequence. Do not acquire race/user/global locks later in that
transaction. Initial planning includes only BUCKET memberships up to that mark
without an assigned race. Later elections enter an incremental lane and do not
force a population-wide planning retry.

Materialize one group per transaction under universal lock order. Each group
creates its race, bucket, participants, assignments, links, and membership race
IDs atomically, with deterministic reserved IDs. A crash before commit retries
the same group; a crash after commit sees materialized identity. A failed group
does not roll back already prepared groups or require a population-wide retry.
Never report the window complete while reserved/elected members are stranded.

Page membership/election reads at 500 users and write plan groups in bounded
chunks, with a durable cursor and an unpublished/planning state until all plan
groups and reservations are coherent. Use preparation generation and stable
group ordinal to upsert one bounded group plus its membership pointers per
transaction under the window lock. Persist the cursor in that transaction.
Exclude any member already admitted by the current Join recovery lane and
never replace its raceId. A resulting undersized recovery group is preferable
to moving accepted racers; ordinary early preparation retains balanced groups.

Publish PLAN_READY only after a bounded-page completeness check confirms every
eligible snapshot member is either reserved exactly once or already assigned.
Materializers cannot consume an unpublished plan. A changed lease token fences
every write; takeover resumes the same persisted generation and cursor. It may
discard an unpublished generation only after clearing its pointers in bounded
transactions, and no materialization is permitted until the cleanup finishes.
Published plans are never discarded or repacked. No transaction writes the
entire population's reservations. The architect reviews this protocol before
implementation.

During unpublished current-window recovery, explicit Join must not wait for
the whole plan: it can directly admit its user under universal locks, then
remove only that user's unpublished reservation under the window lock. The
planner/completeness pass reconciles the excluded user. All other pre-elected
users remain durable and eligible for their scheduled-start scoring.

Late post-plan elections allocate into reserved or materialized PENDING room
without changing existing group assignments; if reserved room is used, update
its payload/reservation under the same window lock before materialization.
No generic finalizer early-return based on `bucketCount > 0` may strand these
entries. Existing historical `finalise` tests can remain as tests of the old
batch-only seam; test the new admission/preparation public path separately.

Missing current plan/groups after a crash: urgent recovery materializes bounded
reserved groups and handles unassigned durable pre-boundary elections; manual
Join may create current capacity without forcing a full plan in HTTP. Recovery
must exclude those newly assigned members, preserving all prior cohorts.

### 7.3 Scheduler separation and work reduction

| Schedule (America/New_York) | Responsibility |
| --- | --- |
| Sunday 23:15 | Begin weekly upcoming preparation. |
| Every day 23:30 | Begin daily upcoming preparation. |
| 23:50–00:10 | Defer bulk preparation of farther-future windows; current/boundary recovery and incremental admissions continue. |
| Midnight / every minute recovery tick | Promote due prepared races with stored midnight anchors. |
| 00:10 onward | Resume bounded future enrollment/reconciliation. |
| All day | Immediate current Join; persist incremental upcoming elections. |

Use ET calendar helpers, not fixed UTC offsets or 24-hour arithmetic. Weekly
start remains Monday midnight. Schedule jobs by `notBeforeAt`/window identity
so a restart after the intended minute catches up; no equality-to-minute gate.

Separate renewal phases: first all due activations across seeds, then urgent
missing current memberships, then due preparation tasks. Single owner, no
overlapping ticks. Stop starting nonurgent work when due lifecycle work exists.
Use one materialization transaction at a time; do not increase PM2 workers or
pool limits. The deployed topology stays two HTTP workers, one cron, one
resolution worker.

Replace per-participant missing box-threshold updates with one predicate-safe
update per promoted race. Use set-based race links and membership updates per
materialized group. Keep boundary-time inactivity assessment correct: the two
completed ET days change at midnight, so it cannot simply move to 23:30.
Batch these reads for bounded due groups and apply changes under fences.

Bulk auto-enrollment repair must use bounded keyset pages and select only
unclaimed users; it must not repeatedly load all opted-in users each minute.
Capture new eligibility/elections promptly in settings/signup/capability paths,
and persist a retry record in the same preference update transaction when
best-effort enrollment cannot finish. A bounded reconciliation pass is the
backstop for missed changes, not the only way a last-minute opt-in is captured.
Do not add extra database work to every step sync just to service this job.
Integrate capability intents with `users/services/clientFeaturesWriteBatch.js`
only when persisted capability changes, batching their inserts with the change.
Wire signup through `ensureAppleUser.js` and `ensureGoogleUser.js`; reuse their
existing account setup boundary. Settings changes go through users/routes.js
and the User model's cache invalidation contract. Processing an old ON intent
after OFF must preserve an already committed election but must not mint future
elections beyond that intent's exact window.

The earlier times become permanent defaults only after the full path passes
tests/load validation. Ship the working admission and scheduler change together
in the backend; deploy backend before either app. No clock-only early-cutoff
change is an acceptable partial release.

## 8. Scoring and economy

Use the server's committed joinedAt; client timestamps cannot backdate entry.
Pre-enrolled users score from window start; manual late entrants score from
their later join instant. Preserve delayed sample correction, timezone handling,
step-based effects, box thresholds, and settlement/display parity.

Under the confirmed proportional policy, no new scoring version is needed.
Carry the same join boundary through prefetch, Home, detail, resolution,
effects, and settlement. Do not retrofit older participants or merely filter
the frontend counter.

Keep stamped payout versions and existing caps (daily 35, weekly 100). No
join-time payout proration or new minimum-walking threshold is introduced.
Existing policy permits a late positive-scoring entrant to contribute to the
full-duration funded pool. Small overflow groups can be easier competition;
solo groups do not guarantee a funded prize. These are explicit tradeoffs,
not evidence that immediate admission is exploit-free.

Prevent duplicate seed/window membership, client-picked opponents, arbitrary
reassignment, repeated welcome rewards, and forfeit/rejoin resets. Update the
economy document with actual unchanged policy and this admission effect after
game-analyst review; do not copy superseded prize constants from old prose.

## 9. Flutter implementation plan (iOS and Android)

Keep the established arcade card, strip height, typography, and action location.
No second challenge card, new tab, modal, or new graphics.

- Add a defensive typed current-join parser/result (new
  `lib/models/seeded_challenge_join.dart`), plus
  `joinCurrentSeededChallenge` in `backend_api_service.dart`. Keep
  `assignSeededRaceBucket` and its tests for old UPCOMING behavior.
- The currentJoin projection is authoritative for updated private cards.
  JOINABLE shows Join even if old `myStatus` is ELECTED. JOINED shows View using
  the viewer's race ID. FORFEITED shows the existing own-race destination or a
  non-join action; no second entry. UNAVAILABLE/malformed state shows a stable
  unavailable action and readable feedback, never a guessed public Join.
- Missing currentJoin on an older backend: preserve View for a known accepted
  existing race. For an unassigned private card, do not silently enroll for
  tomorrow; show unavailable feedback and allow refresh. Legacy public cards
  retain the existing generic Join path. New current endpoint must be verified
  in production before app release, so this fallback is exceptional.
- A tap sets loading in the same button; disable repeated taps for that seed.
  Persist the attempt ID in account/window-scoped in-memory state for network
  retry while this screen lives. A result with a valid assigned race updates
  the current card immediately, then refreshes discovery. A failed refresh
  must not erase the committed success or replace it with an older pending
  response. Missing required success fields triggers reconciliation rather
  than a success toast or an unchecked cast.
- Scope requests/results to authenticated user, seed, window, and screen
  generation. Ignore responses after logout/account switch/disposal or a newer
  generation. Clear stale request IDs/current overlays when the window changes;
  an in-flight old receipt cannot overwrite the new window's card.
- Refresh/reconcile on resume and successful Join. VIEW opens the existing race
  detail. If the receipt's race ended while the request was in flight, refresh
  current state and report that membership accurately; never reuse its success
  to claim current-window enrollment.
- Preserve Home suggestion layout and generic join coordinator; inspect their
  routing so seeded private Join is never dispatched through public race IDs.
  Home Browse links render the same PublicRacesScreen.
- Update test/demo services only where consumed. No fake fixture should make a
  real network request. Tutorial's currently unused Featured fixtures must not
  accidentally introduce a duplicate strip.

## 10. Exact implementation sequence and ownership

After user approval and architect review, invoke exactly the backend-developer
and frontend-developer agents prescribed by the skill; do not start code now.

1. Backend agent owns backend migration, model, HTTP, admission/preparation,
   scheduler, and tests. First write failing real-HTTP tests for the contract
   and lifecycle cases below. Lock the additive contract and parser fixtures
   before frontend implementation begins.
2. Add migration/models and durable receipts/preparation; validate old runtime
   against new schema locally. Wire current admission and preserve `/assign`.
3. Share mechanics with signup/settings/recovery, including source stamps and
   exactly-once side effects. Add red concurrency tests before business logic.
4. Implement bounded durable preparation and scheduler separation; test missed
   tick/crash recovery before moving scheduled times. Replace looped writes.
5. Frontend agent owns model/API adapter/public browser/widget fixtures and
   real widget tests on both platforms. Start after contract lock; parallelize
   with remaining backend work. Follow section 9 exactly.
6. Run focused integration suites on a confirmed dedicated test DB, then
   `npm run test:unit` and appropriate broader integrations (never bare
   `npm test`). Preserve existing assertions; surface conflicting tests.
7. Run `flutter analyze` clean and full `flutter test`; diagnose failures with
   the failing suite only. Run the manual checklist in section 13.
8. Code-reviewer reviews combined implementation, version skew, and tests.
   Resolve required issues before presenting implementation as complete.
9. Request fresh production deployment authorization separately. Backend first;
   verify contracts/readiness in prod, then matching iOS and Android releases
   only when authorized. Read README before each build/upload.

Principal backend files: routes.js; new commands/joinCurrentSeededChallenge.js;
new services/seededChallengeAdmission.js and seededChallengePreparation.js;
new jobs/seededChallengePreparation.js; services/seededRaceBuckets.js;
jobs/seededRaceRenewal.js; commands/autoEnrollNewUser.js and
autoJoinFeaturedRaces.js; users/routes.js and durable capability/signup hooks;
queries/getFeaturedRaces.js; shared discovery serialization; prisma/schema.prisma
and migration. Existing race fence, global enrollment, exposure, cache, and
resolution helpers remain the integration surfaces.

## 11. Tests-first acceptance criteria

### Backend real HTTP / real DB

New integration suites: `seeded-current-join.test.js`,
`seeded-early-preparation.test.js`, and `seeded-join-version-skew.test.js`.
Use real handlers and DB, injected clock only at the application scheduler seam;
do not import internal admission/scoring utilities to bypass the public path.
Pure matching/date tests may supplement, never replace, these cases.

- A1: Unassigned daily/weekly Join at noon immediately returns an accessible
  ACTIVE race; subsequent GET featured/home/detail agree. Auto-join off stays off.
- A2: Before/after 23:15/23:30/23:55, same-day Join stays available. Future
  election never hides current Join. UPCOMING still means next day/week.
- A3: Current member double tap, two devices, signup+manual race, receipt retry
  after lost response, and receipt retry after midnight yield no duplicates,
  backdating, repeated gifts, or cross-window phantom success.
- A4: Concurrent last-slot and all-full joins respect caps and reuse one
  available overflow. Recheck database state and received response, not mocks.
- A5: No current groups, partial materialization, lease takeover, failure before
  commit/after commit, and restart after scheduled time recover every durable
  election exactly once. Late recovery preserves pre-elected start-time credit.
- A6: Stale ACTIVE ended race and lock wait across midnight never admit into an
  expired window. ET DST transitions and Sunday/Monday boundary are covered.
- A7: Signup still gets its once-per-human gifts and default settings. Manual
  Join does not. No new funded-exposure denial for guaranteed seeded admission.
- A8: System-pruned return works without exceeding capacity or losing audit;
  forfeit/completed/accepted rows cannot exploit that path. Manual membership
  survives automatic inactivity sweep for its current window only.
- A9: Automatic enable late after prep and just before midnight is durable;
  disable does not revoke accepted membership. Capability upgrades, LEGACY
  stream, current plus next membership, and missed repair pages do not duplicate
  or strand users. Old code/new schema and frozen old request headers tested.
- A10: Real pre-join sync → Join → post-join sync → Home/detail → settlement
  agree on join-forward score and payout. Include five-minute/hourly crossing
  samples with proportional overlap, delayed replacements, no samples/daily-only, buffs, leech,
  global events, and box awards. No retroactive grants or pre-join event credit.
- A11: Guessed private IDs remain denied; receipt access is user-scoped; invalid
  request fields cannot choose opponents or backdate joins.

Relevant existing suites retained: seeded-race-buckets, seeded-race-window-modes,
seeded-bucket-election-ordering, seeded-challenge-payouts-inactivity,
featured-auto-join, public-join-box-window, five-minute-step-samples,
global-event enrollment/scoring, and API compact/discovery tests.

### Frontend real widgets

Extend `test/public_races_featured_strip_test.dart` with new-contract fixtures.
**Existing-test conflict requiring explicit approval with this spec:** the test
`private virtual bucket elects once and becomes pending` currently asserts the
exact behavior being replaced: JOIN calls UPCOMING, then no VIEW appears.
It cannot remain an expectation for the updated current-Join screen. Approval
must specifically authorize updating that behavioral assertion to immediate
current admission and VIEW; do not silently weaken/delete/skip it. Keep the
separate old `/assign` API tests and add frozen-request compatibility tests.
All other existing assertions remain protected. Assert
JOIN → loading → VIEW, pending upcoming plus current Join, already joined,
timeout/retry, stale refresh, stale window/account responses, missing/unknown
fields, and both navigation entrypoints. Test fake/demo isolation. No weakened
existing assertion just to make the changed behavior pass.

### Performance acceptance

Use dedicated local/test DB only; verify its identity before integration/load
tests. Compare baseline/candidate with the same fixtures and traffic: at least
1,000 and 5,000 users, daily+weekly coincident boundary, concurrent step sync,
last-slot/full-group joins, and cold recovery. Account for all downstream jobs.

Record SQL calls/writes/rows scanned, lock wait and transaction p95/p99, worker
queue age, HTTP Join/step-sync latency and errors, preparation duration, and
database CPU. The normal preparation plan must finish before 23:50 at tested
scale; no population-sized SQL loop or transaction in HTTP admission; no
regression in step-sync errors/latency relative to equivalent baseline. Show
measurable reduction in midnight SQL/lock work before claiming improvement.
Failed performance gates require optimization and re-review, not more workers.

Production verification after authorized deployment is observational: compare
actual traffic/cohort sizes and job timings. Do not claim 70% idle from a brief
quiet sample. No load tests, test users, or mutation probes against production.

## 12. Backward compatibility and release

Additive schema first; new code tolerates old null rows. New backend retains
old UPCOMING, public legacy, and response fields. No existing completed data or
prize stamps change. Shared ledger protects duplicate entry during mixed
versions. A rollback leaves durable rows available for compatible recovery;
never drop preparation/receipt data as part of rollback.

Before release, validate running old/new workers against the new schema and
the transition from old finalizer to new preparation owner. Use the existing
single cron owner and transaction fences; an old finalizer seeing materialized
buckets must not repack them. If an older worker can still strand reserved
members, deployment must drain that worker before admitting the new preparation
protocol. This is an ownership handoff, not a new release flag.

Fresh production approval covers backend deployment only. Verify GET/POST
contract availability and healthy queues before building/releasing the new
app. README defines release configuration; both platforms must be verified.
The app cannot depend on a brand-new production field without that check.

## 13. Manual UI-placement test plan

**Manual UI-Placement Test Plan — Daily/weekly immediate join**

*Elements under test:*  
Daily/weekly Featured card action: Join → loading indicator → View, within the existing button position.  
Current participation display: upcoming enrollment must not replace or obscure the current challenge’s action.  
Unavailable/error feedback: appears without hiding the card or adding a duplicate action.

*Checklist*

1. **Public browser — real screen**
   - **Get there:** Races → Public Races → Featured, using an account without current daily/weekly participation.
   - **Verify:** Auto-join settings remain above the Featured header; daily/weekly cards remain before tournament cards. Each challenge has one action at the bottom of its card. No duplicate Featured strip appears on the Races tab.

2. **Public browser — joining states**
   - **Get there:** On those daily and weekly cards, tap Join; use a local/test account enrolled for an upcoming window but not the current window.
   - **Verify:** Loading and View occupy the original button location without shifting the strip. Upcoming enrollment does not cover or replace the current Join action. Cards do not gain a second action elsewhere.

3. **Public browser — unavailable/error state**
   - **Get there:** Use a local/test build with missing `currentJoin` data, then a simulated join failure.
   - **Verify:** The card and its action area remain visible; feedback is readable and does not overlap the button or bottom navigation. No stray success action or duplicate card appears.

4. **Home discovery and browser entrypoints — real screen**
   - **Get there:** Home → race suggestions; also open Public Races through Home’s Browse/Browse All entrypoint and trailing public-race card when present.
   - **Verify:** Suggestion actions remain within their cards; any loading state stays in that action position. The browser presents the same Featured strip arrangement as the Races entrypoint. Home does not gain a duplicate Featured strip.

5. **Tab tutorial — shared Home/Races screens**
   - **Get there:** Profile → Settings → View Tutorial → Home and Races preview beats.
   - **Verify:** Home’s suggested-race cards and their action areas remain visible in their established positions. The Races preview does not acquire a duplicate Featured strip. Existing spotlights still surround their intended widgets.

6. **Both platforms — constrained layout**
   - **Get there:** Repeat the Featured strip and Home suggestion checks on iOS and Android, including a small device with enlarged system text.
   - **Verify:** Join, loading, View, and unavailable states stay within the cards; horizontal scrolling reaches both daily and weekly cards. No clipping, overlapping actions, or displaced tournament cards.

*Surfaces confirmed unaffected:*

- Demo race tutorial: `demo_race_host.dart` renders create/invite/race-detail screens, not the Featured browser.
- Tutorial race-detail preview: renders `RaceDetailScreen`; no Featured card or current-join action is embedded.
- Real race detail and box-opening screens: existing destinations; this proposal adds no placement changes there.
- Tutorial’s hand-copied tab bar and demo coach chrome: no tab order, anchor, or coach placement changes proposed.
- Races-tab effect plates/inventory: no shared widgets with the affected Featured card.

*Risks found while planning:*

- `FeaturedRaceCard` renders only in `public_races_screen.dart`. `RacesTab` retains unused Featured parameters, which can mislead implementation or testing into checking the wrong surface.
- Home suggestions use a separate renderer and join coordinator; browser checks alone do not cover that entrypoint.
- Tutorial Featured fixtures lack `currentJoin` and use noncanonical daily/weekly seed values. They are currently unused by the Races preview; if newly consumed, they must be updated.
- Public Featured cards have a bounded strip height. Additional status text could clip or displace the button, especially with enlarged text.
- No current tutorial beat renders the public browser. Tutorial success cannot substitute for checking its daily/weekly cards directly.

## 14. Review and revision log

- Initial draft: grounded in the research and confirmed current/weekly/join-
  forward requirements; group placement and sample precision were initially
  identified as open decisions.
- Product clarification: user selected proportional overlap and accepted an
  initially solo overflow group when existing groups are full. Preserve caps,
  reuse overflow space for subsequent arrivals, and retain existing automatic
  enrollment behavior. No open question remains on these two decisions; this
  clarification is not approval to implement or deploy the whole spec.
- Gap pass 1: added a sequence-based election snapshot, fenced plan publication,
  bounded reservation commits, and a direct current-Join escape from unpublished
  recovery so durable preparation never blocks immediate admission. Added
  authoritative prune-race and exposure checks from economy review.
- Gap pass 2: pinned cold/LEGACY current admission without rewriting old window
  modes; added transactional enrollment intent storage and its exact hooks;
  clarified reserved capacity and receipt lifecycle handling. Surfaced the
  directly conflicting old widget assertion instead of promising it can pass
  unchanged. Added stale-prune revalidation and explicit exceptional recovery.
- Game-analyst: SOUND WITH CHANGES. Required in-transaction prune exemption,
  authoritative activity/effect guards, and exposure reconciliation folded into
  sections 4/7/11. Backend docs/economy.md received a source-only factual note;
  no live payout or population measurements claimed.
- UI-test-planner: checklist inserted verbatim; actual Featured owner, Home
  entrypoints, unused tutorial fixtures, and bounded card-height risks reflected
  in section 9. No new tutorial beat or duplicated strip proposed.
- Architect review: after user approval, as required by repository AGENTS.md.
- No implementation, tests, builds, or deployment performed for this spec.
