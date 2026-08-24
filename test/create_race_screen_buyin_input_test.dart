import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// App-funded prize pools (spec §7.1 / D7). This file used to cover the buy-in
// amount field: typing coins, digit filtering, and the affordability guard.
// There is no amount to type any more — the pool is derived from the race's own
// shape and paid by the app — so the same screen is covered here through the
// derived figure instead.

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
    DateTime? scheduledEndAt,
  }) async {
    lastCreateRaceCall = {
      'identityToken': identityToken,
      'name': name,
      'maxDurationDays': maxDurationDays,
      'powerupsEnabled': powerupsEnabled,
      'powerupStepInterval': powerupStepInterval,
      'buyInAmount': buyInAmount,
      'payoutPreset': payoutPreset,
      'isPublic': isPublic,
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

Future<AuthService> _createAuthService({int coins = 420}) async {
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

Future<void> _pump(
  WidgetTester tester,
  BackendApiService api, {
  int coins = 420,
}) async {
  final authService = await _createAuthService(coins: coins);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('there is no buy-in amount field to type into', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _FakeBackendApiService());

    // The race name is the only thing left to type on this screen.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('BUY-IN'), findsNothing);
    expect(find.text('BUY-IN PER RUNNER'), findsNothing);
  });

  testWidgets('the prize pool is derived from the race, not entered', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackendApiService();
    await _pump(tester, backend, coins: 5000);

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Gold Rush',
    );

    // The app funds the prize pool; no client-entered pool is rendered.
    expect(find.byKey(const Key('create-prize-pool-coins')), findsNothing);

    // Growing the field remains available, with no coin input anywhere.
    await tester.ensureVisible(find.text('25'));
    await tester.tap(find.text('25'));
    await tester.pump();
    expect(find.byKey(const Key('create-prize-pool-coins')), findsNothing);

    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CREATE RACE'));
    await tester.pumpAndSettle();

    expect(backend.lastCreateRaceCall, isNotNull);
    // Nothing is staked — the server funds the pool.
    expect(backend.lastCreateRaceCall!['buyInAmount'], 0);
    expect(backend.lastCreateRaceCall!['maxParticipants'], 25);
  });

  testWidgets('creation is never blocked by the player coin balance', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackendApiService();
    await _pump(tester, backend, coins: 0);

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Gold Rush',
    );
    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pumpAndSettle();

    expect(backend.lastCreateRaceCall, isNotNull);
    expect(
      find.text('You do not have enough gold for this buy-in'),
      findsNothing,
    );
  });
}
