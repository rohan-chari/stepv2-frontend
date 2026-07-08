import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/daily_reward_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _BoxModeApi extends BackendApiService {
  _BoxModeApi({this.claimedToday = false, this.odds});

  final bool claimedToday;
  final Map<String, dynamic>? odds;
  int legacyClaimCalls = 0;
  int boxClaimCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    return {
      'cycleLength': 6,
      'currentDay': 1,
      'claimedToday': claimedToday,
      'ladder': const [],
      'box': {
        'streak': 7,
        'streakCap': 30,
        'odds': odds ?? {'COMMON': 0.6, 'UNCOMMON': 0.27, 'RARE': 0.13},
        'coinRanges': {
          'COMMON': [10, 30],
          'UNCOMMON': [40, 80],
        },
        'accessoryPool': [
          {'id': 'a1', 'assetKey': 'cowboy_hat', 'name': 'Cowboy Hat'},
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> claimDailyReward({
    required String identityToken,
    required String localDate,
  }) async {
    legacyClaimCalls += 1;
    return const {'rewardType': 'COINS', 'coinAmount': 10, 'coins': 10};
  }

  @override
  Future<Map<String, dynamic>> claimDailyRewardBox({
    required String identityToken,
    required String localDate,
  }) async {
    boxClaimCalls += 1;
    return const {
      'rarity': 'UNCOMMON',
      'rewardType': 'COINS',
      'coinAmount': 55,
      'shopItem': null,
      'coins': 155,
      'streak': 7,
    };
  }
}

// Old backend: no `box` field in the status response.
class _LegacyApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    return {
      'cycleLength': 6,
      'currentDay': 1,
      'claimedToday': false,
      'ladder': [
        for (int day = 1; day <= 6; day++)
          {
            'day': day,
            'reward': day == 6
                ? {'type': 'ACCESSORY'}
                : {'type': 'COINS', 'coinAmount': day * 10},
            'claimed': false,
            'isToday': day == 1,
          },
      ],
    };
  }
}

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

// SpinningCoin animates forever, so pumpAndSettle never settles on screens
// that show coins (legacy ladder, coin reveal) — pump fixed frames instead.
Future<void> _pumpScreen(
  WidgetTester tester,
  BackendApiService api,
  AuthService auth,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DailyRewardScreen(authService: auth, backendApiService: api),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('box mode goes straight to the reel WITHOUT claiming', (
    WidgetTester tester,
  ) async {
    final auth = await _authService();
    final api = _BoxModeApi();
    await _pumpScreen(tester, api, auth);

    // No intermediate screen, and — deferred roll — no claim yet: closing
    // now must leave today's box unclaimed.
    expect(api.boxClaimCalls, 0);
    expect(find.text('OPEN BOX'), findsNothing);
    expect(find.text('SWIPE OR TAP'), findsOneWidget);
    expect(find.text('7-DAY STREAK'), findsOneWidget);
    expect(find.text('CLAIM TODAY'), findsNothing);
  });

  testWidgets('? tooltip explains streak odds with percentages', (
    WidgetTester tester,
  ) async {
    final auth = await _authService();
    await _pumpScreen(tester, _BoxModeApi(), auth);

    await tester.tap(find.text('?').first);
    await tester.pumpAndSettle();

    expect(find.text('HOW IT WORKS'), findsOneWidget);
    expect(find.textContaining('longer your streak'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('27%'), findsOneWidget);
    expect(find.text('13%'), findsOneWidget);

    await tester.tap(find.text('GOT IT'));
    await tester.pumpAndSettle();
    expect(find.text('HOW IT WORKS'), findsNothing);
  });

  testWidgets('opening the box spins the case reel and reveals rarity', (
    WidgetTester tester,
  ) async {
    final auth = await _authService();
    final api = _BoxModeApi();
    await _pumpScreen(tester, api, auth);

    // Reel armed, nothing claimed yet — the swipe is what claims.
    expect(api.boxClaimCalls, 0);
    expect(api.legacyClaimCalls, 0);
    expect(find.text('SWIPE OR TAP'), findsOneWidget);
    expect(find.text('CLAIMED!'), findsNothing);

    // Swipe: claim fires, then 4s scroll + 600ms pause, then the reveal.
    await tester.tap(find.text('SWIPE OR TAP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.boxClaimCalls, 1);
    expect(find.text('OPENING...'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('CLAIMED!'), findsOneWidget);
    expect(find.text('UNCOMMON'), findsOneWidget);
    expect(find.text('+55 COINS'), findsOneWidget);
  });

  testWidgets('reel decoys show real accessories at the live odds', (
    WidgetTester tester,
  ) async {
    final auth = await _authService();
    // RARE odds pinned to 1.0: every decoy tile must be an accessory drawn
    // from the pool the backend says is winnable.
    final api = _BoxModeApi(
      odds: {'COMMON': 0.0, 'UNCOMMON': 0.0, 'RARE': 1.0},
    );
    await _pumpScreen(tester, api, auth);

    expect(find.text('SWIPE OR TAP'), findsOneWidget);
    expect(find.text('Cowboy Hat'), findsWidgets);
  });

  testWidgets('already-claimed box mode shows come-back state, no claim', (
    WidgetTester tester,
  ) async {
    final auth = await _authService();
    final api = _BoxModeApi(claimedToday: true);
    await _pumpScreen(tester, api, auth);

    expect(api.boxClaimCalls, 0);
    expect(find.text('COME BACK TOMORROW'), findsOneWidget);
    expect(find.text('SWIPE OR TAP'), findsNothing);
  });

  testWidgets('falls back to legacy ladder when backend has no box field', (
    WidgetTester tester,
  ) async {
    final auth = await _authService();
    await _pumpScreen(tester, _LegacyApi(), auth);

    expect(find.text('CLAIM TODAY'), findsOneWidget);
    expect(find.text('OPEN BOX'), findsNothing);
    expect(find.text('DAY 1'), findsOneWidget);
  });
}
