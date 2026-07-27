import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/demo/demo_race_host.dart';
import 'package:step_tracker/demo/demo_race_script.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';

import 'support/demo_race_harness.dart';

/// Spec §10 items 1-14, 16b, 16c, 16d, 16e, 16h, 16i and 18.
///
/// Integration-first: every assertion below is made against the REAL
/// `RaceDetailScreen` and the REAL `CaseOpeningScreen`, driven through the same
/// taps a user makes. Nothing here pokes the engine directly.

/// A [BackendApiService] that records nothing and reaches nothing. The host
/// uses a REAL api service for telemetry only; this stands in for it.
class _SilentApi extends BackendApiService {
  final List<Map<String, dynamic>> sent = [];

  @override
  Future<void> sendActivationEvents({
    required String identityToken,
    required List<Map<String, dynamic>> events,
  }) async {
    sent.addAll(events);
  }
}

Future<List<Map<String, dynamic>>> queuedEvents() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('activation_events_v1');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .cast<Map>()
      .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
      .toList();
}

class _Clock {
  DateTime value = DateTime(2026, 7, 26, 12);
  DateTime call() => value;
  void advance(Duration d) => value = value.add(d);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Without this, PackageInfo.fromPlatform() never resolves inside
    // testWidgets' fake-async zone, so every activation-event write hangs
    // silently mid-record and the queue stays empty.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  // -- Harness ---------------------------------------------------------------

  ({
    SeededAuthService auth,
    DemoRaceEngine engine,
    _Clock clock,
    _SilentApi api,
    List<bool> completions,
  })
  build() {
    final auth = seededRealAuthService();
    final clock = _Clock();
    final engine = DemoRaceEngine(
      myUserId: auth.userId!,
      myDisplayName: auth.displayName!,
      clock: clock.call,
    );
    return (
      auth: auth,
      engine: engine,
      clock: clock,
      api: _SilentApi(),
      completions: <bool>[],
    );
  }

