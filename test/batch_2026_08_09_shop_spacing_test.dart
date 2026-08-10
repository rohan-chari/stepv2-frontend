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
      home: ShopTab(authService: auth, backendApiService: _FakeShopApi()),
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
    final pills = find.byKey(const Key('shop-category-pills'));
    final controls = find.byKey(const Key('shop-filter-sort-button'));

    expect(segment, findsOneWidget);
    expect(pills, findsOneWidget);
    expect(
      controls,
      findsOneWidget,
      reason: 'filter/sort row renders in STORE + POWERUPS',
    );

    final abovePills = _gap(tester, segment, pills);
    final aboveControls = _gap(tester, pills, controls);

    expect(abovePills, closeTo(8.0, 0.01));
    expect(
      aboveControls,
      closeTo(8.0, 0.01),
      reason:
          'gap above the filter/sort row must equal the gap above the pills',
    );
    expect(aboveControls, closeTo(abovePills, 0.01));
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

    // The pills are still the last thing in the header column: nothing was
    // left behind where the conditional filter row used to be.
    final pills = find.byKey(const Key('shop-category-pills'));
    final segment = find.byKey(const Key('shop-segment-control'));
    expect(_gap(tester, segment, pills), closeTo(8.0, 0.01));
  });

  testWidgets('INVENTORY: filter row absent, pill gap unchanged', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('INVENTORY'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('shop-filter-sort-button')), findsNothing);
    expect(
      _gap(
        tester,
        find.byKey(const Key('shop-segment-control')),
        find.byKey(const Key('shop-category-pills')),
      ),
      closeTo(8.0, 0.01),
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
