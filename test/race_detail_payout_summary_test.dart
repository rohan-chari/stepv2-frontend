import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Batch 2026-07-27 item 9 — the daily/weekly challenge payout summary.
///
/// A seeded Daily is created `TOP_HALF`, so a 300-runner field produces 150
/// IDENTICAL payout tiers. The old podium row ("1ST / 2ND / 3RD / +147 MORE")
/// answered none of the questions a runner actually has, and 150 rows in a card
/// is unusable. The summary answers them in four lines, and keeps the full list
/// behind a tap.
///
/// Every number here is READ off `payoutTiers`; the app never recomputes a
/// payout. An older backend that omits `payoutTiers` must render exactly what
/// it renders today — nothing — without throwing.

List<Map<String, dynamic>> _field(int size) => [
  for (var i = 0; i < size; i++)
    {
      'userId': i == 0 ? 'me' : 'u$i',
      'displayName': i == 0 ? 'Bara' : 'Runner $i',
      'status': 'ACCEPTED',
    },
];

Map<String, dynamic> _dailyChallenge({
  String status = 'ACTIVE',
  int fieldSize = 300,
  int paidPlaces = 150,
  int perHead = 40,
  int poolCoins = 6000,
  bool withTiers = true,
  String preset = 'TOP_HALF',
}) => {
  'id': 'race-daily',
  'name': 'Daily Challenge',
  'seedKind': 'DAILY',
  'status': status,
  'maxDurationDays': 1,
  'buyInAmount': 0,
  'payoutPreset': preset,
  'potCoins': 0,
  'heldPotCoins': 0,
  'projectedPotCoins': poolCoins,
  'prizePool': {
    'coins': poolCoins,
    'projected': status != 'COMPLETED',
    'atMax': false,
    'playerCount': fieldSize,
    'durationDays': 1,
    'durationPoints': 1,
    'coinUnit': 20,
    'maxCoins': 320000,
    'funded': true,
  },
  if (withTiers)
    'payoutTiers': [
      for (var i = 1; i <= paidPlaces; i++)
        {'placement': i, 'amount': perHead},
    ],
  'myStatus': 'ACCEPTED',
  'isCreator': false,
  'powerupsEnabled': false,
  'endsAt': '2126-04-10T12:00:00.000Z',
  'participants': _field(fieldSize),
};

class _StubApi extends BackendApiService {
  _StubApi(this.race, {this.myPlacement = 62});

