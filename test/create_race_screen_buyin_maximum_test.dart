import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// App-funded prize pools (spec §7.1 / D7). This file used to guard the buy-in
// CEILING (200 coins). Buy-ins are gone, so it guards the prize-pool ceiling
// instead: the pool saturates at PRIZE_POOL_MAX (3,200) and the UI must stop
// implying it keeps growing past it, while creation is never blocked.

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
    return const {'coins': 5000, 'heldCoins': 0};
  }
}

Future<AuthService> _createAuthService({int coins = 5000}) async {
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

Future<void> _selectField(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
}

Future<void> _selectDuration(WidgetTester tester, int days) async {
  final chip = find.byKey(Key('duration-option-$days'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a big-but-legal pool shows in full with no MAX tag', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _FakeBackendApiService());

    // 50 runners x 3 days -> 50 x 2 x 20 = 2,000, under the 3,200 ceiling.
    await _selectField(tester, '50');
    expect(_poolCoins(tester), '2,000');
    expect(find.byKey(const Key('create-prize-pool-max')), findsNothing);
  });

  testWidgets('the pool clamps to 3,200 and says MAX past the ceiling', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _FakeBackendApiService());

    // 50 x 7 days -> 50 x 4 x 20 = 4,000 -> clamped to 3,200.
    await _selectField(tester, '50');
    await _selectDuration(tester, 7);
    expect(_poolCoins(tester), '3,200');
    expect(find.byKey(const Key('create-prize-pool-max')), findsOneWidget);

    // Pushing further does not inflate the promise.
    await _selectField(tester, '100');
    await _selectDuration(tester, 14);
    expect(_poolCoins(tester), '3,200');
    expect(find.byKey(const Key('create-prize-pool-max')), findsOneWidget);
  });

  testWidgets('a capped race still creates, and free', (
    WidgetTester tester,
  ) async {
    final backend = _FakeBackendApiService();
    await _pump(tester, backend);

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Big Race',
    );
    await _selectField(tester, '100');
    await _selectDuration(tester, 14);

    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pumpAndSettle();

    expect(backend.lastCreateRaceCall, isNotNull);
    expect(backend.lastCreateRaceCall!['buyInAmount'], 0);
    expect(backend.lastCreateRaceCall!['maxParticipants'], 100);
    expect(backend.lastCreateRaceCall!['maxDurationDays'], 14);
  });
}
