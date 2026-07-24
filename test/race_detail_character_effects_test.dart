import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Spec §4.4 — the race-detail effects rail renders additive `characterBonus`
/// (herd bonus) and `zoomies` (active 3x window) chips from the viewer's own
/// participant on the progress payload. Both degrade safely when absent: an
/// older backend omits them and the rail renders nothing new.
class _CharacterApi extends BackendApiService {
  _CharacterApi({this.characterBonus, this.zoomies});

  final Map<String, dynamic>? characterBonus;
  final Map<String, dynamic>? zoomies;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => {
    'id': raceId,
    'name': 'Herd Alley',
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
  }) async {
    final me = <String, dynamic>{
      'userId': 'me',
      'displayName': 'Bara',
      'totalSteps': 5000,
    };
    if (characterBonus != null) me['characterBonus'] = characterBonus;
    if (zoomies != null) me['zoomies'] = zoomies;
    return {
      'status': 'ACTIVE',
      'participants': [
        me,
        {'userId': 'u1', 'displayName': 'Otter42', 'totalSteps': 4000},
      ],
      'powerupData': {
        'enabled': true,
        'inventory': const [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': const [],
        'powerupStepInterval': 5000,
        'stepsUntilNextPowerup': 1000,
      },
    };
  }

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

Future<void> _pump(WidgetTester tester, _CharacterApi api) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-herd',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('herd bonus chip renders from characterBonus block', (
    tester,
  ) async {
    await _pump(
      tester,
      _CharacterApi(
        characterBonus: const {
          'animal': 'capybara',
          'perDay': 300,
          'bonusSteps': 900,
        },
      ),
    );

    expect(find.text('Herd Bonus'), findsOneWidget);
    // Per-day rate is surfaced so the racer can see why their total grew.
    expect(find.textContaining('300'), findsWidgets);
  });

  testWidgets('active zoomies chip renders as a 3x hype moment', (tester) async {
    await _pump(
      tester,
      _CharacterApi(
        zoomies: const {'active': true, 'endsAt': '2027-12-01T00:00:00.000Z'},
      ),
    );

    expect(find.text('Zoomies'), findsOneWidget);
    expect(find.textContaining('3x'), findsWidgets);
  });

  testWidgets('inactive zoomies renders no chip', (tester) async {
    await _pump(
      tester,
      _CharacterApi(zoomies: const {'active': false}),
    );

    expect(find.text('Zoomies'), findsNothing);
  });

  testWidgets('absent character fields render nothing (old-backend safe)', (
    tester,
  ) async {
    await _pump(tester, _CharacterApi());

    expect(find.text('Herd Bonus'), findsNothing);
    expect(find.text('Zoomies'), findsNothing);
    // With no powerup effects and no character powers, the ACTIVE EFFECTS
    // block stays collapsed entirely.
    expect(find.text('ACTIVE EFFECTS'), findsNothing);
  });
}
