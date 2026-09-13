# Accessory availability and artwork lifecycle

Status: proposed design; user has resolved behavior questions, implementation not approved. Separate approved 33-row cleanup is an operational data change, not deployment of this feature.

## Summary and confirmed decisions

An administrator manages every accessory in one list, including inactive entries. Each row has Active and TestFlight-only controls and an entry to the existing placement tuner. Active controls new sales/rewards, not existing ownership. Production means both Production and TestFlight, not production exclusively. Turning an accessory off preserves owners’ ability to equip and use it. Unused published artwork is removed from origin/CDN only after a verified private source copy exists; owners, current equipment and saved outfits protect artwork. Reactivation restores artwork before making the item obtainable.

User confirmed all three decisions: owners retain use; protect referenced artwork and preserve private source; list-level controls. Existing character/powerup admin behavior is outside scope. No new artwork, prices, refunds, ownership deletion, runtime rollout flags or app cache erasure.

## Existing implementation and gaps

- Flutter `lib/screens/admin_accessory_tuner_screen.dart:383` already has draft Active and TestFlight-only switches; Save at line270 calls `BackendApiService.adminUpdateShopItem` (`lib/services/backend_api_service.dart:2996`). Reuse the service and tuner rather than creating a second source of policy.
- Backend `src/modules/admin/routes.js:568,710` lists and patches shop rows; it invalidates catalog/manifest and best-effort mirrors peer state. Current PATCH is not an artwork lifecycle transaction.
- `src/modules/cosmetics/getShopCatalog.js` filters active, non-earn-only rows. `characterWardrobes.js:242,267` preserves owned rows but uses active to block equip; legacy equip paths also need examination. Owned use must be independent of sale status across all paths.
- `src/routes/assets.js` publishes inactive assetVersion rows intentionally. `src/shared/lib/remoteAssets.js` constructs stable versioned URLs. `src/app.js:498` mounts a public static tree with one-year immutable caching. `scripts/assets-add.js` writes git-tracked PNGs; no private archive or CDN purge lifecycle exists.
- `RemoteAssetCache` and `RemoteOrBundledAccessoryImage` keep device copies and bundled fallbacks. Neither CDN purge nor this feature can erase frozen/offline clients’ local files. Removal is server availability and public-origin/CDN withdrawal, not DRM.

## Product behavior

| State | New purchases/rewards | Owners’ use | Public artwork |
| --- | --- | --- | --- |
| Active + Production | Existing server eligibility and compatible channels | Preserved | Published before activation |
| Active + TestFlight only | Existing test channel policy; never enters production reward pool | Preserved across channel changes on capable clients | Published |
| Inactive + references | None | Equippable and usable | Retained |
| Inactive + no references | None | No current owners | Archived privately, unpublished, purge requested |
| Reactivating | Remains unavailable until ready | Preserved | Restored and verified, then enabled |

Channel changes affect acquisition, not revocation of owned items. Compatible old clients must retain equipped/owned rendering after production-to-TestFlight changes. Capability restrictions still apply: a client without remote rendering cannot receive remote-only gear. Public asset manifests may include protected artwork regardless of sale channel to render legitimate owned/social appearances; they do not confer purchase permission.

Historical purchase rows and replay records are never deleted. A conservative reference resolver also protects any still-rendered historical appearance, billing grant/release, shared key/version, and pending acquisition. A historical row alone must not be treated as proof that artwork can be deleted. If safety cannot be established, leave art published and explain the hold to the admin. The initial snapshot includes Jetpack, Peacock Tail and Skateboard purchase history despite zero current owners.

For initially inactive rows, import and reconcile their real state instead of assuming they were already cleaned up. Bundled-only artwork has no published file to remove; show that accurately and keep its source. Existing permanent-retirement restrictions continue to block activation.

## API contract (additive)

Keep `GET /admin/shop/items` and its existing `items` payload. Add `lifecycle` to each accessory and bounded cursor pagination for the new list (default legacy response remains compatible while catalog size is bounded; new requests use `limit=40&cursor=...`, maximum100). Characters are excluded only with the explicit accessory filter; existing tuner requests retain their behavior.

Example accessory extension:

```json
{"id":"item-id","active":false,"testOnly":true,"lifecycle":{"revision":7,"desiredActive":false,"artworkStatus":"retained","reason":"owned","ownerCount":4,"equippedCount":1,"savedOutfitCount":2,"operationId":null,"canActivate":true}}
```

`artworkStatus`: `published`, `retained`, `cleanup_pending`, `unpublished`, `restoring`, `failed`, `bundled_only`. These describe durable lifecycle state, not release flags. Aggregate reference counts only; no user identifiers. Unknown fields/statuses degrade to neutral unavailable status.

