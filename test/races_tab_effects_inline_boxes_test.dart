import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/widgets/spinning_crate.dart';

// Item 11: on an ACTIVE race row the buff/debuff badge cluster moves inline
// with the boxes row, split by a slim muted "|" separator. The separator only
// renders when there are active effects, so a no-effects row is just the boxes.

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

Map<String, dynamic> _activeRace({List<Map<String, dynamic>>? myActiveEffects}) {
  final race = <String, dynamic>{
    'id': 'r1',
    'name': 'My Race',
    'status': 'ACTIVE',
    'maxDurationDays': 7,
    'participantCount': 3,
    'myStatus': 'ACCEPTED',
    'isCreator': false,
    'endsAt':
        DateTime.now().add(const Duration(days: 2)).toUtc().toIso8601String(),
  };
  if (myActiveEffects != null) race['myActiveEffects'] = myActiveEffects;
  return race;
}

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> race,
}) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: auth,
          racesState: Loadable.success({
            'active': [race],
            'pending': const [],
            'completed': const [],
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

const _cluster = Key('race-effects-r1');
const _separator = Key('race-effects-sep-r1');

List<Map<String, dynamic>> _effects() => [
  {
    'type': 'RUNNERS_HIGH',
    'sourceUserId': 'user-1',
    'expiresAt': '2027-12-01T00:00:00.000Z',
  },
  {
    'type': 'LEG_CRAMP',
    'sourceUserId': 'u2',
    'expiresAt': '2027-12-01T00:00:00.000Z',
  },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'effects + boxes: boxes, separator, then badges render in one left-to-right row',
    (tester) async {
      await _pump(tester, race: _activeRace(myActiveEffects: _effects()));

      // Boxes still render (empty inventory crates).
      expect(find.byType(CrateIcon), findsWidgets);
      // Separator and cluster both present.
      expect(find.byKey(_separator), findsOneWidget);
      expect(find.byKey(_cluster), findsOneWidget);

      // Left-to-right order: a box crate, then the separator, then the cluster.
      final crateDx = tester.getTopLeft(find.byType(CrateIcon).first).dx;
      final sepDx = tester.getTopLeft(find.byKey(_separator)).dx;
      final clusterDx = tester.getTopLeft(find.byKey(_cluster)).dx;
      expect(crateDx, lessThan(sepDx));
      expect(sepDx, lessThan(clusterDx));
    },
  );

  testWidgets('no active effects: boxes only, no separator, no cluster',
      (tester) async {
    await _pump(tester, race: _activeRace());
    expect(find.byType(CrateIcon), findsWidgets);
    expect(find.byKey(_separator), findsNothing);
    expect(find.byKey(_cluster), findsNothing);
  });

  testWidgets('effects present: badge cluster renders alongside the boxes',
      (tester) async {
    await _pump(tester, race: _activeRace(myActiveEffects: _effects()));
    expect(find.byKey(_cluster), findsOneWidget);
    expect(find.byType(CrateIcon), findsWidgets);
  });
}
