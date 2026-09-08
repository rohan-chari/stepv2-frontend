# Coin purchases, paid rerolls, and Bara+ — implementation plan

Status: **real implementation and all final policy answers approved**, 2026-09-07.
The user approved the frontend preview and requested completing the remaining
implementation. `bara-billing-contract.md` now owns the locked implementation
interface and supersedes the earlier technical proposals below. Production
deployment and store release remain separate steps. The user approved all refund/calendar/restore/test-account recommendations;
the locked contract records their exact rules.

## 1. Summary and scope

User story: a signed-in Bara player can buy coins, pay for box rerolls, and
subscribe to Bara+ with explicitly defined recurring benefits on iOS and Android.
The backend continues to serve frozen older clients throughout deployment.

Confirmed in this conversation: the user wants an implementation plan for these
monetization features, asks that nothing be assumed, and invites questions.
User decisions recorded 2026-09-07:
- Use RevenueCat for coin purchases and Bara+, retaining the existing backend
  as wallet/benefit authority.
- Coin packs selected: 500/$0.99, 2,800/$4.99, 6,000/$9.99 (US reference
  prices, localized by the platform store). Earlier pack quantities are superseded.
- Include all discussed Bara+ benefits: cosmetic and powerup shop discounts,
  included rerolls, monthly cosmetic, member badge/profile customization, and
  monthly coins. Selected monthly plan is $4.99, 15% shop discount, 500 coins
  and ten paid reroll actions per month, plus the cosmetic and member styling.
- Offer monthly at $4.99 and annual at $49.99. Annual subscribers receive all
  6,000 coins and 120 paid reroll actions upfront after the successful annual
  payment, including after trial conversion. No monthly annual coin/credit drip.
- Cosmetics follow a shared calendar collection. Exact award boundaries,
  duplicate handling and calendar timezone remain to be confirmed.
- Subscription trial lasts seven days. Permanent cosmetic and coin gifts begin
  only after the first successful payment. Trial includes active discount/member
  styling and three trial reroll actions; unused trial credits expire at trial
  end. First payment grants the full paid allowance, coins and cosmetic.
- Charge 50 coins per reroll action, including Reroll All. All methods share the
  existing one-reroll-per-item limit and replacement/odds rules.
- Unused paid reroll credits carry over and remain usable after membership ends.
  Normal subscription expiry never deletes or disables these paid credits.
- Retain separate Apple/Google accounts; do not add account linking in this scope.
- Purchased coins can be spent anywhere existing coins can, including powerups
  and race/tournament buy-ins. Do not introduce paid-source spend restrictions.
- Refund policy: absorb already-spent coin shortfalls; no debt or recovery from
  future earnings. Precise available-balance debit allocation and subscription
  refund treatment still need definition. The chosen policy does not authorize
  purchase/use penalties, account bans or reversing other players' race rewards.

Not yet confirmed: cosmetic award boundaries and duplicates, purchase limits,
remaining refund rules, account
restoration/transfer rules, launch territories, and operational/admin scope.
Web checkout, additional purchase types, and any paid advantage restrictions
must be explicitly included or excluded in the interview.

## 2. Prior-document reconciliation

- `docs/bara-plus-monetization-concept.md` is an unapproved product concept.
- `docs/feature-batch-2026-08-18-requirements.md` contains an earlier direct-store
  coin-purchase plan. Its subscription exclusion and manual finish/consume
  instructions cannot govern a RevenueCat subscription integration.
- Prior price candidates were 100/$0.99, 550/$4.99, 1,200/$9.99 (US reference
  prices). User selected replacements 500/$0.99, 2,800/$4.99, 6,000/$9.99.
  Older `docs/economy.md` section 13 prices also conflict and are not authoritative.
- Prior owner-interview notes mention refund debt; the current session explicitly
  chooses to absorb spent shortfalls, superseding those debt requirements.
- Earlier purchase caps and paid-powerup use caps were review proposals, not
  accepted requirements. Paid-source spend/buy-in restrictions are now expressly
  excluded. Retain purchase provenance needed for auditing/refunds without
  restricting where purchased coins are spendable.
- Remove/supersede prior launch flags from the final billing plan. Repo rules
  prohibit release flags unless the user explicitly approves an exception.
- Earlier warning about precommit `awardCoins` cache invalidation is stale:
  current backend uses `deferUntilAfterCommit`. Preserve that transaction path.

## 3. Open decisions / interview

