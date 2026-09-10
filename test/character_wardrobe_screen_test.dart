import 'support/shop_navigation.dart';
import 'package:flutter/foundation.dart';
import 'package:step_tracker/tutorial/spotlight_overlay.dart';
import 'package:step_tracker/widgets/app_refresh_indicator.dart';
import 'package:step_tracker/widgets/race_ui.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'unified_shop_test.dart' show ShopApi, shopAuth;

const emptySlots = <String, String?>{
  'HEAD': null,
  'FACE': null,
  'NECK': null,
  'BACK': null,
  'FEET': null,
};
const hat = <String, dynamic>{
  'id': 'shop-baseball-cap',
  'sku': 'baseball_cap',
  'name': 'Baseball Cap',
  'slot': 'HEAD',
  'assetKey': 'baseball_cap',
  'priceCoins': 200,
};
const corgi = <String, dynamic>{
  'id': 'character-corgi',
  'sku': 'corgi',
  'name': 'Corgi',
  'slot': 'CHARACTER',
  'assetKey': 'corgi_puppy',
  'priceCoins': 300,
};

class WardrobeApi extends ShopApi {
  String active = 'default';
  int appearance = 0;
  final outfits = <String, Map<String, String?>>{
    'default': {...emptySlots},
    'character-corgi': {...emptySlots},
  };
  final revisions = <String, int>{'default': 0, 'character-corgi': 0};
  bool hidden = false;
  bool omitRevision = false;
  bool hatOwned = true;
  bool conflict = false;
  bool unsupported = false;
  int saves = 0;
  int activations = 0;
  Completer<Map<String, dynamic>>? delayed;
  Map<String, dynamic> outfit(String key) => {
    if (!omitRevision) 'revision': revisions[key],
    'editable': !hidden,
    'hasHiddenItems': hidden,
    'slots': outfits[key],
    'items': [if (outfits[key]?['HEAD'] != null) hat],
    'unavailableItemIds': <String>[],
  };
  Map<String, dynamic> envelope() => {
    'contract': 'character-wardrobes-v1',
    'appearanceRevision': appearance,
    'activeCharacterKey': active,
    'activeCharacterVisible': true,
    'coins': 100,
    'adUnlock': null,
  };
  Map<String, dynamic> row(String key, {bool owned = true}) => {
    'characterKey': key,
    'name': key == 'default' ? 'Capybara' : 'Corgi',
    'item': key == 'default' ? null : {...corgi, 'id': key},
    'owned': owned,
    'active': key == active,
    'canPurchase': !owned,
    'canActivate': owned,
    'canEdit': owned,
    'availability': 'available',
    'outfit': owned ? outfit(key) : null,
  };

