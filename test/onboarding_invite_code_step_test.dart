import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/services/onboarding_state_service.dart';

/// Regression coverage for removing invite-code entry from onboarding while
/// retaining its device/auth state compatibility for the relocated Home prompt.

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _FakeHealthService extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;

  @override
  Future<HealthSetupResult> setUpHealthAccess() async =>
      HealthSetupResult.authorized;

  @override
  Future<int> probeTrailingSteps({int days = 7}) async => 500;

  @override
  Future<bool> openPlatformHealthSettings() async => true;

  @override
  Future<StepData> getStepsToday() async =>
      StepData(steps: 1234, date: DateTime(2026, 8, 9));

  @override
  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async => const [];
}

class _FakeBackgroundSync extends BackgroundSyncBootstrapService {}

class _FakeApi extends BackendApiService {
  _FakeApi({this.redeemResult});

  final Map<String, dynamic>? redeemResult;
  int redeemCalls = 0;
  int inviterRaceCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchReferralStatus({
    required String identityToken,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> redeemReferralCode({
    required String identityToken,
    required String code,
  }) async {
    redeemCalls += 1;
    final result = redeemResult;
    if (result == null) throw const ApiException('offline');
    return result;
  }

  @override
  Future<Map<String, dynamic>?> fetchInviterRace({
    required String identityToken,
  }) async {
    inviterRaceCalls += 1;
    return null;
  }

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async => {'sessionToken': authToken, 'user': const <String, dynamic>{}};

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
      const {'displayName': 'Trail Walker', 'incomingFriendRequests': 0};

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

Map<String, Object> _prefs({
  bool v3 = true,
  bool authPayloadApplied = true,
  String? referredByCode,
  bool? inviteCodeEnabled,
  bool inviteStepDone = false,
}) {
  return {
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_first_race_onboarding_seen': false,
    'auth_tutorial_onboarding_seen': false,
    'auth_onboarding_v2_enabled': true,
    if (v3) 'auth_onboarding_v3_enabled': true,
    if (authPayloadApplied) 'auth_payload_applied': true,
    'auth_referred_by_code': ?referredByCode,
    'auth_onboarding_invite_code_enabled': ?inviteCodeEnabled,
    if (inviteStepDone) OnboardingStateService.keyInviteCodeStepDone: true,
    'health_authorized': true,
  };
}

Future<AuthService> _auth(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required AuthService auth,
  BackendApiService? api,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MainShell(
        authService: auth,
        healthService: _FakeHealthService(),
        backendApiService: api ?? _FakeApi(),
        backgroundSyncBootstrapService: _FakeBackgroundSync(),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<List<String>> _queuedEventNames() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('activation_events_v1');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .cast<Map>()
      .map((e) => e['name'].toString())
      .toList();
}

final _demoRace = find.byKey(const Key('onboarding-demo-race-start'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Known trap: without this, PackageInfo.fromPlatform() never resolves in
    // the fake-async zone and anything touching analytics hangs.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
  });
  // -------------------------------------------------------------------------
  // Item 7 (show condition) + item 9 (AuthService), through the real host
  // -------------------------------------------------------------------------

  group('show condition (MainShell)', () {
    testWidgets('v3 onboarding no longer shows invite entry', (tester) async {
      final auth = await _auth(_prefs());
      await _pumpShell(tester, auth: auth);

      expect(find.text('GOT AN INVITE CODE?'), findsNothing);
      expect(_demoRace, findsOneWidget);
      expect(
        await _queuedEventNames(),
        isNot(contains('invite_code_step_shown')),
        reason: 'removed onboarding placement must not emit an impression',
      );
    });

    testWidgets('legacy persisted ON value cannot resurrect the removed step', (
      tester,
    ) async {
      final auth = await _auth(_prefs(inviteCodeEnabled: true));
      await _pumpShell(tester, auth: auth);

      expect(find.text('GOT AN INVITE CODE?'), findsNothing);
      expect(_demoRace, findsOneWidget);
    });

    testWidgets('hidden when the account is already attributed', (
      tester,
    ) async {
      final auth = await _auth(_prefs(referredByCode: 'BARA-FRND'));
      await _pumpShell(tester, auth: auth);

      expect(find.text('GOT AN INVITE CODE?'), findsNothing);
      expect(_demoRace, findsOneWidget);
    });

    testWidgets('hidden when the kill switch is off', (tester) async {
      final auth = await _auth(_prefs(inviteCodeEnabled: false));
      await _pumpShell(tester, auth: auth);

      expect(find.text('GOT AN INVITE CODE?'), findsNothing);
      expect(_demoRace, findsOneWidget);
    });

    testWidgets('hidden under v3-off (the step lives in the v3 branch only)', (
      tester,
    ) async {
      final auth = await _auth(_prefs(v3: false));
      await _pumpShell(tester, auth: auth);

      expect(find.text('GOT AN INVITE CODE?'), findsNothing);
    });

    testWidgets('hidden once the local done-flag is set', (tester) async {
      final auth = await _auth(_prefs(inviteStepDone: true));
      await _pumpShell(tester, auth: auth);

      expect(find.text('GOT AN INVITE CODE?'), findsNothing);
      expect(_demoRace, findsOneWidget);
    });

    testWidgets('NO FLASH: hidden until the auth payload has been applied', (
      tester,
    ) async {
      final auth = await _auth(_prefs(authPayloadApplied: false));
      await _pumpShell(tester, auth: auth);

      expect(
        find.text('GOT AN INVITE CODE?'),
        findsNothing,
        reason: 'referredByCode is unknown — never guess and flash the step',
      );
    });

    testWidgets('onboarding never resolves the Home prompt implicitly', (
      tester,
    ) async {
      final auth = await _auth(_prefs());
      await _pumpShell(tester, auth: auth);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(OnboardingStateService.keyInviteCodeStepDone),
        isNot(true),
      );
      expect(await _queuedEventNames(), isNot(contains('invite_code_skipped')));
      expect(find.text('GOT AN INVITE CODE?'), findsNothing);
    });

    testWidgets('onboarding does not submit a manual invite code', (
      tester,
    ) async {
      final api = _FakeApi(redeemResult: {'attributed': true});
      final auth = await _auth(_prefs());
      await _pumpShell(tester, auth: auth, api: api);

      expect(find.byKey(const Key('invite-code-field')), findsNothing);
      expect(api.redeemCalls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(OnboardingStateService.keyInviteCodeStepDone),
        isNot(true),
      );
      expect(await _queuedEventNames(), isNot(contains('invite_code_applied')));
    });
  });

  // -------------------------------------------------------------------------
  // Item 9 — AuthService parse / persist / clear
  // -------------------------------------------------------------------------

  group('AuthService', () {
    test('referredByCode parses, persists and clears on sign-out', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      auth.applyBackendUser({'id': 'u1', 'referredByCode': 'BARA-FRND'});
      expect(auth.referredByCode, 'BARA-FRND');
      expect(auth.authPayloadApplied, isTrue);

      await auth.syncFromBackendUser({
        'id': 'u1',
        'referredByCode': 'BARA-FRND',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_referred_by_code'), 'BARA-FRND');

      await auth.signOut();
      expect(auth.referredByCode, isNull);
      expect(auth.authPayloadApplied, isFalse);
      expect(prefs.getString('auth_referred_by_code'), isNull);
    });

    test('an absent referredByCode reads as null (older backend)', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      auth.applyBackendUser({'id': 'u1'});
      expect(auth.referredByCode, isNull);
      expect(
        auth.authPayloadApplied,
        isTrue,
        reason:
            'an old backend still resolves the question — as "not attributed"',
      );
    });

    test('an explicit null clears a previously known code', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      auth.applyBackendUser({'id': 'u1', 'referredByCode': 'BARA-FRND'});
      auth.applyBackendUser({'id': 'u1', 'referredByCode': null});
      expect(auth.referredByCode, isNull);
    });

    test('legacy invite-code flag payloads are safely ignored', () async {
      SharedPreferences.setMockInitialValues({
        'auth_onboarding_invite_code_enabled': true,
      });
      final auth = AuthService();
      await auth.restoreSession();
      auth.applyBackendUser({
        'id': 'u1',
        'featureFlags': const {'onboardingInviteCodeEnabled': true},
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auth_onboarding_invite_code_enabled'), isNull);
    });
  });

  group('done-flag storage', () {
    test('the key is in the sign-out wipe set', () {
      expect(
        OnboardingStateService.allKeys,
        contains(OnboardingStateService.keyInviteCodeStepDone),
        reason:
            'a different account on the same device gets its own chance; '
            'server-truth referredByCode is what stops re-prompting an '
            'already-attributed account',
      );
    });

    test('the key is device-scoped (no userId suffix)', () {
      expect(
        OnboardingStateService.keyInviteCodeStepDone,
        'invite_code_step_done',
      );
    });
  });

  group('analytics allowlist', () {
    test('the relocated invite-code names are allowed', () {
      expect(
        ActivationAnalyticsService.allowedEventNames,
        containsAll(<String>[
          'invite_code_setup_shown',
          'invite_code_setup_applied',
          'invite_code_setup_dismissed',
          'settings_invite_code_opened',
        ]),
      );
    });
  });
}
