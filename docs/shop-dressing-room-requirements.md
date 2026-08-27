# Shop dressing room and equipment-state requirements

**Status:** Draft for owner approval  
**Surfaces:** Flutter Shop tab on iOS and Android  
**Backend:** Existing additive contracts only; no migration or new endpoint

## Summary and user story

The Shop currently has two related problems. First, its item-level `equipped`
booleans can disagree with the authoritative `equipped` slot map after an equip
mutation. The UI then offers `EQUIP` for the item actually being worn and marks
the previously worn item `EQUIPPED`. Second, the live Bara preview is only a
small thumbnail while the merchandise cards consume most of the screen, so it
is difficult to judge an outfit. Store cosmetics can technically update that
thumbnail when their detail sheet opens, but the interaction is too small and
indirect to work as a useful try-on experience.

As a player choosing a character or accessory, I want a large, responsive
dressing-room stage and a compact item picker so I can compare outfits on my
actual Bara before buying or equipping anything, and I want every equipped
badge/action to reflect the loadout the server says I am wearing now.

## Current-state evidence

- `lib/screens/tabs/shop_tab.dart:646-674` patches only the top-level
  `equipped` map after `PUT /shop/equipment/:slot`; it does not rewrite each
  catalog item's `equipped` boolean.
- `lib/screens/tabs/shop_tab.dart:1583-1629` nevertheless drives Inventory
  badges and `EQUIP`/`CLEAR` actions from `item['equipped']`. This explains the
  reported Cowboy Hat/Bunny Ears inversion after a same-slot change.
- `lib/screens/tabs/shop_tab.dart:1094-1197` already builds a local outfit from
  the equipped map plus one draft selection, but constrains the whole preview
  to roughly 92 dp and the avatar window to 66 dp.
- `lib/screens/tabs/shop_tab.dart:1493-1579` invokes the draft preview only as
  part of opening a Store detail sheet. Preview selection itself does not call
  the backend, which is the correct foundation for a real try-on flow.
- `lib/screens/tabs/shop_tab.dart:1220-1242` and `:2574-2775` use large
  three-column cards with a 48 dp footer action. These cards compete with the
  avatar instead of behaving like a compact wardrobe picker.
- `lib/screens/tabs/shop_tab.dart:296-360` already prefers additive
  `GET /shop/bootstrap`. `backend_api_service.dart:5368-5410` falls back to the
  older catalog, powerup-catalog, and inventory endpoints only after a definite
  bootstrap 404; malformed 2xx data and transient/server errors remain errors
  and must not silently fan out.
- The backend's `src/modules/shop/queries/getShopBootstrap.js` already loads
  cosmetics, powerups, and inventory concurrently. Its
  `src/modules/cosmetics/getShopCatalog.js` caches only the channel/capability-
  variant global catalog rows in Redis while reading coins, ownership, and
  equipment from Postgres on every request.

## Scope

1. Make the top-level `equipped` slot map the single frontend source of truth
   for cosmetic/character equipped state.
2. Replace the small preview with a large dressing-room stage whenever
   `CHARACTERS` or `ACCESSORIES` is selected in Store or Inventory.
3. Turn cosmetic/character merchandise into a compact selection grid below the
   stage while preserving accessible touch targets and readable names.
4. Let any unowned Store character/accessory be previewed on the player's
   currently equipped avatar without purchasing, equipping, or making another
   network request.
5. Keep purchase confirmation, affordability/ad-unlock behavior, accessory
   conflict handling, remote/bundled art fallback, and the existing Powerups
   experience intact.
6. Account for small phones, large text, tablets, light/dark palettes, iOS, and
   Android.

## Non-goals

- No new cosmetic, character, artwork, price, currency, odds, inventory rule,
  slot, compatibility rule, or economy change.
- No changes to race/profile/home avatar rendering outside the shared renderer
  already consumed by the Shop preview.
