import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/start_screen.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _FakeBackendApiService extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    return const {'claimedToday': true};
  }
}

void main() {
  testWidgets('StartScreen describes Bara as a social step challenge app', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: StartScreen()));

    expect(find.text('Bara'), findsOneWidget);
    expect(
      find.text(
        'Step challenges are more fun when you can steal someone’s steps.',
      ),
      findsOneWidget,
    );
    expect(find.text('STEP. RACE. WIN.'), findsNothing);
    expect(
      find.text("We're on a mission to make your daily steps fun"),
      findsNothing,
    );
    expect(find.text('RACE\nFRIENDS'), findsOneWidget);
    expect(find.text('EARN\nPOWERUPS'), findsOneWidget);
    expect(find.text('CLIMB THE\nLEADERBOARD'), findsOneWidget);
    expect(find.byKey(const Key('start-hero-capybara')), findsOneWidget);
    expect(find.byKey(const Key('start-sign-in-dock')), findsOneWidget);
    expect(find.text('STEP RACES'), findsNothing);
    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.text('GET STARTED'), findsNothing);
  });

  testWidgets('HomeTab omits the retired challenge and leaderboard buttons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTab(
            stepData: StepData(steps: 2388, date: DateTime(2026, 3, 19)),
            isLoading: false,
            error: null,
            healthAuthorized: true,
            notificationsState: true,
            displayName: 'Trail Walker',
            authService: AuthService(),
            backendApiService: _FakeBackendApiService(),
            onRefresh: () async {},
            onEnableHealth: () {},
            onEnableNotifications: () {},
            onDisplayNameChanged: () {},
            friendsSteps: const [],
          ),
        ),
      ),
    );

    expect(find.text('CHALLENGES'), findsNothing);
    expect(find.text('LEADERBOARD'), findsNothing);
  });

  testWidgets('HomeTab omits the retired daily reward slots', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTab(
            stepData: StepData(steps: 2388, date: DateTime(2026, 3, 19)),
            isLoading: false,
            error: null,
            healthAuthorized: true,
            notificationsState: true,
            displayName: 'Trail Walker',
            authService: AuthService(),
            backendApiService: _FakeBackendApiService(),
            onRefresh: () async {},
            onEnableHealth: () {},
            onEnableNotifications: () {},
            onDisplayNameChanged: () {},
            friendsSteps: const [],
          ),
        ),
      ),
    );

    expect(find.text('1x GOAL'), findsNothing);
    expect(find.text('2x GOAL'), findsNothing);
  });

  testWidgets('HomeTab displays the current name and step HUD', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTab(
            stepData: StepData(steps: 2388, date: DateTime(2026, 3, 19)),
            isLoading: false,
            error: null,
            healthAuthorized: true,
            notificationsState: true,
            displayName: 'Trail Walker',
            authService: AuthService(),
            backendApiService: _FakeBackendApiService(),
            onRefresh: () async {},
            onEnableHealth: () {},
            onEnableNotifications: () {},
            onDisplayNameChanged: () {},
            friendsSteps: const [
              {'displayName': 'Summit Buddy', 'steps': 6200, 'stepGoal': 7000},
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('@Trail Walker'), findsOneWidget);
    expect(find.text('STEPS TODAY'), findsOneWidget);
  });
}
