import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/screens/ranked_results_summary_screen.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/screens/tabs/ranked_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';
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

  @override
  Future<List<StepSampleData>> getStepSamples({
    required DateTime startTime,
    required DateTime endTime,
    int bucketMinutes = 60,
  }) async {
    return const [];
  }
}

class _FakeBackgroundSyncBootstrapService
    extends BackgroundSyncBootstrapService {
  @override
  Future<void> enableHealthKitBackgroundDelivery() async {}
}

Map<String, dynamic> _compactAuthUser({
  bool omitEmail = false,
  bool invalidCoins = false,
}) => {
  'id': 'user-1',
  if (!omitEmail) 'email': 'compact@example.com',
  'displayName': 'Compact Walker',
  'firstName': 'Compact',
  'lastName': null,
  'profilePhotoUrl': null,
  'profilePhotoPromptDismissedAt': null,
  'referredByCode': null,
  'nameSetupOnboardingRequired': false,
  'nameSetupCompletedAt': null,
  'renameChipShownCount': 0,
  'renameChipDismissedAt': null,
  'isAdmin': false,
  'coins': invalidCoins ? 'bad' : 0,
  'heldCoins': 0,
  'firstRaceOnboardingSeen': true,
  'tutorialOnboardingSeen': true,
  'hiddenFromLeaderboard': false,
  'autoJoinFeaturedRaces': false,
  'incomingFriendRequests': 0,
  'featureFlags': {
    'characterPowersEnabled': false,
    'teamRacesEnabled': true,
    'customRaceWindowEnabled': true,
    'onboardingV2Enabled': true,
    'onboardingV3Enabled': true,
    'onboardingInviteCodeEnabled': false,
    'openUserRaceDiscoveryEnabled': true,
    'quickCreateRaceCtaEnabled': true,
    'setupInviteCodePromptEnabled': true,
    'homeInviteModalEnabled': true,
    'tutorialMandatoryEnabled': true,
    'stepSampleBucketMinutes': 5,
  },
};

