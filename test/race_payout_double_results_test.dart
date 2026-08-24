import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/race_payout_double_offer.dart';
import 'package:step_tracker/screens/race_results_summary_screen.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/spinning_coin.dart';

const _offerId = 'd05cb2a4-16b7-463f-977d-58231987a0ac';

Map<String, dynamic> _offerJson({
  String? offerId,
  List<String> raceIds = const ['race-a'],
  int baseCoins = 120,
  int bonusCoins = 120,
  int maxBonusCoins = 500,
  int remaining = 500,
  String? rewardMode,
}) => <String, dynamic>{
  'offerId': offerId,
  'raceIds': raceIds,
  'baseCoins': baseCoins,
  'bonusCoins': bonusCoins,
  'maxBonusCoins': maxBonusCoins,
  'rolling24hRemainingBeforeClaim': remaining,
  // ignore: use_null_aware_elements
  if (rewardMode case final mode?) 'rewardMode': mode,
};

Map<String, dynamic> _flatOfferJson({
  String? offerId,
  List<String> raceIds = const ['race-a'],
  int baseCoins = 600,
  int? bonusCoins,
  String? status,
}) => <String, dynamic>{
  ..._offerJson(
    offerId: offerId,
    raceIds: raceIds,
    baseCoins: baseCoins,
    bonusCoins: bonusCoins ?? 50 * raceIds.length,
    rewardMode: 'flat_50',
  ),
  // ignore: use_null_aware_elements
  if (status case final value?) 'status': value,
};

List<Map<String, dynamic>> _races({int payout = 120}) => [
  {
    'id': 'race-a',
    'name': 'Sunset Sprint',
    'participantCount': 4,
    'myPlacement': 2,
    'myPayoutCoins': payout,
    'myStatus': 'ACCEPTED',
    'myResultsSeen': false,
  },
];

class _FakeRacePayoutAdController implements RacePayoutDoubleAdController {
  bool ready = false;
  bool earnReward = true;
  int loadCalls = 0;
  int showCalls = 0;
  String? loadedUserId;
  String? loadedOfferId;
  Completer<void>? loadCompleter;

  @override
  bool get isSupported => true;

  @override
  bool get isReady => ready;

  @override
  Future<void> loadForRacePayoutDouble({
    required String userId,
    required String offerId,
  }) async {
    loadCalls++;
    loadedUserId = userId;
    loadedOfferId = offerId;
    if (loadCompleter != null) await loadCompleter!.future;
    ready = true;
  }

  @override
  Future<bool> showAndAwaitReward() async {
    showCalls++;
    ready = false;
    return earnReward;
  }

  @override
  void dispose() {}
}

class _FakeRacePayoutApi extends BackendApiService {
  Map<String, dynamic> prepared = <String, dynamic>{
    ..._offerJson(offerId: _offerId),
    'status': 'PENDING',
  };
  List<Object> claimResults = [
    <String, dynamic>{
      'awarded': true,
      'alreadyClaimed': false,
      ..._offerJson(offerId: null),
      'coins': 845,
    },
  ];
  int prepareCalls = 0;
  int claimCalls = 0;
  List<String>? preparedRaceIds;
  final List<String> claimedOfferIds = [];
  Completer<void>? claimCompleter;

  @override
  Future<RacePayoutDoubleOffer> createRacePayoutDoubleOffer({
    required String identityToken,
    required List<String> raceIds,
    required List<String> popupRaceIds,
  }) async {
    prepareCalls++;
    preparedRaceIds = List<String>.of(raceIds);
    final parsed = RacePayoutDoubleOffer.tryParse(
      prepared,
      popupRaceIds: popupRaceIds,
      requirePendingStatus: true,
    );
    if (parsed == null) throw const ApiException('Malformed offer.');
    return parsed;
  }

