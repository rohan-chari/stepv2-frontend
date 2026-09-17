# Publish Quicksand and unify Bara Gold shop cards

## Summary & user story

Publish the existing Quicksand powerup to testing and production for clients
that advertise the existing `powerups4` capability. Keep backend ownership of
availability and Gold acquisition policy. Make premium powerup shop tiles use
the same Bara Gold border and centered label treatment as premium character
cards so the shop has one recognizable premium-card language.

## Scope / non-goals

In scope:

- Backend release of the existing premium catalog rows (Hitchhike, Leech, and
  Quicksand) in test and production through the existing additive migration/
  config path (`testOnly=false`, `dailyRewardEligible=true`); this request's
  newly visible item is Quicksand.
- Preserve the existing `powerups4` compatibility gate so older binaries never
  receive an unsupported powerup type.
- Preserve server-authoritative Gold-only acquisition, Daily Spin eligibility,
  mystery/race-box exclusion, and grandfathered inventory use.
- Frontend reuse/generalization of the character Bara Gold card border and
  centered label for premium powerup tiles, including light/dark themes.
- Tests-first backend integration coverage and real Flutter shop widget coverage.

Out of scope: new Quicksand behavior/art, pricing or economy changes, release
flags, entitlement changes, App Store/TestFlight/Play uploads, or production
deployment in this implementation turn.

## API contract

No endpoint shape changes are required. The existing catalog response remains
additive and server-authoritative:

`GET /shop/powerups` keeps its existing envelope and returns `coins` plus an
`items` array. The Quicksand item includes the additive policy fields
`powerupType`, `requiresGold`, `goldEligible`, and `purchaseEligibility`.
Purchase keeps its existing request/idempotency contract and returns
`403 {"code":"GOLD_REQUIRED"}` for a non-Gold acquisition attempt.

The backend must continue filtering Quicksand for clients without
`powerups4`; capable clients receive it in testing and production. Missing
premium fields remain safe for the Flutter client and never cause it to invent
premium policy.

## Data/config path

- Use the existing backend migration
  `20260916180000_gold_premium_powerup_catalog` and verify its row update covers
  Hitchhike, Leech, and Quicksand in the test database and the production
  release plan. The broader row update is intentional because those premium
  rows were introduced together; no new economy numbers are changed here.
- Do not add a duplicate catalog row, migration, feature flag, or client-side
  allowlist.
- Confirm the existing `storeOnlyTypes` configuration continues excluding
  Quicksand from mystery/race-box drops.
- Invalidate or allow the documented bounded TTL for all capability/channel
  variants of the cached powerup catalog after applying the migration.

## Frontend plan

- Extract the character card’s Bara Gold border/label geometry into a shared
  catalog-card treatment or extend `PremiumItemFrame` to support that exact
  centered label variant.
- Apply it to premium powerup tiles based only on server `requiresGold` and
  `goldEligible` metadata; preserve the existing Gold-only action path.
- Keep compact tile art, name band, price strip, loading/error behavior, and
  responsive grid geometry intact.
- Render safely when additive fields are missing: ordinary legacy tile, with no
  local Quicksand classification.
- Exercise both iOS and Android through shared Flutter code; no platform
  conditional is needed.

## Backward compatibility & rollout

Deploy backend first, then the app if a frontend binary is needed. Frozen old
clients remain protected by `powerups4` filtering and continue seeing their
existing response shape. New clients tolerate an older backend missing the
additive premium fields. No release flag is permitted or needed.

Production deployment and any store upload require separate explicit approval.

## Tests-first plan

Backend:

- Real integration test: capable testing/production-channel catalog exposes
  Quicksand after the publish migration; incapable clients do not.
- Real integration test: Gold/non-Gold acquisition and Daily Spin behavior
  remain unchanged; non-Gold purchase cannot debit coins.
- Real integration test: Quicksand remains absent from mystery/race-box pools
  and existing inventory remains usable.

Frontend:

- Real shop widget test: premium powerup renders the same centered Bara Gold
  label and border geometry/key behavior as a premium character.
- Test both themes and non-premium/legacy-missing metadata fallbacks.
- Preserve the existing Quicksand renderer/copy and purchase-route assertions.

## Acceptance criteria / definition of done

- Quicksand is published for capable clients in testing and production via the
  existing backend path, with no old-client leakage.
- Server policy remains authoritative for Gold access and reward pools.
- Premium powerup and character cards visibly share the Bara Gold treatment.
- New tests are written before implementation and pass; existing assertions are
  not weakened; `flutter analyze` is clean.
- Backend reviewer and code reviewer have no blockers, and the manual UI plan
  below is completed by the user before release.

## Manual UI-placement test plan

1. Shop → Powerups: verify Quicksand appears for a capable test/prod account,
   has the centered Bara Gold label and matching gold border, and its art/name/
   price remain contained in the tile.
2. Compare Shop → Characters: verify premium character and premium powerup use
   the same label placement, border thickness, corner radius, and inset across
   light and dark themes.
3. Test a non-Gold account: verify the tile remains visible, shows the existing
   Gold-only action, and does not purchase or unlock Quicksand.
4. Test a Gold account and an account with existing Quicksand: verify purchase,
   quantity display, and use remain intact; no premium frame clips at 320px,
   normal width, or enlarged text.
5. Repeat the real Shop route and the Settings Shop Tutorial/preview harness;
   verify the card remains mounted, spotlight/layout targets are not displaced,
   and Back/navigation safe areas remain unchanged.

## Revision log

- Initial draft: separated publication/configuration from frontend styling;
  preserved `powerups4` compatibility and backend-owned policy.
- Gap pass 1: added test/prod channel verification, no-allowlist rule, and
  grandfathered-inventory/mystery-box checks.
- Gap pass 2: added tutorial/preview mirror checks and explicit missing-field
  fallback behavior.
