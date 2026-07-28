import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/leaderboard_plank.dart';

// Stress the standings plank at the smallest supported width with the worst
// realistic pile-up: a 6-digit step count, a long name, a FROZEN multiplier
// chip, and an 8-effect tray. The tray must stay capped (swipeable, not
// widening), the step count must render in full, and nothing may overflow —
// the name is the only element allowed to give way (ellipsis).
void main() {
  Widget effectPlate(Key key) => Container(
        key: key,
        width: 30,
        height: 30,
        color: const Color(0xFF888888),
      );

  // Every mainstream iPhone logical width, smallest first.
  for (final width in const [320.0, 375.0, 390.0, 430.0]) {
    testWidgets(
        'plank absorbs 100k+ steps and 8 effects without overflow at ${width.toInt()}pt',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

    // The real tray caps at 103px and scrolls; emulate its cap here.
    final tray = SizedBox(
      width: 103,
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 8,
        separatorBuilder: (_, _) => const SizedBox(width: 3),
        itemBuilder: (_, i) => effectPlate(Key('plate-$i')),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeaderboardPlank(
            rank: 3,
            name: 'StepMaxxerLongName',
            steps: 179188,
            formattedSteps: '179,188',
            isUser: true,
            currentMultiplier: 0, // FROZEN chip
            effectIcons: [tray],
          ),
        ),
      ),
    );
    await tester.pump();

    // No RenderFlex overflow was thrown.
    expect(tester.takeException(), isNull);
    // The full step count renders (never truncated — it sits outside the
    // flexible middle section).
    expect(find.text('179,188'), findsOneWidget);
    // The frozen chip (icon-only snowflake) and the tray both survive.
    expect(find.byIcon(Icons.ac_unit_rounded), findsOneWidget);
    expect(find.byKey(const Key('plate-0')), findsOneWidget);
    });
  }
}
