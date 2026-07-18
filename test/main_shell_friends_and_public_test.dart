import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/screens/ranked_results_summary_screen.dart';
import 'package:step_tracker/screens/tabs/friends_tab.dart';
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
}

class _FakeBackgroundSyncBootstrapService
    extends BackgroundSyncBootstrapService {
  @override
  Future<void> enableHealthKitBackgroundDelivery() async {}
}

class _FakeBackendApiService extends BackendApiService {
  _FakeBackendApiService({
    this.publicRacesError = false,
    this.publicRacesCount = 0,
    this.incomingFriendRequests = 0,
    this.rankedLastWeek,
  });

  final bool publicRacesError;
  final int publicRacesCount;
  final int incomingFriendRequests;
  final Map<String, dynamic>? rankedLastWeek;

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

  testWidgets('tab index 2 renders the Friends tab, not the Ranked tab', (
    WidgetTester tester,
  ) async {
    await _pumpShell(tester, _FakeBackendApiService());

    await _tapTab(tester, 2);

    expect(find.byType(FriendsTab), findsOneWidget);
    expect(find.byType(RankedTab), findsNothing);
  });

  testWidgets('tab item 2 is labeled Friends and the Profile badge moved', (
    WidgetTester tester,
  ) async {
    await _pumpShell(
      tester,
      _FakeBackendApiService(incomingFriendRequests: 2),
    );

    final tabBar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));
    expect(tabBar.items[2].label, 'Friends');
    expect(tabBar.items[2].icon, Icons.people_rounded);
    // The incoming-request badge now lives on Friends, not Profile.
    expect(tabBar.items[2].badgeCount, 2);
    expect(tabBar.items[4].badgeCount, 0);
  });

  testWidgets('selecting the Friends tab clears the incoming-request badge', (
    WidgetTester tester,
  ) async {
    await _pumpShell(
      tester,
      _FakeBackendApiService(incomingFriendRequests: 2),
    );

    var tabBar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));
    expect(tabBar.items[2].badgeCount, 2);

    await _tapTab(tester, 2);

    tabBar = tester.widget<WoodenTabBar>(find.byType(WoodenTabBar));
    expect(tabBar.items[2].badgeCount, 0);
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
