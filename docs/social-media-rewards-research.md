# Social Follow Rewards — Research Report

Research-only report for a possible Social Follow Rewards feature. Inspected repositories:

- Frontend: `/Users/rohan/repos/stepv2-frontend` (Flutter package `step_tracker`).
- Backend: `/Users/rohan/repos/stepv2-backend` (Node/Express/Prisma/PostgreSQL).

No application code, Prisma schema, migration, test, or configuration was changed by this research. The only change in this phase is this document.

Evidence labels: **VERIFIED** means found in the checked-out source; **NOT VERIFIED** means the repository does not establish the fact. External facts are separated and linked to official documentation.

## 1. Executive Summary

The safest MVP is a server-owned, one-time claim per authenticated Bara user and platform, backed by the existing `CoinTransaction` ledger and shared `awardCoins` function. A new conceptual claim table is preferable to putting three nullable fields on `User`, because the feature has a per-platform state machine, needs opened/claimed timestamps and configuration evolution, and should be queryable independently. The ledger remains the financial source of truth; the claim row is the eligibility/state source of truth.

The existing coin path already provides the critical concurrency guarantee: `CoinTransaction` has `@@unique([userId, reason, refId])`; `awardCoins` inserts the ledger row and increments `User.coins` in one transaction, catches Prisma `P2002`, and returns the current balance without a second grant. `src/shared/economy/awardCoins.js:30-91` and `prisma/schema.prisma:1104-1132` are the closest reusable primitives.

The current app already has a natural destination: the Get Coins hub (`lib/screens/get_coins_screen.dart`) reached from the Home coin badge (`lib/screens/tabs/home_tab.dart:1428-1460`). Existing social outbound links use `url_launcher` with `LaunchMode.externalApplication`; the settings implementation currently contains Instagram and X but not TikTok. `main.dart` and several screens already refresh server state on `AppLifecycleState.resumed`.

The repository does not contain a social-follow reward implementation, official social OAuth integration, or a verified TikTok handle. The current known configured social URLs are Instagram `https://instagram.com/Bara.steps.app` and X `https://x.com/BaraStepsApp` in `lib/screens/settings_screen.dart:500-524`; an older product requirements document records different handles (`@bara.steps`, `@barastepz`), so the canonical accounts require product confirmation before implementation. No official follow-verification path is established for ordinary consumer use. Honor-system opened/claim is therefore the smallest safe MVP.

The 600-coin maximum is material but not extraordinary: the economy report records direct ad coins at 25 per watch, up to 3/day (75/day), daily rewards commonly 10–50 with a 100-coin legacy path, referral reward 100 in the cited runtime sample, race finish around 188.5 average in one sample, and many powerup prices from 40 to 200. The reward is roughly eight days of maximum direct ad coins, or about one to several common purchases, and should be treated as a meaningful acquisition incentive.

## 2. Current Coin Architecture

### Frontend

| Path | Symbol | Responsibility and evidence |
|---|---|---|
| `lib/services/auth_service.dart:58-62,161,235,941-942,1389-1393` | `AuthService` | Owns the in-memory coin balance, persists `auth_coins` in SharedPreferences, updates it from authenticated server payloads, and notifies listeners. The persisted value is a display/cache convenience, not authority. |
| `lib/services/backend_api_service.dart:1628-1645` | `fetchCurrentUser` / auth-me path | Fetches `/auth/me?view=shell-v1`; the response may carry `coins`. |
| `lib/widgets/coin_balance_badge.dart:7-73` | `CoinBalanceBadge` | Shared balance display, animated `SpinningCoin`, and circular add button. It accepts `coins` and `onAddTap`; it does not mutate balance. |
| `lib/screens/tabs/home_tab.dart:1428-1460` | Home header coin badge | Renders `CoinBalanceBadge(coins: authService.coins)` and routes the add action to shop/Get Coins. |
| `lib/screens/get_coins_screen.dart:22-31,250-490` | `GetCoinsScreen` | Existing coin-earning hub. It shows balance, rewarded-ad card, referral card, and daily reward card. This is the natural insertion point for social rows. |
| `lib/services/rewarded_coins_controller.dart:104-119,158-160,270-294` | `RewardedCoinsController` | Loads the server offer, starts the rewarded-ad flow, claims via API after server-side verification, and applies returned `coins` through `AuthService`. It coalesces/refreshes on lifecycle resume. |
| `lib/widgets/home_rewarded_coins.dart:8-150` | `HomeRewardedCoins` | Home presentation of the rewarded-ad coin offer and success toast. |
| `lib/screens/daily_reward_screen.dart` | `DailyRewardScreen` | Daily reward/box presentation and claim UI; uses status and claim APIs, loading/error states, and returned balance. |
| `lib/widgets/spinning_coin.dart`, `lib/widgets/coin_glyph.dart` | visual primitives | Coin animation/iconography; no economic authority. |
| `lib/widgets/pocket_watch_sheet.dart` and shop screens | spending UI | Show affordability, prices and coin glyphs; purchases are server-authoritative and refresh returned balances. |

