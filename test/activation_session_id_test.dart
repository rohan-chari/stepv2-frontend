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

/// `onboardingSessionId` is a **per-run** correlation id, not an install id.
///
/// The old behaviour minted it once per install and reused it forever, so a
/// settings-tutorial replay months later carried the onboarding run's id and
/// was counted inside the onboarding funnel.
///
/// The run boundary is the pair of events that genuinely bracket a run:
/// `onboarding_started` opens one (always minting a fresh id) and
/// `home_reached` closes it (recording under the run's id, then clearing it).

class _OfflineApi extends BackendApiService {
  @override
  Future<void> sendActivationEvents({
    required String identityToken,
    required List<Map<String, dynamic>> events,
  }) async {}
}

ActivationAnalyticsService service() =>
    ActivationAnalyticsService(backendApiService: _OfflineApi());

Future<List<Map<String, dynamic>>> queue() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('activation_events_v1');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .cast<Map>()
      .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
      .toList();
}

Future<String?> idOf(String name) async {
  final events = await queue();
  final match = events.where((e) => e['name'] == name);
  return match.isEmpty ? null : match.last['onboardingSessionId'] as String?;
}

Future<List<String?>> idsOf(String name) async =>
    (await queue()).where((e) => e['name'] == name).map((e) {
      return e['onboardingSessionId'] as String?;
    }).toList();

