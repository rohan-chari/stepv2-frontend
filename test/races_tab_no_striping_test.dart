import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/styles.dart';

Future<void> _noop() async {}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'viewer',
    'auth_display_name': 'Trail Walker',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Map<String, dynamic> _activeRace(int i) => {
  'id': 'race-$i',
  'name': 'Race $i',
  'status': 'ACTIVE',
  'endsAt': DateTime.now()
      .add(const Duration(hours: 3, minutes: 20))
      .toUtc()
      .toIso8601String(),
  'participantCount': 4,
  'myPlacement': 2,
  'placementPrivacyActive': false,
};

Future<void> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> races,
) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: await _auth(),
          racesData: {
            'active': races,
            'pending': const [],
            'completed': const [],
          },
          friendsSteps: const [],
          onRacesChanged: _noop,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The card surface is a `Material` whose color carries the card background.
Color _cardColor(WidgetTester tester, String raceId) {
  final material = tester.widget<Material>(
    find
        .descendant(
          of: find.byKey(Key('race-card-surface-$raceId')),
          matching: find.byType(Material),
        )
        .first,
  );
  return material.color!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every race card uses the same parchment background', (
    tester,
  ) async {
    await _pump(tester, [_activeRace(0), _activeRace(1), _activeRace(2)]);

    final context = tester.element(find.byType(RacesTab));
    final parchment = AppColors.of(context).parchment;

    final colors = [
      _cardColor(tester, 'race-0'),
      _cardColor(tester, 'race-1'),
      _cardColor(tester, 'race-2'),
    ];

    expect(colors, everyElement(parchment));
    // Explicitly pin the odd index: it used to render parchmentLight.
    expect(colors[1], parchment);
    expect(colors[1], isNot(AppColors.of(context).parchmentLight));
  });

  testWidgets('card background does not depend on list index', (tester) async {
    // Same race rendered at index 0 and at index 1 must look identical.
    await _pump(tester, [_activeRace(7)]);
    final soloColor = _cardColor(tester, 'race-7');

    await _pump(tester, [_activeRace(0), _activeRace(7)]);
    expect(_cardColor(tester, 'race-7'), soloColor);
  });
}
