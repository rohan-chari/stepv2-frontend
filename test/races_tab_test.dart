import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/widgets/spinning_crate.dart';

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
    'RacesTab renders the queue slot as a plain filled crate (not the dimmed '
    'clock-badge variant) with a 3px gap matching the other slots',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final boxKey = GlobalKey();

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
              tutorialBoxKey: boxKey,
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

      // The inventory row lives inside the tutorial-anchored SizedBox.
      final inventoryRow = tester.widget<Row>(
        find.descendant(of: find.byKey(boxKey), matching: find.byType(Row)),
      );
      final children = inventoryRow.children;

      // The queue slot is the last child: a plain filled crate, NOT the
      // dimmed/clock-badge queued variant.
      final queueSlot = children.last;
      expect(queueSlot, isA<CrateIcon>());
      expect((queueSlot as CrateIcon).filled, isTrue);
      expect(queueSlot.queued, isFalse);

      // No crate anywhere in the row uses the queued (dimmed + clock) variant.
      for (final child in children) {
        if (child is CrateIcon) {
          expect(child.queued, isFalse);
        }
      }

      // The gap immediately before the queue slot is 3px, matching the
      // inter-slot gaps (no wider 8px separator anymore).
      final gap = children[children.length - 2];
      expect(gap, isA<SizedBox>());
      expect((gap as SizedBox).width, 3);
    },
  );
}

Future<void> _noop() async {}
