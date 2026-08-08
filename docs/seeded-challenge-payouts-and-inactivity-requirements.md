# Seeded Challenge Top-Heavy Payouts + Inactive-Participant Pruning — Requirements

Status: FINAL DRAFT — awaiting owner approval (Phase 4 gate). Do not implement until approved.

## 1. Summary & user story

Two coupled changes to the auto-seeded Daily/Weekly Challenge races (seed kinds
`DAILY_10K` / `WEEKLY_50K`, renamed in-DB to "Daily Challenge" / "Weekly
Challenge" on 2026-08-05):

**A. Top-heavy payouts.** New seeded challenge races pay their funded TOP_HALF
pool on the existing geometric decay curve (ratio 0.7, 1-coin floor) instead of
even shares. Winning the daily should feel like winning, not like tying with
149 people.

> As a competitive user, I want finishing 1st in the Daily/Weekly Challenge to
> pay dramatically more than scraping into the top half, so placement is worth
> chasing.

**B. Inactivity pruning.** Users who recorded zero steps on each of the
previous two completed days are removed from (and not auto-enrolled into)
seeded challenges — at enrollment, at promotion (race start), and via a daily
mid-race sweep of the ACTIVE weekly — so dead accounts stop cluttering the
field and inflating the advertised (projected) prize pool. Brand-new accounts
are exempt — they have no history to judge.

> As an active user, I want the challenge field to consist of people actually
> playing, so the advertised pool/paid-places reflect reality and my rank isn't
> propped up by ghosts.

**Owner decisions locked (2026-08-05 interview — ALL open questions resolved):**
- D1: Curve = geometric, ratio 0.7, 1-coin floor (the existing
  `distributeGeometric`, `racePayoutPresets.js:83-106`). 1st ≈ 30% of pool.
- D2: Scope = seeded challenges only. User-created funded TOP_HALF races keep
  the even split (shipped clients' create-screen copy "splits evenly" stays
  true for them).
- D3: Prune targets **every** 2-day-zero ACCEPTED participant regardless of
  how they joined (auto-enroll, manual JOIN, settings toggle). No
  enrollment-source column. Accepted consequence, stated plainly: a user who
  explicitly opts in and then rests two days is removed like anyone else
  (including the weekly weekend-rester — accepted).
- D4: Mid-race sweep = **weekly only**, once per ET day, and only for
  participants with **zero steps in the race so far** (ghost removal — a
  competitor who walked early in the week then rested keeps their earned
  position). The daily is boundary-only (enrollment + promotion).
- D5: Pruning is **silent** — no push, no in-app record.
- D6: Projection→settlement 1st-place shrink under geometric: accepted with
  disclosure — the new client card labels the figure "projected"; server math
  unchanged.

### What research changed about the framing (read this first)

- **Settlement is NOT currently skewed by zero-steppers.** For funded races,
  pool minting and paid-place count already use only walkers:
  `settlementPlayerCount` requires `ACCEPTED && placement != null &&
  (totalSteps||0) > 0` (`racePrizePool.js:35-42`), and walkers always outrank
  zero-steppers, so zero-steppers can never capture a payout slot
  (`completeRace.js:286-325`). What zero-steppers DO skew:
  - the **live projection** — projected pool & tier count use raw
    `acceptedCount` including zero-step joiners (`racePrizePool.js:110-138`),
    so the lobby over-promises vs. what settles;
  - the **visible field** — standings length, "N racing" copy, and everyone's
    nominal rank denominator.
  Pruning fixes both; it does not change who gets paid.
- **"Zero steps" ≈ "no data" in practice.** Clients drop zero-step buckets at
  the source (`AppDelegate.swift:911`, `health_service.dart:282-338`) and only
  write a daily `steps` row when a sync actually runs; a user who doesn't open
  the app for two days typically has NO rows for those days. The predicate
  therefore treats *absence* of data as zero (see §4.2) and protects new
  accounts by `createdAt`, not by data presence.
- **The curve must be a property of the RACE ROW, not of read-time logic**
  (gap pass 1, F1/F2). The funded read path recomputes payouts on every read —
  even for completed races (`racePrizePool.js:109-138`) — and the codebase's
  own rule is that a payout table must never change shape underneath an
  in-flight or settled race (`racePayoutPresets.js:145-147`). Keying the curve
  off `seedId` at read time would (a) rewrite the displayed tiers of every
  *historical* seeded race to numbers that were never paid, and (b) flip an
  ACTIVE weekly's advertised split mid-race at deploy. Hence `payoutCurve` is
  **stamped at race creation** (§4.1) — the same discriminator pattern as
  `fundedPrize` (`completeRace.js:279-285`).

## 2. Scope / non-goals

In scope:
- New `Race.payoutCurve` discriminator stamped by `createSeededRace`;
  geometric funded payouts wherever the row says so (projection + settlement,
  same function — they can never disagree).
- Inactivity filter at seeded-race auto-enrollment (`enrollAutoJoinUsers`),
  prune at promotion (`promoteSeededRace`), and a once-per-ET-day mid-race
  sweep of the ACTIVE weekly (§4.3 Hook 3) — all behind ONE kill-switch flag.
- One additive migration (§4.4): `races.payout_curve`.
- Frontend polish (next regular app release, non-blocking): friendly 403
  state on race detail, auto-join toggle copy, top-heavy payout summary card.

Non-goals:
- No change to user-created funded races' split (D2) — their `payoutCurve`
  stays NULL (= even for graded presets).
- No change to already-created races of any kind: NULL `payoutCurve` rows
  (everything pre-deploy, including in-flight and completed seeded races)
  read, settle, and display exactly as today.
- No change to legacy buy-in pot math (`computeRacePayouts`).
- No change to tournaments — verified unreachable, not assumed: bracket
  matchup races are created with NO `seedId` and
  `payoutPreset: "WINNER_TAKES_ALL"`
  (`src/modules/tournaments/services/tournamentRounds.js:38-63`), and
  `completeRace`'s tournament branch early-returns before the funded-payout
  block (`completeRace.js:84-141`). A cheap regression test pins this (§7).
- No mid-race sweep of the DAILY (D4) — its field was filtered at enrollment
  and pruned at promotion hours earlier with nearly the same window.
- No *blocking* of manual joins (`joinPublicRace`) or the settings-toggle
  path at join time — anyone may join/opt in at any moment regardless of
  history. (Per D3, their row is later prunable like any other if they stay
  at 2-day-zero; joining is not a shield, it's just never refused.)
- No blocking of the signup auto-enroll path (`autoEnrollNewUser.js` —
  separate command, untouched by construction; it force-enrolls new accounts
  and grants welcome boxes; new accounts are exemption-protected, §4.2).
- No prune notifications (D5).
- No new "inactive user" concept anywhere else in the app.

## 3. API contract

**No new endpoints. No new request fields. No removed response fields.**

Changed semantics (all additive-safe for frozen clients):

1. `payoutTiers[]` / `payouts{first,second,third}` for a seeded funded race
   **created after the flag is enabled** carry geometric amounts instead of
   equal amounts. Shape unchanged. Payout fields are emitted by exactly THREE
   read paths — `getRaceDetails.js:44`, `getRaces.js:186`,
   `getPublicRaces.js:48` (via `serializePayouts`); `getFeaturedRaces` and
   `getSharedRacePreview` emit only `prizePool`/`myStatus`-shaped data and
   carry no tiers (gap pass 2, G2 — the earlier "every read path" claim was
   wrong). Frozen clients render whatever numbers arrive. Historical and
   in-flight races are untouched (NULL curve).
   - Shipped-client behavior verified: the race-detail "even split" summary
     card gates on the **actual tier amounts being equal**
     (`race_detail_screen.dart:5820-5821 _isEvenSplitPayout`), not the preset
     string — unequal tiers automatically fall back to the podium row
     ("1ST / 2ND / 3RD / +N MORE") with the full tier list one tap away.
     Nothing lies, nothing crashes.
   - `payoutCurve` itself is NOT serialized to clients (nothing needs it;
     amounts speak for themselves). May be added later if a client wants to
     label the curve.
2. A pruned/swept user's `RaceParticipant` row is hard-deleted, so the race
   silently drops out of `GET /races`, `GET /races/featured` /
   `discovery-summary` (`myStatus: null`), and `GET /home/race-card` on the
   next poll. All membership is server-derived; the frontend persists no
   membership locally (verified — only the auto-join *preference* is in
   SharedPreferences).
3. `GET /races/:id/details` for a pruned user returns the **existing** 403
   `"You are not a participant in this race"` (`getRaceDetails.js:20-34`).
   Frozen clients show today's rough-but-safe behavior: raw-message toast over
   a "Failed to load race" body on open, and a *repeating* "Couldn't refresh
   race progress." toast every 30s if the screen was already open
   (`race_detail_screen.dart:827-836`). The new build gets a friendly state
   that also stops the poll (§5).
4. **Projection→settlement disclosure (gap pass 2, G3 — accepted as D6).**
   The live projection sizes the pool and tiers from `acceptedCount`
   (zero-steppers included, `racePrizePool.js:110-117`); settlement uses
   walkers only. Under the even split this barely moved the per-head figure
   (pool and slots both scale with the field: daily ≈ 40/head either way —
   ghosts only changed the tier *count*). Under geometric, 1st ≈ 30% **of the
   pool**, so the counted-field gap lands concentrated on the top spots: 300
   accepted / 120 walkers ⇒ projected 1st ≈ 1,800 but settled 1st ≈ 720.
   Pruning + the weekly sweep shrink this gap (dead accounts leave the count)
   but race-window no-shows remain. Mitigation in §5.3: the new client card
   labels the 1st-place figure as projected. Frozen clients simply see the
   number shrink at settlement — safe, but new.

Error cases: none new. Backend compat for older app versions: items 1–4 above
are the whole story — no client-version gating needed for the payout change or
the prune (both are server-side truths every client version already renders
defensively).

## 4. Backend design

### 4.1 Feature A — geometric seeded payouts, stamped at creation

**Schema:** `Race.payoutCurve String? @map("payout_curve")` — nullable text,
no default, no backfill. Semantics: `NULL` = today's behavior (even split for
graded presets); `"GEOMETRIC"` = geometric decay for graded presets. Only
`createSeededRace` ever writes it.

**Flag:** `seededGeometricPayoutsEnabled`, registered in `KNOWN_FLAGS`
(`src/shared/config/appSettings.js:12-77` — note `setFlag` REJECTS unknown
keys, `appSettings.js:144-149`; registration auto-surfaces it on the admin
flags screen; reads have a ~30s cache, `appSettings.js:81`). Default `false`.
`createSeededRace` (`seededRaceRenewal.js:46-95`) consults it **at creation**:
flag ON → stamp `payoutCurve: "GEOMETRIC"`. Flag OFF later → only *future*
races revert; already-stamped races keep their advertised curve to settlement
(exact `fundedPrize` semantics — the row is the authority, never the live
flag, `completeRace.js:279-285`).

**Math:** `computeFundedPayouts({ preset, poolCoins, participantCount,
curve = null })` (`racePayoutPresets.js:148-157`): when `curve ===
"GEOMETRIC"` and the preset is graded (TOP_HALF / ALL_BUT_LAST), use
`distributeGeometric(pool, slots)` instead of `distributeEvenly(pool,
slots)`. Slot count is unchanged (`gradedSlotCount` — still `ceil(field/2)`),
so paid-place counts and every `.length` consumer are unaffected.
`distributeGeometric` is numerically sound at 150 slots (0.7¹⁴⁹ ≈ 8e-24, no
underflow; sum-to-pot and monotonicity hold by construction). Zero-amount
tiers are unreachable under the 16,000-coin cap (would need a >32,000 field),
and doubly defended anyway: settlement skips `amount <= 0`
(`completeRace.js:305-308`) and the client drops zero tiers
(`race_payouts.dart`).

**Call sites** (pass `curve: race.payoutCurve ?? null`):
- `racePrizePool.js:134` (projection + post-settle read path).
- `completeRace.js:299` (settlement; race loaded via `findById` include —
  carries all scalars).
- `placementRecompute.js:310` — pass for consistency; only `.length` is used,
  identical either way (both distributions return exactly `slots` entries).
  NOTE its race query is a **lean select** (`models/race.js:446` area) —
  `payoutCurve: true` must be added there.
- Every `buildRaceMoneyView` / `serializePayouts` caller
  (`racePrizePool.js:68,145` — gap pass 2, G8: earlier drafts named a
  nonexistent `buildRacePrizeFields`) loads the race via full-row `include`
  (`getRaceDetails`→`findById` `race.js:39-52`; `getRaces`→
  `findSummariesForUser` `race.js:241-258`; `getPublicRaces`→
  `findPublicPending` `race.js:339-360`), so the new scalar arrives
  automatically — but this presence is **implicit** and a future lean-select
  refactor would silently downgrade to even. §7 therefore pins geometric
  tiers with an integration assertion on each of the THREE tier-emitting
  read paths (gap pass 1 F6, corrected by gap pass 2 G2).

Worked example (300 walkers, 6,000-coin pool, 150 paid): 1st ≈ 1,756, 2nd ≈
1,229, 3rd ≈ 861, 10th ≈ 71, ~22nd onward = 1-coin floor (rank 18 still pays
≈5). Sum equals the pool exactly (remainder to 1st, existing convention).

Non-funded legacy branch (`completeRace.js:334-341`) is untouched: if
`fundedPrizePoolsEnabled` is ever flipped off, seeded races revert to the
legacy graded finish reward exactly as today.

### 4.2 Feature B — the inactivity predicate

A user is **inactive** at evaluation instant `t` iff, for BOTH of the two most
recent *completed* ET calendar days D-1 and D-2 (America/New_York — the seed
timezone, `seededRaceRenewal.js:20`):

```
max( sum(step_samples within the ET-day UTC window), any steps-daily-row ?? 0 ) == 0
```

…AND none of these exemptions apply:
- `user.createdAt >= startOf(D-2, ET)` — the account hasn't existed for the
  full two-day window (**the new-user protection**).
- Promotion prune + weekly sweep only: `user.createdAt >= race.createdAt` —
  the account was born after this race row was minted, i.e. signup
  auto-enrolled into it. The weekly's PENDING row exists up to 7 days before
  promotion (`seededRaceRenewal.js:206-221`), so the 2-day rule alone would
  prune a Tuesday signup who never granted health permission from the very
  race onboarding promised them ("We saved you a spot in both",
  `onboarding_flow.dart:908-913`). This exemption keeps that promise for the
  full pre-start window (gap pass 1, F4). From their *second* window onward
  they're subject to the normal rule.
- `user.isReviewAccount == true` — review accounts must keep their demo state
  (note `Steps.findRowsInRange` excludes review accounts by default — do NOT
  use that helper here, or review accounts would all read as inactive; use
  `Steps.findByUserIdsAndDateRange`, which doesn't filter —
  `steps.js:44-53`, verified filter-free).

Deliberate consequences (owner-accepted, D3):
- An *old* account that has never synced anything (`lastStepSyncAt == null`)
  IS inactive — it has zero steps for the window and is not new.
- A user who synced but genuinely walked 0 both days IS inactive (rare —
  requires the app to have synced a 0-total day, `AppDelegate.swift:817-823`).
- The **weekly** challenge promotes at Monday 00:00 ET, so its promotion
  prune judges Saturday + Sunday — a weekend-rester gets pruned from the
  weekly (accepted; they can re-join manually, and they re-qualify for
  auto-enroll as soon as they walk).
- Manual joiners and toggle opt-ins are prunable like anyone else (D3).

Implementation (no N+1, patterned on `getHomeRaceCard.js:228-330` prefetch):
1. Compute the two ET day windows once via `zonedDateTimeToUtc` /
   `getTimeZoneParts` (`src/shared/time/week.js`) — DST-exact.
2. One `StepSample.findRowsForUsersInRange(userIds, D2start, D1end)`
   (`stepSample.js:276-291`) → per-user per-day sums in memory. Bucket each
   sample by **periodStart's ET day** — the signal is binary zero/non-zero,
   so proration precision is irrelevant.
3. One daily-rows query with a **lower bound only**: `steps.date >= D-3`
   (gap pass 1 F5, widened again by gap pass 2 G6): `steps.date` is the
   client-asserted *local* date, so an active user in a tz ahead of ET (whose
   only data path is daily rows — e.g. a very old binary, or samples failing
   while the daily post succeeds) may key their activity to local date `D` or
   even `D+1`; any non-zero row from D-3 onward marks the user active
   (future-dated rows can only *keep* someone — over-keeping is explicitly
   safe, over-pruning is a frozen-client violation). Sample sums still use
   the exact two ET windows.
   **Mechanics pinned (gap pass 2, G5):** the bound is an ET-*calendar date
   string* converted to a UTC-midnight Date (matching `@db.Date` storage),
   NOT the `startOfDayNewYork` window instant (04:00/05:00 UTC — that would
   silently narrow the range past the D-3 boundary row; the tempting
   `getHomeRaceCard.js:249-264` precedent passes instants and must not be
   copied here). `D` is derived via `getTimeZoneParts(now,
   "America/New_York")`, never `now.toISOString().slice(0,10)` (after 20:00
   ET the UTC date is already D+1). Unit test 15 covers an evening-ET
   evaluation instant.
4. One `prisma.user.findMany` select `{ id, createdAt, isReviewAccount }`.

Helper lives in `src/modules/races/services/seededInactivity.js` as
`filterInactiveUserIds({ userIds, now, raceCreatedAt, prisma }) ->
Set<userId>` so all three hook points share one implementation and one test
surface.

### 4.3 Feature B — hook points (all three, ONE flag)

Kill switch: app-settings flag `seededInactivityPruneEnabled`, registered in
`KNOWN_FLAGS` (same registration mechanics + 30s read cache as §4.1's flag —
convergence well inside the 60s reconcile tick). Default **false**. Enable on
staging first, then prod. No deploy to toggle. One flag governs all three
hooks (they are one policy).

No enrollment-source column (D3 — interview removed gap-pass-1's
`autoEnrolled` design): the prune targets every ACCEPTED row that fails the
predicate, so nothing needs to record how a row was created. (Seeded races
can only ever contain ACCEPTED rows — invites require a creator and seeded
races have `creatorId: null`; both enroll paths and `joinRaceCore` write
ACCEPTED explicitly. Adding `status: "ACCEPTED"` to the deleteMany is
harmless belt-and-braces.)

**Hook 1 — enrollment filter.** `enrollAutoJoinUsers`
(`autoJoinFeaturedRaces.js:50-61`): after selecting opted-in users, drop
inactive ones (2-day rule; the race is being created now, so the
race-createdAt exemption is vacuous) before the capacity slice + `createMany`.
Applies wherever the renewal cron enrolls (`created-active` cold start and
`created-upcoming` steady state, `seededRaceRenewal.js:196-220`). The
toggle-ON path (`optUserIntoPendingSeededRaces`, `:66-81`) shares the
`enroll()` helper but is NOT filtered (joining is never refused, §2); its
rows are simply prunable later like all others. Membership is otherwise
decided at PENDING-creation — up to 24h (daily) / 7d (weekly) before start —
which is why Hooks 2 and 3 exist.

**Hook 2 — promotion prune.** In `promoteSeededRace`
(`seededRaceRenewal.js:122-165`), **compute the inactive set BEFORE flipping
the race ACTIVE** (gap pass 1, F10: the predicate is 3 bulk queries; doing it
while the race is still PENDING closes the window where soon-pruned users are
briefly live — visible to step syncs and getFeaturedRaces, and racing a
concurrent box init). Order of operations:
1. Fetch ACCEPTED participants of the still-PENDING race.
2. Run `filterInactiveUserIds` over all of them, with the `raceCreatedAt`
   exemption.
3. `raceParticipant.deleteMany({ where: { raceId, userId: { in: inactive },
   status: "ACCEPTED" } })` — **deleteMany, not per-row delete** (gap pass 1,
   F9): naturally idempotent, so a pm2 cluster reload double-running the
   promotion (`index.js:59-66` documents the cross-process exposure; the flip
   at `seededRaceRenewal.js:131` is not a compare-and-set) cannot throw
   P2025. `RacePowerup`/`RaceActiveEffect` cascade on participant delete
   (`schema.prisma:1150,1192`), and at promotion instant no boxes/effects
   exist yet — side-effect-free. (Concurrency: a user who manually re-joins
   between compute and delete had their OLD row in the computed set; the
   deleteMany may remove the fresh row too — consistent with policy, since
   they are still 2-day-zero, and they can join again.)
4. Flip ACTIVE, init `nextBoxAtSteps`, emit `RACE_STARTED` — the `accepted`
   refetch at `:133` now excludes pruned users, so they get neither box
   thresholds nor the "your race started" push. This guarantee is end-to-end:
   the push handler iterates the **payload's** `participantUserIds`
   (`notificationHandlers.js:296-331`) and the only other consumer is a log
   line (`eventHandlers.js:52-54`) — no refetch anywhere.

**Hook 3 — weekly mid-race sweep (D4).** Once per ET day, sweep the ACTIVE
race of every seed with `cadence === "WEEKLY"`:
- **Scheduling:** runs inside the existing 60s `renewSeededRaces` tick,
  gated by `JobRun.claimRun("seeded_weekly_sweep:" + race.id, etDayKey(now))`
  (atomic CAS — the pm2-cluster-safe primitive; NEVER `markRan`, and never an
  advisory lock held across the callback — the 3e6c827 outage rule). Target
  hour 03:00 ET (aligns with the retention job's quiet window; the exact hour
  is not load-bearing).
- **Eligibility (both conditions, plus §4.2 exemptions):**
  a. fails the 2-day predicate (`filterInactiveUserIds`, with the
     `raceCreatedAt` exemption), AND
  b. has **zero steps in the race so far** (D4 ghost guard): persisted
     `RaceParticipant.totalSteps == 0` AND, for the surviving candidates
     only, a bulk race-window activity check (sample-sum + daily rows from
     the race's start ET-day to now — same primitives as §4.2) confirms
     zero. A competitor who walked earlier in the week then rested is
     untouchable. (An unsynced walker is indistinguishable from a ghost by
     definition; if swept, re-joining restarts them from `joinedAt` — edge
     accepted, they were ≥2 days unsynced.)
- **Side-effect guard:** skip any candidate holding a `RacePowerup` row or
  appearing in `RaceActiveEffect` for this race (as caster or target). A
  zero-step participant normally has neither (boxes require 2,000 steps),
  but store-bought powerups/cast debuffs are possible; deleting such a row
  could cascade into effects that alter OTHER participants' scoring
  mid-race. The implementer MUST verify the `RaceActiveEffect` FK relations
  before relying on cascades here; skipping is the safe default and costs
  nothing (such users are rare and remain payout-harmless).
- **Removal:** same idempotent `deleteMany` shape as Hook 2. Silent (D5).
  Fail-open: any error logs and skips the race, never blocks the tick.

Prune failures everywhere are try/catch-swallowed (log + continue), and a
total predicate failure must never block promotion or the tick — the
challenge running matters more than the prune (same posture as `autoEnroll`,
`seededRaceRenewal.js:101-115`).

**Removal mechanism: hard-delete, not DECLINED.** `joinRaceCore` blocks
re-join on ANY existing row, not just DECLINED (`joinRaceCore.js:230-236`
ALREADY_RESPONDED) — so hard-delete is the *only* re-joinable option. A
DECLINED row would also hide the race from every list permanently. Precedent:
`kickRaceParticipant.js:66`.

**Re-entry story (self-healing):** pruned user walks today → tomorrow's
enrollment includes them again automatically (predicate recomputed fresh each
time; no state accumulates). Same day, they can tap JOIN on the featured card
(`joinPublicRace` — no inactivity check), capacity permitting; pruning frees
the slots it vacates (`remainingCapacity` counts ACCEPTED rows,
`autoJoinFeaturedRaces.js:25-32`). Once they have any step activity, no hook
touches them again.

**No notification to pruned users (D5):** they are by definition not using
the app; a push "you were removed for inactivity" reads punitive. The
unconsumed `RACE_PARTICIPANT_KICKED` event exists if we ever change our mind.

### 4.4 Data model / migrations

One additive, default-safe migration (no backfill, instant on prod PG 18):
1. `races.payout_curve TEXT NULL` — NULL = even (all existing rows), written
   only by `createSeededRace`.

(The gap-pass-1 `race_participants.auto_enrolled` column was REMOVED by
owner decision D3 — the prune no longer distinguishes enrollment source.)

Deploy-order safety: old backend code running against the migrated schema
(pm2 reload window) simply never reads/writes the column; new code reading a
NULL `payoutCurve` behaves exactly as today. No prod-DB scripts; both flags
ride the existing app-settings row mechanism.

## 5. Frontend plan (non-blocking; next regular release; iOS + Android from the same Dart code)

Load `mobile-design` + `frontend-design` skills before any UI work (standing
rule). All items degrade safely against an older backend (they key off data
already present or absent today).

1. **Race-detail 403 state** (`race_detail_screen.dart:663-726`, `:2828-2837`).
   Detect `ApiException.statusCode == 403` on details load (`ApiException`
   carries `statusCode`; attached on every non-2xx —
   `backend_api_service.dart:28-36`, `:2991-3018`) → render a purpose-built
   empty state ("You're not in this race" + a "Find it on Races" button that
   pops to the Races tab) instead of the raw-message toast over "Failed to
   load race". Also the mid-session case: if the 30s progress poll 403s
   (`:826-836`), STOP polling and swap to the same state — today's behavior is
   a repeating error toast every 30s over a stale interactive screen. States:
   loading / loaded / not-a-participant / generic-error.
2. **Auto-join toggle copy** (`public_races_screen.dart:1272`).
   "Auto-enters you into each new challenge." → "Auto-enters you into each
   new challenge while you're active." (exact copy at implementer's
   discretion, must mention the activity condition). One string only — the
   pinned card reuses the same `_FeaturedAutoJoinToggle` widget
   (`public_races_screen.dart:837-843`), no duplicate.
3. **Top-heavy payout summary card** (`race_detail_screen.dart:5806-5835`;
   BOTH gating call sites: `:3214` prize-pool sheet and `:3396` main card —
   gap pass 2, G7). Gate on **graded preset AND unequal tiers**
   (`payoutPreset` TOP_HALF/ALL_BUT_LAST with a preset-agnostic fallback
   headline, mirroring `_evenSplitHeadline`) — NOT on "tiers descending"
   alone, which would misfire on legacy buy-in graded races and TOP3 presets
   that already serve descending tiers and today correctly render the podium
   row. Show "Top half wins — bigger prizes up top", the 1st-place amount
   **labelled as projected** (D6/§3 item 4 — it can shrink at settlement),
   the viewer's projected amount at their current rank, and the cut line —
   reusing the figures already in `payoutTiers` (server owns the math; no
   client-side computation). Falls back to the podium row when tiers are
   absent (older backend).
4. **Onboarding copy check** (`onboarding_flow.dart:908-913`): "We saved you a
   spot in both" stays true — new accounts are protected by BOTH the 2-day
   rule and the race-createdAt exemption (§4.2), covering the weekly's full
   7-day pre-start window. No change required; noted for awareness.

Missing-field degradation: none of 1–3 depend on new backend fields; a newer
app against an older backend renders exactly today's behavior.

## 6. Backward-compat & rollout

Deploy order:
1. `prisma migrate deploy` (one additive column; NOTE the deploy-footgun
   memory: never pipe `migrate deploy` through `tail` — it masks `set -e`).
2. **Backend deploy** (both features; BOTH flags ship OFF — zero behavior
   change at deploy).
3. Staging: flip both flags ON → observe one full daily cycle (creation →
   promotion-prune → settlement) plus one weekly-sweep firing → verify
   geometric tiers on the three tier-emitting read paths and prune/sweep
   counts in logs.
4. Prod: flip `seededGeometricPayoutsEnabled` ON (next-created races get the
   curve; in-flight races finish on their advertised even split), then
   `seededInactivityPruneEnabled` ON.
5. Frontend items ride the next App Store/Play release (phased ~a week; no
   coupling — old builds are fully served by 1–4).

Frozen-client audit (the #1 rule):
- Payout numbers: server-computed; legacy `payouts{first,second,third}` and
  `payoutTiers[]` both served on the tier-emitting endpoints — old builds
  render the podium; the even-split card self-disables on unequal amounts
  (verified, `race_detail_screen.dart:5820`). Historical/settled races keep
  showing the even numbers they actually paid (NULL curve).
- Pruned membership: server-derived on every surface; disappears on next poll
  / tab visit (refresh triggers: startup, resume, tab-select,
  pull-to-refresh). No client persistence to go stale. Active users on ANY
  binary version cannot be wrongly pruned by tz drift (lower-bound-only
  daily-row window, §4.2.3).
- 403 on a stale deep link / open detail screen: existing (pre-feature)
  behavior, ugly but safe; improved in the new build only.
- Kill switches: `seededInactivityPruneEnabled` OFF restores today's behavior
  exactly and immediately (all three hooks); `seededGeometricPayoutsEnabled`
  OFF stops stamping new races (already-stamped races honor their advertised
  curve — correct, not a bug).
- Prod DB safety: additive-only migration; integration tests run only
  against the local test Postgres (never prod — standing rule).

## 7. Test plan (tests FIRST, then implementation)

Backend — `test/integration/` (real HTTP + real test DB; use
`test:integration`, never bare `npm test`):
1. Seeded funded race with `payoutCurve: "GEOMETRIC"` settles geometric:
   6 walkers → tiers strictly descending, sum == stamped pool, 1st >
   even-share, last paid ≥ 1; `RaceParticipant.payoutCoins` match tiers.
2. NULL-curve funded race (user-created TOP_HALF *and* a pre-deploy-style
   seeded race) still settles EVEN — D2 + no-retroactive-change regression
   guard. A completed NULL-curve race's details keep serving even tiers.
3. Read-path parity: a live GEOMETRIC seeded race serves geometric tiers on
   **each of the three tier-emitting read paths** (`/races/:id/details`,
   `/races`, `/races/public`) — pins the implicit include of `payoutCurve`
   per endpoint (F6, corrected by G2). For `/races/featured` (and
   discovery-summary, which wraps it) and shared-preview, assert `prizePool`
   is present and coherent — they carry no tiers by design.
4. Legacy compat: response carries `payouts.first/second/third` == tiers[0..2].
5. Flag semantics: `seededGeometricPayoutsEnabled` ON → next created seeded
   race stamped GEOMETRIC; OFF → stamped NULL; flipping OFF does not alter an
   existing stamped race's tiers.
6. Tournament regression: bracket matchup race settles WINNER_TAKES_ALL,
   untouched by both flags (F7).
7. Enrollment filter: opted-in user with zero data both prior ET days is NOT
   enrolled at PENDING creation; user with steps on one of the two days IS;
   brand-new account (createdAt inside window, zero data) IS enrolled.
8. Promotion prune: zero-step ACCEPTED participant's row is deleted at
   promotion **regardless of join source** (cron-enrolled, manual
   `joinPublicRace`, toggle-enrolled — all three seeded and all three
   pruned, D3); active participant kept; user with `createdAt >=
   race.createdAt` and zero data kept (weekly signup-promise case, F4);
   `RACE_STARTED` payload's `participantUserIds` excludes the pruned user;
   pruned user's `nextBoxAtSteps` never initialized.
9. Prune idempotency: running the prune twice for the same race is a no-op
   the second time (deleteMany, F9).
10. All hooks respect the flag: `seededInactivityPruneEnabled=false` → nobody
    filtered, pruned, or swept.
11. Review-account exemption: `isReviewAccount` user with zero data survives
    all three hooks.
12. Re-join: pruned user `POST /races/:id/join` succeeds (fundedPrize → no
    buy-in), row recreated ACCEPTED.
13. Signup path untouched: `autoEnrollNewUser` enrolls a fresh account into
    ACTIVE + PENDING seeded races with both flags ON (both create sites, G4).
14. Daily-row tz guard: user whose ONLY activity is a `steps` row dated `D`
    (or `D+1`, tz-ahead) is NOT pruned (F5/G6).
15. Weekly sweep: ACTIVE weekly participant with 2-day-zero AND zero race
    steps is deleted by the sweep; participant with 2-day-zero but >0 race
    steps (early-week walker) is KEPT (D4 guard); participant holding a
    `RacePowerup`/`RaceActiveEffect` row is SKIPPED; the daily's ACTIVE race
    is never swept; `claimRun` makes the sweep once-per-ET-day (second tick
    same day = no-op).

Backend — unit (pure math, the sanctioned exception):
16. `filterInactiveUserIds` ET-window math: DST transition days (Mar/Nov),
    sample exactly at ET midnight (periodStart bucketing), daily-row-only
    activity, samples-only activity, `max()` rule, lower-bound-only row
    window, and an **evening-ET evaluation instant** (D must come from
    `getTimeZoneParts`, not the UTC date — G5).
17. `distributeGeometric` invariants at 150 slots: sum == pool, monotonic
    non-increasing, floor respected (extend existing tests only if absent —
    NEVER modify existing tests; surface any that look wrong instead).

Frontend — widget tests (pump the real screen):
18. Race detail renders the not-a-participant state on a 403 details load,
    and stops polling on a mid-session 403.
19. Payout card: unequal descending tiers on a graded preset render the
    graded summary (with the "projected" label on 1st); equal tiers still
    render the even-split card; TOP3/buy-in descending tiers do NOT trigger
    the graded card (G7); absent tiers render the podium.
    (Remember `PackageInfo.setMockInitialValues` in setUp — known hang trap.)

## 8. Acceptance criteria / definition of done

- [ ] New seeded funded challenges (flag ON) settle geometric 0.7 tiers
      summing exactly to the stamped pool; user-created funded races and ALL
      pre-existing races (in-flight + completed) unchanged, byte-for-byte.
- [ ] Projection and settlement produced by the same call with the same
      row-derived `curve` at every call site (no drift possible); all three
      tier-emitting read paths integration-pinned.
- [ ] With prune flag ON: a 2-day-zero user is skipped at enrollment, pruned
      at promotion (before the ACTIVE flip, any join source), and swept from
      the ACTIVE weekly only if they also have zero race steps and no
      powerup/effect rows; excluded from RACE_STARTED pushes; can always
      manually re-join; all silently (no notifications).
- [ ] New accounts (2-day rule + race-createdAt rule) and review accounts are
      never blocked/pruned/swept; signup auto-enroll + welcome boxes
      unaffected; the daily is never mid-race swept.
- [ ] Both flags OFF == exact current behavior (integration-proven).
- [ ] All new tests written first, failing for the right reason, then green;
      no existing test modified; `test:integration` green on local test DB.
- [ ] Frontend: 403 state, toggle copy, graded payout card (projected label;
      graded-preset gating) shipped in one build for BOTH iOS and Android
      (lockstep rule); older-backend degradation verified.
- [ ] Staging soak: one full daily cycle + one weekly-sweep firing observed
      with both flags ON before prod.

## 9. Open questions

None. All resolved in the 2026-08-05 interview (D1–D6, §1).

## 10. Revision log

- v1 (2026-08-05): Initial draft from three research passes (settlement
  zero-step handling; step-data/inactivity primitives; enrollment + frontend
  surfaces).
- Gap pass 1 (2026-08-05, independent agent, 13 findings → all folded):
  - F1/F2 (MAJOR): read-time `seedId` keying would have rewritten historical
    races' displayed tiers and flipped in-flight races mid-race → curve is now
    **stamped on the row at creation** (`payoutCurve` column + creation-time
    flag, the `fundedPrize` pattern). Added migration §4.4.
  - F3 (MAJOR): promotion prune would have deleted explicit opt-ins →
    `autoEnrolled` column proposed (later REMOVED by owner decision D3).
  - F4 (MAJOR): weekly's 7-day-early PENDING creation defeated the 2-day
    new-user exemption for signup-enrolled users → added
    `createdAt >= race.createdAt` exemption; onboarding promise now holds.
  - F5 (MAJOR): daily-row date range D-2..D-1 could wrongly prune an active
    ahead-of-ET user on an old binary → widened (final form: lower-bound-only,
    G6).
  - F6: implicit include of the curve field per read path → per-endpoint
    integration assertions (test 3).
  - F7: tournament non-reachability now cited (tournamentRounds.js:38-63,
    completeRace.js:84-141) + regression test 6.
  - F8: KNOWN_FLAGS registration requirement + 30s flag cache noted.
  - F9: per-row delete → idempotent `deleteMany` (pm2 double-promotion);
    test 9.
  - F10: prune moved BEFORE the ACTIVE flip (closes the briefly-live window).
  - F11: RACE_STARTED exclusion evidence cited (payload-driven handler).
  - F12: worked-example tail corrected (~22nd onward at floor, not ~18th).
  - F13: toggle string is one widget not two; repeating 30s error toast
    documented as the frozen-client mid-session behavior.
- Gap pass 2 (2026-08-05, second independent agent, 8 findings → all folded):
  - G1 (BLOCKER): the `autoEnrolled`-stamping `createMany` is a SHARED helper
    used by both the cron and the settings-toggle path → resolved at the time
    by threading the flag through `enroll()`; superseded by D3 (column
    removed), which dissolves the trap entirely.
  - G2 (MAJOR): "every read path serializes tiers" was false — only three
    endpoints emit payout fields; §3/§4.1/test 3 corrected.
  - G3 (MAJOR): geometric concentrates the projection→settlement field gap on
    1st place (even split masked it) → disclosed in §3 item 4, "projected"
    label in §5.3, accepted as D6.
  - G4: `autoEnrollNewUser` has two create sites (loop + over-capacity
    fallback); both named.
  - G5: daily-row query bounds pinned (ET-calendar date strings, not window
    instants; D from getTimeZoneParts) + evening-ET unit case.
  - G6: daily-row window upper bound dropped (lower-bound-only; future-dated
    rows only ever keep users).
  - G7: graded summary card gated on preset+unequal-tiers (not "descending",
    which misfires on legacy buy-in/TOP3 races); both call sites named.
  - G8: nonexistent `buildRacePrizeFields` corrected to
    `buildRaceMoneyView`/`serializePayouts`.
  - Verified-sound (no change): writer list completeness, ACCEPTED-only
    seeded participants, zero-tier unreachability + double defenses,
    prune/join concurrency, midnight/DST window math, placementRecompute
    length-invariance, tutorial fixtures unaffected, instant PG 18 default.
- v3 (2026-08-05, Phase 3 interview — all questions resolved):
  - D3: prune targets EVERY 2-day-zero ACCEPTED row regardless of join
    source → `autoEnrolled` column and its migration removed (spec is
    simpler than the gap-pass-1 design); opt-in/manual-join prunability now
    stated as accepted behavior; weekend-rester consequence accepted.
  - D4: NEW SCOPE — weekly mid-race sweep (Hook 3, §4.3): once per ET day
    via `claimRun`, zero-race-steps ghost guard (early-week walkers keep
    earned positions), powerup/effect side-effect guard, daily excluded.
    Tests 15 added; test 8 rewritten for all-join-sources pruning; former
    toggle-exemption test removed.
  - D5: silent pruning confirmed.
  - D6: projection shrink accepted with "projected" label (was Q6).
