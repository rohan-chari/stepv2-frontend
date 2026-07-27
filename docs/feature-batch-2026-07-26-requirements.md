# Feature & Bugfix Batch — 2026-07-26

**Status:** BUILT (Phase 5 complete) — uncommitted in both repos, NOT deployed.
Blocked on one owner decision: three existing tests assert behaviour this batch
deliberately changed (see §13). Nothing was committed, pushed, or deployed.
**Items:** 18 reported → **16 to build** (item 5 closed as no-change; item 4 reduced to copy + feed line)
**Numbering:** owner's 1–18 preserved throughout
**Repos:** `stepv2-frontend`, `stepv2-backend`

---

## 1. Summary & user story

A mixed batch of 18 owner/tester-reported items from the 2.0.1 TestFlight round: shop
usability (1, 2, 7), dark-mode legibility (3, 13), character visibility and switching
(6, 8, 11), powerup correctness (4, 5, 9, 10, 14, 17), cross-screen number
consistency (12, 16), and two copy/asset polish items (15, 18).

Three items turned out to be symptoms of deeper defects that exploration confirmed:

- **Items 12 + 16 are one bug.** The backend maintains *two scoring worlds* (live
  effect-resolved vs persisted `RaceParticipant.totalSteps`) and *five* different rank
  comparators. Home, the races list, and race detail each read a different one.
- **Item 8 is a backend visibility bug, not a client/asset bug.** Turtle and corgi are
  `testOnly:true`, and `characterPresentation()` strips test-only characters with no
  release-channel awareness and **no self-exemption** — so a TestFlight turtle user is
  served `animal: null` for their own row.
- **Item 3 is systemic.** The team totals render at **1.09:1 contrast** in night mode
  (WCAG AA needs 4.5:1). The audit found ~40 more theme-blind sites.

Two items are **not bugs as reported** and need an owner decision before any code is
written — see §3 (item 5) and §8 (item 17).

---

## 2. Scope / non-goals

### In scope
All 18 items below, across both repos, iOS + Android in lockstep.

### Explicit non-goals
- **No unification of the two scoring worlds.** Items 12/16 are fixed by making the
  *display* surfaces agree (one server-authoritative rank), not by rewriting scoring.
  A full merge of live vs persisted totals is a separate project.
- **No dark-mode rewrite.** Item 3's audit found ~40 offenders; this batch fixes the
  user-visible ones (P1–P7 in §4) and adds a regression guard. Decorative
  CustomPainter art and the systemic drop-shadow issue are logged, not fixed.
- **No new powerup types**, no economy/pricing changes, no new characters.
- **Item 11 does not change Zoomies' scoring math** — only how a window is started.
- Legacy dead widgets (`race_track.dart`, `GoalTrack`) are not revived or deleted here.

---

## 3. Per-item findings, decisions, and implementation path

Each item lists: **Finding** (what exploration actually proved), **Decision**
(locked in §11 — all decisions are final), **Path** (files, in order).

---

### Item 1 — Shop filter/sort chips truncate; merge into one dropdown

**Finding.** `lib/screens/tabs/shop_tab.dart`. The filter row is four `Expanded` pills
(`_powerupFilterPill`, `:1089-1124`) labelled **ALL / OFFENSE / DEFENSE / UTILITY**
(`:99-114`) — note the existing labels are already "OFFENSE/DEFENSE", not
"OFFENSIVE/DEFENSIVE". Chip text is 10pt with `maxLines:1, overflow: ellipsis`
(`:1111-1121`), so they clip on narrow phones. The sort control (`:1126-1177`) is a
`PopupMenuButton<_PowerupSort>` whose label `'Sort: ${_powerupSort.label}'` (`:1161`)
has **no `maxLines`/ellipsis**, so its Row overflows rather than clipping.
Categories come from the backend `category` field, normalized client-side by
`_powerupCategoryOf` (`:1018-1022`) — unknown/missing → `utility`.

**Decision.** Replace the entire filter-pill row **and** the sort pill with a **single
dropdown control** opening one sheet with two labelled groups:
- **Filter** — All / Offense / Defense / Utility (single-select)
- **Sort** — Name (A–Z) / Price: Low→High / Price: High→Low / Rarity (single-select)

The collapsed button shows the active state compactly, e.g. `Offense · Price ↑`, with
`maxLines:1` + ellipsis. Reuse the existing `_PowerupCategoryFilter` and `_PowerupSort`
enums and `_visiblePowerupStoreItems()` (`:1037-1063`) — **filter/sort semantics do not
change**, only the control. Defaults stay All + Name (A–Z).

**Path.** `shop_tab.dart`: delete `_buildPowerupControls` (`:1065-1087`),
`_powerupFilterPill` (`:1089-1124`), `_buildSortControl` (`:1126-1177`); add a
`_ShopFilterSortBar` widget + bottom sheet; rewire the `:521-525` build branch.
Load the **`mobile-design` skill first** — this is new UI.
**Test impact:** `test/shop_powerup_filter_sort_test.dart` drives the old pills
(`:109,:123,:133,:143,:171`). Per the hard rule, do **not** edit it — the agent must
surface it; owner decides. (See §11 Q7.)

---

### Item 2 — Show the price even when unaffordable

**Finding.** `shop_tab.dart:1428-1439` (powerups) and `:937-946` (cosmetics) replace
the price with the ad/get-coins CTA. `_routeFor` (`:1184-1190`) picks
`affordable | watchAds | getCoins`. Only the affordable branch ever prints the number,
so an unaffordable item shows **no price anywhere on the tile**.

**Decision.** The tile's strip keeps the CTA, and the **price is always displayed** —
added as a small coin+number chip in the art area's top-left (mirroring the existing
`xN` owned badge at top-right, `:1823-1860`). This costs no strip width, so it does not
worsen item 1's truncation. Also add `maxLines:1` + ellipsis to the sort label per item 1.

**Path.** `shop_tab.dart` `_ShopTile` (`:1754-1938`): add a `priceBadge` prop, render in
the `Stack` at `:1809-1863`; pass from `_storePowerupTile` (`:1401`) and
`_storeCosmeticTile` (`:877`). Owned/inventory tiles pass none.

---

### Item 3 — Night-mode team race text unreadable + full dark-mode audit

**Finding (the reported bug).** `lib/widgets/team_h2h_banner.dart:121` renders the big
team total with `TeamRace.colorDark(team, context)`. That resolves in night mode to
`pillGoldShadow 0xFF241D38` (team A) / `roofMid 0xFF214637` (team B), painted on night
`parchment 0xFF1B2A34`:

| Element | fg | bg | contrast |
|---|---|---|---|
| Team A total | `0xFF241D38` | `0xFF1B2A34` | **1.09:1** |
| Team B total | `0xFF214637` | `0xFF1B2A34` | **1.40:1** |

AA requires 4.5:1 (3:1 large). The "STEPS" caption below correctly uses `textMid` and
is legible — which is exactly why only the numbers vanish. Same bug for per-player
totals at `lib/screens/race_detail_screen.dart:6463`.

**The fix already exists in-repo.** `lib/widgets/team_scoreline.dart:44-50` solved this
for the compact scoreline by branching on `colors.isDark` to `feedGold` /`successText`
— both already contrast-asserted in `test/theme_controller_test.dart:127,133`.
The banner and roster cells were simply never migrated.

**Why tests missed it.** `test/night_mode_contrast_fixes_test.dart:127-130` asserts the
*token resolution* is correct, never that the resolved value contrasts with the surface
it is painted on. `theme_controller_test.dart:119` checks contrast but omits
`pillGoldShadow`/`roofMid` **as foregrounds**.

**Decision.** Introduce one shared helper — `TeamRace.textColorOn(team, context)` in
`lib/utils/team_race.dart` — implementing the `team_scoreline.dart` rule, and route
every "team colour as text on parchment" site through it. Fix P1–P7 below. Log the rest.

**Fix list (priority order):**

| P | file:line | issue |
|---|---|---|
| P1 | `widgets/team_h2h_banner.dart:121` | reported bug, 1.09:1 |
| P2 | `screens/race_detail_screen.dart:6463` | per-player totals, same |
| P3 | `screens/race_results_summary_screen.dart:346,372` | `colorDark` as text on parchment |
| P4 | `screens/public_races_screen.dart:1118` | same |
| P5 | `widgets/race_ui.dart:32` + `widgets/tournament_game_card.dart:71-74` | `Pill.foreground` defaults to the light constant `AppColors.textDark`; BRACKET pill = **2.28:1** |
| P6 | `widgets/tier_badge.dart:41-47` | `RankedTier.color` is a context-free getter → daytime medals at night; unranked **3.18:1** |
| P7 | `screens/tabs/ranked_tab.dart:918,946,1796` | demotion clay `0xFFB4503C` = **2.91:1** (palette has night-safe `error`) |
| P8 | `screens/race_detail_screen.dart:6371-6375` | **inverse bug** — `'No one yet'` in `textLight` on `parchment` is invisible in *light* mode |

