import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/team_lobby_board.dart';

// Issue 2: the hop animation's geometry is extracted into pure functions so the
// arc math is unit-testable without a render tree. Slots are uniform, so any
// slot center (including the departed "from" slot that no longer exists in the
// widget tree after the rebuild) is computed analytically from the measured
// column width + the fixed slot metrics and the known indices.

void main() {
  group('lobbySlotCenter — analytic slot geometry', () {
    const columnWidth = 150.0;
    const slotHeight = 64.0;
    const slotGap = 8.0;
    const columnGap = 12.0;

    test('Team A slot 0 sits at the left column mid, half a slot down', () {
      final c = lobbySlotCenter(
        team: RaceTeam.teamA,
        index: 0,
        columnWidth: columnWidth,
        slotHeight: slotHeight,
        slotGap: slotGap,
        columnGap: columnGap,
      );
      expect(c.dx, columnWidth / 2);
      expect(c.dy, slotHeight / 2);
    });

    test('Team B is offset by a full column + the gap', () {
      final a = lobbySlotCenter(
        team: RaceTeam.teamA,
        index: 0,
        columnWidth: columnWidth,
        slotHeight: slotHeight,
        slotGap: slotGap,
        columnGap: columnGap,
      );
      final b = lobbySlotCenter(
        team: RaceTeam.teamB,
        index: 0,
        columnWidth: columnWidth,
        slotHeight: slotHeight,
        slotGap: slotGap,
        columnGap: columnGap,
      );
      expect(b.dx - a.dx, columnWidth + columnGap);
      expect(b.dy, a.dy);
    });

    test('each slot index steps down by slotHeight + slotGap', () {
      final s0 = lobbySlotCenter(
        team: RaceTeam.teamA,
        index: 0,
        columnWidth: columnWidth,
        slotHeight: slotHeight,
        slotGap: slotGap,
        columnGap: columnGap,
      );
      final s2 = lobbySlotCenter(
        team: RaceTeam.teamA,
        index: 2,
        columnWidth: columnWidth,
        slotHeight: slotHeight,
        slotGap: slotGap,
        columnGap: columnGap,
      );
      expect(s2.dy - s0.dy, 2 * (slotHeight + slotGap));
    });
  });

  group('lobbyHopPosition — single-easing parabolic arc', () {
    const from = Offset(75, 288); // Team A slot 3-ish
    const to = Offset(237, 32); // Team B slot 0-ish

    test('anchors exactly on the from/to slots at the endpoints', () {
      expect(lobbyHopPosition(from: from, to: to, t: 0), from);
      expect(lobbyHopPosition(from: from, to: to, t: 1), to);
    });

    test('at the midpoint it is horizontally centered and arcing upward', () {
      final mid = lobbyHopPosition(from: from, to: to, t: 0.5);
      // Horizontal midpoint (easeInOut is symmetric at 0.5).
      expect(mid.dx, closeTo((from.dx + to.dx) / 2, 0.001));
      // The arc lifts the capy above the straight-line midpoint by exactly the
      // scaled peak (smaller y == higher on screen).
      final lineMidY = (from.dy + to.dy) / 2;
      expect(mid.dy, closeTo(lineMidY - lobbyHopPeak(from, to), 0.001));
      expect(mid.dy, lessThan(lineMidY));
    });

    test('t is clamped so out-of-range values never throw', () {
      expect(lobbyHopPosition(from: from, to: to, t: -1), from);
      expect(lobbyHopPosition(from: from, to: to, t: 2), to);
    });
  });

  group('lobbyHopPeak — distance-scaled arc height', () {
    test('a longer jump peaks higher than a short one (until clamped)', () {
      final shortPeak = lobbyHopPeak(const Offset(0, 0), const Offset(0, 40));
      final longPeak = lobbyHopPeak(const Offset(0, 0), const Offset(0, 200));
      expect(longPeak, greaterThan(shortPeak));
    });

    test('peak stays within sane clamps', () {
      final tiny = lobbyHopPeak(const Offset(0, 0), const Offset(0, 1));
      final huge = lobbyHopPeak(const Offset(0, 0), const Offset(0, 5000));
      expect(tiny, greaterThanOrEqualTo(46.0));
      expect(huge, lessThanOrEqualTo(140.0));
    });
  });
}
