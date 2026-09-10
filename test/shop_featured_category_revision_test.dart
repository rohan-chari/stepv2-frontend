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
import 'unified_shop_test.dart'
    show pumpShop, pumpRetainedMembership, AvailabilityBilling;
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
  testWidgets('Featured begins the continuous Shop sections', (tester) async {
    addTearDown(tester.view.reset);
    await pumpShop(tester, billing: FakeBilling());
    expect(find.text('ITEMS'), findsNothing);
    expect(find.text('INVENTORY'), findsNothing);
    expect(find.text('ACCESSORIES'), findsNothing);
    expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
    for (final section in ['featured', 'powerups', 'characters']) {
      expect(find.byKey(Key('shop-section-$section')), findsOneWidget);
    }
    expect(find.byType(CoinPackOffers), findsOneWidget);
  });
  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets(
      'Featured starts with coins and merchandise sizes match at $width',
      (tester) async {
        addTearDown(tester.view.reset);
        await pumpShop(tester, billing: FakeBilling(), width: width);
        final membership = find.byKey(const Key('shop-membership-toggle'));
        final coin = find.byKey(const Key('coin-tile-coins_500'));
        expect(membership, findsNothing);
        expect(coin, findsOneWidget);
        expect(
          tester
              .getBottomLeft(find.byKey(const Key('shop-section-featured')))
              .dy,
          lessThanOrEqualTo(tester.getTopLeft(coin).dy),
        );
        await selectShopCategory(tester, 'POWERUPS');
        final powerup = tester.getSize(
          find.byKey(const Key('shop-product-card')).first,
        );
        await selectShopCategory(tester, 'CHARACTERS');
        final character = tester.getSize(
          find.byKey(const Key('shop-character-default')),
        );
        expect(character.width, closeTo(powerup.width, .01));
        expect(character.height, closeTo(powerup.height, .01));
        if (width < 360) {
          expect(powerup.width, closeTo((width - 32 - 24) / 3, .01));
        }
        expect(powerup.height, closeTo(powerup.width / .68, .01));
        expect(tester.takeException(), isNull);
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
    'retained membership body observes products arriving when mounted directly',
    (tester) async {
      addTearDown(tester.view.reset);
      final billing = AvailabilityBilling()
        ..state = const BillingSnapshot(
          operationStatus: BillingOperationStatus.loading,
        );
      await pumpRetainedMembership(tester, billing: billing);
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
  testWidgets(
    'retained membership body ignores purchase feedback after identity change',
    (tester) async {
      addTearDown(tester.view.reset);
      final billing = _SwitchingBilling()
        ..pendingPurchase = Completer<BillingResult>();
      await pumpRetainedMembership(tester, billing: billing);
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
      expect(find.byType(BaraPlusBody), findsOneWidget);
      billing.pendingPurchase?.complete(
        const BillingResult(success: true, message: 'Old purchase complete'),
      );
      await tester.pump();
      expect(find.text('Old purchase complete'), findsNothing);
    },
  );
  testWidgets(
    'enlarged section headers remain readable and vertically ordered',
    (tester) async {
      addTearDown(tester.view.reset);
      await pumpShop(
        tester,
        billing: FakeBilling(),
        width: 320,
        textScale: 1.6,
      );
      final featured = find.byKey(const Key('shop-section-featured'));
      final powerups = find.byKey(const Key('shop-section-powerups'));
      final characters = find.byKey(const Key('shop-section-characters'));
      expect(
        tester.getBottomLeft(featured).dy,
        lessThan(tester.getTopLeft(powerups).dy),
      );
      expect(
        tester.getBottomLeft(powerups).dy,
        lessThan(tester.getTopLeft(characters).dy),
      );
      await selectShopCategory(tester, 'CHARACTERS');
      expect(
        find.byKey(const Key('shop-character-default')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(CoinPackOffers), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'legacy membership focus and identity cleanup preserve unrelated route',
    (tester) async {
      addTearDown(tester.view.reset);
      final billing = _SwitchingBilling();
      await pumpShop(tester, billing: billing, focus: ShopFocus.membership);
      expect(find.byType(BaraPlusBody), findsNothing);
      expect(find.byType(CoinPackOffers), findsOneWidget);
      Navigator.of(tester.element(find.byType(ShopTab))).push(
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
    },
  );
}
