# Shop Decoy and accessories revision

## Summary and authorization
Restore Decoy for 150 coins and prevent reactivation for one hour after a targeted attack pops it. Make unpurchased accessories discoverable directly in Shop. The user explicitly authorized implementation, backend deployment if needed, and TestFlight upload in the task; no additional approval gate is needed.

## Scope and frontend plan
Retain the existing green/pixel shop design. Rename Characters & Accessories to Characters. Add an Accessories section after Characters, showing unowned non-character catalog items through existing purchase sheets. Include Edit outfit under Accessories for the active character, retaining existing character-menu editing. Keep ownership, purchase refresh, ad/top-up behavior and compatibility filters. Show appropriate loading/error/empty states and safe older-backend fallback. Update tutorial wording and anchors as required.
Scale displayed powerup artwork down and character artwork slightly up within existing cards; keep card size, text, and hit targets. No source bitmap editing or new artwork. Shared Dart applies to iOS and Android.
Implementation: lib/screens/tabs/shop_tab.dart (existing _buildStore, _storeCosmeticTile/purchase flow, character menu); lib/widgets/shop_character_card.dart (shop-specific display scaling). Avoid globally changing RacerAvatar.

## Backend and API contract
Use existing catalog, purchase, inventory/redeem and powerup-use endpoints; no new required request fields or changed response shapes. Remove all permanent Decoy sale exclusions (including ad purchase only if it is the normal shop affordance), seed/migrate the existing POWERUP_DECOY row to priceCoins150 and active sale availability. Preserve all unrelated live balance settings and box odds.
Add a race/user scoped post-consumption cooldown of 3600000ms; activation itself does not start it and ordinary duration expiry does not count as a pop. All attack consumption paths must record the same durable timestamp inside the existing command transaction and participant/race serialization. Reject reuse before expiry with a stable 409 error and retainHeld:true, without deducting inventory or coins. Allow reuse at the exact boundary. Preserve current active-Decoy guard and existing redirect/absorb logic. Add nullable RaceActiveEffect.decoyConsumedAt and an index on (targetParticipantId, type, decoyConsumedAt), with no speculative backfill. Atomically stamp with EXPIRED in consumeDecoy and the Power Outage bulk-consumption branch. Query most recent matching consumed effect with timestamp strictly greater than now minus3600000ms. Do not add AoE participant writes: preserve the single-writer invariant. Pin the error as code DECOY_COOLDOWN, HTTP409, message explaining the wait, internal retainHeld:true handling; inspect and document the actual existing serialized error envelope rather than exposing an invented details field.
Relevant modules: src/modules/powerups/commands/usePowerup.js (consumeDecoy and other consumption sites, Decoy use validation); queries/getPowerupShopCatalog.js; commands/purchasePowerupItem.js; commands/unlockPowerupWithAds.js; economy/commands/grantAdReward.js; routes/shop.js; prisma/seed.js and a narrowly scoped new migration. Implementation agent must pin exact error JSON and persistence choice before frontend dependency work.

## Compatibility and performance
Backend first. Older clients may keep hiding Decoy but held items retain valid use/error behavior; legacy headers must have a public HTTP integration test. Bundled Decoy/accessory assets already exist, no new content flag required. Do not change API shape or other powerup eligibility. All cooldown authority is server-side, at most one bounded indexed check per Decoy activation, no added step-sync work. Ensure any effect cleanup retains cooldown evidence for the whole hour. Preserve exactly two production HTTP workers and leave staging stopped.

## Tests first
Backend: real HTTP/local test DB catalog price, coin purchase and standard alternate purchase paths; activate then pop then immediate reuse rejection/unchanged inventory; reuse at one hour; activation/natural expiry alone not cooling; redirect and absorb consumption paths, concurrency, old-client response. Confirm dedicated local/test DATABASE_URL before running.
Frontend: real Shop renders Decoy and150 from server, unowned Accessories section and purchase flow/ownership refresh, owned exclusion, Edit outfit navigation, missing catalog/backend states, section tutorial anchors and art-only sizing. Existing assertions that require retired Decoy or combined section are obsolete under the explicit requested behavior; surface and update only those expectations to assert restored sale/separate sections, never weaken unrelated assertions.

