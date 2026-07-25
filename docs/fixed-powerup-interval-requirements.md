# Fixed 2,000-step powerup interval — requirements

Status: **APPROVED 2026-07-24 — in implementation**
Owner: Rohan · Drafted 2026-07-24

Post-approval addendum (owner, 2026-07-24): the create/edit screens must carry a
short, themed **blurb next to the powerups enable/disable toggle** telling the
player it's 2,000 steps to each powerup. Folded into §7.1 / §7.2 and test 10.

---

## 1. Summary & user story

Today, whoever creates a race picks how many steps it takes to earn a powerup
box: the create screen offers 2k / 3k / 4k / 5k / 10k / 25k
(`lib/screens/create_race_screen.dart:138`). The edit screen offers the same
list again (`lib/screens/edit_race_screen.dart:84`), so the gap can be re-tuned
after the fact.

> As a player, I want every powerup-enabled race to run the same way, so I
> always know a box is 2,000 steps away and I never have to reason about a
> creator's setting.

The knob goes away. Any race with powerups enabled uses **2,000 steps per
powerup, always** — chosen by the app, enforced by the backend, and applied
uniformly to user races, team races, tournaments, and the seeded daily/weekly
challenges.

The interesting part is not the constant; it is that **frozen app binaries keep
sending their own value forever** (App Store rollout is phased over ~a week, and
some users never update). This spec's core requirement is that those clients
keep working *and* get the new rules.

---

## 2. Scope / non-goals

### In scope
1. Create-race screen: interval picker removed; always sends 2,000.
2. Edit-race screen: interval picker removed; the field is no longer sent.
3. Tournaments: created from the same screen (`create_race_screen.dart:498`),
   so they inherit 2,000; the backend pins it too.
4. Seeded daily/weekly challenges: `seededRaceRenewal` mints races at 2,000
   regardless of the `RaceSeed.powerupStepInterval` column (prod currently
   holds **2500** for both `DAILY_10K` and `WEEKLY_50K`).
5. Backend coercion so old binaries land on 2,000 too.

### Non-goals
- **Existing races are not touched.** A race already running at 5,000 finishes
  at 5,000. See §4.3 for why retro-fitting is actively dangerous.
- No admin/balance-config knob for the interval. The value is a code constant.
  ("No need to customize it anymore" — owner, 2026-07-24.)
- No change to drop odds, rarity pools, or box contents. Only the *spacing*.
- No migration of the `powerup_step_interval` columns. They stay in the schema
  (old clients read them; existing rows keep their historical values).
- The `RaceSeed.powerupStepInterval` column is not dropped; it is simply no
  longer read (a prod `UPDATE` to 2000 is optional tidiness, §5.4).

---

## 3. Decisions taken (owner, 2026-07-24)

| # | Question | Decision |
|---|---|---|
| D1 | What does the backend do with an old client's `powerupStepInterval`? | **Accept and ignore it — coerce to 2,000.** Never a 400. |
| D2 | How far does "2k always" reach? | Create **and** edit **and** tournaments **and** seeded races. |
| D3 | Do in-flight races get re-pointed to 2,000? | **No** (see §4.3 — mid-race change back-mints boxes). |

---

## 4. Design

### 4.1 One constant, one normalizer

Add `src/modules/races/constants/powerupInterval.js`:

```js
// Every powerup-enabled competition earns a box every 2,000 steps. Formerly a
// per-race creator choice (2k–25k); fixed by owner decision 2026-07-24 so the
// rules are identical in every race. Deliberately a CODE constant, not balance
// config — it must not be admin-editable.
const FIXED_POWERUP_STEP_INTERVAL = 2000;
```

`validatePowerupConfig` in `src/modules/races/services/validateRaceConfig.js:38`
changes from a throw-only validator to a **normalizer that returns the value to
store**:

```js
// Returns the interval to persist. The caller's powerupStepInterval is read
// ONLY by old clients that still send one, and is deliberately discarded.
function normalizePowerupConfig({ powerupsEnabled }) {
  return powerupsEnabled ? FIXED_POWERUP_STEP_INTERVAL : null;
}
```

Returning the value (rather than validating in place) is what makes this
enforceable: a call site that forgets to use the return value stores `undefined`
and fails loudly in tests, instead of silently persisting the client's number.

This mirrors the pattern already used one field over for app-funded prize pools
(`createRace.js:206`): *"A frozen client's `buyInAmount` is accepted and IGNORED
(coerced to 0) — never a 400, or every un-updated binary loses the ability to
create a race."* Same reasoning, same shape.

### 4.2 The three call sites

| File | Line (today) | Change |
|---|---|---|
| `races/commands/createRace.js` | 192, 236 | Use the normalizer's return for `powerupStepInterval` |
| `races/commands/editRace.js` | 143–161 | **Ignore** `updates.powerupStepInterval` entirely (§4.3) |
| `tournaments/commands/createTournament.js` | 102, 158 | Use the normalizer's return |

