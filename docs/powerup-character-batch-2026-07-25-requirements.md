# Powerup & Character Batch — Requirements (2026-07-25)

Seven items: Drill Sergeant sleep blocker, race-detail box helper reorder,
Pocket Watch × Ghost Pepper fix, powerup duration standardization, tournament
round minimum, character powerups (Bara herd bonus + Corgi zoomies), and a hard
powerups-disabled gate. Backend repo: `/Users/rohan/repos/stepv2-backend`.
Frontend repo: `/Users/rohan/repos/stepv2-frontend`.

STATUS: INTERVIEWED 2026-07-24 — all open questions resolved (§11); awaiting owner approval to implement.

---

## 1. Summary & user stories

1. **Drill Sergeant sleep blocker** — as a racer, I can't be dared to hit 3,000
   steps while I'm asleep with no chance to respond. Using Drill Sergeant on a
   target whose local time is in their sleep window is rejected before coins or
   the powerup are consumed.
2. **Box helper reorder** — as a racer on the race detail page, I see
   "X steps to go" ABOVE the box/item slots instead of below them.
3. **Pocket Watch × Ghost Pepper** — as a racer, using Pocket Watch while my
   Ghost Pepper is active must not silently lengthen my own burnout freeze
   (empirically proven current behavior — see §3.3).
4. **Duration standardization** — as a player, powerup durations are legible:
   windowed, upgradeable powerups run 1h base, +1h per upgrade level (1/2/3/4h).
   Deliberately-short strong powerups (Ghost Pepper 30m) and long passives
   (24h/12h shields etc.) keep their current durations.
5. **Tournament round minimum** — as a tournament creator, rounds are at least
   2 days so busy days don't decide a bracket.
6. **Character powerups** — as a Bara (capybara) player, every capybara in my
   race earns me +100 bonus steps/day (herd bonus). As a Corgi player, twice a
   day I get "Zoomies": 3x steps for 10 minutes.
7. **Powerups-disabled hard gate** — as a race creator who disabled powerups,
   NO powerup can be used or redeemed into my race — including shop powerups.

## 2. Scope / non-goals

- In scope: backend enforcement + scoring, one frontend layout swap, frontend
  surfacing of new blockers/effects, catalog copy updates.
- Non-goals: no new art; no new powerup SKUs; no change to box-drop cadence;
  no rebalancing of prices or magnitudes beyond durations listed in §5; no
  retroactive changes to running races/tournaments; no change to Ghost
  Pepper's own 30m/30m shape.

---

## 3. Item specs

### 3.1 Drill Sergeant sleep blocker (backend)

Current state: `usePowerup.js:2890-2921` creates the 2h dare effect; no
time-of-day logic exists anywhere in powerup targeting. The backend knows
`User.timezone` (`prisma/schema.prisma:95`, IANA string, sticky-written from
the `X-Timezone` header).

Rule: when the caster uses `DRILL_SERGEANT`, compute the **target's** local
wall-clock time from `targetUser.timezone`. If it falls inside the sleep
window **[22:00, 07:00)** target-local (owner-confirmed), reject
with HTTP 400:

```json
{ "error": "That rival is likely asleep — Drill Sergeant is blocked from 10PM to 7AM their time.", "code": "TARGET_ASLEEP" }
```

- Rejection happens in validation BEFORE the powerup is consumed and before
  any coin spend; the held/redeemed powerup stays usable (existing rejection
  path already refunds redeemed powerups — `refundRedeemedOnRejection`,
  `usePowerup.js:621-639`).
- Fallback when `targetUser.timezone` is null/invalid: fall back to
  `Race.timezone` (`schema.prisma:800`); if that is also null, **allow** the
  use (fail-open — owner-confirmed).
- The dare must also not *expire* into an unfair judgment: no change needed —
  the 2h window starting outside sleep hours may run into them, which is
  acceptable (the target saw the dare while awake).
- Implementation site: new validation branch in `usePowerupCore` alongside the
  existing target validations (`usePowerup.js` TARGETED_TYPES handling), using
  a pure helper `isInQuietHours(date, timeZone, startMin, endMin)` in a new
  `src/modules/powerups/constants/quietHours.js` (uses `Intl.DateTimeFormat`
  with `timeZone` — same pattern as race-tz day bucketing). The window WRAPS
  midnight (`startMin > endMin` ⇒ in-window when `min >= start || min < end`);
  the helper is unit-tested across DST boundaries.
