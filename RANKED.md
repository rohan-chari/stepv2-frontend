# Ranked

> Status: **Design / not yet built.** This is the agreed spec, not shipped behavior.

A competitive ladder driven by walking. You earn **Ranked Points (RP)** for daily
activity, climb through tiers, and at the end of each ~monthly **season** your
final tier is locked in and rewarded. New season, soft reset, climb again.

## Locked decisions

| Decision | Choice |
|---|---|
| Model | **Hybrid** — fixed-threshold climb for lower tiers, percentile-capped top tier, seasonal soft reset |
| Tiers | **Bronze · Silver · Gold · Diamond** (no Platinum / Master / GM / Challenger) |
| Points source | **Milestone completion + steps** (blended; consistency-weighted, volume-tilted) |
| Season cadence | **Monthly** (~30-day fixed windows) |
| Rewards | **Coins + exclusive cosmetics + persistent profile badge** |

> Note: the original "goal completion" points idea was dropped because step goals
> were removed from the product (`recordSteps` writes `stepGoal: null`). The live
> equivalent is **StepMilestones** (5k/10k/15k/20k), so RP is sourced from those.

---

## Core principle: never break older app versions

Per `CLAUDE.md`, a shipped binary is frozen and the prod backend serves all
versions at once. Ranked is built so that:

- **RP derives only from data every shipped app already sends** (`{steps, date}`
  on `/steps`). No new request field. Points are computed by aggregating existing
  `Step` rows at compute time, so accrual is structurally idempotent (re-posting
  the same daily total is a no-op) and works for every frozen binary.
- All new tables/columns are **additive + nullable/defaulted**; new migration
  after `20260529000000`; past migrations are never edited.
- `GET /ranked` is a **new route** — old apps never call it. **Backend ships
  first.** New app against an old backend gets a 404; because `BackendApiService`
  throws on non-2xx, the tab **catches `ApiException` and renders an unranked
  state** rather than relying on empty-list optimism.
- The tab is **appended at PageView index 4** — never inserted mid-list, which
  would silently break the hardcoded `jumpToPage`/`animateToPage`/`onPageChanged`
  index literals in `main_shell.dart`.

---

## Ranked Points (RP)

Computed **per local day**, summed over the season. Everything is recoverable
from historical `Step` rows, so no write-path changes are required.

```
daily RP = milestone_points          # consistency: 5k→+20, 10k→+30, 15k→+30, 20k→+20  (cap 100/day)
         + floor(steps / 1000) * 1    # volume tilt: 20k steps → +20
         + streak_bonus               # +5 per consecutive ≥5k day, cap +50/day

season RP = carry_over_seed + Σ daily RP    # monotonic within a season
```

- **Consistency dominates** (a 10k/day walker ≈ 60–95 RP/day) so the ladder
  rewards showing up, not just raw leg length.
- **Volume adds a tail** for high-effort days.
- **Streak** = consecutive local days with steps ≥ 5,000 (the first milestone).
  Self-contained, computed from `Step` rows.
- Weights are **tunable** — see *Calibration* below.

Manual step entries are excluded (already `includeManualEntry: false`), as are
`isReviewAccount` users.

---

## Tiers

Three fixed-threshold tiers you climb visibly, plus a percentile-capped Diamond.

| Tier | How you get it | Divisions |
|---|---|---|
| **Bronze** | season RP in band | III / II / I |
| **Silver** | season RP in band | III / II / I |
| **Gold** | season RP in band | III / II / I |
| **Diamond** | RP ≥ Gold ceiling **AND** in the top *X%* | single (no divisions) |

**Why Diamond is percentile-capped:** with the LoL apex tiers gone, Diamond plays
the role of "the elite few." Requiring **both** RP ≥ ceiling **and** a top-%
slot prevents over-promotion on a small/early ladder (a real risk in the existing
`Math.ceil(count * fraction)` logic). Bronze→Gold stay fixed-threshold so your
tier is stable and never drops mid-season.

