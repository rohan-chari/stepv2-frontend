import '../services/backend_api_service.dart';
import '../models/race_resolution_status.dart';
import 'demo_race_engine.dart';

/// A fake backend for the REAL `RaceDetailScreen` (spec §5.1).
///
/// `RaceDetailScreen` routes every read and write through `_api`, and makes
/// ~25 distinct `_api.*` calls (F1). **Any one of them not overridden here is a
/// live HTTPS request against prod with a fabricated race id.** The transport
/// helpers on [BackendApiService] are private, so the base class cannot be
/// cheaply sealed — which is why `test/demo_race_network_guard_test.dart`
/// enumerates the call sites from source and fails when a 26th appears.
///
/// Every override below either serves the engine or is a deliberate no-op. None
/// of them touch the network, and none of them can reach real race, powerup or
/// settlement logic.
class DemoRaceApiService extends BackendApiService {
  DemoRaceApiService(this.engine);

  final DemoRaceEngine engine;
  final Map<String, String> _socialState = <String, String>{};
  final Map<String, String> _socialIds = <String, String>{};

  void seedReversePending(String targetUserId) {
    _socialState[targetUserId] = 'incoming';
    _socialIds[targetUserId] = 'demo-reverse-pending';
  }

  // Social reads and mutations are local fixtures as well. The real Race
  // Detail can open the same dossier as production, but a tutorial/demo
  // target must never turn that gesture into a live request.
  @override
  Future<Map<String, dynamic>> fetchPublicProfile({
    required String identityToken,
    required String userId,
  }) async => {
    'contract': 'public-profile-v1',
    'user': {
      'id': userId,
      'displayName': userId == engine.myUserId ? 'Rohan' : 'Demo Runner',
      'profilePhotoUrl': null,
      'equippedAnimal': null,
      'equippedAccessories': const <Map<String, dynamic>>[],
    },
    'stats': {
      'racePodiums': {'first': 1, 'second': 0, 'third': 0},
      'avgStepsPerDay': 12000,
    },
  };

  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    final friends = <Map<String, dynamic>>[];
    final incoming = <Map<String, dynamic>>[];
    final outgoing = <Map<String, dynamic>>[];
    _socialState.forEach((id, state) {
      final user = {'id': id, 'displayName': 'Demo Runner'};
      final friendshipId = _socialIds[id];
      if (state == 'friends') {
        friends.add({...user, 'friendshipId': friendshipId});
      }
      if (state == 'incoming') {
        incoming.add({'friendshipId': friendshipId, 'user': user});
      }
      if (state == 'outgoing') {
        outgoing.add({'friendshipId': friendshipId, 'user': user});
      }
    });
    return {
      'friends': friends,
      'pending': {'incoming': incoming, 'outgoing': outgoing},
    };
  }

  @override
  Future<Map<String, dynamic>> sendFriendRequest({
    required String identityToken,
    required String addresseeId,
  }) async {
    final reverse = _socialState[addresseeId] == 'incoming';
    if (!reverse && _socialState[addresseeId] == 'outgoing') {
      throw const ApiException(
        'Friend request already pending.',
        statusCode: 409,
      );
    }
    _socialState[addresseeId] = reverse ? 'friends' : 'outgoing';
    _socialIds[addresseeId] ??= 'demo-request';
    return {
      'friendship': {
        'id': _socialIds[addresseeId],
        'status': reverse ? 'ACCEPTED' : 'PENDING',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> respondToFriendRequest({
    required String identityToken,
    required String friendshipId,
    required bool accept,
  }) async {
    final target = _socialIds.entries
        .where((entry) => entry.value == friendshipId)
        .map((entry) => entry.key)
        .firstOrNull;
    if (target != null) _socialState[target] = accept ? 'friends' : 'none';
    return {
      'friendship': {
        'id': friendshipId,
        'status': accept ? 'ACCEPTED' : 'DECLINED',
      },
    };
  }

  @override
  Future<void> removeFriend({
    required String identityToken,
    required String friendshipId,
  }) async {
    final target = _socialIds.entries
        .where((entry) => entry.value == friendshipId)
        .map((entry) => entry.key)
        .firstOrNull;
    if (target != null) _socialState[target] = 'none';
  }

  // Demo/tutorial narratives must never request live recipient-private impact
  // data or present an unscripted settlement overlay over a spotlight beat.
  @override
  Future<PrivateRaceImpactFeedPage> fetchPrivateRaceImpactFeed({
    required String identityToken,
    required String raceId,
    String? cursor,
    int limit = 50,
  }) async => PrivateRaceImpactFeedPage.empty;

  @override
  Future<List<Map<String, dynamic>>> fetchRaceImpactNotices({
    required String identityToken,
    required String raceId,
  }) async => const [];

  @override
  Future<ActiveImpactNoticesResult> fetchActiveRaceImpactNotices({
    required String identityToken,
    required String raceId,
    DateTime? resolvedAfter,
  }) async => ActiveImpactNoticesResult.empty;

  @override
  Future<RaceResolutionStatus> fetchRaceResolutionStatus({
    required String identityToken,
    required String jobId,
    required int generation,
  }) async => const RaceResolutionStatus(RaceResolutionState.notFound);

  @override
  Future<bool> acknowledgeActiveRaceImpactNotice({
    required String identityToken,
    required String raceId,
    required String noticeId,
  }) async => false;

  @override
  Future<bool> acknowledgeActiveImpactReceipt({
    required String identityToken,
    required String raceId,
    required String receiptId,
  }) async => false;

  @override
  Future<void> acknowledgeRaceImpactNotice({
    required String identityToken,
    required String raceId,
    required String noticeId,
  }) async {}

  /// The engine owns the clock (and the tests own the engine's), so the served
  /// `endsAt` and the engine's countdown can never disagree.
  DateTime get _now => engine.now();

  // -- Reads the screen makes on open ----------------------------------------

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    // Accepted and ignored, exactly like fetchRaceBootstrap below — the demo
    // roster is smaller than a page, and the engine is the only source of
    // truth here. Never let this reach a network.
    int? participantsLimit,
  }) async => engine.raceDetails(_now, wallNow: DateTime.now());

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async => engine.raceProgress(_now);

  @override
  Future<RaceBootstrapResult> fetchRaceBootstrap({
    required String identityToken,
    required String raceId,
    // Accepted and ignored — the demo roster is smaller than a page, and the
    // engine is the only source of truth here. Never let this reach a network.
    int? participantsLimit,
  }) async => RaceBootstrapResult(
    supported: true,
    race: engine.raceDetails(_now, wallNow: DateTime.now()),
    progress: engine.raceProgress(_now),
    globalPowerupInventory: const {'items': []},
  );

  @override
  Future<RaceProgressResult> fetchRaceProgressCompact({
    required String identityToken,
    required String raceId,
  }) async => RaceProgressResult(
    progress: engine.raceProgress(_now),
    globalPowerupInventory: const {'items': []},
    hasCompactInventory: true,
  );

  @override
  Future<RaceProgressResult> fetchRaceProgressParticipants({
    required String identityToken,
    required String raceId,
    int offset = 0,
    int limit = 10,
  }) async {
    final full =
        (engine.raceProgress(_now)['participants'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];
    final start = offset < 0 ? 0 : offset;
    final take = limit <= 0 ? 10 : (limit > 50 ? 50 : limit);
    final participants = full.skip(start).take(take).toList();
    return RaceProgressResult(
      progress: {...engine.raceProgress(_now), 'participants': participants},
      globalPowerupInventory: const {'items': []},
      hasCompactInventory: true,
      participantsPagination: {
        'offset': offset,
        'limit': limit,
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
    final powerupData = (engine.raceProgress(_now)['powerupData'] as Map?)
        ?.cast<String, dynamic>();
    final inventory = powerupData?['inventory'] is List
        ? (powerupData?['inventory'] as List)
              .whereType<Map<String, dynamic>>()
              .toList()
        : const [];
    return {
      'participants':
          (engine.raceProgress(_now)['participants'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [],
      'powerupData': {
        'powerupSlots': powerupData?['powerupSlots'] ?? 3,
        'inventory': inventory,
        'queuedBoxCount': powerupData?['queuedBoxCount'] ?? 0,
        'myPlacement': engine.myPlacement,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRacePowerupTargetContext({
    required String identityToken,
    required String raceId,
    required String powerupType,
  }) async {
    final legacy = await fetchRacePowerupUseContext(
      identityToken: identityToken,
      raceId: raceId,
    );
    final participants =
        (legacy['participants'] as List?)?.whereType<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    return {
      'contract': 'race-powerup-target-context-v1',
      'participants': [
        for (final participant in participants)
          {
            'userId': participant['userId'],
            'displayName': participant['displayName'],
            'profilePhotoUrl': participant['profilePhotoUrl'],
            'team': participant['team'],
            'forfeitedAt': participant['forfeitedAt'],
            'stealthed': participant['stealthed'] == true,
            if (powerupType == 'BOUNTY')
              'totalSteps': (participant['totalSteps'] as num?)?.toInt() ?? 0,
          },
      ],
      'powerupData': legacy['powerupData'],
    };
  }

  /// Empty global stash: the demo's lesson is the in-race slots, and a stash
  /// row would offer a "USE" button that spends real coins.
  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => const {'items': []};

  // -- Powerups ---------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> usePowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    String? targetUserId,
    String? targetDirection,
    String? targetEffectId,
    int upgradeLevel = 0,
  }) async {
    // `upgradeLevel` is ignored on purpose: the upgrade ladders are disabled in
    // demoMode (§5.7b), and an upgrade would charge coins.
    return engine.usePowerup(powerupId: powerupId, targetUserId: targetUserId);
  }

  /// Quicksand is not in the demo's inventory, so this is unreachable — but it
  /// must still never leave the device.
  @override
  Future<Map<String, dynamic>> useQuicksand({
    required String identityToken,
    required String raceId,
    required String powerupId,
    required List<String> targetUserIds,
  }) async => engine.usePowerup(powerupId: powerupId);

  @override
  Future<Map<String, dynamic>> openMysteryBox({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async => engine.openBox(powerupId);

  /// OPEN ALL is disabled in demoMode (§5.7b); this exists so the call site
  /// cannot leak if that ever changes.
  @override
  Future<Map<String, dynamic>> openMysteryBoxBatch({
    required String identityToken,
    required String raceId,
    required List<String> powerupIds,
    bool includeQueued = true,
    int maxCount = 20,
  }) async {
    return {
      'results': [
        for (final id in powerupIds)
          {
            ...engine.openBox(id)['result'] as Map<String, dynamic>,
            'queued': false,
          },
      ],
    };
  }

  /// Discard is disabled in demoMode — discarding the Protein Shake would
  /// dead-end the script with no recovery (§5.7b). No-op, never a network call.
  @override
  Future<Map<String, dynamic>> discardPowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> redeemPowerupToRace({
    required String identityToken,
    required String raceId,
    required String powerupType,
  }) async => const {'result': {}};

  @override
  Future<Map<String, dynamic>> fetchSneakySwapTargets({
    required String identityToken,
    required String raceId,
  }) async => const {'targets': []};

  // -- Rewards and wallet (§5.6 / G1) ----------------------------------------

  /// The starter reward is NOT the tutorial reward. Claiming it here would mint
  /// 100 coins against a fake race, so the demo never sees it as eligible —
  /// and `demoMode` skips the fetch entirely.
  @override
  Future<Map<String, dynamic>> fetchStarterReward({
    required String identityToken,
  }) async => const {'eligible': false, 'claimed': false};

  @override
  Future<Map<String, dynamic>> claimStarterReward({
    required String identityToken,
  }) async => const {'granted': false};

  /// `_refreshWallet` writes the result through `authService.updateCoins`.
  /// `DemoAuthService` no-ops that write, and this reports the real balance
  /// back unchanged, so the demo cannot move the user's coins.
  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return {'coins': null, 'heldCoins': null};
  }

  // -- Race creation (the prologue, §5.1) -------------------------------------
  //
  // The demo opens on the REAL CreateRaceScreen, so every create path that
  // screen can take has to land here. None of them post anything: they mark the
  // engine's prologue beat and hand back the demo race the tutorial is about to
  // run. A missing override here would create a REAL race on the user's
  // account before they have finished onboarding.

  @override
  Future<Map<String, dynamic>> createRace({
    required String identityToken,
    required String name,
    int buyInAmount = 0,
    int maxDurationDays = 3,
    bool powerupsEnabled = true,
    int? powerupStepInterval,
    String payoutPreset = 'WINNER_TAKES_ALL',
    bool isPublic = false,
    int? maxParticipants,
    DateTime? scheduledStartAt,
    // Mirrored, not omitted: an override that drops a param the base class
    // declares does not compile, and one that silently diverges would let the
    // create screen fall through to the REAL createRace inside onboarding
    // (§10.1 risk 2). The demo ignores the value — its window is scripted.
    DateTime? scheduledEndAt,
  }) async {
    engine.markRaceCreated(durationDays: maxDurationDays);
    return {'race': engine.raceDetails(_now, wallNow: DateTime.now())};
  }

  /// Teams are hidden in the demo's create screen, but the call site exists —
  /// and an unoverridden one is a real team race on a real account.
  @override
  Future<Map<String, dynamic>> createTeamRace({
    required String identityToken,
    required String name,
    required int teamSize,
    int buyInAmount = 0,
    int maxDurationDays = 3,
    bool powerupsEnabled = true,
    int? powerupStepInterval,
    bool isPublic = false,
    DateTime? scheduledStartAt,
    DateTime? scheduledEndAt,
    String? teamAName,
    String? teamBName,
    String? creatorTeam,
  }) async {
    engine.markRaceCreated(durationDays: maxDurationDays);
    return {'race': engine.raceDetails(_now, wallNow: DateTime.now())};
  }

  @override
  Future<Map<String, dynamic>> createTournament({
    required String identityToken,
    required String name,
    required int bracketSize,
    required int matchupDurationDays,
    int buyInAmount = 0,
    bool powerupsEnabled = true,
    int? powerupStepInterval,
    bool isPublic = false,
    List<String> inviteeIds = const [],
  }) async {
    engine.markRaceCreated();
    return const {'tournament': null};
  }

  /// Cosmetic name pairs for the (hidden) teams mode. Served locally so the
  /// screen never reaches for the pool.
  @override
  Future<(String, String)?> fetchTeamNameSuggestion({
    required String identityToken,
  }) async => null;

  // -- Race lifecycle: every one of these is a no-op ---------------------------

  @override
  Future<Map<String, dynamic>> startRace({
    required String identityToken,
    required String raceId,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> leaveRace({
    required String identityToken,
    required String raceId,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> forfeitRace({
    required String identityToken,
    required String raceId,
  }) async => const {};

  @override
  Future<void> cancelRace({
    required String identityToken,
    required String raceId,
  }) async {}

  @override
  Future<void> kickRaceParticipant({
    required String identityToken,
    required String raceId,
    required String userId,
  }) async {}

  @override
  Future<Map<String, dynamic>> inviteToRace({
    required String identityToken,
    required String raceId,
    required List<String> inviteeIds,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> respondToRaceInvite({
    required String identityToken,
    required String raceId,
    required bool accept,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> acceptTeamRaceInvite({
    required String identityToken,
    required String raceId,
    required String team,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> setRaceTeam({
    required String identityToken,
    required String raceId,
    required String team,
  }) async => const {};

  /// Never mint a share link for a race that does not exist (§5.6).
  @override
  Future<Map<String, dynamic>> createRaceShareLink({
    required String identityToken,
    required String raceId,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> setRaceChatMute({
    required String identityToken,
    required String raceId,
    required bool muted,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> setRacePlacementMute({
    required String identityToken,
    required String raceId,
    required bool muted,
  }) async => const {};

  // -- Chat / activity feed (RaceChatService + RaceFeedService) --------------

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async => engine.messages(kind);

  @override
  Future<Map<String, dynamic>> fetchRaceTimeline({
    required String identityToken,
    required String raceId,
    String? cursor,
    int limit = 30,
  }) async {
    final system = engine.messages('SYSTEM')['messages'];
    final user = engine.messages('USER')['messages'];
    final messages = <Map<String, dynamic>>[
      if (system is List)
        ...system.whereType<Map>().map(Map<String, dynamic>.from),
      if (user is List) ...user.whereType<Map>().map(Map<String, dynamic>.from),
    ]..sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
    return {'messages': messages, 'nextCursor': null, 'timelineVersion': 1};
  }

  @override
  Future<RaceMessageStreamsResult> fetchRaceMessageStreams({
    required String identityToken,
    required String raceId,
    required bool includeUser,
    int limit = 50,
  }) async {
    final system = engine.messages('SYSTEM');
    final user = includeUser ? engine.messages('USER') : null;
    final userRows = user?['messages'];
    final ids = userRows is List
        ? userRows
              .whereType<Map>()
              .map((row) => row['id'])
              .whereType<String>()
              .take(50)
              .toList(growable: false)
        : const <String>[];
    return RaceMessageStreamsResult(
      supported: true,
      systemStream: system,
      userStream: user,
      systemResolved: true,
      userResolved: includeUser,
      chatWatermark: {'recentIds': ids},
    );
  }

  @override
  void resetRaceMessageConditionalState({String? raceId}) {}

  @override
  Future<Map<String, dynamic>> markRaceChatRead({
    required String identityToken,
    required String raceId,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> sendRaceMessage({
    required String identityToken,
    required String raceId,
    required String body,
  }) async => const {};

  @override
  Future<Map<String, dynamic>> deleteRaceMessage({
    required String identityToken,
    required String raceId,
    required String messageId,
  }) async => const {};

  /// Batch 2026-08-08 item 11 — the rewarded-ad box reroll.
  ///
  /// UNREACHABLE in the demo by design: the reroll button is gated on
  /// `powerupData.boxReroll == true` AND `!demoMode`, and this service's
  /// progress payload never carries the flag. The override exists so the
  /// §8.4 network-leak guard stays honest — an un-overridden call site is a
  /// live HTTPS request against prod with a fabricated race id, whether or not
  /// today's UI can reach it.
  @override
  Future<Map<String, dynamic>> rerollPowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    required String localDate,
  }) async => const {};

  /// Batch 2026-08-10b item 1 — the rewarded-ad REROLL ALL after OPEN ALL.
  ///
  /// UNREACHABLE in the demo by design: OPEN ALL itself is suppressed in
  /// demoMode (§5.7b), `_boxRerollBatchEnabled` carries its own `!demoMode`
  /// guard, and this service's progress payload never advertises
  /// `boxRerollBatch`. The override exists so the §8.4 network-leak guard
  /// stays honest — an un-overridden call site is a live HTTPS request against
  /// prod with a fabricated race id, whether or not today's UI can reach it.
  @override
  Future<Map<String, dynamic>> rerollPowerupBatch({
    required String identityToken,
    required String raceId,
    required List<String> powerupIds,
    required String localDate,
  }) async => const {};

  // -- Telemetry --------------------------------------------------------------
  //
  // Activation events for the demo funnel are recorded through a REAL
  // BackendApiService owned by the host, never through this one: an event
  // emitted here would carry a fabricated raceId (§5.6). Batching through the
  // demo service is therefore dropped on the floor.

  @override
  Future<void> sendActivationEvents({
    required String identityToken,
    required List<Map<String, dynamic>> events,
  }) async {}
}
