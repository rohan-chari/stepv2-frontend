import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

// Item 13 of the 2026-07-27 batch: the profile stats row reads "Streak", not
// "Goal Streak". Asserted through the real tab, on what renders.

class _StatsApi extends BackendApiService {
  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {
        'displayName': 'Trail Walker',
        'isAdmin': false,
        'coins': 70,
        'heldCoins': 0,
      };

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the profile stat row is labelled Streak', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'apple-token',
      'auth_user_identifier': 'apple-user-123',
      'auth_session_token': 'session-token',
      'auth_backend_user_id': 'user-1',
      'auth_display_name': 'Trail Walker',
    });
    final api = _StatsApi();
    final auth = AuthService(backendApiService: api);
    await auth.restoreSession();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: Scaffold(
          body: ProfileTab(
            authService: auth,
            displayName: 'Trail Walker',
            email: 'walker@example.com',
            onSettingsChanged: () {},
            backendApiService: api,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Streak'), findsOneWidget);
    expect(find.text('Goal Streak'), findsNothing);
    expect(find.text('4 days'), findsOneWidget);
  });
}
