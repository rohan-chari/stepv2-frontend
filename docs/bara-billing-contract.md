# Bara billing v1 — implementation contract

User authorized completing real billing on 2026-09-07 after approving the visual
preview. Existing navigation stays unchanged. This document supplements and
supersedes the draft technical proposals in bara-plus-billing-requirements.md.
The user answered “yes to all” remaining owner-policy questions on 2026-09-07.
The rules below are approved implementation requirements.

## Catalog and prices (original monthly/annual implementation; permanent revision below supersedes sale catalog)

| Kind | Apple product ID | Google product/base plan | Grant |
|---|---|---|---|
| Coins | bara_coins_500_v1 | bara_coins_500_v1 | 500 coins |
| Coins | bara_coins_2800_v1 | bara_coins_2800_v1 | 2,800 coins |
| Coins | bara_coins_6000_v1 | bara_coins_6000_v1 | 6,000 coins |
| Monthly | bara_plus_monthly_v1 | bara_plus_v1:monthly | 500 coins + 10 credits per paid transaction |
| Annual | bara_plus_annual_v1 | bara_plus_v1:annual | 6,000 coins + 120 credits per paid transaction |

Reference US prices: $0.99/$4.99/$9.99; membership $4.99/month and $49.99/year.
Both plans share RevenueCat entitlement `bara_plus`. Native localized store
prices and actual eligible introductory offers drive checkout presentation.
Trial: seven days and three expiring credits; paid permanent grants start after
charge. Paid credits survive normal membership expiry. Current member discount
is 15%; integer price = base - floor(base * 15 / 100). Free items stay free.

Mappings also bind the configured RevenueCat project/app, verified store,
environment and immutable grant version. API product IDs from RevenueCat must
be resolved to the allowed app/store identifier; never trust a client's product
quantity or a webhook alias as a new owner. No web checkout or direct cash
reroll SKU: rerolls use purchased/earned coins, credits, or existing ads.

## Locked API — backend owner, 2026-09-07

All user routes require existing auth. A billing identity is a server-generated
UUIDv4, permanently bound to an account/environment; it survives deletion as a
tombstone. Client hints cannot select an account, environment or financial grant.
Missing billing credentials is a setup dependency, not a new release flag.

GET `/billing/bootstrap` (or initial authenticated session bootstrap):

```json
{
  "available": true,
  "contract": "bara-billing-v1",
  "identity": {"appUserId": "uuid-v4", "environment": "production"},
  "products": [
    {"id": "coins_500", "storeProductId": "bara_coins_500_v1", "kind": "coins", "coins": 500, "plan": null},
    {"id": "plus_monthly", "storeProductId": "bara_plus_monthly_v1", "kind": "subscription", "coins": 500, "plan": "monthly"}
  ],
  "membership": {"status": "free", "plan": null, "accessUntil": null, "renews": false, "discountPercent": 0},
  "credits": {"paid": 0, "trial": 0, "trialExpiresAt": null},
  "coins": 350,
  "reroll": {"supported": true, "coinCost": 50, "maxItems": 8},
  "cosmetic": null,
  "managementUrl": null
}
```

The products array contains all configured platform products (example abbreviated).
Platform is an explicit non-authoritative request parameter or existing client
platform metadata; backend owner pins it. Status is free/trial/active/expired;
accessUntil/trialExpiresAt are ISO8601 UTC strings. Optional cosmetic describes
an actual published/owed release using existing compatible asset metadata.
Unavailable response: `{"available":false,"contract":"bara-billing-v1"}`.
Missing/null fields and older-backend 404 degrade to existing free gameplay;
do not invent live prices, grants, eligibility or memberships in Flutter.

POST `/billing/sync`, optional body `{"transactionId":"store-id-hint"}`:
verified provider reconciliation only. `200 {"status":"complete", ...bootstrap}`
or `202 {"status":"pending","retryAfterMs":2000, ...bootstrap}`. A hint is
not evidence of ownership/payment and never authorizes another grant. Return
pending when the hinted purchase is not yet durably reconciled; stop presenting
checkout as successful until fulfillment is known. Reopening/resume retries it.

POST `/races/:raceId/powerups/reroll-purchase`, header `Idempotency-Key: UUID`:

```json
{"powerupIds":["item-id"],"funding":"coins","expectedCoinCost":50}
```

`funding` is coins or credits; 1–8 distinct IDs, canonical sorted fingerprint.
Response:

```json
{"results":[{"powerupId":"item-id","type":"PROTEIN_SHAKE","rarity":"COMMON","rerolledAt":"2026-09-07T12:00:00Z"}],"charged":{"coins":50,"paidCredits":0,"trialCredits":0},"coins":300,"credits":{"paid":0,"trial":0,"trialExpiresAt":null}}
```

