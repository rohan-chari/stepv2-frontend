import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/screens/daily_reward_screen.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/screens/race_results_summary_screen.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/screens/tabs/leaderboard_tab.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/widgets/ad_banner_slot.dart';
import 'package:step_tracker/widgets/ad_inline_card.dart';
import 'package:step_tracker/widgets/game_container.dart';
import 'package:step_tracker/widgets/pill_button.dart';
import 'package:step_tracker/widgets/wooden_tab_bar.dart';

// ---------------------------------------------------------------------------
// Ad placement: the footer banner has been HOISTED to the main shell. Exactly
// ONE AdBannerSlot lives at the shell level, pinned above the bottom tab bar,
// so it loads once and survives PageView tab switches (no per-tab reload). It
// is shown on every nav tab EXCEPT home, and never during onboarding. The
// individual nav tabs (races/friends/leaderboard/profile) therefore no longer
// host their own AdBannerSlot. Pushed/standalone screens that are NOT nav tabs
// keep their own footer banner (race detail, race results, daily reward).
//
// These tests pin placement/structure only — actual ad loading never happens
// in tests (bannersEnabled is false off-iOS), so a mounted AdBannerSlot renders
// zero-size; `find.byType(AdBannerSlot)` still locates the mounted widget.
// ---------------------------------------------------------------------------

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 125,
    'auth_held_coins': 0,
    'auth_first_race_onboarding_seen': true,
    'auth_tutorial_onboarding_seen': true,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

class _RaceDetailApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    return {
      'id': raceId,
      'name': 'Banner Test Race',
      'status': 'PENDING',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 0,
      'payouts': {'first': 0, 'second': 0, 'third': 0},
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {'coins': 0, 'heldCoins': 0};
  }
}

class _LeaderboardApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async {
    return {
      'top100': [
        {
          'rank': 1,
          'userId': 'other-user',
          'displayName': 'AceWinner',
          'totalSteps': 12000,
          'equippedAccessories': const [],
        },
      ],
      'currentUser': {
        'rank': 1,
        'displayName': 'AceWinner',
        'totalSteps': 12000,
        'inTop100': true,
      },
    };
  }
}

class _FriendsApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    return const {
      'friends': [],
      'pending': {'incoming': [], 'outgoing': []},
    };
  }
}

class _ProfileApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchStats({
    required String identityToken,
  }) async {
    return const {
      'thisWeek': 12000,
      'thisMonth': 45000,
      'thisYear': 150000,
      'allTime': 300000,
      'streak': 4,
      'wins': 3,
      'losses': 1,
    };
  }
}

class _DailyRewardApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    return {
      'cycleLength': 6,
      'currentDay': 1,
      'claimedToday': true,
      'ladder': const [],
      'box': {
        'streak': 7,
        'streakCap': 30,
        'odds': {'COMMON': 0.6, 'UNCOMMON': 0.27, 'RARE': 0.13},
        'coinRanges': {
          'COMMON': [10, 30],
          'UNCOMMON': [40, 80],
        },
        'accessoryPool': const [],
      },
    };
  }
}

Map<String, dynamic> _race(int i, {String status = 'ACTIVE'}) => {
  'id': 'race-$i',
  'name': 'Race $i',
  'targetSteps': 10000,
  'participantCount': 2,
  'status': status,
  'creator': {'displayName': 'RaceMaker'},
  'isCreator': false,
  'endsAt': DateTime(2027, 1, 1).toIso8601String(),
};

Future<void> _pumpRacesTab(
  WidgetTester tester, {
  required List<Map<String, dynamic>> active,
  List<Map<String, dynamic>> completed = const [],
}) async {
  final authService = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RacesTab(
          authService: authService,
          racesData: {'active': active, 'completed': completed},
          friendsSteps: const [],
          onRacesChanged: () async {},
          displayName: 'Trail Walker',
        ),
      ),
    ),
  );
  await tester.pump();
}

// --- MainShell fakes (mirrors main_shell_nav_order_test) so the shell can be
// pumped past onboarding to exercise the hoisted footer banner. ------------

class _FakeHealthService extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;

  @override
  Future<StepData> getStepsToday() async =>
      StepData(steps: 1234, date: DateTime(2026, 6, 1));

  @override
  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async => const [];
}

class _FakeBackgroundSyncBootstrapService
    extends BackgroundSyncBootstrapService {
  @override
  Future<void> enableHealthKitBackgroundDelivery() async {}
}