Keep `PATCH /admin/shop/items/:id` and existing request booleans. New list sends optional expected revision and idempotency key:

```json
{"active":false,"testOnly":true,"expectedLifecycleRevision":7}
```

Header `Idempotency-Key` binds actor/item/payload. Omitted revision/key remains accepted for existing admin clients, with serialized state transitions. Reused key with another payload is409. Stale revision409 returns current item for refresh. Invalid types400, unauthenticated401, non-admin403, absent404, permanently retired activation409. Return existing `item`/`mirror` keys plus lifecycle, with HTTP200 after the durable request is accepted. During restoration actual `item.active` remains false and `desiredActive` is true; only confirmed publication permits actual activation. Save errors must never be displayed as successful changes.

Add `GET /admin/shop/items/:id/lifecycle` returning the same item extension for bounded polling while visible and pending. Add `POST /admin/shop/items/:id/lifecycle/retry` with expected revision and idempotency header; retries only the current desired operation, never a stale activation/deletion. Repeating the current desired PATCH is also idempotent. Error details must not expose filesystem paths or provider credentials.

Public catalog/wardrobe contracts remain compatible. Server `canPurchase=false` when off; owners get true equip eligibility based on ownership, compatibility and character support. Legacy owned catalog entries may need inclusion even when inactive so frozen clients can select retained gear, with purchase handlers independently rejecting acquisition. Preserve existing fields and test actual old client headers.

## Data, storage and lifecycle operations

Use an additive migration for a per-item lifecycle revision/desired state, a versioned accessory artwork registry and durable operations. Default existing items to their actual current active/channel policy, not inactive. Backfill registry from verified public PNG hashes; verify shared asset associations. Record all published versions that may still be referenced, not just the current version. Do not null assetVersion to indicate withdrawal: that means bundled fallback.

Registry stores validated asset key/version, checksum, archive locator, public publication state and associations. Operations store item, target revision, desired state, step/checkpoint, attempts and sanitized error. Unique operation identity prevents duplicate jobs. Keep a bounded retry schedule with one worker and deterministic steps; database stays source of truth. Normal storage/provider credentials are configuration, not feature flags.

Private archive is durable, access-restricted storage outside both static web roots and deploy checkout, with verified backup and checksums. Never rely on a deleted working-tree file or Git history as the sole recovery copy. Choose the existing deployment’s supported persistent storage during implementation; verify space/access/backup before enabling cleanup. Published bytes use a distinct managed directory outside the git checkout. Preserve stable `/assets/accessories/key@hash.png` URLs.

A managed route before static serving must enforce registry publication, so an old git-tracked file cannot become public again during the next deployment. Existing unregistered assets retain the legacy serve path until imported; no unrelated character/powerup change. Indexed lookup by category/key/version, bounded cache with invalidation; never load all references on each PNG request. Exported archive paths cannot come from untrusted request values; validate key, hash, MIME and checksum.

Disable sequence:
1. Lock per-item policy and shared asset state; serialize with every acquisition/grant and outfit mutation. Commit inactive acquisition policy and durable cleanup operation, then invalidate all catalog/presentation variants.
2. Recheck ownership, equipment, saved wardrobes, retained historical/pending/billing references and shared assets at execution. If protected, retain published art and report reason.
3. Verify private archive and recoverability before public removal. Stop advertising unreferenced withdrawn assets in manifest; invalidate variants.
4. Unpublish managed origin path, remove managed public file and purge exact known version URLs from CDN. Purge credential/access verification is a precondition; if unavailable report cleanup_pending/failed rather than claiming deletion. Handle cached404 on later restore.
5. Verify origin withdrawal and provider purge acknowledgement, then mark unpublished. Global propagation is not instantaneous; local app caches are outside this guarantee.

Enable sequence: verify archive checksum; restore exact original bytes atomically; publish origin; purge any cached negative response; verify public fetch/hash; commit active only for the still-current desired revision; invalidate catalogs/manifests. A newer disable cancels stale restoration activation. A newer enable prevents stale cleanup from deleting the restored asset. A crash at any step resumes from durable state. Never hold DB transactions while calling CDN or writing files.

All grant/acquisition paths must lock/revalidate availability and publication consistently. Pending ad/billing obligations are honored safely and protect needed art. Reference collection uses bounded set-based queries per batch, with indexes by item/asset and planned union counts; no per-owner loops. Peer/staging mirroring must never publish availability before that origin has art; stopped staging stays stopped. Deactivation remains effective even if art cleanup fails.

## Frontend plan

