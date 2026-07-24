import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// A Piggy Bank the viewer owns shows a live "banked so far" counter in the
/// ACTIVE EFFECTS row subtitle, driven by the optional `piggyBank` field the
/// backend attaches to the owner's own entry. When that field is absent or
/// malformed — the shape an older backend serves — the row degrades to the
/// existing static "Banking steps for coins" copy without crashing.
class _EffectsApi extends BackendApiService {
  _EffectsApi(this.activeEffects);

  final List<Map<String, dynamic>> activeEffects;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => {
    'id': raceId,
    'name': 'Piggy Alley',
    'status': 'ACTIVE',
    'maxDurationDays': 7,
    'buyInAmount': 0,
    'myStatus': 'ACCEPTED',
    'powerupsEnabled': true,
    'endsAt': '2027-12-10T12:00:00.000Z',
    'participants': [
      {'userId': 'me', 'displayName': 'Bara', 'status': 'ACCEPTED'},
      {'userId': 'u1', 'displayName': 'Otter42', 'status': 'ACCEPTED'},
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': 'ACTIVE',
    'participants': [
      {'userId': 'me', 'displayName': 'Bara', 'totalSteps': 5000},
      {'userId': 'u1', 'displayName': 'Otter42', 'totalSteps': 4000},
    ],
    'powerupData': {
      'enabled': true,
      'inventory': const [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': activeEffects,
      'powerupStepInterval': 5000,
      'stepsUntilNextPowerup': 1000,
    },
  };

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async => const {'events': []};

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 300, 'heldCoins': 0};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Bara',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester, _EffectsApi api) async {
  await tester.binding.setSurfaceSize(const Size(430, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-piggy',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('owned Piggy Bank with piggyBank field shows banked counter', (
    tester,
  ) async {
    final api = _EffectsApi([
      {
        'type': 'PIGGY_BANK',
        'onSelf': true,
        'sourceUserId': 'me',
        'targetUserId': 'me',
        'expiresAt': '2027-12-01T00:00:00.000Z',
        'piggyBank': {'bankedCoins': 13, 'coinCap': 80, 'windowSteps': 3926},
      },
    ]);
    await _pump(tester, api);

    expect(find.text('Piggy Bank'), findsOneWidget);
    expect(find.text('Banked 13/80 coins'), findsOneWidget);
    // The static fallback copy must NOT appear when live data is present.
    expect(find.text('Banking steps for coins'), findsNothing);
  });

  testWidgets('Piggy Bank without piggyBank field falls back to static copy', (
    tester,
  ) async {
    final api = _EffectsApi([
      {
        'type': 'PIGGY_BANK',
        'onSelf': true,
        'sourceUserId': 'me',
        'targetUserId': 'me',
        'expiresAt': '2027-12-01T00:00:00.000Z',
      },
    ]);
    await _pump(tester, api);

    expect(find.text('Piggy Bank'), findsOneWidget);
    expect(find.text('Banking steps for coins'), findsOneWidget);
    expect(find.textContaining('Banked'), findsNothing);
  });

  testWidgets('Piggy Bank with malformed piggyBank falls back to static copy', (
    tester,
  ) async {
    final api = _EffectsApi([
      {
        'type': 'PIGGY_BANK',
        'onSelf': true,
        'sourceUserId': 'me',
        'targetUserId': 'me',
        'expiresAt': '2027-12-01T00:00:00.000Z',
        'piggyBank': {'bankedCoins': null},
      },
    ]);
    await _pump(tester, api);

    expect(find.text('Piggy Bank'), findsOneWidget);
    expect(find.text('Banking steps for coins'), findsOneWidget);
    expect(find.textContaining('Banked'), findsNothing);
  });
}
