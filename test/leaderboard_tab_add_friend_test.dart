import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/leaderboard_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FakeBackendApiService extends BackendApiService {
  int fetchFriendsCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
  }) async {
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
      ],
      'currentUser': {
        'rank': 2,
        'userId': 'user-1',
        'displayName': 'Trail Walker',
        'totalSteps': 11000,
        'inTop100': true,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    fetchFriendsCalls += 1;
    // Stranger: not a friend, no pending requests.
    return {
      'friends': const [],
      'pending': {'incoming': const [], 'outgoing': const []},
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
    'tapping another player opens the friendship-aware sheet (ADD FRIEND)',
    (tester) async {
      final authService = await _createAuthService();
      final api = _FakeBackendApiService();

      await tester.pumpWidget(
        _buildLeaderboard(authService: authService, backendApiService: api),
      );
      await tester.pump();

      await tester.tap(find.text('AceWinner'));
      // Drive the modal-sheet route transition + the fetchFriends future
      // without pumpAndSettle (the leaderboard's refresh progress bar can
      // animate indefinitely and would time pumpAndSettle out).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(api.fetchFriendsCalls, 1);
      expect(find.text('ADD FRIEND'), findsOneWidget);
    },
  );

  testWidgets('tapping your own row does not open an add-friend sheet', (
    tester,
  ) async {
    final authService = await _createAuthService();
    final api = _FakeBackendApiService();

    await tester.pumpWidget(
      _buildLeaderboard(authService: authService, backendApiService: api),
    );
    await tester.pump();

    await tester.tap(find.text('Trail Walker').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.fetchFriendsCalls, 0);
    expect(find.text('ADD FRIEND'), findsNothing);
  });
}
