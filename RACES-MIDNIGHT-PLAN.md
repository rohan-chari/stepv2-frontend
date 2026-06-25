# Midnight-ET races + pre-registration — implementation plan

**Goal (user request):** daily/weekly races should start at **midnight Eastern** and users
should be able to **opt into the next race up to ~24h before it starts**, so nobody is forced
to start a race already in progress and sit at 0 while others have steps.

**Chosen direction:** Path A (calendar-align + pre-registration). **"Midnight EST" = Eastern
Time, DST-aware** (`America/New_York`), not literal fixed UTC-5.

**Status:** plan only. No code written yet.

---

## What changed from the first draft (refinements)

1. **Promotion does NOT reuse `startRace`.** `startRace` would (a) compute `endsAt` as `+N*24h`
   (wrong on DST days), (b) reject via the payout-preset `>=4 participants` guard, and (c)
   assumes a non-null `creatorId` (seeded races have `creatorId = null`). Use a dedicated
   `promoteSeededRace` path instead.
2. **Canonical-timezone scoring has THREE call sites, not two** — `getRaceProgress.js`,
   `raceExpiry.js` (settlement), **and `getHomeRaceCard.js`** (`checkActiveRaces` computes live
   totals via `calculateBaseAdjusted`, `:252-259`).
3. **`getHomeRaceCard` verified safe** for the PENDING leak (its public/friend suggestions are
   `status:"ACTIVE"`-only). Only `findPublicPending` and `getFeaturedRaces` need compat guards.
4. **Featured array is explicitly filtered to `status==='ACTIVE'`** rather than relying on the
   accident that a null `startedAt` loses the "most-recently-started" tiebreak.
5. **Open decisions resolved** (see below): weekly opt-in = full current week; seeded cap raised
   to 500 (+ payload-scaling caveat); a late-join *informational nudge* is included (distinct
   from the hard guardrail you declined).
6. **Reconciler spelled out** as an idempotent per-seed algorithm with ordering + cold-start.

---

## Resolved product decisions

