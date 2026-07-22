# Ad Rewards — Phase 1: Extra Daily Box Spin (Design)

Status: implemented 2026-07-06 (backend + frontend, staging-ready; needs real
AdMob IDs + store privacy forms before prod release).

## Goal

Introduce ads to Bara without disrupting gameplay. Phase 1 is a single
**opt-in rewarded-video placement**: after claiming the free daily mystery
box, the user may watch one ad per day for **one extra box spin**.

No banners. No interstitials. Rewarded video only, always user-initiated.

## Provider

**AdMob** via the first-party `google_mobile_ads` Flutter plugin.

- Least integration weight (Firebase already in the Android build).
- Built-in **server-side verification (SSV)** for rewarded ads — required
  because the reward is real economy currency (coins/accessories).
- If revenue justifies it later, AppLovin MAX can replace it behind the same
  `AdService` abstraction (higher eCPM at scale). All plugin calls go through
  `lib/services/ad_service.dart`; no screen touches `google_mobile_ads`
  directly.

## Trust model — the client is never trusted

A client saying "I watched an ad" mints nothing. The flow:

1. Client loads a rewarded ad with `ServerSideVerificationOptions(userId:
   <backend user id>, customData: <localDate YYYY-MM-DD>)`.
2. User watches the ad. Google's servers call our backend:
   `GET /ads/ssv?...&user_id=...&custom_data=...&transaction_id=...&signature=...&key_id=...`
3. Backend verifies the ECDSA-SHA256 signature against Google's published
   public keys (`https://www.gstatic.com/admob/reward/verifier-keys.json`,
   cached), then inserts an **`AdRewardGrant`** ledger row — idempotent on
   `transaction_id` (unique), mirroring `grantReferralReward.js`'s
   insert-ledger-first pattern.
4. Client's `onUserEarnedReward` fires → client calls
   `POST /daily-reward/claim-extra-box {localDate}`. The command **consumes an
   unconsumed grant for that date** and rolls the box. No grant → 409
   `AD_NOT_VERIFIED`; the client retries briefly (SSV can lag the client
   callback by a few seconds), then tells the user the spin will be available
   on next visit (the grant stays consumable all day).

Replay/abuse coverage:
- Faked/replayed SSV call → signature check fails, or `transaction_id`
  unique-collides. No grant.
- Replayed claim call → the grant is consumed with a conditional
  `updateMany(... consumedAt: null)`; second consume finds nothing → 409.
- Coin mint is `awardCoins(reason: "ad_extra_spin", refId: <grantId>)` —
  idempotent on its own ledger, so a crash between consume and mint can't
  double-pay on retry.
- One per day: claim requires `lastDailyClaimDate === localDate` (free spin
  first) and rejects if a consumed grant already exists for that date.

## Backend changes (`stepv2-backend`)

- **Prisma**: new `AdRewardGrant` model — `userId`, `adUnit?`,
  `transactionId @unique`, `rewardKind` (default `extra_daily_spin`),
  `grantedDate` (user-local `YYYY-MM-DD` from `custom_data`, server UTC date
  fallback), `consumedAt?`, roll-result columns (`rarity`, `rewardType`,
  `coinAmount`, `shopItemId`) written at consumption. Additive migration.
  (`DailyRewardClaim` is NOT reused: its `@@unique([userId, claimedDate])` is
  load-bearing for the free spin.)
- **`src/utils/admobSsv.js`** — parse + verify the SSV query string. Message =
  raw query string up to `&signature=`; signature is base64url DER ECDSA;
  key set fetched+cached from Google, injectable for tests.
  `ADMOB_SSV_SKIP_VERIFY=true` escape hatch for local/staging only.
- **`src/commands/grantAdReward.js`** — validate + insert the grant
  (P2002 → already granted, OK/no-op).
- **`src/commands/claimExtraDailyRewardBox.js`** — guards above, then reuses
  the existing box-roll machinery (`rollDailyBoxRarity`, `coinAmountForTier`,
  `pickAccessory`, `getUnownedAccessoryPool`) at the user's **current**
  `dailyLoginStreak`. Does **not** touch `lastDailyClaimDate` or streaks.
  Response shape matches `/claim-box` so the client reuses the reel + reveal.
