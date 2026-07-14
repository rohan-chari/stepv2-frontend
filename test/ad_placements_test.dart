import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/daily_reward_screen.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/screens/race_results_summary_screen.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/screens/tabs/leaderboard_tab.dart';
import 'package:step_tracker/screens/tabs/profile_tab.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/ad_banner_slot.dart';
import 'package:step_tracker/widgets/ad_inline_card.dart';
import 'package:step_tracker/widgets/game_container.dart';
import 'package:step_tracker/widgets/pill_button.dart';

// ---------------------------------------------------------------------------
// Ad placement expansion: every banner surface hosts an AdBannerSlot (which
// collapses to zero size unless this build has banners enabled AND an ad
// loads), and the races tab carries exactly one in-feed AdInlineCard in the
// ACTIVE section. These tests pin placement/structure only — actual ad
// loading never happens in tests (bannersEnabled is false off-iOS).
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Story 4: leaderboard banner', () {
    testWidgets('LeaderboardTab hosts exactly one AdBannerSlot', (
      tester,
    ) async {
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

      expect(find.byType(AdBannerSlot), findsOneWidget);
      // Podium/list content is untouched.
      expect(find.textContaining('AceWinner'), findsWidgets);
    });
  });

  group('Story 1: race detail anchored banner', () {
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
  });

  group('Story 2: race results banner', () {
    testWidgets('results modal hosts an AdBannerSlot and NICE still pops', (
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
  });

  group('friends / profile / daily spin banners', () {
    testWidgets('FriendsTab hosts exactly one AdBannerSlot', (tester) async {
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

      expect(find.byType(AdBannerSlot), findsOneWidget);
    });

    testWidgets('ProfileTab hosts exactly one AdBannerSlot', (tester) async {
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

      expect(find.byType(AdBannerSlot), findsOneWidget);
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

  group('Story 3: in-feed ad card in races list', () {
    testWidgets('exactly one AdInlineCard in the ACTIVE section', (
      tester,
    ) async {
      await _pumpRacesTab(
        tester,
        active: [for (var i = 0; i < 6; i++) _race(i)],
        completed: [for (var i = 6; i < 12; i++) _race(i, status: 'COMPLETED')],
      );

      expect(find.byType(AdInlineCard, skipOffstage: false), findsOneWidget);
      expect(
        find.byKey(const Key('active-section-ad'), skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('short ACTIVE section still gets the card (after last row)', (
      tester,
    ) async {
      await _pumpRacesTab(tester, active: [_race(0), _race(1)]);

      expect(
        find.byKey(const Key('active-section-ad'), skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('no AdInlineCard when there are no active races', (
      tester,
    ) async {
      await _pumpRacesTab(
        tester,
        active: const [],
        completed: [for (var i = 0; i < 6; i++) _race(i, status: 'COMPLETED')],
      );

      expect(find.byType(AdInlineCard, skipOffstage: false), findsNothing);
    });
  });
}