Result rows retain all existing reveal/provenance fields; the example is
abbreviated. One action costs 50 coins OR one credit for the entire submitted
batch. Eligible expiring trial credits are consumed before FIFO paid lots.
Validate every item under locks, then debit/replace/persist replay result in
one transaction. No partial paid batch. Same key/payload replays the exact
stored response even if the race later ends; same key/different payload is409.
Do not resubmit a timed-out operation using a new key.

Errors use existing `{error,code}` shape: 400 invalid body/key; 401 unauthorized;
404 missing race/item; 409 PRICE_CHANGED, IDEMPOTENCY_CONFLICT, ALREADY_REROLLED,
INSUFFICIENT_COINS, INSUFFICIENT_CREDITS, or RACE_NOT_ACTIVE; 503 provider/setup
unavailable when applicable. Backend owner pins exact codes in route tests.
A conflict has no charge or replacement. Existing ad routes retain their exact
meaning and continue to use SSV; no absent funding field can mean paid consent.

Shop API keeps legacy `priceCoins` as actual effective price and adds
`basePriceCoins` and `discountPercent`. The same Postgres membership-price
function applies to cosmetic/powerup catalog, bootstrap, purchase and ad-shortfall
paths. Personalized pricing overlays the shared base catalog cache. Checkout
accepts optional `expectedPriceCoins`; mismatch409 returns current price before
any debit. Old clients that omit it retain their existing supported checkout.
New clients show current/previous prices consistently at every confirmation.

## Durable backend state and processing

Use additive models for billing identity, purchase, subscription, benefit grant,
credit lots/entries, provider inbox, reconciliation work, cosmetic releases and
grants, and paid reroll operations. Backend owner owns final Prisma names and
indexes. Purchase uniqueness binds provider project/app/store/environment and
canonical transaction, independently of event IDs. Retain global financial
ownership through account deletion; no user-cascade deletes deduplication.

Authenticate and size-limit provider webhooks, persist an inbox row before200,
then reconcile using server credentials outside database locks. DB leases and
indexed next-attempt timestamps let the existing two workers recover abandoned
work safely. Do not store billing authority in Redis or add runtime flags.
Use current transaction/after-commit cache invalidation wrappers and guarded
awardCoins/deductCoinsAtomic writers.

Recover paginated RevenueCat customer purchases/subscriptions and each
subscription's transactions. Entitlement access alone never proves a paid grant.
Separate temporary/unverified access from verified charge and trial issuance.
Do not infer refund from expiry or a missing provider response. Authenticated
explicit refunds enter the same idempotent reversal path. Include a Transactions
export import backstop using transaction/refunded_at/updated_at provenance to
recover older missed refunds; document its scheduled/operator setup clearly.
Out-of-order stale snapshots/events must not revoke a newer paid period or
reissue previously reversed gifts. Refund reversal restores only amounts
actually recovered/revoked, never the absorbed spent portion again.

Race mutation lock order remains canonical race -> participant -> powerup rows,
then wallet/credit resources, with stable ordering and existing mutation fences.
Paid batch must reuse the established odds and compatibility rules; don't copy
a divergent reward table. Provider calls never occur while holding these locks.

Approved owner policies: UTC calendar grants at first paid access and each
calendar month of paid access (possibly 13 releases across an annual period),
with no owned-cosmetic substitute. Refunds debit the current coin balance,
including earned coins, up to the refunded grant; remove only unused credits
attributable to that purchase. Absorb spent shortfalls without debt and retain
cosmetics. Access follows verified store state. Purchases stay with the original
Bara account even after deletion; no automatic ownership transfer. Monthly/yearly
changes take effect at renewal, with benefits only after actual payment.
Sandbox/reviewer accounts have a permanent isolated economic realm.
Normal accounts must never receive spendable sandbox grants. Existing reviewer
visibility filtering is insufficient; competition/invitation admission must
reject mixed sandbox/ordinary economic participation before sandbox grants ship.

## Frontend implementation

Preserve approved screens and current app navigation. Replace preview-only
controller injection in the normal entrypoint with an account-bound RevenueCat
adapter. Keep the standalone offline preview untouched as a separate entrypoint.
Scope above Navigator. Serialize SDK configure/login identity changes, require
signed-in server identity before checkout, and fence every async completion by
session/identity. Purchase/restore/native management always refresh server state.
Do not grant coins in Flutter. RevenueCat owns native finish/consume lifecycle.

