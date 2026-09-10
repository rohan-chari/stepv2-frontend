import 'dart:async';
import 'package:flutter/material.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/character_wardrobe.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/shop_character_card.dart';
import 'unified_shop_test.dart' show pumpShop, shopAuth, ShopApi;
import 'billing_components_test.dart' show FakeBilling;

class _LoadingCharactersApi extends ShopApi {
  final response = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> fetchShopCharacters({
    required String identityToken,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) => response.future;
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
  for (final width in [300.0, 390.0, 1600.0]) {
    for (final scale in [1.0, 1.6]) {
      for (final dark in [false, true]) {
        testWidgets(
          'matching merchandise geometry width $width scale $scale dark $dark',
          (tester) async {
            addTearDown(tester.view.reset);
            await pumpShop(
              tester,
              billing: FakeBilling(),
              width: width,
              textScale: scale,
              palette: dark ? AppPalette.night : AppPalette.light,
            );
            final power = find.byKey(const Key('shop-product-card')).first;
            final character = find.byKey(const Key('shop-character-default'));
            expect(tester.getSize(character), tester.getSize(power));
            expect(
              tester.getSize(find.byKey(const Key('shop-cosmetic-grid'))).width,
              lessThanOrEqualTo(1000),
            );
            for (final description in [
              'Stock up on coins for powerups and accessories.',
              'Buy powerups for races. The badge shows how many you own.',
              'Tap a character to customize its outfit or unlock a new one.',
            ]) {
              expect(find.text(description), findsOneWidget);
            }
            expect(find.byKey(const Key('shop-membership-toggle')), findsNothing);
            expect(find.textContaining('Bara+'), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  testWidgets(
    'character loading grid retains the loaded merchandise geometry',
    (tester) async {
      final auth = await shopAuth();
      final api = _LoadingCharactersApi();
      await tester.pumpWidget(
        BillingScope.disabled(
          child: MaterialApp(
            home: ShopTab(authService: auth, backendApiService: api),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final loading = tester.widget<GridView>(
        find.byKey(const Key('shop-loading-grid')),
      );
      final powerups = tester.widget<GridView>(
        find.byKey(const Key('shop-product-grid')),
      );
      final a =
          loading.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      final b =
          powerups.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(a.crossAxisCount, b.crossAxisCount);
      expect(a.childAspectRatio, b.childAspectRatio);
      expect(a.mainAxisSpacing, b.mainAxisSpacing);
      expect(loading.padding, powerups.padding);
      api.response.complete(
        await ShopApi().fetchShopCharacters(identityToken: 'session'),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );
  for (final state in [
    (owned: false, active: false, purchasable: false),
    (owned: false, active: false, purchasable: true),
    (owned: true, active: false, purchasable: false),
    (owned: true, active: true, purchasable: false),
  ]) {
    final owned = state.owned;

    testWidgets('character lock preserves tap and ownership semantics $state', (
      tester,
    ) async {
      var taps = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 112,
                height: 165,
                child: ShopCharacterCard(
                  character: ShopCharacter.fromJson({
                    'characterKey': 'turtle',
                    'name': 'Turtle',
                    'owned': owned,
                    'active': state.active,
                    'canPurchase': state.purchasable,
                  }),
                  onPressed: () => taps++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.byIcon(Icons.lock_rounded),
        owned ? findsNothing : findsOneWidget,
      );
      expect(
        find.text(
          state.active
              ? 'ACTIVE'
              : owned
              ? 'OWNED'
              : 'LOCKED',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Turtle, ${owned ? 'owned' : 'locked'}')),
        findsOneWidget,
      );
      if (!owned) {
        final lock = find.byIcon(Icons.lock_rounded);
        final art = find.byKey(const Key('shop-character-art'));
        expect(tester.getCenter(lock), tester.getCenter(art));
        expect(find.byKey(const Key('locked-shop-art-shade')), findsOneWidget);
      } else {
        expect(find.byKey(const Key('locked-shop-art-shade')), findsNothing);
      }
      await tester.tap(find.byType(ShopCharacterCard));
      expect(taps, 1);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}
