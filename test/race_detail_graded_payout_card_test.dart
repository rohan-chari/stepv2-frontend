import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Top-heavy seeded-challenge payouts (spec §5 item 3, §7 item 19).
///
/// A seeded challenge stamped `payoutCurve: "GEOMETRIC"` still serves a graded
/// preset (TOP_HALF / ALL_BUT_LAST) but with DESCENDING `payoutTiers` instead of
/// 150 identical ones. The even-split card would be a lie there, and the podium
/// row ("1ST / 2ND / 3RD / +N MORE") buries the one fact that changed: winning
/// now pays dramatically more than scraping in.
///
/// Gating is preset + unequal tiers, NOT "tiers descend" — legacy buy-in and
/// TOP3 races have always served descending tiers and must keep the podium row.
///
/// Every figure is read straight off `payoutTiers`; the app computes no payout.
/// `payoutCurve` is never serialized to clients, so the amounts are the only
/// signal — and an older backend that omits tiers must render exactly what it
/// renders today.

List<Map<String, dynamic>> _field(int size) => [
  for (var i = 0; i < size; i++)
    {
      'userId': i == 0 ? 'me' : 'u$i',
      'displayName': i == 0 ? 'Bara' : 'Runner $i',
      'status': 'ACCEPTED',
    },
];

/// A geometric-decay tier table: strictly descending, sums to the pool.
const _geometricTiers = [
  {'placement': 1, 'amount': 300},
  {'placement': 2, 'amount': 210},
  {'placement': 3, 'amount': 147},
  {'placement': 4, 'amount': 103},
  {'placement': 5, 'amount': 40},
];

Map<String, dynamic> _challenge({
  String status = 'ACTIVE',
  int fieldSize = 9,
  int poolCoins = 800,
  String preset = 'TOP_HALF',
  List<Map<String, dynamic>>? tiers = _geometricTiers,
  bool omitPreset = false,
  // A legacy buy-in race: a real pot, no app-funded `prizePool` object. It can
  // serve unequal graded tiers of its own, and must keep the podium row.
  bool buyIn = false,
}) => {
  'id': 'race-daily',
  'name': buyIn ? 'Gold Sprint' : 'Daily Challenge',
  if (!buyIn) 'seedKind': 'DAILY',
  'status': status,
  'maxDurationDays': 1,
  'buyInAmount': buyIn ? 100 : 0,
  if (!omitPreset) 'payoutPreset': preset,
  'potCoins': buyIn ? poolCoins : 0,
  'heldPotCoins': 0,
  'projectedPotCoins': poolCoins,
  if (!buyIn)
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
  'payoutTiers': ?tiers,
  'myStatus': 'ACCEPTED',
  'isCreator': false,
  'powerupsEnabled': false,
  'endsAt': '2126-04-10T12:00:00.000Z',
  'participants': _field(fieldSize),
};

class _StubApi extends BackendApiService {
  _StubApi(this.race, {this.myPlacement = 3});

