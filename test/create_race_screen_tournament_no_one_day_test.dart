import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Spec §3.5 — the tournament create picker drops the 1-day matchup option and
/// defaults to 2 days, so a single busy day can't decide a bracket. The server
/// clamps any stale 1 sent by a frozen client, so the app only needs to stop
/// offering it.
class _RecordingApi extends BackendApiService {
  Map<String, dynamic>? lastCreateTournamentCall;

  @override
  Future<Map<String, dynamic>> createTournament({
    required String identityToken,
    required String name,
    required int bracketSize,
    required int matchupDurationDays,
    int buyInAmount = 0,
    bool powerupsEnabled = false,
    int? powerupStepInterval,
    bool isPublic = false,
    List<String> inviteeIds = const [],
  }) async {
    lastCreateTournamentCall = {
      'name': name,
      'bracketSize': bracketSize,
      'matchupDurationDays': matchupDurationDays,
    };
    return {
      'tournament': {'id': 'tourney-1', 'name': name, 'status': 'PENDING'},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 5000, 'heldCoins': 0};
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 5000,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pump(
  WidgetTester tester,
  AuthService authService,
  _RecordingApi api,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CreateRaceScreen(
        authService: authService,
        backendApiService: api,
        initialCustomizeExpanded: true,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _switchToTournament(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('race-format-tournament')));
  await tester.tap(find.byKey(const Key('race-format-tournament')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('picker offers 2 and 3 day matchups but never 1', (tester) async {
    final auth = await _createAuthService();
    await _pump(tester, auth, _RecordingApi());
    await _switchToTournament(tester);

    expect(find.byKey(const Key('matchup-duration-1')), findsNothing);
    expect(find.byKey(const Key('matchup-duration-2')), findsOneWidget);
    expect(find.byKey(const Key('matchup-duration-3')), findsOneWidget);
  });

  testWidgets('submit defaults to a 2-day matchup without touching the picker', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final api = _RecordingApi();
    await _pump(tester, auth, api);
    await _switchToTournament(tester);

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Friday Gauntlet',
    );

    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pump();
    await tester.pump();

    expect(api.lastCreateTournamentCall, isNotNull);
    expect(api.lastCreateTournamentCall!['matchupDurationDays'], 2);
  });
}
