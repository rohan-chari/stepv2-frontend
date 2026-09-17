# Bara Gold Character Access Requirements

Status: implementation specification pending architecture review and explicit approval gate

## Summary & user story

While active Bara Gold is valid, a user can use every otherwise-visible normal
character without permanently owning it. Permanent ownership remains durable
and independent. When Gold ends, temporary access ends, the active appearance
falls back safely to the synthesized default Capybara, and the character's
saved wardrobe and user-owned accessories remain intact for future
resubscription.

Internal identifiers such as `bara_plus_monthly_v1` and `bara_gold_v1` remain
unchanged.

## Scope / non-goals

In scope:

- backend character access calculation and authorization
- additive API access-state fields
- character collection, wardrobe, outfit, activation, and dependent accessory paths
- Gold expiration repair and resubscription behavior
- coexistence with coin ownership, direct IAP, restores, refunds, and reversals
- Flutter shop, picker, wardrobe, account switching, and Gold copy
- compatibility, scale, security, and integration/widget tests

Out of scope:

- billing-system redesign
- RevenueCat identifier/configuration changes
- changing unrelated Gold benefits
- deleting direct character IAP products
- changing catalog records merely to implement access
- per-user temporary entitlement rows
- historical race mutation
- deployment unless separately authorized after validation

## Approved access model

Permanent ownership remains represented by `user_shop_items`, with provenance
in `shop_item_ownership_sources`. Gold never inserts or deletes those rows.

The backend computes:

```text
hasAccess = globallyFree OR permanentlyOwned OR activeGold
```

The response semantics are:

```json
{
  "owned": false,
  "hasAccess": true,
  "accessSource": "gold"
}
```

`owned` continues to mean permanent ownership. Recommended sources are
`owned`, `gold`, `free`, or `null` for inaccessible characters. The synthesized
default Capybara retains existing semantics.

Gold applies to every normal character returned by existing catalog,
release-channel, test-only, remote-only, and client-capability rules. No
Mouse/Hedgehog/Sea Lion allowlist may decide Gold access.

## Purchase policy

While active Gold:

- unowned characters have access through Gold
- coin character purchase is unavailable
- direct character IAP is unavailable in the UI and API policy
- the 15% Gold discount remains available for unrelated store items

When Gold expires, existing permanent purchase paths become available again.
Existing ownership and verified direct-IAP products remain intact.

## Canonical backend abstraction

Create one shared server-side abstraction, shaped to the backend conventions,
that accepts the character, permanent ownership projection, centralized Gold
membership result, and capabilities. It must return permanent ownership,
access, source, and purchase-relevant policy.

It must use `goldMembershipForUser()` or its centralized underlying authority.
It must not call RevenueCat during character requests and must not trust
Flutter state, client fields, or capability headers as proof of membership.

All security-sensitive character reads/writes must use the same authority:

- `GET /shop/characters`
- `GET /shop/characters/:characterKey/wardrobe`
- `PUT /shop/characters/:characterKey/outfit`
- `PUT /shop/active-character`
- character-slot accessory operations
- any other endpoint accepting a character identifier

## API contract

### `GET /shop/characters`

Preserve existing fields and add fields additively:

```json
{
  "characterKey": "mouse",
  "owned": false,
  "hasAccess": true,
  "accessSource": "gold",
  "active": false,
  "canActivate": true,
  "canEdit": true,
  "canPurchase": false,
  "goldAccess": true,
  "benefitVersion": "bara_gold_v1",
  "coinPurchaseAllowed": false,
  "directPurchase": {},
  "unavailableReason": null
}
```

For a permanently owned character:

```json
{
  "owned": true,
  "hasAccess": true,
  "accessSource": "owned"
}
```

For a locked character:

```json
{
  "owned": false,
  "hasAccess": false,
  "accessSource": null
}
```

New fields must be optional/default-safe for old clients. Existing capability
filtering remains authoritative for whether a row or asset is returned.

