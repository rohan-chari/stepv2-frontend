import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/screens/main_shell.dart';
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
    this.completeOnboarding = true,
  });

  final Map<String, dynamic> racesData;
  final bool completeOnboarding;
  int homeSuggestionCalls = 0;
  int racesDiscoveryCalls = 0;
  int payoutClaimCalls = 0;
  int seenCalls = 0;
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
    return const {'state': 'EMPTY'};
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
      'Friends',
      'Boards',
      'Profile',
    ]);
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

      expect(find.text('Frozen Race'), findsOneWidget);
      expect(find.text('Later Race'), findsNothing);
      expect(api.payoutClaimCalls, 1);
      expect(find.text('120 PAYOUT + 120 AD BONUS'), findsOneWidget);

      await tester.tap(find.text('NICE'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.seenCalls, 1);
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
      expect(find.text('Old User Finish'), findsOneWidget);

      await authService.syncFromBackendUser(const {'id': 'user-2'});
      await authService.updateSessionToken('new-user-token');
      await tester.pump();
      await tester.tap(find.text('NICE'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.seenRequests, isEmpty);
      final records = await queue.debugRecords();
      expect(records, hasLength(1));
      expect(records.single.userId, 'user-1');
      expect(records.single.raceIds, ['old-user-race']);
    },
  );
}
