// Feature batch 2026-08-08 — Item 18: stealth standings "1 2 1 2" fix.
//
// Root cause: the backend nulls `placement` on stealthed rows, and
// `orderRaceParticipantsForDisplay` was all-or-nothing — one null placement
// made EVERY row fall back to index ranks, so stealthed rows rendered their
// array index (1, 2) while visible rows rendered server placement (1, 2, 3).
//
// The fix has two halves, both covered here:
//   * ordering — partial-null (stealth) keeps server placement for the rows
//     that have one; ALL-null (Detour Sign) keeps the wholesale fallback.
//   * rendering — a stealthed row shows "?" on its shield, never a number.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/race_participant_display.dart';
import 'package:step_tracker/widgets/leaderboard_plank.dart';

Map<String, dynamic> _p(
  String userId, {
  int? placement,
  bool stealthed = false,
  int steps = 0,
}) {
  return <String, dynamic>{
    'userId': userId,
    'displayName': userId,
    'totalSteps': steps,
    'stealthed': stealthed,
    'finishedAt': null,
    if (placement != null) 'placement': placement,
  };
}

List<String> _ids(List<Map<String, dynamic>> rows) =>
    rows.map((r) => r['userId'] as String).toList();

void main() {
  group('Item 18 — ordering with partially-masked placements', () {
    test(
      'stealthed rows pin to the top and visible rows keep server placement',
      () {
        // Server sort order: stealthed first, then by placement. The stealthed
        // rows carry NO placement (backend masks it).
        final participants = <Map<String, dynamic>>[
          _p('stealth-a', stealthed: true, steps: 900),
          _p('stealth-b', stealthed: true, steps: 800),
          _p('visible-1', placement: 1, steps: 700),
          _p('visible-2', placement: 2, steps: 600),
          _p('visible-3', placement: 3, steps: 500),
        ];

        final ordered = orderRaceParticipantsForDisplay(participants);

        expect(_ids(ordered), [
          'stealth-a',
          'stealth-b',
          'visible-1',
          'visible-2',
          'visible-3',
        ]);
      },
    );

    test('visible rows are ordered by placement, not payload order', () {
      final participants = <Map<String, dynamic>>[
        _p('visible-3', placement: 3, steps: 500),
        _p('stealth-a', stealthed: true, steps: 900),
        _p('visible-1', placement: 1, steps: 700),
        _p('visible-2', placement: 2, steps: 600),
      ];

      final ordered = orderRaceParticipantsForDisplay(participants);

      expect(_ids(ordered), [
        'stealth-a',
        'visible-1',
        'visible-2',
        'visible-3',
      ]);
    });

    test(
      'a non-stealthed row that is missing a placement sorts after placed rows',
      () {
        final participants = <Map<String, dynamic>>[
          _p('no-placement', steps: 10),
          _p('visible-2', placement: 2, steps: 600),
          _p('stealth-a', stealthed: true, steps: 900),
          _p('visible-1', placement: 1, steps: 700),
        ];

        final ordered = orderRaceParticipantsForDisplay(participants);

        expect(_ids(ordered), [
          'stealth-a',
          'visible-1',
          'visible-2',
          'no-placement',
        ]);
      },
    );

    test('Detour Sign — ALL placements null keeps the wholesale fallback', () {
      // Detour Sign nulls `placement` on EVERY row with stealthed:false. The
      // scrambled/unranked look is the intended illusion, so we must keep the
      // pre-existing client-side comparator (steps-descending) rather than
      // deriving per-row index ranks.
      final participants = <Map<String, dynamic>>[
        _p('low', steps: 100),
        _p('high', steps: 900),
        _p('mid', steps: 500),
      ];

      final ordered = orderRaceParticipantsForDisplay(participants);

      expect(_ids(ordered), _ids(sortRaceParticipantsForDisplay(participants)));
      expect(_ids(ordered), ['high', 'mid', 'low']);
    });

    test('every row placed — unchanged behaviour (regression guard)', () {
      final participants = <Map<String, dynamic>>[
        _p('c', placement: 3, steps: 1),
        _p('a', placement: 1, steps: 2),
        _p('b', placement: 2, steps: 3),
      ];

      expect(_ids(orderRaceParticipantsForDisplay(participants)), [
        'a',
        'b',
        'c',
      ]);
    });

    test('an empty roster is still safe', () {
      expect(orderRaceParticipantsForDisplay(const []), isEmpty);
    });

    test('ties in placement keep payload order', () {
      final participants = <Map<String, dynamic>>[
        _p('first-in-payload', placement: 2, steps: 5),
        _p('second-in-payload', placement: 2, steps: 5),
        _p('leader', placement: 1, steps: 9),
      ];

      expect(_ids(orderRaceParticipantsForDisplay(participants)), [
        'leader',
        'first-in-payload',
        'second-in-payload',
      ]);
    });
  });

  group('Item 18 — the rank shield hides the number for a stealthed row', () {
    Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Column(children: [child])),
    );

    testWidgets('a stealthed plank paints "?" instead of an index rank', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const LeaderboardPlank(
            rank: 0,
            name: 'Ghost',
            steps: 0,
            formattedSteps: '???',
            isStealthed: true,
            rankHidden: true,
          ),
        ),
      );

      final plank = tester.widget<LeaderboardPlank>(
        find.byType(LeaderboardPlank),
      );
      expect(plank.rankHidden, isTrue);
      expect(plank.rankLabel, '?');
    });

    testWidgets('a visible plank still paints its number', (tester) async {
      await tester.pumpWidget(
        wrap(
          const LeaderboardPlank(
            rank: 2,
            name: 'Runner',
            steps: 500,
            formattedSteps: '500',
          ),
        ),
      );

      final plank = tester.widget<LeaderboardPlank>(
        find.byType(LeaderboardPlank),
      );
      expect(plank.rankHidden, isFalse);
      expect(plank.rankLabel, '3');
    });
  });
}
