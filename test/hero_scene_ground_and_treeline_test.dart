import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/home_hero_scene.dart';
import 'package:step_tracker/widgets/onboarding_scene.dart';

// The hero world is the same everywhere: bare sky + a ground strip that is
// always walking. No horizon hedge anywhere, and no scene where the ground
// stands still while the capybara walks in place.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the onboarding scene walks its ground and draws no hedge', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OnboardingScene(headline: 'Connect steps', actions: []),
      ),
    );
    await tester.pump();

    final scene = tester.widget<HomeHeroScene>(find.byType(HomeHeroScene));
    expect(
      scene.groundScrollSpeed,
      isNot(0),
      reason: 'the onboarding ground must scroll like the title screen',
    );

    // The hedge art must not render anywhere in the scene.
    final treelineImages = tester
        .widgetList<Image>(find.byType(Image))
        .where(
          (image) =>
              image.image is AssetImage &&
              (image.image as AssetImage).assetName.contains('treeline'),
        );
    expect(treelineImages, isEmpty);
  });

  test('every HomeHeroScene call site scrolls its ground', () {
    // Structural guard: a new scene that forgets groundScrollSpeed silently
    // falls back to the 0 default and freezes, which is only visible by eye.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!source.contains('HomeHeroScene(')) continue;
      // Skip the widget's own definition.
      if (entity.path.endsWith('home_hero_scene.dart')) continue;

      for (final match in RegExp('HomeHeroScene\\(').allMatches(source)) {
        // Read the constructor's argument list up to its closing paren by
        // walking balanced parens from the opening one.
        var depth = 0;
        var end = match.end - 1;
        for (var i = match.end - 1; i < source.length; i++) {
          if (source[i] == '(') depth++;
          if (source[i] == ')') {
            depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
        }
        final args = source.substring(match.end, end);
        if (!args.contains('groundScrollSpeed')) {
          offenders.add(entity.path);
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'these HomeHeroScene call sites leave the ground frozen',
    );
  });

  test('the hedge widget and its art are gone from the codebase', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('HeroTreeline') || source.contains('hero_treeline')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
