import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';
import 'package:step_tracker/screens/multi_case_opening_screen.dart';
import 'package:step_tracker/widgets/app_refresh_indicator.dart';
import 'package:step_tracker/widgets/case_opening_strip.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';
import 'package:step_tracker/widgets/powerup_guide_sheet.dart';
import 'unified_shop_test.dart' show ShopApi, shopAuth;

class _Api extends ShopApi {
  List<String> types = ['IMPOSTER', 'DECOY', 'FUTURE_ITEM'];
  Object? price = 123;
  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {
    'coins': 100,
    'items': [
      for (final type in types)
        {
          'sku': type,
          'powerupType': type,
          'name': type,
          'description': 'Server item',
          'priceCoins': price,
        },
    ],
  };
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
    PowerupCopy.resetForTest();
  });
  testWidgets(
    'Shop follows returned types, repricing and removals without local item policy',
    (tester) async {
      final api = _Api();
      await tester.pumpWidget(
        MaterialApp(
          home: ShopTab(
            authService: await shopAuth(),
            backendApiService: api,
            initialFocus: ShopFocus.items,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (final type in api.types) {
        expect(find.text(type), findsOneWidget);
      }
      await tester.ensureVisible(find.text('IMPOSTER'));
      await tester.tap(find.text('IMPOSTER'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('WATCH'), findsNothing);
      expect(find.text('GET MORE COINS'), findsOneWidget);
      Navigator.of(tester.element(find.text('GET MORE COINS'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      api.types = ['FUTURE_ITEM'];
      api.price = 42;
      await tester
          .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(find.text('IMPOSTER'), findsNothing);
      expect(find.text('DECOY'), findsNothing);
      await tester.ensureVisible(find.text('FUTURE_ITEM'));
      await tester.tap(find.text('FUTURE_ITEM'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('BUY · 42'), findsOneWidget);
    },
  );
  for (final quote in [null, -1, 1.5, double.nan, double.infinity, 0]) {
    testWidgets('Shop never invents a price from quote $quote', (tester) async {
      final api = _Api()
        ..types = ['FUTURE_ITEM']
        ..price = quote;
      await tester.pumpWidget(
        MaterialApp(
          home: ShopTab(
            authService: await shopAuth(),
            backendApiService: api,
            initialFocus: ShopFocus.items,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      if (quote == 0) {
        await tester.ensureVisible(find.text('FUTURE_ITEM'));
        await tester.tap(find.text('FUTURE_ITEM'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('BUY · 0'), findsOneWidget);
      } else {
        expect(find.text('FUTURE_ITEM'), findsNothing);
        expect(find.text('BUY · 0'), findsNothing);
      }
    });
  }
  for (final odds in <Map<String, dynamic>?>[
    null,
    {},
    {
      'reelPreviewAvailable': 'true',
      'byType': {'IMPOSTER': 1.0},
    },
    {'reelPreviewAvailable': true, 'byType': {}},
    {
      'reelPreviewAvailable': true,
      'byType': {'IMPOSTER': 0.5},
    },
    {
      'reelPreviewAvailable': true,
      'byType': {'IMPOSTER': double.nan},
    },
  ]) {
    testWidgets(
      'invalid or missing reel authorization $odds uses neutral tiles and actual winner',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CaseOpeningStrip(
                onComplete: () {},
                dropOdds: odds,
                resultType: 'SERVER_WINNER',
                resultRarity: 'UNCOMMON',
              ),
            ),
          ),
        );
        await tester.pump();
        final icons = tester.widgetList<PowerupIcon>(find.byType(PowerupIcon));
        expect(icons, isNotEmpty);
        expect(
          icons.every(
            (icon) =>
                icon.type == 'MYSTERY_BOX' || icon.type == 'SERVER_WINNER',
          ),
          isTrue,
        );
        expect(icons.where((icon) => icon.type == 'SERVER_WINNER'), isNotEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('guide accepts restored items and authoritative empty roster', (
    tester,
  ) async {
    Future<void> load(List<Map<String, dynamic>> rows) => PowerupCopy.refresh(
      fetch: () async => {
        'version': 'v',
        'availabilityVersion': 2,
        'powerups': rows,
      },
    ).then((_) {});
    await load([
      {
        'type': 'IMPOSTER',
        'name': 'Restored Imposter',
        'description': 'Server description',
        'upgradeTierLabels': [],
        'availability': {'shop': true, 'roll': false},
      },
    ]);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PowerupGuideSheet())),
    );
    expect(find.text('Restored Imposter'), findsWidgets);
    await load([]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PowerupGuideSheet())),
    );
    expect(find.byType(PowerupIcon), findsNothing);
  });
  for (final multiple in [false, true]) {
    for (final available in [true, false]) {
      testWidgets(
        '${multiple ? 'multi' : 'single'} box uses server pool only when authorized=$available',
        (tester) async {
          final odds = {
            'reelPreviewAvailable': available,
            'byType': {'FUTURE_ITEM': 1.0, 'IMPOSTER': 0.0},
          };
          await tester.pumpWidget(
            MaterialApp(
              home: multiple
                  ? MultiCaseOpeningScreen(
                      boxCount: 2,
                      openAll: () async => [
                        {'type': 'WINNER', 'rarity': 'RARE'},
                        {'type': 'WINNER', 'rarity': 'RARE'},
                      ],
                      dropOdds: odds,
                    )
                  : CaseOpeningScreen(
                      openMysteryBox: () async => {},
                      dropOdds: odds,
                    ),
            ),
          );
          await tester.pump();
          if (multiple) {
            await tester.tap(find.text('OPEN ALL').last);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 50));
          }
          final icons = tester.widgetList<PowerupIcon>(
            find.descendant(
              of: find.byType(CaseOpeningStrip),
              matching: find.byType(PowerupIcon),
            ),
          );
          expect(icons, isNotEmpty);
          expect(
            icons.every(
              (icon) =>
                  icon.type == (available ? 'FUTURE_ITEM' : 'MYSTERY_BOX') ||
                  (multiple && icon.type == 'WINNER'),
            ),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
