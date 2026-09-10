import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/widgets/coin_pack_offers.dart';
import 'package:step_tracker/widgets/shop_product_grid.dart';
import 'unified_shop_test.dart' show pumpShop;
import 'billing_components_test.dart' show FakeBilling;

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
  testWidgets(
    'Shop contains ordered sections and local inventory preserves surrounding content',
    (tester) async {
      addTearDown(tester.view.reset);
      await pumpShop(tester, billing: FakeBilling());
      expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
      final featured = find.byKey(const Key('shop-section-featured'));
      final powerups = find.byKey(const Key('shop-section-powerups'));
      final characters = find.byKey(const Key('shop-section-characters'));
      expect(
        tester.getTopLeft(featured).dy,
        lessThan(tester.getTopLeft(powerups).dy),
      );
      expect(
        tester.getTopLeft(powerups).dy,
        lessThan(tester.getTopLeft(characters).dy),
      );
      expect(
        tester
            .getBottomLeft(find.byKey(const Key('shop-membership-toggle')))
            .dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(CoinPackOffers)).dy),
      );
      await tester.ensureVisible(find.text('OWNED'));
      await tester.tap(find.text('OWNED'));
      await tester.pump();
      expect(find.byType(CoinPackOffers), findsOneWidget);
      expect(find.byKey(const Key('shop-character-default')), findsOneWidget);
      expect(find.byKey(const Key('shop-product-card')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 1.6]) {
    testWidgets(
      'Powerups grid is spacious and accessible at text scale $scale',
      (tester) async {
        addTearDown(tester.view.reset);
        await pumpShop(
          tester,
          billing: FakeBilling(),
          focus: ShopFocus.items,
          textScale: scale,
        );
        final grid = tester.widget<GridView>(
          find.byKey(const Key('shop-product-grid')),
        );
        final delegate =
            grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, scale == 1 ? 3 : 2);
        expect(delegate.mainAxisSpacing, 16);
        expect(find.byType(ShopProductGrid), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('wide Powerups grid has a bounded merchandise width', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pumpShop(tester, billing: FakeBilling(), width: 1600);
    expect(
      tester.getSize(find.byKey(const Key('shop-product-grid'))).width,
      lessThanOrEqualTo(1000),
    );
  });
}