  Future<void> pumpHost(
    WidgetTester tester,
    ({
      SeededAuthService auth,
      DemoRaceEngine engine,
      _Clock clock,
      _SilentApi api,
      List<bool> completions,
    })
    ctx,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: DemoRaceHost(
          // Unique per context: without it, re-pumping inside one test reuses
          // the previous State (and therefore the previous engine).
          key: ValueKey(ctx.engine),
          authService: ctx.auth,
          backendApiService: ctx.api,
          engine: ctx.engine,
          analytics: ActivationAnalyticsService(backendApiService: ctx.api),
          onDone: (completed) => ctx.completions.add(completed),
        ),
      ),
    );
    await settleDemo(tester);
  }

  // -- 1 ---------------------------------------------------------------------

  testWidgets('1 — the demo mounts the REAL race screen, 2nd, ~2:00 left', (
    tester,
  ) async {
    final ctx = build();
    await pumpHost(tester, ctx);

    expect(find.byType(RaceDetailScreen), findsOneWidget);
    expect(find.text(kDemoBeatCopy[DemoBeat.intro]!.title), findsOneWidget);
    // The real standings, with the real user in 2nd behind the scripted leader.
    expect(find.textContaining('Sam Rivera'), findsWidgets);
    expect(
      find.textContaining('${ctx.auth.displayName} (you)'),
      findsWidgets,
    );
    expect(ctx.engine.myPlacement, 2);
    // The real countdown chip, near two minutes.
    final shown = renderedCountdown();
    expect(shown, isNotNull);
    expect(shown! <= DemoRaceEngine.initialRemaining, isTrue);
    expect(shown >= const Duration(seconds: 100), isTrue);
  });

  // -- 2 / 3 -----------------------------------------------------------------

  testWidgets('2/3 — tapping the box pushes the REAL reel and the Protein '
      'Shake lands in the REAL inventory tray', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await tapCoach(tester);

    expect(find.text(kDemoBeatCopy[DemoBeat.openBox]!.title), findsOneWidget);
    expect(boxSlots(), findsNWidgets(2));

    await tester.tap(boxSlots().first);
    await settleDemo(tester);
    expect(find.byType(CaseOpeningScreen), findsOneWidget);

    await openABoxTail(tester);

    // One box left, and the boost is now a held slot on the real screen.
    expect(boxSlots(), findsNWidgets(1));
    expect(heldSlots(), findsNWidgets(2));
    expect(find.text(kDemoBeatCopy[DemoBeat.useBoost]!.title), findsOneWidget);
  });

  // -- 4 ---------------------------------------------------------------------

  testWidgets('4 — using the boost raises the user\'s steps, still 2nd', (
    tester,
  ) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await tapCoach(tester);
    await openABox(tester);

    final before = ctx.engine.stepsFor(ctx.auth.userId!);
    await useHeldPowerup(tester, 'PROTEIN_SHAKE');

    expect(ctx.engine.stepsFor(ctx.auth.userId!), before + 1500);
    expect(ctx.engine.myPlacement, 2);
    expect(
      find.text(kDemoBeatCopy[DemoBeat.openSecondBox]!.title),
      findsOneWidget,
    );
  });

  // -- 5 / 6 / 16e -----------------------------------------------------------

  testWidgets('5/6/16e — the shield goes up, then the scripted rival attack '
      'resolves through the REAL blocked outcome UI', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await tapCoach(tester);
    await openABox(tester);
    await useHeldPowerup(tester, 'PROTEIN_SHAKE');
    await openABox(tester);

    expect(find.text(kDemoBeatCopy[DemoBeat.useShield]!.title), findsOneWidget);
    await useHeldPowerup(tester, 'COMPRESSION_SOCKS');

    // The shield is live in the REAL active-effects row.
    expect(find.text('ACTIVE EFFECTS'), findsOneWidget);

    // Beat 6 is not a tap: the attack resolves on its own.
    await settleDemo(tester, frames: 40);
    expect(ctx.engine.attackResolved, isTrue);
    // The REAL blocked-outcome modal, classified from the real discriminators.
    expect(find.text('BLOCKED!'), findsOneWidget);
  });

  // -- 7 / 8 / 16d -----------------------------------------------------------

  testWidgets('7/8/16d — the REAL target picker excludes the user and lists '
      'three rivals; picking Sam takes 1st in the REAL standings', (
    tester,
  ) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await runToShortcutBeat(tester, ctx);

    expect(
      find.text(kDemoBeatCopy[DemoBeat.useShortcut]!.title),
      findsOneWidget,
    );

    await tester.tap(heldSlots().first);
    await settleDemo(tester);
    expect(find.text('Shortcut'), findsWidgets);
    await tester.tap(find.text('USE'));
    await settleDemo(tester);

    // The REAL picker: three rivals, and never the user themselves (G2).
    expect(find.textContaining('Sam Rivera'), findsWidgets);
    expect(find.textContaining('Jordan Lee'), findsWidgets);
    expect(find.textContaining('Priya N.'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.textContaining('${ctx.auth.displayName}'),
      ),
      findsNothing,
      reason: 'the user must be excluded from their own target picker',
    );

    await tester.tap(find.textContaining('Sam Rivera').last);
    await settleDemo(tester);

    expect(ctx.engine.myPlacement, 1);
  });

  // -- 9 / 10 ----------------------------------------------------------------

  testWidgets('9/10 — the clock runs out, the demo renders as won, and '
      'CONTINUE finishes the step', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await runToShortcutBeat(tester, ctx);
    await useShortcutOn(tester, 'Sam Rivera');

    // The floor lifts and the clock runs down.
    ctx.clock.advance(DemoRaceEngine.finalCountdown);
    await settleDemo(tester, frames: 100);

    expect(ctx.engine.isCompleted, isTrue);
    expect(find.byKey(const Key('demo-win-card')), findsOneWidget);

    await tester.tap(find.byKey(const Key('demo-win-continue')));
    await settleDemo(tester);

    expect(ctx.completions, [true]);
  });

  // -- 11 --------------------------------------------------------------------

  testWidgets('11 — skip works at every beat, grants no coins, never crashes', (
    tester,
  ) async {
    for (final stopAfter in [0, 1, 2, 3, 4, 5, 6]) {
      final ctx = build();
      await pumpHost(tester, ctx);
      await advanceBeats(tester, ctx, stopAfter);

      expect(find.byKey(const Key('demo-skip')), findsOneWidget);
      await tester.tap(find.byKey(const Key('demo-skip')));
      await settleDemo(tester);

      expect(ctx.completions, [false], reason: 'skipped after $stopAfter beats');
      expect(
        ctx.auth.coins,
        1840,
        reason: 'a skip grants no coins (D4)',
      );
    }
  });

  // -- 12 --------------------------------------------------------------------

  testWidgets('12 — backgrounding mid-demo and returning does not duplicate '
      'beats or double-reward', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await tapCoach(tester);
    await openABox(tester);

    final beatBefore = ctx.engine.beat;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settleDemo(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleDemo(tester);

    expect(ctx.engine.beat, beatBefore);
    expect(ctx.completions, isEmpty);

    // And a full run still reports exactly one completion.
    await useHeldPowerup(tester, 'PROTEIN_SHAKE');
    await openABox(tester);
    await useHeldPowerup(tester, 'COMPRESSION_SOCKS');
    await settleDemo(tester, frames: 40);
    await dismissBlockedModal(tester);
    await useShortcutOn(tester, 'Sam Rivera');
    ctx.clock.advance(DemoRaceEngine.finalCountdown);
    await settleDemo(tester, frames: 100);
    await tester.tap(find.byKey(const Key('demo-win-continue')));
    await settleDemo(tester);

    expect(ctx.completions, [true]);
  });

  // -- 13 --------------------------------------------------------------------

  testWidgets('13 — idling past the natural expiry holds the clock at 0:20 '
      'and the demo is still completable', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);

    // Well past the two-minute race.
    ctx.clock.advance(const Duration(minutes: 20));
    await settleDemo(tester, frames: 60);

    final held = renderedCountdown();
    expect(held, isNotNull);
    expect(held! <= DemoRaceEngine.clockFloor, isTrue);
    expect(
      held >= const Duration(seconds: 15),
      isTrue,
      reason: 'the clock must hold at the floor, not run out',
    );

    await runToShortcutBeat(tester, ctx);
    await useShortcutOn(tester, 'Sam Rivera');
    ctx.clock.advance(DemoRaceEngine.finalCountdown);
    await settleDemo(tester, frames: 100);
    expect(find.byKey(const Key('demo-win-card')), findsOneWidget);
  });

  // -- 14 --------------------------------------------------------------------

  testWidgets('14 — the rendered countdown never increases across a poll', (
    tester,
  ) async {
    final ctx = build();
    await pumpHost(tester, ctx);

    var last = renderedCountdown();
    expect(last, isNotNull);

    for (final step in [
      const Duration(seconds: 20),
      const Duration(seconds: 20),
      // A backwards clock must not raise the countdown.
      const Duration(seconds: -45),
      const Duration(seconds: 40),
      const Duration(minutes: 5),
    ]) {
      ctx.clock.advance(step);
      await settleDemo(tester, frames: 60);
      final now = renderedCountdown();
      expect(now, isNotNull);
      expect(
        now! <= last!,
        isTrue,
        reason: 'countdown went up: $last -> $now',
      );
      last = now;
    }
  });

  // -- 16b -------------------------------------------------------------------

  testWidgets('16b — demo box opens do NOT consume the real first-box '
      'notification trigger', (tester) async {
    final ctx = build();
    var realBoxOpenCallbacks = 0;

    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: DemoRaceHost(
          authService: ctx.auth,
          backendApiService: ctx.api,
          engine: ctx.engine,
          analytics: ActivationAnalyticsService(backendApiService: ctx.api),
          onDone: (completed) => ctx.completions.add(completed),
          onRealBoxOpened: () async => realBoxOpenCallbacks += 1,
        ),
      ),
    );
    await settleDemo(tester);
    await tapCoach(tester);
    await openABox(tester);
    await useHeldPowerup(tester, 'PROTEIN_SHAKE');
    await openABox(tester);

    expect(ctx.engine.beat, DemoBeat.useShield);
    expect(
      realBoxOpenCallbacks,
      0,
      reason:
          'the relocated notification ask must still fire on the user\'s '
          'FIRST REAL box, not on a demo box',
    );
  });

  // -- 16c -------------------------------------------------------------------

  testWidgets('16c — no demo action moves the coin balance; the win-card '
      'grant is the only mutation', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await runToShortcutBeat(tester, ctx);
    await useShortcutOn(tester, 'Sam Rivera');

    expect(
      ctx.auth.coinUpdates,
      0,
      reason: 'opening boxes and using powerups must not touch the wallet',
    );
    expect(ctx.auth.coins, 1840);
  });

  // -- 16h -------------------------------------------------------------------

  testWidgets('16h — wandering into chat, the odds sheet and a participant '
      'row does not break the script', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await tapCoach(tester);

    // Read-only exploration stays enabled: the coach simply waits.
    final chatTab = find.text('CHAT');
    if (chatTab.evaluate().isNotEmpty) {
      await tester.tap(chatTab.first);
      await settleDemo(tester);
      await tester.tap(find.text('ACTIVITY').first);
      await settleDemo(tester);
    }
    await tester.tap(find.textContaining('Sam Rivera').first);
    await settleDemo(tester);
    // Close whatever the tap opened, if anything.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    if (navigator.canPop()) {
      navigator.pop();
      await settleDemo(tester);
    }

    // Still on beat 2, still advancing.
    expect(ctx.engine.beat, DemoBeat.openBox);
    await openABox(tester);
    expect(ctx.engine.beat, DemoBeat.useBoost);
  });

  // -- 16i -------------------------------------------------------------------

  testWidgets('16i — back / swipe-back routes through skip', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await tapCoach(tester);

    // The system back gesture.
    await tester.binding.handlePopRoute();
    await settleDemo(tester);

    expect(
      ctx.completions,
      [false],
      reason: 'back is the skip affordance, not a silent exit',
    );
  });

  // -- 18 --------------------------------------------------------------------

  testWidgets('18 — telemetry: opened/completed carry source onboarding, and '
      'skip carries step as a STRING', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await tapCoach(tester);
    await settleDemo(tester);

    var events = await queuedEvents();
    expect(
      events.where((e) => e['name'] == 'tutorial_opened').length,
      1,
    );
    expect(
      (events.firstWhere((e) => e['name'] == 'tutorial_opened')['context']
          as Map)['source'],
      'onboarding',
    );

    await tester.tap(find.byKey(const Key('demo-skip')));
    await settleDemo(tester);

    events = await queuedEvents();
    final skipped = events.firstWhere((e) => e['name'] == 'tutorial_skipped');
    expect((skipped['context'] as Map)['source'], 'onboarding');
    expect(
      (skipped['context'] as Map)['step'],
      isA<String>(),
      reason: 'the wire type for step is a decimal string (F7)',
    );
    expect((skipped['context'] as Map)['step'], '2');
  });

  testWidgets('18b — the demo action events are recorded', (tester) async {
    final ctx = build();
    await pumpHost(tester, ctx);
    await tapCoach(tester);
    await openABox(tester);
    await useHeldPowerup(tester, 'PROTEIN_SHAKE');
    await settleDemo(tester);

    final names = (await queuedEvents()).map((e) => e['name']).toList();
    expect(names, contains('demo_box_opened'));
    expect(names, contains('demo_powerup_used'));
  });
}