### Wardrobe read/write endpoints

Gold-accessible unowned characters may be read and edited. Expired Gold users
without permanent ownership continue receiving the existing access error or a
compatible generic unavailable error. Outfit saves never grant ownership or
accessories.

### Active-character mutation

Activation succeeds only when the server derives access through permanent
ownership, global-free status, or active Gold, and all existing visibility,
active-item, release-channel, and capability checks pass.

## Expiration and repair

If a temporary Gold character is active when Gold access ends:

1. Permanent ownership is not changed.
2. Wardrobe rows are not deleted.
3. Accessory ownership is not changed.
4. Active appearance is repaired idempotently to default Capybara.
5. Appearance revision/cache invalidation follows existing writer contracts.
6. Historical race state is not rewritten.

Use the existing character wardrobe state/repair architecture. Prefer a
bounded transactional lazy repair or narrowly scoped repair at a trusted
appearance/read boundary; do not create per-character expiration fanout.

On resubscription, access returns dynamically without inserting ownership, and
the preserved wardrobe can be selected again.

## Permanent purchase, IAP, refund, and restore requirements

- Existing permanent ownership remains available after Gold expiration.
- A purchase during Gold creates permanent ownership only through the existing
  verified purchase path, if the purchase policy permits it after Gold ends;
  while Gold is active, character purchase is suppressed.
- A refunded direct IAP revokes only its permanent provenance source.
- If Gold remains active after refund, access remains with `owned: false` and
  `accessSource: gold`.
- If Gold later ends, access is removed unless globally free.
- Restore re-establishes permanent ownership only from verified non-consumable
  history.

## Frontend plan

Update only paths that need access semantics:

- `lib/models/character_wardrobe.dart`: parse additive `hasAccess` and
  `accessSource`, default safely when absent.
- `lib/services/character_wardrobe_controller.dart`: retain account-bound
  clearing and use server state.
- `lib/screens/tabs/shop_tab.dart`: use `hasAccess` for selection, suppress
  character purchase actions for Gold access, and show temporary status.
- `lib/widgets/shop_character_card.dart`: show `Included with Gold`, never
  `Owned` for temporary access, and hide coin/direct-IAP CTAs.
- `lib/screens/character_wardrobe_screen.dart`: allow Gold-accessible wardrobe
  actions while preserving accessory ownership and fit rules.
- `lib/screens/bara_plus_screen.dart` and related Gold widgets: describe
  unlocking every character.
- preview/tutorial fixtures: update only where the real contract is mirrored.

Do not compute authorization from `BillingController.isGold` in individual
widgets. Server character state is authoritative.

## Backend plan

Likely files:

- `src/modules/cosmetics/characterWardrobes.js`
- `src/modules/cosmetics/characterWardrobeState.js`
- `src/modules/cosmetics/equipAccessory.js`
- `src/modules/cosmetics/getShopCatalog.js`
- `src/modules/cosmetics/purchaseShopItem.js`
- `src/modules/cosmetics/accessoryCompatibility.js` only where hard-coded Gold
  inclusion is policy rather than legitimate fit logic
- `src/modules/billing/queries/goldPolicy.js`
- `src/modules/home/getHomeRaceCard.js` or trusted appearance repair seam
- relevant profile/leaderboard/race presentation paths only if current-state
  repair requires them

Do not change direct IAP catalog definitions, historical migrations, or
legitimate character-specific fit rules merely because the Gold allowlist is
removed.

## Data model / migrations

Expected implementation requires no migration:

- retain `user_shop_items`
- retain `shop_item_ownership_sources`
- retain billing subscription state
- retain character wardrobes and fit tables

If the implementation unexpectedly requires a migration, stop and explain the
reason before proceeding. Do not add a Gold inclusion field or entitlement
table unless repository evidence makes it unavoidable.

## Backward compatibility and rollout

Deploy backend before frontend. Old clients must continue receiving valid
payloads and must not receive unsupported assets. Preserve:

- `owned` meaning
- `characters` capability behavior
- `remote_assets` behavior
- `bara_gold_v1` compatibility behavior
- test-only and release-channel filtering

New fields are additive and defensive. Old clients must not be required to
understand temporary-access fields.

## Scale and security

The collection path must perform one Gold membership resolution per request,
retain batched/`EXISTS` ownership checks, and compute per-row access in memory.
No RevenueCat requests, per-character entitlement rows, or expiration fanout
are permitted.

All character mutations must independently derive access server-side. Spoofed
`owned`, `hasAccess`, `goldAccess`, product IDs, billing state, or capability
claims must not grant access.

## Test-first plan

Backend integration tests must cover:

- non-Gold unowned locked
- Gold unowned accessible without permanent ownership
- permanent owner accessible without Gold
- response semantics for owned/gold/free/locked
- Gold activation and wardrobe read/save
- expired Gold rejection and safe default fallback
- preserved wardrobe/accessories and resubscription
- permanent purchase/direct IAP coexistence
- refund plus active Gold and refund plus expired Gold
- restore
- purchase suppression while Gold is active
- capability and remote-asset restrictions
- account switching
- historical race preservation
- spoofed client data and concurrency

Frontend tests must cover the corresponding card, picker, wardrobe, paywall,
account-switch, expiration-refresh, and capability states.

Use dedicated test databases for backend integration tests. Never run tests
against production.

## Acceptance criteria / definition of done

- Access is server-authoritative and centralized.
- Active Gold grants temporary access to every otherwise-visible normal character.
- No Gold action creates or deletes permanent character ownership.
- `owned` remains permanent ownership only.
- Gold access is represented separately and safely defaults when absent.
- Activation and wardrobe writes enforce access server-side.
- Character purchases are suppressed while Gold is active.
- Refund/reversal and restore preserve source semantics.
- Expiration safely falls back without deleting wardrobes/accessories/history.
- Resubscription restores access without ownership writes.
- Account switching cannot leak access.
- Old clients remain compatible.
- Query work remains bounded and no RevenueCat call occurs on character requests.
- Focused and broader tests are classified against baseline.
- `flutter analyze` is clean.
- Required code review and UI-placement checklist are complete.
- Backend is deployed and verified before any frontend release preparation.

## Revision log

### Draft revision 1

- Converted the approved product behavior into an implementation contract.
- Preserved permanent ownership and billing architecture.
- Explicitly prohibited Gold ownership writes and per-user entitlement rows.
- Added expiration repair, purchase suppression, refund, restore, compatibility,
  scale, and test-first requirements.

### Gap pass 1

- Added explicit capability/release/test-only restrictions to the Gold rule.
- Added wardrobe and accessory preservation requirements.
- Added old-client additive-field behavior.

### Gap pass 2

- Added concurrency, account-switching, historical-race, spoofed-client, and
  no-migration stop conditions.
- Clarified that direct IAP definitions and legitimate fit data remain intact.

## Manual UI-placement test plan

Before presenting the implementation as complete, manually verify:

1. Home → Shop → Characters for a non-Gold account: unowned characters retain
   locked/purchase behavior.
2. Gold account: every otherwise-visible character is selectable, shows
   `Included with Gold`, and has no character coin/direct-IAP CTA.
3. Gold account: selecting a temporary character opens its wardrobe and saving
   an outfit preserves accessory ownership semantics.
4. Gold expiration fixture/account: active temporary character safely falls
   back to Capybara and its saved wardrobe remains available after resubscribe.
5. Permanently owned character remains marked owned through Gold expiration.
6. Account A → logout → Account B: no Gold label, wardrobe, active character,
   or access state leaks.
7. Verify the real shop, character wardrobe, Gold paywall, onboarding/tutorial
   preview, billing preview, home appearance, race detail, results, leaderboard,
   and public profile surfaces.
8. Verify iOS and Android layouts and both release/capability paths.

