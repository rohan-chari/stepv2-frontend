# Daily reward exact coin amounts

## Summary & user story

When a player opens the daily reward reel, coin decoy tiles should show the
exact coin amount that the current streak would award, rather than a range such
as `10–30 coins`. A player should be able to understand the actual coin value
before spinning without changing the server's reward odds, reward selection, or
payout rules.

The exact amount is computed by the backend using the same balance snapshot and
streak-specific formula used by `/daily-reward/claim-box` and
`/daily-reward/claim-extra-box`. The Flutter client displays the server's
preview value; it does not reimplement payout policy.

## Scope / non-goals

In scope:

- Additive exact coin-preview metadata to the daily reward status response.
- Display exact amounts on daily-reward reel coin decoys for COMMON, UNCOMMON,
  and RARE_FALLBACK coin outcomes.
- Keep the landed reward authoritative from the claim response.
- Preserve the existing range field for frozen app versions.
- Keep status, free-claim, and extra-spin payout calculations on the same
  explicit balance-config snapshot when each request is evaluated.

Out of scope:

- Changing rarity odds, streak progression, coin ranges, rounding, or expected
  value.
- Changing the actual free or rewarded-ad claim behavior.
- Changing the legacy six-day ladder.
- Adding a release flag, database column, migration, or new endpoint.
- Showing an exact amount when the backend does not provide a valid exact
  preview; the safe fallback is a neutral `Coins` label, never a guessed value.

## Existing behavior and implementation evidence

- `lib/screens/daily_reward_screen.dart:929-1001` builds decorative reel
  candidates from server `box.itemOdds`, `box.accessoryPool`,
  `box.powerupPool`, and `box.coinRanges`.
- `lib/screens/daily_reward_screen.dart:942-958` currently converts the
  server range into labels such as `10–30 coins`.
- `lib/screens/daily_reward_screen.dart:1061-1084` renders the actual landed
  result from `coinAmount`; this remains authoritative and unchanged.
- `src/modules/economy/queries/getDailyRewardStatus.js:135-202` (backend)
  currently returns the bounds and item odds but not the exact streak-specific
  coin amount.
- `src/modules/economy/dailyBoxOdds.js:139-150` (backend) computes the actual
  amount with `coinAmountForTier`, using the active balance config, projected
  streak, and nearest-five rounding.
- `src/modules/economy/commands/claimDailyRewardBox.js:149-160` (backend)
  uses that helper for real claims. The extra-spin command uses the same helper.

## API contract

Change `GET /daily-reward/status` only by adding this optional field inside the
existing `box` object:

```json
{
  "box": {
    "streak": 7,
    "streakCap": 30,
    "coinRanges": {
      "COMMON": [10, 30],
      "UNCOMMON": [40, 80]
    },
    "coinAmounts": {
      "COMMON": 15,
      "UNCOMMON": 50,
      "RARE_FALLBACK": 120
    }
  }
}
```

Contract rules:

- `coinAmounts` is additive and optional. Its only allowed keys are `COMMON`,
  `UNCOMMON`, and `RARE_FALLBACK`; values are non-negative safe integer coin
  amounts. A valid `0` is retained and displayed as an exact value.
- `COMMON` and `UNCOMMON` are computed for the response's projected `box.streak`.
- `RARE_FALLBACK` is computed too, even when the current client has a non-empty
  rare prize pool, because it is the exact safe value for the server's rare
  fallback path. It does not mean a rare fallback is currently likely.
- Values, `box.streakCap`, `box.coinRanges`, and the existing
  `box.itemOdds.configVersion` must all come from the same
  `balanceConfig.getSnapshot()` already loaded by `getDailyRewardStatus`; do
  not add a database query or read the synchronous cache separately.
- The existing `coinRanges` field remains unchanged for old clients. No field
  is renamed, removed, or repurposed.
- The claim endpoints' request/response shapes remain unchanged. Their
  returned `coinAmount` remains the final authority if the status response is
  stale because config or account state changed between status and claim.
- The free claim and extra-spin claim must pass their request's explicit
  balance snapshot into `coinAmountForTier`; neither may fall back to the
  synchronous config cache. This closes the current extra-spin parity gap at
  `claimExtraDailyRewardBox.js:183-194`.

Backend response validation is per key. If a range is missing, malformed,
non-integer, reversed, non-finite, or produces an unsafe result, omit that
`coinAmounts` key; do not turn an invalid/missing range into zero. If every key
is invalid, omit `coinAmounts` entirely. Backend balance-config fallback still
applies when the configured snapshot itself is unavailable, but the response
must only emit values that pass the same validation.