`tournaments/services/tournamentRounds.js:56` copies the tournament's interval
onto each matchup race, so bracket matches inherit 2,000 with no change needed.

### 4.3 Why edit must ignore the field, not coerce it

`rollPowerup.js:176,227` walks a ratchet: `currentThreshold += powerupStepInterval`.
Lowering a *running* race's interval from 5,000 to 2,000 does not just change
future boxes — it changes how many boxes the participant should *already* have,
and the next steps-sync mints the difference at once. A player at 20,000 steps
jumps from 4 boxes earned to 10, minting 6 instantly.

That is precisely the bug class we already shipped once: the public-join
over-grant, where a wrong box-window start handed mid-race joiners boxes for
steps walked before they joined. Do not re-introduce it.

So `PATCH /races/:id` **drops `powerupStepInterval` on the floor**: no
persistence, no 400. `powerupsEnabled` remains editable, and flipping it from
false → true sets the interval to 2,000 (that race had `null` before, so there
is no ratchet history to disturb).

### 4.4 Seeded daily/weekly

`races/jobs/seededRaceRenewal.js:67` currently does
`powerupStepInterval: seed.powerupStepInterval ?? null`. It becomes the
normalizer call keyed on `seed.powerupsEnabled`. Same one-line change in
`tournaments/jobs/tournamentSeedRenewal.js:82`.

Effect in prod: tomorrow's `DAILY_10K` is minted at 2,000 instead of 2,500.
Today's already-minted challenge keeps 2,500 until it rolls over — consistent
with §2's "existing races are not touched".

---

## 5. API contract

### 5.1 `POST /races` (and `POST /tournaments`)

Request — **unchanged shape**. `powerupStepInterval` remains an accepted,
optional field so no client of any version 400s.

```jsonc
{
  "name": "Morning Walk",
  "timeBased": true,
  "maxDurationDays": 7,
  "powerupsEnabled": true,
  "powerupStepInterval": 10000   // accepted, IGNORED, never an error
}
```

Response — `race.powerupStepInterval` is **2000** whenever
`powerupsEnabled` is true, and `null` when false. No new fields, no removed
fields, no status-code changes.

| Client sends | Stored | Response says |
|---|---|---|
| `powerupsEnabled: true, powerupStepInterval: 10000` (old app) | 2000 | 2000 |
| `powerupsEnabled: true, powerupStepInterval: 2000` (new app) | 2000 | 2000 |
| `powerupsEnabled: true`, field omitted | 2000 | 2000 |
| `powerupsEnabled: false` (any interval) | `null` | `null` |
| `powerupsEnabled: true, powerupStepInterval: 999` (out of old band) | 2000 | 2000 |

That last row is a deliberate behavior change: the old validator threw
`400 "Powerup step interval must be between 2,000 and 50,000"`. Since the value
is discarded, there is nothing left to validate, and a 400 would only ever
punish a client for a number we ignore. **The error is retired.**

### 5.2 `PATCH /races/:id`

`powerupStepInterval` is accepted and ignored (no 400, no persistence). Response
echoes the race's unchanged stored interval. Everything else is untouched.

### 5.3 Read paths — no change at all

`getRaceDetails.js:83`, `getPublicRaces.js:63`, `getRaceProgress.js:606`, and
`serializeTournament.js:78` keep returning `powerupStepInterval` exactly as
before. This is what makes an old binary correct: its race-detail screen renders
*"You earn a powerup every 2,000 steps this race"* from the server's value
(`lib/screens/race_detail_screen.dart:4200`), even though its own create screen
briefly showed "10k" at the moment of submission.

### 5.4 Old-client compatibility summary (the #1 rule)

| Combination | Behavior |
|---|---|
| **Old app + new backend** | Creates fine. Picks "10k" in its UI, gets a 2k race, and its own race-detail screen then reads 2,000 from the API and displays it correctly. Edit "saves" the interval with no effect; a refetch shows the true value. |
| **New app + old backend** | Sends `powerupStepInterval: 2000` explicitly. 2,000 is inside the legacy `[2000, 50000]` band, so **every** currently-deployed backend accepts it. This is why the app keeps sending the field rather than omitting it. |
| **Old app + old backend** | Untouched. |

The one visible wart — an old create screen claiming 10k for the few seconds
before the race detail loads — is accepted (D1). The alternative (400ing old
clients) would break race creation for every un-updated binary for a week.

---

## 6. Data model / migrations

**No migration.** `races.powerup_step_interval`,
`tournaments.powerup_step_interval`, and `race_seeds.powerup_step_interval` all
stay exactly as they are:

- `races` / `tournaments`: still written (now always 2000 or null) and still
  read by every client version.