**Also verify (may be fine — on coloured surfaces):** `create_race_screen.dart:1190`,
`widgets/team_lobby_board.dart:507`, `widgets/team_side_picker.dart:55`.

**Logged, NOT fixed this batch:** `utils/tournament.dart:591-597` (a second static
light-only palette — quarantine before it spreads); Category-D `Colors.black/white`
alpha scrims in `shop_tab.dart:620,625,1102,1107` and
`tournament_detail_screen.dart:710-834`; the systemic `Color(0x66000000)` card shadow
and `Color(0x40000000)` header text-shadow (~24 files) that do nothing on night parchment.

**Regression guard (this is the point of the item — "I keep having to come in and do this"):**
extend `test/theme_controller_test.dart:119` to assert `contrast(fg, parchment) >= 4.5`
for **every token used as a foreground** (`pillGoldShadow`, `roofMid`,
`pillGreenShadow`, `textMid`, `textLight` in both modes), **plus** a widget test that
pumps `TeamH2HBanner` and the race-detail team roster under `AppThemeData.night()` and
asserts the rendered `Text.style.color` is not a `colorDark` token — matching the shape
at `night_mode_contrast_fixes_test.dart:156`.

---

### Item 4 — "My Trail Mine never activated" (DrAmogh, step-maxing race)

**Finding.** Trail Mine is a **position trap on the owner's own step count**, not a
timed effect. `usePowerup.js:3155-3182` stores `metadata.positionSteps = my current
total`. `triggerTrailMines()` (`raceStateResolution.js:482-570`) detonates only when a
rival's total crosses that exact band in a single resolution tick:

```
previousTotal < positionSteps   AND   newTotal >= positionSteps
```

plus: not the owner, not forfeited, not a same-team member.

Ranked causes for a no-show:

- **(A) — dominant.** `usePowerup.js:1832-1836` *hard-blocks planting while in last
  place*. So the planter is structurally ahead of someone, and in a step-maxing race
  the leader plants a mine at a position **nobody behind them ever reaches**. Working
  as coded, useless as designed.
- **(B)** `POST /steps/sync-v2` **never evaluates mines** —
  `reconcileUploaderRaces.js:28-35` writes only the uploader's own total. Detonation
  depends on the durable full-field worker running afterwards.
- **(C)** That worker is kill-switchable (`raceResolutionQueue.js:127`).
- **(D)** The home card explicitly never triggers mines (`getHomeRaceCard.js:501`), so
  a home-screen-only user never detonates one.
- **(G)** Only **one** victim per tick; a second crosser in the same tick is ignored.
- **(I)** A victim holding Compression Socks consumes the socks and the mine is spent
  for **zero** penalty — indistinguishable from "never activated" to the owner.

There is **no** hourly-bucket, `timeBased`, or target-race branch in the trail-mine
path. Race type is not the cause.

**PROD FORENSICS (read-only, 2026-07-26) — cause (A) confirmed, plumbing exonerated.**

Race **"step maxxing"**, DrAmogh's four mines:

| mine `positionSteps` | status | why |
|---|---|---|
| 117,985 | `active_effect` | never crossed |
| 122,118 | `active_effect` | never crossed |
| 123,822 | `active_effect` | never crossed |
| 101,830 | `expired_effect` | **crossed and detonated correctly** |

DrAmogh is the leader at **144,570**; 2nd place (ShefaliG) is at **112,774** — *below all
three live mines*. The 101,830 mine sits below three racers and fired. So the trigger
path, the durable worker, and the sync plumbing all work; the three live mines are
simply planted in a step range **nobody has walked through**.

**Scoping nuance — do not over-correct.** Fleet-wide there are **292 `expired_effect`
vs 17 `active_effect`** trail mines (all 17 in still-running races). Mines detonate
~94% of the time. This is **not** a broken mechanic — it is a specific failure mode for
a *runaway leader*, whose own position is far above the pack. Any fix must not
meaningfully buff the 94% case.

*(Enum note for implementers: prod enum labels are lowercase — `trail_mine`, and status
`active_effect`/`expired_effect`/`blocked`. Querying `'TRAIL_MINE'` silently returns
zero rows.)*

**DECISION (owner, locked): no mechanic change — comms only.** Given the 94% base rate,
this is a communication problem, not a balance problem. Ship:
1. **Item copy** that makes the trap explicit — it is planted at *your current step
   count* and fires when a rival's total crosses it. Update
   `powerupCopySeed.js:183-195`.
2. **A feed line when a mine expires untriggered** at race end, so the owner learns the
   outcome instead of silently wondering. Emit from the race-end path alongside the
   existing detonation feed event (`raceStateResolution.js:548-568`).

**Explicitly NOT doing** (rejected with the mechanic change; do not let an agent
smuggle these in): no `positionSteps` offset, no plant-behind, no refund-on-expiry, no
change to the "cannot plant while last" rule (`usePowerup.js:1832-1836`).

**Logged, not fixed** — the two plumbing gaps are real but were *exonerated* as the
cause here and are out of scope for this batch: `reconcileUploaderRaces.js:28-35`
(sync-v2 skips mines) and `getHomeRaceCard.js:501` (home never triggers them). Revisit
only if a mine is ever shown to have survived a genuine crossing.

---

### Item 5 — "Trail Mix should count store powerups"

**Finding — it already does.** `usePowerup.js:2967-2982` counts
`findUsedTypesByParticipant()`, which is
`racePowerup.js:87-95`: `where { participantId, status:"USED", type: {not:null} },
distinct:["type"]`. There is **no source/provenance filter**, and the `RacePowerup`
schema has **no provenance column at all** (`schema.prisma:1103-1133`) —
`redeemPowerupToRace.js:124-134` mints an identical row. Once a store item is used it
is indistinguishable from a box-dropped one. Blocked attacks still mark `USED`
(`:2110-2116`) and so still count.

Two things that could make it *look* like store items don't count:
1. Trail Mix counts **unique types**, not uses — `test/integration/powerups-trail-mix.test.js:161-170`
   pins "used the same type twice counts once". Buying a second Leg Cramp adds nothing.
2. The powerup must reach `status: "USED"`. A store item sitting **HELD** in the race
   (redeemed but never used) does not count.

**DECISION (owner, locked): NO CHANGE. Item 5 is closed and out of scope.**
Owner confirmed Trail Mix is working as expected. Do **not** change the mechanic, the
counting rule, or the copy. No test, no code, no catalog edit. This item exists in the
spec only to record that it was investigated and dismissed.

*(Pass 1 — verified and dismissed: an earlier draft flagged a possible `MYSTERY_BOX`
over-count. It cannot happen. `MYSTERY_BOX` is a **status**, not a rolled type — it is
the *unopened placeholder* status (`racePowerup.js:36,43,49`) and is deliberately
excluded from `BALANCE_POWERUP_TYPES` (`balanceConfig.defaults.js:19-21`). An unopened
box is `status:"MYSTERY_BOX"`, never `status:"USED"`, so the Trail Mix query cannot see
it. No fix needed — do not let an agent "harden" this.)*

---

### Item 6 — Can't switch back to capybara

**Finding — confirmed.** Capybara is **not a shop item**. There is no `capybara` row in
`data/cosmetics.json` (only `corgi_puppy` and `turtle` are CHARACTER-slot); it is the
compiled-in default (`lib/config/animals.dart:34 kDefaultAnimal`), and the backend
treats "no CHARACTER row" as capybara (`characterPowers.js:47-53 isCapybara`).

The shop Inventory CHARACTERS list is `owned.where(_isCharacter)`
(`shop_tab.dart:1593,1606-1613`). Capybara is never `owned`, so it has **no tile**. The
only route back is the **CLEAR** strip on the equipped character's own tile
(`:965-969` → `_equip('CHARACTER', null)`) — undiscoverable. (Note: equipped items are
*not* hidden from inventory, so this is a missing-tile bug, not a filter bug.)

**Decision.** Render a **synthetic, always-present "Capybara" tile** as the first entry
in Inventory → CHARACTERS. It is client-side only (no backend change, no fake catalog
row): tapping EQUIP calls `_equip('CHARACTER', null)`; it shows `EQUIPPED` +
`highlighted:true` when `equipped['CHARACTER']` is null. Art via
`animalSpriteFor(kDefaultAnimal)`.

**Path.** `shop_tab.dart` `_buildInventory` (`:1592-1623`) — prepend the synthetic tile
to the character group; reuse `_inventoryCosmeticTile`'s strip semantics.
No backend work. **Degrades safely** on any backend version (purely local).

---

### Item 7 — Weird rectangle under the shop icon

**Finding.** `_ShopTile.build` (`:1782-1937`) stacks three differently-filled bands with
only one separator:
1. Outer `DecoratedBox` — `parchment`, radius **14**, 2px border (`:1785-1802`)
2. `ClipRRect` radius **12** (`:1803`) → a 2px ring of outer parchment shows inside the border
3. Art area (`:1809-1863`) — `Positioned.fill(ColoredBox(parchmentDark @ 0.6))`, `Expanded`
4. Name band (`:1875-1883`) — height 38, **no colour** → falls through to lighter `parchment`
5. Action strip (`:1885-1931`) — `parchmentDark` or `pillGold`, with a 1.5px top border

