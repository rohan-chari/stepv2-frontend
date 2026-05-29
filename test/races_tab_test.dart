import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RacesTab shows a loading skeleton before race data loads', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RacesTab(
            authService: authService,
            racesState: const Loadable.loading(),
            friendsSteps: const [],
            onRacesChanged: _noop,
            displayName: 'Trail Walker',
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('races-loading-skeleton')), findsOneWidget);
    expect(find.text('No races yet'), findsNothing);
  });

  testWidgets('RacesTab shows a retry state when race data fails to load', (
    WidgetTester tester,
  ) async {
    final authService = await _createAuthService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RacesTab(
            authService: authService,
            racesState: const Loadable.error(
              'Couldn’t load races. Check your connection and try again.',
            ),
            friendsSteps: const [],
            onRacesChanged: _noop,
            displayName: 'Trail Walker',
          ),
        ),
      ),
    );

    expect(find.text('Couldn’t load races'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(find.text('No races yet'), findsNothing);
  });

  testWidgets(
    'RacesTab keeps placement and queued boxes aligned with the race title',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RacesTab(
              authService: authService,
              racesData: const {
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
                    'queuedBoxCount': 2,
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

      final headerRow = find.byKey(const Key('race-card-header-race-1'));

      expect(headerRow, findsOneWidget);
      expect(
        find.descendant(of: headerRow, matching: find.text('Morning Dash')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: headerRow, matching: find.text('1ST PLACE')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: headerRow, matching: find.text('2 QUEUED')),
        findsOneWidget,
      );
    },
  );
}

Future<void> _noop() async {}
