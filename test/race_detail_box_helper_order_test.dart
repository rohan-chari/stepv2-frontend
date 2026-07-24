import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/item_slot.dart';

/// Spec §3.2 — the "You earn a powerup every N steps … X to go" helper must
/// render ABOVE the box/item slots Row, not below it.
class _HelperApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => {
    'id': raceId,
    'name': 'Helper Alley',
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
      'activeEffects': const [],
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

Future<void> _pump(WidgetTester tester, _HelperApi api) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-helper',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('next-powerup helper renders above the box/item slots Row', (
    tester,
  ) async {
    await _pump(tester, _HelperApi());

    final helper = find.textContaining('You earn a powerup every');
    expect(helper, findsOneWidget);

    final slots = find.byType(ItemSlot);
    expect(slots, findsWidgets);

    final helperY = tester.getTopLeft(helper).dy;
    final firstSlotY = tester.getTopLeft(slots.first).dy;
    expect(
      helperY,
      lessThan(firstSlotY),
      reason: 'helper text should sit above the slots Row (spec §3.2)',
    );
  });
}
