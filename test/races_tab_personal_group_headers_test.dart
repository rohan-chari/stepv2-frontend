import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_backend_user_id': 'user-1',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Map<String, dynamic> _race(
  String id, {
  bool team = false,
  String status = 'ACTIVE',
}) => {
  'id': id,
  'name': id,
  'status': status,
  'myStatus': 'ACCEPTED',
  'maxDurationDays': 7,
  'participants': const [],
  if (team) 'isTeamRace': true,
};

Map<String, dynamic> _tournament(String id, {String status = 'ACTIVE'}) => {
  'id': id,
  'name': id,
  'status': status,
  'myStatus': 'ACCEPTED',
  'bracketSize': 8,
  if (status == 'ACTIVE') 'myCurrentMatch': const {'raceId': 'match-1'},
  'myIdentity': const {'equippedAccessories': []},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'active personal list groups classic, team, and tournament cards in order',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RacesTab(
              authService: await _auth(),
              racesState: Loadable.success({
                'active': [_race('classic'), _race('team', team: true)],
                'pending': const [],
                'completed': const [],
                'tournaments': [_tournament('bracket')],
              }),
              friendsSteps: const [],
              onRacesChanged: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      final classic = find.byKey(const Key('personal-group-classic'));
      final teams = find.byKey(const Key('personal-group-teams'));
      final tournaments = find.byKey(const Key('personal-group-tournaments'));
      expect(classic, findsOneWidget);
      expect(teams, findsOneWidget);
      expect(tournaments, findsOneWidget);
      expect(
        tester.getTopLeft(classic).dy,
        lessThan(tester.getTopLeft(teams).dy),
      );
      expect(
        tester.getTopLeft(teams).dy,
        lessThan(tester.getTopLeft(tournaments).dy),
      );
    },
  );

  for (final state in ['PENDING', 'COMPLETED']) {
    testWidgets('$state personal list keeps all non-empty group headers', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RacesTab(
              authService: await _auth(),
              racesState: Loadable.success({
                'active': const [],
                'pending': state == 'PENDING'
                    ? [
                        _race('classic-$state', status: state),
                        _race('team-$state', team: true, status: state),
                      ]
                    : const [],
                'completed': state == 'COMPLETED'
                    ? [
                        _race('classic-$state', status: state),
                        _race('team-$state', team: true, status: state),
                      ]
                    : const [],
                'tournaments': [_tournament('bracket-$state', status: state)],
              }),
              friendsSteps: const [],
              onRacesChanged: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(Key('personal-state-${state.toLowerCase()}')),
      );
      await tester.pump();
      expect(find.byKey(const Key('personal-group-classic')), findsOneWidget);
      expect(find.byKey(const Key('personal-group-teams')), findsOneWidget);
      expect(
        find.byKey(const Key('personal-group-tournaments')),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'empty categories do not leave a personal-list group header behind',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RacesTab(
              authService: await _auth(),
              racesState: Loadable.success({
                'active': const [],
                'pending': const [],
                'completed': const [],
                'tournaments': [_tournament('bracket')],
              }),
              friendsSteps: const [],
              onRacesChanged: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('personal-group-classic')), findsNothing);
      expect(find.byKey(const Key('personal-group-teams')), findsNothing);
      expect(
        find.byKey(const Key('personal-group-tournaments')),
        findsOneWidget,
      );
    },
  );
}
