import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/daily_reward_button.dart';

void main() {
  testWidgets('DailyRewardButton shows the unclaimed state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyRewardButton(unclaimed: true, onPressed: () {}),
        ),
      ),
    );

    expect(find.text('Daily reward'), findsOneWidget);
    expect(find.text('Ready to open'), findsOneWidget);
    expect(find.text('CLAIM'), findsOneWidget);
  });

  testWidgets('DailyRewardButton shows the claimed state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyRewardButton(unclaimed: false, onPressed: () {}),
        ),
      ),
    );

    expect(find.text('Daily reward'), findsOneWidget);
    expect(find.text('Today is already claimed'), findsOneWidget);
    expect(find.text('VIEW'), findsOneWidget);
  });
}