Relevant API methods include `/daily-reward/status`, `/daily-reward/claim`, `/daily-reward/claim-extra-box`, `/coins/claim-ad-reward`, shop/powerup purchase endpoints, tutorial completion, referral endpoints, and `/auth/me`. Exact client methods are in `lib/services/backend_api_service.dart:4937-4945,6232-6305,6395-6470`.

### Full current balance path

1. A user taps a Home coin badge/add button or an earning card.
2. Flutter screen/controller calls `BackendApiService`; the client sends the authenticated token and capability headers.
3. Backend route validates identity and reward-specific eligibility.
4. Reward command calls `awardCoins`, normally inside a Prisma transaction.
5. `awardCoins` creates a `CoinTransaction` row and increments `users.coins` atomically; duplicate ledger insertion prevents a second grant.
6. The response contains the resulting balance (`coins`) and reward outcome.
7. Flutter calls `AuthService.updateCoins`, persists the display cache, notifies widgets, and/or performs a full auth/home refresh.
8. `awardCoins` schedules invalidation of the `/auth/me` Redis/cache entry after commit via `authMeCache.invalidateSafe`.

No frontend optimistic coin minting was found. Error paths generally preserve the old displayed balance, show a toast/message, and allow retry. The client is deliberately defensive about missing newer response fields in many newer flows; any new status response must follow that version-skew rule.

## 3. Homepage / Coin UI

The relevant Home tree is `HomeTab` → header/identity area → `CoinBalanceBadge` (`lib/screens/tabs/home_tab.dart:1400-1460`). The add affordance opens the Get Coins/shop route with `ShopFocus.coins`, passing the existing ad controller and rewarded-coins controller. Home also renders `HomeRewardedCoins` and a daily reward block in the home content (`home_tab.dart` around `1540` and `lib/widgets/home_rewarded_coins.dart`).

`GetCoinsScreen` is explicitly documented as “where the + next to the coin balance lands.” Its existing order is balance/header, earn list, rewarded ad, referral/invite, daily box, and coin purchase offers. Keys useful for future tests include `get-coins-earn-list`, `get-coins-watch-ad-card`, `get-coins-referral-card`, and `get-coins-daily-card`.

Relevant tests: `test/get_coins_screen_test.dart`, `test/home_rewarded_coins_test.dart`, `test/home_todays_coins_above_races_test.dart`, `test/daily_reward_box_screen_test.dart`, `test/rewarded_ad_context_cache_test.dart`, and `test/batch_2026_08_08_settings_and_admin_test.dart` (social settings rows). No social reward UI test exists.

The feature belongs in Get Coins, not as a separate parallel wallet. The Home coin badge should remain unchanged except for navigation; the Get Coins hub can add a clearly bounded “Follow Bara” section using the existing card/row spacing and coin presentation.

## 4. Existing Reward Claim Patterns

### Best analogue: tutorial completion

Backend `src/routes/tutorial.js:22-48` calls `awardCoins` with a stable `reason`/`refId`; the frontend method is documented at `lib/services/backend_api_service.dart:4937-4945` as a one-time 100-coin reward protected by the coin ledger so retries/reinstalls do not re-grant. This is structurally closest to a one-time social claim.

### Other analogues

