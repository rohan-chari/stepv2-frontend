# Daily/weekly immediate Join and midnight contention — research findings

Research date: 2026-09-09. Frontend inspected at `648e4fe`; backend at
`cd46d1a`. Backend paths below are relative to the separate backend repository.
This records the initial source research and proposed direction, not a production
performance measurement. At that research stage, no runtime code, database data,
configuration, or schedules had changed. The subsequent approved implementation
and validation are recorded in [the feature specification](daily-weekly-immediate-join-requirements.md).

## Confirmed product requirements

- Tapping Join enters the currently running challenge immediately.
- Only steps after joining count; earlier steps from the day/week do not.
- This applies to daily and weekly challenges.
- Moving cohort preparation earlier must not introduce a joining cutoff.

Subsequent product clarifications, recorded in the implementation spec:

- Reuse existing capacity first. When groups are full, the user accepted
  creating overflow even though its first entrant may initially be alone.
  Later arrivals reuse that group's space; keep the existing hard caps.
- The user selected proportional overlap for samples crossing the join time.
- Preserve existing automatic enrollment alongside immediate manual Join;
  manual admission does not change the user's setting.

## Findings and correction to the earlier explanation

### 1. Manual Join and signup use different admission paths

The statement that finalized cohorts cannot accept anyone was too broad.
Regular manual Join is restricted, but signup already has a late-entry path.

Frontend evidence:

- `lib/screens/public_races_screen.dart:262`: a virtual private challenge card
  calls `assignSeededRaceBucket`, rather than joining a current race.
- `lib/services/backend_api_service.dart:3787`: this always sends
  `POST /races/seeded/:seedKind/assign` with `{ "window": "UPCOMING" }`.
- `lib/screens/public_races_screen.dart:886`: an elected user gets a pending,
  non-navigable card. Current and upcoming membership are not distinct actions.
- `test/public_races_featured_strip_test.dart:176`: the existing widget test
  explicitly expects Join to become YOU'RE IN with no VIEW action.
- The current card presents DAILY/WEEKLY and an end countdown even though its
  virtual Join action elects into the upcoming window. This explains the gap
  between the apparent action and the product requirement.

Backend evidence:

- `src/modules/races/routes.js:1281`: `/assign` returns HTTP 202 with
  `elected`, null `raceId`, and `finalizesAt`.
- `src/modules/races/services/seededRaceBuckets.js:574`: `elect` accepts only
  UPCOMING. It rejects enrollment once any bucket exists for that window.
- The same service at `:494` stops automatic election after finalization.
- The same service at `:936` projects the current race but can use an upcoming
  election to set `myStatus: ELECTED` when the user has no current race.
- `src/modules/races/commands/joinPublicRace.js:68` rejects private bucket
  races; using the generic public Join endpoint is not a valid workaround.

These are current private-cohort paths, not a claim that all legacy public
daily races reject mid-race joining. `joinRaceCore.js:227` permits ACTIVE
individual races, subject to the caller's access and capacity checks.

### 2. Signup already proves that adding members need not reshuffle cohorts

`src/modules/races/commands/autoEnrollNewUser.js`:

- `:76`: creates a participant in an existing cohort under locks, rechecks
  status/capacity, and writes membership and assignment records.
- `:172`: creates a capped overflow cohort if existing capacity is exhausted;
  checks for reusable capacity again to handle simultaneous signups.
- `:475`: selects current ACTIVE private races for new users.
- `:535`: prefers available capacity and retries races filled concurrently.
- It keeps existing cohort identities and members in place.

The current caps are 35 daily and 100 weekly. These are existing source policy,
not proposed economy changes. The superseding section of backend
`docs/daily-challenge-cohort-minimum-requirements.md` explicitly reserves
headroom for late onboarding.

Signup stores `matchSteps: 0` and prefers the most available capacity. Returning
manual joiners can have substantial history; do not silently classify them as
newcomers. Assess historical skill fit among bounded available candidates,
without reshuffling members or exposing opponent selection to the client.

Do not expose the whole signup command as manual Join: it also changes the
auto-enrollment setting, attempts both cadences, and grants welcome rewards.
Extract or share admission mechanics while retaining caller-specific effects.
Signup is best effort; an explicit Join needs a durable, truthful response.

### 3. Join-forward scoring exists, with a sample-resolution limitation

