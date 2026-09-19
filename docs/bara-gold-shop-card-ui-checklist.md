# Bara Gold shop carousel and modal cleanup

## Scope

The Shop promo keeps its compact animated hero, cape, title and upgrade action.
The four stacked benefits are now one horizontally swipeable row. It advances
one benefit every four seconds and wraps without scrolling back across all
pages. Four small dots indicate position. At normal phone width/text size it is
56 logical pixels tall, matching the Upgrade button. Both rows share a measured
height and grow together when narrow widths or accessibility text require it.

The modal keeps its full static benefit list, two plan cards and existing
checkout controls. It uses the same benefit order, titles, icons and colors as
the carousel, with full descriptions instead of teasers. The coin icon is the
existing paw coin. Unused soil is cropped from the hero without changing the
avatar, terrain scale or animation. Selected plans and the action button use
the existing gold/day and violet/night palette. Standalone membership pages
have one centered title; embedded sheets keep their existing host title.

No billing controller, API, prices, trial rules, rewards, entitlement policy or
purchase actions are changed. No new dependency, generated art or release flag.

## Manual placement checklist

1. **Live Shop > Featured:** One benefit row above one Upgrade button, with
   equal width and height. No old four-row panel remains. The title, cape and
   grass stay in their compact positions. Swipe through all four perks, and
   wait for the automatic rotation to wrap. Swiping must not open the modal;
   tapping the hero, benefit or Upgrade action still opens it once.
2. **Membership modal:** The host title/close button stay put. Confirm the
   shorter scene, all four static benefit tiles, and weekly/monthly plan cards
   in the same centered positions. Switch plans, then check the trial or
   subscribe action, disclosure, Restore, and active-member Manage state.
   The modal must not itself contain an auto-scrolling benefit row.
3. **Day/night, narrow phone and large text:** Benefit text stays inside the
   single row; row and Upgrade button grow together rather than truncate.
   Modal tiles wrap, plan cards grow vertically, and all controls remain
   reachable by scrolling. Check selection contrast in both themes.
4. **Motion and interruptions:** Autoplay pauses while a finger is down,
   while accessible navigation or reduced animations are requested, while
   the app is backgrounded, or while the membership modal covers the Shop.
   It restarts with a full reading interval when appropriate. Manual swiping
   still works with reduced motion and accessible navigation.
5. **Other Shop entry paths and mirrors:** Open from coin and membership
   entry links, replay the Shop walkthrough, and open Shop in the existing
   billing preview. Confirm scroll targets/spotlights still land correctly
   and coin offers follow the shorter promo without overlap. The preview
   renders the real Shop widget. The tab tutorial host has no Shop page and
   disables billing, so this change adds no promo there.

## Verification

Widget tests were authored for timed rotation, wrap, manual swiping, interval
reset, lifecycle/modal and accessibility pauses, disposal, unchanged navigation
and visibility policy, row/button size parity, both palettes and large text.
Modal tests cover shared copy/icons, full static benefits, retained controls
and plan-card sizing. Existing card assertions were adapted to visit each page
rather than require all four titles on screen at once; other assertions remain.
Legacy paywall copy assertions now use the new exact titles.

Flutter/Dart are not installed in the editing environment. These tests have NOT
been executed. No simulator/device render, full suite, platform build or
independent subagent review has been performed. This checklist is not a record
of completed manual testing. The changes are platform-neutral Flutter UI and
introduce no new backend contract.

Run locally:

```sh
dart format lib/widgets/bara_gold_benefits.dart lib/widgets/bara_gold_benefits_carousel.dart lib/widgets/bara_plus_card.dart lib/screens/bara_plus_screen.dart test/bara_gold_benefits_carousel_test.dart test/bara_gold_shop_card_benefits_test.dart test/bara_gold_modal_cleanup_test.dart test/bara_gold_frontend_test.dart
flutter analyze
flutter test test/bara_gold_shop_card_avatar_test.dart test/bara_gold_shop_card_benefits_test.dart test/bara_gold_benefits_carousel_test.dart test/bara_gold_modal_cleanup_test.dart test/bara_gold_frontend_test.dart
```
