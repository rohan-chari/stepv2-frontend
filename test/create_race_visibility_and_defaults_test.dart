import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/screens/edit_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

// Feature batch 2026-07-27 — items 2, 6 and 8 on the race-creation form.
//
//  * Item 2: powerups start ON. A race created without touching the customize
//    section must still send `powerupsEnabled: true` AND the fixed 2,000-step
//    interval, because a backend that has not deployed yet 400s on
//    powerupsEnabled with no interval.
//  * Item 6: the public/private control was a single switch whose LABEL
//    changed with its own value — "PRIVATE RACE" next to an OFF switch reads
//    as "private is the thing that is off", so people flipped it to get a
//    private race and got a public one. It is now a two-segment control with
//    both options always visible.
//  * Item 8: the prize plaque no longer footnotes "FUNDED BY BARA · FREE TO
//    ENTER" (nor the tournament "FREE TO ENTER · CHAMPION TAKES ALL").
//
// Everything here is asserted through the real screen and the real request the
// screen sends — never a private field.

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
      'isPublic': isPublic,
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
      'isPublic': isPublic,
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
      'isPublic': isPublic,
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
    lastUpdate = {'name': name, 'isPublic': isPublic};
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

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpCreate(
  WidgetTester tester,
  AuthService authService,
  _RecordingApi api, {
  bool expanded = true,
}) async {
  _useTallSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: CreateRaceScreen(
        authService: authService,
        backendApiService: api,
        initialCustomizeExpanded: expanded,
      ),
    ),
  );
  await tester.pump();
}

Map<String, dynamic> _race({bool isPublic = false}) => {
  'id': 'race-1',
  'name': 'Morning Walk',
  'status': 'PENDING',
  'maxDurationDays': 3,
  'buyInAmount': 0,
  'payoutPreset': 'WINNER_TAKES_ALL',
  'isPublic': isPublic,
  'maxParticipants': 10,
  'powerupsEnabled': true,
  'powerupStepInterval': 2000,
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

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('CREATE RACE'));
  await tester.pump();
  await tester.tap(find.text('CREATE RACE'));
  await tester.pump();
  await tester.pump();
}

bool _powerupsToggleValue(WidgetTester tester) => tester
    .widget<Switch>(
      find.descendant(
        of: find.byKey(const Key('powerups-toggle')),
        matching: find.byType(Switch),
      ),
    )
    .value;

