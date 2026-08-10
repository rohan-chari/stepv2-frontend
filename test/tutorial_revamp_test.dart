import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart';
import 'package:step_tracker/widgets/coach_tip.dart';

/// The tutorial hosts the REAL tab screens fed by seeded offline data, so the
/// walkthrough shows exactly what ships. Those screens self-load asynchronously
/// and run infinite animations, so we never pumpAndSettle — we pump fixed
/// durations to let the seeded futures resolve and the spotlight settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('NEXT'));
  await _settle(tester);
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

class _RewardAuthService extends AuthService {
  _RewardAuthService({required this.granted});

  final bool granted;
  int claims = 0;

  @override
  Future<bool> claimTutorialReward() async {
    claims += 1;
    return granted;
  }
}

const _titles = [
  'Just walk.',
  'Race your friends.',
  'Grab mystery boxes.',
  'Mess with rivals.',
  'Win coins.',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Without this, PackageInfo.fromPlatform() never resolves inside
    // testWidgets' fake-async zone, so every activation event silently hangs
    // mid-record and the queue stays empty.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  // 20 / 21 / 22.
  testWidgets('the tutorial is five steps ending on DONE', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: TutorialScreen(onComplete: (_) {})),
    );
    await _settle(tester);

    expect(find.text('STEP 1 / 5'), findsOneWidget);
    expect(find.text(_titles[0]), findsOneWidget);

    for (var i = 1; i < _titles.length; i++) {
      await _next(tester);
      expect(find.text('STEP ${i + 1} / 5'), findsOneWidget);
      expect(find.text(_titles[i]), findsOneWidget);
    }

    // Four NEXT taps reached the last step; the CTA is now DONE.
    expect(find.text('DONE'), findsOneWidget);
    expect(find.text('NEXT'), findsNothing);
  });

  // 23. SKIP on every step, and skipping claims no reward.
  testWidgets('SKIP is present on every step and claims no reward', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var completed = false;
    await tester.pumpWidget(
      MaterialApp(home: TutorialScreen(onComplete: (_) => completed = true)),
    );
    await _settle(tester);

    for (var i = 0; i < _titles.length - 1; i++) {
      expect(find.text('SKIP'), findsOneWidget);
      await _next(tester);
    }
    expect(find.text('SKIP'), findsOneWidget);

    await tester.tap(find.text('SKIP'));
    await tester.pump();
    await _settle(tester);
    expect(completed, isTrue);
    // No AuthService is wired here, so no reward could be claimed; the
    // tutorial_skipped event proves the skip path (not the finish path) ran.
    expect(
      (await _queuedEvents()).any((e) => e['name'] == 'tutorial_skipped'),
      isTrue,
    );
    expect(
      (await _queuedEvents()).any((e) => e['name'] == 'tutorial_completed'),
      isFalse,
    );
  });

  // 25. An OS back-gesture routes through the SKIP path.
  testWidgets('a back gesture routes through SKIP, not a silent pop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var completed = false;
    await tester.pumpWidget(
      MaterialApp(home: TutorialScreen(onComplete: (_) => completed = true)),
    );
    await _settle(tester);

    final popScope = tester.widget<PopScope>(
      find.byKey(const Key('tutorial-pop-scope')),
    );
    expect(popScope.canPop, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await _settle(tester);

    expect(completed, isTrue);
    expect(
      (await _queuedEvents()).any((e) => e['name'] == 'tutorial_skipped'),
      isTrue,
    );
  });

  // 28. opened / completed / skipped share one session id.
  testWidgets('tutorial analytics carry a shared session id', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: TutorialScreen(onComplete: (_) {})),
    );
    await _settle(tester);
    for (var i = 0; i < _titles.length - 1; i++) {
      await _next(tester);
    }
    await tester.tap(find.text('DONE'));
    await _settle(tester);

    final events = await _queuedEvents();
    final names = events.map((e) => e['name']).toSet();
    expect(names.contains('tutorial_opened'), isTrue);
    expect(names.contains('tutorial_completed'), isTrue);
    final ids = events.map((e) => e['onboardingSessionId']).toSet();
    expect(ids, hasLength(1));
    expect(ids.first, isNotNull);
  });

  // 24. completing all five claims the reward exactly once; a replay that the
  //     backend refuses shows no modal.
  testWidgets('completing the tutorial claims the reward once', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = _RewardAuthService(granted: true);
    await tester.pumpWidget(
      MaterialApp(
        home: TutorialScreen(onComplete: (_) {}, authService: auth),
      ),
    );
    await _settle(tester);
    for (var i = 0; i < _titles.length - 1; i++) {
      await _next(tester);
    }
    await tester.tap(find.text('DONE'));
    await _settle(tester);

    expect(auth.claims, 1);
    expect(find.text('TUTORIAL COMPLETE'), findsOneWidget);
  });

  testWidgets('a refused replay claims nothing and shows no modal', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = _RewardAuthService(granted: false);
    await tester.pumpWidget(
      MaterialApp(
        home: TutorialScreen(onComplete: (_) {}, authService: auth),
      ),
    );
    await _settle(tester);
    for (var i = 0; i < _titles.length - 1; i++) {
      await _next(tester);
    }
    await tester.tap(find.text('DONE'));
    await _settle(tester);

    expect(auth.claims, 1);
    expect(find.text('TUTORIAL COMPLETE'), findsNothing);
  });
  // Per-step drop-off (§5.11.8, unblocked by the widened context allowlist).
  testWidgets('skipping reports the 1-indexed step the user bailed on', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: TutorialScreen(onComplete: (_) {})),
    );
    await _settle(tester);
    // Advance to step 3, then bail.
    await _next(tester);
    await _next(tester);

    await tester.tap(find.text('SKIP'));
    await tester.pump();
    await _settle(tester);

    final skipped = (await _queuedEvents()).firstWhere(
      (e) => e['name'] == 'tutorial_skipped',
    );
    expect((skipped['context'] as Map)['step'], '3');
    expect((skipped['context'] as Map)['source'], 'onboarding');
  });

  testWidgets('a back-gesture bail reports its step too', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: TutorialScreen(onComplete: (_) {})),
    );
    await _settle(tester);
    await _next(tester);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await _settle(tester);

    final skipped = (await _queuedEvents()).firstWhere(
      (e) => e['name'] == 'tutorial_skipped',
    );
    expect((skipped['context'] as Map)['step'], '2');
  });

  testWidgets('completing carries no step key', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: TutorialScreen(onComplete: (_) {})),
    );
    await _settle(tester);
    for (var i = 0; i < _titles.length - 1; i++) {
      await _next(tester);
    }
    await tester.tap(find.text('DONE'));
    await _settle(tester);

    final events = await _queuedEvents();
    final completed = events.firstWhere((e) => e['name'] == 'tutorial_completed');
    expect((completed['context'] as Map).containsKey('step'), isFalse);
    final opened = events.firstWhere((e) => e['name'] == 'tutorial_opened');
    expect((opened['context'] as Map).containsKey('step'), isFalse);
  });

  test('the step context key accepts 1 through 10 and nothing else', () {
    final allowed = ActivationAnalyticsService.allowedContext['step'];
    expect(allowed, isNotNull);
    expect(allowed, {'1', '2', '3', '4', '5', '6', '7', '8', '9', '10'});
  });

  // 26. v3 places the teaching step between the health gate and the race
  //     intro; v2 never renders it. (v2 side is covered unmodified by
  //     test/onboarding_v2_test.dart.) The teaching step is the playable demo
  //     race under the demo-race spec; the structural intent is unchanged.
  test('the v3 flow orders the teaching step before the race intro', () {
    final source = File('lib/screens/onboarding_flow.dart').readAsStringSync();
    final v3Branch = source.indexOf('onboardingV3Enabled) {');
    expect(v3Branch, greaterThan(-1));
    // Strengthened (invite-code spec, test-plan item 8): the invite-code step
    // is the FIRST v3 step — attribution intent is captured before the demo
    // race, so a successful apply means the rest of onboarding (including the
    // inviter-race step) already knows the inviter.
    final inviteAt = source.indexOf('OnboardingInviteCodeStep(', v3Branch);
    final teachingAt = source.indexOf('OnboardingDemoRaceStep(', v3Branch);
    final raceAt = source.indexOf('OnboardingInviterRaceStep(', v3Branch);
    expect(inviteAt, greaterThan(-1));
    expect(teachingAt, greaterThan(-1));
    expect(raceAt, greaterThan(-1));
    expect(
      inviteAt,
      lessThan(teachingAt),
      reason: 'the invite-code step must come first under v3',
    );
    expect(
      teachingAt,
      lessThan(raceAt),
      reason: 'the teaching step must gate the race intro under v3',
    );
  });

  group('§5.11.6 just-in-time tips', () {
    // 29. each tip fires once and never again after dismissal.
    testWidgets('a tip shows once, then never again', (tester) async {
      final store = CoachTipStore();

      Future<bool> pumpTip() async {
        var shown = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CoachTipHost(
                tip: CoachTipId.milestoneClaim,
                store: store,
                enabled: true,
                onShown: () => shown = true,
                child: const SizedBox(width: 100, height: 40),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        return shown;
      }

      expect(await pumpTip(), isTrue);
      expect(find.text('Tap it to claim your coins.'), findsOneWidget);

      await tester.tap(find.text('GOT IT'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Tap it to claim your coins.'), findsNothing);

      expect(await pumpTip(), isFalse);
      expect(find.text('Tap it to claim your coins.'), findsNothing);
    });

    // 30. exactly three tips ship, and none of them is wired to box opening.
    test('exactly three tips ship and none fires on box open', () {
      expect(CoachTipId.values, hasLength(3));
      expect(CoachTipId.values.toSet(), {
        CoachTipId.milestoneClaim,
        CoachTipId.friendsAdd,
        CoachTipId.leaderboardScope,
      });

      for (final path in const [
        'lib/screens/case_opening_screen.dart',
        'lib/screens/multi_case_opening_screen.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('CoachTip'),
          isFalse,
          reason: '$path must not fire a coach tip — the box-open moment '
              'belongs to the notification ask alone (§5.11.6)',
        );
      }
    });

    test('every shipped tip has copy', () {
      for (final id in CoachTipId.values) {
        expect(coachTipCopy(id).trim().isNotEmpty, isTrue);
      }
      expect(
        coachTipCopy(CoachTipId.friendsAdd),
        'Add friends to race them. Invite one and you both earn coins.',
      );
      expect(
        coachTipCopy(CoachTipId.leaderboardScope),
        'Switch between everyone and just your friends.',
      );
    });
  });
}
