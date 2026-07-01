import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _LeaderboardApi extends BackendApiService {
  bool? lastHidden;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> updateLeaderboardVisibility({
    required String identityToken,
    required bool hidden,
  }) async {
    calls += 1;
    lastHidden = hidden;
    return {'hiddenFromLeaderboard': hidden};
  }

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

Future<AuthService> _createAuthService(
  BackendApiService api, {
  bool hidden = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_hidden_from_leaderboard': hidden,
  });
  final authService = AuthService(backendApiService: api);
  await authService.restoreSession();
  return authService;
}

Future<void> _openSettings(WidgetTester tester, AuthService auth, BackendApiService api) async {
  await tester.pumpWidget(
    MaterialApp(
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
  await tester.tap(find.text('SETTINGS'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('settings sheet renders a CupertinoSwitch reflecting auth state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _LeaderboardApi();
    final auth = await _createAuthService(api, hidden: true);
    await _openSettings(tester, auth, api);

    expect(find.text('Hide me from the global leaderboard'), findsOneWidget);
    final switchFinder = find.byType(CupertinoSwitch);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<CupertinoSwitch>(switchFinder).value, isTrue);
  });

  testWidgets('toggling the switch calls updateLeaderboardVisibility', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _LeaderboardApi();
    final auth = await _createAuthService(api, hidden: false);
    await _openSettings(tester, auth, api);

    final switchFinder = find.byType(CupertinoSwitch);
    expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(api.calls, 1);
    expect(api.lastHidden, isTrue);
    expect(auth.hiddenFromLeaderboard, isTrue);
    expect(tester.widget<CupertinoSwitch>(switchFinder).value, isTrue);
  });
}
