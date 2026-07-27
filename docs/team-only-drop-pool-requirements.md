# Team-only drop pool — requirements

**Status:** awaiting approval
**Date:** 2026-07-26
**Repos:** `stepv2-backend` (owner), `stepv2-frontend` (admin visibility only)

---

## 1. Summary & user story

Rally Flag is a 150-coin store powerup that **nobody has ever bought** (0 purchases,
0 mints in prod, all-time). It is also the only powerup whose effect is
exclusively a team-race effect: `usePowerup.js:1205` hard-rejects it in a solo
race with `"Rally Flag needs a team race"` (400 `INVALID_TARGET`).

> As a player in a team race, I want Rally Flag to turn up in my mystery boxes,
> so that team races have a mechanic solo races don't — instead of being
> solo-with-shared-scoring.

To do that the roll has to learn a fact it does not currently know: **whether the
race is a team race.** Today the drop pool is conditioned only on leaderboard
position. This spec adds one new dimension to that seam, in the shape of the
existing one, and moves Rally Flag from the store into the team-race drop pool.

Rally Flag is the first user of the seam. Uprising and Power Outage are the
obvious next two (both already reject a `targetUserId`, and Uprising has a
losing-team gate) — they are **out of scope here** but the seam is designed for
them, not special-cased to Rally Flag.

## 2. Scope / non-goals

**In scope**
- A new balance-config key `teamOnlyTypes`, and a drop-pool filter that honours it.
- A `powerups5` client-feature filter on the **in-race mystery-box roll**, which
  today has no client gating at all.
- Moving `RALLY_FLAG` out of `storeOnlyTypes` and into `dropPool.UNCOMMON`.
- Hiding `RALLY_FLAG` from the powerup store (`active=false`).
- Admin visibility of the new key.

**Non-goals**
- Moving Uprising / Power Outage (separate decision; the seam supports it).
- Changing Rally Flag's effect, duration (1h), or multiplier (1.25x).
- Making the daily reward box team-aware — it has no race context and never can.
- A general per-race-mode balance system. `teamOnlyTypes` is one flat list.
- Editing drop-pool membership from the admin app (see §5.3 — deliberately not
  added; the editor stays a typed form over scalars).

## 3. Why this is not a config-only change

Two facts discovered while scoping. Both invalidate the "just flip it in the
balance editor" plan, and both must be handled or the change silently does nothing.

**3.1 The code defaults veto the stored config.**
`enforceStoreOnlyExclusion` (`balanceConfig.js:78`) filters the drop pool using
the **union** of the stored `storeOnlyTypes` and `defaultConfig().storeOnlyTypes`:

```js
const storeOnly = new Set([
  ...(Array.isArray(config?.storeOnlyTypes) ? config.storeOnlyTypes : []),
  ...defaultConfig().storeOnlyTypes,   // <-- code defaults always win
]);
```

`RALLY_FLAG` is in the defaults list (`balanceConfig.defaults.js:202`). So adding
it to a stored `dropPool` while it remains in the shipped defaults produces
**exactly zero behaviour change** — the merge strips it on every read. This is
the same asymmetry recorded for Pocket Watch, running the other way. Removing it
from the defaults is a **code change and a deploy**, not an admin edit.

**3.2 A stored `dropPool` array replaces the defaults wholesale.**
`mergeOverDefaults` replaces arrays rather than unioning them, and prod's stored
config carries its own `dropPool`. So editing `dropPool` in the defaults file
does not reach prod either. Enabling this requires **both** a deploy (defaults)
**and** a new stored config version (data).

**3.3 There is no supported write path for `dropPool`.**
The admin balance editor is a typed form and renders `dropPool` as read-only
chips (`admin_balance_config_screen.dart:1040`); its header comment is explicit
that it is "never a raw JSON editor". The only write path is
`PUT /admin/balance-config` with a full config body. §5.3 specifies a script for
this rather than loosening the editor.

## 4. The compatibility problem this must solve

In-race box drops have **no client-feature gating anywhere**. That has been safe
only structurally: wave-5 types aren't in `dropPool`, so the question never
arose. `openMysteryBox({userId, raceId, powerupId, displayName})` does not even
receive the channel or the client features.

