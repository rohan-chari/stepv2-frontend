import 'support/legacy_shop_wardrobe_fixture.dart';
import 'package:step_tracker/widgets/race_ui.dart';
import 'package:step_tracker/widgets/home_course_track.dart'
    show CapybaraSpriteWithAccessories, AnimatedCapybaraWithAccessories;
import 'support/shop_navigation.dart';
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

class _DressingRoomApi extends BackendApiService
    with LegacyShopWardrobeFixture {
  @override
  Future<Map<String, dynamic>> wardrobeFixtureCatalog(String token) async {
    if (failLegacyRefresh && equipWrites > 0) {
      throw const ApiException('Refresh failed.');
    }
    return catalog;
  }

  Completer<Map<String, dynamic>>? nextWardrobe;
  @override
  Future<Map<String, dynamic>> fetchCharacterWardrobe({
    required String identityToken,
    required String characterKey,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async {
    final pending = nextWardrobe;
    nextWardrobe = null;
    if (pending != null) {
      fixtureWardrobeReads++;
      return pending.future;
    }
    return super.fetchCharacterWardrobe(
      identityToken: identityToken,
      characterKey: characterKey,
      limit: limit,
      cursor: cursor,
      localDate: localDate,
    );
  }

  @override
  Future<Map<String, dynamic>> saveCharacterOutfit({
    required String identityToken,
    required String characterKey,
    required int expectedOutfitRevision,
    required Map<String, String?> slots,
  }) async {
    final result = await super.saveCharacterOutfit(
      identityToken: identityToken,
      characterKey: characterKey,
      expectedOutfitRevision: expectedOutfitRevision,
      slots: slots,
    );
    final equipment = equipResult?['equipped'];
    if (equipment is Map &&
        equipment.entries.any(
          (entry) => entry.value is! Map || entry.value['slot'] != entry.key,
        )) {
      fixtureEquipment = null;
      fixtureOutfits.clear();
    }
    return result;
  }

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
    int? expectedPriceCoins,
  }) async {
    purchaseWrites += 1;
    final pending = nextPurchase;
    nextPurchase = null;
    final error = purchaseError;
    if (error != null) throw error;
    final initialCatalog = catalog;
    final result = pending == null
        ? _ownedMoonPurchase(coins: 900)
        : await pending.future;
    if (identical(initialCatalog, catalog) && result['item'] is Map) {
      final item = Map<String, dynamic>.from(result['item'] as Map);
      catalog = {
        ...catalog,
        'coins': result['coins'],
        'ownedItemIds': [...(catalog['ownedItemIds'] as List), item['id']],
        'items': [
          for (final row in catalog['items'] as List)
            if (row is Map && row['id'] == item['id']) item else row,
        ],
      };
    }
    return result;
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
        initialFocus: ShopFocus.items,
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
  await tester.tap(find.text('Buy · 425'));
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
  await selectShopCategory(tester, category);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _selector(String id) => find.byKey(
  Key(
    id == '__default_capybara__'
        ? 'shop-character-default'
        : id == 'corgi'
        ? 'shop-character-corgi'
        : 'wardrobe-item-$id',
  ),
);
Finder _stage() => find.byKey(const Key('wardrobe-preview'));

Iterable<String> _previewIds(WidgetTester tester) => tester
    .widget<AnimatedCapybaraWithAccessories>(
      find.descendant(
        of: _stage(),
        matching: find.byType(AnimatedCapybaraWithAccessories),
      ),
    )
    .accessories
    .map((row) => row['id'] as String);
Future<void> _dismissToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save outfit'));
  await tester.pump();
  await tester.tap(find.text('Save outfit'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _leaveWardrobe(WidgetTester tester, {bool discard = false}) async {
  await _dismissToasts(tester);
  await tester.tap(find.byKey(const Key('wardrobe-back')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (discard) {
    expect(find.text('Discard outfit changes?'), findsOneWidget);
    await tester.tap(find.text('Discard changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

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
      find.descendant(of: _selector('cowboy'), matching: find.text('Selected')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _selector('bunny'), matching: find.text('Selected')),
      findsNothing,
    );

    await tester.tap(_selector('cowboy'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Save outfit'), findsOneWidget);

    await tester.tap(_selector('bunny'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Save outfit'), findsOneWidget);
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
    await tester.tap(find.text('Save outfit'));
    await tester.pump(const Duration(milliseconds: 220));

    expect(api.equipWrites, 1);
    expect(api.bootstrapReads, 1);
    expect(api.legacyCatalogReads, 0);
    expect(
      find.descendant(of: _selector('cowboy'), matching: find.text('Selected')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _selector('bunny'), matching: find.text('Selected')),
      findsNothing,
    );
    expect(find.byKey(const Key('wardrobe-saved-status')), findsOneWidget);
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
      await tester.tap(find.text('Save outfit'));
      await tester.pump(const Duration(milliseconds: 220));

      expect(api.fixtureWardrobeReads, greaterThanOrEqualTo(2));
      expect(_previewIds(tester), contains('bunny'));
      expect(
        api.catalog['equipped'],
        containsPair('HEAD', containsPair('id', 'cowboy')),
      );
      expect(find.byKey(const Key('wardrobe-unsaved-status')), findsOneWidget);
      expect(
        find.text('Could not verify the save. Your draft is kept.'),
        findsOneWidget,
      );
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
    await tester.tap(find.text('Save outfit'));
    await tester.pump(const Duration(milliseconds: 220));

    expect(api.legacyCatalogReads, 0);
    expect(
      find.descendant(of: _selector('cowboy'), matching: find.text('Selected')),
      findsNothing,
    );
    expect(
      find.descendant(of: _selector('bunny'), matching: find.text('Selected')),
      findsNothing,
    );
    expect(find.byKey(const Key('wardrobe-saved-status')), findsOneWidget);
  });

  testWidgets(
    'selecting default Capybara opens its own saved look then clears CHARACTER',
    (tester) async {
      final catalog = _catalog();
      final items = (catalog['items'] as List).cast<Map<String, dynamic>>();
      final index = items.indexWhere((item) => item['id'] == 'corgi');
      items[index] = {...items[index], 'owned': true};
      catalog['ownedItemIds'] = ['cowboy', 'bunny', 'corgi'];
      (catalog['equipped'] as Map<String, dynamic>)['CHARACTER'] = _row(
        id: 'corgi',
        sku: 'CORGI',
        name: 'Corgi Puppy',
        slot: 'CHARACTER',
        assetKey: 'corgi_puppy',
      );
      final api = _DressingRoomApi(catalog: catalog)
        ..equipResult = {'equipped': <String, dynamic>{}};
      await _pumpShop(tester, api);
      await _open(tester, section: 'INVENTORY', category: 'CHARACTERS');
      final capybara = _selector('__default_capybara__');
      expect(
        tester
            .widget<RacerAvatar>(
              find.descendant(of: capybara, matching: find.byType(RacerAvatar)),
            )
            .accessories,
        isEmpty,
      );
      expect(
        find.byKey(const Key('shop-character-equip-default')),
        findsOneWidget,
      );
      expect(api.equipWrites, 0);
      await tester.tap(find.byKey(const Key('shop-character-equip-default')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.fixtureActivations, 1);
      expect(api.lastEquipSlot, 'CHARACTER');
      expect(api.lastEquipItemId, isNull);
      expect(
        find.descendant(of: capybara, matching: find.text('ACTIVE')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<RacerAvatar>(
              find.descendant(of: capybara, matching: find.byType(RacerAvatar)),
            )
            .accessories,
        isEmpty,
      );
    },
  );

  testWidgets('Store selection is a zero-write local try-on', (tester) async {
    final api = _DressingRoomApi();
    await _pumpShop(tester, api);
    await _open(tester, section: 'STORE', category: 'ACCESSORIES');

    await tester.tap(_selector('moon-pack'));
    await tester.pump(const Duration(milliseconds: 180));

    expect(
      find.descendant(
        of: _stage(),
        matching: find.byKey(const Key('wardrobe-unsaved-status')),
      ),
      findsOneWidget,
    );
    expect(find.text('Buy · 425'), findsOneWidget);
    expect(find.byKey(const Key('shop-item-sheet')), findsNothing);
    expect(api.bootstrapReads, 1);
    expect(api.equipWrites, 0);
    expect(api.purchaseWrites, 0);
  });

  testWidgets(
    'locked character inspection uses its base art without another character outfit',
    (tester) async {
      final api = _DressingRoomApi();
      await _pumpShop(tester, api);
      await _open(tester, section: 'STORE', category: 'CHARACTERS');
      final card = _selector('corgi');
      final art = tester.widget<RacerAvatar>(
        find.descendant(of: card, matching: find.byType(RacerAvatar)),
      );
      expect(art.animal, 'corgi_puppy');
      expect(art.accessories, isEmpty);
      await tester.tap(find.byKey(const Key('shop-character-buy-corgi')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('shop-item-sheet')), findsOneWidget);
      expect(find.text('BUY · 350'), findsOneWidget);
      expect(api.bootstrapReads, 1);
      expect(api.equipWrites, 0);
      expect(api.purchaseWrites, 0);
    },
  );

  testWidgets('failed Store purchase keeps the local preview selected', (
    tester,
  ) async {
    final api = _DressingRoomApi()
      ..purchaseError = const ApiException('Purchase failed.');
    await _pumpShop(tester, api);
    await _open(tester, section: 'STORE', category: 'ACCESSORIES');

    await tester.tap(_selector('moon-pack'));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(find.text('Buy · 425'));
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
    expect(find.byKey(const Key('wardrobe-unsaved-status')), findsOneWidget);
    expect(find.text('Purchase failed.'), findsOneWidget);
    expect(api.equipWrites, 0);
  });

  testWidgets('wardrobe Back requires discard before clearing a local try-on', (
    tester,
  ) async {
    final api = _DressingRoomApi();
    await _pumpShop(tester, api);
    await _open(tester, section: 'STORE', category: 'ACCESSORIES');
    await tester.tap(_selector('moon-pack'));
    await tester.pump();
    expect(find.byKey(const Key('wardrobe-unsaved-status')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wardrobe-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Discard outfit changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_previewIds(tester), contains('moon-pack'));
    await _leaveWardrobe(tester, discard: true);
    expect(_stage(), findsNothing);
    await _open(tester, section: 'STORE', category: 'ACCESSORIES');
    expect(find.byKey(const Key('wardrobe-saved-status')), findsOneWidget);
    expect(_previewIds(tester), isNot(contains('moon-pack')));
    expect(api.equipWrites, 0);
    expect(api.purchaseWrites, 0);
  });

  testWidgets('cosmetic stage and grid use 3, 4, and 6 column breakpoints', (
    tester,
  ) async {
    for (final entry in const [(320.0, 3), (390.0, 4), (700.0, 6)]) {
      await _pumpShop(tester, _DressingRoomApi(), size: Size(entry.$1, 900));
      await _open(tester, section: 'INVENTORY', category: 'ACCESSORIES');

      final grid = tester.widget<GridView>(
        find.byKey(const Key('wardrobe-accessory-grid')).first,
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, entry.$2);
      expect(tester.getSize(_stage()).height, greaterThanOrEqualTo(160));
      expect(
        tester.getBottomLeft(_stage()).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('wardrobe-controls'))).dy,
        ),
      );
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
    tester.widget<ListView>(find.byType(ListView).last).controller!.jumpTo(0);
    await tester.pump();
    expect(_previewIds(tester), contains('moon-pack'));
    for (final switcher in tester.widgetList<AnimatedSwitcher>(
      find.descendant(of: _stage(), matching: find.byType(AnimatedSwitcher)),
    )) {
      expect(switcher.duration, Duration.zero);
    }
    expect(
      tester
          .widget<CapybaraSpriteWithAccessories>(
            find.descendant(
              of: _stage(),
              matching: find.byType(CapybaraSpriteWithAccessories),
            ),
          )
          .frameIndex,
      0,
    );
    await tester.scrollUntilVisible(
      find.text('Buy · 425'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Buy · 425').hitTestable(), findsOneWidget);
    expect(api.equipWrites, 0);
    expect(api.purchaseWrites, 0);
  });

  testWidgets('stale refresh cannot overwrite an accepted saved outfit', (
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
    final old = await api.fetchCharacterWardrobe(
      identityToken: 'session-token',
      characterKey: 'default',
    );
    final pending = Completer<Map<String, dynamic>>();
    api.nextWardrobe = pending;
    final refresh = tester
        .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator).last)
        .onRefresh();
    await tester.pump();
    await tester.tap(_selector('cowboy'));
    await tester.pump();
    await _save(tester);
    expect(api.fixtureSaves, 1);
    expect(_previewIds(tester), contains('cowboy'));
    pending.complete(old);
    await refresh;
    await tester.pump();
    expect(_previewIds(tester), contains('cowboy'));
    expect(_previewIds(tester), isNot(contains('bunny')));
    expect(find.byKey(const Key('wardrobe-saved-status')), findsOneWidget);
  });

  testWidgets('stale refresh cannot overwrite malformed-save recovery state', (
    tester,
  ) async {
    final api = _DressingRoomApi()
      ..equipResult = {
        'equipped': {
          'HEAD': {'id': 'bunny', 'slot': 'FACE'},
        },
      };
    await _pumpShop(tester, api);
    await _open(tester, section: 'INVENTORY', category: 'ACCESSORIES');
    final old = await api.fetchCharacterWardrobe(
      identityToken: 'session-token',
      characterKey: 'default',
    );
    final pending = Completer<Map<String, dynamic>>();
    api.nextWardrobe = pending;
    final refresh = tester
        .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator).last)
        .onRefresh();
    await tester.pump();
    api.fixtureOutfits['default'] = {
      'HEAD': 'cowboy',
      'FACE': null,
      'NECK': null,
      'BACK': null,
      'FEET': null,
    };
    api.catalog = _catalog(equippedHead: 'bunny');
    await tester.tap(_selector('bunny'));
    await tester.pump();
    await _save(tester);
    expect(api.equipWrites, 1);
    expect(api.fixtureWardrobeReads, greaterThanOrEqualTo(3));
    expect(_previewIds(tester), contains('bunny'));
    expect(_previewIds(tester), isNot(contains('cowboy')));
    pending.complete(old);
    await refresh;
    await tester.pump();
    expect(_previewIds(tester), contains('bunny'));
    expect(_previewIds(tester), isNot(contains('cowboy')));
    expect(find.byKey(const Key('wardrobe-saved-status')), findsOneWidget);
  });

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
      final callbacksBeforeCommit = changed.length;
      purchase.complete(_ownedMoonPurchase(coins: 900));
      await tester.pump(const Duration(milliseconds: 220));
      expect(auth.coins, 900);

      staleBootstrap.complete(_bootstrap(_catalog(), powerupCoins: 777));
      await refresh;
      await tester.pump(const Duration(milliseconds: 220));

      await _dismissToasts(tester);
      expect(_selector('moon-pack'), findsOneWidget);
      expect(auth.coins, 900);
      expect(changed, hasLength(callbacksBeforeCommit + 1));
      expect(changed.last['ownedItemIds'], contains('moon-pack'));
      expect(api.purchaseWrites, 1);
      expect(api.equipWrites, 0);
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
      final callbackCount = changed.length;
      expect(callbackCount, greaterThanOrEqualTo(2));
      expect(
        find.text('Please reopen the shop for this account.'),
        findsOneWidget,
      );
      expect(_selector('moon-pack'), findsNothing);
      purchase.complete(_ownedMoonPurchase(coins: 111));
      await tester.pump(const Duration(milliseconds: 400));
      expect(auth.coins, 222);
      expect(changed, hasLength(callbackCount));
      expect(find.text('Moon Pack unlocked.'), findsNothing);
      expect(_selector('moon-pack'), findsNothing);
      await _leaveWardrobe(tester);
      await _open(tester, section: 'STORE', category: 'ACCESSORIES');
      expect(_previewIds(tester), contains('bunny'));
      expect(_previewIds(tester), isNot(contains('cowboy')));
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
      final callbackCount = changed.length;
      expect(callbackCount, greaterThanOrEqualTo(1));
      expect(auth.coins, 1000);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
      purchase.complete(_ownedMoonPurchase(coins: 111));
      await tester.pump(const Duration(milliseconds: 220));

      expect(changed, hasLength(callbackCount));
      expect(auth.coins, 1000);
      expect(find.text('Moon Pack unlocked.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'accepted refresh removes disappeared item controls and preserves draft for review',
    (tester) async {
      final api = _DressingRoomApi();
      await _pumpShop(tester, api);
      await _open(tester, section: 'STORE', category: 'ACCESSORIES');
      await tester.tap(_selector('moon-pack'));
      await tester.pump();
      expect(find.byKey(const Key('wardrobe-unsaved-status')), findsOneWidget);
      final refreshed = _catalog();
      refreshed['items'] = (refreshed['items'] as List)
          .where((item) => item is! Map || item['id'] != 'moon-pack')
          .toList();
      api.catalog = refreshed;
      await tester
          .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator).last)
          .onRefresh();
      await tester.pump();
      expect(_selector('moon-pack'), findsNothing);
      expect(find.text('Buy · 425'), findsNothing);
      expect(
        tester
            .widget<PillButton>(find.widgetWithText(PillButton, 'Save outfit'))
            .onPressed,
        isNull,
      );
      expect(api.equipWrites, 0);
      expect(find.text('Reset'), findsNothing);
      await _leaveWardrobe(tester, discard: true);
      await _open(tester, section: 'STORE', category: 'ACCESSORIES');
      await tester.pump();
      expect(find.byKey(const Key('wardrobe-saved-status')), findsOneWidget);
      expect(_previewIds(tester), contains('cowboy'));
      expect(_previewIds(tester), isNot(contains('moon-pack')));
    },
  );

  testWidgets(
    '60-item compact grid scrolls and selects without backend churn',
    (tester) async {
      final api = _DressingRoomApi(catalog: _catalogWithManyAccessories(60));
      await _pumpShop(tester, api);
      await _open(tester, section: 'STORE', category: 'ACCESSORIES');

      final grids = tester.widgetList<GridView>(
        find.byKey(const Key('wardrobe-accessory-grid')),
      );
      expect(
        grids.fold<int>(
          0,
          (count, grid) =>
              count + (grid.childrenDelegate.estimatedChildCount ?? 0),
        ),
        24,
      );
      expect(api.fixtureWardrobeReads, 1);

      final lateSelector = _selector('performance-59');
      final shopScrollable = find.byType(Scrollable).first;
      final scrollState = tester.state<ScrollableState>(shopScrollable);
      for (var page = 0; page < 12 && lateSelector.evaluate().isEmpty; page++) {
        await tester.drag(shopScrollable, const Offset(0, -500));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.ensureVisible(lateSelector);
      await tester.pump();
      expect(api.fixtureWardrobeReads, 3);
      final readsBeforeSelection = api.fixtureWardrobeReads;
      await tester.pump();
      expect(scrollState.position.pixels, greaterThan(0));
      await tester.tap(lateSelector);
      await tester.pump(const Duration(milliseconds: 180));

      final selectedSemantics = find
          .descendant(of: lateSelector, matching: find.byType(Semantics))
          .first;
      expect(
        tester.widget<Semantics>(selectedSemantics).properties.selected,
        isTrue,
      );
      expect(api.fixtureWardrobeReads, readsBeforeSelection);
      expect(api.bootstrapReads, 1);
      expect(api.legacyCatalogReads, 0);
      expect(api.equipWrites, 0);
      expect(api.purchaseWrites, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
