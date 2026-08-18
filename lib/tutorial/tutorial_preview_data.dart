import '../models/step_data.dart';
import '../models/home_race_suggestion.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';

// Seeded services that let the tutorial render the REAL tab screens with
// deterministic, offline data instead of hand-built mock screens. Nothing here
// touches the network: TutorialPreviewBackendApiService overrides every read
// the previewed screens make, and TutorialPreviewAuthService reports a
// non-empty auth token (so the self-fetching widgets proceed) plus a seeded
// coin balance / display name. The shipped app never constructs these — they
// are only wired up by the tutorial host — so production behaviour is untouched.

/// The stable id used for the "you" rows across the previewed screens, so the
/// real screens highlight the right leaderboard/cohort row.
const String tutorialPreviewUserId = 'preview-user';

/// Stable id for the race the "Powerups & boxes" tutorial step opens into. It
/// matches the first active race on the previewed Races tab so the flow reads
/// as "tap that race → see its detail".
const String tutorialPreviewRaceId = 'race-active-1';

class TutorialPreviewAuthService extends AuthService {
  TutorialPreviewAuthService() {
    // Seed enough of the user for the hero (coins, name) and to suppress the
    // home "add a photo" setup prompt (a non-empty photo url; never loaded as
    // an image on the previewed screens).
    applyBackendUser(const {
      'id': tutorialPreviewUserId,
      'displayName': 'Rohan',
      'firstName': 'Rohan',
      'lastName': null,
      'nameSetupOnboardingRequired': false,
      'nameSetupCompletedAt': '2026-08-11T12:00:00.000Z',
      'profilePhotoUrl': 'preview-photo',
      'coins': 1840,
    });
  }

  // The previewed self-fetching widgets bail out when the token is empty; a
  // constant non-empty token keeps them on the happy path. The seeded backend
  // ignores the token entirely.
  @override
  String? get authToken => 'preview-token';
}

class TutorialPreviewBackendApiService extends BackendApiService {
  // New recipient-private settlement surfaces are deliberately suppressed in
  // the deterministic tutorial; no live fetch may cover a scripted beat.
  @override
  Future<List<Map<String, dynamic>>> fetchRaceImpactNotices({
    required String identityToken,
    required String raceId,
  }) async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchPrivateRaceImpactFeed({
    required String identityToken,
    required String raceId,
  }) async => const [];

  // -- Home: feedback card (batch 2026-08-10b item 5) --
  //
  // The home tab renders the real feedback card inside the tutorial preview,
  // and this service EXTENDS the real BackendApiService — so without this
  // override a tap inside the tutorial would fire a genuine
  // POST /feedback/suggestions. The only other thing standing in the way is
  // the opaque GestureDetector in spotlight_overlay.dart, which is incidental
  // chrome, not a guarantee (architect R4 / ui-test-planner risk 2).
  @override
  Future<void> submitSuggestion({
    required String identityToken,
    required String text,
  }) async {}

  // -- Home: step milestones (StepMilestonesSection) --
  @override
  Future<Map<String, dynamic>> fetchStepMilestonesToday({
    required String identityToken,
    required String localDate,
  }) async {
    return {
      'currentSteps': 13420,
      'totalCoinsClaimed': 20,
      'milestones': [
        {'threshold': 5000, 'coins': 20, 'claimed': true, 'claimable': false},
        {'threshold': 10000, 'coins': 30, 'claimed': false, 'claimable': true},
        {'threshold': 15000, 'coins': 30, 'claimed': false, 'claimable': false},
        {'threshold': 20000, 'coins': 40, 'claimed': false, 'claimable': false},
      ],
    };
  }

