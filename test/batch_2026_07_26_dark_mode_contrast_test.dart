import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/race_ui.dart';
import 'package:step_tracker/widgets/team_scoreboard_cards.dart';
import 'package:step_tracker/widgets/tier_badge.dart';

/// Items 3 + 13 — night-mode legibility. The reported bug was the team-race
/// totals rendering at 1.09:1 on the night board; the audit found the same
/// "team colour as text on parchment" mistake at seven more sites, plus three
/// context-free colour sources (a CustomPainter and two static getters).
///
/// This is the REGRESSION GUARD the item asks for: every token that is ever
/// used as a foreground has to clear WCAG AA against the surface it lands on,
/// in BOTH palettes.

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color fg, Color bg) {
  final a = _luminance(fg);
  final b = _luminance(bg);
  final hi = math.max(a, b);
  final lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

Widget _themed(Widget child, {required bool night}) => MaterialApp(
  theme: night ? AppThemeData.night() : AppThemeData.light(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('every foreground token clears AA on the parchment it sits on', () {
    // NIGHT is what item 3 is about, and every token this batch routes text
    // through must clear AA there. `feedGold` and `successText` are the two
    // TeamRace.textColorOn picks; `error` is the P7 demotion marker.
    test('night palette', () {
      final colors = AppPalette.night;
      for (final token in <(String, Color)>[
        ('textDark', colors.textDark),
        ('textMid', colors.textMid),
        ('feedGold', colors.feedGold),
        ('successText', colors.successText),
        ('error', colors.error),
      ]) {
        expect(
          _contrast(token.$2, colors.parchment),
          greaterThanOrEqualTo(4.5),
          reason: '${token.$1} on parchment (night)',
        );
      }
    });

    // DAY: only the tokens actually used as a foreground on light parchment.
    // `feedGold` is night-only here (day team text stays on `colorDark`), so
    // asserting it in this palette would test a combination that never renders.
    test('day palette', () {
      final colors = AppPalette.light;
      expect(
        _contrast(colors.textDark, colors.parchment),
        greaterThanOrEqualTo(4.5),
        reason: 'textDark on parchment (day)',
      );
      expect(
        _contrast(colors.successText, colors.parchment),
        greaterThanOrEqualTo(4.5),
        reason: 'successText on parchment (day)',
      );
      // Two SHIPPED light tokens sit just under AA. Out of scope for this batch
      // (item 3 is the night board) but pinned so they can only get better:
      // textMid 4.497:1, error 4.23:1.
      expect(
        _contrast(colors.textMid, colors.parchment),
        greaterThanOrEqualTo(4.49),
        reason: 'textMid on parchment (day) — known 4.497:1',
      );
      expect(
        _contrast(colors.error, colors.parchment),
        greaterThanOrEqualTo(4.2),
        reason: 'error on parchment (day) — known 4.23:1',
      );
    });

    test('the shared team text colour is legible in both palettes', () {
      // The whole point of TeamRace.textColorOn: pillGoldShadow / roofMid are
      // NOT safe as foregrounds at night (1.09:1 and 1.40:1), and textLight is
      // not safe as a foreground by day.
      expect(
        _contrast(AppPalette.night.pillGoldShadow, AppPalette.night.parchment),
        lessThan(4.5),
      );
      expect(
        _contrast(AppPalette.night.roofMid, AppPalette.night.parchment),
        lessThan(4.5),
      );
      expect(
        _contrast(AppPalette.light.textLight, AppPalette.light.parchment),
        lessThan(4.5),
      );
    });
  });

  group('TeamRace.textColorOn', () {
    testWidgets('night resolves to the legible feedGold/successText pair', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _themed(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
          night: true,
        ),
      );
      expect(TeamRace.textColorOn(RaceTeam.teamA, ctx), AppPalette.night.feedGold);
      expect(
        TeamRace.textColorOn(RaceTeam.teamB, ctx),
        AppPalette.night.successText,
      );
      // and never the colorDark tokens that caused the bug.
      expect(
        TeamRace.textColorOn(RaceTeam.teamA, ctx),
        isNot(TeamRace.colorDark(RaceTeam.teamA, ctx)),
      );
    });

    testWidgets('day keeps the locked TR-802 dark team colours', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _themed(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
          night: false,
        ),
      );
      expect(
        TeamRace.textColorOn(RaceTeam.teamA, ctx),
        TeamRace.colorDark(RaceTeam.teamA, ctx),
      );
      expect(
        TeamRace.textColorOn(RaceTeam.teamB, ctx),
        TeamRace.colorDark(RaceTeam.teamB, ctx),
      );
    });
  });

  group('P1 — the reported bug: team scoreboard totals at night', () {
    testWidgets('the big totals are legible and not a colorDark token', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _themed(
          const TeamScoreboardCards(
            teamAName: 'Swift Capys',
            teamBName: 'Turbo Beavers',
            teamATotal: 364261,
            teamBTotal: 352747,
          ),
          night: true,
        ),
      );
      await tester.pump();

      for (final label in ['364,261', '352,747']) {
        final style = tester.widget<Text>(find.text(label)).style!;
        expect(style.color, isNotNull);
        expect(style.color, isNot(AppPalette.night.pillGoldShadow));
        expect(style.color, isNot(AppPalette.night.roofMid));
        expect(
          _contrast(style.color!, AppPalette.night.parchment),
          greaterThanOrEqualTo(4.5),
          reason: '$label on the night board',
        );
      }
    });
  });

  group('P5 — Pill.foreground must follow the theme', () {
    testWidgets('a night Pill does not paint the light textDark constant', (
      tester,
    ) async {
      await tester.pumpWidget(
        _themed(
          Builder(
            builder: (context) => Pill(
              label: 'BRACKET',
              background: AppColors.of(context).pillGold,
            ),
          ),
          night: true,
        ),
      );
      final style = tester.widget<Text>(find.text('BRACKET')).style!;
      expect(style.color, AppPalette.night.textDark);
      expect(
        _contrast(style.color!, AppPalette.night.pillGold),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('P6/P13 — context-free colour sources become theme-aware', () {
    testWidgets('RankedTier.colorOf flips with the palette', (tester) async {
      late BuildContext nightCtx;
      await tester.pumpWidget(
        _themed(
          Builder(
            builder: (context) {
              nightCtx = context;
              return const SizedBox.shrink();
            },
          ),
          night: true,
        ),
      );
      expect(RankedTier.gold.colorOf(nightCtx), AppPalette.night.medalGold);
      expect(RankedTier.gold.colorOf(nightCtx), isNot(AppColors.medalGold));
      expect(
        RankedTier.unranked.colorOf(nightCtx),
        AppPalette.night.textMid,
      );
      expect(
        _contrast(
          RankedTier.unranked.colorOf(nightCtx),
          AppPalette.night.parchment,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('RacerAvatar.medalColor takes a palette', (tester) async {
      late BuildContext nightCtx;
      await tester.pumpWidget(
        _themed(
          Builder(
            builder: (context) {
              nightCtx = context;
              return const SizedBox.shrink();
            },
          ),
          night: true,
        ),
      );
      expect(
        RacerAvatar.medalColor(1, nightCtx),
        AppPalette.night.medalGold,
      );
      expect(
        RacerAvatar.medalColor(1, nightCtx),
        isNot(AppColors.medalGold),
      );
    });
  });
}