| ID | Decision needed | Why it changes implementation |
|---|---|---|
| D01 — RESOLVED | RevenueCat for both stores and both product types | SDK, verification, notification and completion ownership |
| D02 | First-release purchases: coins, rerolls, membership only? | Store catalog and endpoints |
| D03 — RESOLVED | All discussed benefits, including cosmetic and powerup discounts and monthly coins | Membership model, pricing and inventory grants |
| D04 — RESOLVED | Packs selected; membership $4.99/month, 15%, 500 coins, 10 rerolls; reroll 50; annual $49.99 with 6,000 coins and 120 credits upfront | Immutable SKU mapping and benefit stamps |
| D05 — RESOLVED | Monthly AND annual; 7-day trial with 3 expiring credits; permanent gifts and full paid allowance after charge | No annual currency/credit installment scheduler |
| D06 — RESOLVED | One credit/cost per action including Reroll All | Batch charging, allowance display and economics |
| D07 — RESOLVED | Keep current one-reroll cap, replacement rules, and odds for all methods | Single/batch eligibility and outcome engine |
| D08 — RESOLVED | Paid credits roll over and remain usable after expiry; trial credits expire at trial end | Credit lots distinguish paid from trial |
| D09 — PARTIAL | Annual coins/credits upfront; shared calendar cosmetics selected; award boundaries/duplicates/timezone still open | Calendar releases and once-only ownership |
| D10 — PARTIAL | Purchased coins usable everywhere; purchase/use limits not selected | No paid-source spend restriction; durable refund audit still needed |
| D11 — PARTIAL | Absorb spent coin shortfall, no debt; exact debit allocation/subscription benefit reversals open | Reversal ledger and customer support |
| D12 — PARTIAL | Retain separate Apple/Google accounts; restore/transfer and recreation still open | No account linking work; durable store ownership policy still needed |
| D13 | Store/RevenueCat accounts configured? Launch territories and testing setup? | External prerequisites and supported environments |
| D14 | Offer placements, custom Flutter vs RevenueCat paywall, admin controls | UI routes, native setup, support tooling |
| D15 | Behavior for paying members on older app builds | Price presentation and compatible monthly artwork delivery |

First interview asks D01–D05. Inventory-driven follow-up asks D06–D08 and
D10–D12. Remaining questions will use those answers to avoid asking about
benefits or billing modes the user does not select.

## 4. Verified Flutter inventory

### Coin-pack selection

US reference prices only; display platform-localized prices at checkout.

| Option | $0.99 pack | $4.99 pack | $9.99 pack |
|---|---:|---:|---:|
| A | 300 | 1,700 | 3,600 |
| B — SELECTED by user | 500 | 2,800 | 6,000 |
| C | 750 | 4,200 | 9,000 |

Ghost Pepper cost 200 coins in the recorded Aug 29 production snapshot; no
fresh live price was queried. At that price, the small packs buy respectively
one, two or three Ghost Peppers with 100, 100 or 150 coins left. These options
respond to the user's desired purchasing power, not a validated revenue model.
Value per dollar increases with pack size in all three options. B's medium and
large give approximately 11.1% and 18.9% better value per dollar than its small.

Larger quantities can reduce repeat buying and increase paid competitive
inventory. Old proposed 1,200/day and 6,000/month limits are not carried forward:
they would conflict with these options and were never user-selected.

Trial selected: seven days; permanent cosmetic/coin gifts begin at the first
successful paid charge. Three trial reroll actions expire at trial end; the
first payment grants the full paid allowance. The schema/event pipeline must
distinguish trial benefits from paid-period grants and avoid duplicate grants
on restore/recreation; separate platform accounts cannot prove one natural
person has never trialled on the other store.

Refund clarification supplied to user: example purchase 1,000 coins, spend 800,
then refund with 200 remaining. A debt policy removes 200 and applies the next
800 earned coins toward recovery before spendable balance grows. This is an
in-game adjustment, not a new cash charge. Alternative policies include removing
available coins and absorbing unrecoverable spent value, with different abuse
exposure. User selected absorbing spent shortfalls; the debt example is retained
only to explain the rejected alternative. Do not reverse recipients' race rewards
merely because the purchaser later refunds; recipient treatment must be explicit
if any such scope is ever proposed.

All paths in this section are in this frontend repository. Lines were inspected
on 2026-09-07 and are navigation anchors, not immutable implementation targets.

