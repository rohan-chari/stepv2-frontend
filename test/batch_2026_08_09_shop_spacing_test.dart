import 'support/shop_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Batch 2026-08-09 item 3 — shop header spacing.
///
/// The section-local filter/sort row follows the description without a toggle.
/// The continuous Shop has no category bar or category-sized blank viewport.
class _FakeShopApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => {
    'coins': 1000,
    'ownedItemIds': <String>[],
    'equipped': <String, dynamic>{},
    'items': <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {
    'coins': 1000,
    'items': [
      {
        'sku': 'PW_ZAP',
        'name': 'Zap',
        'description': 'Hit a rival',
        'priceCoins': 10,
        'powerupType': 'LEG_CRAMP',
        'category': 'offense',
        'rarity': 'COMMON',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => {'items': <Map<String, dynamic>>[]};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'auth_coins': 1000,
    'auth_held_coins': 0,
  });
  final service = AuthService();
  await service.restoreSession();
  return service;
}

Future<void> _pump(WidgetTester tester) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: ShopTab(
        initialFocus: ShopFocus.items,
        authService: auth,
        backendApiService: _FakeShopApi(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Vertical void between the bottom of [top] and the top of [bottom].
double _gap(WidgetTester tester, Finder top, Finder bottom) =>
    tester.getRect(bottom).top - tester.getRect(top).bottom;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.example.bara',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    PowerupCopy.resetForTest();
  });

  testWidgets('Powerups description and filter retain a 12px local gap', (
    tester,
  ) async {
    await _pump(tester);
    final segment = find.byKey(const Key('shop-segment-control'));
    final controls = find.byKey(const Key('shop-filter-sort-button'));
    expect(segment, findsNothing);
    expect(controls, findsOneWidget);
    expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
    expect(
      _gap(
        tester,
        find.byKey(const Key('shop-section-description-powerups')),
        controls,
      ),
      closeTo(12.0, 0.01),
    );
    expect(
      tester.getTopLeft(controls).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('shop-section-powerups'))).dy,
      ),
    );
  });

  testWidgets(
    'Characters follows Powerups without another filter or category viewport',
    (tester) async {
      await _pump(tester);
      await selectShopCategory(tester, 'CHARACTERS');
      expect(find.byKey(const Key('shop-filter-sort-button')), findsOneWidget);
      expect(find.byKey(const Key('shop-segment-control')), findsNothing);
      expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
      final characters = find.byKey(const Key('shop-section-characters'));
      expect(
        tester.getTopLeft(characters).dy,
        greaterThan(
          tester
              .getBottomLeft(find.byKey(const Key('shop-filter-sort-button')))
              .dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unified Powerups keeps filters and surrounding sections', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('OWNED'), findsNothing);
    expect(find.text('BUY'), findsNothing);
    expect(find.byKey(const Key('shop-filter-sort-button')), findsOneWidget);
    expect(find.byKey(const Key('shop-segment-control')), findsNothing);
    expect(find.byKey(const Key('shop-bottom-navigation')), findsNothing);
    expect(find.byKey(const Key('shop-section-featured')), findsOneWidget);
    expect(find.byKey(const Key('shop-section-characters')), findsOneWidget);
  });

  testWidgets('no layout overflow on a small (SE-size) screen', (tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('shop-filter-sort-button')), findsOneWidget);
  });
}
