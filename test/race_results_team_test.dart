import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/race_results_summary_screen.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/celebration_confetti.dart';

// TR-807: team-framed results — winning team name + members, tie copy
// ("It's a tie — buy-ins refunded"), confetti on a team WIN (the race-finish
// confetti moment), and the review-prompt gate that counts a team win as a
// top-3-equivalent strictly when winnerTeam == your team (ties never qualify,
// forfeited members never qualify).

Map<String, dynamic> _teamRace({
  String? winnerTeam = 'TEAM_A',
  String myTeam = 'TEAM_A',
  bool myForfeited = false,
  int? myPlacement = 1,
  int myPayoutCoins = 90,
}) {
  return {
    'id': 'race-t',
    'name': 'Team Clash',
    'status': 'COMPLETED',
    'isTeamRace': true,
    'teamSize': 2,
    'teamAName': 'Swift Capys',
    'teamBName': 'Turbo Beavers',
    'winnerTeam': winnerTeam,
    'myTeam': myTeam,
    'myForfeited': myForfeited,
    'myPlacement': myPlacement,
    'myPayoutCoins': myPayoutCoins,
    'participantCount': 4,
    'participants': [
      {
        'userId': 'user-1',
        'displayName': 'Trail Walker',
        'team': 'TEAM_A',
        'placement': 1,
      },
      {
        'userId': 'u2',
        'displayName': 'Hill Climber',
        'team': 'TEAM_A',
        'placement': 1,
      },
      {
        'userId': 'u3',
        'displayName': 'Sneaky Pete',
        'team': 'TEAM_B',
        'placement': 2,
      },
    ],
  };
}

Future<void> _pump(WidgetTester tester, Map<String, dynamic> race) async {
  await tester.pumpWidget(
    MaterialApp(home: RaceResultsSummaryScreen(races: [race])),
  );
  await tester.pump();
}

void main() {
  group('results screen (TR-807)', () {
    testWidgets('team win shows the winning team + members and confetti',
        (tester) async {
      await _pump(tester, _teamRace());

      expect(find.textContaining('SWIFT CAPYS'), findsWidgets);
      expect(find.text('VICTORY'), findsOneWidget);
      // Winning team members are listed.
      expect(find.textContaining('Trail Walker'), findsOneWidget);
      expect(find.textContaining('Hill Climber'), findsOneWidget);
      // Race finish = the approved confetti moment.
      expect(find.byType(CelebrationConfetti), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('team loss shows defeat framing without confetti',
        (tester) async {
      await _pump(
        tester,
        _teamRace(winnerTeam: 'TEAM_B', myTeam: 'TEAM_A', myPlacement: 2,
            myPayoutCoins: 0),
      );

      expect(find.text('DEFEAT'), findsOneWidget);
      expect(find.byType(CelebrationConfetti), findsNothing);
    });

    testWidgets('tie shows the dedicated refund copy and no confetti',
        (tester) async {
      await _pump(
        tester,
        _teamRace(winnerTeam: null, myPlacement: 1, myPayoutCoins: 0),
      );

      expect(
        find.textContaining('It’s a tie — buy-ins refunded'),
        findsOneWidget,
      );
      expect(find.byType(CelebrationConfetti), findsNothing);
    });
  });

  group('review-prompt gate (TR-807)', () {
    test('winning team member qualifies', () {
      expect(raceCountsAsReviewHappyMoment(_teamRace()), isTrue);
    });

    test('losing team member does not qualify', () {
      expect(
        raceCountsAsReviewHappyMoment(
          _teamRace(winnerTeam: 'TEAM_B', myTeam: 'TEAM_A'),
        ),
        isFalse,
      );
    });

    test('ties never qualify even though placement is 1', () {
      expect(
        raceCountsAsReviewHappyMoment(
          _teamRace(winnerTeam: null, myPlacement: 1),
        ),
        isFalse,
      );
    });

    test('forfeited members never qualify even on the winning team', () {
      expect(
        raceCountsAsReviewHappyMoment(_teamRace(myForfeited: true)),
        isFalse,
      );
    });

    test('individual races keep the top-3 rule', () {
      expect(
        raceCountsAsReviewHappyMoment(const {'myPlacement': 3}),
        isTrue,
      );
      expect(
        raceCountsAsReviewHappyMoment(const {'myPlacement': 4}),
        isFalse,
      );
      expect(raceCountsAsReviewHappyMoment(const {}), isFalse);
    });
  });
}
