import 'dart:math' as math;

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
                  {
                    'slot': 'FACE',
                    'assetKey': 'sunglasses',
                    'renderMetadata': {
                      'offsetX': 0.025,
                      'offsetY': -0.04,
                      'rotation': -0.08,
                      'scale': 1.65,
                    },
                  },
                  {
                    'slot': 'FEET',
                    'assetKey': 'shoes',
                    'renderMetadata': {
                      'offsetX': 0.03,
                      'offsetY': 0.02,
                      'rotation': -0.03,
                      'scale': 1.1,
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
    expect(
      find.byWidgetPredicate((widget) {
        return widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.contains('sunglasses.png');
      }),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((widget) {
        return widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.contains('shoes.png');
      }),
      findsNWidgets(4),
    );
  });

  testWidgets('animates feet accessories with gait-aware shoe rotation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_feetSpriteForFrame(2));

    final angles = _shoeRotationAngles(tester);
    final centers = _shoeCenters(tester);
    final highestShoe = centers.map((center) => center.dy).reduce(math.min);
    final lowestShoe = centers.map((center) => center.dy).reduce(math.max);

    expect(angles, hasLength(4));
    expect(angles.any((angle) => angle > 0.05), isTrue);
    expect(angles.any((angle) => angle < -0.12), isTrue);
    expect(lowestShoe - highestShoe, greaterThan(5));
  });

  testWidgets('renders beaver tail as a frame-synced behind-body sheet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: CapybaraSpriteWithAccessories(
            capybaraSize: 96,
            frameIndex: 4,
            accessories: [
              {
                'slot': 'BACK',
                'assetKey': 'beaver_tail',
                'renderMetadata': {
                  'offsetX': 0,
                  'offsetY': 0,
                  'rotation': 0,
                  'scale': 1,
                  'animationFrames': 6,
                  'renderLayer': 'behind',
                },
              },
            ],
          ),
        ),
      ),
    );

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    final assetNames = images
        .map((image) => (image.image as AssetImage).assetName)
        .toList();

    expect(assetNames[0], contains('accessories/beaver_tail.png'));
    expect(assetNames[1], contains('capybara_walk_right.png'));
    expect(images[0].width, 96 * 6);
    expect(images[0].height, 96);
  });
}

Widget _feetSpriteForFrame(int frameIndex) {
  return MaterialApp(
    home: Center(
      child: CapybaraSpriteWithAccessories(
        capybaraSize: 96,
        frameIndex: frameIndex,
        accessories: const [
          {
            'slot': 'FEET',
            'assetKey': 'shoes',
            'renderMetadata': {
              'offsetX': 0.03,
              'offsetY': 0.02,
              'rotation': -0.03,
              'scale': 1.1,
            },
          },
        ],
      ),
    ),
  );
}

Finder _shoeImageFinder() {
  return find.byWidgetPredicate((widget) {
    return widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName.contains('shoes.png');
  });
}

List<double> _shoeRotationAngles(WidgetTester tester) {
  final transformFinder = find.ancestor(
    of: _shoeImageFinder(),
    matching: find.byType(Transform),
  );
  return tester.widgetList<Transform>(transformFinder).map((transform) {
    final storage = transform.transform.storage;
    return math.atan2(storage[1], storage[0]);
  }).toList();
}

List<Offset> _shoeCenters(WidgetTester tester) {
  final shoes = _shoeImageFinder();
  return List.generate(shoes.evaluate().length, (index) {
    return tester.getCenter(shoes.at(index));
  });
}
