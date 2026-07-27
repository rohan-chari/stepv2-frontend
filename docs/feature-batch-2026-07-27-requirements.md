# Feature / bug batch — 2026-07-27

**Status:** Phase 5 — approved, in implementation. All 23 items specified, zero open
questions.
**Spec owner:** PM/BA pass (Claude)
**Repos:** `stepv2-frontend` (Flutter), `stepv2-backend` (Node/Prisma)

---

## 1. Summary & user story

A 23-item owner batch off a hands-on pass through the 2.0.1 build: one urgent
crash, several economy/copy corrections, a set of dark-mode and responsive-layout
defects, and a handful of small UX reversals ("go back to the old design").

There is no single user story. The batch splits into five themes:

| Theme | Items |
|---|---|
| **Crash / correctness** | 21 (urgent white screen), 7 (prize pool cap), 9 (challenge payout display) |
| **Create-race UX** | 2, 5, 6, 8 |
| **Shop & economy surfacing** | 3, 22, 23, 12 |
| **Home / theme polish** | 4, 10, 11, 14, 15, 17, 18, 20 |
| **Copy & information architecture** | 1, 13, 16, 19 |

**Deploy shape:** **two** backend changes, both env constants and neither changing a
payload shape — item 7 (`PRIZE_POOL_MAX_COINS` 3200 → 16000) and item 12
(`REFERRAL_REFERRER_COINS` 1000 → 500) — plus one backend-adjacent *verification*
(item 9, where the server-side work turns out to already be done). Everything else is
frontend-only. That keeps the compat surface small: no migration, no new endpoint, and
every rollback is an env var plus `pm2 reload`.

---

## 2. Scope / non-goals

### In scope
All 23 items below, each with its own acceptance criteria.

### Explicit non-goals
- **No new backend endpoints.** Item 5 (invite search) filters the friend list the
  client already has; item 9 renders `payoutTiers` the backend already emits.
- **No change to the payout *math*** beyond raising one ceiling (item 7). Preset
  selection, tier computation, and settlement are untouched.
- **No re-tuning of referral economics** beyond making the existing numbers visible
  (item 12) — unless D6 says otherwise.
- **No redesign** of the leaderboard, shop grid, or home hero beyond the specific
  reversals named (items 1, 15, 17, 18, 20).
- **Item 21's fix is the type bug only.** No refactor of the shop catalog model.

---

## 3. Item-by-item specification

Each item states: **Finding** (what the code actually does, with file:line),
**Change**, and **Risk/compat**.

---

### Item 21 — URGENT: Inventory → Characters white-screens after equipping a character

**Finding — root cause confirmed, no reproduction needed.**

`lib/screens/tabs/shop_tab.dart:896-898`:

```dart
final equippedCharacter =
    (_catalog?['equipped'] as Map?)?['CHARACTER'] as String?;
final equipped = equippedCharacter == null;
```

The backend's `equipped` map holds **serialized accessory objects**, not strings.
`buildEquipmentMap` (`stepv2-backend/src/modules/cosmetics/shopCosmetics.js:49-54`)
does `equipment[accessory.slot] = serializeEquippedAccessory(accessory)`.

The frontend itself already reads it correctly everywhere else — `main_shell.dart:1704-1707`:

```dart
final character = equipped['CHARACTER'];
final animal = character is Map<String, dynamic>
    ? animalFromJson(character['assetKey'])
    : null;
```

So `as String?` in `_capybaraInventoryTile()` throws
`TypeError: type '_Map<String, dynamic>' is not a subtype of type 'String?'`
**during build**, the moment `equipped['CHARACTER']` is non-null.

That is exactly the reported symptom:
- Capybara equipped (no `CHARACTER` row) → `null as String?` succeeds → page renders.
- Equip corgi/turtle → `CHARACTER` becomes a Map → the cast throws → the CHARACTERS
  inventory page renders `ErrorWidget` (blank in release).

The tile is only built under `_ShopCategory.characters` in `_buildInventory`
(`shop_tab.dart:~1150`), which is why only that page dies.

**Why no test caught it:** `_capybaraInventoryTile` was added by the "capybara is
not a shop item" batch, and its tests seed `equipped` as `{}` or `{'CHARACTER': null}` —
never the real object shape.

**Change** — `lib/screens/tabs/shop_tab.dart`:

```dart
final equippedCharacter = (_catalog?['equipped'] as Map?)?['CHARACTER'];
final equipped = equippedCharacter is! Map;
```

Read defensively (a non-Map, including a legacy String, still means "something is
equipped" only if non-null; the safe reading is: `equipped == true` iff the value
is null/absent). Prefer an explicit helper so there is exactly one reader:

```dart
/// The equipped CHARACTER's assetKey, or null for the default capybara.
/// The backend serializes `equipped[slot]` as an OBJECT; reading it as a String
/// threw during build and blanked the Characters page (batch 2026-07-27 item 21).
String? _equippedCharacterAssetKey() {
  final row = (_catalog?['equipped'] as Map?)?['CHARACTER'];
  if (row is Map) return row['assetKey'] as String?;
  if (row is String) return row;   // defensive: never emitted today
  return null;
}
```

**Risk/compat:** frontend-only, strictly widens what is accepted. Works against
every backend version.

**Tests (integration-first, per CLAUDE.md):**
- `testWidgets`: pump `ShopTab` with a catalog whose `equipped` is
  `{'CHARACTER': {'id': 'x', 'assetKey': 'turtle', ...}}`, switch to INVENTORY →
  CHARACTERS, assert the capybara tile renders **and** shows no EQUIPPED badge,
  and that `tester.takeException()` is null.
- Same with `equipped: {}` → capybara tile shows EQUIPPED.
- A regression guard that the fixture object shape matches
  `serializeEquippedAccessory`'s real keys.

---

### Item 1 — Leaderboard: drop the steps/races type toggle; move visibility here

**Finding**
- `lib/screens/tabs/leaderboard_tab.dart:22` — `enum _LeaderboardType { steps, races }`,
  threaded through ~15 call sites (`:60-110`, `:148`, `:174-244`, `:288-312`,
  `:543-564`, `:856`).
- `requestedType` (`:135`) is a public constructor param — check callers before removing.
- The **scope** toggle (`_ScopeIconToggle`, `:508`, `:1026`) is a *different* control
  (global vs friends) and **stays**.
- The visibility switch lives in Settings: `lib/screens/settings_screen.dart:235`
  (`_LeaderboardVisibilityToggle`, defined `:669-735`), copy
  `'Hide me from the global leaderboard'` (`:717`), backed by
  `authService.hiddenFromLeaderboard` / `updateLeaderboardVisibility`.

**Change**
1. Delete the type toggle UI and collapse `_LeaderboardType` to steps-only. Prefer
   deleting the enum entirely over leaving a one-value enum.
2. `requestedType` becomes a no-op (keep the param, ignore it) **or** is removed —
   check every call site first; removing a constructor param is a compile break, not
   a runtime one, so removal is safe if all callers are updated.
3. Period selection currently branches on type (`:174`, `:186`, `:227`) — keep the
   steps branch.
4. Move `_LeaderboardVisibilityToggle` out of `settings_screen.dart` into a shared
   widget file (`lib/widgets/leaderboard_visibility_toggle.dart`) and render it at
   the **bottom** of the leaderboard tab, below the standings. Remove it from
   Settings (`settings_screen.dart:235`).

**Risk/compat:** frontend-only. The `/leaderboard` endpoint still accepts a `type`
param; the app just always sends `steps`. Old builds keep working unchanged.

**Open:** does the races leaderboard get deleted server-side too? **No** — leave the
endpoint alone (D-none needed; non-goal).

---

### Item 2 — Powerups default ON at race creation

**Finding** `lib/screens/create_race_screen.dart:39` — `bool _powerupsEnabled = false;`
Tournaments already force it on at `:681-683`.

**Change** `= true`. The create request already sends `powerupsEnabled` explicitly
(`:499`, `:545`, `:559`) plus `powerupStepInterval: kFixedPowerupStepInterval` when
on, so nothing downstream changes.

**Risk/compat:** none — a client-side default. Frozen old clients keep defaulting off,
which is fine.

**Test:** widget test on `CreateRaceScreen` asserting `Key('powerups-toggle')` is on
at first paint, and that the created-race payload carries
`powerupsEnabled: true, powerupStepInterval: 2000`.

---

### Item 3 — Shop coin icon must be the paw coin, not a dollar sign

**Finding** The shop uses Material's `Icons.monetization_on_rounded` — a **$** glyph —
in 5+ places: `shop_tab.dart:976, 1027, 1589`, `_ShopTile`'s price badge (`:~1050` in
the `_ShopTile` class), and the powerup tile strip. The header badge the owner wants
to match is `CoinBalanceBadge` → `SpinningCoin` → `assets/images/coin.png`
(`lib/widgets/spinning_coin.dart:28`).

**Change**
1. Add `lib/widgets/coin_glyph.dart` — a **static** (non-spinning) `Image.asset`
   of `assets/images/coin.png` with the same `_CoinFallback` error path. Static, not
   `SpinningCoin`: a grid of 20 spinning coins is needless animation cost, and the
   strip is a label not a hero element.
2. `PillButton` currently only accepts `IconData` (`lib/widgets/pill_button.dart:14`).
   Add an optional `Widget? leading` that takes precedence over `icon`, rendered at
   `fontSize + 2` like the icon is today. Do **not** replace `icon` — dozens of call
   sites use it.
3. Replace every coin-denominated `Icons.monetization_on_rounded` in `shop_tab.dart`
   with `CoinGlyph`. Sweep the rest of `lib/` for the same icon used to mean coins
   (get-coins screen, daily reward, race detail prize plaque) and convert those too —
   the complaint is "it looks like real money", which is equally true anywhere.

