import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

/// B6 — the ACTIVE/PENDING/COMPLETED pill counts get a circular min-width badge.
///
/// The count Text keeps its existing `personal-state-count-*` Key (older tests
/// read it), but is now wrapped in a rounded/circular badge container. The badge
/// must not change the pill height and two-digit counts must fit (min-width
/// circle, padding-based — not a fixed width).
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
}) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: auth,
          racesState: Loadable.success({
            'active': active,
            'pending': const [],
            'completed': const [],
            'tournaments': const [],
          }),
          friendsSteps: const [],
          onRacesChanged: _noop,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The dedicated badge container wrapping the count (keyed distinctly from the
/// pill itself so we don't accidentally match the pill's own decoration).
BoxDecoration? _badgeDecoration(WidgetTester tester, String state) {
  final badgeFinder = find.byKey(Key('personal-state-badge-$state'));
  expect(badgeFinder, findsOneWidget, reason: '$state has no badge widget');
  // The keyed badge must wrap the keyed count text.
  expect(
    find.descendant(
      of: badgeFinder,
      matching: find.byKey(Key('personal-state-count-$state')),
    ),
    findsOneWidget,
    reason: '$state badge does not wrap its count',
  );
  final decoratedFinder = find
      .descendant(of: badgeFinder, matching: find.byType(DecoratedBox))
      .first;
  final decorated = tester.widget<DecoratedBox>(decoratedFinder);
  final decoration = decorated.decoration;
  return decoration is BoxDecoration ? decoration : null;
}

double _pillHeight(WidgetTester tester, String state) {
  return tester.getSize(find.byKey(Key('personal-state-$state'))).height;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('each count sits inside a rounded badge in both states',
      (tester) async {
    // ACTIVE is selected by default; PENDING/COMPLETED are unselected.
    await _pump(tester, active: [_race('r1', 'Active Race', 'ACTIVE')]);

    for (final state in ['active', 'pending', 'completed']) {
      final deco = _badgeDecoration(tester, state);
      expect(deco, isNotNull, reason: '$state has no badge decoration');
      // A circular/rounded badge, not a square block.
      final radius = deco!.borderRadius as BorderRadius?;
      expect(radius, isNotNull, reason: '$state badge has no borderRadius');
      expect(
        radius!.topLeft.x,
        greaterThanOrEqualTo(9),
        reason: '$state badge is not rounded enough to read as a pill/circle',
      );
    }
  });

  testWidgets('a two-digit count does not change the pill height',
      (tester) async {
    // Single digit.
    await _pump(tester, active: [_race('r1', 'Active Race', 'ACTIVE')]);
    final singleDigitHeight = _pillHeight(tester, 'active');
    expect(
      tester.widget<Text>(find.byKey(const Key('personal-state-count-active'))).data,
      '1',
    );

    // Double digit: 12 active races.
    await _pump(
      tester,
      active: [for (var i = 0; i < 12; i++) _race('r$i', 'Race $i', 'ACTIVE')],
    );
    final doubleDigitHeight = _pillHeight(tester, 'active');
    expect(
      tester.widget<Text>(find.byKey(const Key('personal-state-count-active'))).data,
      '12',
    );

    // The badge grows horizontally (min-width circle), never taller.
    expect(doubleDigitHeight, singleDigitHeight);
  });
}
