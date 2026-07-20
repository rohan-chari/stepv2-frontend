import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/tournament_bracket.dart';
import 'package:step_tracker/widgets/tournament_bracket_board.dart';

// Item 11 (render): the bracket board shows `???` for a masked player instead
// of a blank.
//
// The former "sponsor card collapses when the kill switch is off" case was
// removed with TournamentSponsorCard (spec §3 — retired native ad replaced by a
// fixed AdBannerSlot in TournamentDetailScreen). Collapse-to-zero on no-fill is
// now covered by AdBannerSlot's own contract and the §3 tournament banner test.

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 420, height: 760, child: child),
      ),
    );

Map<String, dynamic> _activeWithMasked() => {
      'id': 't1',
      'status': 'ACTIVE',
      'bracketSize': 4,
      'currentRound': 1,
      'totalRounds': 2,
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
                {'userId': 'b', 'totalSteps': null}, // masked
              ],
            },
            {
              'matchIndex': 1,
              'status': 'ACTIVE',
              'raceId': 'r2',
              'players': [
                {'userId': 'c', 'totalSteps': 800},
                {'userId': 'd', 'totalSteps': 300},
              ],
            },
          ],
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('masked player renders ??? on the bracket', (tester) async {
    final model = buildTournamentBracket(_activeWithMasked(), 'a');
    await tester.pumpWidget(_host(TournamentBracketBoard(model: model)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Bob is masked → shows ??? rather than a number.
    expect(find.text('???'), findsOneWidget);
    // Visible players still show their formatted step counts (1200 → "1.2k").
    expect(find.text('1.2k'), findsOneWidget);
  });
}
