import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

/// §4.1 — the personal-list state pills, and the perf constraints that the
/// redesign must not regress (§9.5's lazy slivers).
Future<void> _noop() async {}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 500,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Map<String, dynamic> _race(String id, String name, String status) => {
      'id': id,
      'name': name,
      'status': status,
      'myStatus': 'ACCEPTED',
      'maxDurationDays': 7,
      'participantCount': 3,
      'isCreator': false,
      'endsAt':
          DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String(),
    };

Future<void> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>> active = const [],
  List<Map<String, dynamic>> pending = const [],
  List<Map<String, dynamic>> completed = const [],
  List<Map<String, dynamic>> tournaments = const [],
}) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: auth,
          racesState: Loadable.success({
            'active': active,
            'pending': pending,
            'completed': completed,
            'tournaments': tournaments,
          }),
          friendsSteps: const [],
          onRacesChanged: _noop,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _selectState(WidgetTester tester, String state) async {
  await tester.tap(find.byKey(Key('personal-state-$state')));
  await tester.pump(const Duration(milliseconds: 200));
}

String _countText(WidgetTester tester, String state) {
  return tester
      .widget<Text>(find.byKey(Key('personal-state-count-$state')))
      .data!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pills always render', () {
    testWidgets('all three appear with count badges, defaulting to ACTIVE',
        (tester) async {
      await _pump(tester, active: [_race('r1', 'Active Race', 'ACTIVE')]);

      for (final state in ['active', 'pending', 'completed']) {
        expect(find.byKey(Key('personal-state-$state')), findsOneWidget);
        expect(
          find.byKey(Key('personal-state-count-$state')),
          findsOneWidget,
          reason: state,
        );
      }
      // Default selection shows the active race without any interaction.
      expect(find.text('Active Race'), findsOneWidget);
    });

    testWidgets('zero counts still render a badge', (tester) async {
      // "Including 0" — an empty shelf must be legible before tapping it.
      await _pump(tester);
      expect(_countText(tester, 'active'), '0');
      expect(_countText(tester, 'pending'), '0');
      expect(_countText(tester, 'completed'), '0');
    });
  });

  group('counts combine races and tournaments', () {
    testWidgets('each state counts both sources', (tester) async {
      await _pump(
        tester,
        active: [
          _race('r1', 'A1', 'ACTIVE'),
          _race('r2', 'A2', 'ACTIVE'),
        ],
        pending: [_race('r3', 'P1', 'PENDING')],
        completed: [_race('r4', 'C1', 'COMPLETED')],
        tournaments: [
          // Live matchup -> ACTIVE
          {
            'id': 't1',
            'name': 'Live Bracket',
            'status': 'ACTIVE',
            'myStatus': 'ACCEPTED',
            'myCurrentMatch': {'raceId': 'race-9'},
          },
          // Lobby -> PENDING
          {
            'id': 't2',
            'name': 'Lobby Bracket',
            'status': 'PENDING',
            'myStatus': 'ACCEPTED',
          },
          // Eliminated -> COMPLETED
          {
            'id': 't3',
            'name': 'Dead Bracket',
            'status': 'ACTIVE',
            'myStatus': 'ACCEPTED',
            'myEliminatedInRound': 1,
          },
        ],
      );

      expect(_countText(tester, 'active'), '3'); // 2 races + 1 tournament
      expect(_countText(tester, 'pending'), '2'); // 1 race + 1 tournament
      expect(_countText(tester, 'completed'), '2'); // 1 race + 1 tournament
    });

    testWidgets('invites are NOT counted in the pills', (tester) async {
      // They live in the pinned strip; double-counting them would misreport
      // how much is actually in each state.
      await _pump(
        tester,
        pending: [
          {
            'id': 'r1',
            'name': 'Invited Race',
            'status': 'PENDING',
            'myStatus': 'INVITED',
            'maxDurationDays': 7,
            'participantCount': 2,
          },
        ],
      );
      expect(_countText(tester, 'pending'), '0');
      expect(find.byKey(const Key('invites-strip-header')), findsOneWidget);
    });
  });

  group('perf: only the selected state builds rows', () {
    testWidgets('non-selected states do not build their rows', (tester) async {
      await _pump(
        tester,
        active: [_race('r1', 'Active Race', 'ACTIVE')],
        pending: [_race('r2', 'Pending Race', 'PENDING')],
        completed: [_race('r3', 'Completed Race', 'COMPLETED')],
      );

      // ACTIVE selected: the other two states' rows must not exist in the tree.
      expect(find.text('Active Race'), findsOneWidget);
      expect(find.text('Pending Race'), findsNothing);
      expect(find.text('Completed Race'), findsNothing);

      await _selectState(tester, 'pending');
      expect(find.text('Pending Race'), findsOneWidget);
      expect(find.text('Active Race'), findsNothing);
      expect(find.text('Completed Race'), findsNothing);

      await _selectState(tester, 'completed');
      expect(find.text('Completed Race'), findsOneWidget);
      expect(find.text('Active Race'), findsNothing);
      expect(find.text('Pending Race'), findsNothing);
    });

    testWidgets('rows build inside a lazy SliverList, not a Column',
        (tester) async {
      // A long list must not materialise every row. With a short viewport only
      // a bounded number of the 60 rows should be built.
      await _pump(
        tester,
        active: [
          for (var i = 0; i < 60; i++) _race('r$i', 'Race $i', 'ACTIVE'),
        ],
      );

      expect(find.byType(SliverList), findsWidgets);
      // Far fewer than 60 rows are realised.
      expect(find.text('Race 0'), findsOneWidget);
      expect(find.text('Race 59'), findsNothing);
    });
  });

  group('state-specific empty messages', () {
    testWidgets('an empty selected state explains which shelf is empty',
        (tester) async {
      await _pump(tester, active: [_race('r1', 'Active Race', 'ACTIVE')]);

      await _selectState(tester, 'completed');
      expect(
        find.byKey(const Key('personal-state-empty-completed')),
        findsOneWidget,
      );
      expect(find.textContaining('No finished races'), findsOneWidget);

      await _selectState(tester, 'pending');
      expect(find.textContaining('Nothing waiting to start'), findsOneWidget);
    });

    testWidgets('a user with nothing at all still gets the pills',
        (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('personal-state-active')), findsOneWidget);
      // …plus the fuller onboarding nudge rather than a terse one-liner.
      expect(find.textContaining('Start one with friends'), findsOneWidget);
    });
  });

  group('older-backend shapes', () {
    testWidgets('a payload with no tournaments key renders normally',
        (tester) async {
      final auth = await _auth();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RacesTab(
              authService: auth,
              racesState: Loadable.success({
                'active': [_race('r1', 'Active Race', 'ACTIVE')],
                'pending': const [],
                'completed': const [],
              }),
              friendsSteps: const [],
              onRacesChanged: _noop,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Active Race'), findsOneWidget);
      expect(_countText(tester, 'active'), '1');
    });

    testWidgets('a tournament with only the legacy raceId still counts ACTIVE',
        (tester) async {
      await _pump(tester, tournaments: [
        {
          'id': 't1',
          'name': 'Legacy Bracket',
          'status': 'ACTIVE',
          'myStatus': 'ACCEPTED',
          'myCurrentMatchRaceId': 'race-9',
        },
      ]);
      expect(_countText(tester, 'active'), '1');
      expect(find.text('Legacy Bracket'), findsOneWidget);
    });
  });
}
