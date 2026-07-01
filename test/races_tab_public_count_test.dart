import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 125,
    'auth_held_coins': 0,
  });

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'PUBLIC RACES button shows the public-races count and still navigates',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RacesTab(
              authService: authService,
              racesData: const {'active': [], 'pending': [], 'completed': []},
              friendsSteps: const [],
              onRacesChanged: _noop,
              displayName: 'Trail Walker',
              publicRacesCount: 3,
            ),
          ),
        ),
      );
      await tester.pump();

      // Count is rendered inline in the button label.
      expect(find.text('PUBLIC RACES (3)'), findsOneWidget);

      // Tapping still pushes the public-races screen.
      await tester.tap(find.text('PUBLIC RACES (3)'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PublicRacesScreen), findsOneWidget);
    },
  );

  testWidgets('PUBLIC RACES button defaults the count to (0) when unset', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RacesTab(
            authService: authService,
            racesData: const {'active': [], 'pending': [], 'completed': []},
            friendsSteps: const [],
            onRacesChanged: _noop,
            displayName: 'Trail Walker',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('PUBLIC RACES (0)'), findsOneWidget);
  });
}

Future<void> _noop() async {}