| Surface | Existing anchors | Planned responsibility if selected |
|---|---|---|
| Dependencies/platforms | `pubspec.yaml:29`; `ios/Podfile:2`; `android/app/src/main/AndroidManifest.xml:33`; `android/app/build.gradle.kts:56` | Add/pin tested billing SDK; verify capabilities/merged BILLING permission and prod/staging identity. Current iOS target 15, Android minSdk 28, launchMode singleTop |
| Account lifecycle | `lib/services/auth_service.dart:481`, `:564`, `:636`, `:1085`; `lib/screens/main_shell.dart:702` | Bind opaque server-issued billing ID; fence all callbacks by signed-in session; isolate demo/reviewer/test flows |
| Get Coins | `lib/screens/get_coins_screen.dart:225`; `lib/screens/tabs/home_tab.dart:1418`; `lib/screens/tabs/shop_tab.dart:1593`, `:2913` | Shared product display, store-localized price, purchase/pending/fulfillment states |
| Cosmetic and powerup checkout | `lib/screens/tabs/shop_tab.dart:1020`, `:1125`, `:1932`, `:2513`, `:2586`, `:2879`, `:2887`, `:3305` | Align effective prices, details, affordability and ad-shortfall calculation; avoid tile-only discounts |
| Shop API | `lib/services/backend_api_service.dart:5786`, `:5905`, `:6022`, `:6045`, `:6077` | Add defensive typed billing/benefit responses; preserve bootstrap fallback and legacy endpoints |
| Profile | `lib/screens/tabs/profile_tab.dart:139`, `:267`, `:453` | Membership status/manage/restore entry placement remains user decision |
| Single reveal | `lib/screens/race_detail_screen.dart:7733`; `lib/screens/case_opening_screen.dart:470` | Reroll quote/choice/result UI |
| Batch reveal | `lib/screens/race_detail_screen.dart:7198`; `lib/screens/multi_case_opening_screen.dart:81`, `:161`, `:506` | Explicit batch coverage, cost and atomic result; current max display is eight |
| Held powerups | `lib/screens/race_detail_screen.dart:4467`, `:4118` | Ordinary and Pocket Watch sheets have independent reroll controls |
| Reroll availability/execution | `lib/screens/race_detail_screen.dart:7291`, `:7307`, `:7390`, `:7476`, `:7585` | Split paid/member eligibility from ad-unit availability; preserve all agreed per-item caps |

There is no `purchases_flutter` or `in_app_purchase` dependency in the inspected
pubspec. No implemented subscription purchase surface was found in Flutter.

## 5. Proposed technical architecture (not yet a locked API)

### Membership pricing and delivery selected

One Bara+ tier with monthly AND annual billing. Monthly price is $4.99; benefits
are a 15% cosmetic/powerup shop discount, 500 monthly coins, ten monthly paid
reroll actions, a monthly cosmetic and member badge/profile customization.

Annual price is $49.99, 16.52% below twelve monthly payments totaling $59.88.
Each qualifying annual payment grants 6,000 coins and 120 paid reroll actions
upfront, exactly once. Do not also schedule currency/credit grants each month.
Monthly cosmetics remain separate calendar releases while eligible; permanent
future cosmetics are not all delivered at purchase.

Selected coin reroll price: 50 per action, including Reroll All. Prior 100-coin
candidate is superseded. Analyst reviewed local default probabilities and discard
prices (2/5/10 coins; expected new item4.91–6.65coins). Compared with discarding
original COMMON items, a five-item paid reroll loses26.75–35.45coins in expected
discard value, including the50coin fee. Even the theoretical eight-ID command
bound loses12.80–26.72coins incrementally. The maximum80coin gross outcome is
not evidence of positive expected profit. No positive-EV discard loop was found
under these defaults; verify actual production configuration and attainable
inventory before implementation. Paid/trial credits have no marginal coin debit.

For the selected monthly plan, 500 coins plus ten actions used instead of paying
50 coins each substitute for 1,000 coins of spending before discounts/cosmetic
value. At the same $4.99, the selected pack grants 2,800 unrestricted coins.
This comparison is conditional: replacing an ad saves time, not wallet coins.
Coins must be issued once per paid period; carried credits are additive, never
cleared at renewal. A 15% shop discount increases eligible buying power 17.6%.

Trial selected: discount and active member styling plus three separately
stamped trial reroll actions. Unused trial credits expire at trial end. Permanent
gifts and the full ten paid credits begin at first charge for the monthly plan.
Annual conversion grants the entire paid-year coin/credit allotment. Trial rerolls can produce lasting
powerups/discard coins despite excluding direct permanent gifts; issue once per
eligible trial, not once per login or app-account recreation.

With RevenueCat selected:

1. Apple/Google own native checkout. RevenueCat owns store verification and SDK
   finish/consume lifecycle. Do not also install a competing manual finalizer.
2. The backend owns coin balances and transaction history, benefit grants,
   allowance debits, inventory ownership and checkout discounts.
3. Membership access derives from verified provider state, persisted locally.
   A boolean entitlement is not evidence of another paid renewal reward.
4. Every charged consumable is recoverable from verified provider history even
   if the store transaction has already been completed by the SDK.
5. No balance or entitlement is granted merely because the device reports success.
6. Keep the existing wallet authoritative; RevenueCat In-App Currency migration
   is a separate decision, not implicitly included in this integration.

### Proposed backend records

Concrete proposed Prisma roster; residual policy choices affect some fields,
but not the need for durable grant/purchase uniqueness:

| New model | Principal fields and uniqueness | Purpose |
|---|---|---|
| `BillingIdentity` | Opaque unique provider customer ID; nullable unique userId; retained ownership/tombstone data | Purchase ownership survives normal account deletion without cross-provider linking |
| `BillingProductVersion` | Immutable app/store/environment/product mapping; kind; stamped coin quantity or benefit-plan version | Historical grants retain their original meaning; new pack amounts get new product IDs |
| `BillingPurchase` | Unique store/environment/transactionKey; owner; productVersion; quantity; paid/trial evidence; period; grant/refund state; actual recovered/absorbed coins | Ledger for consumables AND subscription charge transactions |
| `BillingSubscription` | Unique canonical subscription identity; owner; current paid/access period; renewal/billing state; verifiedAt | Access authority separate from per-charge benefits |
| `BillingBenefitGrant` | Unique purchaseId/benefitKind; stamped amount; applied/reversed state; wallet/credit reference | Once-only paid coin/credit rewards and separately identified trial benefits |
| `BillingCosmeticRelease` | Unique calendarMonth; shopItemId; releaseAt; immutable publication version | Shared monthly collection with archived definitions for recovery |
| `BillingCosmeticGrant` | Unique billingIdentityId/calendarMonth; qualifying verified paid period; release; pending/fulfilled state | Once-only calendar cosmetic delivery independent of annual currency grant |
| `BillingRerollCreditEntry` | Owner; grant/spend/reversal delta; linked benefitGrant or rerollOperation; paid/trial kind and trial expiry | Append-only rollover ledger; aggregate under owner lock; never clear paid credits on renewal/expiry |
| `BillingRerollOperation` | Unique owner/idempotencyKey; canonical request hash; item IDs; funding; charged cost; quote stamp; committed result | Retries return same results and never reroll/charge again |
| `BillingProviderEvent` | Unique provider/project/environment/eventId; validated recoverable data; state; retry/lease metadata | Durable authenticated inbox independent of purchase uniqueness |
| `BillingReconciliationCheckpoint` | App/environment cursor and customer check progress | Resume missed-event recovery after restart/pagination |

Use nullable user foreign keys or durable billing ownership links as appropriate;
deletion must not cascade global financial deduplication records. Exact retention
and recreation policy will be pinned after the identity interview. Reuse existing
UserShopItem ownership; do not create a competing cosmetic inventory. Calendar
release/grant models now follow the user's selected shared collection.

The prior annual `BillingBenefitPeriod` proposal is removed: paid transaction
identity is sufficient for the selected upfront coin/credit grants. Verify actual
store paid periods for both monthly and annual subscriptions. Product-change
notifications alone must never grant another bundle.

Calendar cosmetics reconcile on payment, account billing sync and a durable
scheduled scan. Missing art does not block coin/credit fulfillment: persist an
owed cosmetic entry for later delivery, preserving its original release identity.
Approved UTC boundary rule: grant current month at first paid
access and each new month with qualifying paid access, once per calendar month,
with no duplicate substitute. A mid-month annual start can therefore overlap
13 calendar releases. Alternative anniversary delivery capped at 12 is not
selected. Calendar timezone and late-event eligibility must be pinned in the
final contract. Free-trial-only access never authorizes a permanent cosmetic.

Approved plan-switch rule: both directions effective next
renewal, with no new grants until the actual next paid transaction. On Apple
use the same subscription group/service level with different durations; on
Google use the supported deferred replacement behavior. Validate configured
store timing in native sandbox; never infer charge from a metadata change.

- Wallet reversal audit records for D11; no debt columns, repayment from future
  awards, or paid-source spending buckets. A simple bounded current-balance
  refund debit avoids an every-spend provenance migration, but that precise
  allocation rule is approved, including removal of later-earned coins. Retaining only the unspent portion of a particular purchase instead
  requires lot/spend allocation; do not silently conflate those policies.