- No multi-item saved outfits, wishlist, cart, compare mode, 3D rotation, or
  server-persisted preview state.
- No feature flag, rollout percentage, kill switch, or temporary environment
  toggle.
- No Redis cache for user ownership/equipment and no client-side durable Shop
  response cache.

## Product and interaction requirements

### Authoritative equipped state

Add defensive helpers in `shop_tab.dart` that read a slot row from
`_catalog['equipped']` and compare its non-empty `id` with the catalog item's
non-empty `id`. The top-level map wins whenever an item-level `equipped` boolean
contradicts it. Missing, null, scalar, or malformed slot rows must return “not
equipped” without throwing. The default Capybara remains equipped precisely
when there is no valid `CHARACTER` row.

All Inventory tile badges, highlights, actions, sheet copy, placeholder tint,
and stage CTA state must use that derived answer. No cosmetic UI may make an
independent decision from `item['equipped']`. After an equip response, replacing
the top-level map must immediately and atomically move the equipped state from
the old item to the new item without a catalog refetch.

### Dressing-room stage

For `CHARACTERS` and `ACCESSORIES`, the existing `shop-character-preview`
becomes an art-led stage above the compact picker:

- target stage height: 210-230 dp on phones and up to 250 dp on wider layouts;
- target visible avatar footprint: approximately 120-140 dp, at least twice the
  current rendered footprint, without clipping tall HEAD/BACK/FEET art;
- retain the arcade-green/parchment visual language, pixel typography, and
  deliberate flat framing already used by the app; do not introduce default
  Material cards or a generic gradient;
- show `YOUR BARA`, a short equipped/previewing status, and one clear selected-
  item action area without covering the art;
- animate selection changes with a restrained 140-200 ms scale/cross-fade keyed
  by character plus ordered accessory asset keys. Respect reduced-motion
  platform settings by using an instantaneous or opacity-only transition;
- semantic label announces the current base character and previewed item.
  Preview changes are also exposed as a polite live-region announcement while
  focus remains on the tapped selector.

On `POWERUPS`, retain the current compact header footprint rather than spending
most of the viewport on an irrelevant avatar. Switching section or category
clears a draft selection and returns the stage to the actual equipped look.
Refreshing, failed mutations, and closing a detail sheet do not accidentally
equip the draft.

### Compact character/accessory picker

Create a cosmetic picker presentation separate from the existing powerup card:

- 3 columns below 360 dp, 4 columns from 360-599 dp, and 6 columns at 600 dp or
  wider;
- the entire selector is one semantic button and at least 48 dp in both axes;
- art remains the primary content, with a maximum two-line fitted name and a
  small price/equipped/owned marker; remove the large 48 dp action footer from
  cosmetic selector cards because the selected action lives in the stage;
- selection uses a visible gold focus/selection outline distinct from the
  actual `EQUIPPED` marker;
- keyboard/focus activation and screen-reader labels expose item name, slot,
  ownership, price, selected state, and equipped state;
- loading geometry for cosmetic categories mirrors the compact grid to avoid a
  layout jump. The Powerups loading/live grids remain unchanged.

### Store try-on and actions

Tapping a Store character/accessory selects it and composes a local preview by
replacing only that item's slot in the currently equipped loadout. A CHARACTER
preview replaces the base animal but retains the equipped accessories, matching
the shared renderer's current behavior. An accessory preview replaces only its
slot and preserves every other equipped slot.

Selection makes zero API calls and performs no durable write. The stage shows
the name and price plus a `DETAILS & BUY` (or existing ad/get-coins equivalent)
action that opens the existing scrollable confirmation sheet. Buying remains
possible only from that sheet, preserving the existing protection against an
accidental charge. A failed purchase leaves the preview selected and shows the
existing error; a successful purchase patches/refetches through the current
path and returns the stage to the authoritative equipped look.

### Inventory try-on and actions

