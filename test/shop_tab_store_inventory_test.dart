import 'support/shop_navigation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/remote_asset_cache.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/tutorial/spotlight_overlay.dart';
import 'package:step_tracker/widgets/accessory_thumbnail.dart';

// Store/Inventory overhaul for the shop tab.
//
// STORE shows:
//   - cosmetics the user does NOT yet own (owned cosmetics leave the store)
//   - purchasable powerups which are RE-BUYABLE
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
  int tutorialCompletionCalls = 0;

  Map<String, dynamic> get outfit => {
    'revision': 0,
    'editable': true,
    'hasHiddenItems': false,
    'slots': {
      'HEAD': null,
      'FACE': null,
      'NECK': null,
      'BACK': null,
      'FEET': null,
    },
    'items': [],
    'unavailableItemIds': [],
  };
  Map<String, dynamic> get envelope => {
    'contract': 'character-wardrobes-v1',
    'appearanceRevision': 0,
    'activeCharacterKey': 'default',
    'activeCharacterVisible': true,
  };
  @override
  Future<Map<String, dynamic>> fetchShopCharacters({
    required String identityToken,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async => {
    ...envelope,
    'characters': [
      {
        'characterKey': 'default',
        'name': 'Capybara',
        'owned': true,
        'active': true,
        'canEdit': true,
        'canActivate': true,
        'canPurchase': false,
        'item': null,
        'availability': 'available',
        'outfit': outfit,
      },
    ],
    'nextCursor': null,
  };
  @override
  Future<Map<String, dynamic>> fetchCharacterWardrobe({
    required String identityToken,
    required String characterKey,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async => {
    ...envelope,
    'characterKey': 'default',
    'name': 'Capybara',
    'active': true,
    'canActivate': true,
    'outfit': outfit,
    'accessories': [
      for (final item
          in catalog['items'] is List ? catalog['items'] as List : [])
        if (item is Map)
          {
            'item': item,
            'owned': item['owned'] == true,
            'canPurchase': item['owned'] != true,
            'canSelect': item['owned'] == true,
            'canPreview': true,
            'fit': 'approved',
            'unavailableReason': null,
          },
    ],
    'nextCursor': null,
  };

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
    int? expectedPriceCoins,
  }) async {
    return {
      'coins': 0,
      'inventory': {'powerupType': 'IMPOSTER', 'quantity': 1},
    };
  }

  @override
  Future<Map<String, dynamic>> completeShopTutorial({
    required String identityToken,
  }) async {
    tutorialCompletionCalls += 1;
    return const {
      'tutorialKey': 'shop_v1',
      'completedAt': '2026-09-06T12:00:00.000Z',
    };
  }
}

class _HeldShopApi extends _FakeShopApi {
  _HeldShopApi()
    : super(
        catalog: const <String, dynamic>{},
        powerupCatalog: const <String, dynamic>{},
        inventory: const <String, dynamic>{},
      );

  final catalogCompleter = Completer<Map<String, dynamic>>();
  final powerupCatalogCompleter = Completer<Map<String, dynamic>>();
  final inventoryCompleter = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) => catalogCompleter.future;

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) => powerupCatalogCompleter.future;

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) => inventoryCompleter.future;
}

Future<AuthService> _createAuthService([BackendApiService? api]) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'auth_coins': 1000,
    'auth_held_coins': 0,
  });
  final authService = AuthService(backendApiService: api);
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
      'priceCoins': 75,
      'powerupType': 'IMPOSTER',
      'ownedQuantity': 2,
    },
    {
      'sku': 'POWERUP_SIGNAL_JAMMER',
      'name': 'Signal Jammer',
      'description': 'Jam a rival — they can\'t use powerups for 1 hour',
      'priceCoins': 75,
      'powerupType': 'SIGNAL_JAMMER',
      'ownedQuantity': 0,
    },
  ],
};

Map<String, dynamic> _inventory() => {
  'items': [
    {'powerupType': 'IMPOSTER', 'quantity': 2},
    {'powerupType': 'SIGNAL_JAMMER', 'quantity': 3},
  ],
};

