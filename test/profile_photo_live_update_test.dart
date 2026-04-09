import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/challenge_week_step_sync_service.dart';
import 'package:step_tracker/services/health_service.dart';

class _FakeHealthService extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;

  @override
  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async => const [];
}

class _FakeBackgroundSyncBootstrapService
    extends BackgroundSyncBootstrapService {
  @override
  Future<void> enableHealthKitBackgroundDelivery() async {}
}

class _FakeChallengeWeekStepSyncService extends ChallengeWeekStepSyncService {
  _FakeChallengeWeekStepSyncService(this.result);

  final List<StepData> result;

  @override
  Future<List<StepData>> loadCurrentChallengeWeekSteps({
    required String identityToken,
  }) async {
    return result;
  }
}

class _FakeBackendApiService extends BackendApiService {
  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async {
    return {
      'sessionToken': authToken,
      'user': {
        'displayName': 'Trail Walker',
        'stepGoal': 8000,
        'isAdmin': false,
        'coins': 70,
        'heldCoins': 0,
      },
    };
  }

  @override
  Future<void> recordSteps({
    required String identityToken,
    required StepData stepData,
  }) async {}

  @override
  Future<void> recordStepSamples({
    required String identityToken,
    required List<StepSampleData> samples,
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchCurrentChallenge({
    required String identityToken,
  }) async => const {'challenge': null, 'instances': [], 'syncDays': []};

  @override
  Future<Map<String, dynamic>> fetchLeaderboardHighlights({
    required String identityToken,
  }) async => const {'cards': []};

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {
      'stepGoal': 8000,
      'incomingFriendRequests': 0,
      'displayName': 'Trail Walker',
      'email': 'walker@example.com',
      'isAdmin': false,
      'coins': 70,
      'heldCoins': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async => const {'races': []};

  @override
  Future<Map<String, dynamic>> fetchStats({
    required String identityToken,
  }) async {
    return {
      'thisWeek': 12000,
      'thisMonth': 45000,
      'thisYear': 150000,
      'allTime': 300000,
      'streak': 4,
      'wins': 3,
      'losses': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchStepCalendar({
    required String identityToken,
    required String month,
  }) async => const {'days': []};
}

Future<AuthService> _createAuthService({String? profilePhotoUrl}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_step_goal': 8000,
    if (profilePhotoUrl != null) 'auth_profile_photo_url': profilePhotoUrl,
  });

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'MainShell home prompt reacts immediately to profile photo auth changes',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FakeBackendApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: backendApiService,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
            challengeWeekStepSyncService: _FakeChallengeWeekStepSyncService([
              StepData(steps: 2400, date: DateTime.utc(2026, 4, 9)),
            ]),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('ADD A PROFILE PHOTO?'), findsOneWidget);

      await authService.syncFromBackendUser({
        'profilePhotoUrl': 'https://example.com/profile.jpg',
      });
      await tester.pump();

      expect(find.text('ADD A PROFILE PHOTO?'), findsNothing);

      await authService.syncFromBackendUser({'profilePhotoUrl': null});
      await tester.pump();

      expect(find.text('ADD A PROFILE PHOTO?'), findsOneWidget);
    },
  );

  testWidgets(
    'ProfileTab photo controls react immediately to profile photo auth changes',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileTab(
              authService: authService,
              displayName: 'Trail Walker',
              stepGoal: 8000,
              email: 'walker@example.com',
              onSettingsChanged: () {},
              backendApiService: _FakeBackendApiService(),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('ADD PHOTO'), findsOneWidget);
      expect(find.text('REMOVE PHOTO'), findsNothing);

      await authService.syncFromBackendUser({
        'profilePhotoUrl': 'https://example.com/profile.jpg',
      });
      await tester.pump();

      expect(find.text('CHANGE PHOTO'), findsOneWidget);
      expect(find.text('REMOVE PHOTO'), findsOneWidget);

      await authService.syncFromBackendUser({'profilePhotoUrl': null});
      await tester.pump();

      expect(find.text('ADD PHOTO'), findsOneWidget);
      expect(find.text('REMOVE PHOTO'), findsNothing);
    },
  );
}