class _ShellApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async {
    return {
      'sessionToken': authToken,
      'user': {'firstRaceOnboardingSeen': true, 'tutorialOnboardingSeen': true},
    };
  }

  @override
  Future<void> recordSteps({
    required String identityToken,
    required StepData stepData,
    bool skipRaceResolution = false,
  }) async {}

  @override
  Future<StepSyncV2Result> recordStepSyncV2({
    required String identityToken,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async => const StepSyncV2Result(kind: StepSyncV2Kind.unsupported);

  @override
  Future<RaceDiscoverySummary> fetchRaceDiscoverySummary({
    required String identityToken,
  }) async => RaceDiscoverySummary.unsupportedResult;

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) async => const {'state': 'EMPTY'};

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return const {
      'displayName': 'Trail Walker',
      'incomingFriendRequests': 0,
      'firstRaceOnboardingSeen': true,
      'tutorialOnboardingSeen': true,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async {
    return const {
      'invites': <Map<String, dynamic>>[],
      'waiting': <Map<String, dynamic>>[],
      'active': <Map<String, dynamic>>[],
      'completed': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    return const {
      'coins': 0,
      'equipped': <String, dynamic>{},
      'items': <Map<String, dynamic>>[],
    };
  }
}

Future<void> _pumpShell(WidgetTester tester) async {
  final authService = await _createAuthService();
  await tester.pumpWidget(
    MaterialApp(
      home: MainShell(
        authService: authService,
        healthService: _FakeHealthService(),
        backendApiService: _ShellApi(),
        backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Shell footer banner (hoisted single banner)', () {
    testWidgets('no AdBannerSlot on the home tab', (tester) async {
      await _pumpShell(tester);

      // Lands on Home: the shell gates the footer banner off entirely.
      expect(find.byType(AdBannerSlot), findsNothing);
    });

    testWidgets('exactly one shell AdBannerSlot on a non-home tab', (
      tester,
    ) async {
      await _pumpShell(tester);

      // Drive the tab bar over to Races (index 1).
      final tabBar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));
      tabBar.onTap(1);
      await tester.pumpAndSettle();

      expect(find.byType(AdBannerSlot), findsOneWidget);

      // ...and it lives at the shell level, above the tab bar — a sibling of
      // the WoodenTabBar, not nested inside any tab's scroll view.
      expect(find.byType(WoodenTabBar), findsOneWidget);
    });

    testWidgets('banner is retired again when returning to home', (
      tester,
    ) async {
      await _pumpShell(tester);
      final tabBar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));

      tabBar.onTap(1); // Races
      // Home has a perpetual animation, so drive the page transition with
      // explicit pumps rather than pumpAndSettle (which would never settle).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AdBannerSlot), findsOneWidget);

      tabBar.onTap(0); // back to Home
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AdBannerSlot), findsNothing);
    });
  });

  group('Nav tabs no longer host their own banner', () {
    testWidgets('LeaderboardTab hosts no AdBannerSlot', (tester) async {
      final authService = await _createAuthService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LeaderboardTab(
              authService: authService,
              backendApiService: _LeaderboardApi(),
              displayName: 'Trail Walker',
              requestedType: 'steps',
              requestedPeriod: 'today',
              selectionNonce: 0,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AdBannerSlot), findsNothing);
      // Podium/list content is untouched.
      expect(find.textContaining('AceWinner'), findsWidgets);
    });

    testWidgets('FriendsTab hosts no AdBannerSlot', (tester) async {
      final authService = await _createAuthService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FriendsTab(
              authService: authService,
              onFriendsChanged: () {},
              backendApiService: _FriendsApi(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AdBannerSlot), findsNothing);
    });

    testWidgets('ProfileTab hosts no AdBannerSlot', (tester) async {
      final authService = await _createAuthService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileTab(
              authService: authService,
              displayName: 'Trail Walker',
              onSettingsChanged: () {},
              backendApiService: _ProfileApi(),
              showBackButton: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AdBannerSlot), findsNothing);
    });

    testWidgets('RacesTab hosts no AdBannerSlot and no in-feed AdInlineCard', (
      tester,
    ) async {
      await _pumpRacesTab(
        tester,
        active: [for (var i = 0; i < 6; i++) _race(i)],
        completed: [for (var i = 6; i < 12; i++) _race(i, status: 'COMPLETED')],
      );

      expect(find.byType(AdBannerSlot), findsNothing);
      expect(find.byType(AdInlineCard, skipOffstage: false), findsNothing);
      expect(
        find.byKey(const Key('active-section-ad'), skipOffstage: false),
        findsNothing,
      );
    });
  });

  group('Standalone screens keep their own footer banner', () {
    testWidgets('RaceDetailScreen hosts exactly one AdBannerSlot', (
      tester,
    ) async {
      final authService = await _createAuthService();
      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-banner-1',
            backendApiService: _RaceDetailApi(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(AdBannerSlot), findsOneWidget);
      // Pinned outside the scrollable: not a descendant of the scroll view.
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(AdBannerSlot),
        ),
        findsNothing,
      );
    });

    testWidgets('race results modal hosts an AdBannerSlot and NICE still pops', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RaceResultsSummaryScreen(
            races: [
              {
                'id': 'r1',
                'name': 'Weekend Sprint',
                'participantCount': 4,
                'myPlacement': 2,
                'myPayoutCoins': 120,
                'myStatus': 'ACCEPTED',
                'winner': {'displayName': 'Alex'},
              },
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AdBannerSlot), findsOneWidget);
      // Footer style: the banner sits at the screen bottom, not nested
      // inside the parchment results card.
      expect(
        find.descendant(
          of: find.byType(GameContainer),
          matching: find.byType(AdBannerSlot),
        ),
        findsNothing,
      );

      await tester.tap(find.widgetWithText(PillButton, 'NICE'));
      await tester.pumpAndSettle();
      expect(find.text('RACE FINISHED'), findsNothing);
    });

    testWidgets('DailyRewardScreen hosts a footer AdBannerSlot', (
      tester,
    ) async {
      final authService = await _createAuthService();
      await tester.pumpWidget(
        MaterialApp(
          home: DailyRewardScreen(
            authService: authService,
            backendApiService: _DailyRewardApi(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AdBannerSlot), findsOneWidget);
      // Footer style: at the screen bottom, not inside the reward card.
      expect(
        find.descendant(
          of: find.byType(GameContainer),
          matching: find.byType(AdBannerSlot),
        ),
        findsNothing,
      );
    });
  });
}
