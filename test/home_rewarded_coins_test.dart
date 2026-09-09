import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/get_coins_screen.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/widgets/step_milestones_section.dart';
import 'package:step_tracker/services/rewarded_coins_controller.dart';
import 'package:step_tracker/widgets/home_rewarded_coins.dart';
import 'package:step_tracker/widgets/app_refresh_indicator.dart';

Map<String, dynamic> _status({Map<String, dynamic>? adCoinReward}) {
  return {
    'claimedToday': false,
    'cycleLength': 6,
    'currentDay': 3,
    'ladder': <dynamic>[],
    'adCoinReward': ?adCoinReward,
  };
}

const _claimResult = <String, dynamic>{
  'coinAmount': 47,
  'coins': 150,
  'remainingToday': 4,
};

class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService({
    required this.status,
    this.claimResults = const [_claimResult],
  });

  Map<String, dynamic> status;
  // One entry per expected claim attempt; an ApiException entry is thrown.
  final List<Object> claimResults;
  Completer<Map<String, dynamic>>? delayedStatus;
  Completer<Map<String, dynamic>>? delayedClaim;
  bool failStatus = false;
  int getCoinsCalls = 0;
  @override
  Future<Map<String, dynamic>> fetchGetCoinsStatus({
    required String identityToken,
    required String localDate,
  }) async {
    getCoinsCalls++;
    if (failStatus) throw const ApiException("Network error");
    final delayed = delayedStatus;
    return delayed == null ? status : delayed.future;
  }

  int claimCalls = 0;
  int statusCalls = 0;
  final List<String> claimDates = [];

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    statusCalls++;
    return status;
  }

  @override
  Future<Map<String, dynamic>> claimAdCoinReward({
    required String identityToken,
    required String localDate,
  }) async {
    claimDates.add(localDate);
    final result = claimResults[claimCalls.clamp(0, claimResults.length - 1)];
    claimCalls++;
    if (result is ApiException) throw result;
    final response = delayedClaim != null
        ? await delayedClaim!.future
        : Map<String, dynamic>.from(result as Map);
    final block = status['adCoinReward'];
    if (block is Map<String, dynamic>) {
      status = {
        ...status,
        'adCoinReward': {
          ...block,
          'remainingToday': response['remainingToday'],
          'pendingGrant': false,
          'available': response['remainingToday'] != 0,
        },
      };
    }
    return response;
  }
}

