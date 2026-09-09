# Full-screen shop and character wardrobes

Status: APPROVED FOR IMPLEMENTATION — user authorized September 9, 2026, including removal of the Profile membership button. Supersedes the earlier four-category proposal. Architect: APPROVE (no remaining required changes). Game analyst: SOUND (no remaining required changes). UI-test-planner: checklist and implementation risks incorporated. Implementation is authorized. Production deployment, content mutations and uploads require separate authorization.

## Summary and user story
As a player I want a dedicated shop with a clear exit, a unified collection of owned and locked characters, and a wardrobe designed for each character so outfits fit the character and stay easy to manage.

The user selected a full-screen shop and then supplied these additions:
- Featured contains in-app purchases.
- Powerups remains its own section, retaining its behavior.
- Characters shows owned and locked characters together. Each owned character's card renders that character's saved outfit.
- Tapping a character opens a menu: purchase if locked, edit its outfit if owned.
- Accessories belong inside the relevant character's wardrobe, rather than a global top-level accessories destination.
- Start fresh with accessories that are not currently active; create designs appropriate to each character's anatomy. Preserve existing player ownership while identifying exactly what can be retired.

## Navigation and visual layout
- Fixed header: labeled Back control, SHOP title, existing coin balance/add action. Exit returns to the actual invoking app route.
- Shop-only fixed bottom navigation: Featured / Powerups / Characters. No app bottom navigation inside this route and no top-level Accessories destination.
- Remove the global Store / Inventory switch. Characters is one owned+locked collection. Keep a local Buy / Owned switch inside Powerups to retain its current store/inventory functionality. User confirmed a unified Characters collection; local Buy / Owned controls preserve Powerups functionality.
- Featured retains coin packs and Bara+ membership content, with existing localized billing offers and subscription terms. Coin/membership shortcuts open the relevant Featured anchor.
- Characters collection: show character artwork, character name, Owned or Locked status, and a distinct Active marker for the character currently used in the app. Owned and Active are different states. Locked characters show their base appearance; owned characters show their own saved outfits.
- Tap a locked character: character detail menu with current purchase/unlock eligibility, price and existing purchase confirmation. Retain ad-unlock paths where offered by the current catalog. Purchasing does not silently equip it.
- Tap an owned character: menu with Edit outfit and Use character actions. Editing an inactive character must not silently switch the active character.
- Edit outfit opens a dedicated wardrobe view within the shop route stack, titled for the character, with a clear return to Characters. Character/wardrobe controls are above the dressing-room preview, then compatible accessory choices below. No preview above navigation and no large preview on the collection landing page.
- Wardrobe behavior: preview changes locally; explicit Save outfit persists the selected character's outfit; Reset restores its saved outfit. Saving an inactive character does not activate it. Accessory purchases remain explicit purchases and are not undone by discarding an outfit draft. Back, bottom-tab navigation or shop exit with unsaved changes opens Discard changes / Keep editing; Reset returns to the last authoritative saved outfit. Buying does not close the editor or save the draft. Save stays disabled while a preview contains unowned items, with a clear Buy action; do not silently drop them from the submitted outfit.
- Owned character cards immediately reflect successful outfit saves. Every character retains a separate outfit when another becomes active. Default capybara is a first-class owned character with its own saved wardrobe.
- Preserve warm parchment cards, pixel typography/artwork, readable statuses, consistent button hierarchy, comfortable hit targets, day/night support and adaptive layouts.

## Profile membership entry removal — approved addition

Remove the membership/Bara+ button from the Profile surface. Remove its reserved spacing and obsolete tutorial target if present. Keep Home Shop and coin-add controls and Featured Bara+ content. Cover the real Profile screen and tutorial/preview mirrors on both iOS and Android. This is a placement-only addition; billing entitlements, pricing and existing backend endpoints are unchanged.

## Original UX fixes retained
- Coin packs and other merchandise share a consistent primary purchase-button treatment; actual localized real-currency prices and coin prices remain distinct. Bara+ retains required subscription/trial wording.
- Powerup tiles shrink to cosmetic density, retaining filters, sorting, ownership quantities, eligibility and existing detail/purchase/ad-unlock interactions. “Keep the same” is interpreted as keeping functionality; original request for smaller tiles remains in scope.
- Dressing-room layout groups avatar, concise item/status text, and actions instead of repeated identity text.
- Coin/Bara+ action success/error uses existing top-floating game toasts within the safe area. Emit once per operation; preserve busy/cancel/pending semantics and durable entitlement/pending state. Avoid stale messages after route exit or account changes. Keep Back reachable.

## Character-specific accessory policy and cleanup
- Wardrobes display accessories explicitly compatible with that character. Do not infer fit because an overlay can technically render.
- Distinguish item ownership, character compatibility, and character-specific art/placement. A jersey could have separately fitted capybara and corgi variants; a turtle needs a deliberately designed compatible version. A missing character variant must not stretch an unrelated sprite over that character.
- This implementation keeps existing per-item ownership unchanged and adds no new variants/SKUs. Future shared-design versus separately purchased variants will be decided in the content task before art/pricing; no economy numbers change here.
- Audit existing catalog and art references first. Enumerate IDs/SKUs, active, testOnly, earnOnly, ownership/equipment references, and appearance in billing rewards or tutorial fixtures. “Inactive” and “unreleased” are different: testOnly is not the same as active=false.
- User-confirmed cleanup scope: retire unused unreleased drafts from the future assortment, preserving currently released content, owned/equipped items, earned rewards and old-client rendering dependencies. Archive source artwork rather than deleting it as part of navigation work. Exact retirement list requires review before mutations.
- Do not delete existing ownership, purchase history, equipment, reward entitlements or assets required by shipped clients. Any affected legacy accessories need an explicit wardrobe compatibility/migration rule before restriction is introduced.
- No new shippable art is generated in this phase. Future art work must use accessory-art skill and its image-generation pipeline, fitted and verified per character.

