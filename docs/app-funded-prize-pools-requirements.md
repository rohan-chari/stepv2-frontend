# App-Funded Prize Pools (buy-ins removed) — Requirements

Status: **SPEC COMPLETE — zero open questions. Awaiting owner approval to spawn
the two build agents (CLAUDE.md Phase 5).**
Author: PM/BA pass, 2026-07-24. Owner decisions folded in (§12).

---

## 1. Summary & user story

Today a race's prize pool is **funded by the players**: each joiner's coins are
debited and held (`RaceParticipant.buyInAmount` / `buyInStatus`), committed into
`Race.potCoins` at start, and paid back out by finishing place at settlement
(`src/modules/races/commands/startRace.js:104-140`,
`src/modules/races/commands/completeRace.js:246-285`). Tournaments work the same
way with `Tournament.potCoins`.

**Buy-ins are removed everywhere.** Every race and every tournament is **funded
by the app** — coins are minted at settlement, the same mechanism as today's
seeded finish reward (`src/modules/races/constants/raceFinishReward.js`).
Entering costs nothing, ever.

```
prizePool = playerCount × durationPoints(days) × 20
```

Duration points double per band: **1 day = 1, 3 days = 2, 7 days = 4,
14 days = 8**.

Owner-supplied fixtures (these are acceptance tests, not examples):

| Players | Duration | Points | Pool |
|---|---|---|---|
| 4 | 3 days | 2 | **160** |
| 20 | 14 days | 8 | **3,200** |
| 2 | 1 day | 1 | 40 |
| 10 | 7 days | 4 | 800 |

The pool splits by the race's existing `payoutPreset` (winner takes all / top 3 /
top half / everyone but last).

> **User story:** *As a player I want to join any race for free and still race for
> real coins, with a prize pool that visibly grows as more friends join and the
> longer the race runs.*

