import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/demo/demo_race_engine.dart';
import 'package:step_tracker/demo/demo_race_host.dart';
import 'package:step_tracker/demo/demo_race_script.dart';
import 'package:step_tracker/screens/case_opening_screen.dart';
import 'package:step_tracker/widgets/item_slot.dart';

import 'support/demo_race_harness.dart';

/// Off-script tap gating.
///
/// The engine's `beat` is deliberately order-tolerant — it reports the first
/// unsatisfied goal so nothing can dead-end. That tolerance had a cost: while
/// the coach asked for the Protein Shake, the SECOND mystery box was still
/// tappable, and opening it silently satisfied the "open the second box" beat.
/// The user skipped a lesson without ever being told they had.
///
/// Integration-first: every assertion here goes through the REAL race screen's
/// tray, driven by the same taps a user makes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Without this, PackageInfo.fromPlatform() never resolves inside
    // testWidgets' fake-async zone and activation writes hang silently.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Finder boxSlots() => find.byWidgetPredicate(
    (w) => w is ItemSlot && w.state == ItemSlotState.mysteryBox,
  );

  Finder heldSlotOf(String type) => find.byWidgetPredicate(
    (w) =>
        w is ItemSlot &&
        w.state == ItemSlotState.held &&
        w.powerupType == type,
  );

  Future<void> pumpHost(WidgetTester tester, DemoRaceEngine engine) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: DemoRaceHost(
          key: ValueKey(engine),
          authService: SeededAuthService(),
          engine: engine,
          onDone: (_) {},
        ),
      ),
    );
    await settleDemo(tester);
  }

  /// Acknowledges the intro card and opens the first box through the REAL reel,
  /// leaving the demo sitting on the "use the Protein Shake" beat.
  Future<void> reachUseBoost(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('demo-coach-cta')));
    await settleDemo(tester);

    await tester.tap(boxSlots().first);
    await settleDemo(tester);
    await tester.tap(find.byType(CaseOpeningScreen));
    await settleDemo(tester, frames: 60);
    if (find.byType(CaseOpeningScreen).evaluate().isNotEmpty) {
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await settleDemo(tester);
    }
  }

  testWidgets('the second box is refused while the coach asks for the boost', (
    tester,
  ) async {
    final engine = DemoRaceEngine(
      myUserId: 'usr_real_1',
      myDisplayName: 'Wandering Otter42',
    );
    await pumpHost(tester, engine);
    await reachUseBoost(tester);

    expect(engine.beat, DemoBeat.useBoost);
    expect(boxSlots(), findsNWidgets(1));

    // The off-script tap: the remaining box, while the lesson is the boost.
    await tester.tap(boxSlots().first);
    await settleDemo(tester);

    // No reel was pushed, the box was not consumed, and the beat did not move.
    expect(find.byType(CaseOpeningScreen), findsNothing);
    expect(boxSlots(), findsNWidgets(1));
    expect(engine.beat, DemoBeat.useBoost);
    // The coach is still asking for the same thing, not a skipped-ahead step.
    expect(
      find.text(kDemoBeatCopy[DemoBeat.useBoost]!.title),
      findsOneWidget,
    );
  });

  testWidgets('the on-script powerup is still tappable on the same beat', (
    tester,
  ) async {
    final engine = DemoRaceEngine(
      myUserId: 'usr_real_1',
      myDisplayName: 'Wandering Otter42',
    );
    await pumpHost(tester, engine);
    await reachUseBoost(tester);

    expect(engine.beat, DemoBeat.useBoost);

    // The gate must only ever block the WRONG control — if it swallowed this
    // one the demo would be unfinishable, which is worse than the skip it
    // replaces.
    await tester.tap(heldSlotOf('PROTEIN_SHAKE').first);
    await settleDemo(tester);

    expect(find.text('USE'), findsWidgets);
  });

  test('the gate answers per beat, and never blocks the current lesson', () {
    final engine = DemoRaceEngine(
      myUserId: 'usr_real_1',
      myDisplayName: 'Wandering Otter42',
    );

    // Intro: card-driven, so the tray is not the lesson.
    expect(engine.isOnScriptTap(isMysteryBox: true), isFalse);

    engine.acknowledgeIntro();
    expect(engine.beat, DemoBeat.openBox);
    expect(engine.isOnScriptTap(isMysteryBox: true), isTrue);
    expect(
      engine.isOnScriptTap(isMysteryBox: false, type: 'PROTEIN_SHAKE'),
      isFalse,
    );
  });
}
