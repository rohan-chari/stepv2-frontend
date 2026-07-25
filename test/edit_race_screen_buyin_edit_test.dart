import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/edit_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// App-funded prize pools (spec §7 / D7). This file used to assert that the
// owner could edit a race's buy-in. Buy-ins are gone: there is no buy-in card,
// nothing is ever charged or refunded when a race is edited, and the PATCH
// carries no buy-in field. What the owner still controls is how the funded pool
// is split — the payout mode.

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
  }) async {
    lastUpdate = {
      'buyInAmount': buyInAmount,
      'payoutPreset': payoutPreset,
      'maxDurationDays': maxDurationDays,
    };
    return {
      'race': {'id': raceId},
    };
  }
}

/// A funded race with runners already in it (contract §5.1: `buyInAmount: 0`,
/// nothing held).
Map<String, dynamic> _fundedRace() => {
  'id': 'race-1',
  'name': 'Free Ride',
  'status': 'PENDING',
  'maxDurationDays': 3,
  'buyInAmount': 0,
  'payoutPreset': 'WINNER_TAKES_ALL',
  'isPublic': false,
  'maxParticipants': 10,
  'prizePool': const {
    'coins': 400,
    'projected': true,
    'atMax': false,
    'playerCount': 2,
    'durationDays': 3,
    'durationPoints': 2,
    'coinUnit': 20,
    'maxCoins': 3200,
    'funded': true,
  },
  'participants': const [
    {'userId': 'u1', 'status': 'ACCEPTED', 'buyInStatus': 'NONE'},
    {'userId': 'u2', 'status': 'ACCEPTED', 'buyInStatus': 'NONE'},
  ],
};

/// A race from a backend older than this build: no `prizePool` at all.
Map<String, dynamic> _legacyRace() => {
  'id': 'race-1',
  'name': 'Coin Clash',
  'status': 'PENDING',
  'maxDurationDays': 7,
  'buyInAmount': 100,
  'payoutPreset': 'WINNER_TAKES_ALL',
  'isPublic': false,
  'maxParticipants': 10,
  'participants': const [
    {'userId': 'u1', 'status': 'ACCEPTED', 'buyInStatus': 'HELD'},
  ],
};

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pump(
  WidgetTester tester,
  BackendApiService api, {
  Map<String, dynamic>? race,
}) async {
  final authService = await _authService();
  await tester.pumpWidget(
    MaterialApp(
      home: EditRaceScreen(
        authService: authService,
        backendApiService: api,
        raceId: 'race-1',
        race: race ?? _fundedRace(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the buy-in card is gone', (tester) async {
    await _pump(tester, _RecordingApi());

    expect(find.text('BUY-IN'), findsNothing);
    expect(find.text('BUY-IN PER RUNNER'), findsNothing);
    expect(find.text('PAID RACE'), findsNothing);
    expect(find.byKey(const Key('edit-buyin-input')), findsNothing);
    // No coins move on an edit any more, so there is nothing to warn about.
    expect(find.byKey(const Key('edit-buyin-consequence')), findsNothing);
    expect(find.textContaining('refunds or re-charges'), findsNothing);
    // Only the race-name field remains.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the buy-in card is gone for a legacy paid race too', (
    tester,
  ) async {
    await _pump(tester, _RecordingApi(), race: _legacyRace());

    expect(find.byKey(const Key('edit-buyin-input')), findsNothing);
    expect(find.text('BUY-IN PER RUNNER'), findsNothing);
  });

  testWidgets('saving sends no buy-in field', (tester) async {
    final api = _RecordingApi();
    await _pump(tester, api);

    // Change something real so the sparse PATCH actually fires.
    await tester.ensureVisible(find.byKey(const Key('duration-option-7')));
    await tester.tap(find.byKey(const Key('duration-option-7')));
    await tester.pump();

    await tester.ensureVisible(find.text('SAVE CHANGES'));
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pump();
    await tester.pump();

    expect(api.lastUpdate, isNotNull);
    expect(api.lastUpdate!['maxDurationDays'], 7);
    expect(api.lastUpdate!['buyInAmount'], isNull);
  });

  testWidgets('the payout mode is still editable and is PATCHed', (
    tester,
  ) async {
    final api = _RecordingApi();
    await _pump(tester, api);

    expect(find.text('PAYOUT MODE'), findsOneWidget);

    await tester.ensureVisible(find.text('TOP 3'));
    await tester.tap(find.text('TOP 3'));
    await tester.pump();

    await tester.ensureVisible(find.text('SAVE CHANGES'));
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pump();
    await tester.pump();

    expect(api.lastUpdate, isNotNull);
    expect(api.lastUpdate!['payoutPreset'], 'TOP3_70_20_10');
    expect(api.lastUpdate!['buyInAmount'], isNull);
  });

  testWidgets('duration options land on the prize-pool bands', (tester) async {
    await _pump(tester, _RecordingApi());

    for (final days in [1, 3, 7, 14]) {
      expect(find.byKey(Key('duration-option-$days')), findsOneWidget);
    }
    expect(find.byKey(const Key('duration-option-5')), findsNothing);
  });
}
