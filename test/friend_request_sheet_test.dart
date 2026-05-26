import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/friend_request_sheet.dart';

/// Fake backend that returns the `/friends` payload in the shape the real
/// backend uses (see backend `src/queries/getFriends.js`): accepted friends
/// carry a top-level `id`, while pending requests nest the other person under
/// `user: { id, ... }`.
class _FakeFriendsApi extends BackendApiService {
  int fetchFriendsCalls = 0;
  List<Map<String, dynamic>> friends = const [];
  List<Map<String, dynamic>> incoming = const [];
  List<Map<String, dynamic>> outgoing = const [];

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
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'me-1',
    'auth_display_name': 'Trail Walker',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _openSheet(
  WidgetTester tester, {
  required AuthService authService,
  required BackendApiService api,
  required String userId,
  required String displayName,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showFriendRequestSheet(
                context: context,
                authService: authService,
                backendApiService: api,
                userId: userId,
                displayName: displayName,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows FRIENDS for a user already in the friends list (top-level id)',
    (tester) async {
      final authService = await _createAuthService();
      final api = _FakeFriendsApi()
        ..friends = [
          {
            'id': 'friend-1',
            'displayName': 'Buddy',
            'friendshipId': 'fr-1',
          },
        ];

      await _openSheet(
        tester,
        authService: authService,
        api: api,
        userId: 'friend-1',
        displayName: 'Buddy',
      );

      expect(find.text('FRIENDS'), findsOneWidget);
      expect(find.text('ADD FRIEND'), findsNothing);
    },
  );

  testWidgets(
    'shows REQUESTED for a user with an outgoing pending request (nested user.id)',
    (tester) async {
      final authService = await _createAuthService();
      final api = _FakeFriendsApi()
        ..outgoing = [
          {
            'friendshipId': 'fr-2',
            'user': {'id': 'pending-1', 'displayName': 'Pending Pal'},
          },
        ];

      await _openSheet(
        tester,
        authService: authService,
        api: api,
        userId: 'pending-1',
        displayName: 'Pending Pal',
      );

      expect(find.text('REQUESTED'), findsOneWidget);
      expect(find.text('ADD FRIEND'), findsNothing);
    },
  );

  testWidgets(
    'shows ACCEPT REQUEST for a user with an incoming pending request',
    (tester) async {
      final authService = await _createAuthService();
      final api = _FakeFriendsApi()
        ..incoming = [
          {
            'friendshipId': 'fr-3',
            'user': {'id': 'incoming-1', 'displayName': 'New Friend'},
          },
        ];

      await _openSheet(
        tester,
        authService: authService,
        api: api,
        userId: 'incoming-1',
        displayName: 'New Friend',
      );

      expect(find.text('ACCEPT REQUEST'), findsOneWidget);
      expect(find.text('ADD FRIEND'), findsNothing);
    },
  );

  testWidgets('shows ADD FRIEND for a stranger', (tester) async {
    final authService = await _createAuthService();
    final api = _FakeFriendsApi()
      ..friends = [
        {'id': 'friend-1', 'displayName': 'Buddy', 'friendshipId': 'fr-1'},
      ];

    await _openSheet(
      tester,
      authService: authService,
      api: api,
      userId: 'stranger-1',
      displayName: 'Stranger',
    );

    expect(find.text('ADD FRIEND'), findsOneWidget);
    expect(find.text('FRIENDS'), findsNothing);
  });

  testWidgets('shows "That\'s you!" for your own row without a fetch', (
    tester,
  ) async {
    final authService = await _createAuthService();
    final api = _FakeFriendsApi();

    await _openSheet(
      tester,
      authService: authService,
      api: api,
      userId: 'me-1',
      displayName: 'Trail Walker',
    );

    expect(find.text("That's you!"), findsOneWidget);
    expect(find.text('ADD FRIEND'), findsNothing);
    expect(api.fetchFriendsCalls, 0);
  });
}
