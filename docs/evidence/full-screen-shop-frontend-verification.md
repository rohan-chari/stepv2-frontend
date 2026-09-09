# Full-screen Shop frontend verification

Implementation follows the approved full-screen Shop requirements and coordinated `canPreview` contract addition. No artwork, economy values, backend deployment, platform build, or upload was performed by the frontend implementation agent.

## Implemented surfaces

- `ShopTab` is a dedicated pushed route with Back, balance, and Featured / Powerups / Characters navigation. Powerups retain local Buy / Owned, sorting, quantities, and purchase/ad policies. Product cards use actual layout constraints and compact 3/4/6-column geometry. Actual merchandise purchase actions use the primary treatment.
- Character collection cards show owned/locked/active status and saved character-specific art. Owned menus expose Edit outfit and Use character independently. The wardrobe route has header/exit, Save / Reset above the preview, compatible accessories, and Other owned items. Purchasing keeps ownership independent of draft discard.
- The controller and backend service consume the four additive v1 endpoints. Complete outfit slots and revisions are validated before enabling replacement or activation. Unknown/missing contracts or bare 404/405 responses retain legacy character browsing and purchase while disabling unsafe outfit actions.
- Wardrobe reads reject stale completions, restart incoherent page sets, retain dirty preview art, and allow further pagination after superseding a pending page. Auth changes invalidate menus/requests and release busy exits. Lost save or activation results are verified against freshly fetched authoritative state before reporting success.
- The real Shop tutorial measures six targets across the collection and wardrobe routes without wardrobe writes. Offline preview pushes/exits/reopens the Shop, supports per-character state, resets scenario state, and includes earned/unavailable/legacy-preserved examples plus delayed-response gates. Its network guard covers the new controller and screen.
- Profile's Membership entry and its spacing were removed; Featured retains Bara+. Home had no membership shortcut; real Home and tutorial-preview Home regressions assert Shop remains reachable. General tab tutorial and demo race contain no ShopTab and continue rendering existing public equipment fields.
- Parent-owned billing components supply typed pending/terminal results and anchored dismissible toasts. Shop and wardrobe provide measured header anchors and dispose their own feedback.

## Defensive compatibility

Missing ownership never grants ownership or purchase authority. Missing `canPreview` permits inspection only. Missing/invalid revisions, malformed/duplicate/unknown slots, missing expanded items, or hidden outfit contents make the outfit read-only. Missing asset metadata uses existing fallbacks. Unsupported additive endpoints never trigger legacy complete-outfit writes. Existing merchandise purchase/equip API implementations remain available for old clients and unrelated supported paths.

## Assertion migration map

The spec explicitly superseded the old navigation, direct-equip, and card geometry assertions. Their behavioral equivalents were retained:

| Previous assertion | Approved equivalent |
| --- | --- |
| Global Store / Inventory and Accessories category | Three Shop destinations; local Powerups Buy / Owned; owned and purchasable accessories together inside character wardrobe |
| Landing live-preview stage | No preview on merchandise destinations; explicit saved/draft preview below wardrobe controls |
| Tap accessory then EQUIP | Inspect/preview accessory, Save outfit; retain ownership, conflict, error, price, and authoritative equipment assertions |
| Capybara inventory tile / EQUIPPED | Always-present default character card / ACTIVE; Use character clears the public CHARACTER slot |
| Cosmetic preview before purchase | Character-specific draft selection and explicit purchase sheet; no implicit purchase or save |
| Tall powerup footer touch target | Compact visual strip inside a full-card minimum 48px interaction target |
| Old tablet column count | Shared compact 3/4/6 breakpoints measured from actual constraints; readable art and preserved sort order |
| Refresh discards a removed try-on | Refresh retains unsaved draft art, blocks unsafe Save, and Reset restores authoritative saved state |
| Conflict preserves equipped appearance | Authoritative equipment stays unchanged; unsaved compatible draft remains available for review |

Historical fixture migration uses `LegacyShopWardrobeFixture` only to adapt older in-memory test fixtures. Independent real-screen v1 fixtures verify new saved-outfit and activation authority; historical adapters do not substitute for those tests.

## Verification

The initial frontend-owned diagnostic run passed **109 tests in 13 suites**:

- `full_screen_shop_test.dart`
- `home_shop_entry_test.dart`
- `profile_membership_entry_test.dart`
- `character_wardrobe_screen_test.dart` (initial 25 cases; now 29)
- `shop_tab_store_inventory_test.dart`
- `shop_tab_buy_confirmation_test.dart`
- `shop_ad_unlock_and_type_scale_test.dart`
- `batch_2026_07_26_shop_test.dart`
- `batch_2026_08_09_shop_spacing_test.dart`
- `turtle_character_test.dart`
- `accessory_layering_and_compatibility_test.dart`
- `billing_preview_network_guard_test.dart`
- `preview_wardrobe_fixtures_test.dart`

New cases were introduced before their corresponding implementation fixes. Confirmed red-to-green regressions include unowned preview/purchase eligibility, account-switch busy cleanup, duplicate outfit IDs, stale paging and paging-busy recovery, lost save/activation reconciliation, and Profile membership removal. The six-target tutorial, old-server fallback purchases, and complete purchase/save/discard/activate journeys exercise real widgets.

The parent orchestrator owns final full-suite execution, independent code review, visual evidence, and combined billing verification. Both iOS and Android use the same shared Dart changes. Follow-up acceptance tests run explicit iOS/Android variants with real iOS edge swipes and Android system Back, clean wardrobe/Shop exits, protected dirty and pending saves, and labeled Keep/Discard handling. Profile removal runs on both platforms. The final two affected suites pass 31 tests. The follow-up also verifies Characters collection page deduplication/revision reset and the explicit compatible-empty prompt alongside Other owned items. Platform builds are separately coordinated by the parent and are not claimed by this report. Manual placement verification and backend-first release gates remain in the approved requirements/readiness documents.

## Combined parent verification

The complete Flutter suite passed **3,180/3,180 tests** with no failures, and `flutter analyze` reported no issues. This includes the parent-owned billing, dressing-room, preview and shell-navigation migrations. [Command results and source fingerprints](full-screen-shop/frontend-final-checks.json) record the exact verified source. The two shell Back tests first reproduced the end-of-frame/reverse-transition timing failure and then passed with waits matching the real route lifecycle; their write-count and Home appearance assertions remain intact.

Final expanded full-suite checkpoint: **3,186/3,186 passed** in 123 seconds, including all final acceptance additions and parent standalone Get Coins coverage. Source fingerprints were refreshed. Local paired platform builds are now parent-owned work in progress.

Paired local production-configuration builds also passed: iOS IPA and Android prod AAB, both version 2.3.13 at validation build mapping 10 / 203140. Actual artifact metadata, AAB validation and SHA-256 hashes are recorded in [platform evidence](full-screen-shop/platform-build-verification.json). No uploads occurred. Final post-build analysis remains clean and source fingerprints still match the expanded test run.
