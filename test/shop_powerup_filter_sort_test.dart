import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Item 9 — powerup store category pills + sort-by.
class _FakeShopApi extends BackendApiService {
  _FakeShopApi({required this.powerupCatalog});

  final Map<String, dynamic> powerupCatalog;

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    return {
      'coins': 1000,
      'ownedItemIds': <String>[],
      'equipped': <String, dynamic>{},
      'items': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => powerupCatalog;

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

/// Mixed categories + one item with NO category (must default to utility).
Map<String, dynamic> _catalog() => {
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
    {
      'sku': 'PW_GUARD',
      'name': 'Guard',
      'description': 'Shield yourself',
      'priceCoins': 50,
      'powerupType': 'STEALTH_MODE',
      'category': 'defense',
      'rarity': 'EPIC',
    },
    {
      'sku': 'PW_ANCHOR',
      'name': 'Anchor',
      'description': 'Self buff',
      'priceCoins': 90,
      'powerupType': 'RUNNERS_HIGH',
      'category': 'utility',
      'rarity': 'RARE',
    },
    {
      // No category → defaults to utility (older backend compat).
      'sku': 'PW_MYSTERY',
      'name': 'Mystery',
      'description': 'Unknown',
      'priceCoins': 30,
      'powerupType': 'COIN_FLIP',
      'rarity': 'LEGENDARY',
    },
  ],
};

Future<void> _pump(WidgetTester tester, BackendApiService api) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(home: ShopTab(authService: auth, backendApiService: api)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PowerupCopy.resetForTest());

  testWidgets('category pills + default sort control render', (tester) async {
    await _pump(tester, _FakeShopApi(powerupCatalog: _catalog()));
    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('OFFENSE'), findsOneWidget);
    expect(find.text('DEFENSE'), findsOneWidget);
    expect(find.text('UTILITY'), findsOneWidget);
    expect(find.text('Sort: Name (A–Z)'), findsOneWidget);
    // All four items visible under the default ALL filter.
    expect(find.text('Zap'), findsOneWidget);
    expect(find.text('Guard'), findsOneWidget);
    expect(find.text('Anchor'), findsOneWidget);
    expect(find.text('Mystery'), findsOneWidget);
  });

  testWidgets('tapping OFFENSE shows only offense items', (tester) async {
    await _pump(tester, _FakeShopApi(powerupCatalog: _catalog()));
    await tester.tap(find.text('OFFENSE'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Zap'), findsOneWidget); // offense
    expect(find.text('Guard'), findsNothing); // defense filtered out
    expect(find.text('Anchor'), findsNothing); // utility filtered out
    expect(find.text('Mystery'), findsNothing);
  });

  testWidgets('a category-less item falls into UTILITY', (tester) async {
    await _pump(tester, _FakeShopApi(powerupCatalog: _catalog()));
    await tester.tap(find.text('UTILITY'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Anchor'), findsOneWidget); // explicit utility
    expect(find.text('Mystery'), findsOneWidget); // defaulted utility
    expect(find.text('Zap'), findsNothing);
    expect(find.text('Guard'), findsNothing);
  });

  testWidgets('default order is alphabetical; Price sort reorders', (
    tester,
  ) async {
    await _pump(tester, _FakeShopApi(powerupCatalog: _catalog()));
    // Alphabetical default: Anchor above Zap.
    expect(
      tester.getTopLeft(find.text('Anchor')).dx <
          tester.getTopLeft(find.text('Zap')).dx,
      isTrue,
    );

    // Switch to Price: Low→High via the sort dropdown.
    await tester.tap(find.text('Sort: Name (A–Z)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Price: Low→High').last, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Zap (10) now sits above Anchor (90).
    expect(find.text('Sort: Price: Low→High'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Zap')).dx <
          tester.getTopLeft(find.text('Anchor')).dx,
      isTrue,
    );
  });

  testWidgets('Rarity sort orders COMMON→LEGENDARY', (tester) async {
    await _pump(tester, _FakeShopApi(powerupCatalog: _catalog()));
    await tester.tap(find.text('Sort: Name (A–Z)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Rarity').last, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Zap COMMON above Guard EPIC above Mystery LEGENDARY.
    expect(
      tester.getTopLeft(find.text('Zap')).dx <
          tester.getTopLeft(find.text('Guard')).dx,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.text('Guard')).dx <
          tester.getTopLeft(find.text('Mystery')).dx,
      isTrue,
    );
  });
}
