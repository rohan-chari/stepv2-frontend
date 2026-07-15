import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// TR-801: create flow gains a wooden-signpost segmented control
// ("Free-for-all / Teams"); picking Teams reveals the 1v1..5v5 stepper and the
// two team-name plaques with dice-reroll + tap-to-edit. TR-107: the whole
// control hides when the remote kill switch is off.

class _RecordingApi extends BackendApiService {
  _RecordingApi({this.suggestions});

  /// Successive pairs handed back by the suggest endpoint; null = the route
  /// is unavailable (older backend / offline), exercising the local fallback.
  final List<(String, String)>? suggestions;
  int suggestCalls = 0;

  Map<String, dynamic>? lastCreateRaceCall;
  Map<String, dynamic>? lastCreateTeamRaceCall;

  @override
  Future<(String, String)?> fetchTeamNameSuggestion({
    required String identityToken,
  }) async {
    suggestCalls += 1;
    final pool = suggestions;
    if (pool == null || pool.isEmpty) return null;
    return pool[(suggestCalls - 1) % pool.length];
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
    lastCreateRaceCall = {'name': name, 'maxParticipants': maxParticipants};
    return {
      'race': {'id': 'race-1', 'name': name},
    };
  }

  @override
  Future<Map<String, dynamic>> createTeamRace({
    required String identityToken,
    required String name,
    required int teamSize,
    int maxDurationDays = 7,
    bool powerupsEnabled = false,
    int? powerupStepInterval,
    int buyInAmount = 0,
    bool isPublic = false,
    DateTime? scheduledStartAt,
    String? teamAName,
    String? teamBName,
    String? creatorTeam,
  }) async {
    lastCreateTeamRaceCall = {
      'name': name,
      'teamSize': teamSize,
      'teamAName': teamAName,
      'teamBName': teamBName,
      'creatorTeam': creatorTeam,
      'maxDurationDays': maxDurationDays,
      'buyInAmount': buyInAmount,
    };
    return {
      'race': {'id': 'race-t1', 'name': name, 'isTeamRace': true},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 500, 'heldCoins': 0};
  }
}

Future<AuthService> _createAuthService({bool teamRacesEnabled = true}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 500,
    'auth_held_coins': 0,
    'auth_team_races_enabled': teamRacesEnabled,
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
      ),
    ),
  );
  await tester.pump();
}