Add localized membership offer data and native intro eligibility; show trial
CTA only when supported/eligible, otherwise ordinary subscribe. Add Terms and
Privacy links and proper recurring-price/trial disclosure. Management opens the
store subscription screen; don't claim cancellation occurred merely on return.
Signed-out or unconfigured store/backend states leave existing gameplay working.
Paid reroll support is independently available from ad support on both platforms.

## Verification and rollout

Tests first: real HTTP and dedicated local *_test Postgres, no production writes;
real Flutter screens with injected provider boundary. Cover duplicate two-worker
fulfillment, killed-client recovery, missed renewals/refunds, account changes and
deletion, trial/paid transition, annual upfront grants, rollover, mixed realm
rejection, cached/noncached old-client prices, stale quotes, atomic single/batch
rerolls and durable replay after race end. Preserve existing assertions.

Backend deployment requires separate explicit production approval per backend
AGENTS.md; current task authorizes code and verification only. Staging stays off
until explicitly authorized. Build iOS+Android in lockstep. External console
credentials/products, scheduled cosmetic publication, sandbox store tests and
first product review submission are documented in bara-billing-store-setup.md.

## Revision passes and review

Pass1: adopted architect's recovery, price-overlay, paid-batch atomicity and
native-price/eligibility requirements. Pass2: made refund reversal provenance,
test-account contamination, session fencing and deferred fulfillment explicit.
Architect/economy reviews require these guards before completion; final policy
answers and backend-owned JSON/schema lock must be recorded before dependent
business logic. UI placements remain the approved preview's real-screen additions;
the normal app navigation is not replaced by the preview navigation.

## Backend interface lock

The endpoint shapes above are locked with these concrete details. Policy answers
may change eligibility internals but not these request or response shapes.

- `GET /billing/bootstrap?platform=ios|android` and
  `POST /billing/sync?platform=ios|android`. Platform is optional; omitted platform
  is inferred from the authenticated account's Apple/Google provider. An explicit
  invalid platform is `400 INVALID_PLATFORM`. It only selects catalog display.
- Available bootstrap always contains all five platform products, `membership`,
  `credits`, `coins`, `reroll`, `cosmetic` (nullable), `managementUrl` (nullable),
  `identity`, `contract`, and `available`. Product `id` values are `coins_500`,
  `coins_2800`, `coins_6000`, `plus_monthly`, `plus_annual`. Coin products have
  `plan:null`; subscriptions have `monthly`/`annual`. Android subscriptions use
  `storeProductId:"bara_plus_v1:monthly"` / `"bara_plus_v1:annual"`.
- `identity.environment` is `production` or `sandbox`; it is derived solely from
  durable server account classification. Never pass it to bootstrap or sync.
- Coin pack objects contain only their configured quantity; subscription `coins`
  is the confirmed paid-period benefit. No prices or trial-eligibility assertions
  come from this API. Store SDK data is required for checkout.
- `POST /billing/sync` body is optional. `transactionId`, when present, must be a
  nonempty string of at most 256 characters. Unknown fields never grant value.
  `200 status:complete` means the complete provider read is durably reconciled
  and the optional transaction hint is fulfilled or explicitly reversed.
  Unknown hints return `202 status:pending,retryAfterMs:2000`. An unavailable
  provider/setup returns `503 BILLING_UNAVAILABLE`; ownership conflicts return
  `409 PURCHASE_ACCOUNT_MISMATCH`; environment mismatch is `409 BILLING_REALM_MISMATCH`.
- Missing billing credentials: bootstrap returns the documented `available:false`
  envelope with status200; sync503. Paid reroll still works without store setup;
  normal races need no membership for coin funding.
- Paid reroll key must be UUIDv4. Missing/malformed key is `400 INVALID_IDEMPOTENCY_KEY`.
  Empty/duplicate/non-string/over-eight IDs, unknown funding, or a noninteger
  expectedCoinCost are `400 INVALID_REROLL_REQUEST`. For coins,
  `expectedCoinCost` is required. For credits it may be absent and is ignored.
  Unknown/not-owned race or item is `404 NOT_FOUND`; valid-owned ineligible item
  is `409 NOT_HELD`; already rerolled is `409 ALREADY_REROLLED`; inactive race is
  `409 RACE_NOT_ACTIVE`. All remaining conflicts are exactly those listed above.
  `PRICE_CHANGED` includes `coinCost:50`. The full result row includes
  `powerupId,type,rarity,rerolled:true,rerolledAt,configVersion`.
- Cosmetic/powerup checkout `expectedPriceCoins` is optional for old clients.
  Invalid quote is400; stale quote is `409 PRICE_CHANGED` with `priceCoins`,
  `basePriceCoins`, `discountPercent`. Legacy free-user catalog entries may omit
  the additive price fields to preserve strict existing response assertions;
  discounted entries include them and all clients pay the same effective price.