- `src/modules/races/queries/getRaceProgress.js:444` uses the later of
  participant `joinedAt` and race `startedAt`.
- `src/modules/races/services/raceStateResolution.js:83` uses the same boundary
  for canonical scoring/settlement.
- Mid-day starts do not simply fall back to the entire day's step total
  (`getRaceProgress.js:489`).
- `prisma/schema.prisma` persists `RaceParticipant.joinedAt`.

However, stored health samples are intervals, not individual step timestamps.
`src/modules/steps/models/stepSample.js:587` prorates a sample overlapping the
join instant. A 100-step 10:00–10:05 sample with a 10:02 join contributes an
estimated 60 steps, even if the actual walking within that interval was uneven.
The current code therefore implements an interval-based cutoff, not physically
exact attribution at the tap. Older/coarser samples amplify this limitation.

The requirement remains join-forward. A final design must explicitly handle
this sensor precision limit and test delayed/replaced samples, old clients,
powerups, box thresholds, live display, and final settlement. Do not count all
earlier steps to work around missing sample data.

### 4. Matching can move earlier without waiting for the end-of-day total

`src/modules/races/services/seededRaceBuckets.js:414` matches on historical
activity: daily matching excludes the immediately preceding day; weekly
matching excludes the immediately preceding week. There is no need to wait
until 11:55 PM for that evening's walking to finish.

Friendships, late historical syncs, and enrollment can still change. Preparing
earlier intentionally takes an earlier matching snapshot; it must not freeze
the ability to join. Late assignment should add a participant without
recomputing everyone else's groups.

### 5. The renewal worker couples urgent and deferrable work

`src/modules/races/jobs/seededRaceRenewal.js` checks every minute and:

1. Recovers missing current cohorts and finalizes upcoming ones in the last
   five minutes (`:552–586`).
2. Promotes due races (`:591`), including inactivity checks and transactional
   participant/event work (`:440–520`).
3. Creates future races and retries automatic enrollment (`:645–715`).

The minute cadence is not itself wrong: lifecycle recovery needs to be prompt.
The problem is performing broad future preparation in the same pass as due
activation. Merely changing the five-minute threshold leaves that coupling.

Structural work counts, not measured SQL traces:

- Finalization uses bulk inserts but still performs one race-link update and
  one membership update per bucket: at least `2 × bucketCount` update calls
  in those two loops, plus the other reads, writes, and locks
  (`seededRaceBuckets.js:852–910`).
- Promotion initializes missing box thresholds one participant at a time
  (`seededRaceRenewal.js:502`): `missingThresholdParticipants` update calls.
  These are candidates for set-based writes with the same predicates.
- Future automatic enrollment repeatedly checks the candidate population
  (`seededRaceBuckets.js:464`, `seededRaceRenewal.js:674`). A no-op in business
  terms can still issue SQL and take locks.
- Signup loads a growing set of active seeded races, groups capacity, then may
  try multiple races (`autoEnrollNewUser.js:481–575`). Reusing it unchanged for
  every manual Join would spread unnecessary work throughout the day.

## Recommended direction

### Admission independent of batch preparation

Introduce a shared current-window admission service for explicit daily/weekly
Join and signup. Determine the ET window on the server, return the user's
existing membership on retries, select bounded eligible capacity, recheck it
under the established lock order, and create overflow only when necessary.
The server chooses the group; clients cannot pick opponents by race ID.

Preserve one membership per seed/window/user. Existing unique constraints on
window membership and assignment already support this (`schema.prisma:2244`).
Never move existing racers to rebalance after racing has begun. At the boundary,
recheck the current time and deadline under lock so a stale ACTIVE row cannot
admit someone into yesterday's ended race. Resolve an unprepared current
window durably rather than returning a false success or waiting for tomorrow.

Use short, bounded admission transactions, one deduplicated resolution request
for the affected race, and post-commit cache invalidation. Global-event
enrollment must preserve its existing join-time entitlement rules. Final
design must establish whether existing indexes are sufficient or a repairable
capacity summary is justified; do not cache authoritative capacity without a
transactional recheck.

### Proposed scheduling sequence

These are provisional ET times, not a measured optimal schedule:

