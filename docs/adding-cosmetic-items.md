# Adding a cosmetic / clothing item

How to add a new wearable accessory (hat, glasses, backpack, shoes, …) that
shows up on the capybara and in the shop.

Cosmetics live in the backend's **`shop_items` table — the DB is the single
source of truth** (the old `data/cosmetics.json` is gone). Prod and staging stay
in lockstep automatically: every admin create/edit is mirrored to the peer DB by
sku (`PEER_DATABASE_URL`). The frontend is slot-agnostic: it reads each item's
`slot` + `renderMetadata` and renders the PNG. So a new item is normally **one
PNG asset (frontend) + one admin API create (backend)** — no Dart code change
required.

## ⚠️ Read this first: old-app compatibility

A cosmetic's PNG is bundled into the **app binary**. The `assetKey` points at
`assets/images/accessories/<assetKey>.png`, which only exists in builds that
shipped that file. Per the repo's core rule (`CLAUDE.md`), older app versions
stay in users' hands for ~a week+ after release.

If you make a new item prod-visible immediately, an **older app that doesn't
bundle the PNG** will try to render it the moment anyone equips it. Two things
soften this, but neither replaces sequencing:
- The renderer has an `errorBuilder` fallback (placeholder painter) when the
  asset is missing — no crash, but it looks wrong.
- `buildAccessoriesList` (backend) strips `testOnly` items from **other** users'
  avatars, so a test item never reaches a prod client that can't render it.

**Therefore: ship a new cosmetic as `testOnly: true` first.** TestFlight/dev
clients (which have the new asset) can see and tune it. Once the App Store build
that bundles the PNG is live and rolled out, flip it to `testOnly: false`. See
"Step 4".

## The fields (body of `POST /admin/shop/items`)

```jsonc
{
  "sku": "backpack",          // stable unique key; the peer mirror upserts on this
  "name": "Backpack",         // shop display name
  "description": "Gear up for the long haul.",
  "slot": "BACK",             // HEAD | FACE | NECK | BACK | FEET
  "priceCoins": 1000,         // 0 = free
  "assetKey": "backpack",     // PNG filename WITHOUT .png, in assets/images/accessories/
  "active": true,             // visible in shop (default true)
  "testOnly": true,           // TestFlight/dev-only gate — DEFAULTS to true on create (see above)
  "earnOnly": false,          // true = not purchasable, granted only (e.g. ranked rewards)
  "sortOrder": 90,            // shop ordering, ascending
  "renderMetadata": { "offsetX": 0, "offsetY": 0, "rotation": 0, "scale": 1 }
}
```

### `renderMetadata` (placement)
- `offsetX` / `offsetY`: if `|value| <= 1` it's a **fraction of capybara size**
  (scales with render size); if `> 1` it's raw pixels.
- `rotation`: radians. `scale`: multiplier on the slot rect (default `1`).
- Optional animation keys:
  - `animationFrames`: positive integer for a horizontal frame sheet.
  - `renderLayer`: `"front"` or `"behind"`; use `"behind"` for tails/capes that should sit under the capybara body.
- Start neutral (`0/0/0/1`) and dial it in with the admin tuner (Step 3).

Animated accessories should be exported like `capybara_walk_right.png`: one
horizontal PNG sheet with equal-width frames. The frontend crops the accessory
sheet to the same `frameIndex` as the capybara walk cycle.

## Slots

| Slot   | For              | Animation                                         |
|--------|------------------|---------------------------------------------------|
| `HEAD` | hats, caps       | bobs with the head walk-cycle                     |
| `FACE` | glasses, masks   | bobs with the head                                |
| `NECK` | chains, scarves  | bobs with the head                                |
| `BACK` | backpacks, capes | static (no bob)                                   |
| `FEET` | shoes            | special: placed per-foot across the 4 walk frames |

Only one item per slot can be equipped at a time. Adding a brand-new slot value
is a schema change: `ALTER TYPE "AccessorySlot" ADD VALUE '<SLOT>'` in its own
Prisma migration (see `_add_feet_accessory_slot`) before any item can use it.

## Steps

### 1. Add the PNG (frontend)
Drop `assets/images/accessories/<assetKey>.png` into the frontend repo. The
`assets/images/accessories/` directory is already globbed in `pubspec.yaml`, so
no pubspec edit is needed — the file bundles automatically on the next build.

### 2. Create the catalog row (backend admin API)
`POST /admin/shop/items` with the body above (admin session token required).
This is the only birth channel for new items. The create writes the environment
you point it at **and mirrors to the peer DB by sku**, so staging + prod get the
row together — safe because `testOnly` defaults to `true`.

```bash
curl -X POST https://staging.steptracker-api.org/admin/shop/items \
  -H "Authorization: Bearer <admin session token>" -H "Content-Type: application/json" \
  -d '{"sku":"backpack","name":"Backpack","slot":"BACK","priceCoins":1000,"assetKey":"backpack"}'
```

The response includes a `mirror` status — if `mirror.ok` is false, reconcile
with `npm run cosmetics:sync-peer -- --repair` (backend repo). Don't add items
via Prisma migration — that's the pre-JSON-era method and creates a second
source of truth.

### 3. Tune placement (admin tuner)
In a dev/TestFlight build, open **Admin → Accessory Tuner**
(`lib/screens/admin_accessory_tuner_screen.dart`). Select the item, drag the
offset/rotation/scale sliders against a live capybara, then "SAVE TO ALL USERS"
— this PATCHes `/admin/shop/items/{id}` (`updateAdminShopItem`) and writes
`renderMetadata` straight to the DB (and mirrors it to the peer DB). Nothing to
write back anywhere — the DB is the source of truth and deploys never touch
cosmetics.

### 4. Go prod
After the App Store build that bundles the PNG is live and rolled out, flip the
item's `testOnly` to `false` in the admin tuner (mirrors to both DBs) — so prod
users see it on themselves and on others.

## Where the code lives (frontend)
- `lib/widgets/home_course_track.dart` — `_AccessoryOverlay` / `CapybaraSpriteWithAccessories` / `_FeetAccessoryOverlay`: rendering, slot rects, metadata math.
- `lib/screens/tabs/shop_tab.dart` — shop list, purchase, equip/unequip UI.
- `lib/screens/admin_accessory_tuner_screen.dart` — the placement tuner.
- `lib/services/backend_api_service.dart` — `fetchShopCatalog`, `equipAccessory`, `fetchAdminShopItems`, `updateAdminShopItem`.
- `lib/tutorial/tutorial_preview_data.dart` — `tutorialPreviewAccessories`: a worked example of the item shape.

## Where the code lives (backend)
- `shop_items` table — **the catalog source of truth** (per environment, peer-mirrored).
- `src/modules/admin/routes.js` — `POST /admin/shop/items` (create) + `PATCH /admin/shop/items/:id` (tuner).
- `src/modules/cosmetics/mirrorShopItem.js` — the prod ↔ staging peer mirror.
- `scripts/cosmetics-sync-peer.js` (`npm run cosmetics:sync-peer`) — drift report / `--repair`.
- `scripts/cosmetics-clone.js` (`npm run cosmetics:clone`) — bootstrap a fresh/local DB from staging.
- `src/modules/cosmetics/shopCosmetics.js` — slots, serialization, `buildAccessoriesList` (the `testOnly` strip for others' avatars).
- `src/queries/getShopCatalog.js`, `src/commands/equipAccessory.js`, `src/commands/purchaseShopItem.js`.
- `prisma/schema.prisma` — `ShopItem`, `AccessorySlot` enum.
