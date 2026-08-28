import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/styles.dart';

// The personal race list now uses individually inset rounded tickets. The page
// header and state pill bar retain their existing insets.

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

Future<double> _pumpRaces(
  WidgetTester tester,
  AuthService auth, {
  Map<String, dynamic>? racesData,
}) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeData.light(),
      home: Scaffold(
        body: RacesTab(
          authService: auth,
          racesData:
              racesData ??
              const {
                'active': [
                  {
                    'id': 'race-1',
                    'name': 'Morning Dash',
                    'targetSteps': 12000,
                    'participantCount': 3,
                    'status': 'ACTIVE',
                    'creator': {'displayName': 'RaceMaker'},
                    'isCreator': false,
                    'myPlacement': 1,
                    'placementPrivacyActive': false,
                  },
                ],
                'pending': [],
                'completed': [],
              },
          friendsSteps: const [],
          onRacesChanged: _noop,
          displayName: 'Trail Walker',
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.view.physicalSize.width / tester.view.devicePixelRatio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an active race ticket is inset from both screen edges', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final screenWidth = await _pumpRaces(tester, auth);

    final card = find.byKey(const Key('race-card-surface-race-1'));
    expect(card, findsOneWidget);
    final rect = tester.getRect(card);
    expect(rect.left, 10);
    expect(screenWidth - rect.right, 10);
  });

  testWidgets('the page header and state pills keep their insets', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final screenWidth = await _pumpRaces(tester, auth);

    final title = find.text('RACES');
    expect(title, findsOneWidget);
    expect(tester.getRect(title).left, greaterThanOrEqualTo(16));

    // The state pill bar (ACTIVE / PENDING / COMPLETED) stays inset.
    final pill = find.text('ACTIVE');
    expect(pill, findsWidgets);
    final pillRect = tester.getRect(pill.first);
    expect(pillRect.left, greaterThan(8));
    expect(screenWidth - pillRect.right, greaterThan(8));
  });

  testWidgets('the empty state card reaches both screen edges', (tester) async {
    final auth = await _createAuthService();
    final screenWidth = await _pumpRaces(
      tester,
      auth,
      racesData: const {'active': [], 'pending': [], 'completed': []},
    );

    expect(find.text('No races yet'), findsOneWidget);
    final cardRect = tester.getRect(
      find.byKey(const Key('races-empty-state-card')),
    );
    expect(cardRect.left, 0);
    expect(cardRect.right, screenWidth);
  });
}
