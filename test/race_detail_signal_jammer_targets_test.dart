import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';

/// Fake API for the Signal Jammer target-picker flow. Renders an ACTIVE race
/// with powerups enabled and a single held SIGNAL_JAMMER in the signed-in
/// user's inventory. Unlike Sneaky Swap (which has its own targets endpoint),
/// the jammer uses the generic picker built from the progress participants,
/// excluding self and stealthed racers.
class _SignalJammerBackendApiService extends BackendApiService {
  _SignalJammerBackendApiService();

  int usePowerupCalls = 0;
  String? lastUsedPowerupId;
  String? lastTargetUserId;
  int lastUpgradeLevel = -1;

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
    // Deliberately mutable (no const): the screen's optimistic inventory
    // removal mutates powerupData in place after a use.
    return {
      'status': 'ACTIVE',
      'participants': [
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
          // Stealthed racers are excluded from the target picker.
          'stealthed': true,
        },
      ],
      'powerupData': {
        'enabled': true,
        'inventory': [
          {
            'id': 'pw-jammer-1',
            'type': 'SIGNAL_JAMMER',
            'rarity': 'RARE',
            'status': 'HELD',
          },
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
  Future<Map<String, dynamic>> usePowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    String? targetUserId,
    String? targetDirection,
    int upgradeLevel = 0,
  }) async {
    usePowerupCalls += 1;
    lastUsedPowerupId = powerupId;
    lastTargetUserId = targetUserId;
    lastUpgradeLevel = upgradeLevel;
    return const {'success': true};
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
// pickers contain a spinning PowerupIcon (infinite animation) that never
// "settles".
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openSignalJammerUse(WidgetTester tester) async {
  // Tap the held SIGNAL_JAMMER inventory slot to open the powerup actions
  // sheet.
  final heldSlot = find.byWidgetPredicate(
    (w) => w is ItemSlot && w.state == ItemSlotState.held,
  );
  expect(heldSlot, findsOneWidget);
  await tester.ensureVisible(heldSlot);
  await tester.tap(heldSlot);
  await _pumpFrames(tester);

  // SIGNAL_JAMMER is non-upgradeable, so the sheet shows the single USE
  // button (no tier buttons).
  expect(find.text('USE'), findsOneWidget);
  await tester.tap(find.text('USE'));
  await _pumpFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Signal Jammer opens the target picker and uses on the chosen racer',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _SignalJammerBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-jammer',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await _openSignalJammerUse(tester);

      // The generic target picker is shown.
      expect(find.text('CHOOSE A TARGET'), findsOneWidget);

      // Scope name assertions to the picker sheet subtree (these names also
      // appear in the race board behind the sheet).
      final pickerColumn = find
          .ancestor(
            of: find.text('CHOOSE A TARGET'),
            matching: find.byType(Column),
          )
          .last;
      // Rival racer appears in the picker; self does not; stealthed racer is
      // excluded.
      expect(
        find.descendant(of: pickerColumn, matching: find.text('@Hill Climber')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pickerColumn, matching: find.text('@Trail Walker')),
        findsNothing,
      );
      expect(
        find.descendant(of: pickerColumn, matching: find.text('@Ridge Runner')),
        findsNothing,
      );

      // Pick the rival -> the use call goes out with their userId, base level.
      await tester.tap(
        find.descendant(of: pickerColumn, matching: find.text('@Hill Climber')),
      );
      await _pumpFrames(tester);

      expect(api.usePowerupCalls, 1);
      expect(api.lastUsedPowerupId, 'pw-jammer-1');
      expect(api.lastTargetUserId, 'user-2');
      expect(api.lastUpgradeLevel, 0);

      // Let any post-use toast/refresh timers finish so nothing is pending at
      // teardown.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}