// -- Shared step helpers ------------------------------------------------------

Finder coachCta() => find.byKey(const Key('demo-coach-cta'));

Finder boxSlots() => find.byWidgetPredicate(
  (w) => w is ItemSlot && w.state == ItemSlotState.mysteryBox,
);

Finder heldSlots() => find.byWidgetPredicate(
  (w) => w is ItemSlot && w.state == ItemSlotState.held,
);

Future<void> tapCoach(WidgetTester tester) async {
  await tester.tap(coachCta());
  await settleDemo(tester);
}

/// Opens the first mystery box all the way through the REAL reel.
Future<void> openABox(WidgetTester tester) async {
  await tester.tap(boxSlots().first);
  await settleDemo(tester);
  await openABoxTail(tester);
}

Finder heldSlotOfType(String type) => find.byWidgetPredicate(
  (w) =>
      w is ItemSlot &&
      w.state == ItemSlotState.held &&
      w.powerupType == type,
);

/// Uses the held powerup of [type] through the real sheet's USE button.
Future<void> useHeldPowerup(WidgetTester tester, String type) async {
  final slot = heldSlotOfType(type);
  expect(slot, findsOneWidget, reason: 'no held $type slot on the tray');
  await tester.tap(slot);
  await settleDemo(tester);
  await tester.tap(find.text('USE'));
  await settleDemo(tester);
}