Tapping an owned character/accessory selects and previews it without equipping.
The stage action is `EQUIP` when the selected item is not worn, `CLEAR` when it
is worn, and inert `EQUIPPED` for the default Capybara. The existing detail sheet
remains reachable from a secondary `DETAILS` affordance in the stage, not from
the selection tap. Equip/Clear remains reversible and may execute directly.

While an equip request is in flight, disable all outfit mutation CTAs but keep
scrolling and preview inspection available. Success applies the response's
authoritative `equipped` map, clears the draft, updates `onShopChanged`, and
shows the correct badges in the same frame. Failure preserves both the previous
equipped map and the local draft; `ACCESSORY_CONFLICT` continues to use the
server message.

The default Capybara participates in the same selection flow while another
character is equipped: selecting it previews the default body locally and its
`EQUIP` action clears the `CHARACTER` slot through the existing endpoint.

Local preview is visual and intentionally permissive. Catalog items do not
serialize the full compatibility graph, so a draft combination may later be
rejected by the server as `ACCESSORY_CONFLICT`; the failed mutation leaves the
authoritative outfit and local draft intact.

### Completion ordering and session safety

Shop state uses a monotonically increasing session/request generation tied to
the current authenticated user. Auth changes and disposal advance the
generation. Every async load, purchase, and equipment mutation captures both
generation and user identity and may apply results only if both still match.

Every accepted equipment, purchase, or ad-unlock mutation advances the Shop
state epoch before applying its result. Any catalog/powerup load that captured
an older epoch is discarded, including a refresh that began while the mutation
was in flight, read pre-commit state, and completed afterward. A refresh started
after that acceptance may replace the state, and must revalidate the selected
draft against the refreshed catalog: keep it only when the same item remains
visible in the current section/category; otherwise clear it. A completion from
a prior user/session is discarded and cannot call `onShopChanged`, update
coins, show a toast, or patch the next user's Shop.

## API contract

No endpoint or response shape changes are required.

### Read

The frontend continues to prefer:

`GET /shop/bootstrap?localDate=YYYY-MM-DD`

```json
{
  "contract": "shop-bootstrap-v1",
  "cosmetics": {
    "coins": 1000,
    "ownedItemIds": ["item-id"],
    "equipped": {
      "HEAD": {
        "id": "item-id",
        "sku": "cowboy_hat",
        "name": "Cowboy Hat",
        "slot": "HEAD",
        "assetKey": "cowboy_hat",
        "renderMetadata": {}
      }
    },
    "items": []
  },
  "resolved": { "powerups": true, "inventory": true },
  "powerups": {},
  "inventory": {}
}
```

Older backends may return 404 for bootstrap; only that definite unsupported
result activates the existing fallback to `GET /shop/catalog`,
`GET /shop/powerups`, and `GET /powerups/inventory`. A malformed 2xx bootstrap,
401, timeout, or 5xx remains a load error and must not trigger fallback fan-out.
Optional item art/render fields remain optional.

### Equip/Clear

`PUT /shop/equipment/:slot`

Equip request:

```json
{ "itemId": "item-id" }
```

Clear request:

```json
{ "itemId": null }
```

Success remains the complete, capability-filtered equipment map (not merely the
mutated slot):

```json
{
  "equipped": {
    "HEAD": {
      "id": "item-id",
      "sku": "cowboy_hat",
      "name": "Cowboy Hat",
      "slot": "HEAD",
      "assetKey": "cowboy_hat",
      "renderMetadata": {}
    }
  }
}
```

Existing errors remain unchanged:

| Status | Meaning / body behavior |
|---|---|
| 400 | invalid slot/item/body; existing `{ "error": "…" }` copy |
| 401 | missing/invalid session; existing auth error |
| 403 | item is unowned |
| 409 | `ACCESSORY_CONFLICT`, with optional `code`, `conflictingItemIds`, and `conflictingSlots` |
| 500 | existing generic internal-server error |

