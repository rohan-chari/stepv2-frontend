import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/race_track.dart';

void main() {
  testWidgets('renders without errors with valid data',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RaceTrack(
            mySteps: 10000,
            theirSteps: 7000,
            myName: 'Alice',
            theirName: 'Bob',

          ),
        ),
      ),
    );

    expect(find.byType(RaceTrack), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RaceTrack),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders with both steps at zero', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RaceTrack(
            mySteps: 0,
            theirSteps: 0,
            myName: 'Alice',
            theirName: 'Bob',

          ),
        ),
      ),
    );

    expect(find.byType(RaceTrack), findsOneWidget);
  });

  testWidgets('renders with tied steps', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RaceTrack(
            mySteps: 5000,
            theirSteps: 5000,
            myName: 'Alice',
            theirName: 'Bob',

          ),
        ),
      ),
    );

    expect(find.byType(RaceTrack), findsOneWidget);
  });

  testWidgets('uses specified height', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RaceTrack(
            mySteps: 8000,
            theirSteps: 4000,
            myName: 'Alice',
            theirName: 'Bob',

            height: 300,
          ),
        ),
      ),
    );

    final sizedBox = tester.widget<SizedBox>(find.descendant(
      of: find.byType(RaceTrack),
      matching: find.byType(SizedBox),
    ));
    expect(sizedBox.height, 300);
  });

  testWidgets('handles empty names gracefully', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RaceTrack(
            mySteps: 5000,
            theirSteps: 3000,
            myName: '',
            theirName: '',

          ),
        ),
      ),
    );

    expect(find.byType(RaceTrack), findsOneWidget);
  });

  testWidgets('handles single character names', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RaceTrack(
            mySteps: 5000,
            theirSteps: 3000,
            myName: 'A',
            theirName: 'B',

          ),
        ),
      ),
    );

    expect(find.byType(RaceTrack), findsOneWidget);
  });
}
