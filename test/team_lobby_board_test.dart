import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/team_race.dart';
import 'package:step_tracker/widgets/home_course_track.dart'
    show AnimatedCapybaraWithAccessories;
import 'package:step_tracker/widgets/team_lobby_board.dart';

// TR-802: the LoL-custom-lobby team picker — two team columns facing each
// other around a carved VS medallion, exactly teamSize slots per side, filled
// slots showing the member's capy + name, empty slots as dashed pegs that ARE
// the join/switch affordance. A side at cap shows no empty slots (TR-202).

Map<String, dynamic> _race({int teamSize = 2}) => {
      'isTeamRace': true,
      'teamSize': teamSize,
      'teamAName': 'Swift Capys',
      'teamBName': 'Turbo Beavers',
    };

List<Map<String, dynamic>> _members() => [
      {
        'userId': 'u1',
        'displayName': 'Trail Walker',
        'status': 'ACCEPTED',
        'team': 'TEAM_A',
        'accessories': const [],
      },
      {
        'userId': 'u2',
        'displayName': 'Hill Climber',
        'status': 'ACCEPTED',
        'team': 'TEAM_B',
        'accessories': const [],
      },
      // INVITED rows haven't picked a side and must not occupy slots (TR-303).
      {
        'userId': 'u3',
        'displayName': 'Fence Sitter',
        'status': 'INVITED',
        'team': null,
      },
    ];

Future<void> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? race,
  List<Map<String, dynamic>>? participants,
  String? myUserId,
  void Function(RaceTeam)? onTapEmptySlot,
  double width = 400,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: TeamLobbyBoard(
              race: race ?? _race(),
              participants: participants ?? _members(),
              myUserId: myUserId ?? 'u1',
              onTapEmptySlot: onTapEmptySlot,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('TR-802: two plaques, VS medallion, teamSize slots per side',
      (tester) async {
    await _pump(tester);

    expect(find.text('SWIFT CAPYS'), findsOneWidget);
    expect(find.text('TURBO BEAVERS'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);

    // 2v2 -> one filled + one empty peg per side.
    expect(find.byKey(const Key('lobby-slot-A-0')), findsOneWidget);
    expect(find.byKey(const Key('lobby-empty-A-1')), findsOneWidget);
    expect(find.byKey(const Key('lobby-slot-B-0')), findsOneWidget);
    expect(find.byKey(const Key('lobby-empty-B-1')), findsOneWidget);

    // Filled slots render the member's capy with cosmetics + name.
    expect(find.byType(AnimatedCapybaraWithAccessories), findsNWidgets(2));
    expect(find.textContaining('Trail Walker'), findsOneWidget);
    expect(find.textContaining('Hill Climber'), findsOneWidget);

    // INVITED rows without a side occupy no slot.
    expect(find.textContaining('Fence Sitter'), findsNothing);
  });

  testWidgets('TR-202: a side at cap shows no empty pegs', (tester) async {
    await _pump(
      tester,
      race: _race(teamSize: 1),
      participants: [
        {
          'userId': 'u1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
          'team': 'TEAM_A',
        },
        {
          'userId': 'u2',
          'displayName': 'Hill Climber',
          'status': 'ACCEPTED',
          'team': 'TEAM_B',
        },
      ],
    );

    expect(find.byKey(const Key('lobby-slot-A-0')), findsOneWidget);
    expect(find.byKey(const Key('lobby-slot-B-0')), findsOneWidget);
    expect(find.byKey(const Key('lobby-empty-A-0')), findsNothing);
    expect(find.byKey(const Key('lobby-empty-B-0')), findsNothing);
  });

  testWidgets('TR-802: tapping an empty peg reports the side', (tester) async {
    RaceTeam? tapped;
    await _pump(tester, onTapEmptySlot: (team) => tapped = team);

    await tester.tap(find.byKey(const Key('lobby-empty-B-1')));
    await tester.pump();
    expect(tapped, RaceTeam.teamB);

    await tester.tap(find.byKey(const Key('lobby-empty-A-1')));
    await tester.pump();
    expect(tapped, RaceTeam.teamA);
  });

  testWidgets('TR-802: my slot is marked YOU', (tester) async {
    await _pump(tester, myUserId: 'u1');
    expect(
      find.descendant(
        of: find.byKey(const Key('lobby-slot-A-0')),
        matching: find.text('YOU'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'TR-810: 5v5 on a narrow screen keeps the two-column face-off '
      'without overflow', (tester) async {
    await _pump(
      tester,
      race: {
        'isTeamRace': true,
        'teamSize': 5,
        'teamAName': 'Extraordinarily Long Name',
        'teamBName': 'Another Very Long Name',
      },
      participants: [
        for (var i = 0; i < 5; i++)
          {
            'userId': 'a$i',
            'displayName': 'Longnamed Racer Number $i',
            'status': 'ACCEPTED',
            'team': 'TEAM_A',
          },
        for (var i = 0; i < 4; i++)
          {
            'userId': 'b$i',
            'displayName': 'Second Team Racer $i',
            'status': 'ACCEPTED',
            'team': 'TEAM_B',
          },
      ],
      width: 320,
    );

    expect(tester.takeException(), isNull);
    // Ten slot positions exist: 5 filled + 4 filled + 1 empty peg on B.
    expect(find.byKey(const Key('lobby-slot-A-4')), findsOneWidget);
    expect(find.byKey(const Key('lobby-empty-B-4')), findsOneWidget);
  });

  testWidgets('TR-802: switching sides plays the hop animation overlay',
      (tester) async {
    final participants = _members();
    await _pump(tester, participants: participants, myUserId: 'u1');

    // Rebuild with me on the other side — the board notices the move and
    // animates a flying capy overlay across the divider.
    final moved = [
      {...participants[0], 'team': 'TEAM_B'},
      participants[1],
      participants[2],
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: TeamLobbyBoard(
                race: _race(),
                participants: moved,
                myUserId: 'u1',
                onTapEmptySlot: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('lobby-hop-overlay')), findsOneWidget);
    // The walk-cycle sprite loops forever, so settle with timed pumps instead
    // of pumpAndSettle: fly (700ms) + a frame to clear the overlay.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 50));
    // Overlay lands and disappears; capy sits in the destination slot.
    expect(find.byKey(const Key('lobby-hop-overlay')), findsNothing);
  });
}
