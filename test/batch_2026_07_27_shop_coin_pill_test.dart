import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/coin_glyph.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/streak_chip.dart';

/// Batch 2026-07-27 — items 3 (paw coin, not a dollar sign), 4 (PillButton
/// silently ellipsizes), 22 (centre the EQUIPPED pill) and 23 (the price lives
/// in the strip, always).
class _FakeShopApi extends BackendApiService {
  _FakeShopApi({
    required this.powerupCatalog,
    this.cosmetics = const [],
    this.coins = 1000,
    this.powerupInventory = const [],
  });

  final Map<String, dynamic> powerupCatalog;
  final List<Map<String, dynamic>> cosmetics;
  final int coins;
  final List<Map<String, dynamic>> powerupInventory;

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    return {
      'coins': coins,
      'ownedItemIds': const <String>[],
      'equipped': const <String, dynamic>{'CHARACTER': null},
      'items': cosmetics,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {...powerupCatalog, 'coins': coins};

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => {'items': powerupInventory};

  @override
  Future<Map<String, dynamic>> equipAccessory({
    required String identityToken,
    required String slot,
    required String? itemId,
  }) async => <String, dynamic>{};
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

/// Prices 10 / 50 / 90. `adUnlock` is served by the backend, so the tests can
/// move the ceiling without the app hardcoding anything.
Map<String, dynamic> _powerupCatalog({Map<String, dynamic>? adUnlock}) => {
  'coins': 1000,
  'adUnlock': ?adUnlock,
  'items': [
    {
      'sku': 'PW_ZAP',
      'name': 'Zap',
      'description': 'Hit a rival',
      'priceCoins': 10,
      'powerupType': 'LEG_CRAMP',
      'category': 'offense',
    },
    {
      'sku': 'PW_GUARD',
      'name': 'Guard',
      'description': 'Shield yourself',
      'priceCoins': 50,
      'powerupType': 'STEALTH_MODE',
      'category': 'defense',
    },
    {
      'sku': 'PW_ANCHOR',
      'name': 'Anchor',
      'description': 'Self buff',
      'priceCoins': 90,
      'powerupType': 'RUNNERS_HIGH',
      'category': 'utility',
    },
  ],
};

List<Map<String, dynamic>> _cosmetics({bool equipped = false}) => [
  {
    'id': 'cos-1',
    'sku': 'COS_HAT',
    'name': 'Top Hat',
    'description': 'A very tall hat',
    'priceCoins': 60,
    'slot': 'HEAD',
    'assetKey': 'cowboy_hat',
    'equipped': equipped,
  },
];

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
    MaterialApp(
      home: ShopTab(authService: auth, backendApiService: api),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openInventoryCharacters(WidgetTester tester) async {
  await tester.tap(find.text('INVENTORY'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('CHARACTERS'));
  await tester.pump(const Duration(milliseconds: 300));
}

/// True when the laid-out label was clipped by `maxLines: 1` — i.e. the user
/// clips a value-forward ticket label instead of scaling it to fit.
bool _truncated(WidgetTester tester, String label) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.text(label, skipOffstage: false),
  );
  return paragraph.didExceedMaxLines;
}

/// The home tab's quick-actions row: two half-width `Expanded`s inside 16pt
/// page padding, separated by a 10pt gap.
Widget _halfWidthRow(Widget left, Widget right) => MaterialApp(
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
      ),
    ),
  ),
);

class _FakeExtraSpinAds implements ExtraSpinAdController {
  @override
  bool get isSupported => true;
  @override
  bool get isReady => true;
  @override
  Future<void> load({
    required String userId,
    required String localDate,
  }) async {}
  @override
  Future<bool> showAndAwaitReward() async => true;
  @override
  void dispose() {}
}

