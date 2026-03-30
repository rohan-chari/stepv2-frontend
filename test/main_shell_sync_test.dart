import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/challenge_week_step_sync_service.dart';
import 'package:step_tracker/services/health_service.dart';

class _FakeHealthService extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;
}

class _FakeBackgroundSyncBootstrapService
    extends BackgroundSyncBootstrapService {
  int enableCalls = 0;

  @override
  Future<void> enableHealthKitBackgroundDelivery() async {
    enableCalls += 1;
  }
}

class _FakeChallengeWeekStepSyncService extends ChallengeWeekStepSyncService {
  _FakeChallengeWeekStepSyncService(this.result);

  final List<StepData> result;
  int loadCalls = 0;

  @override
  Future<List<StepData>> loadCurrentChallengeWeekSteps({
    required String identityToken,
  }) async {
    loadCalls += 1;
    return result;
  }
}

class _FakeBackendApiService extends BackendApiService {
  final List<StepData> recordedSteps = [];

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async {
    return {
      'sessionToken': authToken,
      'user': {'isAdmin': false, 'coins': 60},
    };
  }

  @override
  Future<void> recordSteps({
    required String identityToken,
    required StepData stepData,
  }) async {
    recordedSteps.add(stepData);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async {
    return const [];
  }

  @override
  Future<Map<String, dynamic>> fetchCurrentChallenge({
    required String identityToken,
  }) async {
    return const {'challenge': null, 'instances': [], 'syncDays': []};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {
      'stepGoal': 8000,
      'incomingFriendRequests': 0,
      'displayName': 'Trail Walker',
      'email': 'walker@example.com',
      'isAdmin': false,
      'coins': 70,
    };
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_step_goal': 8000,
  });

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('coins are refreshed from fetchMe after step sync', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'apple-token',
      'auth_user_identifier': 'apple-user-123',
      'auth_session_token': 'session-token',
      'auth_backend_user_id': 'user-1',
      'auth_coins': 60,
    });

    final authService = AuthService();
    await authService.restoreSession();
    expect(authService.coins, 60);

    final backendApiService = _FakeBackendApiService();
    final challengeWeekStepSyncService = _FakeChallengeWeekStepSyncService([
      StepData(steps: 9000, date: DateTime.utc(2026, 3, 29)),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: backendApiService,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
          challengeWeekStepSyncService: challengeWeekStepSyncService,
        ),
      ),
    );

    // Let _restoreAndFetch complete including fire-and-forget _refreshStepGoal
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // fetchMe returned coins: 70 — _refreshStepGoal should have updated them
    expect(authService.coins, 70);
  });

  testWidgets('MainShell posts the full challenge week on initial sync', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();
    final backendApiService = _FakeBackendApiService();
    final challengeWeekStepSyncService = _FakeChallengeWeekStepSyncService([
      StepData(steps: 4100, date: DateTime.utc(2026, 3, 17)),
      StepData(steps: 8765, date: DateTime.utc(2026, 3, 18)),
      StepData(steps: 9321, date: DateTime.utc(2026, 3, 19)),
    ]);
    final bootstrapService = _FakeBackgroundSyncBootstrapService();

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: backendApiService,
          backgroundSyncBootstrapService: bootstrapService,
          challengeWeekStepSyncService: challengeWeekStepSyncService,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(bootstrapService.enableCalls, 1);
    expect(challengeWeekStepSyncService.loadCalls, 1);
    expect(backendApiService.recordedSteps, [
      isA<StepData>()
          .having((stepData) => stepData.steps, 'steps', 4100)
          .having(
            (stepData) => stepData.date,
            'date',
            DateTime.utc(2026, 3, 17),
          ),
      isA<StepData>()
          .having((stepData) => stepData.steps, 'steps', 8765)
          .having(
            (stepData) => stepData.date,
            'date',
            DateTime.utc(2026, 3, 18),
          ),
      isA<StepData>()
          .having((stepData) => stepData.steps, 'steps', 9321)
          .having(
            (stepData) => stepData.date,
            'date',
            DateTime.utc(2026, 3, 19),
          ),
    ]);
  });
}
