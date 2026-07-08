import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/get_coins_screen.dart';
import 'package:step_tracker/screens/referral_screen.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// ---------------------------------------------------------------------------
// Get Coins hub (the "+" next to the coin balance): one page listing every way
// to earn coins — watch-ad-for-coins (SSV-verified, capped per day), invite
// friends (pushes the existing ReferralScreen), and the daily spin.
//
// The /daily-reward/status response may carry an additive `adCoinReward` block
// ({available, pendingGrant, remainingToday, coinAmount}) — only when the
// backend has the feature enabled AND this build declared `ads` in
// X-Client-Features. Old backends omit the field: no watch-ad section, ever.
// ---------------------------------------------------------------------------

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
  'coinAmount': 25,
  'coins': 150,
  'remainingToday': 2,
};

class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService({
    required this.status,
    this.claimResults = const [_claimResult],
  });

  final Map<String, dynamic> status;
  // One entry per expected claim attempt; an ApiException entry is thrown.
  final List<Object> claimResults;
  int claimCalls = 0;
  int statusCalls = 0;

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
    final result = claimResults[claimCalls.clamp(0, claimResults.length - 1)];
    claimCalls++;
    if (result is ApiException) throw result;
    return Map<String, dynamic>.from(result as Map);
  }
}

class _FakeAdController implements ExtraSpinAdController {
  _FakeAdController({this.readyAfterLoad = true});

  final bool readyAfterLoad;
  bool _ready = false;
  int loadCalls = 0;
  int showCalls = 0;
  bool earnReward = true;
  String? lastLoadLocalDate;