Inactive items, test-only/channel-unavailable items, wrong-slot items, invalid
slots, and malformed request bodies remain 400 responses.

The client validates a mutation map before accepting it: `{}` is valid; every
known populated slot must be a map with a non-empty string `id` and a `slot`
equal to its map key; null known slots and unknown future slots are ignored
defensively. If `equipped` is absent/scalar or contains a malformed known row,
retain the prior authoritative map and draft, then refresh the catalog. If that
refresh also fails, preserve the old map/draft and show the refresh/mutation
error rather than erasing visible equipment.

### Purchase

`POST /shop/items/:itemId/purchase` and the existing cosmetic ad-unlock endpoint
are unchanged. Preview never calls them. Existing idempotency and confirmation
requirements remain in force.

## Data model and migrations

No schema or data migration. Postgres remains authoritative for
`user_shop_items` ownership and `user_equipped_accessories` equipment. No
preview row is written anywhere.

## Performance and Redis architecture

This feature must not add a request per tile, per preview tap, or per animation
frame. The initial Shop load remains one bootstrap request on capable backends;
all try-on composition is in memory from that payload. Use the existing shared
`RacerAvatar`, remote-or-bundled accessory resolver, and image cache so the
stage does not decode a second bespoke copy of an asset. Preserve canonical
accessory order and renderer keys.

The backend already makes the appropriate cache split: immutable-ish global
catalog rows use a bounded, channel/capability-variant Redis cache, while coins,
ownership, and equipment are fetched from Postgres per user. Do not cache the
assembled per-user bootstrap or equipment map for this feature; doing so would
create avoidable invalidation and cross-user leakage risk for a screen whose
preview is local. Redis remains fail-open and never authorizes purchases or
equipment writes. Existing admin catalog invalidation and post-equip user
presentation/auth cache invalidation remain unchanged.

Frontend implementation should isolate the stage and selector widgets, use
stable keys, and avoid timers/controllers per tile. One short stage transition
may run at a time; rapidly tapping items replaces the target rather than
queuing animations. Prefer a lazy sliver/builder for cosmetic selectors if the
60-item profile shows the shrink-wrapped grid rebuilding/layouting excessively.
Measure/debug-profile a catalog with at least 60 cosmetics: selection must not
trigger network traffic, image decoding should reuse cache, and
scrolling/selection should remain smooth on a representative phone.

## Frontend implementation path

1. In `test/shop_dressing_room_test.dart`, first add failing real-`ShopTab`
   widget tests for contradictory equipment fields, mutation response patching,
   Store try-on with zero writes, Inventory preview/action behavior, responsive
   stage/grid geometry, large text, reduced motion, dark theme, and missing art.
2. In `lib/screens/tabs/shop_tab.dart`, add total equipment-map readers and
   route every cosmetic equipped decision through them. Keep item booleans only
   as ignored compatibility input.
3. Replace the single `_draftPreviewItem` behavior with explicit selection
   state whose lifetime is defined above; keep it local to the screen.
4. Extract focused private widgets/configuration for the responsive dressing
   stage and compact cosmetic selector. Reuse `_cosmeticArt`, `RacerAvatar`,
   `PillButton`, theme tokens, and existing sheets/services.
5. Split cosmetic/character category bodies from powerup category bodies so
   only outfit categories use the new responsive selector geometry. Update the
   corresponding loading skeleton. Preserve every existing Powerup control,
   filter/sort position, card footer, and loading geometry.
6. Keep Store purchase/ad routing in the existing confirmation sheet. Move
   Inventory equip/clear and detail affordances into the selected-item stage.
   Give the scrollable header an obvious unobstructed path to the first picker
   row on short phones; keep the stage action/status region separate from tall
   HEAD/BACK/FEET art at narrow widths and large text; render selection outline
   and equipped marker as non-overlapping, semantically distinct states.