## Existing implementation and implications
- `lib/screens/main_shell.dart:4828` already pushes ShopTab; preserve this origin-return behavior and dependencies. Audit Home coin shortcut, removal of the Profile membership shortcut and Settings shop tutorial in their current files.
- `lib/screens/tabs/shop_tab.dart:1554` owns the scaffold; category enum currently contains four destinations at line 97. Existing mode/category handling and preview composition around lines 1760 and 2026 assume a global wardrobe.
- `lib/screens/tabs/shop_tab.dart:3955` currently splits shop and inventory character lists; replace this with the confirmed unified character collection.
- `lib/widgets/shop_product_grid.dart` currently couples Featured and Powerup geometry; decouple their sizing so smaller powerups do not shrink billing controls.
- `lib/widgets/coin_pack_offers.dart` and `lib/screens/bara_plus_screen.dart` own inline billing messages; reuse info_toast/error_toast with operation and account/controller identity guards. Include embedded Featured and retained standalone billing screens.
- `lib/preview/billing_preview_app.dart` embeds ShopTab inside a host with its own navigation. Push the real shop over an offline host so only shop navigation is visible and exit restores the host.
- Backend `prisma/schema.prisma` defines UserEquippedAccessory uniquely by userId + slot, not by character. Existing ShopTab preview composes one equipped map and swaps its CHARACTER row. Independent saved character outfits require backend-supported persistence and migration/compatibility design; this is no longer a frontend-only layout change.
- Backend ShopItem already has active/testOnly/earnOnly and server-owned compatibility metadata; inspect existing handlers before proposing overlapping concepts. Source inspection does not establish the current production catalog or production API readiness.

## API contract — additive character wardrobes v1

All new paths are registered in `src/modules/shop/routes.js` (createShopBootstrapRouter, mounted before the legacy router in `src/app.js:202–203`), using injected queries/commands, asyncHandler and AppError.meta for response extras. Queries/commands call cosmetics public exports; cosmetics owns DB model access. Do not add new handlers to legacy `src/routes/shop.js`. Reuse authentication and release-channel/render-capability middleware. New route semantics are permanent (`contract: "character-wardrobes-v1"`), not a rollout switch. Do not introduce environment controls or change the required inputs/outputs of existing catalog, bootstrap, purchase, ad-unlock or equipment endpoints. Register static paths before dynamic SKU routes.

### Identities, bounds and value types
- `characterKey` is literal `default` for capybara or an opaque CHARACTER ShopItem ID. It is not a mutable asset key, SKU or display name. Default is implicitly owned; do not fabricate a ShopItem purchase.
- Each outfit has exactly five slots: HEAD, FACE, NECK, BACK, FEET. CHARACTER is never an outfit slot. Values are owned accessory ShopItem IDs or null.
- `outfitRevision` and `appearanceRevision` are nonnegative safe integers. Missing/malformed revisions are an unavailable editing state, never silently interpreted as permission to overwrite.
- Collection/wardrobe queries: `limit` default 24, integer 1–48; `cursor` opaque base64url versioned keyset cursor, maximum 512 bytes; `localDate` optional, handled by existing ad-unlock date policy. Deterministic order: default only on the first Characters page, then `(sortOrder,id)`; accessory pages `(sortOrder,id)`. Cursor binds resource/filter/channel and the last tuple; invalid cursor/limit returns 400. Fetch limit+1 to determine nextCursor. No offset pagination, silent truncation or global per-user lists.
- Character row source is active purchasable characters UNION owned character rows (including earned/unlisted ones), always respecting release/art visibility. De-duplicate by ID. Owned inactive items remain represented as unavailable; no purchase or reactivation. Default is always present. A hidden active character is not leaked: envelope `activeCharacterKey:null` plus `activeCharacterVisible:false`, preserving its server state until an explicit user activation.
- `ShopItem` uses the exact existing serializer fields: id, sku, name, description (nullable), slot, priceCoins (server-priced integer), assetKey, renderMetadata (nullable); optional bobble, assetVersion, assetUrl, basePriceCoins and discountPercent. Preserve metadata and remote asset identity verbatim. No character-specific rendering override format is introduced here.
- `EquipmentItem` uses existing serializeEquippedAccessory fields: id, sku, name, slot, assetKey, renderMetadata, optional bobble/assetVersion/assetUrl. Every query feeding it selects the existing required metadata.
- `adUnlock` is null when unavailable, otherwise exactly `{maxShortfall,coinsPerAd,maxAds,dailyCap,remainingToday}` with nonnegative integers from existing buildAdUnlockBlock, once per request. Do not recalculate constants in Flutter. Both member pricing and ad policy reuse existing services once per request, not once per tile.

### GET /shop/characters?limit=24&cursor=...&localDate=YYYY-MM-DD
200 example with only the implicit default row (illustrative revisions, not catalog pricing):
```json
{
  "contract":"character-wardrobes-v1",
  "appearanceRevision":7,
  "activeCharacterKey":"default",
  "activeCharacterVisible":true,
  "coins":0,
  "adUnlock":null,
  "characters":[{
    "characterKey":"default","name":"Capybara","item":null,
    "owned":true,"active":true,"canPurchase":false,"canActivate":true,"canEdit":true,
    "availability":"available",
    "outfit":{
      "revision":2,"editable":true,"hasHiddenItems":false,
      "slots":{"HEAD":null,"FACE":null,"NECK":null,"BACK":null,"FEET":null},
      "items":[],"unavailableItemIds":[]
    }
  }],
  "nextCursor":null
}
```
Non-default rows have `item: ShopItem`. All row keys above are required. `availability` is available or unavailable. `owned:false` implies `outfit:null`, `active:false`, `canActivate:false`, `canEdit:false`; `canPurchase` follows the existing purchasable row policy, not coin sufficiency. Locked characters can show their normal purchase/ad eligibility in the menu. For owned rows, outfit items are their own saved outfit, never another character's projection. Selected outfit items are fully expanded separately from catalog pagination. No new wardrobe row is created by GET or purchase.

### GET /shop/characters/:characterKey/wardrobe?limit=24&cursor=...&localDate=YYYY-MM-DD
Only owned, visible characters (including default). 200:
```json
{
  "contract":"character-wardrobes-v1",
  "appearanceRevision":7,"activeCharacterKey":"default","activeCharacterVisible":true,
  "characterKey":"default","name":"Capybara","active":true,"canActivate":true,
  "outfit":{
    "revision":2,"editable":true,"hasHiddenItems":false,
    "slots":{"HEAD":null,"FACE":null,"NECK":null,"BACK":null,"FEET":null},
    "items":[],"unavailableItemIds":[]
  },
  "coins":0,"adUnlock":null,"accessories":[],"nextCursor":null
}
```
Each accessories entry is `{item:ShopItem,owned:boolean,canPurchase:boolean,canPreview:boolean,canSelect:boolean,fit:"approved"|"legacy-preserved"|"preservation-only",unavailableReason:null|"inactive"|"incompatible"}`. Query compatible purchasable accessories UNION owned/retained accessories needed for this character; include owned earnOnly rows without making them purchasable. Inactive owned items are visible but disabled; preserve existing equip eligibility. Outfit.items is EquipmentItem[] of length at most five, independent of accessory page. Cross-item tag conflicts remain server enforced. `approved` permits normal selection; `legacy-preserved` is a current/saved grandfathered selection that may be retained; `preservation-only` is an owned item shown in Other owned items with canSelect=false and unavailableReason=incompatible. No frontend inference from fit overrides canSelect. `canPreview` independently permits a local visual draft: true only when character/accessory are active, fit is approved or legacy-preserved, and accessory is owned or approved+purchasable (not earnOnly). Compatible unowned sale items have canPreview=true/canSelect=false; Save stays blocked until ownership is verified. Current saved legacy-preserved owned items can preview; preservation-only/inactive/hidden rows cannot start a preview. Missing canPreview defaults false; inspection/purchase remain available according to their own permissions without inferring draft eligibility.

