import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/tournament.dart';
import 'package:step_tracker/utils/tournament_bracket.dart';

// The draggable bracket board is driven by a pure, normalized model derived
// from the tournament payload. This locks its layout/logic: matchup counts per
// round, the PENDING join-order preview, ACTIVE winner/eliminated states, the
// champion cap, and defensive handling of missing fields (the #1 rule).

void main() {
  group('matchup counts', () {
    test('per round for 4 / 8 / 16', () {
      expect(BracketModel.matchupsInRound(4, 1), 2);
      expect(BracketModel.matchupsInRound(4, 2), 1);
      expect(BracketModel.matchupsInRound(8, 1), 4);
      expect(BracketModel.matchupsInRound(8, 2), 2);
      expect(BracketModel.matchupsInRound(8, 3), 1);
      expect(BracketModel.matchupsInRound(16, 1), 8);
      expect(BracketModel.matchupsInRound(16, 4), 1);
    });
  });

  group('PENDING preview (join order)', () {
    Map<String, dynamic> pending(List<Map<String, dynamic>> participants) => {
      'id': 't1',
      'status': 'PENDING',
      'bracketSize': 4,
      'matchupDurationDays': 1,
      'participants': participants,
    };

    test('accepted players fill leaves in join order, top-to-bottom', () {
      final t = pending([
        {
          'userId': 'c',
          'displayName': 'Cara',
          'status': 'ACCEPTED',
          'joinedAt': '2026-07-16T00:03:00.000Z',
        },
        {
          'userId': 'a',
          'displayName': 'Ann',
          'status': 'ACCEPTED',
          'joinedAt': '2026-07-16T00:01:00.000Z',
        },
        {
          'userId': 'b',
          'displayName': 'Bea',
          'status': 'ACCEPTED',
          'joinedAt': '2026-07-16T00:02:00.000Z',
        },
      ]);
      final model = buildTournamentBracket(t, 'b');

      expect(model.bracketSize, 4);
      expect(model.totalRounds, 2);
      expect(model.rounds, hasLength(2));
      final leaves = model.rounds[0];
      expect(leaves, hasLength(2));

      // Sorted by joinedAt: Ann(0:01), Bea(0:02), Cara(0:03) → then one OPEN.
      expect(leaves[0].top.displayName, 'Ann');
      expect(leaves[0].bottom.displayName, 'Bea');
      expect(leaves[1].top.displayName, 'Cara');
      expect(leaves[1].bottom.state, BracketSlotState.open);

      // Viewer 'b' (Bea) is flagged on her slot.
      expect(leaves[0].bottom.isMe, isTrue);
      expect(leaves[0].top.isMe, isFalse);

      // Round 2 is all TBD until it starts.
      expect(model.rounds[1], hasLength(1));
      expect(model.rounds[1][0].top.state, BracketSlotState.tbd);
      expect(model.rounds[1][0].bottom.state, BracketSlotState.tbd);
    });

    test('untimed entries keep payload order after timed ones', () {
      final t = pending([
        {'userId': 'x', 'displayName': 'X', 'status': 'ACCEPTED'},
        {
          'userId': 'y',
          'displayName': 'Y',
          'status': 'ACCEPTED',
          'joinedAt': '2026-07-16T00:01:00.000Z',
        },
      ]);
      final leaves = buildTournamentBracket(t, null).rounds[0];
      // Timed 'Y' first, then untimed 'X'.
      expect(leaves[0].top.displayName, 'Y');
      expect(leaves[0].bottom.displayName, 'X');
    });

    test('champion cap is TBD while pending', () {
      final model = buildTournamentBracket(pending(const []), null);
      expect(model.champion.state, BracketSlotState.tbd);
      // All leaves open with no participants.
      expect(model.rounds[0][0].top.state, BracketSlotState.open);
    });
  });

  group('ACTIVE from payload', () {
    Map<String, dynamic> active() => {
      'id': 't1',
      'status': 'ACTIVE',
      'bracketSize': 4,
      'currentRound': 1,
      'totalRounds': 2,
      'participants': [
        {'userId': 'a', 'displayName': 'Ann', 'status': 'ACCEPTED'},
        {'userId': 'b', 'displayName': 'Bea', 'status': 'ACCEPTED'},
        {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
        {'userId': 'd', 'displayName': 'Dan', 'status': 'ACCEPTED'},
      ],
      'rounds': [
        {
          'round': 1,
          'label': 'SEMIFINALS',
          'matchups': [
            {
              'matchIndex': 0,
              'raceId': 'r1',
              'status': 'COMPLETED',
              'players': [
                {'userId': 'a', 'totalSteps': 5000, 'forfeited': false},
                {'userId': 'b', 'totalSteps': 3000, 'forfeited': false},
              ],
              'winnerUserId': 'a',
              'tie': false,
            },
            {
              'matchIndex': 1,
              'raceId': 'r2',
              'status': 'ACTIVE',
              'players': [
                {'userId': 'me', 'totalSteps': 900, 'forfeited': false},
                {'userId': 'd', 'totalSteps': 850, 'forfeited': false},
              ],
              'winnerUserId': null,
            },
          ],
        },
        // Round 2 omitted from payload → must render as TBD skeleton.
      ],
    };

    test('winner / eliminated states resolve from a completed matchup', () {
      final model = buildTournamentBracket(active(), 'me');
      final m0 = model.rounds[0][0];
      expect(m0.completed, isTrue);
      expect(m0.top.state, BracketSlotState.winner); // Ann
      expect(m0.bottom.state, BracketSlotState.eliminated); // Bea
      expect(m0.top.steps, 5000);
    });

    test('my live matchup is flagged with its raceId', () {
      final model = buildTournamentBracket(active(), 'me');
      final m1 = model.rounds[0][1];
      expect(m1.isMine, isTrue);
      expect(m1.liveForMe, isTrue);
      expect(m1.raceId, 'r2');
      expect(m1.top.state, BracketSlotState.filled);
      expect(m1.top.isMe, isTrue);
    });

    test('a round missing from the payload still draws as TBD', () {
      final model = buildTournamentBracket(active(), 'me');
      expect(model.rounds, hasLength(2));
      final finalRound = model.rounds[1];
      expect(finalRound, hasLength(1));
      expect(finalRound[0].top.state, BracketSlotState.tbd);
    });
  });

  group('COMPLETED', () {
    test('champion cap is crowned and flags the viewer', () {
      final t = {
        'id': 't1',
        'status': 'COMPLETED',
        'bracketSize': 4,
        'championUserId': 'me',
        'participants': [
          {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
        ],
        'rounds': const [],
      };
      final model = buildTournamentBracket(t, 'me');
      expect(model.champion.state, BracketSlotState.champion);
      expect(model.champion.isMe, isTrue);
      expect(model.champion.displayName, 'Me');
    });
  });

  group('defensive', () {
    test('empty map yields an empty model, no crash', () {
      final model = buildTournamentBracket(const {}, 'me');
      expect(model.isEmpty, isTrue);
      expect(model.rounds, isEmpty);
      expect(model.champion.state, BracketSlotState.tbd);
    });

    test('unknown bracket size yields empty rounds', () {
      final model = buildTournamentBracket(
        {'status': 'ACTIVE', 'bracketSize': 5},
        null,
      );
      expect(model.rounds, isEmpty);
    });
  });
}
