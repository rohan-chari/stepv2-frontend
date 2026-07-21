import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/daily_reward_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Spec §6.3.B.9-10 / test plan 24: the daily-reward box exposes an exact-odds
/// sheet built from `box.itemOdds` (including the COINS slice of `rareMix`,
/// which the legacy `rarePrizeMix` omits), and hides the affordance entirely
/// when the field is absent or malformed.
class _ItemOddsApi extends BackendApiService {
  _ItemOddsApi({this.itemOdds, this.odds, this.claimedToday = true});

  final Map<String, dynamic>? itemOdds;
  final Map<String, dynamic>? odds;
  final bool claimedToday;

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    return {
      'cycleLength': 6,
      'currentDay': 1,
      // Claimed: keeps the screen on the box card instead of auto-opening the
      // reel, so the affordance is assertable without driving a spin.
      'claimedToday': claimedToday,
      'ladder': const [],
      'box': {
        'streak': 7,
        'streakCap': 30,
        if (odds != null) 'odds': odds,
        'coinRanges': {
          'COMMON': [10, 30],
          'UNCOMMON': [40, 80],
        },
        'accessoryPool': const [
          {'id': 'a1', 'assetKey': 'cowboy_hat', 'name': 'Cowboy Hat'},
        ],
        if (itemOdds != null) 'itemOdds': itemOdds,
      },
    };
  }
}

const _validItemOdds = {
  'configVersion': 7,
  'rarity': {'COMMON': 0.44, 'UNCOMMON': 0.31, 'RARE': 0.25},
  'rareMix': {'ACCESSORY': 0.4, 'POWERUP': 0.4, 'COINS': 0.2},
  'accessories': [
    {'sku': 'cowboy_hat', 'p': 1.0},
  ],
  'powerups': [
    {'type': 'SIGNAL_JAMMER', 'p': 1.0},
  ],
};

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pumpScreen(WidgetTester tester, BackendApiService api) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: DailyRewardScreen(
        authService: await _authService(),
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('itemOdds present -> ODDS sheet renders rarity, the rareMix '
      'COINS slice, and the accessory + powerup slices', (
    WidgetTester tester,
  ) async {
    await _pumpScreen(tester, _ItemOddsApi(itemOdds: _validItemOdds));

    expect(find.text('ODDS'), findsOneWidget);
    await tester.tap(find.text('ODDS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('BOX ODDS'), findsOneWidget);
    expect(find.text('44%'), findsOneWidget);
    expect(find.text('31%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);

    // rareMix INCLUDING the coins slice — the fix for audit register #9.
    expect(find.text('ACCESSORY'), findsOneWidget);
    expect(find.text('POWERUP'), findsOneWidget);
    expect(find.text('COINS'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);
  });

  testWidgets('itemOdds absent -> no ODDS affordance (old backend)', (
    WidgetTester tester,
  ) async {
    await _pumpScreen(tester, _ItemOddsApi());

    expect(find.text('ODDS'), findsNothing);
    // The legacy "?" HOW IT WORKS affordance is untouched.
    expect(find.text('?'), findsWidgets);
  });

  testWidgets('malformed itemOdds -> no ODDS affordance, no crash', (
    WidgetTester tester,
  ) async {
    await _pumpScreen(
      tester,
      _ItemOddsApi(
        itemOdds: const {
          'configVersion': 7,
          // Sums to 0.4 — never render partial odds.
          'rarity': {'COMMON': 0.2, 'UNCOMMON': 0.1, 'RARE': 0.1},
          'rareMix': {'ACCESSORY': 0.4, 'POWERUP': 0.4, 'COINS': 0.2},
        },
      ),
    );

    expect(find.text('ODDS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reel decoy fallback odds match a real backend row (0.70/0.25) '
      'when the backend omits box.odds', (WidgetTester tester) async {
    // Audit register #8: the old 0.50/0.35 fallbacks matched NO backend row.
    // With odds omitted the decoys must be drawn at the streak-1 row, so RARE
    // decoys (accessories) are ~5% and coin tiles dominate.
    await _pumpScreen(tester, _ItemOddsApi(claimedToday: false));

    expect(dailyBoxFallbackOdds['COMMON'], 0.70);
    expect(dailyBoxFallbackOdds['UNCOMMON'], 0.25);
    expect(dailyBoxFallbackOdds['RARE'], closeTo(0.05, 1e-9));
    expect(find.text('SWIPE OR TAP'), findsOneWidget);
  });
}
