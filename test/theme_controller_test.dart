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
    // Batch 2026-08-15 item 1: the window is a fixed 10 PM - 7 AM US-Eastern
    // window shared by every user, not the device's own local hour. Every
    // input below is an explicit UTC instant so the test host's own time zone
    // can never leak into the case under test.
    // (Superseded: the 2026-07-27 item 14 assertions for a *local* 9 PM start,
    // including `nightStartHour == 21`, are intentionally re-pointed here.)
    test('night runs from 10 PM through 6:59 AM Eastern', () {
      // 2026-07-21 is EDT (UTC-4).
      ThemeMode at(DateTime utc) =>
          AppThemeController.resolve(AppThemePreference.automatic, utc);

      // 6:59 AM ET -> still night.
      expect(at(DateTime.utc(2026, 7, 21, 10, 59)), ThemeMode.dark);
      // 7:00 AM ET -> day.
      expect(at(DateTime.utc(2026, 7, 21, 11)), ThemeMode.light);
      expect(at(DateTime.utc(2026, 7, 21, 22, 59)), ThemeMode.light); // 6:59 PM
      expect(at(DateTime.utc(2026, 7, 21, 23)), ThemeMode.light); // 7 PM
      // 9 PM ET is daytime now that night starts at 10 PM.
      expect(at(DateTime.utc(2026, 7, 22, 1)), ThemeMode.light); // 9 PM ET
      expect(at(DateTime.utc(2026, 7, 22, 1, 59)), ThemeMode.light);
      // 10:00 PM ET exactly -> the new night boundary.
      expect(at(DateTime.utc(2026, 7, 22, 2)), ThemeMode.dark);
      expect(at(DateTime.utc(2026, 7, 22, 6)), ThemeMode.dark); // 2 AM ET

      expect(AppThemeController.nightStartHour, 22);
      expect(AppThemeController.dayStartHour, 7);
    });

    test('the trigger point is the UTC instant, not the viewer time zone', () {
      // 2026-07-22 02:00Z is 10 PM ET *and* 7 PM PT on 2026-07-21. A
      // west-coast user flips at the same real-world moment as an east-coast
      // one, at their own local 7 PM.
      expect(
        AppThemeController.resolve(
          AppThemePreference.automatic,
          DateTime.utc(2026, 7, 22, 2),
        ),
        ThemeMode.dark,
      );
      // ...and 7:00 AM ET is 4:00 AM PT: still light for the west coast.
      expect(
        AppThemeController.resolve(
          AppThemePreference.automatic,
          DateTime.utc(2026, 7, 21, 11),
        ),
        ThemeMode.light,
      );
    });

    test('the Eastern offset uses the two distinct UTC transition hours', () {
      // DST starts the 2nd Sunday in March at 07:00 UTC (2026-03-08).
      expect(
        AppThemeController.easternOffset(DateTime.utc(2026, 3, 8, 6, 59)),
        const Duration(hours: -5),
      );
      expect(
        AppThemeController.easternOffset(DateTime.utc(2026, 3, 8, 7)),
        const Duration(hours: -4),
      );
      // DST ends the 1st Sunday in November at 06:00 UTC (2026-11-01) - a
      // different UTC hour than the March transition.
      expect(
        AppThemeController.easternOffset(DateTime.utc(2026, 11, 1, 5, 59)),
        const Duration(hours: -4),
      );
      expect(
        AppThemeController.easternOffset(DateTime.utc(2026, 11, 1, 6)),
        const Duration(hours: -5),
      );
      // A later year with different calendar dates (2027-03-14 / 2027-11-07).
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
    });

    test('resolve honours the DST switch on transition days', () {
      ThemeMode at(DateTime utc) =>
          AppThemeController.resolve(AppThemePreference.automatic, utc);

      // Spring forward day: 11:00Z is 07:00 EDT (light). Reading it as EST
      // would be 06:00 -> dark.
      expect(at(DateTime.utc(2026, 3, 8, 11)), ThemeMode.light);
      expect(at(DateTime.utc(2026, 3, 8, 10, 59)), ThemeMode.dark);

      // Fall back day: 11:00Z is 06:00 EST (dark). Reading it as EDT would be
      // 07:00 -> light.
      expect(at(DateTime.utc(2026, 11, 1, 11)), ThemeMode.dark);
      expect(at(DateTime.utc(2026, 11, 1, 12)), ThemeMode.light);
    });

    test('the boundary timer fires at the next Eastern 10 PM / 7 AM edge', () {
      // 08:00 ET -> the next flip is tonight at 10 PM ET (02:00Z next day).
      expect(
        AppThemeController.nextBoundaryUtc(DateTime.utc(2026, 7, 21, 12)),
        DateTime.utc(2026, 7, 22, 2),
      );
      // 11 PM ET -> the next flip is 7 AM ET the same Eastern day.
      expect(
        AppThemeController.nextBoundaryUtc(DateTime.utc(2026, 7, 22, 3)),
        DateTime.utc(2026, 7, 22, 11),
      );
      // Exactly on a boundary picks the *next* one, never itself.
      expect(
        AppThemeController.nextBoundaryUtc(DateTime.utc(2026, 7, 22, 2)),
        DateTime.utc(2026, 7, 22, 11),
      );
    });

    test('boundary candidates use the offset at the candidate instant', () {
      // Next-day rollover across spring forward: now is 11 PM EST on Mar 7
      // (2026-03-08 04:00Z). The next 7 AM Eastern lands *after* the 07:00Z
      // switch, so it is 11:00Z (EDT), not 12:00Z (EST).
      expect(
        AppThemeController.nextBoundaryUtc(DateTime.utc(2026, 3, 8, 4)),
        DateTime.utc(2026, 3, 8, 11),
      );
      // Same-day candidate on the transition day itself: now is 04:00 EDT.
      expect(
        AppThemeController.nextBoundaryUtc(DateTime.utc(2026, 3, 8, 8)),
        DateTime.utc(2026, 3, 8, 11),
      );
      // Next-day rollover across fall back: now is 11 PM EDT on Oct 31
      // (2026-11-01 03:00Z). The next 7 AM Eastern is after the 06:00Z switch,
      // so it is 12:00Z (EST), not 11:00Z (EDT).
      expect(
        AppThemeController.nextBoundaryUtc(DateTime.utc(2026, 11, 1, 3)),
        DateTime.utc(2026, 11, 1, 12),
      );
      // And the 10 PM edge on the fall-back day is 03:00Z the next day (EST).
      expect(
        AppThemeController.nextBoundaryUtc(DateTime.utc(2026, 11, 1, 20)),
        DateTime.utc(2026, 11, 2, 3),
      );
    });

    test('controllers resolve from the injected UTC clock', () {
      // 9 PM ET -> light under the new 10 PM boundary.
      final evening = AppThemeController(
        preference: AppThemePreference.automatic,
        clock: () => DateTime.utc(2026, 7, 22, 1),
      );
      addTearDown(evening.dispose);
      expect(evening.resolvedMode, ThemeMode.light);

      // 10:00 PM ET exactly resolves dark.
      final night = AppThemeController(
        preference: AppThemePreference.automatic,
        clock: () => DateTime.utc(2026, 7, 22, 2),
      );
      addTearDown(night.dispose);
      expect(night.resolvedMode, ThemeMode.dark);

      // Past midnight is still night until 7 AM ET.
      final small = AppThemeController(
        preference: AppThemePreference.automatic,
        clock: () => DateTime.utc(2026, 7, 22, 7),
      );
      addTearDown(small.dispose);
      expect(small.resolvedMode, ThemeMode.dark);
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