- Mirror interaction: the check runs against the ORIGINAL target before any
  Mirror bounce; a reflected dare lands on the caster, who is by definition
  awake (they just pressed the button) — no extra check needed.
- Old clients: they receive a 400 with `error` text they already render from
  the standard error toast path — safe. No new client requirement.

### 3.2 Box helper reorder (frontend only)

`lib/screens/race_detail_screen.dart:3801-3812` renders
`_buildInventoryContent()` (slots/boxes Row, method at :4536) first, then
`_buildNextPowerupHelper()` ("You earn a powerup every N steps… X to go",
:4041-4060) below it inside `Padding(top: 10)`. Swap the order: helper text
first (with bottom padding instead of top), boxes Row second. No backend
change; no API change.

### 3.3 Pocket Watch × Ghost Pepper (backend)

Empirical probe (2026-07-24, real HTTP path,
`test/integration/pocketwatch-ghost-pepper-probe.test.js`): legacy Pocket
Watch (no `targetEffectId`) extends a live Ghost Pepper row's `expiresAt` by
the full watch duration (60m at L0), and because scoring computes the boost
window from `startsAt + metadata.boostMs` (`effectMultiplier.js:56-109`), the
entire extension lands on the **burnout freeze**: 1000 steps in boost → 3000;
1000 in the original freeze → 0; 1000 in the extension hour → 0.

Root cause: `isPocketWatchExtendable` (`usePowerup.js:222-229`) admits any
self-applied timed effect; Ghost Pepper is self-applied (`SELF_ONLY_TYPES`).

Fix (owner-approved): **legacy Pocket Watch only extends
effects whose remaining tail is favorable to the caster.** Concretely,
`isPocketWatchExtendable` additionally returns false for:
- `GHOST_PEPPER` (extension = longer burnout freeze, proven above);
- `COIN_FLIP` rows whose metadata records a LOSING flip (self ×0.5 debuff —
  same footgun family; winning flips stay extendable). Coin Flip is self-only
  (`SELF_ONLY_TYPES`, `usePowerup.js:202`) so legacy mode catches it today.
`CAMPFIRE_REST` was audited and stays extendable: its row is
freeze-then-boost, so extending `expiresAt` lengthens the BOOST — favorable.
If nothing extendable remains after the filter, the Pocket Watch use is
rejected with the existing "no self-buff" error path so the watch is not
consumed or wasted. The filter MUST be applied identically in the
VALIDATION check and the APPLICATION loop (one shared helper) — otherwise
validation could pass on a pepper-only state and application would then
extend zero effects while still consuming the watch.

- No remediation of past uses (forward-only) unless owner says otherwise.
- The probe file is promoted from "probe" to the regression test for the new
  behavior (assertions flipped to the fixed expectations, console logging
  removed).

### 3.4 Powerup duration standardization (backend)

Current ladders (`powerupUpgrades.js:28-41`) and fixed windows
(`usePowerup.js` constants) vs the new rule "1h base, +1h per level; strong
short ones stay; long passives stay":

| Powerup | Today | New | Notes |
|---|---|---|---|
| LEG_CRAMP | 2/3/4/6h | 1/2/3/4h | ladder |
| RUNNERS_HIGH | 3/4/5/7h | 1/2/3/4h | ladder |
| STEALTH_MODE | 60/75/90/120m | 1/2/3/4h | ladder (owner-approved; supersedes the 2026-07-24 nerf) |
| WRONG_TURN | 1/1.5/2/3h | 1/2/3/4h | ladder |
| DETOUR_SIGN | 3/4/5/7h | 1/2/3/4h | ladder |
| POCKET_WATCH | extends 1/1.5/2/3h | extends 1/2/3/4h | ladder (extension amount) |
| CAMPFIRE_REST | freeze 30m + boost 45/60/75/90m | **unchanged** | owner: campfire is disabled — do not touch it |
| COMPRESSION_SOCKS | 24/30/36/48h | unchanged | long passive shield (owner-confirmed) |
| RAINSTORM / SIGNAL_JAMMER / LEECH / HITCHHIKE / COIN_FLIP / RALLY_FLAG | 60m fixed | unchanged (already 1h) | non-upgradeable |
| UPRISING / QUICKSAND / DRILL_SERGEANT | 2h fixed | 1h | owner-approved; non-upgradeable, standardize to 1h base |
| GHOST_PEPPER | 30m+30m | **unchanged** | owner-named exception |
| POWER_OUTAGE | 30m | **unchanged** | owner-confirmed pepper-like exception |
| MIRROR / DECOY / UMBRELLA / PIGGY_BANK / FANNY_PACK | 24/24/12/24/24h | unchanged | passives, not "action windows" |

