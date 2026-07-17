import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/tournament.dart';
import 'package:step_tracker/utils/tournament_bracket.dart';

/// Item 11 — a detoured/masked tournament player must surface as `???` on the
/// bracket (mirroring the race leaderboard), driven by a `stealthed` bool on the
/// slot. The bool is set from the backend `stealthed` flag OR, defensively, from
/// `totalSteps == null` so it works against the current prod backend before the
/// explicit flag ships (#1 rule).
void main() {
  Map<String, dynamic> activeTournament() => {
        'id': 't1',
        'status': 'ACTIVE',
        'bracketSize': 4,
        'totalRounds': 2,
        'currentRound': 1,
        'participants': const [
          {'userId': 'a', 'displayName': 'Alice', 'status': 'ACCEPTED'},
          {'userId': 'b', 'displayName': 'Bob', 'status': 'ACCEPTED'},
          {'userId': 'c', 'displayName': 'Cara', 'status': 'ACCEPTED'},
          {'userId': 'd', 'displayName': 'Dan', 'status': 'ACCEPTED'},
        ],
        'rounds': [
          {
            'round': 1,
            'matchups': [
              {
                'matchIndex': 0,
                'status': 'ACTIVE',
                'raceId': 'r1',
                'players': [
                  {'userId': 'a', 'totalSteps': 1200},
                  {'userId': 'b', 'totalSteps': null}, // masked via null
                ],
              },
              {
                'matchIndex': 1,
                'status': 'ACTIVE',
                'raceId': 'r2',
                'players': [
                  {'userId': 'c', 'totalSteps': 800},
                  // masked via explicit backend flag (even with a number present)
                  {'userId': 'd', 'stealthed': true, 'totalSteps': 500},
                ],
              },
            ],
          },
          {'round': 2, 'matchups': const []},
        ],
      };

  group('Tournament.playerStealthed', () {
    test('true when totalSteps is explicitly null (defensive inference)', () {
      expect(
        Tournament.playerStealthed({'userId': 'b', 'totalSteps': null}),
        isTrue,
      );
    });

    test('true when the backend stealthed flag is set', () {
      expect(
        Tournament.playerStealthed(
            {'userId': 'd', 'stealthed': true, 'totalSteps': 500}),
        isTrue,
      );
    });

    test('false for a normal player with a step count', () {
      expect(
        Tournament.playerStealthed({'userId': 'a', 'totalSteps': 1200}),
        isFalse,
      );
    });

    test('false when totalSteps is absent entirely (missing data, not masked)',
        () {
      // A payload that simply omits the field must NOT read as masked.
      expect(Tournament.playerStealthed({'userId': 'x'}), isFalse);
    });
  });

  group('buildTournamentBracket carries stealthed onto the slot', () {
    test('masked players (null OR flag) become stealthed slots', () {
      final model = buildTournamentBracket(activeTournament(), 'a');
      final r1 = model.rounds[0];

      // Matchup 0: Alice visible, Bob masked (null).
      expect(r1[0].top.userId, 'a');
      expect(r1[0].top.stealthed, isFalse);
      expect(r1[0].top.steps, 1200);
      expect(r1[0].bottom.userId, 'b');
      expect(r1[0].bottom.stealthed, isTrue);

      // Matchup 1: Cara visible, Dan masked (flag).
      expect(r1[1].top.stealthed, isFalse);
      expect(r1[1].bottom.userId, 'd');
      expect(r1[1].bottom.stealthed, isTrue);
    });

    test('BracketSlot defaults to not stealthed', () {
      expect(BracketSlot.open.stealthed, isFalse);
      expect(BracketSlot.tbd.stealthed, isFalse);
    });
  });
}