The translucent `parchmentDark @0.6` art box directly above a lighter, unseparated name
band is the "weird rectangle": it reads as a stray fill, not an intentional frame.

**Decision.** Make the art area an intentional inset frame: match the clip radius to the
container (12 ↔ 14 mismatch), give the art box a defined inner radius + a hairline
bottom border so it separates from the name band deliberately, and use a solid
theme-token fill instead of a 0.6-alpha overlay. Keep the tile's silhouette, shadow, and
grid metrics **unchanged** — this is a fill/edge fix, not a redesign. Load the
**`mobile-design` skill**. Update `_ShopLoadingSkeleton._tile` (`:1665-1723`) to match
(its name band is 34 vs the real 38 — fix that drift too).

---

### Item 8 — Turtle/corgi users can't see themselves in the race track (TestFlight)

**Finding — root cause confirmed; it is a backend bug.** Not assets (all three sheets
exist and `pubspec.yaml:85` bundles the directory), not `X-Client-Features`
(`backend_api_service.dart:126-128` sends `characters` on every request), not the
Prisma select (`race.js:3-34` selects `testOnly`).

1. `corgi_puppy` and `turtle` are `testOnly:true` — `data/cosmetics.json:1284,:1304`.
2. `equippedAnimal()` / `characterPresentation()` —
   `src/modules/cosmetics/shopCosmetics.js:78-100` — drop any `testOnly` CHARACTER
   **unconditionally**, take **no channel argument**, and have **no self-exemption**.
3. That helper is the sole source of `animal` on every race surface
   (`getRaceDetails.js:99`, `getRaceProgress.js:227,878`, `getLeaderboard.js:80-88`,
   `getHomeRaceCard.js:54,635-639`).
4. But `getShopCatalog.js:44-53` **is** channel-aware. Hence the exact reported
   asymmetry: character visible on the home hero and in the shop, capybara in races.

The frontend is already correct — every participant renders their own `animal`
(`race_detail_screen.dart:3783-3785`, `:3172`, `:5581`, `:6405`;
`race_card_capybara_row.dart:106`), via `HomeCourseTrack` (the real track;
`race_track.dart` is dead code).

**⚠ A backend test currently asserts the buggy behaviour:**
`test/integration/characterVisibility.test.js:206` — *"test-only character never leaks,
even to capable viewers"* asserts `bobRow.animal === null`. Per the hard rule the agent
must **not** edit it — surface it to the owner. (§11 Q3.)

**DECISION (owner, locked): route (a) — channel-aware fix, keep `testOnly:true`.**
Thread `channel` into `characterPresentation`/`equippedAnimal` so TestFlight viewers see
test-only characters (including their **own** row); prod viewers are unchanged. No app
change is required — the client already sends `X-Release-Channel`. **Do NOT flip
`testOnly:false`** in this batch; that is a separate, later, gated step once an App
Store build carrying both PNGs has rolled out.

The two routes considered:
- **(a) Thread `channel` into `characterPresentation`** (it is already on
  `req.releaseChannel`, `releaseChannel.js:27`) so TestFlight sees test-only characters.
  Keeps prod users from seeing art their frozen binary lacks. Requires changing the test above.
  **Verified (Pass 1):** the Flutter client does send `X-Release-Channel` — set at
  `lib/services/backend_api_service.dart:2859` and `:2898`, the same two chokepoints
  that set `X-Client-Features` (every GET and every JSON request). So route (a) works
  today with no client change. This was an unverified assumption in the v1 draft.
- **(b) Flip `testOnly:false`** on both characters. Simpler, but per CLAUDE.md this is
  only safe **after** an App Store build carrying both PNGs has rolled out — otherwise
  frozen old clients get an unknown `assetKey` (which `animalSpriteFor` renders as a
  capybara, so it degrades safely, but they cannot see what others bought).

Recommendation: **(a) now**, (b) later as a separate release gate.

---

### Item 9 — Herd bonus abuse via mid-race character switching

**Finding — confirmed farming vector.**
- `computeHerdBonus` (`characterPowers.js:148-155`) is **fully retroactive**:
  `bonusSteps = herdPerDay(capyCount) × raceLocalDayCount(joinDay … now)`, recomputed
  from scratch on every read. `HERD_BONUS_PER_CAPY=100`, `HERD_MAX_CAPY=10`,
  `HERD_DAILY_CAP=1000`.
- `countCapybaras` (`:115-117`) reads `isCapybara(p.user)` **at read time**, and
  `isCapybara` (`:49-53`) returns **true when no character is equipped**.
- `equipAccessory.js:30-90` is a plain upsert with **no cooldown, no per-race guard, no
  per-day guard, no in-active-race lock**.

**The exploit:** run 6 days of a 7-day race as a corgi, then swap to capybara (or simply
unequip) before settlement. `raceExpiry.js:202` awards the herd bonus for **every day
since join**, including the corgi days. Worse, it **retroactively inflates `capyCount`
for every other capybara in the race**. And Zoomies are already banked as persisted
`CharacterEffectWindow` rows that scoring folds in with **no re-check that the user is
still a corgi** (`getRaceProgress.js:449-453`, `raceExpiry.js:196-201`) — so the swap
keeps the 3× windows *and* gains the full retroactive herd bonus.

(Shell is the only power evaluated strictly live, at attack time — self-limiting.)

**DECISION (owner, locked): option (a) — per-day character snapshot.**
Log the user's equipped character per local day. Herd bonus counts **only days they were
a capybara**; Zoomies windows score **only days they were a corgi**. This also fixes the
retroactive `capyCount` inflation that currently boosts *other* participants when
someone swaps. Applies to both the live path (`getRaceProgress.js:359,444-467`) and
settlement (`raceExpiry.js:136-140,194-206`) — if those two disagree, live display
diverges from payout, which is the failure mode this codebase has hit before.

Requires a small migration (per-day character log). Legitimate mid-race switching stays
allowed — it just stops paying for days you weren't that character.

Options considered:
- **(a) Per-day equip snapshot. ← CHOSEN.** Log the user's character per local day; award
  herd only for days they were a capybara, and fold Zoomies windows only for corgi days.
  Correct, and fixes the `capyCount` inflation.
- **(b) Snapshot at join.** Store `RaceParticipant.animalAtJoin`; herd + zoomies both
  keyed off it. Cheap; punishes legitimate mid-race switching.
- **(c) Lock the CHARACTER slot while in an active race.** Simplest, worst UX, and
  conflicts with item 11 (manual corgi activation) and item 6.

Whichever is chosen must apply to **both** the live path (`getRaceProgress.js:359,444-467`)
and settlement (`raceExpiry.js:136-140,194-206`), or live display diverges from payout.

---

### Item 10 — Cap the CAPY (herd) bonus at 500/day, down from 1000

> **Owner correction, 2026-07-26.** The v1 draft misread "capy bonus" as "copy bonus"
> and specced a cap on the **Hitchhike** copied-steps mechanic. That was the wrong
> subsystem. This item is the **capybara herd bonus**, and Hitchhike is **not** being
> capped in this batch. Any agent that finds a Hitchhike cap in an older draft must
> ignore it.

**Finding.** `src/modules/races/services/characterPowers.js:109-112`:

```js
const HERD_BONUS_PER_CAPY = 100;   // :110
const HERD_MAX_CAPY       = 10;    // :111
const HERD_DAILY_CAP      = 1000;  // :112   <-- the 1000
```

`herdPerDay(capyCount)` = `min(capyCount, HERD_MAX_CAPY) × HERD_BONUS_PER_CAPY`, then
clamped to `HERD_DAILY_CAP`. Note the cap is currently **exactly** the maximum the
formula can produce (10 × 100 = 1000), so today it never actually binds — it is a
no-op safety clamp.

**Decision.** Set **`HERD_DAILY_CAP = 500`**. The cap now binds at **5 capybaras**: a
race with 5+ capybaras pays 500/day instead of scaling to 1000/day. Per-capy value
(100) and `HERD_MAX_CAPY` (10) are **unchanged** — this halves the ceiling only.

```
capyCount:   1    2    3    4    5    6    7    8    9   10
today:     100  200  300  400  500  600  700  800  900 1000
after:     100  200  300  400  500  500  500  500  500  500
```

**Path.** One constant at `characterPowers.js:112`. It flows automatically to both the
live path (`getRaceProgress.js:359,444-467`) and settlement
(`raceExpiry.js:136-140,194-206`) because both call `computeHerdBonus` — so live display
and payout stay in parity with no second edit. **Do not** clamp at the call sites.

**⚠ Deploys hot.** `computeHerdBonus` is recomputed on every read and is **fully
retroactive over the whole race** (`:148-155`), so the moment this ships, users in
**in-flight races** with 6+ capybaras see their accumulated herd bonus **drop** — for
every day since they joined, not just going forward. In a 7-day race with 10 capybaras
that is a visible −3,500 step swing mid-race.
**DECISION (owner, locked): ship hot — applies everywhere immediately**, including
in-flight races. No per-race gating, no stored cap. Accept that users mid-race in a
6+-capybara race see their accumulated herd bonus drop retroactively. This keeps the
change to the single constant at `characterPowers.js:112`.

