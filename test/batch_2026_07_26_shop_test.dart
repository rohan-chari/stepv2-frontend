import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

/// Batch 2026-07-26 — shop items 1 (one filter/sort dropdown), 2 (price always
/// visible), 6 (synthetic Capybara inventory tile) and 7 (the "weird rectangle"
/// under the tile art).
class _FakeShopApi extends BackendApiService {
  _FakeShopApi({
    required this.powerupCatalog,
    this.cosmetics = const [],
    this.equippedCharacterId,
    this.coins = 1000,
  });

  final Map<String, dynamic> powerupCatalog;
  final List<Map<String, dynamic>> cosmetics;
  final String? equippedCharacterId;
  final int coins;

  final List<({String slot, String? itemId})> equipCalls = [];

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    return {
      'coins': coins,
      'ownedItemIds': <String>[],
      'equipped': <String, dynamic>{'CHARACTER': equippedCharacterId},
      'items': cosmetics,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => powerupCatalog;

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => {'items': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> equipAccessory({
    required String identityToken,
    required String slot,
    required String? itemId,
  }) async {
    equipCalls.add((slot: slot, itemId: itemId));
    return <String, dynamic>{};
  }
}

Future<AuthService> _auth({int coins = 1000}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'auth_coins': coins,
    'auth_held_coins': 0,
  });
  final service = AuthService();
  await service.restoreSession();
  return service;
}

Map<String, dynamic> _powerupCatalog() => {
  'coins': 1000,
  'items': [
    {
      'sku': 'PW_ZAP',
      'name': 'Zap',
      'description': 'Hit a rival',
      'priceCoins': 10,
      'powerupType': 'LEG_CRAMP',
      'category': 'offense',
      'rarity': 'COMMON',
    },
    {
      'sku': 'PW_GUARD',
      'name': 'Guard',
      'description': 'Shield yourself',
      'priceCoins': 50,
      'powerupType': 'STEALTH_MODE',
      'category': 'defense',
      'rarity': 'EPIC',
    },
    {
      'sku': 'PW_ANCHOR',
      'name': 'Anchor',
      'description': 'Self buff',
      'priceCoins': 90,
      'powerupType': 'RUNNERS_HIGH',
      'category': 'utility',
      'rarity': 'RARE',
    },
  ],
};

