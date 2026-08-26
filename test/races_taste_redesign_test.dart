import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: await _auth(),
          racesData: const {'active': [], 'pending': [], 'completed': []},
          friendsSteps: const [],
          onRacesChanged: _noop,
          displayName: 'Trail Walker',
          publicRacesCount: 12,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _noop() async {}

void main() {
  testWidgets('Races header uses one primary action and compact discovery', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.text(
        'Race friends, climb the board, and turn daily steps into wins.',
      ),
      findsNothing,
    );
    final create = find.byKey(const Key('races-new-action'));
    final public = find.byKey(const Key('races-public-action'));
    expect(create, findsOneWidget);
    expect(public, findsOneWidget);
    expect(tester.getSize(public), const Size(58, 58));
    expect(tester.getSize(create).height, 58);
    expect(tester.getTopLeft(create).dy, tester.getTopLeft(public).dy);
    expect(tester.getRect(create).right, lessThan(tester.getRect(public).left));
    expect(
      find.descendant(of: public, matching: find.text('12')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Public races, 12 available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
