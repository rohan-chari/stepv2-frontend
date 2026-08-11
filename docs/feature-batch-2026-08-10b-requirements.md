# Feature batch 2026-08-10 (part 2) — requirements

Six items. Two are bug fixes with no new surface (items 4, 6), three are UI
additions/moves (2, 3, 5), one is a new ad-funded feature with a new endpoint
(item 1).

| # | Item | Backend | Frontend | Gate |
|---|------|---------|----------|------|
| 1 | Reroll-all after OPEN ALL (one rewarded ad) | new endpoint | new UI | `ADS_BOX_REROLL_ENABLED` (existing) + `boxRerollBatch` advertisement |
| 2 | Discard modal must say when the daily coin cap is hit | additive field | copy | none (additive) |
| 3 | Home: race invite moves above Today's Coins | none | move | none |
| 4 | Reroll populates inventory before the reel lands | none | fix | none |
| 5 | Home: feedback entry point | none | new section | none |
| 6 | Rainstorm doesn't halve a buffed multiplier | fix | none | `RAINSTORM_MULTIPLICATIVE_ENABLED` (new, ships OFF) |

---

## Item 1 — REROLL ALL after OPEN ALL

### Summary & user story

As a racer who just opened all my boxes at once and got a bank of junk, I want
to watch one rewarded ad and re-roll **every** box from that batch, so the
Open All flow has the same second chance the single-box flow has.

Today `CaseOpeningScreen` offers a REROLL button after the reveal
(`lib/screens/case_opening_screen.dart:575`), wired to
`_rerollBoxPowerup` in `lib/screens/race_detail_screen.dart:4985`, which shows
one rewarded ad and calls `POST /races/:raceId/powerups/:powerupId/reroll`.
`MultiCaseOpeningScreen` (`lib/screens/multi_case_opening_screen.dart`) has no
reroll at all — `onReroll` is simply never passed to it.

### Scope

**In:** one REROLL ALL button on the Open All **summary** card (the `_Phase.done`
state), one rewarded ad, one ad grant, all eligible boxes from that batch
re-rolled together, a disclaimer stating that it rerolls all boxes, the reels
re-spun to the new results.

**Out (non-goals):**
- Per-box reroll inside Open All (the user chose one-ad-for-all).
- Rerolling a second time. One reroll per box, server-enforced via
  `racePowerup.rerolledAt` — a box already rerolled by the single-box flow is
  simply skipped by the batch.
- Any change to the single-box reroll's behavior, price, or odds.
- Android. `AdService.boxRerollAdUnitId` resolves to `''` on Android without
  `ADMOB_BOX_REROLL_AD_UNIT_ID_ANDROID`, and `boxRerollSupported` is then false,
  so the button compiles out exactly as the single-box one does. iOS-first, same
  as item 11 of batch 2026-08-08.

### Decision (user, 2026-08-10)

**One ad → rerolls every eligible box in the batch.** All-or-nothing: the user
cannot cherry-pick which boxes to keep. This is what the disclaimer says.

### API contract

**New:** `POST /races/:raceId/powerups/reroll-batch`

Request:
```json
{ "powerupIds": ["pw_1", "pw_2", "pw_3"], "localDate": "2026-08-10" }
```
- `powerupIds` — the ids the client just opened in this batch. Required,
  non-empty array of strings. **De-duplicated first, then truncated to
  `REROLL_BATCH_MAX_COUNT`** (a named constant in the new command — NOT
  `openMysteryBoxBatch`'s `DEFAULT_MAX_COUNT`; its value is set by the
  `game-analyst` review, see §Economy note). Ids past the cap are returned with
  `skipped: "OVER_CAP"` and their unchanged type/rarity — never silently
  dropped, so "every owned id appears in `results`" holds without contradiction.
- `localDate` — optional, same validation and semantics as the single reroll
  (`isValidLocalDate` + `withinOneDayOfServer`, `adjacentDates` lookup). Absent
  → server derives from the user's stored zone.

Success `200`:
```json
{
  "results": [
    { "powerupId": "pw_1", "type": "RED_CARD", "rarity": "RARE",   "rerolled": true },
    { "powerupId": "pw_2", "type": "PROTEIN_SHAKE", "rarity": "COMMON", "rerolled": true },
    { "powerupId": "pw_3", "type": "LEG_CRAMP", "rarity": "UNCOMMON", "rerolled": false,
      "skipped": "NOT_HELD" }
  ],
  "rerolledCount": 2
}
```
- **The row key is `powerupId`, not `id`** — matching its sibling
  `open-batch` (`openMysteryBoxBatch.js:68,80`), which is what already
  populates `MultiCaseOpeningScreen._results`. The single reroll returns `id`;
  this endpoint deliberately does not copy that, because the client joins these
  rows against `_results` entries keyed `powerupId`. An `id`/`powerupId`
  mismatch would fail silently — every reel keeps its old result and no error
  is shown — which is the hardest failure mode to catch in QA. The join is
  `response.powerupId == _results[i]['powerupId']`.
- Every requested id that belongs to the caller appears in `results`, in request
  order, so the client can map result→reel by `powerupId`.
