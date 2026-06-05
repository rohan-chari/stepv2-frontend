import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/leaderboard_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Fake that records the scope (plus type/period) the tab requests and returns
/// an empty board for the friends scope so the friends empty state can render.
class _FakeBackendApiService extends BackendApiService {
  final List<({String type, String period, String scope})> leaderboardCalls =
      [];

  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async {
    leaderboardCalls.add((type: type, period: period, scope: scope));

    if (scope == 'friends') {
      // Zero-friends board: empty list, no current-user row.
      return const {'top100': [], 'currentUser': null};
    }

    return {
      'top100': [
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
        {
          'rank': 3,
          'userId': 'third-user',
          'displayName': 'BronzeWalker',
          'totalSteps': 10000,
        },
      ],
      'currentUser': {
        'rank': 2,
        'displayName': 'Trail Walker',
        'totalSteps': 11000,
        'inTop100': true,
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
        displayName: 'Trail Walker',
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LeaderboardTab defaults to the global scope and renders both scope tabs',
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
        (type: 'steps', period: 'today', scope: 'global'),
      ]);
      expect(find.text('GLOBAL'), findsOneWidget);
      expect(find.text('FRIENDS'), findsOneWidget);
    },
  );

  testWidgets(
    'LeaderboardTab keeps the scope tabs visible on the races type',
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
        scope: 'global',
      ));
      expect(find.text('GLOBAL'), findsOneWidget);
      expect(find.text('FRIENDS'), findsOneWidget);
    },
  );

  testWidgets(
    'LeaderboardTab requests the friends scope when the friends tab is tapped',
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

      await tester.tap(find.text('FRIENDS'));
      await tester.pump();

      expect(backendApiService.leaderboardCalls.last, (
        type: 'steps',
        period: 'today',
        scope: 'friends',
      ));
    },
  );

  testWidgets(
    'LeaderboardTab shows the add-friends empty state on an empty friends board',
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

      await tester.tap(find.text('FRIENDS'));
      await tester.pump();

      expect(
        find.text('No friends on the board yet. Add some to compete!'),
        findsOneWidget,
      );
      // The global steps empty title must not appear on the friends scope.
      expect(find.text('No steps yet - get walking!'), findsNothing);
    },
  );
}
