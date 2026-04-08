import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/admin_challenge_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FakeBackendApiService extends BackendApiService {
  int fetchAdminWeeklyChallengeCalls = 0;
  int resetAdminWeeklyChallengeCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchAdminWeeklyChallenge({
    required String identityToken,
  }) async {
    fetchAdminWeeklyChallengeCalls += 1;
    return {
      'weeklyChallenge': {
        'id': 'weekly-1',
        'weekOf': '2026-03-16',
        'resolvedAt': '2026-03-20T14:00:00.000Z',
        'challenge': {'id': 'challenge-1', 'title': 'Beat Your Partner'},
      },
      'instances': const [],
      'instanceCounts': {
        'total': 0,
        'pendingStake': 0,
        'active': 0,
        'completed': 0,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> resetAdminWeeklyChallenge({
    required String identityToken,
  }) async {
    resetAdminWeeklyChallengeCalls += 1;
    return {
      'reset': true,
      'deletedInstances': 0,
      'weeklyChallenge': {
        'id': 'weekly-1',
        'weekOf': '2026-03-16',
        'resolvedAt': null,
        'challenge': {'id': 'challenge-1', 'title': 'Beat Your Partner'},
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'apple-token',
      'auth_user_identifier': 'apple-user-123',
      'auth_session_token': 'session-token',
      'auth_is_admin': true,
    });
  });

  testWidgets('AdminChallengeScreen resets the current week from admin tools', (
    WidgetTester tester,
  ) async {
    final authService = AuthService();
    await authService.restoreSession();
    final backendApiService = _FakeBackendApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: AdminChallengeScreen(
          authService: authService,
          backendApiService: backendApiService,
          showToast: (_, _) {},
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('RESET CURRENT WEEK'), findsOneWidget);
    expect(backendApiService.fetchAdminWeeklyChallengeCalls, 1);

    await tester.ensureVisible(find.text('RESET CURRENT WEEK'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('RESET CURRENT WEEK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(backendApiService.resetAdminWeeklyChallengeCalls, 1);
    expect(backendApiService.fetchAdminWeeklyChallengeCalls, 2);
  });

  testWidgets(
    'AdminChallengeScreen exposes test info and error toast buttons',
    (WidgetTester tester) async {
      final authService = AuthService();
      await authService.restoreSession();
      final backendApiService = _FakeBackendApiService();
      final infoMessages = <String>[];
      final errorMessages = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: AdminChallengeScreen(
            authService: authService,
            backendApiService: backendApiService,
            showInfoToast: (_, message) {
              infoMessages.add(message);
            },
            showErrorToast: (_, message) {
              errorMessages.add(message);
            },
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.ensureVisible(find.text('TEST INFO TOAST'));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('TEST INFO TOAST'));
      await tester.pump();
      await tester.tap(find.text('TEST ERROR TOAST'));
      await tester.pump();

      expect(infoMessages, ['This is a test notification toast.']);
      expect(errorMessages, ['This is a test error toast.']);
    },
  );
}
