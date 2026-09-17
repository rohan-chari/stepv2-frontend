# Bara Gold shop subsections

## Summary & user story

As a shopper, I want Powerups, Characters, and Accessories to separate
standard merchandise from Bara Gold merchandise, so Gold exclusives such as
Hedgehog, Mouse, and Sea Lion are clearly grouped and future Gold powerups or
accessories behave consistently. Direct IAP actions should use the concise
label `BUY`.

## Scope / non-goals

In scope: the Flutter Shop screen's three merchandise categories, server-owned
Gold metadata (`goldAccess`/`requiresGold` and eligibility), subsection labels,
future premium-item behavior, direct-purchase button copy, mirrored preview and
test surfaces, and release verification. Out of scope: changing catalog policy,
prices, product flags, ownership, billing products, or backend economy rules.

## Current implementation and exact plan

- `lib/screens/tabs/shop_tab.dart` already has subsection builders for
  characters and accessories and a standard/Gold split for powerups. Verify
  all three paths use defensive metadata and retain empty/loading/error states.
- `lib/models/character_wardrobe.dart` already reads `goldAccess` and direct
  purchase metadata defensively. Preserve the server as policy authority.
- `lib/widgets/shop_character_card.dart` changes `DIRECT PURCHASE` to `BUY`
  while preserving the existing direct-purchase callback and semantics.
- Add/adjust frontend widget tests in `test/` first for all three subsection
  splits, Gold-locked and Gold-member states, missing metadata, the three named
  characters, and `BUY` copy. Use real ShopTab/card rendering with fake service
  boundaries; do not weaken existing assertions.
- No backend endpoint or migration is expected: existing catalog and wardrobe
  responses remain additive and compatible. If production inspection shows
  missing Gold metadata, stop and report it rather than inventing client policy.

## API contract and compatibility

No API shape change. Gold classification is read from existing server fields;
missing fields remain standard/unavailable according to existing defensive
defaults. Frozen clients continue receiving the same additive fields and
rendering their prior layouts. Backend remains authoritative for eligibility,
availability, pricing, and ownership.

## Frontend states and platforms

The iOS and Android Flutter screens must match. Standard and Gold subsections
render only when non-empty; loading, error, unavailable, and empty states stay
safe. Gold-locked items offer the existing membership path; Gold members retain
the existing purchase/equip behavior. No platform-specific release flag is
introduced.

## Rollout

No backend deploy is required unless production verification identifies a
missing already-supported metadata contract. If needed, deploy backend first,
then build and upload the paired iOS TestFlight artifact and verify Android in
lockstep per `README.md`/`DEPLOYMENT.md`. Do not change production item flags as
part of this UI task.

## Test plan

Write tests first, then implementation: subsection visibility and ordering for
powerups, characters, and accessories; server-driven Gold classification;
missing/null metadata; Gold lock/member states; direct action labeled `BUY`;
and existing purchase/equip behavior. Run targeted tests, full `flutter test`,
and `flutter analyze`.

## Acceptance criteria / definition of done

- All three categories visibly separate Standard and Bara Gold merchandise.
- Hedgehog, Mouse, and Sea Lion appear in the Bara Gold character subsection
  whenever the backend returns them as Gold items.
- Future Gold powerups/accessories follow the same server-driven split.
- Direct purchase displays `BUY`.
- Tests and analysis pass; iOS and Android are accounted for; manual mirrored
  UI checklist is completed; approved release is deployed/uploaded.

## Manual UI-placement test plan

- Shop → Powerups: verify Standard then Bara Gold subsection, including no Gold
  subsection when empty and Gold lock/member action states.
- Shop → Characters: verify Standard then Bara Gold; verify Hedgehog, Mouse,
  and Sea Lion placement and `BUY` action.
- Shop → Accessories: verify the same split and Gold lock/member behavior with
  a fixture containing `requiresGold`.
- Open Shop from Home, Settings, preview, onboarding/tutorial/demo surfaces;
  verify each uses the same subsection layout and scrolls to the intended
  category without blank spacing or broken spotlight targets.
- Check iOS and Android-sized viewports, loading/error/empty states, and
  accessibility labels.

## Revision log

- Gap pass 1: preserved existing backend-owned metadata and identified the
  direct-purchase copy as the remaining visible mismatch.
- Gap pass 2: added missing/null metadata, empty-state, tutorial/preview,
  accessibility, and paired-platform coverage.
- Architect/UI review: pending explicit approval and available review pass.
