# Trail Mine visibility and accessory preview requirements

## Approved scope and user story

A player can see where their own active Trail Mine was planted. A shopper can
preview an unowned accessory on their equipped compatible character, or a
server-approved fallback, in the existing environment scene before buying.
The existing application purchase menu gains Preview. Character and accessory
artwork loses both the lock icon and dark overlay; gold prices and ownership
controls remain. The user confirmed this scope, instructed implementation to
proceed, and initially authorized TestFlight only. The latest instruction defers that
upload so additional changes can be packaged together. Complete implementation,
tests and review now; leave building/uploading for the combined release. No App Review submission or
replacement is authorized; the existing build 19 submission remains untouched.
No gameplay, prices, odds, ownership rules, or artwork changes are intended.

## Backend API contract — locked

### Owner Trail Mine placement

Existing authenticated `GET /races/:raceId/progress` and race bootstrap progress
retain their exact current contract. An existing owner-visible ACTIVE Trail
Mine entry in `powerupData.activeEffects` gains optional
`trailMine: { positionSteps: number }` when stored `metadata.positionSteps` is a
finite nonnegative number. Keep `expiresAt: null`, `onSelf: true`, and all
existing fields. Missing/malformed placement omits `trailMine` without dropping
the effect. Do not serialize raw metadata. Rivals and teammates never receive
another player's planted mine or placement. Derive this at viewer projection
time from the existing shared raw effect snapshot, with no added queries.
Triggered/blocked/expired effects disappear through existing ACTIVE filtering;
existing plant-feed privacy and gameplay stay unchanged.

### Read-only accessory preview

Add authenticated `GET /shop/items/:itemId/preview`, using existing release
channel and `characters` / `remote_assets` capability headers. No request body
or new required query parameters. Return HTTP 200:

```json
{
  "itemId": "accessory-id",
  "canPreview": true,
  "unavailableReason": null,
  "usedFallbackCharacter": false,
  "character": {
    "characterKey": "default",
    "name": "Capybara",
    "item": null
  },
  "accessories": [
    {
      "id": "accessory-id",
      "sku": "example_hat",
      "name": "Example hat",
      "slot": "HEAD",
      "assetKey": "example_hat",
      "renderMetadata": {}
    }
  ]
}
```

`accessories` is the complete final preview outfit, INCLUDING the candidate,
using existing render-only equipped-item fields (`id`, `sku`, `name`, `slot`,
`assetKey`, `renderMetadata`, optional `bobble`, `assetVersion`, `assetUrl`).
A nondefault `character.item` uses that same render-only shape; default has
`item:null`. No invented economic quote or purchase eligibility is included.
The app must render this context without guessing item fits or combining it
with a different character/outfit. Current scene/background decoration is
client presentation; there is no backend environment preference to mutate.

Resolve character entirely on the server from `shop_item_character_fits`:
first the user's active character if active, visible and approved; then the
approved default; then another active visible approved character in stable
`sortOrder,id` order. An unowned fallback mannequin is allowed if not earn-only;
an owned active character may be earn-only. Default also requires an explicit
approved fit. Channel/capability-hidden characters must never leak. Set
`usedFallbackCharacter` according to whether the chosen character differs from
the actual active character; it reveals no hidden character identifier.

For the chosen character, reuse its current outfit when active or its saved
wardrobe otherwise. Retain only owned, active, visible accessories with an
approved fit. Replace the candidate's slot and remove accessories conflicting
with the candidate under existing server accessory compatibility rules. Resolve
any remaining legacy outfit conflicts deterministically in slot order. An
unowned mannequin begins with an empty outfit. Preview never saves, equips,
activates, purchases, grants ownership, repairs legacy rows, increments any
revision, or changes coins. Existing wardrobe GET ownership restrictions and
all mutation contracts remain unchanged.

A visible inactive candidate returns HTTP 200 with `canPreview:false`,
`unavailableReason:"inactive"`, `usedFallbackCharacter:false`,
`character:null`, `accessories:[]`. An otherwise visible candidate without any
approved visible eligible character uses `unavailableReason:"no_compatible_character"`
and the same empty context. Missing, channel/capability-hidden, CHARACTER-slot,
or unowned earn-only candidates return HTTP 404 with existing AppError shape
`{ "error": "Shop item not found", "code": "ITEM_NOT_FOUND" }`.
Missing authentication uses existing HTTP 401 behavior. Failed infrastructure
reads use the existing HTTP 500 handler; never invent preview context.

Bounded read plan: one candidate lookup; load current/default candidates by
specific keys and, only when needed, select the first eligible approved fallback
through the indexed fit relation with `take:1`, ordered by `sortOrder,id`.
Reuse bounded `readState` from `src/modules/cosmetics/characterWardrobeState.js`
for at most the active and selected wardrobes, and query only IDs in those
bounded slot sets for ownership/fit validation. Never enumerate all character
fits, user ownership, or wardrobes. Record query count in implementation evidence.
Use a bounded read-only snapshot transaction and existing fit indexes; no
migrations or new flags. Do not share-cache personalized preview results.
Older clients ignore additive mine metadata and never call the new endpoint;
new clients receiving 404/absent preview metadata show unavailable preview.

## Implementation path

Backend: extend the owner effect projection in
`src/modules/races/queries/getRaceProgress.js`, reusing metadata already selected
by `raceProgressSnapshot.js`. Add the preview query and route under
`src/modules/shop`, reusing `characterWardrobes.js` fit/visibility serializers
and `accessoryCompatibility.js` conflict policy. Keep the existing wardrobe
ownership restriction. There is no schema change, backfill or migration.