- `race_seeds`: no longer read by the renewal jobs. Optional tidiness after
  deploy, on prod and staging:
  ```sql
  UPDATE race_seeds SET powerup_step_interval = 2000 WHERE powerups_enabled;
  ```
  This is cosmetic only — the code no longer consults the column — so it is
  safe to skip, and it must never run against a test DB's prod connection
  string.

No backfill of existing races (§2, §4.3).

---

## 7. Frontend plan

Both platforms ship from the same Dart, so iOS and Android are covered by the
same edits and must be built in lockstep.

### 7.1 `lib/screens/create_race_screen.dart`
- Delete `_intervalPresets` (line 138) and the `Wrap` of preset chips
  (lines ~1605–1650).
- `_powerupInterval` becomes `const _kPowerupInterval = 2000` — still sent on
  all three create paths (races 504, team 548, tournaments 560) for the
  new-app-old-backend case (§5.4).
- Replace the picker with an explanatory **blurb sitting directly under the
  POWERUPS enable/disable row** inside the same `RetroCard` (owner request,
  2026-07-24). Requirements:
  - It explains the rule in plain language — the player should come away
    knowing a box arrives **every 2,000 steps** — rather than just labelling a
    number. Something in the register of *"You'll earn a powerup box every
    2,000 steps."*
  - It must read as **app chrome we already have**, not a bolted-on note: reuse
    the existing `PixelText` scale and `AppColors.of(context)` roles used
    elsewhere in this card (`textMid` for secondary copy, `textDark` for
    emphasis) so it themes correctly in **both light and night mode**. Per
    `dark-mode-fix-batch-2026-07-23`, do not hardcode `ink`/`pillGold` — those
    flip at night.
  - Whether it shows only when the toggle is ON, or is always visible as a
    description of what the toggle does, is the implementer's call — but the
    card must not be left with dead space or an orphaned heading once the
    "POWERUP EVERY" label and chips are gone.
  - The design skills (`.claude/skills/mobile-design`,
    `.claude/skills/frontend-design`) are loaded **before** this is written.

### 7.2 `lib/screens/edit_race_screen.dart`
- Delete `_intervalPresets` (84), `_powerupInterval` (52, 135), the dirty-check
  clauses at 419 and 496–497, and the picker at ~780–800.
- `updates` never contains `powerupStepInterval`.
- Same blurb treatment as §7.1 — but the number is read from
  `race['powerupStepInterval']` with a **2,000 fallback**, so a grandfathered
  5,000-step race honestly says 5,000 rather than lying about its own rules.

### 7.3 Degradation when the field is missing
`race_detail_screen.dart:4185` already guards `null`/`<= 0` and hides the line —
unchanged. The new edit-screen line uses the same defensive read: absent or
non-numeric → fall back to 2,000 rather than throwing or rendering "null".

### 7.4 Load the design skills
Per `ui-redesign-feedback-rules`, the frontend agent loads the mobile-design and
frontend-design skills before touching either screen. The change removes a
control from an existing card, so the card must not be left with dead vertical
space or an orphaned heading.

---

## 8. Backward-compat & rollout

**Deploy order: backend first, then the app.** Non-negotiable.

1. **Backend** (safe alone): old apps immediately start getting 2,000-step
   races while still showing their own picker. Nothing breaks; the rules just
   become uniform ahead of the app.
2. **App** (iOS `flutter build ipa` + Android `flutter build appbundle
   --flavor prod`, in lockstep, same version/build number): removes the picker.
3. **Seeded challenges** switch to 2,000 on the next renewal tick after step 1.

No feature flag and no `testOnly` gating is needed: there is no new field, no
new endpoint, and no new enum for a frozen client to choke on. The change is
purely "a number the server now decides".

**Rollback:** revert the backend commit. Races created while it was live keep
2,000 (they are ordinary rows); nothing needs undoing.

---

## 9. Test plan (written FIRST, before any logic)

Per CLAUDE.md these are integration tests through the real HTTP path and the
real widgets — not unit tests over the normalizer.

### Backend — `test/integration/fixed-powerup-interval.test.js`
1. `POST /races` with `powerupStepInterval: 10000` → 201, and
   `GET /races/:id` reports **2000**. *(the old-binary case)*
2. `POST /races` with the field omitted entirely → 2000.
3. `POST /races` with `powerupStepInterval: 999` → **201, not 400**, stored 2000.
   *(the retired validation error)*
4. `POST /races` with `powerupsEnabled: false, powerupStepInterval: 5000` →
   stored `null`.
5. `POST /tournaments` with `powerupStepInterval: 25000` → tournament stores
   2000, **and** its first-round matchup races store 2000.
6. `PATCH /races/:id` sending `powerupStepInterval: 5000` on a 2000-step race →
   200, still 2000 afterwards. *(edit is inert, not an error)*
