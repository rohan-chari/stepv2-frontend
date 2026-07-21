import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/powerup_shop_admin_item.dart';
import 'package:step_tracker/screens/admin_powerup_shop_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pixel_switch.dart';

/// Spec §5.1 / audit register #1 + #10: powerup shop prices and flags must be
/// editable WITHOUT a deploy, or "the DB is authority" doesn't hold for the
/// exact values the Leech drift was about.
class _ShopApi extends BackendApiService {
  _ShopApi({this.supported = true, this.failWith});

  final bool supported;
  final String? failWith;

  final List<Map<String, dynamic>> patches = [];

  @override
  Future<List<PowerupShopAdminItem>?> fetchAdminPowerupShopItems({
    required String identityToken,
  }) async {
    if (!supported) return null;
    return const [
      PowerupShopAdminItem(
        id: 'item-leech',
        sku: 'POWERUP_LEECH',
        name: 'Leech',
        powerupType: 'LEECH',
        priceCoins: 300,
        active: true,
        testOnly: true,
        sortOrder: 4,
      ),
      PowerupShopAdminItem(
        id: 'item-jammer',
        sku: 'POWERUP_SIGNAL_JAMMER',
        name: 'Signal Jammer',
        powerupType: 'SIGNAL_JAMMER',
        priceCoins: 75,
        active: false,
        testOnly: false,
        sortOrder: 2,
      ),
    ];
  }

  @override
  Future<PowerupShopAdminItem?> updateAdminPowerupShopItem({
    required String identityToken,
    required String itemId,
    int? priceCoins,
    bool? active,
    bool? testOnly,
    int? sortOrder,
  }) async {
    patches.add({
      'itemId': itemId,
      if (priceCoins != null) 'priceCoins': priceCoins,
      if (active != null) 'active': active,
      if (testOnly != null) 'testOnly': testOnly,
      if (sortOrder != null) 'sortOrder': sortOrder,
    });
    if (failWith != null) throw ApiException(failWith!, statusCode: 400);
    return PowerupShopAdminItem(
      id: itemId,
      sku: 'POWERUP_LEECH',
      name: 'Leech',
      powerupType: 'LEECH',
      priceCoins: priceCoins ?? 300,
      active: active ?? true,
      testOnly: testOnly ?? true,
      sortOrder: sortOrder ?? 4,
    );
  }
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Admin',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester, BackendApiService api) async {
  tester.view.physicalSize = const Size(1400, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: AdminPowerupShopScreen(
        authService: await _authService(),
        backendApiService: api,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _setField(WidgetTester tester, Key key, String value) async {
  final field = find.byKey(key, skipOffstage: false);
  expect(field, findsOneWidget, reason: 'missing field $key');
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('old backend (GET 404) -> unsupported notice, not an empty form', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _ShopApi(supported: false));

    expect(find.textContaining('not supported by this backend'), findsOneWidget);
    expect(find.byKey(const Key('ps-price-item-leech')), findsNothing);
  });

  testWidgets('lists every shop item with its price and flags', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _ShopApi());

    expect(find.text('Leech'), findsOneWidget);
    expect(find.text('POWERUP_LEECH'), findsOneWidget);
    expect(find.text('Signal Jammer'), findsOneWidget);
    expect(find.byKey(const Key('ps-price-item-leech')), findsOneWidget);
    expect(find.byKey(const Key('ps-sort-item-leech')), findsOneWidget);
    expect(find.byKey(const Key('ps-active-item-leech')), findsOneWidget);
    expect(find.byKey(const Key('ps-testonly-item-leech')), findsOneWidget);
  });

  testWidgets('name and description are NOT editable — PowerupCopy owns copy', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _ShopApi());

    expect(find.byKey(const Key('ps-name-item-leech')), findsNothing);
    expect(find.byKey(const Key('ps-description-item-leech')), findsNothing);
    // Exactly two editable fields per item (price + sortOrder), so a copy
    // field can't be added here by accident.
    expect(find.byType(TextField), findsNWidgets(4));
  });

  testWidgets('save is disabled until something changes, so an empty PATCH '
      'body (400) can never be sent', (WidgetTester tester) async {
    final api = _ShopApi();
    await _pump(tester, api);

    final save = find.byKey(const Key('ps-save-item-leech'));
    expect(tester.widget<TextButton>(save).onPressed, isNull);

    await _setField(tester, const Key('ps-price-item-leech'), '350');
    expect(tester.widget<TextButton>(save).onPressed, isNotNull);

    // Typing the original value back is not a change.
    await _setField(tester, const Key('ps-price-item-leech'), '300');
    expect(tester.widget<TextButton>(save).onPressed, isNull);
    expect(api.patches, isEmpty);
  });

  testWidgets('editing the price PATCHes ONLY the changed key, for the right '
      'item, and adopts the server echo', (WidgetTester tester) async {
    final api = _ShopApi();
    await _pump(tester, api);

    await _setField(tester, const Key('ps-price-item-leech'), '350');
    await _tap(tester, find.byKey(const Key('ps-save-item-leech')));

    expect(api.patches, hasLength(1));
    expect(api.patches.single, {'itemId': 'item-leech', 'priceCoins': 350});

    // The row now reflects the server's echoed item, and is clean again.
    expect(
      tester.widget<TextButton>(
        find.byKey(const Key('ps-save-item-leech')),
      ).onPressed,
      isNull,
    );
  });

  testWidgets('toggling active/testOnly PATCHes only the booleans', (
    WidgetTester tester,
  ) async {
    final api = _ShopApi();
    await _pump(tester, api);

    await _tap(tester, find.byKey(const Key('ps-testonly-item-leech')));
    await _tap(tester, find.byKey(const Key('ps-save-item-leech')));

    expect(api.patches, hasLength(1));
    expect(api.patches.single, {'itemId': 'item-leech', 'testOnly': false});
    expect(
      tester
          .widget<PixelSwitch>(find.byKey(const Key('ps-testonly-item-leech')))
          .value,
      isFalse,
    );
  });

  testWidgets('a price the contract would reject is blocked client-side', (
    WidgetTester tester,
  ) async {
    final api = _ShopApi();
    await _pump(tester, api);

    await _setField(tester, const Key('ps-price-item-leech'), '-5');

    expect(find.textContaining('non-negative'), findsOneWidget);
    expect(
      tester.widget<TextButton>(
        find.byKey(const Key('ps-save-item-leech')),
      ).onPressed,
      isNull,
    );
    expect(api.patches, isEmpty);
  });

  testWidgets('a rejected PATCH keeps the edit on screen instead of silently '
      'discarding it', (WidgetTester tester) async {
    final api = _ShopApi(failWith: 'priceCoins must be an integer >= 0');
    await _pump(tester, api);

    await _setField(tester, const Key('ps-price-item-leech'), '350');
    await _tap(tester, find.byKey(const Key('ps-save-item-leech')));

    expect(api.patches, hasLength(1));
    // Still dirty: the admin's unsaved intent survives a failed save.
    expect(
      tester.widget<TextButton>(
        find.byKey(const Key('ps-save-item-leech')),
      ).onPressed,
      isNotNull,
    );
  });
}
