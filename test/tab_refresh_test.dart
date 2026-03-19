import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/challenges_tab.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FakeFriendsApi extends BackendApiService {
  int fetchFriendsCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    fetchFriendsCalls += 1;
    return {
      'friends': const [],
      'pending': {'incoming': const [], 'outgoing': const []},
    };
  }
}

class _FakeProfileApi extends BackendApiService {
  int fetchStatsCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchStats({
    required String identityToken,
  }) async {
    fetchStatsCalls += 1;
    return {
      'thisWeek': 12000,
      'thisMonth': 45000,
      'thisYear': 150000,
      'allTime': 300000,
      'streak': 4,
      'wins': 3,
      'losses': 1,
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

Future<void> _pullToRefresh(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 300));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ChallengesTab pull-to-refresh calls the page refresh callback', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    var refreshCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChallengesTab(
            authService: authService,
            currentChallenge: {
              'challenge': {
                'title': 'Summit Sprint',
                'description': 'Outwalk your friend this week.',
              },
              'instances': const [],
            },
            friendsSteps: const [],
            onChallengeChanged: () {},
            onRefresh: () async {
              refreshCalls += 1;
            },
          ),
        ),
      ),
    );

    expect(find.byType(RefreshIndicator), findsOneWidget);

    await _pullToRefresh(tester);

    expect(refreshCalls, 1);
  });

  testWidgets('FriendsTab pull-to-refresh reloads friends and shell state', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    final backendApiService = _FakeFriendsApi();
    var shellRefreshCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendsTab(
            authService: authService,
            friendsSteps: const [],
            currentChallenge: const {'instances': []},
            onFriendsChanged: () {},
            onRefresh: () async {
              shellRefreshCalls += 1;
            },
            backendApiService: backendApiService,
          ),
        ),
      ),
    );

    await tester.pump();
    expect(backendApiService.fetchFriendsCalls, 1);

    await _pullToRefresh(tester);

    expect(backendApiService.fetchFriendsCalls, 2);
    expect(shellRefreshCalls, 1);
  });

  testWidgets(
    'ProfileTab pull-to-refresh reloads profile shell data and stats',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FakeProfileApi();
      var shellRefreshCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileTab(
              authService: authService,
              displayName: 'Trail Walker',
              stepGoal: 8000,
              email: 'walker@example.com',
              onSettingsChanged: () {},
              onRefresh: () async {
                shellRefreshCalls += 1;
              },
              backendApiService: backendApiService,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(backendApiService.fetchStatsCalls, 1);

      await _pullToRefresh(tester);

      expect(backendApiService.fetchStatsCalls, 2);
      expect(shellRefreshCalls, 1);
    },
  );
}
