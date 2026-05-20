import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/daily_reward_button.dart';
import 'package:step_tracker/widgets/daily_reward_trigger.dart';
import 'package:step_tracker/widgets/loading_skeleton.dart';

class _FailingDailyRewardApi extends BackendApiService {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    calls += 1;
    throw const ApiException('Connection timed out.');
  }
}

class _UnusedDailyRewardApi extends BackendApiService {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    calls += 1;
    return const {'claimedToday': true};
  }
}

Future<AuthService> _authService({bool signedIn = true}) async {
  SharedPreferences.setMockInitialValues(
    signedIn
        ? {
            'auth_identity_token': 'apple-token',
            'auth_user_identifier': 'apple-user-123',
            'auth_session_token': 'session-token',
            'auth_backend_user_id': 'user-1',
            'auth_display_name': 'Trail Walker',
          }
        : {},
  );
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DailyRewardTrigger stops loading when status check fails', (
    WidgetTester tester,
  ) async {
    final api = _FailingDailyRewardApi();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyRewardTrigger(
            authService: await _authService(),
            backendApiService: api,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(api.calls, 1);
    expect(find.byType(LoadingSkeleton), findsNothing);
    expect(find.byType(DailyRewardButton), findsOneWidget);
    expect(find.text('Today is already claimed'), findsOneWidget);
  });

  testWidgets('DailyRewardTrigger stops loading without an auth token', (
    WidgetTester tester,
  ) async {
    final api = _UnusedDailyRewardApi();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyRewardTrigger(
            authService: await _authService(signedIn: false),
            backendApiService: api,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(api.calls, 0);
    expect(find.byType(LoadingSkeleton), findsNothing);
    expect(find.byType(DailyRewardButton), findsOneWidget);
    expect(find.text('Today is already claimed'), findsOneWidget);
  });
}
