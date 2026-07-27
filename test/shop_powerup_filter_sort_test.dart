import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Item 9 — powerup store category pills + sort-by.
class _FakeShopApi extends BackendApiService {
  _FakeShopApi({required this.powerupCatalog});

  final Map<String, dynamic> powerupCatalog;

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    return {
      'coins': 1000,
      'ownedItemIds': <String>[],
      'equipped': <String, dynamic>{},
      'items': <Map<String, dynamic>>[],
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
}

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
  final service = AuthService();
  await service.restoreSession();
  return service;
}

/// Mixed categories + one item with NO category (must default to utility).
Map<String, dynamic> _catalog() => {
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
    {
      // No category → defaults to utility (older backend compat).
      'sku': 'PW_MYSTERY',
      'name': 'Mystery',
      'description': 'Unknown',
      'priceCoins': 30,
      'powerupType': 'COIN_FLIP',
      'rarity': 'LEGENDARY',
    },
  ],
};

Future<void> _pump(WidgetTester tester, BackendApiService api) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(home: ShopTab(authService: auth, backendApiService: api)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

/// Batch 2026-07-26 item 1: the four ALL/OFFENSE/DEFENSE/UTILITY pills and the
/// separate `Sort: …` PopupMenuButton were replaced by ONE control that opens a
/// sheet with labelled FILTER and SORT groups. The filter/sort *semantics* did
/// not change, so every property this file guarded still holds — it is only the
/// interaction that moved. Updated in place rather than deleted.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shop-filter-sort-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _choose(WidgetTester tester, Key option) async {
  await _openSheet(tester);
  await tester.tap(find.byKey(option), warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The grid is a single 4-column row for these fixtures, so left-to-right x
/// position is the render order (same assumption the pill-era tests made).
void _expectOrder(WidgetTester tester, String left, String right) {
  expect(
    tester.getTopLeft(find.text(left)).dx <
        tester.getTopLeft(find.text(right)).dx,
    isTrue,
    reason: '$left should render before $right',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PowerupCopy.resetForTest());

  testWidgets('one filter/sort control renders with the default summary', (
    tester,
  ) async {
    await _pump(tester, _FakeShopApi(powerupCatalog: _catalog()));

    // The single control replaces the four pills + the sort pill.
    expect(find.byKey(const Key('shop-filter-sort-button')), findsOneWidget);
    expect(find.text('All · Name A–Z'), findsOneWidget);

    // The SHOUTING pill labels are gone from the shop chrome.
    expect(find.text('OFFENSE'), findsNothing);
    expect(find.text('DEFENSE'), findsNothing);
    expect(find.text('Sort: Name (A–Z)'), findsNothing);

    // All four items visible under the default All filter.
    expect(find.text('Zap'), findsOneWidget);
    expect(find.text('Guard'), findsOneWidget);
    expect(find.text('Anchor'), findsOneWidget);
    expect(find.text('Mystery'), findsOneWidget);
  });

  testWidgets('the sheet exposes both FILTER and SORT groups', (tester) async {
    await _pump(tester, _FakeShopApi(powerupCatalog: _catalog()));
    await _openSheet(tester);

    expect(find.text('FILTER'), findsOneWidget);
    expect(find.text('SORT'), findsOneWidget);
    for (final f in ['All', 'Offense', 'Defense', 'Utility']) {
      expect(find.byKey(Key('shop-filter-option-$f')), findsOneWidget);
    }
    for (final s in ['Name A–Z', 'Price ↑', 'Price ↓']) {
      expect(find.byKey(Key('shop-sort-option-$s')), findsOneWidget);
    }
  });

  testWidgets('choosing Offense shows only offense items', (tester) async {
    await _pump(tester, _FakeShopApi(powerupCatalog: _catalog()));
    await _choose(tester, const Key('shop-filter-option-Offense'));

    expect(find.text('Zap'), findsOneWidget); // offense
    expect(find.text('Guard'), findsNothing); // defense filtered out
    expect(find.text('Anchor'), findsNothing); // utility filtered out
    expect(find.text('Mystery'), findsNothing);
    // The collapsed summary reflects the active state.
    expect(find.text('Offense · Name A–Z'), findsOneWidget);
  });

  testWidgets('a category-less item falls into Utility', (tester) async {
    await _pump(tester, _FakeShopApi(powerupCatalog: _catalog()));
    await _choose(tester, const Key('shop-filter-option-Utility'));

    expect(find.text('Anchor'), findsOneWidget); // explicit utility
    expect(find.text('Mystery'), findsOneWidget); // defaulted utility
    expect(find.text('Zap'), findsNothing);
    expect(find.text('Guard'), findsNothing);
  });

  testWidgets('default order is alphabetical; Price ↑ reorders', (
    tester,
  ) async {
    await _pump(tester, _FakeShopApi(powerupCatalog: _catalog()));
    _expectOrder(tester, 'Anchor', 'Zap'); // alphabetical default

    await _choose(tester, const Key('shop-sort-option-Price ↑'));

    expect(find.text('All · Price ↑'), findsOneWidget);
    _expectOrder(tester, 'Zap', 'Anchor'); // Zap (10) now above Anchor (90)
  });

  testWidgets('filter and sort compose', (tester) async {
    await _pump(tester, _FakeShopApi(powerupCatalog: _catalog()));
    await _choose(tester, const Key('shop-filter-option-Utility'));
    await _choose(tester, const Key('shop-sort-option-Price ↑'));

    expect(find.text('Utility · Price ↑'), findsOneWidget);
    expect(find.text('Zap'), findsNothing); // filter still applied
    expect(find.text('Guard'), findsNothing);
    _expectOrder(tester, 'Mystery', 'Anchor'); // Mystery (20) before Anchor (90)
  });
}