7. Clear draft state at section/category boundaries and after successful
   purchase/equip; preserve it on failures. Add the user-bound generation rule,
   invalidate pre-mutation reads, and revalidate selection on accepted refresh.
8. Update existing Shop geometry tests mechanically where the approved layout
   intentionally changes; never weaken their accessibility, dark-theme,
   confirmation, or compatibility assertions.

## Backend implementation path

1. Before frontend coding, confirm and pin the unchanged contract above against
   `src/modules/cosmetics/getShopCatalog.js`,
   `src/modules/cosmetics/equipAccessory.js`, and
   `src/modules/shop/queries/getShopBootstrap.js`.
2. Add/extend a real HTTP integration assertion only if current coverage does
   not prove that `cosmetics.equipped` and item booleans are consistent on a
   cold bootstrap read and that equip returns the complete new map. Write the
   assertion first and run only against the dedicated test database.
3. Do not add backend production code, a migration, runtime control, or cache
   unless the contract audit disproves the current-state findings. Any newly
   discovered backend requirement returns the spec to architecture/owner
   approval before implementation.

## Backward compatibility and rollout

- A frozen old app against the unchanged backend sees the same additive
  catalog/bootstrap/equip responses and behaves exactly as before.
- The new app against an older backend falls back from bootstrap and derives
  equipment from the long-standing `equipped` map. Missing optional art fields
  use existing bundled/placeholder behavior.
- No new content is introduced, so `testOnly` staging is not required.
- No backend deployment is expected. If the backend audit finds a required
  additive fix, deploy it first; otherwise release the iOS and Android builds
  in lockstep with matching version/backend URL.
- Do not deploy production or perform production writes without explicit,
  in-the-moment owner approval.

## Tests-first plan

### Frontend widget/integration tests

1. Seed Cowboy Hat with `item.equipped=false`, Bunny Ears with
   `item.equipped=true`, and `equipped.HEAD=Cowboy Hat`; assert Cowboy alone is
   highlighted/CLEAR and Bunny offers EQUIP.
2. Begin with Bunny equipped, return Cowboy in the real equip response, and
   assert the UI and preview switch immediately without a catalog refetch.
   Separately prove `{}` is accepted, while absent/scalar/malformed known-slot
   maps retain the prior state and trigger refresh; a refresh failure must not
   erase the prior state or draft.
3. Tap an unowned Store accessory and character; assert the stage replaces only
   the intended slot, shows the selected name/price, makes zero purchase/equip
   calls, and leaves the durable equipped map unchanged.
4. Verify Store purchase remains behind the details/confirmation sheet and a
   failed purchase does not mutate equipment.
5. Tap Inventory items; assert selection only previews, the stage CTA uses the
   map-derived correct action, conflicts preserve the old map/draft, and success
   clears the draft. Select synthetic Capybara while another character is worn,
   preview it locally, and prove `EQUIP` clears `CHARACTER`.
6. Verify stage and compact-grid breakpoints at 320, 390, and 700 dp, minimum
   48 dp selectors, no overflow at 2.5x text, and skeleton/live geometry parity.
7. Verify light/dark contrast tokens, selection vs equipped semantics, keyboard
   activation, reduced-motion behavior, missing/malformed response fields, and
   remote/bundled missing-art fallback.
8. Re-run existing Shop confirmation, ad-unlock, character-shape, compatibility,
   filter/sort, coin-pill, spacing, and Store/Inventory suites.
9. Use completer-driven fake responses to prove a refresh started before or
   during equip cannot overwrite the accepted equip map; repeat the during-
   mutation ordering case for purchase; prove a completion from a prior auth
   user or after dispose cannot patch state/callbacks/toasts; and prove a later
   accepted refresh clears a draft item no longer present.
10. Prove a bootstrap 404 uses the legacy endpoint fallback, while malformed
    2xx bootstrap data does not fan out and renders the existing load error.

### Backend integration tests

Use `test/integration/shop.test.js` or the existing bootstrap integration suite
through real HTTP and a dedicated `*_test` database. Confirm:

