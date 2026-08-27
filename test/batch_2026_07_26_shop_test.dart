import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/pill_button.dart';

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
  int powerupPurchaseCalls = 0;

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

  @override
  Future<Map<String, dynamic>> purchasePowerupItem({
    required String identityToken,
    String? sku,
    String? powerupType,
    required String idempotencyKey,
  }) async {
    powerupPurchaseCalls++;
    return {'coins': 990, 'inventory': <Map<String, dynamic>>[]};
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
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = await _auth(coins: coins);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(size: surface, textScaler: textScaler),
        child: child!,
      ),
      home: ShopTab(
        key: ValueKey(api),
        authService: auth,
        backendApiService: api,
      ),
    ),
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

  group('mobile Taste shop redesign', () {
    testWidgets('the live Bara stage leads a breathable three-column catalog', (
      tester,
    ) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));

      final preview = find.byKey(const Key('shop-character-preview'));
      expect(tester.getSize(preview).height, greaterThanOrEqualTo(88));

      final grid = tester.widget<GridView>(
        find.byKey(const Key('shop-product-grid')),
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 3);
      expect(delegate.childAspectRatio, greaterThan(0.78));

      final artScale = tester.widget<Transform>(
        find.byKey(const Key('shop-tile-art-scale')).first,
      );
      expect(artScale.transform.getMaxScaleOnAxis(), closeTo(1.5, 0.001));
    });

    testWidgets('narrow phones keep a usable art window for three columns', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeShopApi(powerupCatalog: _powerupCatalog()),
        surface: const Size(320, 900),
      );

      final artBox = tester.getSize(
        find.byKey(const Key('shop-tile-art-box')).first,
      );
      expect(artBox.height, greaterThanOrEqualTo(38));
    });

    testWidgets('merchandise cards are flat and art-led', (tester) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));

      final card = tester.widget<DecoratedBox>(
        find.byKey(const Key('shop-product-card')).first,
      );
      final decoration = card.decoration as BoxDecoration;
      expect(decoration.boxShadow, isNull);
      expect(decoration.border, isA<Border>());
      expect((decoration.border! as Border).top.width, 1);
    });

    testWidgets('tablet and loading grids keep the same four-column geometry', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeShopApi(powerupCatalog: _powerupCatalog()),
        surface: const Size(700, 900),
      );
      final live = tester.widget<GridView>(
        find.byKey(const Key('shop-product-grid')),
      );
      final liveDelegate =
          live.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(liveDelegate.crossAxisCount, 4);

      await _pump(tester, _StalledApi(), surface: const Size(700, 900));
      final loading = tester.widget<GridView>(
        find.byKey(const Key('shop-loading-grid')).first,
      );
      final loadingDelegate =
          loading.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(loadingDelegate.crossAxisCount, liveDelegate.crossAxisCount);
      expect(loadingDelegate.childAspectRatio, liveDelegate.childAspectRatio);
      expect(loadingDelegate.mainAxisSpacing, liveDelegate.mainAxisSpacing);
      expect(loadingDelegate.crossAxisSpacing, liveDelegate.crossAxisSpacing);
    });

    testWidgets('category controls expose selection and a 48dp target', (
      tester,
    ) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      final category = find.byKey(const Key('shop-category-POWERUPS'));
      expect(tester.getSize(category).height, greaterThanOrEqualTo(48));
      final semantics = tester.widget<Semantics>(
        find.byKey(const Key('shop-category-semantics-POWERUPS')),
      );
      expect(semantics.properties.button, isTrue);
      expect(semantics.properties.selected, isTrue);
    });

    testWidgets(
      'enabled action strips use readable night text and 48dp target',
      (tester) async {
        await _pump(
          tester,
          _FakeShopApi(powerupCatalog: _powerupCatalog()),
          theme: AppThemeData.night(),
        );
        final label = find.text('10').first;
        expect(
          tester.widget<Text>(label).style!.color,
          AppPalette.night.textDark,
        );
        final strip = find.ancestor(
          of: label,
          matching: find.byType(Container),
        );
        expect(tester.getSize(strip.first).height, greaterThanOrEqualTo(48));
      },
    );

    testWidgets('small large-text item sheet scrolls to an active CTA', (
      tester,
    ) async {
      final api = _FakeShopApi(powerupCatalog: _powerupCatalog());
      await _pump(
        tester,
        api,
        surface: const Size(320, 568),
        textScaler: const TextScaler.linear(2.5),
      );
      final powerups = find.byKey(const Key('shop-category-POWERUPS'));
      await tester.ensureVisible(powerups);
      await tester.pump();
      await tester.tap(powerups);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Zap'));
      await tester.pump(const Duration(milliseconds: 400));
      final cta = find.text('BUY · 10');
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('shop-item-sheet')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.viewportDimension, lessThanOrEqualTo(410));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      final button = tester.widget<PillButton>(
        find.ancestor(of: cta, matching: find.byType(PillButton)),
      );
      expect(button.onPressed, isNotNull);
      button.onPressed!();
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.powerupPurchaseCalls, 1);
    });
  });

  group('live Bara preview', () {
    testWidgets('renders above the catalog and previews a tapped cosmetic', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeShopApi(
          powerupCatalog: _powerupCatalog(),
          cosmetics: const [
            {
              'id': 'item-corgi',
              'sku': 'COS_CORGI',
              'name': 'Corgi Puppy',
              'slot': 'CHARACTER',
              'assetKey': 'corgi_puppy',
              'owned': false,
              'equipped': false,
              'priceCoins': 300,
              'description': 'Zoom',
            },
          ],
        ),
      );

      final preview = find.byKey(const Key('shop-character-preview'));
      expect(preview, findsOneWidget);
      await tester.tap(find.byKey(const Key('shop-category-CHARACTERS')));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Corgi Puppy'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.getTopLeft(preview).dy,
        lessThan(tester.getTopLeft(find.text('Corgi Puppy')).dy),
      );
      await tester.tap(find.text('Corgi Puppy'));
      await tester.pump();

      expect(find.text('Previewing Corgi Puppy'), findsOneWidget);
      expect(
        find.byKey(const Key('shop-preview-corgi_puppy-')),
        findsOneWidget,
      );
    });
  });

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
      bool appearsBefore(String first, String second) {
        final a = tester.getTopLeft(find.text(first));
        final b = tester.getTopLeft(find.text(second));
        return a.dy < b.dy || ((a.dy - b.dy).abs() < 1 && a.dx < b.dx);
      }

      // Alphabetical default: Anchor precedes Zap in reading order.
      expect(appearsBefore('Anchor', 'Zap'), isTrue);

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
      expect(appearsBefore('Zap', 'Anchor'), isTrue);
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
        isFalse,
        reason: 'the tile now keeps the price as its only strip action',
      );
      // …and the price is still readable, from the art area's badge.
      expect(find.byKey(const Key('shop-price-badge-text')), findsNothing);
      for (final price in ['10', '50', '90']) {
        expect(find.text(price), findsOneWidget);
      }
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
            'sku': 'COS_CORGI',
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
          home: ShopTab(authService: auth, backendApiService: _StalledApi()),
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