/// Plays beats 1-6 so the Shortcut beat is live.
Future<void> runToShortcutBeat(WidgetTester tester, dynamic ctx) async {
  await tapCoach(tester);
  await openABox(tester);
  await useHeldPowerup(tester, 'PROTEIN_SHAKE');
  await openABox(tester);
  await useHeldPowerup(tester, 'COMPRESSION_SOCKS');
  await settleDemo(tester, frames: 40);
  await dismissBlockedModal(tester);
}

/// Plays the first [count] user-driven beats, for the skip-at-every-beat sweep.
Future<void> advanceBeats(WidgetTester tester, dynamic ctx, int count) async {
  if (count >= 1) await tapCoach(tester);
  if (count >= 2) await openABox(tester);
  if (count >= 3) await useHeldPowerup(tester, 'PROTEIN_SHAKE');
  if (count >= 4) await openABox(tester);
  if (count >= 5) {
    await useHeldPowerup(tester, 'COMPRESSION_SOCKS');
    // The scripted attack resolves on its own and opens the real blocked
    // reveal; dismiss it so the rest of the screen is reachable again.
    await settleDemo(tester, frames: 40);
    await popBlockedModal(tester);
  }
  if (count >= 6) {
    final cta = find.byKey(const Key('demo-coach-cta'));
    if (cta.evaluate().isNotEmpty) {
      await tester.tap(cta);
      await settleDemo(tester);
    }
  }
}

