import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';

// Race timeline options — spec §9 tests 13-18, on the REAL create screen.
//
// The chips become 1 DAY / 1 WEEK / 2 WEEKS / CUSTOM; CUSTOM owns
// scheduledStartAt (so the SCHEDULED START card is hidden while it is
// selected) and adds an exact scheduledEndAt. The whole custom control is
// gated on `featureFlags.customRaceWindowEnabled`, which DEFAULTS OFF so a new
// build against an older backend is behaviorally identical to today.

class _RecordingApi extends BackendApiService {
  Map<String, dynamic>? lastCreateRaceCall;
  Map<String, dynamic>? lastCreateTeamRaceCall;

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
    DateTime? scheduledEndAt,
  }) async {
    lastCreateRaceCall = {
      'name': name,
      'maxDurationDays': maxDurationDays,
      'scheduledStartAt': scheduledStartAt,
      'scheduledEndAt': scheduledEndAt,
    };
    return {
      'race': {'id': 'race-1', 'name': name},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 0, 'heldCoins': 0};
}

Future<AuthService> _authService({bool customWindow = true}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 0,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  if (customWindow) {
    // Read through the REAL flag surface, exactly as /auth/me delivers it.
    authService.applyBackendUser(const {
      'featureFlags': {'customRaceWindowEnabled': true},
    }, authoritative: true);
  }
  return authService;
}

Future<CreateRaceScreenState> _pump(
  WidgetTester tester,
  BackendApiService api, {
  bool customWindow = true,
  bool expanded = true,
}) async {
  // A tall surface so the whole form is laid out at once: `ensureVisible`
  // parks a chip under the fixed header on the default 800x600 view and the
  // tap then lands on the header instead of the chip.
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final authService = await _authService(customWindow: customWindow);
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
  return tester.state<CreateRaceScreenState>(find.byType(CreateRaceScreen));
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await tester.pump();
}

String _derivation(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('create-prize-pool-derivation')))
    .data!;

String _coins(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('create-prize-pool-coins'))).data!;