**Risk/compat:** frontend-only, asset already bundled.

**Test:** widget test asserting no `Icons.monetization_on_rounded` renders on the shop
tab, and that a `CoinGlyph` renders in the price strip.

---

### Item 4 — "EXTRA SPIN" truncates on smaller screens; audit for the same class of bug

**Finding** `lib/widgets/streak_chip.dart:199` renders `PillButton(label: 'EXTRA SPIN',
icon: …, fullWidth: true)` inside an `Expanded` that is **half the screen width**
(`home_tab.dart:876-901` — a Row of `[StreakChip, 10px, SHOP]`).

`PillButton` (`lib/widgets/pill_button.dart:20`) hard-codes
`padding: EdgeInsets.symmetric(horizontal: 32, vertical: 14)` and renders
`[Icon(fontSize+2), 8px gap, Flexible(Text(maxLines:1, ellipsis))]`. On a 375pt-wide
device the available text width after 64pt padding + 17pt icon + 8pt gap is ~85pt —
"EXTRA SPIN" at 15pt pixel type does not fit, so it ellipsizes to "EXTRA SP…".

It is *not* an overflow assertion — it silently ellipsizes, which is why it shipped.

**Change** — fix the widget, not the one label:
1. `PillButton`: when `fullWidth` is true, wrap the `Row` in a `FittedBox(fit:
   BoxFit.scaleDown, alignment: Alignment.center)` so the label shrinks rather than
   truncates, and reduce the default horizontal padding to `20` for `fullWidth`
   buttons (a full-width button does not need 32pt side padding; it is centred by
   the parent's width).
2. Keep `maxLines: 1` + ellipsis as the last-resort backstop.

**Audit (required deliverable, not optional).** Grep every `PillButton` with
`fullWidth: true` **or** a label ≥ 10 characters that lives inside an `Expanded` /
`Flexible` / fixed-width box, and verify at **320pt** (iPhone SE 1st gen) and
**375pt**. Known candidates found while specing:

| Site | Label | Constraint |
|---|---|---|
| `streak_chip.dart:199` | `EXTRA SPIN` | half-width Expanded |
| `home_tab.dart:894` | `SHOP` | half-width Expanded — safe, short |
| `shop_tab.dart:990` | `WATCH 3 ADS TO UNLOCK` | full-width sheet — at `fontSize: 13` |
| `shop_tab.dart:1003` | `GET MORE COINS` | full-width sheet |
| `race_alert_opt_in_card.dart:110` | `ENABLE RACE ALERTS` | `flex: 2` of a Row, already dropped to `fontSize: 10` — a symptom of this same bug |
| `home_tab.dart` `_SmallRaceButton` | `CHALLENGE` | **fixed `width: 78`** at `size: 10` — separate widget, same defect class; must be audited |
| `onboarding_flow.dart:898` | `START THE DAILY CHALLENGE` | full-width |
| `create_race_screen.dart` CTA row | varies | — |

The `fontSize: 10` / `fontSize: 13` overrides already scattered around are
work-arounds for this bug; once `FittedBox` lands, they can be normalised, but
**do not** change them in this batch beyond where they still truncate — that is scope
creep and a visual-regression risk.

**Test:** a `testWidgets` that pumps the home tab at 320×568 and 375×667 and asserts
the rendered `EXTRA SPIN` text has no ellipsis (`findsOneWidget` on the exact string
plus a check that the `Text`'s laid-out size is not clipped — use
`tester.renderObject<RenderParagraph>(…).didExceedMaxLines == false`).

---

### Item 5 — No search bar when adding people to a race

**Finding** Neither `lib/screens/friend_picker_screen.dart` nor
`lib/screens/race_invite_screen.dart` contains a `TextField` — confirmed by grep.
Both render the full friend list unfiltered.

**Change** Add a shared `lib/widgets/friend_search_field.dart` — a parchment-styled
`TextField` with a leading search icon and a clear button — and wire it into **both**
screens. Filter client-side, case-insensitively, on display name **and** the `@handle`
(`lib/utils/at_name.dart`). Debounce is unnecessary (local list). Show an empty state
("No friends match *query*") when the filter yields nothing, distinct from the
"no friends yet" empty state.

Show the field only when the list has more than a threshold of entries (**8**) so a
3-friend list is not cluttered — see D2.

**Risk/compat:** frontend-only, no request shape change.

**Test:** pump each screen with 20 fixture friends, type a query, assert only matching
rows render; assert selection survives clearing the query.

---

### Item 6 — The public/private toggle reads backwards

**Finding** `lib/screens/create_race_screen.dart:1694-1745`. A single
`Switch.adaptive(value: _isPublic)` with a label above it that flips between
`PUBLIC RACE` / `PRIVATE RACE`. Default `_isPublic = false` (`:41`).

The owner's complaint is precise: the card **says** "PRIVATE RACE" and the switch is
**off**, which reads as "PRIVATE is the thing that is turned off" — so users flip it
to *get* a private race and get a public one. A boolean switch whose label mutates
with its own value is inherently ambiguous.

**Change** Replace the switch with a **two-option segmented control**: `PRIVATE |
PUBLIC`, both always visible, the selected one filled. Subcopy under it describes the
selected option only (`INVITE ONLY` / `ANYONE CAN JOIN`). Default stays PRIVATE.
Reuse the visual language of the existing STORE/INVENTORY segmented control
(`shop_tab.dart:~540-590`) rather than inventing a third pattern.

Apply the same treatment in `lib/screens/edit_race_screen.dart` if it carries the
same switch — verify during implementation.

**Risk/compat:** frontend-only; `isPublic` request field unchanged.

**Test:** widget test asserting both segments render, PRIVATE is selected at first
paint, tapping PUBLIC sends `isPublic: true`, and the subcopy matches the selection.

---

### Item 7 — Prize-pool cap is wrong: 100 players × 14 days should be 16,000

**Finding — the owner's arithmetic is correct.**

Formula (`lib/models/race_prize_pool.dart:35-54`, mirroring
`stepv2-backend/src/shared/economy/prizePool.js`):

```
pool = playerCount × durationPoints(days) × PRIZE_COIN_UNIT,  clamped to PRIZE_POOL_MAX_COINS
durationPoints: ≤1d → 1,  ≤3d → 2,  ≤7d → 4,  else → 8
```

100 players × 14 days (→ 8 points) × 20 = **16,000**, clamped to
`PRIZE_POOL_MAX_COINS = 3200` (`.env.example:19`, mirrored at
`race_prize_pool.dart:24`) → the observed **3,200**.

**Change** Raise the ceiling to **16,000** — the exact maximum the formula can produce
at the legal field cap.

**Field cap confirmed:** `validateMaxParticipants` rejects anything outside `2..100`
(`stepv2-backend/src/modules/races/services/validateRaceConfig.js:56-68`), so a
user-created race maxes at 100 × 8 × 20 = **16,000**. The new ceiling is therefore
non-binding for every race a user can create — exactly what the owner asked for.

**Seeded challenges are the exception, and 16,000 stays a hard ceiling for them
(D3, owner-decided).** Seeded daily/weekly races take `maxParticipants` from their
seed row and never pass through `validateMaxParticipants`, so their field can exceed
100 (`seededRaceRenewal.js:67`; the source comment references "a 300-player Daily").
A 300-player Weekly would compute 300 × 4 × 20 = 24,000 and **will clamp to 16,000**.
That is deliberate: it bounds total minting, which would otherwise scale without limit
as signups grow. One global `PRIZE_POOL_MAX_COINS`, no second knob.

1. Backend: `PRIZE_POOL_MAX_COINS=16000` in `.env.example`, in prod `.env`, and in
   staging `.env`. Confirm `src/shared/economy/prizePool.js:15` reads it with the
   right default (update the hard-coded default to 16000 too, so a missing env var
   does not silently reinstate 3200).
2. Frontend mirror: `kPrizePoolMaxCoins = 16000` (`race_prize_pool.dart:24`).
   `race_prize_pool_test` is the existing tripwire for this mirror — update its
   fixtures.
3. Tournaments keep `kTournamentPrizePoolMaxCoins = 1000` / `MAX_CHAMPION_PRIZE`
   **unchanged** (`race_prize_pool.dart:26-28` — an explicit prior decision, D9 of the
   funded-pools spec). Do not touch it.

**Risk/compat — this is the item with real blast radius.**
- **Economic:** this raises the maximum app-minted payout of a single race by 5×.
  A 100-player 14-day race now mints 16,000 coins instead of 3,200. Kill switch is
  the existing `fundedPrizePoolsEnabled` flag; a softer rollback is putting the env
  var back to 3200 and `pm2 reload` (no deploy).
- **Frozen old clients:** they carry `kPrizePoolMaxCoins = 3200` compiled in, so their
  **create-screen preview** will under-promise (show 3,200 where the server will mint
  16,000). That is the safe direction — under-promise, over-deliver — and every
  *server-rendered* figure is correct on old clients because `RacePrizePool.fromJson`
  reads `maxCoins` off the payload (`race_prize_pool.dart:118`) and `atMax` off the
  server (`:113`). **No old client shows a wrong number for a real race.**
- The old client's `atMax` "this pool is maxed out" copy comes from the server too,
  so it will correctly stop claiming max-out at 3,200.

**Deploy order:** backend env change **first** (it is the source of truth), app after.
Between the two, new-client previews are right and old-client previews under-promise.

**Test (backend, integration):** create a 100-player 14-day funded race via the real
endpoint, assert `prizePool.coins === 16000`, `atMax === true`,
`maxCoins === 16000`. Assert a 100-player 30-day race also lands 16,000 (the band
is flat above 7 days) and that a 4-player 1-day race is unchanged at 80.
**Test (frontend):** `race_prize_pool_test` fixture for (100, 14) → 16,000.

---

### Item 8 — Remove "FUNDED BY BARA · FREE TO ENTER" from race creation

**Finding** `lib/screens/create_race_screen.dart:351` —
`footnote: 'FUNDED BY BARA · FREE TO ENTER'` on the prize-pool preview plaque.

Same phrase also appears on **race detail** at `race_detail_screen.dart:3160-3163`
and `:3335-3336`, and a tournament variant `'FREE TO ENTER · CHAMPION TAKES ALL'` at
`create_race_screen.dart:982`.

**Change (D4 — owner decided: remove all three sites).**

1. `create_race_screen.dart:351` — drop `'FUNDED BY BARA · FREE TO ENTER'`.
2. `create_race_screen.dart:982` — drop `'FREE TO ENTER · CHAMPION TAKES ALL'`
   (tournament variant).
3. `race_detail_screen.dart:3160-3163` and `:3335-3336` — drop the
   `'Funded by Bara — free to enter…'` lines. Note both sites have a **two-branch**
   string: a plain form and an at-max form ("This pool is maxed out." /
   "The pool grows as…"). The *pool-grows* and *maxed-out* information is useful and
   is **not** what the owner objected to — keep those clauses, drop only the
   "Funded by Bara — free to enter" lead-in. Where removing the lead-in leaves an
   empty string, render nothing rather than an empty line.

The `footnote` param on `_prizePoolPlaque` becomes unused by the create screen but
stays on the widget (nullable) — do not delete it in this batch.

**Risk/compat:** copy-only.

---

### Item 9 — Daily/weekly challenge shows no payout distribution

**Finding — the backend half is already done.**

Seeded daily *and* weekly challenges are **already** created with
`payoutPreset: "TOP_HALF"` —
`stepv2-backend/src/modules/races/jobs/seededRaceRenewal.js:58`, with an explicit
comment that a 300-player Daily spreads the pool across 150 finishers. So
*"change the weekly challenge to be a top half payout"* is **already true, for both
cadences**. Nothing to change server-side. This must be confirmed against prod data
before the item is called done (see acceptance criteria).

The **display** is the real gap. `getRaceDetails` emits `payoutTiers`
(`queries/getRaceDetails.js:44,70`) and race detail renders a breakdown at
`race_detail_screen.dart:3344` — but gated on
`_hasPrizeDisplay && payoutTiers.isNotEmpty` (`:3027-3031`).

Two reasons a user sees nothing:
1. **Field too small.** TOP_HALF needs ≥4 accepted runners (`race_payouts.dart:37-38`);
   below that the server pays nothing and `payoutTiers` is empty → no breakdown.
2. **Field too large.** A 300-player Daily produces **150 tiers**. Rendering 150 rows
   in a card is unusable — and if `_buildPayoutBreakdown` truncates or the card
   collapses, the user perceives "no breakdown".

**Change — a summarised breakdown, not a 150-row list (D5, owner-approved layout):**

```
┌──────────────────────────────┐
│ PRIZE POOL      6,000 🐾     │
│ Top half splits it evenly    │
│                              │
│ ~40 coins each               │
│ Top 150 of 300 get paid      │
│                              │
│ You're 62nd — in the money   │
│           See all payouts ›  │
└──────────────────────────────┘
```

Add this to race detail (and to the featured-challenge card on the Races tab). It
answers *"how much do I get if I finish where I'm finishing?"*:

- **Headline:** the preset in plain words — "Top half splits the pool evenly".
- **The number that matters:** "≈ N coins each" — pool ÷ paid places, read from
  `payoutTiers` (all TOP_HALF tiers carry the same amount, so take `tiers.first.amount`;
  do **not** recompute client-side).
- **Cut line:** "Top {paidPlaces} of {fieldSize} get paid" — `paidPlaces = tiers.length`.
- **Your line, when the viewer is in the race:** "You're {placement} — {in the money |
  {n} places from the cut}".