**Interacts with item 9.** Both change herd-bonus scoring. Land them together and test
them together, or the item-9 per-day snapshot tests will be written against the old
ceiling. Item 9's anti-farm fix also *reduces* which days count, so a user could see
both reductions at once — worth one combined feed/UX message rather than two silent drops.

---

### Item 11 — Manually activate the corgi power

**Finding.** Zoomies today are **100% passive and cron-driven**: two secret 10-minute
**3× windows** per user-local day, 08:00–22:00, ≥120min apart
(`characterPowers.js:156-165`), drawn deterministically by FNV-1a hash
(`drawZoomiesStartMinutes`, `:182-195`), materialized as `CharacterEffectWindow` rows by
a 5-min cron (`characterEffectScheduler.js:47-105`), unique on
`(userId, localDayKey, slot)` (`schema.prisma:1449-1461`).
**No route exposes ZOOMIES** — there is no activation endpoint to call.

The "powerup dropdown on the homepage" is `lib/widgets/character_power_chip.dart` — an
expandable chip (`:92`, `:135-146`) mounted at `home_tab.dart:224-238` behind
`characterPowersEnabled`. It is **purely informational**: no callback, no route, nothing
fetched (its own doc comment says so at `:55-66`).

**DECISION (owner, locked): manual activation REPLACES the 2 random windows.**
The corgi gets **2 player-triggered 10-minute 3× windows per local day** instead of 2
secret cron-drawn ones. **Net 3× minutes/day is unchanged at 20** — this is a pure
control upgrade, not a power buff. Constraints carried over unchanged:
`ZOOMIES_MULTIPLIER = 3`, `ZOOMIES_WINDOW_LEN_MIN = 10`, `ZOOMIES_SLOTS = 2`,
allowed window **08:00–22:00 local**, and `ZOOMIES_MIN_GAP_MIN = 120` between windows.

Consequences the agents must handle:
- `drawZoomiesStartMinutes` (`characterPowers.js:182-195`) is **no longer the source of
  windows** for corgi users; the scheduler cron
  (`characterEffectScheduler.js:47-105`) must stop auto-minting them. Do not delete the
  draw function or the cron — turtle/other slots and the existing rows still use that
  machinery, and old rows must keep scoring.
- **In-flight day handling:** a user who already had cron-drawn windows minted for today
  must not get 2 more manual charges on deploy day. Charges for the current local day
  must account for windows already minted.
- **Old clients never call the endpoint**, so a frozen client's corgi would get *zero*
  Zoomies once the cron stops minting. **This is a real regression for un-updated
  users** — gate the cron shutoff behind the same flag as the endpoint, and only stop
  auto-minting for users on a build that can activate manually
  (or keep auto-mint as the fallback until the App Store build has rolled out).
  ⚠ Flag this to the owner at implementation time; it is the one place item 11 can
  break the #1 rule.

**Path once pinned.**
- Backend: new `POST /character-powers/zoomies/activate` — insert a
  `CharacterEffectWindow` for now→now+10min via `createIfAbsent`
  (`characterEffectWindow.js:9-13`), reusing the `(userId, localDayKey, slot)` unique key
  for idempotency. Must respect `CHARACTER_POWERS_ENABLED` and reject non-corgi users.
  Ship behind a kill switch.
- Frontend: add `onActivate` + charge/cooldown state to `CharacterPowerChip`; extend
  `test/home_character_power_chip_test.dart`.
- Existing manual-activation UX precedent to mirror:
  `race_detail_screen.dart:4917-4995` (`ItemSlot` → `_showPowerupActions`).
- **Old-client compat:** the endpoint is additive; frozen clients simply never call it
  and keep the passive windows. Safe.

---

### Item 12 — Home placement ≠ race-detail placement
### Item 16 — Team scoreboard on the races tab ≠ actual score

**These are one defect.** Exploration found **five** rank implementations over **two**
scoring sources:

| Surface | Rank source | Totals |
|---|---|---|
| Home ticket (`home_tab.dart:435,1468`) | server `userPlacement` (`getHomeRaceCard.js:213-241,611,646`) | **live recompute** (or persisted under `homePersistedTotals=1`) |
| Races list (`races_tab.dart:1347-1351`) | server `myPlacement` (`getRaces.js:10-40,42-51`) | **persisted `totalSteps` only** |
| Race detail (`race_detail_screen.dart:3745,6857`) | **client-side sort, rank = array index** | live recompute |
| Push cron | 3rd sort (`placementRecompute.js:287-289`) | persisted |
| Client re-sort | 5th sort (`utils/race_participant_display.dart:7-42`) | — |

`GET /races/:id/progress` **returns no rank at all** — its server sort (`:891-898`) has
no finisher bucket and no tiebreak, pins stealthed racers to slot 0, then IMPOSTER
swaps array slots (`:900-917`). The client then re-sorts with *different* bucket rules.

**Concrete divergence causes (all confirmed):**
1. **Stale vs live.** `getRaces`/`placementRecompute` read persisted `totalSteps`, which
   only advances when someone opens that race or the 5-min cron fires. Home/detail recompute live.
2. **`homePersistedTotals=1`** (`backend_api_service.dart:1064-1071` → `getHomeRaceCard.js:440,508-515`)
   makes home read persisted while detail reads live — the direct home-vs-detail mismatch.
3. **UTC vs device tz.** `placementRecompute.js:262` resolves with **no `timeZone`** →
   defaults to UTC (`raceStateResolution.js:593`), while live paths use
   `raceTimeZone(race, req.timeZone)`. For a user-created race (`race.timezone` NULL) the
   two disagree for hours around local midnight. *(This is the same class of bug as the
   previously-fixed placement-push divergence.)*
4. **Stealth** shifts detail rank but not home rank.
5. **Detour Sign:** `getRaces.js:232-236` hides placement, `getRaceProgress.js:846-861`
   masks all totals to null — but **`checkActiveRaces` has no Detour handling at all**,
   so home keeps showing a real placement while the list shows "???".
6. **Finishers.** Home puts all finishers above runners; progress sorts purely by steps.
7. **Ties.** Home breaks by `joinedAt` then `userId`; detail by DB array order. **At 0
   steps everyone is tied**, so at the start of a day the two ranks are unrelated.

**For item 16 specifically:** the list's team totals are raw persisted
(`teamRaces.js:87-93` — `participant.totalSteps || 0`), while detail's are **live
effect-adjusted** (`getRaceProgress.js:538-546,934` — base-adjusted + hitchhike copies +
leech transfers + global-event multiplier). Every active buff, debuff, leech and copy is
missing from the list until a write happens. Also: `checkActiveRaces` **never emits
`teams`/`isTeamRace`** (compare `getHomeRaceCard.js:201-206` with `:649-656`), so on the
new home state a team race renders as an individual ticket with no scoreline.
And the frontend fallback `_teamTotalFromProgress` (`race_detail_screen.dart:1376-1392`)
coerces stealthed members' `null` totals to 0 (`team_race.dart:155`), silently
undercounting a team with a stealthed member.

**Decision.**
- **B-12a — one server-authoritative rank.** `GET /races/:id/progress` returns
  `myPlacement` (and a `placement` on each participant row) computed with the **shared**
  `compareParticipantsForPlacement`. Extract that comparator into one module and have
  `getHomeRaceCard.js:213`, `getRaces.js:10`, `getRaceProgress`, and
  `placementRecompute.js:287` **all import it** — deleting the duplicates.
- **B-12b — fix the tz default.** `placementRecompute.js:262` must pass the race's
  resolved timezone, not fall through to UTC.
- **B-12c — item 16. DECISION (owner, locked): accept bounded staleness.** `getRaces`
  keeps serving the cheap **persisted** team totals and gains `teams.asOf` (ISO-8601,
  nullable) marking when they were last written; the client renders a staleness
  affordance ("as of N min ago"). **Do NOT recompute live totals on the list** —
  that re-introduces exactly the N+1 cost the earlier perf work removed, on the
  most-frequently-polled screen, against a single shared vCPU. The numbers are allowed
  to differ from race detail; they are no longer allowed to differ *silently*.
- **B-12d** — `checkActiveRaces` must emit `teams`/`isTeamRace` and honour Detour Sign.
- **F-12e** — race detail renders the **server** `placement`, not the array index; the
  client-side comparator becomes a fallback only when the field is absent.
- **F-16f (added Pass 1)** — fix the stealth undercount in the client fallback.
  `_teamTotalFromProgress` (`race_detail_screen.dart:1376-1392`) falls back to
  `TeamRace.teamTotal` over the *displayed* planks, and a stealthed member's
  `totalSteps: null` (`getRaceProgress.js:879`) is coerced to 0 (`team_race.dart:155`),
  silently undercounting that team. The fallback must prefer the server `teams` block
  and, when genuinely absent, must not treat a null (hidden) total as zero.

