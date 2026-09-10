# Native store evidence — 2026-09-10

`storekit-before-propagation.json`: real Apple StoreKit2 query returned four
products immediately after the missing6,000-coin localization was created.

`native-storekit-revenuecat-products.json`: later real StoreKit2 and pinned
RevenueCat SDK queries both returned allfive actual products with localized USD
prices; monthly introductory eligibility lookup completed. This used iOS26.5
Simulator, bundlecom.rohanchari.steptracker, no StoreKit configuration file and
no network interception. RevenueCat used the compiled public iOS key and an
alreadyexisting billing identity. No purchase, restore, fulfillment or sync call
was made. Identifiers/customer/receipt/credential payloads and native log messages
were not recorded. The temporary identity file and disposable simulator were
removed after verification.

These prove current native product availability and SDK configuration, not paid
checkout/fulfillment or every possible device/account/network condition. UI
regression tests separately reproduce the false initial-unavailable state and
category/trial failure isolation through the real Flutter adapter/controller.
