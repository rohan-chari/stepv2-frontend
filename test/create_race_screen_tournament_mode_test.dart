import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// Spec §9/§10: the create flow gains a third "BRACKET" signpost segment. In
// tournament mode the bracket-size (4/8/16) + matchup-length (1/2/3) pickers
// appear, the FFA/team-only controls (payout / max runners / scheduled start /
// team plaques) are hidden, and submit calls createTournament with the picked
// shape. The buy-in max re-clamps when the bracket size changes (D4).

class _RecordingApi extends BackendApiService {
  Map<String, dynamic>? lastCreateTournamentCall;
  bool createRaceCalled = false;

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
      'buyInAmount': buyInAmount,
      'powerupsEnabled': powerupsEnabled,
      'powerupStepInterval': powerupStepInterval,
      'isPublic': isPublic,
    };
    return {
      'tournament': {'id': 'tourney-1', 'name': name, 'status': 'PENDING'},
    };
  }

  @override
  Future<Map<String, dynamic>> createRace({
    required String identityToken,
    required String name,
    int maxDurationDays = 7,
    bool powerupsEnabled = false,
    int? powerupStepInterval,
    int buyInAmount = 0,
    String payoutPreset = 'WINNER_TAKES_ALL',
    bool isPublic = false,
    int? maxParticipants = 10,
    DateTime? scheduledStartAt,
  }) async {
    createRaceCalled = true;
    return {
      'race': {'id': 'race-1', 'name': name},
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
    'auth_team_races_enabled': true,
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

  testWidgets('third BRACKET segment exists and reveals the pickers', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await _pump(tester, auth, _RecordingApi());

    expect(find.byKey(const Key('race-format-tournament')), findsOneWidget);
    expect(find.byKey(const Key('tournament-reveal')), findsNothing);

    await _switchToTournament(tester);

    expect(find.byKey(const Key('tournament-reveal')), findsOneWidget);
    expect(find.byKey(const Key('bracket-size-4')), findsOneWidget);
    expect(find.byKey(const Key('bracket-size-8')), findsOneWidget);
    expect(find.byKey(const Key('bracket-size-16')), findsOneWidget);
    expect(find.byKey(const Key('matchup-duration-1')), findsOneWidget);
    expect(find.byKey(const Key('matchup-duration-2')), findsOneWidget);
    expect(find.byKey(const Key('matchup-duration-3')), findsOneWidget);
  });

  testWidgets('FFA/team-only controls are hidden in tournament mode', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await _pump(tester, auth, _RecordingApi());
    await _switchToTournament(tester);

    // Payout mode picker, scheduled start, max-runners presets, team plaques
    // are all hidden; the fixed matchup pickers replace the [3,5,7,14] chips.
    expect(find.text('PAYOUT MODE'), findsNothing);
    expect(find.text('SCHEDULED START'), findsNothing);
    expect(find.text('MAX RUNNERS'), findsNothing);
    expect(find.byKey(const Key('team-plaque-a')), findsNothing);
    // The old duration chips card is gone.
    expect(find.text('DURATION'), findsNothing);
  });

  testWidgets('buy-in hint reflects the D4 ladder max and re-clamps on '
      'bracket-size change', (tester) async {
    final auth = await _createAuthService();
    await _pump(tester, auth, _RecordingApi());
    await _switchToTournament(tester);

    // Default 8-bracket → max 100, pot up to 800.
    expect(find.textContaining('Buy-in max 100'), findsOneWidget);

    // Switch to 16 → max 62, pot up to 992.
    await tester.tap(find.byKey(const Key('bracket-size-16')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Buy-in max 62'), findsOneWidget);
  });

  testWidgets('submit calls createTournament with the picked shape', (
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
    // Pick 16-bracket, 3-day matchups.
    await tester.tap(find.byKey(const Key('bracket-size-16')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('matchup-duration-3')));
    await tester.pumpAndSettle();

    // Submit.
    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pump();
    await tester.pump();

    expect(api.createRaceCalled, isFalse);
    expect(api.lastCreateTournamentCall, isNotNull);
    expect(api.lastCreateTournamentCall!['name'], 'Friday Gauntlet');
    expect(api.lastCreateTournamentCall!['bracketSize'], 16);
    expect(api.lastCreateTournamentCall!['matchupDurationDays'], 3);
    expect(api.lastCreateTournamentCall!['buyInAmount'], 0);
    // Powerups default ON for tournaments (Rohan's default) — flows through to
    // the create call without the user touching the toggle.
    expect(api.lastCreateTournamentCall!['powerupsEnabled'], isTrue);
  });
}
