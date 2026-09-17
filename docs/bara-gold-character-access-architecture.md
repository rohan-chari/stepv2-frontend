# Bara Gold Character Access Architecture Report

Research date: 2026-09-17

Repositories inspected:

- Frontend: `/Users/rohan/repos/stepv2-frontend`
- Backend: `/Users/rohan/repos/stepv2-backend`

This is a read-only architecture report. No code, database rows, migrations,
RevenueCat configuration, catalog records, deployment state, or tests were
modified by this research.

## A. Executive Summary

The current system does not implement temporary Gold character access.

Characters are catalog records in `shop_items`. Permanent ownership is
represented by `user_shop_items`, with provenance in
`shop_item_ownership_sources`. Gold membership is computed from billing
subscription records, but current Gold character logic is limited to catalog
filtering, metadata, styling, and purchase policy.

Gold-capable clients can receive three special character rows—Mouse, Hedgehog,
and Sea Lion—but those rows remain `owned: false` unless the user has a durable
ownership record. Character wardrobe reads and activation still require
permanent ownership.

The proposed model therefore needs backend authorization changes, not merely
frontend UI changes:

```text
character access = permanent ownership OR active Gold OR globally free
```

Temporary Gold access must remain separate from `user_shop_items`.

## B. Current Character Ownership Model

### Catalog model

Characters are ordinary `ShopItem` records with fields including:

- `id`
- `sku`
- `name`
- `slot`
- `active`
- `testOnly`
- `remoteOnly`
- `earnOnly`
- `sortOrder`
- `priceCoins`
- `assetKey`
- `assetVersion`
- rendering metadata
- accessory compatibility metadata

Important files:

- `prisma/schema.prisma`
- `src/modules/cosmetics/shopCosmetics.js`
- `src/modules/cosmetics/characterWardrobes.js`
- `prisma/migrations/20260704120000_add_character_slot/migration.sql`

### Permanent ownership source of truth

The canonical durable ownership signal is:

```text
user_shop_items(user_id, shop_item_id)
```

Ownership provenance is tracked in:

```text
shop_item_ownership_sources
```

The provenance infrastructure was added by:

`prisma/migrations/20260915150000_bara_gold_ownership/migration.sql`

Permanent ownership should remain durable and independent of subscription
state.

### Acquisition paths

#### Coin purchase

Relevant files:

- `src/modules/cosmetics/purchaseShopItem.js`
- `src/modules/cosmetics/getShopCatalog.js`
- `src/modules/billing/services/memberPrice.js`

The server validates catalog policy, applies membership pricing, deducts coins
transactionally, and creates or upserts durable ownership.

#### Direct character IAP

Relevant files:

- `src/modules/billing/catalog.js`
- `src/modules/billing/models/billingState.js`
- `src/modules/billing/services/revenueCatProvider.js`
- `src/modules/billing/commands/sync.js`
- `test/integration/billing/character-iap-lifecycle.test.js`

Verified non-consumable purchases create:

- a `billing_purchases` record
- a `shop_item_ownership_sources` record
- a `user_shop_items` record

The ownership source uses a `DIRECT_IAP:<canonical billing key>` source value.

#### Admin grants

Admin grants use durable `user_shop_items` ownership. The Mouse publication
documentation records user locking, item locking, idempotent insertion, and
no automatic equip:

- `docs/mouse-character-publication.md`

#### Restore

RevenueCat purchase history reconciliation re-fulfills verified non-consumable
character purchases into durable ownership.

#### Refund and reversal

`reverseDirectCharacter()` in
`src/modules/billing/models/billingState.js` revokes the matching ownership
source and removes `user_shop_items` only when no active permanent source
remains. A refund reversal restores the source and ownership.

Subscription processing does not currently create character ownership rows.

## C. Current Bara Gold Character Behavior

Current identifiers include:

- `bara_gold_v1`
- `bara_plus_v1`
- `bara_plus_weekly_v1`
- `bara_plus_monthly_v1`
- `bara_plus_annual_v1`
- `bara_plus_permanent_v1`
- `GOLD_BENEFIT_VERSION = 'bara_gold_v1'`
- `GOLD_SUBSCRIPTION_GROUP = 'bara_gold_subscription_group_v1'`