- **Routes**: new `src/routes/ads.js` (`GET /ssv`, unauthenticated — Google
  calls it); `POST /daily-reward/claim-extra-box` (auth'd).
- **Status**: `GET /daily-reward/status` gains an additive `adExtraSpin`
  block `{ available, pendingGrant, used }` — emitted **only** when the
  request carries `ads` in `X-Client-Features` AND the kill switch is on.
- **Kill switch**: `src/config/adRewards.js`, `ADS_EXTRA_SPIN_ENABLED=false`
  disables the status block and the claim endpoint without an app release.

## Frontend changes (`stepv2-frontend`)

- `google_mobile_ads` dependency; `lib/services/ad_service.dart` wrapper
  (preload on daily-reward screen open, `isReady`, `show()` → earned-reward
  future). Constructor-injectable fake for widget tests. No-op on
  macOS/unsupported platforms.
- `X-Client-Features: characters,ads` (both request paths in
  `backend_api_service.dart`), + `claimExtraDailyRewardBox()` API method.
- `daily_reward_screen.dart`: when status has `adExtraSpin.available` and the
  ad is loaded, the post-claim view shows **"Watch an ad · +1 spin"**. Tap →
  show ad → on reward, claim-with-retry → existing reel/reveal flow runs
  again with the extra result. Reward application (`updateCoins`,
  `onClaimed`) reuses the existing settle-once guard per spin.
- Platform config: Android manifest `AD_ID` permission + AdMob
  `APPLICATION_ID` meta-data; iOS `GADApplicationIdentifier`,
  `SKAdNetworkItems`, `NSUserTrackingUsageDescription`. **Google's public
  test app/ad-unit IDs are wired for now** — swap in real IDs (per-flavor,
  via the same `--dart-define` pattern as `BACKEND_BASE_URL`) before prod.

## Old-client compatibility (per CLAUDE.md)

- All backend changes are additive: new endpoints, new table, new optional
  status field. Old binaries never send `ads` in `X-Client-Features`, so they
  never see `adExtraSpin` and never call the new endpoints. `/claim`,
  `/claim-box`, and their guards are untouched.
- New client against old backend: `adExtraSpin` absent → button never shows.
- Kill switch handles emergencies without an App Store cycle.

## Phase 2: display banners (shop + race mystery-box)

Status: implemented 2026-07-07 (frontend only; needs a real AdMob banner unit +
prod `--dart-define=ADMOB_BANNER_AD_UNIT_ID` before release).

Two **display-only** standard 320x50 banners — **no SSV, no reward, no backend,
no economy tie-in** — so this is a pure client change with no old-client
compatibility surface. The standard banner format is shared by Google demand,
Meta Audience Network bidding, and AppLovin mediation:

- **Shop/inventory** (`shop_tab.dart`): banner pinned just above the shell tab
  bar (a `Positioned` layer in the existing `Stack`).
- **Race mystery-box overlay** (`case_opening_screen.dart`): banner pinned to
  the screen bottom, below the vertically-centered opening/reveal card. The
  reveal waits for a "Continue" tap, so the banner has time to fill.

Both use `lib/widgets/ad_banner_slot.dart` (`AdBannerSlot`), which collapses to
zero size unless `AdService.bannersEnabled` AND an ad actually loads — screens
never reserve dead space for a missing/unfilled banner. SDK init + ATT is shared
with the rewarded path via `AdService.ensureInitialized()`.

Gating mirrors the rewarded unit: banners render **only on iOS builds carrying a
real `ADMOB_BANNER_AD_UNIT_ID`**. Android (no AdMob app) and define-less builds
show nothing; dev/staging fall back to Google's public test banner. No backend
kill switch — to stop a live banner without an App Store cycle, pause the ad
unit in the AdMob console.

## Not in Phase 1 (deliberately)

- ATT pre-prompt UX polish (we request non-personalized ads if ATT is
  denied/undetermined; a nicer explainer screen can come later).
- Post-race "double payout" and store "watch-to-earn" placements — same
  plumbing, separate decision.
- AppLovin MAX mediation.

## Release checklist (before prod)

1. ~~AdMob account + iOS app + rewarded unit~~ DONE 2026-07-06: publisher
   `pub-4538901002392200`, iOS app `~5288861983`, rewarded unit
   `/8833390717` with SSV verified against
   `https://steptracker-api.org/ads/ssv` (prod). `app-ads.txt` live at
   barastep.com / steptracker-api.org; AdMob app verification pending the
   App Store listing's Marketing URL (barastep.com) going public.
2. ~~Real iOS IDs in the build~~ DONE: real app ID in `Info.plist`; unit ID
   via `--dart-define=ADMOB_EXTRA_SPIN_AD_UNIT_ID=…` (see `DEPLOYMENT.md`).
   The `ads` capability is only sent by iOS builds with the define present,
   so a forgotten define (or any Android build) safely hides the feature.
3. **Android: deferred.** No AdMob Android app/unit yet; the Android manifest
   still carries Google's TEST app ID. Before enabling ads on Android:
   create the AdMob Android app + rewarded unit, replace the manifest
   `APPLICATION_ID` (per-flavor), and extend the capability guard.
4. App Store privacy nutrition label update (ads/tracking) — required with
   the release that ships ads.
5. Register your own devices as AdMob test devices before watching the real
   ad unit (invalid-traffic protection).