- Rewarded ad: `src/modules/economy/routes/coins.js`, `commands/claimAdCoinReward.js`, `commands/grantAdReward.js`, `adRewards.js`, and Prisma `AdRewardGrant`. Strong server verification and consumption/idempotency, but more complex than social MVP because an external ad provider supplies an immutable SSV identity.
- Daily reward: `src/modules/economy/routes/dailyReward.js`, `commands/claimDailyReward.js`, `commands/claimDailyRewardBox.js`, `queries/getDailyRewardStatus.js`, `DailyRewardClaim`. Uses a dedicated claim table and local-date uniqueness; useful for status/claim separation, but daily recurrence does not match social lifetime claims.
- Referral reward: `src/modules/social/commands/grantReferralReward.js`, `referralRewards.js`, `ReferralRewardGrant`/related referral facts. Strong qualification and durable fact ownership, but referral qualification is multi-party and asynchronous.
- Race/leaderboard rewards: `completeRace.js`, `raceExpiry.js`, settlement/payout services. Reuse `awardCoins` with stable payout refs and transaction boundaries; stronger domain complexity than needed.
- Mystery box/spins: daily box and powerup commands use reward rows/consumption state and `awardCoins` for coin prizes. They are not a direct one-time platform claim analogue.
- Admin grants/giveaways: admin routes and `src/modules/giveaways/services/prize.js` record audit/status and use the ledger. They show how audit metadata can be retained, but social claims should not be admin-authorized.

Comparison: tutorial wins on simple eligibility plus ledger idempotency; daily reward wins on a dedicated durable claim representation; rewarded ads win on provider-bound anti-replay. Social should combine tutorial’s claim path with daily reward’s dedicated per-platform state.

## 5. Database Models

**VERIFIED:** `User` stores the current balance in `prisma/schema.prisma:9-170`, including `coins`, daily fields and relations. `CoinTransaction` is at `schema.prisma:1104-1132`. `DailyRewardClaim` is at `schema.prisma:752-785`; `AdRewardGrant` is immediately below it (`schema.prisma:788-821`). `ActivationEvent` is at `schema.prisma:1134+` and stores privacy-bounded analytics.

### Candidate designs

| Approach | Assessment |
|---|---|
| A. Dedicated `SocialRewardClaim` table with `(userId, platform)` unique | **Recommended.** Models opened/claimed timestamps, amount snapshot, configuration/version, and future verification state. Unique constraint is explicit and durable across devices/reinstalls. |
| B. Generic reward/claim table | Not found as a general-purpose claim table. Existing tables are domain-specific (`DailyRewardClaim`, `AdRewardGrant`, referral/giveaway facts). Creating an abstraction solely to avoid one focused table would add risk. |
| C. Ledger metadata only | Insufficient for a pre-claim opened state and status GET without interpreting coin history. Ledger should remain the financial audit, not the UI state machine. |
| D. Three nullable fields on `User` | Smallest migration but poor extensibility, awkward analytics/status queries, no clean platform uniqueness, and mixes product state into identity. Not recommended. |

Conceptual row: `id`, `userId`, `platform` (server allowlist), `openedAt`, `claimedAt`, `rewardAmount` snapshot, optional `claimVersion`/`verificationState`, timestamps, and relation to `User`; unique `(userId, platform)`, indexes for admin/analytics as needed. Do not create this schema in the research phase.

## 6. Coin Mutation and Transaction Safety

`awardCoins` is the only shared positive balance seam; `deductCoinsAtomic.js` is the paired negative seam. The backend structural guard `test/services/coinSeamStructuralGuard.test.js` protects this invariant. `awardCoins` with a transaction client uses `createMany(..., skipDuplicates: true)` and only increments the balance when the insert count is one. Without an outer transaction it uses a Prisma `$transaction` array and catches `P2002`. The unique ledger index is the concurrency boundary; the preliminary read is explicitly only an optimization.

For two simultaneous `POST .../claim` requests, both may initially read unclaimed state, but only one can insert the same `(userId, reason, refId)` ledger key. The losing transaction’s balance increment is rolled back and it returns `awarded:false` with the current balance. A social claim must use a stable ref such as `platform` plus a fixed reward version, never a client-generated request ID.

The claim-state row should also be updated in the same transaction as the ledger grant. Recommended sequence: validate authenticated user/platform/config; atomically create or conditionally claim the platform row; call `awardCoins({tx, userId, amount, reason:'social_follow_reward', refId:<stable platform/version>})`; commit. If the claim row is the first uniqueness gate and ledger has the same stable key, both protect against different retry/concurrency failure modes. Do not rely on Redis locks or client loading state.

Cache: `awardCoins` invalidates auth-me after commit. No social reward cache exists. Status may be returned from the durable claim table and should not be cached longer than the existing authenticated-user cache contract without an invalidation plan.

