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
/// The gap between the STORE/INVENTORY segment control and the category pills
/// (8px) and the gap between the category pills and the filter/sort row (was
/// 2px, cramped — screenshot IMG_3502) must match. Asserted geometrically off
/// the real ShopTab so the check survives a refactor of the header column.
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

  testWidgets('STORE+POWERUPS: pill gap and filter-row gap are both 8px', (
    tester,
  ) async {
    await _pump(tester);

    final segment = find.byKey(const Key('shop-segment-control'));
    final pills = find.byKey(const Key('shop-bottom-navigation'));
    final controls = find.byKey(const Key('shop-filter-sort-button'));

    expect(segment, findsOneWidget);
    expect(pills, findsOneWidget);
    expect(
      controls,
      findsOneWidget,
      reason: 'filter/sort row renders in STORE + POWERUPS',
    );

    expect(_gap(tester, segment, controls), closeTo(8.0, 0.01));
    expect(
      tester.getTopLeft(pills).dy,
      greaterThan(tester.getBottomLeft(controls).dy),
    );
    expect(
      tester.getBottomRight(pills).dy,
      lessThanOrEqualTo(tester.getSize(find.byType(ShopTab)).height),
    );
  });

  testWidgets('STORE+CHARACTERS: no filter row and no stray void below pills', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('shop-category-CHARACTERS')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('shop-filter-sort-button')), findsNothing);
    expect(find.byKey(const Key('shop-filter-sort-label')), findsNothing);

    expect(find.byKey(const Key('shop-segment-control')), findsNothing);
    expect(find.byKey(const Key('shop-bottom-navigation')), findsOneWidget);
  });

  testWidgets('INVENTORY: filter row absent, pill gap unchanged', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('OWNED'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('shop-filter-sort-button')), findsNothing);
    expect(find.byKey(const Key('shop-segment-control')), findsOneWidget);
    expect(find.byKey(const Key('shop-bottom-navigation')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('shop-bottom-navigation'))).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('shop-segment-control'))).dy,
      ),
    );
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
