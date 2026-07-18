import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';

// TR-201/204: a share link to a TEAM race must ask for a side before joining
// (the join API requires `team`), and a link to an ALREADY-STARTED team race
// shows the friendly "race already started" state instead of joining.
// Individual share links keep their existing one-call join (TR-705).

class _FakeHealthService extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;

  @override
  Future<StepData> getStepsToday() async =>
      StepData(steps: 1234, date: DateTime(2026, 6, 1));

  @override
  Future<List<StepSampleData>> getHourlySteps({
    required DateTime startTime,
    required DateTime endTime,
  }) async => const [];
}

class _FakeBootstrap extends BackgroundSyncBootstrapService {
  @override
  Future<void> enableHealthKitBackgroundDelivery() async {}
}

class _ShareApi extends BackendApiService {
  _ShareApi({required this.preview});

  final Map<String, dynamic> preview;
  String? joinedWithTeam;
  bool plainJoinCalled = false;

  @override
  Future<Map<String, dynamic>> fetchSharedRace({
    required String token,
    String? identityToken,
  }) async => preview;

  @override
  Future<Map<String, dynamic>> joinRaceByShareToken({
    required String identityToken,
    required String token,
    bool onboarding = false,
  }) async {
    plainJoinCalled = true;
    return {'raceId': preview['id']};
  }

  @override
  Future<Map<String, dynamic>> joinRaceByShareTokenOnTeam({
    required String identityToken,
    required String token,
    required String team,
    bool onboarding = false,
  }) async {
    joinedWithTeam = team;
    return {'raceId': preview['id']};
  }

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async => {
    'sessionToken': authToken,
    'user': {'firstRaceOnboardingSeen': true, 'tutorialOnboardingSeen': true},
  };

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
  }) async => const {'state': 'EMPTY'};

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchMe({
    required String identityToken,
  }) async => const {
    'displayName': 'Trail Walker',
    'firstRaceOnboardingSeen': true,
    'tutorialOnboardingSeen': true,
  };

  @override
  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async => const {
    'pending': <Map<String, dynamic>>[],
    'active': <Map<String, dynamic>>[],
    'completed': <Map<String, dynamic>>[],
  };

  @override
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async => const [];

  @override
  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async => const {
    'friends': <Map<String, dynamic>>[],
    'incoming': <Map<String, dynamic>>[],
    'outgoing': <Map<String, dynamic>>[],
  };
}

Map<String, dynamic> _teamPreview({String status = 'PENDING'}) => {
      'id': 'race-shared',
      'name': 'Shared Team Race',
      'status': status,
      'isTeamRace': true,
      'teamSize': 2,
      'teamAName': 'Red',
      'teamBName': 'Blue',
      'teams': {
        'teamA': {'memberCount': 2},
        'teamB': {'memberCount': 1},
      },
    };

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_first_race_onboarding_seen': true,
    'auth_tutorial_onboarding_seen': true,
    'auth_pending_share_token': 'share-abc',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpShell(WidgetTester tester, _ShareApi api) async {
  final authService = await _authService();
  await tester.pumpWidget(
    MaterialApp(
      home: MainShell(
        authService: authService,
        healthService: _FakeHealthService(),
        backendApiService: api,
        backgroundSyncBootstrapService: _FakeBootstrap(),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TR-201: a PENDING team share link asks for a side and joins it',
      (tester) async {
    final api = _ShareApi(preview: _teamPreview());
    await _pumpShell(tester, api);

    expect(find.text('PICK YOUR SIDE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('side-pick-B')));
    await _settle(tester);

    expect(api.joinedWithTeam, 'TEAM_B');
    expect(api.plainJoinCalled, isFalse);
  });

  testWidgets('TR-204: a share link to an ACTIVE team race never joins',
      (tester) async {
    final api = _ShareApi(preview: _teamPreview(status: 'ACTIVE'));
    await _pumpShell(tester, api);

    expect(find.text('PICK YOUR SIDE'), findsNothing);
    expect(api.joinedWithTeam, isNull);
    expect(api.plainJoinCalled, isFalse);
  });

  testWidgets('TR-705: an individual share link joins directly, no picker',
      (tester) async {
    final api = _ShareApi(
      preview: const {
        'id': 'race-shared',
        'name': 'Shared Solo Race',
        'status': 'PENDING',
      },
    );
    await _pumpShell(tester, api);

    expect(find.text('PICK YOUR SIDE'), findsNothing);
    expect(api.plainJoinCalled, isTrue);
    expect(api.joinedWithTeam, isNull);
  });
}
