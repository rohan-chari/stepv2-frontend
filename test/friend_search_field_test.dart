import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/screens/friend_picker_screen.dart';
import 'package:step_tracker/screens/race_invite_screen.dart';
import 'package:step_tracker/widgets/friend_search_field.dart';

/// Item 5 (batch 2026-07-27) — searching a long friend list.
///
/// Both surfaces that pick people for a race rendered the whole friend list
/// unfiltered. These tests pump the REAL screens (never the filter helper on
/// its own) and assert on what a user actually sees: which rows survive a
/// query, that the '@handle' is searchable and not just the raw name, that a
/// no-match query reads differently from "you have no friends", and that a
/// selection made before typing is still selected after the query is cleared.

/// 20 fixtures — comfortably over the threshold that reveals the field.
///
/// The two distinctive names lead the list on purpose: the screens use a lazy
/// [ListView.builder], so a row parked at index 18 is never built at this
/// viewport size and `findsNothing` would pass for the wrong reason.
List<Map<String, dynamic>> _friends() => [
  {'id': 'friend-hill', 'displayName': 'Hill Climber'},
  {'id': 'friend-zeb', 'displayName': 'Zebra Sprint'},
  for (var i = 0; i < 18; i++) {'id': 'friend-$i', 'displayName': 'Walker$i'},
];

Finder _rowFor(String name) => find.text('@$name');

void main() {
  group('FriendPickerScreen search', () {
    testWidgets('field appears only once the list is long enough', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FriendPickerScreen(
            friends: [
              {'id': 'a', 'displayName': 'Ann'},
              {'id': 'b', 'displayName': 'Bo'},
              {'id': 'c', 'displayName': 'Cy'},
            ],
          ),
        ),
      );
      expect(find.byType(FriendSearchField), findsNothing);

      await tester.pumpWidget(
        MaterialApp(home: FriendPickerScreen(friends: _friends())),
      );
      expect(find.byType(FriendSearchField), findsOneWidget);
    });

    testWidgets('typing narrows the list to matching rows only', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: FriendPickerScreen(friends: _friends())),
      );
      expect(_rowFor('Hill Climber'), findsOneWidget);
      expect(_rowFor('Walker1'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'hill');
      await tester.pumpAndSettle();

      expect(_rowFor('Hill Climber'), findsOneWidget);
      expect(_rowFor('Walker1'), findsNothing);
      expect(_rowFor('Zebra Sprint'), findsNothing);
    });

    testWidgets('the @handle matches, not just the bare name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: FriendPickerScreen(friends: _friends())),
      );

      await tester.enterText(find.byType(TextField), '@zebra');
      await tester.pumpAndSettle();

      expect(_rowFor('Zebra Sprint'), findsOneWidget);
      expect(_rowFor('Hill Climber'), findsNothing);
    });

    testWidgets('no-match state is distinct from the empty-list state', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: FriendPickerScreen(friends: _friends())),
      );

      await tester.enterText(find.byType(TextField), 'qqqq');
      await tester.pumpAndSettle();

      expect(find.textContaining('No friends match'), findsOneWidget);
      expect(find.textContaining('qqqq'), findsWidgets);
      // The "you have no friends" copy must NOT be what a bad query shows.
      expect(find.textContaining('No friends yet'), findsNothing);
    });

    testWidgets('the clear button restores the full list', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: FriendPickerScreen(friends: _friends())),
      );

      await tester.enterText(find.byType(TextField), 'hill');
      await tester.pumpAndSettle();
      expect(_rowFor('Walker1'), findsNothing);

      await tester.tap(find.byKey(const Key('friend-search-clear')));
      await tester.pumpAndSettle();

      expect(_rowFor('Walker1'), findsOneWidget);
      expect(_rowFor('Hill Climber'), findsOneWidget);
    });
  });

  group('RaceInviteScreen search', () {
    testWidgets('typing narrows the list to matching rows only', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: RaceInviteScreen(friends: _friends())),
      );
      expect(find.byType(FriendSearchField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.pumpAndSettle();

      expect(_rowFor('Zebra Sprint'), findsOneWidget);
      expect(_rowFor('Hill Climber'), findsNothing);
      expect(_rowFor('Walker1'), findsNothing);
    });

    testWidgets('the @handle matches, not just the bare name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: RaceInviteScreen(friends: _friends())),
      );

      await tester.enterText(find.byType(TextField), '@hill');
      await tester.pumpAndSettle();

      expect(_rowFor('Hill Climber'), findsOneWidget);
      expect(_rowFor('Zebra Sprint'), findsNothing);
    });

    testWidgets('the discoverable first and last name is searchable', (
      tester,
    ) async {
      final friends = [
        ..._friends(),
        {
          'id': 'real-name',
          'discoverableName': 'Nina Chari',
          'displayName': 'nima_runner',
        },
      ];
      await tester.pumpWidget(
        MaterialApp(home: RaceInviteScreen(friends: friends)),
      );

      await tester.enterText(find.byType(TextField), 'Nina');
      await tester.pumpAndSettle();

      expect(_rowFor('nima_runner'), findsOneWidget);
      expect(_rowFor('Hill Climber'), findsNothing);
    });

    testWidgets('no-match state is distinct from the empty-list state', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: RaceInviteScreen(friends: _friends())),
      );

      await tester.enterText(find.byType(TextField), 'qqqq');
      await tester.pumpAndSettle();

      expect(find.textContaining('No friends match'), findsOneWidget);
      // The "nobody left to invite" copy is a different situation.
      expect(find.textContaining('Nobody left to invite'), findsNothing);
    });

    testWidgets('a selection survives filtering and clearing the query', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: RaceInviteScreen(friends: _friends())),
      );

      // Select someone from the unfiltered list.
      await tester.tap(_rowFor('Hill Climber'));
      await tester.pumpAndSettle();
      expect(find.text('INVITE 1 FRIEND'), findsOneWidget);

      // Filter them out entirely...
      await tester.enterText(find.byType(TextField), 'zebra');
      await tester.pumpAndSettle();
      expect(_rowFor('Hill Climber'), findsNothing);
      expect(find.text('INVITE 1 FRIEND'), findsOneWidget);

      // ...add a second while filtered...
      await tester.tap(_rowFor('Zebra Sprint'));
      await tester.pumpAndSettle();
      expect(find.text('INVITE 2 FRIENDS'), findsOneWidget);

      // ...and clearing keeps both.
      await tester.tap(find.byKey(const Key('friend-search-clear')));
      await tester.pumpAndSettle();

      expect(find.text('INVITE 2 FRIENDS'), findsOneWidget);
      expect(_rowFor('Hill Climber'), findsOneWidget);
      expect(_rowFor('Zebra Sprint'), findsOneWidget);
    });
  });
}
