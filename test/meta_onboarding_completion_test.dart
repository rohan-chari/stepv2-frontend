import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/widgets/wooden_tab_bar.dart';

class _FakeHealthService extends HealthService {
  _FakeHealthService({this.restored = false});

  bool restored;
  final setupResults = const [HealthSetupResult.authorized];
  final probeSteps = 0;
  int setupCalls = 0;
  int probeCalls = 0;
  int settingsCalls = 0;

  @override
  Future<bool> restoreHealthAuthState() async => restored;

  @override
  Future<HealthSetupResult> setUpHealthAccess() async {
    final result = setupResults[setupCalls.clamp(0, setupResults.length - 1)];
    setupCalls += 1;
    return result;
  }

  @override
  Future<int> probeTrailingSteps({int days = 7}) async {
    probeCalls += 1;
    return probeSteps;
  }

  @override
  Future<bool> openPlatformHealthSettings() async {
    settingsCalls += 1;
    return true;
  }

  @override
  Future<StepData> getStepsToday() async =>
      StepData(steps: 1234, date: DateTime(2026, 7, 26));

  @override
  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async => const [];
}

class _FakeBackgroundSync extends BackgroundSyncBootstrapService {
  @override
  Future<void> enableHealthKitBackgroundDelivery() async {}
}

class _FakeBackendApiService extends BackendApiService {
  bool failMarker = false;
  @override
  Future<void> markFirstRaceOnboardingSeen({
    required String identityToken,
  }) async {
    if (failMarker) throw const ApiException('offline');
  }

  @override
  Future<void> markTutorialOnboardingSeen({
    required String identityToken,
  }) async {}
  @override
  Future<Map<String, dynamic>> claimTutorialReward({
    required String identityToken,
  }) async => {'granted': false};
  AuthService? authService;

  Map<String, dynamic> get _featureFlags => {
    'onboardingV2Enabled': authService?.onboardingV2Enabled ?? false,
    'onboardingV3Enabled': authService?.onboardingV3Enabled ?? false,
    'tutorialMandatoryEnabled': authService?.tutorialMandatoryEnabled ?? false,
    'customRaceWindowEnabled': authService?.customRaceWindowEnabled ?? false,
    'setupInviteCodePromptEnabled':
        authService?.setupInviteCodePromptEnabled ?? false,
    'stepSampleBucketMinutes': authService?.stepSampleBucketMinutes ?? 60,
  };

  @override
  Future<Map<String, dynamic>?> fetchInviterRace({
    required String identityToken,
  }) async => null;

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async => {
    'sessionToken': authToken,
    'user': {'featureFlags': _featureFlags},
  };

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
    bool homePull = false,
  }) async => const StepSyncV2Result(kind: StepSyncV2Kind.unsupported);

  @override
  Future<RaceDiscoverySummary> fetchRaceDiscoverySummary({
    required String identityToken,
  }) async => RaceDiscoverySummary.unsupportedResult;

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) async => const {'state': 'EMPTY'};

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      {
        'displayName': 'Trail Walker',
        'incomingFriendRequests': 0,
        'featureFlags': _featureFlags,
      };

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async => const {
    'invites': <Map<String, dynamic>>[],
    'waiting': <Map<String, dynamic>>[],
    'active': <Map<String, dynamic>>[],
    'completed': <Map<String, dynamic>>[],
  };

  @override
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => const {
    'coins': 0,
    'equipped': <String, dynamic>{},
    'items': <Map<String, dynamic>>[],
  };

  @override
  Future<void> sendActivationEvents({
    required String identityToken,
    required List<Map<String, dynamic>> events,
  }) async {
    throw const ApiException('offline');
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<AuthService> _mount(
  WidgetTester tester,
  _FakeBackendApiService api, {
  bool completed = false,
  bool tutorialSeen = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'apple',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'health_authorized': true,
    'auth_first_race_onboarding_seen': completed,
    'auth_tutorial_onboarding_seen': tutorialSeen,
    'auth_onboarding_v2_enabled': true,
    'auth_onboarding_v3_enabled': true,
  });
  final auth = AuthService(backendApiService: api);
  await auth.restoreSession();
  api.authService = auth;
  await tester.pumpWidget(
    MaterialApp(
      home: MainShell(
        authService: auth,
        backendApiService: api,
        healthService: _FakeHealthService(restored: true),
        backgroundSyncBootstrapService: _FakeBackgroundSync(),
      ),
    ),
  );
  await _frames(tester);
  return auth;
}

void main() {
  const channel = MethodChannel('com.steptracker/meta_app_events');
  final events = <Object?>[];
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    events.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'logEvent') events.add(call.arguments);
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  for (final markerFails in [false, true]) {
    testWidgets(
      'real final onboarding CTA reports once (markerFails=$markerFails)',
      (tester) async {
        final api = _FakeBackendApiService()..failMarker = markerFails;
        final auth = await _mount(tester, api);
        expect(find.text('FIND A RACE'), findsOneWidget);
        expect(events, isEmpty);
        final finalStep = tester.widget<OnboardingFlow>(
          find.byType(OnboardingFlow),
        );
        await tester.tap(find.text('FIND A RACE'));
        await _frames(tester);
        expect(auth.firstRaceOnboardingSeen, isTrue);
        expect(find.byType(OnboardingFlow), findsNothing);
        expect(find.byType(WoodenTabBar), findsOneWidget);
        expect(events, [
          {'event': 'onboardingCompleted'},
        ]);
        finalStep.onSkipFirstRace();
        await auth.updateCoins(12);
        await _frames(tester);
        expect(events, [
          {'event': 'onboardingCompleted'},
        ]);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }
  testWidgets(
    'finishing the teaching step does not report before the final gate',
    (tester) async {
      final auth = await _mount(
        tester,
        _FakeBackendApiService(),
        tutorialSeen: false,
      );
      expect(
        find.byKey(const Key('onboarding-demo-race-skip')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('onboarding-demo-race-skip')));
      await _frames(tester);
      expect(auth.tutorialOnboardingSeen, isTrue);
      expect(auth.firstRaceOnboardingSeen, isFalse);
      expect(events, isEmpty);
      expect(find.text('FIND A RACE'), findsOneWidget);
      await tester.tap(find.text('FIND A RACE'));
      await _frames(tester);
      expect(events, [
        {'event': 'onboardingCompleted'},
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
  testWidgets(
    'existing login and tutorial replay reward never report onboarding',
    (tester) async {
      final auth = await _mount(
        tester,
        _FakeBackendApiService(),
        completed: true,
      );
      expect(find.byType(OnboardingFlow), findsNothing);
      expect(find.byType(WoodenTabBar), findsOneWidget);
      expect(events, isEmpty);
      // Settings tutorial replays use this real AuthService reward path; they do
      // not clear an onboarding gate in the host.
      await auth.claimTutorialReward();
      await auth.updateCoins(4);
      await _frames(tester);
      expect(events, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