Saved/current combinations inherited from the legacy client remain readable and may be retained even without newly approved fit metadata. They do not grant selection rights to unrelated unowned items. Hidden test/remote item IDs are redacted to null in their slot values and omitted from items; set hasHiddenItems=true and editable=false so sending a complete visible-only outfit cannot silently remove them. Do not expose hidden item IDs. An owned inactive character also returns editable=false/canActivate=false. The UI explains unavailable state without deleting a saved outfit.

### PUT /shop/characters/:characterKey/outfit
Request is a complete slot replacement; all five keys required, no unknown keys or duplicates across non-null values:
```json
{"expectedOutfitRevision":2,"slots":{"HEAD":null,"FACE":null,"NECK":null,"BACK":null,"FEET":null}}
```
200 (no-op example, resaving the empty outfit returned above):
```json
{
  "contract":"character-wardrobes-v1","characterKey":"default",
  "appearanceRevision":7,"activeCharacterKey":"default","activeCharacterVisible":true,
  "outfit":{"revision":2,"editable":true,"hasHiddenItems":false,"slots":{"HEAD":null,"FACE":null,"NECK":null,"BACK":null,"FEET":null},"items":[],"unavailableItemIds":[]},
  "appearanceChanged":false,"equipped":{}
}
```
`equipped` is the current active equipment map using the existing serializer/filtering. If inactive outfit saved, appearanceChanged=false and appearanceRevision does not advance; current equipment is unchanged. If active outfit changed, atomically update its projection and appearance revision. An identical request matching current state with the matching revision is a no-op: revisions do not advance. Validate ownership, item slot, active/channel/render eligibility, species fit and pairwise conflicts inside transaction before any mutation. Unchanged grandfathered entries can be retained; cannot reintroduce a removed grandfathered entry unless it has approved fit. Removal is always allowed for visible existing entries. No coins, grants, ads or purchase writes occur here.

### PUT /shop/active-character
```json
{"characterKey":"default","expectedAppearanceRevision":7,"expectedOutfitRevision":2}
```
200 has the same envelope as outfit PUT, with target outfit and the complete resulting active `equipped` map. Atomically activate only the target's saved outfit, never an unsaved local preview. Appearance revision advances if public equipment changed; outfit revision changes only if its slot content changes (normally activation does not change it). Re-selecting identical active state is a no-op. Validate the entire saved outfit before activation; inactive/unavailable entries or pairwise conflicts cause an error listing visible invalid IDs, with no partial equip or silent stripping. UI offers Edit outfit to fix it. A user may edit/save inactive wardrobes without ever activating them.

### Errors and retry semantics
All new-route errors use existing top-level style. Example:
```json
{"error":"Your outfit changed on another device.","code":"OUTFIT_CHANGED","current":{"characterKey":"default","outfitRevision":3,"appearanceRevision":8,"activeCharacterKey":"default"}}
```
`current` above is required only on revision conflicts and filtered for visibility. Specific codes:

| HTTP | Code | When / UI |
|---|---|---|
| 400 | INVALID_WARDROBE_REQUEST | Bad key syntax, cursor, limit, revision, slots, duplicate item IDs; no writes |
| 401 | existing authentication error | Sign-in/session handling unchanged |
| 403 | CHARACTER_NOT_OWNED / ITEM_NOT_OWNED | Existing visible character or accessory unowned; no grant |
| 404 | CHARACTER_NOT_FOUND | Missing or channel/render-hidden character; no hidden metadata |
| 409 | OUTFIT_CHANGED | Stale expected outfit revision; retain draft, refetch, show Review changes / Reload saved |
| 409 | APPEARANCE_CHANGED | Stale expected active appearance revision; refetch before explicit retry |
| 409 | ITEM_UNAVAILABLE | Inactive, hidden, wrong slot, or removed item; optional visible itemIds, no hidden IDs |
| 409 | CHARACTER_FIT_CONFLICT | Accessory not selectable/retainable for this character; visible itemIds |
| 409 | ACCESSORY_CONFLICT | Existing pairwise conflicts; preserve conflictingItemIds/conflictingSlots semantics |
| 409 | WARDROBE_NOT_EDITABLE | Hidden outfit items or unavailable character prevent safe full replacement |
| 429/503 | WARDROBE_BUSY | Existing rate limit / exhausted bounded DB retry; keep draft |
| 500 | existing Internal server error | Keep last good state and show retry; never report saved |

Validate syntactic request before DB access; under lock check resource visibility/ownership, revisions, then slot eligibility and conflicts. Concurrency mismatch never triggers silent automatic overwrite. A network timeout is an unknown result: refetch; if the complete submitted outfit equals authoritative state, UI may report `Outfit is saved`; otherwise retain draft and ask to review. Activation similarly reconciles target and complete expected saved outfit. No durable replay ledger is promised for these zero-cost state assignments; existing purchase/ad endpoints keep their durable idempotency keys and verification unchanged. Do not automatically replay a paid action with a new key.

### Older backend behavior
A bare route 404/405 or absent/unknown contract on the collection endpoint means wardrobe v1 is unavailable. Keep Featured and Powerups usable; render Characters with existing safely parsed catalog and base/current previews where known, and a clear retry/unavailable state for Edit outfit / Use saved outfit. Do not synthesize per-character saves through legacy slot-by-slot writes. Ownership/purchase uses existing endpoints, but lack of wardrobe data is never labeled a saved empty outfit. Network/500 errors are retryable failures, not permanent unsupported capability. Only collection absence establishes unsupported routing; a specific character 404 remains a character error.

## Data model, concurrency and migration

