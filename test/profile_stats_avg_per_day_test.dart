import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _StatsBackendApiService extends BackendApiService {
  _StatsBackendApiService(this.stats);

  final Map<String, dynamic> stats;

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async {
    return {
      'sessionToken': authToken,
      'user': {
        'displayName': 'Trail Walker',
        'stepGoal': 8000,
        'isAdmin': false,
        'coins': 70,
        'heldCoins': 0,
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {
      'stepGoal': 8000,
      'incomingFriendRequests': 0,
      'displayName': 'Trail Walker',
      'email': 'walker@example.com',
      'isAdmin': false,
      'coins': 70,
      'heldCoins': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async => const {'races': []};

  @override
  Future<Map<String, dynamic>> fetchStats({
    required String identityToken,
  }) async => stats;

  @override
  Future<Map<String, dynamic>> fetchStepCalendar({
    required String identityToken,
    required String month,
  }) async => const {'days': []};
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_step_goal': 8000,
    'auth_profile_photo_url': 'https://example.com/profile.jpg',
  });

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pumpProfileTab(
  WidgetTester tester,
  Map<String, dynamic> stats,
) async {
  final authService = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProfileTab(
          authService: authService,
          displayName: 'Trail Walker',
          email: 'walker@example.com',
          onSettingsChanged: () {},
          backendApiService: _StatsBackendApiService(stats),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Stats rows show per-day averages with new relabeled headings',
    (WidgetTester tester) async {
      await _pumpProfileTab(tester, {
        'thisWeek': 81666,
        'thisMonth': 350000,
        'thisYear': 4259090,
        'avgPerDayWeek': 11666,
        'avgPerDayMonth': 11290,
        'avgPerDayYear': 11668,
        'allTime': 300000,
        'streak': 4,
      });

      // New relabeled headings.
      expect(find.text('Steps/Day This Week'), findsOneWidget);
      expect(find.text('Steps/Day This Month'), findsOneWidget);
      expect(find.text('Steps/Day This Year'), findsOneWidget);

      // Old headings are gone.
      expect(find.text('This Week'), findsNothing);
      expect(find.text('This Month'), findsNothing);
      expect(find.text('This Year'), findsNothing);

      // Averages render as plain integers with thousands separators,
      // not abbreviated (e.g. not '11.7k').
      expect(find.text('11,666'), findsOneWidget);
      expect(find.text('11,290'), findsOneWidget);
      expect(find.text('11,668'), findsOneWidget);

      // Unchanged rows remain.
      expect(find.text('All Time'), findsOneWidget);
      expect(find.text('Goal Streak'), findsOneWidget);
      expect(find.text('4 days'), findsOneWidget);
    },
  );

  testWidgets(
    'Old backend without avg fields falls back to showing the total',
    (WidgetTester tester) async {
      await _pumpProfileTab(tester, {
        'thisWeek': 12000,
        'thisMonth': 45000,
        'thisYear': 150000,
        'allTime': 300000,
        'streak': 4,
      });

      // Relabeled headings still appear even on an old backend.
      expect(find.text('Steps/Day This Week'), findsOneWidget);
      expect(find.text('Steps/Day This Month'), findsOneWidget);
      expect(find.text('Steps/Day This Year'), findsOneWidget);

      // Falls back to the plain-formatted total (no blank, no crash).
      expect(find.text('12,000'), findsOneWidget);
      expect(find.text('45,000'), findsOneWidget);
      expect(find.text('150,000'), findsOneWidget);
    },
  );
}
