import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/theme_controller.dart';

double _relativeLuminance(Color color) {
  double channel(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final values = [_relativeLuminance(a), _relativeLuminance(b)]..sort();
  return (values.last + 0.05) / (values.first + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('automatic appearance schedule', () {
    test('night runs from 7 PM through 6:59 AM local time', () {
      expect(
        AppThemeController.resolve(
          AppThemePreference.automatic,
          DateTime(2026, 7, 21, 6, 59),
        ),
        ThemeMode.dark,
      );
      expect(
        AppThemeController.resolve(
          AppThemePreference.automatic,
          DateTime(2026, 7, 21, 7),
        ),
        ThemeMode.light,
      );
      expect(
        AppThemeController.resolve(
          AppThemePreference.automatic,
          DateTime(2026, 7, 21, 18, 59),
        ),
        ThemeMode.light,
      );
      expect(
        AppThemeController.resolve(
          AppThemePreference.automatic,
          DateTime(2026, 7, 21, 19),
        ),
        ThemeMode.dark,
      );
    });

    test('explicit choices ignore the clock', () {
      expect(
        AppThemeController.resolve(
          AppThemePreference.light,
          DateTime(2026, 7, 21, 23),
        ),
        ThemeMode.light,
      );
      expect(
        AppThemeController.resolve(
          AppThemePreference.dark,
          DateTime(2026, 7, 21, 12),
        ),
        ThemeMode.dark,
      );
    });
  });

  test('preference defaults safely and persists locally', () async {
    SharedPreferences.setMockInitialValues({});
    expect(
      await AppThemeController.loadPreference(),
      AppThemePreference.automatic,
    );

    final controller = AppThemeController(
      preference: AppThemePreference.automatic,
      clock: () => DateTime(2026, 7, 21, 12),
    );
    addTearDown(controller.dispose);
    await controller.setPreference(AppThemePreference.dark);

    expect(controller.resolvedMode, ThemeMode.dark);
    expect(await AppThemeController.loadPreference(), AppThemePreference.dark);
  });

  testWidgets('theme extensions expose matching palettes and scene assets', (
    tester,
  ) async {
    late AppPalette palette;
    late AppThemeAssets assets;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.night(),
        home: Builder(
          builder: (context) {
            palette = AppColors.of(context);
            assets = AppThemeAssets.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(palette.isDark, isTrue);
    expect(assets.homeHeroSky, endsWith('_night.png'));
    expect(assets.homeHeroGround, endsWith('_night.png'));
    expect(assets.homeCourse, endsWith('_night.png'));
    expect(assets.raceDayCourse, endsWith('_night.png'));
  });

  test('night body and button text meet WCAG AA contrast', () {
    final colors = AppPalette.night;
    expect(_contrast(colors.textDark, colors.parchment), greaterThan(4.5));
    expect(_contrast(colors.textMid, colors.parchment), greaterThan(4.5));
    expect(_contrast(colors.buttonText, colors.buttonFace), greaterThan(4.5));
    expect(_contrast(colors.textDark, colors.pillGold), greaterThan(4.5));
    expect(_contrast(colors.textMid, colors.roofDark), greaterThan(4.5));
    expect(_contrast(colors.textLight, colors.roofLight), greaterThan(4.5));
    expect(_contrast(colors.textLight, colors.woodDarker), greaterThan(4.5));
    expect(_contrast(colors.successText, colors.parchment), greaterThan(4.5));
    expect(
      _contrast(colors.successText, colors.parchmentLight),
      greaterThan(4.5),
    );
    expect(_contrast(colors.feedGold, colors.parchment), greaterThan(4.5));
    for (final medal in [
      colors.medalGold,
      colors.medalSilver,
      colors.medalBronze,
    ]) {
      expect(_contrast(colors.textDark, medal), greaterThan(4.5));
    }
    expect(_contrast(colors.buttonText, colors.pillTerra), greaterThan(4.5));
    expect(_contrast(colors.textLight, colors.pillGreenDark), greaterThan(4.5));
    expect(
      _contrast(colors.emptySlotLabel, colors.emptySlotFace),
      greaterThan(4.5),
    );
    expect(
      _contrast(colors.emptySlotMark, colors.emptySlotFace),
      greaterThan(3),
    );
    for (final accent in [
      colors.feedAttack,
      colors.feedShield,
      colors.feedGold,
      colors.feedBoost,
    ]) {
      expect(_contrast(accent, colors.parchment), greaterThan(3));
    }
  });
}
