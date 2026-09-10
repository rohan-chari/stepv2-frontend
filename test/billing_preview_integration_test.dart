import 'support/shop_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/preview/billing_preview_app.dart';
import 'package:step_tracker/preview/preview_billing_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> launch(
    WidgetTester tester,
    PreviewBillingController controller,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(BillingPreviewApp(controller: controller));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('OPEN SHOP'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> exitShop(WidgetTester tester) async {
    await closeShopMembership(tester);
    await tester.tap(find.byKey(const Key('shop-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  testWidgets(
    'root Coins return keeps preview navigation and wallet metadata isolated',
    (tester) async {
      SharedPreferences.setMockInitialValues({'auth_held_coins': 73});
      final controller = PreviewBillingController();
      addTearDown(controller.dispose);
      await launch(tester, controller);
      await exitShop(tester);
      await tester.tap(find.byKey(const Key('preview-nav-coins')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('preview-nav-shop')), findsNothing);
      expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
      expect(find.byKey(const Key('shop-section-featured')), findsOneWidget);
      expect(find.byKey(const Key('shop-section-powerups')), findsOneWidget);
      expect(find.byKey(const Key('shop-section-characters')), findsOneWidget);
      await exitShop(tester);
      await tester.tap(find.byKey(const Key('preview-nav-shop')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await exitShop(tester);
      expect(find.byKey(const Key('preview-nav-shop')), findsOneWidget);
      await controller.auth.updateHeldCoins(0);
      expect(
        (await SharedPreferences.getInstance()).getInt('auth_held_coins'),
        73,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('real shop and profile reflect member pricing and identity', (
    tester,
  ) async {
    final controller = PreviewBillingController();
    controller.setScenario(PreviewBillingScenario.monthly);
    addTearDown(controller.dispose);
    await launch(tester, controller);
    expect(find.byKey(const Key('billing-shop-membership')), findsNothing);
    await selectShopCategory(tester, 'POWERUPS');
    await tester.pump();
    await tester.tap(find.text('Ghost Pepper').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('BUY · 170'), findsOneWidget);
    await tester.tap(find.text('BUY · 170'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(controller.snapshot.coins, 680);
    await exitShop(tester);
    await tester.tap(find.byKey(const Key('preview-nav-profile')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('billing-profile-badge')), findsNothing);
    expect(find.byKey(const Key('billing-profile-membership')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'preview shows restored Decoy and direct discounted accessories',
    (tester) async {
      final controller = PreviewBillingController();
      controller.setScenario(PreviewBillingScenario.monthly);
      addTearDown(controller.dispose);
      await launch(tester, controller);
      expect(find.text('Decoy'), findsOneWidget);
      expect(find.byKey(const Key('shop-section-accessories')), findsOneWidget);
      final accessory = find.byKey(const Key('shop-accessory-baseball_cap'));
      await tester.ensureVisible(accessory);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(accessory);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('BUY · 170'), findsOneWidget);
      await tester.ensureVisible(find.text('BUY · 170'));
      await tester.pump();
      await tester.tap(find.text('BUY · 170'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.ownedCosmetics, contains('baseball_cap'));
      expect(accessory, findsNothing);
      expect(find.byKey(const Key('shop-edit-outfit')), findsNothing);
      expect(find.byIcon(Icons.edit_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('all coin offers render in the real Shop coins section', (
    tester,
  ) async {
    final controller = PreviewBillingController();
    addTearDown(controller.dispose);
    await launch(tester, controller);
    await exitShop(tester);
    await tester.tap(find.byKey(const Key('preview-nav-coins')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('500'), findsWidgets);
    expect(find.textContaining('2,800'), findsWidgets);
    expect(find.textContaining('6,000'), findsWidgets);
    expect(find.textContaining('PREVIEW'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'changing membership closes stale price sheet and reloads prices',
    (tester) async {
      final controller = PreviewBillingController();
      controller.setScenario(PreviewBillingScenario.monthly);
      addTearDown(controller.dispose);
      await launch(tester, controller);
      await selectShopCategory(tester, 'POWERUPS');
      await tester.pump();
      await tester.tap(find.text('Ghost Pepper').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('BUY · 170'), findsOneWidget);
      controller.setScenario(PreviewBillingScenario.free);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('shop-item-sheet')), findsNothing);
      await tester.tap(find.text('Ghost Pepper').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('BUY · 200'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