Apply existing Bara parchment/gold/pixel style, using mobile-design guidance; no new pictorial art. Add `lib/screens/admin_accessories_screen.dart`, linked from existing Admin tools. Each row shows existing thumbnail/name, Active switch, explicit TestFlight-only switch (off = Production + TestFlight), artwork status when relevant, and Edit placement action into the tuner. Paginate; keep inactive items visible and searchable. Preserve drafts while loading another page; serialize saves per item, disable only that row while saving, and reconcile with returned server truth. Use immediate per-row save for the two list switches; tuner retains existing Save semantics and uses the same service.

Loading, retryable errors, empty/filter-empty and pending cleanup/restoration states are distinct. On unknown/missing lifecycle metadata, existing booleans remain readable and the screen states artwork status unavailable; it must not promise automatic cleanup against an older backend. Conflicts refresh the row and explain that another admin changed it. List/tuner edits refresh each other on return. Owned thumbnails use retained art; archived unused thumbnails need an authenticated admin preview endpoint or safe local fallback, never a public archive URL. Pin its exact endpoint/security contract before implementation contract lock.

Same screen on iOS and Android; narrow width and large text keep labels and controls readable. No new consumer controls. Account changes clear cached admin data and pending responses must not update another account.

## Tests first and rollout

Backend integration tests use real HTTP and dedicated test Postgres, with a local fake origin/CDN adapter for external I/O. Prove list/auth/defaults, legacy PATCH, optimistic conflict, idempotent retry, unowned disable, owned off-and-reequip, channel downgrade with owners, saved inactive-character outfit, shared versions, historical references, pending rewards, purchase-vs-disable, stale worker vs reenable, archive/copy/purge failures and restart recovery. Verify old/new client headers and warm catalog/manifest/presentation caches; production reward pool selection must exclude inactive rows while owned use continues. Ensure deployments do not resurrect withdrawn URLs.

Frontend tests pump actual list/tuner/wardrobe screens for switches, missing metadata, loading/error/conflict, out-of-order responses, account change, pending restoration, pagination and retained gear. Do not weaken existing assertions; surface tests encoding intentionally changed inactive-use semantics before updating expected behavior. Relevant tests and flutter analyze must pass. Analyst reviews future removal impacts on production pools; initial 33-row cleanup changes no current production pool.

Deploy backend and private archive/import infrastructure first, verify legacy APIs and archive restore before enabling real cleanup. Import/backfill is bounded and resumable; migration alone never deletes files. Then build/verify both platforms and ship admin list with separate release authorization. No new release flag. Code reviewer must review implementation before completion. Production deployment remains a separate approval from this spec.

## Acceptance criteria

An admin can find every accessory including inactive ones, change both controls, see truthful pending/error/completed status, and edit placement. Owners can re-equip inactive gear and retain saved outfits on supported clients. Unused artwork is privately recoverable and withdrawn from public origin/CDN; reactivation safely restores it. No ownership/history loss, invented policy, stale worker activation, deploy resurrection, or unsupported claim of clearing installed-app copies. Staging is not started. Old app users retain their supported behavior.

## Revision log

- Pass1: separated acquisition from ownership use; identified existing inactive equip block and channel downgrade issues; preserved legacy API and admin clients.
- Pass2: covered private archive verification, shared/historical versions, redeploy resurrection, cached404 restoration, durable races/retries and truthful cleanup status. Separated approved cleanup from future implementation.
- User interview: confirmed preserve owners, guarded CDN cleanup with private source, and list-level controls.
- Architect review returned REVISE; economy review returned SOUND WITH CHANGES. Required revisions and the added character review are recorded below; this draft is not ready for implementation approval.

## Added scope: per-character accessory eligibility

User requested one-by-one review of allowed character/accessory combinations. Live backend already has `shop_item_character_fits` (`prisma/schema.prisma:4305`), and `characterWardrobes.js` enforces approved combinations with preservation for existing outfits. `data/character-wardrobe-fits.json` contains an earlier review; it is not a substitute for current user decisions.

Use `docs/accessory-character-review.md` as the decision ledger for all29 retained accessories. Current characters are Capybara/default, Corgi Puppy and Turtle. Live rules allow17 retained accessories on all three; Trail Shoes on Capybara/Corgi;11 have no approved mappings, with existing use preserved. Empty approval sets are authoritative. Do not interpret them as all characters allowed.

Add allowed-character management to the accessory admin workflow, with real-character previews using current artwork and placement metadata. Character choices come from backend catalog; no compiled character allowlist. Keep acquisition status, channel and allowed-character sets separate. Review one accessory at a time and record each confirmed set; no bulk assumption or mutation from visual guesses. Distinguish “this combination is disallowed” from “placement needs adjustment.” New unreviewed character combinations start unavailable for new equip. Preserve already-owned items and existing saved/current combinations unless the user explicitly requests revocation. A compatibility restriction does not delete an accessory or its artwork.