class _FakeAdController
    implements ExtraSpinAdController, ContextBoundRewardedAdController {
  _FakeAdController({this.readyAfterLoad = true});

  final bool readyAfterLoad;
  bool _ready = false;
  int loadCalls = 0;
  int showCalls = 0;
  bool earnReward = true;
  bool supported = true;
  Completer<bool>? showCompleter;
  String? lastLoadLocalDate;
  int disposeContextCalls = 0;
  RewardedAdContext? lastContext;

  @override
  bool get isSupported => supported;

  @override
  bool get isReady => _ready;

  @override
  Future<void> load({required String userId, required String localDate}) async {
    loadCalls++;
    lastLoadLocalDate = localDate;
    _ready = readyAfterLoad;
  }

  @override
  Future<bool> showAndAwaitReward() async {
    showCalls++;
    _ready = false;
    return showCompleter?.future ?? Future.value(earnReward);
  }

  @override
  Future<void> warm(RewardedAdContext context) async {
    lastContext = context;
    await load(userId: context.userId, localDate: context.customData);
  }

  @override
  bool isReadyFor(RewardedAdContext context) =>
      _ready && lastContext == context;

  @override
  Future<bool> showAndAwaitRewardFor(RewardedAdContext context) async {
    if (!isReadyFor(context)) return false;
    return showAndAwaitReward();
  }

  @override
  void disposeContext(RewardedAdContext context) {
    disposeContextCalls++;
    if (lastContext == context) _ready = false;
  }

  @override
  void dispose() {}
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_coins': 125,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

const _liveOffer = <String, dynamic>{
  'available': true,
  'pendingGrant': false,
  'remainingToday': 5,
  'coinAmount': 25,
  'coinRewardMin': 25,
  'coinRewardMax': 50,
};
Future<AuthService> _pumpHome(
  WidgetTester tester,
  _FakeBackendApiService api,
  _FakeAdController ads, {
  bool tutorial = false,
  DateTime Function()? now,
  Size size = const Size(800, 1800),
  double textScale = 1,
  bool disposeAtTearDown = true,
}) async {
  final auth = await _createAuthService();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final rewards = RewardedCoinsController(
    auth: auth,
    api: api,
    ads: ads,
    now: now,
  );
  if (disposeAtTearDown) addTearDown(rewards.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: HomeTab(
          stepData: StepData(steps: 4200, date: DateTime.now()),
          isLoading: false,
          error: null,
          healthAuthorized: true,
          notificationsState: true,
          displayName: 'Capy',
          authService: auth,
          backendApiService: api,
          getCoinsAdController: ads,
          rewardedCoinsController: rewards,
          onRefresh: () async {},
          onEnableHealth: () {},
          onEnableNotifications: () {},
          onDisplayNameChanged: () {},
          friendsSteps: const [],
          isTutorialPreview: tutorial,
          raceCard: const {'state': 'EMPTY'},
        ),
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  return auth;
}

void main() {
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'test',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    ),
  );
  testWidgets(
    'Home places direct rewarded offer below milestones and before races',
    (tester) async {
      final api = _FakeBackendApiService(
        status: _status(adCoinReward: _liveOffer),
      );
      await _pumpHome(tester, api, _FakeAdController());
      expect(find.text('Bonus coins'), findsOneWidget);
      expect(
        find.text('Random 25–50 coins · 5 ads left today'),
        findsOneWidget,
      );
      final row = tester.getRect(find.byKey(const Key('home-rewarded-coins')));
      expect(
        row.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byType(StepMilestonesSection)).bottom,
        ),
      );
      expect(
        row.bottom,
        lessThanOrEqualTo(tester.getTopLeft(find.text('Suggested Races')).dy),
      );
    },
  );
  testWidgets('Home watches directly, updates balance and collapses at cap', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: _liveOffer),
      claimResults: const [
        {'coinAmount': 47, 'coins': 172, 'remainingToday': 0},
      ],
    );
    final ads = _FakeAdController();
    final auth = await _pumpHome(tester, api, ads);
    await tester.tap(find.text('WATCH AD'));
    await tester.pump();
    expect(ads.showCalls, 1);
    expect(api.claimCalls, 1);
    expect(auth.coins, 172);
    expect(find.text('Bonus coins'), findsNothing);
    expect(find.byType(GetCoinsScreen), findsNothing);
  });
  testWidgets('Home pending grant claims without showing another ad', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: {..._liveOffer, 'pendingGrant': true}),
    );
    final ads = _FakeAdController();
    await _pumpHome(tester, api, ads);
    await tester.tap(find.text('CLAIM COINS'));
    await tester.pump();
    expect(ads.showCalls, 0);
    expect(api.claimCalls, 1);
  });
  testWidgets('Home no fill and cancellation recover', (tester) async {
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: _liveOffer),
    );
    final ads = _FakeAdController(readyAfterLoad: false);
    await _pumpHome(tester, api, ads);
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pump();
    expect(ads.loadCalls, 2);
    expect(api.claimCalls, 0);
  });
  testWidgets('tutorial never loads the Home offer', (tester) async {
    final ads = _FakeAdController();
    await _pumpHome(
      tester,
      _FakeBackendApiService(status: _status(adCoinReward: _liveOffer)),
      ads,
      tutorial: true,
    );
    expect(find.text('Bonus coins'), findsNothing);
    expect(ads.loadCalls, 0);
  });
  for (final block in [
    null,
    <String, dynamic>{},
    {..._liveOffer, 'remainingToday': 'bad'},
    {..._liveOffer, 'remainingToday': 0},
  ]) {
    testWidgets('Home safely hides unavailable status $block', (tester) async {
      final ads = _FakeAdController();
      await _pumpHome(
        tester,
        _FakeBackendApiService(status: _status(adCoinReward: block)),
        ads,
      );
      expect(find.text('Bonus coins'), findsNothing);
      expect(ads.loadCalls, 0);
    });
  }
  testWidgets(
    'Home plus opens Shop and preserves Home claimed allowance on return',
    (tester) async {
      final api = _FakeBackendApiService(
        status: _status(adCoinReward: _liveOffer),
      );
      final ads = _FakeAdController();
      await _pumpHome(tester, api, ads);
      await tester.tap(find.text('WATCH AD'));
      await tester.pump();
      expect(
        find.text('Random 25–50 coins · 4 ads left today'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GetCoinsScreen), findsNothing);
      expect(find.byType(ShopTab), findsOneWidget);
      expect(find.text('WATCH AD · RANDOM COINS'), findsNothing);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Random 25–50 coins · 4 ads left today'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('WATCH AD'));
      await tester.pump();
      expect(ads.showCalls, 2);
      expect(api.claimCalls, 2);
    },
  );
  testWidgets('Home canceled video never claims and re-arms', (tester) async {
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: _liveOffer),
    );
    final ads = _FakeAdController()..earnReward = false;
    await _pumpHome(tester, api, ads);
    await tester.tap(find.text('WATCH AD'));
    await tester.pump();
    expect(api.claimCalls, 0);
    expect(ads.loadCalls, 2);
    expect(find.text('WATCH AD'), findsOneWidget);
  });
  testWidgets(
    'Home claim failure refreshes pending grant for direct recovery',
    (tester) async {
      final api = _FakeBackendApiService(
        status: _status(adCoinReward: _liveOffer),
        claimResults: [
          const ApiException('Unavailable', statusCode: 500),
          _claimResult,
        ],
      );
      final ads = _FakeAdController();
      await _pumpHome(tester, api, ads);
      api.status = _status(adCoinReward: {..._liveOffer, 'pendingGrant': true});
      await tester.tap(find.text('WATCH AD'));
      await tester.pump();
      expect(find.text('CLAIM COINS'), findsOneWidget);
      await tester.tap(find.text('CLAIM COINS'));
      await tester.pump();
      expect(ads.showCalls, 1);
      expect(api.claimCalls, 2);
    },
  );
  testWidgets('Home suppresses unsupported platforms without ad loads', (
    tester,
  ) async {
    final ads = _FakeAdController()..supported = false;
    await _pumpHome(
      tester,
      _FakeBackendApiService(status: _status(adCoinReward: _liveOffer)),
      ads,
    );
    expect(find.text('Bonus coins'), findsNothing);
    expect(ads.loadCalls, 0);
  });
  testWidgets('Home malformed reward range uses generic wording', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      _FakeBackendApiService(
        status: _status(
          adCoinReward: {
            ..._liveOffer,
            'coinRewardMin': 'bad',
            'coinRewardMax': null,
          },
        ),
      ),
      _FakeAdController(),
    );
    expect(find.text('Random coins · 5 ads left today'), findsOneWidget);
  });
  testWidgets('compact reward row fits narrow screens at large text scale', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: _liveOffer),
    );
    final auth = await _createAuthService();
    final rewards = RewardedCoinsController(
      auth: auth,
      api: api,
      ads: _FakeAdController(),
    );
    addTearDown(rewards.dispose);
    await rewards.refresh();
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: HomeRewardedCoins(controller: rewards)),
        ),
      ),
    );
    expect(find.text('WATCH AD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('late pre-claim status cannot restore spent Home allowance', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: _liveOffer),
      claimResults: const [
        {'coinAmount': 47, 'coins': 172, 'remainingToday': 0},
      ],
    );
    await _pumpHome(tester, api, _FakeAdController());
    final rewards = tester
        .widget<HomeRewardedCoins>(find.byType(HomeRewardedCoins))
        .controller;
    api.delayedStatus = Completer();
    final pendingStatus = rewards.refresh();
    await tester.tap(find.text('WATCH AD'));
    await tester.pump();
    api.delayedStatus!.complete(_status(adCoinReward: _liveOffer));
    await pendingStatus;
    await tester.pump();
    expect(find.text('Bonus coins'), findsNothing);
  });
  testWidgets('account switch while video shows never claims for new account', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: _liveOffer),
    );
    final ads = _FakeAdController()..showCompleter = Completer<bool>();
    final auth = await _pumpHome(tester, api, ads);
    await tester.tap(find.text('WATCH AD'));
    await tester.pump();
    await auth.syncFromBackendUser(const {'id': 'user-2'});
    ads.showCompleter!.complete(true);
    await tester.pump();
    expect(api.claimCalls, 0);
    expect(auth.coins, 125);
  });
  testWidgets('midnight while video shows never submits yesterday claim', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 6, 23, 59);
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: _liveOffer),
    );
    final ads = _FakeAdController()..showCompleter = Completer<bool>();
    await _pumpHome(tester, api, ads, now: () => now);
    await tester.tap(find.text('WATCH AD'));
    await tester.pump();
    now = DateTime(2026, 9, 7);
    ads.showCompleter!.complete(true);
    await tester.pump();
    expect(api.claimCalls, 0);
    expect(ads.lastContext?.localDate, '2026-09-07');
  });
  testWidgets('disposing standalone Home while video shows never claims', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: _liveOffer),
    );
    final ads = _FakeAdController()..showCompleter = Completer<bool>();
    await _pumpHome(tester, api, ads, disposeAtTearDown: false);
    final rewards = tester
        .widget<HomeRewardedCoins>(find.byType(HomeRewardedCoins))
        .controller;
    await tester.tap(find.text('WATCH AD'));
    await tester.pump();
    // Simulate shell/session disposal; route-only detach must not own this controller.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    rewards.dispose();
    ads.showCompleter!.complete(true);
    await tester.pump();
    expect(api.claimCalls, 0);
  });
  testWidgets(
    'foreground midnight restores exhausted Home offer without interaction',
    (tester) async {
      var now = DateTime(2026, 9, 6, 23, 59, 58);
      final api = _FakeBackendApiService(
        status: _status(
          adCoinReward: {
            ..._liveOffer,
            'remainingToday': 0,
            'available': false,
          },
        ),
      );
      await _pumpHome(tester, api, _FakeAdController(), now: () => now);
      expect(find.text('Bonus coins'), findsNothing);
      api.status = _status(adCoinReward: _liveOffer);
      now = DateTime(2026, 9, 7);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Bonus coins'), findsOneWidget);
    },
  );
  testWidgets('unsupported Get Coins retains server daily and referral state', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: {
        'claimedToday': true,
        'referralRewards': {'referrerCoins': 99, 'refereeCoins': 33},
      },
    );
    final auth = await _createAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: GetCoinsScreen(
          authService: auth,
          backendApiService: api,
          adController: _FakeAdController()..supported = false,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('CLAIMED TODAY'), findsOneWidget);
    expect(find.textContaining('99'), findsOneWidget);
  });
  testWidgets('Home pending status hides until eligibility arrives', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: _liveOffer),
    )..delayedStatus = Completer();
    final ads = _FakeAdController();
    await _pumpHome(tester, api, ads);
    expect(find.text('Bonus coins'), findsNothing);
    expect(ads.loadCalls, 0);
    api.delayedStatus!.complete(_status(adCoinReward: _liveOffer));
    await tester.pump();
    expect(find.text('WATCH AD'), findsOneWidget);
  });
  testWidgets(
    'Home status error hides safely and refresh recovers without health sync',
    (tester) async {
      final api = _FakeBackendApiService(
        status: _status(adCoinReward: _liveOffer),
      )..failStatus = true;
      final ads = _FakeAdController();
      await _pumpHome(tester, api, ads);
      expect(find.text('Bonus coins'), findsNothing);
      expect(ads.loadCalls, 0);
      api.failStatus = false;
      final rewards = tester
          .widget<HomeRewardedCoins>(find.byType(HomeRewardedCoins))
          .controller;
      await rewards.refresh();
      await tester.pump();
      expect(find.text('WATCH AD'), findsOneWidget);
    },
  );
  testWidgets('ordinary phone keeps reward action beside the copy', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: _liveOffer),
    );
    await _pumpHome(
      tester,
      api,
      _FakeAdController(),
      size: const Size(393, 1600),
    );
    final title = tester.getRect(find.text('Bonus coins'));
    final button = tester.getRect(find.text('WATCH AD'));
    expect(button.left, greaterThan(title.right));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Home pull refresh never waits on a pending reward status request',
    (tester) async {
      final api = _FakeBackendApiService(
        status: _status(adCoinReward: _liveOffer),
      );
      await _pumpHome(tester, api, _FakeAdController());
      api.delayedStatus = Completer();
      final refresh = tester
          .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator))
          .onRefresh;
      var completed = false;
      unawaited(refresh().then((_) => completed = true));
      await tester.pump();
      expect(completed, isTrue);
      api.delayedStatus!.complete(_status(adCoinReward: _liveOffer));
      await tester.pump();
      expect(find.text('WATCH AD'), findsOneWidget);
    },
  );
}
