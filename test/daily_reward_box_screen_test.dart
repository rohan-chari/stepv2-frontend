import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/daily_reward_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';

class _BoxModeApi extends BackendApiService {
  _BoxModeApi({
    this.claimedToday = false,
    this.odds,
    this.powerupPool,
    this.rarePrizeMix,
    this.boxResult,
  });

  final bool claimedToday;
  final Map<String, dynamic>? odds;
  final List<Map<String, dynamic>>? powerupPool;
  final Map<String, dynamic>? rarePrizeMix;
  final Map<String, dynamic>? boxResult;
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
        if (powerupPool != null) 'powerupPool': powerupPool,
        if (rarePrizeMix != null) 'rarePrizeMix': rarePrizeMix,
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
    return boxResult ??
        const {
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
  AuthService auth, {
  ThemeMode themeMode = ThemeMode.light,
  Size? surfaceSize,
  TextScaler textScaler = TextScaler.noScaling,
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  if (surfaceSize != null) {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemeData.light().copyWith(platform: platform),
      darkTheme: AppThemeData.night().copyWith(platform: platform),
      themeMode: themeMode,
      home: MediaQuery(
        data: MediaQueryData(
          size: surfaceSize ?? const Size(390, 844),
          textScaler: textScaler,
          padding: platform == TargetPlatform.iOS
              ? const EdgeInsets.only(top: 47, bottom: 34)
              : const EdgeInsets.only(top: 24),
        ),
        child: DailyRewardScreen(authService: auth, backendApiService: api),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Taste redesign', () {
    testWidgets('claimed night state uses the restored popup metadata', (
      tester,
    ) async {
      final auth = await _authService();
      await _pumpScreen(
        tester,
        _BoxModeApi(claimedToday: true),
        auth,
        themeMode: ThemeMode.dark,
      );

      expect(find.byKey(const Key('daily-reward-header')), findsNothing);
      expect(find.byKey(const Key('daily-reward-streak-line')), findsNothing);
      expect(
        find.byKey(const Key('daily-reward-claimed-status')),
        findsNothing,
      );
      expect(find.byKey(const Key('daily-reward-streak-pill')), findsOneWidget);
      expect(find.text('DAILY REWARD'), findsOneWidget);
      expect(find.text('COME BACK TOMORROW'), findsOneWidget);
    });

    testWidgets('night reel is a flat focal surface and fits narrow text', (
      tester,
    ) async {
      final auth = await _authService();
      await _pumpScreen(
        tester,
        _BoxModeApi(),
        auth,
        themeMode: ThemeMode.dark,
        surfaceSize: const Size(320, 700),
        textScaler: const TextScaler.linear(1.3),
      );

      expect(
        find.byKey(const Key('case-opening-reel-viewport')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

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

  testWidgets('popup hides odds/help and pins a tappable close affordance', (
    WidgetTester tester,
  ) async {
    final auth = await _authService();
    await _pumpScreen(tester, _BoxModeApi(), auth);

    expect(find.text('% ODDS'), findsNothing);
    expect(find.text('?'), findsNothing);
    final close = find.bySemanticsLabel('Close daily reward');
    expect(close, findsOneWidget);
    expect(tester.getSize(close).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('claimed box uses the exact tomorrow copy on a narrow phone', (
    WidgetTester tester,
  ) async {
    final auth = await _authService();
    await _pumpScreen(
      tester,
      _BoxModeApi(claimedToday: true),
      auth,
      surfaceSize: const Size(320, 568),
      textScaler: const TextScaler.linear(2),
    );

    expect(find.text('Come back tomorrow.'), findsOneWidget);
    expect(find.text('COME BACK TOMORROW'), findsOneWidget);
    expect(
      find.textContaining('Today\'s reward has been claimed'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'popup honors accessible type across phone and platform metrics',
    (WidgetTester tester) async {
      const sizes = [
        Size(320, 568),
        Size(360, 640),
        Size(390, 844),
        Size(430, 932),
      ];
      for (final platform in const [
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        for (final size in sizes) {
          for (final scale in const [1.0, 1.3, 2.0]) {
            final auth = await _authService();
            await _pumpScreen(
              tester,
              _BoxModeApi(claimedToday: true),
              auth,
              surfaceSize: size,
              textScaler: TextScaler.linear(scale),
              platform: platform,
            );

            expect(find.text('Come back tomorrow.'), findsOneWidget);
            expect(find.text('COME BACK TOMORROW'), findsOneWidget);
            expect(find.text('% ODDS'), findsNothing);
            expect(find.text('?'), findsNothing);
            final body = tester
                .widgetList<RichText>(find.byType(RichText))
                .firstWhere(
                  (rich) => rich.text.toPlainText() == 'Come back tomorrow.',
                );
            expect(
              body.textScaler.scale(10),
              closeTo(10 * scale, 0.01),
              reason: '$platform $size scale=$scale',
            );
            final close = find.bySemanticsLabel('Close daily reward');
            expect(tester.getSize(close), const Size(44, 44));
            expect(close.hitTestable(), findsOneWidget);
            expect(
              tester.getSemantics(close),
              matchesSemantics(
                label: 'Close daily reward',
                isButton: true,
                hasTapAction: true,
              ),
            );
            final closeRect = tester.getRect(close);
            expect(closeRect.right, lessThanOrEqualTo(size.width));
            expect(closeRect.top, greaterThanOrEqualTo(0));
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

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

  testWidgets('winning a powerup reveals its name and inventory note', (
    WidgetTester tester,
  ) async {
    final auth = await _authService();
    final api = _BoxModeApi(
      powerupPool: [
        {
          'sku': 'POWERUP_SIGNAL_JAMMER',
          'name': 'Signal Jammer',
          'powerupType': 'SIGNAL_JAMMER',
        },
      ],
      rarePrizeMix: {'ACCESSORY': 0.0, 'POWERUP': 1.0},
      boxResult: const {
        'rarity': 'RARE',
        'rewardType': 'POWERUP',
        'coinAmount': null,
        'shopItem': null,
        'powerup': {
          'sku': 'POWERUP_SIGNAL_JAMMER',
          'name': 'Signal Jammer',
          'powerupType': 'SIGNAL_JAMMER',
        },
        'coins': 100,
        'streak': 7,
      },
    );
    await _pumpScreen(tester, api, auth);

    await tester.tap(find.text('SWIPE OR TAP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.boxClaimCalls, 1);
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('CLAIMED!'), findsOneWidget);
    expect(find.text('RARE'), findsOneWidget);
    expect(find.text('Signal Jammer'), findsOneWidget);
    expect(find.text('Added to your powerups'), findsOneWidget);
  });

  testWidgets('an older backend cannot reveal a retired Imposter reward', (
    WidgetTester tester,
  ) async {
    final auth = await _authService();
    final api = _BoxModeApi(
      powerupPool: const [
        {
          'sku': 'POWERUP_IMPOSTER',
          'name': 'Imposter',
          'powerupType': 'IMPOSTER',
        },
      ],
      rarePrizeMix: const {'ACCESSORY': 0.0, 'POWERUP': 1.0},
      boxResult: const {
        'rarity': 'RARE',
        'rewardType': 'POWERUP',
        'powerup': {
          'sku': 'POWERUP_IMPOSTER',
          'name': 'Imposter',
          'powerupType': 'IMPOSTER',
        },
        'coins': 100,
        'streak': 7,
      },
    );
    await _pumpScreen(tester, api, auth);

    // The retired item is absent from decoys even when an older backend still
    // returns it in the optional pool.
    expect(find.text('Imposter'), findsNothing);

    await tester.tap(find.text('SWIPE OR TAP'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 4100));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Imposter'), findsNothing);
    expect(find.text('POWERUP RETIRED'), findsOneWidget);
    expect(find.text('This reward is no longer available.'), findsOneWidget);
  });

  testWidgets('popup omits odds even when the backend supplies a rare mix', (
    WidgetTester tester,
  ) async {
    final auth = await _authService();
    final api = _BoxModeApi(
      powerupPool: [
        {
          'sku': 'POWERUP_SIGNAL_JAMMER',
          'name': 'Signal Jammer',
          'powerupType': 'SIGNAL_JAMMER',
        },
      ],
      rarePrizeMix: {'ACCESSORY': 0.5, 'POWERUP': 0.5},
    );
    await _pumpScreen(tester, api, auth);

    expect(find.text('?'), findsNothing);
    expect(find.text('% ODDS'), findsNothing);
    expect(find.text('new accessory or powerup'), findsNothing);
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