Future<void> _switchToTeams(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('race-format-teams')));
  await tester.tap(find.byKey(const Key('race-format-teams')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-801: signpost shows both formats, defaults to free-for-all',
      (tester) async {
    final authService = await _createAuthService();
    await _pump(tester, authService, _RecordingApi());

    expect(find.byKey(const Key('race-format-ffa')), findsOneWidget);
    expect(find.byKey(const Key('race-format-teams')), findsOneWidget);
    // Team controls are hidden until Teams is picked.
    expect(find.byKey(const Key('team-size-stepper')), findsNothing);
    expect(find.byKey(const Key('team-plaque-a')), findsNothing);
  });

  testWidgets('TR-107: kill switch off hides the Teams signpost entirely',
      (tester) async {
    final authService = await _createAuthService(teamRacesEnabled: false);
    await _pump(tester, authService, _RecordingApi());

    expect(find.byKey(const Key('race-format-teams')), findsNothing);
    expect(find.byKey(const Key('race-format-ffa')), findsNothing);
  });

  testWidgets(
      'TR-801: picking Teams reveals the stepper and two distinct name plaques',
      (tester) async {
    final authService = await _createAuthService();
    await _pump(tester, authService, _RecordingApi());
    await _switchToTeams(tester);

    expect(find.byKey(const Key('team-size-stepper')), findsOneWidget);
    expect(find.text('2v2'), findsOneWidget); // default size
    expect(find.byKey(const Key('team-plaque-a')), findsOneWidget);
    expect(find.byKey(const Key('team-plaque-b')), findsOneWidget);
    expect(find.byKey(const Key('team-name-reroll')), findsOneWidget);

    final nameA = tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(const Key('team-plaque-a')),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    final nameB = tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(const Key('team-plaque-b')),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    expect(nameA, isNotEmpty);
    expect(nameB, isNotEmpty);
    expect(nameA.toLowerCase(), isNot(equals(nameB.toLowerCase())));
  });

  testWidgets('TR-101: stepper clamps team size to 1..5', (tester) async {
    final authService = await _createAuthService();
    await _pump(tester, authService, _RecordingApi());
    await _switchToTeams(tester);

    final plus = find.byKey(const Key('team-size-plus'));
    final minus = find.byKey(const Key('team-size-minus'));

    // 2 -> 5, then clamp.
    for (var i = 0; i < 5; i++) {
      await tester.tap(plus);
      await tester.pump();
    }
    expect(find.text('5v5'), findsOneWidget);

    for (var i = 0; i < 7; i++) {
      await tester.tap(minus);
      await tester.pump();
    }
    expect(find.text('1v1'), findsOneWidget);
  });

  testWidgets('TR-801: dice reroll swaps in a fresh distinct pair',
      (tester) async {
    final authService = await _createAuthService();
    await _pump(tester, authService, _RecordingApi());
    await _switchToTeams(tester);

    String nameOf(String plaqueKey) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(Key(plaqueKey)),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;

    final before = (nameOf('team-plaque-a'), nameOf('team-plaque-b'));
    await tester.tap(find.byKey(const Key('team-name-reroll')));
    await tester.pump();
    final after = (nameOf('team-plaque-a'), nameOf('team-plaque-b'));

    expect(after.$1.toLowerCase(), isNot(equals(after.$2.toLowerCase())));
    expect(after, isNot(equals(before)));
  });

  testWidgets(
      'TR-101/104: creating a 2v2 calls createTeamRace with size, names, and '
      'the picked side', (tester) async {
    final authService = await _createAuthService();
    final api = _RecordingApi();
    await _pump(tester, authService, api);
    await _switchToTeams(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('team-plaque-a')),
        matching: find.byType(TextField),
      ),
      'Mossy Rockets',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('team-plaque-b')),
        matching: find.byType(TextField),
      ),
      'Puddle Jumpers',
    );

    // Creator picks Team B (default is Team A, TR-104).
    await tester.ensureVisible(find.byKey(const Key('team-side-b')));
    await tester.tap(find.byKey(const Key('team-side-b')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Capy Cup',
    );

    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pump();

    expect(api.lastCreateRaceCall, isNull);
    expect(api.lastCreateTeamRaceCall, isNotNull);
    expect(api.lastCreateTeamRaceCall!['name'], 'Capy Cup');
    expect(api.lastCreateTeamRaceCall!['teamSize'], 2);
    expect(api.lastCreateTeamRaceCall!['teamAName'], 'Mossy Rockets');
    expect(api.lastCreateTeamRaceCall!['teamBName'], 'Puddle Jumpers');
    expect(api.lastCreateTeamRaceCall!['creatorTeam'], 'TEAM_B');
  });

  testWidgets('TR-102: Teams mode hides payout-preset picker and max runners',
      (tester) async {
    final authService = await _createAuthService();
    await _pump(tester, authService, _RecordingApi());

    // Free-for-all shows MAX RUNNERS.
    expect(find.text('MAX RUNNERS'), findsOneWidget);

    await _switchToTeams(tester);
    expect(find.text('MAX RUNNERS'), findsNothing);

    // Buy-in stays available in Teams mode, but the payout-preset picker
    // (ignored for team races) is gone.
    await tester.ensureVisible(find.text('BUY-IN'));
    await tester.tap(find.text('BUY-IN'));
    await tester.pumpAndSettle();
    expect(find.text('BUY-IN PER RUNNER'), findsOneWidget);
    expect(find.text('PAYOUT MODE'), findsNothing);
  });

  group('TR-103: server-pool name suggestions (contract §3b)', () {
    String nameOf(WidgetTester tester, String plaqueKey) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byKey(Key(plaqueKey)),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;

    testWidgets('plaques show names from the real backend pool', (tester) async {
      final authService = await _createAuthService();
      final api = _RecordingApi(
        suggestions: const [('Server Alphas', 'Server Betas')],
      );
      await _pump(tester, authService, api);
      await _switchToTeams(tester);
      await tester.pump();

      expect(api.suggestCalls, greaterThanOrEqualTo(1));
      expect(nameOf(tester, 'team-plaque-a'), 'Server Alphas');
      expect(nameOf(tester, 'team-plaque-b'), 'Server Betas');
    });

    testWidgets('the dice pulls a fresh pair from the server pool',
        (tester) async {
      final authService = await _createAuthService();
      final api = _RecordingApi(
        suggestions: const [
          ('Server Alphas', 'Server Betas'),
          ('Second Roll A', 'Second Roll B'),
        ],
      );
      await _pump(tester, authService, api);
      await _switchToTeams(tester);
      await tester.pump();

      final before = api.suggestCalls;
      await tester.tap(find.byKey(const Key('team-name-reroll')));
      await tester.pump();
      await tester.pump();

      expect(api.suggestCalls, before + 1);
      expect(nameOf(tester, 'team-plaque-a'), 'Second Roll A');
      expect(nameOf(tester, 'team-plaque-b'), 'Second Roll B');
    });

    testWidgets('server names ride the create body as creator overrides',
        (tester) async {
      final authService = await _createAuthService();
      final api = _RecordingApi(
        suggestions: const [('Server Alphas', 'Server Betas')],
      );
      await _pump(tester, authService, api);
      await _switchToTeams(tester);
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('race-name-field')),
        'Capy Cup',
      );
      await tester.ensureVisible(find.text('CREATE RACE'));
      await tester.tap(find.text('CREATE RACE'));
      await tester.pump();

      // The plaques must never lie: what was shown is what gets created.
      expect(api.lastCreateTeamRaceCall!['teamAName'], 'Server Alphas');
      expect(api.lastCreateTeamRaceCall!['teamBName'], 'Server Betas');
    });

    testWidgets('an unavailable suggest route falls back to the local pool '
        'and still creates', (tester) async {
      final authService = await _createAuthService();
      // suggestions: null -> the endpoint answers nothing (older backend).
      final api = _RecordingApi();
      await _pump(tester, authService, api);
      await _switchToTeams(tester);
      await tester.pump();

      final a = nameOf(tester, 'team-plaque-a');
      final b = nameOf(tester, 'team-plaque-b');
      expect(a, isNotEmpty);
      expect(b, isNotEmpty);
      expect(a.toLowerCase(), isNot(equals(b.toLowerCase())));

      // Reroll still works offline.
      await tester.tap(find.byKey(const Key('team-name-reroll')));
      await tester.pump();
      await tester.pump();
      expect(nameOf(tester, 'team-plaque-a'), isNotEmpty);

      // And creation is never blocked by the failed suggest.
      await tester.enterText(
        find.byKey(const Key('race-name-field')),
        'Capy Cup',
      );
      await tester.ensureVisible(find.text('CREATE RACE'));
      await tester.tap(find.text('CREATE RACE'));
      await tester.pump();
      expect(api.lastCreateTeamRaceCall, isNotNull);
    });

    testWidgets('a name the user typed survives a rebuild (no clobbering)',
        (tester) async {
      final authService = await _createAuthService();
      final api = _RecordingApi(
        suggestions: const [('Server Alphas', 'Server Betas')],
      );
      await _pump(tester, authService, api);
      await _switchToTeams(tester);
      await tester.pump();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('team-plaque-a')),
          matching: find.byType(TextField),
        ),
        'My Own Name',
      );
      await tester.pump();
      // Toggling away and back must not silently overwrite the custom name.
      await tester.tap(find.byKey(const Key('race-format-ffa')));
      await tester.pumpAndSettle();
      await _switchToTeams(tester);
      await tester.pump();

      expect(nameOf(tester, 'team-plaque-a'), 'My Own Name');
    });
  });

  testWidgets('TR-103: identical custom names are rejected before the API call',
      (tester) async {
    final authService = await _createAuthService();
    final api = _RecordingApi();
    await _pump(tester, authService, api);
    await _switchToTeams(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('team-plaque-a')),
        matching: find.byType(TextField),
      ),
      'Same Name',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('team-plaque-b')),
        matching: find.byType(TextField),
      ),
      'same name',
    );
    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Capy Cup',
    );

    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pump();

    expect(api.lastCreateTeamRaceCall, isNull);
    expect(find.text('Give the two teams different names.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
