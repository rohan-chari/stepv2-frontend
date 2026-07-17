import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/tournament_bracket.dart';
import 'package:step_tracker/widgets/tournament_bracket_board.dart';

// Smoke + interaction tests for the draggable bracket canvas: it lays out
// 4/8/16 brackets without throwing, labels every round, renders nothing for an
// empty model, and fires the callback when the viewer taps their live matchup.

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SizedBox(width: 420, height: 760, child: child),
  ),
);

Map<String, dynamic> _active16() {
  final participants = [
    for (var i = 0; i < 16; i++)
      {'userId': 'u$i', 'displayName': 'P$i', 'status': 'ACCEPTED'},
  ];
  return {
    'id': 't1',
    'status': 'ACTIVE',
    'bracketSize': 16,
    'currentRound': 1,
    'totalRounds': 4,
    'participants': participants,
    'rounds': [
      {
        'round': 1,
        'matchups': [
          for (var i = 0; i < 8; i++)
            {
              'matchIndex': i,
              'raceId': 'r$i',
              'status': 'ACTIVE',
              'players': [
                {'userId': 'u${2 * i}', 'totalSteps': 10, 'forfeited': false},
                {'userId': 'u${2 * i + 1}', 'totalSteps': 5, 'forfeited': false},
              ],
            },
        ],
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('16-bracket lays out with every round label, no exception',
      (tester) async {
    final model = buildTournamentBracket(_active16(), 'u0');
    await tester.pumpWidget(_host(TournamentBracketBoard(model: model)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('ROUND OF 16'), findsOneWidget);
    expect(find.text('QUARTERFINALS'), findsOneWidget);
    expect(find.text('SEMIFINALS'), findsOneWidget);
    expect(find.text('FINAL'), findsOneWidget);
    // 'CHAMPION' appears as the column label AND the (uncrowned) crown node.
    expect(find.text('CHAMPION'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty model renders nothing (no crash)', (tester) async {
    final model = buildTournamentBracket(const {}, 'me');
    await tester.pumpWidget(_host(TournamentBracketBoard(model: model)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('tapping my live matchup fires the callback with its raceId',
      (tester) async {
    String? tapped;
    final t = {
      'id': 't1',
      'status': 'ACTIVE',
      'bracketSize': 4,
      'currentRound': 1,
      'totalRounds': 2,
      'participants': [
        {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
        {'userId': 'b', 'displayName': 'Bee', 'status': 'ACCEPTED'},
      ],
      'rounds': [
        {
          'round': 1,
          'matchups': [
            {
              'matchIndex': 0,
              'raceId': 'race-99',
              'status': 'ACTIVE',
              'players': [
                {'userId': 'me', 'totalSteps': 100, 'forfeited': false},
                {'userId': 'b', 'totalSteps': 90, 'forfeited': false},
              ],
            },
          ],
        },
      ],
    };
    final model = buildTournamentBracket(t, 'me');
    await tester.pumpWidget(
      _host(TournamentBracketBoard(
        model: model,
        onTapMyMatchup: (id) => tapped = id,
      )),
    );
    await tester.pump();

    await tester.tap(find.text('TAP TO RACE'));
    await tester.pump();
    expect(tapped, 'race-99');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tapping another live matchup fires the spectate callback',
      (tester) async {
    String? watched;
    final t = {
      'id': 't1',
      'status': 'ACTIVE',
      'bracketSize': 4,
      'currentRound': 1,
      'totalRounds': 2,
      'participants': [
        {'userId': 'me', 'displayName': 'Me', 'status': 'ACCEPTED'},
        {'userId': 'b', 'displayName': 'Bee', 'status': 'ACCEPTED'},
        {'userId': 'x', 'displayName': 'Ex', 'status': 'ACCEPTED'},
        {'userId': 'y', 'displayName': 'Why', 'status': 'ACCEPTED'},
      ],
      'rounds': [
        {
          'round': 1,
          'matchups': [
            {
              'matchIndex': 0,
              'raceId': 'race-mine',
              'status': 'ACTIVE',
              'players': [
                {'userId': 'me', 'totalSteps': 100, 'forfeited': false},
                {'userId': 'b', 'totalSteps': 90, 'forfeited': false},
              ],
            },
            {
              'matchIndex': 1,
              'raceId': 'race-spec',
              'status': 'ACTIVE',
              'players': [
                {'userId': 'x', 'totalSteps': 40, 'forfeited': false},
                {'userId': 'y', 'totalSteps': 30, 'forfeited': false},
              ],
            },
          ],
        },
      ],
    };
    final model = buildTournamentBracket(t, 'me');
    await tester.pumpWidget(
      _host(TournamentBracketBoard(
        model: model,
        onTapMyMatchup: (_) {},
        onTapMatchup: (id) => watched = id,
      )),
    );
    await tester.pump();

    // The matchup I'm not in shows a subtle "WATCH" affordance and spectates.
    expect(find.text('WATCH'), findsOneWidget);
    await tester.tap(find.text('WATCH'));
    await tester.pump();
    expect(watched, 'race-spec');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