- **Full list behind a tap** ("See all payouts"), rendered lazily in a sheet, so the
  150-row case is opt-in and scrollable.

Every field degrades to absent: no `payoutTiers` (old backend) → render nothing,
exactly as today. Never compute a payout figure client-side; the server owns the math.

**Risk/compat:** frontend-only. Reads a field the current prod backend already emits;
absent → current behaviour.

**Test (frontend, integration-style):** pump `RaceDetailScreen` with (a) a 300-player
TOP_HALF payload → assert the summary shows "150 of 300" and the per-head amount, and
that only the summary (not 150 rows) is in the tree; (b) a payload with no
`payoutTiers` → assert no summary and no exception; (c) a 4-player payload → assert
"2 of 4".

---

### Item 10 — "Clean pace so far" shown at midnight with 0 steps

**Finding — already fixed on `main`, not yet shipped.**

`lib/screens/tabs/home_tab.dart:916-931`:

```dart
/// The pace line under the capy. [steps] is null when today hasn't started —
/// either no steps yet, or no `stepData` at all (item 18). Both used to fall
/// through to the positive "Clean pace so far" bucket…
String _heroSummary({required int? steps}) {
  if (steps == null || steps <= 0) {
    return 'Fresh day. Get moving to hit your first milestone.';
  }
  …
```

This landed in commit `54f945d` (batch 2026-07-26) and has **not** reached the App
Store — the owner is testing 2.0.1, which predates it.

**Change** No code change expected. **Verify** on a build off current `main` that a
0-step midnight state renders "Fresh day.", then close the item. If it still
reproduces on `main`, the cause is upstream in `stepData` (a stale non-zero
`stepData.steps` carried across midnight would land in the ≥5,000 bucket, not this
one) — escalate rather than patching the string.

**Test:** add the missing regression test if absent — `_heroSummary` with
`steps: null` and `steps: 0` both → "Fresh day.".

---

### Item 11 — "INVITE" is invisible in night mode

**Finding — confirmed, and it is broader than INVITE.**

`home_tab.dart` `_HomeRaceActionRow` draws its eyebrow label with
`color: AppColors.of(context).roofMid`:

```dart
Text(label, style: PixelText.title(size: 10, color: AppColors.of(context).roofMid)),
```

Night palette (`lib/styles.dart:342`): `roofMid = #214637` (dark green).
Night `parchment` (`:337`): `#1B2A34` (near-black navy).
Contrast ratio ≈ **1.2:1** — effectively invisible. Day mode is fine
(`roofMid #2E5D47` on `parchment #FFFBF5` ≈ 7:1), which is why it shipped.

This is the same class as the logged `ink`/`pillGold` night-flip trap: a token that
is a *surface-ish* colour by day being used as *text* at night.

It affects **every** eyebrow on that row, not just INVITE: `ACTIVE`, `LIVE`,
`FINISHED`, `PUBLIC`, `OPEN`.

**Change** Use a token that is night-safe as text on parchment. `textMid` is the
correct semantic (it is a text token, defined for both palettes). If the owner wants
the label to stay green-accented, add a `successText`-style token — note
`_AppColorToken.successText` already maps to `roofMid` in the day palette
(`styles.dart:288`); give it a legible night value rather than reusing `roofMid`.

**Sweep required:** grep every `color: AppColors.of(context).roofMid` and
`.roofDark` used as a **text/icon** colour and check each against the night parchment.
Surface uses (borders, fills) are fine and must not be touched.

**Test:** a golden-free contrast test — pump `_HomeRaceActionRow` under the dark
theme and assert the label's resolved colour is not `roofMid`; plus a unit assertion
that the chosen token clears 4.5:1 against night `parchment`.

---

### Item 12 — State the coins earned for sharing a link

**Finding** The referral share copy says "we'll both earn coins" with **no number**
(`referral_screen.dart:553-557`), and the referral screen's blurb likewise
(`:248` — "you BOTH earn coins"). Actual configured values
(`stepv2-backend/src/modules/social/referralRewards.js`):

- `REFERRAL_REFERRER_COINS` = **1000** (the sharer)
- `REFERRAL_REFEREE_COINS` = **500** (the friend who joins)

So "500" is already what the *joiner* gets; the sharer already gets 1,000. The owner
said "i think 500 is prob good" — which reading they meant is **D6**.

`referral_rules_screen.dart:8-10` deliberately avoids hardcoding amounts and says
they are "shown live on the referral/welcome surfaces" — but they currently are not.

**D6 — owner decided: both sides get 500, and say so.** So this item carries an
**economy change** as well as a copy change: `REFERRAL_REFERRER_COINS` drops
1,000 → **500**. See §4.3 for the deploy note; this is the second (and last) backend
change in the batch.

Consequence worth naming: the sharer's incentive halves. Referral payout per completed
referral goes from 1,500 total (1,000 + 500) to 1,000 total — a **33% cut in referral
cost**, and the sharer no longer earns more than the person who did nothing but join.
Flagging, not blocking — the owner reaffirmed 500 for both.

**Change**
1. **Serve the numbers, don't hardcode them.** `GET /social/referral-preview`
   (`getReferralPreview.js`) already imports `REFEREE_REWARD_COINS` — extend the
   existing `/referrals/status` (or preview) response with both figures if not already
   present. If the field is absent (older backend), fall back to **no number** — the
   current copy — never to a hardcoded guess that could contradict config.
2. Surface them on: the referral screen headline, the share text, and the Get Coins
   hub's invite row.
3. Share copy becomes explicit and symmetric, e.g. *"…we both pocket 500 coins once
   you finish your first race"* (final wording folded into item 16's conversational
   rewrite).

