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
        'Track your steps, challenge friends,\nand put a stake on the week.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.text('GET STARTED'), findsNothing);
  });

  testWidgets('HomeTab shows action buttons for challenge and leaderboard', (
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

    expect(find.text('CHALLENGES'), findsOneWidget);
    expect(find.text('LEADERBOARD'), findsOneWidget);
  });

  testWidgets('HomeTab shows daily reward slots', (WidgetTester tester) async {
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

    expect(find.text('1x GOAL'), findsOneWidget);
    expect(find.text('2x GOAL'), findsOneWidget);
  });

  testWidgets('HomeTab displays username and step count in status bar', (
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

    expect(find.text('@Trail Walker'), findsOneWidget);
    expect(find.text('2,388'), findsOneWidget);
    expect(find.text('out of 5k'), findsOneWidget);
  });
}