Before final approval, pin the additive fit-edit API with revision conflict handling, per-character fit/placement metadata if needed, and old-client equip enforcement. Changes in fit applicability may affect purchase eligibility; the server must reject purchases that cannot be used and explain applicable characters. Define pending review state distinctly from explicit empty allowed sets. Include real widget preview captures in each review when needed; screenshots must reflect actual app rendering rather than a generated approximation.

## Required review revisions before implementation approval

1. Explicitly change owner-aware catalog merge outside shared caches, legacy equip, wardrobe eligibility and `shopCosmetics.js` social presentation; preserve character-specific policy and renderer capabilities. Include old-header tests for inactive re-equip and channel downgrade.
2. Complete a shared-asset execution protocol: deterministic lock ordering, durable operation claims, crash takeover and fencing external file actions. A paused delete must not resume after reactivation and remove restored bytes. Use generation-specific managed files and publication pointers or an equivalently proven fenced design; do not rely only on a final DB revision check. Schedule through existing guarded scheduler, without extra PM2 capacity.
3. Cover admin creation, assetVersion/key replacement, asset import and peer mirroring in the same registry/lifecycle boundary. Protect old referenced versions; raw installer writes must not bypass withdrawal state.
4. Pin exact list filter/search/cursor contracts, conflict/retry JSON and authenticated private-preview endpoint. Placement-only tuner saves must not cancel accepted pending activation. Both new and legacy tuner payloads need explicit semantics.
5. Pin origin registry cache TTL/invalidation and fail-closed behavior: registered withdrawn paths never fall through to git static files, including DB errors and deploy/restart. Do not claim withdrawal until warm-cache origin verification and CDN purge acknowledgement succeed.
6. Define durable pre-disable entitlement proof and cutoff across paid/billing, ranked, daily and ad SSV grants. Honor legitimate existing obligations exactly once, prevent new grants while inactive, and reject client-invented timestamps as proof. Preserve committed reward outcome across retries; never reroll to gain a better prize.
7. Add server-side impact preview for production acquisition/pool changes, showing affected users and newly empty per-user pools. Test preview and actual reward selection, including legacy fallback rewards. The current33 cleanup has zero production EV impact; arbitrary future toggles do not.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Accessory lifecycle**

*Elements under test:*\
Admin tools: new accessory-list entry.\
Accessory rows: thumbnail/name, Active, TestFlight only, artwork status and Edit placement.\
Consumer surfaces: inactive offerings disappear; owned and saved outfit artwork remains.

*Checklist*

1. **Admin accessory list**
   - **Get there:** Admin account → Profile → Settings → Admin Tools → new accessory list.
   - **Verify:** Every row groups both switches and Edit placement with its own thumbnail/name. Inactive rows remain visible. Search and scroll through additional pages: no duplicated rows, detached switches or overlapping status text.
2. **Placement tuner**
   - **Get there:** Accessory list → Edit placement; also open the existing Accessory Render Tuner entry.
   - **Verify:** Preview, accessory picker, existing switches and Save remain accessible. Returning to the list shows one intact row, without duplicate controls or an overlay left behind.
3. **Artwork lifecycle states**
   - **Get there:** In a prepared test environment, open list rows representing retained, unpublished, restoring and failed artwork states.
   - **Verify:** Status and any retry control stay within the correct row. Archived artwork has an admin preview or deliberate placeholder, without a broken-image tile or collapsed row.
4. **Shop and owned wardrobe**
   - **Get there:** Home → Shop → Accessories; repeat through coin “+”. Then Characters → Edit an owned character, including one with an inactive accessory saved.
   - **Verify:** Inactive offerings are absent from purchase choices without empty grid gaps. Owned accessory tiles and saved outfit pieces remain visible; inspect an inactive character’s saved outfit too.
5. **Shop tutorial**
   - **Get there:** Profile → Settings → View Shop Tutorial → customization.
   - **Verify:** Remaining accessory choices occupy their normal sections, with no orphaned tiles. Spotlights still surround their intended controls; no admin controls appear.

Repeat list/tuner checks on iOS and Android, including a narrow screen with larger text. Repeat consumer checks on TestFlight and an available older production app.

*Surfaces confirmed unaffected:*\
General tab/onboarding tutorial: offline fixtures; no admin list or live accessory catalog.\
Demo race tutorial: no accessory-management screen; removal candidates are absent from fixtures.\
Billing preview: independent fixture catalog; live lifecycle changes do not propagate.

*Risks found while planning:*\
The existing tuner already has both switches; list controls and tuner controls are separate placements to verify.\
The new list entry and exact row layout remain proposed.\
Archived thumbnail handling needs its contract finalized before implementation.\
Shop tutorial uses live wardrobe data, so catalog changes can alter its highlighted content.

Character-eligibility UI extension needs a supplementary planner pass once its exact preview/controls placement is specified. The checklist above predates that scope addition.
