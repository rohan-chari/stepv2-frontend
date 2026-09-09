import 'dart:async';
import 'support/shop_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/screens/bara_plus_screen.dart';
import 'package:step_tracker/models/billing.dart';
import 'package:step_tracker/widgets/coin_pack_offers.dart';
import 'unified_shop_test.dart' show pumpShop, AvailabilityBilling;
import 'billing_components_test.dart' show FakeBilling;

class _SwitchingBilling extends FakeBilling {
  String id = 'test';
  Completer<BillingResult>? pendingPurchase;
  @override
  Future<BillingResult> startTrial(BillingPlan plan) async {
    final pending = pendingPurchase;
    if (pending == null) return super.startTrial(plan);
    update(
      const BillingSnapshot(operationStatus: BillingOperationStatus.loading),
    );
    return pending.future;
  }

  @override
  String get userId => id;
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'token',
      'auth_user_identifier': 'apple',
      'auth_session_token': 'session',
      'auth_backend_user_id': 'user',
      'auth_coins': 100,
    });
  });
  testWidgets('Featured uses three shop bottom destinations', (tester) async {
    addTearDown(tester.view.reset);
    await pumpShop(tester, billing: FakeBilling());
    expect(find.text('ITEMS'), findsNothing);
    expect(find.text('INVENTORY'), findsNothing);
    expect(find.text('ACCESSORIES'), findsNothing);
    final categories = find.byKey(const Key('shop-bottom-navigation'));
    for (final name in ['FEATURED', 'POWERUPS', 'CHARACTERS']) {
      expect(
        find.descendant(of: categories, matching: find.text(name)),
        findsOneWidget,
      );
    }
    expect(
      tester.getTopLeft(categories).dy,
      greaterThan(tester.getBottomLeft(find.text('SHOP')).dy),
    );
    expect(find.byType(CoinPackOffers), findsOneWidget);
  });
  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets(
      'Featured cards match each other and Powerups match Characters at $width',
      (tester) async {
        addTearDown(tester.view.reset);
        await pumpShop(tester, billing: FakeBilling(), width: width);
        final membership = tester.getSize(
          find.byKey(const Key('shop-membership-toggle')),
        );
        final coin = tester.getSize(
          find.byKey(const Key('coin-tile-coins_500')),
        );
        expect(coin, membership);
        await tester.ensureVisible(find.text('POWERUPS'));
        await tester.pump();
        await tester.tap(find.text('POWERUPS'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final powerup = tester.getSize(
          find.byKey(const Key('shop-product-card')).first,
        );
        await selectShopCategory(tester, 'CHARACTERS');
        final character = tester.getSize(
          find.byKey(const Key('shop-character-default')),
        );
        expect(powerup.width, character.width);
        expect(powerup.height, character.height);
        expect(powerup.width, lessThanOrEqualTo(coin.width));
      },
    );
  }
  testWidgets('Powerups remembers local Owned selection across destinations', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpShop(tester, billing: FakeBilling(), focus: ShopFocus.coins);
    await selectShopCategory(tester, 'POWERUPS');
    await tester.tap(find.text('OWNED'));
    await tester.pump();
    expect(find.byKey(const Key('shop-product-card')), findsNothing);
    await selectShopCategory(tester, 'CHARACTERS');
    expect(find.byKey(const Key('shop-character-default')), findsOneWidget);
    await selectShopCategory(tester, 'FEATURED');
    expect(find.byType(CoinPackOffers), findsOneWidget);
    await selectShopCategory(tester, 'POWERUPS');
    expect(find.byKey(const Key('shop-product-card')), findsNothing);
    await tester.tap(find.text('BUY'));
    await tester.pump();
    expect(find.byKey(const Key('shop-product-card')), findsOneWidget);
  });
  testWidgets(
    'membership focus loading opens details and observes products arriving',
    (tester) async {
      addTearDown(tester.view.reset);
      final billing = AvailabilityBilling()
        ..state = const BillingSnapshot(
          operationStatus: BillingOperationStatus.loading,
        );
      await pumpShop(tester, billing: billing, focus: ShopFocus.membership);
      expect(find.byType(BaraPlusBody), findsOneWidget);
      expect(
        find.text('Store pricing is currently unavailable.'),
        findsOneWidget,
      );
      billing.membership = true;
      billing.update(const BillingSnapshot());
      await tester.pump();
      expect(find.textContaining('0.99'), findsNothing);
      expect(find.byKey(const Key('start-bara-trial')), findsOneWidget);
    },
  );
  testWidgets('open membership sheet closes on billing identity change', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final billing = _SwitchingBilling()
      ..pendingPurchase = Completer<BillingResult>();
    await pumpShop(tester, billing: billing, focus: ShopFocus.membership);
    expect(find.byType(BaraPlusBody), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('start-bara-trial')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('start-bara-trial')));
    await tester.pump();
    billing.id = 'next-account';
    billing.update(const BillingSnapshot());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BaraPlusBody), findsNothing);
    billing.pendingPurchase?.complete(
      const BillingResult(success: true, message: 'Old purchase complete'),
    );
    await tester.pump();
    expect(find.text('Old purchase complete'), findsNothing);
  });
  testWidgets('enlarged category navigation remains one scrollable row', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpShop(tester, billing: FakeBilling(), width: 320, textScale: 1.6);
    final firstY = tester.getTopLeft(find.text('FEATURED')).dy;
    for (final label in ['POWERUPS', 'CHARACTERS']) {
      expect(tester.getTopLeft(find.text(label)).dy, firstY);
    }
    await tester.ensureVisible(find.text('CHARACTERS'));
    await tester.pump();
    await tester.tap(find.text('CHARACTERS'));
    await tester.pump();
    expect(find.byType(CoinPackOffers), findsNothing);
  });
  testWidgets('identity cleanup preserves unrelated route above membership', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final billing = _SwitchingBilling();
    await pumpShop(tester, billing: billing, focus: ShopFocus.membership);
    Navigator.of(tester.element(find.byType(BaraPlusBody))).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Notification details')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    billing.id = 'next-account';
    billing.update(const BillingSnapshot());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Notification details'), findsOneWidget);
  });
}