Frontend: add the optional preview GET in `lib/services/backend_api_service.dart`
and defensive render-context parsing. Extend `_openStoreCosmeticSheet` /
`_showItemSheet` in `lib/screens/tabs/shop_tab.dart` using existing parchment,
pixel text and PillButton styling. Retain Buy, ad, insufficient-coins and
idempotency behavior. Reuse `HomeHeroScene` and
`AnimatedCapybaraWithAccessories` composition from
`lib/screens/character_wardrobe_screen.dart` in a read-only modal. Preserve the
current client environment. Render the server's final accessory set verbatim;
never save, equip, activate or purchase from a preview load or close action.
Show loading, unavailable, failure/retry and close states, with session guards
so late responses cannot display another account's data. Use existing motion
and remote-asset fallback handling. A fallback label identifies the displayed
character without implying the user's equipment changed.

Remove `LockedShopArt` decoration at `shop_character_card.dart` and wardrobe
accessory tiles, retaining ownership labels, selection, price, taps and save
eligibility. Explicit user reversal supersedes only lock/scrim visual test
expectations; preserve all unrelated assertions.

Render valid `trailMine.positionSteps` within the existing Trail Mine row in
`race_detail_screen.dart`, along with its existing Until used state. Missing or
malformed values retain the generic row. Do not add duplicate rows or expose
rival mines. Audit races-tab badges and update demo/tutorial/billing fixtures
for positive shared-screen coverage. Do not alter mine trigger or penalty rules.

## Tests first and acceptance

Backend real HTTP tests use a dedicated test database, never production. Cover
owner/rival/team views, cold and warm snapshots, multiple mines, missing metadata,
trigger/blocked removal, default/current/fallback compatibility, hidden or
inactive content, conflicts, old capability headers, and repeated previews
leaving coins, ownership, equipment and revisions unchanged. Confirm bounded
queries and no preview writes. Prepare failures before query logic changes.

Frontend real-widget tests first: Buy and Preview use the existing menu;
compatible and fallback contexts render with current scene; loading/error/
missing fields are safe; closing preview makes no mutation; session changes
reject stale results. Confirm locks and scrims absent while purchase/edit/save
behavior stays intact. Verify owner placement and generic missing-field rows,
expiry refresh, mirrors, narrow sizes and larger text. Run relevant suites and
clean `flutter analyze`, then independent code review. Existing unrelated
baseline failures remain disclosed; do not weaken them.

## Compatibility and release

Old clients ignore the optional mine metadata and retain their existing purchase
and wardrobe flows. New clients tolerate missing metadata and unavailable new
preview endpoint without breaking Buy. Deploy compatible backend first and
verify production GET behavior before the new app upload. Keep production at
its current worker capacity and staging stopped. For a subsequently authorized combined release, read README before each
build/upload, allocate matching unused iOS/Android versions, build and verify
both platforms, then upload iOS to TestFlight and confirm tester-group
availability. No build/upload is part of the current completion step.
No Play upload or App Review changes. No feature flags or new content assets.

## Revision log

Pass 1: confirmed mines already appear as owner-targeted active effects; add
placement to existing rows instead of a duplicate effect list. Reuse raw cached
snapshot metadata and preserve viewer privacy without additional queries.
Pass 2: paginated wardrobe reads cannot establish candidate compatibility;
pinned a dedicated read-only preview context. Server resolves all fits, saved
outfit conflicts and hidden-content policy; client retains environment because
no persisted server environment field exists. Unowned fallback is a mannequin,
not an ownership grant. Explicitly retain purchase and wardrobe restrictions.
Architect review: approved after adding bounded candidate/fallback/wardrobe reads, complete frontend lifecycle and validation/release sections, and a success example containing the candidate. No remaining required architectural changes.

## Manual UI-placement test plan

1. **Shop artwork and accessory Preview:** Home → Shop → Characters, then
   Accessories → accessory Buy menu → Preview. Character artwork has no lock
   or overlay. Preview appears once beside the existing purchase action, shows
   the accessory on the compatible character in the current environment, and
   closes back to its originating flow without duplicate dialogs.
2. **Compatible-character fallback:** With prepared incompatible current
   character data, Preview shows the server-approved fallback wearing the item.
   Unavailable data shows an unavailable state instead of a misleading preview.
3. **Wardrobe and its Buy menu:** Shop → character Edit → accessory grids →
   unpurchased accessory → Buy → Preview. No grid locks or overlays; names,
   selection markers and controls remain positioned correctly. Closing restores
   the wardrobe flow.
4. **Owner Trail Mine:** Active race → Active Effects. Position appears within
   its existing row, without a duplicate card. Missing position retains the row
   without an empty placeholder. Another participant cannot see the mine.
5. **Races and tutorial mirrors:** Races-tab badges remain compact. Settings →
   VIEW TUTORIAL and fresh-account demo race use prepared mine fixtures; shared
   detail rows show position and spotlight targets remain aligned.
6. **Shop tutorial and billing preview:** Settings → VIEW SHOP TUTORIAL →
   wardrobe; offline preview → Shop / VIEW RACE STASH. Artwork stays unobscured;
   supported fixture menus expose Preview and fixture mine rows show placement.
7. **Narrow iOS and Android:** Repeat modal, wardrobe and mine row at small
   widths and large text. Art, position text, close and action buttons remain
   within bounds and reachable; tile/Edit taps still work.

Placement risks: wardrobe and Shop purchase entrances both need coverage;
races-tab badges are separately implemented; demo/tutorial/billing fixtures
need positive mine/preview data. Box opening and general tutorial Home do not
render these changed components. No manual physical-device pass is claimed.
