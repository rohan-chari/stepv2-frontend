# Feature & Bugfix Batch — 2026-07-24

**Status:** Draft for approval (Phase 4 gate). No code until Rohan says go.
**Repos:** frontend `/Users/rohan/repos/stepv2-frontend`, backend `/Users/rohan/repos/stepv2-backend`.
**Owner decisions:** captured inline (see each item + Revision log).

---

## 0. Summary

Twelve items: three real bugs (5, 12, and the milestone/refresh color regressions in 3/4),
several UI/UX refinements (1, 2, 9, 11), two balance changes (7, 8), and one large new
race-detail feature (6: per-user multiplier display + fire animation + high-multiplier push).

**The #1 rule governs everything here (CLAUDE.md):** a shipped app binary is frozen and the
prod backend serves *all* app versions at once. Every backend change below is either
server-computed (reaches all clients instantly, e.g. 7, 8) or additive (new nullable
fields/endpoints old clients ignore). No breaking API shape changes. Deploy **backend first**,
then the app.

### Scope / non-goals
- **In:** the 12 items as specified below.
- **Out:** changing referral coin amounts (item 1 is *report + move button* only, not a reward
  change); redesigning the shop beyond pills+sort (item 9); any change to how multipliers are
  *scored* (item 6 is display + notification only — **no scoring/settlement change**, per owner);
  Play app-signing App-Link fix ships only if Rohan supplies the SHA-256 (item 1 follow-up).

---

## 1. Move "Invite friends" button to the Friends page + referral review

**Type:** Frontend-only move + a written answer to the referral questions. No API change.

### Findings (answers to "how many coins / do links work")
- **Rewards are double-sided:** referrer **1000 coins**, referee **500 coins**
  (`backend/src/modules/social/referralRewards.js:7-10`, env-overridable
  `REFERRAL_REFERRER_COINS`/`REFERRAL_REFEREE_COINS`). Granted on the referee's **first
  qualifying race completion** from the single settlement point
  (`completeRace.js:346`, team path `:214`). Qualify window 30d, daily cap 20, monthly cap 100.
  These are the *live* values; the older docs' 300/100 are stale. **No change requested.**
- **Links work** on iOS Universal Links (`ios/Runner/Runner.entitlements:28-31`) and Android
  App Links (`AndroidManifest.xml:65-92`), plus the `bara://` custom scheme. Frontend capture is
  complete (`deep_link_service.dart:126-179`).
- **One real gap:** the Play **app-signing** key SHA-256 is still a TODO
  (`backend/src/modules/web/sharing.js:34`). Until appended, Play-Store-installed Android users'
  `https://.../r/BARA-xxxx` links fall back to the browser landing page (the custom-scheme
  "Open in app" still works after install). **Follow-up, not blocking:** append the Play
  app-signing cert SHA-256 (Play Console → App integrity → App signing) to the assetlinks in
  `sharing.js`. Requires Rohan to provide the SHA — flagged, not implemented in this batch.

### Change
- **Remove** the invite `PillButton` block from `profile_tab.dart:413-451` (the "INVITE FRIENDS"
  section header + `PulseGlow`-wrapped button + `tutorialInviteKey` anchor).
- **Add** it to `friends_tab.dart` — a new `SliverToBoxAdapter` between the header and body
  slivers (~`:361-364`), or inside `_buildFriendsHeader` (`:391`). Keep the same tap target
  (push `ReferralScreen`), same copy ("INVITE FRIENDS & EARN COINS"), same `PulseGlow`.
- **Move `tutorialInviteKey`** with the button so the onboarding spotlight still anchors to a
  live widget (verify the tutorial step that references it doesn't crash if the key is on a
  different screen — if the tutorial only runs on the profile tab, drop that step or re-point it;
  frontend agent to confirm `tutorial` usages of `tutorialInviteKey`).
- Load design skills; match the friends-tab visual language.

### Tests
- Widget test: pump `FriendsTab` → the invite button renders and tapping it pushes
  `ReferralScreen`. Pump `ProfileTab` → the invite button is **absent**.

---

## 2. Public-races count includes featured (minus self-enrolled) + discoverable auto-enroll

**Owner decision:** *Count the featured daily/weekly races **and** the featured Daily Dash
bracket in "PUBLIC RACES (X)", keep them shown, **but do not count any the user is already
enrolled in.*** Also make the auto-enrollment toggle discoverable.

### Backend (contract)
- **Changed field, additive semantics:** `GET /races/discovery-summary` →
  `summary.publicRaceCount` (`getRaceDiscoverySummary.js`) is recomputed as:
  `publicRaceCount = (existing browsable public races, already excludes joined/full)`
  `+ (featured seeded daily/weekly races the viewer is NOT a participant of)`
  `+ (featured Daily Dash tournament brackets the viewer is NOT enrolled in)`.
  - Reuse `getFeaturedRaces.js` (it already knows joined vs not — it flips joined cards to
    VIEW/FULL rather than dropping them, so the count logic must **exclude** the ones where the
    viewer is a participant) and the featured-tournament source (`fetchPublicTournaments`'
    `featured`, filtered to brackets the viewer is not in).
  - Keep `getPublicRaceCount.js` / `getPublicRaces.js` (`/races/public`) **unchanged** — those
    still return only individual public races (old-client fallback path).
