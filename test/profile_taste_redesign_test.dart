import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _Api extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchStats({
    required String identityToken,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> fetchStepCalendar({
    required String identityToken,
    required String month,
  }) async => const {'days': []};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'VeryLongArcadeRunnerName',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

void main() {
  testWidgets('Profile keeps identity primary and Settings compact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileTab(
            authService: await _auth(),
            displayName: 'VeryLongArcadeRunnerName',
            email: 'averylongarcaderunner@example.com',
            backendApiService: _Api(),
            onSettingsChanged: () {},
            showBackButton: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Your streak, your stats, and a quick way to manage the basics.',
      ),
      findsNothing,
    );
    final settings = find.byKey(const Key('profile-settings-action'));
    expect(settings, findsOneWidget);
    expect(tester.getSize(settings), const Size(58, 58));
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
