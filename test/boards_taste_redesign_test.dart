import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/leaderboard_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _Api extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async => const {'top100': [], 'currentUser': null};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

void main() {
  testWidgets('Boards uses a compact single-row arcade header', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeaderboardTab(
            authService: await _auth(),
            backendApiService: _Api(),
          ),
        ),
      ),
    );
    await tester.pump();

    final title = find.byKey(const Key('boards-header-title'));
    final period = find.byKey(const Key('boards-period-filter'));
    expect(find.text('BOARDS'), findsOneWidget);
    expect(find.text('LEADERBOARD'), findsNothing);
    expect(title, findsOneWidget);
    expect(period, findsOneWidget);
    expect(tester.getCenter(title).dy, tester.getCenter(period).dy);
    expect(find.text('PRIVACY'), findsNothing);
    expect(find.text('Hide me from the global leaderboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