- `rerolled: false` + `skipped: <reason>` for a box that could not be rerolled.
  Reasons mirror the single command's guards: `NOT_HELD` (status ≠ HELD, used,
  null rarity, upgraded), `ALREADY_REROLLED`, `OVER_CAP`. **`NOT_FOUND` was
  specified but is deliberately never emitted** (implementation note,
  2026-08-10): an unknown id is indistinguishable from another user's id without
  an existence oracle, and foreign ids must be omitted entirely — so both are
  omitted from `results`. The client already handles this ("leaves any reel
  whose id is missing on its original result"). For a skipped row the
  `type`/`rarity` returned are the row's **current** (unchanged) values, so the
  client re-renders it as-is rather than blanking it.
- Foreign ids (`userId`/`raceId` mismatch) are **omitted entirely** — never
  echoed, never counted. They must not confirm another user's powerup exists.

Errors:
| Status | code | When |
|---|---|---|
| 503 | `DISABLED` | `ADS_BOX_REROLL_ENABLED` not `"true"` |
| 400 | `INVALID_LOCAL_DATE` | malformed / >1.5 days from server |
| 400 | — | `powerupIds` missing, not an array, or empty |
| 400 | — | race not ACTIVE |
| 403 | — | caller not a participant |
| 409 | `AD_NOT_VERIFIED` | no unconsumed `box_reroll` grant yet (SSV lag) |
| 409 | `NOTHING_TO_REROLL` | every requested id is ineligible |

**`NOTHING_TO_REROLL` is checked BEFORE the grant is consumed.** The eligibility
sweep runs first over all ids; if zero survive, the ad watch is not burned. This
mirrors the single command's ordering ("ALL of it runs before the ad credit is
consumed").

**One grant, N rerolls.** The batch consumes exactly one `adRewardGrant` row of
kind `box_reroll` via the same find + CAS `updateMany` the single command uses.
This is the deliberate economic change: N boxes per watch instead of 1.

**Advertisement.** `getRaceProgress` gains `powerupData.boxRerollBatch = true`,
set under the **same** condition as the existing `boxReroll` flag
(`supportsAds && adsBoxRerollEnabled()`, `src/modules/races/queries/getRaceProgress.js:870`)
— key OMITTED, never `false`, when off.

### Backward compatibility with older app versions

- The endpoint is **new**. No shipped binary calls it. A frozen client is
  unaffected by its existence.
- `boxRerollBatch` is a **new additive key** on `powerupData`. Frozen clients
  read unknown keys and ignore them (they parse `powerupData` as
  `Map<String, dynamic>`).
- The new app must **feature-detect**: it shows REROLL ALL only when
  `powerupData['boxRerollBatch'] == true` (literal true) **and**
  `AdService.boxRerollSupported`. Against a backend that predates this batch the
  key is absent → button hidden → Open All behaves exactly as it does today.
  A 404 from the endpoint is additionally caught and surfaced as "Reroll isn't
  available right now" rather than a crash.
- The new app must **not** assume `results` ordering or completeness; it maps by
  `id` and leaves any reel whose id is missing on its original result.
- Wave-5 gate: the batch threads `supportsPowerups5` from `X-Client-Features`
  into every roll, exactly like `open-batch` and the single reroll. Forgetting
  this would make REROLL ALL a way to land a type this binary can't use.

### Data model / migrations

**None.** Reuses `race_powerups.rerolledAt` and `ad_reward_grants`.

### Backend implementation path

1. `src/modules/powerups/commands/rerollMysteryBoxBatch.js` (new).
   Structure it as `buildRerollMysteryBoxBatch(dependencies)` returning the
   command, matching `rerollMysteryBox.js` and `openMysteryBoxBatch.js`.
   Order of operations — **this order is the spec**:
   a. Kill switch → 503 `DISABLED`.
   b. Validate `powerupIds` (array, non-empty) → 400.
   c. Validate/derive `localDate` (reuse the single command's `isValidLocalDate`
      / `withinOneDayOfServer` / `localDateFor` — **export them** from
      `rerollMysteryBox.js` rather than copy-pasting; three divergent copies of
      a date guard is the `renderMetadata` incident's shape).
   d. Load race (must be ACTIVE → 400) and participant (→ 403).
   e. Eligibility sweep over the (capped, de-duplicated) ids: for each, load the
      row, drop foreign/missing, classify eligible vs `skipped`.
   f. If no eligible ids → 409 `NOTHING_TO_REROLL`, **grant untouched**.
   g. Find + CAS-consume ONE `box_reroll` grant → 409 `AD_NOT_VERIFIED` on
      either miss.
   h. Load participants once, compute `rawPositionFor` once, `buildRollContext`
      once, `balance.getSnapshot()` once — then roll each eligible box with the
      same Fanny-Pack rejection loop, `resolveNullRoll`, and
      `canonicalRarityFor` stamp the single command applies. **One position/
      context for the whole batch**: the rolls are simultaneous from the
      player's point of view, and re-deriving position per box would let the
      batch's own writes shift the odds mid-loop.
   i. Persist each with the same conditional `updateMany`
      (`status: "HELD", rerolledAt: null`); a row that loses the CAS becomes
      `skipped: "ALREADY_REROLLED"` in the response rather than failing the
      whole batch. **The grant is not refunded** in that case — it was already
      consumed and at least one other box rerolled; if EVERY row loses its CAS,
      still return 200 with `rerolledCount: 0` (the ad is spent — the only
      way to reach this is a concurrent duplicate request, which is the client
      double-firing, not the user being cheated).
   j. Emit one `POWERUP_REROLLED` audit event **per rerolled box**, same hidden
      event type as the single path (it is filtered out of the visible feed by
      `getRaceFeed` and `HIDDEN_SYSTEM_EVENT_TYPES`) — do NOT invent a new event
      type, which would appear in the feed and leak box contents.
   k. No `invalidateRaceProgress` (inventory is read live per viewer, same
      reasoning as the single command).
2. Export from `src/modules/powerups/index.js`.
3. Route `POST /:raceId/powerups/reroll-batch` in
   `src/modules/races/routes.js`, directly after the single reroll handler
   (line 843) and mirroring the existing `open-batch` route's shape. Routing
   note: this is safe next to `/:raceId/powerups/:powerupId/reroll` because
   every parameterized powerup route carries a further path segment, and no
   bare `POST /:raceId/powerups/:powerupId` route exists today — verify that
   still holds before adding, since a bare one would shadow this path.
   Thread `timeZone: req.user.timezone || req.timeZone || null`,
   `localDate: req.body?.localDate`,
   `supportsPowerups5: req.clientFeatures?.has("powerups5") ?? false`.
4. `getRaceProgress.js` — add `powerupData.boxRerollBatch = true` inside the
   existing `if (supportsAds && adsBoxRerollEnabled())` block at line 870.

### Frontend plan

1. `BackendApiService.rerollPowerupBatch({identityToken, raceId, powerupIds,
   localDate})` → `POST /races/$raceId/powerups/reroll-batch`.
2. `MultiCaseOpeningScreen` gains
   `final Future<List<Map<String, dynamic>>?> Function(List<String> powerupIds)?
   onRerollAll;` — **null by default**, so nothing else that builds this screen
   (there is nothing else today) acquires the button implicitly.
3. Summary card (`_buildSummary`, line 308) gains, above Continue and only when
   `onRerollAll != null && !_rerollUsed && _rerollableIds.isNotEmpty`:
   - a `PillButton` keyed `Key('open-all-reroll-button')`, label `REROLL ALL`,
     `loading: _rerollingAll`, with the ad-badge treatment the single-box button
     uses;
   - directly beneath it, the disclaimer, keyed
     `Key('open-all-reroll-disclaimer')`:
     **"Watch an ad to reroll ALL of these boxes. Every roll is replaced — the
     new rolls are final."**
   - Continue is **disabled** while `_rerollingAll` is true, and the summary is
     non-dismissable during that window (`_canDismiss` must return false), so a
     backgrounded ad can't leave a half-applied batch behind a popped route.
4. `_rerollableIds` = the ids of results that are plausibly rerollable from the
   client's view: `powerupId != null && autoActivated != true &&
   alreadyOpened != true`. This is a **display filter only** — the server
   re-checks everything. An auto-activated Fanny Pack is already USED and would
   come back `skipped`.
5. On tap → `onRerollAll(_rerollableIds)`:
   - null result (user backed out of the ad / error already toasted) → clear
     `_rerollingAll`, leave the summary exactly as it was.
   - non-null → set `_rerollUsed = true`, merge each returned `powerupId` onto the
     matching `_results` entry (`type`, `rarity`), **leave unmatched entries
     untouched**, then drop back to `_Phase.revealing`, rebuild the reel stack
     with a fresh `_completed = 0`, and pulse `_trigger` next frame — the user
     watches the new results land, exactly like the single-box reroll's
     re-armed reel.
   - `widget.onResults` fires again from `_onReelComplete` once the second bank
     lands, so the host's optimistic inventory is corrected to the new types.
     **`onResults` must therefore be idempotent per id** — it already is
     (`_optimisticallyApplyBoxOpen` overwrites the row by id).
   - **Reel remount (REQUIRED, architect S1):** each reel's key must include a
     roll-generation counter — `ValueKey('$powerupId:$rollGen')`, not today's
     `ValueKey('reel_$i')` — so the second bank is a genuine remount. If Flutter
     reuses the existing reel `State`, `_onReelComplete` never fires again,
     `_phase` stays `revealing` and `_canDismiss` stays false: a permanently
     stuck, undismissable overlay.
   - **The disclaimer must not lie when capped:** if the eligible-id count
     exceeds `REROLL_BATCH_MAX_COUNT`, it reads "Watch an ad to reroll **N of
     these boxes**…" instead of "ALL of these boxes".
6. `race_detail_screen.dart`:
   - `bool get _boxRerollBatchEnabled` — mirrors `_boxRerollEnabled` but reads
     `_powerupData?['boxRerollBatch'] != true → false`. It is a hand-copy of an
     existing getter, so copy **both** guards: the leading
     `if (widget.demoMode) return false;` (line 4953) and the
     `widget.boxRerollAdController != null || AdService.boxRerollSupported`
     tail. Dropping the demo guard would surface REROLL ALL in the tutorial the
     moment the separate demo OPEN ALL suppression (line 4829) ever changes.
   - `_rerollAllBoxPowerups(List<String> ids)` — same ad-then-call shape as
     `_rerollBoxPowerup`: `isSupported` → `load` → `isReady` → `showAndAwaitReward`
     → `_rerollBatchWithRetry` (the same bounded 5×2s `AD_NOT_VERIFIED` retry,
     with the SAME `localDate` captured before the retry loop) → warm the next
     ad. Error copy: `NOTHING_TO_REROLL` → "Nothing left to reroll."; anything
     else → "Couldn't reroll those boxes."
   - **Do not call `_loadProgress()` before the reels land** — see item 4; the
     refresh happens in `_openAllBoxes`'s existing `finally`.
   - Pass `onRerollAll: _boxRerollBatchEnabled ? _rerollAllBoxPowerups : null`
     into `MultiCaseOpeningScreen`.
7. **`DemoRaceApiService` must override `rerollPowerupBatch` (REQUIRED,
   architect R3).** `lib/demo/demo_race_api_service.dart:328-342` already
   overrides `rerollPowerup` for exactly this reason, with the comment: "an
   un-overridden call site is a live HTTPS request against prod with a
   fabricated race id, whether or not today's UI can reach it." Add the
   matching override returning `const {}`, carrying the same comment, so the
   §8.4 network-leak guard test stays honest.
8. Degradation: absent `boxRerollBatch`, absent ad unit, demo mode, or an
   injected-controller-free test → `onRerollAll` is null → the summary renders
   byte-identically to today.
9. **Storage note (architect S4):** the batch writes only `race_powerups` (N
   single-row `updateMany`s keyed by id) and `ad_reward_grants` — never
   `race_participants`. It is not a new request-path bulk writer and does not
   need the C0 resolution queue. Recorded so a future reviewer doesn't
   re-litigate it.
10. **Lost-response case (architect S5, accepted):** if the HTTP response is
    lost after a successful batch, the client shows the old reels and an error
    toast, then `_openAllBoxes`'s `finally` refreshes the inventory to the new
    types after the overlay closes. Self-healing but confusing. On a **timeout
    specifically**, the toast reads "Reroll may have completed — check your
    boxes."

### Economy note — `game-analyst` verdict: **SOUND**, no repricing needed

`REROLL_BATCH_MAX_COUNT = 8`. This is a **performance** bound, not a balance
one: the request does one `findById` per id on a single-vCPU box, and the
inventory ceiling makes anything above 8 physically unreachable (3 base slots +
max observed `powerup_slots` 4 + 1 queued = 5). De-duplicate before the sweep.

Why no cap is needed for balance — the counter-intuitive result is that
**all-or-nothing batching is per-box *worse* than the existing single reroll**,
because it forfeits cherry-picking. Simulated on live `balance_config` v4 with
the backend's own `typeOddsForPosition` (4×10⁵ trials/cell):

| Position | 1 ad = 1 box (today) | N=2 | N=3 | N=4 | N=5 |
|---|---|---|---|---|---|
| P1 | +470 steps/ad (470/box) | +643 (322/box) | +777 (259) | +892 (223) | +1,000 (200) |
| P6 | +686 (686/box) | +939 (470) | +1,158 (386) | +1,340 (335) | +1,503 (301) |

Per-**ad** value rises 1.37×–2.19×; per-**box** value *falls* 32–57%.

Box-hoarding to inflate N is **not** a dominant strategy: ad watches are
uncapped, so an optimizer willing to watch 4 ads gets 4 × 470 = 1,880 by
rerolling singly, beating +892 from one batched ad. Hoarding also costs all
three slots for ~1.4 median days and risks forfeiting overflow crossings
(2,486 forfeits/30d, each worth 1,100–1,550 steps). Batching is a **time**
saver, never the value-maximizing line.

Also verified: store-bought powerups carry `rarity = NULL` and are rejected by
the reroll guard, so coins cannot be laundered into box rolls. The reroll +
discard coin loop is bounded by the unchanged 40-coin/local-day discard cap —
batching only cuts the ads needed to max that cap from ~7 to ~2.

Measured reality check: the spec's "up to 20" was never reachable. Real
open-burst sizes over 30d (n=10,288) are mean 1.24, and mean 2.32 given ≥2.

---

## Item 2 — discard modal must show when the daily coin cap is hit

### Summary

`_confirmAndDiscardPowerup` (`lib/screens/race_detail_screen.dart:1980`) already
has the copy — `"Daily discard bonus reached — you'll get 0 coins."` — gated on
`_discardCapRemaining == 0`. But `_discardCapRemaining` is **only ever assigned
from a discard response** (line 2026). On a fresh screen it is `null`, so the
first discard after the cap is hit shows "Discard X for 10 coins?" and then pays
0. The dialog lies exactly once per screen visit, every time.

### Fix

Serve the headroom in `powerupData` so the dialog knows before the first discard.

**API (additive):** `powerupData.discardCapRemaining: <integer ≥ 0>` in
`getRaceProgress`.

- Computed from the same `consumedToday` + `discardDailyCap()` the award uses
  (`src/modules/powerups/services/discardRewards.js`) — export a small
  `discardCapRemainingFor({ userId, timezone })` from that module so there is
  exactly one implementation of the day-boundary SQL. **Do not re-derive the
  local day in JS** (prod datetimes are tz-naive; see the module's comment).
- Timezone: `req.user.timezone || req.timeZone || null`, same precedence as the
  discard route — never the spoofable header alone.
- **Placement (REQUIRED, architect R5).** NOT next to `discardPrices` at line
  859 — `slotPowerups`, the only thing that can answer "does this viewer hold a
  HELD row?", isn't read until line 897. Compute **after line 903**, gated on
  `powerupData.inventory.some(p => p.status === "HELD")`. Computing at 859
  either costs a second query or silently drops the guard.
- **Sargability (REQUIRED, architect R6).** `consumedToday`'s predicate
  `(created_at AT TIME ZONE 'UTC' AT TIME ZONE $tz)::date = …`
  (`discardRewards.js:62-68`) wraps `created_at` in an expression, defeating
  range pruning — it scans every `powerup_discard` row the user has ever
  accumulated. Fine on a button press, not on the hottest endpoint on a
  one-vCPU box, and a memo doesn't help the users with the longest ledgers. Add
  a sargable pre-filter `AND created_at >= now() - interval '3 days'` ahead of
  the tz-date equality, in **both** `consumedToday` and the extracted
  `discardCapRemainingFor`.
- **Caching (REQUIRED, architect R5).** Go through the existing derived-data
  layer properly, not an ad-hoc key:
  - add `redisCacheDiscardCapEnabled: false` to `KNOWN_FLAGS`
    (`src/shared/config/appSettings.js`),
  - add `userDiscardCap(userId)` to `src/shared/cache/cacheKeys.js` under a
    `v1:user:discardcap` prefix — **keyed on `userId` alone**, no localDate
    component (architect S2: at a 60s TTL it buys nothing and introduces a
    JS-local-date vs SQL-local-day disagreement at midnight; the TTL
    self-heals the rollover),
  - read via `derivedCache.cachedRead({key, prefix, ttlSeconds: 60, enabled,
    load})`, and invalidate via `derivedCache.invalidate` in `discardPowerup`.
- **Redis is a pure optimization, never a precondition.** The earlier draft said
  "if the cache is unavailable the key is simply omitted" — that is backwards.
  It would mean the feature does not exist in dev, in CI, or during a Redis
  outage, and it would fail backend test 1 outright, since the suite runs with
  `REDIS_URL` unset. **Always compute** (behind the HELD guard); `cachedRead`
  already falls back to Postgres on any Redis error.
- **Overlay-only (architect S3).** `discardCapRemaining` lives in the per-viewer
  overlay and must never enter the shared C3 `v1:race:progress` snapshot or its
  pinned field allowlist (`getRaceProgress.js:949,1293`). Structurally safe
  today because `powerupData` is overlay-only — stated so it stays that way.

### Frontend

- `int? get _serverDiscardCapRemaining` reading `powerupData['discardCapRemaining']`
  defensively (`is num` → `toInt()`, else null).
- `_discardCapRemaining` becomes: the discard-response value when we have one
  (it is newer), else the server-served value. Concretely, keep the existing
  field as a "last write wins" override and fall back:
  `_discardCapRemaining ?? _serverDiscardCapRemaining`. Introduce
  `int? get _capRemaining` returning that, and use it in **both**
  `_discardPriceTrailing` (line 1962) and `_confirmAndDiscardPowerup` (line 1983).
- **Third price surface (ui-test-planner, REQUIRED):** `race_detail_screen.dart:2737`
  passes `discardPriceCoins: _discardCapRemaining == 0 ? null : _discardPriceFor(powerup)`
  into `lib/widgets/pocket_watch_sheet.dart`. This call site must use the same
  `_capRemaining` and `min(price, cap)` clamp as the other two, or the Pocket
  Watch sheet keeps promising the full price. Three call sites, one rule.
- **Override lifetime (REQUIRED, architect R7).** Do **not** clear the local
  override on every progress payload. With a 60s memoized server value that
  re-introduces the exact bug being fixed: discard → response `capRemaining: 0`
  → override 0 → next poll lands a payload built from a cache entry populated
  *before* the discard → override cleared → `_capRemaining` reads the stale
  non-zero value → the very next dialog promises coins it won't pay.
  Invalidation-on-discard narrows this to a race rather than a certainty, but
  the override exists precisely because the served value can be stale.
  Correct rule: **stamp the override with the local date it was written on**
  (`_discardCapDate`) and drop it only when `DateTime.now()`'s local date
  differs. That survives day rollover without trusting a stale cache read.
- **Partial-award copy (new):** the backend pays `min(price, capRemaining)`.
  When `0 < capRemaining < price`, the dialog currently promises the full price.
  Body becomes: `"Discard $name for $capRemaining coins? (daily bonus almost
  used up)"`. Three bodies today become four:
  | condition | body |
  |---|---|
  | unopened box | "Discard this mystery box? You won't get coins for unopened boxes." (unchanged) |
  | `cap == 0` | "Daily discard bonus reached — you'll get 0 coins." (unchanged) |
  | `0 < cap < price` | "Discard $name for $cap coins? Your daily discard bonus is nearly used up." |
  | otherwise (incl. cap unknown) | "Discard $name for $price coins?" (unchanged) |
- The `+N 🪙` trailing tag on the DISCARD button uses the same clamped number
  (`min(price, cap)`) when the cap is known, and hides at 0 as it does today.
- **Degradation:** an older backend sends no `discardCapRemaining`; `_capRemaining`
  is null; every branch falls through to today's exact copy. No new crash surface.

---

## Item 3 — home: race invite above Today's Coins

### Summary

Home's sections are built in `lib/screens/tabs/home_tab.dart:200-325`:
quick actions (StaggerIn 0) → global event banner (1) → SETUP (2) → Today's
Coins / `StepMilestonesSection` (3) → RACES (4). A pending race invite renders
inside RACES, via `_buildRaceOpportunityRow`'s `RaceCardState.pendingInvite`
branch (line 483) — i.e. below Today's Coins.

### Change (frontend only)

When `RaceCardData.fromJson(raceCard).state == RaceCardState.pendingInvite`,
render the invite row as its **own block above** the Today's Coins section, and
render nothing for it inside the RACES section.

- New `Widget? _buildPendingInviteSection()` returning the existing
  `_HomeRaceActionRow` (identical label/title/subtitle/callbacks — this is a
  move, not a redesign), wrapped in `Padding(fromLTRB(16, 16, 16, 0))`, keyed
  `Key('home-pending-invite')`.
- Inserted between SETUP (index 2) and Today's Coins. **Stagger indices shift**:
  invite becomes 3, Today's Coins 4, RACES 5, feedback card (item 5) 6. The
  comment at line 258-260 spells out that the cascade is ordered by index and
  must stay in visual order — update every index, don't append. **Both** RACES
  branches move to 5: `if (raceCard != null) StaggerIn(index: 4, …)` **and** the
  `else if (raceCardLoading)` skeleton at index 4. Missing the skeleton branch
  produces a wrong-order cascade only during the loading frame — easy to ship.
- **Tutorial fixture guard (REQUIRED):** `tutorialMilestonesKey` — the spotlight
  anchor — sits on the `KeyedSubtree` at index 3, exactly where the invite block
  is being inserted. It is safe today only because
  `tutorialPreviewHomeRaceCard()` returns `ACTIVE_RACES` and so never renders an
  invite. Add a comment at that fixture stating that seeding a `PENDING_INVITE`
  state there would push the milestones spotlight below the fold.
- `_buildRaceSection` keeps its header and, for the `pendingInvite` state,
  renders the **empty-state** row instead (`RaceCardState.empty`'s
  "Race your friends" row) so the RACES section is never a bare header with
  nothing under it. This is the one non-mechanical judgment in the item and is
  explicitly part of the spec.
- Everything else about `_buildRaceOpportunityRow` is untouched.

### Known limitation (accepted, not fixed here)

The backend returns exactly one home-card state. When a user has an active race,
`getHomeRaceCard` returns `ACTIVE_RACES` and a pending invite is **not present in
the payload at all** (`src/modules/home/getHomeRaceCard.js:687`). So this item
moves the invite in the case where it renders today; it does not make invites
appear during an active race. The user chose this scope explicitly.

### Compat

Frontend-only, reading fields that already exist. Nothing to gate.

---

## Item 4 — reroll populates the inventory before the reel finishes

### Root cause

`_rerollBoxPowerup` (`lib/screens/race_detail_screen.dart:5014`) calls
`_loadProgress()` **immediately after the reroll request returns**, before it
hands the new result back to `CaseOpeningScreen`. `_loadProgress` refetches
`powerupData.inventory`, whose row now carries the **new** type — and the case
overlay is non-opaque, so the inventory row behind the still-spinning reel
updates instantly, spoiling the reveal.

This is precisely the bug the original open path documents and avoids at
line 5093-5100 ("Firing this on the API response instead spoiled the result").
The reroll path reintroduced it.

### Fix

Remove the `_loadProgress()` call from `_rerollBoxPowerup`. The refresh already
happens after the overlay closes, in `_openMysteryBox`'s `finally`. If a refresh
is genuinely wanted sooner, it must be triggered from `onRevealed` (which fires
on reel landing), never from the API response.

- Same rule applies to the new item-1 batch path: `_rerollAllBoxPowerups` must
  not call `_loadProgress()`; `_openAllBoxes`'s `finally` already does.
- The existing `_optimisticallyApplyBoxOpen` in `CaseOpeningScreen.onRevealed`
  continues to be the only thing that mutates the visible row mid-overlay, and
  it already fires post-landing.

### Test

Widget test: pump `RaceDetailScreen` with an injected `boxRerollAdController`,
open a box, reroll, and assert the inventory tile still shows the **pre-reroll**
type while the reel is mid-spin, and the post-reroll type only after the second
reveal completes. Assert `_loadProgress`'s underlying API call is not issued
between the reroll response and the reveal.

---

## Item 5 — feedback entry point on home

### Summary

`SEND FEEDBACK` exists in Settings (`lib/screens/settings_screen.dart:395`),
opening the private `_FeedbackSheet` (line 592) which POSTs
`/feedback/suggestions` via `BackendApiService.submitSuggestion`
(`lib/services/backend_api_service.dart:835`). Home has no equivalent.

### Change (frontend only)

1. **Extract** `_FeedbackSheet` from `settings_screen.dart` into
   `lib/widgets/feedback_sheet.dart` as a public `FeedbackSheet` plus a
   `Future<void> showFeedbackSheet({required BuildContext context, required
   AuthService authService, required BackendApiService backendApiService})`
   helper carrying the existing `showModalBottomSheet` configuration
   (`isScrollControlled`, parchment background, 16px top radius).
   Settings calls the helper. **Keep every existing widget key**
   (`feedback-sheet`, `feedback-input`, `feedback-error`, `feedback-submit`) —
   the settings tests assert on them and must not be touched.
2. **New home section**, last block inside the home Column, below RACES:
   a `GameContainer` card keyed `Key('home-feedback-card')` reading
   **"Found a bug? Have an idea? Let us know"** with a single
   `SEND FEEDBACK` pill (`Key('home-feedback-button')`) that calls
   `showFeedbackSheet`. Stagger index = one past RACES (6 after item 3's
   shift).
3. `HomeTab` is a `StatelessWidget` and already holds `authService` and
   `backendApiService`; the sheet needs a `BuildContext` from the button's
   builder, which is available. No state added.
4. Renders unconditionally — no gate, no backend dependency beyond the
   already-live endpoint.
5. **Tutorial preview must not be able to submit (REQUIRED, ui-test-planner).**
   The planned "null `backendApiService` → disabled button" degradation **never
   triggers**: `TutorialPreviewBackendApiService extends BackendApiService`,
   does not override `submitSuggestion`, and `HomeTab` receives it non-null. The
   only thing standing between a tutorial tap and a real
   `POST /feedback/suggestions` is the opaque full-screen `GestureDetector` in
   `spotlight_overlay.dart:55` — which is incidental, not a guarantee. Fix it
   properly: either override `submitSuggestion` in the preview service to a
   no-op, or pass an explicit `previewMode` flag that hides the card. Do **not**
   rely on the overlay.

---

## Item 6 — Rainstorm doesn't halve a buffed multiplier

### The bug (reproduced from prod, "runners hi", 2026-08-10)

DrAmogh held a Rally Flag (×1.25) and a Ghost Pepper (×3) during a 2× global step
event, showing ~8×. A Rainstorm took him to 7×, not ~4×.

`signedMultiplierAt` in
`src/modules/races/services/effectMultiplier.js` sums buffs
(1.25 + 3 = 4.25) and then applies reductions **subtractively**:

```js
if (reduced) M = Math.max(0, M - lost);   // 4.25 - 0.5 = 3.75
```

The global event multiplies on top (`globalStepEvent.js`: `steps * m * (E-1)`
added to a base of `steps * m` ⇒ `steps * m * E`), so the display went
4.25×2 = 8.5 → 3.75×2 = 7.5, rendered 8 → 7. Rainstorm's own copy says "Steps
halved by rain" (`lib/constants/powerup_copy.dart:502`), and the metadata field
is literally `multiplier: 0.5`. Subtracting 0.5 only equals halving when the
victim is unbuffed.

### Fix (Rainstorm only — user decision, 2026-08-10)

In `signedMultiplierAt` step 3, compute the resulting `M` for **every** active
reduction independently and **keep the lowest** (`game-analyst`, REQUIRED):

- a candidate from the **`rainstorms` group** yields `M * retained` (retained =
  metadata `multiplier` clamped to [0,1], default 0.5) — a true halving.
- a candidate from the **`coinFlipLoses` group** yields `Math.max(0, M - lost)` —
  unchanged.
- final `M` = the minimum across all candidates (and `M` itself when none are
  active).

This replaces the earlier "pick the max `lostFraction`, then branch" rule, which
had a latent inversion: with one branch multiplicative and one subtractive,
`lostFraction` is no longer a valid ordering. At M = 4.25 a coin-flip loss with
`lostFraction = 0.75` yields 3.5 while Rainstorm's 0.5 yields 2.125 — so a
*nominally stronger* debuff would **shield** the victim from the storm.
Unreachable today (both hardcode 0.5, so they always tie), but live the moment
either value becomes configurable or a Mystery Potion variant sets a different
fraction. Taking the minimum makes "Rainstorm wins the 0.5/0.5 tie" fall out of
the math instead of being a stated convention, and preserves the existing
"never stack two reductions" clamp exactly (two storms both yield `M * 0.5`;
the min is `M * 0.5`, never `M * 0.25`).

**Dispatch on the group array, NEVER on `effect.type` (REQUIRED, architect R8).**
`umbrellaAdjustedRainstorms` (`effectiveStepScoring.js:180-185`) returns synthetic
rows shaped `{startsAt, expiresAt, metadata}` with **no `type` field**, and those
are what land in `groups.rainstorms` whenever the victim holds an Umbrella
(verified 2026-08-10). An implementer writing `if (winner.type === "RAINSTORM")`
would get the multiplicative branch for everyone *except* umbrella-holders, who
silently keep the old subtractive behavior — a divergence visible only in the one
case the Umbrella exists for. The two loops already know which group they are
iterating; carry that through as the candidate's branch.

Unchanged by construction: an unbuffed victim (M = 1) still lands on 0.5 under
either branch; the Umbrella subtraction still happens before this function is
called; Wrong Turn still negates the post-reduction rate; freeze still short-
circuits above.

The user was told Coin Flip's losing side runs the identical code path and chose
to leave it subtractive. Recorded here so the divergence is intentional and
documented, not drift.

### Blast radius — every caller must stay consistent

`signedMultiplierAt` is the single source of truth and is called from:
- `effectiveStepScoring.computeEffectModifiers` (live scoring, sample path),
- `effectiveStepScoring.signedMultiplierForEffects` (the displayed
  `currentMultiplier`),
- `raceStateResolution.multiplierForTime` (finish-time interpolation),
- `globalStepEvent.computeGlobalEventBoost` (event boost).

All four inherit the fix automatically.

**Finish-time interpolation is the exception, and this fix magnifies an existing
bug there (REQUIRED, architect R9).** `calculateCurrentTotal`
(`raceStateResolution.js:270-288`) returns the **raw** `rainstorms` list
(`byType.RAINSTORM`) — it does not return `umbrellas` at all — and `raceExpiry.js:293-304`
passes that straight into `determineFinishSnapshot`. So an umbrella'd racer's
finish-time multiplier is already wrong today by a subtractive 0.5; after this
change it would be wrong by a *factor* of ~2 on a buffed racer. Shipping that
silently is how a settlement bug ships as "no API change."

**Fix, in this batch:** umbrella-adjust the `rainstorms` in
`calculateCurrentTotal`'s returned object (reuse `umbrellaAdjustedRainstorms`;
it is already imported in that module's dependency graph), so both consumers see
the same windows. This is a small, deliberate scope addition beyond the six
items — it changes finish-time interpolation for umbrella holders — and is
called out for the user in the approval summary rather than smuggled in. With it,
display and settlement agree by construction, which is the property the
buff-stacking spec exists to protect. Add a test pinning
"buffed + rainstorm + overlapping umbrella" agreement across display, scoring
and finish interpolation.

**The snapshot fallback path does NOT inherit it.** `computeEffectModifiersFallback`
and `mergeRainstormWindows` (`effectiveStepScoring.js`) apply
`frozenSteps += windowSteps * lostFraction` against **raw** steps for users with
no hourly samples. That is already a different approximation (it does not know
about buffs at all), and changing it is out of scope — but the implementer must
**not** "fix" it to match, and must add a comment noting the divergence and why.
Quantify the affected population in the release notes (architect S6):
`hasSampleData === false` users now diverge from sampled users by a *factor*
rather than by an offset when buffed.

### Balance impact — `game-analyst` verdict: **SOUND WITH CHANGES**

Measured over the same 588 real victim-rows (60 casts, 9 casters):

| Metric | Before (`M − 0.5`) | After (`M × 0.5`) |
|---|---|---|
| Store price | 75 coins (not 300) | unchanged |
| Victims per cast | 9.8 | unchanged |
| Victim buffed during storm | 12.2% of rows / 16.3% of storm-window steps | unchanged |
| Realised damage all-time | 173,564 steps (2,893/cast, 38.6 steps/coin) | **220,707 (3,678/cast, 49.0/coin)** — **+27.2%** |
| Unbuffed victim (M = 1) | 0.5 | 0.5 — **bit-identical** |
| Worst realistic single victim (Ghost Pepper 3×, 2,000 steps/30min) | −1,000 steps | **−4,000 steps (4×)** |

Market band for reference (swing-steps/coin): Wrong Turn L1 58, Leg Cramp L1 43,
Ghost Pepper ≈13. Rainstorm moves to 49 average, ~150 when deliberately timed
onto a 3–4× stack. Coin sources/sinks are **unaffected** — neither item mints or
burns coins (Rainstorm has sold 61 copies ever, ≈4,575 coins all-time, against a
−914/day purchase sink).

**Two follow-on changes the analyst raised — both DECLINED by the user
(2026-08-10). Neither is in scope for this batch:**

1. **Umbrella stays `active=false`.** The analyst rated re-activating it
   REQUIRED: after this fix the only reachable counter to a 27%-stronger AoE is
   Compression Socks (a free RARE at 3.4–6.0%/box), so a buff-buyer has no
   purchasable protection for their 150-coin Ghost Pepper. The user chose to
   ship the fix without it. **Watch item:** if buff purchases fall or storm
   complaints rise after rollout, re-activating the Umbrella (a DB-only change —
   the deploy seed omits `priceCoins`/`active`) is the first lever to reach for.
2. **Rainstorm stays at 75 coins.** The analyst's RECOMMENDED (not required)
   reprice to 150 was declined in favor of watching real usage first — the live
   sample is thin (61 copies sold ever) and the coin-sink impact is negligible
   either way. At 75 it is the best-priced offensive store item post-fix
   (49 swing-steps/coin vs Ghost Pepper's ~13, Wrong Turn L1's 58).

Both are deliberate, recorded decisions — not oversights. Revisit together once
there is post-rollout usage data.

### Kill switch (REQUIRED, architect R10)

"Reverting means reverting the commit" is not adequate for a change that alters
scoring for every in-flight race on restart. `signedMultiplierAt` is pure and
DB-free, so an app setting is the wrong shape; use an **env var read at call
time**, the same idiom as `discardDailyCap()` (`discardRewards.js:27`):

- `RAINSTORM_MULTIPLICATIVE_ENABLED`, default `"false"`.
- Ships OFF, verified on staging, then flipped ON in prod with a pm2 reload.
- A bad settlement is then reverted by a reload, not a code deploy.

**BLOCKING follow-up when the flag is flipped ON.**
`test/queries/rainstormScoring.test.js:83-86` — "rain + Runner's High stays
additive: 1.5x", asserting `totalFor(effects, 6000) === 9000` — encodes `M − 0.5`
on a buffed victim. It is still *correct for production* while the flag is OFF,
so it was deliberately left verbatim (with a header note pointing at the
flag-ON assertion). **The moment `RAINSTORM_MULTIPLICATIVE_ENABLED=true` goes to
prod, this expected value becomes 6000** (M = 2 × 0.5 = 1). No other suite
asserts a buffed victim under rain.

### Not correcting the affected race

Explicit user instruction: no back-scoring, no repair of "runners hi". The fix is
forward-only. Because live display and settlement both read the same function,
the race will simply score the new way from deploy onward.

### Compat

Backend-only, no API shape change. `currentMultiplier` continues to be a number.
Frozen clients render whatever number they are sent — the frontend does no
multiplier math (verified: no multiplier computation exists under `lib/`).
This **is** a live gameplay change mid-race: any race in flight when the backend
restarts will see rainstormed multipliers drop further than they did a minute
earlier. Accepted (the current behavior is the bug), but it belongs in the
release notes.

---

## Rollout & deploy order

1. **Backend first**, in one deploy: item 1 endpoint + `boxRerollBatch` flag,
   item 2 `discardCapRemaining`, item 6 multiplier fix.
   - Item 1's endpoint is inert without an app that calls it; `boxRerollBatch`
     is only advertised when `ADS_BOX_REROLL_ENABLED=true` (already true in prod
     for the single reroll).
   - Item 2's field is additive and ignored by every frozen client.
   - Item 6 takes effect immediately for all clients — intended.
2. **Staging verification** of all three against a staging race.
3. **App release** (2.2.4) carrying items 1 (client half), 2 (copy), 3, 4, 5.
   iOS build must include `--dart-define=ADMOB_BOX_REROLL_AD_UNIT_ID=…` or
   REROLL ALL compiles out. Android ships in lockstep from the same Dart code;
   REROLL ALL is absent there (no Android reroll unit) exactly as it is today.
4. **Kill switches:**
   - Item 1 — `ADS_BOX_REROLL_ENABLED=false` removes both `boxReroll` and
     `boxRerollBatch` and 503s both endpoints.
   - Item 2 — no switch for the field itself (it can only make the dialog more
     honest); the *cache* is switched by `redisCacheDiscardCapEnabled`.
     **It ships default-OFF (codebase convention) but MUST be turned ON in prod
     as part of this deploy** (code review, issue 3): with the cache off,
     `discardCapRemainingFor` runs a net-new Postgres round trip on *every*
     `/races/:id/progress` poll for any viewer holding a HELD powerup — most
     active racers, several times a minute, on the hottest endpoint on a
     one-vCPU box (~2.5k DAU cliff). The sargable 3-day pre-filter keeps it
     cheap, not free. Watch p95 on `/progress` after deploy either way.
   - Item 6 — `RAINSTORM_MULTIPLICATIVE_ENABLED`, default `"false"`, read at
     call time. **Ships OFF**; flipped on after staging verification. This
     changes step 1 of the deploy order: the backend deploy is inert for item 6
     until the env flip.

### What a frozen old client does against the new backend

| Item | Old client behavior |
|---|---|
| 1 | Never calls the new endpoint; ignores `boxRerollBatch`. Single-box reroll unchanged. |
| 2 | Ignores `discardCapRemaining`; keeps today's (occasionally wrong) dialog until updated. |
| 3, 4, 5 | Frontend-only; old clients unaffected. |
| 6 | Renders the corrected multiplier it is sent. No client math to disagree. |

---

## Test plan (written BEFORE the code, per CLAUDE.md)

### Backend — `test/integration/` (real HTTP, real DB, test database only)

Item 1 — `test/integration/powerup-reroll-batch.test.js`:
1. Kill switch off → 503 `DISABLED`, and no grant consumed.
2. Happy path: 3 HELD box-rolled powerups + 1 unconsumed `box_reroll` grant →
   200, all three `rerolled: true` with (possibly) new types, `rerolledAt` set on
   all three, **exactly one** grant consumed, `rerolledCount: 3`.
3. Mixed batch: one HELD, one already-rerolled, one USED → 200,
   `rerolledCount: 1`, the other two carry `skipped` and their **unchanged**
   type/rarity, one grant consumed.
4. All-ineligible batch → 409 `NOTHING_TO_REROLL` **and the grant is still
   unconsumed** (assert on the row).
5. No grant → 409 `AD_NOT_VERIFIED`, nothing rerolled.
6. Foreign powerupId (another user's) → omitted from `results`, not rerolled,
   no 403 leak; a batch of only foreign ids → 409 `NOTHING_TO_REROLL`.
7. Race not ACTIVE → 400. Non-participant → 403.
8. `localDate` invalid → 400 `INVALID_LOCAL_DATE`; `localDate` one day off →
   200 (adjacent-date lookup).
9. Wave-5 gate: without `X-Client-Features: powerups5`, no result carries a
   wave-5 type across a forced-config run.
10. Empty/missing `powerupIds` → 400. A duplicate-listed id is de-duplicated
    before the cap is applied and appears once in `results`.
10b. More than `REROLL_BATCH_MAX_COUNT` eligible ids → the first N reroll, the
    remainder come back `skipped: "OVER_CAP"` with unchanged type/rarity, and
    exactly one grant is consumed.
10c. Response rows are keyed **`powerupId`**, not `id` (a schema assertion —
    this is the silent-failure mode R2 identifies).
11. `getRaceProgress` advertises `boxRerollBatch: true` only with ads-capable
    client features + switch on; key **absent** otherwise (assert absence, not
    `false`).

Item 2 — `test/integration/discard-cap-visibility.test.js`:
1. Fresh user, nothing discarded today → `powerupData.discardCapRemaining`
   equals the configured cap.
2. After discarding to exactly the cap → subsequent progress returns 0.
3. Partial headroom (cap − 2) → returns 2, and a RARE discard then pays 2
   (existing partial-award behavior, asserted through the response).
4. Viewer with no HELD powerups → key omitted (the cost guard), and the dialog
   degrades correctly.
4b. The whole suite runs with `REDIS_URL` **unset** and every case above still
   passes — Redis is an optimization, never a precondition.
5. Timezone: a user whose stored zone rolls the day over sees the cap reset;
   assert against the stored zone, not `X-Timezone`.

Item 6 — extend `test/integration/buff-stacking-event-scoring.test.js` and
`test/queries/rainstormScoring.test.js` (the existing unit suite is the right
home for the pure-math cases — many-case algebra is the documented exception):
1. **The prod repro**: Rally Flag + Ghost Pepper boost + 2× global event,
   rainstormed → effective multiplier ≈ 4.25, not 7.5. Assert the number and
   the scored steps.
2. Unbuffed + rainstorm → 0.5 (unchanged; guards the regression).
3. Two simultaneous rainstorms → single 0.5 factor, not 0.25 (the per-caster
   clamp must survive).
4. Rainstorm + Coin Flip loss simultaneously on a buffed victim → the minimum
   rule picks Rainstorm's multiplicative result; assert the exact value.
4a. **Inversion guard:** a synthetic coin-flip loss with `lostFraction = 0.75`
   alongside a 0.5 Rainstorm at M = 4.25 → 2.125 (the storm), NOT 3.5. This is
   the case the old "max lostFraction wins" rule got backwards.
4b. **Buffed victim + rainstorm + partially-overlapping Umbrella** → the
   umbrella-adjusted synthetic rows (which carry no `type`) still take the
   multiplicative branch. This is the case a `effect.type` dispatch would
   silently get wrong.
4c. **Display / scoring / finish-interpolation agreement** for that same
   umbrella case, pinning the R9 fix.
4d. `RAINSTORM_MULTIPLICATIVE_ENABLED` unset/`"false"` → the old subtractive
   behavior, exactly. The flag's OFF path is the production default at deploy
   time and must be tested, not assumed.
5. Coin Flip loss alone on a buffed racer → **unchanged** subtractive behavior
   (this is the deliberate divergence; the test pins it so nobody "fixes" it).
6. Frozen (Leg Cramp) + rainstorm → still 0.
7. Wrong Turn + rainstorm → −(halved) rate.
8. Display/settlement parity: `signedMultiplierForEffects` and the scoring path
   agree on the same effect set.

**Existing assertions in these suites are protected.** Cases 2, 3, 6, 7 exist
today and must keep their current expected values; only genuinely buffed-victim
cases change. Any existing assertion that encodes `M − 0.5` on a buffed victim
is a case this fix intentionally changes — the implementer must **surface it in
the PR description**, not silently rewrite it.

### Frontend — widget tests (pump the real screen)

- `test/` — Open All summary shows REROLL ALL + the disclaimer when
  `powerupData.boxRerollBatch == true` and an ad controller is injected; shows
  **neither** when the flag is absent, when the flag is `false`, or in demo mode.
- Tapping REROLL ALL with a stubbed controller re-spins the bank and lands on
  the new types; `onResults` fires once per landing with the new types.
- Backing out of the ad leaves the summary and results untouched, and the
  button is still enabled.
- Item 2: discard dialog renders each of the four bodies for
  (unopened box / cap 0 / partial cap / unknown cap) from a stubbed
  `powerupData`. Existing discard-dialog tests must keep passing unmodified.
- Item 3: home renders `home-pending-invite` **above** the milestones section
  (assert on vertical order via `tester.getTopLeft`), and the RACES section
  shows the empty-state row rather than a duplicate invite.
- Item 4: the regression test described in item 4 above.
- Item 5: `home-feedback-card` renders; tapping opens `feedback-sheet`;
  settings' existing feedback tests still pass against the extracted widget.
- `PackageInfo.setMockInitialValues` in every new widget test's `setUp` (known
  hang, see memory).

---

## Acceptance criteria / definition of done

1. Open All → summary → REROLL ALL → one ad → every eligible box re-rolls, the
   bank re-spins, and the race inventory matches the new types after the overlay
   closes. Exactly one ad grant consumed per batch.
2. The reroll disclaimer is visible before the ad, and states that all boxes are
   rerolled.
3. Discarding when the daily coin bonus is exhausted shows "you'll get 0 coins"
   on the **first** discard of a screen visit, with no prior discard needed; a
   partially-exhausted cap quotes the clamped amount.
4. A pending race invite renders above Today's Coins on home.
5. Rerolling a single box no longer changes the inventory row until the reel
   lands.
6. Home shows "Found a bug? Have an idea? Let us know" with a working sheet.
7. A rainstormed racer at 8× drops to ~4×, and an unrainstormed/unbuffed racer's
   scoring is bit-identical to before.
8. Both platforms build (`flutter build ipa` + `flutter build appbundle
   --flavor prod`), and `flutter test` + backend `test:unit` and
   `test:integration` are green.
9. `code-reviewer` has reviewed the combined diff.

---

## Manual UI-placement test plan

From the `ui-test-planner` agent. Every checkpoint must be walked before this
batch is called done.

**A. Real home tab (items 3 + 5)**

1. Home tab, account WITH a pending invite and NO active race (second
   account/device sends the invite; you must have no ACTIVE race — the backend
   returns one card state only). **Verify:** the INVITE row (`@Name challenged
   you` / ACCEPT / DECLINE) sits above the Today's Coins / milestones block and
   below SETUP. Scroll down: the RACES header exists and shows the "Race your
   friends" empty row — not a second invite row, not a bare header.
2. Same screen, pull-to-refresh so the StaggerIn cascade replays. **Verify:**
   blocks bounce in strictly top-to-bottom — quick actions → (event banner) →
   SETUP → invite → Today's Coins → RACES → feedback card. Nothing out of order
   or simultaneous with a neighbor.
3. Home tab, account with NO invite. **Verify:** no empty gap or stray padding
   where the invite block would be; RACES renders its normal state unchanged.
4. Scroll to the bottom of Home. **Verify:** the "Found a bug? Have an idea? Let
   us know" card is the last block, below RACES (and below the RACES skeleton
   while loading). Tapping SEND FEEDBACK opens the sheet; the sheet is not
   clipped by the tab bar or the keyboard when typing.
