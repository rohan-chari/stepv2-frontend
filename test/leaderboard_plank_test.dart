import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/leaderboard_plank.dart';

void main() {
  testWidgets('LeaderboardPlank renders finished badge for completed runner', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LeaderboardPlank(
            rank: 0,
            name: 'Sugaroro',
            steps: 100000,
            formattedSteps: '100,000',
            isFinished: true,
            finishPlace: 1,
          ),
        ),
      ),
    );

    expect(find.text('1ST FINISH'), findsOneWidget);
  });

  testWidgets('LeaderboardPlank hides finished badge for active runner', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LeaderboardPlank(
            rank: 1,
            name: 'Shefali G',
            steps: 98765,
            formattedSteps: '98,765',
          ),
        ),
      ),
    );

    expect(find.text('1ST FINISH'), findsNothing);
  });
}
