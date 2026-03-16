import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/home_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/health_service.dart';

class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService({required List<Map<String, dynamic>> responses})
    : _responses = responses;

  final List<Map<String, dynamic>> _responses;
  int fetchCurrentChallengeCalls = 0;

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async {
    return {
      'sessionToken': 'session-token',
      'user': {'isAdmin': false},
    };
  }

  @override
  Future<void> recordSteps({
    required String identityToken,
    required StepData stepData,
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async {
    return [];
  }

  @override
  Future<Map<String, dynamic>> fetchCurrentChallenge({
    required String identityToken,
  }) async {
    final index = fetchCurrentChallengeCalls;
    fetchCurrentChallengeCalls += 1;

    if (index >= _responses.length) {
      return _responses.last;
    }

    return _responses[index];
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return {
      'stepGoal': 400,
      'incomingFriendRequests': 0,
      'displayName': 'Rohan',
      'isAdmin': false,
    };
  }
}

class _FakeHealthService extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;

  @override
  Future<StepData> getStepsToday() async {
    return StepData(steps: 1662, date: DateTime(2026, 3, 16));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'apple-token',
      'auth_user_identifier': 'apple-user-123',
      'auth_session_token': 'session-token',
      'auth_step_goal': 400,
      'auth_display_name': 'Rohan',
      'health_authorized': true,
    });
  });

  testWidgets(
    'HomeScreen refreshes current challenge after returning from settings',
    (WidgetTester tester) async {
      final authService = AuthService();
      await authService.restoreSession();
      final backendApiService = _FakeBackendApiService(
        responses: [
          {
            'challenge': {
              'title': 'Day by Day',
              'description': 'Walk steadily through the week.',
            },
            'instances': [],
          },
          {'challenge': null, 'instances': []},
        ],
      );

      await tester.pumpWidget(
        TickerMode(
          enabled: false,
          child: MaterialApp(
            home: HomeScreen(
              authService: authService,
              backendApiService: backendApiService,
              healthService: _FakeHealthService(),
              scheduleBackgroundSync: () async => true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Day by Day'), findsOneWidget);
      expect(backendApiService.fetchCurrentChallengeCalls, 1);

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('SETTINGS'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));

      expect(backendApiService.fetchCurrentChallengeCalls, 2);
      expect(find.text('Day by Day'), findsNothing);
      expect(find.text('THIS WEEK’S CHALLENGE'), findsNothing);
    },
  );
}