| Decision | Choice | Why |
|---|---|---|
| Weekly opt-in window | **Full current week** (next week's PENDING race is created when this week starts) | Trivial to support and far better than a 24h window for a 7-day commitment. |
| Seeded `maxParticipants` | **Raise to 500** (from 100); treat the cap as real | Pre-registration can fill slots before start; 100 is too low for a flagship daily. **Caveat:** the progress/leaderboard payload returns *all* participants — large fields need top-N/pagination (out of scope for v1; 500 is safe today). |
| Late-join handling | **Informational nudge only** (no hard cutoff) | You chose plain Path A over the guardrail. A nudge ("race ends in 8h — opt into tomorrow's to start fresh at 12 AM") steers users to the fair path without blocking anyone. |
| `timezone` meaning | `America/New_York` (DST-aware) | US DST flips at 02:00, so **00:00 is never ambiguous** — midnight is always well-defined. |

---

## Core mechanism

At steady state, each seed (DAILY_10K, WEEKLY_50K) always has **two** live races:

```
ACTIVE :  [ M_today    , M_tomorrow )      ← running now, joinable, on the leaderboard
PENDING:  scheduledStartAt = M_tomorrow    ← opt-in target; startedAt stays NULL
          endsAt          = M_dayafter
```
…where `M_x` = 00:00 `America/New_York` for day `x` (Monday 00:00 ET for weekly).

At midnight, within one cron tick: `raceExpiry` settles the ACTIVE race; the reconciler promotes
the PENDING race to ACTIVE and creates the next PENDING. Everyone who opted in starts together.

### Why this is fair with no scoring rewrite
Scoring anchors on `effectiveStart = max(joinedAt, raceStartedAt)` (`getRaceProgress.js:319-321`,
`raceStateResolution.js:20-22`). A pre-registrant's `joinedAt` is *before* the race start, so
`effectiveStart` collapses to `raceStartedAt` = midnight — identical for every pre-registrant.
We don't touch the anchor. Someone who still joins mid-day is late *by choice* (24h notice), with
`effectiveStart` = their join time, exactly as today.

---

## Backend changes (`stepv2-backend`)

### B1. ET-midnight helpers — `src/utils/week.js`
Already has `zonedDateTimeToUtc`, `getTimeZoneParts`, `getMondayOfWeek`, and the precedent
`getNextMonday9amNewYork`. Add:
- `startOfDayNewYork(date)` → UTC instant of 00:00 ET for that date's ET day.
- `nextMidnightNewYork(date)` → 00:00 ET of the following ET day.
- `startOfWeekNewYork(date)` / `nextWeekStartNewYork(date)` → Monday 00:00 ET (reuse `getMondayOfWeek` → `zonedDateTimeToUtc({…,hour:0})`).

These make `endsAt` the **true next ET midnight** (DST-exact: 23h on spring-forward, 25h on
fall-back), not a fixed `+24h` offset.

### B2. Schema migration (additive, safe for all clients)
Add `Race.timezone String?` (nullable, default null). Seeded races set `"America/New_York"`;
user-created races stay null → existing behavior unchanged. Old clients never read it.

### B3. Rewrite `seededRaceRenewal.js` as an idempotent per-seed reconciler
Replaces the current "skip if any PENDING/ACTIVE exists" block (`:19-33`). Per active seed, in
order (wrap per-seed in a `pg_advisory_xact_lock` like `raceJoinLock.js` to be safe against
overlapping ticks):

1. **Promote**: find a PENDING race with `scheduledStartAt <= now`; if present, `promoteSeededRace(it)` (see B4).
2. **Ensure current**: re-query ACTIVE for the seed. If none covers *now* (cold start / gap),
   create one for `[startOfDay…(now), next…(now)]` as `status:"ACTIVE"`, `timezone:"America/New_York"`.
3. **Ensure next**: if no PENDING race exists for the seed, create it: `status:"PENDING"`,
   `scheduledStartAt = next…(now)`, `endsAt =` the midnight after that, `timezone:"America/New_York"`,
   **`startedAt: null`**, `isPublic:true`, `maxParticipants:500`, copy `powerupsEnabled` etc. from seed.

**Tighten the cron to every 1 minute** (from 5) so the promote/settle handoff window at midnight
is ≤1 min (see "Midnight handoff" below). It's a cheap query.

### B4. `promoteSeededRace(race)` — new, dedicated (do NOT call `startRace`)
- `status:"ACTIVE"`, `startedAt = race.scheduledStartAt`, keep the precomputed `endsAt` (DST-exact).
- For each ACCEPTED participant: if `powerupsEnabled && powerupStepInterval`, init `nextBoxAtSteps`.
  (No buy-in commit — seeded races are free; no `joinedAt` reset needed — `max()` already yields midnight.)
- Emit the `RACE_STARTED` event/notification to ACCEPTED participants (mirror `startRace.js:114`)
  so pre-registrants get a "your race just started" push at midnight.

### B5. ⚠️ Compat guard A — `models/race.js findPublicPending` (`:194-210`)
Today returns `isPublic + status IN (PENDING,ACTIVE)`. A PENDING seeded race (public, null creator)
would leak into `/races/public` on **old clients** with a misleading "ends in" countdown.
**Fix:** exclude PENDING *seeded* races (only surface seeded races there when ACTIVE). No-op for
today's behavior (seeded races are always ACTIVE now).

### B6. ⚠️ Compat guard B — `queries/getFeaturedRaces.js`
It keeps the most-recently-*started* race per seed (`:32-38`); a future-`startedAt` PENDING race
could shadow the live one on old clients.
**Fix:**
- Partition `findLiveSeeded()` results by status. The **returned array stays ACTIVE-only** (same
  shape → old clients byte-identical).
- Attach an additive field to each ACTIVE card:
  ```jsonc
  "upcoming": {
    "raceId": "…",
    "scheduledStartAt": "2026-06-26T04:00:00.000Z", // ISO UTC; client renders .toLocal()
    "participantCount": 12,
    "maxParticipants": 500,
    "isFull": false,
    "myStatus": "ACCEPTED" | null   // null → render "Opt in"; ACCEPTED → "You're in ✓"
  }
  ```
  New clients render it; old clients ignore the unknown field.
- Fix `isFull` to treat `maxParticipants == null` as unlimited (today `|| 100` at `:47`).

### B7. `getHomeRaceCard.js` — verified safe, but needs the tz change
No leak fix needed (public/friend suggestions are `status:"ACTIVE"`-only, `:434-441`/`:347-351`).
But `checkActiveRaces` computes live totals (`:252-259`) → must use the canonical race tz (B8).

### B8. Canonical-timezone scoring (also fixes the live-vs-settlement UTC divergence)
Add helper `raceTimeZone(race, fallback)` → `race.timezone || fallback`. Apply at **all three**
`calculateBaseAdjusted` call sites:
- `getRaceProgress.js` (`:275`,`:311`): `raceTimeZone(race, requesterTimeZone)`.
- `raceExpiry.js:67`: replace hardcoded `"UTC"` with `raceTimeZone(race, "UTC")`.
- `getHomeRaceCard.js checkActiveRaces` (`:252`): `raceTimeZone(race, timeZone)`.

Now seeded races bucket steps in ET everywhere → live == home == settlement, and "midnight" is the
same instant for every participant globally. User-created races (`timezone` null) keep their current
fallback behavior. Invisible to old clients (they only render `totalSteps`).
See `[[race-live-vs-settlement-tz-divergence]]`.

### B9. Start-day rule — required for daily reliability
A midnight-aligned daily race is **exactly one ET day**, so the *whole race* is the "start day,"
which today trusts **hourly samples only** (`getRaceProgress.js:343-351`,
`raceStateResolution.js:56-65`). A device that syncs daily totals but not hourly samples would show
0 all day. But when `effectiveStart` sits on a local-midnight boundary, pre-race steps that day are
impossible, so the daily total is safe.
**Fix:** when `effectiveStart === startOfDay(effectiveStart, raceTimeZone)`, use `max(daily, samples)`
for the start day (like subsequent days). Late joiners (mid-day `effectiveStart`) stay sample-only —
still correct.

### B10. Weekly
Same pattern aligned to Monday 00:00 ET; next week's PENDING race created when the current week
starts (≈7-day opt-in window). Canonical-tz scoring removes the multi-day UTC settlement skew.

---

## Frontend changes (`stepv2-frontend`, ships in a new app build)

### F1. Featured "Tomorrow" card
- Model (`backend_api_service.dart` fetchFeaturedRaces): parse the new `upcoming` object.
- Render it as a distinct **"TOMORROW"** card (data rides on the live ACTIVE card; the *new client*
  draws it as its own card — old clients never see it). Show a **countdown to `scheduledStartAt`**
  ("Starts in 7h 12m") via the existing `.toLocal()` formatter, and a CTA:
  `myStatus == null` → **Opt in**; `ACCEPTED` → **You're in ✓**; `isFull` → **Full**.
- Opt-in calls the existing join endpoint with `upcoming.raceId` (PENDING join already works).

### F2. Race detail — seeded-PENDING state
`race_detail_screen.dart` PENDING branch is built for user-created races (creator/START button).
Add a seeded-PENDING variant: **no START button** (users can't start seeded races), just
"You're in — starts in Hh Mm" using `_formatScheduledStart` (`:304-310`). Generalize the countdown
helper to a "starts-in → then ends-in" mode for PENDING races.

### F3. Late-join nudge (informational)
On the live race's JOIN affordance, when `upcoming` exists, add copy like
"Joins now · ends in 8h — or opt into tomorrow's race to start fresh at 12 AM." No blocking.

---

## What old app versions see (the compatibility contract)
- `/races/featured`: same ACTIVE daily/weekly cards, same array shape (+ ignored `upcoming` field).
  Start times are simply predictable now.
- `/races/public`: unchanged (PENDING seeded races excluded).
- `/home/race-card`: unchanged (only ACTIVE races surfaced).
- They keep joining the live race mid-day exactly as today; they just lack the opt-in feature.
- **Net: zero breakage.**

---

## Midnight handoff (the one timing subtlety)
Between 00:00 and the next cron tick, the old race is `ACTIVE`-but-expired and the new one is still
`PENDING`. During that gap `getFeaturedRaces` filters the expired race (`:30-31`) and the new one
isn't ACTIVE yet → the daily card can briefly disappear. With the 1-minute cron (B3) the gap is
≤1 min. Acceptable; no special-casing needed.

---

## Rollout
1. **Migration** for `Race.timezone` (additive).
2. **Backend deploy** — safe for all client versions. Per backend `CLAUDE.md`, don't pipe
   `migrate deploy` through `tail` (it masks `set -e`); see `[[backend-deploy-pipe-masks-set-e]]`.
3. **One-time cutover** (admin script): for each currently-rolling seeded ACTIVE race, set
   `endsAt = nextMidnightNewYork(now)` and `timezone = "America/New_York"`, then create the first
   PENDING race for the following window. Expect one slightly-short transition race, then perfect
   alignment. (The reconciler's "ensure current" is only a safety net for true gaps.)
4. **Frontend** opt-in UI in the next app version — **build iOS + Android in lockstep** with
   matching flavor / `--dart-define=BACKEND_BASE_URL` / version (frontend `CLAUDE.md`).

---

## Tests
- `week.js`: `nextMidnightNewYork` on spring-forward (2026-03-08 → 23h day) and fall-back
  (2026-11-01 → 25h day); Monday-00:00 weekly boundaries.
- `seededRaceRenewal`: reconciler creates current+next, promotes a due PENDING (even with 1
  participant, `creatorId` null), is idempotent across ticks, recovers from a cold/empty DB.
- Compat: a PENDING seeded race never appears in `findPublicPending` nor the `getFeaturedRaces`
  array (only in `upcoming`).
- `getRaceProgress`: pre-registrant (`effectiveStart == midnight`) gets the daily-total fallback;
  mid-day joiner stays sample-only.
- tz consistency: live (`getRaceProgress`) == home (`getHomeRaceCard`) == settlement (`raceExpiry`)
  for a seeded weekly race spanning a day boundary for a non-ET user.

---

## Implemented (2026-06-25, on `main`)

Built per this plan. Deltas discovered during implementation:

- **Canonical-tz had 4 call sites, not 3.** Added `resolveRaceState` (the live
  placement-recompute path, `raceStateResolution.js`) alongside getRaceProgress,
  raceExpiry, and getHomeRaceCard — it also scores and writes `totalSteps`.
  Centralized via `src/utils/raceTimeZone.js`.
- **B9 needed a third edit (boundary guard).** A midnight-aligned daily race
  settles at *exactly* the ET day boundary, which made `calculateSubsequentSteps`
  add the next day's daily total to every score. Fixed with
  `if (dayStart >= now) break;` in `src/utils/raceSteps.js` (shared, so display ==
  settlement). Covered by a test (`calculateBaseAdjustedStartDay.test.js`).
- **Promotion is a dedicated path** (`promoteSeededRace` in seededRaceRenewal.js),
  not `startRace`, for the reasons above.
- **Concurrency:** used an in-process `running` guard in the scheduler instead of a
  pg advisory lock — the cron is single-process. (Revisit if prod ever runs
  multiple instances.)
- **F3 nudge** is realized as the **adjacent "TOMORROW" opt-in card** next to the
  live card, rather than extra copy on the live JOIN button.
- **Cutover** lives at `scripts/cutover-seeded-races-to-midnight.js` (`--dry-run`).
- Migration `20260625000000_add_race_timezone_bump_seed_cap` (timezone column +
  seed cap 100→500); applied to the local integration DB. **Still needs
  `prisma migrate deploy` on staging/prod at release.**

Tests added (all green): `raceTimeZone`, `weekMidnight` (incl. DST 23h/25h),
`getFeaturedRaces` (no PENDING-seeded leak + `upcoming`), `seededRaceRenewal`
(reconcile/promote/cold-start), `calculateBaseAdjustedStartDay` (pre-reg fallback,
late-joiner sample-only, no settlement-boundary leak), `cutoverSeededRaces`,
integration `seeded-race-prereg`, and frontend `featured_race_card`.
Pre-existing unrelated test failures in both repos were left untouched.

## Suggested PR order
1. `Race.timezone` migration + B8 canonical-tz helper at all 3 call sites (pure correctness; no behavior change for user races).
2. B5/B6 compat guards (so PENDING seeded races are safe to introduce).
3. B1 helpers + B3 reconciler + B4 promotion (the feature, backend).
4. One-time cutover script + deploy.
5. B9 start-day relaxation.
6. Frontend F1–F3 (new app build).
