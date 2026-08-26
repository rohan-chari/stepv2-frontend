import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

// Spec §6 (dark-mode owned pill), §7 (server-served ad-unlock rules) and §8
// (shop type scale) — all three live on the shop tab, so they share a harness
// that pumps the REAL ShopTab against a fake catalog.

class _FakeShopApi extends BackendApiService {
  _FakeShopApi({
    required this.coins,
    required this.price,
    this.adUnlock,
    this.ownedQuantity = 0,
    this.powerupName = 'Big Bang',
    this.cosmetics = const [],
  });

  final int coins;
  final int price;
  final Map<String, dynamic>? adUnlock;
  final int ownedQuantity;
  final String powerupName;
  final List<Map<String, dynamic>> cosmetics;

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => {
    'coins': coins,
    'ownedItemIds': <String>[],
    'equipped': <String, dynamic>{},
    'items': cosmetics,
    if (adUnlock != null) 'adUnlock': adUnlock,
  };

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {
    'coins': coins,
    if (adUnlock != null) 'adUnlock': adUnlock,
    'items': [
      {
        'sku': 'PW_SHORT',
        'name': powerupName,
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
  }) async => {
    'items': [
      if (ownedQuantity > 0)
        {'powerupType': 'RED_CARD', 'quantity': ownedQuantity},
    ],
  };

  @override
  Future<Map<String, dynamic>> unlockShopItemWithAds({
    required String identityToken,
    required String sku,
    required String idempotencyKey,
    String? localDate,
  }) async {
    return {'coins': 0, 'adsWatched': 1, 'owned': true};
  }
}

Future<AuthService> _auth(int coins) async {
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
  return auth;
}

Future<void> _pump(
  WidgetTester tester, {
  required int coins,
  required int price,
  Map<String, dynamic>? adUnlock,
  int ownedQuantity = 0,
  String powerupName = 'Big Bang',
  List<Map<String, dynamic>> cosmetics = const [],
  ThemeData? theme,
}) async {
  final auth = await _auth(coins);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppThemeData.light(),
      home: ShopTab(
        // A fresh key per pump: without it Flutter reuses the previous
        // ShopTab's State and never reloads the fake catalog.
        key: UniqueKey(),
        authService: auth,
        backendApiService: _FakeShopApi(
          coins: coins,
          price: price,
          adUnlock: adUnlock,
          ownedQuantity: ownedQuantity,
          powerupName: powerupName,
          cosmetics: cosmetics,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

TextStyle _styleOf(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label).first).style!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PowerupCopy.resetForTest());

  // ── §6 / test 14 — the owned-count pill ────────────────────────────────
  //
  // `parchment` is a SURFACE token: cream by day, near-black navy at night.
  // Used as the badge's TEXT color it painted near-black on the dark-green
  // `roofMid` pill. The badge must resolve to the cream `textLight` token in
  // BOTH palettes so the night flip can never silently regress.
  group('§6 owned-count badge', () {
    testWidgets('is cream in the DAY palette', (tester) async {
      await _pump(
        tester,
        coins: 1000,
        price: 150,
        ownedQuantity: 2,
        theme: AppThemeData.light(),
      );
      expect(_styleOf(tester, 'x2').color, AppPalette.light.textLight);
    });

    testWidgets('is cream in the NIGHT palette, not the near-black surface', (
      tester,
    ) async {
      await _pump(
        tester,
        coins: 1000,
        price: 150,
        ownedQuantity: 2,
        theme: AppThemeData.night(),
      );
      final color = _styleOf(tester, 'x2').color;
      expect(color, AppPalette.night.textLight);
      expect(color, isNot(AppPalette.night.parchment));
    });
  });

  // ── §8 / test 16 — type scale ──────────────────────────────────────────
  group('§8 shop type scale', () {
    testWidgets('badge, name and action strip are raised', (tester) async {
      await _pump(tester, coins: 1000, price: 150, ownedQuantity: 2);
      expect(_styleOf(tester, 'x2').fontSize, 10);
      expect(_styleOf(tester, 'Big Bang').fontSize, 13);
      expect(_styleOf(tester, '150').fontSize, 13);
    });

    // The phone grid is two tiles wide, giving merchandise room to breathe.
    // The name still steps down from 13pt only as far as it must — long
    // two-word names must still render whole, never ellipsised.
    testWidgets('long names render un-ellipsised at 320dp and 360dp wide', (
      tester,
    ) async {
      for (final width in const [320.0, 360.0]) {
        tester.view.physicalSize = Size(width * 3, 720 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        for (final name in const ['Signal Jammer', 'Ghost Pepper']) {
          await _pump(tester, coins: 1000, price: 150, powerupName: name);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(name).first,
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '"$name" ellipsised inside the tile name box at ${width}dp',
          );
        }
      }
    });

    testWidgets('a short name keeps the full 13pt', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await _pump(tester, coins: 1000, price: 150, powerupName: 'Leech');
      expect(_styleOf(tester, 'Leech').fontSize, 13);
    });

    testWidgets('sheet chip and description are raised', (tester) async {
      await _pump(tester, coins: 1000, price: 150, ownedQuantity: 2);
      await tester.tap(find.text('Big Bang').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_styleOf(tester, 'OWNED x2').fontSize, 11);
      expect(_styleOf(tester, 'Pricey powerup').fontSize, 15);
    });
  });