Future<String?> storedId() async =>
    (await SharedPreferences.getInstance()).getString(
      OnboardingStateService.keyOnboardingSessionId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // PackageInfo.fromPlatform() never resolves inside testWidgets' fake-async
    // zone, so without this every activation-event write hangs mid-record.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('a run is one id, start to finish', () {
    test('every stage of a genuine onboarding run shares the id minted by '
        'onboarding_started', () async {
      final analytics = service();
      // Exactly the order the app records them in.
      await analytics.record('onboarding_started');
      await analytics.record('health_cta_tapped');
      await analytics.record('health_result', context: {'result': 'granted'});
      await analytics.record('tutorial_opened', context: {
        'source': 'onboarding',
      });
      await analytics.record('demo_box_opened');
      await analytics.record('demo_powerup_used');
      await analytics.record('demo_won');
      await analytics.record('tutorial_completed', context: {
        'source': 'onboarding',
      });
      await analytics.record('home_reached');

      final events = await queue();
      expect(events, hasLength(9));
      final ids = events.map((e) => e['onboardingSessionId']).toSet();
      expect(
        ids,
        hasLength(1),
        reason: 'one run must be one correlation id, or the funnel splits',
      );
      expect(ids.first, isA<String>());
      expect((ids.first as String).isNotEmpty, isTrue);
    });

    test('THE ANCHOR GUARANTEE: the id a run uses is always the one minted by '
        'onboarding_started, and that event always carries it', () async {
      // The backend counts a session toward the funnel only if it has an
      // onboarding_started event. If any later stage could carry an id that
      // onboarding_started never carried, the anchor would drop a real funnel
      // and the whole chart would read zero.
      final analytics = service();
      await analytics.record('onboarding_started');
      final anchorId = await idOf('onboarding_started');
      expect(anchorId, isNotNull);
      expect(anchorId, await storedId());

      for (final name in const [
        'health_cta_tapped',
        'daily_intro_viewed',
        'tutorial_opened',
        'demo_box_opened',
        'demo_powerup_used',
        'demo_won',
        'tutorial_completed',
        'home_reached',
      ]) {
        await analytics.record(name);
        expect(
          await idOf(name),
          anchorId,
          reason: '$name escaped the anchored run id',
        );
      }
    });
  });

  group('a new run mints a new id', () {
    test('two onboarding_started events are two different runs', () async {
      final analytics = service();
      await analytics.record('onboarding_started');
      final first = await storedId();
      await analytics.record('onboarding_started');
      final second = await storedId();

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(
        second,
        isNot(first),
        reason: 'the id is per RUN, not per install',
      );

      final ids = await idsOf('onboarding_started');
      expect(ids, [first, second]);
    });

    test('a user who quits mid-onboarding and comes back is two runs, both '
        'anchored', () async {
      final analytics = service();
      // Launch 1: bails at the demo.
      await analytics.record('onboarding_started');
      await analytics.record('tutorial_opened');
      final runA = await storedId();
      // Launch 2: MainShell still sees firstRaceOnboardingSeen == false.
      await analytics.record('onboarding_started');
      await analytics.record('tutorial_opened');
      await analytics.record('home_reached');
      final events = await queue();

      final runIds = events
          .where((e) => e['name'] == 'onboarding_started')
          .map((e) => e['onboardingSessionId'])
          .toList();
      expect(runIds.toSet(), hasLength(2));
      expect(runIds.first, runA);
      // Every event in launch 2 carries launch 2's anchor.
      final runB = runIds.last;
      for (final e in events.sublist(2)) {
        expect(e['onboardingSessionId'], runB);
      }
    });
  });

  group('a run ends at home_reached', () {
    test('home_reached is recorded under the run id and then closes it',
        () async {
      final analytics = service();
      await analytics.record('onboarding_started');
      final runId = await storedId();
      await analytics.record('home_reached');

      expect(await idOf('home_reached'), runId);
      expect(
        await storedId(),
        isNull,
        reason: 'the run is over; nothing after it belongs to that funnel',
      );
    });

    test('a settings-tutorial replay does NOT inherit the onboarding run id',
        () async {
      final analytics = service();
      await analytics.record('onboarding_started');
      await analytics.record('tutorial_opened', context: {
        'source': 'onboarding',
      });
      await analytics.record('tutorial_completed', context: {
        'source': 'onboarding',
      });
      final runId = await idOf('onboarding_started');
      await analytics.record('home_reached');

      // …months later, from Profile → Settings → VIEW TUTORIAL.
      await analytics.record('tutorial_opened', context: {
        'source': 'profile',
      });
      await analytics.record('tutorial_completed', context: {
        'source': 'profile',
      });

      final replayIds = (await queue())
          .where((e) => (e['context'] as Map)['source'] == 'profile')
          .map((e) => e['onboardingSessionId'])
          .toSet();
      expect(replayIds, hasLength(1));
      expect(
        replayIds.first,
        isNot(runId),
        reason:
            'the replay must not be counted inside the onboarding funnel — '
            'this is the bug the per-run id exists to fix',
      );
    });

    test('a replayed run is unanchored, so the backend anchor drops it',
        () async {
      final analytics = service();
      await analytics.record('onboarding_started');
      await analytics.record('home_reached');
      await analytics.record('tutorial_opened', context: {
        'source': 'profile',
      });

      final events = await queue();
      final replayId = events.last['onboardingSessionId'];
      final anchored = events.any(
        (e) =>
            e['name'] == 'onboarding_started' &&
            e['onboardingSessionId'] == replayId,
      );
      expect(
        anchored,
        isFalse,
        reason: 'no onboarding_started under this id == not a funnel session',
      );
    });

    test('a later launch by an already-onboarded user is its own unanchored '
        'id', () async {
      final analytics = service();
      await analytics.record('onboarding_started');
      await analytics.record('home_reached');
      final runId = await idOf('home_reached');

      // Next launch: MainShell skips onboarding_started entirely.
      await analytics.record('home_reached');
      final ids = await idsOf('home_reached');
      expect(ids, hasLength(2));
      expect(ids.first, runId);
      expect(ids.last, isNot(runId));
    });
  });

  group('boundaries that already worked keep working', () {
    test('a fresh install mints on first record', () async {
      final analytics = service();
      expect(await storedId(), isNull);
      await analytics.record('onboarding_started');
      expect(await storedId(), isNotNull);
    });

    test('sign-out clears the id, so the next account is a new run', () async {
      final analytics = service();
      await analytics.record('onboarding_started');
      final before = await storedId();
      expect(before, isNotNull);

      // AuthService.signOut() removes every OnboardingStateService key; this
      // asserts the analytics side reacts correctly to that clearing.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(OnboardingStateService.keyOnboardingSessionId);

      await analytics.record('onboarding_started');
      expect(await storedId(), isNot(before));
    });

    test('an explicit sessionId still wins and never closes the run', () async {
      final analytics = service();
      await analytics.record('onboarding_started');
      final runId = await storedId();

      await analytics.record('home_reached', sessionId: 'caller-supplied');
      expect(await idOf('home_reached'), 'caller-supplied');
      expect(
        await storedId(),
        runId,
        reason: 'a caller correlating a different session must not end ours',
      );
    });

    test('a disallowed event name records nothing and mints nothing', () async {
      final analytics = service();
      await analytics.record('not_on_the_allowlist');
      expect(await queue(), isEmpty);
      expect(await storedId(), isNull);
    });
  });

  // -- The anchor, verified through the REAL app path ------------------------
  //
  // The service-level tests above prove the id is minted BY onboarding_started.
  // These prove the app actually emits that event, first, on a genuine run —
  // which is what makes the backend's funnel anchor safe.

  group('MainShell emits the anchor first on a real onboarding run', () {
    testWidgets('onboarding_started is the first event and owns the run id', (
      tester,
    ) async {
      final auth = await onboardingAuthService(firstRaceSeen: false);
      await pumpShell(tester, auth);

      final events = await queue();
      expect(events, isNotEmpty);
      expect(
        events.first['name'],
        'onboarding_started',
        reason:
            'if anything is recorded before the anchor, that event falls '
            'outside the funnel',
      );
      expect(events.first['onboardingSessionId'], await storedId());

      // Everything the run records afterwards rides the same anchored id.
      final analytics = service();
      await analytics.record('tutorial_opened');
      await analytics.record('demo_box_opened');
      await analytics.record('demo_won');
      final after = await queue();
      final anchorId = events.first['onboardingSessionId'];
      for (final e in after) {
        expect(e['onboardingSessionId'], anchorId);
      }
    });

    testWidgets('an already-onboarded launch emits no anchor and closes no '
        'run', (tester) async {
      final auth = await onboardingAuthService(firstRaceSeen: true);
      await pumpShell(tester, auth);

      final events = await queue();
      expect(
        events.where((e) => e['name'] == 'onboarding_started'),
        isEmpty,
        reason: 'a returning user is not a new funnel row',
      );
      // home_reached fired and closed out whatever id it minted, so the next
      // thing recorded is a fresh, still-unanchored session.
      expect(events.any((e) => e['name'] == 'home_reached'), isTrue);
      expect(await storedId(), isNull);
    });
  });

}

