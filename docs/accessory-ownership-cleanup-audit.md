# Accessory ownership cleanup audit

Production snapshot: 2026-09-10T23:38:40.165Z. Aggregate SELECT-only query in a repeatable-read, read-only transaction, with a 15-second statement timeout. No user identifiers exported. Includes all accounts, current equipment and saved outfits for inactive characters. Characters and powerups are outside scope.

## Proposed change

Keep 29 accessories with ownership, equipment or saved-outfit references. Deactivate the 33 currently active unused accessories listed below using existing backend availability policy (`shop_items.active=false`). Leave the other 5 unused accessories inactive. No database rows, purchase history, CDN images or bundled assets should be deleted. No production change has been applied.

Immediately before application, recheck ownership/equipment/saved-outfit references and protect against concurrent grants or purchases; preserve any item newly referenced since this snapshot. Invalidate every shop catalog cache variant after applying. Retain an exact before/after record. No new app binary or backend runtime deployment is needed for the existing availability mechanism.

All 33 newly deactivated rows are TestFlight-only. The existing production daily reward pool remains 18 accessories; the analyst found no change to current per-user reward pools or reward expected value. Kept items retain current prices and channel restrictions.

## Keep

| Accessory | SKU | Owners | Currently equipped | Saved outfit rows |
| --- | --- | ---: | ---: | ---: |
| 3D Glasses | `glasses_3d` | 45 | 14 | 1 |
| Backpack | `backpack` | 1 | 0 | 0 |
| Baseball Cap | `baseball_cap` | 60 | 12 | 0 |
| Beanie | `beanie` | 45 | 17 | 1 |
| Beard | `beard` | 31 | 10 | 2 |
| Birthday Hat | `birthday_hat` | 16 | 6 | 3 |
| Bunny Ears | `bunny_ears` | 21 | 9 | 2 |
| Chef Hat | `chef_hat` | 34 | 8 | 3 |
| Clown Nose | `clown_nose` | 4 | 0 | 0 |
| Cowboy Hat | `cowboy_hat` | 83 | 40 | 3 |
| Cycling Helmet | `cycling_helmet` | 1 | 0 | 0 |
| Dragon Tail | `dragon_tail` | 1 | 1 | 0 |
| Flower Crown | `flower_crown` | 1 | 0 | 0 |
| Flower Lei | `flower_lei` | 2 | 1 | 1 |
| Football Helmet | `football_helmet` | 26 | 7 | 1 |
| Gold Chain | `gold_chain` | 52 | 39 | 7 |
| Graduation Cap | `graduation_cap` | 39 | 8 | 2 |
| Heart Glasses | `heart_glasses` | 1 | 1 | 0 |
| Knight Helmet | `knight_helmet` | 16 | 9 | 2 |
| Legend Crown | `ranked_legend_crown` | 1 | 0 | 0 |
| Mustache | `mustache` | 1 | 0 | 0 |
| Pirate Hat | `pirate_hat` | 21 | 8 | 3 |
| Santa Hat | `santa_hat` | 20 | 2 | 0 |
| Ski Goggles | `ski_goggles` | 18 | 10 | 1 |
| Sunglasses | `sunglasses` | 90 | 52 | 7 |
| Top Hat | `top_hat` | 22 | 5 | 0 |
| Trail Shoes | `shoes` | 45 | 24 | 3 |
| Turtle Shell | `turtle_shell` | 1 | 0 | 0 |
| Wizard Hat | `wizard_hat` | 1 | 1 | 0 |

## Remove from availability

Each row has zero owners, equipped copies and saved-outfit references at the snapshot.

| Accessory | SKU | Item ID | Historical purchase requests |
| --- | --- | --- | ---: |
| Angel Wings | `angel_wings` | `48a4a200-5ef4-400e-a649-be86d1f12c0f` | 0 |
| Balloon Bundle | `balloon_bundle` | `f54bbbb4-2a79-445a-8413-a602873ff903` | 0 |
| Bandana | `bandana` | `a4ab6910-2d56-490b-a7bb-fc67f580c3f0` | 0 |
| Beaver Tail | `beaver_tail` | `fac093ee-58e5-4ef9-9c93-73c45a1ff8b6` | 0 |
| Bell Collar | `bell_collar` | `6957dc6b-a373-4d17-903d-8945e14f5c3a` | 0 |
| Bowtie | `bowtie` | `ceb1c8d8-9d02-4fa0-b2a9-4e9d8bdcb635` | 0 |
| Bunny Tail | `bunny_tail` | `2c6e9480-5d0b-4255-94c8-dd79c750c450` | 0 |
| Butterfly Wings | `butterfly_wings` | `de53e4b8-cd1a-4ea9-93c6-7c51783e112f` | 0 |
| Catcher's Mask | `catchers_mask` | `c812c13c-2c72-483b-a42a-a30dd91759b1` | 0 |
| Coach Whistle | `coach_whistle` | `74060140-eb85-449a-b5ed-1e4b46c2f91b` | 0 |
| Devil Horns | `devil_horns` | `29cf75a7-61a6-4e8b-bd4a-ee5370286b66` | 0 |
| Fox Tail | `fox_tail` | `857a8e2f-5f88-4902-b33c-a32f48c03706` | 0 |
| Gold Medal | `gold_medal` | `8ca732ba-b506-4024-8dcc-3f1b25dfccac` | 0 |
| Halo | `halo` | `442bf6fe-c21f-487f-8f60-61d2c9ed412f` | 0 |
| Headphones | `headphones` | `2c8041ec-ac3b-4bee-9643-f3b81c7a7793` | 0 |
| Hero Cape | `cape` | `b4172519-e8a9-418f-9024-b109dcbaf8ea` | 0 |
| Jetpack | `jetpack` | `272b5a01-a6ce-4c52-81cd-f8d52f7b2804` | 1 |
| Monocle | `monocle` | `b7efae05-79a6-43c1-b247-550514961882` | 0 |
| Necktie | `necktie` | `6d0fd2d1-b1eb-4f0b-b7be-5afc8560ba19` | 0 |
| Party Blower | `party_blower` | `0fadf61f-938d-40ad-b268-c968a546a3c2` | 0 |
| Peacock Tail | `peacock_tail` | `19798b2c-b95a-4c80-800b-736339538725` | 1 |
| Pearl Necklace | `pearl_necklace` | `982a18cc-7f2b-45c1-ac3f-dcb3695ba017` | 0 |
| Propeller Cap | `propeller_cap` | `fc8160e0-5b13-4a3c-914d-130d7433f3a5` | 0 |
| Pumpkin Hat | `pumpkin_hat` | `df2438fb-ef8b-4e75-a43a-e9442409dbe9` | 0 |
| Reindeer Antlers | `reindeer_antlers` | `d07c252c-84ac-48dd-a1f3-83f4cc854d9c` | 0 |
| Rocket | `rocket` | `8805116a-2154-4ba1-a04e-7b48d5bf8bb2` | 0 |
| Scarf | `scarf` | `46cdd5e1-2f34-47e4-82a5-3843edd99313` | 0 |
| Skateboard | `skateboard` | `fe867983-3b7d-4374-ae86-3a39ddac42c5` | 1 |
| Snorkel Mask | `snorkel_mask` | `4254a885-2b6a-4e8c-a059-ddbc1078bba1` | 0 |
| Spinning Basketball | `basketball` | `4b8c6b4e-4b4d-4012-9686-8ba869ea4a76` | 0 |
| Sweatband | `sweatband` | `175faed8-8210-48f6-95d8-14ba8962c560` | 0 |
| Tennis Visor | `tennis_visor` | `e3564307-25a5-4768-be01-22a788886719` | 0 |
| Viking Helmet | `viking_helmet` | `bf4326a8-35c1-48e1-bf28-b3bc1c16afc8` | 0 |

