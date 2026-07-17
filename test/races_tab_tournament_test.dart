import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// Spec §9/§10: the races tab renders a TOURNAMENTS section from the additive
// GET /races `tournaments` bucket — ticket states (alive / knocked out /
// filling / champion), invited brackets with inline accept/decline, and a
// clean absence when the key is missing (older backend).

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
}) async {
  final auth = await _auth();
  final api = _RecordingApi();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: auth,
          racesState: Loadable.success({
            'active': const [],
            'pending': const [],
            'completed': const [],
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('no tournaments key → no TOURNAMENTS section (older backend)',
      (tester) async {
    await _pump(tester);
    expect(find.text('TOURNAMENTS'), findsNothing);
  });

  testWidgets('ACTIVE alive ticket shows the alive status line',
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
      },
    ]);
    // The user's brackets render under the "MY BRACKETS" section header (the
    // TOURNAMENTS label now belongs to the featured-row filter pill, which only
    // shows when there's featured content — none in this test).
    expect(find.text('MY BRACKETS'), findsOneWidget);
    expect(find.textContaining("YOU'RE ALIVE"), findsOneWidget);
    expect(find.text('ALIVE'), findsOneWidget);
  });

  testWidgets('eliminated ticket shows KNOCKED OUT', (tester) async {
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
    expect(find.textContaining('KNOCKED OUT'), findsOneWidget);
    expect(find.text('OUT'), findsOneWidget);
  });

  testWidgets('PENDING ticket shows fill count', (tester) async {
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
    expect(find.text('5/8 FILLED'), findsOneWidget);
    expect(find.text('LOBBY'), findsOneWidget);
  });

  testWidgets('invited ticket shows accept/decline and calls respond',
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
    expect(find.byKey(const Key('tournament-accept-tinv')), findsOneWidget);
    expect(find.byKey(const Key('tournament-decline-tinv')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tournament-accept-tinv')));
    await tester.pump();
    expect(api.lastRespondCall, isNotNull);
    expect(api.lastRespondCall!['tournamentId'], 'tinv');
    expect(api.lastRespondCall!['accept'], true);
  });

  testWidgets('champion ticket surfaces CHAMPION badge', (tester) async {
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
    expect(find.text('CHAMPION'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);
  });
}
