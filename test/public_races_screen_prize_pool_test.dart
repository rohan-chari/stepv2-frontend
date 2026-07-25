import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/public_races_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// App-funded prize pools on the public races board (spec §7.3 / §9).
// The BUY-IN stat becomes PRIZE, read from `prizePool.coins` and falling back
// to `projectedPotCoins` when the backend predates the object. Joining is one
// tap — nothing is charged.

class _Api extends BackendApiService {
  _Api(this.races);

  final List<Map<String, dynamic>> races;
  bool joined = false;

  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async => races;

  @override
  Future<Map<String, dynamic>> joinPublicRace({
    required String identityToken,
    required String raceId,
    bool onboarding = false,
  }) async {
    joined = true;
    return {
      'participant': {'id': 'rp-1', 'raceId': raceId},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 0, 'heldCoins': 0};
}

Map<String, dynamic> _fundedRace() => {
  'id': 'race-1',
  'name': 'Free Ride',
  'participantCount': 3,
  'maxParticipants': 10,
  'maxDurationDays': 3,
  'buyInAmount': 0,
  'projectedPotCoins': 120,
  'prizePool': const {
    'coins': 120,
    'projected': true,
    'atMax': false,
    'playerCount': 3,
    'durationDays': 3,
    'durationPoints': 2,
    'coinUnit': 20,
    'maxCoins': 3200,
    'funded': true,
  },
  'creator': const {'displayName': 'RaceMaker'},
  'powerupsEnabled': false,
};

/// A backend older than this build: no `prizePool`, but a projected pot.
Map<String, dynamic> _legacyRace() => {
  'id': 'race-2',
  'name': 'Gold Sprint',
  'participantCount': 3,
  'maxParticipants': 10,
  'maxDurationDays': 7,
  'buyInAmount': 100,
  'projectedPotCoins': 300,
  'creator': const {'displayName': 'RaceMaker'},
  'powerupsEnabled': false,
};

Future<AuthService> _authService() async {
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
  return authService;
}

Future<void> _pump(WidgetTester tester, _Api api) async {
  final authService = await _authService();
  await tester.pumpWidget(
    MaterialApp(
      home: PublicRacesScreen(
        authService: authService,
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a funded race card shows PRIZE from the pool, not a buy-in', (
    tester,
  ) async {
    await _pump(tester, _Api([_fundedRace()]));

    expect(find.text('PRIZE'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('BUY-IN'), findsNothing);
  });

  testWidgets('an older backend falls back to the projected pot', (
    tester,
  ) async {
    await _pump(tester, _Api([_legacyRace()]));

    expect(find.text('PRIZE'), findsOneWidget);
    expect(find.text('300'), findsOneWidget);
    expect(find.text('BUY-IN'), findsNothing);
  });

  testWidgets('joining a funded race is one tap with no confirm sheet', (
    tester,
  ) async {
    final api = _Api([_fundedRace()]);
    await _pump(tester, api);

    await tester.tap(find.text('JOIN'));
    await tester.pumpAndSettle();

    expect(find.textContaining('GOLD BUY-IN'), findsNothing);
    expect(find.text('LOCK IT IN'), findsNothing);
    expect(api.joined, isTrue);
  });

  testWidgets('a broke player can still join a funded race', (tester) async {
    final api = _Api([_fundedRace()]);
    await _pump(tester, api);

    await tester.tap(find.text('JOIN'));
    await tester.pumpAndSettle();

    expect(find.text('Not enough gold for this buy-in'), findsNothing);
    expect(api.joined, isTrue);
  });
}