5. Profile → Settings → SEND FEEDBACK. **Verify:** the sheet looks and behaves
   exactly as before (parchment sheet, rounded top, scrollable with keyboard up,
   error line, submit). The SEND FEEDBACK row's placement in Settings is
   unchanged.

**B. Real race detail (items 1 + 2)**

6. Open All summary. **iOS build only**, built with
   `--dart-define=ADMOB_BOX_REROLL_AD_UNIT_ID=…`, backend with
   `ADS_BOX_REROLL_ENABLED=true`. Any ACTIVE race with ≥2 openable boxes →
   POWERUPS header → OPEN ALL → let all reels land. **Verify:** REROLL ALL sits
   above Continue with the disclaimer directly beneath it; no reroll control on
   the individual reels or the header. While rerolling: Continue disabled,
   swipe/back cannot dismiss. After the ad: the bank re-spins and the summary
   returns with REROLL ALL gone — not a second copy, not a dead greyed pill.
7. Same, on the Android build (no reroll ad unit). **Verify:** the summary
   renders byte-identically to today — no REROLL ALL, no disclaimer, no empty
   space above Continue.
8. Open one box normally. **Verify:** the single REROLL button is still in its
   existing place on `CaseOpeningScreen`, unduplicated.
9. Discard down until the daily coin bonus is nearly exhausted, then **fully
   close and reopen the app** and enter the race fresh (this is the case that
   lied before). **Verify:** on the **first** discard of the visit the dialog
   quotes the clamped amount ("… for N coins? Your daily discard bonus is nearly
   used up."), and the `+N 🪙` tag on DISCARD shows the **same** clamped N, not
   the full price.
10. Same race after the cap is fully exhausted; also tap an unopened
    MYSTERY_BOX slot. **Verify:** cap-0 → "you'll get 0 coins" on the first
    discard, `+N 🪙` tag absent (not "+0"). Unopened box → the existing box
    copy, tag absent.
11. Hold a Pocket Watch → tap it → its two-mode sheet. **Verify:** its DISCARD
    price chip shows the same clamped number as the generic sheet, and
    disappears at cap 0.

**C. Demo race tutorial (real screens, fake services)**

12. Fresh account → onboarding → demo race (or Profile → admin → re-run
    onboarding/demo). **Verify:** the POWERUPS header shows **no** OPEN ALL
    button, so no REROLL ALL surface exists; the single-box reveal shows **no**
    REROLL; the held-powerup action sheet gains no `+N 🪙` tag and no new dialog
    body (discard is disabled in demo).
13. Same run, beats that ring the POWERUPS tray and the clock. **Verify:** the
    spotlight ring still lands exactly on the powerups tray and the header clock
    chip — nothing above them moved.

**D. Tutorial previews (real screens, seeded fixtures)**

14. Profile → admin → re-run tutorial (or fresh account onboarding v3) → home
    beats. **Verify:** the feedback card renders at the bottom of the preview and
    looks intentional; **no** invite block above Today's Coins (fixture state is
    `ACTIVE_RACES`); spotlights for steps, Today's Coins/milestones, shop and
    friends each still ring their element with nothing clipped or scrolled off.
    Tapping the feedback card must not submit anything (see item 5 step 5).
