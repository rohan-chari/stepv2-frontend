import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';

/// §7/§9 powerups5 — Drill Sergeant and Bounty route through the target picker.
/// Bounty additionally pre-filters the picker to rivals currently AHEAD of me.
///
/// Signed-in user is `user-1` with 38,000 steps. Rivals: `user-2` (ahead,
/// 42,000), `user-3` (behind, 31,000). A held wave-5 powerup is injected per
/// test via [_Api.heldType].
class _Api extends BackendApiService {
  _Api({required this.heldType});

  final String heldType;
  int usePowerupCalls = 0;
  String? lastTargetUserId;

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
      'participants': [
        {'userId': 'user-1', 'displayName': 'Trail Walker', 'totalSteps': 38000},
        {'userId': 'user-2', 'displayName': 'Hill Climber', 'totalSteps': 42000},
        {'userId': 'user-3', 'displayName': 'Ridge Runner', 'totalSteps': 31000},
      ],
      'powerupData': {
        'enabled': true,
        'inventory': [
          {
            'id': 'pw-1',
            'type': heldType,
            'rarity': 'UNCOMMON',
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
    return const {'coins': 5000, 'heldCoins': 0};
  }

  @override
  Future<Map<String, dynamic>> usePowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    String? targetUserId,
    String? targetDirection,
    String? targetEffectId,
    int upgradeLevel = 0,
  }) async {
    usePowerupCalls += 1;
    lastTargetUserId = targetUserId;
    return const {
      'result': {'outcome': 'APPLIED', 'coinsSpent': 0},
    };
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 5000,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openUse(WidgetTester tester, _Api api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-1',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();

  final heldSlot = find.byWidgetPredicate(
    (w) => w is ItemSlot && w.state == ItemSlotState.held,
  );
  expect(heldSlot, findsOneWidget);
  await tester.ensureVisible(heldSlot);
  await tester.tap(heldSlot);
  await _pumpFrames(tester);

  expect(find.text('USE'), findsOneWidget);
  await tester.tap(find.text('USE'));
  await _pumpFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Drill Sergeant opens the picker with every rival', (
    tester,
  ) async {
    final api = _Api(heldType: 'DRILL_SERGEANT');
    await _openUse(tester, api);

    expect(find.text('CHOOSE A TARGET'), findsOneWidget);
    final picker = find
        .ancestor(
          of: find.text('CHOOSE A TARGET'),
          matching: find.byType(Column),
        )
        .last;
    // Both rivals present (ahead and behind); self excluded.
    expect(
      find.descendant(of: picker, matching: find.text('@Hill Climber')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.text('@Ridge Runner')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets(
    'Bounty opens the picker filtered to rivals ahead of me only',
    (tester) async {
      final api = _Api(heldType: 'BOUNTY');
      await _openUse(tester, api);

      expect(find.text('CHOOSE A TARGET'), findsOneWidget);
      final picker = find
          .ancestor(
            of: find.text('CHOOSE A TARGET'),
            matching: find.byType(Column),
          )
          .last;
      // Only the racer ahead of me (Hill Climber, 42k > my 38k) is offered.
      expect(
        find.descendant(of: picker, matching: find.text('@Hill Climber')),
        findsOneWidget,
      );
      // The racer behind me (Ridge Runner, 31k) is filtered out.
      expect(
        find.descendant(of: picker, matching: find.text('@Ridge Runner')),
        findsNothing,
      );

      // Pick the eligible target -> use call carries their userId.
      await tester.tap(
        find.descendant(of: picker, matching: find.text('@Hill Climber')),
      );
      await _pumpFrames(tester);

      expect(api.usePowerupCalls, 1);
      expect(api.lastTargetUserId, 'user-2');

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}
