import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/app_refresh_indicator.dart';
import 'package:step_tracker/widgets/pill_button.dart';

class _DressingRoomApi extends BackendApiService {
  _DressingRoomApi({Map<String, dynamic>? catalog})
    : catalog = catalog ?? _catalog();

  Map<String, dynamic> catalog;
  Map<String, dynamic>? equipResult;
  Object? equipError;
  Object? purchaseError;
  Completer<ShopBootstrapResult>? nextBootstrap;
  Completer<Map<String, dynamic>>? nextPurchase;
  bool failLegacyRefresh = false;
  int powerupCoins = 1000;

  int bootstrapReads = 0;
  int legacyCatalogReads = 0;
  int equipWrites = 0;
  int purchaseWrites = 0;
  String? lastEquipSlot;
  String? lastEquipItemId;

  @override
  Future<ShopBootstrapResult> fetchShopBootstrap({
    required String identityToken,
    required String localDate,
  }) async {
    bootstrapReads += 1;
    final pending = nextBootstrap;
    if (pending != null) {
      nextBootstrap = null;
      return pending.future;
    }
    return ShopBootstrapResult(
      supported: true,
      cosmetics: catalog,
      powerups: {'coins': powerupCoins, 'items': <Map<String, dynamic>>[]},
      inventory: const {'items': <Map<String, dynamic>>[]},
    );
  }

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    legacyCatalogReads += 1;
    if (failLegacyRefresh) {
      throw const ApiException('Refresh failed.');
    }
    return catalog;
  }

  @override
  Future<Map<String, dynamic>> equipAccessory({
    required String identityToken,
    required String slot,
    required String? itemId,
  }) async {
    equipWrites += 1;
    lastEquipSlot = slot;
    lastEquipItemId = itemId;
    final error = equipError;
    if (error != null) throw error;
    return equipResult ?? <String, dynamic>{'equipped': <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> purchaseShopItem({
    required String identityToken,
    required String itemId,
    required String idempotencyKey,
  }) async {
    purchaseWrites += 1;
    final pending = nextPurchase;
    if (pending != null) {
      nextPurchase = null;
      return pending.future;
    }
    final error = purchaseError;
    if (error != null) throw error;
    return {'coins': 900};
  }
}

Map<String, dynamic> _row({
  required String id,
  required String sku,
  required String name,
  required String slot,
  required String assetKey,
}) => {
  'id': id,
  'sku': sku,
  'name': name,
  'slot': slot,
  'assetKey': assetKey,
  'renderMetadata': <String, dynamic>{},
};

Map<String, dynamic> _item({
  required String id,
  required String sku,
  required String name,
  required String slot,
  required String assetKey,
  required bool owned,
  required bool equipped,
  int price = 100,
}) => {
  ..._row(id: id, sku: sku, name: name, slot: slot, assetKey: assetKey),
  'description': '$name description',
  'priceCoins': price,
  'owned': owned,
  'equipped': equipped,
};

Map<String, dynamic> _catalog({String equippedHead = 'cowboy'}) {
  final cowboy = _item(
    id: 'cowboy',
    sku: 'COWBOY_HAT',
    name: 'Cowboy Hat',
    slot: 'HEAD',
    assetKey: 'cowboy_hat',
    owned: true,
    equipped: false,
  );
  final bunny = _item(
    id: 'bunny',
    sku: 'BUNNY_EARS',
    name: 'Bunny Ears',
    slot: 'HEAD',
    assetKey: 'bunny_ears',
    owned: true,
    equipped: true,
  );
  return {
    'coins': 1000,
    'ownedItemIds': ['cowboy', 'bunny'],
    'equipped': {
      'HEAD': equippedHead == 'cowboy'
          ? _row(
              id: 'cowboy',
              sku: 'COWBOY_HAT',
              name: 'Cowboy Hat',
              slot: 'HEAD',
              assetKey: 'cowboy_hat',
            )
          : _row(
              id: 'bunny',
              sku: 'BUNNY_EARS',
              name: 'Bunny Ears',
              slot: 'HEAD',
              assetKey: 'bunny_ears',
            ),
    },
    'items': [
      cowboy,
      bunny,
      _item(
        id: 'moon-pack',
        sku: 'MOON_PACK',
        name: 'Moon Pack',
        slot: 'BACK',
        assetKey: 'missing_moon_pack',
        owned: false,
        equipped: false,
        price: 425,
      ),
      _item(
        id: 'corgi',
        sku: 'CORGI',
        name: 'Corgi Puppy',
        slot: 'CHARACTER',
        assetKey: 'corgi_puppy',
        owned: false,
        equipped: false,
        price: 350,
      ),
    ],
  };
}

Map<String, dynamic> _catalogWithManyAccessories(int count) {
  final catalog = _catalog();
  catalog['items'] = [
    ...(catalog['items'] as List),
    for (var index = 0; index < count; index++)
      _item(
        id: 'performance-$index',
        sku: 'PERFORMANCE_$index',
        name: 'Performance Accessory ${index + 1}',
        slot: 'HEAD',
        // Reuse a shipped cosmetic asset so this smoke test exercises the
        // production renderer and Flutter's shared image cache across rows.
        assetKey: 'cowboy_hat',
        owned: false,
        equipped: false,
        price: 100 + index,
      ),
  ];
  return catalog;
}

Map<String, dynamic> _ownedMoonPurchase({required int coins}) {
  final moonPack = (_catalog()['items'] as List)
      .whereType<Map<String, dynamic>>()
      .singleWhere((item) => item['id'] == 'moon-pack');
  return {
    'coins': coins,
    'item': {...moonPack, 'owned': true},
  };
}

ShopBootstrapResult _bootstrap(
  Map<String, dynamic> catalog, {
  required int powerupCoins,
}) => ShopBootstrapResult(
  supported: true,
  cosmetics: catalog,
  powerups: {'coins': powerupCoins, 'items': <Map<String, dynamic>>[]},
  inventory: const {'items': <Map<String, dynamic>>[]},
);

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
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpShop(
  WidgetTester tester,
  _DressingRoomApi api, {
  Size size = const Size(390, 900),
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  ThemeData? theme,
  AuthService? authService,
  ValueChanged<Map<String, dynamic>>? onShopChanged,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = authService ?? await _auth();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: size,
          textScaler: textScaler,
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: ShopTab(
        authService: auth,
        backendApiService: api,
        onShopChanged: onShopChanged,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 220));
}

Future<void> _replaceAuthSession(
  AuthService auth, {
  required String userId,
  required String token,
  required int coins,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('auth_identity_token', 'identity-$userId');
  await prefs.setString('auth_user_identifier', 'provider-$userId');
  await prefs.setString('auth_session_token', token);
  await prefs.setString('auth_backend_user_id', userId);
  await prefs.setString('auth_display_name', userId);
  await prefs.setInt('auth_coins', coins);
  await auth.restoreSession();
}

Future<void> _startMoonPackPurchase(
  WidgetTester tester,
  _DressingRoomApi api,
) async {
  await _open(tester, section: 'STORE', category: 'ACCESSORIES');
  await tester.tap(_selector('moon-pack'));
  await tester.pump(const Duration(milliseconds: 180));
  await tester.tap(
    find.descendant(of: _stage(), matching: find.text('DETAILS & BUY')),
  );
  await tester.pump(const Duration(milliseconds: 300));
  final buy = tester.widget<PillButton>(
    find.ancestor(
      of: find.text('BUY · 425'),
      matching: find.byType(PillButton),
    ),
  );
  buy.onPressed!();
  await tester.pump();
  expect(api.purchaseWrites, 1);
}

Future<void> _open(
  WidgetTester tester, {
  required String section,
  required String category,
}) async {
  await tester.tap(find.text(section).last);
  await tester.pump(const Duration(milliseconds: 180));
  await tester.tap(find.byKey(Key('shop-category-$category')));
  await tester.pump(const Duration(milliseconds: 180));
}

Finder _selector(String id) => find.byKey(Key('shop-cosmetic-selector-$id'));
Finder _stage() => find.byKey(const Key('shop-dressing-room-stage'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('equipped map overrides contradictory item booleans', (
    tester,
  ) async {
    final api = _DressingRoomApi();
    await _pumpShop(tester, api);
    await _open(tester, section: 'INVENTORY', category: 'ACCESSORIES');

    expect(
      find.descendant(
        of: _selector('cowboy'),
        matching: find.byKey(const Key('shop-cosmetic-equipped-cowboy')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _selector('bunny'),
        matching: find.byKey(const Key('shop-cosmetic-equipped-bunny')),
      ),
      findsNothing,
    );

    await tester.tap(_selector('cowboy'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      find.descendant(of: _stage(), matching: find.text('CLEAR')),
      findsOneWidget,
    );

    await tester.tap(_selector('bunny'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      find.descendant(of: _stage(), matching: find.text('EQUIP')),
      findsOneWidget,
    );
  });

  testWidgets('accepted equip map moves the badge without a catalog refetch', (
    tester,
  ) async {
    final api = _DressingRoomApi(catalog: _catalog(equippedHead: 'bunny'))
      ..equipResult = {
        'equipped': {
          'HEAD': _row(
            id: 'cowboy',
            sku: 'COWBOY_HAT',
            name: 'Cowboy Hat',
            slot: 'HEAD',
            assetKey: 'cowboy_hat',
          ),
        },
      };
    await _pumpShop(tester, api);
    await _open(tester, section: 'INVENTORY', category: 'ACCESSORIES');

    await tester.tap(_selector('cowboy'));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(
      find.descendant(of: _stage(), matching: find.text('EQUIP')),
    );
    await tester.pump(const Duration(milliseconds: 220));

    expect(api.equipWrites, 1);
    expect(api.bootstrapReads, 1);
    expect(api.legacyCatalogReads, 0);
    expect(
      find.byKey(const Key('shop-cosmetic-equipped-cowboy')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shop-cosmetic-equipped-bunny')), findsNothing);
    expect(find.text('Your equipped look'), findsOneWidget);
  });

  testWidgets(
    'malformed equip map preserves the outfit and draft when refresh fails',
    (tester) async {
      final api = _DressingRoomApi()
        ..equipResult = {
          'equipped': {
            'HEAD': {'id': 'bunny', 'slot': 'FACE'},
          },
        }
        ..failLegacyRefresh = true;
      await _pumpShop(tester, api);
      await _open(tester, section: 'INVENTORY', category: 'ACCESSORIES');

      await tester.tap(_selector('bunny'));
      await tester.pump(const Duration(milliseconds: 180));
      await tester.tap(
        find.descendant(of: _stage(), matching: find.text('EQUIP')),
      );
      await tester.pump(const Duration(milliseconds: 220));

      expect(api.legacyCatalogReads, 1);
      expect(
        find.byKey(const Key('shop-cosmetic-equipped-cowboy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shop-cosmetic-equipped-bunny')),
        findsNothing,
      );
      expect(find.text('Previewing Bunny Ears'), findsOneWidget);
      expect(find.text('Refresh failed.'), findsOneWidget);
    },
  );

  testWidgets('an empty complete equip map is accepted atomically', (
    tester,
  ) async {
    final api = _DressingRoomApi()
      ..equipResult = {'equipped': <String, dynamic>{}};
    await _pumpShop(tester, api);
    await _open(tester, section: 'INVENTORY', category: 'ACCESSORIES');

    await tester.tap(_selector('cowboy'));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(
      find.descendant(of: _stage(), matching: find.text('CLEAR')),
    );
    await tester.pump(const Duration(milliseconds: 220));

    expect(api.legacyCatalogReads, 0);
    expect(
      find.byKey(const Key('shop-cosmetic-equipped-cowboy')),
      findsNothing,
    );
    expect(find.byKey(const Key('shop-cosmetic-equipped-bunny')), findsNothing);
    expect(find.text('Your equipped look'), findsOneWidget);
  });

  testWidgets('selecting default Capybara previews then clears CHARACTER', (
    tester,
  ) async {
    final catalog = _catalog();
    final items = (catalog['items'] as List).cast<Map<String, dynamic>>();
    final corgiIndex = items.indexWhere((item) => item['id'] == 'corgi');
    items[corgiIndex] = {...items[corgiIndex], 'owned': true};
    catalog['ownedItemIds'] = ['cowboy', 'bunny', 'corgi'];
    (catalog['equipped'] as Map<String, dynamic>)['CHARACTER'] = _row(
      id: 'corgi',
      sku: 'CORGI',
      name: 'Corgi Puppy',
      slot: 'CHARACTER',
      assetKey: 'corgi_puppy',
    );
    final api = _DressingRoomApi(catalog: catalog)
      ..equipResult = {
        'equipped': {
          'HEAD': _row(
            id: 'cowboy',
            sku: 'COWBOY_HAT',
            name: 'Cowboy Hat',
            slot: 'HEAD',
            assetKey: 'cowboy_hat',
          ),
        },
      };
    await _pumpShop(tester, api);
    await _open(tester, section: 'INVENTORY', category: 'CHARACTERS');

    final capybara = _selector('__default_capybara__');
    await tester.tap(capybara);
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Previewing Capybara'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shop-preview-capybara-cowboy_hat')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: _stage(), matching: find.text('EQUIP')),
    );
    await tester.pump(const Duration(milliseconds: 220));

    expect(api.lastEquipSlot, 'CHARACTER');
    expect(api.lastEquipItemId, isNull);
    expect(find.text('Your equipped look'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shop-preview-capybara-cowboy_hat')),
      findsOneWidget,
    );
  });

  testWidgets('Store selection is a zero-write local try-on', (tester) async {
    final api = _DressingRoomApi();
    await _pumpShop(tester, api);
    await _open(tester, section: 'STORE', category: 'ACCESSORIES');

    await tester.tap(_selector('moon-pack'));
    await tester.pump(const Duration(milliseconds: 180));

    expect(
      find.descendant(
        of: _stage(),
        matching: find.text('Previewing Moon Pack'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _stage(), matching: find.text('DETAILS & BUY')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shop-item-sheet')), findsNothing);
    expect(api.bootstrapReads, 1);
    expect(api.equipWrites, 0);
    expect(api.purchaseWrites, 0);
  });

  testWidgets('Store character try-on preserves equipped accessories locally', (
    tester,
  ) async {
    final api = _DressingRoomApi();
    await _pumpShop(tester, api);
    await _open(tester, section: 'STORE', category: 'CHARACTERS');

    await tester.tap(_selector('corgi'));
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('Previewing Corgi Puppy'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('shop-preview-corgi_puppy-cowboy_hat')),
      findsOneWidget,
    );
    expect(api.bootstrapReads, 1);
    expect(api.equipWrites, 0);
    expect(api.purchaseWrites, 0);
  });

  testWidgets('failed Store purchase keeps the local preview selected', (
    tester,
  ) async {
    final api = _DressingRoomApi()
      ..purchaseError = const ApiException('Purchase failed.');
    await _pumpShop(tester, api);
    await _open(tester, section: 'STORE', category: 'ACCESSORIES');

    await tester.tap(_selector('moon-pack'));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(
      find.descendant(of: _stage(), matching: find.text('DETAILS & BUY')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final buy = tester.widget<PillButton>(
      find.ancestor(
        of: find.text('BUY · 425'),
        matching: find.byType(PillButton),
      ),
    );
    buy.onPressed!();
    await tester.pump(const Duration(milliseconds: 220));

    expect(api.purchaseWrites, 1);
    expect(find.text('Previewing Moon Pack'), findsOneWidget);
    expect(find.text('Purchase failed.'), findsOneWidget);
    expect(api.equipWrites, 0);
  });

  testWidgets('section and category changes clear local try-on state', (
    tester,
  ) async {
    final api = _DressingRoomApi();
    await _pumpShop(tester, api);
    await _open(tester, section: 'STORE', category: 'ACCESSORIES');
    await tester.tap(_selector('moon-pack'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Previewing Moon Pack'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shop-category-CHARACTERS')));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Your equipped look'), findsOneWidget);
    expect(find.text('Previewing Moon Pack'), findsNothing);

    await tester.tap(find.text('INVENTORY').last);
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Your equipped look'), findsOneWidget);
  });

  testWidgets('cosmetic stage and grid use 3, 4, and 6 column breakpoints', (
    tester,
  ) async {
    for (final entry in const [(320.0, 3), (390.0, 4), (700.0, 6)]) {
      await _pumpShop(tester, _DressingRoomApi(), size: Size(entry.$1, 900));
      await _open(tester, section: 'INVENTORY', category: 'ACCESSORIES');

      final grid = tester.widget<GridView>(
        find.byKey(const Key('shop-cosmetic-grid')),
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, entry.$2);
      expect(tester.getSize(_stage()).height, inInclusiveRange(210, 250));
      expect(
        tester.getSize(_selector('cowboy')).height,
        greaterThanOrEqualTo(48),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('large text and reduced motion keep the dressing room usable', (
    tester,
  ) async {
    final api = _DressingRoomApi();
    await _pumpShop(
      tester,
      api,
      size: const Size(320, 900),
      textScaler: const TextScaler.linear(2.5),
      disableAnimations: true,
    );
    await _open(tester, section: 'STORE', category: 'ACCESSORIES');
    await tester.ensureVisible(_selector('moon-pack'));
    await tester.pump();
    await tester.tap(_selector('moon-pack'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('DETAILS & BUY'), findsOneWidget);
    final switcher = tester.widget<AnimatedSwitcher>(
      find.byKey(const Key('shop-stage-avatar-transition')),
    );
    expect(switcher.duration, Duration.zero);
  });

  testWidgets('stale refresh cannot overwrite an accepted equip map', (
    tester,
  ) async {
    final api = _DressingRoomApi(catalog: _catalog(equippedHead: 'bunny'))
      ..equipResult = {
        'equipped': {
          'HEAD': _row(
            id: 'cowboy',
            sku: 'COWBOY_HAT',
            name: 'Cowboy Hat',
            slot: 'HEAD',
            assetKey: 'cowboy_hat',
          ),
        },
      };
    await _pumpShop(tester, api);
    await _open(tester, section: 'INVENTORY', category: 'ACCESSORIES');

    final staleRefresh = Completer<ShopBootstrapResult>();
    api.nextBootstrap = staleRefresh;
    final refresh = tester
        .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator))
        .onRefresh();
    await tester.pump();

    await tester.tap(_selector('cowboy'));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(
      find.descendant(of: _stage(), matching: find.text('EQUIP')),
    );
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      find.byKey(const Key('shop-cosmetic-equipped-cowboy')),
      findsOneWidget,
    );

    staleRefresh.complete(
      ShopBootstrapResult(
        supported: true,
        cosmetics: _catalog(equippedHead: 'bunny'),
        powerups: const {'coins': 1000, 'items': <Map<String, dynamic>>[]},
        inventory: const {'items': <Map<String, dynamic>>[]},
      ),
    );
    await refresh;
    await tester.pump(const Duration(milliseconds: 220));

    expect(
      find.byKey(const Key('shop-cosmetic-equipped-cowboy')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shop-cosmetic-equipped-bunny')), findsNothing);
  });

  testWidgets(
    'stale bootstrap cannot overwrite malformed-equip recovery state',
    (tester) async {
      final api = _DressingRoomApi()
        ..equipResult = {
          'equipped': {
            'HEAD': {'id': 'bunny', 'slot': 'FACE'},
          },
        };
      await _pumpShop(tester, api);
      await _open(tester, section: 'INVENTORY', category: 'ACCESSORIES');

      final staleBootstrap = Completer<ShopBootstrapResult>();
      api.nextBootstrap = staleBootstrap;
      final refresh = tester
          .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator))
          .onRefresh();
      await tester.pump();

      // The mutation commits on the server, but the 2xx response's equipped
      // map is malformed. The legacy recovery read returns the authoritative
      // post-commit state while the older bootstrap remains in flight.
      api.catalog = _catalog(equippedHead: 'bunny');
      await tester.tap(_selector('bunny'));
      await tester.pump(const Duration(milliseconds: 180));
      await tester.tap(
        find.descendant(of: _stage(), matching: find.text('EQUIP')),
      );
      await tester.pump(const Duration(milliseconds: 220));

      expect(api.equipWrites, 1);
      expect(api.legacyCatalogReads, 1);
      expect(
        find.byKey(const Key('shop-cosmetic-equipped-bunny')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shop-cosmetic-equipped-cowboy')),
        findsNothing,
      );

      staleBootstrap.complete(
        ShopBootstrapResult(
          supported: true,
          cosmetics: _catalog(equippedHead: 'cowboy'),
          powerups: const {'coins': 1000, 'items': <Map<String, dynamic>>[]},
          inventory: const {'items': <Map<String, dynamic>>[]},
        ),
      );
      await refresh;
      await tester.pump(const Duration(milliseconds: 220));

      expect(
        find.byKey(const Key('shop-cosmetic-equipped-bunny')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shop-cosmetic-equipped-cowboy')),
        findsNothing,
      );
      expect(find.text('Previewing Bunny Ears'), findsOneWidget);
    },
  );

  testWidgets(
    'bootstrap refresh begun around purchase cannot overwrite accepted state',
    (tester) async {
      final api = _DressingRoomApi();
      final purchase = Completer<Map<String, dynamic>>();
      api.nextPurchase = purchase;
      final changed = <Map<String, dynamic>>[];
      final auth = await _auth();
      await _pumpShop(
        tester,
        api,
        authService: auth,
        onShopChanged: changed.add,
      );

      final staleBootstrap = Completer<ShopBootstrapResult>();
      api.nextBootstrap = staleBootstrap;
      final refresh = tester
          .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator))
          .onRefresh();
      await tester.pump();

      await _startMoonPackPurchase(tester, api);
      purchase.complete(_ownedMoonPurchase(coins: 900));
      await tester.pump(const Duration(milliseconds: 220));
      expect(auth.coins, 900);

      staleBootstrap.complete(_bootstrap(_catalog(), powerupCoins: 777));
      await refresh;
      await tester.pump(const Duration(milliseconds: 220));

      await tester.tap(find.text('INVENTORY').last);
      await tester.pump(const Duration(milliseconds: 180));
      expect(_selector('moon-pack'), findsOneWidget);
      expect(auth.coins, 900);
      expect(changed, hasLength(2));
    },
  );

  testWidgets(
    'prior user purchase completion cannot patch callbacks coins or toasts',
    (tester) async {
      final api = _DressingRoomApi();
      final purchase = Completer<Map<String, dynamic>>();
      api.nextPurchase = purchase;
      final changed = <Map<String, dynamic>>[];
      final auth = await _auth();
      await _pumpShop(
        tester,
        api,
        authService: auth,
        onShopChanged: changed.add,
      );
      await _startMoonPackPurchase(tester, api);

      api
        ..catalog = _catalog(equippedHead: 'bunny')
        ..powerupCoins = 222;
      await _replaceAuthSession(
        auth,
        userId: 'user-2',
        token: 'session-token-2',
        coins: 2000,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      expect(auth.userId, 'user-2');
      expect(auth.coins, 222);
      expect(changed, hasLength(2));
      expect(
        find.byKey(const ValueKey('shop-preview-capybara-bunny_ears')),
        findsOneWidget,
      );

      purchase.complete(_ownedMoonPurchase(coins: 111));
      await tester.pump(const Duration(milliseconds: 220));

      expect(auth.coins, 222);
      expect(changed, hasLength(2));
      expect(_selector('moon-pack'), findsOneWidget);
      expect(find.text('Moon Pack unlocked.'), findsNothing);
      expect(
        find.byKey(const ValueKey('shop-preview-capybara-bunny_ears')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'purchase completion after Shop dispose cannot update external state',
    (tester) async {
      final api = _DressingRoomApi();
      final purchase = Completer<Map<String, dynamic>>();
      api.nextPurchase = purchase;
      final changed = <Map<String, dynamic>>[];
      final auth = await _auth();
      await _pumpShop(
        tester,
        api,
        authService: auth,
        onShopChanged: changed.add,
      );
      await _startMoonPackPurchase(tester, api);
      expect(changed, hasLength(1));
      expect(auth.coins, 1000);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
      purchase.complete(_ownedMoonPurchase(coins: 111));
      await tester.pump(const Duration(milliseconds: 220));

      expect(changed, hasLength(1));
      expect(auth.coins, 1000);
      expect(find.text('Moon Pack unlocked.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('accepted refresh clears a selected item that disappeared', (
    tester,
  ) async {
    final api = _DressingRoomApi();
    await _pumpShop(tester, api);
    await _open(tester, section: 'STORE', category: 'ACCESSORIES');
    await tester.tap(_selector('moon-pack'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Previewing Moon Pack'), findsOneWidget);

    final refreshedCatalog = _catalog();
    refreshedCatalog['items'] = (refreshedCatalog['items'] as List)
        .where((item) => item is! Map || item['id'] != 'moon-pack')
        .toList();
    final acceptedRefresh = Completer<ShopBootstrapResult>();
    api.nextBootstrap = acceptedRefresh;
    final refresh = tester
        .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator))
        .onRefresh();
    await tester.pump();
    acceptedRefresh.complete(_bootstrap(refreshedCatalog, powerupCoins: 1000));
    await refresh;
    await tester.pump(const Duration(milliseconds: 220));

    expect(_selector('moon-pack'), findsNothing);
    expect(find.text('Previewing Moon Pack'), findsNothing);
    expect(find.text('Your equipped look'), findsOneWidget);
    expect(find.text('DETAILS & BUY'), findsNothing);
  });

  testWidgets(
    '60-item compact grid scrolls and selects without backend churn',
    (tester) async {
      final api = _DressingRoomApi(catalog: _catalogWithManyAccessories(60));
      await _pumpShop(tester, api);
      await _open(tester, section: 'STORE', category: 'ACCESSORIES');

      final grid = tester.widget<GridView>(
        find.byKey(const Key('shop-cosmetic-grid')),
      );
      final delegate = grid.childrenDelegate as SliverChildBuilderDelegate;
      expect(delegate.childCount, greaterThanOrEqualTo(60));

      final lateSelector = _selector('performance-59');
      final shopScrollable = find.byType(Scrollable).first;
      final scrollState = tester.state<ScrollableState>(shopScrollable);
      await tester.scrollUntilVisible(
        lateSelector,
        600,
        scrollable: shopScrollable,
      );
      await tester.pump();
      expect(scrollState.position.pixels, greaterThan(0));
      await tester.tap(lateSelector);
      await tester.pump(const Duration(milliseconds: 180));

      final selectedSemantics = find.descendant(
        of: lateSelector,
        matching: find.byType(Semantics),
      ).first;
      expect(
        tester.widget<Semantics>(selectedSemantics).properties.selected,
        isTrue,
      );
      expect(api.bootstrapReads, 1);
      expect(api.legacyCatalogReads, 0);
      expect(api.equipWrites, 0);
      expect(api.purchaseWrites, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
