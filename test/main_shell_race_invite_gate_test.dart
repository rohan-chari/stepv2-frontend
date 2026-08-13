import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/screens/race_results_summary_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/widgets/wooden_tab_bar.dart';
import 'package:step_tracker/widgets/app_refresh_indicator.dart';

class _Health extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;
  @override
  Future<StepData> getStepsToday() async =>
      StepData(steps: 100, date: DateTime(2026, 8, 12));

  @override
  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async => const [];
}

class _Background extends BackgroundSyncBootstrapService {
  @override
  Future<void> enableHealthKitBackgroundDelivery() async {}
}

class _Api extends BackendApiService {
  _Api({
    this.invites = const {'resolved': true, 'invites': []},
    this.syncResult = const StepSyncV2Result(kind: StepSyncV2Kind.unsupported),
    this.preflightThrows = false,
    this.raceData = const {
      'active': [],
      'pending': [],
      'completed': [],
      'tournaments': [],
    },
  });
  Map<String, dynamic> invites;
  StepSyncV2Result syncResult;
  bool preflightThrows;
  Map<String, dynamic> raceData;
  int responds = 0;
  int preflightCalls = 0;
  int homeCardCalls = 0;
  int suggestionsCalls = 0;

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async => const {
    'sessionToken': 'session',
    'user': {
      'id': 'me',
      'firstRaceOnboardingSeen': true,
      'tutorialOnboardingSeen': true,
    },
  };

  @override
  Future<StepSyncV2Result> recordStepSyncV2({
    required String identityToken,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
    bool homePull = false,
  }) async => syncResult;
  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async => raceData;
  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) async {
    homeCardCalls++;
    return const {'state': 'EMPTY'};
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      const {
        'id': 'me',
        'firstRaceOnboardingSeen': true,
        'tutorialOnboardingSeen': true,
      };
  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async => const [];
  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => const {'items': []};
  @override
  Future<RaceDiscoverySummary> fetchRaceDiscoverySummary({
    required String identityToken,
  }) async => RaceDiscoverySummary.unsupportedResult;
  @override
  Future<HomeSuggestedRacesRefresh> fetchHomeSuggestedRaces({
    required String identityToken,
  }) async {
    suggestionsCalls++;
    return const HomeSuggestedRacesRefresh();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async => const [];
  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async => const [];
  @override
  Future<Map<String, dynamic>> fetchPublicTournaments({
    required String identityToken,
  }) async => const {'featured': [], 'tournaments': []};
  @override
  Future<Map<String, dynamic>> fetchHomeInvitePreflight({
    required String identityToken,
  }) async {
    preflightCalls++;
    if (preflightThrows) throw const ApiException('offline');
    return invites;
  }

  @override
  Future<Map<String, dynamic>> respondToRaceInvite({
    required String identityToken,
    required String raceId,
    required bool accept,
  }) async {
    responds++;
    invites = const {'resolved': true, 'invites': []};
    return const {};
  }
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
    'auth_first_race_onboarding_seen': true,
    'auth_tutorial_onboarding_seen': true,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    ),
  );
  testWidgets(
    'Home invite X is nonmutating and Races navigation remains available',
    (tester) async {
      final api = _Api(
        invites: {
          'resolved': true,
          'invites': [
            {
              'kind': 'RACE',
              'id': 'race-1',
              'name': 'Lunch Loop',
              'status': 'PENDING',
            },
          ],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: await _auth(),
            healthService: _Health(),
            backendApiService: api,
            backgroundSyncBootstrapService: _Background(),
            forceHomeInviteEligibilityForTesting: true,
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.text('Lunch Loop'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-invite-dismiss')));
      await tester.pump();
      expect(api.responds, 0);
      expect(find.byType(WoodenTabBar), findsOneWidget);
      expect(find.byKey(const Key('main-shell-pages')), findsOneWidget);
      await tester.tap(find.text('Races'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Races'), findsWidgets);
      expect(find.byKey(const Key('main-shell-pages')), findsOneWidget);
    },
  );

  testWidgets('accept answers then performs a fresh preflight', (tester) async {
    final api = _Api(
      invites: {
        'resolved': true,
        'invites': [
          {
            'kind': 'RACE',
            'id': 'race-1',
            'name': 'Lunch Loop',
            'status': 'PENDING',
          },
        ],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: await _auth(),
          healthService: _Health(),
          backendApiService: api,
          backgroundSyncBootstrapService: _Background(),
          forceHomeInviteEligibilityForTesting: true,
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.tap(find.byKey(const Key('home-invite-accept')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(api.responds, 1);
    expect(api.preflightCalls, greaterThanOrEqualTo(2));
    expect(find.byKey(const Key('home-invite-overlay')), findsNothing);
  });

  testWidgets('unsupported or offline invite preflight leaves Home usable', (
    tester,
  ) async {
    final api = _Api(preflightThrows: true);
    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          authService: await _auth(),
          healthService: _Health(),
          backendApiService: api,
          backgroundSyncBootstrapService: _Background(),
          forceHomeInviteEligibilityForTesting: true,
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.byKey(const Key('home-invite-overlay')), findsNothing);
    expect(find.byKey(const Key('main-shell-pages')), findsOneWidget);
  });

  testWidgets(
    'Home cooldown toast uses approved copy and starts no follow-up work',
    (tester) async {
      final api = _Api(
        syncResult: const StepSyncV2Result(
          kind: StepSyncV2Kind.cooldown,
          retryAfterSeconds: 18,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: await _auth(),
            healthService: _Health(),
            backendApiService: api,
            backgroundSyncBootstrapService: _Background(),
            forceHomeInviteEligibilityForTesting: true,
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      api.homeCardCalls = 0;
      api.suggestionsCalls = 0;
      await tester
          .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(
        find.text('You just synced. Try again in 18 seconds.'),
        findsOneWidget,
      );
      expect(api.homeCardCalls, 0);
      expect(api.suggestionsCalls, 0);
    },
  );

  testWidgets(
    'malformed cooldown delay uses safe copy and starts no follow-up work',
    (tester) async {
      final api = _Api(
        syncResult: const StepSyncV2Result(kind: StepSyncV2Kind.cooldown),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: await _auth(),
            healthService: _Health(),
            backendApiService: api,
            backgroundSyncBootstrapService: _Background(),
            forceHomeInviteEligibilityForTesting: true,
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      api.homeCardCalls = 0;
      api.suggestionsCalls = 0;
      await tester
          .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(find.text('You just synced. Try again shortly.'), findsOneWidget);
      expect(api.homeCardCalls, 0);
      expect(api.suggestionsCalls, 0);
    },
  );
}