## Data model / migrations

No schema change. No new endpoint. No new query. `coinAmounts` is response-only:
it is never persisted and never stored in a separate Redis/cache key. Reuse the
already loaded Postgres-backed `balance_config` snapshot and existing
`coinAmountForTier` helper for three bounded in-memory calculations. The
response's `coinAmounts`, `coinRanges`, and `streakCap` must use that same
snapshot; the existing cache/Redis fallback behavior remains unchanged and is
tested without flushing or mutating production data.

## Frontend plan

Update `DailyRewardScreen`'s reel candidate builder:

1. Read `box.coinAmounts` defensively as a map.
2. For a COMMON or UNCOMMON coin decoy, use the corresponding exact amount.
3. For a RARE coin decoy, use `RARE_FALLBACK`.
4. Render the exact coin label in the existing tile chrome, e.g. `+15 COINS`.
5. If the exact field/key is missing or malformed, render a neutral `Coins`
   label. Do not fall back to `coinRanges`, hardcode 10/30/40/80, or generate a
   random amount in the client.
6. Preserve the claim result path and exact landed amount.

This is shared Dart UI behavior and must be accounted for on both iOS and
Android. `DailyRewardScreen` is reused by Home, Results, and Get Coins entry
points; no forked daily-reward implementation should be added.

## Backward compatibility & rollout

- Deploy the additive backend response first and verify the live status response
  contains valid `coinAmounts` for representative streaks and that status/free
  claim/extra-spin calculations use explicit matching snapshots.
- Then ship the Flutter change. Old app versions ignore the additive field and
  continue their existing range-label behavior; all existing response fields
  and semantics remain unchanged.
- A new app against an older backend safely shows `Coins` for decoys; it does
  not invent an exact value. The actual claim remains compatible and continues
  to show the server-returned exact amount.
- No feature flag or rollout control is needed. This is permanent additive
  metadata with a neutral missing-field fallback.
- Existing client capability headers and backend policy filtering are unchanged.

## Tests first

Backend, before implementation:

- Extend the real daily-reward status integration test to assert exact
  `coinAmounts` at streak 1, an intermediate streak, and the cap, including
  nearest-five rounding and `RARE_FALLBACK`.
- Add a status→free-claim and status→extra-claim integration test around a
  balance-config refresh, proving each request uses its own explicit snapshot
  and that no stale synchronous cache changes the payout.
- Assert malformed/missing ranges omit only the affected exact key, valid zero
  remains present, and an all-invalid result omits `coinAmounts`.
- Assert the existing `coinRanges`, ladder, odds, and claim response remain
  unchanged.
- Assert no additional database read or separate Redis/cache key is introduced
  by the status projection; exercise the existing local/test cache fallback and
  Redis-unavailable path without any production database access.

Frontend, before implementation:

- Pump the real `DailyRewardScreen` and assert COMMON/UNCOMMON decoys show the
  exact server values rather than a range.
- Pin a RARE-only reel with `itemOdds.rareMix.COINS = 1` and assert the
  `RARE_FALLBACK` exact value is displayed.
- Provide malformed, missing, zero, and partial `coinAmounts` payloads and
  assert no exception, no range label, and neutral `Coins` fallback for the
  affected tier. Valid zero must remain a displayed exact amount if the server
  ever supplies it.
- Assert the landed claim still renders the claim response's exact `+N COINS`
  amount and does not use the preview value.
- Assert the same behavior through the existing daily-reward entry routes that
  reuse `DailyRewardScreen`.

## Acceptance criteria

- With a valid status response, no daily-reward coin decoy displays a range.
- At a given projected streak, every coin decoy for a tier displays the exact
  server-provided amount for that tier.
- COMMON/UNCOMMON/RARE_FALLBACK preview values match the backend helper used by
  claims, including nearest-five rounding and streak cap behavior.
- Missing or malformed preview metadata never crashes and never fabricates an
  economic amount.
- Old app versions continue to receive the prior response shape and behavior.
- Existing reward odds, actual claims, coin ledger writes, and landed reward
  rendering are unchanged.
- Tests are written first and pass; `flutter analyze` is clean; both platforms
  are accounted for.

## Manual UI-placement test plan

*Elements under test:*

- Daily-reward reel coin decoy labels: old range text → exact `+N COINS` in the same tile label slot.
- Missing/invalid preview fallback: range text → neutral `Coins` label in the same slot.
- Landed reward remains in the reel’s centered result position with its authoritative `+N COINS` label.

*Checklist*