### Additive schema
1. `User.appearanceRevision Int @default(0)` (nonnegative DB check). Existing public/auth serializers do not change unless new endpoints explicitly expose it.
2. `CharacterWardrobe`: UUID PK; userId FK to User with delete cascade; characterKey text; characterShopItemId nullable FK ShopItem with delete restrict; revision integer default 0; updatedAt. Unique `(userId,characterKey)` and SQL check: default key iff FK is null, otherwise key equals the referenced ShopItem ID text. Only CHARACTER items allowed via service validation. Index characterShopItemId. Do not change UserShopItem uniqueness or grant a default item.
3. `CharacterWardrobeItem`: wardrobeId FK cascade, slot AccessorySlot restricted by CHECK to the five non-CHARACTER slots, shopItemId FK restrict. Primary/unique `(wardrobeId,slot)`; unique `(wardrobeId,shopItemId)`; index shopItemId. All item ownership/slot/type checks remain server authoritative.
4. `ShopItemCharacterFit`: accessoryShopItemId FK restrict, characterKey, characterShopItemId nullable FK restrict using the same default/opaque-ID check. Unique `(accessoryShopItemId,characterKey)`, index `(characterKey,accessoryShopItemId)`. Explicitly approved selection mapping, not new asset overrides or new entitlements. Existing pairwise `compatibility` JSON remains unchanged.
5. Preserve the existing UserEquippedAccessory table as the **active/public source of truth and projection**. Stored inactive wardrobes are authoritative for inactive looks; the active wardrobe mirrors this table transactionally. Existing readers do not query wardrobes.

SQL type names/FK/index identifiers follow existing migration conventions. Do not use mutable asset keys as relational identity. Add fixtures to test account-deletion cascades and disposable load-test cleanup; audit scripts/reset-app-review.sql for new saved state so review resets do not leave dormant outfits behind.

### Legacy fits and future designs
Existing released accessory ownership is preserved. Seed explicit fit rows for verified character/item combinations via an audited manifest; do not infer anatomical fit from missing metadata. For the initial wardrobe rollout, legacy compatibility also permits the player's actual saved/current combinations, without stripping their outfit. Owned legacy accessories without approved fit or a saved combination remain visible in a dedicated `Other owned items` group with unavailable guidance, not silently lost; current old-client equip paths remain working. The audit must give each released item a verified default-capybara fit or an explicit preservation-only classification, including earned cosmetics. New species-specific art/items are a separate content task and cannot be introduced merely by adding fit rows; no stretching/asset override system is built here.

### Shared writer transaction
All runtime equip/unequip paths, new outfit save/activation and operational compatibility repair use one cosmetics transaction helper. Lock the `users` row first (`FOR UPDATE`), then read active projection and at most source/target wardrobes. Acquire any second wardrobe lock in stable characterKey order. Validate all required ownership/items in bounded sets. Compute full result in memory; compute a bounded slot diff and issue set operations only for changed/deleted/inserted slots, never one DB command per UI tile. Preserve unchanged UserEquippedAccessory IDs and updatedAt timestamps: cleanupAccessoryCompatibility chooses precedence by newest updatedAt, then ID. Do not delete/recreate the whole active projection for a one-slot edit. Test that unrelated edits retain repair ordering. Increment only changed state revisions and return authoritative state inside the transaction. Commit before one best-effort presentation and auth/me cache invalidation when active appearance changes; inactive saves invalidate no public appearance caches. Existing TTL/miss/unavailable-Redis fallbacks remain intact. No extra step-sync work, race jobs, notifications or ownership grants.

Initialization under the same lock captures the actual current projection into its active-character wardrobe before the first changed write; untouched inactive wardrobes read as empty with revision 0. GETs synthesize the active outfit from projection without writes. On a legacy character switch, preserve current accessory carry-over: checkpoint source wardrobe, change only CHARACTER as before, then overwrite the target wardrobe with the carried outfit. This is explicitly an old-client action, not a restoration operation. Increment the target revision if contents changed and appearanceRevision if active state changed. Other wardrobes stay intact. Legacy non-character equip/unequip synchronizes only the active outfit. Null CHARACTER means default capybara and still carries accessories. Preserve existing old error statuses/payloads and no new required revision parameters. New endpoints use restore-on-activation semantics; old endpoints retain carry-over semantics.

Concurrent new save versus legacy equip, two activations, null unequip and compatibility repair serialize under the user lock. Revision checks occur after acquiring it. Ownership-only purchase/grant paths do not create wardrobes; shared user locking is reused where the existing pricing/grant path already requires it. Existing owner-mutation eligibility reads may use bounded shared item locks where needed to avoid racing admin policy/retirement; deterministic ordering and tests are required. No new broad locks or unbounded transaction retries.

### Migration, reconciliation and rollback
- Add tables/column first; existing workers ignore them. No irreversible data rewrite or deleted rows. Do not rewrite active equipment during migration.
- Lazy initialization is the default; no whole-population eager wardrobe materialization. A read-only audit compares saved active rows to projection and counts anomalies using user-ID pages of at most 200.
- Provide resumable repair with last-user-ID checkpoint and bounded batches. For users already materialized, reconcile only active saved rows from the current projection while holding the same user lock; never restore projection from a stale wardrobe. Bump affected outfit/appearance revisions so stale clients conflict. Missing inactive wardrobes stay empty. Current-owner/release filtering is applied for display, not destructive repair.
- Deploy as two concrete code releases, without runtime flags: **A, compatible writers**, contains additive schema, locking/null handling, dual-write/revisions and repair tooling but no new v1 routes; **B, wardrobe endpoints**, adds the four routes only after A is fully deployed. Drain old in-flight cosmetics writers, ensure all relevant processes now run A, complete reconciliation, then deploy B. A+B mixed workers are safe because both share the writer protocol. Maintain normal capacity of exactly two HTTP workers; use the existing deployment drain/reload procedure, not an extra replica. Initial app release follows B readiness.
- Routine rollback target for B is A, never the pre-wardrobe writer implementation. Existing newer apps temporarily see the documented unsupported/read-only wardrobe fallback on A; legacy equipment still updates saved state/revisions. Keep additive data intact.
- If an exceptional separately authorized rollback restores pre-A writers, v1 routes must remain absent until the full A drain/upgrade/reconciliation boundary is repeated. Do not expose B endpoints on a mixed pre-A/B fleet. Reconcile active saved rows from projection under locks; bump affected revisions. Preserve inactive wardrobes and all ownership/history. No schema-drop rollback or runtime exposure switch.
- Test A-only, mixed A+B and rollback-to-A behavior through real HTTP/test DB fixtures, plus detection/reconciliation of a simulated pre-A null-unequip write. Production verification must identify all cosmetic writer process versions and prove drain completion; two healthy PM2 processes alone are insufficient.

### Bounded work and cache contract
Source inspection: old getShopCatalog has four top-level reads (user/items/owned/equipment) plus membership pricing and ad-policy reads; item and ownership lists are unbounded today. This is a baseline observation, not a measured round-trip count.

