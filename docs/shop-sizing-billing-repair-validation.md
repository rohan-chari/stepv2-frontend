> **Release resumed:** The owner added the Bara+ hold and outfit-editor changes,
> explicitly requested direct implementation, and authorized deployment afterward.
> The earlier build hold is superseded. Final verification covers the combined batch.

# Shop sizing and billing repair validation — 2026-09-10

## Final animated-preview additions

The owner added icon-only Shop/wardrobe back controls, a clearer accessory
selection state, and the Home environment with the walking draft character.
These reuse the existing scene and renderer; no shared renderer or artwork was
changed. Day/night and reduced motion follow the current app settings. Selected
accessories have a stronger border and check badge. One top-right status icon
replaces the old preview-state text: green check for saved, red information for
unsaved, with a tap explanation. Existing outfit preservation and save/purchase
safeguards remain.

The initial build14 archive completed before these additions; it was never
uploaded and is superseded by a rebuilt archive of the final source. Final scene
captures are in `artifacts/shop-outfit-scene-2026-09-10/`; the earlier
`shop-outfit-repair-2026-09-10/` images document the superseded white-card layout.
Latest independent review: **SHIP**, no issues,52 independently passing tests.
Targeted results:50 wardrobe tests,128 external navigation/billing/cosmetic tests,
and2 Shop tests passed. Final combined full suite: **3,309 passed, zero failures**
(2m08s), `/tmp/bara-shop14-scene-full-test.log`. Final analysis clean (7.4s),
`/tmp/bara-shop14-scene-analyze.log`.

## Earlier additions

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

Verified pair: iOS **2.3.13 (14)** and Android **2.3.13 / 203144**, runtime source
`5071aa2`. Both were rebuilt after the final animated-preview additions. Actual
signatures, required README configuration, native code and artwork passed checks;
see [artifact verification](artifacts/shop-outfit-release-2026-09-10/README.md).

iOS uploaded successfully with the existing ASC key: both `Upload succeeded` and
`EXPORT SUCCEEDED` were confirmed. Existing AppLovinSDK and FBAudienceNetwork dSYM
warnings did not block upload. The earlier intermediate archive was not uploaded.
No new backend deployment, App Review, customer release or Play upload occurred.
Apple confirmed **VALID / IN_BETA_TESTING** at2026-09-10T13:34:34Z.
Build14 is present in the existing **bara testers** group, with unchanged export
compliance (`usesNonExemptEncryption:false`). Apple build ID:
`6f9825a4-ecb9-4b99-876c-e6dd9e8b80c1`.
[Recorded status](artifacts/shop-outfit-release-2026-09-10/testflight-status.json).

The current [manual UI checklist](shop-outfit-release-checklist.md#manual-ui-checklist)
covers Shop, coin entry, wardrobe sections/footer, hidden Bara+ surfaces, tutorials,
iOS/Android responsive palettes and billing preview mirrors.