  final Map<String, dynamic> race;
  final int myPlacement;

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
        'placement': 9,
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

const _sheetKey = Key('race-prize-pool-graded-payout-summary');
const _cardKey = Key('race-graded-payout-summary');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // PackageInfo.fromPlatform() never resolves inside testWidgets' fake-async
    // zone; without this any activation-analytics write hangs silently.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '2.1.2',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'descending TOP_HALF tiers render the graded summary in the sheet',
    (tester) async {
      await _pump(tester, _StubApi(_challenge()));
      await _openPrizeSheet(tester);

      final summary = find.byKey(_sheetKey);
      expect(summary, findsOneWidget);

      // The preset, restated as the thing that changed.
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Top half wins. Bigger prizes up top'),
        ),
        findsOneWidget,
      );
      // The headline figure, straight off payoutTiers[0].
      expect(
        find.descendant(of: summary, matching: find.text('300')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary, matching: find.text('coins for 1st')),
        findsOneWidget,
      );
      // D6: the projection shrinks at settlement, so say so.
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Projected. Final payouts settle on who walked.'),
        ),
        findsOneWidget,
      );
      // Where the money stops.
      expect(
        find.descendant(
          of: summary,
          matching: find.text('Top 5 of 9 get paid'),
        ),
        findsOneWidget,
      );
      // What the viewer's own rank is worth right now — tiers[placement - 1].
      expect(
        find.descendant(
          of: summary,
          matching: find.text('You’re 3rd. 147 coins projected'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('race-prize-pool-tier-list')),
        findsOneWidget,
      );

      // The even-split card must NOT also fire.
      expect(
        find.byKey(const Key('race-prize-pool-payout-summary')),
        findsNothing,
      );
      // Nor the podium row.
      expect(find.byKey(const Key('race-prize-pool-summary')), findsNothing);

      await _teardown(tester);
    },
  );

  testWidgets('a runner below the cut is told how far off the money they are', (
    tester,
  ) async {
    await _pump(tester, _StubApi(_challenge(), myPlacement: 7));
    await _openPrizeSheet(tester);

    expect(find.text('You’re 7th. 2 places from the cut'), findsOneWidget);
    expect(find.textContaining('coins projected'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('the pending race-info card gates on the same rule', (
    tester,
  ) async {
    // Item 3 pins BOTH call sites — the prize-pool sheet and the inline
    // race-info card. A pending race shows the card without a tap.
    await _pump(tester, _StubApi(_challenge(status: 'PENDING')));

    expect(find.byKey(_cardKey), findsOneWidget);
    expect(find.text('TOP CUT PAID'), findsOneWidget);
    expect(find.text('5 OF 9'), findsOneWidget);
    expect(find.text('1ST PLACE'), findsOneWidget);
    expect(find.byKey(const Key('race-payout-summary')), findsNothing);
    // Nobody has a placement before the gun goes off.
    expect(find.textContaining('You’re'), findsNothing);

    await _teardown(tester);
  });

  testWidgets('ALL_BUT_LAST gets its own headline', (tester) async {
    await _pump(
      tester,
      _StubApi(_challenge(status: 'PENDING', preset: 'ALL_BUT_LAST')),
    );

    expect(find.byKey(_cardKey), findsOneWidget);
    expect(find.text('TOP CUT PAID'), findsOneWidget);
    expect(find.text('5 OF 9'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets(
    'equal tiers still render the even-split card, not the graded one',
    (tester) async {
      await _pump(
        tester,
        _StubApi(
          _challenge(
            tiers: const [
              {'placement': 1, 'amount': 160},
              {'placement': 2, 'amount': 160},
              {'placement': 3, 'amount': 160},
              {'placement': 4, 'amount': 160},
              {'placement': 5, 'amount': 160},
            ],
          ),
        ),
      );
      await _openPrizeSheet(tester);

      expect(
        find.byKey(const Key('race-prize-pool-payout-summary')),
        findsOneWidget,
      );
      expect(find.byKey(_sheetKey), findsNothing);
      expect(find.text('Top half splits the pool evenly'), findsOneWidget);

      await _teardown(tester);
    },
  );

  testWidgets('a TOP3 race with descending tiers keeps the podium row (G7)', (
    tester,
  ) async {
    // TOP3 and legacy buy-in races have ALWAYS served descending tiers. Gating
    // on "tiers descend" alone would rewrite their card for no reason.
    await _pump(
      tester,
      _StubApi(
        _challenge(
          status: 'PENDING',
          preset: 'TOP3_70_20_10',
          tiers: const [
            {'placement': 1, 'amount': 560},
            {'placement': 2, 'amount': 160},
            {'placement': 3, 'amount': 80},
          ],
        ),
      ),
    );

    expect(find.byKey(_cardKey), findsNothing);
    expect(find.byKey(const Key('race-payout-summary')), findsNothing);
    expect(find.text('1ST PLACE'), findsOneWidget);
    expect(find.text('560'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets(
    'a legacy buy-in TOP_HALF race with descending tiers keeps the podium row',
    (tester) async {
      // The third gate condition. Only APP-FUNDED races are ever stamped with a
      // payout curve; a buy-in race splits a real pot and carries
      // buyInAmount/potCoins with NO funded `prizePool` object. This mirrors the
      // long-standing fixture in race_detail_screen_test.dart, which must keep
      // rendering its podium row unchanged.
      await _pump(tester, _StubApi(_challenge(status: 'PENDING', buyIn: true)));

      expect(find.byKey(_cardKey), findsNothing);
      expect(find.byKey(const Key('race-payout-summary')), findsNothing);
      expect(find.text('1ST PLACE'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
      expect(find.textContaining('bigger prizes up top'), findsNothing);

      await _teardown(tester);
    },
  );

  testWidgets('a funded prizePool is what unlocks the graded card', (
    tester,
  ) async {
    // The positive twin of the test above: identical preset and tiers, the only
    // difference being the funded `prizePool` object.
    await _pump(tester, _StubApi(_challenge(status: 'PENDING')));

    expect(find.byKey(_cardKey), findsOneWidget);
    expect(find.text('TOP CUT PAID'), findsOneWidget);
    expect(find.text('5 OF 9'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('an explicit funded:false prizePool falls back to the podium', (
    tester,
  ) async {
    final race = _challenge(status: 'PENDING');
    (race['prizePool'] as Map<String, dynamic>)['funded'] = false;
    await _pump(tester, _StubApi(race));

    expect(find.byKey(_cardKey), findsNothing);
    expect(find.text('1ST PLACE'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets(
    'an absent payoutPreset falls back to the podium, never a guess',
    (tester) async {
      // A backend older than payoutPreset can still send tiers. Without the
      // preset we cannot claim "top half wins", so the podium row stands.
      await _pump(
        tester,
        _StubApi(_challenge(status: 'PENDING', omitPreset: true)),
      );

      expect(find.byKey(_cardKey), findsNothing);
      expect(find.text('1ST PLACE'), findsOneWidget);

      await _teardown(tester);
    },
  );

  testWidgets(
    'an older backend with no payoutTiers renders nothing, no crash',
    (tester) async {
      await _pump(tester, _StubApi(_challenge(status: 'PENDING', tiers: null)));

      expect(find.byKey(_cardKey), findsNothing);
      expect(find.byKey(const Key('race-payout-summary')), findsNothing);
      expect(find.textContaining('get paid'), findsNothing);
      expect(find.textContaining('bigger prizes up top'), findsNothing);
      expect(tester.takeException(), isNull);

      await _teardown(tester);
    },
  );
}
