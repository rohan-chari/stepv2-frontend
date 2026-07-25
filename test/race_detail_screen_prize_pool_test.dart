import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// App-funded prize pools on the race detail screen (spec §7.2 / §9).
//
// The contract (§5.1) is additive: a funded race carries a `prizePool` object
// and `buyInAmount: 0`. A backend OLDER than this build sends no `prizePool` at
// all, and then the screen must render exactly today's buy-in / POT UI.

Map<String, dynamic> _fundedRace({
  String status = 'ACTIVE',
  String myStatus = 'ACCEPTED',
  bool projected = true,
  bool atMax = false,
  int coins = 160,
}) => {
  'id': 'race-1',
  'name': 'Free Ride',
  'status': status,
  'maxDurationDays': 3,
  'buyInAmount': 0,
  'payoutPreset': 'TOP3_70_20_10',
  'potCoins': 0,
  'heldPotCoins': 0,
  'projectedPotCoins': coins,
  'prizePool': {
    'coins': coins,
    'projected': projected,
    'atMax': atMax,
    'playerCount': 4,
    'durationDays': 3,
    'durationPoints': 2,
    'coinUnit': 20,
    'maxCoins': 3200,
    'funded': true,
  },
  'payoutTiers': const [
    {'placement': 1, 'amount': 112},
    {'placement': 2, 'amount': 32},
    {'placement': 3, 'amount': 16},
  ],
  'myStatus': myStatus,
  'isCreator': false,
  'powerupsEnabled': false,
  'endsAt': '2126-04-10T12:00:00.000Z',
  'participants': const [
    {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
    {'userId': 'user-2', 'displayName': 'Hill Climber', 'status': 'ACCEPTED'},
  ],
};

Map<String, dynamic> _legacyPaidRace() => {
  'id': 'race-1',
  'name': 'Gold Sprint',
  'status': 'PENDING',
  'maxDurationDays': 7,
  'buyInAmount': 100,
  'payoutPreset': 'TOP3_70_20_10',
  'potCoins': 300,
  'heldPotCoins': 0,
  'projectedPotCoins': 300,
  'payouts': const {'first': 210, 'second': 60, 'third': 30},
  'myStatus': 'ACCEPTED',
  'isCreator': false,
  'powerupsEnabled': false,
  'endsAt': '2126-04-10T12:00:00.000Z',
  'participants': const [
    {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
    {'userId': 'user-2', 'displayName': 'Hill Climber', 'status': 'ACCEPTED'},
  ],
};

class _StubApi extends BackendApiService {
  _StubApi(this.race);

  final Map<String, dynamic> race;
  int respondCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async => race;

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => {
    'status': race['status'],
    'participants': const [
      {
        'userId': 'user-1',
        'displayName': 'Trail Walker',
        'totalSteps': 4200.0,
        'finishedAt': null,
      },
      {
        'userId': 'user-2',
        'displayName': 'Hill Climber',
        'totalSteps': 3800.0,
        'finishedAt': null,
      },
    ],
    'powerupData': const {
      'enabled': false,
      'inventory': [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': [],
    },
  };

  @override
  Future<Map<String, dynamic>> fetchRaceFeed({
    String? cursor,
    required String identityToken,
    required String raceId,
  }) async => const {'events': []};

  @override
  Future<Map<String, dynamic>> respondToRaceInvite({
    required String identityToken,
    required String raceId,
    required bool accept,
  }) async {
    respondCalls += 1;
    return {
      'participant': {'id': 'rp-1', 'status': accept ? 'ACCEPTED' : 'DECLINED'},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 0, 'heldCoins': 0};
}

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

Future<void> _pump(WidgetTester tester, _StubApi api) async {
  final authService = await _authService();
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: authService,
        raceId: 'race-1',
        backendApiService: api,
      ),
    ),
  );
  // Bounded pumps: the hero's spinning coin animates forever, so the tree
  // never fully settles.
  await tester.pump();
  await tester.pump();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a funded race shows a PROJECTED prize pool and the funder line', (
    tester,
  ) async {
    await _pump(tester, _StubApi(_fundedRace(status: 'PENDING')));

    final stat = find.byKey(const Key('race-info-prize-pool'));
    expect(stat, findsOneWidget);
    expect(
      find.descendant(of: stat, matching: find.text('160')),
      findsOneWidget,
    );
    // A pre-settlement pool is a projection, never a promise.
    expect(find.byKey(const Key('race-prize-pool-projected')), findsOneWidget);
    expect(
      find.byKey(const Key('race-prize-pool-funded-copy')),
      findsOneWidget,
    );
    // No buy-in / pot language survives on a funded race.
    expect(find.text('BUY-IN'), findsNothing);
    expect(find.text('POT'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('the funded pool chip opens the payout breakdown', (tester) async {
    await _pump(tester, _StubApi(_fundedRace()));

    final board = find.byKey(const Key('race-prize-pool-board'));
    expect(board, findsOneWidget);

    await tester.tap(board);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final summary = find.byKey(const Key('race-prize-pool-summary'));
    expect(summary, findsOneWidget);
    expect(
      find.descendant(of: summary, matching: find.text('1ST')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('112')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('race-prize-pool-sheet-projected')),
      findsOneWidget,
    );

    await _teardown(tester);
  });

  testWidgets('a settled pool drops the PROJECTED tag', (tester) async {
    await _pump(
      tester,
      _StubApi(_fundedRace(status: 'COMPLETED', projected: false)),
    );

    // A finished funded race still shows what it paid — just not as a guess.
    final board = find.byKey(const Key('race-prize-pool-board'));
    expect(board, findsOneWidget);
    await tester.tap(board);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('race-prize-pool-summary')), findsOneWidget);
    expect(
      find.byKey(const Key('race-prize-pool-sheet-projected')),
      findsNothing,
    );

    await _teardown(tester);
  });

  testWidgets('a capped pool says MAX instead of implying more growth', (
    tester,
  ) async {
    await _pump(
      tester,
      _StubApi(_fundedRace(status: 'PENDING', atMax: true, coins: 3200)),
    );

    expect(find.byKey(const Key('race-prize-pool-max')), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets(
    'an OLDER backend (no prizePool) still renders the buy-in / POT UI',
    (tester) async {
      await _pump(tester, _StubApi(_legacyPaidRace()));

      // Exactly today's stats — the build must not depend on the new field.
      expect(find.text('BUY-IN'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('POT'), findsOneWidget);
      // 300 shows twice: the POT stat and the hero prize chip.
      expect(find.text('300'), findsWidgets);
      expect(find.byKey(const Key('race-info-prize-pool')), findsNothing);
      expect(find.byKey(const Key('race-prize-pool-projected')), findsNothing);
      // The hero prize chip still shows for a legacy paid race.
      expect(find.byKey(const Key('race-prize-pool-board')), findsOneWidget);

      await _teardown(tester);
    },
  );

  testWidgets('accepting an invite to a funded race is one tap — no buy-in sheet',
      (tester) async {
    final api = _StubApi(
      _fundedRace(status: 'PENDING', myStatus: 'INVITED'),
    );
    await _pump(tester, api);

    expect(find.text('ACCEPT'), findsOneWidget);
    await tester.ensureVisible(find.text('ACCEPT'));
    await tester.pump();
    await tester.tap(find.text('ACCEPT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('GOLD BUY-IN'), findsNothing);
    expect(find.text('LOCK IT IN'), findsNothing);
    expect(api.respondCalls, 1);

    await _teardown(tester);
  });
}
