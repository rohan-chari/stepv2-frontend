import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/start_screen.dart';
import 'package:step_tracker/widgets/home_hero_scene.dart';

/// The home hero's capybara walks in place; sliding the tiled ground strip
/// left is what sells "moving forward". These pump the real scene and read the
/// strip's actual transform rather than any helper.
Finder _groundTransform() => find
    .ancestor(
      of: find.byKey(const Key('hero-ground-strip')),
      matching: find.byType(Transform),
    )
    .first;

double _dx(WidgetTester tester) =>
    tester.widget<Transform>(_groundTransform()).transform.getTranslation().x;

Future<void> _pump(
  WidgetTester tester, {
  required double speed,
  bool disableAnimations = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: HomeHeroScene(
            groundHeight: 84,
            groundScrollSpeed: speed,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('ground strip slides left over time', (tester) async {
    await _pump(tester, speed: 26);
    final start = _dx(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final later = _dx(tester);
    expect(later, lessThan(start));
    // 26 px/s for half a second, give or take a frame.
    expect(later - start, closeTo(-13, 2));
  });

  testWidgets('scroll wraps by exactly one tile, never drifting away', (
    tester,
  ) async {
    await _pump(tester, speed: 26);
    // Tile width = srcWidth * groundHeight / srcHeight = 1350 * 84 / 164.
    const tileW = 1350.0 * 84 / 164;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(seconds: 1));
      final dx = _dx(tester);
      expect(dx, lessThanOrEqualTo(0));
      expect(dx, greaterThan(-tileW));
    }
  });

  testWidgets('speed 0 renders a static strip (no transform)', (tester) async {
    await _pump(tester, speed: 0);
    expect(
      find.ancestor(
        of: find.byKey(const Key('hero-ground-strip')),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('frozen when animations are disabled', (tester) async {
    await _pump(tester, speed: 26, disableAnimations: true);
    final start = _dx(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(_dx(tester), start);
  });

  testWidgets('clouds drift opposite the ground, for parallax', (tester) async {
    await _pump(tester, speed: 26);
    // Sample one cloud mid-span (it can't wrap inside the window), so the
    // sign of its movement is unambiguous.
    double cloudX() => tester
        .widget<Positioned>(
          find
              .descendant(
                of: find.byKey(const ValueKey('home-cloud-0')),
                matching: find.byType(Positioned),
              )
              .first,
        )
        .left!;

    final cloudStart = cloudX();
    final groundStart = _dx(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_dx(tester) - groundStart, lessThan(0), reason: 'ground goes left');
    expect(
      cloudX() - cloudStart,
      lessThan(0),
      reason: 'clouds follow the ground more slowly',
    );
  });

  testWidgets('the title screen scrolls its ground too', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: StartScreen()));
    await tester.pump();
    final scene = tester.widget<HomeHeroScene>(find.byType(HomeHeroScene));
    expect(scene.groundScrollSpeed, greaterThan(0));

    final start = _dx(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_dx(tester), lessThan(start));
  });
}