- Provider webhook: `POST /billing/webhook/revenuecat`, authenticated by a
  configured exact Bearer credential using a constant-time comparison;32KiB
  JSON bound. Accepted/duplicate inbox is `200 {"received":true}`. Unsupported
  events are durably recorded and do not grant. Invalid auth401, malformed event400.
- Dependency seams: `createBillingRouter({prisma,billingProvider,billingConfig,
  requireAuth})`, provider method `getCustomerHistory(identity)` returns verified
  provider records; production adapter owns pagination, app/product resolution,
  timeouts and schema validation. Tests may inject the provider boundary only;
  handlers, transactions, coin ledger and database remain real.
- Additive database models: `BillingIdentity`, `BillingPurchase`,
  `BillingSubscription`, `BillingCreditLot`, `BillingCreditEntry`, `BillingInbox`,
  `BillingReconciliation`, `BillingCosmeticRelease`, `BillingCosmeticGrant`,
  `BillingRerollOperation`. `BillingPurchase` is the immutable paid benefit receipt;
  it keeps granted/recovered/absorbed quantities and refund provenance. Identity
  ownership is retained without a cascading User foreign key. Credit lots and
  grants bind to the retained identity, not a deletable alias.

Local verification database confirmed by `SELECT current_database()`:
`steps-tracker-integration_test` on localhost. No production database was read
or changed. Existing untracked backend artifact is unrelated and preserved.

### Configuration and legal URLs (locked addition)

Backend secret configuration names: `REVENUECAT_SECRET_API_KEY` (v2 scoped secret),
`REVENUECAT_PROJECT_ID`, `REVENUECAT_IOS_APP_ID`, `REVENUECAT_ANDROID_APP_ID`,
`REVENUECAT_WEBHOOK_AUTHORIZATION` (complete exact `Bearer ...` header value),
`BILLING_TERMS_URL`, `BILLING_PRIVACY_URL` (absolute HTTPS published legal pages).
These are credentials/identifiers/dependencies, not release controls. No secrets
are returned to clients. Available bootstrap additionally always includes
`termsUrl` and `privacyUrl`. Missing/invalid required config yields unavailable.
Flutter public build settings are `REVENUECAT_IOS_API_KEY` and
`REVENUECAT_ANDROID_API_KEY`; neither is the backend secret API key.

Unavailable bootstrap implementation returns the minimal envelope plus the
account-bound `identity`, current `membership`, `coins`, `credits`, and `reroll`
capability; `products:[]`, `cosmetic:null`, `managementUrl:null`, legal URLs nullable.
Thus `available` controls store checkout only. `reroll.supported:true` is explicit
and independent of store configuration. Clients must read this capability rather
than infer paid reroll availability from `available`.

`cosmetic`, when an actual published compatible release has been granted, is
`{month:"YYYY-MM",item:<existing serializeShopItem JSON>,owned:true,grantedAt:<ISO8601 UTC>}`.
The item keeps existing id/sku/name/description/slot/priceCoins/assetKey/renderMetadata/
bobble and supported existing assetVersion/assetUrl metadata. Without a real grant
(or for an unsupported hidden/remote-only item), `cosmetic:null`; the live paywall
omits sample artwork. No sample wizard hat is advertised as a published release.

## Pending native payments — locked recovery clarification

Ask-to-Buy and other native pending purchases may initially have no transaction
ID. The API remains unchanged: there is no `pendingPurchase` request field and
no matching against a client-provided product timestamp.

Before native checkout, the app obtains and durably persists the account-bound,
product-specific set of known native store transaction IDs. If that baseline
cannot be obtained/persisted, checkout must not start. After an ID-less pending
result, refresh invalidated RevenueCat CustomerInfo. Only a newly observed,
matching product's actual store transaction ID can become the existing
`POST /billing/sync {transactionId}` hint. Subscription IDs come from native
subscription information; consumable IDs come from non-subscription transactions.
A session/identity change fences every callback and the saved intent.

The server still independently verifies and reconciles the entire provider
history. A hinted ID returns `200 status:complete` only when that exact canonical
store transaction, bound to the authenticated billing identity and configured
project/app/store/environment, has a durable fulfilled or explicitly reversed
receipt. Merely discovering the transaction, fetching entitlements, accepting a
webhook, or finishing an empty reconciliation is insufficient. Otherwise return
`202 status:pending` even if the provider read succeeded. Neither the baseline
nor the transaction hint authorizes any grant. A pending action with no resolvable
new native transaction ID remains pending; ordinary no-hint sync success cannot
clear it. Ambiguous product/transaction matching must not select an unrelated
prior purchase or use device-clock tolerance to establish completion.