Put `RALLY_FLAG` in `dropPool` without a gate and any pre-`powerups5` binary can
roll one, then be refused at use time with `UPDATE_REQUIRED`
(`usePowerup.js:896`) — a dead slot in a 3-slot inventory, in a live race.

This is not hypothetical. The `powerups5` token was added **2026-07-23**
(`f72a74e`) and ships in **2.0.0+**; 2.0.x is TestFlight and the App Store
release is still pending. Prod `activation_events` over the last 14 days shows
App Store users on **1.6.7 / 1.6.8 / 1.6.9 / 1.7.0 / 1.7.1** — every one of them
pre-`powerups5`. (Caveat: `app_version` exists only on that table and covers 7
users over 14 days out of 119. Directional, not a census — which is an argument
for the gate, not against it.)

`testOnly` does **not** help here: it gates the store catalog and the daily box,
never the in-race roll.

The gate is also what makes this **shippable now**. Without it, the config flip
must wait for 2.0.x to roll out through a phased release, and never-updaters
would keep rolling duds indefinitely.

## 5. Contract

This is the interface between the two agents. It is pinned before either starts.

### 5.1 Balance config — new key `teamOnlyTypes`

```jsonc
{
  "schemaVersion": 1,
  "teamOnlyTypes": ["RALLY_FLAG"],   // NEW — droppable, but only in team races
  "storeOnlyTypes": [ /* ... RALLY_FLAG REMOVED ... */ ],
  "dropPool": {
    "COMMON":   ["PROTEIN_SHAKE", "TRAIL_MIX", "DETOUR_SIGN", "RUNNERS_HIGH", "PINECONE_TOSS"],
    "UNCOMMON": ["LEG_CRAMP", "STEALTH_MODE", "WRONG_TURN", "RALLY_FLAG"],   // ADDED
    "RARE":     [ /* unchanged */ ]
  }
}
```

Semantics — the three list keys answer three different questions and must not be
conflated (this is the D13 rule the existing comments already state):

| Key | Question | Rally Flag after this change |
|---|---|---|
| `storeOnlyTypes` | Can an in-race mystery box roll this? | removed → yes, it can |
| `teamOnlyTypes` | …but only when the race is a team race? | **yes** |
| `dailyBoxExcludedTypes` | Can the daily spin award it? | stays listed → no |

`rarityByType.RALLY_FLAG` is already `"UNCOMMON"` (`defaults.js:134`) — no change
needed, and `dropPool.UNCOMMON` is the tier that must match it.

### 5.2 Validation (`validateConfig`)

Additive rules:
- `teamOnlyTypes` must be an array; every entry must be in `BALANCE_POWERUP_TYPES`.
- A type may appear in **both** `teamOnlyTypes` and `dropPool` — that is the
  entire point, and the existing store-only rejection must not fire on it.
- A type must **not** appear in both `teamOnlyTypes` and `storeOnlyTypes`
  (contradiction: undroppable and conditionally droppable).

**One existing rule must be relaxed.** Today `dailyBoxExcludedTypes` rejects any
type that is not also store-only:

```
`${type} is excluded from the daily box but is not store-only`
```

Once `RALLY_FLAG` leaves `storeOnlyTypes` but stays in `dailyBoxExcludedTypes`,
**this rejects the config save.** The check must accept `storeOnlyTypes` **or**
`teamOnlyTypes`. Its intent — "don't silently bar something that is otherwise
freely obtainable" — is preserved.

### 5.3 Writing the config

Add `scripts/balance-apply.js` (`npm run balance:apply`), modelled on
`scripts/powerup-store.js`: `--db=local|staging|prod`, **dry-run by default**,
`--apply` to write, printing the diff it would PUT. It saves a new version
through `balanceConfig.saveConfig` so validation, versioning and
`rollbackTo` all apply. It must not bypass `validateConfig`.

Rationale for a script over extending the editor: the editor's stated contract
is a typed form over scalars, and drop-pool membership is a list of enums with
cross-field invariants. A reviewed, dry-runnable script is the safer surface, and
`balance:pull` already exists to record the result in git.

### 5.4 Roll seam

`buildRollContext` (`powerupOdds.js:89`) gains two fields, both defaulting to the
current behaviour when absent:

