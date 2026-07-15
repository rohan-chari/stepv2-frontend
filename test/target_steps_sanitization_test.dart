import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/home_course_track.dart';
import 'package:step_tracker/widgets/race_finishers_banner.dart';

// TR-901: all races are time-based now — the target-steps UI (goal line,
// "Goal: N" header copy, finisher banners on the live screen) is removed.
// Parsing stays null-safe: payloads from the backend still CONTAIN
// `targetSteps`/`finishedAt` (wire compat, TR-903) and must render cleanly
// as time-based races, and COMPLETED target-era races still render (TR-904).

class _TargetEraActiveRaceApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Old Goal Race',
      'status': 'ACTIVE',
      // Old-backend fields still on the wire — must be ignored, not shown.
      'targetSteps': 100000,
      'timeBased': true,
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': false,
      'endsAt': '2026-04-10T12:00:00.000Z',
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
    return {
      'status': 'ACTIVE',
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': 42000,
          // A finisher timestamp from the target era must not resurrect
          // finisher UI on the live screen.
          'finishedAt': '2026-04-02T10:00:00.000Z',
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
    return const {'coins': 320, 'heldCoins': 0};
  }
}

class _TargetEraCompletedRaceApi extends _TargetEraActiveRaceApi {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    final base = await super.fetchRaceDetails(
      identityToken: identityToken,
      raceId: raceId,
    );
    return {
      ...base,
      'status': 'COMPLETED',
      'winner': {'id': 'user-1', 'displayName': 'Trail Walker'},
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
          'totalSteps': 100000,
          'finishedAt': '2026-04-02T10:00:00.000Z',
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'status': 'ACCEPTED',
          'totalSteps': 38000,
          'finishedAt': null,
        },
      ],
    };
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
    'TR-901: ACTIVE race with wire targetSteps shows no goal UI and no '
    'finisher banner',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-old-goal',
            backendApiService: _TargetEraActiveRaceApi(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Renders as a normal time-based race...
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeCourseTrack), findsOneWidget);

      // ...with every target-steps surface gone.
      expect(find.textContaining('Goal:'), findsNothing);
      expect(find.byType(RaceFinishersBanner), findsNothing);
      expect(find.textContaining('FINISHED'), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'TR-904: COMPLETED target-era race still renders without goal UI',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-old-completed',
            backendApiService: _TargetEraCompletedRaceApi(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeCourseTrack), findsOneWidget);
      expect(find.text('RACE COMPLETE'), findsOneWidget);
      expect(find.textContaining('Goal:'), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );
}