The current Gold-specific character set is exactly:

| SKU | Direct product |
|---|---|
| `mouse` | `bara_character_mouse_v1` |
| `hedgehog` | `bara_character_hedgehog_v1` |
| `sea_lion` | `bara_character_sea_lion_v1` |

These identifiers appear in:

- `src/modules/billing/catalog.js`
- `src/modules/billing/queries/goldPolicy.js`
- `src/modules/cosmetics/accessoryCompatibility.js`
- `src/modules/cosmetics/characterWardrobes.js`

`characterPolicy()` returns:

- `goldAccess`
- `benefitVersion`
- `coinPurchaseAllowed`
- `directPurchase`
- `unavailableReason`
- `canPurchase`

However, `goldAccess` is currently a presentation and purchase-policy value.
It does not make `owned` true and does not authorize activation.

## D. Character Catalog and API Flow

```text
shop_items
  -> getCharacters()
  -> characterPolicy()
  -> serialized ShopItem
  -> GET /shop/characters
  -> CharacterWardrobeController
  -> ShopCharacter
  -> Flutter shop UI
```

### `GET /shop/characters`

Backend files:

- `src/modules/shop/routes.js`
- `src/modules/cosmetics/characterWardrobes.js`

The query:

- selects `shop_items` with `slot = CHARACTER`
- applies release-channel visibility
- applies `remoteOnly` and `remote_assets` capability rules
- checks ownership with `EXISTS` against `user_shop_items`
- applies the current hard-coded Gold SKU filter
- uses keyset pagination
- bounds pages to 48 rows
- reads wardrobe state in a repeatable-read snapshot
- separately reads member discount and Gold membership

The response includes `owned`, `active`, `canPurchase`, `canActivate`,
`canEdit`, `goldAccess`, `benefitVersion`, `directPurchase`, and
`unavailableReason`.

The default Capybara is synthesized as:

```text
characterKey = default
name = Capybara
owned = true
```

### `GET /shop/characters/:characterKey/wardrobe`

This currently calls `character()` with ownership required. An unowned
character returns `CHARACTER_NOT_OWNED` even if the user has active Gold.

### `PUT /shop/characters/:characterKey/outfit`

This also requires the character to pass the ownership check. It validates
accessory ownership, fit, conflicts, revisions, and then saves character-
specific wardrobe state. Saving an outfit never grants ownership.

### `PUT /shop/active-character`

This uses the same character wardrobe mutation path and currently permits only
permanently owned characters or the synthesized default character.

### Caching

The character query is bounded and uses ownership `EXISTS` checks rather than
an ownership query per character. Redis infrastructure is derived-data cache
only and falls back to PostgreSQL on failure:

- `src/shared/cache/redisCache.js`
- `src/shared/cache/derivedCache.js`
- `src/shared/cache/cacheKeys.js`

## E. Character Equip / Selection Authorization

Current path:

```text
PUT /shop/active-character
  -> changeCharacterWardrobe.js
  -> characterWardrobes.js
  -> mutate()
  -> character(tx, characterKey, opts)
  -> user_shop_items ownership check
  -> CHARACTER_NOT_OWNED if absent
```

The future server-side predicate needs to be shared across reads and writes:

```text
hasCharacterAccess(user, character) =
  permanently owned
  OR globally free
  OR active Gold AND Gold includes character
```

This predicate must cover collection enrichment, wardrobe reads, outfit saves,
active-character mutation, character-slot equipping, and accessory operations
that depend on the active character.

The frontend must never be authoritative for this decision.

## F. Bara Gold Membership Architecture

RevenueCat webhooks enter through:

```text
POST /billing/webhook/revenuecat
```

Relevant backend files:

- `src/modules/billing/routes.js`
- `src/modules/billing/commands/inbox.js`
- `src/modules/billing/services/revenueCatProvider.js`
- `src/modules/billing/services/reconcile.js`
- `src/modules/billing/services/reconciliationWorker.js`
- `src/modules/billing/models/billingState.js`

