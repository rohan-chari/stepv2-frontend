import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/demo/demo_race_host.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/tutorial/tutorial_gate.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart';

import 'support/demo_race_harness.dart';

/// Batch 2026-08-09 item 9 — mandatory tutorial.
///
/// The escape hatches close ONLY when the backend flag
/// `tutorialMandatoryEnabled` is true AND the local 3-abandon circuit breaker
/// has not tripped. Flag absent (older backend) or false must reproduce
/// today's behavior exactly, and the Settings replay must stay closable in
/// every configuration — a replay user whose spotlight anchor fails to mount
/// has no other way out.
class _SilentApi extends BackendApiService {
  @override
  Future<void> sendActivationEvents({
    required String identityToken,
    required List<Map<String, dynamic>> events,
  }) async {}
}

Future<void> _settle(WidgetTester tester, {int frames = 16}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Fires the OS back gesture at the frontmost route.
Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  // ------------------------------------------------------------------
  // The remote flag
  // ------------------------------------------------------------------
  group('tutorialMandatoryEnabled flag', () {
    test('absent on an older backend reads as false (skippable)', () {
      final auth = AuthService();
      auth.applyBackendUser({'id': 'u1', 'displayName': 'Walker'});
      expect(auth.tutorialMandatoryEnabled, isFalse);
    });

    test('an envelope without the key leaves it false', () {
      final auth = AuthService();
      auth.applyBackendUser({
        'id': 'u1',
        'featureFlags': {'bannerAdsEnabled': true},
      });
      expect(auth.tutorialMandatoryEnabled, isFalse);
    });

    test('only the literal true turns it on', () {
      final auth = AuthService();
      auth.applyBackendUser({
        'id': 'u1',
        'featureFlags': {'tutorialMandatoryEnabled': true},
      });
      expect(auth.tutorialMandatoryEnabled, isTrue);

      auth.applyBackendUser({
        'id': 'u1',
        'featureFlags': {'tutorialMandatoryEnabled': false},
      });
      expect(auth.tutorialMandatoryEnabled, isFalse);

      auth.applyBackendUser({
        'id': 'u1',
        'featureFlags': {'tutorialMandatoryEnabled': 'yes'},
      });
      expect(auth.tutorialMandatoryEnabled, isFalse);
    });

    test('the appSettings envelope flips it too', () {
      final auth = AuthService();
      auth.applyBackendUser({
        'id': 'u1',
        'appSettings': {'tutorialMandatoryEnabled': true},
      });
      expect(auth.tutorialMandatoryEnabled, isTrue);
    });
  });

  // ------------------------------------------------------------------
  // The local circuit breaker
  // ------------------------------------------------------------------
  group('3-abandon circuit breaker', () {
    test('mandatory mode holds until the third abandoned entry', () async {
      expect(await tutorialAbandonCount(), 0);

      for (var i = 1; i <= kTutorialAbandonLimit - 1; i++) {
        await recordTutorialEntry();
        expect(
          tutorialSkippable(
            mandatoryEnabled: true,
            abandonCount: await tutorialAbandonCount(),
          ),
          isFalse,
          reason: 'still mandatory after $i abandoned entries',
        );
      }

      await recordTutorialEntry();
      expect(await tutorialAbandonCount(), kTutorialAbandonLimit);
      expect(
        tutorialSkippable(
          mandatoryEnabled: true,
          abandonCount: await tutorialAbandonCount(),
        ),
        isTrue,
        reason: 'a crash loop must not be able to wedge a user',
      );
    });

    test('completing the tutorial clears the counter', () async {
      await recordTutorialEntry();
      await recordTutorialEntry();
      await clearTutorialAbandons();
      expect(await tutorialAbandonCount(), 0);
    });

    test(
      'sign-out clears the counter so it cannot follow the device',
      () async {
        // Device-scoped, not account-scoped. Left behind, the next account on a
        // shared device would start with the skip already unlocked and could
        // walk past a tutorial it has never seen — the same cross-account leak
        // the health-auth key had.
        SharedPreferences.setMockInitialValues({
          'auth_identity_token': 'apple-token',
          'auth_user_identifier': 'apple-user-123',
          'auth_session_token': 'session-token',
          'auth_backend_user_id': 'user-1',
        });
        final auth = AuthService();
        await auth.restoreSession();

        for (var i = 0; i < kTutorialAbandonLimit; i++) {
          await recordTutorialEntry();
        }
        expect(await tutorialAbandonCount(), kTutorialAbandonLimit);
        expect(
          tutorialSkippable(
            mandatoryEnabled: true,
            abandonCount: await tutorialAbandonCount(),
          ),
          isTrue,
        );

        await auth.signOut();

        expect(await tutorialAbandonCount(), 0);
        expect(
          tutorialSkippable(
            mandatoryEnabled: true,
            abandonCount: await tutorialAbandonCount(),
          ),
          isFalse,
          reason: 'the next account starts mandatory again',
        );
      },
    );

    test('with the flag off the tutorial is skippable at any count', () async {
      expect(
        tutorialSkippable(mandatoryEnabled: false, abandonCount: 0),
        isTrue,
      );
      expect(
        tutorialSkippable(mandatoryEnabled: false, abandonCount: 9),
        isTrue,
      );
    });
  });

  // ------------------------------------------------------------------
  // Intro steps (v3 demo race + v1/v2 spotlight)
  // ------------------------------------------------------------------
  group('v3 demo-race intro step', () {
    testWidgets('default (flag off) keeps Skip for now', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingDemoRaceStep(onStart: () {}, onSkip: () {}),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('onboarding-demo-race-skip')),
        findsOneWidget,
      );
      expect(find.text('Skip for now'), findsOneWidget);
    });

    testWidgets('mandatory removes the skip control entirely', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingDemoRaceStep(
            onStart: () {},
            onSkip: () {},
            mandatory: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('onboarding-demo-race-skip')), findsNothing);
      expect(find.text('Skip for now'), findsNothing);
      // The primary CTA survives and is still the full-width button.
      expect(
        find.byKey(const Key('onboarding-demo-race-start')),
        findsOneWidget,
      );
      expect(find.text('START THE TUTORIAL'), findsOneWidget);
    });

    testWidgets('carries the reassurance copy and keeps the dock label', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingDemoRaceStep(
            onStart: () {},
            onSkip: () {},
            mandatory: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('90 SECONDS · 100 COINS'), findsOneWidget);
      expect(find.textContaining('We promise'), findsOneWidget);
    });
  });

  group('v1/v2 spotlight intro step', () {
    testWidgets('default keeps Skip for now', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingTutorialStep(onStart: () {}, onSkip: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('Skip for now'), findsOneWidget);
    });

    testWidgets('mandatory removes it and mirrors the new copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingTutorialStep(
            onStart: () {},
            onSkip: () {},
            mandatory: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Skip for now'), findsNothing);
      expect(find.text('START TUTORIAL'), findsOneWidget);
      expect(find.textContaining('We promise'), findsOneWidget);
    });
  });

  group('OnboardingFlow threads the flag to the live step', () {
    Widget flow({required bool mandatory, required bool v3}) => MaterialApp(
      home: OnboardingFlow(
        healthAuthorized: true,
        notificationsState: true,
        tutorialOnboardingSeen: false,
        firstRaceOnboardingSeen: false,
        onEnableHealth: () {},
        onEnableNotifications: () {},
        onStartTutorial: () {},
        onSkipTutorial: () {},
        onEnterDaily: () async {},
        onSkipFirstRace: () {},
        onboardingV2Enabled: !v3,
        onboardingV3Enabled: v3,
        tutorialMandatory: mandatory,
      ),
    );

    testWidgets('v3 mandatory hides the skip', (tester) async {
      await tester.pumpWidget(flow(mandatory: true, v3: true));
      await tester.pump();
      expect(find.text('Skip for now'), findsNothing);
      expect(find.text('START THE TUTORIAL'), findsOneWidget);
    });

    testWidgets('v3 with the flag off is unchanged', (tester) async {
      await tester.pumpWidget(flow(mandatory: false, v3: true));
      await tester.pump();
      expect(find.text('Skip for now'), findsOneWidget);
    });

    testWidgets('v1/v2 mandatory hides the skip', (tester) async {
      await tester.pumpWidget(flow(mandatory: true, v3: false));
      await tester.pump();
      expect(find.text('Skip for now'), findsNothing);
    });
  });

  // ------------------------------------------------------------------
  // In-tutorial escape hatches — demo race host (v3)
  // ------------------------------------------------------------------
  group('demo race host', () {
    Future<List<bool>> pumpHost(
      WidgetTester tester, {
      required bool mandatory,
    }) async {
      await tester.binding.setSurfaceSize(const Size(600, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final completions = <bool>[];
      final api = _SilentApi();
      final engine = DemoRaceEngine(
        myUserId: 'usr_real_1',
        myDisplayName: 'Wandering Otter42',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DemoRaceHost(
            key: ValueKey(engine),
            authService: seededRealAuthService(),
            backendApiService: api,
            engine: engine,
            analytics: ActivationAnalyticsService(backendApiService: api),
            mandatory: mandatory,
            onDone: completions.add,
          ),
        ),
      );
      await settleDemo(tester);
      return completions;
    }

    testWidgets('default shows the SKIP chip and it exits', (tester) async {
      final completions = await pumpHost(tester, mandatory: false);

      expect(find.byKey(const Key('demo-skip')), findsOneWidget);
      await tester.tap(find.byKey(const Key('demo-skip')));
      await tester.pump();
      expect(completions, [false]);
    });

    testWidgets('mandatory removes the SKIP chip', (tester) async {
      final completions = await pumpHost(tester, mandatory: true);

      expect(find.byKey(const Key('demo-skip')), findsNothing);
      expect(completions, isEmpty);
    });

    testWidgets('default: back exits the demo as a skip', (tester) async {
      final completions = await pumpHost(tester, mandatory: false);

      await _pressBack(tester);
      expect(completions, [false]);
    });

    testWidgets('mandatory: back is a no-op', (tester) async {
      final completions = await pumpHost(tester, mandatory: true);

      await _pressBack(tester);
      expect(
        completions,
        isEmpty,
        reason: 'a back gesture must not satisfy the onboarding gate',
      );
      // Still on the demo.
      expect(find.byType(DemoRaceHost), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------
  // In-tutorial escape hatches — spotlight tutorial (v1/v2 + replay)
  // ------------------------------------------------------------------
  group('spotlight tutorial', () {
    testWidgets('replay default keeps the SKIP pill and the back exit', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var exited = false;
      bool? reportedCompleted;
      await tester.pumpWidget(
        MaterialApp(
          home: TutorialScreen(
            onComplete: (_, completed) {
              exited = true;
              reportedCompleted = completed;
            },
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('SKIP'), findsOneWidget);
      await _pressBack(tester);
      expect(
        exited,
        isTrue,
        reason: 'the Settings replay must always have an exit',
      );
      // And the exit is reported as a NON-completion, so a host that gates on
      // completion can't mistake a back gesture for finishing the tutorial.
      expect(reportedCompleted, isFalse);
    });

    testWidgets('mandatory hides the SKIP pill', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: TutorialScreen(mandatory: true, onComplete: (_, _) {}),
        ),
      );
      await _settle(tester);

      expect(find.text('SKIP'), findsNothing);
      // The walkthrough itself still works.
      expect(find.text('Just walk.'), findsOneWidget);
      expect(find.text('NEXT'), findsOneWidget);
    });

    testWidgets('mandatory: back does not complete onboarding', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var finished = false;
      await tester.pumpWidget(
        MaterialApp(
          home: TutorialScreen(
            mandatory: true,
            onComplete: (_, _) => finished = true,
          ),
        ),
      );
      await _settle(tester);

      await _pressBack(tester);
      expect(finished, isFalse);
      expect(find.text('Just walk.'), findsOneWidget);
    });

    testWidgets('mandatory: finishing every step still completes', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var finished = false;
      bool? reportedCompleted;
      await tester.pumpWidget(
        MaterialApp(
          home: TutorialScreen(
            mandatory: true,
            onComplete: (_, completed) {
              finished = true;
              reportedCompleted = completed;
            },
          ),
        ),
      );
      await _settle(tester);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('NEXT'));
        await _settle(tester);
      }
      await tester.tap(find.text('DONE'));
      await _settle(tester);

      expect(finished, isTrue);
      // Reaching the last step is the only thing that reports completion —
      // this is what lets the host mark the onboarding step seen.
      expect(reportedCompleted, isTrue);
    });
  });
}
