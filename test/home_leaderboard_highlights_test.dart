import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_profile_photo_prompt_dismissed_at': '2026-04-08T12:00:00.000Z',
  });

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Widget _buildHome({
  required AuthService authService,
  List<Map<String, dynamic>> leaderboardHighlights = const [],
  bool leaderboardHighlightsLoading = false,
  void Function(String leaderboardType, String period)?
  onOpenLeaderboardHighlight,
}) {
  return MaterialApp(
    home: Scaffold(
      body: HomeTab(
        stepData: StepData(steps: 2388, date: DateTime(2026, 3, 19)),
        isLoading: false,
        error: null,
        stepGoal: 5000,
        healthAuthorized: true,
        notificationsState: true,
        displayName: 'Trail Walker',
        authService: authService,
        onRefresh: () async {},
        onEnableHealth: () {},
        onEnableNotifications: () {},
        onSetStepGoal: () {},
        onDisplayNameChanged: () {},
        currentChallenge: null,
        friendsSteps: const [],
        onChallengeChanged: () {},
        leaderboardHighlights: leaderboardHighlights,
        leaderboardHighlightsLoading: leaderboardHighlightsLoading,
        onOpenLeaderboardHighlight: onOpenLeaderboardHighlight,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'HomeTab shows climbing the boards and opens the matching leaderboard highlight',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      String? tappedType;
      String? tappedPeriod;
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildHome(
          authService: authService,
          leaderboardHighlights: const [
            {
              'title': "You're 5th all time in steps. Keep climbing.",
              'subtitle': 'Only 501 steps from 4th.',
              'leaderboardType': 'steps',
              'period': 'allTime',
            },
          ],
          onOpenLeaderboardHighlight: (leaderboardType, period) {
            tappedType = leaderboardType;
            tappedPeriod = period;
          },
        ),
      );

      expect(find.text('CLIMBING THE BOARDS'), findsOneWidget);
      expect(
        find.text("You're 5th all time in steps. Keep climbing."),
        findsOneWidget,
      );
      expect(find.text('Only 501 steps from 4th.'), findsOneWidget);

      await tester.ensureVisible(
        find.text("You're 5th all time in steps. Keep climbing."),
      );
      await tester.tap(
        find.text("You're 5th all time in steps. Keep climbing."),
      );
      await tester.pump();

      expect(tappedType, 'steps');
      expect(tappedPeriod, 'allTime');
    },
  );

  testWidgets(
    'HomeTab hides climbing the boards when no highlight cards are available',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(_buildHome(authService: authService));

      expect(find.text('CLIMBING THE BOARDS'), findsNothing);
    },
  );

  testWidgets(
    'HomeTab shows a lightweight skeleton while leaderboard highlights load',
    (WidgetTester tester) async {
      final authService = await _createAuthService();

      await tester.pumpWidget(
        _buildHome(
          authService: authService,
          leaderboardHighlightsLoading: true,
        ),
      );

      expect(find.byKey(const Key('climbing-boards-skeleton')), findsOneWidget);
    },
  );

  testWidgets(
    'HomeTab auto-advances and supports swipe on the climbing the boards carousel',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildHome(
          authService: authService,
          leaderboardHighlights: const [
            {
              'title': "You're 5th all time in steps. Keep climbing.",
              'subtitle': 'Only 501 steps from 4th.',
              'leaderboardType': 'steps',
              'period': 'allTime',
            },
            {
              'title': "You're 8th all time in challenges. Keep climbing.",
              'subtitle': '5 more wins could move you up.',
              'leaderboardType': 'challenges',
              'period': 'allTime',
            },
          ],
        ),
      );

      expect(
        find.text("You're 5th all time in steps. Keep climbing."),
        findsOneWidget,
      );
      expect(
        find.text("You're 8th all time in challenges. Keep climbing."),
        findsNothing,
      );

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text("You're 8th all time in challenges. Keep climbing."),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('climbing-boards-page-view')),
      );
      await tester.drag(
        find.byKey(const Key('climbing-boards-page-view')),
        const Offset(300, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text("You're 5th all time in steps. Keep climbing."),
        findsOneWidget,
      );
    },
  );
}
