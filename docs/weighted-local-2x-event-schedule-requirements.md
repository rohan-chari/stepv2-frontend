# Weighted local-time daily 2x event schedule

**Status:** Deployed to production on 2026-08-27 at backend commit `d553d2b`;
architecture-reviewed, economy-reviewed (`SOUND`), and post-deploy verified.
The first weighted-v2 event day is 2026-09-01 because event days through
2026-08-31 were already immutably materialized under v1. Staging remained
stopped.

## 1. Summary and user story

The daily 30-minute 2x Race Steps event currently chooses every local minute
from 08:00 through 21:59 with equal probability. Production traffic is
materially higher later in the day, so the event should remain surprising but
be somewhat more likely during high-activity afternoon and evening periods.

As a racer, I continue to receive one unpredictable 30-minute 2x opportunity
per logical event day in my stable local timezone. The exact minute remains
secret and random, but afternoon and evening bands have higher draw weights
than morning bands.

This is a backend-only scheduling-policy change. Frequency remains once per
logical day, duration remains 30 minutes, multiplier remains 2x, and every
participant receives the one shared drawn wall-clock minute converted through
their snapshotted event timezone.

## 2. Product behavior

### 2.1 Approved local-time probability matrix

The backend must choose exactly one start minute using this immutable v2
policy:

| Local start window | Probability | Minutes in band | Probability per hour |
|---|---:|---:|---:|
| 08:00–11:59 | 15% | 240 | 3.75% |
| 12:00–14:59 | 18% | 180 | 6.00% |
| 15:00–16:59 | 18% | 120 | 9.00% |
| 17:00–18:59 | 21% | 120 | 10.50% |
| 19:00–20:59 | 21% | 120 | 10.50% |
| 21:00–21:59 | 7% | 60 | 7.00% |
| **Total** | **100%** | **840** | — |

Band boundaries are half-open. Every minute inside a selected band has equal
probability. All 840 minutes in `[08:00,22:00)` remain possible; midnight–08:00
and 22:00–midnight remain impossible.

The combined chances are 33% before 15:00, 67% from 15:00–21:59, and 42% from
17:00–20:59. No weekday/weekend split is introduced.

### 2.2 Exact draw algorithm

`src/modules/steps/globalStepEvent.js` will replace the uniform
`randomInt(480,1320)` local draw with one cryptographic ticket draw from
`randomInt(0,72000)`.

The v2 policy uses 72,000 equiprobable tickets. Per-minute ticket counts are:

| Local start window | Tickets per minute | Band tickets |
|---|---:|---:|
| 08:00–11:59 | 45 | 10,800 |
| 12:00–14:59 | 72 | 12,960 |
| 15:00–16:59 | 108 | 12,960 |
| 17:00–18:59 | 126 | 15,120 |
| 19:00–20:59 | 126 | 15,120 |
| 21:00–21:59 | 84 | 5,040 |

The implementation subtracts whole-band ticket counts in chronological order,
then divides the winning band's residual ticket by its tickets-per-minute to
obtain the zero-based minute offset. This preserves the current one-call
cryptographic draw, gives exact band probabilities, and makes every minute
within a band uniform without floating-point arithmetic.

The band table, every band object, total ticket count, and policy version must
be named, deeply frozen constants. `chooseLocalStartMinute` must also reject an
injected draw that is not an integer in `[0,72000)`; production
`crypto.randomInt` already provides that contract, while explicit validation
keeps tests and future callers honest.
Module-load or test-time validation must prove that bands are ordered,
contiguous, non-overlapping, cover exactly `[480,1320)`, total 100%, and produce
integer per-minute ticket counts totaling 72,000.

### 2.3 Persistence and immutability

The winning `localStartMinute` remains persisted once on the logical parent
`GlobalStepEvent`. Entitlements continue to persist exact participant-specific
UTC `startsAt`/`endsAt` values derived from that minute and the stable timezone
snapshot.

