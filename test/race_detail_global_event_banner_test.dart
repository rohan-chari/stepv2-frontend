import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// ---------------------------------------------------------------------------
// Global step-multiplier event banner on the race detail page.
//
// When getRaceProgress returns an active `globalEvent`
// ({ active: true, multiplier, endsAt }), the race page shows a "2x STEPS"
// banner with a countdown to endsAt. When the field is absent, no banner.
// Read defensively — old responses simply omit the field.
// ---------------------------------------------------------------------------

class _GlobalEventBackendApiService extends BackendApiService {
  _GlobalEventBackendApiService({this.globalEvent});

  final Map<String, dynamic>? globalEvent;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Gold Sprint',
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
      'powerupsEnabled': false,
      'endsAt': '2026-06-10T12:00:00.000Z',
      'participants': const [
        {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
        {'userId': 'user-2', 'displayName': 'Hill Climber', 'status': 'ACCEPTED'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    final progress = <String, dynamic>{
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
      ],
      'powerupData': const {
        'enabled': false,
        'inventory': [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
      },
    };
    if (globalEvent != null) {
      progress['globalEvent'] = globalEvent;
    }
    return progress;
  }

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async {
    return const {'events': []};
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows the 2x event banner when progress includes an active globalEvent',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      // endsAt far in the future so the countdown is positive and the banner
      // is unambiguously "active".
      final endsAt = DateTime.now().toUtc().add(const Duration(minutes: 20));
      final backendApiService = _GlobalEventBackendApiService(
        globalEvent: {
          'active': true,
          'multiplier': 2,
          'endsAt': endsAt.toIso8601String(),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-event-on',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('race-global-event-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('2x STEPS'), findsOneWidget);

      // Tear down the periodic countdown timer.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'does NOT show the banner when progress omits globalEvent',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _GlobalEventBackendApiService(globalEvent: null);

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-event-off',
            backendApiService: backendApiService,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('race-global-event-banner')), findsNothing);
      expect(find.textContaining('2x STEPS'), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );
}
