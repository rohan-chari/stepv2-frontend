import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

// Each ACTIVE race row on the Races tab shows a compact cluster of the effects
// currently on ME: boosts first, then debuffs, each as its real powerup sprite
// on a polarity-tinted plate. The data rides the already-loaded /races payload
// (`myActiveEffects`) — no per-race fetch — and the cluster renders nothing at
// all when the field is absent (old backend) so old rows never shift.

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

Finder _platesWith(String polarity) => find.byWidgetPredicate((w) {
  final key = w.key;
  return key is ValueKey<String> &&
      key.value.startsWith('effect-plate-$polarity');
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '2 boosts + 1 debuff render 3 sprite plates, boosts before debuffs, tinted',
    (tester) async {
      await _pump(
        tester,
        race: _activeRace(
          // createdAt-asc payload order; a rival-cast UPRISING is still a boost.
          myActiveEffects: [
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
            {
              'type': 'UPRISING',
              'sourceUserId': 'u2',
              'expiresAt': '2027-12-01T00:00:00.000Z',
            },
          ],
        ),
      );

      expect(find.byKey(_cluster), findsOneWidget);

      // Three real sprites render inside the cluster.
      expect(
        find.descendant(of: find.byKey(_cluster), matching: find.byType(PowerupIcon)),
        findsNWidgets(3),
      );

      // Two boost plates, one debuff plate.
      expect(_platesWith('boost'), findsNWidgets(2));
      expect(_platesWith('debuff'), findsOneWidget);

      // Boosts render to the LEFT of debuffs (boosts-first ordering).
      final debuffDx = tester.getTopLeft(_platesWith('debuff')).dx;
      for (final boost in tester.widgetList<Widget>(_platesWith('boost'))) {
        final boostDx = tester.getTopLeft(find.byWidget(boost)).dx;
        expect(boostDx, lessThan(debuffDx));
      }

      // Right tints: boosts use feedBoost @0.15, debuffs use feedAttack @0.15.
      final boostPlate =
          tester.widget<Container>(_platesWith('boost').first);
      final boostDeco = boostPlate.decoration as BoxDecoration;
      expect(
        boostDeco.color,
        AppPalette.light.feedBoost.withValues(alpha: 0.15),
      );
      final debuffPlate = tester.widget<Container>(_platesWith('debuff'));
      final debuffDeco = debuffPlate.decoration as BoxDecoration;
      expect(
        debuffDeco.color,
        AppPalette.light.feedAttack.withValues(alpha: 0.15),
      );
    },
  );

  testWidgets('absent myActiveEffects renders no cluster (old backend)',
      (tester) async {
    await _pump(tester, race: _activeRace());
    expect(find.text('My Race'), findsOneWidget);
    expect(find.byKey(_cluster), findsNothing);
    // No stray sprite plates anywhere on the row.
    expect(_platesWith('boost'), findsNothing);
    expect(_platesWith('debuff'), findsNothing);
  });

  testWidgets('5 effects cap at 3 plates + a "+2" overflow chip',
      (tester) async {
    await _pump(
      tester,
      race: _activeRace(
        myActiveEffects: [
          for (var i = 0; i < 5; i++)
            {
              'type': 'LEG_CRAMP',
              'sourceUserId': 'u2',
              'expiresAt': '2027-12-01T00:00:00.000Z',
            },
        ],
      ),
    );

    expect(
      find.descendant(of: find.byKey(_cluster), matching: find.byType(PowerupIcon)),
      findsNWidgets(3),
    );
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('exactly 3 effects renders no overflow chip', (tester) async {
    await _pump(
      tester,
      race: _activeRace(
        myActiveEffects: [
          for (var i = 0; i < 3; i++)
            {
              'type': 'LEG_CRAMP',
              'sourceUserId': 'u2',
              'expiresAt': '2027-12-01T00:00:00.000Z',
            },
        ],
      ),
    );

    expect(
      find.descendant(of: find.byKey(_cluster), matching: find.byType(PowerupIcon)),
      findsNWidgets(3),
    );
    expect(find.textContaining('+'), findsNothing);
  });
}