New endpoints must not compound it with one call/query per character. Every revision-bearing GET uses one read-only REPEATABLE READ transaction (or a demonstrably single SQL snapshot) for active identity/revision, saved slots, ownership, visibility and expanded item records. Multiple independent READ COMMITTED reads are prohibited: old slots paired with a new revision can cause a silent lost update. Pricing/ad quotes may be advisory reads outside that snapshot and are revalidated by existing purchase commands. Add deterministic concurrent GET/save/activation integration coverage.

Collection: one bounded character-page query, one set ownership query if not joined, one joined saved-outfit+item query for page IDs, one active projection/revision read, and shared pricing/ad-policy work once per request. Wardrobe: one character/ownership lookup, one outfit/projection read, one bounded item page with joined fit/ownership, shared pricing/ad-policy once. Source/target outfit writes touch at most two wardrobes and five accessory slots each. Estimated implementation budget: at most six domain SELECT statements for a collection page and seven for save/activation, excluding BEGIN/COMMIT, explicit lock statements and unchanged membership/ad-policy internals; measure and report actual totals separately before claiming performance. JSON aggregate/join reads should avoid Prisma relation-load N+1 behavior.

Personalized collection/wardrobe responses read PostgreSQL and are not shared-cache entries in this release. New static fit lookups need no new Redis cache. Reuse existing post-commit appearance invalidations only. Audit query plans for `(userId,characterKey)`, `(characterKey,accessoryShopItemId)`, ownership joins and ordered character/accessory pagination; add a matching `(slot,sortOrder,id)` ShopItem index only if local EXPLAIN shows it is needed, with write overhead documented. Operational scans use bounded pages/checkpoints; no query inside a loop per accessory.

## Scope and confirmed decisions

In scope: full-screen three-section shop; unified owned/locked Characters; independent persisted outfits and explicit activation; compatible accessory selection; preservation and retirement audit tooling; original visual/billing cleanup; offline preview/tutorial mirrors; both platforms; compatibility/migration/test coverage.

Confirmed by user: remove Store/Inventory switching from Characters; retire unreleased designs while preserving currently released and owned items. Use the local Buy/Owned Powerups switch to preserve existing functionality. Save/Reset/discard flows above are the concrete implementation design for review.

This release creates no new accessory SKUs, prices or artwork and retains existing global `(userId,shopItemId)` ownership exactly. It does not create bundled multi-character grants or duplicate ownership records. The optional future question about separately purchased character variants versus shared design bundles belongs to the subsequent content task; neither is implemented implicitly here. Fit mapping changes selection eligibility, not entitlement scope. No open product decision blocks this defined implementation scope.

Out of scope: production retirement execution/deployment, app uploads, pricing/drop-rate changes, deleting source/bundled art, new rendering formats, new SKU/variant grants, or release flags. Retirement execution is a separate reviewed production operation under backend AGENTS.md, not a hidden schema migration side effect.

## Retirement and fit audit deliverables

Produce backend `scripts/audit-character-wardrobes.js` and a dated report using SELECT-only access when executed. Report counts and IDs/SKUs without user PII; cursor-page items/users, aggregate reference counts with bounded joins. Include active/testOnly/earnOnly/remoteOnly, ownership, active/saved equipment, purchase requests (including replay histories), ad grants awaiting consumption, reward/billing/ranked references, CDN/bundled references and tutorial fixtures. Check **dynamic reward-pool eligibility**, not only literal references: current getUnownedAccessoryPool includes all active, non-testOnly, non-earnOnly, non-CHARACTER items.

Classify every item as Preserve released / Preserve owned-or-referenced / Candidate unreleased-unused / Needs investigation. Only Candidate rows may enter an explicit reviewed retirement manifest; unknown historical release status is Needs investigation, never proof of unreleased status. No wildcard `testOnly => retire`, no deactivation of reward-pool members, powerups or characters. Deactivated rows remain in history and ownership tables; preserve files needed by frozen clients. Exclude candidates from future seed/catalog authoring using a versioned content retirement manifest so reseeding cannot reactivate them. Any eventual apply command must recheck candidate conditions and expected row versions under transaction locks, abort on changed references, and require separate production authorization. Preparation/dry-run is part of implementation; execution is not.

Create `data/character-wardrobe-fits.json` as an explicit permanent content mapping validated against real IDs/SKUs and character slots. It lists verified approved fits and preservation-only legacy classifications; no default species inference. Dry-run reports missing earned/released items. Fit migration must not reject/strip an existing active or saved combination. Review the concrete mapping and retirement report before shipping them; actual art fit must be manually checked in both clients. No new images are created by this task.

## Economy and entitlement invariants

Game-analyst review requires all of the following:
- Save/activate/preview/reset/discard: zero coin balance, transaction ledger, reward, ad-consumption, subscription or ownership changes. Forged unowned items/character fail atomically. Default capybara is implicitly owned.
- Existing prices use the same server memberDiscount/priceFields calculation, expected-price validation and durable purchase/ad idempotency. Already-owned coin purchases preserve their zero-extra-charge behavior; moving between wardrobes cannot double-charge or reset ad limits.
- Daily accessory reward pool stays global and unchanged. Neither active character, wardrobe draft, fit relation nor owned-character set filters reward selection. No new reward reroll/fallback behavior. Powerup/character unlock eligibility stays server authoritative.
- Owned earned/ranked/Bara+ accessories are returned through ownership joins even though they are absent from sale catalogs. Grant IDs/SKUs retain their meaning. Inactive/hidden eligibility continues to follow existing rules; preservation does not turn an inactive item into a purchasable item.
- For identical actions, source/sink delta is zero. No absolute production EV/affordability claim; UX-induced purchasing frequency is unmeasured. Future variant pricing/bundles require fresh economy review before prices or seeds are committed.

Verified local source findings are recorded in `docs/economy.md`, Wardrobe planning verification — 2026-09-09. Production prices, pools and ownership were not queried during planning.

## Frontend implementation contract