**⚠ Push-notification side effect (added Pass 2).** `placementRecompute.js` is not just
a display path — it emits the *"you're now Nth"* pushes (`:287-316`). Changing its
comparator and its timezone default **changes which users cross a placement boundary**,
so the first cron tick after deploy can fire a burst of placement pushes for positions
that did not really change. This has bitten this codebase before. Mitigation: deploy the
comparator change with the push emit suppressed for one tick, or gate the emit on a
before/after comparison computed under the *new* comparator on both sides.

**Old-client compat (critical).** `placement`/`myPlacement`/`teams` on `/progress` are
**additive**. Frozen clients ignore unknown fields and keep their array-index behaviour —
no crash, no regression. The new client must **default safely when the field is absent**
(older backend) by falling back to the existing client sort. This is the whole reason
F-12e keeps the comparator rather than deleting it.

---

### Item 13 — Dark mode leaderboard text hard to read

**Finding.** Covered by the item-3 audit. Leaderboard-specific offenders:
`widgets/leaderboard_plank.dart:398` (`AppColors.woodShadow` — bare light constant in
`_MedalPainter`), `:171` (`0xFFE8622A` ember chip literal),
`widgets/race_ui.dart:174-177` (`medalColor(int)` is static → daytime medals at night,
inconsistent with `PlacementPill` two lines above which *does* use `AppColors.of`),
`widgets/race_card_capybara_row.dart:59-65`, and the P6 tier badge.
`screens/tabs/leaderboard_tab.dart:1130-1144` is **already mitigated** by
`_medalStyleFor` (`:1148-1150`) — leave it, but the const map is a trap.

**Decision.** Fold into item 3's fix list; make `medalColor` context-aware, and route
`leaderboard_plank`'s painter colours through the palette.

**⚠ Implementation gotcha (added Pass 2).** Two of these offenders live inside a
`CustomPainter` (`leaderboard_plank.dart:398 _MedalPainter`) or a context-free static
getter (`race_ui.dart:174-177 medalColor(int)`, `tier_badge.dart:41-47
RankedTier.color`). **A painter has no `BuildContext`**, so `AppColors.of(context)`
cannot simply be dropped in. The fix must **resolve colours in the widget's `build` and
pass them into the painter/getter as parameters** — changing the painter's constructor
signature and its `shouldRepaint` to compare the new colour fields (or the painter will
not repaint on a theme flip, which reproduces the bug at the exact moment automatic
night mode switches at 19:00). Same applies to `medalColor` and `RankedTier.color`:
they need a `BuildContext`/palette argument, and every call site updated.

---

### Item 14 — Mirrored Leg Cramp stacks instead of resetting duration