class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService({
    this.publicRacesError = false,
    this.publicRacesCount = 0,
    this.featuredTournamentCount = 0,
    this.publicTournamentCount = 0,
    this.incomingFriendRequests = 0,
    this.rankedLastWeek,
    this.homeRaceCard = const {'state': 'EMPTY'},
    this.joinPublicRaceError,
    this.compactSession = false,
    this.malformedCompactIdentity = false,
    this.invalidCompactCoins = false,
  });

  final bool publicRacesError;
  final int publicRacesCount;
  final int featuredTournamentCount;
  final int publicTournamentCount;
  final int incomingFriendRequests;
  final Map<String, dynamic>? rankedLastWeek;
  final Map<String, dynamic> homeRaceCard;
  final ApiException? joinPublicRaceError;
  final bool compactSession;
  final bool malformedCompactIdentity;
  final bool invalidCompactCoins;
  int fetchMeCalls = 0;
  int fetchFriendsCalls = 0;
  int fetchShopCalls = 0;

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async {
    return {
      if (compactSession) 'contract': 'auth-shell-v1',
      'sessionToken': authToken,
      'user': compactSession
          ? _compactAuthUser(
              omitEmail: malformedCompactIdentity,
              invalidCoins: invalidCompactCoins,
            )
          : const {
              'id': 'user-1',
              'firstRaceOnboardingSeen': true,
              'tutorialOnboardingSeen': true,
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
  }) async => RaceDiscoverySummary.unsupportedResult;

  @override
  Future<HomeSuggestedRacesRefresh> fetchHomeSuggestedRaces({
    required String identityToken,
  }) async => const HomeSuggestedRacesRefresh(
    featuredRaces: [],
    publicRaces: [],
    tournaments: [],
  );

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) async => homeRaceCard;

  @override
  Future<Map<String, dynamic>> joinPublicRace({
    required String identityToken,
    required String raceId,
    bool onboarding = false,
  }) async {
    final error = joinPublicRaceError;
    if (error != null) throw error;
    return {
      'participant': {'raceId': raceId},
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
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    fetchMeCalls += 1;
    return {
      'displayName': 'Trail Walker',
      'incomingFriendRequests': incomingFriendRequests,
      'firstRaceOnboardingSeen': true,
      'tutorialOnboardingSeen': true,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async {
    return const {
      'pending': <Map<String, dynamic>>[],
      'active': <Map<String, dynamic>>[],
      'completed': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async {
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async {
    if (publicRacesError) {
      throw const ApiException('public races down');
    }
    return List.generate(
      publicRacesCount,
      (i) => {'id': 'race-$i', 'name': 'Public $i'},
    );
  }

  @override
  Future<Map<String, dynamic>> fetchPublicTournaments({
    required String identityToken,
  }) async => {
    'featured': List.generate(
      featuredTournamentCount,
      (index) => {'id': 'featured-tournament-$index'},
    ),
    'tournaments': List.generate(
      publicTournamentCount,
      (index) => {'id': 'tournament-$index'},
    ),
  };

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    fetchShopCalls += 1;
    return const {
      'coins': 0,
      'equipped': <String, dynamic>{},
      'items': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRankedV2({
    required String identityToken,
  }) async {
    final lastWeek = rankedLastWeek;
    return lastWeek == null ? const {} : {'lastWeek': lastWeek};
  }

  @override
  Future<void> markRankedResultsSeen({
    required String identityToken,
    required int weekIndex,
  }) async {}

  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    fetchFriendsCalls += 1;
    return const {
      'friends': <Map<String, dynamic>>[],
      'incoming': <Map<String, dynamic>>[],
      'outgoing': <Map<String, dynamic>>[],
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
    'auth_first_race_onboarding_seen': true,
    'auth_tutorial_onboarding_seen': true,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

/// Pumps a series of short frames so the async startup chain (and any tab
/// animation) can settle. We avoid [pumpAndSettle] because MainShell starts a
/// periodic foreground-poll timer that never quiesces.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapTab(WidgetTester tester, int index) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(WoodenTabBar),
          matching: find.byType(InkWell),
        )
        .at(index),
  );
  await _settle(tester);
}

Future<MainShell> _pumpShell(
  WidgetTester tester,
  _FakeBackendApiService api,
) async {
  final authService = await _authService();
  final shell = MainShell(
    authService: authService,
    healthService: _FakeHealthService(),
    backendApiService: api,
    backgroundSyncBootstrapService: _FakeBackgroundSyncBootstrapService(),
  );
  await tester.pumpWidget(MaterialApp(home: shell));
  await _settle(tester);
  return shell;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.8',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'compact auth skips only the cold-start me read, not a later Home refresh',
    (WidgetTester tester) async {
      final api = _FakeBackendApiService(compactSession: true);
      await _pumpShell(tester, api);
      expect(api.fetchMeCalls, 0);

      final home = tester.widget<HomeTab>(find.byType(HomeTab));
      unawaited(home.onRefresh());
      await _settle(tester);

      expect(api.fetchMeCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('compact auth hydrates Profile identity before skipping me', (
    WidgetTester tester,
  ) async {
    final api = _FakeBackendApiService(compactSession: true);
    await _pumpShell(tester, api);

    await tester.tap(find.byKey(const Key('home-profile-button')));
    await _settle(tester);

    expect(find.text('compact@example.com'), findsOneWidget);
    expect(find.text('@Compact Walker'), findsOneWidget);
    expect(api.fetchMeCalls, 0);
  });

  testWidgets('malformed compact identity retains the cold me fallback', (
    WidgetTester tester,
  ) async {
    final api = _FakeBackendApiService(
      compactSession: true,
      malformedCompactIdentity: true,
    );
    await _pumpShell(tester, api);

    expect(api.fetchMeCalls, 1);
  });

  testWidgets('wrong-typed compact required field retains the me fallback', (
    WidgetTester tester,
  ) async {
    final api = _FakeBackendApiService(
      compactSession: true,
      invalidCompactCoins: true,
    );
    await _pumpShell(tester, api);

    expect(api.fetchMeCalls, 1);
  });

  testWidgets(
    'malformed compact Home blocks fall back only presentation and friends',
    (WidgetTester tester) async {
      final api = _FakeBackendApiService(
        compactSession: true,
        homeRaceCard: const {
          'contract': 'home-shell-v1',
          'state': 'EMPTY',
          'resolved': {'presentation': true, 'friends': true},
          'presentation': {'coins': 10},
          'friends': {
            'friends': [],
            'pending': {'incoming': []},
          },
        },
      );
      await _pumpShell(tester, api);

      expect(api.fetchShopCalls, 1);
      expect(api.fetchFriendsCalls, 1);
      expect(api.fetchMeCalls, 0);
    },
  );

  testWidgets('compact Home presentation missing cape falls back to catalog', (
    WidgetTester tester,
  ) async {
    final api = _FakeBackendApiService(
      compactSession: true,
      homeRaceCard: const {
        'contract': 'home-shell-v1',
        'state': 'EMPTY',
        'resolved': {'presentation': true},
        'presentation': {'coins': 10, 'equipped': <String, dynamic>{}},
      },
    );
    await _pumpShell(tester, api);

    expect(api.fetchShopCalls, 1);
  });

  testWidgets(
    'PUBLIC RACES count falls back to (0) when the fetch fails (no throw)',
    (WidgetTester tester) async {
      await _pumpShell(tester, _FakeBackendApiService(publicRacesError: true));

      await _tapTab(tester, 1); // Races tab.

      expect(find.text('PUBLIC RACES (0)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('PUBLIC RACES count reflects the fetched public-races list', (
    WidgetTester tester,
  ) async {
    await _pumpShell(tester, _FakeBackendApiService(publicRacesCount: 2));

    await _tapTab(tester, 1); // Races tab.

    expect(find.text('PUBLIC RACES (2)'), findsOneWidget);
  });

  testWidgets('PUBLIC RACES count includes featured and browse tournaments', (
    WidgetTester tester,
  ) async {
    await _pumpShell(
      tester,
      _FakeBackendApiService(
        publicRacesCount: 2,
        featuredTournamentCount: 1,
        publicTournamentCount: 3,
      ),
    );
    await _tapTab(tester, 1);
    expect(find.text('PUBLIC RACES (6)'), findsOneWidget);
  });

  testWidgets(
    'Next Race join shows the five-race limit instead of generic copy',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const message =
          "You're already in 5 races that start automatically. Try again after one is over.";
      await _pumpShell(
        tester,
        _FakeBackendApiService(
          homeRaceCard: const {
            'state': 'EMPTY',
            'nextRace': {
              'resolved': true,
              'eligible': true,
              'discoveryEnabled': true,
              'createEnabled': false,
              'openRaces': [
                {
                  'id': 'race-limit',
                  'name': 'Trail Mix',
                  'participantCount': 3,
                },
              ],
            },
          },
          joinPublicRaceError: const ApiException(
            message,
            statusCode: 409,
            code: 'QUICK_RACE_MEMBERSHIP_LIMIT',
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('home-join-race-limit')));
      await tester.pump();

      expect(find.text(message), findsOneWidget);
      expect(
        find.text('Something went sideways. Give it another try!'),
        findsNothing,
      );
    },
  );

  testWidgets('tab index 2 renders the Friends tab, not the Ranked tab', (
    WidgetTester tester,
  ) async {
    await _pumpShell(tester, _FakeBackendApiService());

    await _tapTab(tester, 3);

    expect(find.byType(FriendsTab), findsOneWidget);
    expect(find.byType(RankedTab), findsNothing);
  });

  testWidgets('tab item 3 is labeled Friends and the Profile badge moved', (
    WidgetTester tester,
  ) async {
    await _pumpShell(tester, _FakeBackendApiService(incomingFriendRequests: 2));

    final tabBar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));
    expect(tabBar.items[3].label, 'Friends');
    expect(tabBar.items[3].icon, Icons.people_rounded);
    // The incoming-request badge now lives on Friends, not Profile.
    expect(tabBar.items[3].badgeCount, 2);
    expect(tabBar.items[4].badgeCount, 0);
  });

  testWidgets('selecting the Friends tab clears the incoming-request badge', (
    WidgetTester tester,
  ) async {
    await _pumpShell(tester, _FakeBackendApiService(incomingFriendRequests: 2));

    var tabBar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));
    expect(tabBar.items[3].badgeCount, 2);

    await _tapTab(tester, 3);

    tabBar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));
    expect(tabBar.items[3].badgeCount, 0);
  });

  testWidgets('the in-app ranked results popup is suppressed on load', (
    WidgetTester tester,
  ) async {
    await _pumpShell(
      tester,
      _FakeBackendApiService(
        rankedLastWeek: const {
          'resultsSeen': false,
          'outcome': 'PROMOTE',
          'weekIndex': 5,
        },
      ),
    );

    expect(find.byType(RankedResultsSummaryScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