15. Continue to the race-detail beat. **Verify:** OPEN ALL still renders in the
    POWERUPS header (the fixture has 1 slot box + 1 queued) and is inert; no
    REROLL ALL anywhere; the POWERUPS spotlight still rings the tray.
16. Any tutorial page with the bottom bar. **Verify:** 5 tabs in the same
    order/labels as the live shell — this copy is hand-forked and nothing in
    this batch should touch it.

**E. Post-onboarding landing**

17. Brand-new account through onboarding v3 to the live Home tab. **Verify:**
    feedback card present as the last block; no invite block; SETUP prompts
    still lead the page above Today's Coins.

**Surfaces confirmed unaffected** (no checkpoint needed): races tab and its
hand-forked effect plates / inventory row; demo prologue beats (create-race,
invite-friends); the daily-reward reel forked from `CaseOpeningScreen`;
tournament and public-races entry points into `RaceDetailScreen` (same screen,
items 1–2 propagate automatically); demo coach chrome and the race-results
summary screen. `MultiCaseOpeningScreen` has exactly one call site, so
`onRerollAll: null` by default reaches no other surface.

**Testing prerequisite:** there is no in-app way to force
`0 < capRemaining < price` for checkpoint 9. Either discard down to it on
staging, or have the backend seed `consumedToday` first.

