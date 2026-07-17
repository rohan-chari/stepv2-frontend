import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/tournament.dart';

// Spec §9/§10: lib/utils/tournament.dart is the defensive-reader util over the
// raw tournament JSON maps. Every reader must degrade safely on an empty,
// partial, or unknown-shape payload (the #1 rule — the backend may be a
// different version than this build). tournamentErrorCopy must cover every
// §6.9 code plus a generic default.

Map<String, dynamic> _fullPayload() => {
  'id': 't1',
  'name': 'Friday Gauntlet',
  'status': 'ACTIVE',
  'bracketSize': 8,
  'matchupDurationDays': 2,
  'buyInAmount': 50,
  'potCoins': 400,
  'powerupsEnabled': true,
  'powerupStepInterval': 2500,
  'isPublic': true,
  'shareToken': 'abc123',
  'currentRound': 2,
  'totalRounds': 3,
  'creatorId': 'me',
  'championUserId': null,
  'startedAt': '2026-07-16T00:00:00.000Z',
  'acceptedCount': 8,
  'myStatus': 'ACCEPTED',
  'participants': [
    {
      'userId': 'u1',
      'displayName': 'Alice',
      'status': 'ACCEPTED',
      'seed': 0,
      'eliminatedInRound': null,
    },
    {
      'userId': 'u2',
      'displayName': 'Bob',
      'status': 'ACCEPTED',
      'seed': 1,
      'eliminatedInRound': 1,
    },
    {
      'userId': 'me',
      'displayName': 'Me',
      'status': 'ACCEPTED',
      'seed': 2,
      'eliminatedInRound': null,
    },
  ],
  'rounds': [
    {
      'round': 1,
      'label': 'QUARTERFINALS',
      'matchups': [
        {
          'matchIndex': 0,
          'raceId': 'r1',
          'status': 'COMPLETED',
          'endsAt': '2026-07-18T14:00:00.000Z',
          'players': [
            {'userId': 'u1', 'totalSteps': 18452, 'forfeited': false},
            {'userId': 'u2', 'totalSteps': 12001, 'forfeited': false},
          ],
          'winnerUserId': 'u1',
          'tie': false,
        },
      ],
    },
    {
      'round': 2,
      'label': 'SEMIFINALS',
      'matchups': [
        {
          'matchIndex': 0,
          'raceId': 'r5',
          'status': 'ACTIVE',
          'endsAt': '2026-07-20T14:00:00.000Z',
          'players': [
            {'userId': 'u1', 'totalSteps': 500, 'forfeited': false},
            {'userId': 'me', 'totalSteps': 900, 'forfeited': false},
          ],
          'winnerUserId': null,
          'tie': false,
        },
      ],
    },
  ],
};