- **Old-client compat:** old apps compute the count from `fetchPublicRaces().length`
  (`main_shell.dart:1172-1183` legacy fallback) — they simply won't see the new inclusive number,
  which is acceptable degradation. New apps read `discovery-summary.publicRaceCount`.

### Frontend
- The "PUBLIC RACES (X)" label (`races_tab.dart:660`) already binds to
  `widget.publicRacesCount` ← `main_shell._publicRacesCount` ← `discovery-summary` (preferred
  path). No frontend count math change needed once the backend field is inclusive; verify the
  preferred path is used and the legacy fallback still degrades safely.
- **Auto-enroll discoverability (UX):** the toggle is currently buried behind a gear icon in a
  modal sheet (`public_races_screen.dart:842-869` → `_FeaturedSettingsSheet` → `_FeaturedAutoJoinToggle`).
  Replace gear-only access with a **visible, labeled toggle row/card** pinned at the top of the
  Public Races page (in/above the FEATURED section header), e.g. a parchment card:
  "🔁 Auto-join daily & weekly races" + a one-line explainer + a `CupertinoSwitch` bound to the
  same `authService.autoJoinFeaturedRaces` / `updateFeaturedAutoJoin` (no new state). Keep the
  existing sheet reachable too. Load design skills; make it obviously tappable.