String _today() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PowerupCopy.resetForTest());

  group('item 3 — the coin glyph is the paw coin, never a dollar sign', () {
    testWidgets('no dollar-sign icon renders anywhere on the shop tab', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeShopApi(
          powerupCatalog: _powerupCatalog(),
          cosmetics: _cosmetics(),
        ),
      );
      expect(find.byIcon(Icons.monetization_on_rounded), findsNothing);
    });

    testWidgets('the price strip carries a CoinGlyph', (tester) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      expect(find.byType(CoinGlyph), findsWidgets);
    });

    testWidgets('the sheet BUY button carries a CoinGlyph, not a dollar icon', (
      tester,
    ) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      await tester.tap(find.text('Zap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('BUY · 10'), findsOneWidget);
      expect(find.byIcon(Icons.monetization_on_rounded), findsNothing);
      expect(
        find.descendant(
          of: find.widgetWithText(PillButton, 'BUY · 10'),
          matching: find.byType(CoinGlyph),
        ),
        findsOneWidget,
      );
    });

    testWidgets('CoinGlyph is static — it does not rebuild every frame', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: CoinGlyph())),
        ),
      );
      await tester.pump();
      // A spinning coin drives an AnimationController, so the tester would
      // still have a pending frame scheduled. A static glyph settles.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('item 4 — quick-action labels fit rather than truncate', () {
    for (final width in <double>[320, 375]) {
      testWidgets('extra-spin pill fits at ${width.toInt()}pt', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final auth = await _auth();
        await tester.pumpWidget(
          _halfWidthRow(
            StreakChip(
              authService: auth,
              backendApiService: _FakeShopApi(powerupCatalog: const {}),
              compact: true,
              adController: _FakeExtraSpinAds(),
              initialData: {
                'claimedToday': true,
                'localDate': _today(),
                'adExtraSpin': {'available': true, 'used': false},
              },
            ),
            PillButton(
              label: 'SHOP',
              icon: Icons.storefront_rounded,
              variant: PillButtonVariant.secondary,
              fullWidth: true,
              onPressed: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.text('BONUS SPIN - WATCH AD'), findsOneWidget);
        expect(
          _truncated(tester, 'BONUS SPIN - WATCH AD'),
          isFalse,
          reason: 'bonus-spin ticket must fit at ${width.toInt()}pt',
        );
        expect(_truncated(tester, 'SHOP'), isFalse);
      });

      testWidgets('a full-width sheet CTA is not ellipsized at '
          '${width.toInt()}pt', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const labels = [
          'WATCH 3 ADS TO UNLOCK',
          'GET MORE COINS',
          'START THE DAILY CHALLENGE',
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                // The item sheet's own horizontal inset (shop_tab's
                // `_showItemSheet` uses fromLTRB(24, 22, 24, 24)).
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final label in labels)
                      PillButton(
                        label: label,
                        icon: Icons.smart_display_rounded,
                        variant: PillButtonVariant.secondary,
                        fullWidth: true,
                        onPressed: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        for (final label in labels) {
          expect(
            _truncated(tester, label),
            isFalse,
            reason: '$label truncates at ${width.toInt()}pt',
          );
        }
      });

      // `race_alert_opt_in_card.dart` puts this label in `Expanded(flex: 2)`
      // WITHOUT `fullWidth: true`, so it is outside the fix and still
      // truncates (audit: FAIL at both widths — reported, not changed here).
      // The one-line remedy is for that call site to declare the full width it
      // is already given; this pins that the widget fix covers it when it does.
      testWidgets('a flex:2 label is not ellipsized once the site declares '
          'fullWidth at ${width.toInt()}pt', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Expanded(child: Text('Not now')),
                    Expanded(
                      flex: 2,
                      child: PillButton(
                        label: 'ENABLE RACE ALERTS',
                        fontSize: 10,
                        fullWidth: true,
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(_truncated(tester, 'ENABLE RACE ALERTS'), isFalse);
      });
    }

    testWidgets('a non-fullWidth PillButton keeps its 32pt side padding', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PillButton(label: 'OK', onPressed: () {}),
            ),
          ),
        ),
      );
      await tester.pump();
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(PillButton),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        container.padding,
        const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      );
    });

    testWidgets(
      'an explicit padding override still wins on a fullWidth button',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PillButton(
                label: 'GO',
                fullWidth: true,
                padding: EdgeInsets.zero,
                onPressed: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        final container = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(PillButton),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(container.padding, EdgeInsets.zero);
      },
    );

    testWidgets('a leading widget takes precedence over icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PillButton(
                label: 'BUY · 5',
                icon: Icons.monetization_on_rounded,
                leading: const CoinGlyph(),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.monetization_on_rounded), findsNothing);
      expect(find.byType(CoinGlyph), findsOneWidget);
    });
  });

  group('item 22 — equipped and selected states stay distinct', () {
    testWidgets('EQUIPPED stays in the compact selector marker band', (
      tester,
    ) async {
      await _pump(tester, _FakeShopApi(powerupCatalog: _powerupCatalog()));
      await _openInventoryCharacters(tester);

      final tile = find.byKey(const Key('shop-capybara-tile'));
      expect(tile, findsOneWidget);
      final badge = find.descendant(
        of: tile,
        matching: find.byKey(
          const Key('shop-cosmetic-equipped-__default_capybara__'),
        ),
      );
      expect(badge, findsOneWidget);
      expect(
        tester.getCenter(badge).dy,
        greaterThan(tester.getCenter(tile).dy),
      );
    });

    testWidgets('the xN quantity badge stays top-right', (tester) async {
      await _pump(
        tester,
        _FakeShopApi(
          powerupCatalog: _powerupCatalog(),
          powerupInventory: const [
            {'powerupType': 'LEG_CRAMP', 'quantity': 4},
          ],
        ),
      );
      await tester.tap(find.text('INVENTORY'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('POWERUPS'));
      await tester.pump(const Duration(milliseconds: 300));

      final badge = find.byKey(const Key('shop-tile-badge'));
      expect(badge, findsOneWidget);
      final tile = find.ancestor(
        of: badge,
        matching: find.byKey(const Key('shop-tile-clip')),
      );
      expect(
        tester.getCenter(badge).dx,
        greaterThan(tester.getCenter(tile).dx),
        reason: 'the quantity marker keeps its corner',
      );
    });
  });

  group('item 23 — the price lives in the strip, in every state', () {
    testWidgets('no per-tile price chip renders anywhere on the grid', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeShopApi(powerupCatalog: _powerupCatalog(), coins: 0),
        coins: 0,
      );
      expect(find.byKey(const Key('shop-price-badge-text')), findsNothing);
    });

    testWidgets('an unaffordable tile still prints the numeric price', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeShopApi(powerupCatalog: _powerupCatalog(), coins: 0),
        coins: 0,
      );
      for (final price in ['10', '50', '90']) {
        expect(find.text(price), findsOneWidget);
      }
      // …and the strip stops advertising the action.
      expect(find.textContaining('Watch '), findsNothing);
      expect(find.text('Get coins'), findsNothing);
    });

    testWidgets('an unaffordable cosmetic tile prints its price too', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeShopApi(
          powerupCatalog: _powerupCatalog(),
          cosmetics: _cosmetics(),
          coins: 0,
        ),
        coins: 0,
      );
      await tester.tap(find.text('ACCESSORIES'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('60'), findsOneWidget);
    });

    testWidgets('tapping an unaffordable tile opens the sheet', (tester) async {
      await _pump(
        tester,
        _FakeShopApi(powerupCatalog: _powerupCatalog(), coins: 0),
        coins: 0,
      );
      await tester.tap(find.text('Zap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Hit a rival'), findsOneWidget);
    });

    testWidgets('the strip stays tappable when unaffordable', (tester) async {
      await _pump(
        tester,
        _FakeShopApi(powerupCatalog: _powerupCatalog(), coins: 0),
        coins: 0,
      );
      // The strip label IS the price now, so tapping it is the strip tap.
      await tester.tap(find.text('10'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Hit a rival'), findsOneWidget);
    });

    testWidgets('the sheet CTA routes off the SERVER-served ad ceiling', (
      tester,
    ) async {
      // Ceiling 20: a 10-coin item with 0 coins is inside it (watch ads); a
      // 90-coin item is well outside (get coins).
      await _pump(
        tester,
        _FakeShopApi(
          powerupCatalog: _powerupCatalog(
            adUnlock: {
              'maxShortfall': 20,
              'coinsPerAd': 20,
              'maxAds': 3,
              'remainingToday': 3,
            },
          ),
          coins: 0,
        ),
        coins: 0,
      );

      await tester.tap(find.text('Zap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('WATCH 1 AD TO UNLOCK'), findsOneWidget);
      Navigator.of(tester.element(find.text('WATCH 1 AD TO UNLOCK'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Anchor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('GET MORE COINS'), findsOneWidget);
    });

    // The strip no longer says "Watch 1 ad", so the cap explanation in the
    // sheet is now the ONLY thing telling a capped user why the ad route
    // vanished. Pinned here so item 23 can't quietly take it with it.
    testWidgets('a spent daily cap still explains itself in the sheet', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeShopApi(
          powerupCatalog: _powerupCatalog(
            adUnlock: {
              'maxShortfall': 20,
              'coinsPerAd': 20,
              'maxAds': 3,
              'remainingToday': 0,
            },
          ),
          coins: 0,
        ),
        coins: 0,
      );
      await tester.tap(find.text('Zap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('You’ve used today’s ad unlock. Come back tomorrow.'),
        findsOneWidget,
      );
      expect(find.textContaining('WATCH'), findsNothing);
      expect(find.text('GET MORE COINS'), findsOneWidget);
    });

    testWidgets('a bigger server ceiling moves the route — nothing is '
        'hardcoded at 20', (tester) async {
      await _pump(
        tester,
        _FakeShopApi(
          powerupCatalog: _powerupCatalog(
            adUnlock: {
              'maxShortfall': 150,
              'coinsPerAd': 50,
              'maxAds': 3,
              'remainingToday': 3,
            },
          ),
          coins: 0,
        ),
        coins: 0,
      );
      await tester.tap(find.text('Anchor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('WATCH 2 ADS TO UNLOCK'), findsOneWidget);
    });
  });

  group('theme parity', () {
    testWidgets('the shop renders in the dark palette without exceptions', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await _auth();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: MediaQuery(
            data: const MediaQueryData(platformBrightness: Brightness.dark),
            child: ShopTab(
              authService: auth,
              backendApiService: _FakeShopApi(
                powerupCatalog: _powerupCatalog(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byType(CoinGlyph), findsWidgets);
      // Sanity: the tokens resolve in both palettes.
      final ctx = tester.element(find.byType(ShopTab));
      expect(AppColors.of(ctx).parchment, isNotNull);
    });
  });
}
