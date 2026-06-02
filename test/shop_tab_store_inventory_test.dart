import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// Store/Inventory overhaul for the shop tab.
//
// STORE shows:
//   - cosmetics the user does NOT yet own (owned cosmetics leave the store)
//   - purchasable powerups (e.g. Imposter, 500 coins) which are RE-BUYABLE
// INVENTORY shows:
//   - owned cosmetics
//   - owned powerups with their quantity counts
//
// Degrades gracefully if the powerup endpoints are missing (older backend).

class _FakeShopApi extends BackendApiService {
  _FakeShopApi({
    required this.catalog,
    required this.powerupCatalog,
    required this.inventory,
    this.powerupEndpointsAvailable = true,
  });

  final Map<String, dynamic> catalog;
  final Map<String, dynamic> powerupCatalog;
  final Map<String, dynamic> inventory;
  final bool powerupEndpointsAvailable;

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
    if (!powerupEndpointsAvailable) {
      throw const ApiException('Not found', statusCode: 404);
    }
    return powerupCatalog;
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async {
    if (!powerupEndpointsAvailable) {
      throw const ApiException('Not found', statusCode: 404);
    }
    return inventory;
  }

  @override
  Future<Map<String, dynamic>> purchasePowerupItem({
    required String identityToken,
    String? sku,
    String? powerupType,
    required String idempotencyKey,
  }) async {
    return {
      'coins': 0,
      'inventory': {'powerupType': 'IMPOSTER', 'quantity': 1},
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

Map<String, dynamic> _catalog() => {
      'coins': 1000,
      'ownedItemIds': ['item-owned'],
      'equipped': <String, dynamic>{},
      'items': [
        {
          'id': 'item-unowned',
          'sku': 'HAT_BLUE',
          'name': 'Blue Hat',
          'description': 'A hat',
          'slot': 'HEAD',
          'priceCoins': 100,
          'assetKey': 'hat_blue',
          'owned': false,
          'equipped': false,
        },
        {
          'id': 'item-owned',
          'sku': 'SCARF_RED',
          'name': 'Red Scarf',
          'description': 'A scarf',
          'slot': 'NECK',
          'priceCoins': 200,
          'assetKey': 'scarf_red',
          'owned': true,
          'equipped': false,
        },
      ],
    };

Map<String, dynamic> _powerupCatalog() => {
      'coins': 1000,
      'items': [
        {
          'sku': 'POWERUP_IMPOSTER',
          'name': 'Imposter',
          'description': 'Swap leaderboard positions for 1 hour',
          'priceCoins': 500,
          'powerupType': 'IMPOSTER',
          'ownedQuantity': 2,
        },
      ],
    };

Map<String, dynamic> _inventory() => {
      'items': [
        {'powerupType': 'IMPOSTER', 'quantity': 2},
      ],
    };

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

void main() {
  testWidgets('STORE shows Imposter (500 coins) as a purchasable powerup',
      (tester) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );

    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'STORE');

    expect(find.text('Imposter'), findsWidgets);
    // The 500-coin price is shown as a buy affordance in the store.
    expect(find.text('500'), findsWidgets);
  });

  testWidgets('STORE shows unowned cosmetics but NOT owned ones',
      (tester) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );

    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'STORE');

    // Unowned cosmetic is offered in the store...
    expect(find.text('Blue Hat'), findsWidgets);
    // ...but the OWNED cosmetic is not in the store list.
    expect(find.text('Red Scarf'), findsNothing);
  });

  testWidgets('INVENTORY shows owned cosmetics and owned-powerup counts',
      (tester) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );

    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'INVENTORY');

    // Owned cosmetic appears in inventory.
    expect(find.text('Red Scarf'), findsWidgets);
    // Owned powerup appears with its quantity (x2).
    expect(find.text('Imposter'), findsWidgets);
    expect(find.textContaining('2'), findsWidgets);
  });

  testWidgets('degrades gracefully when powerup endpoints are unavailable',
      (tester) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
      powerupEndpointsAvailable: false,
    );

    // Should not throw; cosmetics still render.
    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'STORE');
    expect(find.text('Blue Hat'), findsWidgets);

    await _selectSegment(tester, 'INVENTORY');
    expect(find.text('Red Scarf'), findsWidgets);
  });
}
