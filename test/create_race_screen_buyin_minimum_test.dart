import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// App-funded prize pools (spec §7.1 / D7). This file used to guard the buy-in
// FLOOR (the server's 10-coin minimum). There is no buy-in any more, so it
// guards the bottom of the prize-pool range instead: the smallest race a player
// can set up still previews a real pool, and it is never blocked from creation.

class _FakeBackendApiService extends BackendApiService {
  Map<String, dynamic>? lastCreateRaceCall;

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
      'buyInAmount': buyInAmount,
      'maxDurationDays': maxDurationDays,
      'maxParticipants': maxParticipants,
    };
    return {
      'race': {'id': 'race-1', 'name': name},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 320, 'heldCoins': 0};
  }
}

Future<AuthService> _createAuthService({int coins = 1000}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': coins,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pump(WidgetTester tester, BackendApiService api) async {
  final authService = await _createAuthService();
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

String _poolCoins(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('create-prize-pool-coins')))
    .data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the smallest race still previews a real pool', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _FakeBackendApiService());

    // Smallest field, shortest race: 5 runners x 1 day -> 5 x 1 x 20 = 100.
    await tester.ensureVisible(find.text('5'));
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('duration-option-1')));
    await tester.tap(find.byKey(const Key('duration-option-1')));
    await tester.pump();

    expect(_poolCoins(tester), '100');
    // A floor pool is not a maxed pool.
    expect(find.byKey(const Key('create-prize-pool-max')), findsNothing);
  });

  testWidgets('a floor-sized race creates with no charge', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackendApiService();
    await _pump(tester, backend);

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Tiny Race',
    );
    await tester.ensureVisible(find.text('5'));
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('duration-option-1')));
    await tester.tap(find.byKey(const Key('duration-option-1')));
    await tester.pump();

    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pumpAndSettle();

    expect(backend.lastCreateRaceCall, isNotNull);
    expect(backend.lastCreateRaceCall!['buyInAmount'], 0);
    expect(backend.lastCreateRaceCall!['maxDurationDays'], 1);
    expect(backend.lastCreateRaceCall!['maxParticipants'], 5);
  });
}
