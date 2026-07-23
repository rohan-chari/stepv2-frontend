import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

// The FEATURED strip moved to the Public Races screen (2026-07-23); its tests
// were ported to public_races_featured_strip_test.dart. What remains here are
// the personal-list guarantees that still belong to the Races tab: tournaments
// keys degrade safely (the #1 rule) and the tab renders the user's own content
// with no featured chrome.

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

Map<String, dynamic> _activeRace() => {
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

Future<void> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? racesData,
}) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: auth,
          racesState: Loadable.success(
            racesData ??
                {'active': const [], 'pending': const [], 'completed': const []},
          ),
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

  testWidgets('missing tournaments key is defensive (no crash, no section)',
      (tester) async {
    // racesData without a `tournaments` key.
    await _pump(
      tester,
      racesData: {
        'active': [_activeRace()],
        'pending': const [],
        'completed': const [],
      },
    );
    // Race content renders; no tournament row badge anywhere.
    // §4 removed the ACTIVE RACES section header — the personal list is now
    // pills + rows, so assert the user's own race ROW instead.
    expect(find.text('My Race'), findsOneWidget);
    expect(find.text('ALIVE'), findsNothing);
  });

  testWidgets('no featured chrome renders on the Races tab anymore',
      (tester) async {
    await _pump(
      tester,
      racesData: {
        'active': [_activeRace()],
        'pending': const [],
        'completed': const [],
      },
    );
    // The old strip's filter pill is gone (the strip lives on Public Races
    // now)…
    expect(find.byKey(const Key('content-filter-all')), findsNothing);
    expect(find.text('FEATURED'), findsNothing);
    // …and user content still renders normally.
    expect(find.text('My Race'), findsOneWidget);
  });
}