1. **Surface:** Real Daily Reward reel — Home entry

   - **Get there:** Signed-in account with an unclaimed v2 daily box and valid `COMMON`, `UNCOMMON`, and `RARE_FALLBACK` preview values → Home → tap the daily-reward quick action.
   - **Verify:** Coin decoys show the server values, such as `+15 COINS`, `+50 COINS`, and `+120 COINS`, inside their existing tiles. No `10–30 coins`/`40–80 coins` range, old-position label, or duplicate label remains. Spin the reel and confirm the landed reward stays centered in the result position and retains its separate authoritative amount.

2. **Surface:** Get Coins → Daily Box → Daily Reward reel

   - **Get there:** Open the existing Get Coins route → tap `OPEN DAILY BOX`. Use the same unclaimed-box fixture.
   - **Verify:** The reel uses the identical exact-label placement as the Home entry. Confirm the Get Coins card or surrounding screen does not duplicate a reel label, and no range label remains.

3. **Surface:** Daily-reward notification / Inbox destination

   - **Get there:** Use an account with an unclaimed daily box → tap a daily-reward reminder push, or Home → Inbox → tap an alert whose destination is daily reward.
   - **Verify:** The same Daily Reward overlay opens, with exact coin labels in the existing decoy tiles and no range labels or duplicated reel. Confirm the notification path does not show a different or stale layout.

4. **Surface:** Missing or malformed preview metadata

   - **Get there:** Open the reel using a QA response with missing, partial, malformed, and valid-zero `coinAmounts`.
   - **Verify:** Each affected tier shows neutral `Coins` in the existing tile label position. It never shows the old range, a guessed amount, or a duplicated label. A valid zero displays as an exact amount rather than falling back.

5. **Surface:** Small-screen and accessibility layouts

   - **Get there:** Repeat the reel on 320×568 and 320×700 portrait devices, with large accessibility text enabled; repeat on iOS and Android if available. Enable VoiceOver or TalkBack.
   - **Verify:** The popup, header, close/info controls, reel viewport, pointer, and coin labels remain inside the screen with no horizontal overflow. Exact labels do not clip, overlap adjacent tiles, or move outside the tile. Screen-reader focus announces each exact coin amount once; no stale range is exposed.

*Surfaces confirmed unaffected:*

- `RaceResultsSummaryScreen`: grep found only race-payout coin UI and no `DailyRewardScreen` constructor or daily-reward reel.
- `CaseOpeningScreen` and `MultiCaseOpeningScreen`: they share `CaseOpeningReel` chrome but use separate powerup/accessory tile builders.
- Legacy six-day ladder: it renders when no `box` payload exists and does not contain the v2 coin-decoy reel.
- Tutorial race/detail surfaces: no daily-reward reel or `_DailyReelTile` is rendered there.

*Risks found while planning:*

- The requirements mention a Results entry point, but the current code has no Results-side `DailyRewardScreen` call; `analyticsSurface: 'results'` is unused.
- `GetCoinsScreen` contains the daily-box entry, but grep found no current production constructor call; Home’s coin `+` currently opens `ShopTab`.
- The tutorial Home fixture returns only `claimedToday` and no `box.coinAmounts`, so the tutorial cannot render the exact reel; its overlay also absorbs taps.
- RARE coin decoys require `RARE_FALLBACK`, even when the rare prize pool contains other item types.

## Revision log

- Draft: identified that exact amounts must be server-provided because
  `coinRanges` are bounds and backend owns payout policy; selected additive
  `box.coinAmounts` with neutral missing-field behavior.
- Gap pass 1: added `RARE_FALLBACK`, stale-status claim authority, valid-zero
  handling, and explicit prohibition on client range/random fallbacks.
- Gap pass 2: added no-new-query constraint, old-client compatibility, both
  platform coverage, and shared-entry-point verification.
- Architect review: required one explicit balance snapshot for `streakCap`,
  ranges, exact amounts, and item-odds version; explicit snapshot threading for
  extra-spin claims; per-key malformed validation; response-only storage; and
  old-header/cache compatibility tests.
- Game-analyst review: verdict `SOUND WITH CHANGES`; exact preview is
  presentation-only with 0 coin/EV change, but all claim paths must retain
  snapshot parity. Verified streak amounts are 10/40/100 at day 1, 20/60/150
  at day 15, and 30/80/200 at day 30. Updated `docs/economy.md` with the
  review's current economy verification.
- UI-test-planner review: added the manual checklist above and recorded that
  Results and tutorial daily-reward mirrors are not currently rendered, while
  Home, Get Coins, and Inbox/notification routes reuse the real screen.