## 7. External Link Infrastructure

The Flutter package uses `url_launcher` (`pubspec.yaml`, imports in `lib/main.dart`, `lib/screens/settings_screen.dart`, `lib/screens/start_screen.dart`, `lib/services/store_billing_client.dart`, and `lib/services/live_billing_controller.dart`). Social settings uses `_openAbsoluteUrl` at `settings_screen.dart:178-188`, parses a URI and calls `launchUrl(uri, mode: LaunchMode.externalApplication)`.

This asks the OS to open the external app/browser. There is no Bara-owned “try custom scheme then HTTPS” helper for social links; current links are HTTPS. Failure handling is minimal/best-effort: the returned boolean is not converted into a reward or claim. The reward flow must record `opened` only after a successful `launchUrl` result, while still allowing a browser fallback through the HTTPS URL. It must never award based solely on client success.

## 8. App Lifecycle / Return From Social App

`main.dart:255-312` observes lifecycle and performs auth/session refresh on resume. `RewardedCoinsController.didChangeAppLifecycleState` (`lib/services/rewarded_coins_controller.dart:158-160`) resumes its flow; `settings_screen.dart:1068-1069` and `1204-1205`, `race_detail_screen.dart:1211-1262`, `shop_tab.dart:442-443`, and other controllers refresh on resume. `app_route_observer.dart` supplies a global `RouteObserver`.

There is no existing social-specific return detector and no deep-link callback required for an outbound follow. The likely behavior is: launch URL → record opened server-side (or immediately before launch with explicit outcome) → on `resumed`, refetch social reward status → enable claim if status is opened and not claimed. If the process was killed, the durable opened row still permits the later status/claim flow. If product chooses not to persist “opened,” the claim button can simply remain available after any successful launch, but the stated analytics and return behavior favor persisting it.

## 9. Existing Social URLs

**VERIFIED in current UI:** `lib/screens/settings_screen.dart:500-524` contains:

- Instagram: `https://instagram.com/Bara.steps.app`.
- X: `https://x.com/BaraStepsApp`.
- TikTok: no row/current URL.

**Conflicting evidence:** `docs/feature-batch-2026-08-08-requirements.md:401-408` records Instagram `https://instagram.com/bara.steps` and X `https://x.com/barastepz`, while `test/batch_2026_08_08_settings_and_admin_test.dart:453-454` expects `@BaraStepsApp`. `test/referral_giveaway_frontend_test.dart` uses example social links such as `https://www.instagram.com/bara`, not authoritative product configuration. Canonical handles are therefore **NOT VERIFIED** and require product confirmation.

No TikTok official URL was found. No secrets were exposed. Current implementation patterns hardcode the settings URLs; for rewards, server-owned configuration is safer because changing a destination should not require an app release, but the backend must validate allowed HTTPS hosts and return only supported platforms. A remote-config/feature flag is not currently established as a generic social-reward system.

## 10. Analytics

The app uses `ActivationAnalyticsService` (`lib/services/activation_analytics_service.dart`) and backend `/analytics/activation-events` (`lib/services/backend_api_service.dart:4916+`; backend `src/modules/analytics/serverActivationEvents.js`, `routes.js`, `activationEventInsertBatch.js`). Events carry an allowlisted name, compact context, app version, platform, user identity from the authenticated session, and timestamps. Admin analytics consumes activation events/aggregates.

Recommended names fit the existing event seam: `social_reward_impression`, `social_reward_opened`, `social_reward_claimed`, `social_reward_claim_failed`, context `{platform: instagram|tiktok|x, rewardVersion: ...}`. Impression should be defined once per eligible display/session or once per screen exposure before implementation; otherwise conversion denominators will be ambiguous. Claim success should be server-confirmed, not merely button-tap telemetry. Failure should include a bounded error category, never raw tokens or URLs.

Backend coin ledger data already answers total issued coins and claim timestamps if `reason` and `refId` are stable. A dedicated social claim row makes conversion and “opened but never claimed” queries straightforward. No separate analytics provider was proven in the repository; do not invent one.

## 11. Feature Flags / Configuration

