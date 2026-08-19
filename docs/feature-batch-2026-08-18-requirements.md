# Feature Batch — 2026-08-18

**Status:** Spec complete; awaiting owner approval. No implementation, store
product creation, credential change, or production deployment is authorized by
this document. The owner accepted the provisional launch packs and refund-debt
policy on 2026-08-18. Architecture, economy, and UI-placement reviews are folded
in below.

## 1. Summary and user stories

This batch contains two features.

1. As a user, I can open my Inbox from the fourth bottom-navigation slot, where
   its unread badge remains visible throughout the shell. I can still reach the
   Leaderboards from a prominent ticket immediately below Suggested Races on
   Home. Inbox controls remain readable in both themes rather than blending
   into their background.
2. As a user who wants coins immediately, I can buy one of three consumable coin
   packs from Get Coins using Apple In-App Purchase or Google Play Billing. A
   verified purchase credits exactly once, survives an interrupted app session,
   and is never granted from a client assertion alone.

## 2. Scope and non-goals

### 2.1 In scope

- Lock the five shell destinations to Home `0`, Races `1`, Friends `2`, Inbox
  `3`, and Profile `4`.
- Replace the fourth `Boards` tab with `Inbox`, including the unread badge.
- Remove the Inbox icon and duplicate unread badge from Home's top-right chrome.
- Add one full-width `LEADERBOARDS` ticket after the complete Suggested Races
  section and before Feedback in every suggestion state.
- Open Leaderboards as a standalone pushed screen with explicit back navigation
  and no selected Inbox/Boards tab illusion.
- Give Inbox an embedded shell mode and refactor destination handling so a tab
  action never pops `MainShell`.
- Replace disabled-looking Inbox mode pills with an accessible selected segment
  and fix contrast for retry/pagination actions.
- Add three consumable packs to the top of Get Coins:

| Server SKU | Apple and Google product ID | Coins | US launch-price target | Bonus vs. small |
|---|---|---:|---:|---:|
| `COINS_100_V1` | `bara.coins.100.v1` | 100 | $0.99 | baseline |
| `COINS_550_V1` | `bara.coins.550.v1` | 550 | $4.99 | 9.1% |
| `COINS_1200_V1` | `bara.coins.1200.v1` | 1,200 | $9.99 | 18.9% |

- Display only the store-returned localized price. The backend never sends or
  accepts a price or currency as purchase authority.
- Use the official Flutter `in_app_purchase` plugin, StoreKit/App Store server
  verification on iOS, and Play Billing/Google Play Developer API verification
  on Android.
- Add an authenticated catalog/preflight endpoint, an authenticated verification
  endpoint, verified Apple Server Notifications V2 and Google RTDN receivers,
  durable finalization/reconciliation jobs, global receipt/token idempotency,
  purchase provenance, refund debt, limits, kill switches, and telemetry.
- Ship and verify iOS and Android together.

### 2.2 Explicit non-goals

- No player-to-player messaging. Inbox remains alerts plus user/support threads.
- No change to Leaderboard ranking, privacy, filters, periods, or backend query
  semantics.
- No redesign of Suggested Races, Feedback, the Home section order other than
  inserting the one Leaderboards ticket, or the other four shell destinations.
- No subscriptions, real-money cash-out, gifting, trading, peer transfer,
  promotional codes, loot boxes, variable rewards, or web checkout.
- No client-calculated grant, client-supplied coin quantity, client-supplied
  price, or trust in `PurchaseStatus.purchased` without store verification.
- No repurposing a live store product ID. A changed amount or commercial bundle
  requires a new versioned ID.
- No production enablement merely because implementation is merged. Store
  products, agreements, credentials, webhook configuration, sandbox testing,
  app review, and the rollout gate are separate operator steps.
- No destructive migration or removal of current Inbox, Leaderboard, Get Coins,
  ad-reward, referral, daily-box, shop, or wallet contracts.

## 3. Current evidence and constraints

### 3.1 Navigation and Inbox

- `lib/screens/main_shell.dart` currently renders `LeaderboardTab` as the fourth
  `PageView` child and `Boards` as the fourth `WoodenTabBar` item. The existing
  `_openLeaderboardTab` animates to that page.
- `lib/screens/main_shell.dart:_openInbox` pushes `InboxScreen`. Its destination
  handler currently pops that route before switching a shell page or pushing a
  detail. Reusing that behavior in an embedded tab could pop `MainShell`.
- `HomeTab` currently reads `raceCard['inboxUnreadCount']` itself and owns the
  top-right Inbox button. Moving only the icon would lose or stale the badge.
- `LeaderboardTab` is designed as a shell child and reserves shell footer/tab
  space. Pushing it directly would leave an incorrect bottom inset and no
  standalone back affordance.
- `tutorial_real_screens.dart` hand-copies the five tab items and hardcodes
  Leaderboard at index `3`. Its stale `TutorialMockPage.leaderboard` and
  `leaderboard.rank` path must not render Leaderboard while selecting Inbox.
- `InboxScreen` currently uses two `PillButton`s and disables the selected one.
  `PillButton` deliberately lowers disabled opacity, causing `ALERTS`/`SUPPORT`
  and several action buttons to blend into the roof-colored background.

### 3.2 Wallet and purchase infrastructure

- `GetCoinsScreen` is the shared destination from Home, Shop, and insufficient-
  coin flows. It currently lists Watch an Ad, Invite Friends, and Daily Box in
  one scrollable parchment body.
- `BackendApiService` has no store-purchase surface and `pubspec.yaml` has no
  IAP dependency.
- The backend stores the spendable balance in `User.coins`. `CoinTransaction`
  has global per-user/reason/ref idempotency, and
  `src/shared/economy/awardCoins.js` plus `deductCoinsAtomic.js` are the guarded
  balance-writing seams.
- `awardCoins` invalidates the `/auth/me` cache. Its injected transaction branch
  currently invokes invalidation before the outer transaction commits; IAP must
  invalidate again after the purchase transaction commits.
