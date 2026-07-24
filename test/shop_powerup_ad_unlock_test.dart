import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Item 10 — the "watch ads to unlock" affordance vs the +coins route,
/// driven entirely by the coin shortfall against a single 150/300-coin tile.
class _FakeShopApi extends BackendApiService {
  _FakeShopApi({required this.coins, required this.price});

  final int coins;
  final int price;

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    // _loadCatalog syncs the auth balance from here, so this is the coin
    // value the tile reads.
    return {
      'coins': coins,
      'ownedItemIds': <String>[],
      'equipped': <String, dynamic>{},
      'items': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {
    'coins': coins,
    'items': [
      {
        'sku': 'PW_SHORT',
        'name': 'Big Bang',
        'description': 'Pricey powerup',
        'priceCoins': price,
        'powerupType': 'RED_CARD',
        'category': 'offense',
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => {'items': <Map<String, dynamic>>[]};
}

Future<void> _pump(WidgetTester tester, {required int coins, required int price}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'auth_coins': coins,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  await tester.pumpWidget(
    MaterialApp(
      home: ShopTab(
        authService: auth,
        backendApiService: _FakeShopApi(coins: coins, price: price),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PowerupCopy.resetForTest());

  testWidgets('shortfall 120 → "Watch 3 ads"', (tester) async {
    await _pump(tester, coins: 30, price: 150);
    expect(find.text('Watch 3 ads'), findsOneWidget);
    expect(find.text('Get coins'), findsNothing);
  });

  testWidgets('shortfall 40 → "Watch 1 ad"', (tester) async {
    await _pump(tester, coins: 110, price: 150);
    expect(find.text('Watch 1 ad'), findsOneWidget);
  });

  testWidgets('shortfall 300 (>150) → "Get coins" route', (tester) async {
    await _pump(tester, coins: 0, price: 300);
    expect(find.text('Get coins'), findsOneWidget);
    expect(find.textContaining('Watch'), findsNothing);
  });

  testWidgets('affordable → plain price strip, no ad affordance', (tester) async {
    await _pump(tester, coins: 1000, price: 150);
    expect(find.text('150'), findsWidgets);
    expect(find.textContaining('Watch'), findsNothing);
    expect(find.text('Get coins'), findsNothing);
  });
}