```js
buildRollContext({
  stepTotals, myTotalSteps, position, totalParticipants,
  isTeamRace = false,          // NEW
  supportsPowerups5 = false,   // NEW
})
// -> { normalizedPosition, isStepLeader, isStepLast, isTeamRace, supportsPowerups5 }
```

`eligiblePoolFor(rarity, ctx, config)` (`powerupOdds.js:147`) gains two
exclusions alongside the existing `leaderExcluded` / `lastPlaceExcluded`:

1. if `!ctx.isTeamRace`, exclude every type in `config.teamOnlyTypes`;
2. if `!ctx.supportsPowerups5`, exclude every type in `POWERUPS5_GATED_TYPES`.

**Both must be applied OUTSIDE the empty-pool fallback at line 163.** That
fallback (`if (pool.length === 0) pool = basePool.slice()`) exists so an
aggressive balance config can't make a tier unreachable. It is correct for a
balance heuristic and **wrong for a compatibility gate**: restoring the
unfiltered pool would hand a frozen client the exact item the gate exists to
prevent. Required structure:

```js
// balance-only filters, fallback-eligible
let pool = applyPositionRules(basePool, ctx, rules);
if (pool.length === 0) pool = basePool.slice();
// HARD gates, never restored by the fallback
pool = pool.filter((t) => ctx.isTeamRace || !teamOnly.has(t));
pool = pool.filter((t) => ctx.supportsPowerups5 || !POWERUPS5_GATED_TYPES.includes(t));
```

If the hard gates empty a tier the roll returns `null`, which `openMysteryBox`
must handle — see §5.5.

### 5.5 Empty-tier behaviour

With `UNCOMMON` at 4 types of which 1 is gated, a tier can never empty in
practice. It must still be defined, because `drawWeighted` returns `null` on an
empty pool and the caller would write a `null` type onto the row.

**Rule:** if `pickTypeForRarity` returns `null`, `openMysteryBox` re-rolls once
at the tier below (`RARITY_ORDER` order), and if that also returns `null`, awards
`PROTEIN_SHAKE` — the always-present COMMON. It must never persist a `null` type
and never throw: a box the player already tapped must always produce something.

### 5.6 Call sites to thread

| Call site | Change |
|---|---|
| `races/routes.js:770` `POST /:raceId/powerups/:powerupId/open` | pass `supportsPowerups5: req.clientFeatures?.has("powerups5") ?? false` |
| `races/routes.js:794` `POST /:raceId/powerups/open-batch` | same |
| `openMysteryBox` (`commands/openMysteryBox.js`) | accept `supportsPowerups5`; pass it and `race.isTeamRace` into `buildRollContext` |
| `openMysteryBoxBatch` | same |
| `getRaceProgress.js:127` | build ctx with the **same** two fields; needs `supportsPowerups5` threaded from its route |

The `getRaceProgress` one is not optional. `typeOddsForPosition` (line 144) emits
a `byType` map keyed by raw powerup type, so an ungated odds sheet would
advertise `RALLY_FLAG` to a client that cannot roll it — and the whole design of
this seam is that the roll and the disclosure read the same function with the
same ctx. If they diverge, the odds sheet lies.

### 5.7 Store row

`RALLY_FLAG` → `active=false` via the existing tool:

```
npm run powerups:store -- hide RALLY_FLAG --db=prod --apply
```

`testOnly` is left `true`. `active=false` removes it from
`GET /shop/powerups` and 404s a purchase; it does not affect drops, inventory or
use. The script prints the drop-pool consequence after a hide, which after this
change will correctly report `RALLY_FLAG (UNCOMMON)` as still obtainable.

### 5.8 Response shapes

**Unchanged.** No endpoint gains or loses a field. A rolled Rally Flag serializes
exactly like any other powerup, and `getRaces.js:56` / `getRaceProgress.js:687`
already downcast `RALLY_FLAG` → `RUNNERS_HIGH` on the read path for pre-wave-5
clients. That downcast stays and is now belt-and-braces: with §5.4 in place no
such client can hold one.

## 6. Data model / migrations

**No schema migration.** `teamOnlyTypes` is a key inside the existing
`balance_config.config` JSON column.

