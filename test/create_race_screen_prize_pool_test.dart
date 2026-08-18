import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// App-funded creation, real screen. Payout totals are server-owned after
// creation, so the form deliberately omits a local projection; the timeline
// still lands on band boundaries [1,7,14] (3 remains legal for frozen apps).

class _RecordingApi extends BackendApiService {
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
      'name': name,
      'maxDurationDays': maxDurationDays,
      'buyInAmount': buyInAmount,
      'payoutPreset': payoutPreset,
      'maxParticipants': maxParticipants,
    };
    return {
      'race': {'id': 'race-1', 'name': name},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 0, 'heldCoins': 0};
  }
}

Future<AuthService> _authService({int coins = 0}) async {
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
  bool expanded = true,
  int coins = 0,
}) async {
  final authService = await _authService(coins: coins);
  await tester.pumpWidget(
    MaterialApp(
      home: CreateRaceScreen(
        authService: authService,
        backendApiService: api,
        initialCustomizeExpanded: expanded,
      ),
    ),
  );
  await tester.pump();
}

Finder _preview() => find.byKey(const Key('create-prize-pool-preview'));

Future<void> _tapDuration(WidgetTester tester, int days) async {
  final chip = find.byKey(Key('duration-option-$days'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the buy-in controls are gone entirely', (tester) async {
    await _pump(tester, _RecordingApi());

    expect(find.text('BUY-IN'), findsNothing);
    expect(find.text('BUY-IN PER RUNNER'), findsNothing);
    expect(find.text('PAID RACE'), findsNothing);
    expect(find.text('FREE RACE'), findsNothing);
    // Only the race-name field remains — no amount field to type coins into.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('duration options are [1,7,14] — the band boundaries (D3)', (
    tester,
  ) async {
    await _pump(tester, _RecordingApi());

    for (final days in [1, 7, 14]) {
      expect(
        find.byKey(Key('duration-option-$days')),
        findsOneWidget,
        reason: '${days}d must be offered',
      );
    }
    // The off-band 5-day option is retired.
    expect(find.byKey(const Key('duration-option-5')), findsNothing);
    expect(find.text('5d'), findsNothing);
  });

  testWidgets('new race creation omits a locally derived payout total', (
    tester,
  ) async {
    await _pump(tester, _RecordingApi());

    // v1 pays per eligible recipient. Until the backend knows the final
    // recipient count, a locally computed pool could contradict its rounded
    // payout tiers, so the creation form intentionally has no total.
    expect(_preview(), findsNothing);
    expect(find.byKey(const Key('create-prize-pool-coins')), findsNothing);
    expect(find.byKey(const Key('create-prize-pool-derivation')), findsNothing);
    expect(find.byKey(const Key('create-prize-pool-max')), findsNothing);

    // Controls remain usable; omitting the numerical preview must not remove
    // or leave a blank replacement for the timeline flow.
    await _tapDuration(tester, 14);
    await _tapDuration(tester, 1);
    expect(find.byKey(const Key('duration-option-1')), findsOneWidget);
    expect(find.byKey(const Key('customize-race-toggle')), findsOneWidget);
    expect(_preview(), findsNothing);
  });

  testWidgets(
    'payout mode is pickable without a buy-in and is sent on create',
    (tester) async {
      final api = _RecordingApi();
      await _pump(tester, api);

      // The picker is no longer hidden behind a buy-in toggle.
      expect(find.text('PAYOUT MODE'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('race-name-field')),
        'Free Ride',
      );
      await tester.ensureVisible(find.text('TOP 3'));
      await tester.tap(find.text('TOP 3'));
      await tester.pump();

      await tester.ensureVisible(find.text('CREATE RACE'));
      await tester.tap(find.text('CREATE RACE'));
      await tester.pumpAndSettle();

      expect(api.lastCreateRaceCall, isNotNull);
      expect(api.lastCreateRaceCall!['payoutPreset'], 'TOP3_70_20_10');
      // Entry is free, always — nothing is ever charged.
      expect(api.lastCreateRaceCall!['buyInAmount'], 0);
    },
  );

  testWidgets('a broke player can still create a race', (tester) async {
    final api = _RecordingApi();
    await _pump(tester, api, coins: 0);

    await tester.enterText(
      find.byKey(const Key('race-name-field')),
      'Penniless Dash',
    );
    await tester.ensureVisible(find.text('CREATE RACE'));
    await tester.tap(find.text('CREATE RACE'));
    await tester.pumpAndSettle();

    expect(api.lastCreateRaceCall, isNotNull);
    expect(api.lastCreateRaceCall!['buyInAmount'], 0);
  });
}
