import '../models/step_data.dart';
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

  // -- Leaderboard: steps / global / today --
  @override
  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async {
    Map<String, dynamic> row(
      int rank,
      String userId,
      String name,
      int steps,
    ) => {
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
        'settlesAt': now.add(const Duration(days: 4, hours: 12))
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
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async {
    return tutorialPreviewRaceMessages(kind);
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
Map<String, dynamic> tutorialPreviewHomeRaceCard() {
  final now = DateTime.now();
  return {
    'state': 'ACTIVE_RACES',
    'data': {
      'races': [
        {
          'raceId': 'home-race-1',
          'name': 'Weekend 10K',
          'endsAt': now.add(const Duration(days: 2, hours: 4)).toIso8601String(),
          'userPlacement': 2,
          'participantCount': 6,
          'top3': const [
            {'userId': 'rk-1', 'displayName': 'Sam Rivera', 'rank': 1},
            {'userId': tutorialPreviewUserId, 'displayName': 'Rohan', 'rank': 2},
            {'userId': 'rk-3', 'displayName': 'Jordan Lee', 'rank': 3},
          ],
        },
      ],
    },
  };
}

/// Races screen data: active (one with a placement + queued boxes), an invite,
/// and a completed race.
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
        'id': 'race-invite-1',
        'name': 'Morning Crew',
        'status': 'PENDING',
        'maxDurationDays': 7,
        'endsAt': now.add(const Duration(days: 1)).toIso8601String(),
        'participantCount': 3,
        'creator': {'displayName': 'Alex'},
        'isCreator': false,
        'myStatus': 'INVITED',
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
    'targetSteps': 30000,
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
        'body': 'who hit me with the leg cramp 😤',
        'senderId': tutorialPreviewUserId,
        'senderName': 'Rohan',
        'senderPhotoUrl': null,
        'createdAt': now.subtract(const Duration(minutes: 4)).toIso8601String(),
      },
      {
        'id': 'msg-2',
        'kind': 'USER',
        'body': 'gg everyone, catching up tonight 🏃',
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
      'participantCount': 142,
      'finishReward': {'pool': 500},
      'myStatus': null,
      'isFull': false,
    },
    {
      'raceId': 'featured-2',
      'name': 'Weekly 50K Sprint',
      'seedKind': 'WEEKLY',
      'endsAt': now.add(const Duration(days: 3)).toIso8601String(),
      'participantCount': 87,
      'finishReward': {'pool': 2000},
      'myStatus': null,
      'isFull': false,
    },
  ];
}
