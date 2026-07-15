import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/team_race.dart';

void main() {
  group('TR-705 defensive parsing', () {
    test('a race without isTeamRace renders as an individual race', () {
      expect(TeamRace.isTeamRace(const {}), isFalse);
      expect(TeamRace.isTeamRace(const {'isTeamRace': null}), isFalse);
      expect(TeamRace.isTeamRace(const {'name': 'Solo run'}), isFalse);
    });

    test('isTeamRace true only when the flag is explicitly true', () {
      expect(TeamRace.isTeamRace(const {'isTeamRace': true}), isTrue);
      expect(TeamRace.isTeamRace(const {'isTeamRace': false}), isFalse);
      // Defensive against string-encoded booleans from a mismatched backend.
      expect(TeamRace.isTeamRace(const {'isTeamRace': 'true'}), isFalse);
    });

    test('teamSize is null-safe and coerces numeric encodings', () {
      expect(TeamRace.teamSize(const {}), isNull);
      expect(TeamRace.teamSize(const {'teamSize': 3}), 3);
      expect(TeamRace.teamSize(const {'teamSize': 3.0}), 3);
      expect(TeamRace.teamSize(const {'teamSize': null}), isNull);
    });

    test('parseRaceTeam maps wire strings and rejects junk', () {
      expect(parseRaceTeam('TEAM_A'), RaceTeam.teamA);
      expect(parseRaceTeam('TEAM_B'), RaceTeam.teamB);
      expect(parseRaceTeam(null), isNull);
      expect(parseRaceTeam('TEAM_C'), isNull);
      expect(parseRaceTeam(42), isNull);
    });

    test('winnerTeam and participantTeam parse defensively', () {
      expect(TeamRace.winnerTeam(const {}), isNull);
      expect(TeamRace.winnerTeam(const {'winnerTeam': 'TEAM_B'}), RaceTeam.teamB);
      expect(TeamRace.participantTeam(const {}), isNull);
      expect(
        TeamRace.participantTeam(const {'team': 'TEAM_A'}),
        RaceTeam.teamA,
      );
    });
  });

  group('team names', () {
    test('teamName reads wire fields with playful fallbacks', () {
      final race = const {'teamAName': 'Swift Capys', 'teamBName': 'Turbo Beavers'};
      expect(TeamRace.teamName(race, RaceTeam.teamA), 'Swift Capys');
      expect(TeamRace.teamName(race, RaceTeam.teamB), 'Turbo Beavers');
    });

    test('teamName falls back when a name is missing or blank', () {
      expect(TeamRace.teamName(const {}, RaceTeam.teamA), 'Team A');
      expect(
        TeamRace.teamName(const {'teamBName': '   '}, RaceTeam.teamB),
        'Team B',
      );
    });
  });

  group('RaceTeam helpers', () {
    test('other flips the side and wireValue round-trips', () {
      expect(RaceTeam.teamA.other, RaceTeam.teamB);
      expect(RaceTeam.teamB.other, RaceTeam.teamA);
      expect(RaceTeam.teamA.wireValue, 'TEAM_A');
      expect(RaceTeam.teamB.wireValue, 'TEAM_B');
    });

    test('team colors are distinct (warm red vs lake blue, TR-802)', () {
      expect(
        TeamRace.color(RaceTeam.teamA),
        isNot(equals(TeamRace.color(RaceTeam.teamB))),
      );
    });
  });

  group('TR-206 / TR-806 formatting', () {
    test('formatLabel renders NvN', () {
      expect(TeamRace.formatLabel(1), '1v1');
      expect(TeamRace.formatLabel(2), '2v2');
      expect(TeamRace.formatLabel(5), '5v5');
    });

    test('slotsLeftLabel describes remaining capacity on a side', () {
      // A 2v2 with 1 filled on Blue -> "1 slot left on Turbo Beavers".
      final label = TeamRace.slotsLeftLabel(
        teamSize: 2,
        filledCount: 1,
        teamName: 'Turbo Beavers',
      );
      expect(label, '1 slot left on Turbo Beavers');
    });

    test('slotsLeftLabel pluralizes and handles a full side', () {
      expect(
        TeamRace.slotsLeftLabel(teamSize: 3, filledCount: 1, teamName: 'Red'),
        '2 slots left on Red',
      );
      expect(
        TeamRace.slotsLeftLabel(teamSize: 2, filledCount: 2, teamName: 'Red'),
        'Red is full',
      );
    });
  });

  group('team totals & scoreline (TR-401 / TR-806)', () {
    final participants = const [
      {'team': 'TEAM_A', 'totalSteps': 5000},
      {'team': 'TEAM_A', 'totalSteps': 7340},
      {'team': 'TEAM_B', 'totalSteps': 11900},
      {'userId': 'x', 'totalSteps': 999}, // no team -> ignored
    ];

    test('teamTotal sums member effective steps per side', () {
      expect(TeamRace.teamTotal(participants, RaceTeam.teamA), 12340);
      expect(TeamRace.teamTotal(participants, RaceTeam.teamB), 11900);
    });

    test('leadingTeam reflects the higher total, null on a tie', () {
      expect(TeamRace.leadingTeam(participants), RaceTeam.teamA);
      final tied = const [
        {'team': 'TEAM_A', 'totalSteps': 100},
        {'team': 'TEAM_B', 'totalSteps': 100},
      ];
      expect(TeamRace.leadingTeam(tied), isNull);
    });

    test('membersOf groups participants by side', () {
      expect(TeamRace.membersOf(participants, RaceTeam.teamA).length, 2);
      expect(TeamRace.membersOf(participants, RaceTeam.teamB).length, 1);
    });
  });

  group('TR-806/206 list payload readers', () {
    test('listTeamTotals reads a progress-style teams block', () {
      final race = {
        'isTeamRace': true,
        'teams': {
          'teamA': {'totalSteps': 12340, 'memberCount': 2},
          'teamB': {'totalSteps': 11900, 'memberCount': 2},
        },
      };
      expect(TeamRace.listTeamTotals(race), (12340, 11900));
    });

    test('listTeamTotals is null when the block is absent or malformed', () {
      expect(TeamRace.listTeamTotals(const {'isTeamRace': true}), isNull);
      expect(
        TeamRace.listTeamTotals(const {
          'isTeamRace': true,
          'teams': {'teamA': 'junk'},
        }),
        isNull,
      );
    });

    test('sideCounts prefers the teams block and falls back to participants',
        () {
      final withBlock = {
        'teams': {
          'teamA': {'memberCount': 2},
          'teamB': {'memberCount': 1},
        },
      };
      expect(TeamRace.sideCounts(withBlock), (2, 1));

      final withParticipants = {
        'participants': [
          {'status': 'ACCEPTED', 'team': 'TEAM_A'},
          {'status': 'ACCEPTED', 'team': 'TEAM_B'},
          {'status': 'ACCEPTED', 'team': 'TEAM_B'},
          {'status': 'INVITED', 'team': null},
        ],
      };
      expect(TeamRace.sideCounts(withParticipants), (1, 2));

      expect(TeamRace.sideCounts(const {}), isNull);
    });

    test('publicSlotsLabel renders the TR-206 card line', () {
      final race = {
        'isTeamRace': true,
        'teamSize': 2,
        'teamAName': 'Red',
        'teamBName': 'Blue',
        'teams': {
          'teamA': {'memberCount': 2},
          'teamB': {'memberCount': 1},
        },
      };
      expect(TeamRace.publicSlotsLabel(race), '2v2 · 1 slot left on Blue');
    });

    test('publicSlotsLabel prefers the emptier side and degrades gracefully',
        () {
      final bothOpen = {
        'isTeamRace': true,
        'teamSize': 3,
        'teamAName': 'Red',
        'teamBName': 'Blue',
        'teams': {
          'teamA': {'memberCount': 1},
          'teamB': {'memberCount': 2},
        },
      };
      expect(
        TeamRace.publicSlotsLabel(bothOpen),
        '3v3 · 2 slots left on Red',
      );

      // No side data at all -> just the format chip text.
      expect(
        TeamRace.publicSlotsLabel(const {'isTeamRace': true, 'teamSize': 2}),
        '2v2',
      );
    });
  });

  group('TR-651/657 offensive target eligibility', () {
    final teamRace = {
      'isTeamRace': true,
      'teamSize': 2,
      'teamAName': 'Red',
      'teamBName': 'Blue',
    };
    final participants = [
      {'userId': 'me', 'team': 'TEAM_A'},
      {'userId': 'ally', 'team': 'TEAM_A'},
      {'userId': 'enemy1', 'team': 'TEAM_B'},
      {'userId': 'enemy2', 'team': 'TEAM_B'},
    ];

    test('team race offers enemy-team members only (no friendly fire)', () {
      final targets = TeamRace.offensiveTargets(
        participants: participants,
        myUserId: 'me',
        race: teamRace,
      );
      expect(
        targets.map((t) => t['userId']),
        containsAll(['enemy1', 'enemy2']),
      );
      expect(targets.map((t) => t['userId']), isNot(contains('ally')));
      expect(targets.map((t) => t['userId']), isNot(contains('me')));
    });

    test('TR-657: forfeited enemies are excluded from the pool', () {
      final withForfeit = [
        ...participants,
        {
          'userId': 'quitter',
          'team': 'TEAM_B',
          'forfeitedAt': '2026-07-15T10:00:00.000Z',
        },
      ];
      final targets = TeamRace.offensiveTargets(
        participants: withForfeit,
        myUserId: 'me',
        race: teamRace,
      );
      expect(targets.map((t) => t['userId']), isNot(contains('quitter')));
    });

    test('stealthed racers stay excluded (existing rule)', () {
      final withStealth = [
        ...participants,
        {'userId': 'ghost', 'team': 'TEAM_B', 'stealthed': true},
      ];
      final targets = TeamRace.offensiveTargets(
        participants: withStealth,
        myUserId: 'me',
        race: teamRace,
      );
      expect(targets.map((t) => t['userId']), isNot(contains('ghost')));
    });

    test('individual race keeps every non-self, non-stealthed racer', () {
      final targets = TeamRace.offensiveTargets(
        participants: const [
          {'userId': 'me'},
          {'userId': 'a'},
          {'userId': 'b'},
          {'userId': 'ghost', 'stealthed': true},
        ],
        myUserId: 'me',
        race: const {},
      );
      expect(targets.map((t) => t['userId']), ['a', 'b']);
    });

    test('individual race still drops forfeited racers (TR-657)', () {
      final targets = TeamRace.offensiveTargets(
        participants: const [
          {'userId': 'me'},
          {'userId': 'a'},
          {'userId': 'gone', 'forfeitedAt': '2026-07-15T10:00:00.000Z'},
        ],
        myUserId: 'me',
        race: const {},
      );
      expect(targets.map((t) => t['userId']), ['a']);
    });

    test('team race with a team-less viewer degrades to all rivals', () {
      // Defensive: a mismatched payload must never leave the user unable to
      // target anyone at all.
      final targets = TeamRace.offensiveTargets(
        participants: participants,
        myUserId: 'stranger',
        race: teamRace,
      );
      expect(targets.length, 4);
    });
  });

  group('error-code copy (TR-2xx/7xx)', () {
    test('known codes map to playful copy', () {
      expect(teamRaceErrorCopy('TEAM_FULL'), contains('full'));
      expect(teamRaceErrorCopy('TEAMS_UNEVEN').toLowerCase(), contains('even'));
      expect(
        teamRaceErrorCopy('RACE_ALREADY_STARTED').toLowerCase(),
        contains('started'),
      );
      expect(
        teamRaceErrorCopy('UPDATE_REQUIRED').toLowerCase(),
        contains('update'),
      );
      expect(
        teamRaceErrorCopy('INVITEE_NEEDS_UPDATE').toLowerCase(),
        contains('update'),
      );
      expect(
        teamRaceErrorCopy('FEATURE_DISABLED').toLowerCase(),
        contains('team races'),
      );
      expect(
        teamRaceErrorCopy('TEAM_NAMES_IDENTICAL').toLowerCase(),
        contains('different'),
      );
    });

    test('INVITEE_NEEDS_UPDATE names the friend when provided (TR-707)', () {
      expect(
        teamRaceErrorCopy('INVITEE_NEEDS_UPDATE', friendName: 'Alex'),
        contains('Alex'),
      );
    });

    test('unknown code returns a safe generic fallback', () {
      final copy = teamRaceErrorCopy('SOMETHING_NEW');
      expect(copy, isNotEmpty);
    });
  });
}
