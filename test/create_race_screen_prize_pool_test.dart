import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/create_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// App-funded prize pools, create screen (spec §7.1 / §9 "create_race_screen").
// Buy-ins are gone: the screen previews the app-funded pool live from the
// duration + max-players controls, and the duration picker lands on band
// boundaries [1,3,7,14].

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

String _previewCoins(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('create-prize-pool-coins')))
    .data!;

String _previewDerivation(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('create-prize-pool-derivation')))
    .data!;

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

  testWidgets('duration options are [1,3,7,14] — the band boundaries (D3)', (
    tester,
  ) async {
    await _pump(tester, _RecordingApi());

    for (final days in [1, 3, 7, 14]) {
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

  testWidgets('the pool preview tracks duration and matches the fixtures', (
    tester,
  ) async {
    await _pump(tester, _RecordingApi());

    expect(_preview(), findsOneWidget);
    expect(find.text('PRIZE POOL'), findsOneWidget);

    // Defaults: 10 max runners, 3 days -> 10 x 2 x 20 = 400.
    expect(_previewCoins(tester), '400');
    expect(_previewDerivation(tester), '10 PLAYERS × 3 DAYS');

    // Owner fixture: 10 players / 7 days = 800.
    await _tapDuration(tester, 7);
    expect(_previewCoins(tester), '800');
    expect(_previewDerivation(tester), '10 PLAYERS × 7 DAYS');

    // 1 day -> 1 point.
    await _tapDuration(tester, 1);
    expect(_previewCoins(tester), '200');
    expect(_previewDerivation(tester), '10 PLAYERS × 1 DAY');

    // 14 days -> 8 points.
    await _tapDuration(tester, 14);
    expect(_previewCoins(tester), '1,600');
  });

  testWidgets('the pool preview tracks the max-runners selection', (
    tester,
  ) async {
    await _pump(tester, _RecordingApi());

    await tester.ensureVisible(find.text('25'));
    await tester.tap(find.text('25'));
    await tester.pump();

    // 25 x 2 (3 days) x 20 = 1,000.
    expect(_previewCoins(tester), '1,000');
    expect(_previewDerivation(tester), '25 PLAYERS × 3 DAYS');
  });

  testWidgets('the preview saturates at the cap and says so', (tester) async {
    await _pump(tester, _RecordingApi());

    expect(find.byKey(const Key('create-prize-pool-max')), findsNothing);

    await tester.ensureVisible(find.text('100'));
    await tester.tap(find.text('100'));
    await tester.pump();
    await _tapDuration(tester, 14);

    // 100 x 8 x 20 = 16,000 -> clamped to 3,200.
    expect(_previewCoins(tester), '3,200');
    expect(find.byKey(const Key('create-prize-pool-max')), findsOneWidget);
  });

  testWidgets('NO LIMIT previews the capped pool', (tester) async {
    await _pump(tester, _RecordingApi());

    await tester.ensureVisible(find.text('NO LIMIT'));
    await tester.tap(find.text('NO LIMIT'));
    await tester.pump();

    expect(_previewCoins(tester), '3,200');
    expect(find.byKey(const Key('create-prize-pool-max')), findsOneWidget);
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
