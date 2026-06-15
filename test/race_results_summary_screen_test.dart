import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/race_results_summary_screen.dart';

Widget _wrap(List<Map<String, dynamic>> races) {
  return MaterialApp(
    home: RaceResultsSummaryScreen(races: races),
  );
}

void main() {
  testWidgets('single race shows place, winner, and payout', (tester) async {
    await tester.pumpWidget(
      _wrap([
        {
          'id': 'r1',
          'name': 'Weekend Sprint',
          'participantCount': 4,
          'myPlacement': 2,
          'myPayoutCoins': 120,
          'myStatus': 'ACCEPTED',
          'winner': {'displayName': 'Alex'},
        },
      ]),
    );
    await tester.pump();

    expect(find.text('RACE FINISHED'), findsOneWidget);
    expect(find.text('Weekend Sprint'), findsOneWidget);
    expect(find.text('2ND OF 4'), findsOneWidget);
    expect(find.text('+120'), findsOneWidget);
    expect(find.textContaining('Alex'), findsOneWidget);
  });

  testWidgets('null placement renders Did not finish', (tester) async {
    await tester.pumpWidget(
      _wrap([
        {
          'id': 'r1',
          'name': 'DNF Race',
          'participantCount': 3,
          'myPlacement': null,
          'myPayoutCoins': 0,
          'myStatus': 'ACCEPTED',
        },
      ]),
    );
    await tester.pump();

    expect(find.text('DID NOT FINISH'), findsOneWidget);
  });

  testWidgets('multiple races render a card each with plural header', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        {
          'id': 'r1',
          'name': 'Race One',
          'participantCount': 2,
          'myPlacement': 1,
          'myPayoutCoins': 50,
          'winner': {'displayName': 'Me'},
        },
        {
          'id': 'r2',
          'name': 'Race Two',
          'participantCount': 5,
          'myPlacement': 4,
          'myPayoutCoins': 0,
          'winner': {'displayName': 'Sam'},
        },
      ]),
    );
    await tester.pump();

    expect(find.text('RACES FINISHED'), findsOneWidget);
    expect(find.text('Race One'), findsOneWidget);
    expect(find.text('Race Two'), findsOneWidget);
  });

  testWidgets('missing fields default safely (no crash)', (tester) async {
    await tester.pumpWidget(_wrap([<String, dynamic>{}]));
    await tester.pump();

    expect(find.text('Race'), findsOneWidget);
    expect(find.text('DID NOT FINISH'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
