# Race timeline options — requirements

Status: **Reviewed (architect `REVISE` + game-analyst `UNSOUND`, all REQUIRED
changes folded in) — awaiting user approval before implementation.**
Owner: Rohan
Created: 2026-08-16

---

## 1. Summary & user story

**As a race creator**, I want to pick how long my race runs from a short list of
obvious options — **1 Day**, **1 Week**, **2 Weeks** — or choose **Custom** and
pick an exact **start** and **end** date/time, so a race can be made to line up
with a real-world window (a weekend, a work challenge, "Mon 8am → Fri 5pm").

Today the create screen offers `1d / 3d / 7d / 14d` chips
(`lib/screens/create_race_screen.dart:163`) and the only thing the client can
express is an integer **number of days**. The end instant is derived at start
time as `startedAt + maxDurationDays × 24h`
(`stepv2-backend/src/modules/races/commands/startRace.js:124-127`). There is no
way to say "this race ends Friday at 5pm."

This spec adds a **hard end timestamp**: the creator picks the exact end
instant, and the race ends then — not "N days after whenever it started."

## 2. Scope

**In scope**

- Create Race screen: replace the duration chips with
  `1 DAY / 1 WEEK / 2 WEEKS / CUSTOM`.
- `CUSTOM` reveals a **start** picker (date + time, or "start manually") and an
  **end** picker (date + time). The end is honored as an exact instant.
- Backend: a new optional `scheduledEndAt` on race create/edit, a new nullable
  column, and `startRace` honoring it when stamping `endsAt`.
- Edit Race screen: same four chips; a custom race shows its window and can be
  re-picked while `PENDING`.
- Share-link preview gains the race's window so a link pasted in a group chat
  can say when it starts and ends.
- Both iOS and Android (single Dart codebase; no platform-specific work).

**Non-goals**

- Changing a race's end **after it has started** (`endsAt` is stamped at start
  and stays put). Editing the window is `PENDING`-only.
- Recurring / repeating races.
- Tournaments: matchup length stays driven by the bracket picker; the duration
  card is already hidden for tournaments
  (`create_race_screen.dart:1443-1446`). Unchanged.
- Seeded races: they already create with their own explicit `endsAt`
  (`jobs/seededRaceRenewal.js:95-125`) and never go through this path.
- Quick-create sheet (`lib/widgets/quick_create_race_sheet.dart`) — its config
  is fixed and validated by `isSupportedQuickConfig`. Unchanged.
- Time-zone pickers. The window is picked in the creator's device tz and stored
  as an absolute instant (UTC), exactly like `scheduledStartAt` today.

## 3. Current behavior (cited)

| Concern | Where | Today |
|---|---|---|
| Duration chips | `lib/screens/create_race_screen.dart:163`, `lib/screens/edit_race_screen.dart:98` | `[1, 3, 7, 14]`, rendered `1d/3d/7d/14d` |
| Wire field | `lib/services/backend_api_service.dart:2222,2296` | `maxDurationDays` int only |
| Validation | `src/modules/races/services/validateRaceConfig.js:30-38` | integer, 1–30 |
| End instant | `src/modules/races/commands/startRace.js:124-127` | `startedAt + days × 24h` |
| Scheduled start | `src/modules/races/commands/createRace.js:47-61` | optional, must be **strictly future**, else 400 |
| Early manual start | `src/modules/races/commands/startRace.js:64-80` | blocked while `scheduledStartAt` is in the future |
| Auto-start | `src/modules/races/jobs/autoStartScheduledRaces.js` | 5-min cron; anchors to `scheduledStartAt` within a 5-min grace window, else to `now` (late-start backdate guard) |
| Prize pool bands | `src/shared/economy/prizePool.js:30-37`, mirrored `lib/models/race_prize_pool.dart:41-46` | `≤1 → 1, ≤3 → 2, ≤7 → 4, else 8` points |
| Settlement | `src/modules/races/jobs/raceExpiry.js:224` | settles at `race.endsAt` |
| Share link | `src/modules/races/routes.js:963-991`, `queries/getSharedRacePreview.js` | per-race token; preview returns name/status/powerups/buy-in — **no** timing fields |

## 4. UX

### 4.1 The chips

`DURATION` card becomes `TIMELINE`:

```
TIMELINE
[ 1 DAY ] [ 1 WEEK ] [ 2 WEEKS ] [ CUSTOM ]
```

- `1 DAY` → `maxDurationDays = 1`, no custom window. Identical to today's `1d`.
- `1 WEEK` → `7`. `2 WEEKS` → `14`.
- The `3d` option is **removed** from the picker. It remains a legal value
  server-side (frozen clients still send 3, and 3-day races exist in prod), so
  nothing about validation or the prize-pool bands changes.
- Widget keys stay `Key('duration-option-$days')` for 1/7/14 so existing widget
  tests keep working; the custom chip is `Key('duration-option-custom')`.

### 4.2 Custom

Selecting `CUSTOM` expands two rows **inside the same card**:

```
TIMELINE
[ 1 DAY ] [ 1 WEEK ] [ 2 WEEKS ] [ CUSTOM ]

  STARTS   [ Now (start manually)  ▸ ]      ← tap opens date+time picker
  ENDS     [ Fri, Aug 22 · 5:00 PM ▸ ]      ← tap opens date+time picker
  ── 4 days 9 hours ──
```

- **STARTS** defaults to `scheduledStartAt: null`. Tapping it opens the
  existing `_pickScheduledStart` flow (`create_race_screen.dart:447-479`) and
  sets `scheduledStartAt`.

  **Its copy is "When everyone's in", not "Now (start manually)" (architect
  R2).** A private race with no scheduled start already auto-starts the moment
  it has ≥2 accepted participants and no outstanding invites — inline on the
  accept (`privateRaceAutoStart.js:119-157`) and via the 5-minute backstop.
  That is today's behavior for every unscheduled private race, and this spec
  does **not** change it: carving a custom-window exception out of a predicate
  shared by the inline hook and the cron would be a behavior change well beyond
  this feature, and the custom end holds either way. What was wrong was only the
  label. A creator who genuinely wants to control the start picks a time.
- **ENDS** is required for Custom. Default: start + 7 days, rounded to the hour.
- Under the two rows, a live derived label shows the window length and, when
  the end is invalid, the reason (see §4.4).

### 4.3 Interaction with SCHEDULED START (the user's question)

The custom "STARTS" field **is** `scheduledStartAt` — the same value, so there
must not be two controls writing it.

- Chips `1 DAY / 1 WEEK / 2 WEEKS` → the existing `SCHEDULED START` card inside
  `CUSTOMIZE RACE` (`create_race_screen.dart:1564-1673`) renders exactly as it
  does today.
- Chip `CUSTOM` → the `SCHEDULED START` card is **hidden** (not disabled-and-
  greyed: it is redundant, not forbidden), because the STARTS row above owns
  the field. Switching from `CUSTOM` back to a preset **preserves** whatever
  `scheduledStartAt` was picked and re-reveals the card with the toggle on.
- Switching from a preset to `CUSTOM` seeds STARTS from the existing
  `scheduledStartAt` (or "Now" when it is null) and seeds ENDS from
  `start + preset days`.

