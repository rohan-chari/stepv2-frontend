import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/goal_track.dart';

void main() {
  testWidgets('renders with user only', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GoalTrack(
            runners: [GoalTrackRunner(name: 'Alice', progress: 0.5, isUser: true)],
          ),
        ),
      ),
    );

    expect(find.byType(GoalTrack), findsOneWidget);
  });

  testWidgets('renders with user and friends', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GoalTrack(
            runners: [
              GoalTrackRunner(name: 'Alice', progress: 0.6, isUser: true),
              GoalTrackRunner(name: 'Bob', progress: 0.3),
              GoalTrackRunner(name: 'Charlie', progress: 0.8),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(GoalTrack), findsOneWidget);
  });

  testWidgets('renders with all at zero', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GoalTrack(
            runners: [
              GoalTrackRunner(name: 'Alice', progress: 0.0, isUser: true),
              GoalTrackRunner(name: 'Bob', progress: 0.0),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(GoalTrack), findsOneWidget);
  });

  testWidgets('renders with empty runners list', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GoalTrack(runners: []),
        ),
      ),
    );

    expect(find.byType(GoalTrack), findsOneWidget);
  });
}
