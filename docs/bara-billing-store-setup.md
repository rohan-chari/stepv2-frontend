# Bara billing — store and RevenueCat setup

Setup guide for the authorized monthly/permanent billing implementation.
External ASC, Google Play and RevenueCat setup is deferred until code verification. Product IDs match
the locked code contract. Real purchase flows require the external store
accounts, products and credentials below before they can be verified.

## Accounts and app identities

Use the existing production app, bundle/package `com.rohanchari.steptracker`,
inside App Store Connect and Google Play Console. The Android staging package is
`com.rohanchari.steptracker.staging`; it is a separate Play app if used for
store-backed testing. Do not create the production products under that package.

RevenueCat needs one project with an App Store app and a Google Play app. SDK
public API keys differ by platform. The server's secret API key and webhook
Authorization secret belong only in server configuration, never Flutter defines
or committed files. The public SDK keys may be included in the app build.

Official instructions: [connect stores](https://www.revenuecat.com/docs/projects/connect-a-store),
[Flutter installation](https://www.revenuecat.com/docs/getting-started/installation/flutter),
[SDK configuration](https://www.revenuecat.com/docs/getting-started/configuring-sdk).

## App Store Connect

1. Complete the Paid Apps agreement, tax and banking setup for the existing app.
2. Under the app's In-App Purchases, create three **consumable** coin packs.
   Use the exact product IDs from the final code table below, with US reference
   prices $0.99, $4.99 and $9.99. Configure localization, availability, and the
   required review screenshot/notes. Store-localized prices are what users see.
3. Create one subscription group, **Bara+**, containing monthly $4.99
   auto-renewing subscription `bara_plus_monthly_v1`. Add its seven-day
   **free-trial introductory offer**. Create `bara_plus_permanent_v1` separately
   as a **non-consumable** at US $19.99, with no trial or renewal period.
   Do not create an annual offer for this launch. Store eligibility controls
   the monthly trial; do not reset eligibility on login.
4. Upload the In-App Purchase key and other requested App Store credentials in
   the RevenueCat app settings. An App Store Connect API key for product import
   is distinct from the In-App Purchase key; follow the credential labels.
5. Configure App Store server notifications using the URL RevenueCat provides.
   RevenueCat subsequently calls Bara's authenticated webhook; Apple should not
   call that RevenueCat-webhook endpoint directly.
6. Before submission, complete subscription metadata and attach the first
   purchases/subscriptions to the app version being submitted. Merely uploading
   an app build does not submit its products for review.
7. Update App Privacy for RevenueCat purchase history and account identifiers,
   preserving the app's other existing disclosures. Follow
   [RevenueCat's Apple privacy guidance](https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy).

References: [Apple IAP setup](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases),
[create consumables](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/),
[subscription groups](https://developer.apple.com/app-store/subscriptions/),
[RevenueCat Apple credentials](https://www.revenuecat.com/docs/store-configuration/app-store/service-credentials-index).

## Google Play Console

1. Open the existing production app and complete its payments setup.
2. Create three one-time products for the coin packs, using the exact product
   identifiers from the final code table. Configure and activate the purchase
   options, prices and availability. RevenueCat handles consumption after
   verification so a customer can buy the same coin pack again.
3. Create subscription `bara_plus_v1` with the `monthly` auto-renewing base
   plan at US $4.99/month. Add its seven-day free-trial offer for eligible new
   subscribers. Create one-time product `bara_plus_permanent_v1` at US $19.99,
   configured as non-consumable in RevenueCat. Activate the products and monthly
   offer; do not create an annual base plan for this launch. Permanent has no trial.
4. Create the Google Play service account, enable the required APIs, grant the
   package-scoped permissions RevenueCat specifies, and upload its JSON key
   directly to RevenueCat. Wait for RevenueCat's credential checks to pass.
5. Configure Real-time Developer Notifications / Pub/Sub using RevenueCat's
   current instructions. These store notifications go to RevenueCat, while
   RevenueCat's webhook goes to Bara.
6. Add testers to both the internal testing track and license testing as required.
   Install the build through the Play opt-in link using the tester's Play account.
   A debug APK installed with adb is not sufficient proof of a working Play checkout.
7. Update Data Safety for purchase history and identifiers, using
   [RevenueCat's Google disclosure guidance](https://www.revenuecat.com/docs/platform-resources/google-platform-resources/google-plays-data-safety)
   and the app's actual existing uses. Keep the public privacy-policy URL current.

References: [Google subscriptions/base plans/offers](https://support.google.com/googleplay/android-developer/answer/140504?hl=en-EN),
[RevenueCat Google credentials and RTDN](https://www.revenuecat.com/docs/service-credentials/creating-play-service-credentials).

## RevenueCat product setup

Import the five products for each store and map monthly and permanent membership
to the single `bara_plus` entitlement. Coin packs are consumable grants,
not subscription entitlements. The backend derives quantities from its immutable
product mapping, never from editable display text or client-supplied quantities.

The Flutter integration fetches the exact product identifiers directly with
RevenueCat's `getProducts`; it does not require an Offering or Packages. Import
the products and attach the membership products to the entitlement. Do not reuse
an existing SKU to change its coin quantity; introduce a new versioned SKU instead.
Set restore behavior to **Keep with original App User ID**. Purchases remain
with the original Bara account, including after account deletion. On Apple,
the same receipt can also prevent new purchases under a different Bara account;
test this explicitly and direct affected customers to their original account.

Permanent access is a separate non-consumable purchase. It does not cancel an
existing monthly subscription. Bara keeps the monthly management link and tells
customers to cancel future renewal in the store. Any actual separate renewal
still receives its paid bundle. Block new subscription checkout and repeat
permanent checkout while permanent ownership is active. Historical annual
receipts remain recognizable but are no longer offered for sale.

Use the exact server webhook URL and Authorization value from the deployment
configuration. Send all relevant events, including sandbox events required by
the test-account design. A test webhook proves delivery/authentication only;
it does not prove store checkout, entitlement fulfillment, renewal or refunds.

The backend also reconciles provider history: a missed SDK callback or webhook
must not permanently lose a verified consumable or subscription renewal.
References: [webhooks](https://www.revenuecat.com/docs/integrations/webhooks),
[restore behavior](https://www.revenuecat.com/docs/projects/restore-behavior),
[subscription transaction history](https://www.revenuecat.com/docs/api-v2/subscription).

## Before customer release

Deploy the additive backend before shipping the app, after explicit production
deployment approval. Publish the first calendar cosmetic release before enabling
sale in the store; the sample Wizard Hat used in the visual preview is not an
implicit production calendar selection.

Verify on both stores with authorized isolated test accounts: all three packs;
repeat pack purchase; cancel/pending checkout; seven-day trial and paid
conversion; monthly grants; permanent purchase and recurring rewards; restore;
renewal; subscription management while permanent;
refund; interrupted app/server recovery; discounts; single and batch rerolls;
and continued use of paid credits after normal membership expiry.

Record the observed store transaction, provider transaction, and backend grant
IDs for each test. Confirm retries create one grant and one reroll debit. Confirm
a test purchase never credits an ordinary production player's wallet. Then
complete the final store-review checklist and native release builds for both
platforms. Store setup, sandbox checkout and customer release are separate steps.

## Code identifiers and configuration

The locked product identifiers are:

| Product | App Store ID | Google Play ID / base plan |
|---|---|---|
| 500 coins — US $0.99 | `bara_coins_500_v1` | `bara_coins_500_v1` |
| 2,800 coins — US $4.99 | `bara_coins_2800_v1` | `bara_coins_2800_v1` |
| 6,000 coins — US $9.99 | `bara_coins_6000_v1` | `bara_coins_6000_v1` |
| Bara+ monthly — US $4.99 | `bara_plus_monthly_v1` | Subscription `bara_plus_v1`, base plan `monthly` |
| Bara+ permanent — US $19.99 once | `bara_plus_permanent_v1` (non-consumable) | `bara_plus_permanent_v1` (one-time, non-consumable) |

RevenueCat represents Android monthly as `bara_plus_v1:monthly`. Attach it and
`bara_plus_permanent_v1` to `bara_plus` (and attach the corresponding Apple products
in the same project). Coin packs must not be attached to that entitlement.

Permanent grants 500 coins and 10 paid reroll credits on each monthly anniversary.
The first bundle is immediate for a free/trial account; with existing paid
subscription coverage, it starts at that original paid period's end. Dates use
UTC and clamp to a short month's final day without drifting the original anchor.
Missed months remain owed. Restore or second-store purchase never resets the
schedule. The backend worker handles these grants without store renewal events.

For Android, prove the permanent product is acknowledged **without consumption**:
repeat purchase should remain owned, including after reinstall and restore. The
installed native SDK supports non-consumables, but a successful coin-pack test
alone does not verify this product configuration. See
[RevenueCat non-subscription purchases](https://www.revenuecat.com/docs/platform-resources/non-subscriptions).

Frontend public build defines:

- `REVENUECAT_IOS_API_KEY`
- `REVENUECAT_ANDROID_API_KEY`

Backend-only configuration:

- `REVENUECAT_SECRET_API_KEY`
- `REVENUECAT_PROJECT_ID`
- `REVENUECAT_IOS_APP_ID` — RevenueCat's app identifier, not the bundle ID.
- `REVENUECAT_ANDROID_APP_ID` — RevenueCat's app identifier, not the package name.
- `REVENUECAT_WEBHOOK_AUTHORIZATION` — full `Bearer …` value, matching RevenueCat.
- `BILLING_TERMS_URL` — HTTPS URL of deployed `/billing-terms.html`.
- `BILLING_PRIVACY_URL` — HTTPS URL of deployed `/privacy.html`.

Each platform's checkout requires its own app ID. For the user-authorized
iOS-first setup, leave `REVENUECAT_ANDROID_APP_ID` absent until the Google Play
app is configured. With the shared credentials, legal URLs and iOS app ID set,
iOS checkout and account reconciliation work; Android bootstrap reports
`available: false` and an empty product list while retaining wallet/member state.
Use the full REST API project ID shown in Project settings (including `proj`),
not the shortened ID in the dashboard URL. These are credential requirements,
not release flags.

Webhook route: `/billing/webhook/revenuecat` on the approved backend deployment.
Public legal pages are included in the backend web build. Review their purchase
terms and billing disclosure before publishing the deployment.

### Historical refund backstop

Configure RevenueCat's **Transactions** scheduled data export in CSV format,
including new and updated rows. Required information includes the original
RevenueCat customer ID, product identifier, store, sandbox marker, store
transaction ID, refund date and
`updated_at`. These exports are gzip-compressed CSV. Do not substitute the
In-App Currency feed: Bara's wallet remains in its own backend.

Deliver exports to controlled storage and run the backend's import command below.
The importer matches already-verified
purchases; an export row or alias does not authorize minting new currency.
This catches older refunds that a current subscription snapshot cannot identify.
See [RevenueCat scheduled data exports](https://www.revenuecat.com/docs/integrations/scheduled-data-exports).

## Backend operator steps

Run these from the backend repository with its intended database and billing
configuration loaded. Production commands that apply changes require a separate
approved deployment/operation. None of these production operations has been run
as part of implementation.

### Dedicated sandbox accounts

TestFlight builds use Apple's sandbox for purchases. Uploading a build does not
require the purchase products to be approved. To test the products, Apple's
minimum metadata is a reference name, product ID, localized name and price;
complete any missing localization before testing. A review screenshot is not
listed in that sandbox minimum, but is still needed for product submission.
See [Apple's sandbox testing requirements](https://developer.apple.com/documentation/storekit/in-app_purchase/testing_in-app_purchases_with_sandbox).

Use a fresh Bara account before it earns/spends coins, joins competitions, makes
referrals or establishes friendships. Check eligibility first, then apply:

```sh
node scripts/billing-provision-sandbox.js --user-id=TEST_USER_UUID
node scripts/billing-provision-sandbox.js --user-id=TEST_USER_UUID --apply
```

The first command rolls back after validating eligibility. The second permanently
marks the account as sandbox; it cannot later become an ordinary player. Existing
production activity is rejected, not erased. Sandbox identities remain sandbox
after deletion/recreation, and mixed competition admission is blocked in the
database. Sign out/in after provisioning so cached account presentation refreshes.
Confirm `/billing/bootstrap` returns `identity.environment: "sandbox"` before
checkout. A fresh reviewer account created through `/auth/review` is also sandbox.
An existing reviewer with production history needs a separately approved clean
test-account setup; the provision command will not convert its history.

Pair these Bara accounts with Apple Sandbox testers / Google license testers.
The store tester and the Bara account are two separate identities. An ordinary
Bara account intentionally rejects sandbox fulfillment even when installed from
TestFlight or Play internal testing. Use a fresh store test account when testing
original-account ownership after deleting an earlier Bara account.

### Publish the calendar cosmetic

Select an existing compatible shop item; the preview's sample is not a release
selection. Publish before its UTC calendar month begins:

```sh
node scripts/billing-publish-cosmetic.js --month=2026-10 --item-id=SHOP_ITEM_UUID
node scripts/billing-publish-cosmetic.js --month=2026-10 --item-id=SHOP_ITEM_UUID --apply
```

Use the actual release month. Publication is immutable for that month and rejects
inactive/test-only items or missing asset metadata. New artwork must first follow
the ordinary asset rollout rules for older clients. Late publication delivers
owed rewards from verified paid coverage; an already-owned cosmetic has no
substitute. Annual currency/credits are independent of these calendar awards.

### Reconciliation and historical refunds

The existing backend scheduler runs the billing worker. Work and leases live in
Postgres, so process restarts and duplicate delivery do not duplicate grants.
Monitor failures and durable overdue work. For an operator recovery pass:

```sh
node scripts/billing-reconcile.js
node scripts/billing-reconcile.js --identity-id=BILLING_IDENTITY_UUID
```

These commands perform verified reconciliation and can write grants/reversals;
they are not dry runs. An identity ID is the opaque ID from bootstrap, not the
Bara user ID.

Configure a daily RevenueCat **Transactions CSV** export with **new and updated
transactions**. Include these exact columns:

```text
store_transaction_id,product_identifier,store,is_sandbox,
rc_original_app_user_id,refunded_at,updated_at
```

Retain deliveries in controlled storage. Decompress a downloaded `.csv.gz` to CSV
and validate it, then apply:

```sh
node scripts/billing-import-refunds.js --file=/path/to/transactions.csv
node scripts/billing-import-refunds.js --file=/path/to/transactions.csv --apply
```

Schedule delivery/download and this import daily using your storage service and
job runner. Retain failed files and retry them; importing a file again is safe.
Alert on a missing daily delivery or failed import. Unknown transactions are
queued for provider verification; an export row cannot mint coins. Do not drop
older transactions from updated exports: that is how missed historical refunds
are recovered. The storage destination and download credentials are external
setup, not app build configuration.

## Build and console handoff

RevenueCat Dashboard → project → **API keys** provides the platform public SDK
keys; create a server secret key there for REST API v2. See
[RevenueCat API keys](https://www.revenuecat.com/docs/projects/authentication).
Use the production commands in `DEPLOYMENT.md`, which include the public-key
defines and preserve existing OAuth/AdMob configuration. Keep the established
iOS/Android version-number mapping. Never include the secret key in Flutter.

The verified debug artifacts prove both native integrations compile. Store-backed
test builds still need the real public keys, configured products and the deployed
backend. After both stores pass the lifecycle test matrix above, create the
matching signed IPA/AAB, upload them to TestFlight/Play internal testing, and
attach the purchases to the customer release submission. Upload, review
submission and customer release remain distinct actions.
