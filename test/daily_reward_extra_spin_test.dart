import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/daily_reward_screen.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/case_opening_strip.dart';
import 'package:step_tracker/widgets/extra_spin_reward_ticket.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/streak_chip.dart';

// ---------------------------------------------------------------------------
// Rewarded-ad extra daily box spin.
//
// The /daily-reward/status response may carry an additive `adExtraSpin` block
// ({available, pendingGrant, used}) — only when the backend has the feature
// enabled AND this build declared `ads` in X-Client-Features. When present and
// not yet used, the screen offers "WATCH AD · +1 SPIN" after the free box:
// show rewarded ad -> AdMob SSV mints a grant server-side -> client calls
// claim-extra-box (retrying briefly while SSV lags) -> the normal reel spins
// again with the extra roll. Old backends omit the field: no button, ever.
// ---------------------------------------------------------------------------

const _box = <String, dynamic>{
  'streak': 3,
  'streakCap': 30,
  'odds': {'COMMON': 0.65, 'UNCOMMON': 0.26, 'RARE': 0.09},
  'coinRanges': {
    'COMMON': [10, 30],
    'UNCOMMON': [40, 80],
  },
  'accessoryPool': <dynamic>[],
};

Map<String, dynamic> _status({Map<String, dynamic>? adExtraSpin}) {
  return {
    'claimedToday': true,
    'cycleLength': 6,
    'currentDay': 3,
    'ladder': <dynamic>[],
    'box': _box,
    'adExtraSpin': ?adExtraSpin,
  };
}

const _extraResult = <String, dynamic>{
  'rarity': 'COMMON',
  'rewardType': 'COINS',
  'coinAmount': 20,
  'shopItem': null,
  'coins': 520,
  'streak': 3,
  'extra': true,
};

class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService({
    required this.status,
    this.claimResults = const [_extraResult],
  });

  final Map<String, dynamic> status;
  // One entry per expected claim attempt; an ApiException entry is thrown.
  final List<Object> claimResults;
  int claimCalls = 0;
  final List<String> claimDates = [];

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    return status;
  }

  @override
  Future<Map<String, dynamic>> claimExtraDailyRewardBox({
    required String identityToken,
    required String localDate,
  }) async {
    claimDates.add(localDate);
    final result = claimResults[claimCalls.clamp(0, claimResults.length - 1)];
    claimCalls++;
    if (result is ApiException) throw result;
    return Map<String, dynamic>.from(result as Map);
  }
}

class _FakeAdController implements ExtraSpinAdController {
  _FakeAdController({this.readyAfterLoad = true});

  final bool supported = true;
  final bool readyAfterLoad;
  bool _ready = false;
  int loadCalls = 0;
  int showCalls = 0;
  int disposeCalls = 0;
  bool earnReward = true;

  @override
  bool get isSupported => supported;

  @override
  bool get isReady => _ready;

  @override
  Future<void> load({required String userId, required String localDate}) async {
    loadCalls++;
    _ready = readyAfterLoad;
  }

  @override
  Future<bool> showAndAwaitReward() async {
    showCalls++;
    _ready = false;
    return earnReward;
  }

  @override
  void dispose() => disposeCalls++;
}

class _UnsupportedAdController implements ExtraSpinAdController {
  @override
  bool get isReady => false;

  @override
  bool get isSupported => false;

  @override
  void dispose() {}

  @override
  Future<void> load({
    required String userId,
    required String localDate,
  }) async {}

  @override
  Future<bool> showAndAwaitReward() async => false;
}

class _RecordingAnalytics extends ActivationAnalyticsService {
  _RecordingAnalytics()
    : super(backendApiService: _FakeBackendApiService(status: _status()));

  final events = <(String, Map<String, String>)>[];