### Files and state ownership
- Keep `lib/screens/tabs/shop_tab.dart` as route entry/public constructor for existing callers. Extract shop category bar/character cards and `lib/screens/character_wardrobe_screen.dart` rather than growing one monolithic state class.
- Add defensive typed models in `lib/models/character_wardrobe.dart` and four methods in `lib/services/backend_api_service.dart` for the specified endpoints. No direct HTTP calls in widgets. Add a route/session-scoped controller in `lib/services/character_wardrobe_controller.dart`; retain lists keyed by characterKey and ignore async completions from replaced auth/controller generations.
- `ShopTab` fixed header and shop bottomNavigationBar use actual measured safe-area geometry, replacing the inferred 77.5px main-tab allowance. Preserve `_openShop` route push, Home coin focus, injected services/session ad controllers and onShopChanged callbacks. No app bar stacking.
- Characters collection loads one page on entry, fetches more on scroll, and preserves scroll/selection within this shop session. Character list merges by key; reset accumulated collection pages when authoritative appearanceRevision changes so old-page active markers cannot coexist with a new-page marker. Preserve dirty editor drafts independently. Invalidate relevant card/wardrobe after purchase/save and refetch membership-priced data after billing changes. New purchased item ownership refreshes from the existing result/authoritative read without equipping it. Do not refetch on every tile tap or animation frame.
- Wardrobe is a child route with character name, Back to Characters, Save/Reset above the preview and item controls. The shop category bar remains present below it; selecting another category follows discard handling, returns to shop and selects that tab. System back and header back pop wardrobe before exiting shop. A locked-character menu can be a sheet; owned menu presents Edit outfit and Use character. Use character is disabled when already active or pending.
- Featured/Powerups have no redundant outfit strip. Collection shows compact saved-look thumbnails; dedicated wardrobe retains usable avatar art and grouped status/action text. Existing asset metadata/per-animal placement rendering is reused. New wardrobe-specific art overrides are excluded.
- Keep baseline compact grid breakpoints: three columns below 360 logical pixels, four at 360–599, six at 600+. Reduce columns further when large text would clip required names or controls. Minimum interactive target 48 logical pixels. Character art and actions must not require text to shrink below legibility. Featured coin/membership cards can remain larger and equal to each other; Powerups match cosmetics at standard text scale.
- Preserve sort/filter/ad/detail purchase interactions and tutorial completion semantics. Purchase pending overlay remains non-dismissible; header/system back must not cancel an in-flight coin purchase. Other sheets dismiss first. UI loading does not freeze unrelated navigation except transaction protection already present.

### Loading, errors, draft safety and degraded data
Collection/wardrobe controller states: initial loading, loaded, paging, stale-with-refresh-error, empty, unsupported, session-expired. Keep Back/category controls reachable. Empty Owned powerups has an explicit prompt to Buy; empty compatible wardrobe shows the character preview and “No accessories for this character yet.” Missing/default character item metadata uses built-in capybara identity; malformed unknown character rows are skipped with a retry state if no valid data remains. Missing ownership defaults false and disables paid/equip actions until verified. Unknown slots are ignored for display but make a full outfit uneditable; never silently submit a partial parse as a full replacement. Missing asset resolves through existing safe remote/bundled fallback without claiming the item is unavailable for purchase solely because an image is loading.

Keep `saved`, `draft`, `outfitRevision` and `appearanceRevision` separate. Server refresh must not overwrite a dirty draft. Conflict dialog offers Reload saved (explicit discard) or Keep editing after reviewing changed state; do not automatically rebase and save. If save result is unknown, compare against a fresh authoritative response before claiming success. On app restart, unsaved drafts may be discarded; successfully saved outfits persist across devices. Signing out clears local personalized state and prevents another account's toast/outfit from being applied.

### Billing results
Refactor CoinPackOffers and BaraPlusBody to consume the result of each user operation, not replay `snapshot.message` on every build. Current BillingResult has only success/message (`lib/models/billing.dart:102`), so introduce an additive typed disposition (success/error/cancelled/pending/notice) with a backwards-compatible constructor default derived from success when disposition is omitted, and propagate it through live/preview billing adapters; do not infer cancellation by parsing English messages. Keep snapshot pending/entitlement state durable and its contextual loading UI. Only completed success/error creates the corresponding game toast; canceled checkout produces no error toast. Pending shows contextual progress with optional single notice; the later terminal result is delivered once to the active matching session. Maintain operation identity/deduplication within the billing session for asynchronous pending completion; no toast replay on reopening the shop. Legal/manage/restore informational actions use notice disposition.

Reuse existing game toast visual design but expose an optional safe top-offset/anchor so shop messages appear below its measured header and never block Back. Do not shift unrelated screen toasts by changing a global constant. Dispose/remove route-owned toast entries when the route/session ends, keeping existing helper call sites source-compatible. Cover Featured, GetCoinsScreen and standalone BaraPlusScreen via the offline harness, including delayed checkout completion after leaving.

### Offline preview and tutorial mirrors
- `lib/preview/billing_preview_app.dart`: push ShopTab over the preview host instead of embedding it above the host bar; keep sample-account controls accessible from the host or a preview-only control affordance, and restore host on exit. Preview Shop/Coins/Membership entry modes all use real routes and focus anchors.
- `lib/preview/preview_billing_api.dart`: add independent saved outfits, active selection, revisions, locked/owned/default characters, earned/unavailable items, conflicts and late-result fixtures. No network fallback; billing remains simulated.
- Rewrite ShopTab tutorial orchestration: current `_tutorialTargets` requires all four old targets mounted before startup. New route-aware sequence: category bar → Characters card/menu → owned default wardrobe controls/preview → accessory grid or empty state → return/exit. Ensure mounted target/layout before each spotlight; do not rely on removed shop-segment-control/shop-category-pills. Tutorial interactions must not buy/equip/save real items. Reset draft on tutorial exit. Keep skip/back/first-entry completion usable.
- Settings View Shop Tutorial already pushes a real ShopTab with billing disabled; cover this separately from the general tab tutorial. `lib/tutorial/tutorial_real_screens.dart` hand-copies the main WoodenTabBar and Home shop beat; keep those as app navigation. Demo race tutorial contains no ShopTab.
- Home/profile/race/leaderboard/friend/tournament appearance readers keep existing active equipment payloads. Verify only successful active save/activation changes them; inactive editing must not affect public art. Keep character field filtering for old readers.

## Ordered implementation plan after spec approval

Spawn exactly backend-developer and frontend-developer as required by spec-feature. They are not alone in the repositories and must preserve unrelated edits. Backend owns the contract and schema; frontend begins production logic only after backend contract tests lock the schema/JSON behavior. Both can prepare their failing tests first against the written contract.

