# Backpack retirement and refund

User authorization: “can we get rid of backpack and refund everyone”. Scope is Backpack only: deactivate sale, remove owned Backpack and refund actual paid coins. Preserve item identity, source/CDN artwork and purchase history. This is separate from the proposed automated artwork lifecycle.

Production read-only audit found one owner, one SUCCEEDED purchase for1,000 coins and its matching−1,000 shop_purchase ledger entry. No equipped copies, saved wardrobe items, ad/daily grants or billing cosmetic references. Other refund records were for different items/events. No user identifiers are recorded in this report.

Operation must atomically disable Backpack, remove its ownership and credit exactly1,000 coins through the canonical awardCoins seam with a unique ledger reference. Repeat execution must issue zero more coins; changed references or ambiguous evidence must abort. Public production reward pool unchanged because Backpack was TestFlight-only. The purchase and refund net to zero coins; refund issuance itself is+1,000.

Status: COMPLETE. Production verified 2026-09-11T00:41:50.042Z (September10 EDT). Exactly one shop_refund ledger entry for1,000 coins; Backpack inactive and ownership removed. Authenticated Production and TestFlight catalog GETs both200 with Backpack absent from offerings and ownedItemIds. Purchase replay/history and artwork references preserved. All requested cache invalidations completed.

Implementation: backend commit `2a748a4`, pushed to main; only the reviewed one-off script was transferred/run on production. No runtime pull/restart, migration, staging start, app build or upload. Script ran with a one-connection CLI pool. Initial dry run stopped before DB access because the production CLI role was unspecified; rerun used explicit process-local role/pool configuration, with no persistent config change. Fresh production-generated snapshot matched the earlier audited owner/purchase/debit before application. Private plan and execution log retained in the server’s root-only dated backup directory.

Validation:4/4 tests-first dedicated-testDB CLI/realHTTP integration tests passed, covering exact historical refund, retry idempotency, history/art retention, purchase replay without re-grant, and abort guards. Code reviewer SHIP; economy analyst SOUND. JavaScript syntax and diff checks passed. No Flutter source changed; physical-device checklist below remains manual. No production test purchase or second refund was executed.

## Manual UI-placement checklist

1. Reopen Home → Shop → Accessories, including the coin “+” entry: Backpack absent, no empty card/gap; other accessories remain.
2. Refunded account → Shop → Characters → Edit → Back accessories: Backpack absent from Owned and Locked. Existing outfit and other gear remain. Home/shop coin balances render normally.
3. Settings → View Shop Tutorial → customization: Backpack absent, remaining choices and spotlights correctly placed.

Repeat on TestFlight, available older production app and Android. General tutorial, demo race and billing-preview fixtures contain no Backpack. Reopen screens before checking cached content. Refund amount and exactly-once behavior require backend verification separate from this visual checklist.