## Implementation status — 2026-09-07

Backend implementation now includes verified coin/subscription fulfillment,
trial and paid credit lots, bounded refunds and refund reversals, immutable
account ownership, durable database leases and reconciliation retries, paginated
RevenueCat history, refund export recovery, UTC cosmetic publication/grants,
permanent sandbox economic isolation and dedicated-account provisioning.
Reroll charges are atomic and idempotent; legacy public routes, ad rerolls,
bodyless shop purchases and frozen-client prices remain compatible. Purchase
hints and SDK snapshots never authorize value by themselves.

Nine additive migrations have been applied only to confirmed localhost
`steps-tracker-integration_test`: billing v1, nullable periods, billing realm,
fulfillment state, realm admission backstop, realm lock order, reconciliation
provenance, cross-realm friendship admission, and advisory realm admission locks. No production/staging deployment was performed.

Verification: full backend unit suite passed **3,360/3,360**. Final financial,
realm and legacy-shop acceptance passed **66/66**, followed by one additional
converted-zero-price acknowledgement regression passing **1/1**. These include
real reconciliation-CLI recovery without client sync/webhook, late expired
receipt acknowledgement without invented trial benefits, and lease/realm races.
The actual complete integration run (quoted recursive glob including legacy root
files) ran **2,912 tests**: **2,882 passed, 29 failed, one existing test skipped**.
The previously unquoted npm script omitted root suites; its glob is corrected.
A new realm lock interaction that caused a legacy tournament deadlock is fixed
and regression-tested. An isolated baseline reproduced **27 of the original failures**, including the
intermittent UPRISING case; that full file subsequently passed 10/10 on the final
source. The catalog failure also passed its focused rerun. All original failures
are attributed: 27 baseline failures, the fixed realm deadlock, and the catalog
case that passed on rerun. No assertion was weakened. Billing-specific acceptance
is complete, while the repository-wide suite still has those existing failures;
this is not a claim that the full suite is green.

Frontend: full Flutter suite passed 3,039 tests before the additive grace update;
final grace/components/adapter tests passed 35/35, analysis is clean, and the final
source builds for iOS simulator debug and Android prod debug. The static web build
passed (four pages, 15 assets), with three real HTTP legal-page checks. Final UI
placement checks are recorded in the checklist below.

The native pending-payment baseline protocol above changes the frontend recovery
procedure only; no clock-based fulfillment or extra pending-intent endpoint was
added. Frontend verification is tracked by its implementation agent. Store setup
and operator commands are documented in `docs/bara-billing-store-setup.md`; manual
app placement checks are in `docs/bara-billing-ui-checklist.md`. Native sandbox
checkout and release signing require the configured store accounts and devices;
local fixtures/builds do not substitute for those checks.

### Verified grace access (additive contract)

`membership.givesAccess` is an explicit boolean computed by the backend. True
means the current verified membership grants access; false means it does not.
A verified grace period or verified unknown-but-access-granting provider state
can have `status:"active"` with a past/null ordinary `accessUntil`; do not invent
an expiry date or let that ordinary date override explicit `givesAccess:true`.
`status:"trial"` is reserved for an actual verified trial. Missing/malformed
`givesAccess` in older backend responses retains the client's prior defensive
status/date fallback. Grace grants no new paid coins, credits or cosmetic period.
Refunded financial gifts do not independently cancel still-verified access.

### Late zero-price transaction acknowledgement

An initial verified zero-price subscription transaction first recovered after its
interval ended can be acknowledged with zero grants when the subscription is
verified expired or has a later verified paid renewal. This does not assert a
historical trial period or create trial credits. Incomplete/pending payments stay
unresolved. This terminal receipt satisfies exact-hint sync completion; paid
renewal benefits still require the separate verified charge.

## Permanent premium — locked additive contract, 2026-09-07

This section supersedes annual **sales**, not annual receipt recognition. The
original billing UI has not shipped. Shipped pre-billing clients retain their
existing routes and prices; no flags, synthetic expiry or fabricated monthly
plan are introduced. The new decoder/screen must explicitly handle permanent
and unknown plans without describing an unknown plan as a monthly subscription.
New clients suppress annual sales even when an older backend returns that SKU.

Routes, request parameters, errors, identity binding and `contract:"bara-billing-v1"`
remain unchanged. Permanent native transaction hints complete as soon as verified
activation is durable, including when its first currency reward is delayed.

