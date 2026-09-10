import 'package:flutter/material.dart';
import 'dart:ui' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/widgets/coin_glyph.dart';
import 'package:step_tracker/widgets/app_refresh_indicator.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'character_wardrobe_screen_test.dart' show WardrobeApi, pumpWardrobeShop;

class _QuoteApi extends WardrobeApi {
  _QuoteApi(this.price, this.policy, {this.legacy = false});
  Object? price, policy;
  final bool legacy;
  int purchases = 0;
  @override
  Future<Map<String, dynamic>> fetchShopCharacters({
    required String identityToken,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) => legacy
      ? Future.value({})
      : super.fetchShopCharacters(
          identityToken: identityToken,
          limit: limit,
          cursor: cursor,
          localDate: localDate,
        );
  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => legacy
      ? {
          'coins': 100,
          'ownedItemIds': [],
          'equipped': {},
          'items': [
            {
              ...row('locked-corgi', owned: false)['item'] as Map,
              'canPurchase': policy,
            },
          ],
        }
      : await super.fetchShopCatalog(identityToken: identityToken);
  @override
  Future<Map<String, dynamic>> purchaseShopItem({
    required String identityToken,
    required String itemId,
    required String idempotencyKey,
    int? expectedPriceCoins,
  }) async {
    purchases++;
    return {'coins': 100};
  }

  @override
  Map<String, dynamic> row(String key, {bool owned = true}) {
    final result = super.row(key, owned: owned);
    if (!owned) {
      result['canPurchase'] = policy;
      result['item'] = {...result['item'] as Map, 'priceCoins': price};
    }
    return result;
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
      'auth_coins': 100,
      'tutorial_shop_seen': true,
    });
  });
  testWidgets(
    'owned cards edit and equip directly with compact accessible controls',
    (tester) async {
      final api = WardrobeApi();
      final semantics = tester.ensureSemantics();
      await pumpWardrobeShop(tester, api);
      final edit = find.byKey(const Key('shop-character-edit-character-corgi'));
      final equip = find.byKey(
        const Key('shop-character-equip-character-corgi'),
      );
      expect(edit, findsOneWidget);
      expect(equip, findsOneWidget);
      for (final width in [360.0, 375.0, 390.0, 600.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pump();
        expect(tester.getCenter(edit).dy, tester.getCenter(equip).dy);
        expect(
          tester.getSize(edit).width,
          greaterThanOrEqualTo(48),
          reason: 'Edit at $width',
        );
        expect(
          tester.getSize(equip).width,
          greaterThanOrEqualTo(48),
          reason: 'Equip at $width',
        );
      }
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(tester.getCenter(edit).dy, tester.getCenter(equip).dy);
      final equipNode = tester.getSemantics(
        find.bySemanticsLabel('Equip Corgi'),
      );
      expect(
        equipNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      for (final control in [edit, equip]) {
        expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(control).width, greaterThanOrEqualTo(48));
      }
      final visual = find.byKey(
        const Key('shop-character-edit-character-corgi-tag'),
      );
      expect(tester.getSize(visual).height, lessThan(36));
      tester.binding.rootPipelineOwner.semanticsOwner!.performAction(
        equipNode.id,
        SemanticsAction.tap,
      );
      await tester.tap(equip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.activations, 1);
      expect(find.text('Use character'), findsNothing);
      expect(find.text('Edit outfit'), findsNothing);
      if (find.byKey(const Key('info-toast-shell')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('info-toast-shell')));
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.tap(edit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('wardrobe-preview')), findsOneWidget);
      semantics.dispose();
    },
  );
  testWidgets('purchase confirmation cannot buy for a replacement account', (
    tester,
  ) async {
    final api = _QuoteApi(0, true);
    await pumpWardrobeShop(tester, api);
    await tester.tap(find.byKey(const Key('shop-character-buy-locked-corgi')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final confirm = tester
        .widget<PillButton>(
          find.ancestor(
            of: find.text('BUY · 0'),
            matching: find.byType(PillButton),
          ),
        )
        .onPressed;
    final auth = tester
        .widget<ShopTab>(find.byType(ShopTab, skipOffstage: false))
        .authService;
    await auth.syncFromBackendUser({
      'id': 'other-user',
      'coins': 500,
    }, authoritative: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    confirm!();
    await tester.pump();
    expect(api.purchases, 0);
    expect(find.byType(BottomSheet), findsNothing);
  });
  testWidgets('a refreshed purchase quote invalidates an open confirmation', (
    tester,
  ) async {
    final api = _QuoteApi(0, true);
    await pumpWardrobeShop(tester, api);
    await tester.tap(find.byKey(const Key('shop-character-buy-locked-corgi')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final confirm = tester
        .widget<PillButton>(
          find.ancestor(
            of: find.text('BUY · 0'),
            matching: find.byType(PillButton),
          ),
        )
        .onPressed;
    api.policy = false;
    await tester
        .widget<AppRefreshIndicator>(
          find.byType(AppRefreshIndicator, skipOffstage: false).first,
        )
        .onRefresh();
    await tester.pump();
    confirm!();
    await tester.pump();
    expect(api.purchases, 0);
  });
  for (final legacy in [false, true]) {
    for (final price in [300, 0, null, -1, 2.5, '300']) {
      for (final policy in [true, false, null]) {
        testWidgets(
          'unowned character legacy=$legacy quote=$price policy=$policy follows server authority',
          (tester) async {
            await pumpWardrobeShop(
              tester,
              _QuoteApi(price, policy, legacy: legacy),
            );
            final card = find.byKey(const Key('shop-character-locked-corgi'));
            final validPrice = price == 300 || price == 0;
            final buy = find.byKey(
              const Key('shop-character-buy-locked-corgi'),
            );
            expect(
              find.descendant(of: card, matching: find.text('LOCKED')),
              findsNothing,
            );
            if (validPrice && policy == true) {
              expect(buy, findsOneWidget);
              expect(
                find.descendant(of: card, matching: find.text('$price')),
                findsOneWidget,
              );
              expect(
                find.descendant(of: card, matching: find.byType(CoinGlyph)),
                findsOneWidget,
              );
              await tester.ensureVisible(buy);
              await tester.tap(buy);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 400));
              expect(find.byType(BottomSheet), findsOneWidget);
            } else if (legacy && !validPrice) {
              // The legacy catalog rejects malformed economic payloads before
              // character rows reach the renderer.
              expect(card, findsNothing);
              expect(buy, findsNothing);
              expect(find.text('Couldn’t load accessories'), findsOneWidget);
            } else {
              expect(buy, findsNothing);
              expect(
                find.descendant(of: card, matching: find.text('Unavailable')),
                findsOneWidget,
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
