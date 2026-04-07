import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/leaderboard_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FakeBackendApiService extends BackendApiService {
  final List<({String type, String period})> leaderboardCalls = [];

  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
  }) async {
    leaderboardCalls.add((type: type, period: period));

    switch (type) {
      case 'challenges':
        return {
          'minimumCompletedChallenges': 5,
          'top10': [
            {
              'rank': 1,
              'userId': 'challenge-1',
              'displayName': 'AceWinner',
              'wins': 5,
              'losses': 1,
              'completedCount': 6,
              'winPercentage': 0.8333333333,
            },
            {
              'rank': 2,
              'userId': 'challenge-2',
              'displayName': 'BlazeRun',
              'wins': 4,
              'losses': 1,
              'completedCount': 5,
              'winPercentage': 0.8,
            },
          ],
          'currentUser': {
            'rank': null,
            'displayName': 'Trail Walker',
            'wins': 4,
            'losses': 0,
            'completedCount': 4,
            'winPercentage': 1.0,
            'inTop10': false,
            'qualified': false,
          },
        };
      case 'races':
        return {
          'top10': [
            {
              'rank': 1,
              'userId': 'race-1',
              'displayName': 'AtlasRun',
              'firsts': 1,
              'seconds': 1,
              'thirds': 0,
            },
            {
              'rank': 2,
              'userId': 'user-1',
              'displayName': 'Trail Walker',
              'firsts': 1,
              'seconds': 0,
              'thirds': 2,
            },
          ],
          'currentUser': {
            'rank': 2,
            'displayName': 'Trail Walker',
            'firsts': 1,
            'seconds': 0,
            'thirds': 2,
            'inTop10': true,
          },
        };
      case 'steps':
      default:
        return {
          'top10': [
            {
              'rank': 1,
              'userId': 'other-user',
              'displayName': 'AceWinner',
              'totalSteps': 12000,
            },
            {
              'rank': 2,
              'userId': 'user-1',
              'displayName': 'Trail Walker',
              'totalSteps': 11000,
            },
          ],
          'currentUser': {
            'rank': 2,
            'displayName': 'Trail Walker',
            'totalSteps': 11000,
            'inTop10': true,
          },
        };
    }
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

Widget _buildLeaderboard({
  required AuthService authService,
  required BackendApiService backendApiService,
}) {
  return MaterialApp(
    home: Scaffold(
      body: LeaderboardTab(
        authService: authService,
        backendApiService: backendApiService,
        stepData: StepData(steps: 6543, date: DateTime(2026, 4, 7)),
        stepGoal: 8000,
        displayName: 'Trail Walker',
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LeaderboardTab defaults to steps with the period filter visible',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FakeBackendApiService();

      await tester.pumpWidget(
        _buildLeaderboard(
          authService: authService,
          backendApiService: backendApiService,
        ),
      );
      await tester.pump();

      expect(backendApiService.leaderboardCalls, [
        (type: 'steps', period: 'today'),
      ]);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('STEPS'), findsAtLeastNWidgets(1));
      expect(find.text('12.0k'), findsOneWidget);
    },
  );

  testWidgets(
    'LeaderboardTab shows the challenge qualification note and W-L rows',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FakeBackendApiService();

      await tester.pumpWidget(
        _buildLeaderboard(
          authService: authService,
          backendApiService: backendApiService,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('CHALLENGES'));
      await tester.pump();

      expect(backendApiService.leaderboardCalls.last, (
        type: 'challenges',
        period: 'allTime',
      ));
      expect(
        find.text('MINIMUM 5 COMPLETED CHALLENGES TO QUALIFY'),
        findsOneWidget,
      );
      expect(find.text('W-L'), findsOneWidget);
      expect(find.text('5-1'), findsOneWidget);
      expect(find.text('4-0'), findsOneWidget);
      expect(find.text('TODAY'), findsNothing);
    },
  );

  testWidgets(
    'LeaderboardTab shows race podium counts and hides the period filter',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FakeBackendApiService();

      await tester.pumpWidget(
        _buildLeaderboard(
          authService: authService,
          backendApiService: backendApiService,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('RACES'));
      await tester.pump();

      expect(backendApiService.leaderboardCalls.last, (
        type: 'races',
        period: 'allTime',
      ));
      expect(find.text('1ST 1  2ND 1  3RD 0'), findsOneWidget);
      expect(find.text('1ST 1  2ND 0  3RD 2'), findsOneWidget);
      expect(find.text('TODAY'), findsNothing);
    },
  );
}
