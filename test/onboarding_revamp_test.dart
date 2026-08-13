import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/screens/admin_onboarding_funnel.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/services/notification_service.dart';
import 'package:step_tracker/services/onboarding_state_service.dart';
import 'package:step_tracker/utils/onboarding_gate.dart';
import 'package:step_tracker/widgets/notification_ask_dialog.dart';
import 'package:step_tracker/widgets/steps_disconnected_banner.dart';
import 'package:step_tracker/widgets/wooden_tab_bar.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _FakeHealthService extends HealthService {
  _FakeHealthService({
    this.restored = false,
    this.setupResults = const [HealthSetupResult.authorized],
    this.probeSteps = 0,
  });

  bool restored;
  List<HealthSetupResult> setupResults;
  int probeSteps;
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
  _FakeBackendApiService({this.inviterRace, this.inviterRaceThrows = false});

  Map<String, dynamic>? inviterRace;
  bool inviterRaceThrows;
  int inviterRaceCalls = 0;

  @override
  Future<Map<String, dynamic>?> fetchInviterRace({
    required String identityToken,
  }) async {
    inviterRaceCalls += 1;
    if (inviterRaceThrows) {
      throw const ApiException('not found', statusCode: 404);
    }
    return inviterRace;
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
  bool healthAuthorized = false,
  bool firstRaceSeen = true,
  bool tutorialSeen = true,
  Map<String, Object> extra = const {},
}) {
  return {
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_first_race_onboarding_seen': firstRaceSeen,
    'auth_tutorial_onboarding_seen': tutorialSeen,
    'auth_onboarding_v2_enabled': true,
    if (v3) 'auth_onboarding_v3_enabled': true,
    if (healthAuthorized) 'health_authorized': true,
    ...extra,
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
  required HealthService health,
  BackendApiService? api,
  NotificationService? notifications,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MainShell(
        authService: auth,
        healthService: health,
        backendApiService: api ?? _FakeBackendApiService(),
        backgroundSyncBootstrapService: _FakeBackgroundSync(),
        notificationService: notifications,
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<List<Map<String, dynamic>>> _queuedEvents() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('activation_events_v1');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .cast<Map>()
      .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
      .toList();
}

Future<bool> _hasEvent(String name) async =>
    (await _queuedEvents()).any((e) => e['name'] == name);

// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Without this, PackageInfo.fromPlatform() never resolves inside
    // testWidgets' fake-async zone, so every activation event hangs mid-record
    // and the queue stays empty.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('§5.5 / §5.11.3 isOnboarding — single source of truth', () {
    // 15. Table-driven parity over every flag/state combination.
    test('v1 requires health, notifications, tutorial and first race', () {
      bool gate({
        bool health = true,
        bool? notif = true,
        bool tutorial = true,
        bool first = true,
      }) => isOnboardingGate(
        onboardingV3Enabled: false,
        onboardingV2Enabled: false,
        healthAuthorized: health,
        escapedHealthGate: false,
        notificationsState: notif,
        tutorialOnboardingSeen: tutorial,
        firstRaceOnboardingSeen: first,
      );

      expect(gate(), isFalse);
      expect(gate(health: false), isTrue);
      expect(gate(notif: null), isTrue);
      expect(gate(notif: false), isFalse);
      // The v1 regression this spec fixes: the tutorial term was dropped from
      // three of the four inline copies.
      expect(gate(tutorial: false), isTrue);
      expect(gate(first: false), isTrue);
    });

    test('v2 drops the tutorial and notification terms', () {
      bool gate({
        bool health = true,
        bool? notif = true,
        bool tutorial = false,
        bool first = true,
      }) => isOnboardingGate(
        onboardingV3Enabled: false,
        onboardingV2Enabled: true,
        healthAuthorized: health,
        escapedHealthGate: false,
        notificationsState: notif,
        tutorialOnboardingSeen: tutorial,
        firstRaceOnboardingSeen: first,
      );

      expect(gate(), isFalse);
      expect(gate(notif: null), isFalse);
      expect(gate(health: false), isTrue);
      expect(gate(first: false), isTrue);
    });

    test('v3 keeps the tutorial, drops notifications, honours the escape', () {
      bool gate({
        bool health = true,
        bool escaped = false,
        bool? notif = true,
        bool tutorial = true,
        bool first = true,
      }) => isOnboardingGate(
        onboardingV3Enabled: true,
        onboardingV2Enabled: true,
        healthAuthorized: health,
        escapedHealthGate: escaped,
        notificationsState: notif,
        tutorialOnboardingSeen: tutorial,
        firstRaceOnboardingSeen: first,
      );

      expect(gate(), isFalse);
      expect(gate(notif: null), isFalse);
      expect(gate(health: false), isTrue);
      // The escape hatch satisfies the health term without authorization.
      expect(gate(health: false, escaped: true), isFalse);
      expect(gate(tutorial: false), isTrue);
      expect(gate(first: false), isTrue);
    });

    // Structural guard: the 4-copy divergence must not come back.
    test('main_shell declares the onboarding gate exactly once', () {
      final source = File('lib/screens/main_shell.dart').readAsStringSync();
      expect(
        RegExp(r'bool get _isOnboarding').allMatches(source).length,
        1,
        reason: 'the getter must be declared exactly once',
      );
      expect(
        RegExp(r'\bfinal isOnboarding\b').allMatches(source).length,
        0,
        reason: 'no inline copies of the expression may remain',
      );
    });
  });

  group('§5.1 flag plumbing', () {
    test(
      'onboardingV3Enabled defaults false and only literal true opts in',
      () async {
        SharedPreferences.setMockInitialValues({});
        final auth = AuthService();
        auth.applyBackendUser({'id': 'u'});
        expect(auth.onboardingV3Enabled, isFalse);

        auth.applyBackendUser({
          'id': 'u',
          'featureFlags': {'onboardingV3Enabled': 'yes'},
        });
        expect(auth.onboardingV3Enabled, isFalse);

        auth.applyBackendUser({
          'id': 'u',
          'featureFlags': {'onboardingV3Enabled': true},
        });
        expect(auth.onboardingV3Enabled, isTrue);
      },
    );

    test('v3 implies v2 regardless of the stored v2 value', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      auth.applyBackendUser({
        'id': 'u',
        'featureFlags': {
          'onboardingV2Enabled': false,
          'onboardingV3Enabled': true,
        },
      });
      expect(auth.onboardingV2Enabled, isTrue);
    });

    test('an envelope-less payload never flips v3 off mid-session', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      auth.applyBackendUser({
        'id': 'u',
        'featureFlags': {'onboardingV3Enabled': true},
      });
      auth.applyBackendUser({'id': 'u', 'coins': 3});
      expect(auth.onboardingV3Enabled, isTrue);
    });
  });

  group('§5.2 / §5.3 health gate rework', () {
    // 1. v3 off -> the v2 sequence renders exactly as today.
    testWidgets('v3 off renders the v2 onboarding sequence unchanged', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingFlow(
            healthAuthorized: true,
            notificationsState: null,
            tutorialOnboardingSeen: false,
            firstRaceOnboardingSeen: false,
            onboardingV2Enabled: true,
            onEnableHealth: () {},
            onEnableNotifications: () {},
            onStartTutorial: () {},
            onSkipTutorial: () {},
            onEnterDaily: () async {},
            onSkipFirstRace: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('NOTIFICATIONS'), findsOneWidget);
    });

    // 2. v3 on -> the notifications gate is never rendered.
    testWidgets('v3 never renders the notifications gate', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingFlow(
            healthAuthorized: true,
            notificationsState: null,
            tutorialOnboardingSeen: false,
            firstRaceOnboardingSeen: false,
            onboardingV2Enabled: true,
            onboardingV3Enabled: true,
            onEnableHealth: () {},
            onEnableNotifications: () {},
            onStartTutorial: () {},
            onSkipTutorial: () {},
            onEnterDaily: () async {},
            onSkipFirstRace: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('NOTIFICATIONS'), findsNothing);
      // v3 puts the teaching step back in the critical path, before the race
      // intro. Under the demo-race spec that step is the playable demo race.
      expect(find.text('START THE TUTORIAL'), findsOneWidget);
    });

    // 3. first denial -> error + TRY AGAIN, no escape.
    testWidgets('first denial offers a retry and no escape', (tester) async {
      final auth = await _auth(_prefs());
      final health = _FakeHealthService(
        setupResults: const [HealthSetupResult.denied],
      );
      await _pumpShell(tester, auth: auth, health: health);

      expect(find.text('HEALTH DATA'), findsOneWidget);
      await tester.tap(find.text('CONTINUE'));
      await tester.pump();
      await tester.pump();

      expect(find.text('TRY AGAIN'), findsOneWidget);
      expect(find.text('Continue without steps'), findsNothing);
      expect(find.text('OPEN HEALTH CONNECT SETTINGS'), findsNothing);
      expect(await _hasEvent('health_result'), isTrue);
    });

    // 4. second denial -> settings launcher + escape hatch.
    testWidgets('second denial reveals settings and the escape hatch', (
      tester,
    ) async {
      final auth = await _auth(_prefs());
      final health = _FakeHealthService(
        setupResults: const [HealthSetupResult.denied],
      );
      await _pumpShell(tester, auth: auth, health: health);

      await tester.tap(find.text('CONTINUE'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('TRY AGAIN'));
      await tester.pump();
      await tester.pump();

      expect(find.text('OPEN HEALTH CONNECT SETTINGS'), findsOneWidget);
      expect(find.text('Continue without steps'), findsOneWidget);

      await tester.tap(find.text('OPEN HEALTH CONNECT SETTINGS'));
      await tester.pump();
      expect(health.settingsCalls, 1);
    });

    // 5. escaping lets the user in, banner shown, first-race marked locally.
    testWidgets('escaping the gate lands in the app with the banner', (
      tester,
    ) async {
      final auth = await _auth(_prefs(firstRaceSeen: false));
      final health = _FakeHealthService(
        setupResults: const [HealthSetupResult.denied],
      );
      await _pumpShell(tester, auth: auth, health: health);

      await tester.tap(find.text('CONTINUE'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('TRY AGAIN'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Continue without steps'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(find.byType(WoodenTabBar), findsOneWidget);
      expect(find.byType(StepsDisconnectedBanner), findsOneWidget);
      expect(auth.firstRaceOnboardingSeen, isTrue);
      expect(await _hasEvent('health_escaped'), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(OnboardingStateService.keyHealthEscapedGate),
        isTrue,
      );
    });

    // 6. relaunch after an escape must not return the user to the gate.
    testWidgets('a relaunched escaped user is not sent back to the gate', (
      tester,
    ) async {
      final auth = await _auth(
        _prefs(
          firstRaceSeen: true,
          extra: {OnboardingStateService.keyHealthEscapedGate: true},
        ),
      );
      await _pumpShell(tester, auth: auth, health: _FakeHealthService());

      expect(find.text('HEALTH DATA'), findsNothing);
      expect(find.byType(WoodenTabBar), findsOneWidget);
      expect(find.byType(StepsDisconnectedBanner), findsOneWidget);
    });

    // 7. iOS probe returns 0 -> user proceeds, banner stays latent for 6h.
    testWidgets(
      'an inconclusive probe lets the user through without a banner',
      (tester) async {
        final auth = await _auth(_prefs());
        final health = _FakeHealthService(
          setupResults: const [HealthSetupResult.inconclusive],
        );
        await _pumpShell(tester, auth: auth, health: health);

        await tester.tap(find.text('CONTINUE'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 40));
        }

        expect(find.byType(WoodenTabBar), findsOneWidget);
        expect(find.byType(StepsDisconnectedBanner), findsNothing);
        expect(await _hasEvent('health_probe_inconclusive'), isTrue);
      },
    );

    // 8. probe zero + 6h elapsed -> banner shows.
    testWidgets('the banner arms once six hours have passed', (tester) async {
      final armed = DateTime.now()
          .subtract(const Duration(hours: 7))
          .millisecondsSinceEpoch;
      final auth = await _auth(
        _prefs(
          healthAuthorized: true,
          extra: {
            OnboardingStateService.keyHealthProbeInconclusive: true,
            OnboardingStateService.keyHealthProbeArmedAt: armed,
          },
        ),
      );
      await _pumpShell(
        tester,
        auth: auth,
        health: _FakeHealthService(restored: true),
      );

      expect(find.byType(StepsDisconnectedBanner), findsOneWidget);
    });

    // 9. a later non-zero probe clears the state and reports recovery.
    testWidgets('steps appearing clears the banner and reports recovery', (
      tester,
    ) async {
      final armed = DateTime.now()
          .subtract(const Duration(hours: 7))
          .millisecondsSinceEpoch;
      final auth = await _auth(
        _prefs(
          healthAuthorized: true,
          extra: {
            OnboardingStateService.keyHealthProbeInconclusive: true,
            OnboardingStateService.keyHealthProbeArmedAt: armed,
          },
        ),
      );
      // Still zero at launch, so the banner is showing.
      final health = _FakeHealthService(restored: true, probeSteps: 0);
      await _pumpShell(tester, auth: auth, health: health);
      expect(find.byType(StepsDisconnectedBanner), findsOneWidget);

      // The user walks. The next resume re-probes and finds steps.
      health.probeSteps = 5200;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(find.byType(StepsDisconnectedBanner), findsNothing);
      expect(await _hasEvent('health_recovered'), isTrue);
    });
  });

  group('§5.4 notification ask relocation', () {
    // 10. the ask renders once and promises nothing that does not ship.
    testWidgets(
      'the ask is race-oriented and promises no box or powerup push',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NotificationAskDialog(onEnable: () {}, onNotNow: () {}),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Stay in the race'), findsOneWidget);
        expect(
          find.text('Get notified about what’s happening in your races.'),
          findsOneWidget,
        );
        expect(find.text('ENABLE'), findsOneWidget);
        expect(find.text('NOT NOW'), findsOneWidget);

        final copy = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => (t.data ?? '').toLowerCase())
            .join(' ');
        expect(copy.contains('box'), isFalse);
        expect(copy.contains('powerup'), isFalse);
      },
    );

    test('the box-open trigger fires once per install', () async {
      SharedPreferences.setMockInitialValues({});
      final state = OnboardingStateService();

      expect(
        await state.shouldAskForNotifications(
          trigger: NotificationAskTrigger.boxOpen,
          permissionState: null,
        ),
        isTrue,
      );
      await state.recordNotificationAsk(NotificationAskTrigger.boxOpen);
      expect(
        await state.shouldAskForNotifications(
          trigger: NotificationAskTrigger.boxOpen,
          permissionState: null,
        ),
        isFalse,
      );
    });

    test('a resolved permission state never re-asks', () async {
      SharedPreferences.setMockInitialValues({});
      final state = OnboardingStateService();
      expect(
        await state.shouldAskForNotifications(
          trigger: NotificationAskTrigger.boxOpen,
          permissionState: false,
        ),
        isFalse,
      );
      expect(
        await state.shouldAskForNotifications(
          trigger: NotificationAskTrigger.boxOpen,
          permissionState: true,
        ),
        isFalse,
      );
    });

    // 11. never opening a box -> the ask still fires on the third session.
    test('the backstop fires on the third session', () async {
      SharedPreferences.setMockInitialValues({});
      final state = OnboardingStateService();

      Future<bool> session() async {
        await state.bumpSessionCount();
        return state.shouldAskForNotifications(
          trigger: NotificationAskTrigger.session,
          permissionState: null,
        );
      }

      expect(await session(), isFalse); // 1
      expect(await session(), isFalse); // 2
      expect(await session(), isTrue); // 3
    });

    // 12. total asks capped at two per install.
    test('asks are capped at two per install', () async {
      SharedPreferences.setMockInitialValues({});
      final state = OnboardingStateService();
      await state.recordNotificationAsk(NotificationAskTrigger.boxOpen);
      await state.recordNotificationAsk(NotificationAskTrigger.session);
      await state.bumpSessionCount();
      await state.bumpSessionCount();
      await state.bumpSessionCount();
      await state.bumpSessionCount();
      expect(
        await state.shouldAskForNotifications(
          trigger: NotificationAskTrigger.session,
          permissionState: null,
        ),
        isFalse,
      );
    });
  });

  group('§5.8 referral-first landing', () {
    // 13. a referred user with an inviter race sees the inviter step.
    testWidgets('an inviter race replaces the Daily intro', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingInviterRaceStep(
            displayName: 'Trail Walker',
            skipForPendingShare: false,
            onSkipForShare: () {},
            onFetchInviterRace: () async => {
              'race': {
                'id': 'race_abc',
                'name': 'Weekend Warriors',
                'status': 'ACTIVE',
                'participantCount': 6,
                'alreadyJoined': false,
              },
              'inviter': {
                'id': 'user_xyz',
                'displayName': 'Priya',
                'steps': 2400,
              },
            },
            onJoinInviterRace: (_) async {},
            onFetchDaily: () async => null,
            onEnterDaily: (_) async {},
            onFindRace: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Priya'), findsWidgets);
      expect(find.text("JOIN PRIYA'S RACE"), findsOneWidget);
    });

    // 14. a 404 falls back to the Daily intro.
    testWidgets('a 404 falls back to the Daily intro', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingInviterRaceStep(
            displayName: 'Trail Walker',
            skipForPendingShare: false,
            onSkipForShare: () {},
            onFetchInviterRace: () async {
              throw const ApiException('not found', statusCode: 404);
            },
            onJoinInviterRace: (_) async {},
            onFetchDaily: () async => null,
            onEnterDaily: (_) async {},
            onFindRace: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingDailyIntroStep), findsOneWidget);
      expect(find.text('FIND A RACE'), findsOneWidget);
    });

    testWidgets('an explicit {race:null} falls back to the Daily intro', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingInviterRaceStep(
            displayName: 'Trail Walker',
            skipForPendingShare: false,
            onSkipForShare: () {},
            onFetchInviterRace: () async => const {
              'race': null,
              'inviter': null,
            },
            onJoinInviterRace: (_) async {},
            onFetchDaily: () async => null,
            onEnterDaily: (_) async {},
            onFindRace: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingDailyIntroStep), findsOneWidget);
    });
  });

  group('§5.9 analytics funnel', () {
    // 16. every event carries the same non-null onboardingSessionId.
    test('every recorded event carries one shared session id', () async {
      SharedPreferences.setMockInitialValues({});
      final analytics = ActivationAnalyticsService(
        backendApiService: _FakeBackendApiService(),
      );
      await analytics.record('onboarding_started');
      await analytics.record('health_result', context: {'result': 'granted'});
      await analytics.record('home_reached');

      final events = await _queuedEvents();
      expect(events, hasLength(3));
      final ids = events.map((e) => e['onboardingSessionId']).toSet();
      expect(ids, hasLength(1));
      expect(ids.first, isA<String>());
      expect((ids.first as String).isNotEmpty, isTrue);
    });

    test('the eight new event names are on the client allowlist', () {
      for (final name in const [
        'health_result',
        'health_escaped',
        'health_probe_inconclusive',
        'health_recovered',
        'notif_prompt_shown',
        'notif_result',
        'inviter_race_shown',
        'home_reached',
      ]) {
        expect(
          ActivationAnalyticsService.allowedEventNames.contains(name),
          isTrue,
          reason: '$name must be allowlisted or it never leaves the device',
        );
      }
    });
  });

  group('§7 sign-out hygiene', () {
    // 17. sign-out clears every new device-scoped key.
    test('sign-out clears every new onboarding key', () async {
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'apple-token',
        'auth_user_identifier': 'apple-user-123',
        'auth_session_token': 'session-token',
        'auth_onboarding_v3_enabled': true,
        OnboardingStateService.keyHealthAttemptCount: 2,
        OnboardingStateService.keyHealthEscapedGate: true,
        OnboardingStateService.keyHealthProbeInconclusive: true,
        OnboardingStateService.keyHealthProbeArmedAt: 123,
        OnboardingStateService.keyOnboardingSessionId: 'sess',
        OnboardingStateService.keyNotifAskCount: 1,
        OnboardingStateService.keyNotifAskedAfterBox: true,
        OnboardingStateService.keyAppSessionCount: 4,
        OnboardingStateService.keyRenameChipShownCount: 2,
        OnboardingStateService.keyCoachTipsSeen: ['milestone_claim'],
      });

      final auth = AuthService();
      await auth.restoreSession();
      await auth.signOut();

      final prefs = await SharedPreferences.getInstance();
      for (final key in OnboardingStateService.allKeys) {
        expect(
          prefs.get(key),
          isNull,
          reason: '$key must not survive sign-out',
        );
      }
      expect(prefs.getBool('auth_onboarding_v3_enabled'), isNull);
      expect(auth.onboardingV3Enabled, isFalse);
    });
  });

  // Batch 2026-08-09 item 9. The widget-level behavior is pinned in
  // batch_2026_08_09_mandatory_tutorial_test.dart; what can only be checked
  // HERE is the wiring — MainShell combining the remote flag with the local
  // circuit breaker and handing one `tutorialMandatory` down to the live step.
  group('batch 2026-08-09 item 9 — mandatory tutorial through the shell', () {
    Map<String, Object> mandatoryPrefs({bool flag = true, int abandons = 0}) =>
        _prefs(
          healthAuthorized: true,
          tutorialSeen: false,
          extra: {
            if (flag) 'auth_tutorial_mandatory_enabled': true,
            if (abandons > 0) 'tutorial_abandon_count_v1': abandons,
          },
        );

    testWidgets('flag ON: the onboarding tutorial step has no skip', (
      tester,
    ) async {
      final auth = await _auth(mandatoryPrefs());
      await _pumpShell(
        tester,
        auth: auth,
        health: _FakeHealthService(restored: true),
      );

      expect(find.text('START THE TUTORIAL'), findsOneWidget);
      expect(find.text('Skip for now'), findsNothing);
    });

    testWidgets('flag absent: skip is present exactly as it ships today', (
      tester,
    ) async {
      final auth = await _auth(mandatoryPrefs(flag: false));
      await _pumpShell(
        tester,
        auth: auth,
        health: _FakeHealthService(restored: true),
      );

      expect(find.text('START THE TUTORIAL'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);
    });

    testWidgets('circuit breaker: 3 abandoned entries restore the skip', (
      tester,
    ) async {
      // The wedge scenario — flag ON, but this device has failed to get
      // through the tutorial three times. It must not be trapped waiting on a
      // week-long phased rollout of a flag flip.
      final auth = await _auth(mandatoryPrefs(abandons: 3));
      await _pumpShell(
        tester,
        auth: auth,
        health: _FakeHealthService(restored: true),
      );

      expect(find.text('START THE TUTORIAL'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);
    });

    testWidgets('two abandons is not yet enough', (tester) async {
      final auth = await _auth(mandatoryPrefs(abandons: 2));
      await _pumpShell(
        tester,
        auth: auth,
        health: _FakeHealthService(restored: true),
      );

      expect(find.text('Skip for now'), findsNothing);
    });
  });

  group('§5.10 admin flag UI', () {
    // 18. every client-served flag gets a switch. The invite-code kill switch
    // and batch 2026-08-09 item 9's `tutorialMandatoryEnabled` bring the count
    // to seven — the property (one switch per client-served flag, none
    // missing) is unchanged.
    testWidgets('the admin settings card renders every flag switch', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminSettingsCardBody(
                settings: const {
                  'bannerAdsEnabled': false,
                  'dualBoxBannersEnabled': false,
                  'teamRacesEnabled': true,
                  'onboardingV2Enabled': true,
                  'onboardingV3Enabled': false,
                  // Invite-code spec R2: the kill switch needs a device-side
                  // toggle for staging verification.
                  'onboardingInviteCodeEnabled': true,
                  'tutorialMandatoryEnabled': false,
                },
                saving: false,
                onChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Switch), findsNWidgets(7));
      expect(find.text('Onboarding v2'), findsOneWidget);
      expect(find.text('Onboarding v3'), findsOneWidget);
      expect(find.text('Onboarding invite code'), findsOneWidget);
      expect(find.text('Team races'), findsOneWidget);
      expect(find.text('Mandatory tutorial'), findsOneWidget);
      expect(find.textContaining('30s'), findsWidgets);
    });
  });

  group('§6.5 admin onboarding funnel', () {
    Map<String, dynamic> funnel({bool withThirtyDays = false}) => {
      'windowDays': 7,
      'byPlatform': {
        'ios': {
          'onboarding_started': 400,
          'health_cta_tapped': 380,
          'health_granted': 300,
          'health_escaped': 4,
          'health_probe_inconclusive': 20,
          'daily_intro_viewed': 290,
          'home_reached': 280,
        },
        'android': {
          'onboarding_started': 100,
          'health_cta_tapped': 90,
          'health_granted': 50,
          'health_escaped': 12,
          'health_probe_inconclusive': 0,
          'daily_intro_viewed': 48,
          'home_reached': 45,
        },
      },
      if (withThirtyDays)
        'byPlatformLast30Days': {
          'ios': {'onboarding_started': 1600, 'home_reached': 1120},
          'android': {'onboarding_started': 400, 'home_reached': 180},
        },
    };

    // §8.11: an older backend omits the section entirely. Render nothing —
    // not an error, not an empty card.
    testWidgets('renders nothing when the section is absent', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OnboardingFunnelSection(funnel: null)),
        ),
      );
      await tester.pump();

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('ONBOARDING FUNNEL'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing when the section is malformed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnboardingFunnelSection(
              funnel: const {'byPlatform': 'not-a-map'},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ONBOARDING FUNNEL'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders both platforms with counts in funnel order', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(500, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OnboardingFunnelSection(funnel: funnel()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ONBOARDING FUNNEL'), findsOneWidget);
      expect(find.text('IOS'), findsOneWidget);
      expect(find.text('ANDROID'), findsOneWidget);

      // Every stage label appears once per platform.
      for (final label in OnboardingFunnelSection.stageLabels) {
        expect(find.text(label), findsNWidgets(2));
      }

      expect(find.text('400'), findsOneWidget);
      expect(find.text('280'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
    });

    testWidgets('shows step-over-step retention along the funnel spine', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(500, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OnboardingFunnelSection(funnel: funnel()),
            ),
          ),
        ),
      );
      await tester.pump();

      // iOS: 380/400 = 95%, 300/380 = 79%, 290/300 = 97%, 280/290 = 97%.
      expect(find.text('95%'), findsOneWidget);
      expect(find.text('79%'), findsOneWidget);
      // Android: 90/100 = 90%, 50/90 = 56%.
      expect(find.text('90%'), findsOneWidget);
      expect(find.text('56%'), findsOneWidget);
    });

    testWidgets('the 30-day window is offered only when the backend sends it', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(500, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OnboardingFunnelSection(funnel: funnel()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('30D'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OnboardingFunnelSection(
                funnel: funnel(withThirtyDays: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('7D'), findsOneWidget);
      expect(find.text('30D'), findsOneWidget);

      await tester.tap(find.text('30D'));
      await tester.pump();
      expect(find.text('1600'), findsOneWidget);
      expect(find.text('1120'), findsOneWidget);
    });

    testWidgets('a stage the backend omits reads 0 rather than crashing', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(500, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OnboardingFunnelSection(
                funnel: const {
                  'windowDays': 7,
                  'byPlatform': {
                    'ios': {'onboarding_started': 10},
                  },
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('IOS'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('§5.12 team-lead push routing', () {
    // 19. both spellings route to race detail.
    test(
      'TEAM_LEAD_CHANGED routes to race detail alongside the old spelling',
      () {
        final service = NotificationService(
          backendApiService: _FakeBackendApiService(),
        );
        expect(
          service.routeFromType('TEAM_LEAD_CHANGED'),
          NotificationRoute.raceDetail,
        );
        expect(
          service.routeFromType('TEAM_LEAD_CHANGE'),
          NotificationRoute.raceDetail,
        );
      },
    );
  });

  group('degraded state chrome', () {
    testWidgets('the banner is not dismissible and offers one fix action', (
      tester,
    ) async {
      var fixes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StepsDisconnectedBanner(onFix: () => fixes++)),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Steps aren’t connected'), findsOneWidget);
      expect(find.text('Fix this'), findsOneWidget);
      // No dismiss affordance — the banner clears only when steps return.
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      await tester.tap(find.text('Fix this'));
      await tester.pump();
      expect(fixes, 1);
    });
  });
}
