import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/screens/edit_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/powerup_interval_note.dart';

// Fixed 2,000-step powerup interval (spec §7, tests 10-14).
//
// The creator no longer picks how far apart powerup boxes are: every
// powerups-enabled race earns a box every 2,000 steps, decided by the app and
// pinned by the backend. The picker chips are gone from both the create and the
// edit screen and are replaced by a plain-language note.
//
// Two things this file locks down that are easy to get wrong:
//   * The create screen KEEPS SENDING powerupStepInterval: 2000 on all three
//     create paths (§5.4). During the phased App Store rollout this build can
//     hit a backend that has not deployed yet, whose legacy validator 400s on
//     powerupsEnabled: true with no interval — that would mean "cannot create a
//     race at all" for a week.
//   * The edit screen sends NOTHING (§4.3). Lowering a running race's interval
//     back-mints every box the new spacing says the runner should already have.

class _RecordingApi extends BackendApiService {
  Map<String, dynamic>? lastCreateRaceCall;
  Map<String, dynamic>? lastCreateTeamRaceCall;
  Map<String, dynamic>? lastCreateTournamentCall;

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
    lastCreateRaceCall = {
      'name': name,
      'powerupsEnabled': powerupsEnabled,
      'powerupStepInterval': powerupStepInterval,
    };
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
      'powerupsEnabled': powerupsEnabled,
      'powerupStepInterval': powerupStepInterval,
    };
    return {
      'race': {'id': 'race-t1', 'name': name, 'isTeamRace': true},
    };
  }

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
      'powerupsEnabled': powerupsEnabled,
      'powerupStepInterval': powerupStepInterval,
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

class _RecordingEditApi extends BackendApiService {
  Map<String, dynamic>? lastUpdate;