1. Backend: verify dedicated test DB connection, add failing real-HTTP integration suites for the endpoints, migration defaults, legacy null/non-null/carry-over compatibility, ownership/earned items, hidden items, revisions and reward invariants. Capture failing results before business logic. Add structural/migration tests only where real HTTP cannot express the property.
2. Backend: implement additive Prisma migration, `src/modules/cosmetics/characterWardrobes.js` transaction/read helpers (split read/write modules if needed), new injected shop queries/commands and router handlers in `src/modules/shop/routes.js` plus public exports in `src/modules/shop/index.js` and `src/modules/cosmetics/index.js`, shared equip/unequip synchronization, and source-of-truth repair/audit scripts. Preserve serializers and cached appearance shape. Update fixture/account reset paths. Add indexes based on targeted plans.
3. Backend: lock exact JSON contract with passing public-path integration tests and sanitized fixture responses; publish to frontend agent. Do not alter request shape afterward without coordination and updating this spec.
4. Frontend: write failing real-screen/route tests, then typed parsing/controller/route/grid/wardrobe implementation, existing purchase integration, typed billing feedback, preview fixtures and route-aware tutorial. Preserve existing test intent; report superseded expectations listed below explicitly.
5. Backend: finish read-only retirement/fit tooling and static manifests; run dry-run tests locally. Produce reviewable report, concurrency evidence and measured request query/write totals, including shared pricing/ad/cache work. Production audit/apply/deploy remain separately authorized operations.
6. Run code-reviewer on combined implementation after both agents finish. Fix required findings and rerun affected tests. No implementation work or implementation-agent spawning happens during this planning task.
7. Verification: flutter analyze clean; relevant Flutter suites then full flutter test once; diagnose failures per suite. Backend npm run test:unit / npm run test:integration (never bare npm test), only verified test DB. Manual checklist delivered for both platforms. No builds/uploads requested; if later authorized, README release configuration is authoritative and both artifacts are required.

## Tests-first acceptance matrix

| Public path / surface | Required evidence |
|---|---|
| Character collection | Default plus owned/locked/earned/unlisted rows; own saved outfits; correct active marker; deterministic multi-page de-duplication; page limits; channel/remote visibility |
| Wardrobe GET | Selected equipment independent of page; null/missing-safe client parsing; earned and legacy-preserved items; hidden-item read-only behavior; approved fit selection |
| Save and activation | Empty/default, each slot, duplicate/wrong-slot/unowned/inactive/hidden/pairwise/fit rejection, atomic no partial writes, inactive save versus active projection, no-op revisions, restart/cross-device persistence |
| Concurrency and retries | Save vs legacy equip/unequip; two activations; CHARACTER null; conflict refetch without draft loss; lost-response reconciliation; repair race; account/controller change |
| Frozen clients | Old X-Client-Features headers and exact legacy response shape, unchanged carry-over, no CHARACTER leaking as accessory, null equip path, no new required params |
| Economy | Unowned forged save fails, zero wallet/ledger/grant/ad writes on save/activation, already-owned purchase remains zero-charge, same purchase key across navigation, same reward pool/result eligibility across active characters and drafts |
| Public appearance | Real Home/auth/profile and representative race/leaderboard/friend/chat responses show active outfit after commit/invalidation; inactive edits leave all unchanged; cached and uncached parity and Redis failure |
| Routes and placement | Three shop sections/no duplicate nav, all entry focus routes and return origins; child wardrobe back/discard; compact grid/large text/safe areas; locked/owned menu actions |
| Billing | Success/error once; canceled neutral; pending then terminal; retry/restore/manage, localized prices and unchanged terms; disposal/account switch; standalone/Featured parity |
| Tutorials/preview | Real offline host route; no network; new targets mounted per step; first-entry and Settings replay; sample actions cannot mutate real accounts |
| Data/migration | No GET writes, lazy init/no eager grants, preserved ownership/history/FKs, delete/reset fixtures, bounded checkpoint repair, migration from old schema; no reward-eligible retirement candidate |

Protected old-layout assertions explicitly surfaced for replacement on spec approval:
- `test/batch_2026_08_09_shop_spacing_test.dart:98`: old global mode/category 8px spacing → fixed header, local Powerups mode and bottom navigation geometry.
- `test/shop_featured_category_revision_test.dart:47,73,94`: old four-pill visibility and Featured=Powerup size → three destinations, coin=membership sizing and powerup=cosmetic density at the same 320/390/800 widths.
- `test/shop_tab_store_inventory_test.dart:440`: four simultaneously mounted tutorial targets → route-aware target/step mounting with completion/skip coverage.
- `test/shop_dressing_room_test.dart:633`: preserve 3/4/6 grid breakpoints, minimum 48px targets and useful avatar/action geometry on the new wardrobe route. Preserve the 210–250px preview baseline at normal text scale where applicable; allow expanded responsive height for large text with stronger non-overlap checks.
- `test/support/shop_navigation.dart`: mechanically adapt helper navigation; do not weaken purchase/equip/ownership assertions. `test/unified_shop_test.dart`, `test/billing_preview_integration_test.dart`, `test/billing_components_test.dart` and `test/billing_preview_flows_test.dart` retain behavior coverage through new routes.

Do not skip/delete protected behavioral assertions. If a conflict beyond these explicit geometry/navigation changes appears, surface it before modification.

## Manual UI-placement test plan

The following is the ui-test-planner's checklist verbatim.

**Manual UI-Placement Test Plan — Full-screen shop**

*Elements under test:* Shop navigation replaces app navigation; accessories move into character wardrobes; previews move below controls; powerup tiles shrink; billing messages become floating toasts.

*Checklist*

1. **Real shop. Get there:** Home → Shop, Home → coin +; verify Profile no longer shows Membership. **Verify:** Back/header and three bottom destinations; no app bar, global Inventory switch, or Accessories tab.
2. **Characters. Get there:** Shop → Characters. **Verify:** owned/locked cards together; active marker; no landing-page dressing room.
3. **Character menus. Get there:** tap locked, then owned characters. **Verify:** purchase versus outfit/use controls appear in their menus.
4. **Wardrobes. Get there:** owned character → Edit outfit. **Verify:** controls above preview, accessories below; Save/Reset visible; Back returns through Characters.
5. **Powerups. Get there:** Shop → Powerups → Buy/Owned. **Verify:** compact tiles, quantities and filters remain visible.
6. **Tutorial. Get there:** Settings → View Shop Tutorial. **Verify:** every spotlight reaches its new target, including wardrobe.
7. **Preview. Get there:** billing preview host → Shop. **Verify:** host navigation disappears; simulated billing toasts float without inline duplicates; Back restores host. Repeat small-screen/large-text checks on both platforms.

*Surfaces confirmed unaffected:* Tab tutorial and demo race contain no ShopTab.

*Risks found while planning:* Removed tutorial targets currently prevent startup; preview host duplicates navigation.

