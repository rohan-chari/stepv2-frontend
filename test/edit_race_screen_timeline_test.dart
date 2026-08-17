import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/edit_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/race_timeline_card.dart';

// Race timeline options — spec §9 test 19 (+ §10.1 risk 6), on the REAL edit
// screen. The window is editable only while PENDING; a started race renders the
// card read-only against its stamped endsAt rather than offering an edit the
// server answers with 400 RACE_ALREADY_STARTED.

class _RecordingApi extends BackendApiService {
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
    DateTime? scheduledStartAt,
    DateTime? scheduledEndAt,
    bool clearScheduledEndAt = false,
  }) async {
    lastUpdate = {
      'maxDurationDays': maxDurationDays,
      'scheduledStartAt': scheduledStartAt,
      'scheduledEndAt': scheduledEndAt,
      'clearScheduledEndAt': clearScheduledEndAt,
    };
    return {
      'race': {'id': raceId},
    };
  }
}

final _start = DateTime.now().add(const Duration(days: 2));
final _end = _start.add(const Duration(days: 4, hours: 9));

Map<String, dynamic> _customPendingRace() => {
  'id': 'race-1',
  'name': 'Weekend Push',
  'status': 'PENDING',
  'maxDurationDays': 4,
  'payoutPreset': 'WINNER_TAKES_ALL',
  'isPublic': false,
  'maxParticipants': 10,
  'scheduledStartAt': _start.toUtc().toIso8601String(),
  'scheduledEndAt': _end.toUtc().toIso8601String(),
  'participants': const [
    {'userId': 'u1', 'status': 'ACCEPTED'},
  ],
};

Map<String, dynamic> _presetPendingRace() => {
  'id': 'race-1',
  'name': 'Plain Week',
  'status': 'PENDING',
  'maxDurationDays': 7,
  'payoutPreset': 'WINNER_TAKES_ALL',
  'isPublic': false,
  'maxParticipants': 10,
  'participants': const [],
};

Map<String, dynamic> _activeRace() => {
  'id': 'race-1',
  'name': 'Running Already',
  'status': 'ACTIVE',
  'maxDurationDays': 4,
  'payoutPreset': 'WINNER_TAKES_ALL',
  'isPublic': false,
  'maxParticipants': 10,
  'startedAt': DateTime.now()
      .subtract(const Duration(days: 1))
      .toUtc()
      .toIso8601String(),
  'endsAt': _end.toUtc().toIso8601String(),
  'scheduledEndAt': _end.toUtc().toIso8601String(),
  'participants': const [],
};

Future<AuthService> _authService({bool customWindow = true}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final authService = AuthService();
  await authService.restoreSession();
  authService.applyBackendUser({
    'featureFlags': {'customRaceWindowEnabled': customWindow},
  }, authoritative: true);
  return authService;
}

