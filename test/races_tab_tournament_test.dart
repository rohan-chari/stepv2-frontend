import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// §4: personal tournaments are MERGED into the ordinary personal race states
// rather than living in their own MY BRACKETS section.
//
// This file previously asserted that MY BRACKETS section and its ticket
// layout. The approved spec replaces both, so the assertions were rewritten
// against the new UI — but every behaviour the old file covered is still
// covered here:
//
//   old: "no tournaments key -> no TOURNAMENTS section"  -> older-backend group
//   old: "ACTIVE alive ticket shows the alive status line" -> alive-between-rounds
//   old: "eliminated ticket shows KNOCKED OUT"           -> eliminated -> COMPLETED
//   old: "PENDING ticket shows fill count"               -> lobby -> PENDING
//   old: "invited ticket shows accept/decline + responds" -> pinned invites strip
//   old: "champion ticket surfaces CHAMPION badge"        -> champion -> COMPLETED

Future<void> _noop() async {}

class _RecordingApi extends BackendApiService {
  Map<String, dynamic>? lastRespondCall;

  @override
  Future<Map<String, dynamic>> respondToTournamentInvite({
    required String identityToken,
    required String tournamentId,
    required bool accept,
  }) async {
    lastRespondCall = {'tournamentId': tournamentId, 'accept': accept};
    return {
      'tournament': {'id': tournamentId, 'status': 'PENDING'},
    };
  }
}

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

Future<_RecordingApi> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>>? tournaments,
  List<Map<String, dynamic>> active = const [],
  List<Map<String, dynamic>> pending = const [],
  List<Map<String, dynamic>> completed = const [],
}) async {
  final auth = await _auth();
  final api = _RecordingApi();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: auth,
          racesState: Loadable.success({
            'active': active,
            'pending': pending,
            'completed': completed,
            if (tournaments != null) 'tournaments': tournaments,
          }),
          friendsSteps: const [],
          onRacesChanged: _noop,
          backendApiService: api,
        ),
      ),
    ),
  );
  await tester.pump();
  return api;
}