  // ── §7 / test 15 — the ad-unlock rules come from the server ────────────
  group('§7 ad-unlock is driven by the catalog adUnlock block', () {
    testWidgets('adUnlock absent → today\'s 150-coin behaviour is preserved', (
      tester,
    ) async {
      await _pump(tester, coins: 30, price: 150);
      await tester.tap(find.text('Big Bang').first);
      await tester.pump();
      expect(find.text('WATCH 3 ADS TO UNLOCK'), findsOneWidget);
      expect(find.text('GET MORE COINS'), findsNothing);
    });

    testWidgets('maxShortfall 20 → a 90-short tile routes to Get coins', (
      tester,
    ) async {
      await _pump(
        tester,
        coins: 60,
        price: 150,
        adUnlock: {
          'maxShortfall': 20,
          'coinsPerAd': 50,
          'maxAds': 3,
          'dailyCap': 1,
          'remainingToday': 1,
        },
      );
      await tester.tap(find.text('Big Bang').first);
      await tester.pump();
      expect(find.text('GET MORE COINS'), findsOneWidget);
      expect(find.textContaining('Watch'), findsNothing);
    });

    testWidgets('maxShortfall 20 → a 15-short tile offers one ad', (
      tester,
    ) async {
      await _pump(
        tester,
        coins: 135,
        price: 150,
        adUnlock: {
          'maxShortfall': 20,
          'coinsPerAd': 50,
          'maxAds': 3,
          'dailyCap': 1,
          'remainingToday': 1,
        },
      );
      await tester.tap(find.text('Big Bang').first);
      await tester.pump();
      expect(find.text('WATCH 1 AD TO UNLOCK'), findsOneWidget);
    });

    testWidgets(
      'remainingToday 0 → the ad button is absent, fail before the ad',
      (tester) async {
        await _pump(
          tester,
          coins: 135,
          price: 150,
          adUnlock: {
            'maxShortfall': 20,
            'coinsPerAd': 50,
            'maxAds': 3,
            'dailyCap': 1,
            'remainingToday': 0,
          },
        );
        await tester.tap(find.text('Big Bang').first);
        await tester.pump();
        expect(find.textContaining('WATCH'), findsNothing);
        expect(find.text('GET MORE COINS'), findsOneWidget);

        // The sheet explains WHY, so a cap-reached tile doesn't read as
        // "this item is simply too expensive".
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text('You’ve used today’s ad unlock. Come back tomorrow.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a malformed adUnlock block falls back to the legacy rules', (
      tester,
    ) async {
      await _pump(
        tester,
        coins: 30,
        price: 150,
        adUnlock: {'maxShortfall': 'nonsense'},
      );
      await tester.tap(find.text('Big Bang').first);
      await tester.pump();
      expect(find.text('WATCH 3 ADS TO UNLOCK'), findsOneWidget);
    });

    testWidgets('cosmetics get the same ad-unlock affordance', (tester) async {
      await _pump(
        tester,
        coins: 385,
        price: 150,
        adUnlock: {
          'maxShortfall': 20,
          'coinsPerAd': 50,
          'maxAds': 3,
          'dailyCap': 1,
          'remainingToday': 1,
        },
        cosmetics: [
          {
            'id': 'c1',
            'sku': 'corgi_puppy',
            'name': 'Corgi Puppy',
            'slot': 'CHARACTER',
            'assetKey': 'corgi_puppy',
            'priceCoins': 400,
            'description': 'Zoomies!',
          },
        ],
      );
      // Switch to the accessories category so the cosmetic tile renders.
      await tester.tap(find.text('CHARACTERS').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Corgi Puppy').first);
      await tester.pump();
      expect(find.text('WATCH 1 AD TO UNLOCK'), findsOneWidget);
    });

    testWidgets('a cosmetic priced past maxShortfall routes to Get coins', (
      tester,
    ) async {
      await _pump(
        tester,
        coins: 0,
        price: 150,
        adUnlock: {
          'maxShortfall': 20,
          'coinsPerAd': 50,
          'maxAds': 3,
          'dailyCap': 1,
          'remainingToday': 1,
        },
        cosmetics: [
          {
            'id': 'c1',
            'sku': 'corgi_puppy',
            'name': 'Corgi Puppy',
            'slot': 'CHARACTER',
            'assetKey': 'corgi_puppy',
            'priceCoins': 400,
            'description': 'Zoomies!',
          },
        ],
      );
      await tester.tap(find.text('CHARACTERS').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Corgi Puppy').first);
      await tester.pump();
      expect(find.textContaining('Watch'), findsNothing);
      expect(find.text('GET MORE COINS'), findsOneWidget);
    });
  });
}
