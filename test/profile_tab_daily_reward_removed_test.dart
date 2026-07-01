import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _ProfileBackendApiService extends BackendApiService {
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
  }) async => const {
    'thisWeek': 12000,
    'thisMonth': 45000,
    'thisYear': 150000,
    'allTime': 300000,
    'streak': 4,
  };

  @override
  Future<Map<String, dynamic>> fetchStepCalendar({
    required String identityToken,
    required String month,
  }) async => const {'days': []};

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => const {'claimedToday': true};
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });

  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'ProfileTab no longer renders a DAILY REWARD section',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileTab(
              authService: authService,
              displayName: 'Trail Walker',
              email: 'walker@example.com',
              onSettingsChanged: () {},
              backendApiService: _ProfileBackendApiService(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The DAILY REWARD section header and its button content are gone.
      expect(find.text('DAILY REWARD'), findsNothing);
      expect(find.text('Daily reward'), findsNothing);
      expect(find.text('CLAIM'), findsNothing);

      // Neighboring sections remain intact.
      expect(find.text('INVITE FRIENDS'), findsOneWidget);
      expect(find.text('STEP CALENDAR'), findsOneWidget);
      expect(find.text('STATS'), findsOneWidget);
    },
  );
}