Add nullable `GlobalStepEvent.schedulePolicyVersion` mapped to
`global_step_events.schedule_policy_version`:

- `NULL`: legacy global events for which a local draw policy is not applicable,
  or an old backend worker's mixed-version write;
- `1`: existing uniform local-event parents;
- `2`: newly created parents using this weighted policy.

The migration backfills existing `LOCAL_ENTITLEMENTS` parents with version 1.
New local parents write version 2 in the same transaction as the winning
minute. An existing event-day row is authoritative: deployment must never
redraw it or rewrite its policy version, even if it was prepared under v1.

The existing `eventDay` unique constraint and event-day advisory transaction
lock remain the concurrency authority. No runtime flag, rollout percentage,
kill switch, environment toggle, or admin-editable odds are added.

## 3. Scope and non-goals

### 3.1 In scope

- Weighted selection of future local-event start minutes using the approved
  six-band matrix.
- Immutable policy-version stamping for audit and later outcome analysis.
- Tests that exhaustively prove the exact distribution and persistence path.
- Documentation of the new live odds in `docs/economy.md` after implementation.

### 3.2 Non-goals

- Changing the 2x multiplier, 30-minute duration, or once-daily frequency.
- Changing scoring, signed multiplier stacking, race payouts, mystery boxes,
  milestones, coins, notifications, banners, or summary behavior.
- Extending the eligible window outside 08:00–21:59.
- Weekday/weekend, per-country, per-user, traffic-reactive, or adaptive odds.
- Publishing future event times or the winning band before the event begins.
- Redrawing already-created parents or entitlements.
- Adding a feature flag or live configuration surface.
- Frontend, iOS, Android, demo, tutorial, or UI-placement changes.

## 4. Existing-system touchpoints and implementation path

### 4.1 Backend code

1. `src/modules/steps/globalStepEvent.js`
   - Define and export the v2 band table, ticket total, and policy-version
     constant.
   - Keep `GLOBAL_EVENT_WINDOWS_ET_MIN` and `chooseEventStartForEtDay`
     unchanged for legacy-global compatibility; the new weights apply only to
     `LOCAL_ENTITLEMENTS` parent creation.
   - Change only `chooseLocalStartMinute` to map one injected cryptographic
     ticket to a local minute, and export the policy-version constant for the
     model rather than duplicating the literal `2`.
   - Keep `assertLocalSchedule`, `localEventWindowForZone`, timezone conversion,
     compatibility-envelope construction, duration, multiplier, and legacy ET
     hash scheduling unchanged.
2. `src/modules/steps/models/globalStepEvent.js`
   - In `createLocalParentIfAbsent`, write `schedulePolicyVersion: 2` beside the
     selected minute.
   - Preserve the advisory lock, existing-row early return, transaction, cache
     invalidation, and entitlement materialization behavior.
3. `prisma/schema.prisma`
   - Add the nullable mapped integer field to `GlobalStepEvent`.
   - Regenerate the Prisma client after the schema/migration change.
4. `prisma/migrations/<timestamp>_weighted_local_2x_schedule/migration.sql`
   - Wrap the additive `ALTER` and backfill in explicit `BEGIN`/`COMMIT` so a
     failed backfill cannot leave a partially applied migration.
   - Add the nullable integer column with no database default.
   - Backfill version 1 only where `schedule_mode='LOCAL_ENTITLEMENTS'` and the
     new column is null.
   - Do not alter event minutes, entitlements, or legacy-global rows.
5. `docs/economy.md`
   - During implementation, document v2 as approved/code-ready but not yet
     deployed, preserving the verified uniform live description.
   - Only after a separately authorized production deploy may the live entry be
     changed to weighted-v2 with deployment evidence.

`src/modules/steps/jobs/globalStepEventScheduler.js` requires no behavior
change: it already prepares two safe future logical days and delegates the draw
to `createLocalParentIfAbsent`. Its earliest possible minute remains 08:00, so
`firstSafeLocalEventDay` remains valid.

### 4.2 Frontend plan

