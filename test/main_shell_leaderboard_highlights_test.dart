import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/challenge_week_step_sync_service.dart';
import 'package:step_tracker/services/health_service.dart';

class _FakeHealthService extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;
}

class _FakeBackgroundSyncBootstrapService
    extends BackgroundSyncBootstrapService {
  @override
  Future<void> enableHealthKitBackgroundDelivery() async {}
}

class _FakeChallengeWeekStepSyncService extends ChallengeWeekStepSyncService {
  _FakeChallengeWeekStepSyncService(this.result);

  final List<StepData> result;

  @override
  Future<List<StepData>> loadCurrentChallengeWeekSteps({
    required String identityToken,
  }) async {
    return result;
  }
}

class _FakeBackendApiService extends BackendApiService {
  final List<({String type, String period})> leaderboardCalls = [];
  int fetchLeaderboardHighlightsCalls = 0;

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async {
    return {
      'sessionToken': authToken,
      'user': {'isAdmin': false, 'coins': 60},
    };
  }

  @override
  Future<void> recordSteps({
    required String identityToken,
    required StepData stepData,
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async {
    return const [];
  }

  @override
  Future<Map<String, dynamic>> fetchCurrentChallenge({
    required String identityToken,
  }) async {
    return const {'challenge': null, 'instances': [], 'syncDays': []};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {
      'stepGoal': 8000,
      'incomingFriendRequests': 0,
      'displayName': 'Trail Walker',
      'email': 'walker@example.com',
      'isAdmin': false,
      'coins': 70,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async {
    return const {'active': [], 'pending': [], 'completed': []};
  }

  @override
  Future<Map<String, dynamic>> fetchLeaderboardHighlights({
    required String identityToken,
  }) async {
    fetchLeaderboardHighlightsCalls += 1;
    return const {
      'cards': [
        {
          'title': "You're 8th all time in challenges. Keep climbing.",
          'subtitle': '5 more wins could move you up.',
          'leaderboardType': 'challenges',
          'period': 'allTime',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
  }) async {
    leaderboardCalls.add((type: type, period: period));
    if (type == 'challenges') {
      return {
        'minimumCompletedChallenges': 5,
        'top10': const [
          {
            'rank': 1,
            'userId': 'rival-1',
            'displayName': 'AceWinner',
            'wins': 5,
            'losses': 1,
          },
        ],
        'currentUser': const {
          'rank': 8,
          'displayName': 'Trail Walker',
          'wins': 4,
          'losses': 1,
          'inTop10': false,
          'qualified': true,
        },
      };
    }

    return {
      'top10': const [],
      'currentUser': const {
        'rank': 1,
        'displayName': 'Trail Walker',
        'totalSteps': 1000,
        'inTop10': true,
      },
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
    'auth_step_goal': 8000,
  });

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'MainShell taps a home highlight and opens the matching leaderboard state',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FakeBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: backendApiService,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
            challengeWeekStepSyncService: _FakeChallengeWeekStepSyncService([
              StepData(steps: 9321, date: DateTime.utc(2026, 3, 19)),
            ]),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(backendApiService.fetchLeaderboardHighlightsCalls, 1);
      expect(
        find.text("You're 8th all time in challenges. Keep climbing."),
        findsOneWidget,
      );

      await tester.tap(
        find.text("You're 8th all time in challenges. Keep climbing."),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(backendApiService.leaderboardCalls.last, (
        type: 'challenges',
        period: 'allTime',
      ));
      expect(
        find.text('MINIMUM 5 COMPLETED CHALLENGES TO QUALIFY'),
        findsOneWidget,
      );
    },
  );
}
