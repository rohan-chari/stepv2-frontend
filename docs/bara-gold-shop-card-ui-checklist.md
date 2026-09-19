# Bara Gold shop card: UI check

## Scope

Keep the existing live sky, scrolling ground, capybara and cape. Replace the
old button strip with a naturally sized benefits panel and a larger CTA.
The scenery banner is now 30 logical pixels shorter, with its subtitle
removed in every orientation. Its visible height is 160 at normal text size
and 184 with large text. The title, avatar size, terrain scale, benefits panel
and CTA keep their existing styling. No new assets or dependencies are required.

The four rows describe the current paywall benefits: ad-free play, exclusive
characters and shop power-ups, monthly coin bonuses, and ad-free Daily Spin
and box rerolls. The mockup's one-reroll limit is not introduced as a new rule.
No prices, rewards, entitlement checks or purchase flows change.

## Manual placement checklist

1. **Live Shop, Featured:** Open Shop on a non-member account with Gold
   available. The shorter hero shows the Bara Gold title without the old
   "Ad-free. Exclusive perks." subtitle. One benefits panel follows it. All four
   rows appear in order, with one Upgrade button below them. There is no
   second button over the grass or avatar. The coin offers and remaining
   shop sections follow the card without overlapping it.
2. **Shop entry links:** Open Shop through a coin entry and through an
   Upgrade/Learn more entry. Confirm scrolling still reaches the intended
   section. Tapping the hero, a benefit row or the CTA opens the existing
   membership details sheet once; the sheet itself is not redesigned here.
3. **Shop walkthrough:** On the first-time Shop walkthrough, or a replay,
   confirm the Featured section does not cover a spotlight target or
   strand the walkthrough above the power-up section.
4. **Billing preview mirror:** Run the existing billing preview entry point,
   open Shop with the free sample account, and repeat the placement check.
   This uses the real ShopTab and BaraPlusCard, not a separate mockup. Use
   preview controls to switch day/night and confirm there is no duplicate CTA.
5. **Small screens and accessibility:** Repeat on a narrow phone in both
   themes, then with large system text and Reduce Motion. Benefit text and
   the CTA must wrap and remain reachable by scrolling. Check that the
   capybara's feet stay on the grass, the title does not overlap the avatar,
   and the footer does not clip it. In any supported rotated preview, the
   subtitle must remain absent; this change is not orientation-specific.

## Surfaces unchanged in source

- BaraPlusScreen/BaraPlusBody: separate membership details and checkout UI.
- HomeHeroScene and AnimatedCapybaraWithAccessories: shared renderers are not
  changed, so the Home hero and accessory previews retain their layout.
- TutorialRealHost: has no ShopTab page and disables BillingScope. No new
  membership card is added to that tab/tutorial host.

## Verification status

Updated both shop-card widget tests to assert that the subtitle is absent.
The benefits tests cover the compact hero dimensions, unchanged avatar and
terrain sizes, tap callback, policy visibility, reduced motion and narrow/
large-text layouts in both palettes and orientations. Existing unrelated
assertions, including the 56-pixel CTA minimum height, remain intact.

Pending locally (Flutter/Dart are not installed in the editing environment):

```sh
dart format lib/widgets/bara_plus_card.dart test/bara_gold_shop_card_avatar_test.dart test/bara_gold_shop_card_benefits_test.dart
flutter analyze
flutter test test/bara_gold_shop_card_avatar_test.dart test/bara_gold_shop_card_benefits_test.dart
```

No Flutter test run, simulator or device render, full-suite run, platform build
or independent subagent review was performed. The checklist above is not a
record of completed manual testing.