`AuthService` reads additive `featureFlags` from `/auth/me` (`lib/services/auth_service.dart:970+`), and `BackendApiService` sends capability lists (`backend_api_service.dart:390-537`). Backend has app settings/config patterns (`src/shared/config/appSettings.js`, admin settings routes, balance config), but no generic social-follow reward configuration endpoint was found. Feature flags exist in some product areas, but a universal staged rollout contract is **NOT VERIFIED**.

For MVP, fixed server constants for three platforms/200 coins are simplest. If product needs disablement or URL changes without a binary release, use backend configuration returned with the status endpoint, with server validation and additive old-client behavior. Remote reward amount is unnecessary complexity unless operations explicitly need it; if exposed, snapshot the amount in the claim/ledger and never trust a client-supplied amount.

## 12. Admin and Audit Trail

Admin analytics and balance tooling exist (`src/modules/admin`, `lib/screens/admin_metrics_dashboard.dart`, `lib/screens/admin_balance_config_screen.dart`, `lib/screens/admin_purchase_list.dart`). The `CoinTransaction` ledger is already the admin-visible financial history, with a manually maintained admin-history index noted in `schema.prisma:1105-1106`. Existing giveaway admin UI records a coin transaction ID and award timestamps (`test/admin_giveaway_screen_test.dart` fixtures).

Social claims would automatically appear in ledger-based balance/audit queries if they use `awardCoins`, but platform/opened state would not unless a dedicated row is added. No existing admin social-claim page was found. Do not add one for MVP; make ledger reason/refId and claim row fields queryable and document the reason string.

## 13. Abuse and Security

The backend must derive user identity from auth, allowlist platform values, ignore client amount/eligibility, and enforce the unique ledger key. Repeated taps, direct endpoint calls, modified clients, replay, multiple devices, reinstall, and retries then result in at most one ledger grant per authenticated account/platform. UI loading guards improve UX but are not security.

Multiple Bara accounts can still each claim 600 coins. Existing architecture has device registration (`DeviceToken`/`device_tokens`, `installationId`), Apple/Google auth identities, referral identity hashes and rate/admission infrastructure, but a general anti-multi-account social reward control is **NOT VERIFIED**. For a maximum 600-coin honor-system promotion, invasive device fingerprinting is not justified by repository evidence. Use existing authentication/rate-limit/admission conventions only if the endpoint is abused; do not add a new identity system for MVP.

## 14. Offline / Retry Behavior

- Launch while online: record `opened` only on a successful launch result; a failed launch remains retryable.
- Return offline: do not claim locally and do not award. Keep the durable opened state if it was already recorded; show a retryable claim state.
- Claim timeout after commit: retry the same endpoint; stable ledger ref makes the retry return already-claimed/current balance rather than minting again. The UI should refetch `/auth/me`/status after an ambiguous error.
- App killed/social app open: server-persisted opened state survives. On next authenticated status load, show claimable if not claimed.
- Return hours later: status endpoint is authoritative; no time-based expiry unless product explicitly adds one.
- Stale cache: status must be refetched on entering Get Coins and on resume; auth-me invalidation occurs after coin award.
- Second device: claim table and ledger are user-scoped, so state follows the account, not installation.

## 15. Follow Verification Feasibility

### Instagram

**NOT VERIFIED as available for this product.** The repository has no Meta OAuth integration or Instagram API client. Official Meta API capabilities and eligibility change by product/account type; human verification against the current Instagram Graph API documentation is required before treating “does user X follow Bara?” as supported. Any OAuth would require account authorization, scopes, redirect/deep-link handling, token storage, privacy review, and likely would not cover arbitrary consumer-account follow relationships. MVP should not depend on it.

### TikTok

