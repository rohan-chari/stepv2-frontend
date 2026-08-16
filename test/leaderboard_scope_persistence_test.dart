import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/tabs/leaderboard_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Batch 2026-08-15 item 5: the Friends/Global leaderboard scope is persisted
/// in SharedPreferences so it survives tab-switch disposal, app restarts and
/// sign-out/sign-in — and the stored value is read BEFORE the first fetch, so
/// opening the tab issues exactly one `fetchLeaderboard` call.
class _FakeBackendApiService extends BackendApiService {
  final List<({String type, String period, String scope})> leaderboardCalls =
      [];

  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async {
    leaderboardCalls.add((type: type, period: period, scope: scope));

    // Both scopes return populated rows so a wrong-scope render would still
    // paint a board — the assertions key off the scope header, not emptiness.
    return {
      'top100': [
        {
          'rank': 1,
          'userId': 'other-user',
          'displayName': scope == 'friends' ? 'FriendOne' : 'AceWinner',
          'totalSteps': 12000,
        },
        {
          'rank': 2,
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': 11000,
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
}

const _authPrefs = <String, Object>{
  'auth_identity_token': 'apple-token',
  'auth_user_identifier': 'apple-user-123',
  'auth_session_token': 'session-token',
  'auth_backend_user_id': 'user-1',
  'auth_display_name': 'Trail Walker',
  'auth_step_goal': 8000,
};

Future<AuthService> _createAuthService({
  Map<String, Object> extraPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({..._authPrefs, ...extraPrefs});
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Widget _buildLeaderboard({
  required AuthService authService,
  required BackendApiService backendApiService,
}) {
  return MaterialApp(
    home: Scaffold(
      body: LeaderboardTab(
        authService: authService,
        backendApiService: backendApiService,
        stepData: StepData(steps: 6543, date: DateTime(2026, 4, 7)),
        displayName: 'Trail Walker',
      ),
    ),
  );
}

/// Pumps enough frames for the async preference read + fetch to settle without
/// waiting on the tab's continuous arcade animations (pumpAndSettle would time
/// out on those).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<String?> _storedScope() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(LeaderboardTab.scopePreferenceKey);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'scope survives tab-switch disposal and the reopened tab fetches once',
    (WidgetTester tester) async {
      final authService = await _createAuthService();
      final backendApiService = _FakeBackendApiService();

      await tester.pumpWidget(
        _buildLeaderboard(
          authService: authService,
          backendApiService: backendApiService,
        ),
      );
      await _settle(tester);

      expect(backendApiService.leaderboardCalls, [
        (type: 'steps', period: 'today', scope: 'global'),
      ]);
      expect(find.text('Global Leaderboard'), findsOneWidget);

      // Switch to Friends.
      await tester.tap(find.byIcon(Icons.group_rounded));
      await _settle(tester);
      expect(find.text('Friends Leaderboard'), findsOneWidget);
      expect(backendApiService.leaderboardCalls.last, (
        type: 'steps',
        period: 'today',
        scope: 'friends',
      ));
      expect(await _storedScope(), 'friends');

      // Navigate away: the real PageView disposes the LeaderboardTab state.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await _settle(tester);
      expect(find.text('Friends Leaderboard'), findsNothing);

      // Navigate back: a brand new State object.
      backendApiService.leaderboardCalls.clear();
      await tester.pumpWidget(
        _buildLeaderboard(
          authService: authService,
          backendApiService: backendApiService,
        ),
      );
      await _settle(tester);

      expect(find.text('Friends Leaderboard'), findsOneWidget);
      expect(find.text('Global Leaderboard'), findsNothing);
      // Exactly one fetch, on the friends scope: the preference must be read
      // BEFORE the first fetch, never as a second fetch afterwards.
      expect(backendApiService.leaderboardCalls, [
        (type: 'steps', period: 'today', scope: 'friends'),
      ]);
    },
  );

  testWidgets(
    'fresh app start with a stored friends preference opens on Friends with one fetch',
    (WidgetTester tester) async {
      final authService = await _createAuthService(
        extraPrefs: {LeaderboardTab.scopePreferenceKey: 'friends'},
      );
      final backendApiService = _FakeBackendApiService();

      await tester.pumpWidget(
        _buildLeaderboard(
          authService: authService,
          backendApiService: backendApiService,
        ),
      );
      await _settle(tester);

      expect(find.text('Friends Leaderboard'), findsOneWidget);
      expect(backendApiService.leaderboardCalls, [
        (type: 'steps', period: 'today', scope: 'friends'),
      ]);
    },
  );

  testWidgets(
    'an unset or unrecognised stored value falls back to Global with one fetch',
    (WidgetTester tester) async {
      final authService = await _createAuthService(
        extraPrefs: {LeaderboardTab.scopePreferenceKey: 'not-a-scope'},
      );
      final backendApiService = _FakeBackendApiService();

      await tester.pumpWidget(
        _buildLeaderboard(
          authService: authService,
          backendApiService: backendApiService,
        ),
      );
      await _settle(tester);

      expect(find.text('Global Leaderboard'), findsOneWidget);
      expect(backendApiService.leaderboardCalls, [
        (type: 'steps', period: 'today', scope: 'global'),
      ]);
    },
  );

  testWidgets('the scope preference survives sign-out and sign-in', (
    WidgetTester tester,
  ) async {
    var authService = await _createAuthService(
      extraPrefs: {LeaderboardTab.scopePreferenceKey: 'friends'},
    );

    // signOut() removes an explicit list of keys; the scope preference is
    // deliberately not on it (low-stakes UI preference, not account state).
    await authService.signOut();
    final survivingScope = await _storedScope();
    expect(survivingScope, 'friends');

    // Sign back in: the auth keys signOut() removed are restored by the next
    // sign-in, while the untouched scope preference carries straight over.
    SharedPreferences.setMockInitialValues({
      ..._authPrefs,
      LeaderboardTab.scopePreferenceKey: survivingScope!,
    });
    final signedInAgain = AuthService();
    await signedInAgain.restoreSession();
    authService = signedInAgain;

    final backendApiService = _FakeBackendApiService();
    await tester.pumpWidget(
      _buildLeaderboard(
        authService: authService,
        backendApiService: backendApiService,
      ),
    );
    await _settle(tester);

    expect(find.text('Friends Leaderboard'), findsOneWidget);
    expect(backendApiService.leaderboardCalls, [
      (type: 'steps', period: 'today', scope: 'friends'),
    ]);
  });
}
