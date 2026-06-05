import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/global_event_banner.dart';

// ---------------------------------------------------------------------------
// Global step-multiplier event banner on the HOME screen + the shared,
// self-ticking GlobalEventBanner widget.
//
// The /home/race-card response carries a top-level `globalEvent`
// ({ active: true, multiplier, endsAt }). When it is active the home column
// shows the on-brand "2x STEPS" banner with a countdown to endsAt. When the
// field is absent (older backend) or expired, no banner. Read defensively.
// ---------------------------------------------------------------------------

class _FakeBackendApiService extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    return const {'claimedToday': true};
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_profile_photo_url': 'https://example.com/p.png',
    'auth_profile_photo_prompt_dismissed_at': '2026-04-08T12:00:00.000Z',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Widget _buildHome(
  AuthService authService, {
  Map<String, dynamic>? raceCard,
}) {
  return MaterialApp(
    home: Scaffold(
      body: HomeTab(
        stepData: StepData(steps: 2400, date: DateTime(2026, 6, 5)),
        isLoading: false,
        error: null,
        healthAuthorized: true,
        notificationsState: true,
        displayName: 'Trail Walker',
        authService: authService,
        backendApiService: _FakeBackendApiService(),
        onRefresh: () async {},
        onEnableHealth: () {},
        onEnableNotifications: () {},
        onDisplayNameChanged: () {},
        friendsSteps: const [],
        raceCard: raceCard,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'home shows the 2x event banner when race-card includes an active globalEvent',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final authService = await _createAuthService();
      // endsAt far in the future so the countdown is positive and the banner
      // is unambiguously "active".
      final endsAt = DateTime.now().toUtc().add(const Duration(minutes: 20));

      await tester.pumpWidget(
        _buildHome(
          authService,
          raceCard: {
            'state': 'EMPTY',
            'globalEvent': {
              'active': true,
              'multiplier': 2,
              'endsAt': endsAt.toIso8601String(),
            },
          },
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('home-global-event-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('2x STEPS'), findsOneWidget);

      // Tear down the periodic countdown timer.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'home does NOT show the banner when the race-card omits globalEvent',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final authService = await _createAuthService();

      await tester.pumpWidget(
        _buildHome(authService, raceCard: const {'state': 'EMPTY'}),
      );
      await tester.pump();

      expect(find.byKey(const Key('home-global-event-banner')), findsNothing);
      expect(find.textContaining('2x STEPS'), findsNothing);
    },
  );

  testWidgets(
    'home does NOT show the banner when the globalEvent has already expired',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final authService = await _createAuthService();
      final endsAt = DateTime.now().toUtc().subtract(const Duration(minutes: 1));

      await tester.pumpWidget(
        _buildHome(
          authService,
          raceCard: {
            'state': 'EMPTY',
            'globalEvent': {
              'active': true,
              'multiplier': 2,
              'endsAt': endsAt.toIso8601String(),
            },
          },
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('home-global-event-banner')), findsNothing);
      expect(find.textContaining('2x STEPS'), findsNothing);
    },
  );

  testWidgets(
    'GlobalEventBanner renders the multiplier + countdown for an active window',
    (WidgetTester tester) async {
      final endsAt = DateTime.now().add(const Duration(minutes: 20));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlobalEventBanner(
              key: const Key('standalone-event-banner'),
              multiplier: 3,
              endsAt: endsAt,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('standalone-event-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('3x STEPS'), findsOneWidget);
      expect(find.textContaining('ends in'), findsOneWidget);

      // Tear down the periodic countdown timer.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'GlobalEventBanner collapses to nothing when endsAt is already past',
    (WidgetTester tester) async {
      final endsAt = DateTime.now().subtract(const Duration(minutes: 1));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlobalEventBanner(
              key: const Key('expired-event-banner'),
              multiplier: 2,
              endsAt: endsAt,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('2x STEPS'), findsNothing);
      expect(find.textContaining('ends in'), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
  );
}
