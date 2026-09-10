import 'dart:async';
import 'dart:io';
import 'package:step_tracker/services/remote_asset_cache.dart';
import 'package:step_tracker/widgets/accessory_preview_sheet.dart';
import 'package:step_tracker/screens/character_wardrobe_screen.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:step_tracker/demo/demo_race_api_service.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/preview/preview_billing_api.dart';
import 'package:step_tracker/preview/preview_billing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/home_hero_scene.dart';
import 'package:step_tracker/widgets/home_course_track.dart';
import 'character_wardrobe_screen_test.dart' show WardrobeApi, hat, corgi;
import 'unified_shop_test.dart' show shopAuth;

Map<String, dynamic> contextFor({bool fallback = false}) => {
  'itemId': hat['id'],
  'canPreview': true,
  'unavailableReason': null,
  'usedFallbackCharacter': fallback,
  'character': {
    'characterKey': 'character-corgi',
    'name': 'Corgi',
    'item': corgi,
  },
  'accessories': [hat],
};

class _Api extends WardrobeApi {
  Map<String, dynamic> response = contextFor();
  Completer<Map<String, dynamic>>? gate;
  ApiException? failure;
  int previews = 0, purchases = 0;
  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {'coins': 500, 'items': []};
  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => {
    'coins': 500,
    'ownedItemIds': [],
    'equipped': {},
    'items': [hat],
  };
  @override
  Future<Map<String, dynamic>> fetchShopItemPreview({
    required String identityToken,
    required String itemId,
  }) async {
    previews++;
    expect(itemId, hat['id']);
    if (failure != null) throw failure!;
    return gate?.future ?? response;
  }

