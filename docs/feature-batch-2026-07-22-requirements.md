# Ads, Admin Metrics, Settings, Home Motion, Powerups, and Pushes

Status: Approved by owner on 2026-07-22; implementation authorized, production deployment is not
Date: 2026-07-22
Repositories: `stepv2-frontend` and `stepv2-backend`

## 1. Summary and user stories

This batch contains ten product changes and investigations:

1. Retain the bottom banner on race mystery-box and daily-reward spin screens and
   add a second banner at the top under a staged, remotely killable rollout.
2. Show how many daily active users watch a rewarded ad for coins and how many
   watch one for an extra daily spin in Admin Statistics.
3. Replace the profile Settings bottom sheet with a full pushed page.
4. Move the home-scene clouds right-to-left and add more clouds in both themes so
   the right-facing Bara reads as walking forward.
5. Make every active, client-compatible shop powerup winnable in the daily spin,
   with higher-priced powerups less likely than lower-priced powerups.
6. Make bottom-navigation labels and icons white in light mode.
7. Make new-client Stealth Mode durations equal Runner's High durations and keep
   every description/tier label truthful without changing frozen-client behavior.
8. Prove that tapping a powerup-attack push opens the attacked race and include
   the race name in that push.
9. Make Hitchhike copy the target's effective step direction/multiplier: Runner's
   High helps the hitchhiker and Wrong Turn hurts the hitchhiker.
10. Add a store powerup named **Quicksand**:
    a multi-target Leg Cramp that can affect up to three rivals and costs the same
    as Leech.

User stories:

- As a player opening a box, I see sponsor placements at both screen edges without
  either covering the centered wheel or its controls.
- As an operator, I can see rewarded-ad adoption among actual daily users.
- As a player, Settings behaves like a navigable destination rather than a cramped
  drawer.
- As a player looking at the home hero, the environmental motion reinforces Bara's
  walk direction in day and night themes.
- As a player reading daily-spin odds, the list exactly matches the server's live,
  client-compatible prize pool.
- As a light-mode user, I can read every bottom-navigation label.
- As a Stealth Mode user, its duration and copy agree at every tier.
- As a player who was attacked, the push names the race and opens that exact race.
- As a Hitchhike user, I inherit both the upside and downside of the target's
  step-affecting state.
- As a Quicksand buyer, I can select several valid opponents and see a clear result
  for each target from one use.

The governing constraint is the repository's first rule: a backend change must not
break or silently change the contract understood by app binaries already in the
wild. Backend changes below are additive or request-capability-versioned.

## 2. Scope and non-goals

### In scope

- iOS and Android Flutter behavior in lockstep.
- Backend/API/data work needed for Admin Statistics, daily-spin eligibility,
  capability-versioned Stealth, attack pushes, Hitchhike scoring, and Quicksand.
- Day and night home-cloud assets and motion.
- Exact player-facing copy, odds, loading/error/empty states, push payloads, and
  accessibility behavior.
- Tests-first implementation through real HTTP routes and real screens/widgets.

### Non-goals

- Production deployment or production database writes. Those require a separate,
  in-the-moment approval under the backend `CLAUDE.md`.
- Changing rewarded-ad payout amount, daily cap, SSV verification, banner refresh
  rate, ad mediation, or any existing ad-unit ID. A dedicated top-placement unit is
  added without replacing the current footer unit.
- Adding ads to any screen other than the three box-opening routes named in §3.
- Redesigning the profile page apart from how it opens Settings.
- Changing Bara's walk sprite, speed, or orientation.
- Changing in-race mystery-box `dropPool`; §7 concerns the **daily reward box**.
- Recomputing or rewriting historical race totals or already-created timed effects.
- Making Quicksand upgradeable unless the owner explicitly adds that requirement.
- Hand-drawing cloud or Quicksand artwork. Repository art rules require the Codex
  imagegen pipeline and human critique loop.

## 3. Dual banners on box-opening screens and policy assessment

### 3.1 Current state

- Single race box: `lib/screens/case_opening_screen.dart:258-283` places one
  `AdBannerSlot` after the expanded, scrollable opening/reveal content.
- Race **Open All**: `lib/screens/multi_case_opening_screen.dart:155-174` uses the
  same footer placement.
- Daily reward: `lib/screens/daily_reward_screen.dart:331-361` places one footer
  banner below every daily-reward state, including the reel at `:602-713`.
- `AdBannerSlot` is a standard 320x50 `BannerAd` and never clips or overlays the ad
  creative (`lib/widgets/ad_banner_slot.dart:69-130`). It currently collapses to
  zero until load succeeds (`:134-140`), which can shift content when the ad arrives.

### 3.2 Policy conclusion

A banner anchored at the **top** is not inherently prohibited. Google's official
banner documentation expressly supports top or bottom anchored banners. However,
Google warns against banners adjacent to interactive controls, on continuously
interactive gameplay screens, or appearing late and shifting content under a user's
finger. It recommends clear non-clickable separation and a reserved slot:

- [Banner ad guidance](https://support.google.com/admob/answer/6128877)
- [Recommended banner implementations](https://support.google.com/admob/answer/6275335)
- [Discouraged banner implementations](https://support.google.com/admob/answer/6275345)
- [Confirmed Click causes](https://support.google.com/admob/answer/10094971)

The owner selected simultaneous top and bottom banners to increase impression
opportunities. Google does not state a one-banner-per-screen limit, so the count alone
is not a TOS violation. This remains a higher-risk placement than one banner because
the content is interactive and two ads increase density and proximity. It therefore
ships behind a separate kill switch and is judged by traffic quality and engagement,
not impressions alone.

This is a policy-risk assessment, not a guarantee from Google. The compliant design
requirements are:

- Exactly two visible banners per box-opening route while both banner flags are enabled:
  one at the top and the existing one at the bottom.
- Place both inside `SafeArea`, outside the centered wheel/reel overlay, and never as
  floating/overlay nodes over game content.
- Give each an opaque, non-clickable separator/border and at least 12 logical pixels
  between the ad frame and the nearest interactive content.
- Keep close, odds, guide, swipe reel, Continue, and Open All controls outside that
  separation region.
- On banner-enabled builds, reserve both slots before asynchronous loads start so
  content never jumps into a late-arriving ad. If a request fails, leave that reserved
  neutral trackside band in place for the route visit; an unconfigured placement
  renders zero height.
- Never cover, crop, recolor, transform, or add a custom close control to the ad.
- Do not create or refresh the banner in response to the player's spin/swipe gesture;
  its lifecycle is route-scoped so ad appearance cannot be mistaken for part of the
  rewarded interaction.
- Retain the existing bottom ad unit and `bannerAdsEnabled` master switch. Add dedicated
  iOS/Android top-placement ad-unit IDs (`ADMOB_BOX_TOP_BANNER_AD_UNIT_ID` and
  `ADMOB_BOX_TOP_BANNER_AD_UNIT_ID_ANDROID`) and additive remote setting
  `dualBoxBannersEnabled`, default `false`. The top slot requires both flags and a valid
  platform ID; the bottom slot continues to follow the master flag. Old clients ignore
  the additive setting.
- Update `DEPLOYMENT.md` and release commands. A production build missing either new
  platform ID must safely show only the bottom banner; test IDs must never enter a
  production archive.

### 3.3 Frontend plan

- Add a placement/reservation option to `AdBannerSlot`, defaulting to today's
  collapse behavior so every unrelated placement remains byte-for-byte unchanged.
- In the three hosts above, order the route as `top SafeArea -> reserved top
  AdBannerSlot -> non-clickable gap -> Expanded(center content) -> non-clickable gap
  -> reserved bottom AdBannerSlot -> bottom SafeArea`. Retain the footer instance.
- Preserve `PopScope` spin guards and all scroll behavior. Very small devices must
  scroll the cabinet rather than clip it.
- Loading/no-fill/error: the ad host handles these without blocking the box action.
- Add `dualBoxBannersEnabled` to the backend settings allowlist, `/auth/me` app-settings
  envelope, Admin Settings toggle, and defensive Flutter reader. Missing/null/malformed
  values mean `false`.

Additive settings contract:

```json
{
  "featureFlags": {
    "bannerAdsEnabled": true,
    "dualBoxBannersEnabled": true
  }
}
```

`GET /admin/settings` includes the same boolean; `PATCH /admin/settings` accepts
`{"dualBoxBannersEnabled": true|false}` under the existing admin authorization and
validation/error contract. Older backends omit it, new clients default it off, and old
clients ignore it.

### 3.4 Tests first

- Frontend widget tests pump each route and assert exactly two `AdBannerSlot`s when both
  flags are on, one above and one below the opening content and both outside the
  scrollable cabinet. Master-off yields none; dual-off yields the existing bottom one.
- A fake delayed load proves no opening content changes global position.
- Banner-disabled builds contribute zero height; enabled/no-fill contributes the
  reserved band and never blocks close/back.
- Spin, reveal, Open All, and daily extra-spin tests continue to pass unmodified.
- Manual policy QA on smallest supported iPhone and Android sizes, large text, both
  orientations supported by the app, and reduced motion.

Known existing-test extension: `test/ad_placements_test.dart` currently guarantees the
daily footer exists outside the reward card. That behavior remains valid. Preserve it
unchanged and add dual-flag tests for the additional top placement; do not delete or
weaken the existing footer assertion.

## 4. Admin rewarded-ad DAU metrics

### 4.1 Definition

The existing DAU definition is “distinct users with a `steps` row for today's
America/New_York date” (`stepv2-backend/src/modules/admin/getAdminStats.js:9-48`).
Keep that denominator unchanged.

For each rewarded placement, report distinct users who are in that DAU set and had
a verified `ad_reward_grants` row created today in America/New_York:

- coin ad: `reward_kind = "coin_reward"`
- extra spin ad: `reward_kind = "extra_daily_spin"`

Count the verified watch even if the later redemption is still pending; `createdAt`
is written only after signed SSV succeeds (`grantAdReward.js:12-63`). Multiple watches
by one user count once per placement. Return both count and percentage of DAU.

### 4.2 API contract: additive `GET /admin/stats`

Existing keys remain unchanged. Add:

```json
{
  "stats": {
    "activity": {
      "dauToday": 120,
      "rewardedAds": {
        "timeZone": "America/New_York",
        "coinReward": { "uniqueDauWatchers": 18, "pctOfDau": 15 },
        "extraSpin": { "uniqueDauWatchers": 9, "pctOfDau": 8 }
      }
    }
  }
}
```

- Values are non-negative integers. Percentage is rounded to the nearest integer;
  denominator zero returns `0`, never `NaN`/`null`.
- Authorization and error contract stay as today: admin only; `500
  {"error":"Internal server error"}` for an unexpected query failure.
- Old backends omit `rewardedAds`; the new admin UI renders em dashes. Old apps ignore
  the additive object.

### 4.3 Data/query/frontend plan

- No migration: `AdRewardGrant.rewardKind`, `createdAt`, and `userId` already exist
  (`prisma/schema.prisma:202-231`).
- Extend `getAdminStats.js` with one grouped SQL query or CTE intersecting today's
  DAU IDs with today's verified grant rows. Do not use client-supplied `grantedDate`
  as the ET reporting boundary.
- Extend `_AdminStatsCard` at `lib/screens/admin_screen.dart:365-437` with two rows:
  `DAU watched coin ad` and `DAU watched extra-spin ad`, displaying `count (pct%)`.
- Loading/error for the whole card remains unchanged; a missing/malformed nested
  field affects only these two rows.

### 4.4 Tests first

- Backend integration test through authenticated `GET /admin/stats`: same user with
  several watches counts once; non-DAU watcher is excluded; both reward kinds stay
  disjoint; yesterday ET is excluded; zero DAU yields zero percentages.
- Frontend widget test: complete fields render; older response omits the two values
  safely; numeric strings or malformed objects do not throw.

## 5. Settings as a full page

### 5.1 Current state and required experience

`ProfileTab._openSettings` uses `showModalBottomSheet` and builds private
`_SettingsSheet` (`lib/screens/tabs/profile_tab.dart:124-141,787-1025`). Move the
same functions into a pushed `SettingsScreen` in
`lib/screens/settings_screen.dart`.

- The profile's `SETTINGS` button pushes a normal route with a visible back button.
- Use the app's existing game/arcade visual language, safe areas, and a scrollable
  content board; do not introduce a generic Material settings list.
- Preserve Edit Display Name, appearance, notification permission, daily-reward
  reminder, leaderboard visibility, Admin Tools, tutorial, support, privacy, sign
  out, and delete-account behavior.
- Nested pages push on top of Settings. They must not pop Settings first.
- When Settings returns, Profile refreshes once and `onSettingsChanged` synchronizes
  shell state. Sign-out/delete still remove the authenticated stack.
- Loading/error states for the two server-backed toggles stay local to their rows;
  an older backend cannot crash or blank the page.

### 5.2 API/data and tests

No API or migration change.

- Frontend widget test opens Settings and proves it is a pushed page, supports system
  back/iOS swipe-back, and restores Profile.
- Port existing settings-sheet tests without weakening their behavior assertions.
  The inspected settings tests open via the public `SETTINGS` control and assert the
  behaviors inside, not the bottom-sheet container, so they should remain valid with
  only navigation settling adjusted if necessary.
- Tests cover nested Display Name/Admin/Tutorial navigation, local toggle errors,
  sign-out, delete confirmation, small screens, and large text.

## 6. Home clouds: direction, density, day/night

### 6.1 Current state

`HomeHeroScene` runs a 60-second ambient controller and freezes it for reduced motion
(`lib/widgets/home_hero_scene.dart:35-60`). `_DriftCloudsPainter` draws two clouds and
moves them left-to-right (`:165-223`). The user wants the opposite visual flow.

### 6.2 Required experience and art plan

- Clouds move **right-to-left**, opposite Bara's right-facing travel, with seamless
  off-screen wrap and no jump at loop boundaries.
- Five total instances (three more than today), distributed at
  different heights, scales, phases, and integer loop rates. Keep the step-count HUD
  unobstructed and the ground horizon readable.
- Both day and night themes receive purpose-made transparent cloud assets. Night clouds
  should read as moonlit, not as day-white shapes recolored in code.
- Generate `assets/images/home_clouds_day.png` and
  `assets/images/home_clouds_night.png` (sprite strip or atlas) through the Codex
  imagegen chroma-key workflow in a scratch directory, critique on white and on both
  real sky assets, then install. Do not add pictorial `CustomPainter` code.
- Replace `_DriftCloudsPainter` with positioned asset instances; animation/layout code
  is allowed. Preserve pixel filtering and precache both assets.
- `MediaQuery.disableAnimations` freezes the cloud field at a deterministic composition;
  theme switches cross-fade assets without resetting positions.

### 6.3 Tests first

- Widget/animation test samples two controller values and proves every moving cloud's
  wrapped x-coordinate decreases.
- Exactly five cloud instances exist in day and night; switching theme swaps assets
  without changing layout count.
- Reduced motion pumps no ambient frames and displays the deterministic composition.
- Golden/manual checks at narrow/wide sizes ensure clouds do not obscure the HUD/Bara.

## 7. Daily-spin shop-powerup eligibility audit

### 7.1 Answer from current source

**No, not all shop powerups are in the daily spin.** The daily prize pool starts from
active, release-channel-visible `PowerupShopItem` rows, then applies feature gates and
`dailyBoxExcludedTypes` (`getEligiblePowerupPool.js:4-41`). The committed live-config
record explicitly excludes `DEFENSE_SCAN`, `LEECH`, `HITCHHIKE`, and `QUICK_RINSE`
(`stepv2-backend/data/balance-config.json:66-80`). In a nominal capable production
client, the only store-only types not excluded by that list are Imposter, Rainstorm,
and Signal Jammer; runtime `active`, `testOnly`, and kill-switch state can reduce that
pool further. The odds endpoint correctly reports the filtered pool it actually rolls
(`getDailyRewardStatus.js:105-198`), so the complaint is about product eligibility,
not a display-only probability mismatch.

### 7.2 Required change

The owner confirmed that every active, request-compatible shop powerup should be
winnable, with relative rarity based on price:

- Remove the four shipped exclusions from `dailyBoxExcludedTypes`; include Quicksand
  after its carrying build is eligible.
- Extend `spinPowerupFlags` and `getEligiblePowerupPool` with request-scoped
  `supportsPowerups2`, `supportsPowerups3`, and `supportsPowerups4` gates. Removing the
  exclusions without these gates would let an older `spinpowerups` client win a type it
  cannot render or target.
- Apply the identical filtered snapshot to `/status`, `/claim-box`, and
  `/claim-extra-box`; never calculate preview odds and payout pools differently.
- Keep `active:false`, `testOnly:true`, release channel, and per-feature visibility
  authoritative. “All” means all active items safe for **that request's binary**, not
  retired or dark-launch items.
- Fix the Imposter inconsistency: its global disabled-catalog predicate must also
  remove it from the daily pool while disabled.
- `box.powerupPool` and `box.itemOdds.powerups` remain the exact source of truth; no
  frontend hardcoded list is added.
- Keep shop powerups inside the daily box's existing `RARE -> POWERUP` branch. Within
  that branch, use the existing inverse-price weighting shared with accessories:
  `weight = 1 / priceCoins^(1 + streakProgress)`. This makes a 150-coin item less
  likely than a 75-coin item and a 300-coin item less likely than both, without turning
  cheap store-only attacks into COMMON/UNCOMMON outcomes or changing the advertised
  top-level rarity curve.
- The same config snapshot and price values must drive preview probabilities and the
  eventual weighted pick. Admin price changes therefore update relative daily odds
  automatically on the next config/catalog read; no separate rarity table may drift.

#### Full-outcome probability under the existing algorithm

These are not fixed percentages. The top-level RARE chance rises linearly from 5% on
streak day 1 to 45% on day 30. When the player has at least one unowned accessory, half
of RARE outcomes are accessories and half are powerups (`rareCoinsShare = 0`). The
existing price exponent also rises from 1 to 2 with streak progress.

Assuming all eight confirmed shop powerups are active, request-compatible, and in the
pool, the chance that one daily box produces each named item is:

| Powerup (price) | Day 1 | Day 7 | Day 14 | Day 21 | Day 30 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Imposter / Rainstorm / Signal Jammer / Quick Rinse (75 each) | 0.455% each | 1.266% each | 2.292% each | 3.386% each | 4.865% each |
| X-Ray / Hitchhike (150 each) | 0.227% each | 0.549% each | 0.840% each | 1.050% each | 1.216% each |
| Leech / Quicksand (300 each) | 0.114% each | 0.238% each | 0.308% each | 0.325% each | 0.304% each |

The rows sum to a total powerup chance of 2.5%, 6.638%, 11.466%, 16.293%, and
22.5% respectively; the equal remaining half of RARE is an accessory. If the player
owns every accessory, every number in the table doubles because the entire RARE branch
becomes POWERUP. If a powerup is hidden by release channel, capability, active state, or
kill switch, it is removed and the price weights renormalize across the smaller pool.
The slight Leech/Quicksand dip from day 21 to day 30 is existing behavior: the growing
price exponent makes expensive items relatively rarer even while total RARE odds rise.
The player-facing `itemOdds` payload remains the authoritative live answer.

No schema migration. The balance config update is versioned through the existing admin
config path and must be applied backend-first only after the new compatibility gates are
live.

### 7.3 Tests first

- Backend integration test enumerates the shop catalog and daily pool for no features,
  powerups2, powerups3, and powerups4 clients, proving unknown types never leak.
- Status odds and many deterministic claim rolls use the same eligible set.
- Inactive/testOnly/disabled Imposter items are absent; every active visible allowed
  item has non-zero conditional probability and the conditional probabilities sum to 1.
- Frontend odds sheet renders new rows from the payload and hides malformed payloads as
  it does today.

## 8. White bottom-navigation labels and icons in light mode

`WoodenTabBar` currently uses `textMid` for an unselected item and `textDark` for a
selected item (`lib/widgets/wooden_tab_bar.dart:97-152`). On the dark green bar, the
unselected light-mode label lacks the requested treatment.

- In light mode, set each unselected label **and its icon** to `textLight`/white. Mobile
  navigation best practice treats the icon-label pair as one affordance; giving the two
  parts different colors weakens hierarchy and makes the icon look disabled. Keep the
  selected icon and label dark on the gold selection tile for contrast. Night theme
  stays unchanged.
- Preserve badges, semantics, ellipsis, selection animation, and tab order.
- Widget test pumps both themes and asserts selected/unselected label colors explicitly;
  add a contrast check against each background token.

No API or migration change.

## 9. Stealth Mode duration parity with Runner's High

### 9.1 Current state and compatibility risk

Runner's High durations are `[3h, 4h, 5h, 7h]`; Stealth is `[4h, 5h, 6.5h, 8h]`
(`powerupUpgrades.js:27-37`). Backend copy and Flutter emergency copy both advertise
the old Stealth values (`powerupCopySeed.js:89-95` and
`lib/constants/powerup_copy.dart:397-399,480-483`). Changing backend behavior globally
would make frozen binaries' bundled labels false, violating the top-level rule.

### 9.2 Required behavior

- Introduce request capability `stealth_runner_duration` in the new app build.
- A use request with that capability creates Stealth with `[3h,4h,5h,7h]`, exactly
  matching Runner's High at upgrade levels 0-3.
- Requests without it retain `[4h,5h,6.5h,8h]`. Existing effects keep their stored
  `expiresAt`; there is no backfill or in-flight shortening.
- Make `upgradedDuration` accept the duration profile explicitly or add a dedicated
  Stealth selector. Never read the user's sticky stored feature union.
- Make `GET /powerups/catalog` request-capability-aware for Stealth copy:
  - new capability: `Hide ... for 3 hours`; labels `Hide 3h/4h/5h/7h`
  - absent capability: existing 4h/5h/6.5h/8h strings
- Change the new Flutter bundled Stealth description to duration-neutral (for example,
  “Hide your name, steps, and track position while Stealth is active”) and do not bundle
  numeric tier labels. This keeps a new app talking to an older backend truthful until
  it fetches server copy. Persisted/server copy remains preferred.
- Use-result `durationMs` remains additive and must reflect the concrete selected tier.

No database migration is required unless implementation chooses to version copy rows;
the preferred plan is capability-aware serialization over the existing row.

### 9.3 Tests first

- Backend integration tests use the real endpoint with old and new feature headers at
  all four tiers and assert exact `expiresAt-startsAt` plus response `durationMs`.
- Catalog integration test proves old/new copy matches its respective behavior.
- Already-active old effect is unchanged across a deploy simulation.
- Frontend widget tests show duration-neutral fallback against an old/404 backend and
  correct server labels when available.

## 10. Powerup-attack push routing and race name

### 10.1 Audit result

The existing payload-to-route mapping is correct in source, but the full lifecycle is
not correct for every launch state:

- Backend `POWERUP_USED` payload is `{type:"POWERUP_USED", route:"race_detail",
  params:{raceId}}` (`notificationHandlers.js:718-761`).
- iOS extracts nested `params.raceId`; Android accepts top-level or JSON-encoded nested
  params (`lib/services/notification_service.dart:259-313`).
- `POWERUP_USED` maps to `NotificationRoute.raceDetail` (`:328-361`).
- `MainShell` consumes that `raceId` and pushes `RaceDetailScreen` with the same ID
  (`lib/screens/main_shell.dart:240-252,1558-1574`).
- On Android cold start, `main()` awaits `NotificationService.initialize()` before
  `runApp`; `getInitialMessage()` can therefore set `pendingAction` before `MainShell`
  attaches its listener (`lib/main.dart:34-35`, `notification_service.dart:138-144`,
  `main_shell.dart:207-210`). `ValueNotifier` retains the action but does not replay a
  notification to a later listener. The current shell does not drain that initial
  value, so a cold-start tap can fail to navigate.

The work is therefore to add the race name, drain pending launch actions after the
authenticated shell is ready, and add an end-to-end regression test across the
payload-to-screen path.

### 10.2 Push contract

Keep the payload shape unchanged for frozen clients:

```json
{
  "type": "POWERUP_USED",
  "route": "race_detail",
  "params": { "raceId": "race-uuid" }
}
```

The handler already fetches the race to verify it is live. Extend that select to `name`
and include a safe fallback when absent. Exact visible format:

- title: `Powerup Attack!`
- body: `<existing attack sentence> Race: <race name>.`
- fallback when name is absent/malformed: the **existing attack sentence unchanged**.

Trim the server-owned race name, cap the inserted value at 60 Unicode code points, and
replace control/newline characters with spaces before composing the body. Do not change
the payload if name lookup or sanitization fails.

Do not add a new push type. This ensures old apps still route it. Quicksand uses this same
generic type for each actually affected target.

After `MainShell` registers the notifier listener and restores enough authenticated
state to navigate, schedule one post-frame drain of the existing `pendingAction`. Reuse
the same guarded `_onNotificationAction` path; clear the action exactly once only when
it is handed to a valid route. This applies to all notification types and fixes the
shared cold-start seam without inventing a Quicksand-specific path.

### 10.3 Tests first

- Backend integration/handler tests assert name, `raceId`, live-race suppression, and
  fallback when the lookup returns no name.
- Frontend widget/integration test injects an iOS-shaped nested payload and an
  Android-shaped stringified payload, taps each from warm and cold start, and asserts
  the resulting `RaceDetailScreen.raceId` is exactly the payload ID.
- A pending action created before `MainShell` mounts is drained once after mount; a
  rebuild does not open a duplicate route.
- Missing/malformed ID shows the alert but performs no navigation and never crashes.

No migration or endpoint response change.

## 11. Hitchhike inherits target step effects

### 11.1 Current state

Hitchhike currently copies the target's raw in-window samples 1:1 and adds only positive
credit to the caster (`hitchhikeCopies.js:49-93,169-196`). It is deliberately inserted
before Leech resolution at every live/settlement assembly site
(`getRaceProgress.js:779-825`). Therefore Runner's High does not help the caster and
Wrong Turn cannot hurt them today.

### 11.2 Required scoring semantics

Introduce request capability `hitchhike_effective_steps`. A Hitchhike use from a request
with that capability stores `metadata.scoringVersion = 2`; a request without it continues
to create scoring version 1. Existing/version-1 rows retain today's raw-positive copy for
their whole lifetime, so neither a deploy nor an old client use changes meaning.

Version 2 copies the target's **signed effective step accrual** during the Hitchhike
window, using the same interval/multiplier rules as the target's leaderboard scorer:

```text
copiedDelta = sharedTargetScorerContribution(target samples, target effects,
                                              Hitchhike window)
casterPreLeechTotal = max(0, casterPreLeechTotal + copiedDelta)
```

The shared scorer determines interval boundaries, overlap precedence, rounding, and the
existing closed-hour rule; Hitchhike must not approximate those rules with a second
formula.

At minimum:

- normal target step: caster `+1`
- target under 2x Runner's High: caster `+2`
- target under Wrong Turn: caster `-1`
- overlapping Runner's High + Wrong Turn follows the target scorer's existing overlap
  rule; no separate invented multiplier table.

Every timed/global step multiplier that changes the target's earned leaderboard steps
in the window also changes Hitchhike (Leg Cramp/Campfire freeze, Campfire boost,
Rainstorm, and global step event). Instant bonus steps, Leech transfers, and another
Hitchhike are excluded because they are not target raw-step multipliers. Negative copy
cannot advance mystery-box progress; all Hitchhike copy remains outside `baseAdjusted`.

Refactor shared interval multiplier math rather than cloning it. Version 2 must be used
identically in `getRaceProgress`, `raceStateResolution`, `raceExpiry`, forfeit, and
uploader reconciliation. Preserve the structural parity guard and extend it for signed
values; `applyHitchhikeCopies` must stop dropping non-positive deltas.

### 11.3 API/data and tests

No response-shape change and no schema migration: effect metadata is JSON. The existing
use endpoint selects the scoring version from the request-scoped feature header, never
the user's sticky stored capability union. Make catalog copy capability-aware: legacy
requests retain today's raw-step sentence; capable requests are told that boosts and
reversals carry over. Keep the new Flutter bundled fallback neutral enough to be true
against either backend version.

- Backend integration tests through real use/sync/progress/settlement prove normal,
  Runner's High, Wrong Turn, overlaps, caster floor zero, target unchanged, and live vs
  settlement parity.
- Old request and version-1 in-flight fixtures remain raw-positive after new code; a new
  request creates v2. Existing v1 unit tests remain unchanged and a parallel v2 suite is
  added.
- Existing Leech ordering and mystery-box-progress tests remain green unmodified.

## 12. New Quicksand powerup

### 12.1 Confirmed product rules

These rules resolve “basically a Leg Cramp but target 3 people” into the owner-confirmed
contract.

| Rule | Confirmed value |
| --- | --- |
| Display name / enum | `Quicksand` / `QUICKSAND` |
| Price | Same live price as Leech; currently 300 coins |
| Source | Store-only; non-upgradeable |
| Targets | 1-3 distinct eligible rivals selected in one use |
| Duration | 2 hours (base Leg Cramp duration) |
| Effect | Each applied target's raw steps are frozen for the window |
| Teams | Enemy members only; no friendly fire |
| Existing freeze | Cannot target someone with active Leg Cramp or Quicksand |
| Compression Socks | Resolves independently per target and is consumed when it blocks |
| Mirror | Does not reflect (same rule as other store attacks) |
| Consumption | One Quicksand is consumed after valid submission even if some/all targets block |
| Daily spin | Dark until carrying build; then enters the compatible §7 pool |

All target IDs must be validated before any write. A validation failure consumes nothing.
Defense outcomes then resolve independently so one shield does not protect the other two.
The validation, defense consumption, Quicksand inventory consumption, effect creation,
and aggregate feed write are one database transaction. Concurrent duplicate submissions
may produce one success and one existing conflict/not-owned error, but never duplicate
effects or inventory consumption.

### 12.2 API contract

Extend the existing endpoint only for a `powerups4` client using a Quicksand item:

`POST /races/{raceId}/powerups/{powerupId}/use`

```json
{ "targetUserIds": ["u1", "u2", "u3"] }
```

- `targetUserIds` is optional for every existing type and ignored/rejected as an invalid
  parameter combination when sent with a non-Quicksand type.
- For Quicksand it must be an array of 1-3 unique non-empty strings. `targetUserId` is not
  accepted for Quicksand, preventing ambiguous mixed requests.
- Status `400`: malformed/duplicate/count/self/inactive/forfeited/already-frozen target;
  `403`: item/race ownership; `409`: race ended or another use won a race; existing error
  envelope `{ "error": "...", "code": "..." }`.

Success response is additive but retains `result.blocked` for shared old UI helpers:

```json
{
  "result": {
    "outcome": "PARTIAL",
    "blocked": false,
    "durationMs": 7200000,
    "targetResults": [
      { "targetUserId": "u1", "outcome": "APPLIED", "expiresAt": "..." },
      { "targetUserId": "u2", "outcome": "BLOCKED", "expiresAt": null },
      { "targetUserId": "u3", "outcome": "APPLIED", "expiresAt": "..." }
    ]
  }
}
```

- Top-level outcome is `APPLIED`, `PARTIAL`, or `BLOCKED`; `blocked` is true only when
  every selected target blocked.
- Target result order matches request order.
- The command emits one generic `POWERUP_USED` notification event per applied target and
  no attack push for blocked targets. The feed writes one aggregate Quicksand event with
  target IDs/outcomes in metadata; frozen clients can render its server description.

### 12.3 Data model, gating, art, and frontend

- Add enum value `QUICKSAND` with an additive PostgreSQL/Prisma migration.
- Add `PowerupCopy` and `PowerupShopItem` seed rows. Set price from the same declared
  Leech seed/live value during rollout preparation, but do not dynamically couple future
  admin edits: “same price” is the launch value, not a permanent database invariant.
- Set `active:true`, `testOnly:true`; add `POWERUPS4_GATED_TYPES = ["QUICKSAND"]` and
  require request feature `powerups4` in shop/daily visibility. Old binaries never see or
  win the type. Held inventory remains usable only from a capable UI.
- Create `assets/images/powerups/quicksand.png` and `_thumb.png` through the Codex
  imagegen pipeline, using existing powerup icon references (not accessory references),
  critique/iterate, then wire `PowerupIcon` and `pubspec.yaml` glob behavior.
- Add `QUICKSAND` to scorer freeze effect types, expiry handling, effect rails, feed
  styling, copy catalog, shop/inventory, and push attack message allowlist.
- Capability-aware race/feed serialization is mandatory because an older app user can
  still be a victim. A request without `powerups4` receives active Quicksand as the
  already-understood `LEG_CRAMP` compatibility alias (same freeze timing/semantics) and
  a generic server-rendered attack/feed sentence; a capable request receives
  `QUICKSAND`. Scoring always uses the stored canonical enum. Do not expose an unknown
  enum to a frozen client or hide the reason their steps are frozen.
- Add a dedicated multi-select target sheet in `RaceDetailScreen`: checkmarks, `0/3`
  counter, disabled confirmation until one selection, cap at three, enemy-only list,
  and explicit per-target result presentation. Do not overload the single-target sheet.
- `BackendApiService.usePowerup` adds optional `List<String>? targetUserIds`, serialized
  only when non-null. Unknown/missing `targetResults` degrades to the existing generic
  success/error feedback.

### 12.4 Tests first

- Backend integration via real purchase/redeem/use endpoints: 1/2/3 targets; malformed
  and duplicate arrays; self/team/forfeit/inactive; mutual freeze exclusion; mixed and
  all shield outcomes; Mirror intact; one inventory consumption; exact 300-coin launch
  price; per-target push and aggregate feed; expiry and settlement parity.
- Old feature header never receives Quicksand in shop, inventory presentation, daily
  preview, or claim; existing endpoints and response shapes stay unchanged.
- Frontend widget tests cover selection cap/cancel/confirm, small/large race lists,
  partial results, defensive missing fields, art fallback, and semantics.

## 13. Consolidated API contract and migration list

| Surface | Change | Old-client behavior |
| --- | --- | --- |
| `GET /admin/stats` | Add `activity.rewardedAds` object (§4) | Ignores additive key |
| `/auth/me`, `GET/PATCH /admin/settings` | Add `dualBoxBannersEnabled` (§3) | Ignores additive key; top defaults off |
| Daily `/status`, `/claim-box`, `/claim-extra-box` | No shape change; capability-filter pool (§7) | Retains only renderable prizes |
| `GET /powerups/catalog` | Capability-specific Stealth/Hitchhike copy; add Quicksand for p4 (§9/§11/§12) | Receives legacy copy; no Quicksand |
| `POST .../powerups/:id/use` | Optional `targetUserIds`; feature-selected Stealth and Hitchhike behavior (§9/§11/§12) | Existing requests unchanged |
| Push `POWERUP_USED` | Same payload; body gains race name (§10) | Routes as today |
| Race progress/feed | Serialize Quicksand canonically for p4 and as `LEG_CRAMP` for older requests; Hitchhike semantics versioned (§11/§12) | Understandable freeze; v1 effects unchanged |

Migration: one additive `PowerupType` enum value (`QUICKSAND`). No column drop/rename,
historical backfill, or destructive migration.

## 14. Backward compatibility and rollout

1. Land backend tests and additive migration first. Do not enable Quicksand in prod.
2. Deploy backend compatibility gates before the app advertises `powerups4` or
   `stealth_runner_duration`.
3. Build and verify iOS and Android together. The new client sends `powerups4`,
   `stealth_runner_duration`, and `hitchhike_effective_steps`, includes Quicksand
   assets/UI, and has duration-neutral emergency Stealth/Hitchhike copy.
4. Quicksand stays `testOnly:true` through staging/TestFlight and the full phased app
   rollout. A later, separately-approved prod database action may expose it.
5. Remove daily exclusions only after all per-request gates are live.
6. Hitchhike scoring v1/v2 is data-versioned in effect metadata; no active effect changes
   meaning during rollout.
7. Attack push payload type and route never change; old clients get improved body copy.
8. Ship support for the top placement with `dualBoxBannersEnabled=false`; verify dedicated
   production ad-unit IDs, then ramp the flag while watching per-visit impressions,
   revenue, box completion/exit rate, anomalous CTR, and AdMob Confirmed Click/Policy
   Center status. Either the dual flag or master banner flag provides immediate rollback.
9. Do not run integration tests against prod. Confirm test database before every backend
   integration run. Do not deploy or mutate prod without explicit approval.

## 15. Acceptance criteria / definition of done

- [ ] Two policy-separated banners appear at the top and bottom of all three requested
      opening routes when both flags are enabled; neither overlaps the centered content
      or causes it to jump.
- [ ] Admin shows unique DAU coin-ad and extra-spin-ad watchers with percentages, and old
      stats responses render safely.
- [ ] Settings is a pushed full page with all current actions preserved.
- [ ] Five generated cloud instances move right-to-left in both themes and honor reduced
      motion.
- [ ] The daily odds list exactly equals the request-compatible pool; every active safe
      shop powerup is included and weighted inversely by price.
- [ ] Light-mode unselected nav labels and icons are white; selected and night states
      retain contrast.
- [ ] New-client Stealth tiers are exactly 3h/4h/5h/7h; old clients keep their old behavior
      and truthful copy; active effects are untouched.
- [ ] Tapping attack pushes opens the exact race on iOS/Android warm/cold paths, and the
      body names the race.
- [ ] Hitchhike v2 gains from Runner's High and loses from Wrong Turn with live/settlement
      parity; Hitchhike v1 effects retain their original math.
- [ ] Quicksand can validly target up to three rivals, resolves defenses per target, costs
      the confirmed launch price, is art/copy/UI complete, and cannot leak to old clients.
- [ ] New tests are written first. Existing tests are not deleted or weakened; any test
      encoding an explicitly superseded product value is surfaced to the owner.
- [ ] Both platform builds, static analysis, focused widget tests, and backend unit plus
      integration suites pass before implementation is called complete.

## 16. Remaining owner decisions

None.

## 17. Revision log

- **Fresh-eyes pass 1 — lifecycle, policy, and compatibility:** found and specified the
  pre-`runApp` Android cold-start notification drain; preserved the old attack sentence
  as the no-name fallback; added race-name sanitization; prohibited gesture-triggered
  banner refresh; required transactional multi-target resolution and legacy
  `LEG_CRAMP` serialization for older Quicksand victims; verified existing Settings
  tests assert behavior rather than the modal container.
- **Fresh-eyes pass 2 — frozen-client semantics and test contracts:** capability-gated
  Hitchhike v2 so old app uses still create v1; required shared scorer math instead of a
  duplicated multiplier formula; made Hitchhike catalog/fallback copy version-safe; and
  surfaced the existing daily-footer test contract for explicit owner resolution.
- **Owner interview round 1:** confirmed all compatible shop powerups enter the daily
  spin, five clouds, all target step multipliers for Hitchhike, and the complete
  Quicksand rule bundle. Selected unique verified watchers plus percent of stepped-today
  DAU as the most decision-useful ad metric. Applied the mobile-design review by treating
  unselected navigation icons and labels as a single white affordance in light mode.
- **Owner interview round 2:** selected simultaneous top and bottom banners with staged
  rollout/rollback monitoring, and retained the existing streak-sensitive inverse-price
  daily weighting. Added full-outcome example probabilities and documented their
  accessory-ownership and capability dependencies.
- **Fresh-eyes pass 3 — post-interview closure:** removed stale one-banner and
  label-only language; reconciled the dedicated top ad unit with scope; specified the
  additive dual-banner settings contract and defensive defaults; corrected the Prisma
  enum casing; and confirmed the existing footer test remains valid while dual-placement
  coverage is added. Zero owner decisions remain open.