Future<void> openABoxTail(WidgetTester tester) async {
  await tester.tap(find.byType(CaseOpeningScreen));
  await settleDemo(tester, frames: 60);
  if (find.byType(CaseOpeningScreen).evaluate().isNotEmpty) {
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settleDemo(tester);
  }
}

Future<void> popBlockedModal(WidgetTester tester) async {
  if (find.text('BLOCKED!').evaluate().isNotEmpty) {
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    if (nav.canPop()) nav.pop();
    await settleDemo(tester);
  }
}

Future<void> dismissBlockedModal(WidgetTester tester) async {
  await popBlockedModal(tester);
  final cta = find.byKey(const Key('demo-coach-cta'));
  if (cta.evaluate().isNotEmpty) {
    await tester.tap(cta);
    await settleDemo(tester);
  }
}

Future<void> useShortcutOn(WidgetTester tester, String targetName) async {
  await tester.tap(heldSlotOfType('SHORTCUT'));
  await settleDemo(tester);
  await tester.tap(find.text('USE'));
  await settleDemo(tester);
  await tester.tap(find.textContaining(targetName).last);
  await settleDemo(tester);
}

/// The countdown the REAL screen is rendering right now.
Duration? renderedCountdown() {
  final matches = find
      .byWidgetPredicate(
        (w) => w is Text && RegExp(r'^\d+m \d{2}s$').hasMatch(w.data ?? ''),
      )
      .evaluate();
  if (matches.isEmpty) return null;
  final m = RegExp(
    r'^(\d+)m (\d{2})s$',
  ).firstMatch((matches.first.widget as Text).data!)!;
  return Duration(
    minutes: int.parse(m.group(1)!),
    seconds: int.parse(m.group(2)!),
  );
}
