import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/tutorial/spotlight_overlay.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart';

/// The tutorial renders the REAL tab screens fed by seeded offline data, so the
/// walkthrough shows exactly what ships. These screens self-load asynchronously
/// and run infinite animations (spinning coins, pulses), so we never use
/// pumpAndSettle — we pump fixed durations to let the seeded futures resolve and
/// the spotlight target settle loop finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('NEXT'));
  await _settle(tester);
}

void main() {
  testWidgets('walks the real home / races / race-detail screens in five steps',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: TutorialScreen(onComplete: (_, _) {})));
    await _settle(tester);

    // Step 1 (home): the REAL hero step count, no goal editor.
    expect(find.text('Just walk.'), findsOneWidget);
    expect(find.text('13,420'), findsOneWidget);
    expect(find.text('EDIT GOAL'), findsNothing);

    // Step 2 (races): real RACES header + seeded active race.
    await _next(tester);
    expect(find.text('Race your friends.'), findsOneWidget);
    expect(find.text('RACES'), findsWidgets);
    expect(find.text('Weekend 10K'), findsWidgets);

    // Step 3 (races): the box anchor, which no step used to point at.
    await _next(tester);
    expect(find.text('Grab mystery boxes.'), findsOneWidget);

    // Step 4 (race detail): powerups.
    await _next(tester);
    expect(find.text('Mess with rivals.'), findsOneWidget);
    final spotlight = tester.widget<SpotlightOverlay>(
      find.byType(SpotlightOverlay),
    );
    expect(spotlight.targetRect, isNotNull);
    expect(spotlight.targetRect!.width, greaterThan(0));
    expect(find.byKey(const Key('trail-mix-calculation-plate')), findsNothing);
    expect(find.textContaining('BOOST ·'), findsNothing);
    expect(find.textContaining('BURNOUT ·'), findsNothing);

    // Step 5 (home again): the shop, ending on the screen the user lands on.
    await _next(tester);
    expect(find.text('Win coins.'), findsOneWidget);
    expect(find.text('SHOP'), findsWidgets);

    // Four NEXT taps reached the last step.
    expect(find.text('DONE'), findsOneWidget);
  });

  testWidgets('SKIP finishes the tutorial via onComplete', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var completed = false;
    await tester.pumpWidget(
      MaterialApp(home: TutorialScreen(onComplete: (_, _) => completed = true)),
    );
    await _settle(tester);

    expect(find.text('SKIP'), findsOneWidget);
    await tester.tap(find.text('SKIP'));
    await tester.pump();

    expect(completed, isTrue);
  });
}