There is exactly one `_scheduledStartAt` in state; only the surface that renders
it changes.

### 4.4 Client-side validation (mirrors the server)

| Rule | Message |
|---|---|
| End must be after start | `The end has to be after the start` |
| End must be in the future | `Pick an end time in the future` |
| Window ≥ 1 day | `A race has to run at least 1 day` |
| Window ≤ 30 days | `A race can run at most 30 days` |

The CREATE button is disabled (existing disabled treatment) while the window is
invalid, so the user never round-trips to a 400.

### 4.5 Prize pool preview

`_projectedPrizePool` (`create_race_screen.dart:230-240`) currently feeds
`_selectedDuration` into the mirrored band table. For Custom it must feed the
**same derived day count the server will compute** — see §5.3 — so the plaque
never disagrees with the created race. `_projectedPrizeDerivation`'s
`"N PLAYERS × 5 DAYS"` string uses the same number.

**On a not-yet-started custom race the plaque is an UPPER BOUND, not a
promise** (game-analyst R2). Because the priced duration is re-derived from the
actual elapsed window at start (§5.3a), a race that sits `PENDING` past part of
its window prices lower than the plaque showed at create time. The existing "up
to" framing already covers this honestly, but the **race detail screen must
recompute from `endsAt - startedAt` once the race is `ACTIVE`** rather than
echoing the create-time projection, or the two screens disagree.

## 5. Backend design

### 5.1 Data model

```prisma
model Race {
  // ...
  scheduledEndAt  DateTime? @map("scheduled_end_at")
}
```

Migration: **additive, nullable, no backfill.** Every existing row stays NULL
and behaves exactly as today.

**Why a new column rather than writing `endsAt` at create time.** `endsAt` on a
non-COMPLETED race is read all over as "this live race's end instant" —
`getFeaturedRaces.js:76` treats `endsAt <= now` as ended, `getNextRaceHome.js:48`
filters `endsAt > now`, `usePowerup.js:982` refuses powerups past `endsAt`,
`placementRecompute.js:194` qualifies on it. Stamping `endsAt` on a `PENDING`
race that has not started would change the meaning of that field for every one
of those readers. `scheduledEndAt` is inert until `startRace` promotes it.

### 5.2 API contract

**`POST /races`** (and the team-race path — both land in
`commands/createRace.js`) gain one optional field:

```jsonc
{
  "name": "Weekend Push",
  "maxDurationDays": 5,              // still sent; see §5.3
  "scheduledStartAt": "2026-08-18T12:00:00.000Z",  // optional, existing
  "scheduledEndAt":   "2026-08-22T21:00:00.000Z",  // NEW, optional
  // ... all existing fields unchanged
}
```

Response: the race object gains `scheduledEndAt` (ISO string or `null`) on
every read path that already returns `scheduledStartAt` — `queries/getRaces.js`,
`queries/getRaceInvitePreflight.js`, `queries/getPublicRaces.js`,
`queries/getFeaturedRaces.js`.

**`getRaceDetails.js` needs BOTH fields (architect R6).** It returns
`startedAt`/`endsAt` (`:257-258`) but has **never** returned `scheduledStartAt`.
`edit_race_screen.dart:107` initializes from the race-detail map, so without
adding `scheduledStartAt` *and* `scheduledEndAt` there, §6's "a PENDING custom
race opens with CUSTOM selected and its window shown" (test 19) is structurally
impossible. Both are additive keys; frozen clients ignore unknown keys.

**Errors** (all `400`, with a machine-readable `code`):

| Condition | `code` | Message |
|---|---|---|
| Unparseable `scheduledEndAt` | — | **ignored**, treated as absent (same forgiving rule as `validateScheduledStartAt`, `createRace.js:53-60`) |
| End ≤ effective start | `RACE_WINDOW_INVALID` | `The race has to end after it starts` |
| End ≤ now | `RACE_WINDOW_INVALID` | `The race end time must be in the future` |
| Window < `MIN_RACE_WINDOW_MS` (24h) | `RACE_WINDOW_TOO_SHORT` | `A race has to run at least 1 day` |
| Window > 30 days | `RACE_WINDOW_TOO_LONG` | `A race can run at most 30 days` |

"Effective start" = `scheduledStartAt` when set, else `now`.

**`PATCH /races/:raceId`** (`commands/editRace.js:139-144`) accepts
`scheduledEndAt` under the same validation, only while the race is `PENDING`.
`scheduledEndAt: null` clears it and the race falls back to duration-derived
end.

**The non-PENDING rejection is `400`, not `409` (architect R1).**
`editRace.js:65-70` already rejects *any* edit of a non-`PENDING` race with
`400` before a single field is inspected. Moving that guard below field parsing
to emit a `409` would change the status code frozen edit screens already get
for name/buy-in edits — a compat break for a cosmetic gain. The contract is the
existing `400`, optionally carrying an additive `code: "RACE_ALREADY_STARTED"`
(`editRace.js:24-26`).

**Both new fields are read via `hasField`/`!== undefined`, never truthiness
(architect S1).** The route destructures with `!== undefined`
(`routes.js:1961-1974`). The `null`-clears-the-field contract only works if the
two new fields follow that exact idiom — an `if (scheduledEndAt)` check makes
the clear a silent no-op that passes every happy-path test.

**Validation and re-derivation are gated on the fields actually being present
(architect R3).** Two defects this closes:

- "Effective start = now" means a manual-start custom race's window shrinks in
  real time. If revalidation ran on every PATCH, then once `scheduledEndAt` is
  under 24h away, a PATCH that only **renames** the race would return
  `400 RACE_WINDOW_TOO_SHORT`. Window validation runs **only when
  `scheduledStartAt` or `scheduledEndAt` is in `updates`**.
- `maxDurationDays` is re-derived only when the **resulting** `scheduledEndAt`
  is non-null. Moving the scheduled start of a plain 7-day preset race must not
  touch its duration.

**`scheduledStartAt` becomes editable too (Q4).** Today `PATCH /races/:raceId`
does **not** accept it — neither the route's destructure (`routes.js:1940-1958`)
nor `editRace.js` mentions it — so a race's scheduled start has always been
create-only and permanently immutable. Editing a custom window requires moving
both ends, so the PATCH surface gains `scheduledStartAt` as well:

- Accepted only while `PENDING`. On an `ACTIVE` race → `409
  RACE_ALREADY_STARTED` (a started race's start instant is history).
- Same validation as create: strictly future, else `400`.
- **`scheduledStartAt: null` is NOT accepted — un-scheduling is out of scope
  (architect R2/S7).** Clearing the schedule does not mean "revert to manual
  start": `shouldAutoStartPrivateRace`
  (`jobs/privateRaceAutoStart.js:66-105`) skips its schedule guard entirely
  when `scheduledStartAt` is null, so an un-scheduled private race with ≥2
  accepted and no outstanding invites is started by the backstop **on the next
  5-minute tick**. "Un-schedule" would therefore mean "start within 5 minutes"
  — the opposite of what the control appears to do. A creator who wants a later
  start moves the start; they never need to clear it. A `null` here is a
  `400 SCHEDULED_START_NOT_CLEARABLE`.
- The window rules (§5.2 error table) are re-validated against the **resulting**
  pair, not the submitted one: a PATCH that moves only the start must still
  leave ≥ 1 day before the stored `scheduledEndAt`, and vice versa. Validate
  after merging, never field-by-field.
- `maxDurationDays` is re-derived (§5.3) whenever either end moves.

### 5.2a The feature flag (architect R7)

`customRaceWindowEnabled` must be **declared**, not assumed:

- Add to `KNOWN_FLAGS` in `src/shared/config/appSettings.js`, default
  **false**, using the comment convention at `:47`/`:124`.
- Surface it in the `/auth/me` `featureFlags` envelope next to
  `quickCreateRaceCtaEnabled` (`src/modules/users/routes.js:245-246`), read
  client-side through `auth_service.dart:915-948` like every other flag.
- **Flip latency is not instant.** The settings read is TTL-cached in-process
  *and* the assembled `/auth/me` is a Redis surface (`cacheKeys.js:296-317`,
  `userAuthMe`). Rollout step 4 must state the resulting bound so nobody treats
  the kill switch as immediate.

**Server-side kill switch.** When `customRaceWindowEnabled` is off, a
`scheduledEndAt` on create/edit is rejected with `403 FEATURE_DISABLED` — it is
**not** silently ignored. Silently dropping it would create a race that ends at
a time the creator did not choose, which is worse than a clean error. (Same
shape as the `teamRacesEnabled` gate, `createRace.js:186-196`.)

**Old-client compat on edit — the important one.** A frozen edit screen
(`edit_race_screen.dart` in every shipped build) sends `maxDurationDays` on
save and knows nothing about `scheduledEndAt`. Rule:

> An explicit `maxDurationDays` in a PATCH that does **not** also carry
> `scheduledEndAt` **clears** `scheduledEndAt`.

The alternative — silently keeping the custom end while the old client shows
"7d" — makes the edit screen lie. Clearing is the honest, deterministic
outcome: the user on the old build changed the duration, so duration wins. This
is documented in the edit screen's copy for new clients ("changing the preset
replaces your custom window").

### 5.3 Derived `maxDurationDays` — the server is the source of truth

When `scheduledEndAt` is accepted, `createRace` **overwrites** the client's
`maxDurationDays` with:

```js
durationDaysFromWindow = clamp(Math.floor(windowMs / 86_400_000), 1, 30)
```

**`floor`, never `ceil` or `round` (game-analyst R1 — verdict was UNSOUND on the
draft's `ceil`).** The metric that governs an app-funded pool is **coins minted
per walker per elapsed day**, and `floor` is the only rounding that holds it at
today's ceiling:

| Rounding | Max mint rate | vs today |
|---|---|---|
| `ceil` (draft) | 39.97 coins/player-day @ a 24h+1min window | **2.00x** |
| `round` | 26.67 @ 1.5d | 1.33x |
| **`floor`** | **20.00 @ 1.0d** | **1.00x** |

`floor` stays monotonic non-decreasing across the whole legal range, so
`prizePool.js`'s stated invariant — a shorter competition can never pay more
than a longer one — survives intact.

The draft's rationale ("rounding up can only ever pay the field more, never
less, which is the safe direction") was exactly backwards and is struck: it is
true *per race* and false *per day*, and that reasoning is what produced the
bug. With `ceil`, "make every 1-day race a 24h+1min race instead" doubles the
pool at zero behavioral cost — and the create screen's plaque **shows the
creator the doubled number**, so it gets discovered by ordinary users within
days of the flag flipping, not by a determined attacker. 1-day races are 66% of
funded minting in prod today (34,640 of 48,600 coins over 30 days), so that one
substitution would have added ~1,150 coins/day, +15% on all coin sources.

Bands are re-expressed in hours in the docs for clarity (`≤24h → 1, ≤72h → 2,
≤168h → 4, else 8`), but note that **hourly bands fix nothing on their own** —
any upward step function evaluated just past a threshold spikes the rate. Only
lower-rounding the input does.

Why: `maxDurationDays` is what the **prize pool** reads
(`racePrizePool.js:29-31` → `prizePool.js:30-37`) and what old clients render
as the race's length. Letting the client send one number and the window imply
another is how the plaque ends up disagreeing with the payout. One formula,
computed server-side, mirrored verbatim on the client for the preview
(`lib/models/race_prize_pool.dart`), and pinned by a parity test the way the
existing band table already is.

**Where in the sequence (architect R5).** Derivation happens **after** the
quick-config check (`createRace.js:134-154`) and `validateDuration`, and
**before** `raceModel.create`. This matters because `maxDurationDays` is not
only the prize-pool input: `createRace.js:320-323` stamps
`teamPoolMultBps: resolveTeamPoolMultBps({ isTeamRace, durationDays })` — a
creation-time economy value that **settlement reads back**. If the persisted
duration and the pool multiplier are derived from different numbers, a team
custom race settles against a multiplier for a duration it never had. Test 9
asserts both come from the same derived value.

### 5.3a Re-derive the priced duration AT START (game-analyst R2)

**This is the most important rule in the spec.** Without it, `floor` at create
time does not help.

Today the invariant "priced duration == actual elapsed duration" holds *by
construction*, because `endsAt = startedAt + maxDurationDays × 24h`. A stamped
end instant silently breaks it: `maxDurationDays` is derived at **create** time
from `effectiveStart`, but branch 2 of `resolveRaceEndsAt` honors
`scheduledEndAt` against whatever `startedAt` turns out to be. Nothing
re-derives the price.

The exploit that opens (rated **critical**, 8x): create a **public** race —
public races have no auto-start (`privateRaceAutoStart.js` returns false for
`isPublic !== false`), and nothing prunes stale `PENDING` races; prod holds 26
older than two days right now — with `scheduledStartAt: null` and
`scheduledEndAt = now + 30d`. It prices at 30 days → 8 points. Sit on it. Tap
START with ~24h left. The race runs 24 hours and pays `walkers × 8 × 20`. Two
colluding accounts walking **one step each** (the funded-settlement floor is
`totalSteps > 0`) take 320 coins/day instead of 40, under
`WINNER_TAKES_ALL`. Neither amplification is bounded: `createRace.js` has no
rate limit (one prod creator made 58 races in 30 days) and steps count
independently per race, so N races can share one end instant and the same two
walkers. Ten stacked races ≈ 2x the *entire* current race-payout minting rate;
one filled public race hits the 16,000 cap in a single day. It also fires
without any manual action — the cron re-anchors `startedAt` to now past the
grace window, so a stale end that is still ≥24h out is honored against a 30-day
price.

**The fix.** In `startRace`, when `resolveRaceEndsAt` returns the custom end
(branch 2), write back into `maxDurationDays` in the **same** PENDING→ACTIVE CAS
write:

```js
pricedDurationDays = clamp(Math.floor((endsAt - startedAt) / 86_400_000), 1, 30)
```

That restores priced == elapsed by construction, which is how every race that
has ever run behaves. With R1 and R2 both in, the economy delta of this entire
feature is **zero**: a custom window can never mint faster than 20 coins per
player-day, exactly today's ceiling, and custom windows become a pure UX
feature.

Integration test: a race created with a 30-day window, started when 25 hours
remain, settles with a **1-day** pool.

### 5.4 `startRace` honors the window

`commands/startRace.js:124-127` becomes:

```js
const startedAt = startNow();
const fallbackEndsAt = new Date(startedAt.getTime() + durationDays * 86_400_000);
const endsAt = resolveRaceEndsAt({ race, startedAt, fallbackEndsAt });
```

`resolveRaceEndsAt` (new, in `src/modules/races/services/` so it is unit- and
integration-testable, and reusable by any future start path):

1. No `scheduledEndAt` → `fallbackEndsAt`. (Every existing race. Byte-for-byte
   today's behavior.)
2. `scheduledEndAt - startedAt >= MIN_RACE_WINDOW_MS` → `scheduledEndAt`.
   **This is the feature.**
3. Otherwise — the race is starting so late that less than a day of its custom
   window is left — → `fallbackEndsAt` (**Q3**). The race runs its full
   `maxDurationDays` from the actual start. `scheduledEndAt` stays on the row
   untouched as a record of intent; `endsAt` is the authority once stamped, and
   nothing reads `scheduledEndAt` after start. Log at `warn` with the race id
   and both instants so this is visible in prod rather than inferred.

Case 3 is reachable through **two** paths, both of which must be handled:

1. **Auto-start, late.** A scheduled race that never reached 2 accepted
   participants sits `PENDING` and the cron retries it every 5 minutes
   (`autoStartScheduledRaces.js`), so it can start days after its intended
   window. The late-start grace clamp (`LATE_START_GRACE_MS`) already anchors
   `startedAt` to `now` in that case, so a stale `scheduledEndAt` would
   otherwise produce a race that ends before — or seconds after — it begins.
2. **Manual start, late** *(found in Phase 2 pass 2)*. A Custom race whose
   STARTS row is "Now (start manually)" has `scheduledStartAt: null` and is
   never touched by the cron. It waits for the creator to tap START — which
   they may do after `scheduledEndAt` has passed. `resolveRaceEndsAt` covers
   this identically (it keys off `startedAt`, not off how the start was
   triggered): the race starts and runs `maxDurationDays` from now. The START
   button stays live — under Q3 a late start is a normal start — but the create
   screen's derived label and the race detail header must stop advertising the
   stale custom end once it is in the past, or the creator taps START expecting
   "ends Friday" and gets a fresh 5-day race.

DST is a free side-benefit worth stating: the preset path is `+ N × 24h`, so a
7-day race created before a DST change ends an hour "off" in local terms. A
custom end is an absolute instant the creator picked on a local clock, so it
lands where they expect regardless.

**Target/open-ended races.** Races with `endsAt === null` (legacy step-target
races — see `usePowerup.js:980`) are untouched: they never carry a
`scheduledEndAt`, and no code path here can introduce one.

### 5.5 Everything downstream is already end-instant driven

Confirmed by reading the consumers — no change needed in any of them:

- `jobs/raceExpiry.js:224` settles at `race.endsAt`; any instant works.
- `jobs/placementRecompute.js:194-200` qualifies on `endsAt != null` and only
  emits final-stretch nudges when `endsAt - startedAt > 2h` — a very short
  custom race simply gets no nudges, which is correct.
- `commands/usePowerup.js:982,1188` refuse powerups at/after `endsAt`;
  `:3639` clamps effect `expiresAt` to `endsAt`. Both correct for any window.
- `commands/expireEffects.js:150` expires effects at race end. Correct.
- `racePrizePool.js` reads `maxDurationDays`, which §5.3 keeps coherent.
- `getHomeRaceCard.js:130` computes `durationHours = maxDurationDays × 24` for
  a home-card label. For a custom race this is the rounded-up day count, i.e.
  slightly generous. **Fix**: when `endsAt` and `startedAt` are both present,
  compute `durationHours` from them; else keep the existing expression. Purely
  a label; `lib/screens/tabs/home_tab.dart:762` reads it defensively already.

### 5.5a Storage placement: Postgres only, no new cache (architect R8)

`scheduled_end_at` is **Postgres-only**. No cache surface is introduced, and no
key-version bump is needed:

- The C3 standings snapshot pins an explicit allowlist,
  `SNAPSHOT_RACE_FIELDS` (`services/raceProgressSnapshot.js:69-84`). It already
  carries `endsAt` and only ever describes `ACTIVE` races, where `endsAt` is
  stamped. **`scheduledEndAt` must NOT be added to it.**
- `editRace` already calls `invalidateRaceProgress` (`editRace.js:389`), so the
  new PATCH fields inherit the existing invalidation seam for free.
- `startRace`'s end-instant resolution reads Postgres only. Settlement and coins
  never read Redis, and this change does not make them start.

### 5.6 Why the floor is one day (Q1)

`MIN_RACE_WINDOW_MS = 24 × 60 × 60 × 1000`. Custom buys an **exact end
instant**, not a shorter race.

Every race that has ever run is ≥ 1 day, and a hard end timestamp would have
made a 3-hour race expressible for the first time. Five systems assume a race
spans at least a day, and none of them are exercised below that:

- **Day bucketing.** Scoring buckets steps by the race's canonical calendar day
  in `race.timezone` (`raceSteps.js`). A sub-day race is a single partial
  bucket — believed fine, but it has never run in prod.
- **Start-day zeroing.** The known `hasSampleData` behavior zeroes timed buffs
  and Leech for a race that starts late in the day. A 3-hour evening race is
  exactly that shape, permanently.
- **Powerup box cadence.** Boxes mint every 2,000 steps
  (`FIXED_POWERUP_STEP_INTERVAL`). In a 3-hour window most fields mint 0–1
  boxes, so a short race is effectively a powerup-free race.
- **Final-stretch nudges** require `endsAt - startedAt > 2h`
  (`placementRecompute.js:200`) — a shorter race silently gets none.
- **Settlement latency.** `raceExpiry` runs on a 5-minute cron, so a 1-hour
  race settles up to 5 minutes after its end. Proportionally noticeable.

A 24-hour floor sidesteps all five: a custom race is always at least as long as
today's shortest preset, so every one of these systems sees a duration it
already handles in prod. The floor is a single named constant
(`MIN_RACE_WINDOW_MS`) in `validateRaceConfig.js`, mirrored client-side, so
relaxing it later is a one-line change plus this section's risk list.

Consequence to accept: "Mon 9am → Mon 5pm" is **not** expressible. The
validation message says so plainly (`A race has to run at least 1 day`) rather
than silently snapping the end forward.

### 5.7 Share link (the user's second question)

The link itself already works and needs **no** change: `POST
/races/:raceId/share-link` (`routes.js:963-991`) mints a per-race token,
`GET /races/share/:token` previews it, and `joinRaceByShareToken` gates on
status/capacity — never on duration. A scheduled, not-yet-started race is
`PENDING`, which the preview explicitly treats as open
(`getSharedRacePreview.js:26`), so link-joins before the start already work.
That is the whole point of a scheduled race.

The gap worth closing in the same batch: the preview payload
(`getSharedRacePreview.js:40+`) returns name/status/powerups/buy-in and **no
timing at all**, so a link pasted in a group chat can't say when the race runs.
Add four additive fields — `scheduledStartAt`, `scheduledEndAt`, `endsAt`,
`maxDurationDays` — and render them on the landing page. Additive and
display-only; a frozen client that ignores them is unaffected. See §8 Q5.

Note for whoever writes the landing-page copy: on a `PENDING` race `endsAt` is
**null** by design (§5.1) and the end lives in `scheduledEndAt`; on an `ACTIVE`
race `endsAt` is authoritative. Render `endsAt ?? scheduledEndAt`, never
`endsAt` alone, or a shared pre-start link shows no end at all. The backend has
three public pages that duplicate one inline style — all three need the edit if
the landing page changes.

## 6. Frontend plan

Files:

- `lib/screens/create_race_screen.dart`
  - `_durationOptions` → `[1, 7, 14]` + a `_customSelected` flag and a
    `DateTime? _scheduledEndAt`.
  - New `_buildTimelineCard()` replacing the inline duration `Row`
    (`:1447-1508`), keeping `widget.tutorialDurationKey` on the same
    `KeyedSubtree` (the demo tutorial spotlights it —
    `lib/demo/demo_race_host.dart:392`).
  - `_pickCustomEnd()` mirroring `_pickScheduledStart()` (`:447-479`),
    including the `_themedPicker` builder — **required**: the onboarding/night
    theme trap means an unthemed picker renders black-on-black.
  - `SCHEDULED START` card wrapped in `if (!_customSelected)`.
  - `_create()` passes `scheduledEndAt: _customSelected ? _scheduledEndAt : null`.
  - `_projectedPrizePool` / `_projectedPrizeDerivation` use the derived day
    count (§5.3) when custom.
- `lib/screens/edit_race_screen.dart` — same `TIMELINE` card, same chips, same
  STARTS/ENDS rows (extract the card into a shared widget rather than forking it
  — the two screens' duration blocks are already near-duplicates, and a fork is
  how one of them silently drifts). Sends `scheduledStartAt` and/or
  `scheduledEndAt` in `updates` when either changes. When the user taps a
  **preset** chip on a race that had a custom window, send `scheduledEndAt: null`
  explicitly alongside `maxDurationDays` rather than relying on §5.2's implicit
  clear. Editing is offered only while the race is `PENDING`; on an `ACTIVE`
  race the card renders read-only with the stamped `endsAt`.
- `lib/services/backend_api_service.dart` — `scheduledEndAt` param on
  `createRace`, `createTeamRace`, `updateRace`; serialized
  `.toUtc().toIso8601String()` and **omitted from the body when null** (same
  shape as `scheduledStartAt`, `:2248-2250`), so a request to an older backend
  is byte-identical to today's.
- `lib/models/race_prize_pool.dart` — add `prizePoolDurationDaysForWindow(start, end)`
  mirroring §5.3, covered by the existing parity test.
- `lib/demo/demo_auth_service.dart` and `lib/demo/demo_race_api_service.dart` —
  flag override + mirrored method signatures. **See §10.1 risks 1–4: these are
  required, and two of them fail silently.**
- Any surface that renders a race's end reads `endsAt`, which is already
  correct — verified across `race_detail_screen.dart`, `races_tab.dart`,
  `active_race_card.dart`, `public_races_screen.dart`.

**Degradation when the field is missing.** `scheduledEndAt` absent/null from
any response → the screen behaves exactly as today (preset chips, duration-
derived end). No new required field is read anywhere.

**Feature gating.** The whole `CUSTOM` chip is hidden unless the remote flag
`customRaceWindowEnabled` is on (read via the existing `authService` flag
surface, defaulting **false** when the field is absent — an older backend that
doesn't know the flag must not show a control it can't honor). Kill switch:
flip the flag off; already-created custom races keep their windows.

## 7. Backward compatibility & rollout

Deploy order — **backend first, app second**, per CLAUDE.md rule #1.

0. **Run the Prisma migration before the pm2 reload** (architect S4). Prisma
   emits explicit column lists, so new code against an un-migrated DB throws;
   old code against a migrated DB is fine. The additive-nullable column makes
   this ordering safe in exactly one direction.
1. **Backend** (create/edit/start + preview fields), flag
   `customRaceWindowEnabled` **off** in prod, **on** in staging. Note the flag
   flip is **not instant** — it clears only after the in-process settings TTL
   and the `userAuthMe` Redis TTL both expire (§5.2a).
   - A frozen app never sends `scheduledEndAt`, so `startRace` takes branch 1
     of `resolveRaceEndsAt` and every existing race behaves identically.
   - A frozen app reading a race object ignores the new `scheduledEndAt` key
     (all Dart reads are keyed lookups with defaults).
2. **Verify on staging** with the manual checklist (§10).
3. **Ship the app build** (iOS ipa + Android appbundle in lockstep).
4. **After the App Store rollout completes (~1 week, phased)**, flip
   `customRaceWindowEnabled` on in prod.

**What a frozen old client does against the new backend**

| Situation | Behavior |
|---|---|
| Views a custom race pre-start | Shows `maxDurationDays` (ceil'd days). Slightly generous label, no crash. |
| Views a custom race after start | Shows the exact `endsAt`. **Correct** — the countdown is already end-instant driven. |
| Edits a custom race's duration | Clears the custom window (§5.2). Deterministic and honest. |
| Joins via share link | Unchanged. |
| Creates a race | Sends no `scheduledEndAt`; identical to today. |

**What a new client does against an old backend** (possible during the deploy
window, and for anyone on a stale staging build): the flag is absent → defaults
false → the `CUSTOM` chip is hidden → the client is behaviorally identical to
today.

## 8. Decisions (Phase 3 — closed 2026-08-16)

| # | Question | **Decision** |
|---|---|---|
| Q1 | Minimum custom window | **1 day (24h).** No sub-day races. Every system stays in territory it already runs in — §5.6 becomes a "why the floor is a day" note rather than a risk list. |
| Q2 | Maximum custom window | **30 days**, unchanged — same bound `validateDuration` already enforces. |
| Q3 | Start after the custom end has passed | **Fall back to duration.** `endsAt = startedAt + maxDurationDays × 24h` and the race runs normally. No new dead-race state, nothing silently never-runs. |
| Q4 | Editing the window | **Editable while `PENDING`.** `PATCH /races/:raceId` gains **both** `scheduledStartAt` (new to the API entirely) and `scheduledEndAt`. |
| Q5 | Share-link preview timing | **Yes, this batch.** Additive fields + landing-page render. |
| Q6 | Card header copy | **`TIMELINE`.** |

**Zero open questions remain.**

## 9. Test plan (tests written FIRST, per CLAUDE.md)

**Backend — `test/integration/` (real HTTP, real DB, real handler chain)**

1. `POST /races` with `scheduledStartAt` + `scheduledEndAt` → 201; the response
   carries both; `maxDurationDays` is the server-derived `ceil` value, not the
   client's.
2. Auto-start cron starts that race on time → `endsAt === scheduledEndAt`
   exactly (to the millisecond).
3. `POST /races` with **no** `scheduledEndAt` → `endsAt === startedAt + days`
   (regression lock on the legacy path).
4. End ≤ start → 400 `RACE_WINDOW_INVALID`; end in the past → 400; window under
   the minimum → 400 `RACE_WINDOW_TOO_SHORT`; over 30 days → 400
   `RACE_WINDOW_TOO_LONG`.
5. Unparseable `scheduledEndAt` (`"soon"`) → 201, field ignored, legacy end.
6. `PATCH` with `maxDurationDays` only, on a race that had a custom window →
   window cleared, end back to duration-derived (the frozen-old-edit-screen
   case).
7. `PATCH` with `scheduledEndAt` on an `ACTIVE` race → **400** (the existing
   non-PENDING guard, architect R1), optionally with
   `code: "RACE_ALREADY_STARTED"`; same for `scheduledStartAt`.
7a. `PATCH` with `scheduledStartAt: null` → `400
   SCHEDULED_START_NOT_CLEARABLE`, and the race is **still scheduled**
   afterwards (regression lock on the R2 auto-start trap: assert the backstop
   does not start it on the next tick).
7b. `PATCH` moving **only** `scheduledStartAt` forward, so the stored end is now
   under a day away → 400 `RACE_WINDOW_TOO_SHORT` (validation runs on the merged
   pair, not the submitted field).
7c. ~~`scheduledStartAt: null` un-schedules the race.~~ **STRUCK.** Left over
   from the pre-architect draft and directly contradicted by §5.2/R2 and test
   7a, which reject the clear. Test 7a is the correct one.
7d. `PATCH` moving either end re-derives `maxDurationDays`, and the race's
   projected prize pool moves with it.
8. Settlement: a custom race is settled by `raceExpiry` at its custom end, with
   steps bucketed to the custom window.
9. Prize pool: a 25-hour custom race prices at the **1-day** band (`floor`,
   §5.3) on **both** the projection and settlement paths. For a **team** custom
   race, assert `teamPoolMultBps` was stamped from the same derived day count
   as the persisted `maxDurationDays` (architect R5).
9b. **The anti-exploit lock (game-analyst R2).** A race created with a 30-day
   window, started when 25 hours remain, settles with a **1-day** pool — not a
   30-day one. Assert on the settled coin ledger, not just on
   `maxDurationDays`.
10. `GET /races/share/:token` on a `PENDING` custom race returns
    `scheduledStartAt` + `scheduledEndAt` with `endsAt: null`; on the same race
    after start, `endsAt` is the custom instant. Joining by that token still
    works in both states.
10b. A late auto-start (custom end already past) settles on the fallback
    duration and logs the warn line — asserted on the DB row, not the log.

**Backend — unit (only where an integration test structurally can't express it)**

11. `resolveRaceEndsAt` truth table — all three branches, including the
    late-start case, with injected clocks.
12. `durationDaysFromWindow` boundaries under `floor`: `24h-1s → 1`,
    `24h → 1`, `48h-1s → 1`, `48h → 2`, `30d → 30`, `30d+1s → clamped 30`.
    Explicitly assert `24h+1min → 1` (the band-boundary exploit the `ceil`
    draft would have shipped).
12b. Client/server parity: `lib/models/race_prize_pool.dart`'s mirror of
    `durationDaysFromWindow` is pinned by the same parity test that already
    pins the band table (`:41-46`), over the boundary set in test 12.

**Frontend — widget tests (pump the real screen, assert what renders)**

13. Chips render `1 DAY / 1 WEEK / 2 WEEKS / CUSTOM`; `duration-option-3` is
    gone; `duration-option-1/7/14` still resolve (existing tests keep passing).
14. Tapping `CUSTOM` reveals STARTS + ENDS and **hides** the `SCHEDULED START`
    card; tapping a preset restores it with the previously-picked start intact.
15. Picking a window updates the prize-pool plaque to the derived day band.
16. Invalid window (end before start / end in past / too short) disables CREATE
    and shows the right message.
17. `createRace` is called with `scheduledEndAt` for custom and **without the
    key at all** for presets.
18. Flag off → no `CUSTOM` chip anywhere; flag absent → treated as off.
19. Edit screen: a `PENDING` custom race opens with `CUSTOM` selected and its
    window shown; tapping `1 WEEK` sends `scheduledEndAt: null`; moving STARTS
    sends `scheduledStartAt`; an `ACTIVE` race renders the card read-only.
20. `PackageInfo.setMockInitialValues` in `setUp` for any new widget test file
    (known hang otherwise).
21. Flag OFF → `403 FEATURE_DISABLED` on both create and PATCH; `/auth/me`
    carries `customRaceWindowEnabled`; the suite passes with `REDIS_URL` unset
    (it will — this feature touches no cache).
22. Extract the timeline card into `lib/widgets/` and give **it** a widget test,
    rather than testing the same card twice through both screens (architect S3).

**Not weakened.** No existing assertion is changed except mechanically: the
`duration-option-3` references in `test/create_race_screen_prize_pool_test.dart`
and `test/edit_race_screen_buyin_edit_test.dart` move to a still-offered value.
The "5 is not an option" assertions stay as-is.

## 10. Manual UI-placement test plan

Prereq: staging build with `customRaceWindowEnabled` ON. Run 1–9 on staging;
run 10 on a build with the flag OFF (or a prod-pointed build).

**A. Create Race — real screen**

1. **Surface:** Create Race (individual). **Get there:** Races tab → create-race
   FAB (`lib/screens/tabs/races_tab.dart:367`).
   **Verify:** card header reads `TIMELINE` (not `DURATION`), in the same
   position — directly under RACE NAME, above the prize-pool plaque. Four chips
   in order `1 DAY / 1 WEEK / 2 WEEKS / CUSTOM`, all on one row, none clipped.
   **No `3d` chip anywhere on the screen.**
2. **Surface:** Create Race, CUSTOM expansion. **Get there:** same screen → tap
   CUSTOM.
   **Verify:** STARTS and ENDS rows appear **inside the TIMELINE card** (inside
   its border, not as a new card below it), STARTS above ENDS, derived-length
   label beneath both. Prize plaque stays directly under the card and has not
   jumped above it or been pushed off by the expansion. Tap a preset chip again
   → both rows collapse, card returns to its original height, no leftover blank
   gap.
3. **Surface:** Create Race, SCHEDULED START interaction. **Get there:** expand
   `CUSTOMIZE RACE` (toggle at `create_race_screen.dart:1521`), turn SCHEDULED
   START on and pick a time → then tap CUSTOM.
   **Verify:** the `SCHEDULED START` card is **gone** from CUSTOMIZE RACE
   (negative check: it is not merely greyed, and the powerups card below it has
   moved up with no double gap where it was). The STARTS row shows the time you
   already picked — not "Now". Tap `1 WEEK` → SCHEDULED START card reappears in
   its original slot with the toggle still on and the same time. Only one
   control showing a start time at any moment.
4. **Surface:** Create Race, date/time pickers. **Get there:** CUSTOM → tap
   STARTS, then tap ENDS. Run this **at night / dark mode forced in settings**
   (known theme-pin trap).
   **Verify:** both pickers open themed and legible (no black-on-black fields),
   and on dismiss the value lands in the row that opened it — STARTS never
   writes the ENDS row and vice versa.
5. **Surface:** Create Race, prize plaque. **Get there:** CUSTOM with a
   ~25-hour window, then a ~5-day window.
   **Verify:** the plaque's derivation line under the coin figure updates in
   place (`N PLAYERS × N DAYS`) and shows the ceil'd day count; changing runner
   cap still moves it. Plaque position unchanged.
6. **Surface:** Create Race — tournament and team modes. **Get there:**
   CUSTOMIZE RACE → format card → TOURNAMENT; then → TEAM.
   **Verify:** tournament hides the whole TIMELINE card (as DURATION was
   hidden, `create_race_screen.dart:1443-1446`) — and the CUSTOM chip/STARTS/
   ENDS rows do not leak in. Team race shows the TIMELINE card in the same slot
   with the plaque below it.

**B. Edit Race — real screen**

7. **Surface:** Edit Race, PENDING race. **Get there:** open a race you created
   that hasn't started → manage → EDIT (`race_detail_screen.dart:1877`).
   **Verify:** `TIMELINE` card sits where the old `DURATION` card was (under
   RACE NAME / team card), same four chips, no `3d`. On a race created with a
   custom window, CUSTOM is pre-selected and the STARTS/ENDS rows show that
   window. Tapping `1 WEEK` collapses the rows (negative check: the custom
   window is no longer displayed anywhere on the screen).
8. **Surface:** Edit Race, ACTIVE race. **Get there:** open an already-started
   race you own → EDIT.
   **Verify:** the TIMELINE card renders read-only (no tappable chips, no
   pickers open on tap) and shows the stamped end. No CUSTOM chip offering an
   edit that will 409.

**C. Demo race tutorial (real CreateRaceScreen, `demoMode: true`)**

9. **Surface:** Demo race prologue, create beat
   (`lib/demo/demo_race_host.dart:386-395`). **Get there:** fresh account →
   onboarding → demo race (or Profile → admin → re-run onboarding demo).
   **Verify:** (a) the card reads `TIMELINE` with the new chips; (b) the coach's
   spotlight cut-out still rings **both** the TIMELINE card and the CREATE
   button (union rect, `demo_race_host.dart:240-252`) — the card must not sit
   half under the scrim; (c) whether the `CUSTOM` chip appears at all — see Risk
   1: it should be **absent** in the demo. If it IS present, tap it: the
   spotlight hole must re-expand to cover the taller card, CREATE must still be
   reachable/inside the hole, and the date picker must not escape the demo (no
   real network call, no crash); (d) picking `1 WEEK` then CREATE advances the
   beat as before; (e) the demo race detail screen that follows shows a
   duration/prize scorecard consistent with the chip you picked.

**D. Flag-off build**

10. **Surface:** Create Race + Edit Race with `customRaceWindowEnabled` off (and
    against an older backend that doesn't send the flag). **Get there:**
    prod-pointed build, Races tab → create FAB.
    **Verify:** three chips `1 DAY / 1 WEEK / 2 WEEKS`, **no CUSTOM chip**, no
    STARTS/ENDS rows, and the `SCHEDULED START` card is present and unhidden
    inside CUSTOMIZE RACE exactly as today. Same on Edit Race.

**E. Other entry points into the same screen (30-second sweep)**

11. **Surface:** Create Race reached from the other three routes. **Get there:**
    Home next-race CTA → quick-create sheet → `CUSTOMIZE…`
    (`main_shell.dart:372`); Home friend card → "challenge back"
    (`main_shell.dart:3414`); Public races empty state → "Create a Race"
    (`public_races_screen.dart:173`).
    **Verify:** TIMELINE card present and identical in all three. In the
    quick-create sheet itself, the `2 DAY / 7 DAY` preset buttons are
    **unchanged** (separate widget,
    `lib/widgets/quick_create_race_sheet.dart:85`) — negative check that the
    relabel did not leak into the sheet.

**Surfaces confirmed unaffected** (checked, no action): tab tutorial previews
(`lib/tutorial/tutorial_real_screens.dart` never constructs `CreateRaceScreen`
or `EditRaceScreen`); tutorial spotlight ids in `tutorial_screen.dart`; the
hand-forked `WoodenTabBar`; races-tab effect plates and inventory row; demo
coach chrome (`_CoachRing`, `_WinCard`, `coach_tip.dart`,
`spotlight_overlay.dart`); case-opening screens; the race invite screen; and the
duration labels on race detail / races tab / public races / home card, which
read `maxDurationDays`/`endsAt` and have nothing added or moved.

### 10.1 Risks found while planning → implementation steps

These are **required steps**, not observations:

1. **`DemoAuthService` inherits the real flag.**
   `lib/demo/demo_auth_service.dart:23` extends `AuthService` and overrides
   flags one-by-one. A new `customRaceWindowEnabled` with no override inherits
   the real value, so the CUSTOM chip appears inside the demo prologue the
   moment the flag flips on in prod — with a date picker, a growing card, and a
   scripted spotlight never designed for it. **Add
   `@override bool get customRaceWindowEnabled => false;`** with the same
   rationale comment as `onboardingV2Enabled`.
2. **`DemoRaceApiService` signature drift = a real network call.**
   `lib/demo/demo_race_api_service.dart:240,264` override
   `createRace`/`createTeamRace`. Adding `scheduledEndAt` to the
   `BackendApiService` methods without mirroring it in these overrides breaks
   the override contract that `test/demo_race_network_guard_test.dart` protects.
   **Mirror every new param in both demo overrides** (and in `updateRace` if
   the demo overrides it).
3. **`tutorialDurationKey` must stay on the outermost node.**
   `create_race_screen.dart:1448` wraps the whole card. §6 extracts the card
   into a shared widget — if the key lands inside the extracted widget or only
   around the chip `Row`, the demo spotlight silently mis-aims with **no compile
   error and no test failure**. The shared widget takes an optional key param
   applied at its outermost node; the create screen passes
   `widget.tutorialDurationKey` there.
4. **The demo prize-pool fixture forks the band table.**
   `lib/demo/demo_race_engine.dart:507` computes
   `'durationPoints': _durationDays <= 1 ? 1 : 2` — not the real
   `≤1→1, ≤3→2, ≤7→4, else 8` — and its default `_durationDays = 3` (`:131`) is
   a value the picker no longer offers. With `3d` gone, demo users pick 7 or 14,
   where the fork disagrees hardest, and the create plaque and the demo race's
   scorecard show **different pools in the same tutorial**. Point the demo
   engine at the mirrored `computePrizePool` and change its default to 7.
5. **Extract, don't copy.** `create_race_screen.dart:1463-1507` and
   `edit_race_screen.dart:871-915` are already near-identical duplicates — which
   is precisely why both need editing today. A third copy guarantees the next
   chip change misses one.
6. **No prize plaque on Edit Race.** `_buildPrizePoolPreview` exists only on
   create, so re-picking a window while `PENDING` shows no updated pool until
   the user backs out to race detail's payout scorecard. **Decision:** bring the
   plaque along to the edit screen — a control that changes the pool without
   showing the pool is the same class of lie as the stale-duration case in §5.2.
7. **Themed picker for `_pickCustomEnd`.** Reuse `_themedPicker` from
   `_pickScheduledStart` (`create_race_screen.dart:447-479`); an unthemed picker
   renders black-on-black under the onboarding pinned-light theme and at night.
8. **Spacing artifact around the hidden card.**
   `create_race_screen.dart:1688` emits a `SizedBox(height: 12)` keyed only on
   `_customizeExpanded`, independent of the SCHEDULED START card it follows.
   Hiding the card without also gating that spacer leaves a stray gap inside
   CUSTOMIZE RACE.
9. **Stale tutorial fixtures (cosmetic, no action).**
   `lib/tutorial/tutorial_preview_data.dart:633,652` seed races with
   `maxDurationDays: 3` and `5`, rendering "3d race"/"5d race" labels the create
   screen can no longer produce. Still legal server-side. Flagged so it isn't
   mistaken for a bug during a checkpoint sweep.

## 11. Acceptance criteria

- [ ] Create screen shows `1 DAY / 1 WEEK / 2 WEEKS / CUSTOM`.
- [ ] `CUSTOM` lets the creator pick an exact start **and** end date/time.
- [ ] A custom race ends at the picked instant — verified against `endsAt` in
      the DB and the settled result, not just the UI countdown.
- [ ] Only one control writes `scheduledStartAt`; no state can be reached where
      the STARTS row and the SCHEDULED START card disagree.
- [ ] The prize-pool plaque shown at create equals the pool the created race
      reports (as an upper bound — §4.5).
- [ ] **Economy invariant holds: no custom window can mint faster than 20 coins
      per walker per elapsed day**, which is today's ceiling. Verified by the
      §9 tests 9b and 12, not by inspection.
- [ ] A share link on a custom, scheduled, `PENDING` race opens and joins.
- [ ] A frozen 2.3.7 client, pointed at the new backend, creates, views, joins,
      and settles races with no behavior change.
- [ ] iOS ipa and Android appbundle both built and verified.
- [ ] `code-reviewer` run on the combined diff.

## 12. Revision log

- **Draft** — initial spec from Phase 1 exploration.
- **Phase 2, pass 1** — found: (a) `PATCH /races/:raceId` has never accepted
  `scheduledStartAt`, so an editable custom window is a strictly larger API
  change than assumed (callout in §5.2, folded into Q4); (b) no server-side
  behavior was specified for the kill switch — added an explicit
  `403 FEATURE_DISABLED` rather than silently dropping the field, since a
  silently-dropped end time creates a race the user didn't ask for; (c) confirmed
  team races and individual races share one `POST /races` route and one
  `createRace` command, so the new field covers both by construction.
- **Phase 2, pass 2** — found: (a) `resolveRaceEndsAt`'s late-start case is
  reachable through **manual** start too, not just the cron, and the START
  button/endpoint needs the same handling (§5.4); (b) sub-day races are entirely
  unexercised in prod and touch five separate systems — added §5.6 and made Q1
  a real decision rather than a detail; (c) `endsAt` is null on a `PENDING`
  race, so the share landing page must render `endsAt ?? scheduledEndAt` or a
  pre-start link shows no end (§5.7); (d) noted the DST benefit of an absolute
  end instant over `+ N × 24h`; (e) noted that open-ended `endsAt === null`
  target races are structurally untouched.
- **Phase 3 (2026-08-16)** — six open questions answered by the user and folded
  in (§8). Material effects: the minimum window is **1 day**, which retires the
  entire sub-day risk surface (§5.6 rewritten from a risk list to a rationale);
  a late start **falls back to the duration** rather than refusing or cancelling
  (§5.4 branch 3, plus the manual-start note); the window is **editable while
  PENDING**, which pulls `scheduledStartAt` into `PATCH /races/:raceId` for the
  first time and adds merged-pair revalidation, un-scheduling, and four new
  integration tests; the share preview gains timing fields in this batch.
- **Phase 4, ui-test-planner** — checklist added as §10. Nine planning risks
  promoted to required implementation steps (§10.1). The two that would have
  shipped as bugs: `DemoAuthService` inherits unoverridden flags, so the CUSTOM
  chip would have appeared inside the onboarding demo the moment the prod flag
  flipped; and `demo_race_engine.dart:507` forks the prize-pool band table with
  a default duration of 3 — a value this change removes from the picker —
  making the tutorial show two different pools for the same race. Also added:
  the prize plaque now comes along to the edit screen (§10.1 risk 6), and the
  shared-widget extraction must carry `tutorialDurationKey` on its outermost
  node or the demo spotlight mis-aims silently.
- **Phase 4, architect — verdict `REVISE`.** Nine REQUIRED changes folded in.
  The two that would have shipped as defects: (R2) `scheduledStartAt: null`
  does **not** mean "manual start" — `shouldAutoStartPrivateRace` skips its
  schedule guard when the field is null, so "un-schedule" actually means "start
  within 5 minutes"; the capability is dropped from the PATCH surface and the
  STARTS row's copy is corrected to "When everyone's in", which is what
  unscheduled private races have always done. (R3) merged-pair revalidation as
  drafted would have made a PATCH that only **renames** a race fail with
  `RACE_WINDOW_TOO_SHORT` once its end came within 24h. Also: the non-PENDING
  edit rejection is the existing `400`, not a new `409` (R1); `getRaceDetails`
  has never returned `scheduledStartAt`, so the edit screen literally could not
  have rendered the window (R6); the derived duration must be stamped before
  `teamPoolMultBps` reads it (R5); the flag needs declaring in `KNOWN_FLAGS` +
  `/auth/me` and its flip is TTL-bound, not instant (R7); storage is
  Postgres-only and must **not** join `SNAPSHOT_RACE_FIELDS` (R8).
- **Phase 4, game-analyst — verdict `UNSOUND`.** Two REQUIRED numeric changes,
  and it found a larger hole than the one it was asked about.
  (R1) The draft's `ceil` was exploitable at every band boundary, worst at
  **24h+1min → 2.00x** mint rate — sitting directly on top of the most-used
  duration in prod (107 of 287 races). Changed to `floor`, the only rounding
  that holds the ceiling at today's 20 coins/player-day. The draft's stated
  rationale was inverted and is struck.
  (R2, critical) A stamped end instant breaks the invariant "priced duration ==
  elapsed duration", which today holds by construction. A public race priced at
  30 days and started with 24h left pays a 30-day pool for a 1-day race — **8x**,
  unbounded by any rate limit, needing one step per colluder. Fixed by
  re-deriving `maxDurationDays` from the actual window in `startRace`'s CAS
  write (§5.3a). With both fixes the feature's economy delta is **zero**.
  Its non-required R3 (raise funded-settlement eligibility from `totalSteps > 0`
  to 2,000 for all funded races) is **out of scope here** — it is a pre-existing
  economy hole this feature makes more valuable, and it deserves its own
  decision rather than riding along in a UI batch.