### Proposed API responsibilities

These endpoint names are proposals; **exact request/response JSON and errors
are intentionally not claimed complete until the product interview resolves**.

| Proposed route/responsibility | Contract requirements |
|---|---|
| `GET /billing/bootstrap` | Authenticated identity, immutable product mappings and authoritative membership/allowance snapshot; store supplies localized prices; no secrets |
| `POST /billing/sync` | Authenticated purchase refresh/reconciliation; client transaction IDs are lookup hints only; never accept a requested coin amount or arbitrary account ID |
| `POST /billing/webhooks/revenuecat` | Authenticate raw incoming event, reject wrong app/project/environment, persist durably before success; do not trust client-accessible webhook calls |
| Membership state read | Can be within billing bootstrap; absence/null safely renders nonmember/unavailable, never a crash |
| `POST /races/:raceId/powerups/reroll-quote` | Pin selected item IDs, funding choices, actual cost, eligibility and odds snapshot; single/batch use same shape |
| `POST /races/:raceId/powerups/reroll-purchase` | Explicit coins/member operation with quote and Idempotency-Key; execute under the same locks and reject stale quotes without debit |
| Existing shop read/checkout | Preserve old fields, add explicit effective-price/benefit explanation; actual backend debit matches displayed quote and handles entitlement expiry |
| Cosmetic claim, if chosen | Only needed if rewards are claimed rather than automatically granted; decision D09 |

The final spec must enumerate 401, malformed input, provider-not-ready,
pending purchase, duplicate purchase, ownership conflict, provider outage,
refund/revocation, insufficient funds, expired allowance, already-rerolled and
stale quote responses, with client retry behavior for each.

New billing router belongs in `src/modules/billing/` with injected provider
client, commands/models/queries and thin routes, mounted in `src/app.js`.
Existing ad-reroll endpoints retain their body/default behavior. The new paid
route shares fenced replacement logic and rerolledAt eligibility with them.
Define a common lock order before implementing single/batch/legacy concurrency.
Discount application also reaches `unlockShopItemWithAds.js:133` so cosmetic ad
shortfall matches the effective member price. Powerup upgrades remain a separate
eligibility decision; powerup shop discounts alone do not include them.

### Reliable processing

- Unique provider event IDs prevent duplicate event work; separate purchase and
  benefit uniqueness prevent different events from granting the same asset twice.
- Commit purchase record and wallet grant in one DB transaction; defer caches
  and user notifications until commit.
- Run durable inbox processing and periodic reconciliation safely across the
  existing two production PM2 workers using DB ownership/locking, not memory.
- Reconcile refunds and expirations as well as grants. Out-of-order cancellation
  must not revoke a later verified paid period. Provider failures are not proof
  that an active subscription has expired.
- Keep provider network calls outside long-held race/wallet DB locks.
- Respect API pagination/rate limits and resume reconciliation across restarts.
- Separate store sandbox/test transactions from production financial grants.
  TestFlight uses store sandbox; design its dedicated test-account routing before
  external testing. Never run integration tests against production data.

## 6. Backend inventory and required change notes

Backend paths are relative to the separate backend repository, never machine
paths. These findings are from local source inspection, not production queries.