1. `GET /shop/bootstrap` returns a single internally consistent cosmetics
   snapshot for an equipped owned item.
2. `PUT /shop/equipment/HEAD` returns Cowboy as the sole HEAD row after Bunny
   was previously equipped, followed by a catalog/bootstrap read that marks
   Cowboy true and Bunny false.
3. Existing old-client feature headers and Redis enabled/disabled paths do not
   change JSON semantics. The enabled path must use the repository's local test
   Redis on DB 15 and never a production/shared Redis; repeat the public-path
   assertion with `REDIS_URL` unset to prove fail-open/uncached parity. Add no
   mocked internal-utility parity substitute for these public-path assertions.

## Acceptance criteria and definition of done

- Cowboy/Bunny contradictory fixtures and post-mutation behavior prove that the
  UI has exactly one equipped item per slot and never reads stale item booleans.
- Store and Inventory outfit categories show a materially larger, unclipped
  live Bara and materially smaller selectors at all approved breakpoints.
- Every Store cosmetic/character can be previewed on the actual equipped outfit
  with zero mutation and zero additional network requests.
- Purchase confirmation, ad unlock, equipment conflict, remote art, powerups,
  loading/error/empty states, accessibility, and dark mode remain functional.
- `flutter analyze` is clean; relevant tests and the full `flutter test` suite
  pass; existing assertions were not weakened.
- Any backend tests run against a confirmed local/test database and
  `npm run test:unit` / `npm run test:integration` are green as applicable.
- iOS and Android release builds succeed with synchronized version, backend
  URL, and required platform defines.
- Version-skew behavior is verified; architecture, UI-placement, and combined
  code reviews have no unresolved REQUIRED findings.
- The owner receives the manual UI-placement checklist and gives explicit
  production deployment authorization before any deploy.

## Manual UI-placement test plan

**Manual UI-Placement Test Plan — Shop dressing room and equipment state**

*Elements under test:* The live Bara preview grows from the old 92 dp thumbnail into a 210–250 dp dressing-room stage above the picker in Store and Inventory → Characters/Accessories.

*Elements under test:* Character/accessory merchandise changes from large three-column cards with 48 dp footer actions to compact selectors: 3 columns below 360 dp, 4 columns from 360–599 dp, and 6 columns at 600 dp or wider.

*Elements under test:* Store selection and `DETAILS & BUY` move into the dressing-room stage; tapping a selector no longer immediately opens the detail sheet, and cosmetic selector cards no longer have the old action footer.

*Elements under test:* Inventory `EQUIP`/`CLEAR`/`EQUIPPED` and secondary `DETAILS` move into the stage; equipped markers remain on the appropriate selector while selection gets a separate outline.

*Elements under test:* Powerups retain the existing compact preview/header and existing merchandise-card placement rather than showing the enlarged dressing room.

*Checklist*

1. **Production Shop — Store Characters**
   - **Get there:** Sign in with an account that has at least one unowned character → Home → SHOP → STORE → CHARACTERS.
   - **Verify:** A large `YOUR BARA` stage appears above the character picker and shows the full avatar without clipping; compact character selectors appear below it. Tap an unowned character and verify the selected outline appears on that selector, the previewed Bara and `DETAILS & BUY` action appear in the stage, and the old small preview, tile action footer, and automatically opened detail sheet are absent. Tap `DETAILS & BUY` and verify the existing purchase sheet then appears from the bottom.

2. **Production Shop — Store Accessories**
   - **Get there:** From Shop → STORE → ACCESSORIES; use an account with equipped gear and at least two unowned accessories in different slots, including tall HEAD/BACK/FEET art if available.
   - **Verify:** The same large stage remains above the compact accessory picker. Tap different accessories and verify the selection outline moves between selectors while the stage remains the sole location for the selected item’s action; the selected accessory is visible on the enlarged avatar without clipping or covering by the action area. Verify no selected item is duplicated in the old thumbnail position or in a footer beneath its selector.

