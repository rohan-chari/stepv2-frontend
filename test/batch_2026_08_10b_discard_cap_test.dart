// Feature batch 2026-08-10 (part 2) — Item 2: the discard modal must say when
// the daily coin cap is hit (or nearly hit) on the FIRST discard of a screen
// visit, before any discard response has taught the client the headroom.
//
// Pumps the REAL RaceDetailScreen against a stubbed HTTP layer and reads the
// four dialog bodies, the clamped "+N 🪙" tag, and the Pocket Watch sheet's
// own price chip — the third price surface the ui-test-planner found.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';
import 'package:step_tracker/widgets/pill_button.dart';

const _rarePowerup = {
  'id': 'pu-1',
  'type': 'PROTEIN_SHAKE',
  'rarity': 'RARE', // bundled price table: RARE = 10 coins
  'status': 'HELD',
  'upgradeLevel': 0,
};

const _pocketWatch = {
  'id': 'pw-1',
  'type': 'POCKET_WATCH',
  'rarity': 'RARE',
  'status': 'HELD',
  'upgradeLevel': 0,
};

class _CapStubApi extends BackendApiService {
  _CapStubApi({this.discardCapRemaining, this.inventory = const [_rarePowerup]});

  /// `powerupData.discardCapRemaining`. Null = the key is OMITTED, i.e. an
  /// older backend — every dialog must then read exactly as it does today.
  final int? discardCapRemaining;
  final List<Map<String, dynamic>> inventory;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => {
    'id': 'race-1',
    'name': 'Trail Blazers',
    'status': 'ACTIVE',
    'maxDurationDays': 3,
    'buyInAmount': 0,
    'potCoins': 0,
    'heldPotCoins': 0,
    'projectedPotCoins': 0,
    'myStatus': 'ACCEPTED',
    'isCreator': false,
    'powerupsEnabled': true,
    'endsAt': '2126-04-10T12:00:00.000Z',
    'participants': const [
      {'userId': 'user-1', 'displayName': 'Runner 1', 'status': 'ACCEPTED'},
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': const [
      {
        'userId': 'user-1',
        'displayName': 'Runner 1',
        'totalSteps': 9000,
        'finishedAt': null,
      },
    ],
    'powerupData': {
      'enabled': true,
      'inventory': inventory,
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': const [],
      if (discardCapRemaining != null)
        'discardCapRemaining': discardCapRemaining,
    },
  };

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async => const {'events': []};

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 100, 'heldCoins': 0};

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => const {'items': []};

  @override
  Future<Map<String, dynamic>> discardPowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async => const {'ok': true};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Runner',
    'auth_coins': 100,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester, _CapStubApi api) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-1',
        backendApiService: api,
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openSlot(WidgetTester tester, ItemSlotState state) async {
  final slot = find
      .byWidgetPredicate((w) => w is ItemSlot && w.state == state)
      .first;
  await tester.ensureVisible(slot);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(slot);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapDiscard(WidgetTester tester) async {
  await tester.tap(find.text('DISCARD'));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.steps',
      version: '2.2.4',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('Item 2 — the four dialog bodies, on the FIRST discard of a visit', () {
    testWidgets('cap unknown (older backend) → today\'s exact copy', (
      tester,
    ) async {
      await _pump(tester, _CapStubApi());
      await _openSlot(tester, ItemSlotState.held);
      await _tapDiscard(tester);

      expect(find.text('Discard Protein Shake for 10 coins?'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('cap 0 → "you\'ll get 0 coins" with no prior discard', (
      tester,
    ) async {
      await _pump(tester, _CapStubApi(discardCapRemaining: 0));
      await _openSlot(tester, ItemSlotState.held);
      await _tapDiscard(tester);

      expect(
        find.text("Daily discard bonus reached. You'll get 0 coins."),
        findsOneWidget,
      );
      await _teardown(tester);
    });

    testWidgets('0 < cap < price → the CLAMPED amount and the warning', (
      tester,
    ) async {
      await _pump(tester, _CapStubApi(discardCapRemaining: 2));
      await _openSlot(tester, ItemSlotState.held);
      await _tapDiscard(tester);

      expect(
        find.text(
          'Discard Protein Shake for 2 coins? Your daily discard bonus is '
          'nearly used up.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('for 10 coins'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('cap above the price → the full price, unchanged', (
      tester,
    ) async {
      await _pump(tester, _CapStubApi(discardCapRemaining: 40));
      await _openSlot(tester, ItemSlotState.held);
      await _tapDiscard(tester);

      expect(find.text('Discard Protein Shake for 10 coins?'), findsOneWidget);
      await _teardown(tester);
    });

  });

  group('Item 2 — the "+N 🪙" tag uses the same clamped number', () {
    testWidgets('partial cap clamps the tag to the cap', (tester) async {
      await _pump(tester, _CapStubApi(discardCapRemaining: 2));
      await _openSlot(tester, ItemSlotState.held);

      final pill = find.ancestor(
        of: find.text('DISCARD'),
        matching: find.byType(PillButton),
      );
      expect(
        find.descendant(of: pill, matching: find.text('+2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pill, matching: find.text('+10')),
        findsNothing,
      );
      await _teardown(tester);
    });

    testWidgets('cap 0 hides the tag entirely (not "+0")', (tester) async {
      await _pump(tester, _CapStubApi(discardCapRemaining: 0));
      await _openSlot(tester, ItemSlotState.held);

      expect(find.text('+0'), findsNothing);
      expect(find.text('+10'), findsNothing);
      await _teardown(tester);
    });

    testWidgets('cap unknown keeps the full-price tag', (tester) async {
      await _pump(tester, _CapStubApi());
      await _openSlot(tester, ItemSlotState.held);

      expect(find.text('+10'), findsOneWidget);
      await _teardown(tester);
    });
  });

  group('Item 2 — the Pocket Watch sheet is the third price surface', () {
    testWidgets('its DISCARD chip shows the clamped number', (tester) async {
      await _pump(
        tester,
        _CapStubApi(discardCapRemaining: 3, inventory: const [_pocketWatch]),
      );
      await _openSlot(tester, ItemSlotState.held);

      final discard = find.byKey(const Key('pocket-watch-discard'));
      expect(discard, findsOneWidget);
      expect(
        find.descendant(of: discard, matching: find.text('+3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: discard, matching: find.text('+10')),
        findsNothing,
      );
      await _teardown(tester);
    });

    testWidgets('cap 0 removes its chip', (tester) async {
      await _pump(
        tester,
        _CapStubApi(discardCapRemaining: 0, inventory: const [_pocketWatch]),
      );
      await _openSlot(tester, ItemSlotState.held);

      final discard = find.byKey(const Key('pocket-watch-discard'));
      expect(discard, findsOneWidget);
      expect(
        find.descendant(of: discard, matching: find.textContaining('+')),
        findsNothing,
      );
      await _teardown(tester);
    });

    testWidgets('cap unknown keeps the full price chip (older backend)', (
      tester,
    ) async {
      await _pump(tester, _CapStubApi(inventory: const [_pocketWatch]));
      await _openSlot(tester, ItemSlotState.held);

      expect(
        find.descendant(
          of: find.byKey(const Key('pocket-watch-discard')),
          matching: find.text('+10'),
        ),
        findsOneWidget,
      );
      await _teardown(tester);
    });
  });
}
