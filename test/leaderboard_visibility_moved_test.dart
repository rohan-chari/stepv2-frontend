import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/leaderboard_tab.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/pixel_switch.dart';

// Item 1 of the 2026-07-27 batch. The leaderboard is steps-only now: the
// STEPS/RACES type toggle is gone, the global/friends SCOPE toggle stays, and
// the "hide me" privacy switch moves out of Settings onto the board itself.
//
// Pumped through the real tabs rather than the extracted widget, because the
// point of the item is *where* the control renders.

class _FakeApi extends BackendApiService {
  final List<({String type, String period, String scope})> leaderboardCalls =
      [];
  bool? lastHidden;
  int visibilityCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async {
    leaderboardCalls.add((type: type, period: period, scope: scope));
    return {
      'top100': [
        {
          'rank': 1,
          'userId': 'other-user',
          'displayName': 'AceWinner',
          'totalSteps': 12000,
        },
        {
          'rank': 2,
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': 11000,
        },
        {
          'rank': 3,
          'userId': 'third-user',
          'displayName': 'BronzeWalker',
          'totalSteps': 10000,
        },
        {
          'rank': 4,
          'userId': 'fourth-user',
          'displayName': 'FourthWalker',
          'totalSteps': 9000,
        },
      ],
      'currentUser': {
        'rank': 2,
        'displayName': 'Trail Walker',
        'totalSteps': 11000,
        'inTop100': true,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> updateLeaderboardVisibility({
    required String identityToken,
    required bool hidden,
  }) async {
    visibilityCalls += 1;
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
    'auth_step_goal': 8000,
    'auth_hidden_from_leaderboard': hidden,
  });
  final auth = AuthService(backendApiService: api);
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpLeaderboard(
  WidgetTester tester,
  AuthService auth,
  BackendApiService api,
) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeData.light(),
      home: Scaffold(
        body: LeaderboardTab(
          authService: auth,
          backendApiService: api,
          stepData: StepData(steps: 6543, date: DateTime(2026, 4, 7)),
          displayName: 'Trail Walker',
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the leaderboard renders no steps/races type toggle', (
    tester,
  ) async {
    final api = _FakeApi();
    final auth = await _createAuthService(api);
    await _pumpLeaderboard(tester, auth, api);

    expect(find.text('RACES'), findsNothing);
    expect(find.text('STEPS'), findsNothing);
    // Only the steps board is ever requested.
    expect(api.leaderboardCalls.map((c) => c.type).toSet(), {'steps'});
    // The steps period filter stays.
    expect(find.text('TODAY'), findsOneWidget);
  });

  testWidgets('the global/friends scope toggle still renders and works', (
    tester,
  ) async {
    final api = _FakeApi();
    final auth = await _createAuthService(api);
    await _pumpLeaderboard(tester, auth, api);

    expect(find.byIcon(Icons.public_rounded), findsOneWidget);
    expect(find.byIcon(Icons.group_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.group_rounded));
    await tester.pump();
    await tester.pump();

    expect(api.leaderboardCalls.last.scope, 'friends');
  });

  testWidgets('the visibility toggle renders below the standings', (
    tester,
  ) async {
    final api = _FakeApi();
    final auth = await _createAuthService(api, hidden: true);
    await _pumpLeaderboard(tester, auth, api);

    final label = find.text('Hide me from the global leaderboard');
    expect(label, findsOneWidget);

    final switchFinder = find.byType(PixelSwitch);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<PixelSwitch>(switchFinder).value, isTrue);

    // Below the standings: under the last ranked row.
    expect(
      tester.getTopLeft(label).dy,
      greaterThan(tester.getBottomLeft(find.text('@FourthWalker')).dy),
    );
  });

  testWidgets('flipping the toggle calls updateLeaderboardVisibility', (
    tester,
  ) async {
    final api = _FakeApi();
    final auth = await _createAuthService(api);
    await _pumpLeaderboard(tester, auth, api);

    final switchFinder = find.byType(PixelSwitch);
    expect(tester.widget<PixelSwitch>(switchFinder).value, isFalse);

    await tester.ensureVisible(switchFinder);
    await tester.pump();
    await tester.tap(switchFinder);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(api.visibilityCalls, 1);
    expect(api.lastHidden, isTrue);
    expect(auth.hiddenFromLeaderboard, isTrue);
    expect(tester.widget<PixelSwitch>(switchFinder).value, isTrue);
  });

  testWidgets('settings no longer carries the visibility toggle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeApi();
    final auth = await _createAuthService(api, hidden: true);

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
    await tester.tap(find.text('SETTINGS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Hide me from the global leaderboard'), findsNothing);
  });
}
