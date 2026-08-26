import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Item 10 — the "watch ads to unlock" affordance vs the +coins route,
/// driven entirely by the coin shortfall against a single 150/300-coin tile.
class _FakeShopApi extends BackendApiService {
  _FakeShopApi({
    required this.coins,
    required this.price,
    this.includeAdUnlock = false,
  });

  final int coins;
  final int price;
  final bool includeAdUnlock;
  int unlockCalls = 0;
  final List<String?> unlockDates = [];

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    // _loadCatalog syncs the auth balance from here, so this is the coin
    // value the tile reads.
    return {
      'coins': coins,
      'ownedItemIds': <String>[],
      'equipped': <String, dynamic>{},
      'items': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {
    'coins': coins,
    'items': [
      {
        'sku': 'PW_SHORT',
        'name': 'Big Bang',
        'description': 'Pricey powerup',
        'priceCoins': price,
        'powerupType': 'RED_CARD',
        'category': 'offense',
      },
    ],
    if (includeAdUnlock)
      'adUnlock': {
        'maxShortfall': 150,
        'coinsPerAd': 50,
        'maxAds': 3,
        'remainingToday': 1,
      },
  };

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => {'items': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> unlockPowerupWithAds({
    required String identityToken,
    required String sku,
    required String idempotencyKey,
    String? localDate,
  }) async {
    unlockCalls++;
    unlockDates.add(localDate);
    return {
      'coins': 0,
      'powerup': {'powerupType': 'RED_CARD', 'quantity': 1},
    };
  }
}

class _FakeShopAdController implements ExtraSpinAdController {
  bool ready = false;
  int loadCalls = 0;
  int showCalls = 0;
  int disposeCalls = 0;
  Completer<bool>? showCompleter;
  String? lastUserId;
  String? lastCustomData;

  @override
  bool get isReady => ready;

  @override
  bool get isSupported => true;

  @override
  Future<void> load({required String userId, required String localDate}) async {
    loadCalls++;
    lastUserId = userId;
    lastCustomData = localDate;
    ready = true;
  }

  @override
  Future<bool> showAndAwaitReward() async {
    showCalls++;
    ready = false;
    return showCompleter?.future ?? true;
  }

  @override
  void dispose() => disposeCalls++;
}

Future<AuthService> _pump(
  WidgetTester tester, {
  required int coins,
  required int price,
  _FakeShopApi? api,
  _FakeShopAdController? ads,
  ExtraSpinAdController Function()? adControllerBuilder,
  DateTime Function()? now,
}) async {
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
  await tester.pumpWidget(
    MaterialApp(
      home: ShopTab(
        authService: auth,
        backendApiService: api ?? _FakeShopApi(coins: coins, price: price),
        adControllerBuilder:
            adControllerBuilder ?? (ads == null ? null : () => ads),
        now: now,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  // Unlock affordances live in the item sheet; the grid intentionally keeps
  // only the compact price strip.
  await tester.tap(find.text('Big Bang'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PowerupCopy.resetForTest());

  testWidgets('shortfall 120 → "Watch 3 ads"', (tester) async {
    await _pump(tester, coins: 30, price: 150);
    expect(find.text('WATCH 3 ADS TO UNLOCK'), findsOneWidget);
    expect(find.text('GET MORE COINS'), findsNothing);
  });

  testWidgets('shortfall 40 → "Watch 1 ad"', (tester) async {
    await _pump(tester, coins: 110, price: 150);
    expect(find.text('WATCH 1 AD TO UNLOCK'), findsOneWidget);
  });

  testWidgets('shortfall 300 (>150) → "Get coins" route', (tester) async {
    await _pump(tester, coins: 0, price: 300);
    expect(find.text('GET MORE COINS'), findsOneWidget);
    expect(find.textContaining('Watch'), findsNothing);
  });

  testWidgets('affordable → plain price strip, no ad affordance', (
    tester,
  ) async {
    await _pump(tester, coins: 1000, price: 150);
    expect(find.text('150'), findsWidgets);
    expect(find.textContaining('Watch'), findsNothing);
    expect(find.text('GET MORE COINS'), findsNothing);
  });

  testWidgets(
    'valid server adUnlock warms the exact powerup SKU in its sheet',
    (tester) async {
      final ads = _FakeShopAdController();
      final api = _FakeShopApi(coins: 110, price: 150, includeAdUnlock: true);

      await _pump(tester, coins: 110, price: 150, api: api, ads: ads);

      expect(ads.loadCalls, 1);
      expect(ads.lastUserId, 'user-1');
      expect(ads.lastCustomData, 'powerup_unlock:user-1:PW_SHORT');
    },
  );

  testWidgets(
    'older backend keeps legacy action, skips speculation, and loads on tap',
    (tester) async {
      final ads = _FakeShopAdController();
      final api = _FakeShopApi(coins: 110, price: 150);

      await _pump(tester, coins: 110, price: 150, api: api, ads: ads);
      expect(find.text('WATCH 1 AD TO UNLOCK'), findsOneWidget);
      expect(ads.loadCalls, 0);

      await tester.tap(find.text('WATCH 1 AD TO UNLOCK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(ads.loadCalls, 1);
      expect(ads.showCalls, 1);
      expect(api.unlockCalls, 1);
    },
  );

  testWidgets('multi-ad handoff warms N+1 while N is fullscreen and aborts', (
    tester,
  ) async {
    final first = _FakeShopAdController()..showCompleter = Completer<bool>();
    final second = _FakeShopAdController();
    final controllers = <_FakeShopAdController>[first, second];
    var built = 0;
    final api = _FakeShopApi(coins: 30, price: 150, includeAdUnlock: true);

    await _pump(
      tester,
      coins: 30,
      price: 150,
      api: api,
      adControllerBuilder: () => controllers[built++],
    );
    expect(first.loadCalls, 1, reason: 'N is the sheet warmup');

    await tester.tap(find.text('WATCH 3 ADS TO UNLOCK'));
    await tester.pump();

    expect(first.showCalls, 1);
    expect(second.loadCalls, 1, reason: 'N+1 warms during N fullscreen');
    first.showCompleter!.complete(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(second.disposeCalls, 1);
    expect(api.unlockCalls, 0);
  });

  testWidgets('account switch disposes active handoff and blocks mutation', (
    tester,
  ) async {
    final first = _FakeShopAdController()..showCompleter = Completer<bool>();
    final second = _FakeShopAdController();
    final controllers = <_FakeShopAdController>[first, second];
    var built = 0;
    final api = _FakeShopApi(coins: 30, price: 150, includeAdUnlock: true);
    final auth = await _pump(
      tester,
      coins: 30,
      price: 150,
      api: api,
      adControllerBuilder: () => controllers[built++],
    );

    await tester.tap(find.text('WATCH 3 ADS TO UNLOCK'));
    await tester.pump();
    await auth.updateSessionToken('new-session');
    await auth.syncFromBackendUser(const {'id': 'user-2'});
    await tester.pump();

    expect(first.disposeCalls, 1);
    expect(second.disposeCalls, 1);
    first.showCompleter!.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.unlockCalls, 0);
  });

  testWidgets('one-ad account switch cannot mutate the new session', (
    tester,
  ) async {
    final ad = _FakeShopAdController()..showCompleter = Completer<bool>();
    final api = _FakeShopApi(coins: 30, price: 70, includeAdUnlock: true);
    final auth = await _pump(tester, coins: 30, price: 70, api: api, ads: ad);

    await tester.tap(find.text('WATCH 1 AD TO UNLOCK'));
    await tester.pump();
    await auth.updateSessionToken('new-session');
    await auth.syncFromBackendUser(const {'id': 'user-2'});
    ad.showCompleter!.complete(true);
    await tester.pump();

    expect(api.unlockCalls, 0);
  });

  testWidgets('route disposal cancels an active one-ad unlock', (tester) async {
    final ad = _FakeShopAdController()..showCompleter = Completer<bool>();
    final api = _FakeShopApi(coins: 30, price: 70, includeAdUnlock: true);
    await _pump(tester, coins: 30, price: 70, api: api, ads: ad);

    await tester.tap(find.text('WATCH 1 AD TO UNLOCK'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    ad.showCompleter!.complete(true);
    await tester.pump();

    expect(ad.disposeCalls, 1);
    expect(api.unlockCalls, 0);
  });

  testWidgets('unlock posts the date bound before midnight', (tester) async {
    var now = DateTime(2026, 8, 25, 23, 59);
    final ad = _FakeShopAdController()..showCompleter = Completer<bool>();
    final api = _FakeShopApi(coins: 30, price: 70, includeAdUnlock: true);
    await _pump(
      tester,
      coins: 30,
      price: 70,
      api: api,
      ads: ad,
      now: () => now,
    );

    await tester.tap(find.text('WATCH 1 AD TO UNLOCK'));
    await tester.pump();
    now = DateTime(2026, 8, 26, 0, 1);
    ad.showCompleter!.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.unlockCalls, 1);
    expect(api.unlockDates, const ['2026-08-25']);
  });
}