**Finding — confirmed bug.**
- The anti-stack pre-check (`usePowerup.js:1580-1588`, *"Target already has an active
  Leg Cramp"*) runs on the **original** target only.
- The Mirror reflect block (`:1915-1976`) swaps roles (`:1954-1958`) so the effect lands
  on the original attacker — and re-checks stacking **only for `WRONG_TURN`**
  (`:1928-1937`), with a comment describing exactly this class of bug. **`LEG_CRAMP` has
  no post-swap re-check.** Same omission in the Decoy-redirect Mirror branch (`:2050-2062`).
- Application (`:2332-2355`) is an unconditional `effectModel.create(...)` — no upsert,
  no extend, no reset → a **second ACTIVE row**.
- Scoring sums both rows (`effectiveStepScoring.js:16,229,443`;
  `raceStateResolution.js:223`), so overlapping windows double-freeze.

There are currently **three** different behaviours for the same situation: pre-check
rejects (`:1580`), potion path rejects (`:586-589,668-676`), reflect path silently stacks.

**Decision.** As the owner specified: **replace, don't stack** — reset to the **full**
Leg Cramp duration from the moment of application. Ladder: `powerupUpgrades.js:36`
`[1h, 2h, 3h, 4h]`. Implement at `case "LEG_CRAMP"` (`:2332`) as a
**replace-to-full-duration** upsert (mirroring the `upsertBuffWindow` shape at
`:1099-1110`, but replace semantics, **not** union-extend). Must also cover the
`LEG_CRAMP_SELF` potion outcome (`:534-537`, currently no check at all) and the Decoy
Mirror branch. Note QUICKSAND already treats LEG_CRAMP/QUICKSAND as one mutually
exclusive freeze family (`:1022`) — keep that invariant.

---

### Item 15 — Coin Flip active badge has a white background

**Finding — it is the widget, not the PNG.**
`assets/images/powerups/coin_flip.png` is RGBA 128×128 with proper alpha (corner pixels
`(0,0,0,0)`; only 26.5% opaque — in line with every other powerup sprite).
The white comes from `race_detail_screen.dart:7332-7347`
(`_EffectIconWithTooltipState.build`): an inner `Container` filled
`AppColors.of(context).textLight` = `0xFFFFFBF5` light / `0xFFF7F1E7` night
(`styles.dart:83,363`) — near-white in **both** themes.

This is the **only** site in the app that puts a white fill behind a `PowerupIcon`
(verified across every `PowerupIcon` call site). It is **type-agnostic**, so *every*
active effect gets the white plate — Coin Flip just exposes it worst because its art is
a small round coin with a large transparent margin. It feeds both the solo leaderboard
plank (`:6774-6779` → `:6889` → `leaderboard_plank.dart:291-293`) and the team roster
rail (`:6830-6833`).

**Decision.** Replace the white plate with the treatment already used on the races tab:
*(Pass 2: the replacement tint must itself satisfy item 3's contrast rule in **both**
themes — this is a dark-mode surface too, so verify the icon reads against the new fill
in night mode rather than only checking that the white is gone.)*
a **polarity-tinted low-alpha fill** (`races_tab.dart:1637-1652` uses
`feedBoost`/`feedAttack` at 15% via `lib/utils/effect_polarity.dart`), keeping the wood
frame. This fixes every effect badge, not just Coin Flip, and makes the two surfaces
consistent. Single-line-ish change at `race_detail_screen.dart:7342`.

---

### Item 17 — Is the 30% Shell block actually working? If so, nerf to 15%

**Finding — the 30% is correctly implemented.**
`SHELL_BLOCK_CHANCE = 0.3` is a single constant (`characterPowers.js:72`, exported
`:226`, no duplicate anywhere). `shellBlocksAttack` (`:96-107`) does exactly **one**
roll, `random() < 0.3`, strict — pinned by `test/services/turtleShell.test.js:62-68`
and a statistical loop at `:103`. **No code path rolls twice for one single-target
attack**: the Mirror-reflect branch is gated on `!reflected` (`:2102`) and Decoy is a
separate earlier branch (`:1988`); the potion path rolls once on the *rolled* type.

Rohitrohit being blocked in 3 separate races is **P = 0.3³ = 2.7%** — unlucky, not a bug.
But three real amplifiers explain why it *feels* higher:

1. **Per-TYPE, not per-instance.** `isRaceRolledType` (`:78-92`) checks the live
   `dropPool`, so a **coin-shop-bought** Leg Cramp / Shortcut / Red Card is *also*
   Shell-blockable. Players who assume "store powerups shouldn't bounce" read this as
   over-firing. Documented as deliberate at `:66-71`.
   Actually blockable today = dropPool ∩ offensive =
   **LEG_CRAMP, WRONG_TURN, DETOUR_SIGN, PINECONE_TOSS, RED_CARD, SHORTCUT, SNEAKY_SWAP.**
2. **AoE fan-outs roll per victim** — `usePowerup.js:1033` (QUICKSAND), `:1272`
   (POWER_OUTAGE), `:2730-2750` (RAINSTORM). From the caster's view
   P(at least one block) = 1 − 0.7ⁿ → **83% at n=5**. Latent *only* because those types
   sit in `storeOnlyTypes` — **which is admin-editable at runtime**, and
   `isRaceRolledType` reads the live DB config. One admin edit makes this real.
3. **"Blocked" ≠ "Shell-blocked" in the feed.** Compression Socks (`:2196-2215`), Decoy
   fizzles (`:2005-2035`) and Umbrella immunity all emit `POWERUP_BLOCKED`; only the
   Shell path writes *"…'s Shell bounced off…"*. Anything counting `POWERUP_BLOCKED`
   observes a far higher rate than 30%.

**Decision.** The owner's condition is satisfied (*"if it is working as expected, nerf
it to 15%"*) → **set `SHELL_BLOCK_CHANCE = 0.15`.** Additionally:
- **Explicitly exclude AoE/global effects** from Shell (guard at the three fan-out
  sites) so amplifier 2 can never be enabled by an admin config edit.
- Update `test/services/shellBlockableStructuralGuard.test.js` (which only guards
  `DEFAULT_CONFIG`, not the DB config) to cover the AoE exclusion.
- Front-end/feed: make the Shell-block feed line distinguishable from other blocks.
**DECISION (owner, locked): set `SHELL_BLOCK_CHANCE = 0.15`** (`characterPowers.js:72`).
No turtle price change — out of scope for this batch.

**Old-client note:** the constant is server-side only; no client change required, and
`TURTLE_SHELL_DISABLED` remains the kill switch.

---

### Item 18 — "Clean pace so far" at midnight with 0 steps

**Finding.** `lib/screens/tabs/home_tab.dart:920-928`:

```dart
String _heroSummary({required int steps}) {
  if (steps >= 20000) return 'Huge day. ...';
  if (steps >= 5000)  return 'Nice pace. ...';
  return 'Clean pace so far. Keep walking to hit your first milestone.';
}
```

Two thresholds, no floor: the terminal `return` is a *positive* message, so the bucket
is `[0, 5000)` and 0 steps is indistinguishable from 4,999. No zero case, no
"not started" case, no time-of-day input. Called at `:840` with `stepData?.steps ?? 0`,
guarded at `:836` — so it also renders when `stepData == null && !isLoading`.

**Decision.** Add a zero/near-zero case with neutral start-of-day copy (e.g.
*"Fresh day. Get moving to hit your first milestone."*), and treat `stepData == null` as
the same not-started state rather than coercing to 0. **No tests exist for this string**
(`grep "Clean pace" test/` → nothing) — add one.

---

## 4. Data model / migrations

- **Items 1, 2, 3, 6, 7, 13, 15, 18:** none (frontend only).
- **Item 9:** depends on §11 Q4. Option (a) needs a per-day character log (new table or
  a `CharacterEffectWindow`-style row); option (b) needs `RaceParticipant.animalAtJoin`
  (nullable, backfilled NULL = "unknown → treat as capybara", default-safe);
  option (c) needs no migration.
- **Item 11:** no new table — reuses `CharacterEffectWindow`
  (`schema.prisma:1449-1461`). May need a `source` column if manual and cron windows
  must be told apart (depends on Q6's "replace vs add").
- **Items 4, 5, 10, 12, 14, 16, 17:** no migration; behaviour/serializer changes only.

**⚠ Items 9 and 11 interact (added Pass 2).** Manual Zoomies (11) mints a
`CharacterEffectWindow`; the herd anti-farm (9) decides which windows still count after
a character swap. If Q4 chooses a per-day snapshot, a user could manually activate
Zoomies as a corgi and immediately swap to capybara to collect both the 3× window and
the herd bonus for that day. **Rule: the character must be validated both at activation
time and again at scoring time** — a banked window from a day the user did not finish as
a corgi must not score. Whoever implements 9 and 11 must agree on this before coding;
if Q4 chooses option (c) (lock the slot during an active race), it directly conflicts
with items 6 and 11, and Q6 must be re-answered.

Every new column must be **nullable with a safe default** so old rows and old clients
read correctly.

---

## 5. API contract (pinned BEFORE implementation)

The backend agent lands this first; the frontend agent codes against it verbatim.

**Additive-only.** Every field below is new and optional. A frozen old client that has
never heard of these fields ignores them and keeps its current behaviour. A **new**
client hitting an **older** backend must find every one of these absent and fall back —
each fallback is named explicitly.

### C1 — `GET /races/:raceId/progress` (items 12, 16)
```jsonc
{
  "myPlacement": 3,            // NEW, nullable. null when hidden (Detour Sign) or unknown
  "myPlacementHidden": false,  // NEW, mirrors the existing GET /races semantics
  "participants": [
    { "userId": "...", "placement": 1, /* NEW, nullable */ "totalSteps": 12345, "animal": "turtle" }
  ],
  "teams": { "teamA": { "totalSteps": 364261 }, "teamB": { "totalSteps": 352747 } }
}
```
- `placement`/`myPlacement` computed with the **shared** `compareParticipantsForPlacement`.
- **Client fallback when absent:** existing `sortRaceParticipantsForDisplay` + array index.

### C2 — `GET /races` (item 16)
`teams` gains `asOf` (ISO-8601, nullable) marking when the persisted totals were last
written, so the client can render staleness. Existing `teamATotalSteps`/`teamBTotalSteps`
and `myPlacement` are **unchanged in shape**. Totals stay **persisted** (locked
decision — no live recompute on this endpoint). `asOf` absent ⇒ client hides the
staleness affordance and renders exactly as today.

### C3 — `GET /home/race-card` (item 16)
`buildRaceEntry` (`getHomeRaceCard.js:649-656`) gains `isTeamRace` and `teams`, matching
the legacy path at `:201-206`. **Client fallback when absent:** render the individual
ticket exactly as today.

### C4 — race/leaderboard surfaces (item 8)
No shape change. `animal` simply stops being nulled for TestFlight viewers once
`characterPresentation` is channel-aware. Values remain `"corgi_puppy" | "turtle" | null`;
`animalFromJson` already maps unknown → capybara, so this is safe in both directions.

### C5 — `POST /character-powers/zoomies/activate` (item 11)

Manual activation **replaces** the 2 cron-drawn windows (locked, §11 Q6): 2 charges per
local day, 10 min each, 3×, 08:00–22:00 only, ≥120 min apart.
```jsonc
// 200
{ "activated": true, "endsAt": "2026-07-26T18:10:00Z", "chargesRemaining": 0 }
// 400 not a corgi / outside allowed window / no charges left
// 409 already active
```
Additive endpoint; old clients never call it.

### C6 — no contract change
Items 1, 2, 3, 6, 7, 13, 15, 18 (frontend-only); items 5, 10, 14, 17 (server-internal
math only — no shape change).

### Backward-compat rules binding on the backend agent
- Never remove or retype an existing field.
- Never make an existing optional field required.
- Every new response field must be safe to omit.
- `GET /races` must keep serving clients that have never sent `X-Client-Features`.

---

## 6. Frontend plan

**Both platforms, in lockstep.** No item is iOS- or Android-specific; all changes are
pure Dart. Build and verify **both** before calling this done.

| Item | Files | States to cover |
|---|---|---|
| 1, 2, 7 | `screens/tabs/shop_tab.dart` | loading skeleton (`:1665`), empty category, unaffordable, owned, equipped |
| 3, 13 | `utils/team_race.dart`, `widgets/team_h2h_banner.dart`, `screens/race_detail_screen.dart`, `race_results_summary_screen.dart`, `public_races_screen.dart`, `widgets/race_ui.dart`, `tournament_game_card.dart`, `tier_badge.dart`, `screens/tabs/ranked_tab.dart`, `widgets/leaderboard_plank.dart` | **both** light and night for every touched widget |
| 6 | `screens/tabs/shop_tab.dart` | equipped / not-equipped capybara |
| 8 | none (backend fix) | verify turtle+corgi render in race track |
| 11 | `widgets/character_power_chip.dart`, `screens/tabs/home_tab.dart` | idle / active / cooldown / no-charges / flag-off |
| 12, 16 | `screens/race_detail_screen.dart`, `screens/tabs/races_tab.dart`, `screens/tabs/home_tab.dart`, `utils/race_participant_display.dart` | **field present** and **field absent** (older backend) |
| 15 | `screens/race_detail_screen.dart:7342` | boost vs debuff polarity tint |
| 18 | `screens/tabs/home_tab.dart:920` | 0 steps, null stepData, <5k, <20k, ≥20k |

**Degradation rule (the #1 hard rule).** Every new field in §5 is read defensively:
`myPlacement`/`placement` absent → client sort; `teams` absent on home → individual
ticket; `animal` absent/unknown → capybara. **No new required field, no crash on null.**

**Design skills are mandatory** before items 1, 2, 7, and 11 (new/reshaped UI):
load `mobile-design` (and `frontend-design` for visual direction) first.

---

## 7. Backward-compat & rollout

**Deploy order: backend first, then the app.** Non-negotiable — items 8, 12, 16 depend
on new backend fields, and the app must never ship expecting a field prod doesn't serve.

1. **Backend deploy.** Ships C1–C5. All additive. Frozen 2.0.1 and older clients are
   unaffected: they ignore `placement`, `myPlacement`, `teams.asOf`, `isTeamRace`, and
   never call the zoomies endpoint.
2. **Behavioural changes that hit ALL client versions at once** (no version gate is
   possible for these — flag them explicitly to the owner):
   - **Item 10** (herd `HERD_DAILY_CAP` 1000 → 500) — computed on read and fully
     retroactive, so it **lowers accumulated herd bonuses in in-flight races** the
     moment it deploys, for every day since each user joined. Pending §11 Q5.
   - **Item 17** (Shell 30% → 15%) — server-side constant, immediate for everyone.
   - **Item 14** (leg-cramp replace) — immediate.
   - **Item 9** (herd anti-farm) — immediate, and **may reduce herd bonuses users have
     already seen displayed** in a running race. Consider gating to races that start
     after deploy. ⚠ §11 Q4.
   - **Item 8** — TestFlight users start seeing test-only characters on race surfaces.
3. **Kill switches.** Item 11 ships behind a new env flag defaulting **off**. Items 9
   and 17 should each be flag-guarded so they can be reverted without a redeploy.
   Existing switches remain: `CHARACTER_POWERS_ENABLED`, `TURTLE_SHELL_DISABLED`.
4. **App Store rollout is phased over ~a week**, and some users never update. Items 1,
   2, 3, 6, 7, 11, 13, 15, 18 only reach a user on update. The backend must stay correct
   for both cohorts throughout.
5. **`testOnly` discipline.** Do **not** flip `corgi_puppy`/`turtle` to
   `testOnly:false` in this batch unless §11 Q3 chooses route (b) *and* the owner
   confirms an App Store build carrying both PNGs has rolled out.
6. **Never point `cosmetics:apply` or any integration test at the prod DB.**

---

## 8. Test plan (tests FIRST, before business logic)

Per CLAUDE.md: **integration tests by default**; unit tests only where an integration
test structurally cannot express the property. **No existing test may be modified or
deleted** — conflicts get surfaced to the owner (see §11 Q7, and the two known
conflicts: `characterVisibility.test.js:206` and `shop_powerup_filter_sort_test.dart`).

### Backend — `test/integration/` (real HTTP, real test DB)
- **Item 8:** capable TestFlight viewer sees their **own** `animal` on `GET /races/:id`,
  `/progress`, `/leaderboard`, `/home/race-card`; prod-channel viewer still does not.
- **Items 12/16:** *the parity test that does not exist today* — for one seeded race,
  assert `GET /home/race-card`.userPlacement == `GET /races`.myPlacement ==
  `GET /races/:id/progress`.myPlacement, across: ties at 0 steps, a finisher, a
  stealthed racer, and Detour Sign active. Plus: team totals equal across list and
  progress for a race with an active buff/leech/hitchhike.
- **Item 12 tz:** a race with `timezone` NULL near local midnight gives the same
  placement from the cron path as from the live path.
- **Item 10:** a race with 6+ capybaras pays exactly 500/day (not 600+), and the same
  number appears in `/progress`, the home card, and settlement. Assert 5 capybaras =
  500 (boundary) and 4 = 400 (unaffected).
- **Item 14:** A cramps B → B mirrors → A already cramped ⇒ **exactly one** ACTIVE row,
  `expiresAt` == now + full duration. Repeat for the Decoy-redirect branch and
  `LEG_CRAMP_SELF`.
- **Item 17:** stubbed RNG — 0.14 blocks, 0.16 does not; AoE fan-out on 5 victims
  produces **zero** Shell blocks; structural guard covers the AoE exclusion.
- **Item 9:** equip corgi for N days then swap to capybara before settlement ⇒ herd
  bonus counts **only** capybara days, and other participants' `capyCount` is not
  retroactively inflated; live and settlement agree.
- **Item 11:** activate → window exists → scoring applies 3× for 10 min; second call is
  idempotent/rejected; non-corgi rejected; flag off ⇒ 404/400.
- **Item 5:** confirm a redeemed (store) powerup that reaches `USED` counts toward Trail
  Mix, and that `MYSTERY_BOX` never does.
- **Item 4:** per §11 Q1.

### Frontend — `test/` (pump the real widget, assert what renders)
- **Item 1:** dropdown opens; selecting Offense filters; selecting Price sorts; combined
  label fits at 320dp and 360dp without overflow.
- **Item 2:** unaffordable tile renders **both** the price and the CTA.
- **Items 3/13:** pump `TeamH2HBanner` + race-detail team roster + leaderboard plank
  under `AppThemeData.night()`; assert rendered text colour is not a `colorDark` token
  and meets 4.5:1. Extend the `theme_controller_test.dart:119` matrix to every
  foreground token. Add the light-mode assertion for P8.
- **Item 6:** Inventory → CHARACTERS always contains a Capybara tile; it shows EQUIPPED
  when no character is equipped; tapping EQUIP calls `_equip('CHARACTER', null)`.
- **Item 7:** golden/structural assertion that the art area and name band share one
  continuous frame.
- **Items 12/16:** race detail renders the **server** `placement` when present, and
  falls back to the client sort when the field is **absent** (old-backend case).
- **Item 15:** the effect badge's fill is not `textLight`; polarity tint applied.
- **Item 18:** 0 steps and null `stepData` both render the not-started copy; 4,999
  does not.

**Backend commands:** `npm run test:unit` / `npm run test:integration` — **never bare
`npm test`**. Do not re-run the full ~10-min integration suite to diagnose a single
failure; run the one suite.

---

## 9. Acceptance criteria / definition of done

- [ ] All 18 items implemented, or explicitly deferred with the owner's sign-off.
- [ ] API contract §5 implemented exactly; no existing field removed or retyped.
- [ ] Every new frontend read of a new field has a tested absent-field fallback.
- [ ] New tests written **before** the logic, and observed failing for the right reason.
- [ ] **Zero existing tests modified or deleted.** Conflicts surfaced, not "fixed".
- [ ] Dark-mode: P1–P8 fixed; contrast regression guard in place and passing.
- [ ] `flutter test` — no **new** failures vs the pre-batch baseline (a stale-copy
      baseline already exists; record it before starting).
- [ ] `npm run test:unit` and `npm run test:integration` — no new failures vs baseline
      (13 fanny-pack integration failures are known pre-existing).
- [ ] **iOS `flutter build ipa` AND Android `flutter build appbundle --flavor prod`
      both succeed**, same version/build number, same `--dart-define`s.
- [ ] Backend deployed to staging and verified before prod; prod deploy is
      backend-first, app second.
- [ ] Kill switches confirmed working for items 9, 11, 17.
- [ ] No test ever pointed at the prod DB.

---

## 10. Revision log

### Pass 1 — fresh-eyes gap pass
1. **Killed a phantom bug in item 5.** v1 asserted Trail Mix might over-count
   `MYSTERY_BOX` as a unique type. Verified against source: `MYSTERY_BOX` is a *status*
   placeholder (`racePowerup.js:36,43,49`), deliberately excluded from
   `BALANCE_POWERUP_TYPES` (`balanceConfig.defaults.js:19-21`), and never reaches
   `status:"USED"`. Rewrote as an explicit "do not harden this" note so an agent
   doesn't invent a fix for a non-bug.
2. **Removed an unverified assumption in item 8.** v1 recommended the channel-aware fix
   without confirming the client sends `X-Release-Channel`. Verified it does
   (`backend_api_service.dart:2859,:2898`). Route (a) needs no client change.
3. **Added F-16f.** v1 described the stealth-null team undercount in the *finding* but
   never turned it into a decision, so it would have been silently dropped.
4. **Added the deploy-order/version and rollback gaps** to §7 and §9 (below).

### Pass 2 — second independent pass
5. **Added the `CustomPainter` gotcha to items 3/13.** Three of the fix targets have no
   `BuildContext` (`_MedalPainter`, `medalColor(int)`, `RankedTier.color`). Without
   calling this out, an agent would try `AppColors.of(context)` inside a painter, and
   would miss `shouldRepaint` — reproducing the bug at the 19:00 auto-night flip.
6. **Added the placement-push side effect to items 12/16.** Changing
   `placementRecompute`'s comparator/tz changes who crosses a rank boundary, risking a
   burst of false "you slipped to Nth" pushes on the first tick after deploy.
7. **Added the item 9 ↔ item 11 interaction** to §4: manual Zoomies + herd anti-farm can
   be combined into a same-day double-collect unless the character is validated at
   activation **and** at scoring; option (c) for Q4 conflicts outright with items 6/11.
8. **Added item 15's dark-mode constraint** — its replacement tint is itself subject to
   item 3's contrast rule.
9. **Added §12** (agent split and contract-first sequencing), which CLAUDE.md Phase 5
   requires and v1 omitted entirely.

### Pass 3 — owner corrections & prod forensics (post-interview)
10. **Item 10 was specced against the wrong subsystem.** "Capy bonus" was read as "copy
    bonus"; v1 specced a cap on Hitchhike copied-steps. Owner corrected: it is the
    **capybara herd bonus**, `HERD_DAILY_CAP` 1000 → 500
    (`characterPowers.js:112`). Hitchhike is **not** capped in this batch. Rewrote the
    item, and surfaced that the change is retroactive over in-flight races and
    overlaps item 9 — both touch herd scoring and must land together.
    *Lesson for the agents: the spec is the contract; if an older draft of this doc is
    ever consulted, the Hitchhike cap is not part of it.*
11. **Item 4 resolved by read-only prod forensics** rather than by guessing between the
    design and plumbing hypotheses. Confirmed cause (A): DrAmogh is a runaway leader and
    his three live mines sit above the entire field, while his lower mine detonated
    correctly. Also established the fleet-wide base rate (292 detonated vs 17 live,
    ~94%), which reframes the fix as *targeted*, not corrective — and rules out the
    "mines are broken" framing v1 leaned toward.

### All questions resolved (Phase 3 interview, 2026-07-26)
All nine open questions were answered by the owner. See §11 for the locked decisions.
No blocking unknowns remain; the spec is ready for the Phase 4 approval gate.

---

## 11. Interview outcomes — LOCKED DECISIONS (Phase 3, 2026-07-26)

These are owner decisions. They are binding on both implementation agents. Where a
decision **narrows** scope, the narrowing is as binding as the work itself — an agent
that "improves" a closed item is out of spec.

| # | Item | Decision |
|---|---|---|
| Q1 | **4 — Trail Mine** | **No mechanic change.** Comms only: clearer item copy + a feed line when a mine expires untriggered. Resolved by prod forensics (leader's mines planted above the field; 94% fleet-wide detonation rate). No offset, no plant-behind, no refund. |
| Q2 | **5 — Trail Mix** | **NO CHANGE. Item closed.** Owner confirmed it works as expected. No mechanic, no counting-rule, and **no copy** change. Investigated and dismissed. |
| Q3 | **8 — Characters in races** | **Channel-aware fix; keep `testOnly:true`.** TestFlight viewers see test-only characters incl. their own row; prod unchanged. No app change needed. Do **not** flip `testOnly:false` this batch. |
| Q4 | **9 — Herd anti-farm** | **Per-day character snapshot.** Herd counts only capybara days; Zoomies score only corgi days. Fixes retroactive `capyCount` inflation. Small migration. Legit mid-race switching still allowed. |
| Q5 | **10 — Herd cap** | **`HERD_DAILY_CAP` 1000 → 500, shipped hot to all races including in-flight.** Accepts a retroactive mid-race drop for 6+-capybara races. Single constant, no per-race gating. |
| Q6 | **11 — Manual Zoomies** | **Replaces the 2 random windows** with 2 player-triggered ones. Net 3× minutes/day unchanged (20). Same 08:00–22:00 window, same 120-min gap, same 10-min length. |
| Q7 | **Existing-test conflicts** | Agents **surface, never edit.** Two known: `characterVisibility.test.js:206` (asserts the item-8 bug) and `shop_powerup_filter_sort_test.dart` (drives the item-1 pills). Owner adjudicates. |
| Q8 | **16 — List team totals** | **Accept bounded staleness.** List keeps persisted totals + new `teams.asOf`; client shows "as of N min ago". **No live recompute on the list** — protects the perf win on the hottest screen. |
| Q9 | **17 — Shell block** | **Nerf to 15%.** The owner's condition ("if it is working as expected") was verified satisfied: 30% is implemented correctly, one roll per attack, no double-roll path. Rohitrohit's 3-race streak was P=2.7% bad luck. |

### Scope explicitly CLOSED — do not implement
- Item 5: anything at all.
- Item 4: any change to mine positioning, refunds, or the last-place planting rule.
- Item 10: any cap on **Hitchhike** copied steps (this was a misreading in an early draft).
- Item 8: flipping `testOnly:false` on `corgi_puppy` / `turtle`.
- Item 16: recomputing live team totals on `GET /races`.

## 12. Agent split & sequencing (Phase 5)

Two agents, model `claude-opus-4-8`, medium reasoning effort, following this spec's
steps **in order**. Contract first, then parallel.

**Step 0 (before any code, both agents):** record the current test baseline —
`flutter test` and `npm run test:unit` / `npm run test:integration` — and write the
failure counts into the PR description. Known pre-existing: ~35 stale-copy Flutter
failures and 13 fanny-pack integration failures. Anything beyond baseline is this
batch's fault.

**Backend developer — owns the API contract.** Pins and lands §5 (C1–C5) **first**;
neither agent codes against a moving contract. Then: items 4, 5, 8, 9, 10, 11 (server),
12, 14, 16 (server), 17. Owns backward-compat for frozen clients and the kill switches.

**Frontend developer — consumes §5 exactly as written**, inventing no field the contract
does not define. Items 1, 2, 3, 6, 7, 11 (client), 12 (client), 13, 15, 16 (client), 18.
Owns iOS + Android lockstep. **Must load `mobile-design` (and `frontend-design`) before
any UI work** — items 1, 2, 7, 11 are new/reshaped UI.

**Binding on both, without exception:**
- **Write tests FIRST**, observe them fail for the right reason, then write the logic.
- **Never modify or delete an existing test.** Two are already known to conflict
  (`characterVisibility.test.js:206`, `shop_powerup_filter_sort_test.dart`) — surface
  them to the owner; do not "fix" them to go green.
- Backend uses `test:unit` / `test:integration`, never bare `npm test`, and **never
  points at the prod DB**.
- Tag a rollback point before the prod deploy, and deploy **backend first**.

---

## 13. As-built record (Phase 5 complete, 2026-07-26)

Both agents finished. **Nothing committed, pushed, or deployed.** Numbers below were
verified independently of the agents' self-reports.

### Test state (verified)

| Suite | Baseline | Final | Delta |
|---|---|---|---|
| `flutter test` | 33 fail | **38 fail** (1159 pass) | +5, all `shop_powerup_filter_sort_test.dart` |
| `npm run test:unit` | 6 fail | **8 fail** (1912) | +2, both owner-decision conflicts |
| `npm run test:integration` | 16 fail | **17 fail** (895) | +1, **pre-existing race**, not this batch |

Verification method: the frontend files that item 3 touched (`team_h2h_banner_test` 3,
`race_detail_team_active_test` 2, `shop_tab_store_inventory_test` 1,
`tournament_game_card_test` 1 = 7 failures) were re-run in a clean `git worktree` at
HEAD and fail **identically**, confirming they are pre-existing. Do not "fix" them as
part of this batch.

The +1 integration failure (`stamps the new 1h base window…`) is a real pre-existing
race: `expiresAt` and `startsAt` are two separate `now()` reads (`usePowerup.js:1226`
vs `:1154`), so a 1ms tick yields 3599999 instead of 3600000. It passed at baseline by
timing, not correctness. **Worth fixing separately** — it will keep flaking.

### ⚠ Cross-agent integration gap found and fixed
The backend gated the Zoomies cron-shutoff on a **new** client-feature token
`zoomies_manual` (`characterPowers.js:50`) that was NOT in the §5 contract. The frontend
never sent it, so the cron kept minting, charges returned 0, and item 11's button
silently never worked. Fixed by adding `zoomies_manual` to **both branches** of
`clientFeaturesHeader` (`lib/services/backend_api_service.dart`). This is a contract
addition to §5 C5 — treat the token as part of the contract from now on.

### Deviations from spec to be aware of
- **Item 2** narrowed: price badge renders only when the strip is *not* already showing
  the price (i.e. unaffordable only). Showing it always duplicated the number and broke
  three existing tests. Matches the owner's actual complaint; kept.
- **Contrast guard is a NEW file**, not an extension of `theme_controller_test.dart:119`
  as §3 asked — extending it would mean editing an existing test, and the hard rule won.
- **Item 14 also fixed the potion enemy-attack reflect branch**, which had the same
  already-cramped bug and previously silently no-op'd. Not in the named three branches.
- **Item 11 charge state is session-local** — C5 defines no read endpoint for remaining
  charges, so the chip can't show "1 charge left" before the first tap.
- **Item 8 was scoped to race/home/leaderboard only.** `getFriends`, `getRanked`,
  `getRankedV2` and tournament serializers still default to the prod channel.
- Two **light**-palette tokens sit just under AA (`textMid` 4.497:1, `error` 4.23:1).
  Pre-existing, out of scope (item 3 was the night board), pinned so they can only improve.

### ⚠ Pre-deploy checklist
- [ ] **Adjudicate the three conflicting tests** (below) — the only thing blocking.
- [ ] **Review the hand-written migration**
      `prisma/migrations/20260726120000_batch_2026_07_26_character_days_totals_asof/migration.sql`.
      It was hand-authored because the local dev DB has pre-existing drift; it touches
      `RaceParticipant`. Verified only against the integration DB.
- [ ] Deploy **backend first**, tag a rollback point before it.
- [ ] Set `PLACEMENT_BASELINE_RESYNC=true` for one tick on deploy day — this re-seeds
      `lastNotifiedPlacement` under the new comparator emitting nothing, and is the
      mitigation for the false "you slipped to Nth" push burst.
- [ ] Kill switches ship as: `MANUAL_ZOOMIES_ENABLED` **off**,
      `CHARACTER_DAY_SNAPSHOT_DISABLED` off (= new behaviour on),
      `SHELL_BLOCK_CHANCE_OVERRIDE` unset (set `0.3` to revert item 17).
- [ ] Items **10, 14, 17 change behaviour for EVERY client version the moment they
      land** — no version gate is possible. Item 10 retroactively lowers herd bonuses
      in in-flight races (owner accepted).

### Existing-test conflicts — surfaced, NOT edited (awaiting owner)
| Test | Asserts | Now |
|---|---|---|
| `test/shop_powerup_filter_sort_test.dart` (5) | filter pills + `'Sort: Name (A–Z)'` | deleted by item 1; coverage re-created in `batch_2026_07_26_shop_test.dart` |
| `test/services/turtleShell.test.js:103` | block rate ∈ [0.25, 0.35] | 15% per Q9 |
| `test/utils/characterPowers.test.js:17` | `herdPerDay(10) === 1000` | 500 per Q5 |

`test/integration/characterVisibility.test.js:206` — the *expected* conflict **did not
materialise**: it sends no `X-Release-Channel`, resolves to prod, and correctly still
asserts `animal === null`. It passes unchanged.
