import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/team_side_picker.dart';

// TR-201/202: the shared "pick your side" sheet used by every join channel
// that isn't the lobby (public browser, share link). A side at cap is
// physically un-tappable rather than erroring after the fact.

Map<String, dynamic> _race({int aCount = 2, int bCount = 1}) => {
      'isTeamRace': true,
      'teamSize': 2,
      'teamAName': 'Red',
      'teamBName': 'Blue',
      'teams': {
        'teamA': {'memberCount': aCount},
        'teamB': {'memberCount': bCount},
      },
    };

Future<String?> _open(WidgetTester tester, Map<String, dynamic> race) async {
  String? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showTeamSidePicker(context: context, race: race);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('shows both sides with fill counts', (tester) async {
    await _open(tester, _race());
    expect(find.text('PICK YOUR SIDE'), findsOneWidget);
    expect(find.text('RED'), findsOneWidget);
    expect(find.text('BLUE'), findsOneWidget);
    expect(find.text('FULL'), findsOneWidget); // Red is 2/2
    expect(find.text('1/2'), findsOneWidget); // Blue has room
  });

  testWidgets('TR-201: tapping an open side returns its wire value',
      (tester) async {
    await _open(tester, _race());
    await tester.tap(find.byKey(const Key('side-pick-B')));
    await tester.pumpAndSettle();
    expect(find.text('PICK YOUR SIDE'), findsNothing);
  });

  testWidgets('TR-202: a full side does not dismiss the sheet', (tester) async {
    await _open(tester, _race());
    await tester.tap(find.byKey(const Key('side-pick-A')));
    await tester.pumpAndSettle();
    // Sheet stays open — the full side is inert.
    expect(find.text('PICK YOUR SIDE'), findsOneWidget);
  });

  testWidgets('both sides open when the race is empty', (tester) async {
    await _open(tester, _race(aCount: 0, bCount: 0));
    expect(find.text('FULL'), findsNothing);
    expect(find.text('0/2'), findsNWidgets(2));
  });
}