- Only NEW uses get new durations: durations are stamped into the effect row
  at use time, so running effects are untouched. Forward-only.
- Copy: update `powerupCopySeed.js` `upgradeTierLabels` and descriptions that
  name durations; frontend renders server copy (`getPowerupCopyCatalog`), so
  frozen clients self-update their text where server-fed, and any hardcoded
  client strings must be found and made server-fed or generic.
- Existing unit tests pin old durations (`test/utils/powerupUpgrades.test.js`
  etc.) — per house rules the implementing agent must NOT edit existing
  tests; the spec explicitly authorizes the OWNER-approved duration-table
  updates to those pinned constants as part of this feature (listed in §9,
  surfaced here for visibility).

### 3.5 Tournament round minimum 2 days (backend + frontend)

`MATCHUP_DURATIONS = [1, 2, 3]` (`src/modules/tournaments/constants/tournaments.js:12`),
validated by `validateMatchupDuration` (:74-83). Change to `[2, 3]`.

- Old-client compat: frozen clients can still send `matchupDurationDays: 1`.
  **Clamp 1 → 2 server-side** (don't reject) so old creation flows keep
  working; response echoes the clamped value and old clients render whatever
  the server returns.
- Running tournaments with 1-day rounds: untouched; rounds created after
  deploy use the clamped value (round races are created server-side in
  `tournamentRounds.js:17-99` from `tournament.matchupDurationDays`, so
  clamping at CREATE time is sufficient — also clamp defensively in
  `createRoundRaces`).
- Frontend: remove the 1-day option from the tournament create picker;
  default to 2.

### 3.6 Character powerups (backend + frontend) — THE BIG ONE

Characters today: the animal is derived from the equipped CHARACTER-slot
cosmetic — `equippedAnimal(user)` (`shopCosmetics.js:78-85`) returns the
item's `assetKey` (e.g. `"corgi_puppy"`) or `null` = default capybara. No
gameplay effect exists. Corgi is `testOnly` pending app rollout.

#### 3.6.1 Bara herd bonus (+100/day per capybara)

- Definition: for each race, a participant whose character is **capybara**
  (equipped CHARACTER slot empty ⇒ default capybara, or an explicitly
  capybara-assetKey item — owner-confirmed: the DEFAULT no-cosmetic look
  counts as capybara) earns
  `100 × (number of capybara participants in the race, including self)` bonus
  steps per race-local calendar day, **capped at 1,000/day** (at most 10
  capybaras count — owner-confirmed).
- Scoring: computed at read/settle time in `getRaceProgress` and `raceExpiry`
  as part of the existing `bonusSteps` term (formula stays
  `max(0, base − frozen + buffed − 2·reversed + event + bonus)`), NOT minted
  as rows. Days counted = race-local calendar days from the participant's
  join day through min(now, race end), same day-bucketing as
  `calculateBaseAdjusted` (race tz).
- Character membership is evaluated **live at read time** (current equips) —
  owner-approved, including the retro effect: a capybara
  joining (or a rival equipping capybara) on day 5 raises every capy's
  per-day rate for ALL elapsed days at the next read — simplest to build and
  reason about, but history visibly moves. Snapshot-at-join avoids that at
  the cost of a stored per-participant animal column.
- Join-day semantics: the participant's join day (race-local) counts as day 1
  (a full day) — matches how `calculateBaseAdjusted` treats the join day's
  steps.
- Box progress: bonus steps are IGNORED by box math (`computeBoxEffectiveSteps`
  = raw baseAdjusted only) — herd bonus must NOT advance boxes. No change
  needed, but a regression test pins it.
- Client display: bonus shows up inside existing totals; a new additive
  `characterBonus` block per participant on progress (`{ animal, bonusSteps }`)
  lets new clients render a badge; old clients ignore it.

#### 3.6.2 Corgi zoomies (3x for 10 min, twice a day)

- Two 10-minute 3x windows per user-local day (User.timezone, fallback ET),
  at deterministic pseudo-random times inside [08:00, 22:00) local, ≥2h
  apart — seeded like `chooseEventStartForEtDay`
  (`globalStepEvent.js:133-159`) but per (user, local-day).
- Applies to the corgi-equipped user's steps in **all their active
  powerups-enabled races** — friend, public, team, and tournament rounds
  alike; powerups-disabled races get neither power (owner-confirmed).
- Scoring: NEW infra. `GlobalStepEvent` is global-only and `race_active_effects`
  is powerup-instance-bound, so add table `character_effect_windows`:
  `id, userId, animal, multiplier float, startsAt, endsAt, localDayKey
  String, slot Int, notifiedAt DateTime?, createdAt` +
  `@@index([userId, startsAt, endsAt])` + `@@unique([userId, localDayKey, slot])`. A 5-min scheduler job (modeled on
  `globalStepEventScheduler.js`) materializes today's two windows for every
  user whose equipped character is corgi (idempotent per user+local-day).
  Scoring folds the window in like a self-buff: +2 added to the summed buff
  multiplier inside the window (sum rule per `buff-stacking-sum-rule`),
  honored by BOTH `getRaceProgress` and settlement (`raceExpiry`) via the
  shared `effectMultiplier.js` boundary math.
- **Cluster/idempotency (hard requirement):** crons are in-process
  `setInterval` and `JobRun.markRan` is not atomic (see the 3e6c827 outage) —
  materialization MUST be insert-first against a unique key. Table gains
  `localDayKey String` (e.g. `"2026-07-25"`, user-local) and `slot Int`
  (0 | 1) with `@@unique([userId, localDayKey, slot])`; duplicate inserts are
  swallowed. Push dedup: `notifiedAt DateTime?` on the window row, claimed
  via CAS `updateMany({ where: { id, notifiedAt: null }, data: … })`.
- Retention: a weekly cleanup deletes window rows older than 45 days (safely
  past any race settlement that could re-read them).
- Push: "ZOOMIES! 3x steps for 10 minutes — GO!" at window start (respect
  existing notification plumbing; kill-switch env `ZOOMIES_PUSH_DISABLED`).
- Switching characters mid-window: windows are materialized for the equipped
  animal at scheduling time; equip changes take effect the next scheduler
  tick/day (documented; keeps scoring stable).
- Compat: old clients see the multiplied totals only (server-computed);
  additive `zoomies` block (`{ active, endsAt }`) on progress for new
  clients. Deliberately NO next-window hint — window times stay secret until
  they start (BeReal-style surprise, matching the global event). Corgi itself is still `testOnly` until the carrying
  build ships, which gates the whole feature naturally.

#### 3.6.3 Fairness/anti-abuse shared rules

- Herd bonus and zoomies are CHARACTER powers: they bypass powerup jams
  (Signal Jammer/Power Outage) but are disabled entirely in
  powerups-disabled races (owner-confirmed).
- Both surfaces appear in the race-detail effects rail (frontend) with new
  chip copy; polarity via `lib/utils/effect_polarity.dart`.

### 3.7 Powerups-disabled hard gate (backend)

Finding: `usePowerupCore` has NO `powerupsEnabled` guard (only reference in
file is the :3129 push-alert), and `redeemPowerupToRace.js:35-102` has none
either. Shop powerups can be redeemed and "used" into a disabled race today
(effects simply never score — `getRaceProgress.js:382`).

Fix: hard-reject in BOTH entry points when `race.powerupsEnabled === false`:

```json
{ "error": "Powerups are disabled in this race.", "code": "POWERUPS_DISABLED" }
```

- `POST /races/:raceId/powerups/redeem` → 400 before any inventory decrement.
- `POST /races/:raceId/powerups/:powerupId/use` → 400 before consumption;
  redeemed-powerup refund path not reached (nothing consumed).
- Old clients already hide the powerup UI in disabled races
  (`race_detail_screen.dart:3805-3826`), so the new 400 is only reachable via
  stale UI or API misuse — safe.

---

## 4. API contract

All changes are additive or error-code-only; every list shows exact JSON.

1. `POST /races/:raceId/powerups/:powerupId/use`
   - NEW 400 `{ "error": "That rival is likely asleep — Drill Sergeant is blocked from 10PM to 7AM their time.", "code": "TARGET_ASLEEP" }` (Drill Sergeant only).
   - NEW 400 `{ "error": "Powerups are disabled in this race.", "code": "POWERUPS_DISABLED" }`.
   - Pocket Watch legacy mode no longer counts GHOST_PEPPER among
     `extendedEffects`; if it was the only extendable effect, existing
     4xx "no active buffs to extend" error is returned (exact current copy).
2. `POST /races/:raceId/powerups/redeem`
   - NEW 400 `POWERUPS_DISABLED` (same body as above).
3. `POST /tournaments` (create): `matchupDurationDays: 1` is CLAMPED to 2;
   response `tournament.matchupDurationDays: 2`. Values 2, 3 unchanged.
   No new error case (old clients keep working).
4. `GET /races/:raceId/progress` — additive per-participant fields:
   ```json
   "characterBonus": { "animal": "capybara", "perDay": 300, "bonusSteps": 900 },
   "zoomies": { "active": true, "endsAt": "2026-07-25T18:10:00.000Z" }
   ```
   Both omitted when not applicable; old clients ignore them; new clients
   default-safe when absent.
5. Powerup copy catalog (`GET` powerup copy/shop catalog): duration text and
   `upgradeTierLabels` updated server-side; shapes unchanged.
6. No changes to `/auth/me`, steps sync, or shop purchase shapes.

Backend stays compatible with older app versions: every change above is a new
optional field, a clamp, or a new 400 on paths old clients either don't hit
or already render errors for.

## 5. Data model / migrations

- NEW table `character_effect_windows` (§3.6.2). Migration is additive.
- NO column changes to existing tables. Herd bonus is computed, not stored.
- Duration changes are constants-only (`powerupUpgrades.js`, `usePowerup.js`),
  no data migration; running effects keep their stamped windows.
- Seed/copy: `powerupCopySeed.js` text updates ship with deploy (idempotent
  seed on deploy per existing flow — verify seed doesn't clobber
  owner-tuned fields per `leech-price-300-intentional` lesson: durations are
  code constants, not seed-clobberable — OK).

## 6. Frontend plan

- §3.2 reorder in `race_detail_screen.dart` (swap two children + padding).
- Tournament create picker: drop the 1-day chip, default 2 (find picker in
  tournament create screen; validate against server echo).
- Effects rail: render `characterBonus` and `zoomies` chips when present
  (absent ⇒ render nothing — default-safe).
- Drill Sergeant + disabled-race errors: server `error` text surfaces through
  the existing toast; optionally special-case `TARGET_ASLEEP` with a 😴 toast.
- Any hardcoded duration strings for powerups listed in §3.4 must be located;
  prefer server copy catalog (already the pattern).
- Character/shop screens: the capybara + corgi CHARACTER items' descriptions
  gain their power text ("Herd bonus: +100 steps/day for every capybara in
  your race", "Zoomies: 3x steps for 10 min, twice a day") — server-side
  cosmetics catalog copy, so old clients get it too.
- iOS + Android in lockstep; no new assets.

## 7. Backward-compat & rollout

- Deploy order: backend first (all changes old-client-safe per §4), then app.
- Zoomies/herd bonus are live for corgi/capybara the moment backend deploys —
  BUT corgi is `testOnly` until the carrying build rolls out, which naturally
  limits zoomies to test users. Herd bonus (capybara default) is visible to
  ALL users immediately on deploy: gate it behind env
  `CHARACTER_POWERS_ENABLED=false` at deploy; flip after the App Store build
  (which explains the bonus in UI) rolls out (~a week, phased). Same flag
  gates zoomies scheduling + scoring.
- Duration changes: env-less, effective immediately for new uses; old clients
  render server copy so text stays truthful.
- Kill switches: `CHARACTER_POWERS_ENABLED`, `ZOOMIES_PUSH_DISABLED`.

## 8. Test plan (tests FIRST, integration-first)

Backend (`test/integration/`, local test DB only):
1. Drill Sergeant: blocked at 23:00 target-local (tz-parameterized user);
   allowed at 12:00; fallback race-tz; fail-open when no tz; powerup NOT
   consumed and redeemed-copy NOT burned on rejection.
2. Pocket Watch × Ghost Pepper: promote the probe — pepper NOT extended;
   other self-buffs still extended in same call; watch rejected (and not
   consumed) when pepper is the only timed effect; targeted mode still
   rejects pepper; CAMPFIRE_REST boost still extendable.
3. Durations: for each row of §3.4's table, use at level N → effect row
   `expiresAt − startsAt` equals the new duration (loop-driven test);
   unchanged set pinned unchanged.
4. Tournament: create with 1 → persisted/echoed 2; rounds created span 2
   days; create with 2/3 unchanged; existing 1-day tournament untouched.
5. Herd bonus: 3 capys + 1 corgi race → capy participant `bonusSteps` grows
   100×3/day, corgi gets none; totals include it; box progress does NOT;
   settlement (raceExpiry) matches live progress; disabled when env flag off;
   12-capy race pins the 1,000/day cap; powerups-disabled race grants none.
6. Zoomies: scheduler materializes exactly 2 windows per corgi per local day
   (idempotent, tz-correct); steps inside window score 3x live AND at
   settlement; sum-stacking with Runner's High (2+3−1 ⇒ 4x per sum rule —
   verify against `buff-stacking-sum-rule` math); non-corgi gets none.
7. Disabled gate: redeem → 400, use → 400, inventory/coins untouched;
   enabled race unchanged.
8. Unit (fallback tier, pure math): `isInQuietHours` truth table incl.
   midnight wrap + DST transition days; zoomies window-draw determinism
   (same user+day ⇒ same windows, ≥2h apart, inside [08:00, 22:00) local).
Frontend (widget tests): reorder test (helper renders above slots Row);
effects-rail chips render from fixture progress with/without new fields;
tournament picker has no 1-day option.

## 9. Owner-authorized existing-test updates

§3.4 changes constants that existing tests pin. The implementing agents may
update ONLY duration literals in tests that assert a §3.4 "today" value —
known pinners: `test/utils/powerupUpgrades.test.js`,
`test/commands/usePowerup.upgrades.test.js`, `test/commands/stealthMode.test.js`,
and the 2026-07-24 batch tests that pin the fresh stealth 60/75/90/120 ladder
(`test/integration/feature-batch-2026-07-24-powerups.test.js`). Each literal
edit must be listed in the PR description. All other existing tests remain
untouchable per house rules.

## 10. Acceptance criteria / definition of done

- [ ] All §8 tests written first, failing for the right reason, then green.
- [ ] Backend deployed to staging + prod (flags OFF for character powers).
- [ ] Probe test promoted; no console.log left.
- [ ] `MATCHUP_DURATIONS` clamp verified with an old-client-shaped request.
- [ ] Frontend builds on iOS AND Android; layout swap visually verified.
- [ ] No existing test modified beyond §9's authorized duration literals.
- [ ] Copy catalog durations match actual constants (no stale text).

## 11. Resolved owner decisions (interview 2026-07-24)

- Q1 Drill Sergeant: 22:00–07:00 target-local, race-tz fallback, fail-open
  when no timezone is known.
- Q2 Pocket Watch × Ghost Pepper: skip the pepper (and losing Coin Flips);
  reject un-consumed when nothing favorable remains.
- Q3 Durations: STEALTH_MODE adopts 1/2/3/4h (supersedes the 2026-07-24
  nerf); UPRISING/QUICKSAND/DRILL_SERGEANT 2h → 1h; POWER_OUTAGE stays 30m;
  CAMPFIRE_REST untouched ("campfire is disabled — don't worry about it");
  long passives untouched. Nerfs ship with NO refunds, forward-only.
- Q4 Herd bonus: default (no cosmetic) counts as capybara; live equip at
  read time (retro rate shifts accepted); capped at 1,000/day (10 capys).
- Q5 Scope: character powers apply in ALL powerups-enabled races including
  team races and tournament rounds; never in powerups-disabled races.

## 12. Revision log

- Draft v1: initial spec from exploration + empirical probe.
- Gap pass 1: made the quiet-hours midnight wrap + DST testing explicit; added
  Mirror-bounce note (§3.1); widened the Pocket Watch fix to COIN_FLIP losing
  flips and recorded the CAMPFIRE_REST audit (§3.3); flagged the paid-upgrade
  duration nerfs and RH/DETOUR base nerfs for the owner (Q3); added
  cluster-safe insert-first idempotency (localDayKey/slot unique key),
  CAS push dedup, and 45-day retention to zoomies (§3.6.2); added join-day
  semantics and the live-vs-snapshot retro effect note to herd bonus
  (§3.6.1); broadened §9's authorized-test list to the 2026-07-24 batch
  stealth pinners.
- Gap pass 2: required the Pocket Watch filter to be shared between
  validation and application (§3.3); consolidated the
  `character_effect_windows` column list (localDayKey/slot/notifiedAt) into
  one authoritative definition (§3.6.2); dropped the zoomies next-window
  hint — windows stay secret until start (§3.6.2/§4); pinned the exact
  TARGET_ASLEEP error JSON in the contract (§4); added character-power copy
  to the cosmetics catalog so shop screens explain the powers (§6); added
  the quiet-hours/window-draw pure-math unit tests to the test plan (§8).
- Interview fold-in (2026-07-24): all five questions answered by owner and
  folded into §3/§8; §11 converted from open questions to resolved
  decisions; campfire row flipped to unchanged (owner: feature disabled);
  herd-bonus 1,000/day cap added with a pinning test.