No Dart changes are required. Home and race detail continue receiving the
existing optional active-event object and rendering the existing banner. There
are no new loading, empty, or error states and no user-visible schedule table.

Both iOS and Android continue to send timezone information and consume the
same response shape. Demo/tutorial mirrors are unaffected because the event UI,
fixtures, and presentation timing contract do not change.

## 5. API contract

No endpoint, request, or response contract changes.

Existing authenticated responses continue to optionally include:

```json
{
  "globalEvent": {
    "active": true,
    "multiplier": 2,
    "endsAt": "2026-08-27T21:30:00.000Z"
  }
}
```

The policy version is internal audit data and must not be added to public API
responses. Error behavior is unchanged. When no viewer-specific entitlement is
active, `globalEvent` remains absent as it is today. Old clients therefore see
exactly the same payload and only observe that future event times follow a new
distribution.

## 6. Data model and migration safety

Prisma addition:

```prisma
schedulePolicyVersion Int? @map("schedule_policy_version")
```

SQL shape:

```sql
BEGIN;

ALTER TABLE "global_step_events"
  ADD COLUMN "schedule_policy_version" INTEGER;

UPDATE "global_step_events"
SET "schedule_policy_version" = 1
WHERE "schedule_mode" = 'LOCAL_ENTITLEMENTS'
  AND "schedule_policy_version" IS NULL;

COMMIT;
```

The column is additive and nullable, so the currently deployed backend and any
older code can continue reading and writing during migration/deploy ordering.
There is no destructive migration and no required public request field. New
code treats an existing row—whether version 1, 2, or null—as immutable and does
not attempt a repair/redraw.

No index is needed because gameplay does not query by policy version. Aggregate
operational analysis can filter the small daily parent table directly.

## 7. Backward compatibility and rollout

- Frozen app clients: unchanged endpoint shapes, active banner, multiplier,
  notification, and scoring behavior.
- Older backend during deployment: ignores the additive nullable column and
  may create a null/v1-equivalent parent; that parent remains authoritative.
- New backend against an old parent: returns it without redrawing.
- New backend against a new event day: persists policy version 2 and the v2
  weighted minute atomically.
- Already-materialized future days at deployment remain uniform-policy events.
  The weighted policy naturally begins with the first event day created after
  the new backend is live. Because the scheduler prepares two safe future days,
  the visible policy transition may lag deployment by several days; this is
  expected and must not be accelerated by deleting or redrawing parents.

Deployment is backend-only. Apply the additive migration before restarting the
backend processes, then keep production at exactly two HTTP workers plus its
existing non-HTTP process topology. No app release is required. Starting or
reloading staging and every production deploy/data operation require separate,
explicit authorization under the repo runbooks; implementation approval alone
does not authorize them.

No flag is permitted. Rollback means redeploying the previous code; already
created v2 parents remain immutable and valid because every selected minute is
also valid under v1's `[08:00,22:00)` support.

After a separately authorized deploy, record via a read-only query: the first
event day stamped policy version 2, counts grouped by policy version (including
null), and the still-prepared v1 days that explain the transition lag. This is
verification only and must not mutate or redraw any row.

## 8. Tests-first plan

Tests must be added and observed failing for the expected reason before the
business logic or migration implementation lands. Existing assertions may not
be weakened or deleted.

### 8.1 Pure distribution tests

Extend `test/utils/localGlobalStepEventSchedule.test.js`:

1. Inject every ticket from 0 through 71,999 and assert exact band counts:
   10,800 / 12,960 / 12,960 / 15,120 / 15,120 / 5,040.
2. Within each band, assert every minute receives the same number of tickets
   and all 840 eligible minutes are reachable.
3. Assert exact boundary tickets map to 08:00, 11:59, 12:00, 14:59, 15:00,
   16:59, 17:00, 18:59, 19:00, 20:59, 21:00, and 21:59.
