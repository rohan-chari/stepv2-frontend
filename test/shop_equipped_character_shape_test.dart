import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Batch 2026-07-27 item 21 — Inventory → CHARACTERS white-screened the moment a
/// non-capybara character was equipped.
///
/// The backend serializes `equipped[slot]` as an OBJECT
/// (`shopCosmetics.js` `serializeEquippedAccessory`), never a String. Reading it
/// as `String?` threw a `TypeError` during build, so the CHARACTERS inventory
/// page rendered an `ErrorWidget` (blank in release).
///
/// Every fixture here uses the REAL object shape — that is the whole point of
/// the regression: the prior tests seeded `{}` / `{'CHARACTER': null}` /
/// `{'CHARACTER': '<id string>'}` and therefore never exercised the crash.

/// Mirrors `serializeEquippedAccessory` exactly.
Map<String, dynamic> serializedEquippedAccessory({
  String id = 'item-turtle',
  String sku = 'CH_TURTLE',
  String name = 'Turtle',
  String slot = 'CHARACTER',
  String assetKey = 'turtle',
}) => <String, dynamic>{
  'id': id,
  'sku': sku,
  'name': name,
  'slot': slot,
  'assetKey': assetKey,
  'renderMetadata': <String, dynamic>{'scale': 1.0},
  'bobble': false,
};

class _FakeShopApi extends BackendApiService {
  _FakeShopApi({this.equipped = const <String, dynamic>{}, this.cosmetics});

  final Map<String, dynamic> equipped;
  final List<Map<String, dynamic>>? cosmetics;

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => {
    'coins': 1000,
    'ownedItemIds': <String>[],
    'equipped': equipped,
    'items': cosmetics ?? const <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {'coins': 1000, 'items': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => {'items': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> equipAccessory({
    required String identityToken,
    required String slot,
    required String? itemId,
  }) async => <String, dynamic>{};
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

Future<void> _pumpCharacterInventory(
  WidgetTester tester,
  BackendApiService api,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: ShopTab(authService: await _auth(), backendApiService: api)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('INVENTORY'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('CHARACTERS'));
  await tester.pump(const Duration(milliseconds: 300));
}

Map<String, dynamic> _turtleCosmetic({bool equipped = true}) => {
  'id': 'item-turtle',
  'sku': 'CH_TURTLE',
  'name': 'Turtle',
  'slot': 'CHARACTER',
  'assetKey': 'turtle',
  'owned': true,
  'equipped': equipped,
  'priceCoins': 300,
  'description': 'Slow and steady',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => PowerupCopy.resetForTest());

  testWidgets(
    'CHARACTERS inventory renders when equipped[CHARACTER] is the real object',
    (tester) async {
      await _pumpCharacterInventory(
        tester,
        _FakeShopApi(
          equipped: {'CHARACTER': serializedEquippedAccessory()},
          cosmetics: [_turtleCosmetic()],
        ),
      );

      // The crash manifested as a build-time TypeError.
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('shop-capybara-tile')), findsOneWidget);
      expect(find.text('Capybara'), findsOneWidget);
      // A turtle is equipped, so the capybara tile must NOT claim EQUIPPED.
      expect(
        find.descendant(
          of: find.byKey(const Key('shop-capybara-tile')),
          matching: find.text('EQUIPPED'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shop-capybara-tile')),
          matching: find.text('EQUIP'),
        ),
        findsWidgets,
      );
    },
  );

  testWidgets('an empty equipped map means the capybara is equipped', (
    tester,
  ) async {
    await _pumpCharacterInventory(tester, _FakeShopApi());

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('shop-capybara-tile')),
        matching: find.text('EQUIPPED'),
      ),
      findsWidgets,
    );
  });

  testWidgets('an explicit null CHARACTER row means the capybara is equipped', (
    tester,
  ) async {
    await _pumpCharacterInventory(
      tester,
      _FakeShopApi(equipped: {'CHARACTER': null}),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('shop-capybara-tile')),
        matching: find.text('EQUIPPED'),
      ),
      findsWidgets,
    );
  });

  testWidgets('a malformed CHARACTER row never throws', (tester) async {
    // Defensive read: any unexpected shape must degrade, not crash. The backend
    // may be a different version than this build expects.
    await _pumpCharacterInventory(
      tester,
      _FakeShopApi(equipped: {'CHARACTER': 12345}),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('shop-capybara-tile')), findsOneWidget);
  });

  test('the fixture matches serializeEquippedAccessory\'s real keys', () {
    // Guard: if the backend serializer gains/loses a key, this fixture — and
    // therefore the regression above — must be updated with it.
    expect(
      serializedEquippedAccessory().keys.toSet(),
      {'id', 'sku', 'name', 'slot', 'assetKey', 'renderMetadata', 'bobble'},
    );
  });
}
