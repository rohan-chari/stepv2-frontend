import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/config/animals.dart';
import 'package:step_tracker/widgets/goal_track.dart';
import 'package:step_tracker/widgets/home_course_track.dart';

// ---------------------------------------------------------------------------
// Every base character stands on the SAME ground line.
//
// The walk sheets pad their subjects differently inside the frame box: the
// capybara's feet sit 50/64 down the frame, the corgi's 56/64, the turtle's
// 69/88. Drawn in identically sized boxes with no correction, the corgi sinks
// ~9% of a frame below the capybara on the home course — visible when a corgi
// friend and a capybara friend stand side by side.
//
// `AnimalSprite.baselineOffset` corrects that at render time. These tests pump
// the REAL widgets and compute where each sheet's feet land on screen, so they
// fail if the correction is dropped or a new animal ships unaligned.
// ---------------------------------------------------------------------------

/// Row of the frame (as a fraction of frame height) where the subject's feet
/// are, measured from the shipped PNGs' per-frame alpha bounding boxes.
const _feetFractionBySheet = <String, double>{
  'assets/images/capybara_walk_right.png': 50 / 64,
  'assets/images/corgi_puppy_walk_right_short_ears.png': 56 / 64,
  'assets/images/turtle_walk_right.png': 69 / 88,
};

/// Global y of the ground the given animal's sprite is standing on, as laid
/// out by the real widget tree.
double _feetY(WidgetTester tester, String? animal, {required double size}) {
  final asset = animalSpriteFor(animal).asset;
  final image = find.byWidgetPredicate(
    (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == asset,
  );
  expect(image, findsOneWidget, reason: 'expected the $animal sheet to render');
  // The sheet is laid out at height == frame size, so the feet row scales
  // directly off the rendered box.
  return tester.getTopLeft(image).dy + _feetFractionBySheet[asset]! * size;
}

Future<void> _pumpSprite(
  WidgetTester tester,
  String? animal, {
  required double size,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: CapybaraSpriteWithAccessories(
            accessories: const [],
            capybaraSize: size,
            frameIndex: 0,
            animal: animal,
          ),
        ),
      ),
    ),
  );
}

void main() {
  const size = 64.0;

  testWidgets('corgi feet land on the same line as the capybara', (
    tester,
  ) async {
    await _pumpSprite(tester, null, size: size);
    final capybaraGround = _feetY(tester, null, size: size);

    await _pumpSprite(tester, 'corgi_puppy', size: size);
    final corgiGround = _feetY(tester, 'corgi_puppy', size: size);

    expect(corgiGround, moreOrLessEquals(capybaraGround, epsilon: 0.5));
  });

  testWidgets('turtle feet land on the same line as the capybara', (
    tester,
  ) async {
    await _pumpSprite(tester, null, size: size);
    final capybaraGround = _feetY(tester, null, size: size);

    await _pumpSprite(tester, 'turtle', size: size);
    final turtleGround = _feetY(tester, 'turtle', size: size);

    expect(turtleGround, moreOrLessEquals(capybaraGround, epsilon: 0.5));
  });

  testWidgets('alignment holds at the larger home-course user size', (
    tester,
  ) async {
    const bigger = 55.0 * 1.4;
    await _pumpSprite(tester, null, size: bigger);
    final capybaraGround = _feetY(tester, null, size: bigger);

    await _pumpSprite(tester, 'corgi_puppy', size: bigger);
    final corgiGround = _feetY(tester, 'corgi_puppy', size: bigger);

    expect(corgiGround, moreOrLessEquals(capybaraGround, epsilon: 0.5));
  });

  testWidgets(
    'an unknown animal falls back to the capybara and stays aligned',
    (tester) async {
      await _pumpSprite(tester, null, size: size);
      final capybaraGround = _feetY(tester, null, size: size);

      // A newer backend may send an animal this frozen build does not bundle.
      await _pumpSprite(tester, 'unbundled_future_animal', size: size);
      final fallbackGround = _feetY(
        tester,
        'unbundled_future_animal',
        size: size,
      );

      expect(fallbackGround, moreOrLessEquals(capybaraGround, epsilon: 0.5));
    },
  );

  testWidgets('equipped accessories ride the ground-line correction', (
    tester,
  ) async {
    // The correction is applied to the body sheet and to each accessory
    // overlay separately, so gear must move by the SAME amount as the body or
    // a corgi's hat floats off its head.
    const accessories = [
      {
        'slot': 'HEAD',
        'assetKey': 'baseball_cap',
        'renderMetadata': <String, dynamic>{},
      },
      {
        'slot': 'BACK',
        'assetKey': 'beaver_tail',
        'renderMetadata': <String, dynamic>{'renderLayer': 'behind'},
      },
    ];

    Future<Map<String, Offset>> topLefts(String? animal) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: CapybaraSpriteWithAccessories(
                accessories: const [...accessories],
                capybaraSize: size,
                frameIndex: 0,
                animal: animal,
              ),
            ),
          ),
        ),
      );
      final result = <String, Offset>{};
      for (final key in ['baseball_cap', 'beaver_tail']) {
        final finder = find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName.contains('$key.png'),
        );
        expect(finder, findsOneWidget, reason: 'expected $key to render');
        result[key] = tester.getTopLeft(finder);
      }
      result['body'] = tester.getTopLeft(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName ==
                  animalSpriteFor(animal).asset,
        ),
      );
      return result;
    }

    final capybara = await topLefts(null);
    final corgi = await topLefts('corgi_puppy');

    final bodyShift = corgi['body']!.dy - capybara['body']!.dy;
    expect(bodyShift, moreOrLessEquals(-6.0, epsilon: 0.01));
    for (final key in ['baseball_cap', 'beaver_tail']) {
      expect(
        corgi[key]!.dy - capybara[key]!.dy,
        moreOrLessEquals(bodyShift, epsilon: 0.01),
        reason: '$key must move with the body',
      );
    }
  });

  testWidgets('corgi and capybara share a ground line on the home course', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeCourseTrack(
            goalSteps: 8000,
            runners: [
              GoalTrackRunner(name: 'You', progress: 0.5, isUser: true),
              GoalTrackRunner(
                name: 'Corgi Friend',
                progress: 0.5,
                animal: 'corgi_puppy',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));

    // Runner sprite sizes differ (the user renders larger), so compare each
    // sheet's feet using its own rendered box height.
    double groundFor(String asset) {
      final finder = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == asset,
      );
      expect(finder, findsOneWidget);
      final box = tester.getRect(finder);
      return box.top + _feetFractionBySheet[asset]! * box.height;
    }

    final capybaraGround = groundFor('assets/images/capybara_walk_right.png');
    final corgiGround = groundFor(
      'assets/images/corgi_puppy_walk_right_short_ears.png',
    );

    expect(corgiGround, moreOrLessEquals(capybaraGround, epsilon: 1.5));
  });
}