| Time | Work |
| --- | --- |
| Sunday 11:15 PM | Prepare next week's existing auto-enrolled roster. |
| Daily 11:30 PM | Prepare next day's existing auto-enrolled roster. |
| Until 11:50 PM | Verify preparation and retry failed bounded batches. |
| 11:50 PM–12:10 AM | Give due lifecycle work priority over bulk future preparation and nonurgent repair sweeps. |
| Midnight | Activate prepared races and process ended races through bounded workers. |
| After 12:10 AM | Spread future-window preparation/recovery across bounded batches. |
| All day | Admit manual joins immediately; handle post-preparation new enrollments incrementally. |

If auto-enrollment remains enabled, users becoming eligible after preparation
must still get their next-window membership; they cannot be silently omitted
by the existing `finalized > 0` early return. The exact incremental path for
PENDING cohorts must be designed alongside ACTIVE admission.

Do not delay live step intake, actual event boundaries, required enrollment
repair, or user-visible settlement merely because the clock is near midnight.
Keep retries durable and bounded. No new release flags or capacity increase is
needed for this direction. App-host log rotation is lower priority than the
actual PostgreSQL work.

### Economics and fairness

The game-analyst reviewed the source independently. Current funded payouts use
the race's stamped prize policy and full race duration, with positive-scoring
eligible participants at settlement. They do not prorate rewards by join time
(`src/modules/races/racePrizePool.js:46–110`).

Retain existing prize stamps and payout rules for this work unless separately
approved. A late entrant starts behind existing racers. An overflow group may
initially be small, which creates a possible easier-payout incentive even
without retroactive steps. Server-selected placement, reusing existing space,
one membership per window, and preventing leave/rejoin group shopping are
important. Separate late-join groups would make this tradeoff larger.
The current pool function pays no funded pool for fewer than two qualifying
players; immediate admission cannot guarantee an immediate opponent or reward.
The analyst's verdict was SOUND WITH CHANGES, conditional on preserving these
invariants and validating scoring, settlement, retries, and powerups.

Do not claim zero exploit risk or add arbitrary new payout thresholds as part
of a scheduling optimization. Historical economy prose contains superseded
numbers; use each race's immutable stamp in analysis and settlement.

### Compatibility and UI

Preserve existing UPCOMING semantics for frozen clients; do not silently
reinterpret their request as CURRENT. Add an explicit current-window request
contract (new route or additive supported window value) for updated clients.
The response must supply a usable assigned race and truthful membership state.
Final endpoint choice remains a design task.

New clients should render Join → joining → View for the current challenge,
even when an upcoming election exists. Preserve old response fields and legacy
stream protection. A current manual join must not accidentally enroll the user
twice or change their future auto-enrollment preference.

The behavior must work in shared Flutter code on iOS and Android; public race
browser fixtures and tutorial/demo data need review. A UI-placement checklist
and architect review belong to the subsequent approved specification, before
implementation is presented as ready.

## Validation needed before implementation/release

- Real HTTP tests for immediate daily and weekly Join before/after preparation,
  during a running window, at the boundary, and after a missed scheduler tick.
- Existing-member retries, simultaneous joins for the last slot, all-full
  overflow creation/reuse, simultaneous signup/manual Join, and no duplicates.
- Current membership plus an upcoming election; auto-enrollment on/off and
  post-preparation eligibility changes; old UPCOMING and legacy client paths.
- Real sync → Join → sync → displayed progress → completed-race payout tests
  proving join-forward scoring and no retroactive box/event credit.
- Pending and active prepared memberships, leave/forfeit/rejoin behavior,
  private discovery, expired ACTIVE rows, midnight and DST transitions.
- Real Flutter screen tests for immediate navigation/View state, retries,
  missing fields, and separately preserved upcoming state.
- Load tests on a dedicated test database with concurrent step sync, manual
  joins, cohort prep, and daily/weekly rollover. Existing assertions are
  protected; retain batch-finalizer guarantees rather than weakening them to
  enable a distinct late-admission path.

Measure an actual midnight window before selecting final times: per-job SQL
calls/writes, lock wait time, transaction duration, participant counts, queue
age, HTTP latency/errors, and managed database CPU. Compare equivalent traffic
and include downstream resolution/notification work. No measured CPU saving or
query-count reduction is claimed by this research.

No tests were run: this deliverable changes documentation only and does not
claim that a new Join implementation has been validated.
