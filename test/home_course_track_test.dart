import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/goal_track.dart';
import 'package:step_tracker/widgets/home_course_track.dart';

void main() {
  testWidgets('renders the horizontal course track with user and friends', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeCourseTrack(
            goalSteps: 8000,
            runners: [
              GoalTrackRunner(
                name: 'You',
                progress: 0.58,
                isUser: true,
                accessories: [
                  {
                    'slot': 'HEAD',
                    'assetKey': 'baseball_cap',
                    'renderMetadata': {
                      'offsetX': -0.01,
                      'offsetY': 0.02,
                      'rotation': -0.08,
                    },
                  },
                ],
              ),
              GoalTrackRunner(name: 'Maya', progress: 0.33),
              GoalTrackRunner(name: 'Chris', progress: 0.81),
            ],
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(HomeCourseTrack), findsOneWidget);
    expect(find.byKey(const Key('home-course-track-scroll')), findsOneWidget);
    expect(
      find.byKey(const Key('home-course-track-legend-scroll')),
      findsOneWidget,
    );
    expect(find.text('You'), findsWidgets);
    expect(
      find.byWidgetPredicate((widget) {
        return widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.contains('baseball_cap.png');
      }),
      findsOneWidget,
    );
  });
}