  @override
  Future<Map<String, dynamic>> updateRace({
    required String identityToken,
    required String raceId,
    String? name,
    int? maxDurationDays,
    bool? isPublic,
    bool? powerupsEnabled,
    int? powerupStepInterval,
    int? buyInAmount,
    String? payoutPreset,
    int? maxParticipants,
    bool setMaxParticipantsUnlimited = false,
    String? teamAName,
    String? teamBName,
    int? teamSize,
  }) async {
    lastUpdate = {
      'name': name,
      'powerupsEnabled': powerupsEnabled,
      'powerupStepInterval': powerupStepInterval,
    };
    return {
      'race': {'id': raceId},
    };
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

/// The create/edit forms are long. Give the test a tall surface so every
/// control is really on screen — a clipped button can't be tapped.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpCreate(
  WidgetTester tester,
  AuthService authService,
  _RecordingApi api,
) async {
  _useTallSurface(tester);
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

/// A PENDING race the owner can still edit.
Map<String, dynamic> _race({
  bool powerupsEnabled = true,
  Object? powerupStepInterval = 2000,
}) => {
  'id': 'race-1',
  'name': 'Morning Walk',
  'status': 'PENDING',
  'maxDurationDays': 3,
  'buyInAmount': 0,
  'payoutPreset': 'WINNER_TAKES_ALL',
  'isPublic': false,
  'maxParticipants': 10,
  'powerupsEnabled': powerupsEnabled,
  'powerupStepInterval': powerupStepInterval,
  'participants': const [
    {'userId': 'u1', 'status': 'ACCEPTED', 'buyInStatus': 'NONE'},
  ],
};

Future<void> _pumpEdit(
  WidgetTester tester,
  BackendApiService api, {
  required Map<String, dynamic> race,
}) async {
  final authService = await _createAuthService();
  _useTallSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: EditRaceScreen(
        authService: authService,
        backendApiService: api,
        raceId: 'race-1',
        race: race,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _enablePowerups(WidgetTester tester) async {
  final toggle = find.byKey(const Key('powerups-toggle'));
  await tester.ensureVisible(toggle);
  final on = tester.widget<Switch>(
    find.descendant(of: toggle, matching: find.byType(Switch)),
  );
  if (on.value != true) {
    await tester.tap(toggle);
    await tester.pump();
  }
}

/// Presses CREATE RACE.
Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('CREATE RACE'));
  await tester.pump();
  await tester.tap(find.text('CREATE RACE'));
}

String _noteText(WidgetTester tester) {
  final note = tester.widget<Text>(
    find.descendant(
      of: find.byKey(const Key('powerup-interval-note')),
      matching: find.byType(Text),
    ),
  );
  return note.data ?? note.textSpan!.toPlainText();
}

void _expectNoIntervalChips() {
  expect(find.text('POWERUP EVERY'), findsNothing);
  for (final label in ['2k', '3k', '4k', '5k', '10k', '25k']) {
    expect(find.text(label), findsNothing, reason: 'interval chip $label');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Test 10 — the picker is gone from the create screen and the note explains
  // the fixed rule in its place.
  testWidgets('create: no interval chips, and the note names 2,000 steps', (
    tester,
  ) async {
    final auth = await _createAuthService();
    await _pumpCreate(tester, auth, _RecordingApi());

    await _enablePowerups(tester);

    _expectNoIntervalChips();
    expect(find.byKey(const Key('powerup-interval-note')), findsOneWidget);
    expect(_noteText(tester), contains('2,000 steps'));
  });

  // Test 11 — the new app keeps sending 2,000 on every create path, so it still
  // works against a backend that has not deployed yet (§5.4).
  testWidgets('create: the race path sends powerupStepInterval 2000', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final api = _RecordingApi();
    await _pumpCreate(tester, auth, api);

    await _enablePowerups(tester);
    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Morning Walk',
    );

    await _submit(tester);
    await tester.pump();
    await tester.pump();

    expect(api.lastCreateRaceCall, isNotNull);
    expect(api.lastCreateRaceCall!['powerupsEnabled'], isTrue);
    expect(api.lastCreateRaceCall!['powerupStepInterval'], 2000);
  });

  testWidgets('create: the team-race path sends powerupStepInterval 2000', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final api = _RecordingApi();
    await _pumpCreate(tester, auth, api);

    await tester.ensureVisible(find.byKey(const Key('race-format-teams')));
    await tester.tap(find.byKey(const Key('race-format-teams')));
    await tester.pumpAndSettle();

    await _enablePowerups(tester);
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
    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Capy Cup',
    );

    await _submit(tester);
    await tester.pump();
    await tester.pump();

    expect(api.lastCreateTeamRaceCall, isNotNull);
    expect(api.lastCreateTeamRaceCall!['powerupsEnabled'], isTrue);
    expect(api.lastCreateTeamRaceCall!['powerupStepInterval'], 2000);
  });

  testWidgets('create: the tournament path sends powerupStepInterval 2000', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final api = _RecordingApi();
    await _pumpCreate(tester, auth, api);

    await tester.ensureVisible(find.byKey(const Key('race-format-tournament')));
    await tester.tap(find.byKey(const Key('race-format-tournament')));
    await tester.pumpAndSettle();

    await _enablePowerups(tester);
    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Friday Gauntlet',
    );

    await _submit(tester);
    await tester.pump();
    await tester.pump();

    expect(api.lastCreateTournamentCall, isNotNull);
    expect(api.lastCreateTournamentCall!['powerupsEnabled'], isTrue);
    expect(api.lastCreateTournamentCall!['powerupStepInterval'], 2000);
  });

  // Test 12 — edit never sends the field: a PATCH that lowered a running race's
  // interval would back-mint boxes (§4.3).
  testWidgets('edit: no interval chips, and saving sends no interval', (
    tester,
  ) async {
    final api = _RecordingEditApi();
    await _pumpEdit(tester, api, race: _race());

    _expectNoIntervalChips();
    expect(find.byKey(const Key('powerup-interval-note')), findsOneWidget);

    // Change something real so the sparse PATCH actually fires.
    await tester.enterText(find.byType(TextField).first, 'Evening Walk');
    await tester.pump();

    await tester.ensureVisible(find.text('SAVE CHANGES'));
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pump();
    await tester.pump();

    expect(api.lastUpdate, isNotNull);
    expect(api.lastUpdate!['name'], 'Evening Walk');
    expect(api.lastUpdate!['powerupStepInterval'], isNull);
  });

  // Test 13 — a grandfathered race tells the truth about its own spacing.
  testWidgets('edit: a 5,000-step race says 5,000, not 2,000', (tester) async {
    await _pumpEdit(
      tester,
      _RecordingEditApi(),
      race: _race(powerupStepInterval: 5000),
    );

    expect(_noteText(tester), contains('5,000 steps'));
    expect(_noteText(tester), isNot(contains('2,000')));
  });

  // Test 14 — an absent interval (older or newer backend) falls back to 2,000
  // instead of throwing or rendering "null".
  testWidgets('edit: a null interval falls back to 2,000 without throwing', (
    tester,
  ) async {
    await _pumpEdit(
      tester,
      _RecordingEditApi(),
      race: _race(powerupStepInterval: null),
    );

    expect(tester.takeException(), isNull);
    expect(_noteText(tester), contains('2,000 steps'));
    expect(_noteText(tester), isNot(contains('null')));
  });

  // The note is new chrome inside an existing card, so it has to survive the
  // night flip. Per dark-mode-fix-batch-2026-07-23 the trap is hardcoding a
  // color that inverts at night; these read the resolved roles instead.
  group('the note themes in light and night mode', () {
    double contrast(Color a, Color b) {
      double lum(Color c) =>
          0.299 * (c.r * 255) + 0.587 * (c.g * 255) + 0.114 * (c.b * 255);
      return (lum(a) - lum(b)).abs();
    }

    Future<void> pumpNote(WidgetTester tester, ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: PowerupIntervalNote(enabled: true)),
        ),
      );
      await tester.pump();
    }

    void expectReadable(WidgetTester tester, AppPalette palette) {
      final text = tester.widget<Text>(find.byType(Text).first);
      final spans = (text.textSpan! as TextSpan).children!;
      final body = text.style!.color!;
      final emphasis = (spans[1] as TextSpan).style!.color!;
      final surface = tester
          .widget<Container>(find.byType(Container).first)
          .decoration;

      expect(body, palette.textMid);
      expect(emphasis, palette.textDark);
      expect((surface! as BoxDecoration).color, palette.parchmentDark);
      expect(contrast(body, palette.parchmentDark), greaterThan(45));
      expect(contrast(emphasis, palette.parchmentDark), greaterThan(70));
    }

    testWidgets('light', (tester) async {
      await pumpNote(tester, AppThemeData.light());
      expectReadable(tester, AppPalette.light);
    });

    testWidgets('night', (tester) async {
      await pumpNote(tester, AppThemeData.night());
      expectReadable(tester, AppPalette.night);
    });
  });
}