  final Map<String, dynamic> race;
  final int myPlacement;

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
    // The server's placement is the ONE rank every surface agrees on.
    'participants': [
      {
        'userId': 'u1',
        'displayName': 'Runner 1',
        'totalSteps': 9000.0,
        'placement': 1,
        'finishedAt': null,
      },
      {
        'userId': 'me',
        'displayName': 'Bara',
        'totalSteps': 5000.0,
        'placement': myPlacement,
        'finishedAt': null,
      },
      {
        'userId': 'u2',
        'displayName': 'Runner 2',
        'totalSteps': 100.0,
        'placement': 299,
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
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {'coins': 0, 'heldCoins': 0};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Bara',
    'auth_coins': 0,
    'auth_held_coins': 0,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(WidgetTester tester, _StubApi api) async {
  // Wide enough that the hero's chip row (name + pool + timer) does not
  // overflow on this fixture — an existing layout quirk, unrelated to payouts.
  await tester.binding.setSurfaceSize(const Size(600, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: RaceDetailScreen(
        authService: await _auth(),
        raceId: 'race-daily',
        backendApiService: api,
      ),
    ),
  );
  // Bounded pumps: the hero's spinning coin animates forever.
  await tester.pump();
  await tester.pump();
}

Future<void> _openPrizeSheet(WidgetTester tester) async {
  final board = find.byKey(const Key('race-prize-pool-board'));
  expect(board, findsOneWidget);
  await tester.tap(board);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // PackageInfo.fromPlatform() never resolves inside testWidgets' fake-async
    // zone; without this any activation-analytics write hangs silently.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '2.0.1',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'a 300-runner TOP_HALF daily summarises the split instead of listing 150 rows',
    (tester) async {
      await _pump(tester, _StubApi(_dailyChallenge()));
      await _openPrizeSheet(tester);

      final summary = find.byKey(const Key('race-prize-pool-payout-summary'));
      expect(summary, findsOneWidget);

      // The preset in plain words.
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Top half splits the pool evenly'),
        ),
        findsOneWidget,
      );
      // The number that matters — read straight off payoutTiers.
      expect(
        find.descendant(of: summary, matching: find.text('~40')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('coins each')),
        findsOneWidget,
      );
      // Where the money stops.
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Top 150 of 300 get paid'),
        ),
        findsOneWidget,
      );
      // Where the viewer stands relative to it.
      expect(
        find.descendant(
          of: summary,
          matching: find.text('You’re 62nd — in the money'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('See all payouts')),
        findsOneWidget,
      );

      // The 150 rows must NOT be in the tree until asked for.
      expect(find.text('150TH'), findsNothing);
      expect(find.text('149TH'), findsNothing);
      expect(find.text('2ND'), findsNothing);

      await _teardown(tester);
    },
  );

  testWidgets('tapping See all payouts reveals the full per-place list', (
    tester,
  ) async {
    await _pump(tester, _StubApi(_dailyChallenge()));
    await _openPrizeSheet(tester);

    await tester.tap(find.text('See all payouts'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('PAYOUTS'), findsOneWidget);
    expect(find.text('1ST'), findsOneWidget);
    expect(find.text('2ND'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('a runner below the cut is told how far off the money they are', (
    tester,
  ) async {
    await _pump(tester, _StubApi(_dailyChallenge(), myPlacement: 180));
    await _openPrizeSheet(tester);

    expect(
      find.text('You’re 180th — 30 places from the cut'),
      findsOneWidget,
    );

    await _teardown(tester);
  });

  testWidgets('a 4-runner TOP_HALF field reads "Top 2 of 4 get paid"', (
    tester,
  ) async {
    await _pump(
      tester,
      _StubApi(
        _dailyChallenge(
          status: 'PENDING',
          fieldSize: 4,
          paidPlaces: 2,
          perHead: 750,
          poolCoins: 1500,
        ),
      ),
    );

    // A pending race shows the race-info card inline — no tap required.
    expect(find.byKey(const Key('race-payout-summary')), findsOneWidget);
    expect(find.text('Top 2 of 4 get paid'), findsOneWidget);
    expect(find.text('~750'), findsOneWidget);
    // Nobody has a placement before the gun goes off.
    expect(find.textContaining('You’re'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('an ODD field reads the cut off payoutTiers, never floor(n/2)', (
    tester,
  ) async {
    // The backend's gradedSlotCount pays CEIL(field / 2), so 9 runners pay 5
    // places — not 4. An even field (300 -> 150) hides that difference
    // entirely, which is exactly why the odd case is the one worth pinning.
    // The app must never do this division at all: paid places is
    // `payoutTiers.length`, straight off the payload.
    await _pump(
      tester,
      _StubApi(
        _dailyChallenge(
          fieldSize: 9,
          paidPlaces: 5,
          perHead: 120,
          poolCoins: 600,
        ),
        myPlacement: 7,
      ),
    );
    await _openPrizeSheet(tester);

    expect(find.text('Top 5 of 9 get paid'), findsOneWidget);
    expect(find.text('Top 4 of 9 get paid'), findsNothing);
    expect(find.text('~120'), findsOneWidget);
    // 7th with 5 paid places is 2 off — subtraction of two server-owned
    // numbers, no division anywhere.
    expect(find.text('You’re 7th — 2 places from the cut'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('one place off the cut is singular, not "1 places"', (
    tester,
  ) async {
    await _pump(
      tester,
      _StubApi(
        _dailyChallenge(fieldSize: 9, paidPlaces: 5, perHead: 120),
        myPlacement: 6,
      ),
    );
    await _openPrizeSheet(tester);

    expect(find.text('You’re 6th — 1 place from the cut'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('the last paid place on an odd field is still in the money', (
    tester,
  ) async {
    await _pump(
      tester,
      _StubApi(
        _dailyChallenge(fieldSize: 9, paidPlaces: 5, perHead: 120),
        myPlacement: 5,
      ),
    );
    await _openPrizeSheet(tester);

    expect(find.text('You’re 5th — in the money'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('an empty payoutTiers list renders nothing, no crash', (
    tester,
  ) async {
    final race = _dailyChallenge();
    race['payoutTiers'] = const <Map<String, dynamic>>[];
    await _pump(tester, _StubApi(race));
    await _openPrizeSheet(tester);

    expect(
      find.byKey(const Key('race-prize-pool-payout-summary')),
      findsNothing,
    );
    expect(find.textContaining('get paid'), findsNothing);
    expect(tester.takeException(), isNull);

    await _teardown(tester);
  });

  testWidgets('an older backend with no payoutTiers renders nothing, no crash', (
    tester,
  ) async {
    await _pump(tester, _StubApi(_dailyChallenge(withTiers: false)));
    await _openPrizeSheet(tester);

    expect(find.byKey(const Key('race-prize-pool-payout-summary')), findsNothing);
    expect(find.byKey(const Key('race-payout-summary')), findsNothing);
    expect(find.textContaining('get paid'), findsNothing);
    expect(find.textContaining('splits the pool'), findsNothing);
    expect(tester.takeException(), isNull);

    await _teardown(tester);
  });

  testWidgets('an uneven preset keeps the existing podium breakdown', (
    tester,
  ) async {
    // WINNER_TAKES_ALL / TOP 3 are not "everyone gets the same" — the summary
    // would be a lie, so the podium row it has always shown stays.
    final race = _dailyChallenge(status: 'PENDING', preset: 'TOP3_70_20_10');
    race['payoutTiers'] = const [
      {'placement': 1, 'amount': 4200},
      {'placement': 2, 'amount': 1200},
      {'placement': 3, 'amount': 600},
    ];
    await _pump(tester, _StubApi(race));

    expect(find.byKey(const Key('race-payout-summary')), findsNothing);
    expect(find.text('1ST'), findsOneWidget);
    expect(find.text('4200'), findsOneWidget);

    await _teardown(tester);
  });
}
