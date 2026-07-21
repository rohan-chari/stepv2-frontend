import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// §7/§8 — Hitchhike and Quick Rinse in the store and inventory.
///
/// The store is type-generic, so the real risk isn't a missing tile: it's a
/// tile that renders with a raw enum string or a missing sprite because one of
/// the wiring points was skipped. These tests pin the end-to-end render, plus
/// the old-backend case where neither type exists at all.
class _FakeShopApi extends BackendApiService {
  _FakeShopApi({required this.powerupCatalog, required this.inventory});

  final Map<String, dynamic> powerupCatalog;
  final Map<String, dynamic> inventory;

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
  }) async {
    return powerupCatalog;
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async {
    return inventory;
  }
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

Map<String, dynamic> _catalogWithNewTypes() => {
      'coins': 1000,
      'items': [
        {
          'sku': 'POWERUP_HITCHHIKE',
          'name': 'Hitchhike',
          'description': "Copy a rival's steps into your score",
          'priceCoins': 150,
          'powerupType': 'HITCHHIKE',
          'ownedQuantity': 1,
        },
        {
          'sku': 'POWERUP_QUICK_RINSE',
          'name': 'Quick Rinse',
          'description': 'Halve every opponent effect on you',
          'priceCoins': 75,
          'powerupType': 'QUICK_RINSE',
          'ownedQuantity': 0,
        },
      ],
    };

/// What a client WITHOUT `powerups3` visibility sees — i.e. what an older
/// backend, or the gated catalog, returns.
Map<String, dynamic> _catalogWithoutNewTypes() => {
      'coins': 1000,
      'items': [
        {
          'sku': 'POWERUP_SIGNAL_JAMMER',
          'name': 'Signal Jammer',
          'description': 'Jam a rival',
          'priceCoins': 75,
          'powerupType': 'SIGNAL_JAMMER',
          'ownedQuantity': 0,
        },
      ],
    };

Future<void> _pumpShop(
  WidgetTester tester,
  AuthService auth,
  BackendApiService api,
) async {
  await tester.pumpWidget(
    MaterialApp(home: ShopTab(authService: auth, backendApiService: api)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

/// Taps a STORE/INVENTORY segment or a category pill, if present.
Future<void> _tap(
  WidgetTester tester,
  String label, {
  required bool last,
}) async {
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) return;
  await tester.tap(last ? finder.last : finder.first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => PowerupCopy.resetForTest());

  testWidgets('both new powerups render in the store with real names',
      (tester) async {
    final auth = await _auth();
    await _pumpShop(
      tester,
      auth,
      _FakeShopApi(
        powerupCatalog: _catalogWithNewTypes(),
        inventory: {
          'items': [
            {'powerupType': 'HITCHHIKE', 'quantity': 1},
          ],
        },
      ),
    );

    expect(find.text('Hitchhike'), findsWidgets);
    expect(find.text('Quick Rinse'), findsWidgets);
    // The failure mode this batch exists to prevent: a raw enum in the UI.
    expect(find.text('HITCHHIKE'), findsNothing);
    expect(find.text('QUICK_RINSE'), findsNothing);
  });

  testWidgets('their prices render', (tester) async {
    final auth = await _auth();
    await _pumpShop(
      tester,
      auth,
      _FakeShopApi(
        powerupCatalog: _catalogWithNewTypes(),
        inventory: {'items': <Map<String, dynamic>>[]},
      ),
    );
    expect(find.text('150'), findsWidgets);
    expect(find.text('75'), findsWidgets);
  });

  testWidgets('an owned Hitchhike appears in inventory', (tester) async {
    final auth = await _auth();
    await _pumpShop(
      tester,
      auth,
      _FakeShopApi(
        powerupCatalog: _catalogWithNewTypes(),
        inventory: {
          'items': [
            {'powerupType': 'HITCHHIKE', 'quantity': 3},
          ],
        },
      ),
    );

    await _tap(tester, 'INVENTORY', last: true);
    await _tap(tester, 'POWERUPS', last: false);
    expect(find.text('Hitchhike'), findsWidgets);
  });

  testWidgets('a gated catalog without the new types renders normally',
      (tester) async {
    // Old backend / no powerups3 visibility: the shop must simply not show
    // them, never render an empty or broken tile.
    final auth = await _auth();
    await _pumpShop(
      tester,
      auth,
      _FakeShopApi(
        powerupCatalog: _catalogWithoutNewTypes(),
        inventory: {'items': <Map<String, dynamic>>[]},
      ),
    );

    expect(find.text('Signal Jammer'), findsWidgets);
    expect(find.text('Hitchhike'), findsNothing);
    expect(find.text('Quick Rinse'), findsNothing);
  });

  group('use flow classification', () {
    test('Hitchhike opens the target picker; Quick Rinse does not', () {
      expect(kTargetedPowerupTypes, contains('HITCHHIKE'));
      // Quick Rinse is self-only and instantaneous — routing it through the
      // target picker would ask for a rival the server then rejects.
      expect(kTargetedPowerupTypes, isNot(contains('QUICK_RINSE')));
    });
  });
}