- **Defaults (code):** remove `RALLY_FLAG` from `storeOnlyTypes`; add
  `teamOnlyTypes: ["RALLY_FLAG"]`; add `RALLY_FLAG` to `dropPool.UNCOMMON`; leave
  it in `dailyBoxExcludedTypes`.
- **Stored (data):** one new config version via §5.3, same three edits. Required
  because a stored `dropPool` replaces the defaults wholesale (§3.2).
- **Default-safe reads:** a stored config with no `teamOnlyTypes` resolves to the
  defaults' list through `mergeOverDefaults`. Every read must tolerate the key
  being absent or not an array — treat as `[]`, i.e. no team restriction, which
  is the pre-change behaviour.
- **`schemaVersion` is not bumped.** The key is additive and absence is
  well-defined; bumping would reject every stored config on the old value.

## 7. Frontend plan

The frontend already fully supports Rally Flag — it is in the TestFlight store
today, with copy (`lib/constants/powerup_copy.dart`), an icon
(`lib/widgets/powerup_icon.dart`) and polarity (`lib/utils/effect_polarity.dart`).
**No player-facing frontend work is required.**

The one change is admin visibility, so the new state is inspectable:

- `admin_balance_config_screen.dart` — render `teamOnlyTypes` as a read-only chip
  row next to the existing `dropPool` chips, labelled "Team races only".
  Degrade safely: a config with no `teamOnlyTypes` renders nothing at all (not an
  empty box, not an error) — the backend may be older than the app.
- `admin_powerup_shop_screen.dart` — no change; its `active` switch already does
  §5.7's job from the app.

States: loading/error/empty follow the screen's existing patterns. iOS and
Android build in lockstep per CLAUDE.md; there is no platform-specific code here.

## 8. Backward-compat & rollout

**Deploy order**

1. **Backend deploy** — the gate, the validation change, the defaults edit, the
   new script. Behaviour is unchanged at this point: prod's *stored* config still
   lacks `RALLY_FLAG` in `dropPool`, so nothing drops yet. This is deliberate —
   the gate lands strictly before the thing it gates.
2. **Verify** — confirm on staging that a client not advertising `powerups5`
   never rolls a Rally Flag, and that a solo race never rolls one at all.
3. **Config version** — `npm run balance:apply --db=prod --apply`. Drops begin.
4. **Store row** — `npm run powerups:store -- hide RALLY_FLAG --db=prod --apply`.
5. `npm run balance:pull` + `npm run powerups:docs` to record both in git.

**What a frozen old client does.** A pre-`powerups5` binary (every current App
Store version) advertises no `powerups5` token, so §5.4's second filter removes
`RALLY_FLAG` from its pool before the draw. It cannot roll one, is not shown one
in the odds sheet, and its experience is bit-for-bit what it is today. A
`powerups5` client in a **solo** race is likewise unaffected by the first filter.

**Kill switch.** `balanceConfig.rollbackTo(previousVersion)` — no deploy, effective
within the 5s config cache TTL. Rolling back removes `RALLY_FLAG` from the stored
`dropPool`; already-held copies remain usable in team races and rejected in solo,
which is the pre-existing behaviour and needs no cleanup.

**Not required:** waiting for the 2.0.x App Store rollout. That is the entire
return on §5.4.

## 9. Test plan (written FIRST, must fail for the right reason)

**Backend — integration (`test/integration/`), the default per CLAUDE.md**

1. Team race, `powerups5` client, forced UNCOMMON roll → `RALLY_FLAG` is
   reachable (seeded RNG; assert over the real open endpoint, not the roller).
2. **Solo** race, `powerups5` client, forced UNCOMMON → `RALLY_FLAG` is never
   returned across N seeded rolls.
3. Team race, client **without** `powerups5` → `RALLY_FLAG` never returned.
4. Same, via `POST /races/:raceId/powerups/open-batch` — both roll paths, since
   gating one and not the other is the likely miss.
5. `GET /races/:id/progress` odds sheet: `byType` contains `RALLY_FLAG` for a
   `powerups5` client in a team race, and omits it in the other three
   combinations. Asserted through the endpoint response.
6. Purchase `POWERUP_RALLY_FLAG` after §5.7 → 404.
7. A held Rally Flag still applies to the whole team in a team race, and still
   400s in a solo race — the effect is unchanged by this work.

