import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// No one-tap purchases in the store.
//
// A user reading item descriptions mis-tapped the gold price strip on the
// Signal Jammer tile and was instantly charged 300 coins — the strip used to
// call the purchase endpoint directly. Now BOTH tap targets on a store tile
// (tile body and price strip) open the detail sheet, and the sheet's BUY
// button is the only thing that spends coins.

class _FakeShopApi extends BackendApiService {
  _FakeShopApi({
    required this.catalog,
    required this.powerupCatalog,
    required this.inventory,
  });

  final Map<String, dynamic> catalog;
  final Map<String, dynamic> powerupCatalog;
  final Map<String, dynamic> inventory;

  int cosmeticPurchases = 0;
  int powerupPurchases = 0;

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    return catalog;
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async {
    return powerupCatalog;
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async {
    return inventory;
  }

  @override
  Future<Map<String, dynamic>> purchaseShopItem({
    required String identityToken,
    required String itemId,
    required String idempotencyKey,
  }) async {
    cosmeticPurchases++;
    return {'coins': 900};
  }

  @override
  Future<Map<String, dynamic>> purchasePowerupItem({
    required String identityToken,
    String? sku,
    String? powerupType,
    required String idempotencyKey,
  }) async {
    powerupPurchases++;
    return {
      'coins': 700,
      'inventory': {'powerupType': 'SIGNAL_JAMMER', 'quantity': 1},
    };
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'auth_coins': 1000,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

const _jammerDescription =
    'Jam a rival — they cannot use powerups for 1 hour';
const _hatDescription = 'A very readable blue hat';

Map<String, dynamic> _catalog() => {
      'coins': 1000,
      'ownedItemIds': <String>[],
      'equipped': <String, dynamic>{},
      'items': [
        {
          'id': 'item-hat',
          'sku': 'HAT_BLUE',
          'name': 'Blue Hat',
          'description': _hatDescription,
          'slot': 'HEAD',
          'priceCoins': 100,
          'assetKey': 'hat_blue',
          'owned': false,
          'equipped': false,
        },
      ],
    };

Map<String, dynamic> _powerupCatalog() => {
      'coins': 1000,
      'items': [
        {
          'sku': 'POWERUP_SIGNAL_JAMMER',
          'name': 'Signal Jammer',
          'description': _jammerDescription,
          'priceCoins': 300,
          'powerupType': 'SIGNAL_JAMMER',
          'ownedQuantity': 0,
        },
      ],
    };

Map<String, dynamic> _inventory() => {'items': <Map<String, dynamic>>[]};

Future<void> _pumpShop(
  WidgetTester tester,
  AuthService auth,
  BackendApiService api,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ShopTab(authService: auth, backendApiService: api),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _selectSegment(WidgetTester tester, String label) async {
  final seg = find.text(label);
  if (seg.evaluate().isNotEmpty) {
    await tester.tap(seg.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _selectCategory(WidgetTester tester, String label) async {
  final pill = find.text(label);
  if (pill.evaluate().isNotEmpty) {
    await tester.tap(pill.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets(
      'tapping the price strip on a store powerup opens the detail sheet '
      'and does NOT purchase', (tester) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );

    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'STORE');

    // The tile's price strip shows the bare price.
    expect(find.text('300'), findsOneWidget);

    await tester.tap(find.text('300'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The detail sheet is open (full description visible), nothing was bought.
    expect(find.text(_jammerDescription), findsOneWidget);
    expect(find.text('BUY · 300'), findsOneWidget);
    expect(api.powerupPurchases, 0);
  });

  testWidgets('the sheet BUY button is what actually purchases the powerup',
      (tester) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );

    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'STORE');

    await tester.tap(find.text('300'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('BUY · 300'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.powerupPurchases, 1);
  });

  testWidgets(
      'tapping the price strip on a store cosmetic opens the detail sheet '
      'and does NOT purchase', (tester) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );

    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'STORE');
    await _selectCategory(tester, 'ACCESSORIES');

    expect(find.text('100'), findsOneWidget);

    await tester.tap(find.text('100'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(_hatDescription), findsOneWidget);
    expect(find.text('BUY · 100'), findsOneWidget);
    expect(api.cosmeticPurchases, 0);
  });
}