4. Assert the injected `randomInt` is called exactly once with `(0,72000)`.
5. Assert negative, 72,000, and non-integer injected tickets are rejected.
6. Retain and pass the existing timezone reuse, compatibility-envelope, DST,
   and invalid-input tests with only the mechanical injected-ticket update.

A unit test is appropriate for the exhaustive distribution property because
an HTTP path cannot structurally enumerate the cryptographic sample space.

### 8.2 Integration tests

Extend `test/integration/local-global-step-event-entitlements.test.js` through
the real Prisma model and dedicated integration database:

1. Create a local parent with an injected boundary ticket and assert the stored
   `localStartMinute`, `schedulePolicyVersion=2`, 30-minute duration, schedule
   mode, and event day.
2. Call creation again for the same event day with a different injected ticket;
   assert the same row/minute/version is returned and the second random source
   is never called.
3. Run concurrent same-day creation attempts and assert exactly one parent and
   one persisted draw survive the advisory-lock/unique-key path. The test must
   not assume which contender wins; it may assert that the stored minute is one
   of the two injected candidates and that the aggregate draw-call count is one.
4. Verify the migration-backfilled version-1 fixture remains unchanged when
   encountered by the new code.
5. Extend `test/integration/local-global-step-event-schema.test.js` to assert
   `schedule_policy_version` exists, is nullable, and has no database default.

Add a migration-source guard alongside
`test/services/localGlobalEventMigration.test.js` that asserts the migration:

- contains explicit `BEGIN` and `COMMIT`;
- adds a nullable/no-default `schedule_policy_version` column;
- backfills only `schedule_mode='LOCAL_ENTITLEMENTS'` rows whose new field is
  null;
- does not update `local_start_minute`, entitlement windows, legacy rows, or
  contain destructive `DROP`/`DELETE` statements.

Add one real-HTTP integration regression on an existing Home or race-progress
path asserting that an active event still exposes exactly `active`,
`multiplier`, and `endsAt`, with no policy-version field.

Before integration tests, confirm `DATABASE_URL` is the dedicated local
`steps-tracker-integration_test` database. Run only the targeted integration
suite while diagnosing; never point it at production and never use bare
`npm test`.

### 8.3 Verification commands

- `npm run test:unit`
- `npm run test:integration` after explicitly confirming the test database
- `flutter analyze` in the frontend repo to preserve its clean baseline even
  though no Dart changes are expected
- No iOS/Android binary build is required because no dependency, native file,
  Dart code, build configuration, or API contract changes.

## 9. Observability and follow-up analysis

The policy version exists for immutable attribution, not as a runtime control.
After at least 30 completed v2 event days, a read-only early-outcome aggregate
may compare:

- realized event count by band versus the configured probabilities;
- parent counts grouped by `schedulePolicyVersion`, including any null
  mixed-version rows;
- eligible users and users with positive overlapping raw steps;
- overlap-prorated raw steps per eligible user and per walker;
- event summaries/acknowledgements when their lifecycle is complete;
- weekday/weekend outcomes as analysis only;
- valid stable-timezone versus `America/New_York` fallback cohorts, so inherited
  timezone mismatch is not mistaken for local-time performance;
- timed-powerup activation/overlap by type, policy version, and minutes from
  event start, especially Runner's High, Wrong Turn, and freeze effects;
- missing or duplicate event days, out-of-range minutes, and version-2 parents
  with a missing/wrong policy stamp.

Do not use raw request counts alone as the success metric and do not adapt the
matrix automatically. Thirty days is not distribution validation: the 7% band
expects only 2.1 events and each 21% band only 6.3, so report confidence
intervals and retain the exhaustive ticket test as the authoritative odds
proof. Any later odds change is a new policy version, economy review,
requirements update, and permanent code change. Cap any future single hour at
10.5% without a fresh exploit review.

No future draw, selected band, or minute may be exposed before the event starts.
Stable timezone snapshots and immutable entitlements continue preventing
timezone chasing and duplicate windows.

## 10. Economy and exploit impact

