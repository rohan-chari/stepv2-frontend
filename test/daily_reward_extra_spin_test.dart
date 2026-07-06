import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/daily_reward_screen.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/case_opening_strip.dart';
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
  void dispose() {}
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
}) async {
  final auth = authService ?? await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: DailyRewardScreen(
        authService: auth,
        backendApiService: api,
        adController: adController,
      ),
    ),
  );
  // Let the status fetch land. (No pumpAndSettle: screen has looping anims.)
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('extra spin is the primary action when adExtraSpin is available', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(
        adExtraSpin: {'available': true, 'pendingGrant': false, 'used': false},
      ),
    );
    final ads = _FakeAdController();
    await _pumpScreen(tester, api: api, adController: ads);

    expect(find.text('WATCH AD · +1 SPIN'), findsOneWidget);
    expect(find.text('COME BACK TOMORROW'), findsNothing);
    expect(ads.loadCalls, 1, reason: 'ad should preload when offer is live');
  });

  testWidgets('no button when the backend omits adExtraSpin (old backend)', (
    tester,
  ) async {
    final api = _FakeBackendApiService(status: _status());
    final ads = _FakeAdController();
    await _pumpScreen(tester, api: api, adController: ads);

    expect(find.text('WATCH AD · +1 SPIN'), findsNothing);
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

    expect(find.text('WATCH AD · +1 SPIN'), findsNothing);
    expect(find.text('COME BACK TOMORROW'), findsOneWidget);
  });

  testWidgets('home chip shows EXTRA SPIN from the batch payload', (
    tester,
  ) async {
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
    expect(find.text('EXTRA SPIN'), findsOneWidget);

    // Used-up offer degrades to the plain claimed state.
    await tester.pumpWidget(
      chip({'available': false, 'pendingGrant': false, 'used': true}),
    );
    await tester.pump();
    expect(find.text('CLAIMED'), findsOneWidget);
  });

  testWidgets('button disabled while the ad has not loaded', (tester) async {
    final api = _FakeBackendApiService(
      status: _status(
        adExtraSpin: {'available': true, 'pendingGrant': false, 'used': false},
      ),
    );
    final ads = _FakeAdController(readyAfterLoad: false);
    await _pumpScreen(tester, api: api, adController: ads);

    expect(find.text('LOADING AD...'), findsOneWidget);
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

    await tester.tap(find.text('WATCH AD · +1 SPIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ads.showCalls, 1);
    expect(api.claimCalls, 1);
    expect(find.byType(CaseOpeningReel), findsOneWidget);
    // Offer is single-use: no second button behind the reel.
    expect(find.text('WATCH AD · +1 SPIN'), findsNothing);
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
    await tester.tap(find.text('CLAIM EXTRA SPIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ads.showCalls, 0);
    expect(api.claimCalls, 1);
    expect(find.byType(CaseOpeningReel), findsOneWidget);
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

    await tester.tap(find.text('WATCH AD · +1 SPIN'));
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

    await tester.tap(find.text('WATCH AD · +1 SPIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.claimCalls, 0);
    expect(find.byType(CaseOpeningReel), findsNothing);
  });
}