Available sale catalog has the three coin packs, monthly and permanent. Every
product now includes additive `credits`. Permanent is exactly:
`{"id":"plus_permanent","kind":"non_consumable","plan":"permanent","coins":500,"credits":10,"storeProductId":"bara_plus_permanent_v1"}`
on both stores. These quantities describe each scheduled monthly bundle, never
a direct receipt grant. Historical annual remains in the internal recognition
map only. With active permanent access, `products` contains only coin packs:
repeat permanent and new subscription checkout are unavailable. Native stores
still control any independently continuing subscription; every actual subsequent
monthly/annual payment retains its historical bundle.

Every membership includes additive `nextRewardAt` (UTC ISO string or null) and
`subscription` (null or `{givesAccess,status,plan,accessUntil,renews}`). Nested
subscription also retains separately resumable monthly/annual/trial sources in
provider states active, trialing, in_grace_period, in_billing_retry, paused, unknown
or incomplete, even without current access or a provider management URL. Its
status is trial/active when it grants access and expired when suspended, its plan
is monthly/annual, and additive providerStatus preserves the provider state.
Use nested presence for cancellation guidance and native management fallback;
do not require givesAccess or managementUrl to show that separate obligation. Permanent overrides only the effective membership:
`givesAccess:true,status:"active",plan:"permanent",accessUntil:null,renews:false`.
Top-level managementUrl is retained from that separate subscription. A refunded
permanent source with no other valid permanent receipt falls back to the actual
subscription; without either access source it is expired with plan permanent.
`nextRewardAt` is null without permanent access; overdue timestamps mean durable
catch-up remains due, not a new store charge. Existing wallet/credit/cosmetic/legal
and reroll fields keep their meanings. Missing new fields default to null.

### Provider authority and durable state

RevenueCat v2 purchases must have original/current customer equal to the opaque
identity, ownership purchased, configured project/app/store/environment, exact
SKU, nonempty native transaction ID, finite timestamp and strict quantity one
for permanent. Only explicit `status:"owned"` with positive verified gross
payment activates a permanent receipt. `status:"refunded"` is verified revocation;
unknown, pending, absent or null status never activates or issues value. Missing
history is not refund evidence. New permanent rewards and cosmetic grants require
current explicit owned/positive-payment proof for their source. Contradictory
refunded history after an explicit reversal retains known access but defers new
rewards until owned proof is available. Missing source verification preserves
the original due boundary and retries after 60 seconds, without a hot loop. Null/missing malformed provider fields fail503;
recognized-but-unpaid/pending receipts remain pending202. Aggregate bara_plus
entitlements cannot prove which product supplies permanent ownership. Permanent
gross payment evidence must be a finite nonnegative JSON number; missing/null,
strings, negative and nonfinite values are malformed503, not payment. Coins
never supply access. Timestamped authenticated refund/reversal/export evidence
uses existing canonical receipt ownership and event ordering; ordinary stale
owned history cannot reverse a known refund. An explicit newer refund reversal
restores that source's original eligibility interval.

Add tables `BillingPermanentSchedule` (one retained identity, version1, immutable
anchor, nextPeriod cursor, indexed nextDueAt), `BillingPermanentSource` (one
canonical purchase, immutable purchasedAt, current revokedAt, latest observation),
`BillingPermanentGrant` (unique identity/version/period, immutable source receipt,
boundary and benefit counts, recovered/absorbed/revoked quantities), and
`BillingPermanentRevocation` (source, unique operation key, effective revocation,
observed timestamp, nullable reversal observation). Financial records survive
account deletion under the existing identity tombstone. Test cleanup and sandbox
virgin-history guards include these tables. No user FK may cascade the schedule.

The permanent receipt grants zero direct coins/credits and is fulfilled once
activation and schedule are durable. The earliest verified permanent purchase
creates one schedule. Its anchor is that purchase time, except active verified
paid subscription coverage at that time delays it to the greatest qualifying
paid coverage end (including legacy annual). Trial coverage never delays it. The first verified permanent payment ends
remaining trial-only reroll credits once; its paid credits remain usable.
Later receipts/renewals/reversals never move that anchor. Each boundary is computed
from the original UTC day/time with end-of-month clamping, not the last boundary.
Select the earliest eligible source by purchasedAt then canonical key for each
unissued period; source attribution never changes on issued grants.

A currently revoked source cannot fund any newly issued currency or cosmetic,
even for a boundary before revocation. Already owned cosmetics remain.
Refund revokes a source prospectively from its effective refund time and recovers
its already-issued attributable grants using bounded current-wallet recovery and
unused attributable credit lots. Other valid sources preserve access and fund
eligible unissued periods; they do not relabel or restore earlier grants. Refund
reversal closes that revocation retrospectively, restores only actually recovered
coins/revoked credits, and revisits owed unissued periods from the original anchor.
Repurchase supplies eligibility from its own purchase time; it never backfills a
refunded gap or resets an anniversary. Cosmetics use purchase-to-revocation source
intervals independently of the currency anchor and retain the existing one/month
outcome and keep-owned-on-refund policy.

