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
    test('night runs from local 8 PM through 6:59 AM', () {
      ThemeMode at(int hour, [int minute = 0]) => AppThemeController.resolve(
        AppThemePreference.automatic,
        DateTime(2026, 8, 26, hour, minute),
      );

      expect(at(6, 59), ThemeMode.dark);
      expect(at(7), ThemeMode.light);
      expect(at(19, 59), ThemeMode.light);
      expect(at(20), ThemeMode.dark);
      expect(AppThemeController.nightStartHour, 20);
      expect(AppThemeController.dayStartHour, 7);
    });

    // These helpers remain a public, tested utility even though automatic
    // appearance now follows the device-local zone instead of US Eastern.
    test(
      'legacy Eastern offset utility keeps distinct DST transition hours',
      () {
        expect(
          AppThemeController.easternOffset(DateTime.utc(2026, 3, 8, 6, 59)),
          const Duration(hours: -5),
        );
        expect(
          AppThemeController.easternOffset(DateTime.utc(2026, 3, 8, 7)),
          const Duration(hours: -4),
        );
        expect(
          AppThemeController.easternOffset(DateTime.utc(2026, 11, 1, 5, 59)),
          const Duration(hours: -4),
        );
        expect(
          AppThemeController.easternOffset(DateTime.utc(2026, 11, 1, 6)),
          const Duration(hours: -5),
        );
        expect(
          AppThemeController.easternOffset(DateTime.utc(2027, 3, 14, 6, 59)),
          const Duration(hours: -5),
        );
        expect(
          AppThemeController.easternOffset(DateTime.utc(2027, 3, 14, 7)),
          const Duration(hours: -4),
        );
        expect(
          AppThemeController.easternOffset(DateTime.utc(2027, 11, 7, 5, 59)),
          const Duration(hours: -4),
        );
        expect(
          AppThemeController.easternOffset(DateTime.utc(2027, 11, 7, 6)),
          const Duration(hours: -5),
        );
      },
    );

    test('boundary timer uses the next local 8 PM / 7 AM edge', () {
      expect(
        AppThemeController.nextBoundaryUtc(DateTime(2026, 8, 26, 12)),
        DateTime(2026, 8, 26, 20),
      );
      // Calendar rollover remains local, including month/year boundaries.
      expect(
        AppThemeController.nextBoundaryUtc(DateTime(2026, 12, 31, 23, 59)),
        DateTime(2027, 1, 1, 7),
      );
      expect(
        AppThemeController.nextBoundaryUtc(DateTime(2028, 2, 29, 19, 59)),
        DateTime(2028, 2, 29, 20),
      );
      expect(
        AppThemeController.nextBoundaryUtc(DateTime(2026, 8, 26, 23)),
        DateTime(2026, 8, 27, 7),
      );
      expect(
        AppThemeController.nextBoundaryUtc(DateTime(2026, 8, 26, 20)),
        DateTime(2026, 8, 27, 7),
      );
    });

    test('controllers resolve from the injected local clock', () {
      final evening = AppThemeController(
        preference: AppThemePreference.automatic,
        clock: () => DateTime(2026, 8, 26, 19, 59),
      );
      addTearDown(evening.dispose);
      expect(evening.resolvedMode, ThemeMode.light);

      final night = AppThemeController(
        preference: AppThemePreference.automatic,
        clock: () => DateTime(2026, 8, 26, 20),
      );
      addTearDown(night.dispose);
      expect(night.resolvedMode, ThemeMode.dark);

      final overnight = AppThemeController(
        preference: AppThemePreference.automatic,
        clock: () => DateTime(2026, 8, 27, 2),
      );
      addTearDown(overnight.dispose);
      expect(overnight.resolvedMode, ThemeMode.dark);
    });

    test('resume recalculates automatic mode from the current local clock', () {
      var now = DateTime(2026, 8, 26, 19, 59);
      final controller = AppThemeController(
        preference: AppThemePreference.automatic,
        clock: () => now,
      );
      addTearDown(controller.dispose);
      expect(controller.resolvedMode, ThemeMode.light);

      now = DateTime(2026, 8, 26, 20);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(controller.resolvedMode, ThemeMode.dark);

      now = DateTime(2026, 8, 27, 7);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(controller.resolvedMode, ThemeMode.light);
    });

    test('manual choice remains authoritative across resume', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 8, 26, 12);
      final controller = AppThemeController(
        preference: AppThemePreference.automatic,
        clock: () => now,
      );
      addTearDown(controller.dispose);
      await controller.setPreference(AppThemePreference.light);

      now = DateTime(2026, 8, 26, 23);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(controller.preference, AppThemePreference.light);
      expect(controller.resolvedMode, ThemeMode.light);
    });

    test('explicit choices ignore the clock', () {
      expect(
        AppThemeController.resolve(
          AppThemePreference.light,
          DateTime.utc(2026, 7, 22, 3),
        ),
        ThemeMode.light,
      );
      expect(
        AppThemeController.resolve(
          AppThemePreference.dark,
          DateTime.utc(2026, 7, 21, 16),
        ),
        ThemeMode.dark,
      );
      // The manual override short-circuits before any clock/timezone work, so
      // it holds at both Eastern boundaries too.
      expect(
        AppThemeController.resolve(
          AppThemePreference.light,
          DateTime.utc(2026, 7, 22, 2),
        ),
        ThemeMode.light,
      );
      expect(
        AppThemeController.resolve(
          AppThemePreference.dark,
          DateTime.utc(2026, 7, 21, 11),
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
      clock: () => DateTime.utc(2026, 7, 21, 16),
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
