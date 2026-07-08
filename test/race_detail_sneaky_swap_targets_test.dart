import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';

/// Fake API for the Sneaky Swap target-picker flow. Renders an ACTIVE race with
/// powerups enabled and a single held SNEAKY_SWAP in the signed-in user's
/// inventory. The set of racers the picker should offer is driven entirely by
/// [targets] — the value the new `fetchSneakySwapTargets` endpoint returns.
class _SneakySwapBackendApiService extends BackendApiService {
  _SneakySwapBackendApiService({required this.targets});

  /// Targets returned by the new endpoint: list of {userId, displayName}.
  final List<Map<String, dynamic>> targets;

  int sneakySwapTargetsCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Powerup Race',
      'status': 'ACTIVE',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 0,
      'payouts': {'first': 0, 'second': 0, 'third': 0},
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': true,
      'endsAt': '2026-12-10T12:00:00.000Z',
      'participants': const [
        {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
        {'userId': 'user-2', 'displayName': 'Hill Climber', 'status': 'ACCEPTED'},
        {'userId': 'user-3', 'displayName': 'Ridge Runner', 'status': 'ACCEPTED'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'status': 'ACTIVE',
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': 42000,
          'finishedAt': null,
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'totalSteps': 38000,
          'finishedAt': null,
        },
        {
          'userId': 'user-3',
          'displayName': 'Ridge Runner',
          'totalSteps': 31000,
          'finishedAt': null,
        },
      ],
      'powerupData': const {
        'enabled': true,
        'inventory': [
          {'id': 'pw-sneaky-1', 'type': 'SNEAKY_SWAP', 'rarity': 'RARE', 'status': 'HELD'},
        ],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async {
    return const {'events': []};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 500, 'heldCoins': 0};
  }

  @override
  Future<Map<String, dynamic>> fetchSneakySwapTargets({
    required String identityToken,
    required String raceId,
  }) async {
    sneakySwapTargetsCalls += 1;
    return {'targets': targets};
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 500,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

// Pumps fixed frames instead of pumpAndSettle: the powerup actions sheet and
// pickers contain a spinning PowerupIcon (infinite animation) and the empty
// path shows an auto-dismiss toast — neither ever "settles".
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openSneakySwapUse(WidgetTester tester) async {
  // Tap the held SNEAKY_SWAP inventory slot to open the powerup actions sheet.
  final heldSlot = find.byWidgetPredicate(
    (w) => w is ItemSlot && w.state == ItemSlotState.held,
  );
  expect(heldSlot, findsOneWidget);
  await tester.ensureVisible(heldSlot);
  await tester.tap(heldSlot);
  await _pumpFrames(tester);

  // Tap USE in the actions sheet -> triggers the target resolution + picker.
  expect(find.text('USE'), findsOneWidget);
  await tester.tap(find.text('USE'));
  await _pumpFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Sneaky Swap picker shows only racers returned by the new endpoint',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      // Endpoint reports only Hill Climber (user-2) has something stealable.
      final api = _SneakySwapBackendApiService(
        targets: const [
          {'userId': 'user-2', 'displayName': 'Hill Climber'},
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-sneaky',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await _openSneakySwapUse(tester);

      expect(api.sneakySwapTargetsCalls, 1);
      // Picker header is shown (powerup title row + subtitle).
      expect(find.text('CHOOSE A TARGET'), findsOneWidget);

      // Scope name assertions to the picker sheet subtree (these names also
      // appear in the race board behind the sheet). The header and list live
      // in the sheet's root Column, so anchor on the subtitle's outer Column.
      final pickerColumn = find
          .ancestor(
            of: find.text('CHOOSE A TARGET'),
            matching: find.byType(Column),
          )
          .last;
      // Only the endpoint-returned racer appears in the picker.
      expect(
        find.descendant(of: pickerColumn, matching: find.text('@Hill Climber')),
        findsOneWidget,
      );
      // The other eligible (but not-stealable) racer is NOT offered.
      expect(
        find.descendant(of: pickerColumn, matching: find.text('@Ridge Runner')),
        findsNothing,
      );

      // Dismiss the picker sheet so no route animation is left pending.
      Navigator.of(
        tester.element(find.text('CHOOSE A TARGET')),
      ).pop();
      await _pumpFrames(tester);
    },
  );

  testWidgets(
    'Sneaky Swap shows an empty-state and no picker when no one has a stealable powerup',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _SneakySwapBackendApiService(targets: const []);

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-sneaky-empty',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await _openSneakySwapUse(tester);

      expect(api.sneakySwapTargetsCalls, 1);
      // Friendly empty-state, surfaced BEFORE forcing a pick.
      expect(
        find.text('No one has a powerup to steal right now'),
        findsOneWidget,
      );
      // No target picker was opened.
      expect(find.text('TARGET FOR SNEAKY SWAP'), findsNothing);

      // Let the toast auto-dismiss timer + reverse animation finish so no
      // Timer/animation is left pending at test teardown. (Avoid pumpAndSettle:
      // the screen has its own perpetual animations that never settle.)
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}