7. `PATCH /races/:id` flipping `powerupsEnabled` false → true → interval 2000.
8. A race row seeded directly at 5000 (a grandfathered pre-deploy race) is
   **unchanged** by any PATCH, and `GET /races/:id/progress` still paces its
   boxes at 5,000. *(no retroactive box minting — §4.3)*
9. `seededRaceRenewal` minting a fresh race from a seed whose
   `powerupStepInterval` is 2500 produces a race at **2000**.

### Frontend — `test/create_race_powerup_interval_test.dart`
10. Pump `CreateRaceScreen`, enable powerups → **no** interval chips render
    (3k/4k/5k/10k/25k all absent) and the blurb naming **2,000 steps** does.
11. Submitting sends `powerupStepInterval: 2000` on the race, team-race, and
    tournament paths. *(new-app-old-backend guarantee, §5.4)*
12. Pump `EditRaceScreen` for a powerups-on race → no chips; saving produces an
    `updates` map with **no** `powerupStepInterval` key.
13. `EditRaceScreen` for a grandfathered race whose payload says 5000 shows
    "every 5,000 steps", not 2,000.
14. `EditRaceScreen` for a payload with `powerupStepInterval: null` (older or
    newer backend) renders the 2,000 fallback without throwing.

Existing tests are never modified. Checked while drafting: the create/edit
screen suites (`create_race_screen_test.dart`,
`create_race_screen_team_mode_test.dart`,
`create_race_screen_tournament_mode_test.dart`,
`edit_race_screen_buyin_edit_test.dart`) only capture `powerupStepInterval` in
their fake-API signatures — **none asserts on the picker chips** — so removing
the picker should not disturb them. If any existing test does go red, that is
**surfaced to the owner**, not "fixed".

---

## 10. Acceptance criteria

- [ ] Every powerups-enabled race/tournament created after the backend deploy
      stores `powerupStepInterval = 2000`, whatever the client sent.
- [ ] No client version can receive a 400 for a `powerupStepInterval` value.
- [ ] `PATCH` cannot change an existing race's interval.
- [ ] Races created before the deploy keep their original interval and their
      box cadence does not jump.
- [ ] Seeded daily/weekly challenges mint at 2,000 on the next renewal.
- [ ] Neither create nor edit shows an interval picker; both show the real
      per-race value.
- [ ] The new app sends 2,000 explicitly and works against the current
      production backend (verified before the app ships).
- [ ] iOS and Android built in lockstep, same version/build number.
- [ ] All tests in §9 written first, failing for the right reason, then green.

---

## 11. Revision log

**Gap pass 1** (re-read cold, hunting for missed surfaces and hard-rule
violations):
- The draft only covered `POST /races`. Found `createTournament.js:158` and both
  renewal jobs writing the field on paths the create screen never touches;
  tournaments are created *from the same screen* (`create_race_screen.dart:498`),
  so leaving them out would have shipped a bracket whose matches used a stale
  interval. Added §4.2 and §4.4.
- The draft coerced `PATCH` to 2,000 like `POST`. Traced `rollPowerup.js:176`
  and realized that back-mints boxes on any running race whose interval drops —
  the public-join over-grant bug again. Changed to "accepted and ignored" and
  wrote §4.3 to record *why*, so nobody "fixes" it back later.
- The draft had `validatePowerupConfig` keep throwing on out-of-band values.
  That contradicts D1: it would 400 an old client over a number we discard.
  Retired the error and documented it as an intentional contract change (§5.1).

**Gap pass 2** (second independent pass, focused on the frozen-binary rule and
on what a developer would still have to guess):
- **New app + old backend was unhandled.** The draft had the app stop sending
  the field. During the phased rollout the new app can hit a backend that has
  not deployed yet, where `powerupsEnabled: true` with no interval fails the
  legacy `!powerupStepInterval` check → **400, cannot create a race.** Fixed:
  the app keeps sending `2000` explicitly, which every deployed backend accepts.
  This is now called out in §5.4 and locked by test 11.
- Edit screen would have shown "every 2,000 steps" for a grandfathered
  5,000-step race — a lie about that race's own rules. Changed to read the
  server value with a 2,000 fallback (§7.2, tests 13–14).
- Added the "field omitted" and "`powerupsEnabled: false`" rows to the §5.1
  table; the original table only covered a too-large value, leaving the null
  path unspecified.
- Named the prod seed values (2500 for both `DAILY_10K` and `WEEKLY_50K`) rather
  than saying "some value", and marked the `UPDATE` optional so nobody treats a
  cosmetic write as a required migration step.
- Added the explicit "existing tests may assert on the picker → surface, do not
  edit" note to §9, since that is the rule the implementing agents are most
  likely to trip over here.