  @override
  Future<Map<String, dynamic>> purchaseShopItem({
    required String identityToken,
    required String itemId,
    required String idempotencyKey,
    int? expectedPriceCoins,
  }) async {
    purchases++;
    return {
      'coins': 300,
      'item': {...hat, 'owned': true},
    };
  }
}

Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
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
  Future<dynamic> open(
    WidgetTester tester,
    _Api api, {
    double width = 390,
    double scale = 1,
    bool wardrobe = false,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = await shopAuth();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: ShopTab(
          authService: auth,
          backendApiService: api,
          initialFocus: ShopFocus.items,
        ),
      ),
    );
    await frames(tester);
    if (wardrobe) {
      final edit = find.byKey(const Key('shop-character-edit-default'));
      await tester.ensureVisible(edit);
      await frames(tester);
      await tester.tap(edit);
      await frames(tester);
      final item = find.byKey(Key('wardrobe-item-${hat['id']}'));
      await tester.ensureVisible(item);
      await frames(tester);
      await tester.tap(item);
      await frames(tester);
      await tester.ensureVisible(find.text('Buy · 200'));
      await tester.tap(find.text('Buy · 200'));
      await frames(tester);
    } else {
      final tile = find.byKey(Key('shop-accessory-${hat['id']}'));
      await tester.ensureVisible(tile);
      await frames(tester);
      await tester.tap(tile);
      await frames(tester);
    }
    expect(find.text('BUY · 200'), findsOneWidget);
    final preview = find.text('PREVIEW');
    expect(preview, findsOneWidget);
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await frames(tester);
    return auth;
  }

  testWidgets('wardrobe Buy menu preview closes back to its unchanged draft', (
    tester,
  ) async {
    final api = _Api()..hatOwned = false;
    await open(tester, api, wardrobe: true);
    expect(find.byKey(const Key('accessory-preview-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('accessory-preview-close')));
    await frames(tester);
    expect(find.byType(CharacterWardrobeScreen), findsOneWidget);
    expect(find.byKey(Key('wardrobe-selected-${hat['id']}')), findsOneWidget);
    expect([api.purchases, api.saves, api.activations], [0, 0, 0]);
  });
  for (final mode in ['cold', 'warm', 'closed', 'switched']) {
    final warm = mode == 'warm';
    testWidgets(
      'remote character body readiness and late-result guards: $mode',
      (tester) async {
        final cache = RemoteAssetCache.instance;
        final download = Completer<List<int>?>();
        late Directory directory;
        await tester.runAsync(() async {
          directory = await Directory.systemTemp.createTemp(
            'bara-preview-body',
          );
          await cache.debugConfigure(
            cacheDir: directory,
            fetcher: (_, _) => warm
                ? Future.value(
                    File(
                      'assets/images/corgi_puppy_walk_right_short_ears.png',
                    ).readAsBytesSync(),
                  )
                : download.future,
          );
          cache.debugApplyManifest({
            'characters': {
              'future_animal': {
                'url': 'https://assets.example/future.png',
                'version': 'v1',
                'animationFrames': 6,
              },
            },
          });
          if (warm) {
            await cache.fetch(RemoteAssetKind.characters, 'future_animal');
          }
        });
        addTearDown(() async {
          cache.debugReset();
          await directory.delete(recursive: true);
        });
        final api = _Api()
          ..response = {
            ...contextFor(),
            'character': {
              'characterKey': 'remote-id',
              'name': 'Future animal',
              'item': {
                'id': 'remote-id',
                'slot': 'CHARACTER',
                'assetKey': 'future_animal',
                'assetVersion': 'v1',
                'assetUrl': 'https://assets.example/future.png',
              },
            },
          };
        final auth = await open(tester, api);
        if (!warm) {
          expect(
            find.byKey(const Key('accessory-preview-loading')),
            findsOneWidget,
          );
          expect(find.byType(AnimatedCapybaraWithAccessories), findsNothing);
          if (mode == 'closed') {
            await tester.tap(find.byKey(const Key('accessory-preview-close')));
            await frames(tester);
          } else if (mode == 'switched') {
            await auth.syncFromBackendUser({
              'id': 'replacement',
            }, authoritative: true);
            await frames(tester);
          }
          await tester.runAsync(() async {
            download.complete(
              await File(
                'assets/images/corgi_puppy_walk_right_short_ears.png',
              ).readAsBytes(),
            );
          });
          for (var i = 0; i < 5; i++) {
            await tester.pump();
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            });
          }
          await frames(tester);
        }
        if (mode == 'closed' || mode == 'switched') {
          expect(find.byType(AnimatedCapybaraWithAccessories), findsNothing);
        } else {
          expect(
            tester
                .widget<AnimatedCapybaraWithAccessories>(
                  find.byType(AnimatedCapybaraWithAccessories),
                )
                .animal,
            'future_animal',
          );
        }
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final kind in ['tutorial', 'demo', 'billing']) {
    testWidgets(
      '$kind preview fixture renders real scene without production reads',
      (tester) async {
        final billing = PreviewBillingController();
        addTearDown(billing.dispose);
        final BackendApiService api = kind == 'tutorial'
            ? TutorialPreviewBackendApiService()
            : kind == 'demo'
            ? DemoRaceApiService(
                DemoRaceEngine(myUserId: 'user', myDisplayName: 'Demo'),
              )
            : PreviewBillingApi(billing);
        final itemId = kind == 'billing'
            ? 'baseball_cap'
            : 'tutorial-preview-baseball-cap';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AccessoryPreviewSheet(
                itemId: itemId,
                itemName: 'Baseball Cap',
                api: api,
                auth: billing.auth,
              ),
            ),
          ),
        );
        await frames(tester);
        expect(find.text('Previewing on Capybara'), findsOneWidget);
        expect(find.byType(HomeHeroScene), findsOneWidget);
        expect(
          tester
              .widget<AnimatedCapybaraWithAccessories>(
                find.byType(AnimatedCapybaraWithAccessories),
              )
              .accessories
              .single['id'],
          itemId,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final fallback in [false, true]) {
    testWidgets(
      'preview renders exactly the server outfit fallback=$fallback without writes',
      (tester) async {
        final api = _Api()..response = contextFor(fallback: fallback);
        await open(tester, api);
        expect(find.byType(HomeHeroScene), findsOneWidget);
        final sprite = tester.widget<AnimatedCapybaraWithAccessories>(
          find.byType(AnimatedCapybaraWithAccessories),
        );
        expect(sprite.animal, 'corgi_puppy');
        expect(sprite.accessories.map((item) => item['id']), [hat['id']]);
        expect(sprite.animate, isFalse);
        expect(find.text('Previewing on Corgi'), findsOneWidget);
        expect(
          find.text('Your equipped character stays unchanged.'),
          fallback ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.byKey(const Key('accessory-preview-close')));
        await frames(tester);
        expect(find.byType(HomeHeroScene), findsNothing);
        expect(api.previews, 1);
        expect([api.purchases, api.saves, api.activations], [0, 0, 0]);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('pending preview shows loading and ignores account replacement', (
    tester,
  ) async {
    final api = _Api()..gate = Completer<Map<String, dynamic>>();
    final auth = await open(tester, api);
    expect(find.byKey(const Key('accessory-preview-loading')), findsOneWidget);
    await auth.syncFromBackendUser({'id': 'replacement'}, authoritative: true);
    api.gate!.complete(contextFor());
    await frames(tester);
    expect(find.byType(HomeHeroScene), findsNothing);
    expect(find.text('Previewing on Corgi'), findsNothing);
    expect([api.purchases, api.saves, api.activations], [0, 0, 0]);
  });
  for (final response in <Map<String, dynamic>>[
    {},
    {
      'itemId': hat['id'],
      'canPreview': false,
      'unavailableReason': 'no_compatible_character',
    },
    {...contextFor(), 'character': null},
    {...contextFor(), 'accessories': []},
    {...contextFor(), 'itemId': 'other'},
  ]) {
    testWidgets('missing or unavailable preview context is safe $response', (
      tester,
    ) async {
      final api = _Api()..response = response;
      await open(tester, api);
      expect(find.text('Preview is currently unavailable.'), findsOneWidget);
      expect(find.byType(HomeHeroScene), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final status in [404, 500]) {
    testWidgets('preview error $status preserves close and retry', (
      tester,
    ) async {
      final api = _Api()
        ..failure = ApiException('Unavailable', statusCode: status);
      await open(tester, api, width: 320, scale: 2);
      expect(find.byKey(const Key('accessory-preview-close')), findsOneWidget);
      expect(find.byType(HomeHeroScene), findsNothing);
      if (status == 500) {
        api.failure = null;
        await tester.ensureVisible(find.text('TRY AGAIN'));
        await tester.tap(find.text('TRY AGAIN'));
        await frames(tester);
        expect(find.byType(HomeHeroScene), findsOneWidget);
      } else {
        expect(find.text('Preview is currently unavailable.'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