## Phase 5 — implementation & code review (2026-08-10)

Both agents implemented tests-first; `code-reviewer` verdict on the combined
two-repo diff: **SHIP, no blockers**. Three issues raised; two fixed on the
spot, one converted to a deploy step.

- **Fixed — unbounded DB read.** `REROLL_BATCH_MAX_COUNT` was applied *after*
  `findMany({ id: { in: ids } })`, so an authenticated participant could POST
  10,000 ids and buy a 10k-element `IN` on the one-vCPU box **for free** (the
  409 lands afterwards, so no ad is spent). Added `MAX_REQUEST_IDS = 100`,
  enforced before the query. New test: "rejects an oversized powerupIds list
  before touching the database", asserting the grant is left unconsumed.
- **Fixed — `OVER_CAP` counted request positions, not eligible rows.** 8
  ineligible ids listed first would push the only rerollable box past the cap
  and turn a valid batch into a 409 `NOTHING_TO_REROLL`, contradicting the
  contract's "the first N *eligible* ids reroll". The cap now counts eligible
  rows. New test: "the cap counts ELIGIBLE rows".
- **Converted to a deploy step —** `redisCacheDiscardCapEnabled` must be turned
  ON in prod with this deploy (see §Rollout kill switches).
- **Nit fixed:** a 200 carrying no rows re-spun to identical results in
  silence with the ad already spent; it now says so, while still retiring the
  button rather than inviting a second wasted watch.
