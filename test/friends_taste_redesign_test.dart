import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _Api extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async => const {
    'friends': [],
    'pending': {'incoming': [], 'outgoing': []},
  };
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

void main() {
  testWidgets('Friends pairs primary search with compact invite action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: FriendsTab(
          authService: await _auth(),
          backendApiService: _Api(),
          onFriendsChanged: () {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Find your crew and watch them climb the leaderboard.'),
      findsNothing,
    );
    expect(find.widgetWithText(TextField, 'Search friends'), findsOneWidget);

    final search = find.byKey(const Key('friends-search-control'));
    final invite = find.byKey(const Key('friends-invite-action'));
    expect(search, findsOneWidget);
    expect(invite, findsOneWidget);
    expect(tester.getSize(invite).width, 58);
    expect(tester.getSize(invite).height, tester.getSize(search).height);
    expect(tester.getSize(invite).height, greaterThanOrEqualTo(48));
    expect(tester.getTopLeft(search).dy, tester.getTopLeft(invite).dy);
    expect(tester.getRect(search).bottom, tester.getRect(invite).bottom);
    expect(
      find.bySemanticsLabel('Invite friends and earn coins'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