**Risk/compat:** if a new response field is needed, it is **additive** and the app
must render fine without it (CLAUDE.md rule). Confirm the field ships to prod before
the app build goes out.

**Timing matters for the reward cut.** `REFERRAL_REFERRER_COINS` is read at grant
time, not at share time. A user who shared a link *before* the change and whose friend
finishes *after* it gets 500, not the 1,000 the old copy implied. Two mitigations,
both cheap:
- Ship the env change and the app copy as close together as possible.
- The reward is already never promised as a specific number in today's copy ("we'll
  both earn coins"), so no frozen client is displaying a figure that the change
  falsifies. **This is the reason it is safe to do at all** — had the old copy said
  "1,000", cutting it under frozen clients would be a broken promise.

---

### Item 13 — Profile says "Goal Streak"; should say "Streak"

**Finding** `lib/screens/tabs/profile_tab.dart:645` — `'Goal Streak',`.

**Change** → `'Streak'`. Check for a matching test asserting the old string.

---

### Item 14 — Night mode should start at 9 PM, not 7 PM

**Finding — what it does right now:** `lib/theme_controller.dart:24-25`

```dart
static const nightStartHour = 19;   // 7 PM
static const dayStartHour = 7;      // 7 AM
```

Automatic mode resolves dark when `hour >= 19 || hour < 7` (`:50-51`), and a `Timer`
re-evaluates at the next boundary (`:78-95`). It is **device-local time, never the
API** (`:11`), and re-resolves on app resume (`:65-67`).

**Change** `nightStartHour = 21`. `dayStartHour` stays `7` — already what the owner
asked for.

**Risk/compat:** frontend-only, device-local. `_scheduleBoundary` already derives
both boundaries from these constants, so no other change is needed.

**Test:** the existing theme-controller tests almost certainly assert 19:00 —
update them and add cases at 20:59 (light), 21:00 (dark), 06:59 (dark), 07:00 (light).
Include a DST-adjacent case if the suite already models one.

---

### Item 15 — Restore the old chronological "Today's coins" milestone track

**Finding** `lib/widgets/step_milestones_section.dart:293-295` states it plainly:

> The four milestones as discrete parchment tiles laid out in a 2×2 grid
> (owner-requested cards instead of the old connected node track).

Changed in commit **`a4e4153`** ("Feature batch 2026-07-24"). The prior implementation
— `_buildTrack()` / `_connector()` / `_node()` — is recoverable verbatim from
`git show a4e4153^:lib/widgets/step_milestones_section.dart`.

**Change** Restore `_buildTrack` / `_connector` / `_node`; delete `_buildCards` /
`_milestoneCard`. **One deliberate deviation from the old code:** the old `_node`
used `AppColors.success` for the claimed state; the dark-mode batch introduced
`milestoneCollected` for exactly this, and the current `_milestoneCard` uses it
(`:328`, `:406`). **Keep `milestoneCollected`** — reverting to `success` would
re-break dark mode. Same for the `_buildFooter` claimed colour (`:490`).

Everything else in the file (state, fetch, batch consumption, footer) is unchanged by
this item.

**Risk/compat:** frontend-only, no payload change.

**Test:** widget test asserting 4 nodes and 3 connectors render, a claimable node
shows "TAP!", and a claimed node uses `milestoneCollected` (not `success`).

---

### Item 16 — Invite copy is too robotic

**Finding** Current copy is functional and flat:

- `referral_screen.dart:553-557` — *"I'm at 8,432 steps today — think you can beat me?
  Race me on Bara with code X and we'll both earn coins when you finish your first
  race: URL"* (already the most conversational one).
- `referral_screen.dart:248` — *"…you BOTH earn coins."*
- `referral_screen.dart:141` — *"You're in! Finish your first race to earn coins."*
- `race_detail_screen.dart:5083` area — race-invite share copy.
- `friend_picker_screen.dart:54` — `'CHALLENGE A FRIEND'`.
- `onboarding_flow.dart:876` — *"Entered in the Daily & Weekly challenge"*.
- Push/notification invite bodies — `stepv2-backend/src/modules/notifications/`.

**Change** Rewrite every user-facing invite/share string in a conversational register:
second person, contraction-friendly, a light taunt where the context is competitive,
no ALL-CAPS mid-sentence, no "you BOTH earn coins" construction. Fold item 12's coin
figures in here so a single pass produces the final strings.

**Deliverable:** a copy table in this doc (surface → old string → new string) filled in
during implementation, so the owner reviews wording once rather than per-screen.

**Reference screenshot** (owner-supplied) is no longer retrievable — see D1.

**Risk/compat:** copy-only. Backend push copy must be reviewed for old-client safety:
push bodies are rendered by the server and reach frozen clients fine.

---

### Item 17 — Content used to run edge-to-edge; now there is a side gap

**Surface confirmed by owner: the Races tab.**

**Finding** The Races tab root is already edge-to-edge — `races_tab.dart:358-392`
paints a full-bleed `ColoredBox` + `ArcadeCheckerPainter` and applies only *vertical*
padding (`EdgeInsets.only(top: topInset + 14, bottom: tabBarHeight)`). It does **not**
go through `TabLayout`/`ContentBoard`.

The gap comes from the per-section insets inside the scroll view. Every race list
block carries a 10pt horizontal inset:

- `:708` `EdgeInsets.symmetric(horizontal: 10)`
- `:760` `EdgeInsets.only(left: 10, right: 10)`
- `:827` `EdgeInsets.only(left: 10, right: 10, bottom: 8)`
- `:953` `EdgeInsets.fromLTRB(10, 4, 10, 6)` (the filter/section pill bar)
- `:1054`, `:1899` `EdgeInsets.only(left: 10, right: 10, bottom: 8)`
- `:1074` `margin: EdgeInsets.symmetric(horizontal: 10)` (empty-state card)

Section **headers** use 16pt (`:611` `fromLTRB(16, 15, 16, 8)`), so headers and cards
are already inconsistent with each other.

**Change** Take the race **cards / section blocks** full-bleed: drop the 10pt
horizontal inset at `:708, :760, :827, :1054, :1899` and the `:1074` margin so cards
meet the screen edge, as they did before. Two constraints:

1. **Leave the header/pill insets alone** (`:611`, `:953`). A pill row that touches the
   screen edge reads as broken, not full-bleed; the owner asked for the card *sides*
   to reach the edge.
2. Cards carry their own 2pt border and a hard drop shadow. Verify at the edge that
   the shadow is not clipped by the scroll view and that the border still reads —
   full-bleed can make a bordered card look like a seam.

**Caveat, stated honestly:** the 10pt insets are long-standing (they predate the
recent redesign commits — `git log -S` traces them to `526a130`/`b105551`), so this is
**not** a regression I can point to a commit for. It is a deliberate change to what
the owner prefers, and it is one line each to revert if the full-bleed result is not
what they remembered. Screenshot the before/after for review rather than assuming.

**Risk/compat:** frontend-only, cosmetic.

---

### Item 18 — Move the "clean pace" line off the ground brick; put it on a trail sign

**Finding** `home_tab.dart:825-840` positions the pace summary at
`left: 24, right: 24, bottom: 16`, i.e. directly on the scrolling ground strip
(`HomeHeroScene(groundHeight: …, groundScrollSpeed: 26)`), so the text sits on top of
the brick/dirt texture with only a drop shadow separating it.

There is already a `TrailSign` widget (`lib/widgets/trail_sign.dart`) — but it is a
**parchment card**, not a sign: "Compact modal/sign surface that now matches the
homepage arcade chrome." It is not the wooden sign-top the owner is describing, and
reusing it would put a parchment rectangle on the hero.

**Change — art first, per CLAUDE.md's no-hand-drawn-artwork rule.**