// -- MainShell harness --------------------------------------------------------

class _ShellHealthService extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;

  @override
  Future<StepData> getStepsToday() async =>
      StepData(steps: 1234, date: DateTime(2026, 7, 26));

  @override
  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async => const [];
}

class _ShellBootstrap extends BackgroundSyncBootstrapService {
  @override
  Future<void> enableHealthKitBackgroundDelivery() async {}
}

class _ShellApi extends BackendApiService {
  _ShellApi({required this.firstRaceSeen});

  final bool firstRaceSeen;

  Map<String, dynamic> get _user => {
    'displayName': 'Trail Walker',
    'incomingFriendRequests': 0,
    'firstRaceOnboardingSeen': firstRaceSeen,
    'tutorialOnboardingSeen': firstRaceSeen,
  };

  @override
  Future<void> sendActivationEvents({
    required String identityToken,
    required List<Map<String, dynamic>> events,
  }) async {
    // Offline: the queue is what the assertions read.
    throw Exception('offline');
  }

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async => {'sessionToken': authToken, 'user': _user};

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      _user;

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
  }) async => const {'state': 'EMPTY'};

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async => const [];

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
}

Future<AuthService> onboardingAuthService({required bool firstRaceSeen}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_first_race_onboarding_seen': firstRaceSeen,
    'auth_tutorial_onboarding_seen': firstRaceSeen,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> pumpShell(WidgetTester tester, AuthService auth) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MainShell(
        authService: auth,
        healthService: _ShellHealthService(),
        backendApiService: _ShellApi(
          firstRaceSeen: auth.firstRaceOnboardingSeen,
        ),
        backgroundSyncBootstrapService: _ShellBootstrap(),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