bool _createEnabled(WidgetTester tester) {
  final button = tester.widget<PillButton>(
    find.widgetWithText(PillButton, 'CREATE RACE'),
  );
  return button.onPressed != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.7',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  // -- 13 --------------------------------------------------------------------

  testWidgets('the card is TIMELINE with 1 DAY / 1 WEEK / 2 WEEKS / CUSTOM', (
    tester,
  ) async {
    await _pump(tester, _RecordingApi());

    expect(find.text('TIMELINE'), findsOneWidget);
    expect(find.text('DURATION'), findsNothing);
    expect(find.text('1 DAY'), findsOneWidget);
    expect(find.text('1 WEEK'), findsOneWidget);
    expect(find.text('2 WEEKS'), findsOneWidget);
    expect(find.text('CUSTOM'), findsOneWidget);

    for (final days in [1, 7, 14]) {
      expect(find.byKey(Key('duration-option-$days')), findsOneWidget);
    }
    expect(find.byKey(const Key('duration-option-3')), findsNothing);
    expect(find.byKey(const Key('duration-option-custom')), findsOneWidget);
  });

  // -- 14 --------------------------------------------------------------------

  testWidgets(
    'CUSTOM hides SCHEDULED START; a preset restores it with the same time',
    (tester) async {
      final state = await _pump(tester, _RecordingApi());

      expect(find.text('SCHEDULED START'), findsOneWidget);

      final picked = DateTime.now().add(const Duration(days: 2));
      state.debugSetScheduledStart(picked);
      await tester.pump();
      expect(find.text('AUTO-START'), findsOneWidget);

      await _tap(tester, const Key('duration-option-custom'));

      // Exactly one control writes scheduledStartAt (acceptance criterion 4).
      expect(find.text('SCHEDULED START'), findsNothing);
      expect(find.byKey(const Key('timeline-starts-row')), findsOneWidget);
      expect(find.byKey(const Key('timeline-ends-row')), findsOneWidget);
      // The already-picked start is seeded into the STARTS row, not "Now".
      expect(find.text("When everyone's in"), findsNothing);

      await _tap(tester, const Key('duration-option-7'));

      expect(find.text('SCHEDULED START'), findsOneWidget);
      expect(find.text('AUTO-START'), findsOneWidget);
      expect(find.byKey(const Key('timeline-starts-row')), findsNothing);
      expect(find.byKey(const Key('timeline-ends-row')), findsNothing);
    },
  );

  // -- 15 --------------------------------------------------------------------

  testWidgets('the prize plaque follows the DERIVED day count of the window', (
    tester,
  ) async {
    final state = await _pump(tester, _RecordingApi());

    // Default preset: 10 runners x 7 days (4 points) x 20 = 800.
    expect(_coins(tester), '800');
    expect(_derivation(tester), '10 PLAYERS × 7 DAYS');

    await _tap(tester, const Key('duration-option-custom'));

    // A 25-hour window floors to ONE day — the anti-exploit rounding.
    final start = DateTime.now().add(const Duration(hours: 1));
    state.debugSetScheduledStart(start);
    state.debugSetCustomEnd(start.add(const Duration(hours: 25)));
    await tester.pump();

    expect(_derivation(tester), '10 PLAYERS × 1 DAY');
    expect(_coins(tester), '200');

    // A 5-day window prices at the 7-day band (4 points): 10 x 4 x 20 = 800.
    state.debugSetCustomEnd(start.add(const Duration(days: 5)));
    await tester.pump();

    expect(_derivation(tester), '10 PLAYERS × 5 DAYS');
    expect(_coins(tester), '800');
  });

  // -- 16 --------------------------------------------------------------------

  testWidgets('an invalid window disables CREATE and names the reason', (
    tester,
  ) async {
    final state = await _pump(tester, _RecordingApi());
    await _tap(tester, const Key('duration-option-custom'));
    expect(_createEnabled(tester), isTrue);

    final start = DateTime.now().add(const Duration(hours: 1));
    state.debugSetScheduledStart(start);

    // End before start.
    state.debugSetCustomEnd(start.subtract(const Duration(hours: 2)));
    await tester.pump();
    expect(find.text('The end has to be after the start'), findsOneWidget);
    expect(_createEnabled(tester), isFalse);

    // Under the 24h floor.
    state.debugSetCustomEnd(start.add(const Duration(hours: 3)));
    await tester.pump();
    expect(find.text('A race has to run at least 1 day'), findsOneWidget);
    expect(_createEnabled(tester), isFalse);

    // Over 30 days.
    state.debugSetCustomEnd(start.add(const Duration(days: 31)));
    await tester.pump();
    expect(find.text('A race can run at most 30 days'), findsOneWidget);
    expect(_createEnabled(tester), isFalse);

    // A window that is entirely in the past — reachable on a stale scheduled
    // race whose start has already slipped by. End is after start, so this is
    // the "in the future" rule and not the ordering one.
    state.debugSetScheduledStart(DateTime.now().subtract(const Duration(days: 10)));
    state.debugSetCustomEnd(DateTime.now().subtract(const Duration(days: 2)));
    await tester.pump();
    expect(find.text('Pick an end time in the future'), findsOneWidget);
    expect(_createEnabled(tester), isFalse);

    // Back to a legal window: CREATE comes alive again.
    state.debugSetCustomEnd(DateTime.now().add(const Duration(days: 4)));
    await tester.pump();
    expect(_createEnabled(tester), isTrue);
  });

  // -- 17 --------------------------------------------------------------------

  testWidgets('createRace carries scheduledEndAt only for a CUSTOM window', (
    tester,
  ) async {
    final api = _RecordingApi();
    final state = await _pump(tester, api);

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Weekend Push',
    );
    await _tap(tester, const Key('duration-option-custom'));

    final start = DateTime.now().add(const Duration(hours: 1));
    final end = start.add(const Duration(days: 4, hours: 9));
    state.debugSetScheduledStart(start);
    state.debugSetCustomEnd(end);
    await tester.pump();

    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pumpAndSettle();

    expect(api.lastCreateRaceCall!['scheduledEndAt'], end);
    expect(api.lastCreateRaceCall!['scheduledStartAt'], start);
  });

  testWidgets('a preset sends NO scheduledEndAt at all', (tester) async {
    final api = _RecordingApi();
    final state = await _pump(tester, api);

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Plain Week',
    );
    // Pick a custom window, then change your mind and take a preset.
    await _tap(tester, const Key('duration-option-custom'));
    state.debugSetCustomEnd(DateTime.now().add(const Duration(days: 6)));
    await tester.pump();
    await _tap(tester, const Key('duration-option-14'));

    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pumpAndSettle();

    expect(api.lastCreateRaceCall!['scheduledEndAt'], isNull);
    expect(api.lastCreateRaceCall!['maxDurationDays'], 14);
  });

  // -- 18 --------------------------------------------------------------------

  testWidgets('flag OFF: no CUSTOM chip, SCHEDULED START card untouched', (
    tester,
  ) async {
    await _pump(tester, _RecordingApi(), customWindow: false);

    expect(find.text('TIMELINE'), findsOneWidget);
    expect(find.byKey(const Key('duration-option-custom')), findsNothing);
    expect(find.text('CUSTOM'), findsNothing);
    expect(find.byKey(const Key('timeline-starts-row')), findsNothing);
    expect(find.byKey(const Key('timeline-ends-row')), findsNothing);
    // Today's control is present and unhidden.
    expect(find.text('SCHEDULED START'), findsOneWidget);
    for (final days in [1, 7, 14]) {
      expect(find.byKey(Key('duration-option-$days')), findsOneWidget);
    }
  });

  testWidgets('an ABSENT flag reads as off (older backend)', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'apple-token',
      'auth_user_identifier': 'apple-user-123',
      'auth_session_token': 'session-token',
      'auth_backend_user_id': 'user-1',
      'auth_display_name': 'Trail Walker',
    });
    final authService = AuthService();
    await authService.restoreSession();
    // A complete envelope from a backend that has never heard of the flag.
    authService.applyBackendUser(const {
      'featureFlags': {'teamRacesEnabled': true},
    }, authoritative: true);
    expect(authService.customRaceWindowEnabled, isFalse);

    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: CreateRaceScreen(
          authService: authService,
          backendApiService: _RecordingApi(),
          initialCustomizeExpanded: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('duration-option-custom')), findsNothing);
  });

  testWidgets('tournaments hide the whole TIMELINE card, CUSTOM included', (
    tester,
  ) async {
    await _pump(tester, _RecordingApi());

    await _tap(tester, const Key('race-format-tournament'));

    expect(find.text('TIMELINE'), findsNothing);
    expect(find.byKey(const Key('duration-option-custom')), findsNothing);
    expect(find.byKey(const Key('timeline-ends-row')), findsNothing);
  });

  // -- Regressions found in review -------------------------------------------

  testWidgets('entering CUSTOM from 1 DAY seeds a LEGAL window', (
    tester,
  ) async {
    final state = await _pump(tester, _RecordingApi());

    await _tap(tester, const Key('duration-option-1'));
    await _tap(tester, const Key('duration-option-custom'));

    // Rounding the seed DOWN to the hour shaves minutes off the day and the
    // user is met with an error and a dead CREATE for a choice they never
    // made. The seeded window must always clear the 24h floor.
    expect(find.text('A race has to run at least 1 day'), findsNothing);
    expect(_createEnabled(tester), isTrue);
    expect(_derivation(tester), '10 PLAYERS × 1 DAY');
    expect(state.debugCustomEnd, isNotNull);
  });

  testWidgets('entering CUSTOM from a preset never shortens the plaque', (
    tester,
  ) async {
    await _pump(tester, _RecordingApi());

    for (final entry in {1: '1 DAY', 7: '7 DAYS', 14: '14 DAYS'}.entries) {
      await _tap(tester, Key('duration-option-${entry.key}'));
      await _tap(tester, const Key('duration-option-custom'));
      expect(
        _derivation(tester),
        '10 PLAYERS × ${entry.value}',
        reason: 'the seeded window must price the same as the preset it came '
            'from, not one day less',
      );
      expect(_createEnabled(tester), isTrue);
    }
  });

  testWidgets('switching to TOURNAMENT never leaves CREATE dead and silent', (
    tester,
  ) async {
    final state = await _pump(tester, _RecordingApi());

    await _tap(tester, const Key('duration-option-custom'));
    state.debugSetCustomEnd(DateTime.now().add(const Duration(hours: 2)));
    await tester.pump();
    expect(_createEnabled(tester), isFalse);

    // The TIMELINE card is hidden for tournaments, so its error must stop
    // gating the button — otherwise CREATE is permanently disabled with no
    // visible cause anywhere on the screen.
    await _tap(tester, const Key('race-format-tournament'));
    expect(find.text('TIMELINE'), findsNothing);
    expect(_createEnabled(tester), isTrue);
  });

  testWidgets('an illegal window is refused, never silently downgraded', (
    tester,
  ) async {
    final api = _RecordingApi();
    final state = await _pump(tester, api);

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Too Short',
    );
    await _tap(tester, const Key('duration-option-custom'));
    state.debugSetCustomEnd(DateTime.now().add(const Duration(hours: 2)));
    await tester.pump();

    // Reach past the disabled button the way a stale frame or a queued tap
    // would: the create path itself must refuse rather than fall through and
    // post a plain preset race the user never asked for.
    await state.debugCreateForTest();
    await tester.pump();

    expect(api.lastCreateRaceCall, isNull);
  });

  testWidgets('accepting BOTH picker defaults yields a creatable window', (
    tester,
  ) async {
    // The picker's earliest offered value must not be the one that fails
    // validation a second later: `start + 24h` exactly is not `> 24h`, so an
    // unbuffered default kills CREATE the instant the user taps OK twice
    // without changing anything.
    final api = _RecordingApi();
    final state = await _pump(tester, api);

    await _tap(tester, const Key('duration-option-custom'));
    // Drop the seeded end so the picker falls back to its own earliest value.
    state.debugSetCustomEnd(null);
    // Let the card's grow animation finish: AnimatedSize clips mid-flight, so
    // a row tapped before it settles is rendered but not hit-testable.
    await tester.pumpAndSettle();

    await _tap(tester, const Key('timeline-ends-row'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // The time picker follows immediately; accept its default too.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(state.debugCustomEnd, isNotNull);
    expect(find.text('A race has to run at least 1 day'), findsNothing);
    expect(_createEnabled(tester), isTrue);

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Default Window',
    );
    await tester.pump();

    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pumpAndSettle();

    expect(api.lastCreateRaceCall, isNotNull);
    final sent = api.lastCreateRaceCall!['scheduledEndAt'] as DateTime?;
    expect(sent, isNotNull);
    expect(
      sent!.difference(DateTime.now()) > const Duration(days: 1),
      isTrue,
      reason: 'the default the picker offers must clear the 24h floor',
    );
  });

  testWidgets('the kill switch flipping OFF mid-session reverts cleanly', (
    tester,
  ) async {
    final api = _RecordingApi();
    final authService = await _authService();
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    final state = tester.state<CreateRaceScreenState>(
      find.byType(CreateRaceScreen),
    );

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Flag Flip',
    );
    await _tap(tester, const Key('duration-option-custom'));
    state.debugSetCustomEnd(DateTime.now().add(const Duration(days: 4)));
    await tester.pump();
    expect(find.byKey(const Key('timeline-ends-row')), findsOneWidget);
    expect(find.text('SCHEDULED START'), findsNothing);

    // A later /auth/me turns the feature off, on the SAME live screen.
    authService.applyBackendUser(const {
      'featureFlags': {'customRaceWindowEnabled': false},
    }, authoritative: true);
    state.debugSetCustomEnd(state.debugCustomEnd);
    await tester.pump();

    // Degrades to exactly today's screen: no chip, no orphaned rows, and the
    // SCHEDULED START card back where it belongs.
    expect(find.byKey(const Key('duration-option-custom')), findsNothing);
    expect(find.byKey(const Key('timeline-ends-row')), findsNothing);
    expect(find.text('SCHEDULED START'), findsOneWidget);

    // And the create call is a plain preset race — no half-hidden window.
    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pumpAndSettle();
    expect(api.lastCreateRaceCall!['scheduledEndAt'], isNull);
  });
}
