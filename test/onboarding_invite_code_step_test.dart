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
import 'package:step_tracker/screens/onboarding_flow.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/services/onboarding_state_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';

/// Invite-code onboarding step (spec `docs/invite-code-onboarding-requirements.md`,
/// frontend test-plan items 7, 8b-widget, 9 and 10).
///
/// The step fronts 100% of new v3 users to serve the invited fraction, so the
/// tests below care as much about the exits (skip always tappable, terminal
/// rejections advancing, backend outage never trapping) as about the happy path.

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

/// Pumps the REAL onboarding flow with the invite step enabled, standing in for
/// MainShell: the resolved callback flips `showInviteCodeStep` off exactly like
/// the host does, so "the flow advances" is observable.
Future<void> _pumpFlow(
  WidgetTester tester, {
  required Future<Map<String, dynamic>> Function(String code) onApply,
  void Function({required bool attributed, bool skipped})? onResolved,
  Future<Map<String, dynamic>> Function()? onFetchReferralStatus,
  bool canPasteInviteLink = false,
  Future<String?> Function()? onPasteInviteLink,
  bool show = true,
}) async {
  var showStep = show;
  // A fresh key per pump: several tests pump the flow repeatedly, and without
  // it Flutter reuses the step's State (retaining the typed code, the fetched
  // coin figures, and the one-shot resolved guard) across scenarios.
  _pumpCount += 1;
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        key: ValueKey(_pumpCount),
        builder: (context, setState) => OnboardingFlow(
          healthAuthorized: true,
          notificationsState: true,
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
          showInviteCodeStep: showStep,
          onApplyInviteCode: onApply,
          onInviteCodeResolved: ({required bool attributed, bool skipped = false}) {
            onResolved?.call(attributed: attributed, skipped: skipped);
            setState(() => showStep = false);
          },
          onFetchInviteCodeRewards: onFetchReferralStatus,
          canPasteInviteLink: canPasteInviteLink,
          onPasteInviteLink: onPasteInviteLink,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

int _pumpCount = 0;

final _field = find.byKey(const Key('onboarding-invite-code-field'));
final _apply = find.byKey(const Key('onboarding-invite-code-apply'));
final _skip = find.byKey(const Key('onboarding-invite-code-skip'));
final _paste = find.byKey(const Key('onboarding-invite-code-paste'));
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
  // Item 7 — the step itself
  // -------------------------------------------------------------------------

  group('OnboardingInviteCodeStep', () {
    testWidgets('renders as the FIRST v3 step, ahead of the demo race', (
      tester,
    ) async {
      await _pumpFlow(tester, onApply: (_) async => {'attributed': true});

      expect(find.text('GOT AN INVITE CODE?'), findsOneWidget);
      expect(_field, findsOneWidget);
      expect(_apply, findsOneWidget);
      expect(_skip, findsOneWidget);
      expect(_demoRace, findsNothing);
    });

    testWidgets('is absent when the host says not to show it', (tester) async {
      await _pumpFlow(
        tester,
        show: false,
        onApply: (_) async => {'attributed': true},
      );

      expect(find.text('GOT AN INVITE CODE?'), findsNothing);
      expect(_demoRace, findsOneWidget);
    });

    testWidgets('APPLY is disabled until the field has text', (tester) async {
      await _pumpFlow(tester, onApply: (_) async => {'attributed': true});

      expect(_applyEnabled(tester), isFalse);

      await tester.enterText(_field, 'bara-7f3k');
      await tester.pump();

      expect(_applyEnabled(tester), isTrue);
    });

    testWidgets('apply success: toast copy, resolved(attributed), advances', (
      tester,
    ) async {
      bool? resolvedAttributed;
      String? applied;
      await _pumpFlow(
        tester,
        onFetchReferralStatus: () async => {'refereeCoins': 500},
        onApply: (code) async {
          applied = code;
          return {'attributed': true};
        },
        onResolved: ({required bool attributed, bool skipped = false}) {
          resolvedAttributed = attributed;
        },
      );

      await tester.enterText(_field, '  bara-7f3k  ');
      await tester.pump();
      await tester.tap(_apply);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(applied, 'BARA-7F3K', reason: 'trimmed + upper-cased on submit');
      expect(resolvedAttributed, isTrue);
      expect(
        find.textContaining('500 coins are yours'),
        findsOneWidget,
        reason: 'referralRedeemedCopy with the wire figure',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(_demoRace, findsOneWidget, reason: 'flow advanced');
    });

    testWidgets('terminal rejections advance; non-terminal ones stay', (
      tester,
    ) async {
      Future<void> run(String reason, {required bool terminal}) async {
        var resolvedCalls = 0;
        await _pumpFlow(
          tester,
          onApply: (_) async => {'attributed': false, 'reason': reason},
          onResolved: ({required bool attributed, bool skipped = false}) {
            resolvedCalls += 1;
          },
        );
        await tester.enterText(_field, 'BARA-ZZZZ');
        await tester.pump();
        await tester.tap(_apply);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        if (terminal) {
          expect(resolvedCalls, 1, reason: '$reason must mark done + advance');
          await tester.pump(const Duration(milliseconds: 200));
          expect(_demoRace, findsOneWidget, reason: '$reason advances');
        } else {
          expect(resolvedCalls, 0, reason: '$reason must NOT mark done');
          expect(_field, findsOneWidget, reason: '$reason stays on the step');
          expect(_skip, findsOneWidget);
        }
      }

      await run('already_attributed', terminal: true);
      await run('already_raced', terminal: true);
      await run('self_referral', terminal: false);
      await run('unknown_code', terminal: false);
      await run('invalid_code', terminal: false);
    });

    testWidgets('each rejection reason renders its own copy', (tester) async {
      Future<void> expectCopy(String reason, String needle) async {
        await _pumpFlow(
          tester,
          onApply: (_) async => {'attributed': false, 'reason': reason},
        );
        await tester.enterText(_field, 'BARA-ZZZZ');
        await tester.pump();
        await tester.tap(_apply);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(
          find.textContaining(needle),
          findsWidgets,
          reason: 'copy for $reason',
        );
      }

      await expectCopy('already_attributed', 'already connected');
      await expectCopy('self_referral', 'can’t use your own code');
      await expectCopy('already_raced', 'before your first race');
      await expectCopy('unknown_code', 'doesn’t look right');
    });

    testWidgets('a backend outage never traps the user: skip stays tappable', (
      tester,
    ) async {
      var didSkip = false;
      await _pumpFlow(
        tester,
        onApply: (_) async => throw const ApiException('offline'),
      );

      await tester.enterText(_field, 'BARA-7F3K');
      await tester.pump();
      await tester.tap(_apply);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.textContaining('Check your connection'), findsWidgets);
      expect(_skip, findsOneWidget);

      // And it still works.
      await _pumpFlow(
        tester,
        onApply: (_) async => throw const ApiException('offline'),
        onResolved: ({required bool attributed, bool skipped = false}) {
          didSkip = skipped;
        },
      );
      await tester.tap(_skip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(didSkip, isTrue);
      expect(_demoRace, findsOneWidget);
    });

    testWidgets('skip resolves as skipped and advances', (tester) async {
      bool? sawAttributed;
      bool? sawSkipped;
      await _pumpFlow(
        tester,
        onApply: (_) async => {'attributed': true},
        onResolved: ({required bool attributed, bool skipped = false}) {
          sawAttributed = attributed;
          sawSkipped = skipped;
        },
      );

      await tester.tap(_skip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(sawAttributed, isFalse);
      expect(sawSkipped, isTrue);
      expect(_demoRace, findsOneWidget);
    });

    testWidgets('coin figures on the wire upgrade the subtitle in place', (
      tester,
    ) async {
      await _pumpFlow(
        tester,
        onApply: (_) async => {'attributed': true},
        onFetchReferralStatus: () async => {
          'referrerCoins': 500,
          'refereeCoins': 500,
        },
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('500 coins'), findsWidgets);
    });

    testWidgets('absent coin figures degrade to generic copy', (tester) async {
      // An older backend, an offline device, or a null field. The amounts are
      // env-tunable server-side, so a figure must never be baked in.
      await _pumpFlow(
        tester,
        onApply: (_) async => {'attributed': true},
        onFetchReferralStatus: () async => throw const ApiException('offline'),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('500'), findsNothing);
      expect(find.textContaining('coins'), findsWidgets);
    });

    testWidgets('a null refereeCoins field degrades too', (tester) async {
      await _pumpFlow(
        tester,
        onApply: (_) async => {'attributed': true},
        onFetchReferralStatus: () async => {
          'referrerCoins': null,
          'refereeCoins': null,
        },
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('both earn coins'), findsOneWidget);
    });

    // Item 8b (widget half): the deferred pasteboard read.
    testWidgets('paste button appears only in the detect-but-unread state', (
      tester,
    ) async {
      await _pumpFlow(tester, onApply: (_) async => {'attributed': true});
      expect(_paste, findsNothing);

      await _pumpFlow(
        tester,
        onApply: (_) async => {'attributed': true},
        canPasteInviteLink: true,
        onPasteInviteLink: () async => 'BARA-7F3K',
      );
      expect(_paste, findsOneWidget);

      await tester.tap(_paste);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        tester.widget<TextField>(_field).controller!.text,
        'BARA-7F3K',
        reason: 'the consented read fills the field',
      );
    });

    testWidgets('a second paste denial degrades to manual entry', (
      tester,
    ) async {
      await _pumpFlow(
        tester,
        onApply: (_) async => {'attributed': true},
        canPasteInviteLink: true,
        onPasteInviteLink: () async => null,
      );

      await tester.tap(_paste);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_field, findsOneWidget);
      expect(_apply, findsOneWidget);
      expect(_skip, findsOneWidget);
    });

    // Item 10 — keyboard access.
    testWidgets('APPLY and skip stay on screen with the keyboard up', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(375, 667));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 667),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: OnboardingFlow(
              healthAuthorized: true,
              notificationsState: true,
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
              showInviteCodeStep: true,
              onApplyInviteCode: (_) async => {'attributed': true},
              onInviteCodeResolved:
                  ({required bool attributed, bool skipped = false}) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final applyBottom = tester.getBottomLeft(_apply).dy;
      final skipBottom = tester.getBottomLeft(_skip).dy;
      expect(
        applyBottom,
        lessThanOrEqualTo(367.0),
        reason: 'APPLY must sit above the 300pt keyboard',
      );
      expect(skipBottom, lessThanOrEqualTo(367.0));
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Item 7 (show condition) + item 9 (AuthService), through the real host
  // -------------------------------------------------------------------------

  group('show condition (MainShell)', () {
    testWidgets('shows for a v3 user with no attribution and no done-flag', (
      tester,
    ) async {
      final auth = await _auth(_prefs());
      await _pumpShell(tester, auth: auth);

      expect(find.text('GOT AN INVITE CODE?'), findsOneWidget);
      expect(
        await _queuedEventNames(),
        contains('invite_code_step_shown'),
        reason: 'emitted once the step renders',
      );
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

    testWidgets('skipping writes the device-scoped done-flag', (tester) async {
      final auth = await _auth(_prefs());
      await _pumpShell(tester, auth: auth);

      await tester.tap(_skip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingStateService.keyInviteCodeStepDone), true);
      expect(await _queuedEventNames(), contains('invite_code_skipped'));
      expect(find.text('GOT AN INVITE CODE?'), findsNothing);
    });

    testWidgets('a successful apply re-fetches the inviter race', (
      tester,
    ) async {
      final api = _FakeApi(redeemResult: {'attributed': true});
      final auth = await _auth(_prefs());
      await _pumpShell(tester, auth: auth, api: api);

      await tester.enterText(_field, 'BARA-7F3K');
      await tester.pump();
      await tester.tap(_apply);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(api.redeemCalls, 1);
      expect(
        api.inviterRaceCalls,
        greaterThan(0),
        reason: 'the pre-attribution answer was empty; ask again',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingStateService.keyInviteCodeStepDone), true);
      expect(await _queuedEventNames(), contains('invite_code_applied'));
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

      await auth.syncFromBackendUser({'id': 'u1', 'referredByCode': 'BARA-FRND'});
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
        reason: 'an old backend still resolves the question — as "not attributed"',
      );
    });

    test('an explicit null clears a previously known code', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      auth.applyBackendUser({'id': 'u1', 'referredByCode': 'BARA-FRND'});
      auth.applyBackendUser({'id': 'u1', 'referredByCode': null});
      expect(auth.referredByCode, isNull);
    });

    test('the kill switch fails OPEN: absent / non-boolean ⇒ ON', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      expect(auth.onboardingInviteCodeEnabled, isTrue);

      auth.applyBackendUser({'id': 'u1', 'featureFlags': const {}});
      expect(auth.onboardingInviteCodeEnabled, isTrue);

      auth.applyBackendUser({
        'id': 'u1',
        'featureFlags': const {'onboardingInviteCodeEnabled': 'nope'},
      });
      expect(auth.onboardingInviteCodeEnabled, isTrue);
    });

    test('only a literal false disables it', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      auth.applyBackendUser({
        'id': 'u1',
        'featureFlags': const {'onboardingInviteCodeEnabled': false},
      });
      expect(auth.onboardingInviteCodeEnabled, isFalse);

      await auth.signOut();
      expect(
        auth.onboardingInviteCodeEnabled,
        isTrue,
        reason: 'sign-out returns the kill switch to its fail-open default',
      );
    });

    test('a payload with no featureFlags envelope leaves the flag alone', () {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      auth.applyBackendUser({
        'id': 'u1',
        'featureFlags': const {'onboardingInviteCodeEnabled': false},
      });
      auth.applyBackendUser({'id': 'u1'});
      expect(auth.onboardingInviteCodeEnabled, isFalse);
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
    test('the three invite-code names are allowed', () {
      expect(
        ActivationAnalyticsService.allowedEventNames,
        containsAll(<String>[
          'invite_code_step_shown',
          'invite_code_applied',
          'invite_code_skipped',
        ]),
      );
    });
  });
}

/// PillButton expresses "disabled" as a null [PillButton.onPressed].
bool _applyEnabled(WidgetTester tester) =>
    tester.widget<PillButton>(_apply).onPressed != null;
