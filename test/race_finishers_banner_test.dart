import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/race_finishers_banner.dart';

void main() {
  testWidgets('RaceFinishersBanner shows arcade-style finisher summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RaceFinishersBanner(finishedCount: 2, targetSteps: 100000),
        ),
      ),
    );

    expect(find.text('2 FINISHERS'), findsOneWidget);
    expect(find.text('CLEARED THE 100,000 STEP LINE'), findsOneWidget);
    expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
  });

  testWidgets('RaceFinishersBanner uses the pill-gold outline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RaceFinishersBanner(finishedCount: 2, targetSteps: 10000),
        ),
      ),
    );

    final expectedColor = AppColors.pillGold.withValues(alpha: 0.9);
    final matchingBorders = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) {
          final decoration = container.decoration;
          if (decoration is! BoxDecoration) return false;
          final border = decoration.border;
          if (border is! Border) return false;
          return border.top.color == expectedColor;
        });

    expect(matchingBorders, isNotEmpty);
  });
}