Billing state is stored in:

- `billing_identities`
- `billing_purchases`
- `billing_subscriptions`
- `billing_inbox`
- `billing_reconciliation`
- `billing_permanent_sources`
- `billing_permanent_grants`
- `billing_permanent_revocations`

`membershipFor()` in `src/modules/billing/queries/bootstrap.js` considers
access active when a subscription has `givesAccess = true` and either:

- `accessUntil > now`, or
- `providerStatus` is `in_grace_period` or `unknown`

It also handles permanent Bara+ membership separately. Gold-specific membership
is then computed by `goldMembershipForUser()` in
`src/modules/billing/queries/goldPolicy.js`, which requires the active
subscription’s `benefitContract` to equal `bara_gold_v1`.

This centralized definition should be reused by character access logic.

Frontend billing files:

- `lib/services/live_billing_controller.dart`
- `lib/services/billing_controller.dart`
- `lib/services/store_billing_client.dart`
- `lib/models/billing.dart`
- `lib/widgets/live_billing_scope.dart`
- `lib/widgets/billing_scope.dart`

`LiveBillingController` clears state on account changes, reacts to RevenueCat
customer-info changes, refreshes backend state, and does not grant value
locally.

## G. Subscription Expiration Behavior

There is currently no character-specific Gold expiration repair path.

When Gold expires:

- billing state eventually reports no active Gold access
- Gold policy fields change
- Gold-only rows may be filtered or marked unavailable
- permanent ownership remains untouched
- an active Gold-only character may remain in
  `user_equipped_accessories`
- later ownership-only authorization rejects it

Existing character repair infrastructure:

- `src/modules/cosmetics/repairCharacterWardrobes.js`
- `src/modules/cosmetics/characterWardrobeState.js`

Possible approaches are:

1. Repair appearance during billing expiration processing.
2. Lazily repair on the next profile/shop/appearance read.
3. Leave the selected value but block future use.

The existing architecture most naturally supports a lazy, transactional repair
or a narrowly scoped repair at appearance read time. No approach should delete
wardrobes, accessories, or permanent ownership.

## H. Permanent Ownership vs Temporary Gold Access

The current model supports permanent ownership and Gold membership separately,
but does not currently combine them for character authorization.

| Permanent Ownership | Active Gold | Expected Access |
|---|---:|---|
| No | No | Globally free characters only |
| No | Yes | Gold-included characters plus globally free characters |
| Yes | No | Permanently owned characters plus globally free characters |
| Yes | Yes | Permanent, Gold-included, and globally free characters |

The second row is the missing behavior.

## I. Direct Character IAP Interaction

Direct products currently exist for Mouse, Hedgehog, and Sea Lion. Product IDs
are supplied by the backend and purchased through the Flutter billing adapter.

Relevant frontend files:

- `lib/widgets/shop_character_card.dart`
- `lib/screens/tabs/shop_tab.dart`
- `lib/services/live_billing_controller.dart`
- `lib/services/store_billing_client.dart`
- `lib/models/character_wardrobe.dart`

The existing provenance system supports the required ownership cases:

- permanent purchase before Gold remains permanent after Gold expires
- permanent purchase during Gold remains permanent after Gold expires
- refund revokes only the permanent purchase source
- active Gold can independently preserve temporary access after refund
- loss of both permanent ownership and Gold makes the character unavailable

The final two cases require the new shared access predicate.

Restore must restore permanent ownership only from verified non-consumable
history. Subscription access must never create permanent ownership.

## J. Wardrobe / Accessory Interaction

Relevant files:

- `src/modules/cosmetics/characterWardrobes.js`
- `src/modules/cosmetics/characterWardrobeState.js`
- `src/modules/cosmetics/equipAccessory.js`
- `src/modules/cosmetics/accessoryCompatibility.js`
- `src/modules/cosmetics/repairCharacterWardrobes.js`
- `prisma/migrations/20260909190000_character_wardrobes/migration.sql`

Accessory ownership is independent from character ownership. Saved outfits are
stored by `(user_id, character_key)` in `character_wardrobes` and
`character_wardrobe_items`.

