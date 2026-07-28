import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/leaderboard_plank.dart';

Widget _wrap(double? multiplier, {bool stealthed = false}) => MaterialApp(
  home: Scaffold(
    body: LeaderboardPlank(
      rank: 3,
      name: 'Anjali',
      steps: 12000,
      formattedSteps: '12,000',
      isStealthed: stealthed,
      currentMultiplier: multiplier,
    ),
  ),
);

void main() {
  testWidgets('buff multiplier shows an "Nx" badge with no flame', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(3));
    await tester.pump();

    expect(find.text('3x'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
  });

  testWidgets('higher multiplier still renders just the number', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(5));
    await tester.pump();

    expect(find.text('5x'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
  });

  testWidgets('frozen (0) shows only a snowflake, with an a11y label', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(0));
    await tester.pump();

    expect(find.text('FROZEN'), findsNothing);
    expect(find.byIcon(Icons.ac_unit_rounded), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Frozen',
      ),
      findsOneWidget,
    );
  });

  testWidgets('reversed (<0) shows a reversed chip', (tester) async {
    await tester.pumpWidget(_wrap(-2));
    await tester.pump();

    expect(find.text('2x'), findsOneWidget);
    expect(find.byIcon(Icons.u_turn_left_rounded), findsOneWidget);
  });

  testWidgets('neutral (1) renders no chip', (tester) async {
    await tester.pumpWidget(_wrap(1));
    await tester.pump();

    expect(find.textContaining('x'), findsNothing);
  });

  testWidgets('absent multiplier renders nothing new (old backend)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(null));
    await tester.pump();

    expect(find.byIcon(Icons.ac_unit_rounded), findsNothing);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
  });

  testWidgets('a stealthed runner never shows a badge', (tester) async {
    await tester.pumpWidget(_wrap(4, stealthed: true));
    await tester.pump();

    expect(find.text('4x'), findsNothing);
  });
}
