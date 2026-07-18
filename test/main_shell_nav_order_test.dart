import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/widgets/wooden_tab_bar.dart';

class _FakeHealthService extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;

  @override
  Future<StepData> getStepsToday() async {
    return StepData(steps: 1234, date: DateTime(2026, 6, 1));
  }

  @override
  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    return const [];
  }
}

class _FakeBackgroundSyncBootstrapService
    extends BackgroundSyncBootstrapService {
  @override
  Future<void> enableHealthKitBackgroundDelivery() async {}
}

class _FakeBackendApiService extends BackendApiService {
  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async {
    return {
      'sessionToken': authToken,
      'user': {'firstRaceOnboardingSeen': true, 'tutorialOnboardingSeen': true},
    };
  }

  @override
  Future<void> recordSteps({
    required String identityToken,
    required StepData stepData,
    bool skipRaceResolution = false,
  }) async {}

  @override
  Future<StepSyncV2Result> recordStepSyncV2({
    required String identityToken,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async => const StepSyncV2Result(kind: StepSyncV2Kind.unsupported);

  @override
  Future<RaceDiscoverySummary> fetchRaceDiscoverySummary({
    required String identityToken,
  }) async => RaceDiscoverySummary.unsupportedResult;

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) async {
    return const {'state': 'EMPTY'};
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async {
    return const [];
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {
      'displayName': 'Trail Walker',
      'incomingFriendRequests': 0,
      'firstRaceOnboardingSeen': true,
      'tutorialOnboardingSeen': true,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async {
    return const {
      'invites': <Map<String, dynamic>>[],
      'waiting': <Map<String, dynamic>>[],
      'active': <Map<String, dynamic>>[],
      'completed': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async {
    return const [];
  }

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    return const {
      'coins': 0,
      'equipped': <String, dynamic>{},
      'items': <Map<String, dynamic>>[],
    };
  }
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_first_race_onboarding_seen': true,
    'auth_tutorial_onboarding_seen': true,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MainShell renders tabs in the primary navigation order', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: _FakeBackendApiService(),
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final tabBar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));
    expect(tabBar.items.map((item) => item.label), [
      'Home',
      'Races',
      'Friends',
      'Boards',
      'Profile',
    ]);
  });
}