3. **Production Shop — Inventory Characters**
   - **Get there:** Shop → INVENTORY → CHARACTERS; use an account that owns another character as well as the default Capybara.
   - **Verify:** The enlarged stage is above the compact picker and Capybara remains first in the character choices. Select a character without equipping it and verify the selection outline appears on its selector while `EQUIP` and secondary `DETAILS` appear in the stage. For the actually worn character, verify its `EQUIPPED` marker is on the selector and the stage has the appropriate worn-state action; the old per-tile `EQUIP`/`EQUIPPED` footer and tap-to-open-sheet placement are absent.

4. **Production Shop — Inventory Accessories and equipped-marker move**
   - **Get there:** Shop → INVENTORY → ACCESSORIES with Cowboy Hat equipped and Bunny Ears owned, then repeat after equipping Bunny Ears.
   - **Verify:** Initially, only Cowboy Hat has the equipped marker; Bunny Ears may have a selection outline when tapped but must not show an equipped marker. `EQUIP`/`CLEAR` and `DETAILS` appear in the stage, not under either selector. After equipping Bunny Ears, the equipped marker moves to Bunny Ears in the same displayed picker and disappears from Cowboy Hat; neither marker remains in the old footer position and no duplicate equipped marker appears.

5. **Production Shop — category/section boundaries and Powerups**
   - **Get there:** Select a cosmetic in STORE → ACCESSORIES, then switch to CHARACTERS, INVENTORY, and POWERUPS.
   - **Verify:** Each section/category change removes the prior cosmetic selection outline and returns the avatar to the actually equipped look. Characters and Accessories show the large stage above their compact picker. Powerups instead retain the old compact header footprint and existing powerup card/action placement; no large dressing-room stage or leftover cosmetic stage action appears there.

6. **Responsive placement — narrow phone, standard phone, and tablet**
   - **Get there:** Open STORE → ACCESSORIES on a device/emulator below 360 dp wide, one between 360–599 dp, and one at least 600 dp wide; repeat one Inventory cosmetic category at the smallest width with system text size increased to 2.5×.
   - **Verify:** The picker has respectively 3, 4, and 6 columns beneath the stage. Every selector remains at least 48 dp in both axes, names stay within their selector, and the stage/action area does not overlap the avatar, section/category controls, or first picker row. On the narrow/large-text case, verify the stage and picker remain reachable by scrolling and neither the enlarged stage nor compact selectors also appear in their former geometry.

7. **Platform/theme smoke — iOS and Android**
   - **Get there:** On one iOS and one Android build, use Profile → Settings → Appearance to force Dark, then open Home → SHOP → both Store and Inventory → Accessories.
   - **Verify:** On both platforms, the ordering remains header/coin balance, dressing-room stage, controls, then compact picker; selection and equipped markers occupy their intended separate positions. The stage action remains outside the avatar art and no old cosmetic footer returns in dark mode.

8. **Initial loading placement**
   - **Get there:** Cold-open Home → SHOP with network throttling enabled, then choose CHARACTERS or ACCESSORIES before loading completes if the controls are available.
   - **Verify:** Cosmetic loading placeholders occupy the same compact column geometry as the loaded selectors below the stage, with no large legacy footer-shaped placeholder and no visible jump to the old card layout when data arrives.

9. **Tutorial replay — real Home mirror**
   - **Get there:** Profile → Settings → VIEW TUTORIAL → advance to the final “Win coins” beat.
   - **Verify:** The spotlight still rings the existing Home SHOP button. No dressing-room stage or selector leaks into the tutorial Home preview, and tapping through the tutorial does not push a Shop route behind or above the tutorial.

