import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/demo/demo_race_host.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart';
import 'package:step_tracker/utils/onboarding_gate.dart';

import 'support/demo_race_harness.dart';

/// Spec §10 items 10, 11 (the gate half), 19, 20 and 22.

class _NoNetworkAuthService extends AuthService {
  _NoNetworkAuthService() {
    applyBackendUser({
      'id': 'usr_real_1',
      'displayName': 'Wandering Otter42',
      'coins': 0,
    });
  }

  int rewardClaims = 0;

  @override
  String? get authToken => 'seeded-token';

  /// Stubbed so the settings-replay path never reaches the network. Crucially
  /// this does NOT mark the onboarding step seen — that is the behaviour §5.8
  /// moved out of the tutorial and into the onboarding host.
  @override
  Future<bool> claimTutorialReward() async {
    rewardClaims += 1;
    return false;
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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

  Widget flow({
    required bool teachingSeen,
    VoidCallback? onStart,
    VoidCallback? onSkip,
  }) {
    return MaterialApp(
      home: OnboardingFlow(
        healthAuthorized: true,
        notificationsState: null,
        tutorialOnboardingSeen: teachingSeen,
        firstRaceOnboardingSeen: false,
        onEnableHealth: () {},
        onEnableNotifications: () {},
        onStartTutorial: onStart ?? () {},
        onSkipTutorial: onSkip ?? () {},
        onEnterDaily: () async {},
        onSkipFirstRace: () {},
        onboardingV2Enabled: true,
        onboardingV3Enabled: true,
      ),
    );
  }

  testWidgets('v3 onboarding shows the demo-race step, not the spotlight '
      'tutorial step', (tester) async {
    await tester.pumpWidget(flow(teachingSeen: false));
    await settle(tester);

    expect(find.byType(OnboardingDemoRaceStep), findsOneWidget);
    expect(find.byType(OnboardingTutorialStep), findsNothing);
    expect(find.text('START TUTORIAL'), findsNothing);
  });

  testWidgets('the demo step offers both a start and a skip', (tester) async {
    var started = 0;
    var skipped = 0;
    await tester.pumpWidget(
      flow(
        teachingSeen: false,
        onStart: () => started += 1,
        onSkip: () => skipped += 1,
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(const Key('onboarding-demo-race-start')));
    await tester.pump();
    expect(started, 1);

    await tester.tap(find.byKey(const Key('onboarding-demo-race-skip')));
    await tester.pump();
    expect(skipped, 1);
  });

  testWidgets('once the teaching step is cleared, onboarding moves on', (
    tester,
  ) async {
    await tester.pumpWidget(flow(teachingSeen: true));
    await settle(tester);

    expect(find.byType(OnboardingDemoRaceStep), findsNothing);
  });

  test('the gate is satisfied by completing OR skipping the teaching step', () {
    bool gate({required bool teachingSeen}) => isOnboardingGate(
      onboardingV3Enabled: true,
      onboardingV2Enabled: true,
      healthAuthorized: true,
      escapedHealthGate: false,
      notificationsState: null,
      tutorialOnboardingSeen: teachingSeen,
      firstRaceOnboardingSeen: true,
    );

    expect(gate(teachingSeen: false), isTrue, reason: 'still gated');
    expect(gate(teachingSeen: true), isFalse, reason: 'cleared');
  });

  testWidgets('19 — the settings tutorial still renders all five spotlight '
      'steps', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: TutorialScreen(onComplete: (_, _) {})),
    );
    await settle(tester);

    expect(find.text('Just walk.'), findsOneWidget);
    for (final title in const [
      'Race your friends.',
      'Grab mystery boxes.',
      'Mess with rivals.',
      'Win coins.',
    ]) {
      await tester.tap(find.text('NEXT'));
      await settle(tester);
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('DONE'), findsOneWidget);
  });

  testWidgets('20 — finishing the settings tutorial does NOT satisfy the '
      'onboarding gate (§5.8)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = _NoNetworkAuthService();
    expect(auth.tutorialOnboardingSeen, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: TutorialScreen(authService: auth, onComplete: (_, _) {}),
      ),
    );
    await settle(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('NEXT'));
      await settle(tester);
    }
    await tester.tap(find.text('DONE'));
    await settle(tester);

    expect(auth.rewardClaims, 1, reason: 'the replay still pays out once');
    expect(
      auth.tutorialOnboardingSeen,
      isFalse,
      reason:
          'the settings replay is not an onboarding step; only the onboarding '
          'host may clear the gate',
    );
  });

  testWidgets('the demo host claims the tutorial reward exactly once, on the '
      'win card (D5 / §6.2)', (tester) async {
    final auth = seededRealAuthService();
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DemoRaceHost(
          authService: auth,
          onDone: (_) => done += 1,
        ),
      ),
    );
    await settle(tester);

    // Skipping grants nothing.
    await tester.tap(find.byKey(const Key('demo-skip')));
    await settle(tester);

    expect(done, 1);
    expect(auth.tutorialRewardClaims, 0, reason: 'a skip grants no coins (D4)');
  });
}