String _subcopy(WidgetTester tester, Key key) {
  final text = tester.widget<Text>(find.byKey(key));
  return text.data ?? text.textSpan!.toPlainText();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Item 2 — powerups default ON ─────────────────────────────────────────
  group('item 2: powerups start ON at race creation', () {
    testWidgets('the toggle is already on at first paint', (tester) async {
      final auth = await _createAuthService();
      await _pumpCreate(tester, auth, _RecordingApi());

      expect(find.byKey(const Key('powerups-toggle')), findsOneWidget);
      expect(_powerupsToggleValue(tester), isTrue);
    });

    testWidgets('creating without touching anything sends true + 2000', (
      tester,
    ) async {
      final auth = await _createAuthService();
      final api = _RecordingApi();
      // Collapsed: the customize section is never opened, so this is exactly
      // what a creator who just names a race and taps CREATE RACE sends.
      await _pumpCreate(tester, auth, api, expanded: false);

      await tester.enterText(
        find.byKey(const Key('race-name-field')),
        'Morning Walk',
      );
      await _submit(tester);

      expect(api.lastCreateRaceCall, isNotNull);
      expect(api.lastCreateRaceCall!['powerupsEnabled'], isTrue);
      expect(api.lastCreateRaceCall!['powerupStepInterval'], 2000);
    });

    testWidgets('the creator can still turn powerups off', (tester) async {
      final auth = await _createAuthService();
      final api = _RecordingApi();
      await _pumpCreate(tester, auth, api);

      final toggle = find.byKey(const Key('powerups-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(_powerupsToggleValue(tester), isFalse);

      await tester.enterText(
        find.byKey(const Key('race-name-field')),
        'Quiet Walk',
      );
      await _submit(tester);

      expect(api.lastCreateRaceCall!['powerupsEnabled'], isFalse);
      expect(api.lastCreateRaceCall!['powerupStepInterval'], isNull);
    });
  });

  // ── Item 6 — PRIVATE | PUBLIC segmented control ──────────────────────────
  group('item 6: the visibility control names both options', () {
    testWidgets('both segments render and PRIVATE is selected first', (
      tester,
    ) async {
      final auth = await _createAuthService();
      await _pumpCreate(tester, auth, _RecordingApi());

      expect(find.byKey(const Key('race-visibility-private')), findsOneWidget);
      expect(find.byKey(const Key('race-visibility-public')), findsOneWidget);
      expect(find.text('PRIVATE'), findsOneWidget);
      expect(find.text('PUBLIC'), findsOneWidget);

      // The old ambiguous switch is gone: no label that mutates with its own
      // value, and no bare on/off control to misread.
      expect(find.text('PRIVATE RACE'), findsNothing);
      expect(find.text('PUBLIC RACE'), findsNothing);

      expect(
        _subcopy(tester, const Key('race-visibility-subcopy')),
        'INVITE ONLY',
      );
    });

    testWidgets('the default create payload is still private', (tester) async {
      final auth = await _createAuthService();
      final api = _RecordingApi();
      await _pumpCreate(tester, auth, api);

      await tester.enterText(
        find.byKey(const Key('race-name-field')),
        'Morning Walk',
      );
      await _submit(tester);

      expect(api.lastCreateRaceCall!['isPublic'], isFalse);
    });

    testWidgets('tapping PUBLIC updates the subcopy and sends isPublic true', (
      tester,
    ) async {
      final auth = await _createAuthService();
      final api = _RecordingApi();
      await _pumpCreate(tester, auth, api);

      final public = find.byKey(const Key('race-visibility-public'));
      await tester.ensureVisible(public);
      await tester.tap(public);
      await tester.pump();

      expect(
        _subcopy(tester, const Key('race-visibility-subcopy')),
        'ANYONE CAN JOIN',
      );

      await tester.enterText(
        find.byKey(const Key('race-name-field')),
        'Open Trail',
      );
      await _submit(tester);

      expect(api.lastCreateRaceCall!['isPublic'], isTrue);
    });

    testWidgets('tapping back to PRIVATE sends isPublic false', (tester) async {
      final auth = await _createAuthService();
      final api = _RecordingApi();
      await _pumpCreate(tester, auth, api);

      await tester.ensureVisible(find.byKey(const Key('race-visibility-public')));
      await tester.tap(find.byKey(const Key('race-visibility-public')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('race-visibility-private')));
      await tester.pump();

      expect(
        _subcopy(tester, const Key('race-visibility-subcopy')),
        'INVITE ONLY',
      );

      await tester.enterText(
        find.byKey(const Key('race-name-field')),
        'Closed Trail',
      );
      await _submit(tester);

      expect(api.lastCreateRaceCall!['isPublic'], isFalse);
    });

    testWidgets('the edit screen gets the same control, seeded from the race', (
      tester,
    ) async {
      final api = _RecordingEditApi();
      await _pumpEdit(tester, api, race: _race(isPublic: true));

      expect(find.byKey(const Key('race-visibility-private')), findsOneWidget);
      expect(find.byKey(const Key('race-visibility-public')), findsOneWidget);
      expect(find.text('PRIVATE RACE'), findsNothing);
      expect(
        _subcopy(tester, const Key('race-visibility-subcopy')),
        'ANYONE CAN JOIN',
      );

      await tester.ensureVisible(
        find.byKey(const Key('race-visibility-private')),
      );
      await tester.tap(find.byKey(const Key('race-visibility-private')));
      await tester.pump();

      await tester.ensureVisible(find.text('SAVE CHANGES'));
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pump();
      await tester.pump();

      expect(api.lastUpdate, isNotNull);
      expect(api.lastUpdate!['isPublic'], isFalse);
    });

    // The control is new chrome, so it has to survive the night flip
    // (dark-mode-fix-batch-2026-07-23: the trap is a color that inverts).
    // Themes are built INSIDE the test body: AppThemeData reaches for a Google
    // font, which throws "no current invoker" outside a test zone.
    for (final theme in [
      ('light', AppThemeData.light, AppPalette.light),
      ('night', AppThemeData.night, AppPalette.night),
    ]) {
      testWidgets('the selected segment stays legible in ${theme.$1}', (
        tester,
      ) async {
        final auth = await _createAuthService();
        _useTallSurface(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.$2(),
            home: CreateRaceScreen(
              authService: auth,
              backendApiService: _RecordingApi(),
              initialCustomizeExpanded: true,
            ),
          ),
        );
        await tester.pump();

        final selected = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('race-visibility-private')),
            matching: find.text('PRIVATE'),
          ),
        );
        final unselected = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('race-visibility-public')),
            matching: find.text('PUBLIC'),
          ),
        );
        // Selected reads on the roof fill; unselected reads on the parchment
        // track. Neither may collapse into its own background.
        expect(selected.style!.color, isNot(unselected.style!.color));
        expect(unselected.style!.color, theme.$3.textMid);
      });
    }
  });

  // ── Item 8 — no "FUNDED BY BARA" footnote ────────────────────────────────
  group('item 8: the create-screen prize plaque drops the funding footnote', () {
    testWidgets('the race preview plaque has no footnote', (tester) async {
      final auth = await _createAuthService();
      await _pumpCreate(tester, auth, _RecordingApi());

      expect(find.byKey(const Key('create-prize-pool-preview')), findsOneWidget);
      expect(find.text('FUNDED BY BARA · FREE TO ENTER'), findsNothing);
      expect(
        find.textContaining('FUNDED BY BARA', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('FREE TO ENTER', findRichText: true),
        findsNothing,
      );
      // The pool figure itself is untouched.
      expect(find.byKey(const Key('create-prize-pool-coins')), findsOneWidget);
    });

    testWidgets('the tournament plaque has no footnote either', (tester) async {
      final auth = await _createAuthService();
      await _pumpCreate(tester, auth, _RecordingApi());

      await tester.ensureVisible(
        find.byKey(const Key('race-format-tournament')),
      );
      await tester.tap(find.byKey(const Key('race-format-tournament')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('tournament-prize-pool-preview')),
        findsOneWidget,
      );
      expect(
        find.textContaining('FREE TO ENTER', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('CHAMPION TAKES ALL', findRichText: true),
        findsNothing,
      );
      expect(
        find.byKey(const Key('tournament-prize-pool-coins')),
        findsOneWidget,
      );
    });
  });
}
