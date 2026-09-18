# Coin pack amounts — 2026-09-10

Coin packs now grant **500 / 3,000 / 7,500** coins. Cash prices and internal/store
product IDs are retained. The production backend owns the quantities; installed
clients display the new values on their next billing refresh without a new build.
Frontend preview fixtures were updated separately so local previews match.

## Released state

- Backend change `0422190`, deployed as `b8a2969` after merging the existing
  docs-only main update. Release tag `coin-packs-500-3000-7500-20260910`.
- No database migration, dependency, environment or capacity change. Guarded
  reload verified two HTTP workers, cron/resolution online, staging stopped,
  aggregate database pool budget 32, and healthy application/Redis checks.
- Authenticated production iOS bootstrap returns the same `bara-billing-v1`
  contract and product IDs with quantities 500 / 3,000 / 7,500.
- Android remains unconfigured (`available:false`, empty products). The shared
  catalog and tests support the new amounts on Android; this change does not
  activate Android billing. Play's current one-time-product list returned no
  content. No Android store products or binaries were created.
- Apple reference names, version localizations, review notes, and all three
  review screenshots updated. Existing price schedules verified unchanged.
- RevenueCat display names updated and read back after the user granted the
  existing key Products read/write. Product IDs and types retained.
- Old Apple submission withdrawn with user approval. Replacement submission
  `ec62661c-7eae-4d3f-902b-8bf841b4fbd9` submitted at
  `2026-09-10T21:52:38.54Z`: build **2.3.13 (19)** plus all three coin packs,
  **WAITING_FOR_REVIEW**, **MANUAL** release. No customer release.

[Final service verification](artifacts/coin-pack-amounts/verification.json)
records the Apple, RevenueCat and live backend responses without credentials or
customer data. [Review screenshot](artifacts/coin-pack-amounts/shop-review.png)
is a capture of the real Shop widget with local catalog/billing fixtures; it is
not evidence of a real store purchase. No raster text was painted over a prior
screenshot.

## Compatibility and validation

Previously fulfilled receipts retain their recorded grants and are not topped
up. Refunds use each receipt's original grant. Old purchases first fulfilled
after deployment receive the increased amount. Product IDs containing 2800/6000
remain intentional compatibility identifiers, including the existing artwork
mapping. No new query, queue job, or downstream operation was introduced.

- New integration tests failed against the old quantities before implementation.
- All 81 distinct billing integration tests passed using local test PostgreSQL.
  The initial broad run passed 80; its review-seed test lacked local Redis.
  Starting a disposable local Redis and rerunning the entire failing realm suite
  passed all 13 tests. The disposable Redis was then stopped.
- 56 frontend tests passed across billing components, real preview navigation,
  live billing and unified Shop. New real-widget tests prove changing backend
  quantities refreshes existing iOS and Android product tiles.
- Real Shop screenshot capture passed and labels were visually inspected.
- `flutter analyze` clean. Existing assertions retained, with the old expected
  quantities updated to match the explicitly requested behavior.
- Independent code review: SHIP, no blockers/issues/nits. Economy review recorded
  in `economy.md`. No new native build or real-money purchase was needed/run.

## Manual UI checklist

Repeat with products available on iPhone; repeat on Android when billing is
configured. These checks remain for the user; automated checks above passed.

- Home → SHOP: 500 / 3,000 / 7,500 appear once each, above the matching sack,
  with quantities inside their label bands and prices below.
- Home → coin balance “+”: the same coin section opens without duplication.
- First-time real Shop tutorial: the Featured spotlight still frames the row.
- Billing preview → Shop and Coins: both show the updated quantities without
  clipping. A previously installed preview binary needs rebuilding to update its
  bundled examples; this does not affect live backend-driven quantities.

General tab/demo tutorials and Settings → View Shop Tutorial disable billing;
purchase tiles should remain absent there. The orphaned legacy Get Coins screen
shares the same coin widget but has no current navigation callsite.