Future<void> _pump(
  WidgetTester tester,
  BackendApiService api, {
  int coins = 1000,
  Size surface = const Size(360, 900),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = await _auth(coins: coins);
  await tester.pumpWidget(
    MaterialApp(home: ShopTab(authService: auth, backendApiService: api)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openFilterSortSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shop-filter-sort-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PowerupCopy.resetForTest());

  group('item 1 — one dropdown replaces the filter pills and the sort pill', () {
    testWidgets('the collapsed control shows the active filter and sort', (
      tester,
    ) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));

      final label = tester.widget<Text>(
        find.byKey(const Key('shop-filter-sort-label')),
      );
      expect(label.data, 'All · Name A–Z');
      // Never allowed to overflow — the reason the old sort pill was replaced.
      expect(label.maxLines, 1);
      expect(label.overflow, TextOverflow.ellipsis);
    });

    testWidgets('the sheet carries both labelled groups', (tester) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      await _openFilterSortSheet(tester);

      expect(find.text('FILTER'), findsOneWidget);
      expect(find.text('SORT'), findsOneWidget);
      for (final option in ['All', 'Offense', 'Defense', 'Utility']) {
        expect(find.byKey(Key('shop-filter-option-$option')), findsOneWidget);
      }
      // The Rarity sort was removed separately from this batch; the sheet now
      // carries the three surviving orders.
      for (final option in ['Name A–Z', 'Price ↑', 'Price ↓']) {
        expect(find.byKey(Key('shop-sort-option-$option')), findsOneWidget);
      }
    });

    testWidgets('picking Offense filters the grid — semantics unchanged', (
      tester,
    ) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      await _openFilterSortSheet(tester);
      await tester.tap(find.byKey(const Key('shop-filter-option-Offense')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Zap'), findsOneWidget);
      expect(find.text('Guard'), findsNothing);
      expect(find.text('Anchor'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('shop-filter-sort-label')))
            .data,
        'Offense · Name A–Z',
      );
    });

    testWidgets('picking Price ↑ reorders — semantics unchanged', (
      tester,
    ) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      // Alphabetical default: Anchor left of Zap in the grid.
      expect(
        tester.getTopLeft(find.text('Anchor')).dx <
            tester.getTopLeft(find.text('Zap')).dx,
        isTrue,
      );

      await _openFilterSortSheet(tester);
      await tester.tap(find.byKey(const Key('shop-sort-option-Price ↑')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester
            .widget<Text>(find.byKey(const Key('shop-filter-sort-label')))
            .data,
        'All · Price ↑',
      );
      expect(
        tester.getTopLeft(find.text('Zap')).dx <
            tester.getTopLeft(find.text('Anchor')).dx,
        isTrue,
      );
    });

    testWidgets('the control fits a 320dp phone without overflowing', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeShopApi(powerupCatalog: _powerupCatalog()),
        surface: const Size(320, 900),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('shop-filter-sort-button')), findsOneWidget);
    });
  });

  group('item 2 — the price is always on the tile', () {
    testWidgets('an unaffordable powerup shows BOTH the price and the CTA', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeShopApi(powerupCatalog: _powerupCatalog(), coins: 0),
        coins: 0,
      );

      // The strip keeps its call to action — which is exactly what used to
      // REPLACE the price (watch-ads when the shortfall is small enough,
      // get-coins otherwise).
      final strips = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(
        strips.any((s) => s.startsWith('Watch ') || s == 'Get coins'),
        isTrue,
        reason: 'the unaffordable tile still shows its CTA',
      );
      // …and the price is still readable, from the art area's badge.
      final badges = tester
          .widgetList<Text>(find.byKey(const Key('shop-price-badge-text')))
          .map((t) => t.data)
          .toList();
      expect(badges, containsAll(<String>['10', '50', '90']));
    });

    testWidgets('an affordable tile prints the price exactly once', (
      tester,
    ) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      // The strip already carries the number when you can afford it, so the
      // art badge stands down — the tile never shows the same price twice.
      expect(find.byKey(const Key('shop-price-badge-text')), findsNothing);
      for (final price in ['10', '50', '90']) {
        expect(find.text(price), findsOneWidget);
      }
    });
  });

  group('item 6 — a Capybara tile always exists in Inventory → CHARACTERS', () {
    Future<void> openCharacterInventory(WidgetTester tester) async {
      await tester.tap(find.text('INVENTORY'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('CHARACTERS'));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('it is present even with no owned characters', (tester) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      await openCharacterInventory(tester);
      expect(find.text('Capybara'), findsOneWidget);
    });

    testWidgets('it reads EQUIPPED when no character is equipped', (
      tester,
    ) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      await openCharacterInventory(tester);
      expect(find.byKey(const Key('shop-capybara-tile')), findsOneWidget);
      expect(find.text('EQUIPPED'), findsWidgets);
      expect(find.text('CLEAR'), findsNothing);
    });

    testWidgets('tapping EQUIP clears the CHARACTER slot', (tester) async {
      final api = _FakeShopApi(
        powerupCatalog: _powerupCatalog(),
        equippedCharacterId: 'item-corgi',
        cosmetics: [
          {
            'id': 'item-corgi',
            'name': 'Corgi Puppy',
            'slot': 'CHARACTER',
            'assetKey': 'corgi_puppy',
            'owned': true,
            'equipped': true,
            'priceCoins': 300,
            'description': 'Zoom',
          },
        ],
      );
      await _pump(tester, api);
      await openCharacterInventory(tester);

      expect(find.text('Capybara'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('shop-capybara-tile')),
          matching: find.text('EQUIP'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.equipCalls, hasLength(1));
      expect(api.equipCalls.single.slot, 'CHARACTER');
      expect(api.equipCalls.single.itemId, isNull);
    });
  });

  group('item 7 — the art area is one intentional frame, not a stray fill', () {
    testWidgets('the tile clip matches the container radius', (tester) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      final clip = tester.widget<ClipRRect>(
        find.byKey(const Key('shop-tile-clip')).first,
      );
      expect(clip.borderRadius, BorderRadius.circular(14));
    });

    testWidgets('the art box is a solid token fill with a hairline edge', (
      tester,
    ) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      final box = tester.widget<Container>(
        find.byKey(const Key('shop-tile-art-box')).first,
      );
      final decoration = box.decoration as BoxDecoration;
      final palette = AppColors.of(
        tester.element(find.byKey(const Key('shop-tile-art-box')).first),
      );
      // Solid token fill — no 0.6-alpha overlay reading as a stray rectangle.
      expect(decoration.color, palette.parchmentDark);
      expect(decoration.color!.a, 1.0);
      // A defined bottom edge separates the art from the name band.
      expect(decoration.border, isNotNull);
    });

    testWidgets('the loading skeleton name band matches the real tile (38)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await _auth();
      // A never-completing catalog keeps the skeleton on screen.
      await tester.pumpWidget(
        MaterialApp(
          home: ShopTab(
            authService: auth,
            backendApiService: _StalledApi(),
          ),
        ),
      );
      await tester.pump();

      final band = tester.widget<Container>(
        find.byKey(const Key('shop-skeleton-name-band')).first,
      );
      expect(band.constraints?.maxHeight, 38);
    });
  });
}

class _StalledApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) {
    return Future.any([]);
  }
}