Official TikTok Login Kit is OAuth-based and baseline `user.info.basic` exposes basic profile data; it does not establish a consumer-app “does this user follow Bara?” check. TikTok’s Research API documents a following-list endpoint with `research.data.basic`, but TikTok describes Research Tools as for qualified/approved researchers and public-account data, not a normal commercial consumer reward integration. Sources: [Login Kit overview](https://developers.tiktok.com/docs/en/login-kit-overview), [Query User Following](https://developers.tiktok.com/docs/en/research-api-specs-query-user-following), [Research API eligibility](https://developers.tiktok.com/products/research-api), [Research Tools overview](https://developers.tiktok.com/docs/en/about-research-api). Therefore Research API must not be treated as an available V1 solution.

### X

The repository has no X OAuth/API client. X’s official developer documentation must be checked for the current follower/following endpoint, user-context OAuth scopes, app approval and pricing/access tier before any design. **NOT VERIFIED here as a commercially practical current option.** Even if technically possible, it creates OAuth/token/privacy/permission friction and requires checking current pricing and rate limits. Do not assume an app can query a user’s follow relationship merely from a public profile URL.

### Options

1. Honor system: lowest cost and friction; reliable only for exactly-once coin issuance, not actual follows; recommended MVP.
2. Social OAuth: potentially stronger but platform-specific, privacy-heavy, brittle and likely unavailable/limited for Instagram/TikTok/X in the required relationship form.
3. Username entry: not proof; easy to spoof and creates unnecessary personal-data handling.
4. Manual verification: operationally expensive and not scalable.
5. Scraping/third-party services: unreliable, policy/privacy/security/cost risk; not recommended.

Distinguish copy carefully: rewarding “Follow Bara” claims an action the app cannot verify; rewarding “Open Bara on Instagram and claim” is truthful about the observable action but still may be considered an incentivized social action. Product/legal review is required.

## 16. Platform / App Store Policy Considerations

Repository evidence: `docs/referral-giveaway-requirements.md` explicitly keeps social links optional/non-scoring in giveaways and says social follows/posts are not entry requirements; `docs/feature-batch-2026-08-08-requirements.md` documents the current settings social links. No internal App Store runbook specifically approving coin-for-follow incentives was found.

Official external verification required before shipping:

- Apple App Review Guidelines, especially promotion/incentive, user-data, and external-service provisions: [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). The repository does not prove whether this exact copy is acceptable; obtain human product/legal/App Review review.
- Instagram/Meta terms and platform policies for incentivized actions and API use: current official Meta/Instagram developer policies must be checked at implementation time.
- TikTok developer and community/platform terms; do not use Research API outside its stated approved research purpose.
- X developer terms, automation/manipulation rules, OAuth requirements and commercial access tier.

Do not state that Apple or any network definitely prohibits the feature based on this research. The distinction between rewarding a verified follow and rewarding an opened profile is materially important and needs explicit product/legal review. Use “Open profile, then claim” only if product accepts honor-system semantics and policy review approves the incentive.

## 17. Coin Economy Comparison

Numbers below are repository evidence from `docs/economy.md` and its cited code/live snapshots, not a new production query:

| Source/sink | Existing evidence |
|---|---:|
| Direct rewarded-ad coins | 25 coins/watch, maximum 3/day = 75/day (`docs/economy.md:225-229`) |
| Daily reward | Ladder commonly 10/20/30/40/50; legacy day-6 path 100 (`docs/economy.md:275`) |
| Referral reward | 100 in the cited runtime sample (`docs/economy.md:282`) |
| Race finish reward | approximately 188.5 average in one sample (`docs/economy.md:218`) |
| Tournament champion | live seed prize 150 (`docs/economy.md:252-255`) |
| Powerup prices | examples from 40 to 200; Hitchhike 150 in the cited catalog (`docs/economy.md:350-367`) |
| Ghost Pepper / Leech examples | 200 production prices (`docs/economy.md:862`) |
| Social proposal | 200 each, 600 maximum |

Thus 200 is larger than one direct ad claim and roughly comparable to a race reward or a high/common powerup price; 600 is about eight maximum direct ad-coin days and a meaningful one-time windfall. This is context only, not a product-balance recommendation.

## 18. Test Architecture

Existing backend tests are under `../stepv2-backend/test`, with integration tests intended to use a dedicated test database per `AGENTS.md`. Relevant suites/utilities include `test/services/coinSeamStructuralGuard.test.js`, economy/daily reward tests, admin rewarded-ad tests, referral/giveaway integration tests, and `test/services/appSettingsRequestApiGraduation.test.js`. Relevant frontend tests are listed in Sections 2–3.

Future backend integration matrix:

- first claim for each platform awards exactly 200 and returns resulting balance;
- second claim returns already claimed/zero incremental award;
- two concurrent claims produce one ledger row and one 200 increment;
- unauthorized request, invalid platform, disabled platform, and invalid/stale config are rejected;
- client-supplied amount cannot alter the award;
- existing balance is preserved plus exactly 200;
- claim row and `CoinTransaction` reason/refId/timestamps are correct;
- timeout/retry and duplicate request are safe;
- status follows the same account on a second device;
- old clients/backends handle absent optional fields without crashing.

Future frontend integration/widget matrix:

- each unclaimed platform row renders its label, handle/URL, amount and action;
- correct HTTPS URL is passed to launcher;
- launcher failure does not enable claim or award;
- opened state is recorded and return/resume refreshes status;
- successful claim updates row and `AuthService` balance;
- claimed state persists after rebuild/reinstall simulation and remains independent per platform;
- failed/ambiguous claim can retry;
- loading state prevents duplicate taps;
- no network/offline state does not mint locally;
- analytics events have exact names and allowlisted platform context;
- Get Coins and Home tests cover navigation; settings-link tests remain unchanged.

## 19. Recommended Architecture

### Frontend

Add a social-rewards section to `GetCoinsScreen`, backed by a small controller/state object that loads `GET` status, calls an external URL launcher, records/open state, observes resume, and calls claim. Use `AuthService` for the returned balance. Keep URLs/amounts from the server status payload when possible; defensively default missing optional fields to unavailable rather than inventing prices or URLs. Use `url_launcher` HTTPS URLs with `LaunchMode.externalApplication`; no custom deep-link dependency is needed.

### Backend

Add an authenticated social-rewards module with status, opened, and claim operations. Validate platform against a server allowlist. `opened` records a durable observable launch intent but grants nothing. `claim` validates the row/config and executes claim-row transition plus `awardCoins` inside one Prisma transaction. Use `reason: 'social_follow_reward'` and a stable platform/version ref. Return `{platforms, coins}`/status and `{awarded, coins, claim}` shapes additively.

### Database

Use a new dedicated conceptual `SocialRewardClaim` table (Approach A) with a unique `(userId, platform)` constraint and durable timestamps/amount snapshot. Reuse `CoinTransaction` for all money movement and audit. Do not put the schema or migration in this research phase.

### Conceptual API

`GET /social-rewards/status`

```json
{
  "rewards": [
    {"platform":"instagram","label":"Instagram","url":"https://...","amount":200,"state":"opened","openedAt":"...","claimedAt":null}
  ],
  "totalAvailable": 400,
  "totalClaimed": 200
}
```

`POST /social-rewards/:platform/open`

```json
{"platform":"instagram","state":"opened","openedAt":"..."}
```

This must be idempotent and never award coins. Whether it is called before or after launch is a UX/analytics decision; a successful `launchUrl` result should be required before recording it where possible.

`POST /social-rewards/:platform/claim`

```json
{"platform":"instagram","awarded":true,"amount":200,"coins":820,"state":"claimed","claimedAt":"..."}
```

An already-claimed retry should return a successful idempotent response or an explicit already-claimed response with current balance, but must never increment again. Invalid platform/disabled/not-opened states need explicit stable error codes.

## 20. Simplest Safe MVP

1. Confirm canonical Instagram/TikTok/X URLs and policy wording.
2. Server owns a fixed three-platform config and 200 amount.
3. Add a dedicated claim table with unique `(userId, platform)`.
4. Add GET status, POST open, POST claim; no OAuth, scraping, or remote reward amount.
5. Claim uses the existing `awardCoins` transaction/ledger seam with stable reason/refId.
6. Add Get Coins rows, external HTTPS launch, resume refresh, returned-balance update, and four analytics events.
7. Add integration-first concurrency/retry tests and frontend real-widget tests.

This survives reinstall/device switching because state is account/DB-owned, and exact-once behavior is enforced by database uniqueness rather than client behavior.

## 21. V2 Possibilities

Possible later work: server-configurable campaign/version and platform enablement; expiry or campaign history; verified OAuth only for platforms and scopes that officially support the exact relationship; verification state separate from opened/claimed; admin reporting over claim/ledger facts; cohort/region policy; and a general reward-campaign abstraction if multiple future campaigns prove the need. Do not pre-build these abstractions for a three-row MVP.

## 22. Exact Files Likely To Change

| Repository | File | Current Responsibility | Expected Change | Why |
|---|---|---|---|---|
| Frontend | `lib/screens/get_coins_screen.dart` | Get Coins hub | Render social reward section and claim/open states | Natural existing coin UX |
| Frontend | `lib/services/backend_api_service.dart` | HTTP surface | Add status/open/claim methods | Single frontend HTTP surface |
| Frontend | `lib/services/auth_service.dart` | Auth + cached balance | Consume returned balance only if needed | Preserve wallet refresh pattern |
| Frontend | `lib/services/activation_analytics_service.dart` | Activation analytics | Add allowlisted event names/context if required | Existing analytics convention |
| Frontend | `lib/screens/tabs/home_tab.dart` | Home coin badge/navigation | Likely no change; only route wiring if current navigation cannot target section | Avoid changing Home unnecessarily |
| Frontend | `lib/services/rewarded_coins_controller.dart` | Ad reward lifecycle | Likely no change; reference only for resume/controller patterns | Social is not an ad reward |
| Frontend | `lib/screens/settings_screen.dart` | Existing outbound social links | Probably no change; canonical URL source must be reconciled | Current Instagram/X evidence conflicts with docs |
| Frontend | `test/get_coins_screen_test.dart` | Get Coins widget tests | Add social status/open/claim/error tests | Real widget coverage |
| Frontend | new `test/social_rewards_test.dart` or equivalent | None | Add frontend integration/widget matrix | No current feature tests |
| Backend | `prisma/schema.prisma` | User/ledger/reward models | Add conceptual `SocialRewardClaim` model | Durable per-user/platform state |
| Backend | new migration under `prisma/migrations/` | Schema history | Create table/unique index during implementation only | Required persistence; not created now |
| Backend | `src/shared/economy/awardCoins.js` | Exactly-once coin awards | Reuse; likely no change | Existing authoritative seam |
| Backend | new `src/modules/socialRewards/...` module | None | Status/open/claim routes, commands, validation | Isolate feature without parallel wallet |
| Backend | `src/app.js` / module index | Route mounting | Mount authenticated router | Existing Express composition |
| Backend | `src/modules/analytics/...` | Activation analytics | Allow event names/contexts if backend allowlist requires | Server analytics consistency |
| Backend | admin query/report files | Admin metrics/history | Optional query only if ledger/claim visibility is insufficient | No new admin page needed for MVP |
| Backend | integration tests under `test/integration/` | Public HTTP tests | Add first/second/concurrent/retry/security coverage | Contract and concurrency proof |

## 23. Unknowns / Decisions Needed

- Which exact official Instagram, TikTok and X URLs/handles are canonical? Existing evidence conflicts.
- Is the product willing to say “open and claim” rather than imply verified follow?
- Should “opened” be recorded before launch, after launch success, or only on return?
- Is claim allowed after `opened` from a previous session, including after process death?
- Should status include disabled platforms or omit them?
- Is fixed 200 acceptable for the first campaign, or is an operational kill switch truly required? Release-flag policy says do not add one by default.
- What exact App Review/platform policy review outcome is required before launch?
- Should social status be included in `/home` or fetched only by Get Coins? Separate status fetch is lower coupling.
- Which analytics impression definition will be used for conversion denominators?

## 24. Implementation Risks

- Account/handle ambiguity can send users to the wrong social account.
- Rewarding a claimed follow without verification may conflict with platform or store policy; this is not resolved by code.
- A client-only “opened” flag would be lost on reinstall and is not sufficient; server persistence is required.
- A claim implementation that updates `User.coins` directly or uses a random ref can bypass the proven ledger idempotency seam.
- Claim row and ledger updates split across transactions can leave inconsistent state; they must share one Prisma transaction.
- Old app/backend versions may omit new fields or return 404; frontend must treat optional status safely and backend must add routes/fields compatibly.
- Caching stale claimed status can produce confusing UI; resume/entry refresh and auth-me invalidation are needed.
- Remote-configurable amounts without a stored snapshot make historical audit/reconciliation ambiguous.
- The current social URL conflict is a launch-blocking product decision, not a minor copy issue.
- Testing concurrent claims against production is prohibited; use the dedicated test DB/integration harness.

## 25. Final Research Verdict

Proceed only with an honor-system, server-authoritative, exactly-once claim MVP if product/legal/platform review approves the incentive wording. Place it in Get Coins, use HTTPS external launching and lifecycle resume refresh, persist per-user/platform state in a dedicated table, and route every coin grant through `awardCoins`/`CoinTransaction`. Do not implement social OAuth, scraping, device fingerprinting, a parallel balance, client-trusted amounts, or a generic campaign framework in the first version.

The architecture is already capable of safely handling the financial requirement. The unresolved blockers are product/policy decisions and canonical social account configuration—not coin atomicity.

