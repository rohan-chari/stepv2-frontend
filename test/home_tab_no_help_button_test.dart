import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// Item 8: the hero "?" help button was removed (the sun baked into the sky PNG
// covered it). Help/tutorial stays reachable from the Profile tab, so nothing is
// orphaned. This asserts the icon no longer renders on the home hero.
//
// NOTE: this directly contradicts the pre-existing assertion in
// home_tab_no_add_friends_test.dart ("The help button stays" → findsOneWidget),
// which is now outdated by this approved change. Per repo rules that existing
// test is left untouched and flagged for Rohan to invert.

class _FakeBackendApiService extends BackendApiService {}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_profile_photo_url': 'https://example.com/p.png',
    'auth_profile_photo_prompt_dismissed_at': '2026-04-08T12:00:00.000Z',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home hero no longer renders the "?" help button',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final authService = await _createAuthService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTab(
            stepData: StepData(steps: 2400, date: DateTime(2026, 6, 5)),
            isLoading: false,
            error: null,
            healthAuthorized: true,
            notificationsState: true,
            displayName: 'Trail Walker',
            authService: authService,
            backendApiService: _FakeBackendApiService(),
            onRefresh: () async {},
            onEnableHealth: () {},
            onEnableNotifications: () {},
            onDisplayNameChanged: () {},
            friendsSteps: const [],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.help_outline_rounded), findsNothing);
  });
}
