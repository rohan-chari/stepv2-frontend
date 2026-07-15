import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/team_race.dart';

// Conformance against docs/team-races-api-contract.md §9b — the payload shapes
// the backend committed to, transcribed VERBATIM. If the backend changes a
// shape, these fail loudly rather than the UI silently going blank.

/// §9b `GET /races` team-race summary, exactly as documented.
Map<String, dynamic> _listSummary() => {
      'isTeamRace': true,
      'teamSize': 2,
      'teamAName': 'Swift Capys',
      'teamBName': 'Turbo Beavers',
      'winnerTeam': null,
      'myTeam': 'TEAM_A',
      'myForfeited': false,
      'teams': {
        'teamA': {'name': 'Swift Capys', 'totalSteps': 12340, 'memberCount': 2},
        'teamB': {
          'name': 'Turbo Beavers',
          'totalSteps': 11900,
          'memberCount': 2,
        },
      },
      'teamATotalSteps': 12340,
      'teamBTotalSteps': 11900,
    };

/// §9b: "Individual races carry isTeamRace: false, myTeam: null,
/// myForfeited: false, teams: null — shape-stable."
Map<String, dynamic> _individualSummary() => {
      'isTeamRace': false,
      'myTeam': null,
      'myForfeited': false,
      'teams': null,
      'myPlacement': 2,
    };

void main() {
  group('§9b races-list summary (TR-806)', () {
    test('the canonical teams block drives the scoreline', () {
      expect(TeamRace.listTeamTotals(_listSummary()), (12340, 11900));
    });

    test('team identity + format read off the summary', () {
      final race = _listSummary();
      expect(TeamRace.isTeamRace(race), isTrue);
      expect(TeamRace.teamSize(race), 2);
      expect(TeamRace.teamName(race, RaceTeam.teamA), 'Swift Capys');
      expect(TeamRace.teamName(race, RaceTeam.teamB), 'Turbo Beavers');
      expect(TeamRace.formatLabel(TeamRace.teamSize(race)!), '2v2');
    });

    test('an individual summary (teams: null) parses inertly, never throws',
        () {
      final race = _individualSummary();
      expect(TeamRace.isTeamRace(race), isFalse);
      expect(TeamRace.listTeamTotals(race), isNull);
      expect(TeamRace.sideCounts(race), isNull);
      expect(TeamRace.teamSize(race), isNull);
    });
  });

  group('§9b public browser card (TR-206)', () {
    // "GET /races/public cards carry isTeamRace, teamSize, teamAName,
    // teamBName, teams (per-side memberCount; totals are 0 on a PENDING
    // lobby), plus teamAOpenSlots/teamBOpenSlots."
    Map<String, dynamic> publicCard() => {
          'isTeamRace': true,
          'teamSize': 2,
          'teamAName': 'Red',
          'teamBName': 'Blue',
          'teams': {
            'teamA': {'name': 'Red', 'totalSteps': 0, 'memberCount': 2},
            'teamB': {'name': 'Blue', 'totalSteps': 0, 'memberCount': 1},
          },
          'teamAOpenSlots': 0,
          'teamBOpenSlots': 1,
        };

    test('slots line reads from the canonical memberCount', () {
      expect(TeamRace.publicSlotsLabel(publicCard()), '2v2 · 1 slot left on Blue');
    });

    test('sideCounts prefers memberCount over counting participants', () {
      expect(TeamRace.sideCounts(publicCard()), (2, 1));
    });

    test('a PENDING lobby with 0 totals still renders slots, not a scoreline',
        () {
      // totals are 0 pre-start: the label must not imply a live score.
      expect(TeamRace.listTeamTotals(publicCard()), (0, 0));
      expect(TeamRace.publicSlotsLabel(publicCard()), contains('slot left'));
    });
  });

  group('§9b completed bucket → review gate + results (TR-807)', () {
    Map<String, dynamic> completed({
      String? winnerTeam = 'TEAM_A',
      String? myTeam = 'TEAM_A',
      bool myForfeited = false,
    }) =>
        {
          ..._listSummary(),
          'winnerTeam': winnerTeam,
          'myTeam': myTeam,
          'myForfeited': myForfeited,
        };

    test('winnerTeam == myTeam && !myForfeited qualifies', () {
      expect(raceCountsAsReviewHappyMoment(completed()), isTrue);
    });

    test('losing side does not qualify', () {
      expect(
        raceCountsAsReviewHappyMoment(completed(myTeam: 'TEAM_B')),
        isFalse,
      );
    });

    test('§9b: ties (winnerTeam null) are excluded automatically', () {
      expect(
        raceCountsAsReviewHappyMoment(completed(winnerTeam: null)),
        isFalse,
      );
    });

    test('forfeited winner does not qualify', () {
      expect(
        raceCountsAsReviewHappyMoment(completed(myForfeited: true)),
        isFalse,
      );
    });

    test('an individual completed race still uses the top-3 rule', () {
      expect(raceCountsAsReviewHappyMoment(_individualSummary()), isTrue);
      expect(
        raceCountsAsReviewHappyMoment({..._individualSummary(), 'myPlacement': 7}),
        isFalse,
      );
    });
  });

  group('§9b home race-card (TR-809)', () {
    // "an ACTIVE team race's data gains isTeamRace: true, teamSize, myTeam and
    // the same teams block for the TR-809 scoreline."
    test('home card data parses with the same reader as the list', () {
      final data = {
        'raceId': 'r1',
        'name': 'Team Clash',
        'isTeamRace': true,
        'teamSize': 2,
        'myTeam': 'TEAM_B',
        'teams': {
          'teamA': {'name': 'Swift Capys', 'totalSteps': 12340, 'memberCount': 2},
          'teamB': {
            'name': 'Turbo Beavers',
            'totalSteps': 11900,
            'memberCount': 2,
          },
        },
      };
      expect(TeamRace.listTeamTotals(data), (12340, 11900));
      expect(TeamRace.teamSize(data), 2);
      expect(parseRaceTeam(data['myTeam']), RaceTeam.teamB);
    });

    test('an individual home card keeps the legacy shape (no team keys)', () {
      final data = {'raceId': 'r1', 'name': 'Solo', 'userPlacement': 2};
      expect(TeamRace.isTeamRace(data), isFalse);
      expect(TeamRace.listTeamTotals(data), isNull);
    });
  });

  group('§9b detail payload participants', () {
    // "each participant carries team + forfeitedAt"
    test('participant team + forfeit state parse', () {
      const p = {
        'userId': 'u1',
        'team': 'TEAM_B',
        'forfeitedAt': '2026-07-15T10:00:00.000Z',
      };
      expect(TeamRace.participantTeam(p), RaceTeam.teamB);
      expect(TeamRace.hasForfeited(p), isTrue);
      expect(
        TeamRace.hasForfeited(const {'userId': 'u2', 'forfeitedAt': null}),
        isFalse,
      );
    });
  });
}