  // These fixtures exercise the exact approved service surface once added.
  @override
  Future<Map<String, dynamic>> fetchShopCharacters({
    required String identityToken,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async {
    if (unsupported) return {};
    return {
      ...envelope(),
      'characters': [
        row('default'),
        row('character-corgi'),
        row('locked-corgi', owned: false),
      ],
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchCharacterWardrobe({
    required String identityToken,
    required String characterKey,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async => {
    ...envelope(),
    'characterKey': characterKey,
    'name': characterKey == 'default' ? 'Capybara' : 'Corgi',
    'active': characterKey == active,
    'canActivate': true,
    'outfit': outfit(characterKey),
    'accessories': [
      {
        'item': hat,
        'owned': hatOwned,
        'canPurchase': !hatOwned,
        'canSelect': hatOwned,
        'canPreview': true,
        'fit': 'approved',
        'unavailableReason': null,
      },
    ],
    'nextCursor': null,
  };
  @override
  Future<Map<String, dynamic>> saveCharacterOutfit({
    required String identityToken,
    required String characterKey,
    required int expectedOutfitRevision,
    required Map<String, String?> slots,
  }) async {
    saves++;
    if (conflict) {
      throw ApiException(
        'Your outfit changed on another device.',
        statusCode: 409,
        code: 'OUTFIT_CHANGED',
      );
    }
    if (delayed case final pending?) return pending.future;
    outfits[characterKey] = {...slots};
    revisions[characterKey] = (revisions[characterKey] ?? 0) + 1;
    if (active == characterKey) appearance++;
    return {
      ...envelope(),
      'characterKey': characterKey,
      'outfit': outfit(characterKey),
      'appearanceChanged': active == characterKey,
      'equipped': {
        if (outfits[active]?['HEAD'] != null) 'HEAD': hat,
        if (active != 'default') 'CHARACTER': corgi,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> activateShopCharacter({
    required String identityToken,
    required String characterKey,
    required int expectedAppearanceRevision,
    required int expectedOutfitRevision,
  }) async {
    activations++;
    active = characterKey;
    appearance++;
    return {
      ...envelope(),
      'characterKey': characterKey,
      'outfit': outfit(characterKey),
      'appearanceChanged': true,
      'equipped': {
        if (outfits[active]?['HEAD'] != null) 'HEAD': hat,
        if (active != 'default') 'CHARACTER': corgi,
      },
    };
  }
}

class LostSaveApi extends WardrobeApi {
  bool commit = true;
  @override
  Future<Map<String, dynamic>> saveCharacterOutfit({
    required String identityToken,
    required String characterKey,
    required int expectedOutfitRevision,
    required Map<String, String?> slots,
  }) async {
    if (commit) {
      await super.saveCharacterOutfit(
        identityToken: identityToken,
        characterKey: characterKey,
        expectedOutfitRevision: expectedOutfitRevision,
        slots: slots,
      );
    } else {
      saves++;
    }
    throw const ApiException('Response lost.', statusCode: 500);
  }
}

class LostActivationApi extends WardrobeApi {
  LostActivationApi(this.commit);
  final bool commit;
  @override
  Future<Map<String, dynamic>> activateShopCharacter({
    required String identityToken,
    required String characterKey,
    required int expectedAppearanceRevision,
    required int expectedOutfitRevision,
  }) async {
    if (commit) {
      await super.activateShopCharacter(
        identityToken: identityToken,
        characterKey: characterKey,
        expectedAppearanceRevision: expectedAppearanceRevision,
        expectedOutfitRevision: expectedOutfitRevision,
      );
    } else {
      activations++;
    }
    throw const ApiException('Response lost.', statusCode: 500);
  }
}

class PurchaseWardrobeApi extends WardrobeApi {
  PurchaseWardrobeApi() {
    hatOwned = false;
  }
  int purchases = 0;
  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {'coins': 1000, 'items': []};
  @override
  Future<Map<String, dynamic>> purchaseShopItem({
    required String identityToken,
    required String itemId,
    required String idempotencyKey,
    int? expectedPriceCoins,
  }) async {
    expect(expectedPriceCoins, 200);
    purchases++;
    hatOwned = true;
    return {
      'coins': 800,
      'item': {...hat, 'owned': true},
    };
  }
}

class MalformedWardrobeApi extends WardrobeApi {
  MalformedWardrobeApi(this.fault);
  final String fault;
  @override
  Map<String, dynamic> outfit(String key) => switch (fault) {
    'unknown-slot' => {
      ...super.outfit(key),
      'slots': {...emptySlots, 'TAIL': null},
    },
    'duplicate-id' => {
      ...super.outfit(key),
      'slots': {...emptySlots, 'HEAD': hat['id'], 'FACE': hat['id']},
      'items': [hat],
    },
    _ => super.outfit(key),
  };
  @override
  Map<String, dynamic> envelope() => {
    ...super.envelope(),
    if (fault == 'appearance') 'appearanceRevision': null,
  };
  @override
  Map<String, dynamic> row(String key, {bool owned = true}) => {
    ...super.row(key, owned: owned),
    if (fault == 'ownership') 'owned': null,
  };
}

class PagingWardrobeApi extends WardrobeApi {
  final pendingPage = Completer<Map<String, dynamic>>();
  bool refreshed = false;
  int firstPages = 0;
  int pageReads = 0;
  @override
  Future<Map<String, dynamic>> fetchCharacterWardrobe({
    required String identityToken,
    required String characterKey,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async {
    if (cursor != null) {
      pageReads++;
      if (cursor == 'page-new') {
        return {
          ...await super.fetchCharacterWardrobe(
            identityToken: identityToken,
            characterKey: characterKey,
          ),
          'accessories': [],
          'nextCursor': null,
        };
      }
      return pendingPage.future;
    }
    firstPages++;
    final data = await super.fetchCharacterWardrobe(
      identityToken: identityToken,
      characterKey: characterKey,
    );
    return {
      ...data,
      'accessories': refreshed ? [] : data['accessories'],
      'nextCursor': refreshed ? 'page-new' : 'page-2',
    };
  }

  Future<Map<String, dynamic>> latePage({int revision = 0}) async {
    final data = await super.fetchCharacterWardrobe(
      identityToken: 'test',
      characterKey: 'default',
    );
    return {
      ...data,
      'appearanceRevision': revision,
      'outfit': {...outfit('default'), 'revision': revision},
      'accessories': [
        {
          'item': {...hat, 'id': 'stale-page-hat', 'name': 'Stale page hat'},
          'owned': true,
          'canPreview': true,
          'canSelect': true,
          'canPurchase': false,
          'fit': 'approved',
        },
      ],
    };
  }
}

class UnsupportedWardrobeApi extends WardrobeApi {
  UnsupportedWardrobeApi(this.status);
  final int? status;
  int purchases = 0;
  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {'coins': 1000, 'items': []};
  @override
  Future<Map<String, dynamic>> purchaseShopItem({
    required String identityToken,
    required String itemId,
    required String idempotencyKey,
    int? expectedPriceCoins,
  }) async {
    purchases++;
    return {
      'coins': 700,
      'item': {...corgi, 'owned': true},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchShopCharacters({
    required String identityToken,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async {
    if (status == null) return {'contract': 'future-contract'};
    throw ApiException('Unsupported endpoint', statusCode: status);
  }

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => {
    'coins': 1000,
    'items': [
      {...corgi, 'owned': false},
    ],
    'ownedItemIds': [],
    'equipped': {},
  };
}

class PagedCharactersApi extends WardrobeApi {
  final requests = <({int limit, String? cursor})>[];
  @override
  Future<Map<String, dynamic>> fetchShopCharacters({
    required String identityToken,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async {
    requests.add((limit: limit, cursor: cursor));
    if (cursor == null) {
      return {
        ...envelope(),
        'characters': [row('default'), row('character-corgi')],
        'nextCursor': appearance == 0 ? 'page-2' : null,
      };
    }
    return {
      ...envelope(),
      'characters': [
        row('character-corgi'),
        row(
          appearance == 0 ? 'character-second' : 'incoherent-page',
          owned: false,
        ),
      ],
      'nextCursor': 'page-3',
    };
  }
}

class PreservationOnlyApi extends WardrobeApi {
  @override
  Future<Map<String, dynamic>> fetchCharacterWardrobe({
    required String identityToken,
    required String characterKey,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async => {
    ...await super.fetchCharacterWardrobe(
      identityToken: identityToken,
      characterKey: characterKey,
    ),
    'accessories': [
      {
        'item': hat,
        'owned': true,
        'canPurchase': false,
        'canPreview': false,
        'canSelect': false,
        'fit': 'preservation-only',
        'unavailableReason': 'incompatible',
      },
    ],
  };
}

class SectionedAccessoriesApi extends WardrobeApi {
  @override
  Future<Map<String, dynamic>> fetchCharacterWardrobe({
    required String identityToken,
    required String characterKey,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async => {
    ...await super.fetchCharacterWardrobe(
      identityToken: identityToken,
      characterKey: characterKey,
    ),
    'accessories': [
      for (var i = 0; i < 30; i++)
        {
          'item': {...hat, 'id': 'accessory-$i', 'name': 'Accessory $i'},
          'owned': i < 15,
          'canPurchase': i >= 15,
          'canPreview': true,
          'canSelect': i < 15,
          'fit': 'approved',
        },
      {
        'item': {...hat, 'id': 'preserved'},
        'owned': true,
        'canPurchase': false,
        'canPreview': false,
        'canSelect': false,
        'fit': 'preservation-only',
      },
    ],
  };
}

Future<void> platformBack(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  if (debugDefaultTargetPlatformOverride == TargetPlatform.iOS) {
    await tester.timedDragFrom(
      const Offset(1, 350),
      const Offset(350, 0),
      const Duration(milliseconds: 500),
    );
  } else {
    await tester.binding.handlePopRoute();
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> pumpWardrobeShop(WidgetTester tester, WardrobeApi api) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = await shopAuth();
  await tester.pumpWidget(
    BillingScope.disabled(
      child: MaterialApp(home: const Scaffold(body: Text('App host'))),
    ),
  );
  Navigator.of(tester.element(find.text('App host'))).push(
    MaterialPageRoute<void>(
      builder: (_) => ShopTab(authService: auth, backendApiService: api),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await selectShopCategory(tester, 'CHARACTERS');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> openWardrobe(WidgetTester tester, {String key = 'default'}) async {
  if (find.byKey(const Key('info-toast-shell')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('info-toast-shell')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.ensureVisible(find.byKey(Key('shop-character-$key')));
  await tester.pump();
  await tester.tap(find.byKey(Key('shop-character-$key')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('Edit outfit'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'token',
      'auth_user_identifier': 'apple',
      'auth_session_token': 'session',
      'auth_backend_user_id': 'user',
      'auth_coins': 100,
    });
  });
  testWidgets(
    'Owned and Unowned sections keep Save outfit fixed while accessories scroll',
    (tester) async {
      final api = SectionedAccessoriesApi();
      await pumpWardrobeShop(tester, api);
      await openWardrobe(tester);
      expect(find.byKey(const Key('wardrobe-section-owned')), findsOneWidget);
      expect(find.byKey(const Key('wardrobe-section-unowned')), findsOneWidget);
      expect(find.byKey(const Key('wardrobe-item-preserved')), findsNothing);
      expect(find.text('Other owned items'), findsNothing);
      final controls = find.byKey(const Key('wardrobe-controls'));
      await tester.pump(const Duration(milliseconds: 400));
      final before = tester.getRect(controls);
      expect(before.bottom, lessThanOrEqualTo(844));
      await tester.drag(find.byType(ListView).last, const Offset(0, -700));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(controls), before);
      expect(find.text('Save outfit').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Characters collection deduplicates pages and restarts on appearance revision change',
    (tester) async {
      final api = PagedCharactersApi();
      await pumpWardrobeShop(tester, api);
      expect(api.requests, [(limit: 24, cursor: null)]);
      await tester.ensureVisible(find.text('Load more'));
      await tester.pump();
      await tester.tap(find.text('Load more'));
      await tester.pump();
      expect(find.byKey(const Key('shop-character-default')), findsOneWidget);
      expect(
        find.byKey(const Key('shop-character-character-corgi')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shop-character-character-second')),
        findsOneWidget,
      );
      expect(api.requests.last, (limit: 24, cursor: 'page-2'));
      api.appearance = 1;
      api.active = 'character-corgi';
      await tester.ensureVisible(find.text('Load more'));
      await tester.pump();
      await tester.tap(find.text('Load more'));
      await tester.pump();
      expect(api.requests.map((r) => r.cursor), [
        null,
        'page-2',
        'page-3',
        null,
      ]);
      expect(
        find.byKey(const Key('shop-character-character-second')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('shop-character-incoherent-page')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shop-character-default')),
          matching: find.text('ACTIVE'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shop-character-character-corgi')),
          matching: find.text('ACTIVE'),
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'compatible empty state hides preservation-only items without changing ownership',
    (tester) async {
      await pumpWardrobeShop(tester, PreservationOnlyApi());
      await openWardrobe(tester);
      expect(find.byKey(const Key('wardrobe-preview')), findsOneWidget);
      expect(
        find.text('No accessories for this character yet.'),
        findsOneWidget,
      );
      expect(find.text('Other owned items'), findsNothing);
      expect(
        find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'platform Back exits clean routes and protects dirty and pending outfits',
    (tester) async {
      final api = WardrobeApi();
      await pumpWardrobeShop(tester, api);
      await openWardrobe(tester);
      await platformBack(tester);
      expect(find.text('Back to Characters'), findsNothing);
      expect(find.byKey(const Key('shop-character-default')), findsOneWidget);
      await platformBack(tester);
      expect(find.text('App host'), findsOneWidget);
      expect(find.byType(ShopTab), findsNothing);

      // Reopen the real pushed route and verify platform-specific dirty behavior.
      await pumpWardrobeShop(tester, api);
      await openWardrobe(tester);
      await tester.tap(
        find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
      );
      await tester.pump();
      await platformBack(tester);
      expect(find.text('Back to Characters'), findsOneWidget);
      if (debugDefaultTargetPlatformOverride == TargetPlatform.iOS) {
        expect(find.text('Discard outfit changes?'), findsNothing);
      } else {
        expect(find.text('Discard outfit changes?'), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(find.text('Back to Characters'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Keep editing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Trying on'), findsOneWidget);
      expect(api.saves, 0);

      // An outstanding save cannot be abandoned through header/system/edge Back.
      final pending = Completer<Map<String, dynamic>>();
      api.delayed = pending;
      await tester.tap(find.text('Save outfit'));
      await tester.pump();
      await platformBack(tester);
      expect(find.text('Back to Characters'), findsOneWidget);
      expect(find.text('Discard outfit changes?'), findsNothing);
      final back = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Back to Characters'),
          matching: find.byType(TextButton),
        ),
      );
      expect(back.onPressed, isNull);
      expect(api.saves, 1);
      pending.completeError(
        const ApiException('Response lost', statusCode: 500),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Review changed outfit'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Back to Characters'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Discard changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Back to Characters'), findsNothing);
      expect(find.byKey(const Key('shop-character-default')), findsOneWidget);
      expect(api.activations, 0);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
  testWidgets(
    'shop tutorial measures all six real route targets without wardrobe writes',
    (tester) async {
      final api = WardrobeApi();
      final auth = await shopAuth();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        BillingScope.disabled(
          child: MaterialApp(
            home: ShopTab(
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
      for (var index = 0; index < 6; index++) {
        final overlay = tester.widget<SpotlightOverlay>(
          find.byType(SpotlightOverlay),
        );
        expect(overlay.stepIndex, index);
        expect(overlay.targetRect, isNotNull);
        expect(overlay.targetRect!.width, greaterThan(0));
        await tester.tap(find.text(index == 5 ? 'DONE' : 'NEXT'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byType(SpotlightOverlay), findsNothing);
      expect(find.byKey(const Key('shop-character-default')), findsOneWidget);
      expect(api.saves, 0);
      expect(api.activations, 0);
    },
  );
  for (final commit in [true, false]) {
    testWidgets(
      'lost activation response reconciles exact saved look (committed=$commit)',
      (tester) async {
        final api = LostActivationApi(commit);
        await pumpWardrobeShop(tester, api);
        final card = find.byKey(const Key('shop-character-character-corgi'));
        await tester.tap(card);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Use character'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(api.activations, 1);
        expect(
          find.text('Corgi is active.'),
          commit ? findsOneWidget : findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.text('ACTIVE')),
          commit ? findsOneWidget : findsNothing,
        );
      },
    );
  }
  testWidgets('a slow old accessory page cannot overwrite a newer refresh', (
    tester,
  ) async {
    final api = PagingWardrobeApi();
    await pumpWardrobeShop(tester, api);
    await openWardrobe(tester);
    await tester.tap(find.text('Load more'));
    await tester.pump();
    api.refreshed = true;
    final refresh = tester.widget<AppRefreshIndicator>(
      find.byType(AppRefreshIndicator).last,
    );
    await refresh.onRefresh();
    await tester.pump();
    api.pendingPage.complete(await api.latePage());
    await tester.pump();
    expect(find.text('Stale page hat'), findsNothing);
    expect(
      find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
      findsNothing,
    );
    expect(api.firstPages, 2);
    expect(find.text('Load more'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pump();
    expect(api.pageReads, 2);
  });
  testWidgets(
    'a different revision page restarts pagination and preserves the local draft',
    (tester) async {
      final api = PagingWardrobeApi();
      await pumpWardrobeShop(tester, api);
      await openWardrobe(tester);
      await tester.tap(
        find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Load more'));
      await tester.pump();
      await tester.tap(find.text('Load more'));
      await tester.pump();
      api.refreshed = true;
      api.appearance = 1;
      api.revisions['default'] = 1;
      api.pendingPage.complete(await api.latePage(revision: 1));
      await tester.pump();
      expect(api.firstPages, 2);
      expect(find.text('Stale page hat'), findsNothing);
      expect(find.text('Trying on'), findsOneWidget);
      final avatar = tester.widget<RacerAvatar>(
        find.descendant(
          of: find.byKey(const Key('wardrobe-preview')),
          matching: find.byType(RacerAvatar),
        ),
      );
      expect(avatar.accessories.single['id'], hat['id']);
      expect(api.saves, 0);
    },
  );
  for (final status in <int?>[404, 405, null]) {
    testWidgets(
      'unsupported $status server keeps legacy browsing and purchase with no outfit writes',
      (tester) async {
        final api = UnsupportedWardrobeApi(status);
        await pumpWardrobeShop(tester, api);
        expect(find.byKey(const Key('shop-character-default')), findsOneWidget);
        await tester.tap(find.byKey(const Key('shop-character-default')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester
              .widget<PillButton>(
                find.ancestor(
                  of: find.text('Edit outfit'),
                  matching: find.byType(PillButton),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(find.text('Use character'), findsNothing);
        Navigator.of(tester.element(find.text('Edit outfit'))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.byKey(const Key('shop-character-character-corgi')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('BUY · 300'), findsOneWidget);
        await tester.tap(find.text('BUY · 300'));
        await tester.pump();
        expect(api.purchases, 1);
        expect(api.saves, 0);
        expect(api.activations, 0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Back'), findsOneWidget);
        await tester.tap(find.text('Back'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('App host'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'collection includes default owned and locked characters with distinct active status',
    (tester) async {
      await pumpWardrobeShop(tester, WardrobeApi());
      expect(find.byKey(const Key('shop-character-default')), findsOneWidget);
      expect(
        find.byKey(const Key('shop-character-character-corgi')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shop-character-locked-corgi')),
        findsOneWidget,
      );
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.byKey(const Key('shop-character-preview')), findsNothing);
    },
  );
  testWidgets(
    'inactive outfit save persists without activation and reset restores saved draft',
    (tester) async {
      final api = WardrobeApi();
      await pumpWardrobeShop(tester, api);
      await openWardrobe(tester, key: 'character-corgi');
      expect(find.byKey(const Key('wardrobe-preview')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('wardrobe-controls'))).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byKey(const Key('wardrobe-preview'))).dy,
        ),
      );
      await tester.tap(
        find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
      );
      await tester.pump();
      await tester.tap(find.text('Save outfit'));
      await tester.pump();
      expect(api.saves, 1);
      expect(api.active, 'default');
      expect(api.activations, 0);
      expect(api.outfits['character-corgi']?['HEAD'], 'shop-baseball-cap');
      await tester.tap(
        find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
      );
      await tester.pump();
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(find.text('Saved outfit'), findsOneWidget);
    },
  );
  testWidgets(
    'dirty back requires explicit discard and keeps draft when canceled',
    (tester) async {
      final api = WardrobeApi();
      await pumpWardrobeShop(tester, api);
      await openWardrobe(tester);
      await tester.tap(
        find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
      );
      await tester.pump();
      await tester.tap(find.text('Back to Characters'));
      await tester.pump();
      expect(find.text('Discard changes'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pump();
      expect(find.byKey(const Key('wardrobe-preview')), findsOneWidget);
      expect(api.saves, 0);
    },
  );
  for (final malformed in [false, true]) {
    testWidgets('hidden or missing revision outfit is read only ($malformed)', (
      tester,
    ) async {
      final api = WardrobeApi()
        ..hidden = !malformed
        ..omitRevision = malformed;
      await pumpWardrobeShop(tester, api);
      await openWardrobe(tester);
      expect(find.textContaining('unavailable'), findsWidgets);
      await tester.tap(
        find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
      );
      await tester.pump();
      expect(api.saves, 0);
    });
  }
  testWidgets('unowned preview blocks Save and offers explicit purchase', (
    tester,
  ) async {
    final api = WardrobeApi()..hatOwned = false;
    await pumpWardrobeShop(tester, api);
    await openWardrobe(tester);
    await tester.tap(find.byKey(const Key('wardrobe-item-shop-baseball-cap')));
    await tester.pump();
    expect(find.textContaining('Buy'), findsWidgets);
    await tester.tap(find.text('Save outfit'));
    await tester.pump();
    expect(api.saves, 0);
  });
  testWidgets('conflict preserves draft and requires explicit reload', (
    tester,
  ) async {
    final api = WardrobeApi()..conflict = true;
    await pumpWardrobeShop(tester, api);
    await openWardrobe(tester);
    await tester.tap(find.byKey(const Key('wardrobe-item-shop-baseball-cap')));
    await tester.pump();
    await tester.tap(find.text('Save outfit'));
    await tester.pump();
    expect(find.text('Reload saved'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
    expect(api.outfits['default']?['HEAD'], isNull);
  });
  testWidgets(
    'account change during save clears busy state and keeps Back usable',
    (tester) async {
      final api = WardrobeApi()..delayed = Completer<Map<String, dynamic>>();
      await pumpWardrobeShop(tester, api);
      await openWardrobe(tester);
      await tester.tap(
        find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
      );
      await tester.pump();
      await tester.tap(find.text('Save outfit'));
      await tester.pump();
      final auth = tester
          .widget<ShopTab>(find.byType(ShopTab, skipOffstage: false))
          .authService;
      await auth.syncFromBackendUser({
        'id': 'other-user',
        'coins': 500,
      }, authoritative: true);
      await tester.pump();
      expect(auth.userId, 'other-user');
      await tester.tap(find.text('Back to Characters'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byKey(const Key('wardrobe-preview')), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Back to Characters'), findsNothing);
      api.delayed!.complete({});
      await tester.pump();
      expect(find.text('Outfit saved.'), findsNothing);
    },
  );

  for (final committed in [true, false]) {
    testWidgets(
      'unknown save result reconciles authoritative state (committed=$committed)',
      (tester) async {
        final api = LostSaveApi()..commit = committed;
        await pumpWardrobeShop(tester, api);
        await openWardrobe(tester);
        await tester.tap(
          find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
        );
        await tester.pump();
        await tester.tap(find.text('Save outfit'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(api.saves, 1);
        expect(api.outfits['default']?['HEAD'], committed ? hat['id'] : null);
        expect(
          find.text('Outfit is saved.'),
          committed ? findsOneWidget : findsNothing,
        );
        if (!committed) {
          expect(find.text('Keep editing'), findsOneWidget);
          await tester.tap(find.text('Keep editing'));
          await tester.pump();
          expect(find.text('Trying on'), findsOneWidget);
        }
      },
    );
  }
  testWidgets(
    'unowned preview purchase then Save keeps ownership through later discard',
    (tester) async {
      final api = PurchaseWardrobeApi();
      await pumpWardrobeShop(tester, api);
      await openWardrobe(tester);
      await tester.tap(
        find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
      );
      await tester.pump();
      expect(find.text('Trying on'), findsOneWidget);
      await tester.tap(find.text('Buy · 200'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.purchases, 0);
      await tester.tap(find.text('BUY · 200'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(api.purchases, 1);
      expect(api.hatOwned, true);
      expect(api.saves, 0);
      await tester.tap(find.byKey(const Key('info-toast-shell')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Save outfit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.outfits['default']?['HEAD'], hat['id']);
      await tester.tap(
        find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
      );
      await tester.pump();
      await tester.tap(find.text('Back to Characters'));
      await tester.pump();
      await tester.tap(find.text('Discard changes'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(api.hatOwned, true);
      expect(api.purchases, 1);
      expect(api.saves, 1);
    },
  );
  testWidgets(
    'inactive saved card activates its saved outfit and persists when reopened',
    (tester) async {
      final api = WardrobeApi();
      await pumpWardrobeShop(tester, api);
      await openWardrobe(tester, key: 'character-corgi');
      await tester.tap(
        find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
      );
      await tester.pump();
      await tester.tap(find.text('Save outfit'));
      await tester.pump();
      await tester.tap(find.text('Back to Characters'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      final card = find.byKey(const Key('shop-character-character-corgi'));
      expect(
        tester
            .widget<RacerAvatar>(
              find.descendant(of: card, matching: find.byType(RacerAvatar)),
            )
            .accessories
            .single['id'],
        hat['id'],
      );
      if (find.byKey(const Key('info-toast-shell')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('info-toast-shell')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Use character'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(api.activations, 1);
      expect(api.active, 'character-corgi');
      expect(
        find.descendant(of: card, matching: find.text('ACTIVE')),
        findsOneWidget,
      );
      final auth = tester.widget<ShopTab>(find.byType(ShopTab)).authService;
      expect(auth.coins, 100);
      await openWardrobe(tester, key: 'character-corgi');
      expect(find.text('Saved outfit'), findsOneWidget);
      expect(api.outfits['character-corgi']?['HEAD'], hat['id']);
    },
  );
  for (final fault in [
    'unknown-slot',
    'duplicate-id',
    'appearance',
    'ownership',
  ]) {
    testWidgets('malformed $fault authority never writes or activates', (
      tester,
    ) async {
      final api = MalformedWardrobeApi(fault);
      await pumpWardrobeShop(tester, api);
      await tester.tap(find.byKey(const Key('shop-character-default')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (fault == 'ownership') {
        expect(find.text('Edit outfit'), findsOneWidget);
        expect(
          tester
              .widget<PillButton>(
                find.ancestor(
                  of: find.text('Edit outfit'),
                  matching: find.byType(PillButton),
                ),
              )
              .onPressed,
          isNull,
        );
      } else {
        await tester.tap(find.text('Edit outfit'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.byKey(const Key('wardrobe-item-shop-baseball-cap')),
        );
        await tester.pump();
        expect(
          tester
              .widget<PillButton>(
                find.ancestor(
                  of: find.text('Save outfit'),
                  matching: find.byType(PillButton),
                ),
              )
              .onPressed,
          isNull,
        );
      }
      expect(api.saves, 0);
      expect(api.activations, 0);
    });
  }
  testWidgets('owned character menu cannot activate after an account switch', (
    tester,
  ) async {
    final api = WardrobeApi();
    await pumpWardrobeShop(tester, api);
    await tester.tap(find.byKey(const Key('shop-character-character-corgi')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final auth = tester
        .widget<ShopTab>(find.byType(ShopTab, skipOffstage: false))
        .authService;
    await auth.syncFromBackendUser({
      'id': 'other-user',
      'coins': 500,
    }, authoritative: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Use character'), findsNothing);
    expect(api.activations, 0);
  });
}