| Domain | Existing source anchors | Required integration work |
|---|---|---|
| Identity | `prisma/schema.prisma:12`; `src/modules/users/models/user.js:65` | Current accounts are single-provider Apple OR Google. Cross-platform linking requires a separately specified auth flow if chosen |
| Deletion | `src/modules/users/commands/deleteUserAccount.js:374`, `:420` | Coin ledger and ownership delete with account; durable purchase claim uniqueness cannot rely on those rows surviving |
| Coin writers | `src/shared/economy/awardCoins.js:30`; `src/shared/economy/deductCoinsAtomic.js:51`; `prisma/schema.prisma:1177` | Preserve guarded writers; add global store/environment/transaction dedup beyond current user/reason/ref uniqueness |
| Transactions | `src/db.js:312`, `:330`; `src/modules/cosmetics/purchaseShopItem.js:176` | Use runInPrismaTransaction async scope for after-commit invalidation; raw Prisma transactions need explicit after-commit work |
| Shop reads | `src/modules/cosmetics/getShopCatalog.js:14`, `:33`, `:44`, `:94`; `src/routes/shop.js:167`; `src/modules/shop/queries/getShopBootstrap.js:44` | Personalized effective prices must be overlaid outside shared cached catalog rows |
| Cosmetic purchase | `src/modules/cosmetics/purchaseShopItem.js:58`, `:139`, `:150`, `:161` | Shared quote/debit calculation, immutable charged price and replay-safe ownership grant |
| Powerup purchase | `src/modules/powerups/commands/purchasePowerupItem.js:124` | Discount/provenance integration only as agreed; preserve existing purchase idempotency |
| Cosmetic content | `prisma/schema.prisma:1244`, `:1258`, `:1280` | Existing earnOnly, assetVersion/remoteOnly and ownership support benefit delivery; per-period grants are new |
| Reroll routes/single | `src/modules/races/routes.js:2312`, `:2349`; `src/modules/powerups/commands/rerollMysteryBox.js:154`, `:192`, `:257` | Preserve old ad-funded request meaning; add explicit consent and idempotency for paid/member modes |
| Batch reroll | `src/modules/powerups/commands/rerollMysteryBoxBatch.js:34`, `:216`, `:300` | Transactional all-or-nothing funding and replacement; code bound eight is not proof of attainable inventory |
| Discard and buy-ins | `src/modules/powerups/commands/discardPowerup.js:75`; `src/modules/powerups/services/discardRewards.js:10`, `:27`, `:111`; `src/shared/economy/buyIns.js` | If paid funds restricted, prevent laundering through rerolls/upgrades/discards; review existing concurrent discard-cap overshoot |
| Callback example | `src/modules/economy/routes/ads.js:41`; `src/modules/economy/commands/grantAdReward.js:42`; `prisma/schema.prisma:854` | Reuse structural lessons, not ad grant records as membership allowance |
| Module/jobs | `src/app.js:182`; `src/index.js:417`; `src/shared/db/jobRun.js:33` | New billing module/routes plus existing cron infrastructure and durable processing claims |

No RevenueCat, paid-purchase, subscription, paid/free wallet provenance or refund
debt implementation was found in the inspected backend. These require new code.
Authority stays in Postgres; Redis is never sufficient to authorize a benefit.

Confirmed critical difference: single reroll now uses a transaction and race
mutation fence; `src/modules/powerups/commands/rerollMysteryBoxBatch.js:216–245`
and `:300–324` consume the grant and replace items without one encompassing
transaction. Paid/member batch rerolls require an all-or-nothing operation
before attaching a charge. Do not charge independently for each mutated item.
Bodyless or legacy local-date-only reroll requests retain ad-funded meaning;
never silently debit coins or subscription credits for an old client request.
Monthly art must use existing remote-asset capability filtering where supported
and safe compatible treatment for older binaries, not unrenderable ownership.

## 7. Ordered implementation workstreams

User authorized the remaining implementation after approving the frontend.
Policy-dependent behavior waits for the outstanding answers; independent
contract, SDK and verification work proceeds under that authorization.

1. **Decisions and provider setup contract:** resolve D01–D15, confirm store IDs,
   SDK version, RevenueCat identity/restore policy, product mapping and environment.
   Store agreements, credentials and account creation remain explicit setup tasks.
2. **Tests first / additive backend schema:** write HTTP+test-DB integration tests
   for purchase fulfillment, duplication and account binding, then migrations.
   Pin API JSON before frontend implementation depends on it.
3. **Backend billing infrastructure:** provider adapter, webhook inbox, durable
   processing, purchase fulfillment, subscription reconciliation and refund policy.
4. **Backend benefit and economy integration:** period grants, shop prices,
   cosmetic delivery, reroll funding and atomic single/batch operation; refund
   audit changes as specified. No debt or paid-source spending gate. Extend all
   public-path integration tests first.
5. **Flutter billing service:** account-bound SDK lifecycle, injected interface
   for tests, platform setup and complete checkout/fulfillment/restore states.
6. **Flutter purchase and benefit screens:** shared Get Coins, membership page,
   shop pricing, profile/status and all reroll surfaces; real-widget tests first.
7. **Content/admin/support:** agreed cosmetic schedule and compatible assets;
   auditable purchase/benefit diagnostics and any approved admin operations.
8. **Verification/release preparation:** full required checks, native sandbox
   scenarios on both stores, code review, manual placement checklist and docs.
9. **Deployment:** backend first with additive compatibility, then matched iOS
   and Android builds. Production deploy requires separate in-the-moment approval.
   Staging remains off unless explicitly authorized for that use, then off again.

## 8. Test plan and acceptance criteria

