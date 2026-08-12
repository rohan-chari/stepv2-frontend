import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/accessory_thumbnail.dart';
import 'package:step_tracker/widgets/global_event_banner.dart';
import 'package:step_tracker/widgets/info_toast.dart';
import 'package:step_tracker/widgets/team_scoreline.dart';

Widget _night(Widget child) =>
    MaterialApp(theme: AppThemeData.night(), home: Scaffold(body: child));

Widget _day(Widget child) =>
    MaterialApp(theme: AppThemeData.light(), home: Scaffold(body: child));

Color? _textColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label).first).style?.color;

/// Rough perceptual distance between two opaque colors — enough to prove a
/// label isn't drowning in the surface it sits on.
double _contrast(Color a, Color b) {
  double lum(Color c) =>
      (0.299 * (c.r * 255) + 0.587 * (c.g * 255) + 0.114 * (c.b * 255));
  return (lum(a) - lum(b)).abs();
}

void main() {
  group('2x global event banner', () {
    testWidgets('night mode text reads against the dark banner surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        _night(
          GlobalEventBanner(
            multiplier: 2,
            endsAt: DateTime.now().add(const Duration(minutes: 26)),
          ),
        ),
      );

      final surface = AppPalette.night.parchmentLight;
      final title = _textColor(tester, '2x RACE STEPS')!;
      final body = _textColor(
        tester,
        'STEPS COUNT 2x IN ALL RACES. GO!',
      )!;

      expect(title, AppPalette.night.textDark);
      expect(_contrast(title, surface), greaterThan(90));
      expect(_contrast(body, surface), greaterThan(60));
    });

    testWidgets('day mode keeps dark ink on the parchment banner', (
      tester,
    ) async {
      await tester.pumpWidget(
        _day(
          GlobalEventBanner(
            multiplier: 2,
            endsAt: DateTime.now().add(const Duration(minutes: 26)),
          ),
        ),
      );

      final surface = AppPalette.light.parchmentLight;
      final title = _textColor(tester, '2x RACE STEPS')!;
      expect(_contrast(title, surface), greaterThan(90));
    });
  });

  group('game toast', () {
    testWidgets('night mode label reads against the dark toast surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        _night(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showInfoToast(context, 'Heads up!'),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final label = _textColor(tester, 'NOTICE')!;
      expect(_contrast(label, AppPalette.night.parchment), greaterThan(60));
    });
  });

  group('team colors', () {
    testWidgets('sides resolve to the night palette in dark mode', (
      tester,
    ) async {
      late BuildContext nightContext;
      await tester.pumpWidget(
        _night(
          Builder(
            builder: (context) {
              nightContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Team A follows the palette's twilight-violet flip; the daytime ochre
      // never appears on the night board.
      expect(
        TeamRace.color(RaceTeam.teamA, nightContext),
        AppPalette.night.pillGold,
      );
      expect(
        TeamRace.color(RaceTeam.teamA, nightContext),
        isNot(TeamColors.teamA),
      );
      expect(
        TeamRace.color(RaceTeam.teamB, nightContext),
        AppPalette.night.pillGreen,
      );
      expect(
        TeamRace.colorDark(RaceTeam.teamA, nightContext),
        AppPalette.night.pillGoldShadow,
      );
      // The two sides stay instantly distinguishable at night.
      expect(
        TeamRace.color(RaceTeam.teamA, nightContext),
        isNot(TeamRace.color(RaceTeam.teamB, nightContext)),
      );
    });

    testWidgets('day mode keeps the locked TR-802 palette', (tester) async {
      late BuildContext dayContext;
      await tester.pumpWidget(
        _day(
          Builder(
            builder: (context) {
              dayContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(TeamRace.color(RaceTeam.teamA, dayContext), TeamColors.teamA);
      expect(TeamRace.colorLight(RaceTeam.teamA, dayContext), TeamColors.teamALight);
      expect(TeamRace.colorDark(RaceTeam.teamA, dayContext), TeamColors.teamADark);
      expect(TeamRace.color(RaceTeam.teamB, dayContext), TeamColors.teamB);
      expect(TeamRace.colorLight(RaceTeam.teamB, dayContext), TeamColors.teamBLight);
      expect(TeamRace.colorDark(RaceTeam.teamB, dayContext), TeamColors.teamBDark);
    });

    testWidgets('the 2v2 format chip gradient follows the theme', (
      tester,
    ) async {
      await tester.pumpWidget(_night(const TeamFormatChip(teamSize: 2)));

      final chip = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('2v2'),
              matching: find.byType(Container),
            )
            .first,
      );
      final gradient =
          (chip.decoration as BoxDecoration).gradient as LinearGradient;
      expect(gradient.colors, [
        AppPalette.night.pillGold,
        AppPalette.night.pillGreen,
      ]);
    });
  });

  group('sprite-sheet thumbnails', () {
    testWidgets('frame 0 is centered in a non-square tile', (tester) async {
      // A 6-frame walk sheet in a WIDER-than-tall tile: the old top-left crop
      // sliced the letterbox instead of the frame and pushed the character to
      // one side.
      const sheet = 'assets/images/corgi_puppy_walk_right_short_ears.png';
      late BuildContext ctx;
      await tester.pumpWidget(
        _day(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Decode the sheet up front — an undecoded Image has no intrinsic size
      // and nothing meaningful to measure.
      await tester.runAsync(
        () => precacheImage(const AssetImage(sheet), ctx),
      );

      await tester.pumpWidget(
        _day(
          const Center(
            child: SizedBox(
              width: 160,
              height: 90,
              child: AccessoryThumbnail(
                assetKey: 'corgi_puppy',
                assetPath: sheet,
                animationFrames: 6,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final tile = tester.getRect(find.byType(AccessoryThumbnail));
      final crop = tester.getRect(find.byType(ClipRect).last);

      expect(crop.center.dx, moreOrLessEquals(tile.center.dx, epsilon: 0.5));
      expect(crop.center.dy, moreOrLessEquals(tile.center.dy, epsilon: 0.5));
      // And it really is one frame, not the whole strip.
      expect(crop.width, lessThan(tile.width));
    });
  });
}
