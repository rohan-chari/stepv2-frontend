# Powerup Cheat Sheet Availability Requirements

## Summary & user story

Players opening the mystery-box help sheet should see only powerups that are
currently usable in the product: an active shop item or an active mystery-box
roll item for the requesting client capability set. Retired, disabled, or
otherwise unavailable powerups must not appear in either the POWERUPS or
STACKING page.

## Scope / non-goals

In scope: availability projection for the existing `PowerupGuideSheet`,
backend catalog response, bundled fallback behavior, and frontend tests.

Out of scope: changing shop prices, rarity odds, roll weights, stacking rules,
powerup mechanics, or the existing shop/inventory screens.

## Current implementation

- `lib/widgets/powerup_guide_sheet.dart` renders `PowerupCopy.guideEntries`.
- `lib/constants/powerup_copy.dart` loads `/powerups/catalog` and falls back to
  bundled copy, but currently appends bundled types missing from the response.
- `lib/services/backend_api_service.dart` calls `/powerups/catalog`.
- The existing catalog is capability-aware, but availability must become an
  explicit server projection rather than inferred from copy rows.

## API contract

Extend the existing unauthenticated `GET /powerups/catalog` response
additively. Preserve the current `version`, `stackingVersion`, and `powerups`
fields for older clients. New clients may receive:

```json
{
  "version": "...",
  "stackingVersion": 1,
  "availabilityVersion": 1,
  "powerups": [
    {
      "type": "RUNNERS_HIGH",
      "name": "Runner's High",
      "description": "...",
      "stacking": { "samePowerup": "BLOCKED", "otherEffects": "CONDITIONAL", "summary": "..." },
      "availability": { "shop": true, "roll": false }
    }
  ]
}
```

The backend must include only client-capability-compatible rows and mark a row
available when `shop` or `roll` is true. The catalog cache/ETag variant must
include the complete client capability fingerprint and the availability
projection version. Shop availability comes from active, non-test-only shop
items; roll availability comes from the active position-aware roll pool after
store-only and capability gates are applied.

Older clients ignore the additive fields and continue rendering their existing
catalog/fallback behavior. A new client receiving a response without
`availabilityVersion` must retain the current safe behavior rather than
assuming availability data exists.

## Frontend plan

1. Parse availability defensively in `PowerupCopyEntry`.
2. When a valid availability projection is present, make `guideEntries` return
   only entries where `shop == true || roll == true`.
3. Do not append bundled entries that are absent from a valid availability
   projection; this prevents retired or disabled types from reappearing.
4. If the endpoint is unavailable, old, malformed, or has no availability
   projection, use the existing bundled/cached behavior so older backend and
   offline operation remain safe.
5. Apply the same filtered list to both POWERUPS and STACKING pages.

## Data model / migrations

No database migration is required. Read existing active shop-item and active
roll-pool configuration. No Redis surface is introduced; the existing catalog
ETag/cache remains a rebuildable catalog cache.

## Test plan (tests first)

- Frontend widget tests: shop-only, roll-only, both, neither, and retired rows.
- Frontend compatibility tests: missing availability fields, old catalog
  response, malformed row, unavailable endpoint, and bundled fallback.
- Backend integration tests: active/non-test-only shop projection, active roll
  projection, capability filtering, and empty projection.
- Verify both POWERUPS and STACKING pages render the identical filtered set.

## Backward compatibility & rollout

Deploy the additive backend projection first, then the iOS and Android build.
Frozen older clients continue using the old fields and are not broken. The new
client never treats a missing projection as an empty catalog, preventing a
backend lag from hiding all help content.

## Acceptance criteria

- The cheat sheet title remains `POWERUP CHEAT SHEET`.
- With a valid availability projection, every displayed row is active in the
  shop or active in the roll pool.
- Disabled, test-only, retired, and capability-gated rows are absent.
- Both tabs use the same filtered entries.
- Missing/old backend fields preserve safe fallback behavior.
- `flutter analyze` and relevant integration/widget tests pass.

## Revision log

- Draft: separated copy authority from availability authority and preserved
  old-client behavior when the additive projection is absent.
- Gap pass 1: added test-only exclusion, capability/ETag variation, and the
  distinction between empty valid projection and missing projection.
- Gap pass 2: clarified that both tabs share the filter and that no odds,
  pricing, or mechanics change.

## Manual UI-placement test plan

- Open a mystery box and tap `?`; verify the title and both tabs.
- Verify a shop-only item, roll-only item, and disabled item appear/disappear
  as expected.
- Verify POWERUPS and STACKING contain the same filtered powerup set.
- Verify narrow phones, large text, day/night themes, and reduced motion.
- Verify the guide still opens on iOS and Android.