At most 12 period boundaries are processed per identity transaction. Grant,
ledger, paid credit lot, cursor and requeue state commit atomically behind the
existing PostgreSQL lease and wallet locks. Existing requestedVersion fencing
preserves wakeups. Due time is the minimum of provider retry/refresh and reward
boundary; interrupted catch-up requeues immediately. Provider outage retains
known access but issues no new rewards until successful verification. An ended
revoked gap may advance the cursor without a grant; reversal rewinds only the
scan cursor, while unique grant rows prevent duplicate value.

### Complete bootstrap fixtures (Apple, available configuration)

Permanent only

```json
{
  "available": true,
  "contract": "bara-billing-v1",
  "identity": {
    "appUserId": "11111111-1111-4111-8111-111111111111",
    "environment": "production"
  },
  "products": [
    {
      "id": "coins_500",
      "kind": "coins",
      "coins": 500,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_500_v1"
    },
    {
      "id": "coins_2800",
      "kind": "coins",
      "coins": 2800,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_2800_v1"
    },
    {
      "id": "coins_6000",
      "kind": "coins",
      "coins": 6000,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_6000_v1"
    }
  ],
  "membership": {
    "givesAccess": true,
    "status": "active",
    "plan": "permanent",
    "accessUntil": null,
    "renews": false,
    "discountPercent": 15,
    "nextRewardAt": "2026-10-07T18:00:00.000Z",
    "subscription": null
  },
  "credits": {
    "paid": 10,
    "trial": 0,
    "trialExpiresAt": null
  },
  "coins": 500,
  "reroll": {
    "supported": true,
    "coinCost": 50,
    "maxItems": 8
  },
  "cosmetic": null,
  "managementUrl": null,
  "termsUrl": "https://steptracker-api.org/billing-terms.html",
  "privacyUrl": "https://steptracker-api.org/privacy.html"
}
```

Permanent plus separately renewing monthly; first permanent bundle deferred

```json
{
  "available": true,
  "contract": "bara-billing-v1",
  "identity": {
    "appUserId": "11111111-1111-4111-8111-111111111111",
    "environment": "production"
  },
  "products": [
    {
      "id": "coins_500",
      "kind": "coins",
      "coins": 500,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_500_v1"
    },
    {
      "id": "coins_2800",
      "kind": "coins",
      "coins": 2800,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_2800_v1"
    },
    {
      "id": "coins_6000",
      "kind": "coins",
      "coins": 6000,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_6000_v1"
    }
  ],
  "membership": {
    "givesAccess": true,
    "status": "active",
    "plan": "permanent",
    "accessUntil": null,
    "renews": false,
    "discountPercent": 15,
    "nextRewardAt": "2026-09-20T18:00:00.000Z",
    "subscription": {
      "givesAccess": true,
      "status": "active",
      "plan": "monthly",
      "accessUntil": "2026-09-20T18:00:00.000Z",
      "renews": true,
      "providerStatus": "active"
    }
  },
  "credits": {
    "paid": 10,
    "trial": 0,
    "trialExpiresAt": null
  },
  "coins": 500,
  "reroll": {
    "supported": true,
    "coinCost": 50,
    "maxItems": 8
  },
  "cosmetic": null,
  "managementUrl": "https://apps.apple.com/account/subscriptions",
  "termsUrl": "https://steptracker-api.org/billing-terms.html",
  "privacyUrl": "https://steptracker-api.org/privacy.html"
}
```

Refunded permanent, monthly still active

