import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/arcade_page.dart';

class _FakeFriendsApi extends BackendApiService {
  _FakeFriendsApi({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.searchResults = const [],
  });

  final List<Map<String, dynamic>> friends;
  final List<Map<String, dynamic>> incoming;
  final List<Map<String, dynamic>> outgoing;
  final List<Map<String, dynamic>> searchResults;
  int fetchFriendsCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    fetchFriendsCalls += 1;
    return {
      'friends': friends,
      'pending': {'incoming': incoming, 'outgoing': outgoing},
    };
  }

  @override
  Future<List<Map<String, dynamic>>> searchUsers({
    required String identityToken,
    required String query,
  }) async {
    return searchResults;
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

  testWidgets('FriendsTab has route chrome when opened directly', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsTab(
          authService: authService,
          onFriendsChanged: () {},
          backendApiService: _FakeFriendsApi(),
          displayName: 'Trail Walker',
        ),
      ),
    );

    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ArcadePageBackground), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    final displayNameContext = tester.element(find.text('@Trail Walker').first);
    expect(
      DefaultTextStyle.of(displayNameContext).style.decoration,
      isNot(TextDecoration.underline),
    );
  });

  testWidgets('FriendsTab labels existing friends in search results', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsTab(
          authService: authService,
          onFriendsChanged: () {},
          backendApiService: _FakeFriendsApi(
            friends: const [
              {
                'id': 'friend-1',
                'displayName': 'Hill Climber',
                'friendshipId': 'friendship-1',
              },
            ],
            searchResults: const [
              {'id': 'friend-1', 'displayName': 'Hill Climber'},
            ],
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Hill');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('FRIENDS'), findsOneWidget);
    expect(find.text('ADD'), findsNothing);
  });

  testWidgets('FriendsTab labels pending requests in search results', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsTab(
          authService: authService,
          onFriendsChanged: () {},
          backendApiService: _FakeFriendsApi(
            incoming: const [
              {
                'friendshipId': 'friendship-1',
                'user': {'id': 'friend-1', 'displayName': 'Hill Climber'},
              },
            ],
            outgoing: const [],
            searchResults: const [
              {'id': 'friend-1', 'displayName': 'Hill Climber'},
            ],
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Walk');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('ADD'), findsNothing);
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
