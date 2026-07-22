# Five-Minute Step Samples — Requirements

**Status:** DRAFT — awaiting owner approval
**Date:** 2026-07-22
**Repos:** `stepv2-frontend` + `stepv2-backend`

## 1. Summary & user story

All powerup/event scoring windows (Wrong Turn, Leg Cramp, Rainstorm, Campfire,
Leech, Runner's High, the daily 2x global event) prorate the user's step samples
by time-overlap. Samples are uploaded as **hourly buckets**
(`health_service.dart:218 getHourlySteps`), so scoring cannot see *when inside an
hour* steps happened — a timed effect adjacent to a walking burst in the same
hour "smears" the burst into its window.

Real incident (2026-07-22, race `019c562d…`): emersonz walked ~2,500 steps
during the 2x event (11:36–12:06 ET), immediately after a Wrong Turn expired
(10:36–11:36 ET). Uniform proration of her 11:00–12:00 bucket attributed ~60% of
those steps to the already-expired Wrong Turn (reversed ×2) and credited only
~40% to the event — she scored ~900 instead of ~5,000.

**User story:** as a racer, when I time my walking around powerups and events,
my score reflects when I *actually* walked, to within ~5 minutes.

**Approach:** upload step samples in **5-minute buckets** instead of hourly.
No scoring math changes — `prorateSamplesIntoWindow` (`stepSample.js:166`) is
granularity-agnostic; finer input alone shrinks the error from ±60 min to
±5 min for every effect at once.

## 2. Scope / non-goals

**In scope**
- Frontend: bucket health reads at a remotely-configurable granularity
  (default 5 min), both iOS (HealthKit) and Android (Health Connect), uploaded
  through the existing `/steps/sync-v2` (and legacy `/steps/samples`) payloads.
- Backend: granularity-aware overlap resolution so mixed hourly/5-min data for
  the same user never double-counts (old builds keep uploading hourly forever).
- Backend: generalize Leech's "exclude the in-progress hour bucket" rule
  (`leechTransfers.js:35`) to be granularity-agnostic.
- Remote tunable + kill switch: `featureFlags.stepSampleBucketMinutes`
  (`users/routes.js:95` featureFlags block), absent/60 = current behavior.
- Backend: `step_samples` retention cron (owner decision 2026-07-22): prune
  samples old enough that no live or recomputable race can reference them
  (§4.1).

**Non-goals**
- No raw per-sample HealthKit timestamps (loses the deduped, manual-excluded
  aggregate that anti-cheat depends on — `health_service.dart:30-58`).
- No backfill/rewrite of historical hourly rows; accuracy improves from rollout
  forward only.
- No change to proration math, daily `steps` rows, `getStepsToday`, box
  progress formulas, or any scoring formula.
- No sub-5-minute granularity.

## 3. API contract (backend owns; pinned before implementation)

### 3.1 No new endpoints; request shapes unchanged
`POST /steps/sync-v2` and `POST /steps/samples` already accept arbitrary
`{periodStart, periodEnd, steps}` samples (`recordStepSamples.js:32
normalizeSamples` validates presence only, not duration). New clients simply
send more, shorter samples. Old clients keep sending hourly — **no versioning,
no compat break**. Sample count per sync grows from ≤24 to ≤288/day (~35 KB
body worst case — fine).

### 3.2 New feature flag (additive)
`GET /users/me` (and the other `withRuntimeFlags` call sites in
`users/routes.js`) adds:

```json
{ "featureFlags": { "stepSampleBucketMinutes": 5 } }
```

- Integer, one of `{5, 10, 15, 30, 60}`. Served from the existing
  `app_settings` table via `appSettings` (same mechanism as
  `bannerAdsEnabled`); admin-settable through the existing
  `GET/PUT /admin/settings` surface (`admin/routes.js`). The admin settings
  route currently handles boolean flags — the backend agent must extend it to
  accept/validate this numeric key (reject values outside the allowed set with
  a 400) and confirm how `app_settings` stores values (string/JSON) so
  `safeNumber` parses what the admin PUT writes.
- **Absent, null, or non-numeric ⇒ client uses 60 (hourly).** A new app build
  against an older backend therefore behaves exactly like today. `safeFlag`
  in `users/routes.js:85` currently coerces booleans only — add a parallel
  `safeNumber(key, fallback, allowedValues)` helper.
- Error case: none new; flag resolution is defensive like the existing flags.

### 3.3 Server-side overlap resolution (the core backend behavior change)
Today `upsertBatch` (`stepSample.js:45`) blind-upserts on the unique key
`(user_id, period_start)`. With mixed granularities that silently corrupts:
an incoming hourly `15:00–16:00` row would replace a stored `15:00–15:05` row
while the stored `15:05…15:55` rows survive → **double count**. New rules,
applied inside the existing write transaction for BOTH `/steps/sync-v2`
(Transaction A, `recordStepSyncV2.js:214`) and `/steps/samples`:

For each incoming sample `I` (after the existing in-batch `removeOverlaps`):

1. **Drop-coarser rule:** if any stored sample `S` (same user) with
   `S.periodStart ≠ I.periodStart` lies strictly within `I`'s window
   (`I.start ≤ S.start AND S.end ≤ I.end`) → **drop `I`** (finer data already
   stored; an old build must never clobber a new build's finer rows).
2. **Span guard:** if a stored sample `S` overlaps `I` but is NOT fully
   spanned by the batch's covered range (`min(periodStart)…max(periodEnd)` of
   the kept incoming samples), **drop `I` and keep `S`** — deleting `S` would
   destroy step credit outside what this batch replaces. This arises only at
   the day-start boundary after a timezone change (bucket alignment shifts),
   costs at most one coarse bucket of accuracy, and self-limits to the first
   local day after travel.
3. **Otherwise:** **delete every stored sample overlapping `I`'s window**
   (`S.end > I.start AND S.start < I.end`), then **insert `I`.**
   This covers, correctly and uniformly:
   - normal re-sync of the same bucket (same start/end → value update);
   - the in-progress partial bucket maturing (`15:35–15:37` → `15:35–15:40`);
   - a new build converting an old hourly row to 5-min rows (first 5-min
     bucket deletes the hourly row it overlaps);
   - staggered/DST-odd windows (neither contains the other).

Implementation: a single shared model method (working name
`StepSample.reconcileBatch(userId, samples)` / `reconcileBatchOn(client, …)`)
replacing `upsertBatch`/`upsertBatchOn` at both call sites
(`recordStepSamples.js:121`, `recordStepSyncV2.js:233`), doing one set-based
`DELETE … WHERE user_id = $1 AND (overlaps any KEPT incoming window)` + batch
insert per request — not per-row round trips. Rules 1–2 are evaluated against
the stored rows fetched once at the start of the transaction
(`findByUserIdAndTimeRange` over the batch's covered range). The insert still
uses `ON CONFLICT (user_id, period_start) DO UPDATE` so a concurrent sync
racing the delete can't 500 on the unique key.

**Deploy-order consequence:** these rules ship and are verified in prod
**before** any app build sends 5-min samples (see §7). The rules are a no-op
for a pure-hourly world (hour-aligned rows never strictly contain each other,
and same-start overwrite semantics are preserved), so deploying backend-first
is safe for all existing clients.

### 3.4 Leech generalization
`computeLeechEarnedTransfer` (`leechTransfers.js`) currently clamps the
leecher's credited window to the top of the current hour because the
in-progress hourly bucket's prorated value shifts between syncs. Replace the
hour-specific clamp with: **prorate only samples whose `periodEnd ≤ now`**
(i.e., exclude any not-yet-closed bucket, whatever its size). Identical
behavior for hourly data; with 5-min buckets Leech lag drops from up to 60 min
to up to 5 min. Monotonicity is preserved (closed buckets never change under
normal sync; rule 2 deletions only occur when finer data replaces coarser,
which re-runs scoring anyway).

### 3.5 Explicitly unchanged
`sumStepsInWindow(s)`, `prorateSamplesIntoWindow`, `computeGlobalEventBoost`,
`computeEffectModifiers`, `calculateBaseAdjusted`, box-progress math,
`getHomeRaceCard` batching, hitchhike copies — all consume samples through the
same proration primitives and need **zero changes**. The backend agent must
still run `grep -rn "hour" src/modules/{races,powerups,steps}` and confirm
`leechTransfers.js` is the only scoring-path file with bucket-size assumptions.

## 4. Data model / migrations

**No schema migration.** `step_samples` already stores arbitrary
`period_start/period_end` (`timestamp(3) without time zone`, UTC). The unique
key `(user_id, period_start)` stays (rule 2's delete-then-insert makes the
mixed-granularity cases safe).

Row growth: only non-zero buckets are uploaded (`health_service.dart:262`).
Typical user: ~10–16 non-zero hourly rows/day today → ~40–80 non-zero 5-min
rows/day (~4–5×). At current DAU this is thousands of rows/day — negligible
for Postgres with the existing `(user_id, period_start, period_end)` index.
Reads fetch a bounded day-scale range per user and grow by the same ~5×.

Historical rows stay hourly; mixed history is exactly what §3.3 makes safe.

### 4.1 Retention cron (new)
Delete `step_samples` rows that nothing can ever read again:

- **Cutoff:** `period_end < now() - 45 days` **AND** `period_end <
  (oldest `started_at` among races not in a terminal status
  (`COMPLETED`/`CANCELLED`), if any)`. 45 days comfortably exceeds the longest
  race/tournament-round duration plus settlement grace; the second predicate
  makes the guard structural rather than assumed.
- **Mechanics:** in-process cron on the existing scheduler, **insert-first
  `JobRun` unique-key dedup — NOT an advisory lock across the callback** (the
  3e6c827 outage rule; see backend `CLAUDE.md`/cron conventions). Delete in
  bounded batches (`DELETE … WHERE id IN (SELECT … LIMIT 5000)` loop) to avoid
  long row locks; run daily off-peak.
- **Compat:** invisible to all clients (samples this old are unreachable
  through every read path — race scoring reads race-window ranges only).
- **Kill switch:** env `STEP_SAMPLE_RETENTION_DISABLED=true` skips the cron.
  First prod run happens manually-observed (log the delete count).

## 5. Frontend plan (iOS + Android in lockstep)

### 5.1 Bucketing (`health_service.dart`)
Generalize `getHourlySteps` → `getStepSamples({startTime, endTime,
bucketMinutes})` (keep the old name as a thin wrapper for tests):

- Window construction: align the first bucket to the hour as today
  (`health_service.dart:231-251`), then step by `Duration(minutes:
  bucketMinutes)` **by absolute duration** (no wall-clock reconstruction), so
  DST transitions produce contiguous UTC windows. Final bucket stays partial
  (`bucketStart → now`), exactly like today — §3.3 rule 2 handles its maturing.
- **Two-pass read to bound platform calls:** pass 1 reads the existing hourly
  windows (≤24 aggregate calls); pass 2 subdivides only hours with steps > 0
  into `bucketMinutes` windows and re-reads those. Typical day ≈ 24 + 12×(8–12
  active hours) ≈ 120–170 HealthKit/Health Connect aggregate calls vs 288 flat.
  Keep `_hourlyConcurrency = 4` (`health_service.dart:216`).
- Upload only pass-2 (fine) buckets for active hours + nothing for zero hours —
  never both granularities for the same hour in one payload (the in-batch
  `removeOverlaps` would keep the finer ones anyway; don't rely on it).
- **Android manual-steps subtraction** (`_manualStepsInInterval`,
  `health_service.dart:73`) must NOT run per bucket (would double platform
  calls). Read manual-tagged raw records **once** for the whole sync range,
  bucket them client-side by timestamp, and subtract per bucket via the
  existing `accurateAndroidTotal` clamp logic (extended to per-bucket floors —
  the sum of clamped buckets may exceed-clamp vs the old hourly path by design;
  document in code).
- iOS keeps `getTotalStepsInInterval(includeManualEntry: false)` per window —
  the deduped `cumulativeSum` path is untouchable per §2 non-goals.

### 5.2 Flag plumbing
- `AuthService`/me-payload parsing: read
  `featureFlags.stepSampleBucketMinutes`; any value not exactly in
  `{5, 10, 15, 30, 60}` (including missing, null, 20, strings) → **60**.
- Persist the last-accepted value in `SharedPreferences` so the first sync
  after a cold start (which can run before the me-fetch completes) uses the
  last-known granularity instead of silently reverting to hourly.
- `main_shell.dart:803` passes the resolved bucket size into the health read.
  Everything downstream (`buildStepSyncV2Payload`, legacy fallback at
  `main_shell.dart:853`) is payload-shape-agnostic and unchanged.

### 5.3 States & degradation
- Flag absent (old backend), fetch-me failed, or value invalid → hourly. The
  app must never hard-depend on the new field (CLAUDE.md rule #1).
- Health read failure semantics unchanged (null window → sample omitted).
- No new UI. Loading/empty/error surfaces untouched.
- Old app builds: continue hourly forever; backend §3.3 keeps them correct.

## 6. Backward-compat & rollout

- **Deploy order:** (1) backend (overlap rules + leech generalization + flag
  endpoint, flag value still 60/absent) → verify prod syncs unchanged;
  (2) ship iOS + Android builds (lockstep, same version/build number, per
  CLAUDE.md); (3) flip `stepSampleBucketMinutes` to 5 in `app_settings` via
  admin. New builds pick it up on next me-fetch; frozen old builds ignore it.
- **Kill switch:** set the flag back to 60 (or delete it). New clients revert
  to hourly on their next sync; stored 5-min rows remain valid (proration is
  granularity-agnostic) — but note the returning hourly uploads are dropped by
  §3.3 rule 1 for hours that already have finer rows *that sync's values would
  refine*; acceptable because within a day the fine rows self-heal on each
  sync, and next-day data is cleanly hourly.
- **Old client on new backend:** unchanged requests, unchanged responses;
  §3.3 is a behavioral no-op for pure-hourly users.
- **New client on old backend:** flag absent → hourly → bit-identical to today.
- **Mixed devices on one account** (e.g. old-build Android + new-build iOS):
  rule 1 prevents the old build clobbering fine rows; residual cross-device
  divergence is the same as today's last-writer-wins and is out of scope.

## 7. Test plan (tests FIRST, per repo; never against prod DB)

**Backend (`test/integration/`, real HTTP + test Postgres):**
1. `/steps/sync-v2` with 5-min samples → rows persisted verbatim; race totals
   via `GET /races/:id` reflect fine-grained proration.
2. Emersonz replay: seed a race + Wrong Turn (10:36–11:36) + global event
   (11:36–12:06) + 5-min samples concentrated 11:36–12:06 → participant total
   ≈ 2× walked steps; then the same scenario with one hourly sample →
   reproduces today's smeared total (regression contrast, proves the fix).
3. Overlap matrix (each through the public endpoints): hourly-then-5-min same
   hour (hourly deleted); 5-min-then-hourly (hourly dropped, rule 1); partial
   bucket maturing across two syncs; identical re-sync (value update);
   pure-hourly before/after backend deploy (no-op); span guard — a stored
   sample extending before the batch's covered range survives and the
   colliding incoming bucket is dropped (rule 2).
4. Leech: 5-min buckets → transfer credits within one closed 5-min bucket of
   walking; in-progress bucket excluded; monotonic across successive syncs.
5. `featureFlags.stepSampleBucketMinutes`: absent by default, settable via
   admin settings, served on `/users/me`, invalid stored value → omitted.
6. Legacy `/steps/samples` path: same overlap matrix subset.
6b. Retention cron: deletes only rows past both cutoff predicates; a 50-day-old
   sample belonging to a still-ACTIVE race's window survives; `JobRun` dedup
   prevents double-runs; `STEP_SAMPLE_RETENTION_DISABLED=true` skips.

**Frontend (`flutter test`, real widgets/services with fake health platform):**
7. `getStepSamples`: window construction at 5/60 min incl. partial last bucket,
   hour-aligned first bucket, absolute-duration stepping across a DST edge.
8. Two-pass subdivision: zero-step hours not subdivided; active hours re-read;
   emitted samples cover exactly the active hours' fine buckets.
9. Android: day-wide manual read bucketed + subtracted per bucket, clamped ≥0.
10. Flag plumbing: me-payload → bucket size; absent/invalid → 60; sync-v2
    payload carries the fine samples through `buildStepSyncV2Payload`
    unchanged in shape.

Backend uses `test:unit`/`test:integration` (never bare `npm test`); no
existing test is modified or deleted.

## 8. Acceptance criteria / definition of done

- [ ] Backend deployed first; pure-hourly prod traffic byte-identical in
      behavior (spot-check a real user's totals pre/post deploy).
- [ ] All §7 tests written first, failing for the right reason, then green.
- [ ] Overlap rules: no user can ever have two stored samples overlapping in
      time after any sync sequence in the §7 matrix (assert via DB invariant
      check in integration tests).
- [ ] Emersonz-replay integration test passes: timed walking around an expired
      debuff scores within one 5-min bucket of exact.
- [ ] Flag flip 60→5→60 exercised on staging end-to-end with a real device
      build; sync latency at 5-min measured and recorded in the PR
      (target: p50 added latency < 2s vs hourly; if exceeded, ship with flag
      at 15 and file follow-up).
- [ ] iOS + Android builds produced in lockstep (same version/build number,
      correct `--dart-define`s); both verified syncing 5-min samples on
      staging.
- [ ] `leechTransfers.js` hour-assumption grep clean; no other scoring file
      assumes bucket size.
- [ ] Retention cron live with `STEP_SAMPLE_RETENTION_DISABLED=true` initially;
      first prod run manually observed (logged delete count), then flag
      removed.
- [ ] Prod flag may be flipped to 5 any time after the backend deploy is
      verified — only new builds react to it, so the phased App Store/Play
      rollout needs no coordination (unlike `testOnly` cosmetics, there is no
      old-client breakage vector). Staging validation with a real device build
      happens before the prod flip regardless.

## 9. Owner decisions (interviewed 2026-07-22 — no open questions remain)

1. **Bucket size: 5 minutes** in prod once new builds are live.
2. **Sync-latency gate accepted:** two-pass read, p50 added latency < 2s on a
   real device before the prod flip; fall back to flag=15 + follow-up if
   exceeded.
3. **Retention: YES** — prune old samples per §4.1 (45-day + unsettled-race
   guard).

## Revision log

- **Gap pass 1:** Found and closed a data-loss hole: rule 2's blanket
  delete-overlapping could destroy a stored coarse sample extending *outside*
  the batch's covered range (timezone-travel day-boundary case) — added the
  span guard (new rule 2, old rule 2 renumbered to 3). Added
  `ON CONFLICT DO UPDATE` on the post-delete insert so concurrent syncs can't
  500 on the unique key. Added SharedPreferences persistence of the bucket
  flag so cold-start syncs don't silently revert to hourly before the
  me-fetch. Named the shared model method (`reconcileBatch`) and pinned both
  call sites so the two agents converge on one implementation.
- **Gap pass 2:** Tightened flag-clamping ambiguity ("clamp" → any value not
  exactly in the allowed set is 60). Flagged that the admin settings route is
  boolean-only today and must be extended + validate the numeric key with a
  400. Relaxed the rollout gate: the prod flag flip is safe immediately after
  backend deploy (only new builds react) — waiting for full phased rollout was
  cargo-culted from the cosmetics `testOnly` pattern and does not apply here.
  Added the span-guard case to the integration-test overlap matrix.
- **Interview fold-in (2026-07-22):** owner chose 5-min, accepted the <2s
  latency gate, and opted IN to retention — added §4.1 (45-day + unsettled-race
  guard, JobRun-dedup cron, disabled-by-default first run), test 6b, and the
  retention acceptance criterion; removed retention from non-goals.
