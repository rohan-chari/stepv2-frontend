import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/screens/tabs/leaderboard_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _NullableLeaderboardApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async => const {'top100': null, 'currentUser': null};
}

class _FriendsCompatibilityApi extends BackendApiService {
  _FriendsCompatibilityApi({this.missingFields = false});

  final bool missingFields;
  int fetchFriendsCalls = 0;
  final List<({String friendshipId, bool accept})> responses = [];
  bool accepted = false;

  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    fetchFriendsCalls += 1;
    if (missingFields) return const {};
    if (accepted) {
      return const {
        'friends': [
          {
            'id': 'friend-1',
            'displayName': 'Hill Climber',
            'friendshipId': 'friendship-1',
          },
        ],
        'pending': {'incoming': [], 'outgoing': []},
      };
    }
    return const {
      'friends': [],
      'pending': {
        'incoming': [
          {
            'friendshipId': 'friendship-1',
            'user': {'id': 'friend-1', 'displayName': 'Hill Climber'},
          },
        ],
        'outgoing': [],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> respondToFriendRequest({
    required String identityToken,
    required String friendshipId,
    required bool accept,
  }) async {
    responses.add((friendshipId: friendshipId, accept: accept));
    accepted = accept;
    return const {};
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpFriends(
  WidgetTester tester,
  BackendApiService api, {
  VoidCallback? onFriendsChanged,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: FriendsTab(
        authService: await _auth(),
        backendApiService: api,
        onFriendsChanged: onFriendsChanged ?? () {},
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '2.3.3',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'LeaderboardTab treats nullable response fields as an empty board',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LeaderboardTab(
              authService: await _auth(),
              backendApiService: _NullableLeaderboardApi(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No steps yet - get walking!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('FriendsTab treats missing roster fields as an empty page', (
    tester,
  ) async {
    await _pumpFriends(tester, _FriendsCompatibilityApi(missingFields: true));

    expect(
      find.text('No friends yet. Search above to invite some.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('FriendsTab reloads the roster after accepting a request', (
    tester,
  ) async {
    final api = _FriendsCompatibilityApi();
    var friendsChangedCalls = 0;
    await _pumpFriends(
      tester,
      api,
      onFriendsChanged: () => friendsChangedCalls += 1,
    );

    expect(api.fetchFriendsCalls, 1);
    expect(find.text('INCOMING REQUESTS'), findsOneWidget);

    await tester.tap(find.text('ACCEPT'));
    await tester.pump();
    await tester.pump();

    expect(api.responses, [(friendshipId: 'friendship-1', accept: true)]);
    expect(api.fetchFriendsCalls, 2);
    expect(friendsChangedCalls, 1);
    expect(find.text('INCOMING REQUESTS'), findsNothing);
    expect(find.text('@Hill Climber'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
