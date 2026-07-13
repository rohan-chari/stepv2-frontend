import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  testWidgets(
      'walks the real home / friends / profile / races / boards screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: TutorialScreen(onComplete: (_) {})));
    await _settle(tester);

    // Step 1-4 (home): the REAL hero step count + StepMilestonesSection, no goal.
    expect(find.text('13,420'), findsOneWidget);
    expect(find.text("Today's coins"), findsOneWidget);
    expect(find.text('SHOP'), findsWidgets);
    expect(find.text('EDIT GOAL'), findsNothing);

    // Advance through the four home steps (last one spotlights the Friends
    // tab in the nav bar) to the real Friends screen.
    await _next(tester); // milestones
    await _next(tester); // shop
    await _next(tester); // nav.friends
    await _next(tester); // -> friends.search
    expect(find.text('Search by display name'), findsOneWidget);
    expect(find.text('@Maya Chen'), findsWidgets);

    // Profile (step 6): the referral invite button.
    await _next(tester);
    expect(find.text('INVITE FRIENDS & EARN COINS'), findsOneWidget);

    // Races (steps 7-8): real RACES header + seeded active race.
    await _next(tester);
    expect(find.text('RACES'), findsWidgets);
    expect(find.text('Weekend 10K'), findsWidgets);

    // Race detail (step 9): powerups & boxes.
    await _next(tester); // races.pot
    await _next(tester); // -> raceDetail.powerups

    // Boards (step 10): real leaderboard.
    await _next(tester);
    expect(find.text('LEADERBOARD'), findsWidgets);
  });

  testWidgets('SKIP finishes the tutorial via onComplete', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var completed = false;
    await tester.pumpWidget(
      MaterialApp(home: TutorialScreen(onComplete: (_) => completed = true)),
    );
    await _settle(tester);

    expect(find.text('SKIP'), findsOneWidget);
    await tester.tap(find.text('SKIP'));
    await tester.pump();

    expect(completed, isTrue);
  });
}