```json
{
  "available": true,
  "contract": "bara-billing-v1",
  "identity": {
    "appUserId": "11111111-1111-4111-8111-111111111111",
    "environment": "production"
  },
  "products": [
    {
      "id": "coins_500",
      "kind": "coins",
      "coins": 500,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_500_v1"
    },
    {
      "id": "coins_2800",
      "kind": "coins",
      "coins": 2800,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_2800_v1"
    },
    {
      "id": "coins_6000",
      "kind": "coins",
      "coins": 6000,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_6000_v1"
    },
    {
      "id": "plus_monthly",
      "kind": "subscription",
      "coins": 500,
      "credits": 10,
      "plan": "monthly",
      "storeProductId": "bara_plus_monthly_v1"
    },
    {
      "id": "plus_permanent",
      "kind": "non_consumable",
      "coins": 500,
      "credits": 10,
      "plan": "permanent",
      "storeProductId": "bara_plus_permanent_v1"
    }
  ],
  "membership": {
    "givesAccess": true,
    "status": "active",
    "plan": "monthly",
    "accessUntil": "2026-09-20T18:00:00.000Z",
    "renews": true,
    "discountPercent": 15,
    "nextRewardAt": null,
    "subscription": {
      "givesAccess": true,
      "status": "active",
      "plan": "monthly",
      "accessUntil": "2026-09-20T18:00:00.000Z",
      "renews": true,
      "providerStatus": "active"
    }
  },
  "credits": {
    "paid": 10,
    "trial": 0,
    "trialExpiresAt": null
  },
  "coins": 500,
  "reroll": {
    "supported": true,
    "coinCost": 50,
    "maxItems": 8
  },
  "cosmetic": null,
  "managementUrl": "https://apps.apple.com/account/subscriptions",
  "termsUrl": "https://steptracker-api.org/billing-terms.html",
  "privacyUrl": "https://steptracker-api.org/privacy.html"
}
```

Historical annual still active

```json
{
  "available": true,
  "contract": "bara-billing-v1",
  "identity": {
    "appUserId": "11111111-1111-4111-8111-111111111111",
    "environment": "production"
  },
  "products": [
    {
      "id": "coins_500",
      "kind": "coins",
      "coins": 500,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_500_v1"
    },
    {
      "id": "coins_2800",
      "kind": "coins",
      "coins": 2800,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_2800_v1"
    },
    {
      "id": "coins_6000",
      "kind": "coins",
      "coins": 6000,
      "credits": 0,
      "plan": null,
      "storeProductId": "bara_coins_6000_v1"
    },
    {
      "id": "plus_monthly",
      "kind": "subscription",
      "coins": 500,
      "credits": 10,
      "plan": "monthly",
      "storeProductId": "bara_plus_monthly_v1"
    },
    {
      "id": "plus_permanent",
      "kind": "non_consumable",
      "coins": 500,
      "credits": 10,
      "plan": "permanent",
      "storeProductId": "bara_plus_permanent_v1"
    }
  ],
  "membership": {
    "givesAccess": true,
    "status": "active",
    "plan": "annual",
    "accessUntil": "2027-09-07T18:00:00.000Z",
    "renews": false,
    "discountPercent": 15,
    "nextRewardAt": null,
    "subscription": {
      "givesAccess": true,
      "status": "active",
      "plan": "annual",
      "accessUntil": "2027-09-07T18:00:00.000Z",
      "renews": false,
      "providerStatus": "active"
    }
  },
  "credits": {
    "paid": 120,
    "trial": 0,
    "trialExpiresAt": null
  },
  "coins": 6000,
  "reroll": {
    "supported": true,
    "coinCost": 50,
    "maxItems": 8
  },
  "cosmetic": null,
  "managementUrl": "https://apps.apple.com/account/subscriptions",
  "termsUrl": "https://steptracker-api.org/billing-terms.html",
  "privacyUrl": "https://steptracker-api.org/privacy.html"
}
```

### Permanent implementation verification — 2026-09-07

Implemented monthly plus permanent sales, historical annual fulfillment,
source-verified permanent access, immutable anniversary schedules, bounded
12-period recovery, period-level refund/reversal provenance, source-aware
cosmetics, retained suspended-subscription management, and provider backoff.
The existing reconciliation worker and cosmetic publication command wake
permanent-only identities; no new external scheduler/configuration is required.

Local-only additive migrations:
`20260908100000_bara_permanent_premium` and
`20260908110000_permanent_source_provenance`. They retain financial history after
account deletion, guard immutable source/schedule/grant provenance, and include
new history in the sandbox provisioning guard. No production/staging writes.

Tests were observed failing before each change. The combined billing, permanent,
realm and legacy-shop run passed 88/88 before the last three edge regressions;
the final complete permanent suite passed 24/24. Full backend unit suite passed
3,362/3,362 (zero skipped); provider and UTC anniversary fixtures passed 6/6.
The earlier full integration baseline results remain documented above; these
focused green checks do not erase those existing unrelated repository failures.
Final full integration: 2,913 passed, 30 failed, one existing skip (2,944 total).
All billing tests passed. Twenty-seven failure locations match the recorded
baseline; three additional intermittent locations passed targeted reruns.
Final Flutter suite: 3,061 passed; analysis clean; iOS simulator and Android prod
debug builds passed. Final combined code review: SHIP, no findings.
See `bara-permanent-premium-verification.md` for precise limitations and baseline
attribution. External store/RevenueCat setup, signed release builds and real
checkout acceptance remain deferred; no production/staging deployment occurred.