  @override
  Future<RacePayoutDoubleClaimResult> claimRacePayoutDouble({
    required String identityToken,
    required String offerId,
    required List<String> popupRaceIds,
  }) async {
    claimedOfferIds.add(offerId);
    if (claimCompleter != null) await claimCompleter!.future;
    final value = claimResults[claimCalls.clamp(0, claimResults.length - 1)];
    claimCalls++;
    if (value is Exception) throw value;
    final parsed = RacePayoutDoubleClaimResult.tryParse(
      value,
      popupRaceIds: popupRaceIds,
    );
    if (parsed == null) throw const ApiException('Malformed claim.');
    return parsed;
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'id': 'user-1', 'coins': 845};
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'auth_identity_token': 'identity-token',
    'auth_session_token': 'session-token',
    'auth_user_identifier': 'provider-user',
    'auth_backend_user_id': 'user-1',
    'auth_coins': 725,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pump(
  WidgetTester tester, {
  required RacePayoutDoubleOffer? offer,
  _FakeRacePayoutApi? api,
  _FakeRacePayoutAdController? ads,
  List<Map<String, dynamic>>? races,
  Duration claimRetryDelay = Duration.zero,
  bool canStartNextRace = false,
  bool disableAnimations = false,
}) async {
  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: RaceResultsSummaryScreen(
          races: races ?? _races(),
          canStartNextRace: canStartNextRace,
          payoutDoubleOffer: offer,
          authService: auth,
          backendApiService: api,
          adController: ads,
          claimRetryDelay: claimRetryDelay,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('flat_50 accepts a zero base and a bonus greater than that base', () {
    final offer = RacePayoutDoubleOffer.tryParse(
      _flatOfferJson(baseCoins: 0),
      popupRaceIds: const ['race-a'],
    );
    final multiRaceOffer = RacePayoutDoubleOffer.tryParse(
      _flatOfferJson(raceIds: const ['race-a', 'race-b'], baseCoins: 50),
      popupRaceIds: const ['race-a', 'race-b'],
    );

    expect(offer, isNotNull);
    expect(offer!.isFlat50, isTrue);
    expect(offer.bonusCoins, 50);
    expect(multiRaceOffer, isNotNull);
    expect(multiRaceOffer!.bonusCoins, 100);
  });

  test('flat_50 rejects a malformed or non-exact additive reward', () {
    expect(
      RacePayoutDoubleOffer.tryParse(
        {..._flatOfferJson(), 'rewardMode': 'unknown'},
        popupRaceIds: const ['race-a'],
      ),
      isNull,
    );
    expect(
      RacePayoutDoubleOffer.tryParse(
        _flatOfferJson(bonusCoins: 40),
        popupRaceIds: const ['race-a'],
      ),
      isNull,
    );
  });

  testWidgets('flat offer uses a fixed per-race copy for a 600-coin race', (
    tester,
  ) async {
    final offer = RacePayoutDoubleOffer.tryParse(
      _flatOfferJson(),
      popupRaceIds: const ['race-a'],
    );
    await _pump(
      tester,
      offer: offer,
      api: _FakeRacePayoutApi(),
      ads: _FakeRacePayoutAdController(),
      races: _races(payout: 600),
    );

    expect(find.text('FLAT +50 COINS'), findsOneWidget);
    expect(
      find.text('Watch one ad to earn a flat 50-coin bonus.'),
      findsOneWidget,
    );
    expect(find.text('WATCH AD · +50 COINS'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('WATCH AD · +50 COINS')).style?.color,
      Colors.white,
    );
    expect(find.textContaining('DOUBLE'), findsNothing);
    expect(find.textContaining('qualifying race prizes'), findsNothing);
  });

  testWidgets('flat multi-race offer shows 50 per race and exact total', (
    tester,
  ) async {
    final races = [
      ..._races(payout: 600),
      {..._races(payout: 0).single, 'id': 'race-b', 'name': 'Dawn Dash'},
    ];
    final api = _FakeRacePayoutApi()
      ..prepared = _flatOfferJson(
        offerId: _offerId,
        raceIds: const ['race-a', 'race-b'],
        baseCoins: 600,
        status: 'PENDING',
      )
      ..claimResults = [
        <String, dynamic>{
          'awarded': true,
          'alreadyClaimed': false,
          ..._flatOfferJson(
            raceIds: const ['race-a', 'race-b'],
            baseCoins: 600,
          ),
          'coins': 825,
        },
      ];
    final offer = RacePayoutDoubleOffer.tryParse(
      {...api.prepared, 'offerId': null},
      popupRaceIds: const ['race-a', 'race-b'],
    );
    await _pump(
      tester,
      offer: offer,
      api: api,
      ads: _FakeRacePayoutAdController(),
      races: races,
    );

    expect(find.text('FLAT +50 COINS PER RACE'), findsOneWidget);
    expect(find.text('WATCH AD · +50 COINS PER RACE'), findsOneWidget);
    await tester.tap(find.text('WATCH AD · +50 COINS PER RACE'));
    await tester.pump();
    await tester.pump();

    expect(find.text('+100 COINS EARNED'), findsOneWidget);
    expect(find.text('DOUBLE'), findsNothing);
    expect(find.textContaining('partial'), findsNothing);
  });

  testWidgets(
    'full rounded server values render without a cap field or Dart rounding',
    (tester) async {
      final offer = RacePayoutDoubleOffer.tryParse(
        const {
          'raceIds': ['race-a'],
          'baseCoins': 10,
          'bonusCoins': 10,
        },
        popupRaceIds: const ['race-a'],
      );

      await _pump(
        tester,
        offer: offer,
        api: _FakeRacePayoutApi(),
        ads: _FakeRacePayoutAdController(),
        races: _races(payout: 10),
      );

      expect(offer, isNotNull);
      expect(find.text('DOUBLE +10 COINS'), findsOneWidget);
      expect(find.text('WATCH AD · +10 COINS'), findsOneWidget);
      expect(find.textContaining('+7'), findsNothing);
    },
  );

  test('capless partial payout-double values are rejected', () {
    for (final raw in <Map<String, dynamic>>[
      const {
        'raceIds': ['race-a'],
        'baseCoins': 10,
        'bonusCoins': 5,
      },
      const {
        'raceIds': ['race-a'],
        'baseCoins': 10,
        'bonusCoins': 7,
      },
    ]) {
      expect(
        RacePayoutDoubleOffer.tryParse(raw, popupRaceIds: const ['race-a']),
        isNull,
      );
    }
  });

  testWidgets('real result screen places one exact double plaque before CONTINUE', (
    tester,
  ) async {
    final races = _races();
    final offer = RacePayoutDoubleOffer.tryParse(
      _offerJson(),
      popupRaceIds: const ['race-a'],
    );
    await _pump(
      tester,
      offer: offer,
      api: _FakeRacePayoutApi(),
      ads: _FakeRacePayoutAdController(),
      races: races,
    );

    expect(find.byKey(const Key('race-payout-double-panel')), findsOneWidget);
    expect(find.text('DOUBLE +120 COINS'), findsOneWidget);
    expect(find.text('Watch one ad to get another 120.'), findsOneWidget);
    expect(find.text('WATCH AD · +120 COINS'), findsOneWidget);
    final actionText = tester.widget<Text>(
      find.text('WATCH AD · +120 COINS'),
    );
    expect(actionText.style?.color, Colors.white);
    expect(
      tester.getTopLeft(find.byKey(const Key('race-payout-double-panel'))).dy,
      lessThan(tester.getTopLeft(find.text('CONTINUE')).dy),
    );
  });

  testWidgets('legacy capped payout-double values retain their actual copy', (
    tester,
  ) async {
    final cases = <({Map<String, dynamic> raw, String title})>[
      (
        raw: _offerJson(baseCoins: 120, bonusCoins: 50, remaining: 50),
        title: 'GET +50 BONUS COINS',
      ),
      (
        raw: _offerJson(baseCoins: 800, bonusCoins: 500),
        title: 'GET THE MAX +500 BONUS',
      ),
      (
        raw: _offerJson(
          baseCoins: 300,
          bonusCoins: 100,
          maxBonusCoins: 100,
          remaining: 100,
        ),
        title: 'GET THE MAX +100 BONUS',
      ),
    ];
    for (final entry in cases) {
      final offer = RacePayoutDoubleOffer.tryParse(
        entry.raw,
        popupRaceIds: const ['race-a'],
      );
      await _pump(
        tester,
        offer: offer,
        api: _FakeRacePayoutApi(),
        ads: _FakeRacePayoutAdController(),
      );

      expect(offer, isNotNull);
      expect(find.byKey(const Key('race-payout-double-panel')), findsOneWidget);
      expect(find.text(entry.title), findsOneWidget);

      // A new screen instance is required for the next server snapshot: the
      // real result popup owns its offer state in initState.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets('malformed and out-of-popup offers leave no reserved gap', (
    tester,
  ) async {
    for (final raw in <Map<String, dynamic>>[
      _offerJson(bonusCoins: 0),
      _offerJson(bonusCoins: 121, baseCoins: 120),
      const {
        'raceIds': ['race-a'],
        'baseCoins': 120,
        'bonusCoins': 119,
      },
      _offerJson(raceIds: const ['other-race']),
      <String, dynamic>{..._offerJson()}..remove('bonusCoins'),
    ]) {
      final offer = RacePayoutDoubleOffer.tryParse(
        raw,
        popupRaceIds: const ['race-a'],
      );
      await _pump(tester, offer: offer);
      expect(offer, isNull);
      expect(find.byKey(const Key('race-payout-double-panel')), findsNothing);
      expect(find.text('CONTINUE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tap prepares before loading and loading leaves CONTINUE enabled', (
    tester,
  ) async {
    final api = _FakeRacePayoutApi();
    final ads = _FakeRacePayoutAdController()
      ..loadCompleter = Completer<void>();
    final offer = RacePayoutDoubleOffer.tryParse(
      _offerJson(),
      popupRaceIds: const ['race-a'],
    );
    await _pump(tester, offer: offer, api: api, ads: ads);

    await tester.tap(find.text('WATCH AD · +120 COINS'));
    await tester.pump();

    expect(api.prepareCalls, 1);
    expect(api.preparedRaceIds, const ['race-a']);
    expect(ads.loadCalls, 1);
    expect(ads.loadedOfferId, _offerId);
    expect(find.text('LOADING AD…'), findsOneWidget);
    expect(
      tester
          .widget<GestureDetector>(
            find
                .ancestor(
                  of: find.text('CONTINUE'),
                  matching: find.byType(GestureDetector),
                )
                .first,
          )
          .onTapUp,
      isNotNull,
    );
  });

  testWidgets('early close does not claim and reports the exact bonus', (
    tester,
  ) async {
    final api = _FakeRacePayoutApi();
    final ads = _FakeRacePayoutAdController()..earnReward = false;
    final offer = RacePayoutDoubleOffer.tryParse(
      _offerJson(),
      popupRaceIds: const ['race-a'],
    );
    await _pump(tester, offer: offer, api: api, ads: ads);

    await tester.tap(find.text('WATCH AD · +120 COINS'));
    await tester.pump();
    await tester.pump();

    expect(api.claimCalls, 0);
    expect(
      find.text('Finish the ad to earn +120 bonus coins.'),
      findsOneWidget,
    );
  });

  testWidgets('SSV lag retries five total attempts with the immutable ID', (
    tester,
  ) async {
    final api = _FakeRacePayoutApi()
      ..claimResults = <Object>[
        for (var i = 0; i < 4; i++)
          const ApiException(
            'Not verified',
            statusCode: 409,
            code: 'AD_NOT_VERIFIED',
          ),
        <String, dynamic>{
          'awarded': true,
          'alreadyClaimed': false,
          ..._offerJson(offerId: null),
          'coins': 845,
        },
      ];
    final ads = _FakeRacePayoutAdController();
    final offer = RacePayoutDoubleOffer.tryParse(
      _offerJson(),
      popupRaceIds: const ['race-a'],
    );
    await _pump(tester, offer: offer, api: api, ads: ads);

    await tester.tap(find.text('WATCH AD · +120 COINS'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }

    expect(api.claimCalls, 5);
    expect(api.claimedOfferIds, everyElement(_offerId));
    expect(find.text('120 PAYOUT + 120 AD BONUS'), findsOneWidget);
    expect(find.text('WATCH AD · +120 COINS'), findsNothing);
  });

  testWidgets('recovered pending offer claims before loading another ad', (
    tester,
  ) async {
    final api = _FakeRacePayoutApi();
    final ads = _FakeRacePayoutAdController();
    final offer = RacePayoutDoubleOffer.tryParse(
      _offerJson(offerId: _offerId),
      popupRaceIds: const ['race-a'],
    );
    await _pump(tester, offer: offer, api: api, ads: ads);
    await tester.pump();

    expect(api.prepareCalls, 0);
    expect(api.claimCalls, 1);
    expect(ads.loadCalls, 0);
    expect(find.text('120 PAYOUT + 120 AD BONUS'), findsOneWidget);
  });

  testWidgets(
    'transient pending recovery retries the claim without replaying an ad',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final api = _FakeRacePayoutApi()
        ..claimResults = <Object>[
          const ApiException(
            'Temporarily unavailable',
            statusCode: 503,
            code: 'REWARD_TEMPORARILY_UNAVAILABLE',
          ),
          <String, dynamic>{
            'awarded': false,
            'alreadyClaimed': true,
            ..._offerJson(offerId: null),
            'coins': 845,
          },
        ];
      final ads = _FakeRacePayoutAdController();
      final offer = RacePayoutDoubleOffer.tryParse(
        _offerJson(offerId: _offerId),
        popupRaceIds: const ['race-a'],
      );
      await _pump(tester, offer: offer, api: api, ads: ads);
      await tester.pump();

      expect(api.claimCalls, 1);
      expect(find.text('RETRY +120 BONUS'), findsOneWidget);
      final retrySemantics = tester.getSemantics(
        find.byKey(const Key('race-payout-double-semantics')),
      );
      expect(retrySemantics.label, 'Retry verification for 120 bonus coins.');
      expect(
        retrySemantics.getSemanticsData().flagsCollection.isLiveRegion,
        isTrue,
      );

      await tester.tap(find.text('RETRY +120 BONUS'));
      await tester.pump();

      expect(api.claimCalls, 2);
      expect(ads.loadCalls, 0);
      expect(find.text('120 PAYOUT + 120 AD BONUS'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('earned coin is static when reduced motion is requested', (
    tester,
  ) async {
    final offer = RacePayoutDoubleOffer.tryParse(
      _offerJson(offerId: _offerId),
      popupRaceIds: const ['race-a'],
    );
    await _pump(
      tester,
      offer: offer,
      api: _FakeRacePayoutApi(),
      ads: _FakeRacePayoutAdController(),
      disableAnimations: true,
    );
    await tester.pump();

    expect(find.text('120 PAYOUT + 120 AD BONUS'), findsOneWidget);
    final earnedCoin = find.descendant(
      of: find.byKey(const Key('race-payout-double-panel')),
      matching: find.byType(SpinningCoin),
    );
    expect(tester.widget<SpinningCoin>(earnedCoin).animate, false);
  });

  testWidgets(
    'earned copy names qualifying prizes when displayed payout differs',
    (tester) async {
      final offer = RacePayoutDoubleOffer.tryParse(
        _offerJson(offerId: _offerId),
        popupRaceIds: const ['race-a'],
      );
      await _pump(
        tester,
        offer: offer,
        api: _FakeRacePayoutApi(),
        ads: _FakeRacePayoutAdController(),
        races: _races(payout: 200),
      );
      await tester.pump();

      expect(find.text('120 QUALIFYING PRIZES + 120 AD BONUS'), findsOneWidget);
      expect(find.text('120 PAYOUT + 120 AD BONUS'), findsNothing);
    },
  );

  testWidgets('loading verifying and success announce exact state and bonus', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final api = _FakeRacePayoutApi()..claimCompleter = Completer<void>();
    final ads = _FakeRacePayoutAdController()
      ..loadCompleter = Completer<void>();
    final offer = RacePayoutDoubleOffer.tryParse(
      _offerJson(),
      popupRaceIds: const ['race-a'],
    );
    await _pump(tester, offer: offer, api: api, ads: ads);

    expect(
      tester
          .getSemantics(find.byKey(const Key('race-payout-double-semantics')))
          .label,
      'Watch an ad to earn 120 bonus coins on your qualifying race prizes.',
    );

    await tester.tap(find.text('WATCH AD · +120 COINS'));
    await tester.pump();
    var stateSemantics = tester.getSemantics(
      find.byKey(const Key('race-payout-double-semantics')),
    );
    expect(stateSemantics.label, 'Loading ad for 120 bonus coins.');
    expect(
      stateSemantics.getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );

    ads.loadCompleter!.complete();
    await tester.pump();
    await tester.pump();
    expect(api.claimCalls, 0);
    stateSemantics = tester.getSemantics(
      find.byKey(const Key('race-payout-double-semantics')),
    );
    expect(stateSemantics.label, 'Verifying 120 bonus coins.');
    expect(
      stateSemantics.getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );

    api.claimCompleter!.complete();
    await tester.pump();
    await tester.pump();
    final successSemantics = tester.getSemantics(
      find.byKey(const Key('race-payout-double-panel-semantics')),
    );
    expect(
      successSemantics.label,
      '120 qualifying race prize coins plus 120 ad bonus coins awarded.',
    );
    expect(
      successSemantics.getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });
}