  @override
  Future<void> record(
    String name, {
    String? sessionId,
    String? ownerUserId,
    Map<String, String> context = const {},
  }) async {
    events.add((name, context));
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeBackendApiService api,
  ExtraSpinAdController? adController,
  AuthService? authService,
  ActivationAnalyticsService? analytics,
  DateTime Function()? now,
}) async {
  final auth = authService ?? await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: DailyRewardScreen(
        authService: auth,
        backendApiService: api,
        adController: adController,
        analytics: analytics,
        now: now,
      ),
    ),
  );
  // Let the status fetch land. (No pumpAndSettle: screen has looping anims.)
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Step Tracker',
      packageName: 'com.example.steptracker',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'extra spin is the primary action when adExtraSpin is available',
    (tester) async {
      final api = _FakeBackendApiService(
        status: _status(
          adExtraSpin: {
            'available': true,
            'pendingGrant': false,
            'used': false,
          },
        ),
      );
      final ads = _FakeAdController();
      await _pumpScreen(tester, api: api, adController: ads);

      expect(find.text('SPIN AGAIN'), findsOneWidget);
      expect(find.text('COME BACK TOMORROW'), findsNothing);
      expect(ads.loadCalls, 1, reason: 'ad should preload when offer is live');
    },
  );

  testWidgets('no button when the backend omits adExtraSpin (old backend)', (
    tester,
  ) async {
    final api = _FakeBackendApiService(status: _status());
    final ads = _FakeAdController();
    await _pumpScreen(tester, api: api, adController: ads);

    expect(find.text('SPIN AGAIN'), findsNothing);
    expect(ads.loadCalls, 0);
  });

  testWidgets('come-back-tomorrow shows once the extra spin was used', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(
        adExtraSpin: {'available': false, 'pendingGrant': false, 'used': true},
      ),
    );
    await _pumpScreen(tester, api: api, adController: _FakeAdController());

    expect(find.text('SPIN AGAIN'), findsNothing);
    expect(find.text('REWARD CLAIMED'), findsOneWidget);
  });

  testWidgets(
    'home chip renders an accessible reward ticket from the batch payload',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final auth = await _createAuthService();
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final localDate = '${now.year}-${two(now.month)}-${two(now.day)}';

      Widget chip(Map<String, dynamic> adExtraSpin) => MaterialApp(
        home: Scaffold(
          body: StreakChip(
            authService: auth,
            backendApiService: _FakeBackendApiService(status: _status()),
            adController: _FakeAdController(),
            initialData: {
              'claimedToday': true,
              'localDate': localDate,
              'adExtraSpin': adExtraSpin,
            },
          ),
        ),
      );

      await tester.pumpWidget(
        chip({'available': true, 'pendingGrant': false, 'used': false}),
      );
      await tester.pump();
      expect(find.byType(ExtraSpinRewardTicket), findsOneWidget);
      expect(find.text('DAILY REWARD'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Daily reward. One more spin is ready.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Daily reward. One more spin is ready.'),
        ),
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          label: 'Daily reward. One more spin is ready.',
        ),
      );
      semantics.dispose();

      // Used-up offer degrades to the plain claimed state.
      await tester.pumpWidget(
        chip({'available': false, 'pendingGrant': false, 'used': true}),
      );
      await tester.pump();
      expect(find.text('DAILY REWARD'), findsOneWidget);
    },
  );

  testWidgets('home ticket never warms while a verified grant is pending', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final ads = _FakeAdController();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final localDate = '${now.year}-${two(now.month)}-${two(now.day)}';

    await tester.pumpWidget(
      MaterialApp(
        home: StreakChip(
          authService: auth,
          backendApiService: _FakeBackendApiService(status: _status()),
          adController: ads,
          initialData: {
            'claimedToday': true,
            'localDate': localDate,
            'adExtraSpin': const {
              'available': true,
              'pendingGrant': true,
              'used': false,
            },
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ExtraSpinRewardTicket), findsOneWidget);
    expect(ads.loadCalls, 0);
  });

  testWidgets('Home resume gives a failed ticket preload one bounded retry', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final ads = _FakeAdController(readyAfterLoad: false);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final localDate = '${now.year}-${two(now.month)}-${two(now.day)}';

    await tester.pumpWidget(
      MaterialApp(
        home: StreakChip(
          authService: auth,
          backendApiService: _FakeBackendApiService(
            status: _status(
              adExtraSpin: const {
                'available': true,
                'pendingGrant': false,
                'used': false,
              },
            ),
          ),
          adController: ads,
          initialData: {
            'claimedToday': true,
            'localDate': localDate,
            'adExtraSpin': const {
              'available': true,
              'pendingGrant': false,
              'used': false,
            },
          },
        ),
      ),
    );
    await tester.pump();
    expect(ads.loadCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(ads.loadCalls, 2);
  });

  testWidgets('extra-spin pill keeps the existing quick-action footprint', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = await _createAuthService();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final localDate = '${now.year}-${two(now.month)}-${two(now.day)}';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: StreakChip(
                  authService: auth,
                  backendApiService: _FakeBackendApiService(status: _status()),
                  adController: _FakeAdController(),
                  initialData: {
                    'claimedToday': true,
                    'localDate': localDate,
                    'adExtraSpin': const {
                      'available': true,
                      'pendingGrant': false,
                      'used': false,
                    },
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton(
                  key: const Key('reference-shop-pill'),
                  label: 'SHOP',
                  icon: Icons.storefront_rounded,
                  variant: PillButtonVariant.secondary,
                  fullWidth: true,
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));

    expect(tester.takeException(), isNull);
    // The 900ms shimmer/pop repeats every six seconds, so its controller stays
    // alive even while the button has returned to its resting size.
    expect(tester.binding.hasScheduledFrame, isTrue);
    final ticket = tester.getRect(find.byType(ExtraSpinRewardTicket));
    final shop = tester.getRect(find.byKey(const Key('reference-shop-pill')));
    expect(ticket.size, shop.size);
  });

  testWidgets('ticket immediately settles when Reduce Motion turns on', (
    tester,
  ) async {
    Widget ticket({required bool disableAnimations}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: ExtraSpinRewardTicket(onPressed: () {})),
      ),
    );

    await tester.pumpWidget(ticket(disableAnimations: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(ticket(disableAnimations: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('ticket tap records Home context then opens the shared sheet', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final analytics = _RecordingAnalytics();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final localDate = '${now.year}-${two(now.month)}-${two(now.day)}';
    final api = _FakeBackendApiService(
      status: _status(
        adExtraSpin: {'available': true, 'pendingGrant': false, 'used': false},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreakChip(
            authService: auth,
            backendApiService: api,
            adController: _FakeAdController(),
            analytics: analytics,
            initialData: {
              'claimedToday': true,
              'localDate': localDate,
              'adExtraSpin': const {
                'available': true,
                'pendingGrant': false,
                'used': false,
              },
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(ExtraSpinRewardTicket));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      analytics.events,
      contains(('extra_spin_cta_tapped', const {'surface': 'home'})),
    );
    expect(find.byType(DailyRewardScreen), findsOneWidget);
  });

  testWidgets('ad-load failure offers an actionable retry', (tester) async {
    final api = _FakeBackendApiService(
      status: _status(
        adExtraSpin: {'available': true, 'pendingGrant': false, 'used': false},
      ),
    );
    final ads = _FakeAdController(readyAfterLoad: false);
    await _pumpScreen(tester, api: api, adController: ads);

    expect(find.text('SPIN AGAIN'), findsOneWidget);
  });

  testWidgets('daily screen records ready, tap, completion, and claim stages', (
    tester,
  ) async {
    final analytics = _RecordingAnalytics();
    final api = _FakeBackendApiService(
      status: _status(
        adExtraSpin: {'available': true, 'pendingGrant': false, 'used': false},
      ),
    );
    await _pumpScreen(
      tester,
      api: api,
      adController: _FakeAdController(),
      analytics: analytics,
    );

    await tester.tap(find.text('SPIN AGAIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      analytics.events.map((event) => event.$1),
      containsAllInOrder(const [
        'extra_spin_offer_shown',
        'extra_spin_ad_ready',
        'extra_spin_cta_tapped',
        'extra_spin_ad_completed',
        'extra_spin_claim_succeeded',
      ]),
    );
    expect(
      analytics.events.every((event) => event.$2.isEmpty),
      isTrue,
      reason: 'shared routes without a known source must not invent surface',
    );
  });

  testWidgets('not-ready load records a bounded failure result', (
    tester,
  ) async {
    final analytics = _RecordingAnalytics();
    await _pumpScreen(
      tester,
      api: _FakeBackendApiService(
        status: _status(
          adExtraSpin: {
            'available': true,
            'pendingGrant': false,
            'used': false,
          },
        ),
      ),
      adController: _FakeAdController(readyAfterLoad: false),
      analytics: analytics,
    );

    expect(
      analytics.events.any(
        (event) =>
            event.$1 == 'extra_spin_ad_not_ready' &&
            event.$2['result'] == 'load_failed' &&
            event.$2.length == 1,
      ),
      isTrue,
    );
  });

  testWidgets('missing or malformed adExtraSpin never advertises an ad', (
    tester,
  ) async {
    final malformed = _status(
      adExtraSpin: {'available': 'yes', 'pendingGrant': false, 'used': false},
    );
    final ads = _FakeAdController();
    await _pumpScreen(
      tester,
      api: _FakeBackendApiService(status: malformed),
      adController: ads,
    );

    expect(find.text('SPIN AGAIN'), findsNothing);
    expect(ads.loadCalls, 0);
  });

  testWidgets('unsupported builds do not render the CTA or load an ad', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      api: _FakeBackendApiService(
        status: _status(
          adExtraSpin: {
            'available': true,
            'pendingGrant': false,
            'used': false,
          },
        ),
      ),
      adController: _UnsupportedAdController(),
    );

    expect(find.text('SPIN AGAIN'), findsNothing);
  });

  testWidgets('tap: shows the ad, claims, and spins the reel again', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(
        adExtraSpin: {'available': true, 'pendingGrant': false, 'used': false},
      ),
    );
    final ads = _FakeAdController();
    await _pumpScreen(tester, api: api, adController: ads);

    await tester.tap(find.text('SPIN AGAIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ads.showCalls, 1);
    expect(api.claimCalls, 1);
    expect(find.byType(CaseOpeningReel), findsOneWidget);
    // Offer is single-use: no second button behind the reel.
    expect(find.text('SPIN AGAIN'), findsNothing);
  });

  testWidgets('pendingGrant claims directly without showing another ad', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(
        adExtraSpin: {'available': true, 'pendingGrant': true, 'used': false},
      ),
    );
    final ads = _FakeAdController(readyAfterLoad: false);
    await _pumpScreen(tester, api: api, adController: ads);

    // A verified-but-unredeemed watch exists: claim it, don't run a new ad.
    await tester.tap(find.text('SPIN AGAIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ads.showCalls, 0);
    expect(api.claimCalls, 1);
    expect(find.byType(CaseOpeningReel), findsOneWidget);
  });

  testWidgets('midnight invalidates the stale extra-spin ad', (tester) async {
    var now = DateTime(2026, 8, 25, 23, 59);
    final api = _FakeBackendApiService(
      status: _status(
        adExtraSpin: {'available': true, 'pendingGrant': false, 'used': false},
      ),
    );
    await _pumpScreen(
      tester,
      api: api,
      adController: _FakeAdController(),
      now: () => now,
    );

    now = DateTime(2026, 8, 26, 0, 1);
    await tester.tap(find.text('SPIN AGAIN'));
    await tester.pump();

    expect(api.claimDates, isEmpty);
  });

  testWidgets('retries the claim while SSV has not landed yet', (tester) async {
    final api = _FakeBackendApiService(
      status: _status(
        adExtraSpin: {'available': true, 'pendingGrant': false, 'used': false},
      ),
      claimResults: [
        const ApiException(
          'No verified ad reward available yet',
          statusCode: 409,
        ),
        _extraResult,
      ],
    );
    final ads = _FakeAdController();
    await _pumpScreen(tester, api: api, adController: ads);

    await tester.tap(find.text('SPIN AGAIN'));
    await tester.pump();
    expect(api.claimCalls, 1);

    // First attempt 409'd (AD_NOT_VERIFIED); the retry fires ~2s later.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.claimCalls, 2);
    expect(find.byType(CaseOpeningReel), findsOneWidget);
  });

  testWidgets('user closes the ad without earning: no claim, offer stays', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(
        adExtraSpin: {'available': true, 'pendingGrant': false, 'used': false},
      ),
    );
    final ads = _FakeAdController()..earnReward = false;
    await _pumpScreen(tester, api: api, adController: ads);

    await tester.tap(find.text('SPIN AGAIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.claimCalls, 0);
    expect(find.byType(CaseOpeningReel), findsNothing);
  });
}