Future<EditRaceScreenState> _pump(
  WidgetTester tester,
  BackendApiService api, {
  required Map<String, dynamic> race,
  bool customWindow = true,
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final authService = await _authService(customWindow: customWindow);
  await tester.pumpWidget(
    MaterialApp(
      home: EditRaceScreen(
        authService: authService,
        raceId: race['id'] as String,
        race: race,
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  return tester.state<EditRaceScreenState>(find.byType(EditRaceScreen));
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('SAVE CHANGES'));
  await tester.tap(find.text('SAVE CHANGES'));
  await tester.pump();
  await tester.pump();
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

  testWidgets('a PENDING custom race opens on CUSTOM with its window shown', (
    tester,
  ) async {
    await _pump(tester, _RecordingApi(), race: _customPendingRace());

    expect(find.text('TIMELINE'), findsOneWidget);
    expect(find.byKey(const Key('duration-option-custom')), findsOneWidget);
    expect(find.byKey(const Key('timeline-starts-row')), findsOneWidget);
    expect(find.byKey(const Key('timeline-ends-row')), findsOneWidget);
    expect(find.text(formatRaceTimelineInstant(_start)), findsOneWidget);
    expect(find.text(formatRaceTimelineInstant(_end)), findsOneWidget);
  });

  testWidgets('tapping 1 WEEK clears the custom window explicitly', (
    tester,
  ) async {
    final api = _RecordingApi();
    await _pump(tester, api, race: _customPendingRace());

    await tester.ensureVisible(find.byKey(const Key('duration-option-7')));
    await tester.tap(find.byKey(const Key('duration-option-7')));
    await tester.pump();

    // Negative check: the window is no longer displayed anywhere.
    expect(find.byKey(const Key('timeline-starts-row')), findsNothing);
    expect(find.byKey(const Key('timeline-ends-row')), findsNothing);

    await _save(tester);

    expect(api.lastUpdate!['maxDurationDays'], 7);
    expect(api.lastUpdate!['clearScheduledEndAt'], isTrue);
    expect(api.lastUpdate!['scheduledEndAt'], isNull);
    // scheduledStartAt: null is REJECTED by the server — never send it.
    expect(api.lastUpdate!['scheduledStartAt'], isNull);
  });

  testWidgets('moving the window PATCHes both ends', (tester) async {
    final api = _RecordingApi();
    final state = await _pump(tester, api, race: _customPendingRace());

    final newStart = _start.add(const Duration(days: 1));
    final newEnd = _end.add(const Duration(days: 1));
    state.debugSetCustomWindow(start: newStart, end: newEnd);
    await tester.pump();

    await _save(tester);

    expect(api.lastUpdate!['scheduledStartAt'], newStart);
    expect(api.lastUpdate!['scheduledEndAt'], newEnd);
    expect(api.lastUpdate!['clearScheduledEndAt'], isFalse);
  });

  testWidgets('a preset race that stays on presets sends no window fields', (
    tester,
  ) async {
    final api = _RecordingApi();
    await _pump(tester, api, race: _presetPendingRace());

    await tester.ensureVisible(find.byKey(const Key('duration-option-14')));
    await tester.tap(find.byKey(const Key('duration-option-14')));
    await tester.pump();
    await _save(tester);

    expect(api.lastUpdate!['maxDurationDays'], 14);
    expect(api.lastUpdate!['scheduledEndAt'], isNull);
    expect(api.lastUpdate!['scheduledStartAt'], isNull);
    // Nothing to clear: this race never had a custom window.
    expect(api.lastUpdate!['clearScheduledEndAt'], isFalse);
  });

  testWidgets('an ACTIVE race renders the card read-only', (tester) async {
    await _pump(tester, _RecordingApi(), race: _activeRace());

    expect(find.text('TIMELINE'), findsOneWidget);
    for (final days in [1, 7, 14]) {
      expect(find.byKey(Key('duration-option-$days')), findsNothing);
    }
    expect(find.byKey(const Key('duration-option-custom')), findsNothing);
    expect(find.byKey(const Key('timeline-readonly-end')), findsOneWidget);
    expect(
      find.textContaining(formatRaceTimelineInstant(_end)),
      findsOneWidget,
    );
  });

  testWidgets('the flag being off hides CUSTOM but keeps the presets', (
    tester,
  ) async {
    await _pump(
      tester,
      _RecordingApi(),
      race: _presetPendingRace(),
      customWindow: false,
    );

    expect(find.byKey(const Key('duration-option-custom')), findsNothing);
    expect(find.byKey(const Key('duration-option-7')), findsOneWidget);
  });

  // -- The kill switch on a race that ALREADY has a window --------------------
  //
  // The server's flag gate is `startProvided || (endProvided && next !== null)`
  // (`editRace.js:214-226`): SETTING a window is killed, CLEARING one is
  // deliberately exempt so a creator is never stranded holding a window the
  // server no longer honors. The edit surface has to offer exactly that much.

  testWidgets('flag OFF with an existing window: presets stay tappable', (
    tester,
  ) async {
    await _pump(
      tester,
      _RecordingApi(),
      race: _customPendingRace(),
      customWindow: false,
    );

    expect(find.text('TIMELINE'), findsOneWidget);
    // The escape hatch is live.
    for (final days in [1, 7, 14]) {
      expect(find.byKey(Key('duration-option-$days')), findsOneWidget);
    }
    // Setting a window is what the flag kills.
    expect(find.byKey(const Key('duration-option-custom')), findsNothing);
    expect(find.byKey(const Key('timeline-ends-row')), findsNothing);
    expect(find.byKey(const Key('timeline-starts-row')), findsNothing);
    // But the user can still SEE what they are about to replace.
    expect(find.byKey(const Key('timeline-locked-window')), findsOneWidget);
    expect(find.text(formatRaceTimelineInstant(_end)), findsOneWidget);
    // This is NOT the started-race dead end.
    expect(find.byKey(const Key('timeline-readonly-end')), findsNothing);
  });

  testWidgets('flag OFF: tapping a preset issues the clearing PATCH', (
    tester,
  ) async {
    final api = _RecordingApi();
    await _pump(
      tester,
      api,
      race: _customPendingRace(),
      customWindow: false,
    );

    await tester.ensureVisible(find.byKey(const Key('duration-option-7')));
    await tester.tap(find.byKey(const Key('duration-option-7')));
    await tester.pump();

    // The locked window is gone the moment a preset replaces it.
    expect(find.byKey(const Key('timeline-locked-window')), findsNothing);

    await _save(tester);

    expect(api.lastUpdate!['maxDurationDays'], 7);
    expect(api.lastUpdate!['clearScheduledEndAt'], isTrue);
    expect(api.lastUpdate!['scheduledEndAt'], isNull);
    expect(api.lastUpdate!['scheduledStartAt'], isNull);
  });

  testWidgets('flag OFF: a name-only save never clears the window silently', (
    tester,
  ) async {
    // `_customSelected` stays true while the flag is off, so the "left custom"
    // branch must key off the user actually leaving it — not off the set-window
    // branch being skipped — or an unrelated edit destroys the window.
    final api = _RecordingApi();
    await _pump(
      tester,
      api,
      race: _customPendingRace(),
      customWindow: false,
    );

    await tester.enterText(find.byType(TextField).first, 'Renamed Push');
    await tester.pump();
    await _save(tester);

    expect(api.lastUpdate, isNotNull);
    expect(api.lastUpdate!['clearScheduledEndAt'], isFalse);
    expect(api.lastUpdate!['scheduledEndAt'], isNull);
    expect(api.lastUpdate!['maxDurationDays'], isNull);
  });

  testWidgets('a PENDING race whose scheduled start has slipped still opens', (
    tester,
  ) async {
    // The cron retries a scheduled race that never reached two accepted
    // runners, so `scheduledStartAt` can sit days in the past. An unclamped
    // picker anchor gives showDatePicker firstDate > lastDate, which asserts.
    final past = DateTime.now().subtract(const Duration(days: 40));
    await _pump(tester, _RecordingApi(), race: {
      'id': 'race-1',
      'name': 'Stale Schedule',
      'status': 'PENDING',
      'maxDurationDays': 4,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'isPublic': false,
      'maxParticipants': 10,
      'scheduledStartAt': past.toUtc().toIso8601String(),
      'scheduledEndAt': past
          .add(const Duration(days: 4))
          .toUtc()
          .toIso8601String(),
    });

    expect(find.byKey(const Key('timeline-ends-row')), findsOneWidget);
    // The window is in the past, so the client names the rule rather than
    // letting the user save straight into a 400.
    expect(find.text('Pick an end time in the future'), findsOneWidget);

    await tester.tap(find.byKey(const Key('timeline-ends-row')));
    await tester.pumpAndSettle();

    // The picker opened instead of asserting.
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  // §10.1 risk 6 — a control that moves the pool must show the pool.
  testWidgets('the edit screen carries the prize plaque', (tester) async {
    final state = await _pump(tester, _RecordingApi(), race: _presetPendingRace());

    expect(find.byKey(const Key('edit-prize-pool-preview')), findsOneWidget);
    // 10 runners x 7 days (4 points) x 20 = 800.
    expect(
      tester.widget<Text>(find.byKey(const Key('edit-prize-pool-coins'))).data,
      '800',
    );

    await tester.ensureVisible(find.byKey(const Key('duration-option-1')));
    await tester.tap(find.byKey(const Key('duration-option-1')));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('edit-prize-pool-coins'))).data,
      '200',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('edit-prize-pool-derivation')))
          .data,
      '10 PLAYERS × 1 DAY',
    );

    // And it follows a CUSTOM window's DERIVED day count, not the raw hours.
    await tester.ensureVisible(find.byKey(const Key('duration-option-custom')));
    await tester.tap(find.byKey(const Key('duration-option-custom')));
    await tester.pump();
    final s = DateTime.now().add(const Duration(hours: 1));
    state.debugSetCustomWindow(start: s, end: s.add(const Duration(hours: 25)));
    await tester.pump();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('edit-prize-pool-derivation')))
          .data,
      '10 PLAYERS × 1 DAY',
    );
  });

  // A stale-but-untouched window must never hold the rest of the screen
  // hostage. This is the client twin of the backend's architect-R3 rule: a
  // PATCH that only renames a race must not be validated against a window the
  // user did not send.
  testWidgets('flag ON: a stale window does not disable SAVE', (tester) async {
    final api = _RecordingApi();
    final soon = DateTime.now().add(const Duration(hours: 10));
    await _pump(tester, api, race: {
      'id': 'race-1',
      'name': 'Nearly Due',
      'status': 'PENDING',
      'maxDurationDays': 4,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'isPublic': false,
      'maxParticipants': 10,
      // Manual start, so the window is measured against a moving `now` and has
      // quietly shrunk under the 24h floor while the race sat PENDING.
      'scheduledEndAt': soon.toUtc().toIso8601String(),
    });

    // The message still shows — it is useful information.
    expect(find.text('A race has to run at least 1 day'), findsOneWidget);

    // But the creator is not locked out of their own race.
    await tester.enterText(find.byType(TextField).first, 'Renamed Anyway');
    await tester.pump();
    final save = tester.widget<PillButton>(
      find.widgetWithText(PillButton, 'SAVE CHANGES'),
    );
    expect(
      save.onPressed,
      isNotNull,
      reason: 'a window the user never touched must not disable SAVE',
    );

    await _save(tester);

    expect(api.lastUpdate, isNotNull);
    // And the untouched window is not sent, so the server never revalidates it.
    expect(api.lastUpdate!['scheduledEndAt'], isNull);
    expect(api.lastUpdate!['scheduledStartAt'], isNull);
    expect(api.lastUpdate!['clearScheduledEndAt'], isFalse);
  });

  testWidgets('flag ON: MOVING the window into an illegal one still blocks', (
    tester,
  ) async {
    final state = await _pump(
      tester,
      _RecordingApi(),
      race: _customPendingRace(),
    );

    state.debugSetCustomWindow(
      end: _start.add(const Duration(hours: 3)),
    );
    await tester.pump();

    expect(find.text('A race has to run at least 1 day'), findsOneWidget);
    final save = tester.widget<PillButton>(
      find.widgetWithText(PillButton, 'SAVE CHANGES'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('a missing scheduledEndAt degrades to the preset chips', (
    tester,
  ) async {
    // An older backend's getRaceDetails carries neither new key.
    await _pump(tester, _RecordingApi(), race: {
      'id': 'race-1',
      'name': 'Old Payload',
      'status': 'PENDING',
      'maxDurationDays': 7,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'isPublic': false,
      'maxParticipants': 10,
    });

    expect(find.byKey(const Key('timeline-ends-row')), findsNothing);
    expect(find.byKey(const Key('duration-option-7')), findsOneWidget);
  });
}