- **Nits declined, with reasons:** the split `require("../powerups")` blocks in
  `routes.js` match that file's consistent one-block-per-dependency style —
  merging them would read as the odd one out. The `on TimeoutException` catch
  in `_rerollAllBoxPowerups` is **not** dead code: the same `try` wraps
  `_rerollAd.load()` / `showAndAwaitReward()`, which can throw it from the ads
  SDK independently of the API layer.

Reviewer-verified independently: `powerupId` keying agrees across both repos;
both new fields are omitted (never `false`) when off; the eligibility sweep
precedes grant consumption with a correct CAS; item 6 dispatches on the group
array with the flag defaulting OFF, and its flag-OFF path is *algebraically
identical* to the old code (`min over max(0, M−lostᵢ)` == `max(0, M − max lost)`);
`calculateCurrentTotal`'s `rainstorms` has exactly one consumer, which reads
only `startsAt`/`expiresAt`/`metadata`; and no code path refreshes the
inventory between a reroll response and the reel landing.

**Test-integrity check (independent of the agents' claims):** the two modified
backend test files have **zero deleted lines**; the three modified frontend
test files change only finders (`.first` disambiguation), one stagger index,
and the reel-key format — every assertion value is intact.

**Known pre-existing red test, NOT caused by this batch:**
`test/batch_2026_07_27_home_night_test.dart` "the RACES header keeps its padding
after the rule is gone" expects `EdgeInsets.fromLTRB(16,16,16,9)` while the
header uses `(16,8,16,9)` (`home_tab.dart:1582`). Confirmed failing identically
on a clean `HEAD` worktree. Called out because this batch edits that file, so it
must not be misread as a regression — and because a permanently-red assertion is
one nobody notices going wronger. Worth a separate fix.

## Revision log

**Phase 2, pass 1** (fresh re-read):
- Item 1: added the "eligibility sweep before grant consumption" ordering and
  the `NOTHING_TO_REROLL` error, which the first draft left implicit — without
  it a batch of all-ineligible ids burns an ad watch for nothing.
- Item 1: specified that foreign ids are omitted rather than echoed with an
  error, to avoid confirming another user's powerup ids exist.
- Item 1: pinned "one position/roll-context for the whole batch"; the first
  draft would have let the batch's own writes shift position mid-loop.
- Item 1: added the CAS-loser policy (skip, don't fail the batch; no refund) and
  the `rerolledCount: 0` edge case.
- Item 2: added the partial-award dialog copy. The first draft only handled
  cap == 0 and would still have promised 10 coins at 38/40.
- Item 2: added the polling cost guard (skip when nothing is discardable, 60s
  memoization) — `getRaceProgress` is the hottest endpoint and the box is a
  single vCPU.
- Item 3: added the "RACES section must not become a bare header" rule.
- Item 6: added the explicit tie-break between Rainstorm and Coin Flip loss;
  the first draft's "strongest wins" was ambiguous at 0.5/0.5.

**Phase 2, pass 2** (second independent re-read):
- Item 2: caught that `_discardCapRemaining` (post-discard override) would
  shadow a fresher server value forever, including across a local-day rollover.
  Added the clear-on-progress rule.
- Item 4: extended the fix to the new item-1 batch path, which would otherwise
  have shipped the identical bug on day one.
- Item 1: added the "summary is non-dismissable while the ad is up" rule; a
  backgrounded ad over a popped route would have left a half-applied batch.
- Item 1: required `onResults` idempotency (it holds today) since the batch
  reroll makes it fire twice for the same ids.
- Item 5: required preserving every existing feedback-sheet widget key during
  the extraction, so the protected settings tests keep passing as-is.
- Item 6: added the explicit "do not touch the snapshot fallback path" rule and
  the requirement to surface (not rewrite) any existing assertion this fix
  legitimately changes.
- Item 6: added the mid-race behavior change to the rollout section — it is a
  live gameplay change on restart, which the first draft did not call out.
- Item 3: recorded the ACTIVE_RACES limitation as an accepted non-goal so it
  isn't rediscovered as a bug later.

**Phase 4 — `ui-test-planner`** (complete). Added the manual checklist above and
folded six planning risks into the spec as REQUIRED steps:
- Item 2: a **third** discard-price call site the spec had missed —
  `pocket_watch_sheet.dart` via `race_detail_screen.dart:2737` — which would
  otherwise keep quoting the unclamped price.
- Item 5: the "null `backendApiService` disables the button" degradation is
  dead code — the tutorial preview service extends the real one and does not
  override `submitSuggestion`, so only an incidental overlay prevents a real
  submission from inside the tutorial. Replaced with a real guard.
- Item 3: both RACES `StaggerIn(index: 4)` branches (loaded **and** skeleton)
  must shift, and the tutorial home fixture needs a comment noting that seeding
  `PENDING_INVITE` would push the milestones spotlight below the fold.
- Item 1: `_boxRerollBatchEnabled` must copy the demo-mode guard, not just the
  ad-support one.
- Recorded that no demo/tutorial fixture carries `boxRerollBatch` or
  `discardCapRemaining` (correct by omission — both feature-detect), so the new
  copy is only verifiable against a real race on the new backend.

**Phase 4 — `architect`** (verdict: REVISE; all 10 REQUIRED folded in, plus
S1–S7). The consequential ones, both independently verified against the source
before folding:
- **R8** — `umbrellaAdjustedRainstorms` returns synthetic rows with **no `type`
  field**, so dispatching item 6's new branch on `effect.type` would have left
  umbrella-holders on the old subtractive math — wrong in exactly the case the
  Umbrella exists for. Dispatch is now specified on the group array.
- **R9** — `calculateCurrentTotal` returns raw, non-umbrella-adjusted rainstorms
  to finish-time interpolation, so item 6 would have *doubled* an existing
  settlement error instead of leaving it flat. Now fixed in-batch (a deliberate
  scope addition, flagged to the user).
- **R2** — the batch response was keyed `id` while the client's rows are keyed
  `powerupId`; the mismatch fails silently (every reel keeps its old result, no
  error). Response re-keyed to match its sibling `open-batch`.
- **R5/R6** — item 2's cache design bypassed `KNOWN_FLAGS`/`cacheKeys`/
  `derivedCache`, placed the query where the HELD guard can't run, treated Redis
  as a precondition (breaking CI, where `REDIS_URL` is unset), and put a
  non-sargable full-ledger scan on the hottest endpoint. All four corrected.
- **R7** — the clear-on-every-payload rule would have re-introduced the very bug
  item 2 fixes, via a 60s-stale cache read. Now a date-stamped override.
- **R10** — item 6 gets an env kill switch (`RAINSTORM_MULTIPLICATIVE_ENABLED`,
  default off) rather than "revert the commit."
- **R1** — the batch cap is now its own `REROLL_BATCH_MAX_COUNT` awaiting the
  game-analyst number, and the "ignored, not an error" / "every owned id appears
  in results" contradiction is resolved via `skipped: "OVER_CAP"`.
- **R3/R4** — `DemoRaceApiService.rerollPowerupBatch` override (prod-request
  leak guard) and the tutorial feedback-submission guard (same finding as the
  ui-test-planner's risk 2, reached independently).

**Phase 4 — `game-analyst`** (item 1 SOUND, item 6 SOUND WITH CHANGES):
- Item 1 needs **no** cap or repricing for balance. The counter-intuitive
  finding: all-or-nothing batching is per-*box* 32–57% **worse** than the
  existing single reroll, and since ad watches are uncapped, box-hoarding is
  strictly dominated by rerolling singly. `REROLL_BATCH_MAX_COUNT = 8` is set
  purely as a per-request work bound; the physical inventory ceiling is 5.
- Item 1's "up to 20" was never reachable — measured open-burst size is mean
  1.24, and 2.32 given ≥2.
- **Item 6 REQUIRED:** replaced "max `lostFraction` wins, then branch on group"
  with "apply every candidate reduction, keep the lowest resulting M." The old
  rule had a latent inversion where a *stronger* coin-flip loss would shield a
  victim from a Rainstorm (unreachable today; live the moment either fraction
  becomes configurable). The 0.5/0.5 tie-break now falls out of the math.
- **Item 6, Umbrella re-activation (analyst: REQUIRED) — DECLINED by the user.**
  Recorded as a watch item with the remediation lever named.
- **Item 6, Rainstorm reprice 75 → 150 (analyst: RECOMMENDED) — DECLINED by the
  user**, in favor of watching real usage first.
- Corrected a factual error carried into the review prompt: Rainstorm costs
  **75** coins, not 300.
- The analyst also updated `docs/economy.md` (its one writable artifact): §3.2
  rewritten for live config **v4**, which the doc had recorded as v3.
