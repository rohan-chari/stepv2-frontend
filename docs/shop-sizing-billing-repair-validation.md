> **Release resumed:** The owner added the Bara+ hold and outfit-editor changes,
> explicitly requested direct implementation, and authorized deployment afterward.
> The earlier build hold is superseded. Final verification covers the combined batch.

# Shop sizing and billing repair validation — 2026-09-10

## Latest additions

Bara+ entry points are commented out in Shop, Get Coins, Profile and billing
preview navigation; existing discounts, subscription handling and reconciliation
remain intact. Legacy membership focus lands on coin offers. Featured now says
“Stock up on coins for powerups and accessories.”

The wardrobe has Shop-style Owned and Unowned sections and a persistent Save
outfit/Reset footer. Incompatible saved items retain their preservation data while
the Other owned items grid is removed. Save guards and tutorial anchors remain.
Large-text visual review caught and corrected a truncated Save label before
release. Final Shop and wardrobe fixture captures have source/image hashes in
their artifact manifests; these are real widgets with bundled fonts, not live
purchase proof.

Focused wardrobe tests:49 passed. Membership visibility/core-retention tests:66
passed. Independent final code review: **SHIP**, no issues; reviewer independently
ran54 tests. [Manual device checklist and restoration notes](shop-outfit-release-checklist.md).

Final combined full suite: **3,308 passed, zero failures** (2m02s),
`/tmp/bara-shop14-final-test.log`. Analysis clean (`/tmp/bara-shop14-analyze.log`);
the final bounded test migration also passes scoped analysis. The first combined
run had one obsolete unscoped Owned-label assertion; scoping it to the accessory
retained its status check and added both section assertions. Its16-test suite
passed and the reviewer approved before the final full rerun.

Paired release-artifact results are recorded below once complete. No backend runtime changes are required for this follow-up.

## Initial repair — verified before the latest additions

Character and Powerup cards now share complete merchandise geometry, including
loading skeletons and responsive breakpoints. Every section has the approved
short description. Unowned cards show a decorative lock badge using Bara's
existing Home lock icon; owned/active cards and existing buy/edit flows retain
their statuses and behavior. Real font-loaded captures cover normal and enlarged
text in both palettes under `artifacts/shop-sizing-repair-2026-09-10/`.

Native product categories fail independently. Successful products remain available
when another category fails; optional eligibility failure cannot erase offers or
advertise an unconfirmed trial. Each refresh replaces the native checkout cache.
Initial catalog fetches show loading instead of false unavailability, while
pending transactions retain their state. Diagnostic parsing is bounded/nonthrowing
and prints only allowlisted stage/enum values, never arbitrary native payloads.

Architect approved UI and billing contract amendments. Independent code review
returned SHIP after a diagnostic parsing issue was corrected with nonnumeric and
negative-code regressions. No backend API, realm, fulfillment or price change.

## Tests first and suite migration

New tests first failed on original card geometry, missing lock, initial false
unavailability and lost category results. Final focused suite:29pass, including
real controller/RevenueCat adapter/native channel/UI, cache/pending/account guards.
Earlier broader targeted regression:109pass. Final analysis was clean.

Initial full suite:3303pass/3fail. Two older geometry assertions required Powerups
to be wider than characters, contradicting the new explicit requirement. Replaced
those with strict width AND height equality at every existing viewport; retained
numeric spacing, aspect ratio, membership and navigation checks. The nine-test
suite then passed. The third failure was a test helper tapping a now-below-viewport
character at2.5text scale. Added ensureVisible for that actual card before the real
tap, preserving all assertions; the full18-test dressing-room suite passed.
Both bounded test adaptations were surfaced to the owner and independently
reviewed SHIP. No test was skipped, weakened or deleted. Final full suite: **3,306 passed, zero failures** in2m04s. Final
`flutter analyze` clean (7.8s). Logs: `/tmp/bara-shop-repair-final-flutter-test.log`
and `/tmp/bara-shop-repair-final-analyze.log`. Collected after the owner placed
release on hold; no new build, upload or deployment followed.

## Live billing evidence

The deployed backend remains3a60332. Normal authenticated bootstrap verified
HTTP200, available:true, bara-billing-v1 and the samefive product IDs. Existing
identity/reconciliation records were checked before this normal app request;
no integration fixture, purchase or account-realm mutation was used.

ASC's6000-coin product lacked localization. Added only its en-US name/description
and verified all prices, identifiers, types and sale territories unchanged.
At12:39UTC realStoreKit returned the otherfour products. At12:44:11UTC both real
AppleStoreKit2 and the pinnedRevenueCat SDK returned ALLFIVE products with their
localized prices, including6000at$9.99; monthly eligibility lookup also completed.
No StoreKit configuration fixture or network interception was used. Temporary
identity config and disposable simulator were removed. Sanitized evidence is in
`artifacts/shop-billing-repair-2026-09-10/`; backend configuration/metadata audit is
`docs/shop-sizing-billing-backend-validation.md` in the backend repository.

This establishes real product availability and the fixes' tested failure/loading
behavior. No paid purchase or server-fulfillment transaction was performed.

## Release

Planned pair: iOS2.3.13(14), Android2.3.13/203144. Preserve every README configuration
value, verify signatures/native binaries/artifacts, then upload iOS with existing
ASC env references. No new backend deployment, App Review or customer release.

The current [manual UI checklist](shop-outfit-release-checklist.md#manual-ui-checklist)
covers Shop, coin entry, wardrobe sections/footer, hidden Bara+ surfaces, tutorials,
iOS/Android responsive palettes and billing preview mirrors.