- Apple and Google classify these packs as consumable one-time products. Flutter
  requires purchase-stream handling and completion; Android may automatically
  refund an unacknowledged purchase after the platform deadline. Google
  recommends backend verification and backend consumption when a secure backend
  grants the entitlement. See the official
  [Flutter plugin](https://pub.dev/packages/in_app_purchase),
  [Google integration guide](https://developer.android.com/google/play/billing/integrate),
  [Google security guide](https://developer.android.com/google/play/billing/security),
  [Apple StoreKit documentation](https://developer.apple.com/documentation/storekit/in-app_purchase),
  and [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## 4. Product behavior

### 4.1 Shell navigation and unread state

- The order is permanently Home, Races, Friends, Inbox, Profile. Constants,
  `PageView` children, tab items, deep-link routing, and tutorial copies change
  together; no raw index may continue to mean Boards.
- Inbox uses `Icons.inbox_rounded`, label `Inbox`, and the existing wooden-tab
  badge treatment. Badge `0` or a missing/malformed value renders no badge.
- `MainShell`, not `HomeTab`, owns `_inboxUnreadCount`:
  1. defensively seed it from additive `home/race-card.inboxUnreadCount`;
  2. replace it from a valid `GET /inbox/alerts` `unreadCount`;
  3. after a successful read response, use its returned `unreadCount` or, only
     when that field is absent, decrement once for a row that was locally unread;
  4. retain the previous value on timeout, 5xx, malformed data, or failed read.
- Home's Inbox icon and its badge are removed. No blank spacer remains in the
  hero row.
- Selecting Inbox never resets the selected Alerts/Support mode merely because
  another tab was visited. A deliberate auth-user change resets its state.

### 4.2 Embedded Inbox and destinations

- `InboxScreen` gains an explicit host mode or is split into a reusable body:
  `embedded` renders as shell page index `3`, has no back arrow, reserves shell
  footer space, and does not wrap a second bottom navigation; `standalone`
  retains a back affordance only while any legacy/new pushed caller remains.
- Alert destination payloads remain backend-allowlisted through
  `InboxDestination.tryParse`. Missing, malformed, or unknown payloads are a
  no-op after the read attempt.
- Embedded mode never calls `Navigator.pop()` before handling a destination:
  - Home, Friends, Races, and Inbox destinations switch the shell controller;
  - Daily Reward pushes the existing overlay from the shell navigator;
  - race and tournament destinations push their existing detail routes;
  - support opens the selected support thread;
  - Profile, if allowlisted, switches to index `4`.
- Standalone mode may pop itself before a shell switch only when it can prove it
  is the pushed Inbox route. Destination routing is centralized so the two modes
  cannot drift.

### 4.3 Home Leaderboards ticket and standalone screen

- Add exactly one full-width ticket after the whole Suggested Races block and
  before the `FEEDBACK` heading/card. It is outside the carousel/status-body
  builder, so it persists for populated, loading, empty, and error states.
- Visual language: wooden/arcade ticket matching existing Home chrome, explicit
  border and depth, leaderboard icon, title `LEADERBOARDS`, supporting copy
  `See today's top walkers`, and a right chevron. It must have a 48-point minimum
  target, semantic button label, visible focus state, and at least 4.5:1 text
  contrast in light and night palettes. It is not a generic Material card.
- Tap pushes a new `StandaloneLeaderboardScreen`. It reuses the real
  `LeaderboardTab` data/body with a standalone header/back button and bottom
  inset `0` rather than the shell's `77.5`-pixel reservation.
- The standalone host preserves current scope/type/period preference, refresh,
  loading, empty, stale-data, privacy, profile-opening, and retry behavior.
  While touching the response boundary, replace bare server casts with
  missing/null/type-safe parsing and safe empty/error fallbacks.
- Back returns to Home at its prior scroll offset. The bottom shell remains
  behind the pushed route; Inbox is not shown as selected on the Leaderboard.
- Tutorial preview keeps the ticket visible but injects a no-op callback so it
  cannot escape the tutorial.

### 4.4 Inbox contrast and interaction styling

- Replace the two disabled `PillButton`s with a dedicated two-segment selector.
  Both controls remain enabled interaction surfaces; selection is conveyed with
  `Semantics(selected: true)`, not disabled opacity.
- Selected segment: `roofDark`/equivalent strong palette fill, `textLight`, a
  coin-light top edge, and a clear 2-pixel border. Unselected segment:
  `parchmentLight`, `textDark`, and `parchmentBorder`. Night mode uses semantic
  `AppColors.of(context)` values, never bare light constants or alpha alone.
- The Inbox content surface becomes parchment while the app/header roof remains
  strong chrome. Alert/thread rows preserve their current hierarchy.
- `TRY AGAIN`, `LOAD MORE`, `LOAD OLDER`, and the composer `SEND` action receive
  explicit enabled, pressed, focus, loading, and disabled colors. Enabled text
  must meet 4.5:1 contrast; disabled controls remain readable but clearly inert.
- Each segment/action has a minimum 48-point touch target and remains usable at
  200% text size. Loading and empty states do not move above the selector.

### 4.5 Get Coins purchase section

- Add a `BUY COINS` section as the first scroll content under the existing Get
  Coins header. Its cards are ordered 100, 550, 1,200 coins, before Watch an Ad,
  Invite Friends, and Daily Box. Existing earn cards retain their relative order.
- Each pack card shows coin art/glyph, coin quantity, only the store-localized
  price, and optional server-authored `POPULAR`/`BEST VALUE` badge. The button
  label is `BUY FOR <localized price>`. Never synthesize `$` copy from the US
  targets in this document.
- Section states occupy the same top footprint in the scroll view:
  - `loading`: three bounded skeleton tickets;
  - `ready`: only products present in both the valid server catalog and store
    query; missing individual products are omitted and reported to telemetry;
  - `unavailable`: hidden only for definite endpoint 404, `enabled:false`, store
    purchasing unavailable, or no valid matching products;
  - `transient error`: inline `COIN STORE UNAVAILABLE` plus `TRY AGAIN`; the earn
    paths below remain usable;
  - `pending`: the affected card reads `PURCHASE PENDING`, other starts are
    disabled until the coordinator resolves it;
  - `verifying/finalizing`: `VERIFYING PURCHASE...`, with no second checkout;
  - `cancelled`: no grant and a quiet return to ready;
  - `failed`: actionable error without deleting an unfinished store transaction.
- A successful verification updates `AuthService` only from the server's
  returned nonnegative `balance`, shows a one-time coin receipt/reveal, and
  announces the new balance accessibly.
- When `coinDebt > 0`, new checkout is disabled and the section explains
  `Refund balance: N coins. Future coin earnings repay it.` An already charged,
  valid purchase is still verified and applied to the logical debt.

### 4.6 Purchase limits and competitive integrity

- These are default-on launch controls, keyed to the durable provider-identity
  binding rather than a deletable user row:
  - at most 1,200 purchased coins in a rolling 24 hours;
  - at most 6,000 purchased coins in a rolling 30 days;
  - no new checkout while refund debt is positive.
- Limits are a pre-check for starting checkout. A valid transaction already
  charged by a store is always fulfilled, even if callbacks arrive after a
  limit, flag, sign-out, or configuration change.
- Purchased-coin provenance is durable and non-transferable. Paid coins cannot
  fund race/tournament buy-ins or any present/future peer transfer.
- Paid coins may buy cosmetics and powerups. Inventory gained using any paid
  component is stamped paid-funded. Earned inventory is consumed first. A
  paid-funded competitive powerup may be used at most once per user per race
  and once per rolling 24 hours. Cosmetic use has no such cap.
- This requires extending the existing atomic debit seam with an explicit
  spend policy and extending powerup inventory provenance; no caller may infer
  provenance from the current total balance. Existing callers default to their
  current behavior, and buy-in/transfer paths explicitly disallow paid funds.
- Do not reduce the 25-coin ad reward at launch. Compare payer/nonpayer ad views
  before changing the existing earn surface.

## 5. Store and backend authority

### 5.1 Product authority and account binding

- The backend owns an immutable allowlist mapping each server SKU and platform
  product ID to a stamped coin amount. The client cannot request a different
  amount. Products can be disabled, never redefined.
- Each durable IAP identity has an opaque UUID `accountToken`. Pass it as Apple
  `appAccountToken` and Google's obfuscated account identifier. Store verification
  must return the same binding. A callback queued for user A after sign-out can
  never credit user B.
- The binding record is keyed by a non-PII HMAC of provider + provider subject,
  survives account deletion, and can safely rebind when the same provider
  identity recreates an app account. Never log the subject, receipt, JWS,
  purchase token, or full signed notification.

### 5.2 Apple verification

- For an Apple request, use the untrusted transaction ID only to query App Store
  Server API / validate the returned signed transaction. Validate the JWS
  signature chain, Apple environment, bundle ID, transaction ID, product ID,
  product type (consumable), quantity `1`, purchase state, app-account token,
  and absence of revocation. `serverVerificationData` may support StoreKit
  receipt correlation but is never sufficient merely because the device sent it.
- Sandbox transactions are accepted only by the sandbox configuration; a
  production request cannot silently downgrade to sandbox.
- The client finishes the StoreKit transaction only after `GRANTED` or
  `ALREADY_GRANTED`. An ambiguous server timeout leaves it unfinished for
  redelivery.

### 5.3 Google verification and consumption

- Query Google Play Developer API with package name, product ID, and purchase
  token. Validate package, product, token, quantity `1`, `PURCHASED` state, and
  obfuscated account binding. Order ID is audit metadata, never the dedupe key.
- Call `buyConsumable(autoConsume:false)`. After the database grant commits,
  the backend consumes the purchase. Persist `FINALIZATION_PENDING` before the
  attempt; retry durably until Google confirms consumption. Client completion
  mirrors plugin requirements but never substitutes for server consumption.
- `PENDING` is not granted. Cancelled purchases grant nothing. Ambiguous failures
  remain recoverable and must not start a replacement checkout automatically.

## 6. Exact API contract

All client endpoints require the existing authenticated user unless explicitly
marked as a store webhook. Responses are JSON except successful webhooks (`204`).

### 6.1 `GET /iap/coin-products?platform=ios|android`

The app sends its normal capability/version headers and advertises
`iap_coins_v1`. `platform` is required and enum-validated.

Enabled response (`200`):

```json
{
  "contract": "iap-coins-v1",
  "enabled": true,
  "accountToken": "0db5ad7d-42dc-4fb7-b863-9265b939a300",
  "coinDebt": 0,
  "limits": {
    "checkoutAllowed": true,
    "remaining24hCoins": 1200,
    "remaining30dCoins": 6000,
    "reason": null
  },
  "products": [
    {"sku":"COINS_100_V1","storeProductId":"bara.coins.100.v1","coins":100,"badge":null},
    {"sku":"COINS_550_V1","storeProductId":"bara.coins.550.v1","coins":550,"badge":"POPULAR"},
    {"sku":"COINS_1200_V1","storeProductId":"bara.coins.1200.v1","coins":1200,"badge":"BEST VALUE"}
  ]
}
```

Disabled response is `200` with the same contract, `enabled:false`, and an empty
`products` list. It may include a non-user-facing operator reason code. `400
INVALID_PLATFORM`, `401`, and ordinary `5xx` use the existing error envelope.
The app caches definite 404 support per authenticated user/base URL; it does not
turn timeout, malformed JSON, or 5xx into session-long unsupported state.

The feature flag gates catalog exposure and new checkout only. It never disables
verification, finalization, refund handling, or reconciliation.

### 6.2 `POST /iap/coin-purchases/verify`

iOS body:

```json
{
  "platform": "ios",
  "storeProductId": "bara.coins.550.v1",
  "transactionId": "2000001234567890",
  "serverVerificationData": "<opaque StoreKit verification data>"
}
```

Android body:

```json
{
  "platform": "android",
  "storeProductId": "bara.coins.550.v1",
  "purchaseToken": "<opaque Google purchase token>"
}
```

Success/replay response (`200`):

```json
{
  "contract": "iap-coins-v1",
  "status": "GRANTED",
  "purchaseId": "6b6c28d8-9ddb-4b59-a741-fc618e90e78b",
  "coinsGranted": 550,
  "balance": 830,
  "coinDebt": 0,
  "storeFinalization": "CLIENT_FINISH_REQUIRED"
}
```

- `status` is `GRANTED` or `ALREADY_GRANTED`.
- Apple returns `CLIENT_FINISH_REQUIRED`; Google returns
  `SERVER_CONSUMPTION_COMPLETE` or `SERVER_CONSUMPTION_PENDING`.
- A same-user replay returns the original stamped grant and current balance.
- Exact failures:
  - `400 INVALID_PURCHASE_PAYLOAD` or `INVALID_PRODUCT`;
  - `401 UNAUTHENTICATED`;
  - `403 PURCHASE_ACCOUNT_MISMATCH`;
  - `409 PURCHASE_CLAIMED_BY_OTHER_ACCOUNT`;
  - `409 PURCHASE_REVOKED`;
  - `409 PURCHASE_PENDING`;
  - `422 PURCHASE_NOT_VERIFIED`;
  - retryable `502 STORE_VERIFICATION_FAILED`;
  - retryable `503 STORE_VERIFICATION_UNAVAILABLE`.
- No failure completes/consumes an ambiguous purchase. Definite mismatch,
  revoked, or invalid-product results become terminal locally but grant nothing.

### 6.3 Existing Inbox contract addition

`GET /inbox/alerts` adds a default-safe top-level integer `unreadCount`. Existing
fields and cursor behavior are unchanged. Missing/null/malformed means “unknown,”
not zero.

`POST /inbox/alerts/:id/read` remains idempotent and returns:

```json
{"read":true,"unreadCount":2}
```

Older clients ignore the additive body. Reading another user's alert remains
`404`; malformed ID is `400`; authentication remains `401`.

### 6.4 `POST /iap/webhooks/apple`

- Public only in the HTTP-auth sense; authenticity comes from verified Apple
  signed payloads. Validate certificate chain, environment, bundle, transaction,
  and notification data.
- Dedupe by Apple `notificationUUID`. Persist event/state before responding
  `204`. Invalid payload is `400`; transient persistence failure is `5xx` so
  Apple retries.
- `REFUND`/revocation can reverse a credited purchase. A consumption request is
  not itself a completed refund. A verified refund reversal may restore it once.

### 6.5 `POST /iap/webhooks/google-play`

- Accept only authenticated Google Pub/Sub push with validated OIDC audience and
  service-account identity. Invalid auth is `401`.
- Dedupe the Pub/Sub `messageId`, then query Google Play for authoritative state;
  never debit or credit from RTDN fields alone.
- Persist before `204`; persistence/store outages return retryable `5xx`.

## 7. Data model and atomicity

Use additive nullable/default-safe Prisma migrations.

### 7.1 `IapAccount`

- `id`, opaque UUID `accountToken @unique`, non-PII `providerSubjectHash @unique`;
- nullable unique `userId` with `onDelete:SetNull` so tombstone/debt survives;
- nonnegative `paidCoinsAvailable @default(0)`;
- nonnegative `coinDebt @default(0)` representing the logical amount below zero;
- created/updated timestamps and last-bound timestamp.

`User.coins` remains nonnegative for frozen-client safety. New clients display
debt explicitly; old clients safely see zero spendable coins rather than a
negative value they may not understand. On account recreation with the same
provider identity, rebind the durable IAP account and restore its debt/limits.

### 7.2 `IapCoinPurchase`

- `id`, nullable `userId onDelete:SetNull`, required `iapAccountId`;
- `platform`, `environment`, immutable `storeProductId`, server SKU;
- immutable `canonicalStoreKey @unique`:
  `APPLE:<transactionId>` or `GOOGLE:<sha256(purchaseToken)>`;
- redacted/hash-only token lookup material; no plaintext receipt/token logging;
- stamped `coinsGranted`, quantity, verified purchase time;
- lifecycle `RECEIVED|VERIFIED|GRANTED|FINALIZATION_PENDING|FINALIZED|REFUNDED|REFUND_REVERSED|REVOKED`;
- nullable verified/granted/finalized/refunded/reversed timestamps;
- store notification/audit metadata limited to safe identifiers;
- indexes on `(iapAccountId, createdAt)`, `(state, updatedAt)`, and refund/finalize
  reconciliation fields.

The canonical claim row survives user deletion. Global uniqueness, not
user-scoped uniqueness, prevents receipt replay across accounts.

### 7.3 `IapStoreEvent` and reconciliation cursor

- Store, external event ID globally unique per store, canonical purchase key,
  event type, authoritative processed state, safe metadata, received/processed
  timestamps, and retry/error classification.
- A durable per-store cursor/checkpoint supports Apple notification history /
  transaction status and Google Voided Purchases recovery after missed events.

### 7.4 Grant, debt, and provenance transaction

- Lock the purchase and IAP account rows. Verify authoritative store state before
  opening the short database grant transaction; recheck lifecycle/account binding
  under lock before writing.
- Insert/update the purchase and invoke `awardCoins({tx})` in one Postgres
  transaction with `reason:"iap_purchase"` and
  `refId:<canonicalStoreKey>`. The ledger records the stamped gross grant.
- Increment `IapAccount.paidCoinsAvailable` by the spendable portion. If prior
  debt exists, the purchase logically moves that balance toward zero first and
  records a paired deterministic `iap_debt_repayment` transaction; only the
  remainder increments spendable `User.coins`.
- Positive future awards likewise repay debt first using a paired deterministic
  ledger row, then credit the remainder. Existing reward idempotency remains the
  boundary. Invalidate `/auth/me` after the outer transaction commits.
- Atomic spend extends `deductCoinsAtomic` with explicit provenance policy.
  Earned coins are consumed first. Paid balance is consumed only when allowed,
  and paid-funded inventory quantity is stamped atomically.
- Refund handling locks the same purchase row. Only a credited purchase debits,
  exactly once, using deterministic `reason:"iap_refund"`. Remove available
  balance down to zero, reduce paid provenance, and place any unrecovered amount
  in `coinDebt`; never make stored `User.coins` negative. An uncredited refund
  creates a terminal tombstone and no debit.
- Refund/revocation wins any race with verification. A `REFUNDED`/`REVOKED` row
  can never later become `GRANTED`. A verified `REFUND_REVERSED` restores exactly
  once with `reason:"iap_refund_reversed"` and first clears related debt.
- All authoritative purchase, balance, debt, provenance, refund, and finalization
  state is Postgres-only. Redis may not be a source of truth.

## 8. Frontend implementation path

### 8.1 Navigation and UI files

1. Write widget tests first for shell order/indexes, unread badge ownership,
   embedded destinations, Home ticket order in every suggestion state,
   standalone back/inset behavior, Inbox contrast/semantics, and tutorial copy.
2. In `lib/screens/main_shell.dart`, replace Boards child/item/index with Inbox,
   lift unread state, centralize destination routing, and pass callbacks/state.
3. In `lib/screens/tabs/home_tab.dart`, remove Inbox chrome and add the injected
   Leaderboards ticket after Suggested Races/before Feedback.
4. Add `lib/screens/leaderboard_screen.dart` as standalone host; parameterize
   `lib/screens/tabs/leaderboard_tab.dart` for host inset/header semantics and
   harden response parsing.
5. Refactor `lib/screens/inbox_screen.dart` for embedded mode, selected segment,
   semantic palette, and unread callback. Update
   `BackendApiService.markInboxAlertRead` to return defensively parsed data.
6. Update `lib/tutorial/tutorial_real_screens.dart`, tutorial fixtures/tests,
   and any raw index/deep-link assumptions. Remove the unused Leaderboard mock
   path if no beat references it; otherwise render it as standalone with no
   fourth tab selected.

### 8.2 Purchase coordinator and screen

1. Add `in_app_purchase` and its platform implementation imports through the
   Flutter package, preserving both-platform native dependency lockstep.
2. Add an injectable `lib/services/iap_purchase_coordinator.dart`, constructed
   once with the other app-lifetime services before `runApp`, then supplied to
   `MainShell` and every Get Coins push.
3. The coordinator owns exactly one purchase-stream subscription, queues events
   until authentication restoration, keys pending work to the account token,
   serializes duplicates by canonical purchase key, and never credits the user
   signed in after a purchase began.
4. On launch/resume, query outstanding Android purchases and consume retries;
   rely on StoreKit unfinished-transaction redelivery on iOS. Persist minimal
   non-secret pending metadata locally only to improve recovery; backend/store
   remain authoritative.
5. Add exact catalog/verify methods and per-user/base-URL 404 capability caching
   to `lib/services/backend_api_service.dart`; add `iap_coins_v1` to both
   capability-header construction branches.
6. Add the first-section purchase state/cards to
   `lib/screens/get_coins_screen.dart`. Inject the coordinator from Home, Shop,
   and insufficient-balance entry paths rather than constructing leaf listeners.
7. Finish Apple only after `GRANTED|ALREADY_GRANTED`; let the backend consume
   Google after commit and retry `FINALIZATION_PENDING`. Never call a grant from
   a local receipt parser.

## 9. Backend implementation path

1. Write real HTTP + test-Postgres integration tests before logic. Confirm
   `DATABASE_URL` is the dedicated `steps-tracker-integration` database before
   running; never point tests at production.
2. Add the expand-only migration and Prisma models. Apply no destructive change.
3. Add `src/modules/iap/` with one query/command per file, model-only Prisma
   access, injected Apple/Google clients, `asyncHandler`, `AppError`, module
   `index.js`, and a thin mount in `src/app.js`. Do not add legacy
   `src/routes/*` files.
4. Add immutable product policy, account binding, catalog query, verification,
   grant transaction, refund state machine, notification authentication/dedupe,
   server-side Google consumption, and reconciliation services.
5. Extend `awardCoins`/`deductCoinsAtomic` rather than adding a third direct
   `users.coins` writer. Update the structural guard and all debt/provenance
   cases. Re-invalidate auth cache after committed outer transactions.
6. Add `iapCoinPurchasesEnabled:false` to `KNOWN_FLAGS`. Add separate global,
   platform, and SKU checkout switches. None may disable already-started
   verification, finalization, refunds, or reconciliation.
7. Register reconciliation/finalization scheduling inside the existing
   `startCrons()` cluster guard with an environment kill switch. The kill switch
   may pause reconciliation jobs, never webhook authenticity or durable event
   recording.
8. Add redacted operational lookup/logging sufficient to find a purchase by
   canonical transaction hash, user, status, and timestamp without exposing
   tokens or receipts. A new admin UI is not required in this batch.

## 10. Backward compatibility and rollout

### 10.1 Version-skew behavior

- Frozen clients never call `/iap/*`, ignore additive Inbox response fields and
  feature flags, and keep their existing Boards tab/Home Inbox layout. The new
  backend must continue satisfying every old endpoint unchanged.
- New app against an old backend: navigation and styling work locally; a definite
  catalog 404 hides purchasing for that user/base URL; earn cards still work.
  Inbox unread count falls back to the last valid Home value or no badge. No
  missing/null field can crash.
- New app against a transiently failing new backend: purchasing shows retry and
  leaves earn paths active. It never converts 5xx/timeout/malformed data into a
  permanent unsupported cache entry.
- A frozen client on an account with refund debt receives nonnegative
  `User.coins` (possibly zero), so existing display/affordability logic remains
  safe. It ignores additive debt/provenance. Backend spending remains authoritative.
- Disabling storefront exposure mid-purchase blocks new checkout but does not
  strand charged purchases, finalization, refunds, or reconciliation.

### 10.2 Rollout order

1. Create matching sandbox/test and production consumable products in App Store
   Connect and Play Console with the exact IDs. Complete paid-app agreements,
   tax/banking, service accounts, API roles, Pub/Sub/OIDC, Apple keys, localized
   names/descriptions/prices, review screenshot, and support metadata.
2. Submit the first Apple IAP products with the carrying iOS build as required by
   App Store Connect. Keep backend exposure default-off.
3. Deploy additive schema/backend first, default-off. Validate bundle/package,
   environment separation, credentials, signed Apple notifications, Google RTDN,
   Google consumption, reconciliation, redaction, and scheduler singleton in
   staging/sandbox.
4. Build and verify iOS (no flavor) and Android prod/staging flavors with the same
   version/build and backend URL rules. A plugin added for one platform must link
   and launch on the other.
5. Ship both stores. During the approximately one-week phased rollout, keep
   purchase catalog exposure off until the approved carrying builds are available.
6. Enable one platform/SKU at a time, beginning with the 100-coin pack; observe
   verification/finalization/refund metrics, then open remaining packs.
7. Production deploys, migrations, store-console changes, and flag flips each
   require explicit in-the-moment owner confirmation.

## 11. Economy guardrails and observability

Independent review verdict: **SOUND WITH CHANGES**. The required changes are
the provenance, non-transferability, competitive-use limit, purchase limits,
durable refund debt, kill switches, and monitoring specified above.

Launch telemetry must include catalog impressions, pack selection, native sheet
open, pending/cancelled/purchased callbacks, verify/grant/replay/rejection,
account mismatch, global duplicate conflict, finalization age, refunds/reversals,
debt amount/age/repayment, paid issuance by SKU/platform, paid-coin sink, paid-
funded powerup use, payer/nonpayer ad views, and step-matched payer/nonpayer race
win rates. Never include a receipt/token/JWS.

Alert and pause **new checkout only** when any occurs:

- paid issuance exceeds 1,850 coins/day over seven days;
- total economy source/sink ratio exceeds 3.0x;
- refund rate exceeds 5%;
- verification failure exceeds 1%;
- any cross-account/global duplicate grant occurs;
- a Google finalization approaches the platform deadline.

Refund/finalization processing remains live while checkout is paused. Do not
retune ads or existing sources/sinks in the same rollout. The live baseline and
provisional pack analysis are recorded in `docs/economy.md`.

## 12. Tests-first plan

### 12.1 Backend integration tests

Write these as real authenticated HTTP requests through the mounted app with the
dedicated test Postgres and injected deterministic store clients:

1. Catalog default-off, enabled, per-platform/SKU switches, limits, debt block,
   invalid platform, old-client unaffected, and no price/currency authority.
2. Apple valid grant, invalid JWS/chain/bundle/environment/product/quantity/state,
   revoked/pending, account-token mismatch, and transient App Store outage.
3. Google valid grant/consume, invalid package/product/token/quantity/state,
   account mismatch, pending, API outage, and durable consume retry.
4. Same-user concurrent replay grants once and returns `ALREADY_GRANTED`; another
   user cannot claim the global key; delete/recreate cannot replay it.
5. Grant row, coin ledger, balance, paid provenance, and state commit atomically;
   forced failures roll everything back; auth cache is invalidated after commit.
6. Refund after no grant creates a tombstone/no debit; refund after grant debits
   once; insufficient funds create durable debt without negative `User.coins`;
   future awards repay debt; refund reversal restores once.
7. Refund-before-grant and concurrent refund/verify always end terminal without a
   post-refund grant. Duplicate/out-of-order notifications cannot double debit.
8. Apple notification signature/UUID dedupe and Google OIDC/message dedupe +
   authoritative re-query; persistence occurs before 204.
9. Reconciliation finds missed Apple/Google refunds and resumes durable cursors.
10. Feature/checkout flag off mid-purchase still verifies, finalizes, refunds,
    and reconciles. Redis unset/failing changes no result.
11. Purchase limits bind to durable identity across deletion; a valid already-
    charged purchase over a stale preflight limit is still fulfilled.
12. Paid funds cannot enter buy-in/transfer; paid-funded inventory stamps
    correctly; earned inventory consumes first; competitive cap is enforced.
13. Existing ad reward, daily reward, referral, shop, powerup, buy-in, payout,
    `/auth/me`, and Inbox integration suites remain unchanged and pass.
14. Scheduler registers once under PM2/cluster and respects only its job kill
    switch; webhook recording remains active.

### 12.2 Flutter widget/integration tests

Pump real screens/widgets with fake-by-subclass API/store coordinator:

1. Shell order Home/Races/Friends/Inbox/Profile, selected index, unread badge
   seed/update/failure retention, and no Home Inbox icon.
2. Every embedded destination: Home, Friends, Races, Daily Reward, race,
   tournament, support, malformed; none pops the shell.
3. Leaderboards ticket after Suggested Races and before Feedback for success,
   loading, empty, and error; tutorial callback cannot escape.
4. Standalone Leaderboard back navigation, zero shell inset, filters/refresh,
   profile route, missing/null/malformed response, loading/empty/error/stale data.
5. Inbox segment selected semantics and contrast tokens, retry/load placement,
   empty/error/list/thread/composer states, large text, and both themes.
6. IAP catalog 404/disabled hides only Buy Coins; transient error retries;
   malformed/missing/extra products are safe; localized prices are used verbatim.
7. Pack order and card placement from every Get Coins entry point; small screen,
   200% text, notches, keyboard, ad-banner safe area, light/night.
8. Purchase ready/pending/cancel/error/verify/replay/finalization states; no local
   grant; no duplicate listener; no checkout during debt or limits.
9. Sign-out/account switch during purchase cannot credit the new account;
   authentication restoration resumes the correct queued purchase.
10. Launch/resume recovery, Apple unfinished redelivery, Android outstanding
    query, server-consumption pending, and ambiguous timeout remain retryable.
11. Success updates from server balance once and renders receipt/reveal; debt
    repayment copy is truthful.
12. Tutorial hand-copied nav, stale Leaderboard mock handling, spotlights, and
    playable demo exclusions.

### 12.3 Required validation before “done”

- `flutter analyze` clean.
- Relevant Flutter tests pass, then full `flutter test` passes.
- Backend `npm run test:unit` and `npm run test:integration` pass against the
  confirmed test DB; never run bare `npm test`.
- iOS and Android sandbox purchases tested, including interrupted purchase,
  reinstall/redelivery, pending Google payment, duplicate callback, refund,
  refund reversal where supported, server outage, and store outage.
- Both platform builds link and launch with synchronized version/build/config.
- Code reviewer runs after the two implementation agents finish.
- The manual checklist below is handed to the owner verbatim.

## 13. Acceptance criteria / definition of done

- [ ] Fourth shell slot is Inbox with accurate shell-owned unread badge; Boards
      and Home Inbox icon are absent in the new build.
- [ ] Leaderboards ticket always appears exactly between Suggested Races and
      Feedback and opens the full real board with working back navigation.
- [ ] Inbox destinations never pop the shell; all allowlisted routes work.
- [ ] Inbox selector/actions have explicit accessible contrast and semantics in
      light/night, large text, loading, disabled, and error states.
- [ ] All three packs appear above earn paths with store-localized prices only.
- [ ] No client value can determine a coin grant; Apple/Google and server
      allowlist/account binding are verified.
- [ ] Every canonical store transaction grants at most once globally and is
      recoverable across interruption without double credit.
- [ ] Google consumption and Apple finish happen only after a committed grant;
      retries cannot strand or duplicate entitlement.
- [ ] Refunds/reversals are authenticated, reconciled, idempotent, race-safe, and
      create durable logical debt without exposing negative `User.coins` to old
      clients.
- [ ] Paid provenance, buy-in/transfer exclusion, competitive-use cap, rolling
      purchase limits, checkout switches, and alerts are enforced server-side.
- [ ] Old app/new backend and new app/old backend paths remain safe and useful.
- [ ] Tests were written first and passed; analyze is clean; both platforms and
      store sandboxes are verified; required reviewers/checklist are complete.

## 14. Manual UI-placement test plan

The following is the `ui-test-planner` output, included verbatim.

**Manual UI-Placement Test Plan — Feature Batch 2026-08-18**

*Elements under test:* The fourth bottom-nav item moves from Boards to Inbox, with the unread badge moving from the Home hero’s top-right Inbox icon onto that nav item.

*Elements under test:* The Home top-right Inbox icon is removed.

*Elements under test:* A LEADERBOARDS ticket is added directly below Suggested Races and directly above Feedback; it opens Leaderboard as a standalone screen with back navigation.

*Elements under test:* Inbox ALERTS/SUPPORT controls and TRY AGAIN/LOAD MORE/LOADING actions retain their existing positions while their presentation changes.

*Elements under test:* Three coin-purchase cards are added as the first content on Get Coins, above Watch an Ad, Invite Friends, and Daily Box, with loading, pending, error, and unavailable layouts occupying that same purchase area.

*Checklist*

1. **Main shell — real Home and bottom navigation, iOS**
   - **Get there:** Sign in on an iPhone with an account whose Home payload has at least one unread Inbox item; visit Home, then each other bottom tab.
   - **Verify:** The fourth nav slot is Inbox, between Friends and Profile, with its unread badge attached to the Inbox nav item on every tab. Boards is absent from the nav. Home has no Inbox icon in the hero’s top-right and no duplicate unread badge there. Check the nav clears the home indicator and the badge does not collide with the label or adjacent tabs.

2. **Main shell — real Home and bottom navigation, Android**
   - **Get there:** Sign in on a small Android phone with unread Inbox items; visit Home, then each other bottom tab.
   - **Verify:** The fourth nav slot is Inbox in the same order, its badge stays attached to that item, Boards is absent, and the former Home top-right Inbox icon is absent. Check the nav clears gesture/three-button system navigation and the badge does not overlap Friends or Profile.

3. **Home — Leaderboards ticket in every Suggested Races state**
   - **Get there:** On staging, open Home once with suggested races populated, once while suggestions are initially loading, and once with the suggestions empty or failed.
   - **Verify:** In every state, exactly one LEADERBOARDS ticket appears after the complete Suggested Races section/status ticket and before the FEEDBACK header/card. It is not inside the horizontal race carousel, not above Suggested Races, and not duplicated elsewhere on Home.

4. **Standalone Leaderboard — real navigation**
   - **Get there:** Home → scroll below Suggested Races → LEADERBOARDS.
   - **Verify:** Leaderboard opens above the shell as a standalone screen, has a visible back affordance at the top, and does not show Leaderboard as the selected fourth bottom tab. Back returns to Home at the same scroll position, with the LEADERBOARDS ticket still between Suggested Races and Feedback.

5. **Inbox — real fourth nav destination**
   - **Get there:** Tap Inbox in the fourth nav slot with accounts that have alerts, support threads, multiple pages of results, and an empty state; force one initial-load failure.
   - **Verify:** Inbox occupies the shell’s fourth page exactly once. ALERTS and SUPPORT remain side by side at the top above the list. Initial TRY AGAIN stays centered in the content area; LOAD MORE/LOADING stays after the final row rather than floating over rows or the nav; empty-state content remains below the selector. No Leaderboard content remains behind or alongside Inbox.

6. **Inbox support thread — keyboard and pagination placement**
   - **Get there:** Inbox → SUPPORT → open a thread with older messages; tap the composer to show the keyboard, then dismiss it; force an empty initial-load failure if the staging fixture supports it.
   - **Verify:** LOAD OLDER stays above the message history, the initial TRY AGAIN remains in the history area, and the composer/send control remains pinned above the keyboard and bottom safe area without covering messages. None of these actions is duplicated in the Inbox list.

7. **Get Coins — normal purchase-card order from every entry point**
   - **Get there:** Open Get Coins from Home’s coin-balance “+”, then repeat from Shop’s coin-balance “+” and a Shop insufficient-coins purchase prompt.
   - **Verify:** All entry paths show the same single Get Coins screen. The 100-, 550-, and 1,200-coin purchase cards are the first three content cards in ascending order. They appear above Watch an Ad when that card is available and always above Invite Friends and Daily Box. Existing earn cards have not moved between one another or been duplicated.

8. **Get Coins — store presentation states**
   - **Get there:** Use the StoreKit/Play Billing sandbox fixtures to hold product loading, hold one purchase pending, return a product-load error, and make purchases unavailable.
   - **Verify:** Loading, pending, error/retry, and unavailable content occupies the purchase section at the top of the same scroll view. It does not move below the earn cards, cover the header or ad banner, leave duplicate pack cards behind, or remove/reorder Invite Friends and Daily Box.

9. **Responsive layout, text scaling, themes, and safe areas**
   - **Get there:** Repeat Home, Inbox, standalone Leaderboard, and Get Coins on the smallest supported phone and a large phone/tablet; test 200% system text; switch Settings → Appearance between Light and Dark. Include an iPhone with a notch/home indicator and an Android device with display cutout/gesture navigation.
   - **Verify:** The five nav items remain in order and fit without overlap; the Inbox badge remains anchored to its icon; the Home LEADERBOARDS ticket remains between Suggested Races and Feedback; standalone Leaderboard’s back affordance remains reachable; Inbox selectors/actions remain in their intended rows; all three purchase cards stay ahead of the earn cards and remain reachable by scrolling. No element clips into the status bar, bottom safe area, ad banner, or keyboard.

10. **Tab tutorial preview — hand-forked bottom bar**
    - **Get there:** Profile → Settings → View Tutorial; advance through every spotlight beat.
    - **Verify:** Every preview that shows the copied bottom bar uses Home, Races, Friends, Inbox, Profile in that order; Boards is absent. The active fourth-slot assumption never highlights or renders Leaderboard there. Existing spotlights, including `nav.friends`, still ring their intended elements and not the new Inbox slot.

11. **Tab tutorial preview — shared Home surface**
    - **Get there:** Profile → Settings → View Tutorial; inspect both Home beats, including the final Home beat, scrolling only if the preview permits it.
    - **Verify:** The real preview Home has no top-right Inbox icon. The LEADERBOARDS ticket is present exactly once below the seeded Suggested Races section and above Feedback, without covering or shifting the `home.steps`, `home.shop`, or other spotlight targets away from their rings. It must not navigate out of the tutorial if tapped.

12. **Fresh-account onboarding variants**
    - **Get there:** On one fresh account run the spotlight/tab tutorial path; on another fresh account with tutorial v3 enabled run the playable demo race, then enter the real shell.
    - **Verify:** The spotlight path matches checkpoints 10–11. The playable demo contains no shell nav, Home LEADERBOARDS ticket, Inbox, or Get Coins purchase cards. After either onboarding path completes, the real shell shows Inbox in slot four and no Home Inbox icon.

*Surfaces confirmed unaffected:* Demo race tutorial (`demo_race_host.dart`) renders create-race, invite, race-detail, and case-opening surfaces, not MainShell, Home, Inbox, Leaderboard, or Get Coins; none of the new elements should appear during the playable demo.

*Surfaces confirmed unaffected:* Demo race-detail and tutorial race-detail previews reuse `race_detail_screen.dart`; the batch does not move any race-detail element or its `tutorialPowerupsKey`/`tutorialClockKey` anchors.

*Surfaces confirmed unaffected:* Create-race and race-invite demo prologue beats do not render the shell or any changed host screen.

*Surfaces confirmed unaffected:* Case-opening and multi-case-opening demo pushes do not render the shell or Get Coins.

*Surfaces confirmed unaffected:* Races, Friends, and Profile production tab bodies are not changing; only their surrounding shell’s hand-copied tutorial nav must be checked.

*Surfaces confirmed unaffected:* The admin Inbox in `admin_sections.dart` is a separate `AdminInboxBody`, not the recipient Inbox screen; its placement should remain unchanged.

*Risks found while planning:* `tutorial_real_screens.dart` hand-copies the five `WoodenTabBar` items and hardcodes Leaderboard as tab index 3. Replacing only `main_shell.dart` will leave the tutorial showing Boards and can make its active-index mapping wrong.

*Risks found while planning:* `tutorial_real_screens.dart` still owns a standalone `TutorialMockPage.leaderboard`, its index-3 mapping, and a `leaderboard.rank` spotlight key even though the current five-step tutorial does not use that page. Implementation must remove or deliberately remap this stale path so it cannot select Inbox while rendering Leaderboard.

*Risks found while planning:* The unread count is currently parsed inside `HomeTab` from `raceCard['inboxUnreadCount']`. Moving the badge to shell chrome requires lifting that value/state out of Home; otherwise the nav badge will be missing, stale, or available only while Home is built. A missing legacy-backend field should remove only the badge, not the Inbox nav item.

*Risks found while planning:* Home’s tutorial preview intentionally omits Inbox navigation callbacks and currently suppresses the Home Inbox icon with `isTutorialPreview`. The new LEADERBOARDS ticket is on the shared Home surface, so preview wiring must keep it visible but unable to escape the tutorial.

*Risks found while planning:* The Home ticket must be outside `_buildSuggestedRacesBody`; that body changes height and structure across carousel, loading, empty, and error states. Placing the ticket inside it risks hiding it or putting it in the horizontal carousel.

*Risks found while planning:* `LeaderboardTab` is currently the shell’s fourth page and does not itself establish standalone back navigation. The new Home route needs a wrapper/header/back affordance, while the shell page list must replace index 3 with Inbox without disturbing existing deep-link and page-controller index assumptions.

*Risks found while planning:* Get Coins is reached through multiple independent pushes in Home and Shop. All must construct the same IAP-capable screen/service configuration or users will see different top-card placement depending on entry path.

*Risks found while planning:* Get Coins currently has a fixed header, one vertical `ListView`, and a bottom ad with safe-area handling. Three new cards and their state variants must remain inside that list so small screens and large text scroll instead of clipping behind the header or ad.

## 15. Revision log

- **Initial exploration (2026-08-18):** based the format on the 2026-08-17
  batch; traced shell/Home/Inbox/Leaderboard/Get Coins, backend coin ledger, and
  both repositories' compatibility rules.
- **Gap pass 1:** separated embedded Inbox from pushed Leaderboard; locked all
  five indices, shell-owned unread lifecycle, destination behavior, every Home
  suggestion state, tutorial copies, standalone inset/back behavior, and
  defensive Leaderboard parsing.
- **Gap pass 2:** made the money contract exact; added durable account binding,
  global receipt uniqueness, interrupted-purchase recovery, grant/finalization
  ordering, refund races/reversals, missed-event reconciliation, old-backend
  degradation, platform/store rollout, redaction, and tests-first coverage.
- **Owner interview (2026-08-18):** owner accepted provisional defaults of
  100/$0.99, 550/$4.99, 1,200/$9.99; purchase cards at the top of Get Coins; and
  logical negative refund debt repaid by future earnings.
- **Architect review (2026-08-18):** required embedded destination safety,
  exact JSON/error contracts, account-token validation, immutable allowlist,
  atomic tombstone/grant, app-lifetime coordinator, server-side Google consume,
  authenticated/deduped notifications, reconciliation, cluster guarding, and
  default-off rollout. All are incorporated. The spec improves frozen-client
  safety by storing logical debt separately while keeping `User.coins`
  nonnegative.
- **Economy review (2026-08-18):** verdict `SOUND WITH CHANGES`; incorporated
  paid provenance, buy-in/transfer exclusion, paid-funded competitive-use cap,
  rolling purchase limits, durable identity/debt, checkout switches, and metric
  thresholds. The reviewer updated `docs/economy.md` with live baselines and
  marked these packs as planning values, not live configuration.
- **UI-placement review (2026-08-18):** incorporated the hand-forked tutorial
  nav/index risk, shell badge ownership, standalone Leaderboard host, shared Home
  placement, all Get Coins entry points, responsive/store states, and the
  verbatim checklist in section 14.