  // -- Home: daily reward (StreakChip) --
  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    return {'claimedToday': false};
  }

  // -- Profile: lifetime stats (_StatsSection) --
  @override
  Future<Map<String, dynamic>> fetchStats({
    required String identityToken,
  }) async {
    return {
      'thisWeek': 61240,
      'thisMonth': 244890,
      'thisYear': 1893400,
      'avgPerDayWeek': 8748,
      'avgPerDayMonth': 8163,
      'avgPerDayYear': 7920,
      'allTime': 2417800,
      'streak': 6,
    };
  }

  // -- Profile: step calendar --
  @override
  Future<Map<String, dynamic>> fetchStepCalendar({
    required String identityToken,
    required String month,
  }) async {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return {
      'days': [
        for (var d = 1; d <= daysInMonth; d++)
          {
            'steps': d < now.day ? 4200 + (d * 731) % 9200 : 0,
            'goalMet': d < now.day && (d * 731) % 9200 > 3400,
            'isToday': d == now.day,
            'future': d > now.day,
          },
      ],
    };
  }

  // -- Leaderboard: steps / global / today --
  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async {
    Map<String, dynamic> row(int rank, String userId, String name, int steps) =>
        {
          'rank': rank,
          'userId': userId,
          'displayName': name,
          'profilePhotoUrl': null,
          'totalSteps': steps,
          'firsts': null,
          'seconds': null,
          'thirds': null,
          'equippedAccessories': const [],
        };

    return {
      'top100': [
        row(1, 'lb-1', 'Sam Rivera', 18240),
        row(2, 'lb-2', 'Maya Chen', 16110),
        row(3, 'lb-3', 'Jordan Lee', 14880),
        row(4, tutorialPreviewUserId, 'Rohan', 13420),
        row(5, 'lb-5', 'Priya N.', 11290),
        row(6, 'lb-6', 'Chris Park', 9870),
      ],
      'currentUser': {
        'rank': 4,
        'userId': tutorialPreviewUserId,
        'displayName': 'Rohan',
        'profilePhotoUrl': null,
        'totalSteps': 13420,
        'inTop100': true,
        'equippedAccessories': const [],
      },
    };
  }

  // -- Ranked: weekly cohort (v2) --
  @override
  Future<Map<String, dynamic>> fetchRankedV2({
    required String identityToken,
  }) async {
    Map<String, dynamic> member(
      int rank,
      String userId,
      String name,
      int steps,
      String? zone,
    ) => {
      'rank': rank,
      'userId': userId,
      'displayName': name,
      'profilePhotoUrl': null,
      'weeklySteps': steps,
      'zone': zone,
    };

    final now = DateTime.now();
    return {
      'week': {
        'index': 24,
        'startsOn': now.subtract(const Duration(days: 3)).toIso8601String(),
        'endsOn': now.add(const Duration(days: 4)).toIso8601String(),
        'settlesAt': now
            .add(const Duration(days: 4, hours: 12))
            .toIso8601String(),
        'status': 'ACTIVE',
      },
      'currentUser': {
        'ranked': true,
        'tier': 'GOLD',
        'rank': 4,
        'weeklySteps': 74000,
        'zone': null,
        'projectedCoins': 85,
      },
      'cohort': {
        'id': 'cohort-gold-001',
        'tier': 'GOLD',
        'size': 8,
        'promoteCount': 2,
        'demoteCount': 2,
        'members': [
          member(1, 'rk-1', 'Sam Rivera', 88100, 'PROMOTION'),
          member(2, 'rk-2', 'Maya Chen', 80600, 'PROMOTION'),
          member(3, 'rk-3', 'Jordan Lee', 78050, null),
          member(4, tutorialPreviewUserId, 'Rohan', 74000, null),
          member(5, 'rk-5', 'Priya N.', 61500, null),
          member(6, 'rk-6', 'Chris Park', 52400, null),
          member(7, 'rk-7', 'Dana Fox', 41200, 'DEMOTION'),
          member(8, 'rk-8', 'Lee Quinn', 33800, 'DEMOTION'),
        ],
        'rewards': [
          {'rank': 1, 'coins': 300},
          {'rank': 2, 'coins': 225},
          {'rank': 3, 'coins': 125},
          {'rank': 4, 'coins': 85},
        ],
      },
      'tiers': [
        {'key': 'BRONZE', 'label': 'Bronze', 'promotionBonus': 0},
        {'key': 'SILVER', 'label': 'Silver', 'promotionBonus': 100},
        {'key': 'GOLD', 'label': 'Gold', 'promotionBonus': 200},
        {'key': 'PLATINUM', 'label': 'Platinum', 'promotionBonus': 350},
        {'key': 'DIAMOND', 'label': 'Diamond', 'promotionBonus': 500},
        {'key': 'LEGEND', 'label': 'Legend', 'promotionBonus': 1000},
      ],
      'lastWeek': null,
    };
  }

  // -- Friends --
  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    return {
      'friends': [
        {
          'displayName': 'Maya Chen',
          'profilePhotoUrl': null,
          'friendshipId': 'fs-1',
        },
        {
          'displayName': 'Sam Rivera',
          'profilePhotoUrl': null,
          'friendshipId': 'fs-2',
        },
        {
          'displayName': 'Jordan Lee',
          'profilePhotoUrl': null,
          'friendshipId': 'fs-3',
        },
      ],
      'pending': {
        'incoming': [
          {
            'friendshipId': 'fs-in-1',
            'user': {'displayName': 'Dana Fox', 'profilePhotoUrl': null},
          },
        ],
        'outgoing': [
          {
            'friendshipId': 'fs-out-1',
            'user': {'displayName': 'Priya N.', 'profilePhotoUrl': null},
          },
        ],
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async {
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> searchUsers({
    required String identityToken,
    required String query,
  }) async {
    return const [];
  }

  // -- Races (also fed via constructor; provided here as a safety net) --
  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async {
    return tutorialPreviewRacesData();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async {
    return tutorialPreviewFeaturedRaces();
  }

  // -- Race detail (the "Powerups & boxes" step renders the real
  //    RaceDetailScreen, which self-fetches these). --
  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    // Accepted and ignored, exactly like fetchRaceBootstrap below: the
    // tutorial's fixture roster is far smaller than any page size, so it is
    // always "one full page". Emitting no pagination metadata keeps the screen
    // on its unpaged path, which is what the deterministic walkthrough expects.
    int? participantsLimit,
  }) async {
    return tutorialPreviewRaceDetail();
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    return tutorialPreviewRaceProgress();
  }

  @override
  Future<RaceBootstrapResult> fetchRaceBootstrap({
    required String identityToken,
    required String raceId,
    // Accepted and ignored: the tutorial's fixture roster is far smaller than
    // any page size, so it is always "one full page". Returning no pagination
    // metadata keeps the screen on its unpaged path, which is what the
    // deterministic tutorial walkthrough expects.
    int? participantsLimit,
  }) async {
    return RaceBootstrapResult(
      supported: true,
      race: tutorialPreviewRaceDetail(),
      progress: tutorialPreviewRaceProgress(),
      globalPowerupInventory: const {'items': []},
    );
  }

  @override
  Future<RaceProgressResult> fetchRaceProgressCompact({
    required String identityToken,
    required String raceId,
  }) async {
    return RaceProgressResult(
      progress: tutorialPreviewRaceProgress(),
      globalPowerupInventory: const {'items': []},
      hasCompactInventory: true,
    );
  }

  @override
  Future<RaceProgressResult> fetchRaceProgressParticipants({
    required String identityToken,
    required String raceId,
    int offset = 0,
    int limit = 10,
  }) async {
    final progress = tutorialPreviewRaceProgress();
    final full =
        (progress['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    final start = offset < 0 ? 0 : offset;
    final safeLimit = limit <= 0
        ? 10
        : (limit > 50 ? 50 : limit);
    final participants = full.skip(start).take(safeLimit).toList();
    return RaceProgressResult(
      progress: {
        ...progress,
        'participants': participants,
      },
      globalPowerupInventory: const {'items': []},
      hasCompactInventory: true,
      participantsPagination: {
        'offset': start,
        'limit': safeLimit,
        'total': full.length,
        'hasMore': start + participants.length < full.length,
        'nextOffset': start + participants.length,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> fetchRacePowerupUseContext({
    required String identityToken,
    required String raceId,
  }) async {
    final progress = tutorialPreviewRaceProgress();
    final participants =
        (progress['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    final powerupData =
        (progress['powerupData'] as Map?)?.cast<String, dynamic>();
    final inventory =
        powerupData?['inventory'] is List
            ? (powerupData?['inventory'] as List)
                .whereType<Map<String, dynamic>>()
                .toList()
            : const [];
    return {
      'participants': participants,
      'powerupData': {
        'powerupSlots': powerupData?['powerupSlots'] ?? 3,
        'inventory': inventory,
        'queuedBoxCount': powerupData?['queuedBoxCount'] ?? 0,
        'myPlacement': (progress['myPlacement'] as num?)?.toInt() ?? 0,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async {
    return tutorialPreviewRaceMessages(kind);
  }

  @override
  Future<RaceMessageStreamsResult> fetchRaceMessageStreams({
    required String identityToken,
    required String raceId,
    required bool includeUser,
    int limit = 50,
  }) async {
    final system = tutorialPreviewRaceMessages('SYSTEM');
    final user = includeUser ? tutorialPreviewRaceMessages('USER') : null;
    final userRows = user?['messages'];
    final recentIds = userRows is List
        ? userRows
              .whereType<Map>()
              .map((row) => row['id'])
              .whereType<String>()
              .take(limit)
              .toList(growable: false)
        : const <String>[];
    return RaceMessageStreamsResult(
      supported: true,
      systemStream: system,
      userStream: user,
      systemResolved: true,
      userResolved: includeUser,
      chatWatermark: {'recentIds': recentIds},
    );
  }

  // No-op so the race screen's read-receipt ping never hits the network.
  @override
  Future<Map<String, dynamic>> markRaceChatRead({
    required String identityToken,
    required String raceId,
  }) async {
    return const {};
  }

  // Empty global stash — keeps the inventory focused on the in-race slots.
  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async {
    return const {'items': []};
  }
}

/// Sample today's step total for the home hero.
StepData tutorialPreviewStepData() {
  final now = DateTime.now();
  return StepData(steps: 13420, date: DateTime(now.year, now.month, now.day));
}

/// A believable equipped-capybara loadout for the home hero preview.
const List<Map<String, dynamic>> tutorialPreviewAccessories = [
  {
    'slot': 'HEAD',
    'assetKey': 'baseball_cap',
    'renderMetadata': {'offsetX': -0.01, 'offsetY': 0.02, 'rotation': -0.08},
  },
  {
    'slot': 'FACE',
    'assetKey': 'sunglasses',
    'renderMetadata': {
      'offsetX': 0.025,
      'offsetY': -0.04,
      'rotation': -0.08,
      'scale': 1.65,
    },
  },
  {
    'slot': 'FEET',
    'assetKey': 'shoes',
    'renderMetadata': {
      'offsetX': 0.03,
      'offsetY': 0.02,
      'rotation': -0.03,
      'scale': 1.1,
    },
  },
];

/// Home race rail: a single active race so the home RACES section renders the
/// real active-race ticket strip.
///
/// **Must stay `ACTIVE_RACES`.** Batch 2026-08-10b item 3 promotes a
/// `PENDING_INVITE` card into its own block directly above Today's Coins —
/// which is exactly where `tutorialMilestonesKey`, the milestones spotlight
/// anchor, sits. Seeding `PENDING_INVITE` here would push that anchor below the
/// fold and the tutorial would ring an off-screen element.
Map<String, dynamic> tutorialPreviewHomeRaceCard() {
  final now = DateTime.now();
  return {
    'state': 'ACTIVE_RACES',
    'data': {
      'races': [
        {
          'raceId': 'home-race-1',
          'name': 'Weekend 10K',
          'endsAt': now
              .add(const Duration(days: 2, hours: 4))
              .toIso8601String(),
          'userPlacement': 2,
          'participantCount': 6,
          'top3': const [
            {'userId': 'rk-1', 'displayName': 'Sam Rivera', 'rank': 1},
            {
              'userId': tutorialPreviewUserId,
              'displayName': 'Rohan',
              'rank': 2,
            },
            {'userId': 'rk-3', 'displayName': 'Jordan Lee', 'rank': 3},
          ],
        },
      ],
    },
  };
}

List<HomeRaceSuggestion> tutorialPreviewHomeSuggestions() {
  final endsAt = DateTime.now()
      .add(const Duration(days: 2, hours: 4))
      .toUtc()
      .toIso8601String();
  final rows = <Map<String, dynamic>>[
    {
      'kind': 'FEATURED_RACE',
      'id': 'tutorial-daily',
      'seedKind': 'DAILY_10K',
      'name': 'Daily 10K',
      'status': 'ACTIVE',
      'endsAt': endsAt,
      'participantCount': 18,
      'maxParticipants': 100,
      'isFull': false,
      'powerupsEnabled': true,
      'prizePool': null,
      'finishReward': {'pool': 300, 'paidPlaces': 3},
      'joinAction': 'JOIN',
    },
    {
      'kind': 'PUBLIC_RACE',
      'id': 'tutorial-public',
      'name': 'Lunch Break Sprint',
      'status': 'PENDING',
      'maxDurationDays': 1,
      'endsAt': null,
      'startedAt': null,
      'participantCount': 3,
      'maxParticipants': 10,
      'buyInAmount': 0,
      'payoutPreset': 'TOP_HALF_GRADED',
      'powerupsEnabled': true,
      'prizePool': null,
      'isTeamRace': false,
      'teamSize': null,
      'teamAName': null,
      'teamBName': null,
      'teams': null,
      'joinAction': 'JOIN',
    },
    {
      'kind': 'TOURNAMENT',
      'id': 'tutorial-tournament',
      'seedKind': 'DAILY_DASH',
      'name': 'Daily Dash',
      'status': 'PENDING',
      'bracketSize': 8,
      'matchupDurationDays': 1,
      'acceptedCount': 5,
      'buyInAmount': 0,
      'potCoins': 800,
      'prizePool': null,
      'powerupsEnabled': true,
      'powerupStepInterval': 2000,
      'createdAt': '2026-08-11T20:00:00.000Z',
      'joinAction': 'JOIN',
    },
  ];
  return rows
      .map(HomeRaceSuggestion.tryParse)
      .whereType<HomeRaceSuggestion>()
      .toList(growable: false);
}

/// Races screen data: active (one with a placement + queued boxes), a waiting
/// race, and a completed race. Invite decisions belong to the shell gate.
Map<String, dynamic> tutorialPreviewRacesData() {
  final now = DateTime.now();
  return {
    'active': [
      {
        'id': 'race-active-1',
        'name': 'Weekend 10K',
        'status': 'ACTIVE',
        'maxDurationDays': 3,
        'endsAt': now.add(const Duration(days: 2, hours: 4)).toIso8601String(),
        'participantCount': 6,
        'creator': {'displayName': 'Maya Chen'},
        'isCreator': false,
        'myPlacement': 2,
        // One held powerup (sprite) + one unopened mystery box (crate), plus a
        // queued box — showcases all three inventory-slot states in the row.
        'slotItems': const [
          {'id': 'pwr-1', 'type': 'SECOND_WIND', 'status': 'HELD'},
          {'id': 'box-1', 'type': null, 'status': 'MYSTERY_BOX'},
        ],
        'mysteryBoxCount': 1,
        'queuedBoxCount': 1,
      },
      {
        'id': 'race-active-2',
        'name': 'Lunch Loop',
        'status': 'ACTIVE',
        'maxDurationDays': 5,
        'endsAt': now.add(const Duration(days: 4, hours: 6)).toIso8601String(),
        'participantCount': 4,
        'creator': {'displayName': 'Sam Rivera'},
        'isCreator': false,
        'myPlacement': 4,
        'queuedBoxCount': 0,
      },
    ],
    'pending': [
      {
        'id': 'race-waiting-1',
        'name': 'Morning Crew',
        'status': 'PENDING',
        'maxDurationDays': 7,
        'endsAt': now.add(const Duration(days: 1)).toIso8601String(),
        'participantCount': 3,
        'creator': {'displayName': 'Alex'},
        'isCreator': false,
        'myStatus': 'ACCEPTED',
        'myPlacement': null,
        'queuedBoxCount': 0,
      },
    ],
    'completed': [
      {
        'id': 'race-complete-1',
        'name': 'Last Week 5K',
        'status': 'COMPLETED',
        'maxDurationDays': 7,
        'endsAt': now.subtract(const Duration(days: 1)).toIso8601String(),
        'participantCount': 6,
        'creator': {'displayName': 'Jordan Lee'},
        'isCreator': false,
        'myPlacement': 1,
        'queuedBoxCount': 0,
      },
    ],
    // The real RacesTab receives the same additive summaries as production.
    // Keep ordinary races first in every shelf: tutorial spotlights `races.card`
    // and `races.box` intentionally target `race-active-1`, never a bracket.
    'tournaments': [
      {
        'id': 'tournament-preview-active',
        'name': 'Trailblazer Knockout',
        'status': 'ACTIVE',
        'bracketSize': 8,
        'currentRound': 1,
        'totalRounds': 3,
        'myStatus': 'ACCEPTED',
        'championPrizeCoins': 300,
        'myCurrentMatch': {
          'raceId': 'tournament-preview-match',
          'endsAt': now
              .add(const Duration(days: 1, hours: 8))
              .toIso8601String(),
          'myPlacement': 2,
          'slotItems': const [
            {'id': 'preview-powerup', 'type': 'SECOND_WIND', 'status': 'HELD'},
            {'id': 'preview-box', 'type': null, 'status': 'MYSTERY_BOX'},
          ],
          'mysteryBoxCount': 1,
          'queuedBoxCount': 1,
        },
        'myIdentity': const {
          'displayName': 'Rohan',
          'animal': 'corgi_puppy',
          'equippedAccessories': [
            {'slot': 'HEAD', 'assetId': 'baseball_cap'},
            {'slot': 'FACE', 'assetId': 'sunglasses'},
          ],
        },
      },
      {
        'id': 'tournament-preview-pending',
        'name': 'Campfire Bracket',
        'status': 'PENDING',
        'bracketSize': 4,
        'acceptedCount': 3,
        'myStatus': 'ACCEPTED',
        'championPrizeCoins': 150,
        'myIdentity': const {
          'displayName': 'Rohan',
          'animal': 'CAPYBARA',
          'equippedAccessories': [
            {'slot': 'FEET', 'assetId': 'shoes'},
          ],
        },
      },
      {
        'id': 'tournament-preview-champion',
        'name': 'Finished Forest Final',
        'status': 'COMPLETED',
        'bracketSize': 4,
        'championUserId': tutorialPreviewUserId,
        'myStatus': 'ACCEPTED',
        'championPrizeCoins': 150,
        'myIdentity': const {
          'displayName': 'Rohan',
          'animal': 'corgi_puppy',
          'equippedAccessories': [
            {'slot': 'HEAD', 'assetId': 'baseball_cap'},
          ],
        },
      },
      // An intentionally older/partial summary exercises the same neutral
      // capybara fallback a production client needs during staggered rollout.
      {
        'id': 'tournament-preview-no-identity',
        'name': 'Last Lap Bracket',
        'status': 'COMPLETED',
        'bracketSize': 8,
        'myStatus': 'ACCEPTED',
        'myEliminatedInRound': 2,
        'championPrizeCoins': 300,
      },
    ],
  };
}

/// The active race shown behind the "Powerups & boxes" step. An ACTIVE race the
/// preview user has already joined, so the real RaceDetailScreen renders its
/// full live layout (course → standings → powerup inventory).
Map<String, dynamic> tutorialPreviewRaceDetail() {
  final now = DateTime.now();
  return {
    'id': tutorialPreviewRaceId,
    'name': 'Weekend 10K',
    'status': 'ACTIVE',
    'myStatus': 'ACCEPTED',
    'isCreator': false,
    'maxDurationDays': 3,
    'buyInAmount': 0,
    'payoutPreset': 'TOP3_70_20_10',
    'projectedPotCoins': 300,
    'prizePool': const {
      'coins': 300,
      'projected': true,
      'atMax': false,
      'playerCount': 5,
      'durationDays': 3,
      'durationPoints': 2,
      'coinUnit': 20,
      'maxCoins': 16000,
      'funded': true,
    },
    'payoutTiers': const [
      {'placement': 1, 'amount': 210},
      {'placement': 2, 'amount': 60},
      {'placement': 3, 'amount': 30},
    ],
    'endsAt': now.add(const Duration(days: 2, hours: 4)).toIso8601String(),
    'participants': tutorialPreviewRaceParticipants(),
  };
}

/// Shared roster for the race-detail course + standings. The preview user sits
/// 2nd, matching their placement on the home/races previews.
List<Map<String, dynamic>> tutorialPreviewRaceParticipants() {
  return [
    {
      'userId': 'rk-1',
      'displayName': 'Sam Rivera',
      'totalSteps': 24180,
      'profilePhotoUrl': null,
      'accessories': const [],
      'finishedAt': null,
      'stealthed': false,
    },
    {
      'userId': tutorialPreviewUserId,
      'displayName': 'Rohan',
      'totalSteps': 21640,
      'profilePhotoUrl': null,
      'accessories': tutorialPreviewAccessories,
      'finishedAt': null,
      'stealthed': false,
    },
    {
      'userId': 'rk-3',
      'displayName': 'Jordan Lee',
      'totalSteps': 19050,
      'profilePhotoUrl': null,
      'accessories': const [],
      'finishedAt': null,
      'stealthed': false,
    },
    {
      'userId': 'rk-5',
      'displayName': 'Priya N.',
      'totalSteps': 15220,
      'profilePhotoUrl': null,
      'accessories': const [],
      'finishedAt': null,
      'stealthed': false,
    },
    {
      'userId': 'rk-6',
      'displayName': 'Chris Park',
      'totalSteps': 11870,
      'profilePhotoUrl': null,
      'accessories': const [],
      'finishedAt': null,
      'stealthed': false,
    },
  ];
}

/// Progress payload for the previewed race: the live roster plus an enabled
/// powerup loadout — one held powerup, one openable mystery box, a queued box,
/// and an active self-buff — so the POWERUPS block the step spotlights is full.
Map<String, dynamic> tutorialPreviewRaceProgress() {
  final now = DateTime.now();
  return {
    'status': 'ACTIVE',
    'participants': tutorialPreviewRaceParticipants(),
    'powerupData': {
      'enabled': true,
      'powerupSlots': 3,
      'queuedBoxCount': 1,
      'powerupStepInterval': 4000,
      'stepsUntilNextPowerup': 1500,
      'inventory': [
        {
          'id': 'pw-held-1',
          'type': 'PROTEIN_SHAKE',
          'rarity': 'COMMON',
          'status': 'HELD',
        },
        {'id': 'pw-box-1', 'status': 'MYSTERY_BOX'},
      ],
      'activeEffects': [
        {
          'type': 'RUNNERS_HIGH',
          'onSelf': true,
          'targetUserId': tutorialPreviewUserId,
          'expiresAt': now
              .add(const Duration(hours: 2, minutes: 40))
              .toIso8601String(),
        },
      ],
    },
  };
}

/// Seeded Activity (SYSTEM) and Chat (USER) feeds for the race-detail preview,
/// newest-first as the live services expect. [kind] is the value the screen's
/// chat/feed services request ('SYSTEM' for Activity, 'USER' for Chat).
Map<String, dynamic> tutorialPreviewRaceMessages(String? kind) {
  final now = DateTime.now();
  if (kind == 'SYSTEM') {
    return {
      'messages': [
        {
          'id': 'sys-1',
          'kind': 'SYSTEM',
          'eventType': 'POWERUP_USED',
          'powerupType': 'LEG_CRAMP',
          'body': 'Maya Chen used Leg Cramp on you!',
          'actorUserId': 'rk-2',
          'targetUserId': tutorialPreviewUserId,
          'createdAt': now
              .subtract(const Duration(minutes: 6))
              .toIso8601String(),
        },
        {
          'id': 'sys-2',
          'kind': 'SYSTEM',
          'eventType': 'MYSTERY_BOX_OPENED',
          'powerupType': 'PROTEIN_SHAKE',
          'body': 'You opened a mystery box and found a Protein Shake!',
          'actorUserId': tutorialPreviewUserId,
          'createdAt': now
              .subtract(const Duration(minutes: 18))
              .toIso8601String(),
        },
        {
          'id': 'sys-3',
          'kind': 'SYSTEM',
          'eventType': 'POWERUP_USED',
          'powerupType': 'PROTEIN_SHAKE',
          'body': 'Sam Rivera chugged a Protein Shake for +1,500 steps.',
          'actorUserId': 'rk-1',
          'createdAt': now
              .subtract(const Duration(minutes: 33))
              .toIso8601String(),
        },
      ],
      'nextCursor': null,
    };
  }
  return {
    'messages': [
      {
        'id': 'msg-1',
        'kind': 'USER',
        'body': 'who hit me with the leg cramp',
        'senderId': tutorialPreviewUserId,
        'senderName': 'Rohan',
        'senderPhotoUrl': null,
        'createdAt': now.subtract(const Duration(minutes: 4)).toIso8601String(),
      },
      {
        'id': 'msg-2',
        'kind': 'USER',
        'body': 'gg everyone, catching up tonight',
        'senderId': 'rk-1',
        'senderName': 'Sam Rivera',
        'senderPhotoUrl': null,
        'createdAt': now.subtract(const Duration(minutes: 9)).toIso8601String(),
      },
    ],
    'nextCursor': null,
  };
}

List<Map<String, dynamic>> tutorialPreviewFeaturedRaces() {
  final now = DateTime.now();
  return [
    {
      'raceId': 'featured-1',
      'name': 'Daily 10K Challenge',
      'seedKind': 'DAILY',
      'endsAt': now.add(const Duration(hours: 18)).toIso8601String(),
      'participantCount': 6,
      'finishReward': {'pool': 500, 'paidPlaces': 10},
      'myStatus': 'ACCEPTED',
      'isFull': false,
      'bucketPrivate': true,
    },
    {
      'raceId': 'featured-2',
      'name': 'Weekly 50K Sprint',
      'seedKind': 'WEEKLY',
      'endsAt': now.add(const Duration(days: 3)).toIso8601String(),
      'participantCount': 9,
      'finishReward': {'pool': 2000, 'paidPlaces': 18},
      'myStatus': 'ACCEPTED',
      'isFull': false,
      'bucketPrivate': true,
    },
  ];
}