## Release acceptance
Required architect/economy/UI/code reviews; flutter analyze clean and relevant/full tests passing. Read README immediately before builds, retain required iOS configuration and omit inline native units. Build next unused iOS build and matching higher Android versionCode; verify signed artifacts and source/config, deploy backend safely first, upload via existing ASC API key, wait for VALID/IN_BETA_TESTING and existing internal tester group membership. No App Review submission or Play upload requested.

## Revision log
Pass1: scoped cooldown to race/user consistent with existing active-Decoy behavior; separated pop from normal expiry and preserved inventory on denial.
Pass2: covered alternate purchase exclusions, old backend fallback, tutorial mirror, no global sprite resizing, and safe targeted migration of live catalog without re-seeding economy.
Architect: use indexed effect consumption timestamp, not JSON outbox scan or AoE participant writes; cover bulk Power Outage consumption. Economy: production row75 inactive, testOnlyfalse, daily reward exclusion remains; preserve live rare-drop settings. Architect required corrections incorporated: effect cleanup must retain consumed evidence at least one hour; test real serialized error and both held/inventory-redeemed use including bulk consumption.150 is the base price; preserve existing membership discount. Edit outfit follows active-character editing eligibility and truthful legacy unsupported state.

## Manual UI-placement test plan
**Manual UI-Placement Test Plan — Shop sections and asset sizing**

*Elements under test:*

Decoy returns to the main Shop’s Powerups grid.

Unpurchased accessories gain their own Accessories section; Characters becomes a separate section.

Edit outfit is available beneath Accessories.

Powerup artwork becomes smaller and character artwork larger within existing cards.

*Checklist*

1. **Real Shop**
   - **Get there:** Home → Shop, using an account with some unpurchased accessories.
   - **Verify:** Sections appear once in order: Featured, Powerups, Characters, Accessories. Decoy appears once among powerups. Unpurchased accessories appear directly under Accessories without first opening a character. Accessories are not mixed into the Characters grid. Edit outfit appears under Accessories.

2. **Shop artwork and alternate entry**
   - **Get there:** Home → coin balance “+” → scroll through Shop.
   - **Verify:** The same sections appear. Compare several powerups against owned and locked characters: artwork occupies comparable visual space, stays centered, and does not overlap names, badges, or neighboring cards. Cards retain their existing dimensions.

3. **Outfit editor**
   - **Get there:** Shop → Accessories → Edit outfit.
   - **Verify:** The editor opens with character preview and accessory sections visible. Back returns to Shop with Accessories and its edit entrance still present once. Check the existing owned-character menu remains reachable under Characters.

4. **Shop tutorial and its wardrobe preview**
   - **Get there:** Profile → Settings → VIEW SHOP TUTORIAL.
   - **Verify:** Complete every spotlight step. Shop spotlights surround the intended section/card after resizing. The wardrobe preview, accessory grid, controls, and Back spotlights still align. On returning to Shop, Accessories appears in its new position with no duplicate section or edit entrance.

5. **Offline billing preview — development build**
   - **Get there:** Open a device build using `lib/main_billing_preview.dart` → Shop.
   - **Verify:** The shared Shop layout includes Accessories and Edit outfit. Fixture-backed accessories and Decoy are actually visible; an empty fixture is not a successful placement check.

Run checkpoints 1–4 on both iOS and Android, including the smallest available device.

*Surfaces confirmed unaffected:*

- **General tab tutorial:** `tutorial_real_screens.dart` renders Home’s Shop entrance, but does not render Shop itself; preview navigation is disabled.
- **Demo race tutorial:** `demo_race_host.dart` does not render Shop or the character wardrobe.
- **Race detail, race inventory, and box openings:** Shop-only artwork sizing does not change their separately rendered assets.
- **Tutorial tab bar:** Shop is opened as a route; no tab item moves.

*Risks found while planning:*

- Shop tutorial has section/card anchors; its wardrobe continuation has separate preview/grid/control/Back anchors.
- The existing wardrobe intentionally has Owned and Locked accessory sections. Adding main-Shop browsing should preserve the editor’s placement unless explicitly redesigned.
- Billing preview uses hand-maintained API fixtures; new sections can render empty there.
- Keep resizing local to Shop cards to avoid changing race and tutorial sprites.

## Locked API error contract
POST /races/:raceId/powerups/:powerupId/use returns HTTP409 with exactly `{ "error": "Wait 1 hour after your Decoy pops before using another in this race", "code": "DECOY_COOLDOWN" }`. The retainHeld option stays internal; no client-required new fields.