- Tighten the featured grouping so the daily/weekly + bracket read as a deliberate "Featured"
  block, not stray items in the public list (dedicated section header already exists at
  `public_races_screen.dart:829` — polish, don't rebuild).

### Tests
- Backend integration: a viewer NOT in the featured race/bracket → `publicRaceCount` includes
  them; a viewer who IS enrolled → they are excluded from the count. `/races/public` list length
  unchanged.
- Frontend widget: the visible auto-join toggle renders on the Public Races page and flips
  `autoJoinFeaturedRaces`.

---

## 3. Dark-mode milestone cards: collected color + card layout

**Bug + layout.** File: `lib/widgets/step_milestones_section.dart`.

- **Color bug:** collected/claimed state uses `AppColors.of(context).success` → `grassDark`
  (dark value `0xFF29483B`, the muddy old dark green) in five spots (node `:322`, connector `:311`,
  check icon `:355`, "+coins" label `:404`, footer `:481`). Change the **collected** state to the
  "new blue" the app migrated to: `pillTerra` (dark `0xFF527486`, `styles.dart:394`) — the same
  slate-blue used by the home pull-to-refresh. Use a semantic accessor (add e.g.
  `Color get milestoneCollected => isDark ? pillTerra : success;` in `styles.dart` so light mode
  keeps green and only dark mode flips to blue) rather than hardcoding, to stay theme-correct in
  both modes.
- **Layout:** owner wants the milestones as **cards on the page**, not the single connected
  row/track. Re-lay the 5k/10k/15k/20k tiles as discrete cards (e.g. a wrap/grid of four small
  parchment cards) instead of the `_buildTrack` connected-node row. Load design skills; preserve
  all states (locked / claimable "TAP!" / claimed) and the existing claim tap behavior and data
  wiring (`_MilestoneTile`, home batch payload). Confetti rule: no confetti here (confetti only on
  race finishes, per prior guidance).

### Tests
- Widget test: pump `StepMilestonesSection` in dark mode with a claimed milestone → collected
  color is `pillTerra`, not `grassDark`; in light mode → stays green. Cards render as discrete
  tiles.

---

## 4. Pull-to-refresh: blue-in-dark everywhere (shared component)

**Regression.** Only `home_tab.dart:176-178` got the `isDark ? pillTerra : accent` treatment; the
other ~10 `RefreshIndicator`s still hardcode `accent` (green) and are illegible on night parchment.

- **Root cause:** no shared refresh component is actually used — each screen constructs its own
  `RefreshIndicator`. Fix by introducing a shared helper (e.g. `AppRefreshIndicator` in
  `lib/widgets/` or a `RefreshIndicator buildAppRefresh({onRefresh, child})` that applies
  `color: isDark ? pillTerra : accent`, `backgroundColor: parchment`) and route ALL sites through
  it: `races_tab.dart:376`, `leaderboard_tab.dart:348`, `profile_tab.dart:226`,
  `friends_tab.dart:356`, `shop_tab.dart:304`, `ranked_tab.dart:213`, `referral_screen.dart:194`,
  `race_detail_screen.dart:2596`, `public_races_screen.dart:519`, and `tab_layout.dart:131`
  (and migrate `home_tab.dart:176` onto the same helper so there's one source of truth).

### Tests
- Widget test: the shared helper yields `pillTerra` in dark, `accent` in light. Spot-check two
  screens (e.g. races + profile) render the helper.

---

## 5. BUG: stealthed players must not be targetable by manually-aimed powerups

**Owner:** integration test first (reproduce the bug), then fix.

### Root cause
Only `SNEAKY_SWAP` checks target stealth (`usePowerup.js:1550-1557`); every other manually
target-picked offensive powerup ignores it. And under Detour the leaderboard forces
`stealthed:false` for all rows (`getRaceProgress.js:721`), so the client's own stealth filter
(`team_race.dart:212`) is defeated and the stealthed racer appears as a selectable "???". The
**server guard is the real fix** (single source of truth, covers hand-crafted requests too).

### Fix (backend)
- Generalize the `SNEAKY_SWAP` stealth check to **all `TARGETED_TYPES`** (`usePowerup.js:76` =
  LEG_CRAMP, SHORTCUT, WRONG_TURN, DETOUR_SIGN, SNEAKY_SWAP, IMPOSTER, SIGNAL_JAMMER, LEECH,
  HITCHHIKE, DRILL_SERGEANT, BOUNTY — exactly the caller-supplies-`targetUserId` set).
  Add the guard in the generic targeted-validation block (~`:770`), **before** any coin
  deduction / mark-USED / effect creation, so the item stays HELD on rejection:
  `if (TARGETED_TYPES.includes(type)) { const s = await effectModel.findActiveByTypeForParticipant(targetParticipant.id, "STEALTH_MODE"); if (s) throw new PowerupUseError("You cannot target a stealthed player", 400, "TARGET_STEALTHED"); }`
- **Do NOT touch auto-targeted types** `RED_CARD` / `PINECONE_TOSS` (not in `TARGETED_TYPES`).
  The existing test `test/integration/powerups-stealth-redcard.test.js:145-213` asserts Red Card
  *does* land on a stealthed leader — **must stay green; do not edit it.**
- Server-computed → reaches all app versions instantly.

### Fix (frontend)
- Surface the `400 TARGET_STEALTHED` gracefully in `_usePowerup` (already shows error toasts) —
  friendly copy like "That racer is in stealth — pick someone else." Under Detour the picker can't
  self-filter, so this message is the user-visible guard.
- Item 12's atomic-refund fix (below) ensures a rejected cast returns the powerup to the general
  inventory rather than stranding it.

### Tests (write first, must fail before the fix)
- **Backend integration** (model on `powerups-stealth-mode.test.js`, assert through the HTTP
  endpoint): stealthed Bob; Alice holds LEG_CRAMP; `POST .../powerups/:id/use` with
  `targetUserId: bob` → **400 `TARGET_STEALTHED`**; Bob has no LEG_CRAMP effect; Alice's powerup
  is still available (not consumed). Add a second case for WRONG_TURN.
- Keep `powerups-stealth-redcard.test.js` untouched and green (Red Card still hits stealthed leader).

---

## 6. Race-detail: per-user multiplier badge + fire animation + high-multiplier push (LARGE)

**Owner decisions:**
- Show a **current multiplier** next to **every** user on race detail, reflecting stacking.
- **Fire** aura scales **per integer** (2x,3x,4x,5x… bigger each whole step); **nothing at 1x**;
  **frost/ice chip at 0x** (frozen); **reversed chip when negative** (Wrong Turn). No fire ≤1x.
- When a racer's multiplier crosses **> 4x**, send **one push to all OTHER active racers**
  ("🔥 {name}'s multiplier is stacked at {N}x — slow them down or catch up!"); **re-arm** only
  after their multiplier drops back to ≤4x. **No scoring/gameplay change** — display + push only.

### 6a. Backend: expose `currentMultiplier`
- In the existing per-participant loop (`getRaceProgress.js:370-410`, which already builds
  `groups` and calls `computeEffectModifiers`), also compute and attach a new **additive** field
  on each leaderboard entry:
  `currentMultiplier = signedMultiplierAt(nowMs, groups)` (the single source of truth,
  `services/effectMultiplier.js`), **then**, if a global 2x step event is active at `now`,
  multiply the *magnitude* by `GLOBAL_EVENT_MULTIPLIER` preserving sign (so pepper+RH+2x reads as
  10x, matching the owner's example; freeze stays 0; Wrong Turn stays negative).
- Semantics: `> 1` buffed, `1` neutral, `0` frozen, `< 0` reversed. Round for display client-side.
- **Compat:** old clients ignore the field; frontend must render nothing when it is absent/null.
- Do **not** serialize effect `metadata` (still not needed client-side); the client renders off
  `currentMultiplier` alone.

### 6b. Backend: high-multiplier push (once per spike, re-arm on drop)
- **Threshold:** `HIGH_MULTIPLIER_PUSH_THRESHOLD` (env, default `4`, strictly greater-than).
- **Dedup state (migration):** add nullable `highMultiplierNotifiedAt DateTime?
  @map("high_multiplier_notified_at")` to `RaceParticipant` (additive/nullable, matches the
  existing `lastNotifiedPlacement` pattern — old rows/clients unaffected).
- **Shared evaluator** `evaluateHighMultiplierAlert(participant, currentMultiplier)`:
  - If `currentMultiplier > THRESHOLD` and `highMultiplierNotifiedAt == null` → emit
    `HIGH_MULTIPLIER_ALERT` to all **other active, non-finished** participants with push tokens;
    set `highMultiplierNotifiedAt = now`.
  - If `currentMultiplier <= THRESHOLD` and `highMultiplierNotifiedAt != null` → clear it (re-arm).
- **Call sites:** (1) at powerup-use in `usePowerup.js` after a self-buff is created (recompute the
  caster's multiplier — the common spike cause), and (2) in the steps-sync progress recompute path
  (catches event-driven crossings and handles the re-arm when buffs decay). Both go through the one
  evaluator so behavior can't diverge.
- **Notification wiring:** new event type in the notifications module (`eventHandlers.js` /
  `notificationHandlers.js`, mirror `PLACEMENT_CHANGED`). Title/body always populated, so **any**
  app version renders it (push type is opaque to old clients). Route case added additively.
- **Kill switch:** `HIGH_MULTIPLIER_PUSH_DISABLED` (env, default `false`) — ship enabled but
  verify on staging first; can dark-flip without a deploy.
- **Rate/spam:** once-per-spike per racer via the flag; recipients are only the *other* racers.

### 6c. Frontend: multiplier badge + fire + cold states
- Row widget `LeaderboardPlank` (`lib/widgets/leaderboard_plank.dart`), built by
  `_buildLeaderboardPlank` (`race_detail_screen.dart:6466`). Read
  `participant['currentMultiplier']` **defensively** (null → render nothing new).
- **Badge:** a small "{N}x" chip in the name row (~`leaderboard_plank.dart:136`) for `>1`.
  `0` → frost/ice chip ("FROZEN"/❄), `<0` → reversed chip (↩). Nothing at exactly `1`/absent.
- **Fire aura:** around/behind the `AppAvatar`, size/intensity scaling **per integer**
  (`floor(multiplier)`), only for `>1`. Uses a **Codex-imagegen fire sprite/aura** (hand-drawn art
  is disallowed by CLAUDE.md). Animate via `AnimationController` + sprite-sheet like
  `capybara_walk_right.png` (pattern in `home_course_track.dart`); scale/opacity/frame off the
  multiplier, or crossfade a few generated sizes. Respect `MediaQuery.disableAnimations`
  (freeze like `arcade_fx.dart`).
- Show on **all** rows (including the viewer's).
- **Art task (Codex pipeline, `aesprite` repo):** generate a transparent fire sprite/aura sheet
  (warm palette, bold outline optional — this is FX not a worn accessory, so match app FX vibe),
  composite-on-white critique loop, install to `assets/images/` and glob in `pubspec.yaml`. The
  fire PNG only shows on app versions that bundle it; older clients simply show the badge-less/no-fire
  fallback (they don't get `currentMultiplier` anyway).

### Tests
- **Backend integration:** progress payload includes `currentMultiplier` per participant equal to
  `signedMultiplierAt(now,…)`; a stacked buff (e.g. RUNNERS_HIGH + GHOST_PEPPER) yields the summed
  value; an active global 2x event doubles the magnitude; a LEG_CRAMP'd racer reads `0`; a
  WRONG_TURN'd racer reads negative. Push: driving a caster above 4x emits one
  `HIGH_MULTIPLIER_ALERT` to the *other* participant and sets the flag; a second recompute while
  still >4x emits nothing; dropping to ≤4x clears the flag; crossing again re-emits.
- **Frontend widget:** pump race detail with a participant at `currentMultiplier` 3 → "3x" badge +
  fire tier 3; at 5 → tier 5; at 0 → frost chip, no fire; at -2 → reversed chip; absent → nothing.

---

## 7. Nerf stealth upgrade durations to 60/75/90/120 min (all users)

**Owner decision:** base **60m**, L1 **75m**, L2 **90m**, L3 **120m**, uniform across all app
versions. (Today stealth is 3h base for modern clients / 4h for old, up to 7–8h at L3 — this is a
large, deliberate cut. Server-computed → hits every version instantly on deploy.)

### Fix (backend)
- Set the stealth ladder in `powerupUpgrades.js` `DURATIONS_MS.STEALTH_MODE` to
  `[60, 75, 90, 120]` minutes (in ms).
- **Critical:** modern clients currently take the `RUNNERS_HIGH`-duration branch for stealth
  (`usePowerup.js:2441-2444`, gated on the `stealth_runner_duration` capability). Change **both**
  branches to use the stealth ladder — i.e. point the `stealth_runner_duration` branch at
  `upgradedDuration("STEALTH_MODE", level)` too (remove the RUNNERS_HIGH substitution for stealth).
  Do **not** edit `DURATIONS_MS.RUNNERS_HIGH` (that's the real Runner's High buff).
- Update the copy catalog expectation (`getPowerupCopyCatalog.js:53`) to the new durations.
- `DURATIONS_MS` is source (not balance-config) — respect the structural guard test.

### Tests
- Backend integration: cast stealth at L0/L1/L2/L3 with **both** a modern client
  (`stealth_runner_duration` feature header) and an old client → the STEALTH_MODE effect
  `expiresAt ≈ now + {60,75,90,120}min` in both cases. Update the copy-catalog test expectation.

---

## 8. Red Card back to 10% effect (odds unchanged)

**One-line server change.** `usePowerup.js:262` `RED_CARD_PERCENT = 0.05` → `0.10` (removes 10% of
the leader's steps again). Leave the **drop odds** `balanceConfig.defaults.js:262` `RED_CARD: 0.5`
untouched (owner: "keep the odds the same"). Server-computed → all clients.

### Tests
- Backend integration: Red Card on the leader removes 10% of their steps (asserts the new value).
- **Existing-test note (surface to Rohan):** if `powerups-red-card.test.js` asserts the 5%
  magnitude, that single expected constant must move to 10% because the owner explicitly changed
  the value in this spec. This is an owner-sanctioned expectation update (not a silent "fix");
  the backend agent must call it out in its summary. Do not alter unrelated assertions.

---

## 9. Shop: category pills + alphabetical default + sort-by

**Owner decision:** pills **All / Offense / Defense / Utility**; default order **alphabetical**;
add a **sort-by** dropdown with typical choices.

### Backend (contract — additive fields on the powerup catalog)
- `GET` powerup shop catalog (`getPowerupShopCatalog.js:87-97`) currently sends
  `{sku, name, description, priceCoins, powerupType, ownedQuantity}`. Add two **additive** fields:
  - `category`: `"offense" | "defense" | "utility"`, from a backend map keyed by `powerupType`
    (no migration — a code map like the existing `OFFENSIVE_TYPES`). Proposed mapping (backend
    agent finalizes against the live catalog):
    - **offense** = `TARGETED_TYPES` + `RED_CARD` + `PINECONE_TOSS` (anything that hits others).
    - **defense** = self-protection: `STEALTH_MODE`, umbrella/`RAINSTORM`-counter, `MIRROR`,
      `CLEANSE`, `POWER_OUTAGE`/jammer-counter, etc.
    - **utility** = the rest: `PIGGY_BANK`, `COIN_FLIP`, `RUNNERS_HIGH`, `GHOST_PEPPER`,
      `CAMPFIRE_REST`, `UPRISING`, `RALLY_FLAG`, `HITCHHIKE`, etc. (self-buffs + economy).
  - `rarity`: the existing `balanceConfig` rarity for that type (`COMMON|RARE|EPIC|LEGENDARY`),
    surfaced for the sort-by-rarity option.
- **Compat:** additive; old clients ignore both; the frontend must default a missing `category` to
  "utility" (or an "Other" bucket) so an older backend still renders.

### Frontend
- On the powerups store view (`shop_tab.dart` `_buildStore` powerups case, `:933`):
  - **Category pills** `[All] [Offense] [Defense] [Utility]`, filtering `_powerupStoreItems` by
    `item.category` (mirror the existing category-pill pattern `_buildCategoryPills:461`).
  - **Default sort alphabetical** by `name` (currently no client sort — renders backend order).
  - **Sort-by dropdown** with typical choices: **Name (A–Z)** [default], **Price: Low→High**,
    **Price: High→Low**, **Rarity**. Persist the selection in screen state.
- Load design skills for the pill/dropdown styling.

### Tests
- Backend: catalog response includes `category` + `rarity` per item; every live powerup maps to
  exactly one category.
- Frontend widget: pump shop → pills render; tapping "Offense" shows only offense items; default
  order is alphabetical; switching sort-by to Price reorders ascending; to Rarity reorders by rarity.

---

## 10. Shop: "watch ads to afford it" (scaled ads, zero-out coins) or +coins

**Owner decision:** when a user is within **≤150 coins** of a powerup, offer to watch ads — **1 ad
per ~50 coins short, capped at 3** — and on completing them, **zero out all their coins** and grant
the powerup. If **>150 short**, route to the **+coins / Get Coins page** instead. UX-friendly.

### Ad count
`adsNeeded = min(3, ceil(shortfall / 50))` where `shortfall = priceCoins - coins` and
`0 < shortfall ≤ 150`. (≤50→1, ≤100→2, ≤150→3.)

### Frontend
- On an unaffordable powerup store tile (`_storePowerupTile`, `shop_tab.dart:840`):
  - `shortfall ≤ 150`: show a clear "🎬 Watch {N} ad{s} to unlock" affordance. On tap, loop the
    rewarded ad `adsNeeded` times (`ExtraSpinAdController.load` + `showAndAwaitReward`), showing
    progress ("Ad 1 of 3"). On **all** rewards granted, call the new unlock endpoint; on success
    update coins→0 and inventory. If the user bails mid-way, no grant, no coin change.
  - `shortfall > 150`: the CTA routes to `get_coins_screen.dart` (the +coins hub).
- **Ad unit:** prefer a **new dedicated** rewarded unit
  `ADMOB_POWERUP_UNLOCK_AD_UNIT_ID[_ANDROID]` (added to `ad_service.dart` alongside the others,
  injected via `--dart-define` per DEPLOYMENT.md). **Fallback:** if the define is absent, reuse the
  existing extra-spin rewarded unit / test IDs so the flow is never blocked on Rohan creating the
  unit (like the OAuth-client pattern). *Rohan action: create the AdMob unit and provide the ID +
  configure its SSV callback.*

### Backend (contract — new endpoint, SSV-verified)
- `POST /shop/powerups/unlock-with-ads` — body `{ sku, idempotencyKey }`, `Idempotency-Key` header.
  Server logic (single transaction):
  1. Recompute `shortfall = priceCoins - coins`; reject `409/400` if `shortfall <= 0` (they can
     just buy it) or `shortfall > 150`.
  2. Require `adsNeeded = min(3, ceil(shortfall/50))` **SSV-verified** ad watches attributed to
     this flow. Reuse the existing AdMob SSV mechanism (as `claimAdCoinReward.js` does): each ad's
     server-side callback carries `custom_data = "powerup_unlock:{userId}:{sku}"`; the backend
     accrues verified watches; the endpoint only grants when `>= adsNeeded` verified watches exist
     for this user+sku and have not been consumed.
  3. On success: set `coins = 0`, increment `UserPowerupItem` for the `powerupType`, consume the
     verified watches, write a coin-ledger entry (audit), return updated `{coins, inventory}`.
  4. Idempotent on `idempotencyKey` (retry returns the same result, never double-grants).
- **Compat:** new endpoint; old clients never call it. Ship backend first. Fixed-amount
  `claim-ad-reward` remains unchanged for the existing watch-ad-for-coins flow.
- **Guardrail:** because this zeroes coins, the server is the authority on `shortfall` and the ad
  count — never trust client-sent amounts. SSV is mandatory (no client-attested "I watched 3 ads").

### Tests
- Backend integration: with `adsNeeded` SSV-verified watches and `shortfall ≤ 150` → grants
  powerup, `coins→0`, idempotent on retry; missing a verified watch → rejected, no grant, coins
  unchanged; `shortfall > 150` → rejected (client should have routed to +coins); `shortfall ≤ 0`
  → rejected.
- Frontend widget: tile at shortfall 120 shows "Watch 3 ads"; at 40 shows "Watch 1 ad"; at 300
  shows the +coins route; completing the ads calls unlock and updates the UI.

---

## 11. Races tab: move buff/debuff badges inline with the boxes (+ "|" separator)

**Frontend-only.** File: `races_tab.dart`. No backend change (`myActiveEffects` already flows on
`GET /races`).

- Currently the `effectCluster` (BOOSTS/DEBUFFS plates, `_buildEffectCluster:1594`) renders on the
  **time-left row** (`:1494-1497`). Move it onto the **boxes row** (`_buildInventoryRow:1670`, called
  at `:1513`). Wrap both in one outer `Row` (both are `mainAxisSize:min`, matching 18–20px scale):
  `[ _buildInventoryRow(...), if (effectCluster != null) ...[ separator, effectCluster ] ]`.
- **Separator:** a slim "|" (muted `textMid`/parchment tone, ~6–8px symmetric padding) between the
  boxes and the badges. Gate the separator on `effectCluster != null` (both null-paths already
  exist — no effects → no cluster → no separator).
- Load design skills; keep it tidy on narrow rows.

### Tests
- Widget test: an ACTIVE race row with both effects and boxes renders boxes + "|" + badges in one
  row; a row with no active effects renders boxes only, no separator; a row with effects but no
  boxes still renders the badges.

---

## 12. BUG: rejected shop-powerup use strands the item in the race inventory

**Owner:** using a shop powerup that isn't allowed *here* must return it to the **general**
inventory (usable in another race), not leave it bound to this race.

### Root cause
The flow is two-step: `POST .../powerups/redeem` (`redeemPowerupToRace.js`) decrements
`UserPowerupItem` (general) and mints a `HELD` `RacePowerup` bound to the race, then `POST .../use`
(`usePowerup.js`). If `use` rejects (Red Card while not leading, invalid/blocked target, capability
gate, etc.), the `HELD` `RacePowerup` stays bound to that race — stranded. The redeem pre-flight
only mirrors 3 of the many rejection reasons, and there is no un-redeem path.

### Fix (backend — fixes ALL clients, no contract change)
- In `usePowerup.js`, when a `PowerupUseError` is thrown **before** the powerup is marked USED,
  and the `RacePowerup` being used is a **redeemed** one (redeemed items have `rarity == null` and
  `earnedAtSteps == null`, per `redeemPowerupToRace.js:119-123`), **refund it to the general
  inventory within the same transaction**: set that `RacePowerup` `status = "DISCARDED"` and
  `increment` the matching `UserPowerupItem.quantity` by 1. Net effect: a not-allowed-here cast
  returns the powerup to the general pool so it can be redeemed into another race.
- **Do NOT refund box-earned `RacePowerup`s** (`rarity != null` / `earnedAtSteps != null`) — those
  are legitimately race-bound; they stay HELD on rejection as today.
- Server-side + transactional → fixes frozen old clients too (their existing redeem-then-use flow
  now self-heals on rejection). No API shape change.
- Idempotency/atomicity: do the refund in the same DB transaction as the rejection unwind so a
  failure can't double-refund or lose the item.

### Tests
- Backend integration: user redeems + uses a **shop** powerup that `usePowerup` rejects (e.g. Red
  Card while not leading, or an invalid target) → afterward the `UserPowerupItem` quantity is
  restored, no `HELD` `RacePowerup` remains bound to the race, and it can be redeemed into a
  different race. Separate case: a **box-earned** HELD powerup that's rejected stays HELD (not
  refunded).

---

## Global API contract (new/changed — the interface between the two agents)

| Item | Endpoint / field | Shape | Compat |
|---|---|---|---|
| 2 | `GET /races/discovery-summary` `.publicRaceCount` | int, now includes featured races + brackets viewer is NOT enrolled in | additive semantics; old clients use `/races/public` length fallback |
| 5 | `POST /races/:id/powerups/:pid/use` | new `400 {code:"TARGET_STEALTHED"}` for TARGETED_TYPES vs a stealthed target | new error case; old clients show generic error |
| 6 | progress payload leaderboard entries | new `currentMultiplier` (number; >1 buff, 1 neutral, 0 frozen, <0 reversed; global-event-inclusive) | additive nullable; render nothing if absent |
| 6 | push | new `HIGH_MULTIPLIER_ALERT` type, title/body populated | opaque type; any client renders title/body |
| 8 | — | server constant change only | none |
| 9 | powerup shop catalog items | new `category` (`offense\|defense\|utility`) + `rarity` | additive; default missing category → utility |
| 10 | `POST /shop/powerups/unlock-with-ads` | body `{sku, idempotencyKey}`; SSV-verified; sets coins→0 + grants | new endpoint; old clients never call |
| 7,8,12 | — | server-side behavior changes, no shape change | reach all clients |

**Contract-first sequencing:** the backend agent pins and lands all of the above (fields,
endpoint, error code, push type, migration) **before** the frontend agent codes against them.

---

## Data model / migrations

- **Item 6:** add `RaceParticipant.highMultiplierNotifiedAt DateTime? @map("high_multiplier_notified_at")`
  (additive/nullable, no backfill). `prisma migrate deploy` + `generate` on deploy.
- No other schema changes (item 9 category/rarity are code maps + config reads; item 10 reuses the
  SSV/ledger tables — confirm the ad-watch verification table can carry the `powerup_unlock:`
  custom-data tag, else add a small pending-watch row; backend agent decides during contract).

---

## Backward-compat & rollout

1. **Deploy backend first** (all items with a backend part: 2, 5, 6, 7, 8, 9, 10, 12), behind:
   - `HIGH_MULTIPLIER_PUSH_DISABLED=false` (verify on staging, dark-flip if noisy),
   - `HIGH_MULTIPLIER_PUSH_THRESHOLD=4`.
   - Run migration (item 6) + `prisma generate`. Deploy via `pm2 reload` (zero-downtime).
2. **Then ship the app** (frontend parts: 1, 2-toggle, 3, 4, 6-UI+fire, 9, 10, 11) — **iOS + Android
   in lockstep** (`flutter build ipa` + `flutter build appbundle --flavor prod`), version bump,
   backend URL + defines in sync. Item 10 needs `ADMOB_POWERUP_UNLOCK_AD_UNIT_ID[_ANDROID]` defines
   (fallback to test/extra-spin unit if absent). Item 6 fire PNG must be bundled in this build.
3. **Frozen old clients** after backend deploy: get items 5/7/8/12 automatically (server-side);
   ignore `currentMultiplier`/`category`/`rarity` (no badge/fire/pills); still receive the
   `HIGH_MULTIPLIER_ALERT` push (title/body render); never call the new unlock endpoint.
4. **Rohan manual follow-ups (non-blocking):** Play app-signing SHA-256 for item 1 App-Links;
   create the item-10 AdMob rewarded unit + SSV callback; generate/approve the item-6 fire art via
   the Codex pipeline.

---

## Test plan (tests-first, per agent)

**Backend (write failing tests first; `test:unit`/`test:integration`, never bare `npm test`,
never the prod DB):**
- 5: stealth rejects TARGETED cast (400 TARGET_STEALTHED); Red Card still hits stealthed leader
  (unchanged test stays green).
- 6: `currentMultiplier` per participant (stacked/global-event/frozen/reversed); push fires once
  per >4x spike to others + re-arms.
- 7: stealth durations 60/75/90/120 for modern + old clients; copy-catalog expectation updated.
- 8: Red Card removes 10%.
- 9: catalog exposes category + rarity, total mapping coverage.
- 10: unlock grants + zeroes coins with SSV watches; rejects >150 / insufficient watches;
  idempotent.
- 12: rejected shop-powerup refunds to general inventory; box-earned stays HELD.

**Frontend (pump real screens/widgets):**
- 1: invite button on Friends, absent on Profile.
- 2: visible auto-join toggle flips state.
- 3: dark collected color = pillTerra; light stays green; discrete cards.
- 4: shared refresh helper → pillTerra dark / accent light across screens.
- 6: badge + per-integer fire; frost at 0; reversed at <0; nothing when absent.
- 9: pills filter; alphabetical default; sort-by reorders.
- 10: ad-count affordance vs +coins route; unlock updates UI.
- 11: badges inline with boxes + separator gating.

---

## Acceptance criteria (definition of done)

- [ ] 1 — Invite button moved to Friends (gone from Profile), tutorial anchor intact; referral
      Q&A documented; Play-SHA gap flagged to Rohan.
- [ ] 2 — `publicRaceCount` includes featured races + brackets the viewer is NOT enrolled in;
      auto-join toggle is visibly discoverable on the Public Races page.
- [ ] 3 — Collected milestones render `pillTerra` in dark / green in light; milestones are discrete
      cards.
- [ ] 4 — All pull-to-refresh indicators use the shared helper (blue-in-dark, green-in-light).
- [ ] 5 — Stealthed targets can't be hit by any TARGETED powerup (server-enforced); Red Card
      unchanged; repro test written first.
- [ ] 6 — Every race-detail row shows its current (stacked, event-inclusive) multiplier with
      per-integer fire (>1x), frost (0), reversed (<0); >4x pushes other racers once per spike.
      No scoring change.
- [ ] 7 — Stealth durations are 60/75/90/120 min for all clients.
- [ ] 8 — Red Card removes 10%; drop odds unchanged.
- [ ] 9 — Shop has Offense/Defense/Utility pills, alphabetical default, and a sort-by dropdown.
- [ ] 10 — ≤150-short users can unlock via scaled ads (1–3, coins→0, SSV-verified); >150 routes to
      +coins.
- [ ] 11 — Race-list buff/debuff badges sit inline with the boxes, separated by "|".
- [ ] 12 — A rejected shop-powerup returns to the general inventory (usable in another race).
- [ ] Both platforms build; backend deployed first behind switches; no existing test modified
      except the owner-sanctioned Red Card magnitude expectation (item 8, surfaced explicitly).

---

## Revision log

**Gap pass 1 (fresh-eyes) changed:**
- Item 6: pinned that `currentMultiplier` must fold in the active **global 2x event** (owner's
  "pepper+RH+2x=10x" example) rather than being the raw `signedMultiplierAt` — added the
  sign-preserving magnitude-doubling rule and the 0/neutral/negative semantics table.
- Item 6 push: replaced a naive "check at read time" with a **shared evaluator + persisted
  `highMultiplierNotifiedAt` flag** called from both powerup-use and steps-sync, so "once per
  spike + re-arm on drop" is deterministic and can't double-fire; added the kill switch + threshold
  envs.
- Item 5: constrained the guard to `TARGETED_TYPES` (verified membership) so auto-targeted Red
  Card/Pinecone keep hitting stealthed leaders — protecting the existing
  `powerups-stealth-redcard.test.js` (do-not-edit).
- Item 12: chose the **server-side refund-on-rejection** approach over a new atomic endpoint,
  specifically because it also fixes frozen old clients (no app update required) — and scoped it to
  redeemed (not box-earned) powerups via the `rarity==null && earnedAtSteps==null` marker.

**Gap pass 2 (fresh-eyes) changed:**
- Item 8: flagged the tests-first tension — changing `RED_CARD_PERCENT` will fail an existing 5%
  assertion; specified this as an owner-sanctioned expectation update the agent must surface, not a
  silent test "fix" (respects the never-modify-tests rule via explicit approval).
- Item 2: clarified "not counted if enrolled" precisely for both the seeded featured **races**
  (viewer not a participant) and the **tournament bracket** (viewer not enrolled), and noted
  `getFeaturedRaces` keeps joined cards (so the count path must filter them, not rely on the source
  dropping them).
- Item 7: called out that editing `DURATIONS_MS.STEALTH_MODE` alone is insufficient because modern
  clients take the `RUNNERS_HIGH` branch — both branches must point at the stealth ladder, and
  `DURATIONS_MS.RUNNERS_HIGH` must NOT be touched.
- Item 10: hardened the backend as the authority on `shortfall` + ad count with mandatory SSV
  (custom-data tag), idempotency, and a coin-ledger audit — since the flow zeroes a real balance;
  added the AdMob-unit fallback so the app isn't blocked on Rohan creating the unit.
- Item 1: downgraded the Play app-signing App-Link fix to an explicit non-blocking Rohan follow-up
  (needs a SHA only Rohan can pull), keeping this item a pure frontend move + documented Q&A.
- Item 4: specified a single shared refresh helper (not per-site conditionals) as the fix, since
  the root cause is the absence of a reused component.