/// Selects one of the ACTIVE / PENDING / COMPLETED pills.
Future<void> _selectState(WidgetTester tester, String state) async {
  await tester.tap(find.byKey(Key('personal-state-$state')));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('older backend / defensive absence', () {
    testWidgets('a missing tournaments key renders the list with no rows',
        (tester) async {
      await _pump(tester);
      // The old MY BRACKETS section is gone entirely.
      expect(find.text('MY BRACKETS'), findsNothing);
      // And nothing crashed: the pills are the personal-list navigation now.
      expect(find.byKey(const Key('personal-state-active')), findsOneWidget);
    });

    testWidgets('an empty tournaments list is handled', (tester) async {
      await _pump(tester, tournaments: const []);
      expect(find.byKey(const Key('personal-state-active')), findsOneWidget);
    });

    testWidgets('a malformed tournament entry never crashes the list',
        (tester) async {
      await _pump(tester, tournaments: [
        {'id': 't1', 'status': 42, 'myStatus': <String>[]},
      ]);
      expect(find.byKey(const Key('personal-state-active')), findsOneWidget);
    });
  });

  group('§4.2 state mapping renders in the right pill', () {
    testWidgets('a live matchup lands in ACTIVE with its inventory',
        (tester) async {
      await _pump(tester, tournaments: [
        {
          'id': 't1',
          'name': 'Friday Gauntlet',
          'status': 'ACTIVE',
          'bracketSize': 8,
          'currentRound': 2,
          'totalRounds': 3,
          'myStatus': 'ACCEPTED',
          'myCurrentMatch': {
            'raceId': 'race-9',
            'endsAt': '2099-01-01T00:00:00.000Z',
            'myPlacement': 2,
            'queuedBoxCount': 1,
            'mysteryBoxCount': 1,
            'slotItems': [
              {'id': 'p1', 'type': 'LEG_CRAMP', 'status': 'HELD'},
            ],
          },
        },
      ]);

      // ACTIVE is the default pill.
      expect(find.text('Friday Gauntlet'), findsOneWidget);
      expect(find.text('ALIVE'), findsOneWidget);
      expect(find.text('SEMIFINALS'), findsOneWidget);
      expect(find.text('2ND PLACE'), findsOneWidget);
    });

    testWidgets(
        'alive between rounds (no live matchup) lands in PENDING with its '
        'status line', (tester) async {
      // Replaces the old "ACTIVE alive ticket shows the alive status line".
      await _pump(tester, tournaments: [
        {
          'id': 't1',
          'name': 'Friday Gauntlet',
          'status': 'ACTIVE',
          'bracketSize': 8,
          'currentRound': 2,
          'totalRounds': 3,
          'myStatus': 'ACCEPTED',
        },
      ]);

      // Not in ACTIVE — there is nothing to walk in right now.
      expect(find.text('Friday Gauntlet'), findsNothing);

      await _selectState(tester, 'pending');
      expect(find.text('Friday Gauntlet'), findsOneWidget);
      expect(find.textContaining("YOU'RE ALIVE"), findsOneWidget);
      expect(find.text('ALIVE'), findsOneWidget);
    });

    testWidgets('an eliminated bracket lands in COMPLETED as KNOCKED OUT',
        (tester) async {
      await _pump(tester, tournaments: [
        {
          'id': 't1',
          'name': 'Friday Gauntlet',
          'status': 'ACTIVE',
          'bracketSize': 8,
          'currentRound': 3,
          'totalRounds': 3,
          'myStatus': 'ACCEPTED',
          'myEliminatedInRound': 1,
        },
      ]);

      await _selectState(tester, 'completed');
      expect(find.textContaining('KNOCKED OUT'), findsOneWidget);
      expect(find.text('OUT'), findsOneWidget);
    });

    testWidgets('a lobby bracket lands in PENDING with its fill count',
        (tester) async {
      await _pump(tester, tournaments: [
        {
          'id': 't1',
          'name': 'Lobby Bracket',
          'status': 'PENDING',
          'bracketSize': 8,
          'acceptedCount': 5,
          'myStatus': 'ACCEPTED',
        },
      ]);

      await _selectState(tester, 'pending');
      expect(find.text('5/8 FILLED'), findsOneWidget);
      expect(find.text('LOBBY'), findsOneWidget);
    });

    testWidgets('a champion lands in COMPLETED with the CHAMPION badge',
        (tester) async {
      await _pump(tester, tournaments: [
        {
          'id': 't1',
          'name': 'Done Bracket',
          'status': 'COMPLETED',
          'bracketSize': 4,
          'championUserId': 'user-1',
          'potCoins': 400,
          'myStatus': 'ACCEPTED',
        },
      ]);

      await _selectState(tester, 'completed');
      expect(find.text('CHAMPION'), findsOneWidget);
      expect(find.text('400'), findsOneWidget);
    });

    testWidgets('a completed bracket I did not win still lands in COMPLETED',
        (tester) async {
      await _pump(tester, tournaments: [
        {
          'id': 't1',
          'name': 'Done Bracket',
          'status': 'COMPLETED',
          'bracketSize': 4,
          'championUserId': 'someone-else',
          'myStatus': 'ACCEPTED',
        },
      ]);

      await _selectState(tester, 'completed');
      expect(find.text('Done Bracket'), findsOneWidget);
    });
  });

  group('pinned invites strip', () {
    testWidgets('an invited bracket shows accept/decline and calls respond',
        (tester) async {
      final api = await _pump(tester, tournaments: [
        {
          'id': 'tinv',
          'name': 'Invite Me',
          'status': 'PENDING',
          'bracketSize': 4,
          'acceptedCount': 2,
          'myStatus': 'INVITED',
        },
      ]);

      // Visible on FIRST PAINT with no interaction — invites are never behind
      // a pill, which is the whole point of the pinned strip.
      expect(find.byKey(const Key('invites-strip-header')), findsOneWidget);
      expect(find.byKey(const Key('tournament-accept-tinv')), findsOneWidget);
      expect(find.byKey(const Key('tournament-decline-tinv')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tournament-accept-tinv')));
      await tester.pump();
      expect(api.lastRespondCall, isNotNull);
      expect(api.lastRespondCall!['tournamentId'], 'tinv');
      expect(api.lastRespondCall!['accept'], true);
    });

    testWidgets('decline is wired too', (tester) async {
      final api = await _pump(tester, tournaments: [
        {
          'id': 'tinv',
          'name': 'Invite Me',
          'status': 'PENDING',
          'bracketSize': 4,
          'myStatus': 'INVITED',
        },
      ]);

      await tester.tap(find.byKey(const Key('tournament-decline-tinv')));
      await tester.pump();
      expect(api.lastRespondCall!['accept'], false);
    });

    testWidgets('an invite to an already-started bracket still shows',
        (tester) async {
      // §4.2: INVITED + ACTIVE stays in the strip so the user can clear it.
      await _pump(tester, tournaments: [
        {
          'id': 'tinv',
          'name': 'Late Invite',
          'status': 'ACTIVE',
          'bracketSize': 4,
          'myStatus': 'INVITED',
        },
      ]);
      expect(find.byKey(const Key('tournament-decline-tinv')), findsOneWidget);
    });

    testWidgets('the strip is absent entirely when there are no invites',
        (tester) async {
      await _pump(tester, tournaments: [
        {
          'id': 't1',
          'name': 'Lobby Bracket',
          'status': 'PENDING',
          'bracketSize': 8,
          'myStatus': 'ACCEPTED',
        },
      ]);
      expect(find.byKey(const Key('invites-strip-header')), findsNothing);
    });

    testWidgets('a declined bracket is filtered out of every state',
        (tester) async {
      await _pump(tester, tournaments: [
        {
          'id': 't1',
          'name': 'Declined Bracket',
          'status': 'PENDING',
          'bracketSize': 8,
          'myStatus': 'DECLINED',
        },
      ]);
      expect(find.text('Declined Bracket'), findsNothing);
      await _selectState(tester, 'pending');
      expect(find.text('Declined Bracket'), findsNothing);
    });
  });
}
