import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'unified_shop_test.dart' show ShopApi, shopAuth;

class _UnifiedApi extends ShopApi {
  bool unavailable = false;
  bool ownedOnlyRinse = false;
  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async {
    if (unavailable) throw const ApiException('Unavailable');
    return {
      'coins': 100,
      'items': [
        {
          'sku': 'PW_SHIELD',
          'name': 'Shield',
          'description': 'Protect your steps',
          'priceCoins': 50,
          'powerupType': 'STEALTH_MODE',
        },
        if (!ownedOnlyRinse)
          {
            'sku': 'PW_RINSE',
            'name': 'Quick Rinse',
            'description': 'Clean up',
            'priceCoins': 75,
            'powerupType': 'QUICK_RINSE',
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => {
    'items': [
      {'powerupType': 'STEALTH_MODE', 'quantity': 2},
      {'powerupType': 'QUICK_RINSE', 'quantity': 1},
    ],
  };
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
  Future<void> render(
    WidgetTester tester,
    _UnifiedApi api, {
    double scale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [dark ? AppPalette.night : AppPalette.light],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ShopTab(
          authService: await shopAuth(),
          backendApiService: api,
          initialFocus: ShopFocus.items,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'name sort includes owned-only rows and price sorts keep them last',
    (tester) async {
      await render(tester, _UnifiedApi()..ownedOnlyRinse = true);
      expect(
        tester.getCenter(find.text('Quick Rinse')).dx,
        lessThan(tester.getCenter(find.text('Shield')).dx),
      );
      for (final sort in ['Price ↑', 'Price ↓']) {
        final controls = find.byKey(const Key('shop-filter-sort-button'));
        await tester.ensureVisible(controls);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(controls);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byKey(Key('shop-sort-option-$sort')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester.getCenter(find.text('Shield')).dx,
          lessThan(tester.getCenter(find.text('Quick Rinse')).dx),
        );
      }
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'unified grid keeps purchases and readable quantities ${dark ? 'night' : 'day'}',
      (tester) async {
        await render(tester, _UnifiedApi(), dark: dark, scale: 1.6);
        expect(find.byKey(const Key('shop-segment-control')), findsNothing);
        expect(find.text('BUY'), findsNothing);
        expect(find.text('OWNED'), findsNothing);
        expect(find.text('Shield'), findsOneWidget);
        expect(find.text('Quick Rinse'), findsOneWidget);
        for (final count in ['x1', 'x2']) {
          final label = find.text(count);
          expect(label, findsOneWidget);
          expect(
            tester.widget<Text>(label).style?.fontSize,
            greaterThanOrEqualTo(14),
          );
        }
        expect(
          find.byKey(const Key('shop-filter-sort-button')),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Shield'));
        await tester.tap(find.text('Shield'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('BUY · 50'), findsOneWidget);
        expect(find.text('OWNED x2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'catalog failure retains owned quantities as informational tiles',
    (tester) async {
      await render(tester, _UnifiedApi()..unavailable = true);
      expect(find.byKey(const Key('shop-segment-control')), findsNothing);
      expect(find.byKey(const Key('shop-product-card')), findsNWidgets(2));
      expect(find.text('x2'), findsWidgets);
      await tester.ensureVisible(find.text('Quick Rinse'));
      await tester.tap(find.text('Quick Rinse'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('OWNED x1'), findsOneWidget);
      expect(find.textContaining('BUY ·'), findsNothing);
    },
  );
}
