import 'support/shop_navigation.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/home_sync_refresh.dart';
import 'package:step_tracker/models/interstitial_ad.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/screens/onboarding_flow.dart';
import 'package:step_tracker/screens/get_coins_screen.dart';
import 'package:step_tracker/screens/inbox_screen.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/screens/tabs/races_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
import 'package:step_tracker/models/race_payout_double_offer.dart';
import 'package:step_tracker/models/race_resolution_status.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/services/interstitial_ad_service.dart';
import 'package:step_tracker/services/notification_service.dart';
import 'package:step_tracker/services/race_results_ack_queue.dart';
import 'package:step_tracker/services/review_prompt_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/wooden_tab_bar.dart';
import 'package:step_tracker/widgets/home_course_track.dart';
import 'package:step_tracker/widgets/billing_scope.dart';
import 'billing_components_test.dart' show FakeBilling;

class _EquipmentRouteApi extends _FakeBackendApiService {
  bool equipped = false;
  int equipWrites = 0;
  Map<String, dynamic> get hat => {
    'id': 'wizard',
    'sku': 'WIZARD',
    'name': 'Wizard Hat',
    'description': 'A cozy hat',
    'slot': 'HEAD',
    'assetKey': 'wizard_hat',
    'priceCoins': 100,
    'owned': true,
    'equipped': equipped,
  };
  Map<String, dynamic> get envelope => {
    'contract': 'character-wardrobes-v1',
    'appearanceRevision': equipWrites,
    'activeCharacterKey': 'default',
    'activeCharacterVisible': true,
    'coins': 1000,
  };
  Map<String, dynamic> get outfit => {
    'revision': equipWrites,
    'editable': true,
    'hasHiddenItems': false,
    'slots': {
      'HEAD': equipped ? 'wizard' : null,
      'FACE': null,
      'NECK': null,
      'BACK': null,
      'FEET': null,
    },
    'items': [if (equipped) hat],
    'unavailableItemIds': [],
  };
  @override
  Future<Map<String, dynamic>> fetchShopCharacters({
    required String identityToken,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async => {
    ...envelope,
    'characters': [
      {
        'characterKey': 'default',
        'name': 'Capybara',
        'item': null,
        'owned': true,
        'active': true,
        'canPurchase': false,
        'canActivate': true,
        'canEdit': true,
        'availability': 'available',
        'outfit': outfit,
      },
    ],
    'nextCursor': null,
  };
  @override
  Future<Map<String, dynamic>> fetchCharacterWardrobe({
    required String identityToken,
    required String characterKey,
    int limit = 24,
    String? cursor,
    String? localDate,
  }) async => {
    ...envelope,
    'characterKey': characterKey,
    'name': 'Capybara',
    'active': true,
    'canActivate': true,
    'outfit': outfit,
    'accessories': [
      {
        'item': hat,
        'owned': true,
        'canPurchase': false,
        'canPreview': true,
        'canSelect': true,
        'fit': 'approved',
        'unavailableReason': null,
      },
    ],
    'nextCursor': null,
  };
  @override
  Future<Map<String, dynamic>> saveCharacterOutfit({
    required String identityToken,
    required String characterKey,
    required int expectedOutfitRevision,
    required Map<String, String?> slots,
  }) async {
    expect(expectedOutfitRevision, equipWrites);
    equipWrites++;
    equipped = slots['HEAD'] == 'wizard';
    return {
      ...envelope,
      'characterKey': characterKey,
      'outfit': outfit,
      'appearanceChanged': true,
      'equipped': {if (equipped) 'HEAD': hat},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => {
    'coins': 1000,
    'ownedItemIds': ['wizard'],
    'equipped': equipped ? {'HEAD': hat} : <String, dynamic>{},
    'items': [hat],
  };
  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async => {'coins': 1000, 'items': []};
  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => {'items': []};
  @override
  Future<Map<String, dynamic>> equipAccessory({
    required String identityToken,
    required String slot,
    required String? itemId,
  }) async {
    equipWrites++;
    equipped = itemId == 'wizard';
    return {
      'equipped': equipped ? {'HEAD': hat} : <String, dynamic>{},
    };
  }
}

class _FakeHealthService extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;

  @override
  Future<StepData> getStepsToday() async {
    return StepData(steps: 1234, date: DateTime(2026, 6, 1));
  }

  @override
  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    return const [];
  }
}

class _FailingHealthService extends _FakeHealthService {
  @override
  Future<StepData> getStepsToday() async => throw StateError('health failed');
}

class _RecapHealth extends _FakeHealthService {
  _RecapHealth(this.events, {this.rawSteps = 1000});
  final List<String> events;
  int? rawSteps;
  Completer<int?>? pending;
  DateTime? start;
  DateTime? end;
  List<StepSampleData> samples = [];

  @override
  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async => samples;

  @override
  Future<int?> getRawStepsInInterval(DateTime start, DateTime end) async {
    events.add('health-window');
    this.start = start;
    this.end = end;
    return pending == null ? rawSteps : pending!.future;
  }
}

class _RecapApi extends _FakeBackendApiService {
  _RecapApi({super.homeInvitePreflight});
  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async => {
    'friends': [],
    'pending': {'incoming': [], 'outgoing': []},
  };
  final List<String> events = [];
  StepSyncV2Kind syncKind = StepSyncV2Kind.current;
  Map<String, dynamic>? candidate;
  Completer<Map<String, dynamic>?>? pendingGet;
  Completer<Map<String, dynamic>?>? pendingPost;
  int? postedRaw;
  String? postedEventId;
  int? postedRevision;
  int gets = 0;
  int posts = 0;
  Completer<StepSyncV2Result>? pendingSync;
  bool failSamples = false;

  @override
  Future<void> recordSteps({
    required String identityToken,
    required StepData stepData,
    bool skipRaceResolution = false,
  }) async {
    events.add('legacy-total');
  }

  @override
  Future<void> recordStepSamples({
    required String identityToken,
    required List<StepSampleData> samples,
  }) async {
    events.add('legacy-samples');
    if (failSamples) throw StateError('sample upload failed');
  }

  @override
  Future<StepSyncV2Result> recordStepSyncV2({
    required String identityToken,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
    bool homePull = false,
  }) async {
    events.add('sync');
    if (pendingSync != null) return pendingSync!.future;
    return StepSyncV2Result(kind: syncKind);
  }

  @override
  Future<Map<String, dynamic>?> fetchEventRecap({
    required String identityToken,
  }) async {
    events.add('get');
    gets++;
    return pendingGet == null ? candidate : pendingGet!.future;
  }

  @override
  Future<Map<String, dynamic>?> finalizeEventRecap({
    required String identityToken,
    required String eventId,
    required int revision,
    required int rawSteps,
  }) async {
    events.add('post');
    posts++;
    postedRaw = rawSteps;
    postedEventId = eventId;
    postedRevision = revision;
    if (pendingPost != null) return pendingPost!.future;
    candidate = rawSteps == 0
        ? {'state': 'none'}
        : {
            'state': 'ready',
            'globalEventSummary': _globalEventSummary(
              extraRaceSteps: rawSteps * 3,
            ),
          };
    return candidate;
  }
}

Map<String, dynamic> _recapCandidate() {
  final now = DateTime.now().toUtc();
  return {
    'state': 'pending',
    'event': {
      'id': 'event-1',
      'revision': 3,
      'raceCount': 3,
      'startsAt': now.subtract(const Duration(minutes: 40)).toIso8601String(),
      'endsAt': now.subtract(const Duration(minutes: 10)).toIso8601String(),
      'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
    },
  };
}

Future<AuthService> _mountRecap(
  WidgetTester tester,
  _RecapApi api,
  _RecapHealth health,
) async {
  final auth = await _authService();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('last_seen_whats_new_version', '2.3.0');
  await tester.pumpWidget(
    MaterialApp(
      home: MainShell(
        authService: auth,
        healthService: health,
        backendApiService: api,
        backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return auth;
}

class _GrantHealthOnRequest extends _FakeHealthService {
  @override
  Future<bool> restoreHealthAuthState() async => false;
  @override
  Future<HealthSetupResult> setUpHealthAccess() async =>
      HealthSetupResult.authorized;
}

class _RecoveringHomeSuggestionsApi extends _FakeBackendApiService {
  _RecoveringHomeSuggestionsApi({
    this.failFirst = false,
    this.hangFirst = false,
  });
  final bool failFirst;
  final bool hangFirst;
  final stalled = Completer<HomeSuggestedRacesRefresh>();

  @override
  Future<HomeSuggestedRacesRefresh> fetchHomeSuggestedRaces({
    required String identityToken,
  }) async {
    homeSuggestionCalls++;
    if (homeSuggestionCalls == 1) {
      if (failFirst) throw StateError('Response stream interrupted');
      if (hangFirst) return stalled.future;
    }
    final suggestion = HomeRaceSuggestion.tryParse(const {
      'kind': 'FEATURED_RACE',
      'id': 'recovered-daily',
      'seedKind': 'DAILY_10K',
      'name': 'Recovered Daily Race',
      'status': 'ACTIVE',
      'endsAt': '2036-09-10T00:00:00Z',
      'participantCount': 12,
      'maxParticipants': 100,
      'isFull': false,
      'powerupsEnabled': true,
      'prizePool': null,
      'finishReward': null,
      'joinAction': 'JOIN',
    });
    return HomeSuggestedRacesRefresh(
      featuredRaces: [?suggestion],
      publicRaces: const [],
      tournaments: const [],
    );
  }
}

class _AndroidPermissionHealth extends _FakeHealthService {
  bool? permission = false;
  int reads = 0;
  @override
  bool get isAndroid => true;
  @override
  Future<bool?> getStepPermission() async => permission;
  @override
  Future<StepData> getStepsToday() async {
    reads++;
    return super.getStepsToday();
  }
}

class _MissingRaceApi extends _FakeBackendApiService {
  _MissingRaceApi({super.inboxAlerts});

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => throw const ApiException(
    'Race not found',
    statusCode: 404,
    code: 'RACE_NOT_FOUND',
  );
}

class _DelayedSessionMissingRaceApi extends _MissingRaceApi {
  final Completer<Map<String, dynamic>> session = Completer();

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) => session.future;

  void completeSession(String token) {
    session.complete({
      'sessionToken': token,
      'user': {
        'firstRaceOnboardingSeen': true,
        'tutorialOnboardingSeen': true,
        'featureFlags': {'onboardingV3Enabled': false},
      },
    });
  }
}

class _FakeBackgroundSyncBootstrapService
    extends BackgroundSyncBootstrapService {
  @override
  Future<void> enableHealthKitBackgroundDelivery() async {}
}

class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService({
    this.racesData = const {
      'invites': <Map<String, dynamic>>[],
      'waiting': <Map<String, dynamic>>[],
      'active': <Map<String, dynamic>>[],
      'completed': <Map<String, dynamic>>[],
    },
    this.homeInvitePreflight = const {
      'resolved': true,
      'invites': <Map<String, dynamic>>[],
    },
    this.completeOnboarding = true,
    this.displayName = 'Trail Walker',
    this.homeRaceCard = const {'state': 'EMPTY'},
    this.inboxAlerts = const {
      'alerts': <Map<String, dynamic>>[],
      'nextCursor': null,
    },
  });

  final Map<String, dynamic> racesData;
  final Map<String, dynamic> homeInvitePreflight;
  final bool completeOnboarding;
  final String displayName;
  final Map<String, dynamic> homeRaceCard;
  final Map<String, dynamic> inboxAlerts;
  int homeSuggestionCalls = 0;
  int racesDiscoveryCalls = 0;
  int payoutClaimCalls = 0;
  int seenCalls = 0;
  int homeInvitePreflightCalls = 0;
  int globalSummaryAckCalls = 0;
  int reviewClaimCalls = 0;
  final List<({String token, List<String> raceIds})> seenRequests = [];

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async {
    return {
      'sessionToken': authToken,
      'user': {
        'firstRaceOnboardingSeen': completeOnboarding,
        'tutorialOnboardingSeen': completeOnboarding,
        'featureFlags': {'onboardingV3Enabled': !completeOnboarding},
      },
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
    bool homePull = false,
  }) async => const StepSyncV2Result(kind: StepSyncV2Kind.unsupported);

  @override
  Future<RaceDiscoverySummary> fetchRaceDiscoverySummary({
    required String identityToken,
  }) async {
    racesDiscoveryCalls++;
    return RaceDiscoverySummary.unsupportedResult;
  }

  @override
  Future<HomeSuggestedRacesRefresh> fetchHomeSuggestedRaces({
    required String identityToken,
  }) async {
    homeSuggestionCalls++;
    return const HomeSuggestedRacesRefresh(
      featuredRaces: [],
      publicRaces: [],
      tournaments: [],
    );
  }

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) async {
    return homeRaceCard;
  }

  @override
  Future<Map<String, dynamic>> fetchInboxAlerts({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => inboxAlerts;

  @override
  Future<Map<String, dynamic>> markInboxAlertRead({
    required String identityToken,
    required String alertId,
  }) async => const {'read': true, 'unreadCount': 0, 'totalUnreadCount': 0};

  @override
  Future<Map<String, dynamic>> fetchFeedbackThreads({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => const {'threads': <Map<String, dynamic>>[], 'nextCursor': null};

  @override
  Future<Map<String, dynamic>> fetchHomeInvitePreflight({
    required String identityToken,
  }) async {
    homeInvitePreflightCalls++;
    return homeInvitePreflight;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async {
    return const [];
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    return {
      'displayName': displayName,
      'incomingFriendRequests': 0,
      'firstRaceOnboardingSeen': completeOnboarding,
      'tutorialOnboardingSeen': completeOnboarding,
      'featureFlags': {'onboardingV3Enabled': !completeOnboarding},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async {
    return racesData;
  }

  @override
  Future<RacePayoutDoubleClaimResult> claimRacePayoutDouble({
    required String identityToken,
    required String offerId,
    required List<String> popupRaceIds,
  }) async {
    payoutClaimCalls++;
    return RacePayoutDoubleClaimResult.tryParse(const {
      'awarded': false,
      'alreadyClaimed': true,
      'raceIds': ['race-a'],
      'baseCoins': 120,
      'bonusCoins': 120,
      'maxBonusCoins': 500,
      'rolling24hRemainingBeforeClaim': 500,
      'coins': 245,
    }, popupRaceIds: popupRaceIds)!;
  }

  @override
  Future<void> markRaceResultsSeenStrict({
    required String identityToken,
    required List<String> raceIds,
    required bool racePayoutDoubleCapability,
  }) async {
    seenCalls++;
    seenRequests.add((token: identityToken, raceIds: List<String>.of(raceIds)));
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async {
    return const [];
  }

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

  @override
  Future<void> acknowledgeGlobalEventSummary({
    required String identityToken,
    required String summaryId,
  }) async {
    globalSummaryAckCalls++;
  }

  @override
  Future<void> claimReviewOpportunity({
    required String identityToken,
    required String raceId,
    required String opportunityId,
  }) async {
    reviewClaimCalls++;
  }
}

class _DeferredSummaryApi extends _FakeBackendApiService {
  final Completer<Map<String, dynamic>> homeCard = Completer();

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) => homeCard.future;
}

class _SlowStepSyncApi extends _FakeBackendApiService {
  final Completer<StepSyncV2Result> sync = Completer<StepSyncV2Result>();

  @override
  Future<StepSyncV2Result> recordStepSyncV2({
    required String identityToken,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
    bool homePull = false,
  }) => sync.future;
}

class _HomeRequestDagApi extends _FakeBackendApiService {
  final List<String> started = [];
  final Completer<StepSyncV2Result> sync = Completer<StepSyncV2Result>();
  final Completer<Map<String, dynamic>> raceCard =
      Completer<Map<String, dynamic>>();
  final Completer<Map<String, dynamic>> races =
      Completer<Map<String, dynamic>>();
  final Completer<HomeSuggestedRacesRefresh> suggestions =
      Completer<HomeSuggestedRacesRefresh>();
  final Completer<Map<String, dynamic>> friends =
      Completer<Map<String, dynamic>>();
  final Completer<Map<String, dynamic>> catalog =
      Completer<Map<String, dynamic>>();
  final Completer<Map<String, dynamic>> me = Completer<Map<String, dynamic>>();
  final List<bool> persistedTotalFlags = [];

  @override
  Future<StepSyncV2Result> recordStepSyncV2({
    required String identityToken,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
    bool homePull = false,
  }) {
    started.add('sync-v2');
    return sync.future;
  }

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) {
    started.add('race-card');
    persistedTotalFlags.add(usePersistedTotals);
    return raceCard.future;
  }

  @override
  Future<Map<String, dynamic>> fetchRaces({required String identityToken}) {
    started.add('races');
    return races.future;
  }

  @override
  Future<HomeSuggestedRacesRefresh> fetchHomeSuggestedRaces({
    required String identityToken,
  }) {
    started.add('suggestions');
    return suggestions.future;
  }

  @override
  Future<Map<String, dynamic>> fetchFriends({required String identityToken}) {
    started.add('friends');
    return friends.future;
  }

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) {
    started.add('catalog');
    return catalog.future;
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) {
    started.add('me');
    return me.future;
  }
}

class _RacesTabRevealApi extends _FakeBackendApiService {
  _RacesTabRevealApi({required this.cachedFriends});

  static const cachedRaces = <String, dynamic>{
    'invites': <Map<String, dynamic>>[],
    'waiting': <Map<String, dynamic>>[],
    'active': <Map<String, dynamic>>[
      {
        'id': 'cached-race',
        'name': 'Cached Sprint',
        'status': 'ACTIVE',
        'myStatus': 'ACCEPTED',
        'participantCount': 2,
        'placementPrivacyActive': false,
      },
    ],
    'completed': <Map<String, dynamic>>[],
  };

  final List<Map<String, dynamic>> cachedFriends;
  final List<String> started = [];
  final Completer<Map<String, dynamic>> revealCore = Completer();
  final Completer<RaceDiscoverySummary> discovery = Completer();
  final Completer<Map<String, dynamic>> friends = Completer();
  int coreCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) async => <String, dynamic>{
    'contract': 'home-shell-v1',
    'state': 'EMPTY',
    'resolved': const {'presentation': false, 'friends': true},
    'friends': <String, dynamic>{
      'contract': 'friends-summary-v1',
      'incomingFriendRequests': 0,
      'friends': cachedFriends,
      'pending': const {
        'incoming': <Map<String, dynamic>>[],
        'outgoing': <Map<String, dynamic>>[],
      },
    },
  };

  @override
  Future<Map<String, dynamic>> fetchRaces({required String identityToken}) {
    coreCalls++;
    if (coreCalls == 1) return Future.value(cachedRaces);
    started.add('core');
    return revealCore.future;
  }

  @override
  Future<RaceDiscoverySummary> fetchRaceDiscoverySummary({
    required String identityToken,
  }) {
    started.add('discovery');
    return discovery.future;
  }

  @override
  Future<Map<String, dynamic>> fetchFriends({required String identityToken}) {
    started.add('friends');
    return friends.future;
  }
}

class _SyncRefreshApi extends _FakeBackendApiService {
  int fullCalls = 0;
  int narrowCalls = 0;
  int syncCalls = 0;
  int statusCalls = 0;
  int racesCalls = 0;
  int meCalls = 0;
  final Completer<RaceResolutionStatus> completion = Completer();
  final Completer<Map<String, dynamic>> narrow = Completer();
  bool resolved = true;
  int friendsCalls = 0;
  int catalogCalls = 0;
  final List<Future<Map<String, dynamic>>> fullScripts = [];
  final List<Future<Map<String, dynamic>>> narrowScripts = [];
  final List<Future<Map<String, dynamic>>> catalogScripts = [];
  final List<Future<Map<String, dynamic>>> friendScripts = [];
  final Completer<Map<String, dynamic>?> recap = Completer();
  bool deferRecap = false;

  Map<String, dynamic> get fullPayload => {
    'contract': 'home-shell-v1',
    'state': 'EMPTY',
    'data': <String, dynamic>{},
    'resolved': {'presentation': resolved, 'friends': resolved},
    'presentation': {
      'coins': 10,
      'equipped': <String, dynamic>{},
      'cape': null,
    },
    'friends': {
      'friends': [
        {'id': 'friend', 'displayName': 'Fresh Friend', 'steps': 42},
      ],
      'incomingFriendRequests': 0,
      'pending': {'incoming': [], 'outgoing': []},
    },
    'homeServiceBanner': {'message': 'Old service banner'},
  };

  @override
  Future<StepSyncV2Result> recordStepSyncV2({
    required String identityToken,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
    bool homePull = false,
  }) async {
    syncCalls++;
    return StepSyncV2Result(
      kind: StepSyncV2Kind.current,
      jobId: 'job',
      generation: 1,
    );
  }

  @override
  Future<Map<String, dynamic>?> fetchEventRecap({
    required String identityToken,
  }) async => deferRecap ? recap.future : null;

  @override
  Future<RaceResolutionStatus> fetchRaceResolutionStatus({
    required String identityToken,
    required String jobId,
    required int generation,
  }) {
    statusCalls++;
    return completion.future;
  }

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) async {
    fullCalls++;
    if (fullScripts.isNotEmpty) return fullScripts.removeAt(0);
    return fullPayload;
  }

  @override
  Future<HomeSyncRefreshResult> fetchHomeSyncRefresh({
    required String identityToken,
  }) {
    narrowCalls++;
    return (narrowScripts.isNotEmpty
            ? narrowScripts.removeAt(0)
            : narrow.future)
        .then(HomeSyncRefreshResult.parse);
  }

  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    friendsCalls++;
    if (friendScripts.isNotEmpty) return friendScripts.removeAt(0);
    return {
      'friends': <Map<String, dynamic>>[],
      'pending': {'incoming': [], 'outgoing': []},
    };
  }

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) {
    catalogCalls++;
    if (catalogScripts.isNotEmpty) return catalogScripts.removeAt(0);
    return super.fetchShopCatalog(identityToken: identityToken);
  }

  @override
  Future<Map<String, dynamic>> fetchRaces({required String identityToken}) {
    racesCalls++;
    return super.fetchRaces(identityToken: identityToken);
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    meCalls++;
    return {...await super.fetchMe(identityToken: identityToken), 'coins': 77};
  }
}

Future<void> _mountSyncRefresh(
  WidgetTester tester,
  _SyncRefreshApi api, {
  HealthService? healthService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MainShell(
        authService: await _authService(),
        healthService: healthService ?? _FakeHealthService(),
        backendApiService: api,
        backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump();
}

Map<String, dynamic> _globalEventSummary({
  String id = 'summary-1',
  int extraRaceSteps = 125,
  int raceCount = 1,
  Object? expiresAt = '2099-08-27T04:00:00.000Z',
  Object? validForMs = 10000,
}) => {
  'id': id,
  'eventId': 'event-1',
  'extraRaceSteps': extraRaceSteps,
  'raceCount': raceCount,
  'settledAt': '2026-08-26T20:30:05.000Z',
  'expiresAt': expiresAt,
  'validForMs': validForMs,
};

class _AccountSwitchRaceCardApi extends _FakeBackendApiService {
  final Completer<Map<String, dynamic>> oldAccount = Completer();
  final Completer<Map<String, dynamic>> newAccount = Completer();
  final List<String> tokens = [];

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) {
    tokens.add(identityToken);
    return identityToken == 'new-user-token'
        ? newAccount.future
        : oldAccount.future;
  }
}

class _SupportUnreadApi extends _FakeBackendApiService {
  int inboxFetches = 0;

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) async => const {'state': 'EMPTY', 'inboxUnreadCount': 2};

  @override
  Future<Map<String, dynamic>> fetchInboxAlerts({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async {
    inboxFetches++;
    return {
      'alerts': <Map<String, dynamic>>[],
      'nextCursor': null,
      'unreadCount': inboxFetches == 1 ? 5 : 2,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchFeedbackThreads({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => const {
    'threads': <Map<String, dynamic>>[
      {'id': 'thread-1', 'preview': 'A staff reply'},
    ],
    'nextCursor': null,
  };

  @override
  Future<Map<String, dynamic>> fetchFeedbackThread({
    required String identityToken,
    required String threadId,
    String? before,
    int limit = 25,
  }) async => const {'messages': <Map<String, dynamic>>[], 'nextBefore': null};
}

class _FakeRacePayoutDoubleAdController
    implements RacePayoutDoubleAdController {
  @override
  bool get isReady => false;

  @override
  bool get isSupported => true;

  @override
  Future<void> loadForRacePayoutDouble({
    required String userId,
    required String offerId,
  }) async {}

  @override
  Future<bool> showAndAwaitReward() async => false;

  @override
  void dispose() {}
}

class _ReadyRacePayoutDoubleAdController
    implements RacePayoutDoubleAdController {
  _ReadyRacePayoutDoubleAdController({this.onShow});
  final VoidCallback? onShow;
  bool ready = true;
  int shows = 0;

  @override
  bool get isReady => ready;
  @override
  bool get isSupported => true;
  @override
  Future<void> loadForRacePayoutDouble({
    required String userId,
    required String offerId,
  }) async => ready = true;
  @override
  Future<bool> showAndAwaitReward() async {
    shows++;
    onShow?.call();
    ready = false;
    return true;
  }

  @override
  void dispose() {}
}

class _RewardedResultsApi extends _FakeBackendApiService {
  _RewardedResultsApi({required super.racesData});
  int claimAttempts = 0;
  bool adEarned = false;

  @override
  Future<RacePayoutDoubleClaimResult> claimRacePayoutDouble({
    required String identityToken,
    required String offerId,
    required List<String> popupRaceIds,
  }) async {
    claimAttempts++;
    if (!adEarned) {
      throw const ApiException('not verified', code: 'AD_NOT_VERIFIED');
    }
    return RacePayoutDoubleClaimResult.tryParse(const {
      'awarded': true,
      'alreadyClaimed': false,
      'raceIds': ['race-rewarded'],
      'baseCoins': 100,
      'bonusCoins': 100,
      'coins': 300,
    }, popupRaceIds: popupRaceIds)!;
  }
}

class _RewardedCoinsApi extends _FakeBackendApiService {
  String? claimedToken;
  @override
  Future<Map<String, dynamic>> fetchGetCoinsStatus({
    required String identityToken,
    required String localDate,
  }) async => {
    'adCoinReward': {
      'available': true,
      'remainingToday': 5,
      'coinRewardMin': 25,
      'coinRewardMax': 50,
    },
  };
  @override
  Future<Map<String, dynamic>> claimAdCoinReward({
    required String identityToken,
    required String localDate,
  }) async {
    claimedToken = identityToken;
    return {'coins': 123, 'coinAmount': 25, 'remainingToday': 4};
  }
}

class _FakeGetCoinsAdController implements ExtraSpinAdController {
  bool ready = false;
  int loadCalls = 0;
  int showCalls = 0;
  int disposeCalls = 0;
  String? loadedUserId;
  String? loadedCustomData;

  @override
  bool get isReady => ready;

  @override
  bool get isSupported => true;

  @override
  Future<void> load({required String userId, required String localDate}) async {
    loadCalls++;
    loadedUserId = userId;
    loadedCustomData = localDate;
    ready = true;
  }

  @override
  Future<bool> showAndAwaitReward() async {
    showCalls++;
    ready = false;
    return true;
  }

  @override
  void dispose() => disposeCalls++;
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_first_race_onboarding_seen': true,
    'auth_tutorial_onboarding_seen': true,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

class _RecordingInterstitialCoordinator
    implements InterstitialPresentationCoordinator {
  _RecordingInterstitialCoordinator({
    this.primeThrows = false,
    this.warmCompleter,
    this.primeCompleter,
  });
  final bool primeThrows;
  final Completer<void>? warmCompleter;
  final Completer<void>? primeCompleter;
  @override
  String get ownerUserId => 'user-1';
  @override
  String get sessionId => '4b7c1f1e-4a5f-4bc1-a9b8-6bd986112a61';
  final List<InterstitialPlacement> primes = [];
  final List<InterstitialPlacement> warms = [];
  final List<InterstitialPlacement> presentations = [];
  final List<InterstitialPlacement> cancellations = [];
  final List<bool> rewardedArguments = [];

  @override
  Future<void> warm(InterstitialPlacement placement) async {
    warms.add(placement);
    final pending = warmCompleter;
    if (pending != null) await pending.future;
  }

  @override
  Future<void> prime(InterstitialPlacement placement) async {
    primes.add(placement);
    if (primeThrows) throw StateError('prime failed');
    final pending = primeCompleter;
    if (pending != null) await pending.future;
  }

  @override
  bool presentIfReady(
    InterstitialPlacement placement, {
    bool excludedFlow = false,
    bool rewardedPresented = false,
  }) {
    rewardedArguments.add(rewardedPresented);
    if (!rewardedPresented && !excludedFlow) presentations.add(placement);
    return !rewardedPresented && !excludedFlow;
  }

  @override
  Future<void> cancel(InterstitialPlacement placement) async =>
      cancellations.add(placement);
  @override
  Future<void> flushPendingImpressions() async {}
  @override
  void didEnterBackground() {}
  @override
  void didResume() {}
  @override
  void dispose() {}
}

void main() {
  testWidgets(
    'simple recap syncs then reads exact event window and saves once',
    (tester) async {
      final api = _RecapApi()..candidate = _recapCandidate();
      final window = api.candidate!['event'] as Map;
      final health = _RecapHealth(api.events);
      await _mountRecap(tester, api, health);
      expect(api.events, ['sync', 'get', 'health-window', 'post']);
      expect(health.start, DateTime.parse(window['startsAt']));
      expect(health.end, DateTime.parse(window['endsAt']));
      expect(api.postedRaw, 1000);
      expect(api.postedEventId, 'event-1');
      expect(api.postedRevision, 3);
      expect(find.text('2× STEPS COMPLETE'), findsOneWidget);
      expect(find.text('+3,000 steps'), findsOneWidget);
      expect(find.text('extra steps gained across all races'), findsOneWidget);
      await tester.tap(find.text('CONTINUE'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.globalSummaryAckCalls, 1);
      await tester.pump(const Duration(seconds: 20));
      expect(api.gets, 1);
      expect(api.posts, 1);
    },
  );

  for (final kind in [
    StepSyncV2Kind.failed,
    StepSyncV2Kind.ambiguousFailure,
    StepSyncV2Kind.persistedStatusUnknown,
    StepSyncV2Kind.cooldown,
  ]) {
    testWidgets('simple recap defers after $kind sync', (tester) async {
      final api = _RecapApi()
        ..candidate = _recapCandidate()
        ..syncKind = kind;
      await _mountRecap(tester, api, _RecapHealth(api.events));
      expect(api.gets, 0);
      expect(api.posts, 0);
      expect(find.text('2× STEPS COMPLETE'), findsNothing);
    });
  }

  for (final raw in <int?>[null, 0]) {
    testWidgets('simple recap distinguishes raw $raw from failure', (
      tester,
    ) async {
      final api = _RecapApi()..candidate = _recapCandidate();
      await _mountRecap(tester, api, _RecapHealth(api.events, rawSteps: raw));
      expect(api.gets, 1);
      expect(api.posts, raw == null ? 0 : 1);
      expect(find.text('2× STEPS COMPLETE'), findsNothing);
    });
  }

  testWidgets('simple recap discards health response after sign-out', (
    tester,
  ) async {
    final api = _RecapApi()..candidate = _recapCandidate();
    final health = _RecapHealth(api.events)..pending = Completer<int?>();
    final auth = await _mountRecap(tester, api, health);
    expect(api.gets, 1);
    await auth.signOut();
    health.pending!.complete(1000);
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.posts, 0);
    expect(find.text('2× STEPS COMPLETE'), findsNothing);
  });

  for (final response in <Map<String, dynamic>?>[
    null,
    {},
    {'state': 'none'},
    {'state': 'unknown'},
    {'state': 'pending'},
    {
      'state': 'pending',
      'event': {'id': 'event-1'},
    },
    {'state': 'ready', 'globalEventSummary': null},
  ]) {
    testWidgets('simple recap malformed or unavailable $response defers', (
      tester,
    ) async {
      final api = _RecapApi()..candidate = response;
      await _mountRecap(tester, api, _RecapHealth(api.events));
      expect(api.events, ['sync', 'get']);
      expect(api.posts, 0);
      expect(find.byType(HomeTab), findsOneWidget);
      expect(find.text('2× STEPS COMPLETE'), findsNothing);
    });
  }

  testWidgets('simple recap never reads an expired previous-day candidate', (
    tester,
  ) async {
    final candidate = _recapCandidate();
    final event = candidate['event'] as Map;
    final yesterday = DateTime.now().toUtc().subtract(const Duration(days: 1));
    event['startsAt'] = yesterday
        .subtract(const Duration(hours: 1))
        .toIso8601String();
    event['endsAt'] = yesterday
        .subtract(const Duration(minutes: 30))
        .toIso8601String();
    event['expiresAt'] = yesterday.toIso8601String();
    final api = _RecapApi()..candidate = candidate;
    await _mountRecap(tester, api, _RecapHealth(api.events));
    expect(api.events, ['sync', 'get']);
    expect(find.text('2× STEPS COMPLETE'), findsNothing);
  });

  testWidgets('simple recap coalesces refresh while window read is pending', (
    tester,
  ) async {
    final api = _RecapApi()..candidate = _recapCandidate();
    final health = _RecapHealth(api.events)..pending = Completer<int?>();
    await _mountRecap(tester, api, health);
    final refresh = tester.widget<HomeTab>(find.byType(HomeTab)).onRefresh();
    await tester.pump();
    await refresh;
    expect(api.gets, 1);
    expect(api.events.where((e) => e == 'health-window').length, 1);
    health.pending!.complete(1000);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(api.posts, 1);
    expect(find.text('2× STEPS COMPLETE'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(milliseconds: 400));
  });

  for (final retry in ['refresh', 'resume']) {
    testWidgets('simple recap retries missing input only on a later $retry', (
      tester,
    ) async {
      final api = _RecapApi()..candidate = _recapCandidate();
      final health = _RecapHealth(api.events, rawSteps: null);
      await _mountRecap(tester, api, health);
      await tester.pump(const Duration(seconds: 20));
      expect(api.gets, 1);
      health.rawSteps = 1000;
      if (retry == 'refresh') {
        await tester.widget<HomeTab>(find.byType(HomeTab)).onRefresh();
      } else {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(api.gets, 2);
      expect(api.posts, 1);
      expect(find.text('2× STEPS COMPLETE'), findsOneWidget);
      await tester.tap(find.text('CONTINUE'));
      await tester.pump(const Duration(milliseconds: 400));
    });
  }

  for (final boundary in ['sync', 'get', 'health', 'post']) {
    for (final interruption in [
      'sign-out',
      'account switch',
      'dispose',
      'background',
    ]) {
      testWidgets('simple recap discards $boundary after $interruption', (
        tester,
      ) async {
        final api = _RecapApi()..candidate = _recapCandidate();
        if (boundary == 'sync') api.pendingSync = Completer<StepSyncV2Result>();
        if (boundary == 'get') {
          api.pendingGet = Completer<Map<String, dynamic>?>();
        }
        if (boundary == 'post') {
          api.pendingPost = Completer<Map<String, dynamic>?>();
        }
        final health = _RecapHealth(api.events);
        if (boundary == 'health') health.pending = Completer<int?>();
        final auth = await _mountRecap(tester, api, health);
        if (interruption == 'sign-out') await auth.signOut();
        if (interruption == 'account switch') {
          await auth.updateSessionToken('other-account-token');
          await auth.syncFromBackendUser({
            'id': 'other-account',
          }, authoritative: true);
        }
        if (interruption == 'dispose') {
          await tester.pumpWidget(const SizedBox());
        }
        if (interruption == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        }
        if (boundary == 'sync') {
          api.pendingSync!.complete(
            const StepSyncV2Result(kind: StepSyncV2Kind.current),
          );
        }
        if (boundary == 'get') api.pendingGet!.complete(_recapCandidate());
        if (boundary == 'health') health.pending!.complete(1000);
        if (boundary == 'post') {
          api.pendingPost!.complete({
            'state': 'ready',
            'globalEventSummary': _globalEventSummary(),
          });
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(api.posts, boundary == 'post' ? 1 : 0);
        expect(find.text('2× STEPS COMPLETE'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
    }
  }

  testWidgets('simple recap background five-minute sync does not recalculate', (
    tester,
  ) async {
    final api = _RecapApi()..candidate = _recapCandidate();
    await _mountRecap(tester, api, _RecapHealth(api.events, rawSteps: null));
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();
    expect(api.events.where((e) => e == 'sync').length, 2);
    expect(api.gets, 1);
    expect(api.posts, 0);
  });

  testWidgets(
    'simple recap precedes Home invitations without blocking Home rendering',
    (tester) async {
      final api = _RecapApi(
        homeInvitePreflight: {
          'resolved': true,
          'invites': [
            {
              'kind': 'RACE',
              'id': 'invite-1',
              'name': 'After Recap',
              'status': 'PENDING',
            },
          ],
        },
      )..candidate = _recapCandidate();
      final health = _RecapHealth(api.events)..pending = Completer<int?>();
      await _mountRecap(tester, api, health);
      expect(find.byType(HomeTab), findsOneWidget);
      expect(api.homeInvitePreflightCalls, 0);
      expect(find.text('After Recap'), findsNothing);
      health.pending!.complete(1000);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('2× STEPS COMPLETE'), findsOneWidget);
      expect(find.text('After Recap'), findsNothing);
      await tester.tap(find.text('CONTINUE'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(api.homeInvitePreflightCalls, 1);
      expect(find.text('After Recap'), findsOneWidget);
    },
  );
  for (final failed in [false, true]) {
    testWidgets(
      'simple recap requires complete legacy sync when samples fail=$failed',
      (tester) async {
        final api = _RecapApi()
          ..candidate = _recapCandidate()
          ..syncKind = StepSyncV2Kind.unsupported
          ..failSamples = failed;
        final health = _RecapHealth(api.events)
          ..samples = [
            StepSampleData(
              periodStart: DateTime.utc(2026, 9, 11, 10),
              periodEnd: DateTime.utc(2026, 9, 11, 11),
              steps: 200,
            ),
          ];
        await _mountRecap(tester, api, health);
        expect(api.events.take(3), ['sync', 'legacy-total', 'legacy-samples']);
        expect(api.gets, failed ? 0 : 1);
        expect(api.posts, failed ? 0 : 1);
        if (failed) {
          expect(find.byType(HomeTab), findsOneWidget);
          expect(find.text('2× STEPS COMPLETE'), findsNothing);
        } else {
          expect(find.text('2× STEPS COMPLETE'), findsOneWidget);
          await tester.tap(find.text('CONTINUE'));
          await tester.pump(const Duration(milliseconds: 400));
        }
      },
    );
  }

  testWidgets('simple recap coalesces cold-open and immediate resume sync', (
    tester,
  ) async {
    final api = _RecapApi()
      ..candidate = _recapCandidate()
      ..pendingSync = Completer<StepSyncV2Result>();
    await _mountRecap(tester, api, _RecapHealth(api.events));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(api.events, ['sync']);
    api.pendingSync!.complete(
      const StepSyncV2Result(kind: StepSyncV2Kind.current),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(api.events, ['sync', 'get', 'health-window', 'post']);
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('simple recap gets its chance before the version changelog', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.8',
      buildNumber: '1',
      buildSignature: '',
    );
    final api = _RecapApi()..candidate = _recapCandidate();
    final health = _RecapHealth(api.events)..pending = Completer<int?>();
    await _mountRecap(tester, api, health);
    expect(find.byType(HomeTab), findsOneWidget);
    expect(find.byKey(const Key('whats-new-sheet')), findsNothing);
    health.pending!.complete(1000);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('2× STEPS COMPLETE'), findsOneWidget);
    expect(find.byKey(const Key('whats-new-sheet')), findsNothing);
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
    'simple recap finishing in background cannot open the next invite',
    (tester) async {
      final api = _RecapApi(
        homeInvitePreflight: {
          'resolved': true,
          'invites': [
            {
              'kind': 'RACE',
              'id': 'invite-1',
              'name': 'After Recap',
              'status': 'PENDING',
            },
          ],
        },
      )..candidate = _recapCandidate();
      final health = _RecapHealth(api.events)..pending = Completer<int?>();
      await _mountRecap(tester, api, health);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      health.pending!.complete(1000);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(api.posts, 0);
      expect(api.homeInvitePreflightCalls, 0);
      expect(find.text('After Recap'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('successful resolution retains fresh shell and replaces core', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    await _mountSyncRefresh(tester, api);
    expect(api.fullCalls, 1);
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump();
    expect(api.narrowCalls, 1);
    expect(api.fullCalls, 1);
    api.narrow.complete({
      'contract': 'home-sync-refresh-v1',
      'home': {
        'state': 'EMPTY',
        'data': <String, dynamic>{},
        'inboxUnreadCount': 3,
      },
      'retainedSections': ['presentation', 'friends'],
    });
    await tester.pump();
    final home = tester.widget<HomeTab>(find.byType(HomeTab));
    expect(home.raceCard?['inboxUnreadCount'], 3);
    expect(home.raceCard?.containsKey('homeServiceBanner'), false);
    expect(home.friendsSteps.single['displayName'], 'Fresh Friend');
    expect(home.authService.coins, 77);
    expect(api.racesCalls, 2);
    expect(api.meCalls, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unresolved shell uses full catch-up after successful resolution',
    (tester) async {
      final api = _SyncRefreshApi()..resolved = false;
      await _mountSyncRefresh(tester, api);
      api.completion.complete(
        const RaceResolutionStatus(RaceResolutionState.succeeded),
      );
      await tester.pump();
      expect(api.fullCalls, 2);
      expect(api.narrowCalls, 0);
      expect(find.byType(HomeTab), findsOneWidget);
    },
  );

  for (final invalid in <Map<String, dynamic>>[
    {'state': 'EMPTY', 'data': {}},
    {
      'contract': 'home-sync-refresh-v1',
      'home': {},
      'retainedSections': ['presentation', 'friends'],
    },
    {
      'contract': 'home-sync-refresh-v1',
      'home': {
        'state': 'ACTIVE_RACES',
        'data': {
          'races': [null],
        },
      },
      'retainedSections': ['presentation', 'friends'],
    },
  ]) {
    testWidgets('invalid narrow ${invalid.toString()} falls back once', (
      tester,
    ) async {
      final api = _SyncRefreshApi();
      await _mountSyncRefresh(tester, api);
      api.completion.complete(
        const RaceResolutionStatus(RaceResolutionState.succeeded),
      );
      await tester.pump();
      api.narrow.complete(invalid);
      await tester.pump();
      await tester.pump();
      expect(api.narrowCalls, 1);
      expect(api.fullCalls, 2);
      expect(
        tester.widget<HomeTab>(find.byType(HomeTab)).raceCard?['state'],
        'EMPTY',
      );
    });
  }

  testWidgets('transient narrow failure keeps coherent Home without fallback', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    await _mountSyncRefresh(tester, api);
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump();
    api.narrow.completeError(const SocketException('unavailable'));
    await tester.pump();
    expect(api.fullCalls, 1);
    expect(api.narrowCalls, 1);
    final home = tester.widget<HomeTab>(find.byType(HomeTab));
    expect(home.raceCard?.containsKey('homeServiceBanner'), true);
    expect(home.friendsSteps.single['displayName'], 'Fresh Friend');
    expect(home.raceCardLoading, false);
  });

  testWidgets('equipment invalidation during narrow forces one full refresh', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    await _mountSyncRefresh(tester, api);
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump();
    final home = tester.widget<HomeTab>(find.byType(HomeTab));
    home.onShopChanged?.call({'coins': 88, 'equipped': {}, 'items': []});
    api.narrow.complete({
      'contract': 'home-sync-refresh-v1',
      'home': {'state': 'EMPTY', 'data': {}, 'inboxUnreadCount': 99},
      'retainedSections': ['presentation', 'friends'],
    });
    await tester.pump();
    await tester.pump();
    expect(api.fullCalls, 2);
    expect(api.narrowCalls, 1);
    expect(
      tester
          .widget<HomeTab>(find.byType(HomeTab))
          .raceCard?['inboxUnreadCount'],
      isNull,
    );
  });

  testWidgets('expired retained shell uses full resolution refresh', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    await _mountSyncRefresh(tester, api);
    await tester.pump(const Duration(seconds: 61));
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump();
    expect(api.fullCalls, 2);
    expect(api.narrowCalls, 0);
  });

  testWidgets(
    'friend repository invalidation during narrow rejects retention',
    (tester) async {
      final api = _SyncRefreshApi();
      await _mountSyncRefresh(tester, api);
      api.completion.complete(
        const RaceResolutionStatus(RaceResolutionState.succeeded),
      );
      await tester.pump();
      final children =
          tester.widget<PageView>(find.byType(PageView)).childrenDelegate
              as SliverChildListDelegate;
      final friends = children.children.whereType<FriendsTab>().single;
      friends.friendsRepository!.invalidate();
      api.narrow.complete({
        'contract': 'home-sync-refresh-v1',
        'home': {'state': 'EMPTY', 'data': {}, 'inboxUnreadCount': 99},
        'retainedSections': ['presentation', 'friends'],
      });
      await tester.pump();
      expect(api.fullCalls, 2);
      expect(api.narrowCalls, 1);
      expect(
        tester
            .widget<HomeTab>(find.byType(HomeTab))
            .raceCard?['inboxUnreadCount'],
        isNull,
      );
    },
  );

  testWidgets('failed legacy fallback keeps previous coherent shell', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    await _mountSyncRefresh(tester, api);
    final failure = Completer<Map<String, dynamic>>();
    api.fullScripts.add(failure.future);
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump();
    api.narrow.complete({'state': 'EMPTY'});
    await tester.pump();
    failure.completeError(const SocketException('offline'));
    await tester.pump();
    expect(api.fullCalls, 2);
    expect(api.narrowCalls, 1);
    final home = tester.widget<HomeTab>(find.byType(HomeTab));
    expect(home.raceCard?.containsKey('homeServiceBanner'), true);
    expect(home.raceCardLoading, false);
  });

  testWidgets('new completion during narrow schedules one newer catch-up', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    await _mountSyncRefresh(tester, api);
    final later = Completer<Map<String, dynamic>>();
    api.narrowScripts.addAll([api.narrow.future, later.future]);
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump();
    final refresh = tester.widget<HomeTab>(find.byType(HomeTab)).onRefresh();
    await tester.pump();
    await refresh;
    await tester.pump(const Duration(milliseconds: 800));
    expect(api.fullCalls, 2, reason: 'Deliberate pull stays on full path.');
    expect(api.narrowCalls, 1, reason: 'The old catch-up remains in flight.');
    api.narrow.complete({
      'contract': 'home-sync-refresh-v1',
      'home': {'state': 'EMPTY', 'data': {}, 'inboxUnreadCount': 9},
      'retainedSections': ['presentation', 'friends'],
    });
    await tester.pump();
    expect(api.narrowCalls, 2);
    expect(
      tester
          .widget<HomeTab>(find.byType(HomeTab))
          .raceCard?['inboxUnreadCount'],
      isNull,
    );
    later.complete({
      'contract': 'home-sync-refresh-v1',
      'home': {'state': 'EMPTY', 'data': {}, 'inboxUnreadCount': 5},
      'retainedSections': ['presentation', 'friends'],
    });
    await tester.pump();
    expect(
      tester
          .widget<HomeTab>(find.byType(HomeTab))
          .raceCard?['inboxUnreadCount'],
      5,
    );
    expect(api.friendsCalls, 0);
    expect(api.catalogCalls, 0);
  });

  testWidgets('direct saved recap survives a newer narrow Home core', (
    tester,
  ) async {
    final api = _SyncRefreshApi()..deferRecap = true;
    await _mountSyncRefresh(tester, api);
    expect(api.fullCalls, 1);
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump();
    api.narrow.complete({
      'contract': 'home-sync-refresh-v1',
      'home': {'state': 'EMPTY', 'data': {}, 'inboxUnreadCount': 5},
      'retainedSections': ['presentation', 'friends'],
    });
    await tester.pump();
    api.recap.complete({
      'state': 'ready',
      'globalEventSummary': _globalEventSummary(),
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      tester
          .widget<HomeTab>(find.byType(HomeTab))
          .raceCard?['inboxUnreadCount'],
      5,
    );
    expect(find.text('2× STEPS COMPLETE'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets(
    'malformed optional reward sections degrade without crashing Home',
    (tester) async {
      final api = _SyncRefreshApi();
      await _mountSyncRefresh(tester, api);
      api.completion.complete(
        const RaceResolutionStatus(RaceResolutionState.succeeded),
      );
      await tester.pump();
      api.narrow.complete({
        'contract': 'home-sync-refresh-v1',
        'home': {
          'state': 'EMPTY',
          'data': {},
          'dailyReward': 'bad',
          'stepMilestones': [],
        },
        'retainedSections': ['presentation', 'friends'],
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeTab), findsOneWidget);
    },
  );

  testWidgets(
    'account change discards in-flight narrow core and retained friends',
    (tester) async {
      final api = _SyncRefreshApi();
      await _mountSyncRefresh(tester, api);
      api.completion.complete(
        const RaceResolutionStatus(RaceResolutionState.succeeded),
      );
      await tester.pump();
      final auth = tester.widget<HomeTab>(find.byType(HomeTab)).authService;
      final newHome = {
        ...api.fullPayload,
        'inboxUnreadCount': 2,
        'friends': {
          'friends': <Map<String, dynamic>>[],
          'pending': {'incoming': [], 'outgoing': []},
        },
      };
      api.fullScripts.add(Future.value(newHome));
      await auth.syncFromBackendUser(const {'id': 'user-2'});
      await tester.pump();
      api.narrow.complete({
        'contract': 'home-sync-refresh-v1',
        'home': {'state': 'EMPTY', 'data': {}, 'inboxUnreadCount': 99},
        'retainedSections': ['presentation', 'friends'],
      });
      await tester.pump();
      final home = tester.widget<HomeTab>(find.byType(HomeTab));
      expect(home.raceCard?['inboxUnreadCount'], 2);
      expect(home.friendsSteps, isEmpty);
      expect(home.authService.userId, 'user-2');
    },
  );

  testWidgets('new full response wins over an older narrow response', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    await _mountSyncRefresh(tester, api);
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump();
    api.fullScripts.add(
      Future.value({...api.fullPayload, 'inboxUnreadCount': 2}),
    );
    unawaited(tester.widget<HomeTab>(find.byType(HomeTab)).onRefresh());
    await tester.pump();
    api.narrow.complete({
      'contract': 'home-sync-refresh-v1',
      'home': {'state': 'EMPTY', 'data': {}, 'inboxUnreadCount': 99},
      'retainedSections': ['presentation', 'friends'],
    });
    await tester.pump();
    expect(
      tester
          .widget<HomeTab>(find.byType(HomeTab))
          .raceCard?['inboxUnreadCount'],
      2,
    );
    expect(api.fullCalls, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('retaining a narrow result never renews the shell age', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    await _mountSyncRefresh(tester, api);
    // Refresh the shell one minute before the existing five-minute foreground
    // sync. Its resolution arrives late, leaving only twenty seconds of age.
    await tester.pump(const Duration(seconds: 239));
    final refresh = tester.widget<HomeTab>(find.byType(HomeTab)).onRefresh();
    await tester.pump();
    await refresh;
    await tester.pump(const Duration(seconds: 40));
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump();
    api.narrow.complete({
      'contract': 'home-sync-refresh-v1',
      'home': {'state': 'EMPTY', 'data': {}},
      'retainedSections': ['presentation', 'friends'],
    });
    await tester.pump();
    expect(api.narrowCalls, 1);
    await tester.pump(const Duration(seconds: 21));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(api.syncCalls, 3);
    expect(api.statusCalls, 3);
    expect(api.fullCalls, 3);
    expect(api.narrowCalls, 1);
  });

  for (final android in [false, true]) {
    testWidgets(
      'post-resolution retained Home works on ${android ? 'Android' : 'iOS'}',
      (tester) async {
        final api = _SyncRefreshApi();
        await _mountSyncRefresh(
          tester,
          api,
          healthService: android
              ? (_AndroidPermissionHealth()..permission = true)
              : _FakeHealthService(),
        );
        api.completion.complete(
          const RaceResolutionStatus(RaceResolutionState.succeeded),
        );
        await tester.pump();
        api.narrow.complete({
          'contract': 'home-sync-refresh-v1',
          'home': {'state': 'EMPTY', 'data': {}, 'inboxUnreadCount': 3},
          'retainedSections': ['presentation', 'friends'],
        });
        await tester.pump();
        final home = tester.widget<HomeTab>(find.byType(HomeTab));
        expect(home.stepData?.steps, 1234);
        expect(home.raceCard?['inboxUnreadCount'], 3);
        expect(home.authService.coins, 77);
        expect(home.friendsSteps.single['displayName'], 'Fresh Friend');
        expect(api.friendsCalls, 0);
        expect(api.catalogCalls, 0);
        expect(api.narrowCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('mutation during initial full fetch prevents later retention', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    final initial = Completer<Map<String, dynamic>>();
    api.fullScripts.add(initial.future);
    await _mountSyncRefresh(tester, api);
    tester.widget<HomeTab>(find.byType(HomeTab)).onShopChanged?.call({
      'coins': 88,
      'equipped': {},
      'items': [],
    });
    initial.complete(api.fullPayload);
    await tester.pump();
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(api.fullCalls, 2);
    expect(api.narrowCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('acknowledged summary cannot reopen from a stale full receipt', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    await _mountSyncRefresh(tester, api);
    final late = Completer<Map<String, dynamic>>();
    api.fullScripts.add(late.future);
    unawaited(tester.widget<HomeTab>(find.byType(HomeTab)).onRefresh());
    await tester.pump();
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump();
    api.narrow.complete({
      'contract': 'home-sync-refresh-v1',
      'home': {
        'state': 'EMPTY',
        'data': {},
        'globalEventSummary': _globalEventSummary(),
      },
      'retainedSections': ['presentation', 'friends'],
    });
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('2× STEPS COMPLETE'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.globalSummaryAckCalls, 1);
    late.complete({
      ...api.fullPayload,
      'globalEventSummary': _globalEventSummary(),
    });
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('2× STEPS COMPLETE'), findsNothing);
    expect(api.globalSummaryAckCalls, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('pending invite optional malformed data degrades safely', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    await _mountSyncRefresh(tester, api);
    api.completion.complete(
      const RaceResolutionStatus(RaceResolutionState.succeeded),
    );
    await tester.pump();
    api.narrow.complete({
      'contract': 'home-sync-refresh-v1',
      'home': {
        'state': 'PENDING_INVITE',
        'pendingInviteCount': 'bad',
        'data': {
          'raceId': 'invite',
          'inviter': 'bad',
          'participantCount': [],
          'durationHours': 'bad',
        },
      },
      'retainedSections': ['presentation', 'friends'],
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Someone'), findsWidgets);
    expect(api.fullCalls, 1);
  });

  testWidgets(
    'account switch clears retained sections before new full response',
    (tester) async {
      final api = _SyncRefreshApi();
      await _mountSyncRefresh(tester, api);
      final old = tester.widget<HomeTab>(find.byType(HomeTab));
      old.onShopChanged?.call({
        'coins': 10,
        'equipped': {
          'HEAD': {'assetKey': 'wizard_hat'},
        },
        'items': [],
      });
      final next = Completer<Map<String, dynamic>>();
      api.fullScripts.add(next.future);
      await old.authService.syncFromBackendUser(const {'id': 'user-2'});
      await tester.pump();
      final home = tester.widget<HomeTab>(find.byType(HomeTab));
      expect(home.raceCard, isNull);
      expect(home.friendsSteps, isEmpty);
      expect(home.equippedAccessories, isEmpty);
      next.complete(api.fullPayload);
      await tester.pump();
    },
  );

  testWidgets('old catalog load cannot reseed a new account cache', (
    tester,
  ) async {
    final api = _SyncRefreshApi()..resolved = false;
    final oldCatalog = Completer<Map<String, dynamic>>();
    api.catalogScripts.add(oldCatalog.future);
    await _mountSyncRefresh(tester, api);
    expect(api.catalogCalls, 1);
    final auth = tester.widget<HomeTab>(find.byType(HomeTab)).authService;
    await auth.syncFromBackendUser(const {'id': 'user-2'});
    await tester.pump();
    api.catalogScripts.add(
      Future.value({'coins': 22, 'equipped': {}, 'items': []}),
    );
    final refresh = tester.widget<HomeTab>(find.byType(HomeTab)).onRefresh();
    await tester.pump();
    await refresh;
    expect(api.catalogCalls, 2);
    oldCatalog.complete({'coins': 999, 'equipped': {}, 'items': []});
    await tester.pump();
    final home = tester.widget<HomeTab>(find.byType(HomeTab));
    expect(home.shopCatalogState?.data?['coins'], 22);
    expect(home.authService.coins, isNot(999));
    expect(home.authService.userId, 'user-2');
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('old Friends tab response cannot repopulate new account Home', (
    tester,
  ) async {
    final api = _SyncRefreshApi();
    await _mountSyncRefresh(tester, api);
    final auth = tester.widget<HomeTab>(find.byType(HomeTab)).authService;
    final oldFriends = Completer<Map<String, dynamic>>();
    api.friendScripts.add(oldFriends.future);
    final children =
        tester.widget<PageView>(find.byType(PageView)).childrenDelegate
            as SliverChildListDelegate;
    children.children
        .whereType<FriendsTab>()
        .single
        .friendsRepository!
        .invalidate();
    tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).onTap(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.friendsCalls, 1);
    await auth.syncFromBackendUser(const {'id': 'user-2'});
    await tester.pump();
    oldFriends.complete({
      'friends': [
        {'id': 'old-only', 'displayName': 'OLD ACCOUNT ONLY'},
      ],
      'pending': {'incoming': [], 'outgoing': []},
    });
    await tester.pump();
    tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).onTap(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final home = tester.widget<HomeTab>(find.byType(HomeTab));
    expect(
      home.friendsSteps.any((friend) => friend['id'] == 'old-only'),
      false,
    );
    expect(home.authService.userId, 'user-2');
  });

  testWidgets(
    'old account resolution status cannot trigger new account catch-up',
    (tester) async {
      final api = _SyncRefreshApi();
      await _mountSyncRefresh(tester, api);
      final auth = tester.widget<HomeTab>(find.byType(HomeTab)).authService;
      await auth.syncFromBackendUser(const {'id': 'user-2'});
      await tester.pump();
      final calls = api.fullCalls;
      api.completion.complete(
        const RaceResolutionStatus(RaceResolutionState.succeeded),
      );
      await tester.pump();
      expect(api.narrowCalls, 0);
      expect(api.fullCalls, calls);
    },
  );

  for (final duringNarrow in [false, true]) {
    testWidgets(
      'standalone friends replacing full shell ${duringNarrow ? 'during narrow' : 'before completion'} requires full catch-up',
      (tester) async {
        final api = _SyncRefreshApi();
        await _mountSyncRefresh(tester, api);
        final refreshHome = tester
            .widget<HomeTab>(find.byType(HomeTab))
            .onRefresh;
        final independent = Completer<Map<String, dynamic>>();
        api.friendScripts.add(independent.future);
        final children =
            tester.widget<PageView>(find.byType(PageView)).childrenDelegate
                as SliverChildListDelegate;
        children.children
            .whereType<FriendsTab>()
            .single
            .friendsRepository!
            .invalidate();
        tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).onTap(2);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(api.friendsCalls, 1);
        unawaited(refreshHome());
        await tester.pump();
        expect(api.fullCalls, 2);
        tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).onTap(0);
        await tester.pump();
        // The replacement trigger is a real sync and therefore creates an
        // ordinary 750 ms race poll; let it reach its pending status read.
        await tester.pump(const Duration(milliseconds: 800));
        if (duringNarrow) {
          api.completion.complete(
            const RaceResolutionStatus(RaceResolutionState.succeeded),
          );
          await tester.pump();
          expect(api.narrowCalls, 1);
        }
        independent.complete({
          'friends': [
            {'id': 'independent', 'displayName': 'Independent Friend'},
          ],
          'pending': {'incoming': [], 'outgoing': []},
        });
        await tester.pump();
        expect(
          tester
              .widget<HomeTab>(find.byType(HomeTab))
              .friendsSteps
              .single['id'],
          'independent',
        );
        if (duringNarrow) {
          api.narrow.complete({
            'contract': 'home-sync-refresh-v1',
            'home': {'state': 'EMPTY', 'data': {}},
            'retainedSections': ['presentation', 'friends'],
          });
        } else {
          api.completion.complete(
            const RaceResolutionStatus(RaceResolutionState.succeeded),
          );
        }
        await tester.pump();
        expect(api.fullCalls, 3);
        expect(api.narrowCalls, duringNarrow ? 1 : 0);
        expect(
          tester
              .widget<HomeTab>(find.byType(HomeTab))
              .friendsSteps
              .single['id'],
          'friend',
        );
      },
    );
  }

  testWidgets(
    'standalone catalog replacing full presentation requires full catch-up',
    (tester) async {
      final api = _SyncRefreshApi()..resolved = false;
      final catalog = Completer<Map<String, dynamic>>();
      api.catalogScripts.add(catalog.future);
      await _mountSyncRefresh(tester, api);
      expect(api.catalogCalls, 1);
      api.resolved = true;
      unawaited(tester.widget<HomeTab>(find.byType(HomeTab)).onRefresh());
      await tester.pump();
      expect(api.fullCalls, 2);
      catalog.complete({'coins': 123, 'equipped': {}, 'items': []});
      await tester.pump();
      expect(
        tester
            .widget<HomeTab>(find.byType(HomeTab))
            .shopCatalogState
            ?.data?['coins'],
        123,
      );
      api.completion.complete(
        const RaceResolutionStatus(RaceResolutionState.succeeded),
      );
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(api.fullCalls, 3);
      expect(api.narrowCalls, 0);
    },
  );

  testWidgets(
    'authenticated foreground shell warms Race Detail after consent',
    (WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      AdService.setConsentPermission(true);
      addTearDown(() => AdService.setConsentPermission(false));
      final authService = await _authService();
      final coordinator = _RecordingInterstitialCoordinator();

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: _FakeBackendApiService(),
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
            interstitialCoordinator: coordinator,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(coordinator.warms, contains(InterstitialPlacement.raceDetailExit));
      expect(coordinator.primes, isEmpty);
    },
  );

  testWidgets(
    'consent allowed while backgrounded waits for foreground resume',
    (WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      AdService.setConsentPermission(false);
      addTearDown(() => AdService.setConsentPermission(false));
      final authService = await _authService();
      final coordinator = _RecordingInterstitialCoordinator();

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: _FakeBackendApiService(),
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
            interstitialCoordinator: coordinator,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(coordinator.warms, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      AdService.setConsentPermission(true);
      await tester.pump();
      expect(coordinator.warms, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(coordinator.warms, [InterstitialPlacement.raceDetailExit]);
    },
  );

  testWidgets(
    'consent allowed during onboarding waits for onboarding completion',
    (WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      AdService.setConsentPermission(false);
      addTearDown(() => AdService.setConsentPermission(false));
      SharedPreferences.setMockInitialValues({
        'auth_identity_token': 'apple-token',
        'auth_user_identifier': 'apple-user-123',
        'auth_session_token': 'session-token',
        'auth_backend_user_id': 'user-1',
        'auth_display_name': 'Trail Walker',
        'auth_first_race_onboarding_seen': false,
        'auth_tutorial_onboarding_seen': false,
      });
      final authService = AuthService();
      await authService.restoreSession();
      final coordinator = _RecordingInterstitialCoordinator();

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: _FakeBackendApiService(
              completeOnboarding: false,
            ),
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
            interstitialCoordinator: coordinator,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      AdService.setConsentPermission(true);
      await tester.pump();
      expect(coordinator.warms, isEmpty);

      await authService.syncFromBackendUser(const {
        'firstRaceOnboardingSeen': true,
        'tutorialOnboardingSeen': true,
        'featureFlags': {'onboardingV3Enabled': true},
      });
      await tester.pump();
      expect(coordinator.warms, [InterstitialPlacement.raceDetailExit]);
    },
  );

  testWidgets('unauthenticated shell never warms interstitial inventory', (
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    AdService.setConsentPermission(true);
    addTearDown(() => AdService.setConsentPermission(false));
    SharedPreferences.setMockInitialValues({});
    final authService = AuthService();
    await authService.restoreSession();
    final coordinator = _RecordingInterstitialCoordinator();

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: _FakeBackendApiService(),
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
          interstitialCoordinator: coordinator,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(coordinator.warms, isEmpty);
  });

  test(
    'both platform feature-header branches advertise expiring summaries',
    () {
      for (final isIos in [false, true]) {
        for (final adsSupported in [false, true]) {
          final features = BackendApiService.clientFeaturesHeaderForPlatform(
            isIos: isIos,
            adsSupported: adsSupported,
            racePayoutDoubleSupported: false,
          ).split(',');
          expect(features, contains('impact_summaries'));
          expect(features, contains('impact_summary_expiry_v1'));
        }
      }
      expect(
        BackendApiService.clientFeaturesHeader.split(','),
        contains('impact_summary_expiry_v1'),
      );
    },
  );

  for (final supported in [false, true]) {
    testWidgets(
      'cold Home loads steps with ${supported ? 'iOS' : 'Android unsupported'} background registration',
      (tester) async {
        final calls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          BackgroundSyncBootstrapService.channel,
          (call) async {
            calls.add(call.method);
            if (!supported) throw MissingPluginException();
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            BackgroundSyncBootstrapService.channel,
            null,
          );
        });
        final authService = await _authService();
        await tester.pumpWidget(
          MaterialApp(
            home: MainShell(
              authService: authService,
              healthService: _FakeHealthService(),
              backendApiService: _FakeBackendApiService(),
              backgroundSyncBootstrapService: BackgroundSyncBootstrapService(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(tester.takeException(), isNull);
        expect(calls, contains('enableHealthKitBackgroundDelivery'));
        expect(find.bySemanticsLabel('Loading today’s steps'), findsNothing);
        expect(find.byKey(const Key('home-step-count')), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('1,234'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Android revoked access exposes recovery and resumes after external grant',
    (tester) async {
      final health = _AndroidPermissionHealth();
      final auth = await _authService();
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: auth,
            healthService: health,
            backendApiService: _FakeBackendApiService(),
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(health.reads, 0);
      expect(find.bySemanticsLabel('Loading today’s steps'), findsNothing);
      expect(find.textContaining('Steps aren’t connected'), findsOneWidget);
      health.permission = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(health.reads, greaterThan(0));
      expect(find.textContaining('Steps aren’t connected'), findsNothing);
      expect(find.byKey(const Key('home-step-count')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unknown Android permission settles Home without zero or a false reconnect diagnosis',
    (tester) async {
      final health = _AndroidPermissionHealth()..permission = null;
      final auth = await _authService();
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: auth,
            healthService: health,
            backendApiService: _FakeBackendApiService(),
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(health.reads, 0);
      expect(find.bySemanticsLabel('Loading today’s steps'), findsNothing);
      expect(find.textContaining('Steps aren’t connected'), findsNothing);
      expect(find.byKey(const Key('home-step-count')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Home publishes local steps before a slow sync completes', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _SlowStepSyncApi();
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.sync.isCompleted, isFalse);
    expect(find.bySemanticsLabel('Loading today’s steps'), findsNothing);
    expect(find.byKey(const Key('home-step-count')), findsOneWidget);

    api.sync.complete(const StepSyncV2Result(kind: StepSyncV2Kind.unsupported));
    await tester.pump();
  });

  testWidgets('cold health read failure replaces the step loader with error', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FailingHealthService(),
          backendApiService: _FakeBackendApiService(),
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.bySemanticsLabel('Loading today’s steps'), findsNothing);
    expect(find.text('Couldn’t load your pace'), findsOneWidget);
    expect(find.text('Failed to fetch steps.'), findsOneWidget);
  });

  for (final entry in const <(String, String)>[
    ('cold', 'cold'),
    ('foreground', 'foreground'),
    ('background', 'background'),
  ]) {
    testWidgets(
      '${entry.$1} missing-race notification falls back to Races with notice',
      (WidgetTester tester) async {
        final authService = await _authService();
        final notifications = NotificationService(isIosForTesting: false);
        if (entry.$2 == 'cold') {
          await notifications.handleNotificationTapForTesting(const {
            'type': 'POWERUP_USED',
            'subtype': 'DECOY_CONSUMED',
            'route': 'race_detail',
            'params': '{"raceId":"race-deleted"}',
          });
        }
        await tester.pumpWidget(
          MaterialApp(
            home: MainShell(
              authService: authService,
              healthService: _FakeHealthService(),
              backendApiService: _MissingRaceApi(),
              notificationService: notifications,
              forceHomeInviteEligibilityForTesting: true,
              backgroundSyncBootstrapService:
                  _FakeBackgroundSyncBootstrapService(),
            ),
          ),
        );
        await tester.pump();
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        if (entry.$2 == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        }
        if (entry.$2 != 'cold') {
          await notifications.handleNotificationTapForTesting(const {
            'type': 'POWERUP_USED',
            'subtype': 'DECOY_CONSUMED',
            'raceId': 'race-deleted',
          });
        }
        if (entry.$2 == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          addTearDown(
            () => tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            ),
          );
        }
        await tester.pump();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(
          tester
              .widget<WoodenTabBar>(
                find.byType(WoodenTabBar, skipOffstage: false),
              )
              .currentIndex,
          1,
        );
        expect(find.text('That race is no longer available.'), findsOneWidget);
      },
    );
  }

  testWidgets('cold race action waits for session readiness before draining', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _DelayedSessionMissingRaceApi();
    final notifications = NotificationService(isIosForTesting: false);
    await notifications.handleNotificationTapForTesting(const {
      'type': 'POWERUP_USED',
      'params': '{"raceId":"race-deleted"}',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          notificationService: notifications,
          forceHomeInviteEligibilityForTesting: true,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(notifications.pendingAction.value, isNotNull);
    expect(find.text('That race is no longer available.'), findsNothing);

    api.completeSession(authService.authToken!);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(notifications.pendingAction.value, isNull);
    expect(find.text('That race is no longer available.'), findsOneWidget);
  });

  testWidgets('Decoy Inbox public shape falls back from deleted race', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _MissingRaceApi(
      inboxAlerts: const {
        'alerts': [
          {
            'id': 'decoy-alert-1',
            'type': 'POWERUP_USED',
            'subtype': 'DECOY_CONSUMED',
            'title': 'Your Decoy was triggered!',
            'body':
                'Your Decoy protected you in Sunset Sprint. Tap to view the race.',
            'route': 'race_detail',
            'params': {'raceId': 'race-deleted'},
            'readAt': null,
          },
        ],
        'nextCursor': null,
        'totalUnreadCount': 1,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          forceHomeInviteEligibilityForTesting: true,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('home-notifications-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Your Decoy was triggered!'), findsOneWidget);
    await tester.tap(find.text('Your Decoy was triggered!'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(InboxScreen), findsNothing);
    expect(
      tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).currentIndex,
      1,
    );
    expect(find.text('That race is no longer available.'), findsOneWidget);
  });

  testWidgets('MainShell renders tabs in the primary navigation order', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: _FakeBackendApiService(),
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final tabBar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));
    expect(tabBar.items.map((item) => item.label), [
      'Home',
      'Races',
      'Friends',
      'Boards',
      'Profile',
    ]);
    expect(tabBar.items[3].icon, Icons.bar_chart_rounded);
    expect(find.byKey(const Key('home-inbox-button')), findsNothing);
  });

  testWidgets(
    'authenticated Home warms one session Get Coins ad after first frame',
    (WidgetTester tester) async {
      final authService = await _authService();
      final ads = _FakeGetCoinsAdController();

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: _FakeBackendApiService(),
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
            getCoinsAdControllerBuilder: () => ads,
          ),
        ),
      );

      expect(ads.loadCalls, 0, reason: 'Home paint must not be blocked');
      await tester.pump();
      await tester.pump();

      expect(ads.loadCalls, 1);
      expect(ads.loadedUserId, 'user-1');
      expect(ads.loadedCustomData, startsWith('coins:'));
    },
  );

  for (final viaProfile in [false, true]) {
    testWidgets(
      'equipment from ${viaProfile ? "Home Shop after Profile" : "Home plus"} refreshes Home avatar immediately',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final auth = await _authService();
        final api = _EquipmentRouteApi();
        await tester.pumpWidget(
          BillingScope(
            controller: FakeBilling(),
            child: MaterialApp(
              home: MainShell(
                authService: auth,
                healthService: _FakeHealthService(),
                backendApiService: api,
                backgroundSyncBootstrapService:
                    _FakeBackgroundSyncBootstrapService(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester
              .widget<CapybaraCustomizationPreview>(
                find.byType(CapybaraCustomizationPreview),
              )
              .accessories,
          isEmpty,
        );
        if (viaProfile) {
          await tester.tap(find.text('Profile'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('Membership'), findsNothing);
          await tester.tap(find.text('Home'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await Scrollable.ensureVisible(
            tester.element(find.byKey(const Key('home-shop-button'))),
            alignment: 0.5,
          );
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pump();
          await tester.tap(find.byKey(const Key('home-shop-button')));
        } else {
          await tester.tap(find.byIcon(Icons.add_rounded));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await selectShopCategory(tester, 'CHARACTERS');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byKey(const Key('shop-character-edit-default')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byKey(const Key('wardrobe-item-wizard')));
        await tester.pump();
        await tester.tap(find.text('Save outfit'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(api.equipWrites, 1);
        await tester.tap(find.byKey(const Key('wardrobe-back')));
        await tester.pump();
        // The editor enables PopScope at endOfFrame before starting the
        // platform route's reverse transition.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byIcon(Icons.arrow_back).hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final avatar = tester.widget<CapybaraCustomizationPreview>(
          find.byType(CapybaraCustomizationPreview),
        );
        expect(
          avatar.accessories.map((row) => row['assetKey']),
          contains('wizard_hat'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Shop visit survives shell token refresh and Home claims on new token',
    (tester) async {
      final auth = await _authService();
      final api = _RewardedCoinsApi();
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: auth,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
            getCoinsAdControllerBuilder: () => _FakeGetCoinsAdController(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GetCoinsScreen), findsNothing);
      expect(find.text('Featured'), findsOneWidget);
      await auth.updateSessionToken('refreshed-token');
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('WATCH AD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('WATCH AD'));
      await tester.pump();
      expect(api.claimedToken, 'refreshed-token');
      expect(find.textContaining('4 ads left today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account switch disposes the old Get Coins session cache', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final controllers = <_FakeGetCoinsAdController>[];

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: _FakeBackendApiService(),
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
          getCoinsAdControllerBuilder: () {
            final controller = _FakeGetCoinsAdController();
            controllers.add(controller);
            return controller;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(controllers, hasLength(1));
    expect(controllers.single.loadCalls, 1);

    await authService.syncFromBackendUser(const {'id': 'user-2'});
    await tester.pump();
    await tester.pump();

    expect(controllers.first.disposeCalls, 1);
    expect(controllers, hasLength(2));
    expect(controllers.last.loadedUserId, 'user-2');
  });

  testWidgets('onboarding Home never warms or initializes Get Coins ads', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    authService.applyBackendUser(const {
      'firstRaceOnboardingSeen': false,
      'tutorialOnboardingSeen': false,
      'featureFlags': {'onboardingV3Enabled': true},
    });
    final ads = _FakeGetCoinsAdController();

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: _FakeBackendApiService(completeOnboarding: false),
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
          getCoinsAdControllerBuilder: () => ads,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(ads.loadCalls, 0);
  });

  testWidgets('Home keeps notification bell visible with no unread badge', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _FakeBackendApiService(
      inboxAlerts: const {
        'alerts': <Map<String, dynamic>>[],
        'nextCursor': null,
        'totalUnreadCount': 0,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('home-notifications-card')), findsOneWidget);
    expect(find.byKey(const Key('home-notifications-badge')), findsNothing);
    expect(
      find.bySemanticsLabel('Notifications, no unread notifications'),
      findsOneWidget,
    );
  });

  testWidgets('Home shows notification badge when unread count is one', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _FakeBackendApiService(
      inboxAlerts: const {
        'alerts': <Map<String, dynamic>>[],
        'nextCursor': null,
        'totalUnreadCount': 1,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('home-notifications-card')), findsOneWidget);
    expect(find.byKey(const Key('home-notifications-badge')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Notifications, 1 unread notification'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Home quick actions fit long identity and 9+ badge at compact width',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authService = await _authService();
      await authService.updateDisplayName(
        'A Very Long Trail Walker Display Name That Must Truncate',
      );
      await authService.updateCoins(987654321);
      final api = _FakeBackendApiService(
        displayName: 'A Very Long Trail Walker Display Name That Must Truncate',
        inboxAlerts: const {
          'alerts': <Map<String, dynamic>>[],
          'nextCursor': null,
          'totalUnreadCount': 12,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final daily = find.byKey(const Key('home-daily-reward-button'));
      final shop = find.byKey(const Key('home-shop-button'));
      final bell = find.byKey(const Key('home-notifications-card'));
      expect(daily, findsOneWidget);
      expect(shop, findsOneWidget);
      expect(bell, findsOneWidget);
      expect(tester.getSize(daily), tester.getSize(shop));
      expect(tester.getSize(shop).height, 48);
      expect(tester.getRect(bell).bottom, lessThan(tester.getRect(shop).top));
      final longName = find.byKey(const Key('home-username'));
      expect(longName, findsOneWidget);
      expect(
        tester.getRect(longName).right,
        lessThanOrEqualTo(tester.getRect(bell).left),
      );
      expect(find.text('9+'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home opens Inbox from Notifications when unread count is two', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _FakeBackendApiService(
      inboxAlerts: const {
        'alerts': <Map<String, dynamic>>[],
        'nextCursor': null,
        'totalUnreadCount': 2,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('home-notifications-card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-notifications-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(InboxScreen), findsOneWidget);
  });

  testWidgets('Home caps the visible notification badge at 9+', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _FakeBackendApiService(
      inboxAlerts: const {
        'alerts': <Map<String, dynamic>>[],
        'nextCursor': null,
        'totalUnreadCount': 12,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('home-notifications-badge')), findsOneWidget);
    expect(find.text('9+'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Notifications, 12 unread notifications'),
      findsOneWidget,
    );
  });

  testWidgets('Home seats white Mail to the left of the hero sun/moon', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final authService = await _authService();
    final api = _FakeBackendApiService(
      inboxAlerts: const {
        'alerts': <Map<String, dynamic>>[],
        'nextCursor': null,
        'totalUnreadCount': 2,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final shop = find.byKey(const Key('home-shop-button'));
    final bell = find.byKey(const Key('home-notifications-card'));
    final daily = find.byKey(const Key('home-daily-reward-button'));
    expect(tester.getSize(daily), tester.getSize(shop));
    expect(tester.getSize(shop).height, 48);
    expect(tester.getSize(bell), const Size(44, 44));
    expect(tester.getTopRight(bell).dx, closeTo(636, 2));
    expect(tester.getRect(bell).bottom, lessThan(tester.getRect(shop).top));
    final plateFinder = find.byKey(const Key('home-notifications-backplate'));
    final icon = tester.widget<Icon>(
      find.descendant(of: plateFinder, matching: find.byType(Icon)),
    );
    expect(icon.icon, Icons.mail_outline_rounded);
    expect(icon.color, Colors.white);
    expect(icon.size, closeTo(33, 0.1));
    var badge = tester.widget<Container>(
      find.byKey(const Key('home-notifications-badge')),
    );
    final colors = AppColors.of(tester.element(bell));
    expect((badge.decoration! as BoxDecoration).color, colors.coinLight);
    expect(badge.constraints!.minWidth, closeTo(27, 0.1));
    var badgeText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('home-notifications-badge')),
        matching: find.byType(Text),
      ),
    );
    expect(badgeText.style!.color, colors.roofDark);

    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('night-bell'),
        theme: AppThemeData.night(),
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final nightIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('home-notifications-backplate')),
        matching: find.byType(Icon),
      ),
    );
    expect(nightIcon.icon, Icons.mail_outline_rounded);
    expect(nightIcon.color, Colors.white);
    expect(nightIcon.size, closeTo(33, 0.1));
    badge = tester.widget<Container>(
      find.byKey(const Key('home-notifications-badge')),
    );
    final nightColors = AppColors.of(tester.element(bell));
    expect((badge.decoration! as BoxDecoration).color, nightColors.coinLight);
    badgeText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('home-notifications-badge')),
        matching: find.byType(Text),
      ),
    );
    expect(badgeText.style!.color, nightColors.roofDark);
  });

  testWidgets('Home stacks the coin balance below the username', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    await authService.updateDisplayName('Trail Walker');
    final api = _FakeBackendApiService(
      inboxAlerts: const {
        'alerts': <Map<String, dynamic>>[],
        'nextCursor': null,
        'totalUnreadCount': 0,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final name = find.text('@Trail Walker');
    final coins = find.byKey(const Key('home-coin-balance'));
    expect(name, findsOneWidget);
    expect(coins, findsOneWidget);
    expect(tester.getRect(coins).top, greaterThan(tester.getRect(name).bottom));
  });

  testWidgets('nonpositive 2x recap is suppressed on Home', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _FakeBackendApiService(
      homeRaceCard: {
        'state': 'EMPTY',
        'globalEventSummary': _globalEventSummary(
          id: 'summary-net-zero',
          extraRaceSteps: 0,
          raceCount: 2,
        ),
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('2× STEPS COMPLETE'), findsNothing);
    expect(find.textContaining('net 0'), findsNothing);
    expect(api.globalSummaryAckCalls, 0);
  });

  testWidgets(
    '2x summary queues off Home and appears when Home becomes visible',
    (WidgetTester tester) async {
      final authService = await _authService();
      final api = _DeferredSummaryApi();

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      await tester.pump();
      tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).onTap(1);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).currentIndex,
        1,
      );

      api.homeCard.complete({
        'state': 'EMPTY',
        'globalEventSummary': _globalEventSummary(id: 'summary-deferred'),
      });
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('2× STEPS COMPLETE'), findsNothing);

      tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).onTap(0);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('2× STEPS COMPLETE'), findsOneWidget);
      await tester.tap(find.text('CONTINUE'));
      await tester.pump(const Duration(milliseconds: 350));
    },
  );

  testWidgets(
    '2x summary expires from the off-Home queue without acknowledgement',
    (WidgetTester tester) async {
      final authService = await _authService();
      final api = _DeferredSummaryApi();

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      await tester.pump();
      tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).onTap(1);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).currentIndex,
        1,
      );

      api.homeCard.complete({
        'state': 'EMPTY',
        'globalEventSummary': _globalEventSummary(
          id: 'summary-expiring-queued',
          validForMs: 500,
        ),
      });
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 600));
      tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).onTap(0);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('2× STEPS COMPLETE'), findsNothing);
      expect(api.globalSummaryAckCalls, 0);
    },
  );

  testWidgets(
    '2x summary shown before expiry stays open and acknowledges after expiry',
    (WidgetTester tester) async {
      final authService = await _authService();
      final api = _FakeBackendApiService(
        homeRaceCard: {
          'state': 'EMPTY',
          'globalEventSummary': _globalEventSummary(
            id: 'summary-visible-at-expiry',
            validForMs: 500,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('2× STEPS COMPLETE'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('2× STEPS COMPLETE'), findsOneWidget);
      await tester.tap(find.text('CONTINUE'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(api.globalSummaryAckCalls, 1);
    },
  );

  testWidgets('malformed or missing 2x expiry metadata fails soft', (
    WidgetTester tester,
  ) async {
    final invalidSummaries = <Map<String, dynamic>>[
      _globalEventSummary()..remove('expiresAt'),
      _globalEventSummary(expiresAt: 'not-a-date'),
      _globalEventSummary(validForMs: null),
      _globalEventSummary(validForMs: 0),
      _globalEventSummary(validForMs: double.nan),
    ];

    for (var index = 0; index < invalidSummaries.length; index++) {
      final authService = await _authService();
      final api = _FakeBackendApiService(
        homeRaceCard: {
          'state': 'EMPTY',
          'globalEventSummary': invalidSummaries[index],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(index),
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.text('2× STEPS COMPLETE'),
        findsNothing,
        reason: 'invalid summary index $index must be suppressed',
      );
      expect(find.byType(HomeTab), findsOneWidget);
    }
  });

  testWidgets('Home request RTT is subtracted from 2x summary lifetime', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _DeferredSummaryApi();

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    api.homeCard.complete({
      'state': 'EMPTY',
      'globalEventSummary': _globalEventSummary(
        id: 'summary-expired-in-flight',
        validForMs: 100,
      ),
    });
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('2× STEPS COMPLETE'), findsNothing);
    expect(find.byType(HomeTab), findsOneWidget);
  });

  testWidgets('Home loads suggestions without Races discovery fan-out', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _FakeBackendApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.homeSuggestionCalls, 1);
    expect(api.racesDiscoveryCalls, 0);

    tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).onTap(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.racesDiscoveryCalls, 1);
  });

  testWidgets('Home suggestions load after granting health without a pull', (
    tester,
  ) async {
    final auth = await _authService();
    final api = _RecoveringHomeSuggestionsApi();
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: auth,
          healthService: _GrantHealthOnRequest(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(api.homeSuggestionCalls, 0);
    tester.widget<OnboardingFlow>(find.byType(OnboardingFlow)).onEnableHealth();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(HomeTab), findsOneWidget);
    expect(api.homeSuggestionCalls, 1);
    expect(
      tester
          .widget<HomeTab>(find.byType(HomeTab))
          .suggestedRacesState
          .isSuccess,
      isTrue,
    );
    expect(
      find.byKey(const Key('home-suggestion-FEATURED_RACE-recovered-daily')),
      findsOneWidget,
    );
    expect(api.racesDiscoveryCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final hanging in [false, true]) {
    testWidgets(
      'Home suggestions ${hanging ? 'timeout' : 'exception'} ends skeleton and retry recovers',
      (tester) async {
        final auth = await _authService();
        final api = _RecoveringHomeSuggestionsApi(
          failFirst: !hanging,
          hangFirst: hanging,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MainShell(
              authService: auth,
              healthService: _FakeHealthService(),
              backendApiService: api,
              backgroundSyncBootstrapService:
                  _FakeBackgroundSyncBootstrapService(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (hanging) await tester.pump(const Duration(seconds: 21));
        expect(
          tester
              .widget<HomeTab>(find.byType(HomeTab))
              .suggestedRacesState
              .isError,
          isTrue,
        );
        expect(find.byKey(const Key('home-suggestions-error')), findsOneWidget);
        tester
            .widget<HomeTab>(find.byType(HomeTab))
            .onRetrySuggestedRaces
            ?.call();
        await tester.pump();
        expect(api.homeSuggestionCalls, 2);
        expect(
          tester
              .widget<HomeTab>(find.byType(HomeTab))
              .suggestedRacesState
              .isSuccess,
          isTrue,
        );
        expect(
          find.byKey(
            const Key('home-suggestion-FEATURED_RACE-recovered-daily'),
          ),
          findsOneWidget,
        );
        if (hanging) {
          api.stalled.complete(
            const HomeSuggestedRacesRefresh(error: 'Late stale response'),
          );
          await tester.pump();
          expect(
            tester
                .widget<HomeTab>(find.byType(HomeTab))
                .suggestedRacesState
                .isSuccess,
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Races reveal retains cached races and starts discovery plus zero-friends '
    'refresh concurrently after a failed core refresh',
    (WidgetTester tester) async {
      final authService = await _authService();
      final api = _RacesTabRevealApi(cachedFriends: const []);

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(api.coreCalls, 1, reason: 'Home performs the cache-seeding read.');
      expect(api.started, isEmpty);

      // The shared repository absorbs exact duplicate friends reads for one
      // second. After that coalescing window, the shell's separate 60-second
      // freshness rule still refreshes an empty snapshot on Races reveal.
      sleep(const Duration(milliseconds: 1100));

      tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).onTap(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.coreCalls, 2);
      expect(api.started, ['core']);
      expect(find.text('Cached Sprint'), findsOneWidget);
      final refreshing = tester.widget<RacesTab>(find.byType(RacesTab));
      expect(refreshing.racesState?.isRefreshing, isTrue);
      expect(refreshing.racesState?.data, _RacesTabRevealApi.cachedRaces);

      api.revealCore.completeError(StateError('core unavailable'));
      await tester.pump();

      expect(api.started, ['core', 'discovery', 'friends']);
      expect(api.discovery.isCompleted, isFalse);
      expect(api.friends.isCompleted, isFalse);
      expect(find.text('Cached Sprint'), findsOneWidget);
      final failed = tester.widget<RacesTab>(find.byType(RacesTab));
      expect(failed.racesState?.isError, isTrue);
      expect(failed.racesState?.data, _RacesTabRevealApi.cachedRaces);

      api.discovery.complete(RaceDiscoverySummary.empty);
      api.friends.complete(const {
        'contract': 'friends-summary-v1',
        'incomingFriendRequests': 0,
        'friends': <Map<String, dynamic>>[],
        'pending': {
          'incoming': <Map<String, dynamic>>[],
          'outgoing': <Map<String, dynamic>>[],
        },
      });
      await tester.pump();
    },
  );

  testWidgets(
    'Races reveal starts discovery only after core success and keeps a fresh '
    'non-empty friends cache',
    (WidgetTester tester) async {
      final authService = await _authService();
      final api = _RacesTabRevealApi(
        cachedFriends: const [
          {'id': 'friend-1', 'displayName': 'Fresh Friend', 'steps': 3210},
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(api.coreCalls, 1);
      expect(api.started, isEmpty);

      tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).onTap(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(api.started, ['core']);
      api.revealCore.complete(const {
        'active': <Map<String, dynamic>>[],
        'pending': <Map<String, dynamic>>[],
        'completed': <Map<String, dynamic>>[],
      });
      await tester.pump();

      expect(api.started, ['core', 'discovery']);
      expect(api.discovery.isCompleted, isFalse);
      expect(
        api.started,
        isNot(contains('friends')),
        reason:
            'A non-empty friends snapshot fetched less than 60s ago is fresh.',
      );

      api.discovery.complete(RaceDiscoverySummary.empty);
      await tester.pump();
    },
  );

  testWidgets(
    'foreground Home load preserves the shipped request dependency graph',
    (WidgetTester tester) async {
      final authService = await _authService();
      final api = _HomeRequestDagApi();

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.started, contains('sync-v2'));
      expect(
        api.started.where(
          const <String>{'race-card', 'races', 'suggestions'}.contains,
        ),
        isEmpty,
        reason: 'Home reads must wait for step persistence to settle.',
      );

      api.sync.complete(const StepSyncV2Result(kind: StepSyncV2Kind.current));
      await tester.pump();

      expect(
        api.started,
        containsAll(<String>['race-card', 'races', 'suggestions']),
        reason: 'The three initial Home reads launch together after sync.',
      );
      expect(api.persistedTotalFlags, [true]);
      expect(api.started, isNot(contains('friends')));
      expect(api.started, isNot(contains('catalog')));
      expect(api.started, isNot(contains('me')));

      api.raceCard.complete(const {
        'contract': 'home-shell-v1',
        'state': 'EMPTY',
        'resolved': {'presentation': false, 'friends': false},
      });
      await tester.pump();

      expect(
        api.started,
        containsAll(<String>['friends', 'catalog', 'me']),
        reason:
            'Malformed or unresolved race-card blocks trigger both fallbacks, '
            'while Me starts in the same post-card phase.',
      );

      api.races.complete(const {
        'invites': <Map<String, dynamic>>[],
        'waiting': <Map<String, dynamic>>[],
        'active': <Map<String, dynamic>>[],
        'completed': <Map<String, dynamic>>[],
      });
      api.friends.complete(const {
        'contract': 'friends-summary-v1',
        'incomingFriendRequests': 0,
        'friends': <Map<String, dynamic>>[],
        'pending': {
          'incoming': <Map<String, dynamic>>[],
          'outgoing': <Map<String, dynamic>>[],
        },
      });
      api.catalog.complete(const {
        'coins': 0,
        'equipped': <String, dynamic>{},
        'items': <Map<String, dynamic>>[],
      });
      api.me.complete(const {
        'id': 'user-1',
        'displayName': 'Trail Walker',
        'incomingFriendRequests': 0,
      });
      await tester.pump();

      // Suggestions are explicitly non-gating: the required Home phase above
      // settles while this background response is still outstanding.
      expect(api.suggestions.isCompleted, isFalse);
      api.suggestions.complete(
        const HomeSuggestedRacesRefresh(
          featuredRaces: [],
          publicRaces: [],
          tournaments: [],
        ),
      );
      await tester.pump();
    },
  );

  testWidgets('Home Notifications pushes Inbox and never changes shell index', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _FakeBackendApiService(
      homeRaceCard: const {'state': 'EMPTY'},
      inboxAlerts: const {
        'alerts': [
          {
            'id': 'alert-1',
            'type': 'RACE_STARTED',
            'title': 'Back home',
            'body': 'Open Home',
            'readAt': null,
            'destination': {'route': 'home'},
          },
        ],
        'nextCursor': null,
        'unreadCount': 4,
        'totalUnreadCount': 7,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).currentIndex,
      0,
    );
    await tester.tap(find.byKey(const Key('home-notifications-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Back home'), findsOneWidget);
    expect(
      tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).currentIndex,
      0,
    );
  });

  testWidgets(
    'delayed prior-account Home response cannot seed the new Inbox badge',
    (WidgetTester tester) async {
      final authService = await _authService();
      final api = _AccountSwitchRaceCardApi();
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      await tester.pump();
      expect(api.tokens, contains('session-token'));

      await authService.updateSessionToken('new-user-token');
      await authService.syncFromBackendUser(const {'id': 'user-2'});
      await tester.pump();
      expect(api.tokens, contains('new-user-token'));

      api.newAccount.complete(const {'state': 'EMPTY', 'inboxUnreadCount': 2});
      await tester.pump();

      api.oldAccount.complete(const {'state': 'EMPTY', 'inboxUnreadCount': 9});
      await tester.pump();
    },
  );

  testWidgets('opening a support thread refreshes the shell combined badge', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _SupportUnreadApi();
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('home-notifications-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('A staff reply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets(
    'pending payout offer selects seen frozen race before unseen filtering',
    (WidgetTester tester) async {
      final authService = await _authService();
      final api = _FakeBackendApiService(
        racesData: const {
          'invites': <Map<String, dynamic>>[],
          'waiting': <Map<String, dynamic>>[],
          'active': <Map<String, dynamic>>[],
          'completed': <Map<String, dynamic>>[
            {
              'id': 'race-later',
              'name': 'Later Race',
              'myStatus': 'ACCEPTED',
              'myResultsSeen': false,
              'myPayoutCoins': 50,
            },
            {
              'id': 'race-a',
              'name': 'Frozen Race',
              'myStatus': 'ACCEPTED',
              'myResultsSeen': true,
              'myPayoutCoins': 120,
            },
          ],
          'payoutDoubleOffer': {
            'offerId': 'd05cb2a4-16b7-463f-977d-58231987a0ac',
            'raceIds': ['race-a'],
            'baseCoins': 120,
            'bonusCoins': 120,
            'maxBonusCoins': 500,
            'rolling24hRemainingBeforeClaim': 500,
          },
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
            racePayoutDoubleAdController: _FakeRacePayoutDoubleAdController(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Frozen Race'), findsOneWidget);
      expect(find.text('Later Race'), findsNothing);
      expect(api.payoutClaimCalls, 1);
      expect(find.text('120 PAYOUT + 120 AD BONUS'), findsOneWidget);

      // Ranked-results acknowledgement is disabled in the current shell; the
      // payout offer is still selected from the seen frozen race above.
      expect(api.seenCalls, 0);
    },
  );

  testWidgets(
    'completed results defer the Home invite until the results sheet closes',
    (WidgetTester tester) async {
      final authService = await _authService();
      final api = _FakeBackendApiService(
        racesData: const {
          'invites': <Map<String, dynamic>>[],
          'waiting': <Map<String, dynamic>>[],
          'active': <Map<String, dynamic>>[],
          'completed': <Map<String, dynamic>>[
            {
              'id': 'completed-race',
              'name': 'Results Before Invite',
              'myStatus': 'ACCEPTED',
              'myResultsSeen': false,
              'myPayoutCoins': 0,
            },
          ],
        },
        homeInvitePreflight: const {
          'resolved': true,
          'invites': <Map<String, dynamic>>[
            {
              'kind': 'RACE',
              'id': 'pending-invite',
              'name': 'Invite After Results',
              'status': 'PENDING',
            },
          ],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Results Before Invite'), findsOneWidget);
      // Ranked results are disabled in this shell configuration, so the
      // deferred post-results preflight is not invoked.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.homeInvitePreflightCalls, 0);
      expect(find.text('Invite After Results'), findsNothing);
    },
  );

  testWidgets('onboarding suppresses a production race-results payload', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'apple-token',
      'auth_user_identifier': 'apple-user-123',
      'auth_session_token': 'session-token',
      'auth_backend_user_id': 'user-1',
      'auth_display_name': 'Trail Walker',
      'auth_first_race_onboarding_seen': false,
      'auth_tutorial_onboarding_seen': false,
    });
    final authService = AuthService();
    await authService.restoreSession();
    final api = _FakeBackendApiService(
      completeOnboarding: false,
      racesData: const {
        'completed': <Map<String, dynamic>>[
          {
            'id': 'race-a',
            'name': 'Must Not Interrupt',
            'myStatus': 'ACCEPTED',
            'myResultsSeen': false,
            'myPayoutCoins': 120,
          },
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
          racePayoutDoubleAdController: _FakeRacePayoutDoubleAdController(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Must Not Interrupt'), findsNothing);
    expect(find.text('RACE FINISHED'), findsNothing);
  });

  testWidgets(
    'account switch during results modal retains old ack without new-token send',
    (WidgetTester tester) async {
      final authService = await _authService();
      final api = _FakeBackendApiService(
        racesData: const {
          'completed': <Map<String, dynamic>>[
            {
              'id': 'old-user-race',
              'name': 'Old User Finish',
              'myStatus': 'ACCEPTED',
              'myResultsSeen': false,
              'myPayoutCoins': 0,
            },
          ],
        },
      );
      final queue = RaceResultsAcknowledgementQueue(backendApiService: api);
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
            raceResultsAcknowledgementQueue: queue,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Old User Finish'), findsOneWidget);

      await authService.syncFromBackendUser(const {'id': 'user-2'});
      await authService.updateSessionToken('new-user-token');
      await tester.pump();
      // No results modal means there is no acknowledgement action to send.
      expect(api.seenRequests, isEmpty);
      final records = await queue.debugRecords();
      expect(records, isEmpty);
    },
  );

  testWidgets(
    'plain completed-results exit primes before and presents after shell restore',
    (WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final authService = await _authService();
      final coordinator = _RecordingInterstitialCoordinator();
      final api = _FakeBackendApiService(
        racesData: const {
          'completed': <Map<String, dynamic>>[
            {
              'id': 'race-interstitial',
              'name': 'Finished Cleanly',
              'myStatus': 'ACCEPTED',
              'myResultsSeen': false,
              'myPayoutCoins': 10,
            },
          ],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
            interstitialCoordinator: coordinator,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        coordinator.warms,
        contains(InterstitialPlacement.raceResultsExit),
      );
      expect(
        coordinator.primes,
        contains(InterstitialPlacement.raceResultsExit),
      );
      expect(coordinator.presentations, isEmpty);
      await tester.tap(find.text('CONTINUE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Finished Cleanly'), findsNothing);
      expect(coordinator.presentations, [
        InterstitialPlacement.raceResultsExit,
      ]);
    },
  );

  testWidgets(
    'unresolved results warm and prime never delay dismissal or present late',
    (WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final authService = await _authService();
      final warm = Completer<void>();
      final prime = Completer<void>();
      final coordinator = _RecordingInterstitialCoordinator(
        warmCompleter: warm,
        primeCompleter: prime,
      );
      final api = _FakeBackendApiService(
        racesData: const {
          'completed': <Map<String, dynamic>>[
            {
              'id': 'race-unresolved-interstitial',
              'name': 'Finished Without Waiting',
              'myStatus': 'ACCEPTED',
              'myResultsSeen': false,
              'myPayoutCoins': 10,
            },
          ],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: authService,
            healthService: _FakeHealthService(),
            backendApiService: api,
            backgroundSyncBootstrapService:
                _FakeBackgroundSyncBootstrapService(),
            interstitialCoordinator: coordinator,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Finished Without Waiting'), findsOneWidget);
      expect(
        coordinator.primes,
        contains(InterstitialPlacement.raceResultsExit),
      );
      await tester.tap(find.text('CONTINUE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Finished Without Waiting'), findsNothing);
      expect(coordinator.presentations, [
        InterstitialPlacement.raceResultsExit,
      ]);
      warm.complete();
      prime.complete();
      await tester.pump();
      expect(coordinator.presentations, [
        InterstitialPlacement.raceResultsExit,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backgrounded results exit cancels instead of presenting', (
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final authService = await _authService();
    final coordinator = _RecordingInterstitialCoordinator();
    final api = _FakeBackendApiService(
      racesData: const {
        'completed': <Map<String, dynamic>>[
          {
            'id': 'race-background',
            'name': 'Background Finish',
            'myStatus': 'ACCEPTED',
            'myResultsSeen': false,
            'myPayoutCoins': 10,
          },
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
          interstitialCoordinator: coordinator,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Background Finish'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(coordinator.presentations, isEmpty);
    expect(
      coordinator.cancellations,
      contains(InterstitialPlacement.raceResultsExit),
    );
  });

  testWidgets('results prime failures never interrupt the popup', (
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final authService = await _authService();
    final coordinator = _RecordingInterstitialCoordinator(primeThrows: true);
    final api = _FakeBackendApiService(
      racesData: const {
        'completed': <Map<String, dynamic>>[
          {
            'id': 'race-prime-failure',
            'name': 'Prime Failure Finish',
            'myStatus': 'ACCEPTED',
            'myResultsSeen': false,
            'myPayoutCoins': 10,
          },
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
          interstitialCoordinator: coordinator,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Prime Failure Finish'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Start Next Race cancels the results placement', (
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final authService = await _authService();
    final coordinator = _RecordingInterstitialCoordinator();
    final api = _FakeBackendApiService(
      racesData: const {
        'completed': <Map<String, dynamic>>[
          {
            'id': 'race-next',
            'name': 'Next Race Finish',
            'myStatus': 'ACCEPTED',
            'myResultsSeen': false,
            'myPayoutCoins': 10,
          },
        ],
        'nextRace': {
          'resolved': true,
          'eligible': true,
          'discoveryEnabled': true,
          'createEnabled': true,
          'openRaces': <Map<String, dynamic>>[],
        },
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
          interstitialCoordinator: coordinator,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('START YOUR NEXT RACE'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(coordinator.presentations, isEmpty);
    expect(
      coordinator.cancellations,
      contains(InterstitialPlacement.raceResultsExit),
    );
  });

  testWidgets('native review opportunity cancels the results placement', (
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final authService = await _authService();
    final coordinator = _RecordingInterstitialCoordinator();
    final api = _FakeBackendApiService(
      racesData: const {
        'completed': <Map<String, dynamic>>[
          {
            'id': 'race-review',
            'name': 'Review Finish',
            'myStatus': 'ACCEPTED',
            'myResultsSeen': false,
            'myPayoutCoins': 10,
            'reviewOpportunity': {
              'id': 'review-opportunity',
              'raceId': 'race-review',
            },
          },
        ],
      },
    );
    var nativeReviewCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
          interstitialCoordinator: coordinator,
          reviewPromptService: ReviewPromptService(
            requestNativeReview: () async => nativeReviewCalls++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(nativeReviewCalls, 1);
    expect(api.reviewClaimCalls, 1);
    expect(coordinator.presentations, isEmpty);
    expect(
      coordinator.cancellations,
      contains(InterstitialPlacement.raceResultsExit),
    );
  });

  testWidgets('payout rewarded presentation suppresses results interstitial', (
    WidgetTester tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final authService = await _authService();
    final coordinator = _RecordingInterstitialCoordinator();
    final api = _RewardedResultsApi(
      racesData: const {
        'completed': <Map<String, dynamic>>[
          {
            'id': 'race-rewarded',
            'name': 'Rewarded Finish',
            'myStatus': 'ACCEPTED',
            'myResultsSeen': false,
            'myPayoutCoins': 100,
          },
        ],
        'payoutDoubleOffer': {
          'offerId': 'd05cb2a4-16b7-463f-977d-58231987a0ac',
          'raceIds': ['race-rewarded'],
          'baseCoins': 100,
          'bonusCoins': 100,
        },
      },
    );
    final ads = _ReadyRacePayoutDoubleAdController(
      onShow: () => api.adEarned = true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: authService,
          healthService: _FakeHealthService(),
          backendApiService: api,
          backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
          interstitialCoordinator: coordinator,
          racePayoutDoubleAdController: ads,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    await tester.tap(find.textContaining('WATCH AD'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(ads.shows, 1);
    expect(coordinator.presentations, isEmpty);
    expect(coordinator.rewardedArguments, contains(true));
  });
}