Backend tests use real HTTP, real handlers and a dedicated local/test Postgres.
An external-provider boundary can use recorded/synthetic authenticated events
and controlled HTTP responses; verify actual Apple/Google purchase flows in
their sandbox separately. Never weaken existing assertions.

Required scenarios:
- Duplicate callbacks/events/sync requests across two workers grant once.
- Purchase success then app kill, server outage, timeout or delayed webhook
  recovers without requiring another charge; pending/cancelled creates no grant.
- User A purchases, logs out, user B logs in: no balance/entitlement leakage.
- Account deletion/recreation, restores and cross-store overlap follow D12.
- Refund before/after spending, duplicate reversal, older event after renewal,
  normal cancellation vs expiry and grace states follow selected policies.
- Renewals grant each benefit once, including while user is offline; trials,
  annual subperiods and resubscription tested if included.
- Reroll single/batch failure never consumes coins/allowance without all agreed
  replacements; concurrent reroll/use/upgrade/discard/end-of-race is safe.
- Every shop price, detail, confirmation and affordability path agrees with the
  actual debit; entitlement expiry during checkout returns a clear new quote.
- Old client requests/responses remain compatible and new app handles older
  backend missing fields/endpoints without breaking free gameplay.
- Demo and tutorial interactions never initiate a real purchase or production
  grant; ad-unavailable Android can still use available paid/member choices.

Frontend existing suites to extend: `test/get_coins_screen_test.dart`,
`test/shop_tab_buy_confirmation_test.dart`,
`test/shop_ad_unlock_and_type_scale_test.dart`,
`test/shop_powerup_ad_unlock_test.dart`, `test/shop_tab_store_inventory_test.dart`,
`test/shop_dressing_room_test.dart`, `test/batch_2026_08_08_box_reroll_test.dart`,
`test/batch_2026_08_10b_reroll_all_test.dart`,
`test/race_detail_stash_use_confirm_test.dart`,
`test/tutorial_rewarded_ad_isolation_test.dart`,
`test/demo_race_network_guard_test.dart`, `test/auth_service_test.dart`, and
`test/auth_service_signout_health_pref_test.dart`.

Backend existing suites to preserve/extend: `test/integration/shop.test.js`,
`test/integration/batch-0808-box-reroll.test.js`,
`test/integration/powerup-reroll-batch.test.js`,
`test/integration/redis-cache-c5-authme.test.js`, and
`test/integration/accessory-compatibility.test.js`.
Keep `test/services/coinSeamStructuralGuard.test.js` intact.

Completion requires clean `flutter analyze`, relevant tests written first and
passing, full Flutter suite/relevant backend checks, both native builds verified,
required reviews complete and manual UI checklist handed to the user. No tests
or builds are necessary to claim this draft research itself is complete; no
implementation readiness is claimed while decisions/contracts remain open.

## 9. Manual UI-placement plan

Provisional ui-test-planner checklist below is verbatim. Final placement still
depends on D14; repeat planner review once that is selected.

1. **Surface:** Real Get Coins screen\
   **Get there:** Home → coin balance “+”; repeat Shop → balance “+” and an unaffordable item → Get Coins.\
   **Verify:** Pack choices occupy the agreed section once; existing free earning cards remain reachable. Each entry opens the same arrangement.

2. **Surface:** Real shop\
   **Get there:** Home → Shop; use prepared member and nonmember accounts.\
   **Verify:** Membership entry appears once in its agreed position. Eligible item prices appear consistently in catalog tiles, dressing-room selection, and purchase sheet; no duplicate original purchase button remains. Check characters and accessories, plus powerups if included.

3. **Surface:** Shop tutorial\
   **Get there:** Profile → Settings → View Shop Tutorial; also inspect the first shop visit on an eligible fresh account.\
   **Verify:** The real shop’s added membership section does not obscure tutorial targets. Each spotlight still surrounds its intended control. New controls are neither duplicated nor accidentally hidden by the overlay.

4. **Surface:** Profile and membership page\
   **Get there:** Profile tab → agreed membership entry; repeat Home → profile shortcut.\
   **Verify:** Entry appears once in both profile presentations. Membership page contains the agreed offer/member sections and purchase/manage/restore controls in their approved positions, without overlapping navigation.

5. **Surface:** Single and batch box reveals\
   **Get there:** Active race → open one mystery box; separately open several with Open All.\
   **Verify:** Reroll choices appear in the agreed reveal-action area. The former ad-only control is not left alongside a duplicate replacement. Batch layout remains usable with several revealed rewards.

