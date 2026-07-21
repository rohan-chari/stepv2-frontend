import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/widgets/team_scoreline.dart';

// TR-806: races-list rows for team races get a team format chip ("2v2"),
// team color badge, and — for ACTIVE team races with totals — a mini
// scoreline ("Red 12,340 — 11,900 Blue").

Future<void> _noop() async {}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 125,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Map<String, dynamic> _teamRace({
  String status = 'ACTIVE',
  Map<String, dynamic>? teams,
}) {
  return {
    'id': 'race-team',
    'name': 'Team Clash',
    'status': status,
    'isTeamRace': true,
    'teamSize': 2,
    'teamAName': 'Swift Capys',
    'teamBName': 'Turbo Beavers',
    'maxDurationDays': 7,
    'participantCount': 4,
    'myStatus': 'ACCEPTED',
    'isCreator': false,
    'endsAt':
        DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
    if (teams != null) 'teams': teams,
  };
}

Future<void> _pump(WidgetTester tester, Map<String, dynamic> race) async {
  final authService = await _createAuthService();
  final section = race['status'] == 'ACTIVE' ? 'active' : 'pending';
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: authService,
          racesState: Loadable.success({
            'active': section == 'active' ? [race] : [],
            'pending': section == 'pending' ? [race] : [],
            'completed': [],
          }),
          friendsSteps: const [],
          onRacesChanged: _noop,
          displayName: 'Trail Walker',
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-806: ACTIVE team race row shows format chip and scoreline',
      (tester) async {
    await _pump(
      tester,
      _teamRace(
        teams: {
          'teamA': {'totalSteps': 12340, 'memberCount': 2},
          'teamB': {'totalSteps': 11900, 'memberCount': 2},
        },
      ),
    );

    expect(find.text('2v2'), findsOneWidget);
    expect(find.byType(TeamScoreline), findsOneWidget);
    expect(find.textContaining('12,340'), findsOneWidget);
    expect(find.textContaining('11,900'), findsOneWidget);
  });

  testWidgets(
      'TR-806: ACTIVE team race without totals shows the chip but no '
      'scoreline (older payload)', (tester) async {
    await _pump(tester, _teamRace());

    expect(find.text('2v2'), findsOneWidget);
    expect(find.byType(TeamScoreline), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TR-806: PENDING team race row shows the format chip',
      (tester) async {
    await _pump(tester, _teamRace(status: 'PENDING'));
    // §4: the personal list is now state pills defaulting to ACTIVE, so a
    // PENDING row lives behind the PENDING pill. Navigate to it — the
    // assertion below is unchanged.
    await tester.tap(find.byKey(const Key('personal-state-pending')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('2v2'), findsOneWidget);
  });

  testWidgets('TR-705: individual race rows are unchanged', (tester) async {
    final race = _teamRace()
      ..remove('isTeamRace')
      ..remove('teamSize')
      ..remove('teamAName')
      ..remove('teamBName');
    await _pump(tester, race);

    expect(find.text('2v2'), findsNothing);
    expect(find.byType(TeamScoreline), findsNothing);
  });
}