Why: buy-ins gate participation (you need coins to play, and "your gold is held
until the race starts" is the most confusing step in joining), and they make
races zero-sum — nobody is rewarded for showing up. App funding makes entry
frictionless and every race net-positive.

---

## 2. Scope

**In scope**
- Individual races, team races, seeded daily/weekly races, **and tournaments**.
- Removing the buy-in charge/hold/refund from every entry path, and the buy-in
  configuration UI from create/edit (races and brackets).
- The funded-pool computation, its live projection, and its settlement mint.
- **Retiring `raceFinishReward`** as the seeded daily/weekly pool source (§4.3).
- Backward compatibility for frozen builds that still send `buyInAmount`, and for
  **in-flight races/tournaments holding real coins** at deploy time.

**Non-goals**
- Dropping the `RaceBuyInStatus` enum or the `buy_in_*` columns. They stay: they
  settle in-flight legacy competitions, and removing fields breaks frozen clients'
  reads. Dead-column cleanup is a later migration.
- Changing **featured/seeded tournament** prizes. Those already mint
  `seed.championPrizeCoins` (`advanceTournament.js:105-110`) — they are already
  app-funded and ≤ 1,000, so there is nothing to remove; they keep their
  configured amount (§4.4).
- Powerup pricing, store economy, daily rewards, box drops.
- Placement/tiebreak/forfeit logic (`raceExpiry`, `resolveMatchupWinner`).

---

## 3. Current-state map (what the change touches)

**Races — money in**
- `createRace.js:205-266` — validate buy-in, `ensureUserCanAfford`, creator
  participant `HELD`, `reserveRaceBuyIn`.
- `joinRaceCore.js:249-289` — affordability + hold on public/share-link join,
  with a compensating refund if participant create throws.
- `respondToRaceInvite.js:162-180` — same on invite accept.
- `editRace.js:187-336` — buy-in edit + hold reconciliation (`buyInEditEnabled`
  flag, versioned refIds `raceId:userId:vN`).
- `startRace.js:104-140` — `HELD → COMMITTED`, `potCoins += heldPot`.

**Races — money out**
- `completeRace.js:152-211` (team tie refunds / team pot split), `:246-285`
  (individual pot payout by place), `:297-338` (the existing **minted** seeded
  finish reward — the pattern this feature generalizes).
- `cancelRace.js:58-76`, `leaveRace.js:77`, `kickRaceParticipant.js:63` — refunds.
- `deleteUserAccount.js:81,125` — a deleted user's buy-in is forfeited **into**
  `potCoins`.
- `services/raceBuyIns.js` — ledger reason/refId wrappers.
- `racePayoutPresets.js` — `computeRacePayouts` (percentage presets +
  `distributeGeometric` for the graded ones), `computeGradedPayouts` (linear split
  used by the minted seeded reward), `MIN_MULTI_PAYOUT_PARTICIPANTS = 4`.

**Races — read paths that surface money**
- `getRaceDetails.js:36-94`, `getRaces.js:213-307`, `getPublicRaces.js:53-95`,
  `getSharedRacePreview.js` — each computes `heldPotCoins`, `projectedPotCoins`,
  legacy `payouts{first,second,third}`, `payoutTiers[]`, `finishReward`.
- `models/race.js:410-425` — the placement-push select (reads `payoutPreset`,
  `potCoins`).

**Tournaments**
- `constants/tournaments.js` — `TOURNAMENT_BUYIN_MAX {4:100,8:100,16:62}`,
  `MIN_BUY_IN`, `MATCHUP_DURATIONS [2,3]`, `MAX_CHAMPION_PRIZE = 1000`,
  `totalRoundsFor`.
- `createTournament.js:101-191`, `joinTournamentCore.js:183`,
  `inviteToTournament.js:92`, `services/tournamentStart.js:37-50`,
  `cancelTournament.js`, `advanceTournament.js:96-125` (**"exactly one prize
  path: pot (paid) OR minted (seeded)"**), `services/tournamentBuyIns.js`,
  `queries/serializeTournament.js:18`, `jobs/tournamentSeedRenewal.js`.

**Seeded races**
- `jobs/seededRaceRenewal.js:54-96` — creates races ACTIVE straight from the seed
  (never through `startRace`, so the 4-runner preset gate never applies), sets no
  `payoutPreset` → DB default `WINNER_TAKES_ALL`.
- `constants/raceFinishReward.js` — the per-seed minted pools being retired
  (`seed-daily-10k`: 15/head, 100–1,500, top 50 % capped 15 places, 10-coin tail
  floor; `seed-weekly-50k`: 40/head, 500–5,000, top 20 % capped 20).

**Frontend**
- `create_race_screen.dart:36-43,320-341,358-418,853-856,1206` — buy-in toggle /
  field / affordability guard, tournament buy-in clamp, payout preset,
  `_durationOptions = [3,5,7,14]`.
- `edit_race_screen.dart:37-148,447-573,881-1109` — buy-in card.
- `race_detail_screen.dart:811-837` (join confirm), `2788-2890` (pot + breakdown),
  `2947-2987` (BUY-IN / POT stats), `3061,3548-3564` (prize chip gated on
  `buyInAmount > 0`).
- `public_races_screen.dart:147-153,218-240` (race buy-in confirm),
  `375-445` (tournament buy-in confirm), `1036,1125-1127` (BUY-IN stat).
- `tournament_detail_screen.dart`, `lib/utils/tournament.dart:134-138,307,538`
  (`buyInAmount`, `potCoins`), `isValidTournamentBuyIn` / `clampTournamentBuyIn`.
- `lib/models/race_payouts.dart` — preset options, help copy, `parsePayoutTiers`.
- Note: `finishReward` is **not read anywhere in `lib/`** (verified by grep), so
  retiring it is invisible to every client, old and new.

---

## 4. The pool formula (normative)

### 4.1 Core

```js
// src/shared/economy/prizePool.js  (new — shared by races and tournaments)
const PRIZE_COIN_UNIT      = Number(process.env.PRIZE_COIN_UNIT ?? 20);
const PRIZE_POOL_MAX       = Number(process.env.PRIZE_POOL_MAX_COINS ?? 3200);
// Tournaments keep their own, tighter ceiling (constants/tournaments.js).
const TOURNAMENT_POOL_MAX  = MAX_CHAMPION_PRIZE; // 1000

// Duration bands. Monotonic non-decreasing over the whole legal 1..30 range
// (validateDuration allows 30; frozen clients still send 5), so a shorter race
// can never pay more than a longer one.
function durationPoints(days) {
  const d = Math.floor(days || 0);
  if (d <= 1) return 1;
  if (d <= 3) return 2;
  if (d <= 7) return 4;
  return 8;               // 8..30 days
}

function computePrizePool({ playerCount, durationDays, max = PRIZE_POOL_MAX }) {
  const players = Math.max(0, Math.floor(playerCount || 0));
  if (players < 2) return 0;               // a solo field mints nothing
  return Math.min(players * durationPoints(durationDays) * PRIZE_COIN_UNIT, max);
}
```

Both knobs are **env vars** so the economy can be retuned on the droplet without
an App Store release (the `AD_COIN_REWARD_AMOUNT` lesson).

**`playerCount` is deliberately different for projection vs settlement:**

| Context | Count used | Why |
|---|---|---|
| Projected (create preview, race list, race detail, share preview) | `ACCEPTED` participants | It is what the player can see, and it makes the pool visibly grow on each join. |
| Settled (`completeRace`) | `ACCEPTED` **and** `placement != null` **and** `totalSteps > 0` | No-shows and alt accounts must not mint coins. Exactly the `eligible` filter already at `completeRace.js:300-307`. |

Consequence the copy must respect: **the settled pool can be lower than the
projected one.** Every pre-settlement figure is labelled `PROJECTED` / "up to",
never "you will win".

**The cap saturates on purpose.** `PRIZE_POOL_MAX = 3200` is hit by any ≥20-player
14-day race and by every large public/seeded race (a 300-player Daily computes
6,000 → clamps to 3,200). UI therefore never promises growth past the cap: once
`coins === PRIZE_POOL_MAX` the create preview shows `PRIZE POOL — 3,200 🪙 (max)`
and stops incrementing.

### 4.2 Splitting the pool — owner decisions D1/D2

Distribution reuses the existing `payoutPreset` machinery, so old clients'
`payouts{first,second,third}` and new clients' `payoutTiers[]` keep working:

| Preset | Split | Paid places |
|---|---|---|
| `WINNER_TAKES_ALL` | `[pool]` | 1 |
| `TOP3_70_20_10` (and legacy `TOP3_80_15_5`) | percentage, unchanged | 3 |
| `TOP_HALF` | **even** | `ceil(field / 2)` |
| `ALL_BUT_LAST` | **even** | `field - 1` |

- **D1: even, not geometric.** `distributeGeometric` is replaced by an even split
  for the two graded presets. `GRADED_PAYOUT_RATIO` / `GRADED_MIN_PAYOUT` become
  dead and are deleted **only if nothing else references them** (grep first).
- **D2: pay the exact pool.** `share = floor(pool / slots)`, remainder to 1st, so
  the payouts always sum to the advertised pool. Shares are therefore not always
  round numbers (160 across 3 places → 54/53/53) — that is accepted.
- `field <= 1` still yields 0 paid places (`gradedSlotCount`), which is consistent:
  `playerCount < 2` already yields a 0 pool.
- `MIN_MULTI_PAYOUT_PARTICIPANTS = 4` (the "needs 4 accepted runners to start"
  gate in `startRace.js:86-96`) is **retained unchanged**.

### 4.3 Seeded daily/weekly races — owner decisions D5/D8

- Seeded races become funded (`fundedPrize = true`) and use the formula.
- `seededRaceRenewal.js` now creates them with **`payoutPreset: "TOP_HALF"`**
  (D8) so a big field spreads: a 300-player Daily pays 150 people ~21 coins each
  from the capped 3,200. Winner-takes-all on a 300-person field was rejected.
- `raceFinishReward` is **retired as a pool source**: `computeFinishRewardPool` /
  `computeFinishRewardPlaces` are no longer called from `completeRace` or the
  three read queries, and `finishReward` serializes as `null`. The module and its
  config stay in the tree (one deploy from being re-enabled) but are unreferenced.
  Safe because no client reads `finishReward`.
- Net effect on the Weekly: today up to 5,000 across ≤20 concentrated places;
  after, 3,200 across the top half. Deliberate, owner-approved.
- Seeded races never pass through `startRace`, so the 4-runner preset gate does
  not block a thin Daily; a 2-player Daily pays 1 place.

### 4.4 Tournaments — owner decisions D6/D9

- Entry is free. `Tournament.buyInAmount` is coerced to 0; `potCoins` is no
  longer funded by joiners.
- **Duration band = total bracket length**: `totalRoundsFor(bracketSize) ×
  matchupDurationDays` (D9).
- **Pool = `playerCount × durationPoints(totalDays) × 20`, clamped to
  `MAX_CHAMPION_PRIZE = 1000`** — tournaments keep their tighter, existing ceiling
  rather than the 3,200 race cap.
- `playerCount` = `ACCEPTED` tournament participants at start (a bracket only
  starts full, so this equals `bracketSize` in practice; using the accepted count
  is the defensive form).
- Champion takes the whole pool (bracket money has always been winner-takes-all).
- Worked fixtures (acceptance tests):

  | Bracket | Round length | Total | Points | Pool |
  |---|---|---|---|---|
  | 4 | 2 d | 4 d | 4 | **320** |
  | 8 | 2 d | 6 d | 4 | **640** |
  | 16 | 3 d | 12 d | 8 | 2,560 → **1,000** (capped) |

- `advanceTournament.js`'s "exactly one prize path" invariant is **preserved and
  extended to three mutually exclusive branches**, in this order:
  1. `potCoins > 0 && buyInAmount > 0` → legacy pot payout (in-flight brackets),
  2. `seedId` → existing `mintChampionPrize(seed.championPrizeCoins)`
     (featured brackets, unchanged — already app-funded),
  3. `fundedPrize` → mint the computed pool to the champion.
- `TOURNAMENT_BUYIN_MAX` / `isValidTournamentBuyIn` / `clampTournamentBuyIn`
  become unreachable for new brackets; kept for legacy validation only.

---

## 5. API contract (pinned — the interface between the two build agents)

### 5.1 Race payloads — one additive object

`GET /races`, `GET /races/:id`, `GET /races/public`, `GET /races/shared/:token`:

```json
{
  "prizePool": {
    "coins": 160,
    "projected": true,
    "atMax": false,
    "playerCount": 4,
    "durationDays": 3,
    "durationPoints": 2,
    "coinUnit": 20,
    "maxCoins": 3200,
    "funded": true
  }
}
```

- `projected: true` while `PENDING`/`ACTIVE`; `false` once `COMPLETED` (the
  stamped, settled pool).
- `atMax: true` when the raw formula exceeded `maxCoins` (drives the "(max)" UI).
- `prizePool` is **`null`** for a legacy buy-in race (`fundedPrize = false`); the
  client then renders today's buy-in/pot UI.

**Existing fields, and what a funded race puts in them:**

| Field | Funded value | Rationale |
|---|---|---|
| `buyInAmount` | `0` | Frozen clients gate their charge + confirm sheets on this. |
| `potCoins` | `0` while pending/active; **settled pool** once completed | Keeps "pot" honest — nothing is held. |
| `heldPotCoins` | `0` | Nothing is held. |
| `projectedPotCoins` | **the projected pool** | Deliberate re-use: frozen builds render this as `POT` and therefore show the correct prize (§7). |
| `payouts{first,second,third}` | split of the projected/settled pool | Shape unchanged. |
| `payoutTiers[]` | split of the projected/settled pool | Shape unchanged. |
| `finishReward` | `null` always (§4.3) | No client reads it. |
| `myBuyInStatus` | `"NONE"` | |
| `myPayoutCoins` | unchanged (incremented at settlement) | |

### 5.2 Tournament payloads

`serializeTournament` gains the same `prizePool` object (with `maxCoins: 1000`,
`durationDays` = total bracket length), and for funded brackets returns
`buyInAmount: 0` and `potCoins` = projected pool pre-completion / settled pool
after, so `lib/utils/tournament.dart:307,538` keeps rendering a correct figure on
frozen builds.

### 5.3 Writes

- `POST /races`, `PATCH /races/:id`, `POST /tournaments`: `buyInAmount` and
  `buyInEnabled` are **accepted and ignored** (coerced to 0) while
  `fundedPrizePoolsEnabled` is true. **Never a 400** — a frozen client that sends
  `buyInAmount: 100` must still be able to create. Nothing is charged; the
  response echoes `buyInAmount: 0`.
- `payoutPreset` is honored exactly as today.
- New rows get `fundedPrize = true`.
- Join/accept paths (`POST /races/:id/join`, share-link join, invite accept,
  tournament join/accept) never touch coins for funded competitions.

### 5.4 Errors that can no longer occur (codes retained for legacy rows)

`INSUFFICIENT_COINS` (create/join/accept), `BUYIN_UNAFFORDABLE`,
`IMMUTABLE_FIELD` (buy-in edit).

### 5.5 Ledger

```
races:        reason "race_prize_pool_payout"        refId "<raceId>:<placement>"
tournaments:  reason "tournament_prize_pool_payout"  refId "<tournamentId>:champion"
```

Distinct from every existing reason, so retries and legacy rows can never
collide. `awardCoins` dedups on `(userId, reason, refId)`; `completeRace` only
proceeds when it wins the `updateIfActive` flip, and `advanceTournament` runs
inside its transaction — so each mint is exactly-once.

---

## 6. Data model / migrations

```sql
-- prisma/migrations/<ts>_add_funded_prize_pools/migration.sql
ALTER TABLE "races"       ADD COLUMN "funded_prize"     BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "races"       ADD COLUMN "prize_pool_coins" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "tournaments" ADD COLUMN "funded_prize"     BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "tournaments" ADD COLUMN "prize_pool_coins" INTEGER NOT NULL DEFAULT 0;
```

- `fundedPrize` is the **discriminator** that keeps the two money models from
  ever overlapping: set `true` at create while the flag is on; every existing row
  stays `false`. This is what guarantees an in-flight buy-in race settles under
  the old rules and a new race under the new ones, and that **no competition can
  pay both** (§8).
- `prizePoolCoins` stamps the settled pool so results screens and history are
  frozen forever (the accepted count keeps drifting; a recomputation must never
  change a finished race's numbers).
- **No backfill** — the defaults are the safe legacy values.
- Every read treats missing/false `fundedPrize` as "legacy buy-in competition".

---

## 7. Frontend plan (iOS + Android, same Dart)

Load `mobile-design` (and `frontend-design` for new surfaces) before any UI work.
Every widget parses defensively: **the backend may be older than the build**, in
which case `prizePool` is absent and today's buy-in/pot UI must render exactly as
it does now.

**Removed**
- `create_race_screen.dart`: buy-in toggle, amount field, coin-affordability
  guard, and the tournament buy-in clamp (`_clampTournamentBuyIn` path).
- `edit_race_screen.dart`: the buy-in card (`:881-1109`) and its request diff.
- `race_detail_screen.dart:811-837`, `public_races_screen.dart:218-240` and
  `:420-445`: the "N GOLD BUY-IN" confirm sheets — joining is now one tap.
- `public_races_screen.dart:1125-1127`: the `BUY-IN` stat.

**Added / changed**
1. **Create screen — live pool preview** under the duration + max-players
   controls: `PRIZE POOL — up to 160 🪙` with the derivation (`4 players ×
   3 days`), `(max)` when clamped. Computed **client-side** from a mirrored table
   in `lib/models/race_prize_pool.dart` (the race doesn't exist yet), with a
   structural test asserting the Dart table reproduces the backend fixtures.
   Uses `maxParticipants` for the "up to" figure.
2. **Race detail prize card / chip** (`:2788-2890,3061,3548-3564`): gate on
   `prizePool != null || buyInAmount > 0`; label `POT` → `PRIZE POOL`, with a
   `PROJECTED` tag while `prizePool.projected`; existing per-place breakdown
   beneath. Copy: *"Funded by Bara — free to enter."*
3. **Races list + public races**: `BUY-IN` stat → `PRIZE 160 🪙` from
   `prizePool.coins`, falling back to `projectedPotCoins`.
4. **Duration picker `[3,5,7,14]` → `[1,3,7,14]`** (D3) so every option lands on
   a band boundary. Off-band durations from frozen clients (5 days) fall to the
   lower band (4 points) — monotonic, never a downgrade.
5. **Tournament surfaces**: `tournament_detail_screen` + the public-races
   bracket card show `PRIZE POOL` from the new object (fallback `potCoins`), and
   the bracket create flow loses its buy-in row.
6. **Copy pass** in `race_payouts.dart:26-43`: "pot" → "prize pool";
   `TOP_HALF` / `ALL_BUT_LAST` state an **even** split.
7. **States**: loading → existing skeletons; `prizePool == null` → legacy UI;
   `coins == 0` (single accepted player) → hide the card rather than show `0`;
   error → unchanged.

**Frozen old build, no update:** `buyInAmount: 0` makes it skip every confirm
sheet, charge nothing, and hide its buy-in stat; `projectedPotCoins` carries the
pool, so it still shows the right `POT` number and payout breakdown. One cosmetic
wart: an old *create* screen still offers a buy-in toggle the server ignores — the
created race returns `buyInAmount: 0`, so the UI self-corrects on re-read.

---

## 8. Backward compatibility & rollout

**Deploy order: backend first, then app.**

**Kill switch:** `appSettings` flag `fundedPrizePoolsEnabled`, `KNOWN_FLAGS`
default **false**, admin-toggleable. While false the backend behaves exactly as
today. Flipping it on affects **new competitions only** (it decides `fundedPrize`
at create).

| Population | Behavior after backend deploy, flag ON |
|---|---|
| Frozen old app creates a race/bracket | Buy-in ignored → free funded competition; its own UI shows a buy-in it never charged, self-corrects on re-read. |
| Frozen old app joins a funded race | `buyInAmount: 0` → no confirm sheet, no charge; sees the pool via `projectedPotCoins`. |
| New app | Full prize-pool UI. |

**In-flight legacy money (the safety requirement).** At flip time there are
`PENDING`/`ACTIVE` races and tournaments holding real `HELD`/`COMMITTED` coins.
Those rows have `fundedPrize = false`, therefore:
- `completeRace` keeps its `potCoins > 0` branch **verbatim** for them, and the
  funded mint runs **only** when `fundedPrize === true`. Mutually exclusive.
- `advanceTournament` keeps the three-branch order in §4.4.
- `cancelRace`, `leaveRace`, `kickRaceParticipant`, the team-tie refund,
  `cancelTournament`, and `deleteUserAccount`'s forfeit-into-pot stay intact.
  **Phase 1 deletes no refund path.**
- `editRace`'s buy-in reconcile stays reachable for `fundedPrize = false` races
  only (an old client editing an old race); for funded races the branch no-ops.

**Settlement must never read the feature flag.** A mid-race flip must not strand
a promised prize; `fundedPrize` on the row is the only authority.

**Rollback:** flip the flag off. New competitions revert to the buy-in model
(new builds no longer offer a buy-in, so they'd create free races with no pool —
acceptable for a rollback window). Already-funded rows keep paying correctly.

**Economy exposure (be explicit).** This mints where the old model recycled.
Per-race ceiling 3,200; per-bracket 1,000. Worst realistic daily volume should be
sanity-checked against current coin sinks before the flag flip, and
`PRIZE_COIN_UNIT` / `PRIZE_POOL_MAX_COINS` must be present in the droplet `.env`
**before** flipping so they can be dialled down in minutes.

---

## 9. Test plan (tests FIRST, before any business logic)

Never point integration tests at the prod DB. Backend uses `test:unit` /
`test:integration`, never bare `npm test`.

**Backend — `test/integration/` (the primary proof)**
1. `POST /races` with `buyInAmount: 100` from a user with 0 coins → **201**,
   response `buyInAmount: 0`, `fundedPrize` true, balance unchanged.
2. `POST /races/:id/join` (public) with 0 coins → 200, no coin movement, no
   `INSUFFICIENT_COINS`.
3. Owner fixtures end-to-end through real settlement: 4 players/3 days → **160**
   distributed; 20 players/14 days → **3,200**; 2 players/1 day → 40;
   10 players/7 days → 800.
4. All four presets over the API's `payoutTiers` at fields of 4 and 20 — locks
   D1 (even) and D2 (exact pool, remainder to 1st) as executable spec.
5. Projected vs settled: 6 accepted, 2 with zero steps → projected reflects 6,
   `prizePoolCoins` reflects 4; a completed race's numbers never move on re-read.
6. **No double pay:** a `fundedPrize = false` race with a real pot settles via the
   pot branch only; a funded race mints only the pool; `finishReward` is `null`
   and no `race_finish_reward` row is written for a seeded funded race.
7. Idempotency: replay the settlement path → coins minted once
   (`race_prize_pool_payout` dedup).
8. Legacy drain: an ACTIVE pre-flip race with `COMMITTED` buy-ins is cancelled →
   everyone refunded exactly as today.
9. Kill switch OFF → `POST /races` still charges the buy-in (unchanged path).
10. Team race: the winning team's non-forfeited members split the funded pool
    evenly; a tie mints nothing and refunds nothing.
11. `PATCH /races/:id` with `buyInAmount: 50` on a funded race → 200, no coin
    movement, `buyInAmount` stays 0.
12. Cap: a 100-player 14-day race clamps to 3,200 with `atMax: true`.
13. Seeded Daily created by `seededRaceRenewal` → `payoutPreset: "TOP_HALF"`,
    `fundedPrize: true`; a 10-player Daily settles 5 even shares.
14. Tournament fixtures: 4-bracket/2 d → **320**; 8-bracket/2 d → **640**;
    16-bracket/3 d → clamped **1,000**; champion receives it, nobody was charged.
15. Featured/seeded tournament still mints `seed.championPrizeCoins` (branch 2),
    not a funded pool.
16. In-flight paid bracket created pre-flip still pays its pot to the champion.

**Backend — unit (only where integration structurally can't reach)**
- `durationPoints` over every value 1..30: monotonic non-decreasing, band
  boundaries, the four owner fixtures, `players < 2 → 0`, both caps.

**Frontend — widget tests pumping the real screens**
- `create_race_screen`: no buy-in toggle; pool preview tracks duration +
  max-players changes and matches the fixtures; `(max)` at the cap;
  duration options are `[1,3,7,14]`.
- `race_detail_screen`: funded payload → `PRIZE POOL` + `PROJECTED` + breakdown;
  **legacy payload (no `prizePool`, `buyInAmount: 100`) still renders today's
  buy-in/POT UI**; join tap shows **no** buy-in confirm.
- `public_races_screen`: `PRIZE` stat from `prizePool`, fallback
  `projectedPotCoins`; single-tap join for races and brackets.
- `edit_race_screen`: buy-in card absent; save sends no buy-in fields.
- `tournament_detail_screen`: prize pool renders from the new object, falls back
  to `potCoins`.
- Structural: the Dart duration table equals the backend fixtures.

**Existing tests — D7: rewrite, don't delete.** These assert removed buy-in UI
and the agents are **explicitly authorized to edit these files only**, converting
each buy-in assertion into its prize-pool equivalent (same screen, same coverage):
`test/create_race_screen_buyin_input_test.dart`,
`test/create_race_screen_buyin_minimum_test.dart`,
`test/create_race_screen_buyin_maximum_test.dart`,
`test/edit_race_screen_buyin_edit_test.dart`, plus the buy-in assertions inside
`test/public_races_screen_test.dart` and `test/race_detail_screen_test.dart`.
**No other existing test may be modified or deleted** — surface anything else to
the owner. (Pre-existing failures noted in memory — ~35 stale-copy tests, 13
fanny-pack backend integration tests, 2 stale mock unit tests — remain out of
scope.)

---

## 10. Acceptance criteria / definition of done

- [ ] No code path debits coins for entering a race or a bracket (create, public
      join, share-link join, invite accept, edit, bracket join/accept).
- [ ] A funded pool equals `players × durationPoints × 20`, clamped (3,200 races /
      1,000 brackets), and matches every fixture in §1 and §4.4 end-to-end.
- [ ] Payouts split by preset — even for `TOP_HALF`/`ALL_BUT_LAST` — and sum
      exactly to the pool.
- [ ] `prizePool` present and correct on all four race endpoints and on
      tournaments; every legacy field carries the §5.1/§5.2 values.
- [ ] `prizePoolCoins` stamped at settlement, immutable thereafter.
- [ ] Seeded Dailies/Weeklies are funded, use `TOP_HALF`, and no longer mint a
      `race_finish_reward`.
- [ ] A pre-flip buy-in race/bracket still pays or refunds exactly as before and
      never receives a funded mint.
- [ ] Settlement paths never read `fundedPrizePoolsEnabled`.
- [ ] Frozen 1.7.x builds: no charge, no buy-in confirm sheet, correct pool shown.
- [ ] New prize copy shipped on **iOS and Android**, built and verified in
      lockstep with matching `--dart-define`s and version/build numbers.
- [ ] Every §9 test written before its implementation and green.
- [ ] `PRIZE_COIN_UNIT` / `PRIZE_POOL_MAX_COINS` documented in the backend env
      example and set on the droplet **before** the flag flip.

---

## 11. Implementation order (two Opus 4.8 agents, medium effort)

**Contract first, then parallel** (CLAUDE.md Phase 5). Both agents: tests first,
never touch an existing test outside the D7 list, never point tests at prod DB.

Backend agent (owns §5 + §6 — the contract):
1. Migration + `prisma generate` (`fundedPrize`, `prizePoolCoins` × 2 tables).
2. `src/shared/economy/prizePool.js` + unit table tests.
3. Serializers: `prizePool` object + the §5.1/§5.2 field values on all four race
   reads and `serializeTournament` — **this locks the contract; the frontend
   agent starts here.**
4. Coerce buy-ins to 0 behind the flag: race create/join/accept/edit, tournament
   create/join/accept.
5. `completeRace`: funded mint branch, mutually exclusive with the pot branch;
   stamp `prizePoolCoins`; drop the `raceFinishReward` calls.
6. `advanceTournament`: three-branch prize order; `tournamentStart` no longer
   commits a pot.
7. Even split for the graded presets; `seededRaceRenewal` sets `TOP_HALF`;
   `KNOWN_FLAGS` entry.

Frontend agent (consumes the contract verbatim; never invents fields):
1. `lib/models/race_prize_pool.dart` + parsing/structural tests.
2. Create screen: remove buy-in, add preview, `[1,3,7,14]`.
3. Race detail prize card + chip.
4. Races list, public races, edit-screen removal.
5. Tournament surfaces.
6. Copy pass in `race_payouts.dart`; D7 test rewrites.
7. iOS + Android builds in lockstep.

---

## 12. Owner decisions (interview closed — no open questions)

| # | Decision |
|---|---|
| D1 | `TOP_HALF` / `ALL_BUT_LAST` split **evenly** (replaces geometric decay). |
| D2 | Pay the **exact pool**: `floor(pool/slots)`, remainder to 1st; uneven tail accepted. |
| D3 | Duration picker → **`[1,3,7,14]`** (drops 5-day, adds 1-day). |
| D4 | `PRIZE_POOL_MAX` = **3,200** coins per race. |
| D5 | Seeded Daily/Weekly **move onto the formula**; `raceFinishReward` retired. |
| D6 | Tournaments are **in scope now** — free entry, funded bracket pool. |
| D7 | The ~6 buy-in UI tests are **rewritten** as prize-pool tests by the agents. |
| D8 | Seeded races use **`TOP_HALF`** (even) so a 300-player Daily pays 150 people. |
| D9 | Tournament band = **total bracket length**; cap stays **`MAX_CHAMPION_PRIZE` 1,000**. |

---

## 13. Revision log

**Gap pass 1** (re-read cold, hunting rule violations):
- Added the `fundedPrize` discriminator column. Draft 1 decided new-vs-legacy by
  `buyInAmount === 0`, which would have made every existing **free** race (the
  majority) start minting a pool mid-flight, and made "no double pay" depend on a
  coincidence.
- Added the in-flight-money matrix (§8) and the rule that Phase 1 deletes no
  refund path — draft 1's "remove buy-in code" would have stranded
  `HELD`/`COMMITTED` coins on races live at deploy.
- Made buy-in fields on write **ignored, not rejected**. A 400 would break race
  creation for every frozen 1.7.x binary — a direct hit on CLAUDE.md's #1 rule.
- Pinned that settlement must never read the feature flag, so a mid-race flip
  can't strand a promised prize.

**Gap pass 2** (second independent pass):
- Split `playerCount` into projection vs settlement definitions and required
  "projected/up to" copy; draft 1's single "number of players" would have let
  no-shows and alt accounts mint coins.
- Extended `durationPoints` across the full legal 1..30 range and proved
  monotonicity (the owner's table covers only 1/3/7/14, frozen clients send 5,
  the API accepts 30).
- Added `PRIZE_POOL_MAX` + env tunability after computing the 100-player worst
  case (16,000 coins/race).
- Corrected the "everything is a multiple of 20, so every payout is round" claim
  — true for winner-takes-all and dividing even splits, false for
  `ALL_BUT_LAST` of 4 — and raised it rather than silently deciding.
- Added the `prizePoolCoins` stamp (a completed race's prize must not drift) and
  the retry/idempotency test.
- Surfaced the existing-test conflict instead of letting build agents "fix" tests.
- Chose to re-use `projectedPotCoins` for the pool so frozen builds show a
  correct number instead of nothing.

**Gap pass 3** (after folding the nine owner decisions — new surface, new risks):
- Discovered that D5 + `WINNER_TAKES_ALL` (the seeded default, since
  `seededRaceRenewal.js` sets no preset) would have made a 300-player Daily pay
  one winner and 299 nothing, replacing today's 15-place spread. Raised it; D8
  resolved it to `TOP_HALF`, and the renewal job now sets the preset explicitly.
- Verified `finishReward` is read **nowhere** in `lib/`, which is what makes
  retiring `raceFinishReward` a zero-risk client change; recorded the grep.
- Verified seeded races never pass through `startRace`, so
  `MIN_MULTI_PAYOUT_PARTICIPANTS = 4` cannot block a thin Daily on `TOP_HALF`.
- For D6, found `advanceTournament.js:96-110`'s "exactly one prize path"
  invariant and preserved it as an explicitly ordered three-branch rule, so a
  featured bracket can't take both `seed.championPrizeCoins` and a funded pool.
- Kept tournaments on `MAX_CHAMPION_PRIZE = 1000` (D9) rather than the race cap,
  and noted `TOURNAMENT_BUYIN_MAX` / `isValidTournamentBuyIn` become legacy-only.
- Added `atMax` to the contract after D4: at 3,200 the pool saturates for every
  large public/seeded race, so the UI must stop implying growth.
- Recorded D7 as a **scoped, named-files-only** authorization so the agents don't
  read it as blanket permission to edit tests.