void main() {
  group('Tournament defensive readers — full payload', () {
    final t = _fullPayload();

    test('scalar fields parse', () {
      expect(Tournament.id(t), 't1');
      expect(Tournament.name(t), 'Friday Gauntlet');
      expect(Tournament.status(t), TournamentStatus.active);
      expect(Tournament.isActive(t), isTrue);
      expect(Tournament.bracketSize(t), 8);
      expect(Tournament.matchupDurationDays(t), 2);
      expect(Tournament.buyInAmount(t), 50);
      expect(Tournament.potCoins(t), 400);
      expect(Tournament.powerupsEnabled(t), isTrue);
      expect(Tournament.powerupStepInterval(t), 2500);
      expect(Tournament.isPublic(t), isTrue);
      expect(Tournament.shareToken(t), 'abc123');
      expect(Tournament.currentRound(t), 2);
      expect(Tournament.totalRounds(t), 3);
      expect(Tournament.creatorId(t), 'me');
      expect(Tournament.acceptedCount(t), 8);
    });

    test('collections parse', () {
      expect(Tournament.participants(t), hasLength(3));
      expect(Tournament.rounds(t), hasLength(2));
      expect(Tournament.matchups(Tournament.rounds(t).first), hasLength(1));
    });

    test('champion winnings prefers the pot for a paid bracket', () {
      expect(Tournament.championWinnings(t), 400);
      expect(Tournament.hasPrize(t), isTrue);
    });

    test('myMatchup returns my current-round live matchup', () {
      final m = Tournament.myMatchup(t, 'me');
      expect(m, isNotNull);
      expect(m!['raceId'], 'r5');
      expect(Tournament.matchupIsCompleted(m), isFalse);
    });

    test('aliveCount counts non-eliminated accepted players', () {
      // u1 alive, u2 eliminated, me alive => 2
      expect(Tournament.aliveCount(t), 2);
    });

    test('matchup winner / steps / forfeit readers', () {
      final m = Tournament.rounds(t).first['matchups'][0] as Map<String, dynamic>;
      expect(Tournament.matchupWinnerId(m), 'u1');
      expect(Tournament.matchupIsTie(m), isFalse);
      expect(Tournament.matchupIsCompleted(m), isTrue);
      final players = Tournament.matchupPlayers(m);
      expect(Tournament.playerSteps(players.first), 18452);
      expect(Tournament.playerForfeited(players.first), isFalse);
    });
  });

  group('Tournament defensive readers — degraded payloads', () {
    test('empty map never crashes, returns safe defaults', () {
      final t = <String, dynamic>{};
      expect(Tournament.id(t), isNull);
      expect(Tournament.name(t), 'Tournament');
      expect(Tournament.status(t), isNull);
      expect(Tournament.bracketSize(t), 0);
      expect(Tournament.acceptedCount(t), 0);
      expect(Tournament.participants(t), isEmpty);
      expect(Tournament.rounds(t), isEmpty);
      expect(Tournament.aliveCount(t), 0);
      expect(Tournament.myMatchup(t, 'me'), isNull);
      expect(Tournament.championWinnings(t), 0);
      expect(Tournament.hasPrize(t), isFalse);
    });

    test('missing rounds/players read as empty lists', () {
      final t = {'rounds': null, 'participants': null};
      expect(Tournament.rounds(t), isEmpty);
      expect(Tournament.participants(t), isEmpty);
    });

    test('unknown status returns null, not a crash', () {
      expect(Tournament.status({'status': 'WAT'}), isNull);
      expect(Tournament.status({'status': 42}), isNull);
    });

    test('null userId in myMatchup is safe', () {
      expect(Tournament.myMatchup(_fullPayload(), null), isNull);
    });

    test('totalRounds falls back to log2(bracketSize) when absent', () {
      expect(Tournament.totalRounds({'bracketSize': 16}), 4);
      expect(Tournament.totalRounds({'bracketSize': 4}), 2);
    });
  });

  group('Featured / prize helpers', () {
    test('seeded bracket is featured; minted prize is the winnings', () {
      final t = {
        'seedId': 'seed-tournament-daily-dash',
        'seedKind': 'DAILY_DASH',
        'buyInAmount': 0,
        'potCoins': 0,
        'championPrizeCoins': 150,
      };
      expect(Tournament.isFeatured(t), isTrue);
      expect(Tournament.championWinnings(t), 150);
      expect(Tournament.prizePlaque(t), contains('150'));
    });

    test('free user bracket has no prize', () {
      final t = {'buyInAmount': 0, 'potCoins': 0};
      expect(Tournament.isFeatured(t), isFalse);
      expect(Tournament.hasPrize(t), isFalse);
      expect(Tournament.prizePlaque(t).toUpperCase(), contains('CROWN'));
    });

    test('paid user bracket plaque names the pot', () {
      final t = {'buyInAmount': 100, 'potCoins': 800};
      expect(Tournament.prizePlaque(t), contains('800'));
    });
  });

  group('Buy-in ladder (D4)', () {
    test('max scales with bracket size', () {
      expect(tournamentBuyInMaxForSize(4), 100);
      expect(tournamentBuyInMaxForSize(8), 100);
      expect(tournamentBuyInMaxForSize(16), 62);
    });

    test('0 is always valid (free)', () {
      for (final size in kTournamentBracketSizes) {
        expect(isValidTournamentBuyIn(0, size), isTrue);
      }
    });

    test('below the min but above 0 is invalid', () {
      expect(isValidTournamentBuyIn(5, 8), isFalse);
    });

    test('above the ladder max is invalid; a 16-bracket caps at 62', () {
      expect(isValidTournamentBuyIn(100, 16), isFalse);
      expect(isValidTournamentBuyIn(62, 16), isTrue);
      expect(isValidTournamentBuyIn(100, 8), isTrue);
    });

    test('clamp snaps a stale 100 down to 62 when switching to a 16-bracket', () {
      expect(clampTournamentBuyIn(100, 16), 62);
      expect(clampTournamentBuyIn(100, 8), 100);
      expect(clampTournamentBuyIn(5, 8), 0);
      expect(clampTournamentBuyIn(0, 8), 0);
    });
  });

  group('Round labels', () {
    test('16-bracket labels count from the final backward', () {
      expect(Tournament.roundLabelFor(16, 1), 'ROUND OF 16');
      expect(Tournament.roundLabelFor(16, 2), 'QUARTERFINALS');
      expect(Tournament.roundLabelFor(16, 3), 'SEMIFINALS');
      expect(Tournament.roundLabelFor(16, 4), 'FINAL');
    });

    test('8-bracket', () {
      expect(Tournament.roundLabelFor(8, 1), 'QUARTERFINALS');
      expect(Tournament.roundLabelFor(8, 2), 'SEMIFINALS');
      expect(Tournament.roundLabelFor(8, 3), 'FINAL');
    });

    test('4-bracket', () {
      expect(Tournament.roundLabelFor(4, 1), 'SEMIFINALS');
      expect(Tournament.roundLabelFor(4, 2), 'FINAL');
    });

    test('server label preferred when present', () {
      final round = {'round': 1, 'label': 'quarterfinals'};
      expect(Tournament.roundLabel(round, bracketSize: 8), 'QUARTERFINALS');
    });
  });

  group('Ticket status line', () {
    test('pending shows fill', () {
      expect(
        Tournament.ticketStatusLine({
          'status': 'PENDING',
          'bracketSize': 8,
          'acceptedCount': 5,
        }),
        '5/8 FILLED',
      );
    });

    test('active alive vs knocked out', () {
      final alive = Tournament.ticketStatusLine({
        'status': 'ACTIVE',
        'bracketSize': 8,
        'currentRound': 2,
        'totalRounds': 3,
      });
      expect(alive, contains('ALIVE'));
      final out = Tournament.ticketStatusLine({
        'status': 'ACTIVE',
        'bracketSize': 8,
        'currentRound': 2,
        'totalRounds': 3,
        'myEliminatedInRound': 1,
      });
      expect(out, contains('KNOCKED OUT'));
    });
  });

  group('tournamentErrorCopy (§6.9)', () {
    const codes = [
      'UPDATE_REQUIRED',
      'FEATURE_DISABLED',
      'TOURNAMENT_NOT_FOUND',
      'TOURNAMENT_FULL',
      'ALREADY_JOINED',
      'TOURNAMENT_NOT_PENDING',
      'BRACKET_NOT_FULL',
      'NO_LIVE_MATCHUP',
      'INSUFFICIENT_COINS',
      'NOT_CREATOR',
      'NOT_INVITED',
      'NOT_PUBLIC',
      'PARTICIPANT_NOT_FOUND',
      'ALREADY_RESPONDED',
      'CREATOR_CANNOT_LEAVE',
      'INVITEE_NEEDS_UPDATE',
      'TOURNAMENT_RACE_LOCKED',
      'VALIDATION',
    ];

    test('every §6.9 code maps to non-empty copy', () {
      for (final code in codes) {
        expect(tournamentErrorCopy(code), isNotEmpty, reason: code);
      }
    });

    test('unknown and null codes fall back to the generic default', () {
      final fallback = tournamentErrorCopy(null);
      expect(fallback, isNotEmpty);
      expect(tournamentErrorCopy('SOMETHING_NEW'), fallback);
    });

    test('INVITEE_NEEDS_UPDATE names the friend when provided', () {
      expect(
        tournamentErrorCopy('INVITEE_NEEDS_UPDATE', friendName: 'Sam'),
        contains('Sam'),
      );
    });

    test('BRACKET_NOT_FULL and TOURNAMENT_FULL read distinctly', () {
      expect(tournamentErrorCopy('BRACKET_NOT_FULL').toLowerCase(),
          contains('fill'));
      expect(tournamentErrorCopy('TOURNAMENT_FULL').toLowerCase(),
          contains('filled'));
    });
  });
}
