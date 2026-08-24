import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
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
}) {
  return MaterialApp(
    home: Scaffold(
      body: HomeTab(
        stepData: StepData(steps: 2388, date: DateTime(2026, 3, 19)),
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
      ),
    ),
  );
}

void main() {
  testWidgets('HomeTab keeps leaderboard highlights off the Home route', (
    tester,
  ) async {
    final authService = await _createAuthService();
    await tester.pumpWidget(_buildHome(authService: authService));
    expect(find.text('CLIMBING THE BOARDS'), findsNothing);
    expect(find.byKey(const Key('climbing-boards-page-view')), findsNothing);
  });
}
