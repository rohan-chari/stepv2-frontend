import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/fire_aura.dart';
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
  testWidgets('buff multiplier shows an "Nx" badge and a fire aura', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(3));
    await tester.pump();

    expect(find.text('3x'), findsOneWidget);
    expect(find.byType(FireAura), findsOneWidget);
    final fire = tester.widget<FireAura>(find.byType(FireAura));
    expect(fire.tier, 3);
  });

  testWidgets('higher multiplier scales the fire tier', (tester) async {
    await tester.pumpWidget(_wrap(5));
    await tester.pump();

    expect(find.text('5x'), findsOneWidget);
    expect(tester.widget<FireAura>(find.byType(FireAura)).tier, 5);
  });

  testWidgets('frozen (0) shows a frost chip and no fire', (tester) async {
    await tester.pumpWidget(_wrap(0));
    await tester.pump();

    expect(find.text('FROZEN'), findsOneWidget);
    expect(find.byType(FireAura), findsNothing);
  });

  testWidgets('reversed (<0) shows a reversed chip and no fire', (tester) async {
    await tester.pumpWidget(_wrap(-2));
    await tester.pump();

    expect(find.text('2x'), findsOneWidget);
    expect(find.byIcon(Icons.u_turn_left_rounded), findsOneWidget);
    expect(find.byType(FireAura), findsNothing);
  });

  testWidgets('neutral (1) renders no chip and no fire', (tester) async {
    await tester.pumpWidget(_wrap(1));
    await tester.pump();

    expect(find.textContaining('x'), findsNothing);
    expect(find.byType(FireAura), findsNothing);
  });

  testWidgets('absent multiplier renders nothing new (old backend)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(null));
    await tester.pump();

    expect(find.byType(FireAura), findsNothing);
    expect(find.byIcon(Icons.ac_unit_rounded), findsNothing);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
  });

  testWidgets('a stealthed runner never shows a badge or fire', (tester) async {
    await tester.pumpWidget(_wrap(4, stealthed: true));
    await tester.pump();

    expect(find.byType(FireAura), findsNothing);
    expect(find.text('4x'), findsNothing);
  });
}