1. **Generate the sign art via the Codex `imagegen` pipeline** (CLAUDE.md §"Generating
   new accessory art"). Prompt for a *sign top only, no post* — a horizontal wooden
   plank with a bold solid black outline, chunky pixel art, transparent background via
   the chroma-key workflow, sized to sit under a right-facing capybara. Reference the
   capybara sheet plus 2–3 side-profile accessories for style. Generate to a scratch
   dir, composite onto **white** before judging, iterate until orientation/outline/
   alpha all pass.
2. Install as `assets/images/trail_sign_plank.png` (globbed by `assets/images/`
   already — no pubspec change).
3. New widget `lib/widgets/hero_pace_sign.dart`: the plank as a nine-slice-ish
   background (or a fixed-aspect `Image.asset` with the text centred in a padded
   overlay), with the pace text on it. Text must stay legible in **both** palettes —
   the plank is a fixed-colour PNG, so pick a text colour that works on the wood, not
   a theme surface token.
4. Reposition it in the hero so it clears both the capybara's feet and the ground
   scroll — it should read as signage standing in the scene, not floating.

**Do not hand-draw the plank in `CustomPainter`.** That is explicitly prohibited.

**Risk/compat:** frontend + a new bundled asset. The asset ships in the binary, so
there is no old-client concern (old clients simply do not have the widget).

---

### Item 19 — The notification opt-in card should be an overlay, with better copy

**Finding** `lib/widgets/race_alert_opt_in_card.dart` renders an inline `RetroCard`
inside the race-detail scroll view (`race_detail_screen.dart:2893`), pushing the race
content down. Copy:

- Heading: `DON'T MISS THE FINISH`
- Body: *"Get race invites and important match updates. **Bara won't ask the system
  until you tap below.**"* ← the sentence to delete
- CTA: `ENABLE RACE ALERTS` at `fontSize: 10` (a truncation work-around — item 4)

**Change**
1. Convert to an **overlay**: a modal (bottom sheet or centred dialog) presented over
   race detail rather than a widget in the page. There is an existing
   `lib/widgets/notification_ask_dialog.dart` — check whether it can be reused or
   extended instead of building a third notification-prompt surface.
2. Delete the *"Bara won't ask the system until you tap below."* sentence.
3. `ENABLE RACE ALERTS` → **`ENABLE NOTIFICATIONS`** (and with item 4's `FittedBox`,
   the `fontSize: 10` hack can go back to a normal size).
4. **Preserve the dismissal contract exactly.** The current card persists
   `race_alert_card_dismissed_v1` on *both* "Not now" and any enable attempt
   (granted or denied) — "A denial should not nag again inside the race". An overlay
   that appears on every race-detail open would be far more annoying than the inline
   card. Same `storageKey`, same one-shot semantics, and it must still respect
   `onEnable == null` (render nothing).
5. **Demo mode must stay silent.** `test/demo_race_demo_mode_test.dart:170` asserts
   `RaceAlertOptInCard` never renders and no OS prompt fires during the demo race
   (G3). Do not modify that test; the overlay must satisfy it.

**Risk/compat:** frontend-only. Presentation timing matters — present after the first
frame, not during build.

**Test:** update `test/race_alert_opt_in_card_test.dart` for the overlay (do not delete
its assertions); assert the sheet shows once and never again after dismissal; assert
the demo-mode test still passes untouched.

---

### Item 20 — Faint white line under the purple boxes

**Surface confirmed by owner: the home page. Root cause found.**

**Finding** `lib/styles.dart:124`:

```dart
static const feltLine = Color(0x1FFFFFFF);   // 12%-alpha WHITE
```

It is drawn as a full-width top border on the home section headers:

- `home_tab.dart:1361` — `_HomeRaceHeader`: `Border(top: BorderSide(color: dividerColor))`
  where `dividerColor = AppColors.of(context).feltLine`
- `home_tab.dart:1827` — `_HomeSectionHeader`: same `Border(top: BorderSide(color: …feltLine))`

That is literally a faint white line spanning the screen, sitting immediately above a
section header — i.e. under whatever block precedes it. Exactly the reported symptom.

`feltLine` has **no night override** — `styles.dart:311` maps it in the day palette and
the night palette inherits the same 12% white, so it is equally present in both modes.
It is a leftover from the older felt-table look; the current home uses card borders and
the `_SectionTick` marker to separate sections, so the rule is redundant as well as ugly.

**Change** Remove the `Border(top: …feltLine)` decoration from both `_HomeRaceHeader`
(`:1358-1362`) and `_HomeSectionHeader` (`:1823-1828`). Where that empties the
`BoxDecoration`, drop the `Container`'s `decoration` entirely rather than leaving an
empty one, and keep the padding.

**Sweep:** grep `feltLine` across `lib/` — if these two are its only consumers, delete
the token from `styles.dart` and its `_AppColorToken` entry too, so it cannot be
reintroduced. If other surfaces use it deliberately, leave the token and change only
these two sites.

**Risk/compat:** frontend-only, cosmetic. `_SectionTick` and the header text remain, so
sections stay visually delimited.

---

### Item 22 — Centre the EQUIPPED pill on inventory tiles

**Finding** `_ShopTile` (`shop_tab.dart`, `_ShopTile.build`) renders the badge at
`Positioned(top: 4, right: 4)` — top-right — because that slot is shared with the
`xN` owned-quantity badge on powerup tiles.

**Change** Centre the badge horizontally when it is the EQUIPPED badge:
`Positioned(top: 4, left: 0, right: 0, child: Center(child: <pill>))`. Keep the `xN`
quantity badge top-right — it is a different badge with a different job, and centring
it would collide with the (now-removed, item 23) price chip's former slot.

Cleanest implementation: give `_ShopTile` a `badgeAlignment` (default right) rather
than string-matching `'EQUIPPED'`.

**Test:** widget test asserting the EQUIPPED pill's centre-x equals the tile's centre-x.

---

### Item 23 — Kill the per-tile coin badge; put the price back in the strip

**Finding** `_ShopTile.priceBadge` (`shop_tab.dart`, `_ShopTile`) draws a coin chip at
`Positioned(top: 4, left: 4)` over the art. Its own doc comment explains why it
exists:

> Item 2 — the coin price, ALWAYS shown for a store item. The strip's label follows
> the primary action, so an unaffordable item's strip reads "Get coins" / "Watch 1 ad"
> and the number vanished from the tile entirely.

Set at `shop_tab.dart:1016` (cosmetics) and the powerup equivalent:
`priceBadge: route == _AffordRoute.affordable ? null : price`.

The owner is rejecting the *chip* and asking for the price to live in the strip in all
three affordability states.

**Change**
1. Delete `priceBadge` from `_ShopTile` and both call sites (and its `Key('shop-price-badge-text')`
   — update any test asserting it).
2. `stripLabel` becomes **the price, always**: `'$price'` with the `CoinGlyph`
   (item 3) as `stripIcon`, regardless of `_AffordRoute`. The strip stops advertising
   the action.
3. **Tapping an unaffordable tile already opens the sheet** — `onStrip: openSheet` and
   `onTap: openSheet` both point at the sheet (`shop_tab.dart:1030-1031`), and the
   comment above `_storeCosmeticTile` says this was a deliberate anti-misclick change.
   So "let them click into it" is already true; verify it holds for the powerup tile
   too and for `stripEnabled` when unaffordable (it must stay `true`).
4. The **sheet's CTA** carries the routing, which it already does
   (`shop_tab.dart:975-1010`):
   - affordable → `BUY · N`
   - shortfall ≤ ad-unlock ceiling → `WATCH N AD(S) TO UNLOCK`
   - otherwise → `GET MORE COINS` → `_openGetCoins()`
   This is exactly what the owner described. Confirm the ceiling is the server-served
   `adUnlock.maxShortfall` (`shop_tab.dart:1342-1345`) — the owner's "if it falls in
   that 20" refers to the 20-coin ad-unlock ceiling, which is **server config, not a
   constant to hardcode**.
5. Keep `_adUnlockCapNotice(price)` in the sheet — it explains the ceiling.

**Risk/compat:** frontend-only.

**Test:** widget test asserting (a) no price chip renders anywhere on the grid,
(b) an unaffordable tile's strip still shows the numeric price with a coin glyph,
(c) tapping an unaffordable tile opens the sheet, (d) the sheet's CTA is
`WATCH…AD` inside the ceiling and `GET MORE COINS` outside it.

---

## 4. API contract

**Two backend changes in this batch. Both are configuration values; neither changes
a request or response shape.**

### 4.1 `PRIZE_POOL_MAX_COINS` — 3200 → 16000 (item 7)

No request or response **shape** changes. The affected response object is unchanged:

```jsonc
// GET /races/:id → race.prizePool  (contract §5.1, unchanged shape)
{
  "coins": 16000,          // was clamped to 3200
  "projected": true,
  "atMax": true,           // now true at 16000, not 3200
  "playerCount": 100,
  "durationDays": 14,
  "durationPoints": 8,
  "coinUnit": 20,
  "maxCoins": 16000,       // was 3200
  "funded": true
}
```

**Old-client compatibility (the #1 rule):**
- Old clients read `coins`, `atMax`, and `maxCoins` **off this payload**
  (`race_prize_pool.dart:106-123`) — so every server-rendered figure is correct on a
  frozen binary.
- The only stale number on an old client is its **local create-screen preview**, which
  clamps at its compiled-in 3,200 and therefore **under**-promises. Under-promising is
  the safe failure direction and needs no gating.
- No field is added or removed, so no client of any version can break on parsing.

**Rollback:** set the env var back to `3200` and `pm2 reload` — no deploy, no
migration. (Note the known deploy footgun: never pipe `migrate deploy` through `tail`;
not applicable here since there is no migration.)

### 4.2 `REFERRAL_REFERRER_COINS` — 1000 → 500 (item 12, D6)

`stepv2-backend/src/modules/social/referralRewards.js:7-10`. Set
`REFERRAL_REFERRER_COINS=500` in `.env.example`, prod `.env`, and staging `.env`, and
update the hard-coded default from `1000` to `500` so a missing env var does not
silently reinstate the old value. `REFERRAL_REFEREE_COINS` stays **500**.

No shape change. Grants already in flight are unaffected (the constant is read at
grant time). Rollback is the env var + `pm2 reload`.

### 4.3 Referral reward figures on the wire (item 12) — additive, only if not already served

If `GET /social/referral-preview` (or `/referrals/status`) does not already carry the
coin figures, add them **additively**:

```jsonc
{
  "referrerCoins": 500,   // NEW, additive
  "refereeCoins": 500,    // NEW, additive
  …existing fields unchanged
}
```

Old clients ignore unknown keys. The new client **must** render correct copy when both
fields are absent — falling back to the current number-free wording, never to a
hardcoded constant that could contradict server config. This is what keeps the app
correct if the figures are retuned again later without an app release.

**Verify the field is live in prod before the app build ships** (CLAUDE.md: do not
depend on a brand-new backend field without confirming prod serves it).

### 4.4 Nothing else

Items 1, 9, and 5 read fields the current prod backend **already** emits
(`type` param, `payoutTiers`, the friends list). No new endpoints.

---

## 5. Data model / migrations

**None.** No table, column, enum, or index changes in this batch.

- Item 7 is an env constant, not a column.
- Item 9's `TOP_HALF` preset already exists in the `RacePayoutPreset` enum and is
  already the value on seeded races.
- Item 12's figures are env constants (`referralRewards.js`), not stored data.

No backfill. No default-safe-read concerns beyond §4.

---

## 6. Frontend plan

### 6.1 Files touched

| Area | Files |
|---|---|
| Shop | `lib/screens/tabs/shop_tab.dart` (21, 3, 22, 23), new `lib/widgets/coin_glyph.dart` (3) |
| Buttons | `lib/widgets/pill_button.dart` (3, 4) |
| Home | `lib/screens/tabs/home_tab.dart` (11, 18), `lib/widgets/streak_chip.dart` (4), `lib/widgets/step_milestones_section.dart` (15), new `lib/widgets/hero_pace_sign.dart` + `assets/images/trail_sign_plank.png` (18) |
| Leaderboard | `lib/screens/tabs/leaderboard_tab.dart`, `lib/screens/settings_screen.dart`, new `lib/widgets/leaderboard_visibility_toggle.dart` (1) |
| Create/edit race | `lib/screens/create_race_screen.dart` (2, 6, 8), `lib/screens/edit_race_screen.dart` (6) |
| Invite | `lib/screens/friend_picker_screen.dart`, `lib/screens/race_invite_screen.dart`, new `lib/widgets/friend_search_field.dart` (5), `lib/screens/referral_screen.dart` (12, 16) |
| Race detail | `lib/screens/race_detail_screen.dart` (9, 19), `lib/widgets/race_alert_opt_in_card.dart` (19) |
| Theme | `lib/theme_controller.dart` (14), `lib/styles.dart` (11) |
| Models | `lib/models/race_prize_pool.dart` (7) |
| Profile | `lib/screens/tabs/profile_tab.dart` (13) |

### 6.2 States (loading / empty / error)

- **Item 5 search:** three distinct states — full list, filtered list, and
  "no friends match *query*" (distinct from "no friends yet"). Clearing the query
  restores the full list; selection persists across filtering.
- **Item 9 payout summary:** absent `payoutTiers` → render **nothing** (current
  behaviour). Empty list (field < 4 runners) → render nothing. Present → summary.
  The "See all payouts" sheet builds its list lazily.
- **Item 21:** the Characters page must render for every `equipped` shape, including
  malformed ones.
- **Item 12:** absent coin figures → number-free copy, never a hardcoded number.
- **Item 19:** overlay never appears when `onEnable == null`, never appears twice,
  never appears in demo mode.

### 6.3 Degrading safely when a field is missing

Every new read in this batch is defensive by construction:

| Read | Missing → |
|---|---|
| `equipped['CHARACTER']` (21) | any non-Map, including null → capybara equipped |
| `prizePool.maxCoins` (7) | already defaults to the compiled mirror (`race_prize_pool.dart:118`) |
| `payoutTiers` (9) | render no summary |
| `referrerCoins`/`refereeCoins` (12) | number-free copy |

### 6.4 iOS + Android in lockstep

Nothing here is platform-specific — no new plugin, no manifest/entitlement change, no
native code. The new PNG (item 18) is a Flutter asset, bundled identically on both.

**Both platforms still get built and verified** before the batch is called done, per
CLAUDE.md — a dependency added for one links into the other.

- iOS: `flutter build ipa --dart-define=BACKEND_BASE_URL=… [ADMOB defines]` (no `--flavor`)
- Android: `flutter build appbundle --flavor <prod|staging> --dart-define=BACKEND_BASE_URL=…`

Version/build number kept in sync across both.

---

## 7. Backward-compatibility & rollout

### 7.1 Deploy order

1. **Backend first.** On prod and staging: `PRIZE_POOL_MAX_COINS=16000`,
   `REFERRAL_REFERRER_COINS=500`; add the referral coin fields if §4.3 finds them
   missing; `pm2 reload`. (Deploy footgun on record: never pipe `migrate deploy`
   through `tail` — it defeats `set -e`. Not applicable here, no migration.)

   > **`.env.example` is gitignored** (`.gitignore:6`, `.env.*`). Edits to it are
   > documentation only — they never reach the droplet via `git pull`. **Both env vars
   > must be set by hand on prod and staging `.env`.** If either file explicitly
   > carries the old value (`PRIZE_POOL_MAX_COINS=3200`,
   > `REFERRAL_REFERRER_COINS=1000`), the raised code defaults will **not** take
   > effect — the explicit env value wins. Check before assuming the deploy worked.
2. **Verify in prod** that `/races/:id` returns `maxCoins: 16000` for a funded race and
   that the referral figures are served, *before* cutting the app build.
3. **Then** ship the app (iOS + Android in lockstep).

### 7.2 What a frozen old client does against the new backend

| Item | Frozen 2.0.1 client behaviour |
|---|---|
| 7 | Server-sent pools/`atMax` correct (read off payload). Local create preview clamps at 3,200 → **under**-promises. Acceptable. |
| 9 | Already renders `payoutTiers` when the list is short; a 150-tier list may render long or be truncated — **no worse than today**, since the backend already pays TOP_HALF. |
| 12 | Ignores the new additive fields; keeps today's number-free copy ("we'll both earn coins"), which stays **true** at 500/500. No frozen client displays a figure the cut falsifies — that is what makes the cut safe. |
| 21 | **Still crashes.** The fix is client-side; a 2.0.1 user with a character equipped keeps white-screening the Characters page until they update. There is no server-side mitigation short of never serving a `CHARACTER` row, which would break the feature. This is the strongest argument for shipping this build promptly. |
| 1–6, 8, 10–20, 22–23 | Frontend-only; old clients keep today's behaviour exactly. |

### 7.3 Feature gating

**None needed.** No item introduces a capability an old client could be handed and
fail on. Specifically:

- Item 7 needs no gate: the payload shape is identical and old clients read the
  ceiling off the payload.
- Item 18's new PNG ships **inside** the binary, so there is no
  testOnly-until-rolled-out concern (unlike a cosmetic served from the catalog).
- Item 9 renders a field prod already emits.

**Kill switches that already exist and cover this batch:** `fundedPrizePoolsEnabled`
(item 7's blast radius), and the env var itself as a soft rollback.

### 7.4 App Store rollout

Phased over ~a week; some users never update. Item 21's crash therefore persists in
the wild for that window — worth an expedited release rather than waiting to batch
with anything else.

---

## 8. Test plan (written FIRST, before any business logic)

Per CLAUDE.md: **integration tests by default**, unit tests only where an integration
test structurally cannot express the property. Never modify or delete an existing
test — surface it instead. Never point tests at the prod DB.

### 8.1 Backend (`test:integration`, never bare `npm test`)

1. **Prize pool ceiling (item 7)** — real HTTP `POST /races` + `GET /races/:id`:
   - 100 players × 14 days → `prizePool.coins === 16000`, `atMax === true`,
     `maxCoins === 16000`
   - 100 × 30 days → 16,000 (flat band above 7 days)
   - 4 × 1 day → 80 (unchanged, guards against over-broad edits)
   - a tournament bracket → still clamped at its own `MAX_CHAMPION_PRIZE`
2. **Seeded challenge preset (item 9)** — assert the renewal job's created daily
   **and** weekly races come back from `GET /races/:id` with
   `payoutPreset: "TOP_HALF"` and a `payoutTiers` list of length **`ceil(field/2)`**.
   This is a **characterisation test** — it should pass before any change, proving the
   backend half of item 9 is already done.

   > **Correction (implementation, 2026-07-27):** an earlier draft of this line said
   > `floor(field/2)`. `gradedSlotCount`
   > (`stepv2-backend/src/modules/races/racePayoutPresets.js:60-62`) pays
   > **`ceil`** — a 9-runner field pays 5 places, not 4. The "150 of 300" example in
   > item 9 is correct only because 300 is even. **The frontend must never derive the
   > paid-place count**; read `payoutTiers.length` off the payload. Odd-sized fields
   > are the case worth testing, since even fields hide the discrepancy.
3. **Referral figures (item 12)**, only if §4.2 adds fields — assert the endpoint
   returns both, and that omitting them (feature-flag off / old config) still yields a
   valid response.

`DATABASE_URL` confirmed to be the local/test database before every run.

### 8.2 Frontend (`flutter test`) — pump the real widget, assert what renders

| # | Test |
|---|---|
| 21 | ShopTab with object-shaped `equipped['CHARACTER']` → Characters page renders, `takeException()` is null |
| 21 | ShopTab with `equipped: {}` → capybara tile shows EQUIPPED |
| 1 | Leaderboard renders no steps/races segmented control; visibility toggle present on the tab and **absent** from Settings |
| 2 | Create screen: powerups toggle on at first paint; payload carries `powerupsEnabled: true`, interval 2000 |
| 3 | No `Icons.monetization_on_rounded` in the shop tree; `CoinGlyph` present in the price strip |
| 4 | Home tab at 320×568 and 375×667 → `EXTRA SPIN` not clipped (`didExceedMaxLines == false`) |
| 5 | Friend picker + race invite: 20 fixture friends, typed query filters; empty-match state; selection survives clearing |
| 6 | Create screen: both segments visible, PRIVATE selected initially, tapping PUBLIC sends `isPublic: true` |
| 7 | `race_prize_pool_test`: (100, 14) → 16,000; existing fixtures still pass |
| 8 | Create screen prize plaque renders no "FUNDED BY BARA" footnote |
| 9 | Race detail: 300-player TOP_HALF → summary shows paid-places and per-head coins, 150 rows **not** in the tree; no `payoutTiers` → no summary, no exception; 4-player → "2 of 4" |
| 10 | `_heroSummary(steps: null)` and `(steps: 0)` → "Fresh day." |
| 11 | `_HomeRaceActionRow` under the dark theme → eyebrow colour is not `roofMid`; token clears 4.5:1 vs night parchment |
| 13 | Profile shows "Streak", not "Goal Streak" |
| 14 | Theme controller: 20:59 light, 21:00 dark, 06:59 dark, 07:00 light |
| 15 | Milestones render 4 nodes + 3 connectors; claimable shows "TAP!"; claimed uses `milestoneCollected` |
| 16 | Share copy assertions for each rewritten string |
| 18 | Hero renders the pace sign; text legible in both palettes (colour assertion) |
| 19 | Overlay presents once, never after dismissal, never when `onEnable == null`; existing demo-mode test (`demo_race_demo_mode_test.dart:170`) still passes **unmodified** |
| 22 | EQUIPPED pill centre-x == tile centre-x |
| 23 | No price chip in the grid; unaffordable strip shows numeric price; tapping opens the sheet; sheet CTA routes by ceiling |

**Known pre-existing failures** (do not attempt to fix in this batch, do not let them
mask new ones): ~35 stale-copy Flutter failures from the random-onboarding-usernames
change, plus the stale races-tab tests from the dark-mode batch. Record the baseline
count before starting and compare after.

**PackageInfo trap:** any `testWidgets` that touches activation analytics must call
`PackageInfo.setMockInitialValues` in `setUp`, or the test hangs silently.

---

## 9. Acceptance criteria / definition of done

- [ ] **21** — Equipping corgi/turtle, then opening Inventory → Characters, renders
      correctly on a debug **and** a release build. No exception in the console.
- [ ] **1** — Leaderboard has no steps/races toggle; visibility toggle lives on the
      leaderboard and is gone from Settings; flipping it still persists server-side.
- [ ] **2** — New race screen opens with powerups on.
- [ ] **3** — No `$` glyph anywhere coins are shown; shop matches the header badge.
- [ ] **4** — "EXTRA SPIN" fully legible at 320pt; the audit table is filled in and
      every listed site verified at 320pt and 375pt.
- [ ] **5** — Search field present in both invite surfaces; filters name and @handle.
- [ ] **6** — Two-segment PRIVATE|PUBLIC control; default PRIVATE; no one can misread it.
- [ ] **7** — 100 players × 14 days previews **and settles** at 16,000. A >200-player
      seeded Weekly still clamps to 16,000. Verified against the real endpoint on
      staging, then prod env confirmed.
- [ ] **8** — No "Funded by Bara / free to enter" on the create screen, the tournament
      create path, or race detail; the pool-grows / maxed-out clauses survive.
- [ ] **9** — Daily and weekly challenges show the approved payout summary (per-head
      coins, paid places, your-position line, "see all payouts" sheet); prod is
      **confirmed** to already be creating them TOP_HALF.
- [ ] **10** — 0 steps at midnight reads "Fresh day." on a build off current `main`.
- [ ] **11** — Every eyebrow label (INVITE/ACTIVE/LIVE/FINISHED/PUBLIC/OPEN) legible in
      night mode; the `roofMid`-as-text sweep is complete.
- [ ] **12** — Referrer reward is 500 in prod config; both figures shown on the
      referral surfaces, sourced from the server, and absent-field fallback verified.
- [ ] **13** — Profile says "Streak".
- [ ] **14** — Automatic theme flips dark at 21:00 local and light at 07:00 local.
- [ ] **15** — Milestones render as the connected chronological track, with dark mode
      intact.
- [ ] **16** — Copy table reviewed and approved by the owner; every listed surface updated.
- [ ] **17** — Races-tab race cards meet the screen edge; header/pill rows keep their
      inset; card borders and drop shadows not clipped at the edge. Before/after
      screenshots attached for owner review.
- [ ] **18** — Sign art generated via the Codex imagegen pipeline (not hand-drawn),
      critique loop passed, pace text sits on the sign clear of the ground brick.
- [ ] **19** — Overlay, not an inline card; "Bara won't ask…" gone; CTA reads
      "ENABLE NOTIFICATIONS"; one-shot dismissal preserved; demo mode still silent.
- [ ] **20** — No `feltLine` rule above the home section headers, in light **or** dark
      mode; sections still read as separated.
- [ ] **22** — EQUIPPED pill centred.
- [ ] **23** — Price chip gone; price in the strip in all states; unaffordable tiles
      open the sheet; sheet CTA routes by the server-served ceiling.
- [ ] Backend integration suite: no **new** failures vs. the recorded baseline.
- [ ] Flutter suite: no **new** failures vs. the recorded baseline.
- [ ] **iOS `ipa` and Android `appbundle` both build**, same version/build number,
      same `--dart-define` backend URL.
- [ ] Backend deployed and verified in prod **before** the app build is submitted.

---

## 10. Open questions for the owner

### Resolved

| # | Decision |
|---|---|
| **D3** | Field cap **is** 100 (`validateRaceConfig.js:64`), verified in code. `PRIZE_POOL_MAX_COINS=16000` is a single global ceiling; large seeded challenges clamp to it rather than minting without bound. |
| **D4** | Remove the "funded / free to enter" copy from **all three** sites: create preview, tournament create variant, and race detail. Pool-grows / maxed-out clauses survive. |
| **D5** | Summary card (per-head coins, paid places, your-position line) + "See all payouts ›" sheet. Layout approved as mocked in item 9. |
| **D6** | **Both sides 500**, stated explicitly. `REFERRAL_REFERRER_COINS` 1000 → 500. |
| **D2** | *Implementer's call, defaulted:* show the search field when the friend list exceeds **8** entries. Below that it is clutter. Trivially changed later; not worth blocking on. |
| **D7** | *Defaulted to the enumerated surfaces:* referral share text, referral screen blurbs, race-invite share, friend picker header, onboarding challenge copy, and backend push bodies. Owner can add surfaces at copy-table review. |

| **D1** | **Resolved by owner:** side gap = the **Races tab**; white line = the **home page**. Both located in code (item 17: 10pt section insets in `races_tab.dart`; item 20: `feltLine`, a 12%-alpha white top border on the home section headers). Item 17 carries a caveat — the insets are long-standing rather than a recent regression, so the full-bleed result should be eyeballed before it is called done. |

### Still open

None. All 23 items are specified.

---

## 11. Revision log

### Pass 1 — fresh-eyes gap pass

1. **Item 9 was mis-scoped.** The original draft treated "change the weekly challenge
   to be a top half payout" as work. It is **already** TOP_HALF for both cadences
   (`seededRaceRenewal.js:58`). Rewrote the item as display-only and added a
   characterisation test that must pass *before* any change, so the assumption is
   proven rather than asserted.
2. **Item 9's 150-row problem surfaced.** A TOP_HALF Daily with 300 players yields 150
   payout tiers. The naive "show the breakdown" reading produces an unusable card.
   Added the summarised design + lazy full-list sheet.
3. **Item 7's blast radius was understated.** Added the explicit note that this is a
   5× increase in max minted coins per race, named the two rollback levers
   (`fundedPrizePoolsEnabled`, and reverting the env var without a deploy), and
   pinned the compat analysis to the exact line where old clients read `maxCoins`
   off the payload (`race_prize_pool.dart:118`) — which is what makes this safe.
4. **Item 7 gained D3.** The proposed ceiling of 16,000 is only "the max the formula
   can produce" if the field cap really is 100. Made that an explicit dependency
   rather than an assumption.
5. **Item 11 was under-scoped.** The bug is not "INVITE"; it is `roofMid` used as a
   *text* colour on night parchment, which kills every eyebrow label on that row.
   Added the sweep requirement and the measured contrast ratio (≈1.2:1).
6. **Item 4 was under-scoped.** "Extra spin is cut off" is one symptom of
   `PillButton`'s fixed 32pt horizontal padding + `maxLines: 1` ellipsis. Moved the
   fix into the widget, added the required audit table, and flagged that the
   `fontSize: 10`/`13` overrides already in the codebase are prior work-arounds for
   the same defect — including `race_alert_opt_in_card.dart:110`, which item 19 also
   touches.
7. **Item 15 gained a deliberate deviation.** A verbatim revert would restore
   `AppColors.success` and re-break dark mode; `milestoneCollected` must be kept.
8. **Item 19 gained two hard constraints** that a naive "make it an overlay" rewrite
   would have destroyed: the one-shot `race_alert_card_dismissed_v1` contract (an
   overlay on every open is worse than the inline card), and the demo-mode test at
   `demo_race_demo_mode_test.dart:170` that must keep passing untouched.
9. **Item 10 was not a bug.** Already fixed in `54f945d`, unshipped. Reclassified as
   verify-only, with an escalation path if it still reproduces on `main`.

### Pass 2 — second independent gap pass

10. **Item 21's root cause was found rather than assumed.** The first draft said
    "needs reproduction". Re-reading `shop_tab.dart:896` against
    `shopCosmetics.js:49-54` proved the type mismatch: `equipped[slot]` is an object,
    cast as `String?`. Replaced the speculative repro plan with the exact fix and the
    reason no test caught it (fixtures seed `{}`/`null`, never the real shape).
    **This is the highest-value change in the batch and no longer needs investigation
    time.**
11. **Item 23's premise was partly already true.** "Let them click into it" already
    works — `onTap` and `onStrip` both open the sheet, a deliberate anti-misclick
    change. Narrowed the item to what actually changes (delete the chip, price in the
    strip) and added verification that `stripEnabled` stays true when unaffordable.
12. **Item 23's "that 20" was pinned to config.** The ad-unlock ceiling is
    server-served (`adUnlock.maxShortfall`), not a constant — added an explicit
    do-not-hardcode note.
13. **Item 3 hit a widget limitation.** `PillButton` accepts `IconData`, not a
    `Widget`, so a PNG coin cannot be dropped in. Added the `leading` param (additive,
    does not disturb the dozens of existing `icon:` call sites) and chose a **static**
    glyph over `SpinningCoin` — a grid of 20 spinning coins is needless animation cost.
14. **Item 18 was at risk of violating a hard rule.** The obvious implementation is a
    `CustomPainter` sign, which CLAUDE.md explicitly prohibits. Rewrote the item as
    art-first through the Codex imagegen pipeline, and noted that the existing
    `TrailSign` widget is a parchment card, not a sign, so it cannot be reused.
    Also noted the sign is a fixed-colour PNG, so its text colour must not be a theme
    surface token.
15. **Item 1 gained a compile-break warning.** `requestedType` is a public constructor
    param; removing it breaks callers. Made "check every call site first" explicit, and
    clarified that the *scope* toggle (`_ScopeIconToggle`) is a different control that
    stays — an easy thing for an implementer to delete by mistake.
16. **Item 22 gained a collision note.** Centring the badge naively would also centre
    the `xN` quantity badge; specified a `badgeAlignment` param instead of string-
    matching `'EQUIPPED'`.
17. **§7.3 was rewritten from "TBD" to "none needed", with reasons per item.** The
    default instinct on this repo is to gate everything `testOnly`; here nothing
    warrants it, and saying so explicitly (with the item-18 rationale that a bundled
    PNG is not a served cosmetic) prevents a pointless gate.
18. **§8 gained the two known traps** from prior batches: the pre-existing failure
    baseline (~35 stale-copy Flutter failures) must be recorded *before* starting so it
    cannot mask new breakage, and `PackageInfo.setMockInitialValues` is required in
    `setUp` for any test touching activation analytics.
19. **§7.2 gained an honest row for item 21:** there is no server-side mitigation for
    frozen clients. That is the argument for an expedited release, and it belongs in
    the compat table rather than being glossed over.

### Pass 3 — post-interview fold-in

20. **D3 was answered by reading the code, not by asking.** `validateMaxParticipants`
    caps user races at 100, confirming 16,000 as the formula's true max. But the same
    read surfaced a gap the owner's framing ("just remove the cap") did not cover:
    **seeded daily/weekly races bypass that validator entirely** and can field 300+.
    Uncapping would have made total minting scale without bound as signups grow.
    Escalated it as a decision; owner chose one global 16,000 ceiling.
21. **D6 turned a copy item into an economy change.** "Both 500" means
    `REFERRAL_REFERRER_COINS` drops 1,000 → 500 — a second backend change, a 33% cut
    in referral cost, and a sharer who no longer out-earns the joiner. Promoted to
    §4.2, flagged the consequence plainly, and documented *why it is safe under frozen
    clients*: today's copy promises no number, so nothing in the wild is falsified.
    Had the shipped copy said "1,000", this cut would have been a broken promise.
22. **D4's "remove all three" needed a caveat the question did not carry.** The race
    detail strings are two-branch — the at-max and pool-grows clauses are bundled into
    the same sentence as the objectionable lead-in. Specified keeping the informative
    clauses and dropping only the lead-in, plus rendering nothing (not an empty line)
    where that empties the string.
23. **D2 and D7 were closed with defaults rather than escalated.** Neither changes the
    shape of the work and both are trivially adjustable after the fact; blocking a
    23-item batch on a search-field threshold would be poor use of the owner's time.
    Both are recorded as defaults, not silent choices.

### Pass 4 — D1 resolved, items 17 and 20 unblocked

24. **Item 20 root-caused.** `feltLine = Color(0x1FFFFFFF)` (`styles.dart:124`) is a
    **12%-alpha white** hairline drawn as a full-width `Border(top:)` on both home
    section headers (`home_tab.dart:1361`, `:1827`). It has **no night override**, so
    it is equally present in dark mode. A leftover from the older felt-table look,
    made redundant by the current card borders + `_SectionTick`.
25. **Item 17 specified with an explicit caveat instead of false confidence.** The
    Races tab root is *already* full-bleed; the gap is 10pt per-section insets inside
    the scroll view. But `git log -S` shows those insets are long-standing, **not** a
    recent regression — so this is a preference change, not a bug fix, and the spec
    says so rather than inventing a culprit commit. Also carved out the header/pill
    rows (`:611`, `:953`), which should keep their inset: a pill row touching the
    screen edge reads as broken, not full-bleed.

---

## 12. Item 16 copy table

Filled in during implementation (frontend agent, items 5/12/16). Every string
carrying a coin figure has **three** forms, because the figures are read off the
wire (`referrerCoins` / `refereeCoins`, §4.3) and may be absent on an older
backend: *equal figures*, *unequal figures*, and *no figures served*. The
number-free form is the fallback — never a hardcoded amount.

### Referral screen (`lib/screens/referral_screen.dart`)

| Surface | Old string | New string |
| --- | --- | --- |
| Header blurb (`:246-255`) | "Share your link. When a friend finishes their first race, you BOTH earn coins." | **equal:** "Send your link. When your friend finishes their first race, you each pocket 500 coins."<br>**unequal:** "Send your link. When your friend finishes their first race, you pocket 1,000 coins and they get 500."<br>**no figures:** "Send your link. Coins land in both bags when your friend finishes their first race." |
| Share text, steps known (`:552-555`) | "I'm at 8,432 steps today — think you can beat me? Race me on Bara with code X and we'll both earn coins when you finish your first race: URL" | "I'm at 8,432 steps today. Think you can beat that? Race me on Bara with code X — **we'll each pocket 500 coins** once you finish your first race: URL" |
| Share text, steps unknown (`:556-557`) | "Bet you can't out-step me. Race me on Bara with code X and we'll both earn coins when you finish your first race: URL" | "Bet you can't out-step me. Race me on Bara with code X — **we'll each pocket 500 coins** once you finish your first race: URL" |
| Share reward clause — unequal | — | "I'll pocket 1,000 coins and you'll get 500" |
| Share reward clause — no figures | — | "there's a coin drop in it for both of us" |
| Redeem-success toast (`:141`) | "You're in! Finish your first race to earn coins." | **figure known:** "You're in. Finish your first race and 500 coins are yours."<br>**no figure:** "You're in. Finish your first race and the coins are yours." |

### Friend picker (`lib/screens/friend_picker_screen.dart`)

| Surface | Old string | New string |
| --- | --- | --- |
| Header title (`:54`) | "CHALLENGE A FRIEND" | "PICK YOUR RIVAL" |
| Header subtitle (`:62`) | "Pick someone to battle this week" | "Tap a friend and the race is on." |

### Race invite (`lib/screens/race_invite_screen.dart`)

| Surface | Old string | New string |
| --- | --- | --- |
| Header subtitle | "Select friends to race against" | "Tap everyone you want in this race." |
| Empty state | "No friends available to invite" | "Nobody left to invite right now." |
| Search no-match (NEW, item 5) | — | "No friends match \"<query>\"" / "Check the spelling, or clear the search to see everyone." |

### Get Coins hub (`lib/screens/get_coins_screen.dart`)

| Surface | Old string | New string |
| --- | --- | --- |
| Invite row subtitle | "You both earn coins when a friend joins with your link." *(also factually wrong — coins are paid on the friend's first finished race, not on joining)* | **equal:** "You each pocket 500 coins when a friend finishes their first race."<br>**unequal:** "Pocket 1,000 coins when a friend finishes their first race. They get 500."<br>**no figures:** "Coins land in both bags when a friend finishes their first race." |
| Invite row button | "SHARE INVITE LINK" | **unchanged** — see report: the label is inaccurate (it opens the referral screen, it does not share) but `test/get_coins_screen_test.dart:331` taps it by text and existing tests must not be edited. Owner call. |

### Onboarding (`lib/screens/onboarding_flow.dart`)

| Surface | Old string | New string |
| --- | --- | --- |
| Auto-enrolled headline (`:876`) | "Entered in the Daily & Weekly challenge" | "The Daily and Weekly are yours to win" |
| Auto-enrolled dock body | "We saved you a spot in both races and dropped 3 mystery boxes in your bag. You can turn auto-join off anytime on the Races page." | "We saved you a spot in both and dropped 3 mystery boxes in your bag. Turn auto-join off anytime on the Races page." |
| Referral welcome body (`:627-630`) | "Finish your first race and you'll both earn coins — 500 to get you started." | **equal:** "Finish your first race and you each pocket 500 coins — yours to spend right away."<br>**referee figure only:** "Finish your first race and 500 coins are yours."<br>**no figures:** "Finish your first race and the coins start landing." |

### Referral rules (`lib/screens/referral_rules_screen.dart`)

| Surface | Old string | New string |
| --- | --- | --- |
| "How it works" | "…you both earn coins." | "…you each earn coins." (register stays plain — this is a Play-required disclosure, not marketing) |

### Owned by other agents — rows for review only, NOT changed by this agent

| Surface | Old string | Note |
| --- | --- | --- |
| `lib/screens/race_detail_screen.dart` race-invite share copy | (see file) | **owned by race-detail agent** |
| `lib/screens/race_detail_screen.dart:1394` toast | "No friends available to invite" | **owned by race-detail agent** — race-invite screen's copy of this string was reworded, so the two now diverge; align if desired |
| `lib/widgets/coach_tip.dart:21` | "Add friends to race them. Invite one and you both earn coins." | **Surface the spec missed.** Carries the banned "both earn coins" construction. Left unchanged: `test/tutorial_revamp_test.dart:392` asserts it verbatim and existing tests must not be edited. Owner call. |
| Backend push/notification invite bodies | `stepv2-backend/src/modules/notifications/` | **owned by backend agent** |