Planning clarifications (not alterations to the checklist): “no app bar” means no main-app bottom navigation; shop header remains. On iOS, the native edge-back gesture is disabled while the wardrobe is dirty or an operation is pending; it must not discard a draft. Labeled Back and category navigation offer Keep editing / Discard changes when dirty. Clean iOS edge-back and Android system-back return through the real route stack; pending operations block exit. Exercise light/dark, iOS back gesture and Android system back, narrow display/large text/landscape. Also open retained standalone Get Coins/Bara+ through preview harness routes, since no production standalone Bara+ entry was found. Tutorial “unaffected” refers to internal shop layout; its Home entry spotlight still needs the described regression check.

## Compatibility, deployment and verification gates

Backend-first additive migration and deployment, then app release on iOS and Android together. Before app release verify the deployed collection/wardrobe endpoints and old-client contracts against production read-only, successful local integration proof for write paths, complete migration/reconciliation and fit audit reports. Do not claim production support from local code alone. New content that frozen binaries cannot render follows existing channel/remote/content rules; this release adds no such art/items. No runtime rollout flags. Keep production exactly two HTTP workers and staging stopped unless separately authorized.

Implementation approval does not authorize production migrations/retirement/restarts/uploads. Prepare concrete artifacts and tests first; ask for in-the-moment production authorization under backend AGENTS.md. README commands are the source of truth before any later build. Both platforms share behavior and verification; no single-platform shipment.

Planning validation is document/source review only: no Flutter build/analyze/test or DB migration was executed for this spec. Required implementation checks remain in the acceptance matrix; they are not reported as passing now.

## Definition of done

The three-section shop opens with an obvious exit; Characters shows owned and locked together; each character displays its independently saved outfit; buying and dressing remain distinct; safe compatible wardrobe changes persist without affecting inactive public looks; activation updates current appearance; existing ownership/rewards/old-client behavior survive. Original button/toast/grid concerns are resolved. Tests first and passing, analyze clean, backend real-HTTP/test-DB coverage, code-reviewer approval, both platforms accounted for and manual checklist delivered. Audit tooling/reports are prepared; production content retirement/deployment requires its own authorization.

## Revision log
- Original gap passes: preserved existing pushed-route entry, focus shortcuts, purchase callbacks, category availability fallback and offline preview exit.
- Original architect review: preserved the blocking in-flight purchase overlay and surfaced old tile-equality tests. These requirements remain: dismissible sheets close first; an active non-dismissible purchase cannot be canceled by Back.
- September 9 image feedback: replaced four-category proposal with Featured/Powerups/Characters; moved accessories into character wardrobes; added unified ownership states, per-character saved looks and a scoped retirement audit. Removed the obsolete frontend-only API/no-migration claim.
- Revised gap pass 1: separated saved wardrobe from active character, and separated retirement from ownership/asset deletion; identified current user+slot persistence limitation.
- Revised gap pass 2: identified old-client equip write compatibility, migration of current outfits only, pending ownership policy, actual active/testOnly distinction, public avatar propagation and obsolete review/checklist scope.

- User confirmed both follow-up questions: unified owned/locked Characters, and retire unreleased designs while preserving currently released and player-owned accessories.

- Final gap pass 1: completed four exact additive endpoint contracts, bounded paging, hidden-item read-only behavior, complete slot validation, legacy carry-over/null synchronization and per-outfit/appearance revisions.
- Final gap pass 2: specified no-GET-write lazy migration, source-of-truth reconciliation/rollback, earned/unlisted ownership visibility, explicit fit preservation, purchase-independent Save and unsaved discard, future variant policy outside this implementation, and superseded geometry tests.
- UI-test-planner review: seven-item checklist retained verbatim; route-aware shop tutorial, offline route wrapper, fixture wardrobes, standalone billing harness and appearance mirrors added to implementation steps.
- Game-analyst review: required zero-economy-write wardrobe operations, unchanged reward pool independent of character/fit, earned-item visibility, retirement dynamic-pool audit and shared legacy mutation locking folded in. No live economy numbers reverified.

- Architect review pass 1 required changes incorporated: coherent revision-bearing GET snapshots; explicit modern shop router/module ownership; compatible-writer A then endpoint B deployment/rollback boundary; preserve unchanged equipment IDs/timestamps for repair precedence. Suggestions incorporated: default only first page, refresh accumulated pages on appearance revision change, distinguish preservation-only items from selectable saved entries.

- Post-review consistency pass 1: verified all four required architect changes against the finished document and expanded read/concurrency/rollback tests; architect re-review returned APPROVE, no required changes or suggestions remaining.
- Post-review consistency pass 2: reconciled empty-outfit JSON examples with no-op revision semantics, made hidden-slot redaction preserve the five-key response shape, and specified the typed billing-result default. Parsed every JSON example and checked document links/formatting locally.
- Final economy re-review returned SOUND, no remaining required changes; UI checklist incorporated verbatim. Planning is complete; implementation, database/content audit execution and tests remain the next approved phase.

- Implementation authorization: user approved the full final spec and added removal of the Profile membership button. Backend/frontend agents assigned tests-first implementation; production deployment remains a separate step after readiness verification.

- Implementation evidence correction: production SELECT-only catalog inspection found legacy text IDs such as shop-baseball-cap and shop-cowboy-hat. All ShopItem/character IDs are opaque String values, not UUID-validated/cast. DB identity/FK types follow the existing text columns. Birthday Hat is now released and owned, and is explicitly preserved.

### Profile membership removal — manual checklist addendum

This replaces the earlier Home-removal interpretation; the approved addition removes Profile's membership entry.

1. **Profile tab:** With billing available, verify the Membership button and its spacing are gone beneath the header; surrounding profile controls remain aligned. Home → Shop → Featured still contains Bara+.
2. **Home avatar → standalone Profile:** Verify the same absence, with Back and Settings still correctly placed. Repeat both layouts on iOS/Android with large text.

Run both on iOS and Android, including large text. Current tab replay never visits Profile; its retained Profile preview branch shares the widget but is unreachable through the shipped walkthrough. Demo race and billing preview do not render Profile. A test without BillingScope alone cannot prove removal because the old button was conditionally hidden.

- Implementation review correction: separated authoritative canPreview from canSelect for unowned accessory try-on. This additive field preserves saved-selection ownership rules and avoids inferring anatomical fit in the client. Backend and frontend regression coverage use the same response semantics.

- Final platform audit: explicitly documented native iOS dirty-edge-back suppression and verified real platform navigation coverage; this preserves draft safety while keeping the labeled exit/discard path available.

- Final frontend acceptance verification: 3,186 Flutter tests pass and analysis is clean. Added explicit platform navigation/Profile coverage, collection page coherence and standalone Get Coins route feedback. The compatible-empty prompt now also appears when Other owned items is nonempty. Final narrow source review returned SHIP. Paired platform builds and production-based backend release evidence are tracked in the deployment-readiness document.
