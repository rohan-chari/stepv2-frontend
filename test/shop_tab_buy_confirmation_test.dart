import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';

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
    this.idempotentPowerupPurchase = false,
    this.bootstrapResult,
    this.powerupPurchaseCoins = 700,
    this.mutationAdUnlock,
    this.cosmeticPurchaseResult,
  });

  final Map<String, dynamic> catalog;
  final Map<String, dynamic> powerupCatalog;
  final Map<String, dynamic> inventory;
  final bool idempotentPowerupPurchase;
  final ShopBootstrapResult? bootstrapResult;
  final int powerupPurchaseCoins;
  final Map<String, dynamic>? mutationAdUnlock;
  final Map<String, dynamic>? cosmeticPurchaseResult;

  int cosmeticPurchases = 0;
  int powerupPurchases = 0;
  int powerupCatalogReads = 0;
  int inventoryReads = 0;

  @override
  Future<ShopBootstrapResult> fetchShopBootstrap({
    required String identityToken,
    required String localDate,
  }) async {
    final result = bootstrapResult;
    if (result != null) return result;
    return super.fetchShopBootstrap(
      identityToken: identityToken,
      localDate: localDate,
    );
  }

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
    powerupCatalogReads += 1;
    return powerupCatalog;
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async {
    inventoryReads += 1;
    return inventory;
  }

  @override
  Future<Map<String, dynamic>> purchaseShopItem({
    required String identityToken,
    required String itemId,
    required String idempotencyKey,
  }) async {
    cosmeticPurchases++;
    return cosmeticPurchaseResult ?? {'coins': 900};
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
      if (idempotentPowerupPurchase) 'idempotent': true,
      'coins': powerupPurchaseCoins,
      'inventory': {'powerupType': 'SIGNAL_JAMMER', 'quantity': 1},
      if (mutationAdUnlock != null) 'adUnlock': mutationAdUnlock,
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

const _jammerDescription = 'Jam a rival — they cannot use powerups for 1 hour';
const _hatDescription = 'A very readable blue hat';

Map<String, dynamic> _catalog() => {
  'coins': 1000,
  'ownedItemIds': <String>[],
  'equipped': <String, dynamic>{},
  'adUnlock': {
    'coinsPerAd': 100,
    'maxAds': 3,
    'maxShortfall': 500,
    'remainingToday': 3,
  },
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

Map<String, dynamic> _powerupCatalog({int? remainingToday}) => {
  'coins': 1000,
  if (remainingToday != null)
    'adUnlock': {
      'coinsPerAd': 100,
      'maxAds': 3,
      'maxShortfall': 500,
      'remainingToday': remainingToday,
    },
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
    'and does NOT purchase',
    (tester) async {
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
    },
  );

  testWidgets('the sheet BUY button is what actually purchases the powerup', (
    tester,
  ) async {
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
    expect(api.powerupCatalogReads, 1);
    expect(api.inventoryReads, 1);
    expect(auth.coins, 700);
  });

  testWidgets('idempotent powerup purchase refreshes only powerup components', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: {..._powerupCatalog(), 'coins': 625},
      inventory: _inventory(),
      idempotentPowerupPurchase: true,
    );

    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'STORE');
    await tester.ensureVisible(find.text('Signal Jammer'));
    await tester.tap(find.text('Signal Jammer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('BUY · 300'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.powerupPurchases, 1);
    expect(api.powerupCatalogReads, 2);
    expect(api.inventoryReads, 2);
    expect(auth.coins, 625);
  });

  testWidgets(
    'malformed compact powerups fall back without refetching valid inventory',
    (tester) async {
      final auth = await _createAuthService();
      final api = _FakeShopApi(
        catalog: _catalog(),
        powerupCatalog: _powerupCatalog(),
        inventory: _inventory(),
        bootstrapResult: ShopBootstrapResult(
          supported: true,
          cosmetics: _catalog(),
          powerups: const {
            'coins': 1000,
            'items': [
              {
                'sku': 'BROKEN',
                'name': 'Broken',
                'description': 'Bad row',
                'priceCoins': 'malformed',
                'powerupType': 'SIGNAL_JAMMER',
                'ownedQuantity': 0,
              },
            ],
            'adUnlock': {},
          },
          inventory: _inventory(),
        ),
      );

      await _pumpShop(tester, auth, api);
      await _selectSegment(tester, 'STORE');

      expect(find.text('Signal Jammer'), findsOneWidget);
      expect(api.powerupCatalogReads, 1);
      expect(api.inventoryReads, 0);
    },
  );

  testWidgets(
    'malformed compact inventory falls back without refetching valid powerups',
    (tester) async {
      final auth = await _createAuthService();
      final api = _FakeShopApi(
        catalog: _catalog(),
        powerupCatalog: _powerupCatalog(),
        inventory: _inventory(),
        bootstrapResult: ShopBootstrapResult(
          supported: true,
          cosmetics: _catalog(),
          powerups: _powerupCatalog(remainingToday: 3),
          inventory: const {
            'items': [
              {'powerupType': 'SIGNAL_JAMMER', 'quantity': 'malformed'},
            ],
          },
        ),
      );

      await _pumpShop(tester, auth, api);

      expect(api.powerupCatalogReads, 0);
      expect(api.inventoryReads, 1);
    },
  );

  testWidgets('powerup mutation applies the returned ad-unlock cap', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(remainingToday: 1),
      inventory: _inventory(),
      powerupPurchaseCoins: 0,
      mutationAdUnlock: const {
        'coinsPerAd': 100,
        'maxAds': 3,
        'maxShortfall': 500,
        'remainingToday': 0,
      },
    );

    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'STORE');
    await tester.ensureVisible(find.text('Signal Jammer'));
    await tester.tap(find.text('Signal Jammer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('BUY · 300'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(find.text('Signal Jammer'));
    await tester.tap(find.text('Signal Jammer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('GET MORE COINS'), findsOneWidget);
    expect(find.textContaining('WATCH 1 AD'), findsNothing);
  });

  testWidgets('cosmetic mutation overrides a stale powerup ad-unlock cap', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(remainingToday: 1),
      inventory: _inventory(),
      cosmeticPurchaseResult: {
        'coins': 0,
        'item': {
          ...((_catalog()['items'] as List).first as Map<String, dynamic>),
          'owned': true,
        },
        'adUnlock': const {
          'coinsPerAd': 100,
          'maxAds': 3,
          'maxShortfall': 500,
          'remainingToday': 0,
        },
      },
    );

    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'STORE');
    await _selectCategory(tester, 'ACCESSORIES');
    final hatSelector = find.byKey(
      const Key('shop-cosmetic-selector-item-hat'),
    );
    await tester.scrollUntilVisible(
      hatSelector,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(hatSelector);
    await tester.pump(const Duration(milliseconds: 180));
    final stage = find.byKey(const Key('shop-dressing-room-stage'));
    await tester.ensureVisible(stage);
    await tester.pump();
    await tester.tap(
      find.descendant(of: stage, matching: find.text('DETAILS & BUY')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final buyButton = tester.widget<PillButton>(
      find.ancestor(
        of: find.text('BUY · 100'),
        matching: find.byType(PillButton),
      ),
    );
    buyButton.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final powerupsCategory = find.byKey(const Key('shop-category-POWERUPS'));
    await tester.ensureVisible(powerupsCategory);
    await tester.pump();
    await tester.tap(powerupsCategory);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Signal Jammer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('GET MORE COINS'), findsOneWidget);
    expect(find.textContaining('WATCH 1 AD'), findsNothing);
  });

  testWidgets('malformed mandatory compact cosmetics use the error state', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
      bootstrapResult: const ShopBootstrapResult(
        supported: true,
        cosmetics: <String, dynamic>{
          'coins': 1000,
          'ownedItemIds': <String>[],
          'equipped': <String, dynamic>{},
          'adUnlock': <String, dynamic>{},
          'items': <Map<String, dynamic>>[
            {
              'id': 'broken',
              'sku': 'BROKEN',
              'name': 'Broken',
              'description': 'Bad row',
              'slot': 'HEAD',
              'priceCoins': 'malformed',
              'assetKey': 'broken',
              'owned': false,
              'equipped': false,
            },
          ],
        },
        powerups: {'coins': 1, 'items': [], 'adUnlock': {}},
        inventory: {'items': []},
      ),
    );

    await _pumpShop(tester, auth, api);

    expect(find.textContaining('Could not load the shop'), findsWidgets);
    expect(api.powerupCatalogReads, 0);
    expect(api.inventoryReads, 0);
  });

  testWidgets('compact cosmetics render when ad-unlock policy is unavailable', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final cosmetics = {..._catalog()}..remove('adUnlock');
    final powerups = {..._powerupCatalog()}..remove('adUnlock');
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
      bootstrapResult: ShopBootstrapResult(
        supported: true,
        cosmetics: cosmetics,
        powerups: powerups,
        inventory: _inventory(),
      ),
    );

    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'STORE');
    await _selectCategory(tester, 'ACCESSORIES');

    expect(find.text('Blue Hat'), findsOneWidget);
    expect(api.powerupCatalogReads, 0);
    expect(api.inventoryReads, 0);
  });

  testWidgets(
    'completed legacy bootstrap does not retry absent optional reads',
    (tester) async {
      final auth = await _createAuthService();
      final api = _FakeShopApi(
        catalog: _catalog(),
        powerupCatalog: _powerupCatalog(),
        inventory: _inventory(),
        bootstrapResult: ShopBootstrapResult(
          supported: false,
          cosmetics: _catalog(),
          powerups: null,
          inventory: null,
        ),
      );

      await _pumpShop(tester, auth, api);
      await _selectSegment(tester, 'STORE');
      await _selectCategory(tester, 'ACCESSORIES');

      expect(find.text('Blue Hat'), findsOneWidget);
      expect(api.powerupCatalogReads, 0);
      expect(api.inventoryReads, 0);
    },
  );

  testWidgets(
    'cosmetic selection is local and stage details open the purchase sheet',
    (tester) async {
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
      final hatSelector = find.byKey(
        const Key('shop-cosmetic-selector-item-hat'),
      );
      await tester.scrollUntilVisible(
        hatSelector,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(hatSelector);
      await tester.pump(const Duration(milliseconds: 180));
      expect(api.cosmeticPurchases, 0);
      expect(find.byKey(const Key('shop-item-sheet')), findsNothing);

      final stage = find.byKey(const Key('shop-dressing-room-stage'));
      await tester.ensureVisible(stage);
      await tester.pump();
      await tester.tap(
        find.descendant(of: stage, matching: find.text('DETAILS & BUY')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_hatDescription), findsOneWidget);
      expect(find.text('BUY · 100'), findsOneWidget);
      expect(api.cosmeticPurchases, 0);
    },
  );
}
