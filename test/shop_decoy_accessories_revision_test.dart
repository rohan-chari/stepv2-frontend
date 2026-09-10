import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/screens/character_wardrobe_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/app_refresh_indicator.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/race_ui.dart';
import 'package:step_tracker/widgets/shop_character_card.dart';
import 'character_wardrobe_screen_test.dart' show WardrobeApi, hat, corgi;
import 'unified_shop_test.dart' show shopAuth;

class _Api extends WardrobeApi {
  bool empty = false, fail = false, malformed = false;
  Completer<Map<String, dynamic>>? catalogGate;
  String? wardrobeOpened;
  int purchases = 0;
  _Api() {
    hatOwned = false;
  }
  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    if (catalogGate case final gate?) return gate.future;
    if (fail) throw const ApiException('Offline');
    if (malformed) return {'items': null};
    return {
      'coins': 500,
      'items': [
        if (!empty)
          {
            ...hat,
            'description': 'A favorite hat.',
            'owned': hatOwned,
            'equipped': false,
          },
        {...corgi, 'description': '', 'owned': true, 'equipped': false},
      ],
      'ownedItemIds': [if (hatOwned) hat['id'], corgi['id']],
      'equipped': {},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {
    'coins': 500,
    'items': [
      for (final type in ['DECOY', 'IMPOSTER'])
        {
          'sku': 'POWERUP_$type',
          'name': type == 'DECOY' ? 'Decoy' : 'Imposter',
          'description': 'Race powerup',
          'priceCoins': 150,
          'powerupType': type,
        },
    ],
  };
  @override
  Future<Map<String, dynamic>> purchaseShopItem({
    required String identityToken,
    required String itemId,
    required String idempotencyKey,
    int? expectedPriceCoins,
  }) async {
    expect(itemId, hat['id']);
    expect(expectedPriceCoins, 200);
    purchases++;
    hatOwned = true;
    return {
      'coins': 300,
      'item': {
        ...hat,
        'description': 'A favorite hat.',
        'owned': true,
        'equipped': false,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchCharacterWardrobe({
    required String identityToken,
    required String characterKey,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) {
    wardrobeOpened = characterKey;
    return super.fetchCharacterWardrobe(
      identityToken: identityToken,
      characterKey: characterKey,
      limit: limit,
      cursor: cursor,
      localDate: localDate,
    );
  }
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
      'auth_coins': 500,
    });
  });
  Future<AuthService> render(
    WidgetTester tester,
    _Api api, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = await shopAuth();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ShopTab(
          authService: auth,
          backendApiService: api,
          initialFocus: ShopFocus.items,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    return auth;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Decoy returns at server price while Imposter stays hidden', (
    tester,
  ) async {
    await render(tester, _Api());
    expect(find.text('Decoy'), findsOneWidget);
    expect(find.text('Imposter'), findsNothing);
    await tap(tester, find.text('Decoy'));
    expect(find.text('BUY · 150'), findsOneWidget);
  });
  testWidgets(
    'separate Accessories purchases refresh ownership without opening wardrobe',
    (tester) async {
      final api = _Api();
      await render(tester, api);
      expect(find.text('Characters'), findsOneWidget);
      expect(find.text('Characters & Accessories'), findsNothing);
      final accessories = find.byKey(const Key('shop-section-accessories'));
      expect(
        tester.getTopLeft(accessories).dy,
        greaterThan(
          tester
              .getTopLeft(find.byKey(const Key('shop-section-characters')))
              .dy,
        ),
      );
      final tile = find.byKey(Key('shop-accessory-${hat['id']}'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('shop-accessories-grid')),
          matching: find.byType(ShopCharacterCard),
        ),
        findsNothing,
      );
      await tap(tester, tile);
      expect(api.wardrobeOpened, isNull);
      expect(find.text('BUY · 200'), findsOneWidget);
      await tap(tester, find.text('BUY · 200'));
      expect(api.purchases, 1);
      expect(tile, findsNothing);
      expect(find.text('No accessories for sale right now.'), findsOneWidget);
      await tester
          .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(tile, findsNothing);
    },
  );
  testWidgets('Edit outfit opens the active eligible character', (
    tester,
  ) async {
    final api = _Api()..active = 'character-corgi';
    await render(tester, api);
    await tap(tester, find.byKey(const Key('shop-edit-outfit')));
    expect(find.byType(CharacterWardrobeScreen), findsOneWidget);
    expect(api.wardrobeOpened, 'character-corgi');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'unsupported wardrobe keeps accessory purchases and explains disabled editing',
    (tester) async {
      await render(tester, _Api()..unsupported = true);
      expect(find.byKey(Key('shop-accessory-${hat['id']}')), findsOneWidget);
      expect(
        tester
            .widget<PillButton>(find.byKey(const Key('shop-edit-outfit')))
            .onPressed,
        isNull,
      );
      expect(
        find.text('Saved outfit is currently unavailable.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'owned accessories are excluded and empty catalog remains usable',
    (tester) async {
      await render(tester, _Api()..hatOwned = true);
      expect(find.byKey(Key('shop-accessory-${hat['id']}')), findsNothing);
      expect(find.text('No accessories for sale right now.'), findsOneWidget);
      expect(
        tester
            .widget<PillButton>(find.byKey(const Key('shop-edit-outfit')))
            .onPressed,
        isNotNull,
      );
    },
  );
  for (final malformed in [false, true]) {
    testWidgets(
      'accessory catalog error degrades safely malformed=$malformed',
      (tester) async {
        await render(
          tester,
          _Api()
            ..fail = !malformed
            ..malformed = malformed,
        );
        expect(find.byKey(const Key('shop-accessories-error')), findsOneWidget);
        expect(find.byKey(Key('shop-accessory-${hat['id']}')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('accessory loading waits for real catalog and recovers', (
    tester,
  ) async {
    final api = _Api()..catalogGate = Completer<Map<String, dynamic>>();
    await render(tester, api);
    expect(find.byKey(const Key('shop-accessories-loading')), findsOneWidget);
    final pending = api.catalogGate!;
    api.catalogGate = null;
    pending.complete(await api.fetchShopCatalog(identityToken: 'session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('shop-accessories-loading')), findsNothing);
    expect(find.byKey(Key('shop-accessory-${hat['id']}')), findsOneWidget);
  });
  testWidgets('late accessory catalog cannot repaint a replacement account', (
    tester,
  ) async {
    final api = _Api()..catalogGate = Completer<Map<String, dynamic>>();
    final auth = await render(tester, api);
    final oldRead = api.catalogGate!;
    api.catalogGate = null;
    final oldCatalog = await api.fetchShopCatalog(identityToken: 'session');
    api.empty = true;
    await auth.syncFromBackendUser({
      'id': 'other-user',
      'coins': 500,
    }, authoritative: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    oldRead.complete(oldCatalog);
    await tester.pump();
    expect(find.byKey(Key('shop-accessory-${hat['id']}')), findsNothing);
    expect(find.text('No accessories for sale right now.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'art sizing changes preserve matching card geometry and readable labels',
    (tester) async {
      await render(tester, _Api(), scale: 1.6);
      final power = find.byKey(const Key('shop-product-card')).first;
      final character = find.byKey(const Key('shop-character-default'));
      expect(tester.getSize(power), tester.getSize(character));
      final scale = tester.widget<Transform>(
        find.descendant(
          of: power,
          matching: find.byKey(const Key('shop-tile-art-scale')),
        ),
      );
      expect(scale.transform.entry(0, 0), closeTo(.8, .001));
      final characterScale = tester.widget<Transform>(
        find.descendant(
          of: character,
          matching: find.byKey(const Key('shop-character-art-scale')),
        ),
      );
      expect(characterScale.transform.getMaxScaleOnAxis(), closeTo(1.1, .001));
      expect(
        find.descendant(of: character, matching: find.byType(RacerAvatar)),
        findsOneWidget,
      );
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
