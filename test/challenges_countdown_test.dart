import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/challenges_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ChallengesTab shows a live countdown for the weekly challenge', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    var now = DateTime(2026, 3, 19, 12, 0, 0);
    final endsAt = DateTime(2026, 3, 20, 13, 2, 5);

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
              'endsAt': endsAt.toUtc().toIso8601String(),
              'instances': const [],
            },
            friendsSteps: const [],
            onChallengeChanged: () {},
            now: () => now,
          ),
        ),
      ),
    );

    expect(find.text('CHALLENGE ENDS IN'), findsOneWidget);
    expect(find.text('1D 1H 2M 5S'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('1D 1H 2M 4S'), findsOneWidget);
  });
}
