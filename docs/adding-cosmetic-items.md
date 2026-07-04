# Adding a cosmetic / clothing item

How to add a new wearable accessory (hat, glasses, backpack, shoes, …) that
shows up on the capybara and in the shop.

Cosmetics are **defined in the backend**, in **`data/cosmetics.json`** (in the
`stepv2-backend` repo). The frontend is slot-agnostic: it reads each item's
`slot` + `renderMetadata` and renders the PNG. So a new item is normally **one
PNG asset (frontend) + one JSON entry (backend)** — no Dart code change
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

## The fields (one entry in `data/cosmetics.json`)

```jsonc
{
  "sku": "backpack",          // stable unique key; the apply script upserts on this
  "name": "Backpack",         // shop display name
  "description": "Gear up for the long haul.",
  "slot": "BACK",             // HEAD | FACE | NECK | BACK | FEET
  "priceCoins": 1000,         // 0 = free
  "assetKey": "backpack",     // PNG filename WITHOUT .png, in assets/images/accessories/
  "active": true,             // visible in shop
  "testOnly": true,           // TestFlight/dev-only gate — keep true for new items (see above)
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

### 2. Add the entry + apply (backend)
Add the object above to the `items` array in `data/cosmetics.json`, then apply
it to a database. The apply script (`scripts/cosmetics-apply.js`, run via
`npm run cosmetics:apply`) **upserts by `sku`** against whatever `DATABASE_URL`
points at, so it's safe to re-run.

```bash
# staging (from your laptop; needs STAGING_DATABASE_URL in backend .env):
DATABASE_URL="$(grep -E '^STAGING_DATABASE_URL=' .env | cut -d= -f2- | tr -d '"')" \
  npm run cosmetics:apply
```

On a prod deploy, `prisma/seed.js` calls `applyCosmetics()` automatically (see
the deploy runbook), so committing the JSON change to `main` is what ships it to
prod — no manual prod step. NOTE: migrations are the *old* way cosmetics were
added (only `cowboy_hat`/`baseball_cap`); everything since lives in
`cosmetics.json`. Don't add a new item via migration — you'd create a second
source of truth that the JSON-driven upsert fights with.

### 3. Tune placement (admin tuner)
In a dev/TestFlight build, open **Admin → Accessory Tuner**
(`lib/screens/admin_accessory_tuner_screen.dart`). Select the item, drag the
offset/rotation/scale sliders against a live capybara, then "SAVE TO ALL USERS"
— this PATCHes `/admin/shop/items/{id}` (`updateAdminShopItem`) and writes
`renderMetadata` straight to the DB.

> **⚠️ Write the tuned values back into `cosmetics.json`**, or the next deploy's
> `applyCosmetics()` will overwrite your tuning with the stale JSON values.
> `npm run cosmetics:pull` (`scripts/cosmetics-pull.js`) pulls the live DB values
> back into `cosmetics.json` — run it after tuning, then commit. (This is why
> the existing entries have those long tuned floats.)

### 4. Go prod
After the App Store build that bundles the PNG is live and rolled out, set the
item's `testOnly` to `false` in `cosmetics.json`, re-apply, and commit — so prod
users see it on themselves and on others.

## Where the code lives (frontend)
- `lib/widgets/home_course_track.dart` — `_AccessoryOverlay` / `CapybaraSpriteWithAccessories` / `_FeetAccessoryOverlay`: rendering, slot rects, metadata math.
- `lib/screens/tabs/shop_tab.dart` — shop list, purchase, equip/unequip UI.
- `lib/screens/admin_accessory_tuner_screen.dart` — the placement tuner.
- `lib/services/backend_api_service.dart` — `fetchShopCatalog`, `equipAccessory`, `fetchAdminShopItems`, `updateAdminShopItem`.
- `lib/tutorial/tutorial_preview_data.dart` — `tutorialPreviewAccessories`: a worked example of the item shape.

## Where the code lives (backend)
- `data/cosmetics.json` — **the catalog source of truth.**
- `scripts/cosmetics-apply.js` (`npm run cosmetics:apply`) — upserts JSON → DB.
- `scripts/cosmetics-pull.js` (`npm run cosmetics:pull`) — pulls DB → JSON (after tuning).
- `prisma/seed.js` — calls `applyCosmetics()` on deploy.
- `src/utils/shopCosmetics.js` — slots, serialization, `buildAccessoriesList` (the `testOnly` strip for others' avatars).
- `src/queries/getShopCatalog.js`, `src/commands/equipAccessory.js`, `src/commands/purchaseShopItem.js`.
- `prisma/schema.prisma` — `ShopItem`, `AccessorySlot` enum.