10. **Fresh-account onboarding/demo**
    - **Get there:** Sign in with a fresh account → onboarding → start the tutorial/demo-race teaching step and complete it to Home.
    - **Verify:** No Shop dressing-room stage, picker, or moved Shop action appears inside onboarding or the demo race. After reaching the real Home screen, the SHOP button remains in its existing quick-action position and opens the production Shop where the new stage appears only in Characters/Accessories.

*Surfaces confirmed unaffected:* `TutorialRealHost` does not instantiate `ShopTab`; it reuses only `HomeTab` and exposes the existing `home.shop` spotlight anchor, with no `onOpenShop` callback.

*Surfaces confirmed unaffected:* The onboarding spotlight walkthrough and `DemoRaceHost` do not render `ShopTab`; their race, invite, case-opening, and coach surfaces share no Shop dressing-room widgets.

*Surfaces confirmed unaffected:* Home, race, profile, public-profile, and leaderboard avatar placements use shared avatar rendering but do not reuse the Shop stage or selector layout; the spec explicitly leaves those placements unchanged.

*Surfaces confirmed unaffected:* `ShopTab` has only one production construction site, the route pushed by `MainShell._openShop`; there is no hand-forked Shop screen or bottom-tab copy requiring a parallel layout edit.

*Risks found while planning:* The tutorial’s SHOP button is intentionally inert because `TutorialRealHost` supplies no `onOpenShop`; the new dressing room will not be exercised by tutorial fixture data. If Shop is later made interactive there, a seeded Shop API and navigation containment will be required.

*Risks found while planning:* The enlarged stage lives in the same scrollable header as the Store/Inventory and category controls. At 210–250 dp, it can push the first picker row below the fold on short phones; implementation must preserve an obvious, unobstructed scroll path.

*Risks found while planning:* Selection, equipped state, and action placement are three different visual states. The selected gold outline must not be mistaken for or obscure the equipped marker, especially when the selected item is not the worn item.

*Risks found while planning:* Tall HEAD/BACK/FEET artwork and the stage action area compete for the enlarged stage. The action/status block must not overlay or crop the avatar at narrow width or large text.

*Risks found while planning:* Cosmetic loading geometry must be category-aware. The current shared loading grid has legacy card/footer proportions, so simply resizing live cosmetic selectors would still produce a placement jump.

*Risks found while planning:* Powerups share the Shop shell but are explicitly excluded from the large stage and compact cosmetic selector. Splitting the category layouts must not accidentally move Powerup controls, filters, sorting, or card actions.

## Revision log

- **Initial draft (2026-08-27):** traced the stale item-boolean bug to the local
  equip patch, specified an equipment-map source of truth, a responsive large
  dressing-room stage, compact selectors, local Store try-on, unchanged API
  contract, and the existing safe Redis/global-catalog split.
- **Fresh-eyes pass 1 (2026-08-27):** separated cosmetic selector geometry from
  Powerups so the redesign does not regress powerup actions; preserved purchase
  confirmation; defined draft lifetime, mutation failure behavior, reduced
  motion, semantic distinctions, and no-network preview acceptance.
- **Fresh-eyes pass 2 (2026-08-27):** added narrow/large-text/tablet and missing-
  art coverage, explicit backend no-op/audit path, Redis cross-user/invalidation
  constraints, old-backend fallback behavior, tests-first sequencing, and the
  production approval boundary. No unresolved product question remains.
- **Architect review (2026-08-27):** corrected bootstrap fallback to 404-only;
  defined strict-but-forward-compatible equipment-map validation and failure
  preservation; added a user-bound async generation/order contract; pinned
  Redis tests to local DB 15 plus an unset-Redis parity run; added Capybara,
  live-region, permissive-preview/conflict, and lazy-grid coverage; and inserted
  the UI planner's checklist and placement risks.
- **Architect follow-up (2026-08-27):** made every accepted Shop mutation
  advance the state epoch so refreshes begun during equip/purchase cannot apply
  stale pre-commit state, extended the concurrency tests, and corrected the
  unchanged 400/403 equip error classification.