Jetpack, Peacock Tail and Skateboard each have one SUCCEEDED historical purchase (1,500 / 1,500 / 750 coins respectively), despite no current ownership. The reason for missing current ownership is not established by this audit. Preserve their identities and purchase replay data. They are candidates for removal from sale, not deletion. Other audited references: ad grants, daily claims, billing cosmetic releases/grants; no candidate references there. Purchase replay JSON was not exhaustively scanned; it must remain intact.

## Already inactive

- Domino Mask (`domino_mask`)
- Eyepatch (`eyepatch`)
- Hydration Pack (`hydration_pack`)
- Nerd Glasses (`nerd_glasses`)
- Retro Sunglasses (`sunglasses_style_1`)

## CDN behavior

Deleting a CDN file does not remove a catalog row or purchase eligibility. The backend catalog filters active rows without probing image availability. The image renderer can use disk-cached or bundled artwork, and a missing remote file falls back to bundled artwork or a placeholder. The assets manifest also intentionally includes inactive cosmetics for rendering retained references.

Backend deactivation removes these offerings from refreshed TestFlight and production catalogs using the existing API contract; all newly removed rows are already hidden from production clients. An already-open screen may retain old data until refreshed; the backend rejects new purchases of inactive items. It cannot erase bundled files from an already-installed binary.

Evidence: backend `src/modules/cosmetics/getShopCatalog.js`, `characterWardrobes.js`, `purchaseShopItem.js`, `getUnownedAccessoryPool.js`, `src/routes/assets.js`; frontend `lib/widgets/remote_or_bundled_accessory_image.dart`, `lib/services/remote_asset_cache.dart`.

## Manual verification after application

- TestFlight Home → Shop → Accessories: removed offerings disappear after refresh; retained accessories remain. Repeat via the coin-balance shop entry.
- Shop → Characters → Edit: check Capybara and an alternate owned character. Kept owned/equipped and saved accessories remain, including after switching characters; removed items do not appear as available purchases.
- Settings → View Shop Tutorial: verify the real shop and wardrobe steps have the same available accessories and no empty cards or layout gaps.
- App Store/current production and an older supported client: verify the existing accessory selection and equipped appearance remain intact. Check another player’s avatar and a race surface.
- Daily-box accessory preview: production reward pool remains unchanged.
- Demo/tab tutorial and billing-preview fixture controls: retained baseball cap, sunglasses, shoes, wizard hat and gold chain render normally. Offline fixtures are separate from production catalog data.
- Repeat applicable shop and wardrobe placement checks on iOS and Android, including a narrow screen and large text. No physical-device verification claimed.

This is an audit and a concrete data-change proposal, not a shipped implementation. No Flutter source changes, builds or tests were necessary for the read-only audit. Fresh approval is required before production data writes by backend AGENTS.md.

## Approved operation completed

User explicitly approved the 33 deactivations. Applied 2026-09-10T23:47:02.657Z after fresh protected-reference checks under bounded locks. Reviewer approved the one-off script before execution. Exactly 33 rows changed only active; all other 34 accessory policies and all 67 artwork references verified unchanged. Catalog, manifest and presentation invalidations returned success. No CDN deletion, restart, migration or staging changes.

Production HTTP catalog verification returned200 for Production and TestFlight with both legacy and character/remote-asset headers. All 33 candidates absent; 18 production offerings and 28 TestFlight offerings remain, plus the retained earn-only Legend Crown outside the purchase catalog. Production daily accessory pool remains18. Snapshot and evidence: `artifacts/accessory-cleanup-2026-09-10/`. Earlier proposed-action text above is historical. No physical-device verification performed.