Future<void> _pumpShop(
  WidgetTester tester,
  AuthService auth,
  BackendApiService api,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ShopTab(
        initialFocus: ShopFocus.items,
        authService: auth,
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

Future<void> _selectSegment(WidgetTester tester, String label) async {
  final seg = find.text(label == 'STORE' ? 'BUY' : 'OWNED');
  if (seg.evaluate().isNotEmpty) {
    await tester.ensureVisible(seg.last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(seg.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }
}

/// Taps a category pill (POWERUPS / CHARACTERS / ACCESSORIES). One category is
/// shown at a time, so a test wanting cosmetics must select ACCESSORIES first.
Future<void> _selectCategory(WidgetTester tester, String label) async {
  await selectShopCategory(tester, label);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    ),
  );

  testWidgets('shop spotlight covers the control in overlay coordinates', (
    tester,
  ) async {
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );
    final auth = await _createAuthService(api);
    await tester.pumpWidget(
      MaterialApp(
        home: Padding(
          padding: const EdgeInsets.only(left: 40, top: 60),
          child: ShopTab(
            initialFocus: ShopFocus.items,
            authService: auth,
            backendApiService: api,
            forceTutorialReplay: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final overlay = find.byType(SpotlightOverlay);
    final target = tester.widget<SpotlightOverlay>(overlay).targetRect!;
    final control = tester.getRect(
      find.byKey(const Key('shop-section-featured')),
    );
    final overlayOrigin = tester.getTopLeft(overlay);
    expect(target.shift(overlayOrigin), control);
    expect(
      target
          .shift(overlayOrigin)
          .contains(tester.getCenter(find.text('Featured'))),
      isTrue,
    );
    expect(
      target
          .shift(overlayOrigin)
          .contains(tester.getCenter(find.text('Characters & Accessories'))),
      isFalse,
    );
  });

  for (final replay in [false, true]) {
    testWidgets(
      'shop spotlight follows route entry and Back (replay=$replay)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final api = _FakeShopApi(
          catalog: _catalog(),
          powerupCatalog: _powerupCatalog(),
          inventory: _inventory(),
        );
        final auth = await _createAuthService(api);
        await auth.syncFromBackendUser(const {
          'id': 'user-1',
          'shopTutorialCompletedAt': null,
        }, authoritative: true);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      transitionDuration: const Duration(milliseconds: 700),
                      pageBuilder: (_, animation, secondaryAnimation) =>
                          ShopTab(
                            initialFocus: ShopFocus.items,
                            authService: auth,
                            backendApiService: api,
                            forceTutorialReplay: replay,
                          ),
                      transitionsBuilder:
                          (_, animation, secondaryAnimation, child) =>
                              SlideTransition(
                                position: Tween(
                                  begin: const Offset(1, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                    ),
                  ),
                  child: const Text('Open shop'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open shop'));
        await tester.pump();
        var measurements = 0;
        void checkTarget() {
          final overlay = find.byType(SpotlightOverlay);
          if (overlay.evaluate().isEmpty) return;
          final target = tester.widget<SpotlightOverlay>(overlay).targetRect!;
          final actual = target.shift(tester.getTopLeft(overlay));
          final control = tester.getRect(
            find.byKey(const Key('shop-section-featured')),
          );
          expect(actual.left, closeTo(control.left, .01));
          expect(actual.top, closeTo(control.top, .01));
          expect(actual.right, closeTo(control.right, .01));
          expect(actual.bottom, closeTo(control.bottom, .01));
          measurements++;
        }

        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 80));
          checkTarget();
        }
        expect(measurements, greaterThan(3));
        await tester.tap(find.text('NEXT'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        await tester.tap(find.text('BACK'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        checkTarget();
        expect(find.text('EXPLORE THE SHOP'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('explicit incomplete state launches once and skip completes it', (
    tester,
  ) async {
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );
    final auth = await _createAuthService(api);
    await auth.syncFromBackendUser(const {
      'id': 'user-1',
      'shopTutorialCompletedAt': null,
    }, authoritative: true);

    await _pumpShop(tester, auth, api);
    expect(find.byKey(const Key('tutorial-callout-card')), findsOneWidget);
    expect(find.text('EXPLORE THE SHOP'), findsOneWidget);

    await tester.tap(find.text('SKIP'));
    await tester.pump();
    await tester.pump();
    expect(api.tutorialCompletionCalls, 1);
    expect(auth.shopTutorialCompletedAt, isNotNull);
    expect(find.byKey(const Key('tutorial-callout-card')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpShop(tester, auth, api);
    expect(find.byKey(const Key('tutorial-callout-card')), findsNothing);
  });

  testWidgets(
    'first-visit tutorial waits for successful bootstrap and measured targets',
    (tester) async {
      final api = _HeldShopApi();
      final auth = await _createAuthService(api);
      await auth.syncFromBackendUser(const {
        'id': 'user-1',
        'shopTutorialCompletedAt': null,
      }, authoritative: true);

      await tester.pumpWidget(
        MaterialApp(
          home: ShopTab(
            initialFocus: ShopFocus.items,
            authService: auth,
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('tutorial-callout-card')), findsNothing);

      api.catalogCompleter.complete(_catalog());
      await tester.pump();
      expect(find.byKey(const Key('tutorial-callout-card')), findsNothing);

      api.powerupCatalogCompleter.complete(_powerupCatalog());
      await tester.pump();
      expect(find.byKey(const Key('tutorial-callout-card')), findsNothing);

      api.inventoryCompleter.complete(_inventory());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      for (final key in const [
        Key('shop-section-featured'),
        Key('shop-product-grid'),
      ]) {
        expect(find.byKey(key), findsOneWidget);
      }
      expect(find.byKey(const Key('tutorial-callout-card')), findsOneWidget);
      expect(
        tester
            .widget<SpotlightOverlay>(find.byType(SpotlightOverlay))
            .targetRect,
        isNotNull,
      );
    },
  );

  testWidgets('absent and malformed tutorial fields never auto-launch', (
    tester,
  ) async {
    for (final payload in <Map<String, dynamic>>[
      const {'id': 'user-1'},
      const {'id': 'user-1', 'shopTutorialCompletedAt': 42},
    ]) {
      final api = _FakeShopApi(
        catalog: _catalog(),
        powerupCatalog: _powerupCatalog(),
        inventory: _inventory(),
      );
      final auth = await _createAuthService(api);
      await auth.syncFromBackendUser(payload, authoritative: true);
      await _pumpShop(tester, auth, api);
      expect(find.byKey(const Key('tutorial-callout-card')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('settings replay ignores completion without writing it again', (
    tester,
  ) async {
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );
    final auth = await _createAuthService(api);
    await auth.syncFromBackendUser(const {
      'id': 'user-1',
      'shopTutorialCompletedAt': '2026-09-06T12:00:00.000Z',
    }, authoritative: true);
    await tester.pumpWidget(
      MaterialApp(
        home: ShopTab(
          initialFocus: ShopFocus.items,
          authService: auth,
          backendApiService: api,
          forceTutorialReplay: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.byKey(const Key('tutorial-callout-card')), findsOneWidget);
    await tester.tap(find.text('SKIP'));
    await tester.pump();
    expect(api.tutorialCompletionCalls, 0);
  });

  testWidgets(
    'delayed same-account auth state starts the first-visit tutorial',
    (tester) async {
      final api = _FakeShopApi(
        catalog: _catalog(),
        powerupCatalog: _powerupCatalog(),
        inventory: _inventory(),
      );
      final auth = await _createAuthService(api);
      await _pumpShop(tester, auth, api);
      expect(find.byKey(const Key('tutorial-callout-card')), findsNothing);

      await auth.syncFromBackendUser(const {
        'id': 'user-1',
        'shopTutorialCompletedAt': null,
      }, authoritative: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(find.byKey(const Key('tutorial-callout-card')), findsOneWidget);
    },
  );

  testWidgets('tutorial preview never consumes a first real Shop visit', (
    tester,
  ) async {
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );
    final auth = await _createAuthService(api);
    await auth.syncFromBackendUser(const {
      'id': 'user-1',
      'shopTutorialCompletedAt': null,
    }, authoritative: true);
    await tester.pumpWidget(
      MaterialApp(
        home: ShopTab(
          initialFocus: ShopFocus.items,
          authService: auth,
          backendApiService: api,
          isTutorialPreview: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('tutorial-callout-card')), findsNothing);
    expect(api.tutorialCompletionCalls, 0);
    expect(auth.shopTutorialCompletedAt, isNull);
  });

  testWidgets('shop tabs stay legible in dark mode', (tester) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.night(),
        home: ShopTab(
          initialFocus: ShopFocus.items,
          authService: auth,
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    for (final label in ['Featured', 'Characters & Accessories']) {
      expect(
        tester.widget<Text>(find.text(label)).style?.color,
        AppPalette.night.textLight,
      );
    }
  });

  testWidgets('STORE filters retired Imposter from an older backend payload', (
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

    expect(find.text('Imposter'), findsNothing);
    expect(find.text('Signal Jammer'), findsWidgets);
    // The surviving 75-coin powerup still has its normal buy affordance.
    expect(find.text('75'), findsWidgets);
  });

  testWidgets('STORE shows the Signal Jammer as a purchasable powerup', (
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

    expect(find.text('Signal Jammer'), findsWidgets);
    final art = tester
        .widgetList<AccessoryThumbnail>(find.byType(AccessoryThumbnail))
        .where((thumbnail) => thumbnail.assetKey == 'SIGNAL_JAMMER')
        .toList();
    expect(art, isNotEmpty);
    expect(
      art.first.remoteKind,
      RemoteAssetKind.powerups,
      reason: 'shop art must resolve from the powerups CDN manifest section',
    );
  });

  testWidgets(
    'wardrobe shows purchasable and owned cosmetics with distinct actions',
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

      // Unowned cosmetic is offered in the store...
      expect(find.text('Blue Hat'), findsWidgets);
      // The owned cosmetic is grouped separately from purchase offers.
      expect(find.text('Red Scarf'), findsWidgets);
      expect(find.text('100 coins'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('wardrobe-item-item-owned')),
          matching: find.text('Owned'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('wardrobe-section-owned')), findsOneWidget);
      expect(find.byKey(const Key('wardrobe-section-locked')), findsOneWidget);
    },
  );

  testWidgets(
    'INVENTORY hides retired residue and keeps owned powerup counts',
    (tester) async {
      final auth = await _createAuthService();
      final api = _FakeShopApi(
        catalog: _catalog(),
        powerupCatalog: _powerupCatalog(),
        inventory: _inventory(),
      );

      await _pumpShop(tester, auth, api);
      await _selectSegment(tester, 'INVENTORY');

      // Retired residue is omitted while supported inventory remains usable.
      await _selectCategory(tester, 'POWERUPS');
      expect(find.text('Imposter'), findsNothing);
      expect(find.text('Signal Jammer'), findsWidgets);
      expect(find.textContaining('3'), findsWidgets);

      // Owned cosmetic appears under ACCESSORIES.
      await _selectCategory(tester, 'ACCESSORIES');
      expect(find.text('Red Scarf'), findsWidgets);
    },
  );

  testWidgets('Capybara details use identity copy without an ability claim', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
    );

    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'INVENTORY');
    await _selectCategory(tester, 'CHARACTERS');
    await tester.tap(find.byKey(const Key('shop-character-default')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('The original. Steady, sociable, and always in your corner.'),
      findsOneWidget,
    );
    expect(find.textContaining('ability'), findsNothing);
    expect(find.textContaining('bonus'), findsNothing);
  });

  testWidgets('degrades gracefully when powerup endpoints are unavailable', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final api = _FakeShopApi(
      catalog: _catalog(),
      powerupCatalog: _powerupCatalog(),
      inventory: _inventory(),
      powerupEndpointsAvailable: false,
    );

    // Should not throw; cosmetics still render. With powerups unavailable the
    // POWERUPS pill is absent entirely, so it must not be selectable.
    await _pumpShop(tester, auth, api);
    await _selectSegment(tester, 'STORE');
    expect(find.text('Powerups'), findsOneWidget);
    expect(
      find.textContaining('Powerups are currently unavailable'),
      findsOneWidget,
    );

    await _selectCategory(tester, 'ACCESSORIES');
    expect(find.text('Blue Hat'), findsWidgets);

    expect(find.text('Red Scarf'), findsWidgets);
  });
}