6. **Surface:** Held-item sheets, including Pocket Watch\
   **Get there:** Active race → stash → eligible held box reward; repeat with an eligible held Pocket Watch using prepared account state.\
   **Verify:** Each sheet places the new reroll entry beside the intended actions exactly once. Check Pocket Watch separately: its reroll button is rendered outside the shared sheet widget.

7. **Surface:** Tab tutorial and demo race\
   **Get there:** Profile → Settings → View Tutorial for Home, Profile, and race-detail previews; fresh-account onboarding → demo race → box reveal.\
   **Verify:** New elements follow the explicitly chosen tutorial visibility policy. Home’s Get Coins route and Profile’s membership entry show the intended preview arrangement if reachable. Race-detail and box preview actions have no unintended purchase controls. Existing spotlights remain aligned.

Run these checkpoints on both iOS and Android, including a small-screen device.

Planner risks: `lib/tutorial/tutorial_preview_data.dart` contains explicit offline
Get Coins state; Profile is reused without an explicit preview parameter; Shop
has its own live-screen tutorial. Four separate reroll controls and several
price/affordability assemblies need coordinated changes. Current ad-unit-based
visibility must not hide independently available paid/member actions.

## 10. Sources and revision log

Provider references checked 2026-09-07:
- https://www.revenuecat.com/docs/getting-started/installation/flutter
- https://www.revenuecat.com/docs/platform-resources/non-subscriptions
- https://www.revenuecat.com/docs/integrations/webhooks
- https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields
- https://www.revenuecat.com/docs/api-v2/purchase
- https://www.revenuecat.com/docs/customers/identifying-customers
- https://www.revenuecat.com/docs/projects/restore-behavior
- https://www.revenuecat.com/docs/subscription-guidance/subscription-offers
- https://www.revenuecat.com/docs/integrations/webhooks/event-flows
- https://developer.apple.com/app-store/subscriptions/
- https://www.revenuecat.com/docs/subscription-guidance/managing-subscriptions

Pass 1: separated user decisions from prior recommendations; marked superseded
direct-store finalization/flags; mapped actual frontend entry points and missing SDK.
Pass 2: identified batch atomicity, sandbox isolation, duplicate identities,
renewal-grant uniqueness, quote expiry and tests for older clients. Exact API,
migrations and benefit policies remain intentionally unfinished pending interview.
Final architect/economy/UI reviews and approval gate remain pending scope answers.
Inventory review added the missing account-linking decision, global transaction
claim retention through deletion, shared-catalog cache isolation, explicit legacy
ad funding, existing remote-content capability paths, and provenance laundering
through discard rewards. Preliminary economy verdict is sound with changes;
the product policies and numerical model still require user decisions.
Interview update: RevenueCat selected, separate accounts retained, purchased
coins unrestricted in existing spend paths, trial included, rerolls priced per
action. Replaced old pack assumptions with three unselected analyst-reviewed
alternatives. Explained refund shortfalls and clarified ambiguous benefits and
reroll-cap answers. No implementation changes made.
Second interview update: option B selected; all membership benefits confirmed;
one-reroll cap and monthly credit rollover confirmed; trial seven days and
permanent gifts only after first charge; spent refund shortfalls absorbed with
no debt. Further questions ask monthly/annual billing, post-expiry credit use,
and trial allowance. Membership pricing options are being developed for selection.
Added three unselected membership bundles and a candidate 100-coin reroll price
after economy review, plus concrete additive Prisma model/route proposals.
No checkout cap, debt, paid-source restriction or refund penalty was added.
Third interview update: selected $4.99/month bundle (15%,500coins,10actions),
overrode reroll coin cost to50, requires annual billing too, preserves paid
credit use after membership expiry, selected three-credit trial with expiry
and full paid-period grants after charge. Added explicit paid/trial credit lots
and a proposed annual benefit-period scheduler; annual price/cadence and cosmetic
schedule remain questions, not assumed answers.
50coin analysis update: exact local-default discard EV review found no positive
incremental expected-profit reroll/discard loop; distinguish original item value
from gross proceeds. Keep the user's50coin price. Annual49.99 with monthly grants
is now an analyst recommendation only, pending the user's annual selection.
Fourth interview update: annual $49.99 selected; all 6,000 coins/120 credits
upfront selected; shared calendar cosmetics selected. Supersedes prior monthly
annual-delivery recommendation and `BillingBenefitPeriod` scheduler. Added
calendar release/grant records, once-per-payment annual currency grants and
pending boundary/refund/plan-switch questions. No implementation code changed.