- Direct coin source/sink change: zero. The event changes race score, not raw
  steps, mystery-box progress, milestones, or direct coin issuance.
- Expected local start shifts from 14:59:30 under uniform v1 to 16:17:12 under
  weighted v2, a shift of 77 minutes 42 seconds.
- A read-only 31-day production step-sample estimate over 1,031 non-review users
  with event entitlement history projects mean extra race steps per entitled
  user/day rising from 57.7 to 58.8 (+2.0%); median +0.3%, p90 +0.4%, and p99
  +4.4%. This assumes historical local time-of-day behavior continues and is
  not a causal forecast.
- Placement impact: the modest score uplift may redistribute placement but does
  not change prize-pool size.
- Timed-powerup interaction: afternoon/evening buffs become somewhat more
  likely to overlap the event. The strongest blind 1h/2h/3h/4h windows rise
  from 7.14%/14.29%/21.43%/28.57% to 10.5%/21%/31.5%/42%; even the strongest
  four-hour play still misses 58% of days and the exact minute remains hidden.
- Degenerate strategy guard: no published future draw, no per-user redraw, no
  timezone-header scheduling, and no daily adaptive traffic input.

The approved matrix supersedes the earlier research recommendation. The final
game-analyst review recomputed overlap/exploit conclusions against these six
exact bands and returned `SOUND` with no required changes.

## 11. Acceptance criteria and definition of done

1. New local parents use exactly the six approved band probabilities and a
   uniform minute within the winning band.
2. One cryptographic integer draw determines the persisted minute; exhaustive
   tests prove all 72,000 outcomes.
3. Existing parents and entitlements are never redrawn or moved.
4. New parents created by a v2 process persist policy version 2;
   pre-migration local parents are backfilled to version 1; legacy events remain
   nullable/not applicable. A local parent created by an old backend worker
   after migration may remain null, immutable, and separately observable.
5. Frequency, duration, multiplier, timezone semantics, notification timing,
   scoring, UI, and public API shapes remain unchanged.
6. No runtime flag or mutable odds configuration is introduced.
7. Tests are written first; targeted tests, `npm run test:unit`, integration
   tests on a confirmed local test DB, and `flutter analyze` pass.
8. Backend compatibility with old app and mixed backend versions is explicitly
   verified; both mobile platforms are accounted for as no-change consumers.
9. Architect, game-analyst, and post-implementation code-reviewer reviews have
   no unresolved required findings.
10. No staging start, production migration, deploy, or data write occurs without
    its separately required explicit approval.

## 12. Revision log

- **Draft v1 — 2026-08-27:** Initial spec after production traffic analysis,
  six completed local-event outcome aggregates, product confirmation of the
  six-band 08:00–22:00 matrix, and pre-spec game-economy analysis. Preserved a
  one-call cryptographic draw using an exact 72,000-ticket mapping; added an
  immutable policy-version stamp rather than a runtime flag.
- **Gap pass 1 — 2026-08-27:** Corrected the combined matrix arithmetic to
  33%/67%; required frozen/exported constants, invalid-ticket validation,
  Prisma client regeneration, and deployment-honest economy documentation.
- **Gap pass 2 — 2026-08-27:** Isolated weighted-local constants from the
  legacy ET scheduler, documented the intentional multi-day transition caused
  by immutable prepared parents, made the concurrency test order-independent,
  and added policy-version/null observability.
- **Architect review — 2026-08-27:** Required transactional migration coverage
  and resolved mixed-worker null-version wording. Also adopted deep-frozen band
  objects, a real-HTTP response-key regression, and deployment verification of
  the first v2 event day and policy-version counts.
- **Game-analyst review — 2026-08-27 (SOUND):** Verified all 72,000 ticket
  outcomes, quantified the 77m42s expected-time shift, projected a modest 2.0%
  mean score uplift with zero direct coin delta, documented blind timed-powerup
  overlap, and strengthened fallback-timezone, powerup, and small-sample
  monitoring guidance. No required design change remained.