  @override
  bool get isSupported => true;

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
    'auth_coins': 125,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<AuthService> _pumpScreen(
  WidgetTester tester, {
  required _FakeBackendApiService api,
  ExtraSpinAdController? adController,
}) async {
  final auth = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: GetCoinsScreen(
        authService: auth,
        backendApiService: api,
        adController: adController,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return auth;
}

const _liveOffer = <String, dynamic>{
  'available': true,
  'pendingGrant': false,
  'remainingToday': 3,
  'coinAmount': 25,
};

void main() {
  testWidgets('renders all three earn methods when the offer is live', (
    tester,
  ) async {
    final api = _FakeBackendApiService(status: _status(adCoinReward: _liveOffer));
    final ads = _FakeAdController();
    await _pumpScreen(tester, api: api, adController: ads);

    expect(find.text('WATCH AD · +25 COINS'), findsOneWidget);
    expect(find.text('INVITE FRIENDS'), findsOneWidget);
    expect(find.text('OPEN DAILY BOX'), findsOneWidget);
    expect(ads.loadCalls, 1, reason: 'ad should preload when offer is live');
    // SSV custom_data carries the coins: prefix so the backend mints a
    // coin_reward grant, not an extra spin.
    expect(ads.lastLoadLocalDate, startsWith('coins:'));
  });

  testWidgets('watch-ad section hidden when the backend omits adCoinReward', (
    tester,
  ) async {
    final api = _FakeBackendApiService(status: _status());
    final ads = _FakeAdController();
    await _pumpScreen(tester, api: api, adController: ads);

    expect(find.textContaining('WATCH AD'), findsNothing);
    expect(ads.loadCalls, 0);
    // The other earn methods still render.
    expect(find.text('INVITE FRIENDS'), findsOneWidget);
  });

  testWidgets('tap: shows the ad, claims, updates coins and remaining count', (
    tester,
  ) async {
    final api = _FakeBackendApiService(status: _status(adCoinReward: _liveOffer));
    final ads = _FakeAdController();
    final auth = await _pumpScreen(tester, api: api, adController: ads);

    await tester.tap(find.text('WATCH AD · +25 COINS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ads.showCalls, 1);
    expect(api.claimCalls, 1);
    expect(auth.coins, 150);
    expect(find.textContaining('2 of 3'), findsOneWidget);
  });

  testWidgets('retries the claim while SSV has not landed yet', (tester) async {
    final api = _FakeBackendApiService(
      status: _status(adCoinReward: _liveOffer),
      claimResults: [
        const ApiException(
          'No verified ad reward available yet',
          statusCode: 409,
        ),
        _claimResult,
      ],
    );
    final ads = _FakeAdController();
    await _pumpScreen(tester, api: api, adController: ads);

    await tester.tap(find.text('WATCH AD · +25 COINS'));
    await tester.pump();
    expect(api.claimCalls, 1);

    // First attempt 409'd (AD_NOT_VERIFIED); the retry fires ~2s later.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.claimCalls, 2);
  });

  testWidgets(
    'user closes the ad without earning: no claim, and the ad re-arms '
    '(button returns to WATCH AD, never stuck on LOADING)',
    (tester) async {
      final api = _FakeBackendApiService(
        status: _status(adCoinReward: _liveOffer),
      );
      final ads = _FakeAdController()..earnReward = false;
      await _pumpScreen(tester, api: api, adController: ads);

      await tester.tap(find.text('WATCH AD · +25 COINS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.claimCalls, 0);
      expect(ads.loadCalls, 2, reason: 'a fresh ad should preload');
      expect(find.text('WATCH AD · +25 COINS'), findsOneWidget);
      expect(find.text('LOADING AD...'), findsNothing);
    },
  );

  testWidgets(
    'terminal claim failure refetches status and re-arms the ad '
    '(button recovers instead of sticking on LOADING)',
    (tester) async {
      final api = _FakeBackendApiService(
        status: _status(adCoinReward: _liveOffer),
        claimResults: [
          const ApiException('Internal server error', statusCode: 500),
        ],
      );
      final ads = _FakeAdController();
      await _pumpScreen(tester, api: api, adController: ads);

      await tester.tap(find.text('WATCH AD · +25 COINS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.claimCalls, 1);
      expect(api.statusCalls, 2, reason: 'status refetch picks up pendingGrant');
      expect(ads.loadCalls, greaterThanOrEqualTo(2));
      expect(find.text('WATCH AD · +25 COINS'), findsOneWidget);
      expect(find.text('LOADING AD...'), findsNothing);
    },
  );

  testWidgets('ad fails to load: tappable TRY AGAIN instead of stuck LOADING', (
    tester,
  ) async {
    final api = _FakeBackendApiService(status: _status(adCoinReward: _liveOffer));
    final ads = _FakeAdController(readyAfterLoad: false);
    await _pumpScreen(tester, api: api, adController: ads);

    expect(find.text('LOADING AD...'), findsNothing);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(ads.loadCalls, 1);

    await tester.tap(find.text('TRY AGAIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(ads.loadCalls, 2);
  });

  testWidgets('pendingGrant claims directly without showing another ad', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(
        adCoinReward: {
          'available': true,
          'pendingGrant': true,
          'remainingToday': 3,
          'coinAmount': 25,
        },
      ),
    );
    final ads = _FakeAdController(readyAfterLoad: false);
    await _pumpScreen(tester, api: api, adController: ads);

    await tester.tap(find.text('CLAIM +25 COINS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(ads.showCalls, 0);
    expect(api.claimCalls, 1);
  });

  testWidgets('cap exhausted shows come-back-tomorrow and never loads an ad', (
    tester,
  ) async {
    final api = _FakeBackendApiService(
      status: _status(
        adCoinReward: {
          'available': false,
          'pendingGrant': false,
          'remainingToday': 0,
          'coinAmount': 25,
        },
      ),
    );
    final ads = _FakeAdController();
    await _pumpScreen(tester, api: api, adController: ads);

    expect(find.text('COME BACK TOMORROW'), findsOneWidget);
    expect(find.textContaining('WATCH AD ·'), findsNothing);
    expect(ads.loadCalls, 0);
  });

  testWidgets('INVITE FRIENDS pushes the existing ReferralScreen', (
    tester,
  ) async {
    final api = _FakeBackendApiService(status: _status(adCoinReward: _liveOffer));
    await _pumpScreen(tester, api: api, adController: _FakeAdController());

    await tester.tap(find.text('SHARE INVITE LINK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ReferralScreen), findsOneWidget);
  });

  testWidgets('the shop "+" opens the Get Coins hub, not the referral screen', (
    tester,
  ) async {
    final auth = await _createAuthService();
    final api = _FakeBackendApiService(status: _status(adCoinReward: _liveOffer));
    await tester.pumpWidget(
      MaterialApp(home: ShopTab(authService: auth, backendApiService: api)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(GetCoinsScreen), findsOneWidget);
    expect(find.byType(ReferralScreen), findsNothing);
  });
}
