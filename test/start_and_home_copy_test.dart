import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/start_screen.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

void main() {
  testWidgets('StartScreen describes Bara as a social step challenge app', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: StartScreen()));

    expect(find.text('Bara'), findsOneWidget);
    expect(
      find.text(
        'Track your steps, challenge friends, and put a stake on the week.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'HomeTab shows a how-it-works guide when social activity is empty',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTab(
              stepData: StepData(steps: 2388, date: DateTime(2026, 3, 19)),
              isLoading: false,
              error: null,
              stepGoal: 5000,
              healthAuthorized: true,
              notificationsState: true,
              displayName: 'Trail Walker',
              authService: AuthService(),
              onRefresh: () async {},
              onEnableHealth: () {},
              onEnableNotifications: () {},
              onSetStepGoal: () {},
              onDisplayNameChanged: () {},
              currentChallenge: null,
              friendsSteps: const [],
              onChallengeChanged: () {},
            ),
          ),
        ),
      );

      expect(find.text('GET STARTED'), findsOneWidget);
      expect(find.text('ADD FRIENDS'), findsOneWidget);
    },
  );

  testWidgets(
    'HomeTab points users to Challenges when the weekly competition has no matchups yet',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTab(
              stepData: StepData(steps: 2388, date: DateTime(2026, 3, 19)),
              isLoading: false,
              error: null,
              stepGoal: 5000,
              healthAuthorized: true,
              notificationsState: true,
              displayName: 'Trail Walker',
              authService: AuthService(),
              onRefresh: () async {},
              onEnableHealth: () {},
              onEnableNotifications: () {},
              onSetStepGoal: () {},
              onDisplayNameChanged: () {},
              currentChallenge: {
                'challenge': {
                  'title': 'Summit Sprint',
                  'description': 'Outwalk your friend this week.',
                },
                'instances': const [],
              },
              friendsSteps: const [],
              onChallengeChanged: () {},
            ),
          ),
        ),
      );

      expect(find.text('COMPETITIONS'), findsOneWidget);
      expect(
        find.text(
          'No active competitions yet. Head to the Challenges tab to start one.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'HomeTab hides the how-it-works guide once social sections are populated',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTab(
              stepData: StepData(steps: 2388, date: DateTime(2026, 3, 19)),
              isLoading: false,
              error: null,
              stepGoal: 5000,
              healthAuthorized: true,
              notificationsState: true,
              displayName: 'Trail Walker',
              authService: AuthService(),
              onRefresh: () async {},
              onEnableHealth: () {},
              onEnableNotifications: () {},
              onSetStepGoal: () {},
              onDisplayNameChanged: () {},
              currentChallenge: {
                'challenge': {
                  'title': 'Summit Sprint',
                  'description': 'Outwalk your friend this week.',
                },
                'instances': [
                  {
                    'status': 'ACTIVE',
                    'stakeStatus': 'AGREED',
                    'userA': {'id': 'friend-1', 'displayName': 'Summit Buddy'},
                    'userB': {'id': 'user-1', 'displayName': 'Trail Walker'},
                  },
                ],
              },
              friendsSteps: const [
                {
                  'displayName': 'Summit Buddy',
                  'steps': 6200,
                  'stepGoal': 7000,
                },
              ],
              onChallengeChanged: () {},
            ),
          ),
        ),
      );

      expect(find.text('GET STARTED'), findsNothing);
    },
  );
}