### Thresholds (monthly) — calibrated 2026-05-29

Calibrated against the real step distribution (see *Calibration* below) and
validated end-to-end on staging (the live job reproduces this exact spread).

```
Bronze   0 – 199      (III 0–66,     II 67–132,     I 133–199)
Silver   200 – 549    (III 200–316,  II 317–432,    I 433–549)
Gold     550 – 1,399  (III 550–832,  II 833–1,115,  I 1,116–1,399)
Diamond  RP ≥ 1,400   AND  top ~10% of ranked users
```

Every threshold sits in an empty zone between natural clusters in the data, so a
user near a boundary won't flip tiers on small week-to-week noise. Resulting
distribution on the calibration snapshot: **Bronze 27% · Silver 30% · Gold 30% ·
Diamond 12%**; the median walker lands in Silver with Gold/Diamond as climb goals.

> These are **fixed** behavioral thresholds (Gold ≈ "walk consistently all
> month"), intentionally *not* re-derived per population — so a user's tier
> reflects their real activity, not just their rank among the current user base.
> Only **Diamond** is relative (top ~10%), so it self-adjusts as the base grows.

### Soft reset

Each new season you are seeded at the **floor of one tier below** your final tier:

```
Diamond → Gold floor      Silver → Bronze floor
Gold    → Silver floor    Bronze → 0
```

Seeded **lazily** on first activity in the new season. Returning strong players
get a head start but still climb; nobody re-grinds Bronze every month. `season RP`
= `carry_over_seed + earned`, so the ladder ranks on RP (the climbing currency)
while raw season steps remain a separate display stat.

---

## Seasons

- Global, fixed **~30-day** windows.
- `Season { index, startsAt, endsAt, status: ACTIVE | SETTLING | CLOSED }`.
- Boundaries computed in **one canonical timezone** (UTC, or the backend's
  `America/New_York` default) to avoid the local-vs-UTC off-by-one. Daily RP still
  uses the device-local day already stored on `Step`.

---

## The compute job — `src/jobs/computeRanks.js`

A new in-process `setInterval` job (5-min tick), built like
`seededRaceRenewal.js` (DI factory + run-once + `setInterval`) and wired in
`src/index.js` `startServer()` next to `scheduleRaceExpiry()` /
`scheduleSeededRenewal()`. Each tick:

1. **Refresh provisional standings** for the ACTIVE season — recompute RP only
   for users who synced since the last tick (`lastStepSyncAt`), updating
   `SeasonScore.points` + provisional tier/division/rank. → near-live ladder.
2. **If `endsAt ≤ now`, settle**, guarded against double-minting by:
   - a **compare-and-swap** (`updateMany` where `status = ACTIVE` → `SETTLING`;
     0 rows affected ⇒ already rolled, skip), **and**
   - a **`pg_advisory_xact_lock('season-roll')`** inside `prisma.$transaction`
     (precedent: `raceJoinLock.js`, `rollPowerup.js` — use `tx.$executeRaw`).
   The existing jobs have no lock and only stay correct on a single pm2 fork;
   this job **mints rewards**, so the lock is mandatory.

   Settle body (mirrors `raceExpiry.js` + `completeRace.js`): final RP recompute →
   rank 1..N via the `setPlacement` loop → assign tiers (fixed thresholds for
   Bronze→Gold; Diamond by RP-ceiling AND percentile) → mint rewards → emit events
   → mark CLOSED → open next season.

Unit-tested by mirroring `test/jobs/seededRaceRenewal.test.js` (fake prisma +
fixed `now` + silent logger).

---

## Rewards (idempotent)

- **Coins** — `awardCoins({ reason: 'ranked_season_reward', refId: 'season:{id}:user:{uid}' })`,
  scaled by final tier. Stable `refId` never collides with `race_finish_reward`.
  (Note: `awardCoins` dedup is not transaction-isolated, so settlement must run
  single-threaded via the CAS + advisory lock — not rely on `refId` alone.)
- **Exclusive cosmetics** — tier-gated shop items / accessories granted at settle
  (reuse the daily-reward cosmetic-grant path). Earnable *only* through Ranked.
- **Profile badge** — denormalized `User.currentTier` / `currentDivision`
  (additive, nullable) set at settle; rendered next to the user's name in races,
  leaderboard, and profile via a small `TierBadge` (extend `PlacementPill`).
  Null tier ⇒ no badge / unranked.

---

## Frontend — the Ranked tab

Clone `lib/screens/tabs/leaderboard_tab.dart` (self-fetching, `Loadable<T>`,
skeleton/error/**unranked** states, pins *your* row when you're off-screen):

- **Header hero** — large tier badge + division, season RP, progress bar to next
  division, season countdown (`endsAt`).
- **Ladder** — `LeaderboardPlank` rows with tier section dividers; optional
  `ArcadeTabSelector` for **Global / Friends**.
- **Season end** — results sheet styled like `race_finishers_banner`, plus a
  `RANK_PROMOTED` push (self-contained text; tap degrades gracefully on binaries
  that lack a `ranked` deep-link route).

**Tab wiring (`main_shell.dart`):** append `RankedTab` at **PageView index 4** +
a 5th `WoodenTabItem` (label "Ranked"); add `if (index == 4) _fetchRanked();` to
`onPageChanged` (mirrors the existing races hook) or self-fetch like leaderboard.

> ⚠️ Verify visually: **5 tab labels at font-size 10 may clip** — each `Expanded`
> button gets narrower with a 5th item.

---

## Data model (new, additive)

| Table | Shape |
|---|---|
| `Season` | `id, index, startsAt, endsAt, status, createdAt` |
| `SeasonScore` | `id, userId, seasonId, points, rank?, tier?, division?, provisionalTier?, provisionalDivision?, provisionalRank?, createdAt, updatedAt` — `@@unique([userId, seasonId])`; ≈ `RaceParticipant` with `seasonId` |
| `SeasonDayScore` *(optional)* | `@@unique([userId, seasonId, date])` ledger for idempotent accrual — only if not recomputing from `Step` rows at compute time |
| `User` (cols) | `currentTier String?`, `currentDivision Int?` — denormalized for cheap cross-surface badges |

## Endpoints (new)

- `GET /ranked` → `{ season: {index, endsAt, status}, currentUser: {tier, division, points, rank, provisional, inTopTier} | null, ladder: [{userId, displayName, avatar, tier, division, points, rank}], cutoffs }`.
  All fields nullable; client reads defensively.

## Events / push (new)

- `RANK_PROMOTED`, `SEASON_REWARD_GRANTED` — emitted at settle, consumed by
  `notificationHandlers.js`. Keep RP accrual in the **job**, not on the
  `STEPS_RECORDED` event path (handlers are synchronous + in-request and could
  affect the `/steps` response for old clients).

---

## Known risks

- **Android background steps aren't delivered** (iOS-only `AppDelegate`) — Android
  users accrue RP only on foreground sync. Mitigate by syncing on tab open.
- **Provisional Diamond can fluctuate** as others catch up (authentic, but note it
  in the UI). Bronze→Gold are fixed-threshold and never drop mid-season.
- **Timezone off-by-one** at season boundaries if local `/steps` dates and UTC
  windows are mixed — fix the season window to one canonical TZ.

---

## Calibration

**Done 2026-05-29** against staging (synced from prod that day) over the
2026-05-01 → 05-30 window. Method: aggregate `Step` rows → per-user RP via the
formula above → percentile distribution over eligible users
(`scripts/ranked-calibration.sql` in the backend repo — re-runnable).

Snapshot: 42 users with steps; **33 eligible** (≥1 day ≥5k), 9 unranked; median
RP 448, p90 1,381, max 2,670; median 10 active days / month. Thresholds chosen to
snap to natural cluster gaps (197↔209, 471↔559, 1,004↔1,475).

> 🐛 The first calibration pass over-credited rest days (a Postgres
> `LEAST(50, NULL)` returns 50, not NULL, so every non-active day got a phantom
> +50 streak bonus). Caught by validating the live job against the calibration on
> staging — they disagreed, the app was right. The SQL is fixed; the app's JS RP
> never had the bug. Numbers above are post-fix.

> ⚠️ **N = 33 is small** — thresholds are robust because Bronze/Silver/Gold are
> fixed (behavioral) and only Diamond is relative. Re-run the calibration when the
> base grows materially (e.g. every few months or at 200+ eligible users) and
> nudge thresholds only if the cluster gaps move.

---

## Build order (each phase ships independently & compat-safe)

0. ✅ **Calibrate** thresholds from staging step data — done 2026-05-29.
1. ✅ **Backend scaffold** (built + **validated on staging** 2026-05-29; migration
   applied to **staging only — prod NOT migrated**) — in `steps-tracker-backend`:
   - migration `prisma/migrations/20260529120000_add_ranked_seasons` (+ schema:
     `Season`, `SeasonScore`, `SeasonStatus`, `User.currentTier/currentDivision`)
   - `src/constants/rankedTiers.js` (calibrated thresholds, RP formula, rewards)
   - `src/services/rankedPoints.js` (pure RP) + `rankedStandings.js` (rank/tier)
   - `src/models/season.js` (incl. advisory-lock + CAS `claimForSettlement`)
   - `src/commands/settleRankedSeason.js`, `src/jobs/computeRanks.js` (wired in
     `src/index.js`)
   - `src/queries/getRanked.js` + `src/routes/ranked.js` (mounted at `/ranked`)
   - tests: `test/services/rankedScoring.test.js`, `test/jobs/computeRanks.test.js`,
     `test/commands/settleRankedSeason.test.js` (11 passing)
   - **Validated on staging:** migration applies cleanly; the live job reproduces
     the calibration distribution (9/10/10/4) on real data; `GET /ranked` returns
     the expected shape.
   - **Remaining before launch:** apply the migration to **prod** (your call),
     review `TIER_REWARDS` coin amounts (they mint real coins), and decide
     calendar-month vs rolling-30-day season windows.
2. ✅ **Frontend** (built 2026-05-29) — `lib/screens/tabs/ranked_tab.dart`
   (self-fetching; tier hero + ladder; unranked, old-backend-404 "coming soon",
   error, and loading states; pins your row when off-window), `fetchRanked()` on
   `BackendApiService`, shell wiring in `main_shell.dart` (5th `PageView` child at
   **index 4** + 5th `WoodenTabItem` + refresh-on-reveal nonce), an in-file
   `_TierBadge`, and `test/ranked_tab_test.dart` (3 passing; `dart analyze` clean).
   - **Decision:** the nav label `Leaderboard` was shortened to **`Boards`** so all
     5 labels fit at font-size 10 (the clip risk). Tab *content* title is unchanged.
     Tutorial mock updated to match. Easy to revert if you'd rather keep
     "Leaderboard" (and accept truncation on small screens).
   - **Not yet done:** a shared cross-surface `TierBadge` (Phase 3 — render the
     denormalized `User.currentTier` in races/leaderboard/profile), and a live
     progress-to-next-division bar (backend doesn't yet return the next cutoff).
3. **Rewards** — cosmetic grants (coins + `User.currentTier` done in scaffold),
   cross-surface badges
4. **Notifications** — `RANK_PROMOTED` / season-end push + deep link
   (`SEASON_REWARD_GRANTED` is already emitted; needs handlers)

## Open tunables (defaults proposed; not blockers)

RP weights (current formula calibrated, but re-tunable) · Diamond percentile
(~10%) · soft-reset drop depth (one tier) · points name ("RP") · Friends-ladder
filter (recommend yes).
