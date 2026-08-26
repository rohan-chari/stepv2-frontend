import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/edit_race_screen.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/race_payout_scorecard.dart';

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
    int? participantsLimit,
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
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async => const {'messages': [], 'nextCursor': null};

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
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('projected viewer payout names the coin unit', (tester) async {
    final race = _fundedRace(status: 'ACTIVE');
    race['payoutTiers'] = const [
      {'placement': 11, 'amount': 10},
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RacePayoutScorecard(
            presentation: RacePayoutPresentation.fromRace(
              race,
              viewerPlacement: 11,
            ),
            onOpenPayouts: null,
          ),
        ),
      ),
    );

    expect(find.text('YOU: 11TH · 10 COINS PROJECTED'), findsOneWidget);
  });

  testWidgets('compact payout row fits a narrow phone with larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 600),
            textScaler: TextScaler.linear(1.4),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                // The real 320px RaceDetailScreen leaves 276px after its
                // section margin and compact card padding.
                width: 276,
                child: RacePayoutScorecard(
                  presentation: RacePayoutPresentation.fromRace(
                    _fundedRace(status: 'PENDING'),
                  ),
                  onOpenPayouts: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final payouts = find.byKey(const Key('race-payouts-open'));
    expect(payouts, findsOneWidget);
    expect(tester.getSize(payouts).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a funded race shows a PROJECTED prize pool, no funder line', (
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
    // Item 8 (batch 2026-07-27): the "Funded by Bara — free to enter" lead-in
    // was removed on purpose; only actionable copy survives.
    expect(find.byKey(const Key('race-prize-pool-funded-copy')), findsNothing);
    // No buy-in / pot language survives on a funded race.
    expect(find.text('BUY-IN'), findsNothing);
    expect(find.text('POT'), findsNothing);

    final duration = find.text('DURATION');
    final payouts = find.byKey(const Key('race-payouts-open'));
    expect(payouts, findsOneWidget);
    expect(
      (tester.getCenter(duration).dy - tester.getCenter(payouts).dy).abs(),
      lessThan(12),
    );
    expect(
      tester.getTopLeft(payouts).dx,
      greaterThan(tester.getTopRight(stat).dx),
    );

    await _teardown(tester);
  });

  testWidgets('a valid funded zero-coin pool remains funded and visible', (
    tester,
  ) async {
    await _pump(tester, _StubApi(_fundedRace(status: 'PENDING', coins: 0)));

    final stat = find.byKey(const Key('race-info-prize-pool'));
    expect(stat, findsOneWidget);
    expect(find.descendant(of: stat, matching: find.text('0')), findsOneWidget);
    expect(find.byKey(const Key('race-prize-pool-board')), findsOneWidget);
    expect(find.text('BUY-IN'), findsNothing);
    expect(find.text('POT'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('the funded pool chip opens the payout breakdown', (
    tester,
  ) async {
    await _pump(tester, _StubApi(_fundedRace()));

    final board = find.byKey(const Key('race-prize-pool-board'));
    expect(board, findsOneWidget);

    await tester.tap(board);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final list = find.byKey(const Key('race-prize-pool-tier-list'));
    expect(list, findsOneWidget);
    expect(
      find.descendant(of: list, matching: find.text('1ST')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: list, matching: find.text('112')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('race-prize-pool-sheet-projected')),
      findsOneWidget,
    );

    await _teardown(tester);
  });

  testWidgets('a funded TEAM race sheet says the winning team splits the pool '
      'and drops the 1ST tier row', (tester) async {
    final race = _fundedRace(coins: 800)
      ..['isTeamRace'] = true
      ..['teamSize'] = 2
      ..['payoutTiers'] = const [
        {'placement': 1, 'amount': 800},
      ]
      ..['participants'] = const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
          'team': 'TEAM_A',
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'status': 'ACCEPTED',
          'team': 'TEAM_B',
        },
      ];
    await _pump(tester, _StubApi(race));

    final board = find.byKey(const Key('race-prize-pool-board'));
    expect(board, findsOneWidget);
    await tester.tap(board);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The sheet must say how a team pool pays out — split evenly across the
    // winning team, matching backend settlement (completeRace TR-502/503/504).
    // One short line only: the solo growth note is dropped for team races.
    expect(find.byKey(const Key('race-prize-pool-team-split')), findsOneWidget);
    expect(
      find.text('The winning team splits the whole pool evenly.'),
      findsOneWidget,
    );
    expect(find.textContaining('The pool grows'), findsNothing);
    // The individual-race "1ST <full pool>" row would read as per-runner —
    // it must not render for a team race.
    expect(find.byKey(const Key('race-prize-pool-summary')), findsNothing);
    expect(
      find.byKey(const Key('race-prize-pool-payout-summary')),
      findsNothing,
    );
    expect(find.text('1ST'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('a team payload without an authoritative total omits the total', (
    tester,
  ) async {
    final race = _fundedRace(status: 'PENDING')
      ..['isTeamRace'] = true
      ..remove('prizePool')
      ..remove('projectedPotCoins');
    await _pump(tester, _StubApi(race));

    expect(find.byKey(const Key('race-prize-pool-board')), findsNothing);
    expect(find.byKey(const Key('race-info-prize-pool')), findsNothing);
    expect(find.text('POT'), findsNothing);

    await _teardown(tester);
  });

  testWidgets(
    'the exact v1 API marker reaches Edit Race and omits its preview',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final race = _fundedRace(status: 'PENDING')
        ..['isCreator'] = true
        ..['payoutRoundingVersion'] = 1;
      await _pump(tester, _StubApi(race));

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      final editSettings = find.text('EDIT SETTINGS');
      // The existing bottom sheet is taller than the test viewport; invoke the
      // real button callback after confirming the production control exists.
      final button = tester.widget<PillButton>(
        find.ancestor(of: editSettings, matching: find.byType(PillButton)),
      );
      button.onPressed!.call();
      await tester.pump();
      await tester.pump();

      expect(find.byType(EditRaceScreen), findsOneWidget);
      expect(find.byKey(const Key('edit-prize-pool-preview')), findsNothing);

      await _teardown(tester);
    },
  );

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

  testWidgets('legacy payout values stay server-authored and unrounded', (
    tester,
  ) async {
    final race = _legacyPaidRace()
      ..['projectedPotCoins'] = 10
      ..['payouts'] = const {'first': 7, 'second': 2, 'third': 1};
    await _pump(tester, _StubApi(race));

    await tester.tap(find.byKey(const Key('race-prize-pool-board')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final tiers = find.byKey(const Key('race-prize-pool-tier-list'));
    expect(tiers, findsOneWidget);
    expect(
      find.descendant(of: tiers, matching: find.text('7')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tiers, matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tiers, matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.descendant(of: tiers, matching: find.text('10')), findsNothing);

    await _teardown(tester);
  });

  testWidgets('rounded server tiers and total render unchanged', (
    tester,
  ) async {
    final race = _fundedRace(status: 'COMPLETED', projected: false, coins: 20)
      ..['payoutTiers'] = const [
        {'placement': 1, 'amount': 10},
        {'placement': 2, 'amount': 5},
        {'placement': 3, 'amount': 5},
      ];
    await _pump(tester, _StubApi(race));

    expect(find.byKey(const Key('race-prize-pool-board')), findsOneWidget);
    await tester.tap(find.byKey(const Key('race-prize-pool-board')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final tiers = find.byKey(const Key('race-prize-pool-tier-list'));
    expect(
      find.descendant(of: tiers, matching: find.text('10')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tiers, matching: find.text('5')),
      findsNWidgets(2),
    );

    await _teardown(tester);
  });

  testWidgets(
    'accepting an invite to a funded race is one tap — no buy-in sheet',
    (tester) async {
      final api = _StubApi(_fundedRace(status: 'PENDING', myStatus: 'INVITED'));
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
    },
  );
}
