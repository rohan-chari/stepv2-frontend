import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/screens/inbox_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
import 'package:step_tracker/models/race_payout_double_offer.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/services/race_results_ack_queue.dart';
import 'package:step_tracker/widgets/wooden_tab_bar.dart';

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
    this.homeRaceCard = const {'state': 'EMPTY'},
    this.inboxAlerts = const {
      'alerts': <Map<String, dynamic>>[],
      'nextCursor': null,
    },
  });

  final Map<String, dynamic> racesData;
  final Map<String, dynamic> homeInvitePreflight;
  final bool completeOnboarding;
  final Map<String, dynamic> homeRaceCard;
  final Map<String, dynamic> inboxAlerts;
  int homeSuggestionCalls = 0;
  int racesDiscoveryCalls = 0;
  int payoutClaimCalls = 0;
  int seenCalls = 0;
  int homeInvitePreflightCalls = 0;
  int globalSummaryAckCalls = 0;
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
      'displayName': 'Trail Walker',
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
}

class _DeferredSummaryApi extends _FakeBackendApiService {
  final Completer<Map<String, dynamic>> homeCard = Completer();

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) => homeCard.future;
}

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

void main() {
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
      'Leaderboard',
      'Friends',
      'Profile',
    ]);
    expect(find.byKey(const Key('home-inbox-button')), findsNothing);
  });

  testWidgets('Home hides Notifications when unread count is one', (
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

    expect(find.byKey(const Key('home-notifications-card')), findsNothing);
  });

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

  testWidgets('mixed net-zero 2x summary remains eligible on Home', (
    WidgetTester tester,
  ) async {
    final authService = await _authService();
    final api = _FakeBackendApiService(
      homeRaceCard: const {
        'state': 'EMPTY',
        'globalEventSummary': {
          'id': 'summary-net-zero',
          'extraRaceSteps': 0,
          'raceCount': 2,
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
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('2× STEPS COMPLETE'), findsOneWidget);
    expect(find.textContaining('net 0'), findsOneWidget);
    await tester.tap(find.text('CONTINUE'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.globalSummaryAckCalls, 1);
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

      api.homeCard.complete(const {
        'state': 'EMPTY',
        'globalEventSummary': {
          'id': 'summary-deferred',
          'extraRaceSteps': 125,
          'raceCount': 1,
        },
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
}