Fit data is stored in `shop_item_character_fits`.

Gold expiration must not delete:

- user-owned accessories
- accessory ownership sources
- saved character wardrobes
- permanent character ownership

On resubscription, the preserved wardrobe should become usable again if the
character and accessories remain active, visible, owned where required, and
compatible.

## K. Character Visibility and Capability Flags

### `characters`

Sent when the client can render character assets. It controls whether
character-slot catalog rows and character mutations are exposed.

### `remote_assets`

Controls whether remote-only characters and assets can be returned.

### `bara_gold_v1`

Controls whether Gold-specific billing and character fields are included. It is
not itself proof of membership.

The current collection query contains the compatibility rule:

```text
supportsGold
OR sku not in ('mouse', 'hedgehog', 'sea_lion')
OR permanently owned
```

This explains why visibility can differ by client capability and account.

## L. Frontend Impact Map

Core files:

- `lib/models/character_wardrobe.dart`
- `lib/services/character_wardrobe_controller.dart`
- `lib/services/backend_api_service.dart`
- `lib/services/live_billing_controller.dart`

Likely UI files:

- `lib/screens/tabs/shop_tab.dart`
- `lib/widgets/shop_character_card.dart`
- `lib/screens/character_wardrobe_screen.dart`
- `lib/screens/bara_plus_screen.dart`
- `lib/widgets/bara_plus_card.dart`
- `lib/widgets/bara_gold_ribbon.dart`
- `lib/widgets/accessory_preview_sheet.dart`

Other appearance surfaces:

- `lib/screens/tabs/home_tab.dart`
- `lib/screens/race_detail_screen.dart`
- `lib/screens/race_results_summary_screen.dart`
- `lib/screens/public_profile_screen.dart`
- `lib/widgets/public_profile_sheet.dart`
- `lib/widgets/race_card_capybara_row.dart`
- `lib/widgets/team_scoreboard_cards.dart`
- `lib/widgets/active_race_card.dart`
- `lib/widgets/featured_race_card.dart`
- `lib/widgets/race_podium.dart`
- `lib/widgets/race_track.dart`

Demo/tutorial infrastructure also needs review:

- `lib/demo/`
- `lib/tutorial/`
- `lib/tutorial/tutorial_preview_data.dart`
- `lib/preview/preview_billing_api.dart`

The frontend should consume server-provided access state. It should not derive
access from catalog SKU lists or local billing state alone.

## M. Backend Impact Map

Likely affected files:

- `src/modules/cosmetics/characterWardrobes.js`
- `src/modules/cosmetics/characterWardrobeState.js`
- `src/modules/cosmetics/equipAccessory.js`
- `src/modules/cosmetics/accessoryCompatibility.js`
- `src/modules/cosmetics/getShopCatalog.js`
- `src/modules/cosmetics/purchaseShopItem.js`
- `src/modules/billing/queries/goldPolicy.js`
- `src/modules/billing/queries/bootstrap.js`
- `src/modules/billing/models/billingState.js`
- `src/modules/billing/services/reconciliationWorker.js`
- `src/modules/home/getHomeRaceCard.js`
- `src/modules/social/queries/getPublicProfile.js`
- `src/modules/leaderboard/getLeaderboard.js`
- `src/modules/ranked/queries/getRanked.js`
- `src/modules/ranked/queries/getRankedV2.js`
- `src/modules/races/queries/getRaceDetails.js`
- `src/modules/tournaments/queries/getTournamentDetail.js`

## N. Database / Migration Assessment

A migration is not inherently required.

The current schema already provides durable ownership, provenance, revocation,
billing state, saved wardrobes, and character/accessory fit data.

The smallest safe design is:

- keep `user_shop_items` unchanged
- keep ownership sources unchanged
- compute Gold access dynamically
- share one backend access predicate

A small additive catalog field could replace the current hard-coded three-SKU
Gold set if future characters need explicit Gold inclusion policy. A per-user
Gold-character entitlement table is not necessary and would create avoidable
write amplification and expiration fanout.

## O. Caching and Scale Assessment

The efficient request shape is:

1. Load a bounded catalog page.
2. Load ownership for those rows with one query or `EXISTS` projection.
3. Load Gold membership once.
4. Combine access state in memory.

Avoid:

- one Gold query per character
- one RevenueCat call per request
- one ownership query per row
- one entitlement row per user/character
- catalog rebuilds per user
- capability-only caches for account-specific access

Catalog projections may be cached by channel and capability. Membership and
ownership remain account-specific. Redis remains a derived cache, never the
source of truth.

## P. Security / Cheat Resistance

Current protections include authentication, server-side catalog lookup,
visibility checks, ownership checks, transactional coin deduction, verified
RevenueCat fulfillment, idempotent provenance, refund processing, and fit
validation.

A modified client must not be able to gain access by sending:

- a character ID
- `owned: true`
- `goldAccess: true`
- a fake product ID
- a spoofed capability header

Every character mutation must validate permanent ownership, global-free status,
or current server-derived Gold access.

## Q. Backward Compatibility

The rollout should be additive and backend-first.

Older clients may not send `characters`, `remote_assets`, or `bara_gold_v1`,
and may not understand new access fields. Therefore:

- retain existing response fields
- do not repurpose `owned` to mean temporary access
- add new fields only for capable clients where necessary
- preserve existing capability filtering
- do not send unsupported remote assets to old clients
- do not make old clients depend on new endpoints or fields

Returning newly visible characters to a capable new client is safe only if the
client can render them and the server continues to protect old-client paths.

## R. Existing Tests

Important backend tests:

- `test/integration/bara-gold-characters.test.js`
- `test/integration/bara-gold-compatibility.test.js`
- `test/integration/billing/bara-gold.test.js`
- `test/integration/billing/character-iap-lifecycle.test.js`
- `test/integration/billing/billing.test.js`
- `test/integration/billing/monthly-lifecycle.test.js`
- `test/integration/billing/permanent.test.js`
- `test/integration/billing/client-capability-matrix.test.js`
- `test/integration/character-wardrobes.test.js`
- `test/integration/character-wardrobe-operations.test.js`
- `test/integration/character-wardrobe-safety.test.js`
- `test/integration/character-wardrobe-cache.test.js`
- `test/integration/character-wardrobe-writers.test.js`
- `test/integration/accessory-compatibility.test.js`
- `test/integration/accessory-preview.test.js`
- `test/integration/backend-catalog-authority.test.js`
- `test/integration/characterVisibility.test.js`
- `test/integration/public-profile.test.js`

Important frontend tests:

- `test/bara_gold_frontend_test.dart`
- `test/character_wardrobe_screen_test.dart`
- `test/compact_character_actions_test.dart`
- `test/full_screen_shop_test.dart`
- `test/unified_shop_test.dart`
- `test/live_billing_test.dart`
- `test/permanent_billing_test.dart`
- `test/store_billing_adapter_test.dart`
- `test/billing_components_test.dart`
- `test/billing_sign_in_session_test.dart`
- `test/billing_native_catalog_resilience_test.dart`
- `test/shop_tab_store_inventory_test.dart`
- `test/shop_equipped_character_shape_test.dart`
- `test/accessory_preview_test.dart`
- `test/remote_asset_cache_test.dart`

## S. Missing Tests

Required integration coverage includes:

1. Non-Gold plus unowned character is locked.
2. Gold plus unowned included character is accessible.
3. Gold plus unowned character can activate through HTTP.
4. Expiration removes temporary access without deleting ownership or wardrobe.
5. Permanent ownership survives expiration.
6. Purchase during Gold survives expiration.
7. Refunded permanent purchase plus active Gold remains accessible.
8. Refunded purchase plus expired Gold is rejected.
9. Resubscription restores access without inserting ownership.
10. Account switching does not leak Gold access.
11. Active temporary character is safely repaired or rejected according to the chosen policy.
12. Historical race appearance remains unchanged.
13. Wardrobes and accessories survive temporary access loss.
14. Resubscription restores access to the preserved wardrobe.
15. Default/free characters remain available.
16. Spoofed client fields cannot bypass server authorization.
17. Capability combinations remain backward compatible.
18. Concurrent refund, purchase, expiration, and resubscription operations remain source-safe.