**Backend — unit (justified: pure table math, many cases)**

8. `eligiblePoolFor` — the 2×2 of (team/solo) × (powerups5/not) per tier.
9. The empty-pool fallback does **not** restore a hard-gated type (§5.4). This is
   the single highest-value test in the plan.
10. §5.5 empty-tier cascade: `null` → tier below → `PROTEIN_SHAKE`, never `null`
    persisted.
11. `validateConfig`: `teamOnlyTypes` type errors; the both-lists contradiction
    rejects; a `teamOnlyTypes` member in `dropPool` is **accepted**; a
    `dailyBoxExcludedTypes` member that is team-only but not store-only is
    **accepted** (the §5.2 relaxation).
12. `mergeOverDefaults`: a stored config with no `teamOnlyTypes` inherits the
    defaults; `enforceStoreOnlyExclusion` no longer strips `RALLY_FLAG`.
13. Parity: `typeOddsForPosition` and `pickTypeForRarity` produce the same
    eligible set for identical ctx across all four combinations.

**Frontend**

14. Pump `AdminBalanceConfigScreen` with a config carrying `teamOnlyTypes` →
    chips render; with the key absent → nothing renders and no exception.

**Existing tests are never modified.** If one appears wrong, surface it.

## 10. Acceptance criteria

- [ ] A `powerups5` client in a team race can roll Rally Flag from a mystery box.
- [ ] No client can roll it in a solo race.
- [ ] No pre-`powerups5` client can roll it in any race.
- [ ] The odds sheet lists it in exactly the cases it can drop.
- [ ] It cannot be purchased; the store no longer shows it on any channel.
- [ ] The daily reward box never awards it.
- [ ] A box open never persists a `null` type and never 500s.
- [ ] Rally Flag's effect (team-wide, 1.25x, 1h) is byte-identical to today.
- [ ] `npm run test:unit` and `npm run test:integration` green (the 13 known
      fanny-pack integration failures are pre-existing — see memory).
- [ ] `POWERUPS.md` regenerated; `data/balance-config.json` pulled; both committed.
- [ ] iOS **and** Android built in lockstep.
- [ ] Rollback rehearsed on staging: `rollbackTo` stops drops without a deploy.

## 11. Revision log

**Pass 1 — fresh-eyes gap pass**
- **Found the `dailyBoxExcludedTypes` cross-check would reject the config save.**
  The draft said "leave it in `dailyBoxExcludedTypes`" while also removing it
  from `storeOnlyTypes` — which trips the existing
  `"excluded from the daily box but is not store-only"` rule and makes the
  config unsaveable. Added §5.2's relaxation. This would have failed at step 3
  of rollout, after the deploy.
- **Found the defaults-veto and stored-array-replacement asymmetries** (§3.1,
  §3.2). The draft treated this as an admin-editor flip. It is a deploy plus a
  data write, and neither alone does anything.
- **Found there is no write path for `dropPool`** (§3.3) — the editor is
  read-only for it. Added §5.3 rather than assuming one existed.
- Added §5.5: the hard gates make `pickTypeForRarity` able to return `null`, which
  no caller currently handles.

**Pass 2 — second independent pass**
- **Tightened §5.4 from prose to required structure.** "Apply the filter outside
  the fallback" is the kind of instruction that gets implemented as a one-line
  `.filter()` in the wrong place; the ordering is now shown as code, and test 9
  exists specifically to catch it.
- **Added `getRaceProgress` to §5.6.** Pass 1 listed only the two roll paths, which
  would have shipped an odds sheet advertising an undroppable item — the exact
  failure the shared-seam comments at `powerupOdds.js:144` warn about.
- **Added the batch endpoint** to §5.6 and test 4. Gating `open` and forgetting
  `open-batch` is the most plausible partial implementation.
- Pinned §6's "no `schemaVersion` bump" — bumping is the reflex, and it would
  reject every stored config.
- Re-scoped §7 to admin-only after confirming Rally Flag's player-facing assets
  and copy already ship; the draft over-claimed frontend work.
- Framed Uprising / Power Outage as explicit non-goals in §2 so the seam is built
  general but the blast radius stays one powerup.

**Open questions:** none. Everything raised in both passes is resolved above.
