import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';

// TR-651/657: in a team race, offensive single-target powerups may aim only
// at ENEMY-team members, and forfeited members are excluded from the pool.
// Invalid targets are never presented (no grayed-out teammates).

class _TeamPowerupApi extends BackendApiService {
  String? lastTargetUserId;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Team Powerup Race',
      'status': 'ACTIVE',
      'isTeamRace': true,
      'teamSize': 2,
      'teamAName': 'Swift Capys',
      'teamBName': 'Turbo Beavers',
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': true,
      'endsAt': '2026-12-10T12:00:00.000Z',
      'participants': const [
        {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED', 'team': 'TEAM_A'},
        {'userId': 'ally-1', 'displayName': 'Ally Alice', 'status': 'ACCEPTED', 'team': 'TEAM_A'},
        {'userId': 'enemy-1', 'displayName': 'Enemy Eve', 'status': 'ACCEPTED', 'team': 'TEAM_B'},
        {'userId': 'quit-1', 'displayName': 'Quitter Quinn', 'status': 'ACCEPTED', 'team': 'TEAM_B'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    // Mutable (no const): the screen optimistically mutates powerupData.
    return {
      'status': 'ACTIVE',
      'participants': [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'team': 'TEAM_A',
          'totalSteps': 6200,
          'finishedAt': null,
        },
        {
          'userId': 'ally-1',
          'displayName': 'Ally Alice',
          'team': 'TEAM_A',
          'totalSteps': 6100,
          'finishedAt': null,
        },
        {
          'userId': 'enemy-1',
          'displayName': 'Enemy Eve',
          'team': 'TEAM_B',
          'totalSteps': 5900,
          'finishedAt': null,
        },
        {
          // TR-657: forfeited -> out of every targeting pool.
          'userId': 'quit-1',
          'displayName': 'Quitter Quinn',
          'team': 'TEAM_B',
          'totalSteps': 3000,
          'forfeitedAt': '2026-07-15T10:00:00.000Z',
          'finishedAt': null,
        },
      ],
      'powerupData': {
        'enabled': true,
        'inventory': [
          {'id': 'pu-1', 'type': 'SIGNAL_JAMMER', 'status': 'HELD'},
        ],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
        'powerupStepInterval': 5000,
        'stepsUntilNextPowerup': 1000,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async => const {'events': []};

  @override
  Future<Map<String, dynamic>> usePowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    String? targetUserId,
    String? targetDirection,
    int upgradeLevel = 0,
  }) async {
    lastTargetUserId = targetUserId;
    return const {'result': {}};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({
    required String identityToken,
  }) async => const {'coins': 320, 'heldCoins': 0};
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 420,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _openPicker(WidgetTester tester, _TeamPowerupApi api) async {
  // The powerup sheet needs a phone-sized canvas; the 800x600 default overflows.
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final authService = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: authService,
        raceId: 'race-pu',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();

  // Tap the held SIGNAL_JAMMER slot -> actions sheet. The jammer is
  // non-upgradeable, so it shows a single USE button (no tier buttons).
  final heldSlot = find.byWidgetPredicate(
    (w) => w is ItemSlot && w.state == ItemSlotState.held,
  );
  await tester.ensureVisible(heldSlot);
  await tester.tap(heldSlot);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  await tester.tap(find.text('USE'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-651: the picker lists enemies only — no teammates',
      (tester) async {
    final api = _TeamPowerupApi();
    await _openPicker(tester, api);

    // Scope every assertion to the picker itself — teammates legitimately
    // still appear in the standings/course behind the sheet.
    final picker = find.byKey(const Key('powerup-target-list'));
    expect(picker, findsOneWidget);

    expect(
      find.descendant(of: picker, matching: find.textContaining('Enemy Eve')),
      findsOneWidget,
    );
    // No friendly fire: the teammate is never offered, not even grayed out.
    expect(
      find.descendant(of: picker, matching: find.textContaining('Ally Alice')),
      findsNothing,
    );
    // TR-657: the forfeited enemy is out of the pool.
    expect(
      find.descendant(
        of: picker,
        matching: find.textContaining('Quitter Quinn'),
      ),
      findsNothing,
    );
  });

  testWidgets('TR-651: tapping the only enemy sends them as the target',
      (tester) async {
    final api = _TeamPowerupApi();
    await _openPicker(tester, api);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('powerup-target-list')),
        matching: find.textContaining('Enemy Eve'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(api.lastTargetUserId, 'enemy-1');
  });
}
