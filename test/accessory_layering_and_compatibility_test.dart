import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/admin_accessory_tuner_screen.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/home_course_track.dart';

class _TunerApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchAdminShopItems({
    required String identityToken,
  }) async => <String, dynamic>{
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'knight-helmet',
        'sku': 'KNIGHT_HELMET',
        'name': 'Knight Helmet',
        'slot': 'HEAD',
        'assetKey': 'knight_helmet',
        'priceCoins': 0,
        'description': null,
        'renderMetadata': <String, dynamic>{},
      },
    ],
  };
}

class _ConflictShopApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => <String, dynamic>{
    'coins': 1000,
    'ownedItemIds': <String>['knight-helmet', 'glasses-3d'],
    'equipped': <String, dynamic>{
      'HEAD': <String, dynamic>{
        'id': 'knight-helmet',
        'slot': 'HEAD',
        'assetKey': 'knight_helmet',
      },
    },
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'knight-helmet',
        'sku': 'KNIGHT_HELMET',
        'name': 'Knight Helmet',
        'slot': 'HEAD',
        'assetKey': 'knight_helmet',
        'priceCoins': 0,
        'description': null,
        'owned': true,
        'equipped': true,
      },
      <String, dynamic>{
        'id': 'glasses-3d',
        'sku': 'GLASSES_3D',
        'name': '3D Glasses',
        'slot': 'FACE',
        'assetKey': 'glasses_3d',
        'priceCoins': 0,
        'description': null,
        'owned': true,
        'equipped': false,
      },
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => <String, dynamic>{'items': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => <String, dynamic>{'items': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> equipAccessory({
    required String identityToken,
    required String slot,
    required String? itemId,
  }) async {
    throw const ApiException(
      'That accessory conflicts with Knight Helmet.',
      statusCode: 409,
      code: 'ACCESSORY_CONFLICT',
      details: <String, dynamic>{
        'error': 'That accessory conflicts with Knight Helmet.',
        'code': 'ACCESSORY_CONFLICT',
        'conflictingItemIds': <String>['knight-helmet'],
        'conflictingSlots': <String>['HEAD'],
      },
    );
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
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

List<String> _previewAssetKeys(WidgetTester tester) {
  final preview = find.byType(CapybaraCustomizationPreview);
  final images = find.descendant(of: preview, matching: find.byType(Image));
  return tester.widgetList<Image>(images).map((image) {
    final provider = image.image;
    return provider is AssetImage ? provider.assetName : '';
  }).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('canonical accessory order keeps backpack behind the body', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: CapybaraSpriteWithAccessories(
            capybaraSize: 96,
            frameIndex: 0,
            accessories: <Map<String, dynamic>>[
              <String, dynamic>{
                'slot': 'HEAD',
                'assetKey': 'baseball_cap',
                'renderMetadata': <String, dynamic>{},
              },
              <String, dynamic>{
                'slot': 'FACE',
                'assetKey': 'sunglasses',
                'renderMetadata': <String, dynamic>{},
              },
              <String, dynamic>{
                'slot': 'NECK',
                'assetKey': 'gold_chain',
                'renderMetadata': <String, dynamic>{},
              },
              <String, dynamic>{
                'slot': 'BACK',
                'assetKey': 'backpack',
                'renderMetadata': <String, dynamic>{'renderLayer': 'behind'},
              },
              <String, dynamic>{
                'slot': 'FEET',
                'assetKey': 'shoes',
                'renderMetadata': <String, dynamic>{'perFoot': false},
              },
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final assetNames = tester.widgetList<Image>(find.byType(Image)).map((
      image,
    ) {
      final provider = image.image;
      return provider is AssetImage ? provider.assetName : '';
    }).toList();
    expect(
      assetNames,
      containsAllInOrder(<String>[
        'assets/images/accessories/backpack.png',
        'assets/images/capybara_walk_right.png',
        'assets/images/accessories/shoes.png',
        'assets/images/accessories/gold_chain.png',
        'assets/images/accessories/sunglasses.png',
        'assets/images/accessories/baseball_cap.png',
      ]),
    );
  });

  testWidgets(
    'dark-theme layering keeps valid art and uses the normal placeholder for a missing fixture asset',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.light(),
          darkTheme: AppThemeData.night(),
          themeMode: ThemeMode.dark,
          home: const Center(
            child: CapybaraSpriteWithAccessories(
              capybaraSize: 96,
              frameIndex: 0,
              accessories: <Map<String, dynamic>>[
                <String, dynamic>{
                  'slot': 'BACK',
                  'assetKey': 'backpack',
                  'renderMetadata': <String, dynamic>{'renderLayer': 'behind'},
                },
                <String, dynamic>{
                  'slot': 'HEAD',
                  'assetKey': 'fixture_art_missing_from_this_build',
                  'renderMetadata': <String, dynamic>{},
                },
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        Theme.of(
          tester.element(find.byType(CapybaraSpriteWithAccessories)),
        ).brightness,
        Brightness.dark,
      );
      expect(
        find.byType(CustomPaint),
        findsWidgets,
        reason:
            'missing fixture art must use the ordinary accessory placeholder',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tuner simulation replaces and restores the selected preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccessoryTunerScreen(
          authService: await _auth(),
          backendApiService: _TunerApi(),
        ),
      ),
    );
    await tester.pump();

    expect(
      _previewAssetKeys(tester),
      contains('assets/images/accessories/knight_helmet.png'),
    );
    await tester.tap(
      find.byKey(const Key('admin-accessory-tuner-full-loadout-toggle')),
    );
    await tester.pump();
    expect(
      _previewAssetKeys(tester),
      containsAll(<String>[
        'assets/images/accessories/backpack.png',
        'assets/images/accessories/shoes.png',
        'assets/images/accessories/gold_chain.png',
        'assets/images/accessories/sunglasses.png',
        'assets/images/accessories/baseball_cap.png',
      ]),
    );
    expect(
      _previewAssetKeys(tester),
      isNot(contains('assets/images/accessories/knight_helmet.png')),
    );

    await tester.tap(
      find.byKey(const Key('admin-accessory-tuner-full-loadout-toggle')),
    );
    await tester.pump();
    expect(
      _previewAssetKeys(tester),
      contains('assets/images/accessories/knight_helmet.png'),
    );
  });

  testWidgets('a 409 accessory conflict toasts and preserves equipped state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ShopTab(
          authService: await _auth(),
          backendApiService: _ConflictShopApi(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('INVENTORY'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('shop-category-ACCESSORIES')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Knight Helmet'), findsOneWidget);
    expect(find.text('3D Glasses'), findsOneWidget);
    expect(find.text('EQUIPPED'), findsOneWidget);
    await tester.ensureVisible(find.text('3D Glasses'));
    await tester.tap(find.text('3D Glasses'));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('shop-dressing-room-stage')),
        matching: find.text('EQUIP'),
      ),
    );
    await tester.pump();

    expect(
      find.text('That accessory conflicts with Knight Helmet.'),
      findsOneWidget,
    );
    expect(find.text('EQUIPPED'), findsOneWidget);
    expect(find.text('EQUIP'), findsOneWidget);
  });
}