## T. Current Gold Readiness / Known Technical Debt

Verified repository state:

- Backend `HEAD`: `1b7c21f` — `Add social follow rewards`
- Frontend `HEAD`: `10c3bfa` — `Bump release build to 14`
- Backend worktree: clean
- Frontend worktree: unrelated modified and untracked files present
- `flutter analyze`: passed with no issues

Relevant technical debt:

1. Gold character inclusion is hard-coded to three SKUs in multiple backend files.
2. Gold metadata is not equivalent to access authorization.
3. Character activation currently requires permanent ownership.
4. There is no Gold-expiration character repair path.
5. Direct-IAP provenance is source-aware, but temporary Gold access is not part of character authorization.
6. Historical wardrobe release documentation records unrelated full-suite failures accepted during deployment; this audit did not reclassify every historical failure.
7. Production catalog rows were not directly queried during this audit. The three Gold SKUs are verified from source and retained evidence, but all current production values should be confirmed with a read-only query before implementation.

## U. Product Decisions We Still Need To Make

- Can active Gold subscribers permanently purchase characters?
- If yes, are coin purchases allowed?
- If yes, does the 15% Gold discount apply?
- Are direct character IAPs still offered to Gold users?
- What visually happens when Gold expires while a temporary character is equipped?
- What label should temporary characters display?
- Should every future character automatically be included in Gold?
- Or should each character explicitly opt into Gold through catalog metadata?
- Are free characters synthesized, globally accessible, or permanently owned?
- Can Gold users save wardrobes on temporary characters?
- Does Gold access include grace period, billing retry, and unknown provider states?
- Can a temporary character remain active through an in-progress race?

## V. Recommended Architecture Options

### Option 1: Dynamic predicate, no character entitlement rows

Keep durable ownership and billing tables unchanged. Compute access dynamically
from permanent ownership, global-free status, and active Gold.

Advantages:

- no migration required
- no per-user character rows
- low write amplification
- natural resubscription behavior
- efficient bounded reads

Risks:

- active appearance may temporarily reference an expired character
- lazy repair must be transaction-safe
- all ownership-only authorization paths must be audited

### Option 2: Dynamic predicate plus catalog Gold-inclusion field

Add an additive catalog field such as `gold_included`, while retaining dynamic
access computation and durable ownership.

Advantages:

- removes repeated hard-coded SKU lists
- future catalog policy becomes data-driven
- still avoids per-user entitlement writes

Costs:

- likely requires a small additive migration/backfill
- requires an explicit default policy for future characters
- requires additional catalog authority tests

### Option 3: Per-user Gold-character entitlement table

Materialize one entitlement row per Gold user and character.

Advantages:

- explicit persisted access records
- straightforward direct lookup after materialization

Risks:

- subscription activation and expiration fanout
- stale entitlement risk
- increased account deletion and cache complexity
- unnecessary writes at large scale
- resubscription rematerialization

## W. Recommended Direction

Option 1 is the safest starting architecture, with Option 2 as a possible
catalog-policy refinement.

Recommended principles:

1. Keep permanent ownership exactly where it is.
2. Never create ownership rows for Gold access.
3. Reuse `goldMembershipForUser()` for membership semantics.
4. Add one shared server-side character-access predicate.
5. Represent temporary access separately from `owned`.
6. Apply the predicate to all character reads and mutations.
7. Preserve wardrobes and accessories after expiration.
8. Repair invalid active appearance transactionally.
9. Keep old-client capability filtering intact.
10. Keep refund/reversal logic limited to permanent sources.

## X. Implementation Checklist

After product approval:

1. Confirm production catalog rows with read-only queries.
2. Confirm all Gold membership states and reconciliation behavior.
3. Write backend integration tests first.
4. Define the access-state response contract.
5. Implement the shared backend access predicate.
6. Update collection, wardrobe, outfit, activation, and accessory paths.
7. Define and implement expiration repair behavior.
8. Preserve wardrobes and accessory ownership.
9. Add cache invalidation for membership and appearance transitions.
10. Update frontend temporary-access states and labels.
11. Update direct purchase UI according to product decisions.
12. Update Gold copy.
13. Add account-switching, historical-race, refund, and resubscription tests.
14. Verify old capability combinations.
15. Run backend integration tests against a dedicated test database.
16. Run `flutter analyze` and relevant Flutter tests.
17. Run the required mirrored-screen UI checklist.
18. Complete code review.
19. Deploy backend first.
20. Release coordinated iOS and Android builds.

## Y. Files Inspected

### Frontend

- `lib/models/character_wardrobe.dart`
- `lib/models/billing.dart`
- `lib/services/backend_api_service.dart`
- `lib/services/character_wardrobe_controller.dart`
- `lib/services/live_billing_controller.dart`
- `lib/services/billing_controller.dart`
- `lib/services/store_billing_client.dart`
- `lib/screens/tabs/shop_tab.dart`
- `lib/screens/character_wardrobe_screen.dart`
- `lib/screens/bara_plus_screen.dart`
- `lib/widgets/shop_character_card.dart`
- `lib/widgets/bara_plus_card.dart`
- `lib/widgets/bara_gold_ribbon.dart`
- `lib/widgets/accessory_preview_sheet.dart`
- `lib/tutorial/tutorial_preview_data.dart`
- `lib/preview/preview_billing_api.dart`
- `README.md`
- `DEPLOYMENT.md`

### Backend

- `prisma/schema.prisma`
- `prisma/migrations/20260704120000_add_character_slot/migration.sql`
- `prisma/migrations/20260909190000_character_wardrobes/migration.sql`
- `prisma/migrations/20260915150000_bara_gold_ownership/migration.sql`
- `prisma/migrations/20260908100000_bara_permanent_premium/migration.sql`
- `src/modules/shop/routes.js`
- `src/modules/shop/queries/getShopBootstrap.js`
- `src/modules/cosmetics/characterWardrobes.js`
- `src/modules/cosmetics/characterWardrobeState.js`
- `src/modules/cosmetics/shopCosmetics.js`
- `src/modules/cosmetics/getShopCatalog.js`
- `src/modules/cosmetics/purchaseShopItem.js`
- `src/modules/cosmetics/equipAccessory.js`
- `src/modules/cosmetics/accessoryCompatibility.js`
- `src/modules/cosmetics/repairCharacterWardrobes.js`
- `src/modules/billing/catalog.js`
- `src/modules/billing/queries/goldPolicy.js`
- `src/modules/billing/queries/bootstrap.js`
- `src/modules/billing/models/billingState.js`
- `src/modules/billing/routes.js`
- `src/modules/billing/commands/sync.js`
- `src/modules/billing/services/revenueCatProvider.js`
- `src/modules/billing/services/reconcile.js`
- `src/modules/billing/services/reconciliationWorker.js`
- `src/modules/home/getHomeRaceCard.js`
- `src/modules/social/queries/getPublicProfile.js`
- `src/modules/leaderboard/getLeaderboard.js`
- `src/modules/ranked/queries/getRanked.js`
- `src/modules/ranked/queries/getRankedV2.js`
- `src/modules/races/queries/getRaceDetails.js`
- `src/modules/tournaments/queries/getTournamentDetail.js`
- `src/shared/cache/redisCache.js`
- `src/shared/cache/derivedCache.js`
- `src/shared/cache/cacheKeys.js`
- relevant billing, character, wardrobe, catalog, compatibility, and cache docs

## Z. Commands Run

Read-only research commands included:

- `rg --files`
- `rg -n` searches across both repositories
- `find src/modules/shop`
- `sed` inspection of source, schemas, migrations, tests, and docs
- `git status --short`
- `git rev-parse HEAD`
- `git log --oneline --decorate`
- Gold, character, billing, RevenueCat, wardrobe, cache, race, and capability searches
- `flutter analyze`

Result:

```text
flutter analyze
No issues found!
```

No code was modified, no migration was created, no database rows were changed,
no deployment was performed, and no RevenueCat or App Store configuration was
changed.
