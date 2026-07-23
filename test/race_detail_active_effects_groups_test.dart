import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// The ACTIVE EFFECTS block on the race detail screen splits into a BOOSTS
/// group (self-cast buffs + group rallies) and a DEBUFFS group (rival
/// attacks, attributed to their attacker) so a racer can tell at a glance
/// what is helping them and what is hurting them.
class _EffectsApi extends BackendApiService {
  _EffectsApi(this.activeEffects);

  final List<Map<String, dynamic>> activeEffects;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => {
    'id': raceId,
    'name': 'Effect Alley',
    'status': 'ACTIVE',
    'maxDurationDays': 7,
    'buyInAmount': 0,
    'myStatus': 'ACCEPTED',
    'powerupsEnabled': true,
    'endsAt': '2027-12-10T12:00:00.000Z',
    'participants': [
      {'userId': 'me', 'displayName': 'Bara', 'status': 'ACCEPTED'},
      {'userId': 'u1', 'displayName': 'Otter42', 'status': 'ACCEPTED'},
      {'userId': 'u2', 'displayName': 'Marmot', 'status': 'ACCEPTED'},
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
      {'userId': 'u2', 'displayName': 'Marmot', 'totalSteps': 3000},
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
        raceId: 'race-fx',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('effects on me split into BOOSTS and DEBUFFS with attribution', (
    tester,
  ) async {
    final api = _EffectsApi([
      // Self-cast buff → BOOSTS.
      {
        'type': 'RUNNERS_HIGH',
        'onSelf': true,
        'sourceUserId': 'me',
        'targetUserId': 'me',
        'expiresAt': '2027-12-01T00:00:00.000Z',
      },
      // Rival attack on me → DEBUFFS, attributed to the attacker.
      {
        'type': 'LEG_CRAMP',
        'sourceUserId': 'u1',
        'targetUserId': 'me',
        'expiresAt': '2027-12-01T00:00:00.000Z',
      },
      // Group rally cast by a rival still lands on me as a buff → BOOSTS.
      {
        'type': 'UPRISING',
        'sourceUserId': 'u1',
        'targetUserId': 'me',
        'expiresAt': '2027-12-01T00:00:00.000Z',
      },
      // Effect on someone else → not listed in my active effects at all.
      {
        'type': 'WRONG_TURN',
        'sourceUserId': 'me',
        'targetUserId': 'u2',
        'expiresAt': '2027-12-01T00:00:00.000Z',
      },
    ]);
    await _pump(tester, api);

    expect(find.text('BOOSTS'), findsOneWidget);
    expect(find.text('DEBUFFS'), findsOneWidget);

    expect(find.text("Runner's High"), findsOneWidget);
    expect(find.text('Uprising'), findsOneWidget);
    expect(find.text('Leg Cramp'), findsOneWidget);
    // Debuff subtitle leads with who did it.
    expect(find.textContaining('from @Otter42'), findsOneWidget);
    // The effect I cast on Marmot shows on their leaderboard row as an icon,
    // never as a row in my own active-effects list.
    expect(find.text('Wrong Turn'), findsNothing);
  });

  testWidgets('only-buff and only-debuff states hide the empty group', (
    tester,
  ) async {
    final api = _EffectsApi([
      {
        'type': 'LEG_CRAMP',
        'sourceUserId': 'u1',
        'targetUserId': 'me',
        'expiresAt': '2027-12-01T00:00:00.000Z',
      },
    ]);
    await _pump(tester, api);

    expect(find.text('DEBUFFS'), findsOneWidget);
    expect(find.text('BOOSTS'), findsNothing);
  });

  testWidgets(
    'rival-cast effect with onSelf:true (real backend shape) is a DEBUFF',
    (tester) async {
      // The backend sets onSelf = (targetUserId === viewer), so it is true for
      // EVERY row on me — rival attacks included. A rival-cast Rainstorm must
      // still land under DEBUFFS; classification is source-based, not onSelf.
      final api = _EffectsApi([
        {
          'type': 'RAINSTORM',
          'onSelf': true,
          'sourceUserId': 'u1',
          'targetUserId': 'me',
          'expiresAt': '2027-12-01T00:00:00.000Z',
        },
      ]);
      await _pump(tester, api);

      expect(find.text('DEBUFFS'), findsOneWidget);
      expect(find.text('BOOSTS'), findsNothing);
      expect(find.textContaining('from @Otter42'), findsOneWidget);
    },
  );

  testWidgets('no effects on me renders neither group header', (tester) async {
    final api = _EffectsApi([
      {
        'type': 'WRONG_TURN',
        'sourceUserId': 'me',
        'targetUserId': 'u2',
        'expiresAt': '2027-12-01T00:00:00.000Z',
      },
    ]);
    await _pump(tester, api);

    expect(find.text('BOOSTS'), findsNothing);
    expect(find.text('DEBUFFS'), findsNothing);
  });
}
