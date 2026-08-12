import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/home_race_suggestion.dart';
import 'package:step_tracker/models/race_discovery_summary.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/models/step_sample_data.dart';
import 'package:step_tracker/models/step_sync_v2_result.dart';
import 'package:step_tracker/screens/main_shell.dart';
import 'package:step_tracker/screens/discoverable_identity_flow.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/background_sync_bootstrap_service.dart';
import 'package:step_tracker/services/health_service.dart';
import 'package:step_tracker/services/notification_service.dart';
import 'package:step_tracker/widgets/wooden_tab_bar.dart';

class _Health extends HealthService {
  @override
  Future<bool> restoreHealthAuthState() async => true;

  @override
  Future<StepData> getStepsToday() async =>
      StepData(steps: 1234, date: DateTime(2026, 8, 11));

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

class _Notifications extends NotificationService {
  @override
  Future<bool?> getPermissionState() async => true;

  @override
  Future<bool?> getSystemPermissionState() async => true;

  @override
  Future<String> ensureTokenRegistered(String? authToken) async => 'registered';
}

class _MalformedFriendsHttp extends Fake implements HttpClient {
  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _MalformedFriendsRequest(url);
}

class _MalformedFriendsRequest extends Fake implements HttpClientRequest {
  _MalformedFriendsRequest(this.uri);

  @override
  final Uri uri;
  final _MalformedFriendsHeaders _headers = _MalformedFriendsHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _MalformedFriendsResponse(
    uri.path == '/friends/steps'
        ? jsonEncode({
            'friends': [
              {'id': 'friend-1'},
              7,
            ],
          })
        : '{}',
  );
}

class _MalformedFriendsHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MalformedFriendsResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _MalformedFriendsResponse(this.body);

  final String body;

  @override
  int get statusCode => 200;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShellApi extends BackendApiService {
  _ShellApi({
    this.requiredIdentity = false,
    this.malformedFriends = false,
    this.quickRaceShareCapability = false,
    this.eligibleNextRace = false,
  }) : super(httpClient: malformedFriends ? _MalformedFriendsHttp() : null);

  final bool requiredIdentity;
  final bool malformedFriends;
  final bool quickRaceShareCapability;
  final bool eligibleNextRace;
  final delayedRaceReads = <Completer<Map<String, dynamic>>>[];
  Map<String, dynamic> raceData = _emptyRaces;
  ApiException? responseError;
  int fetchRaceCalls = 0;
  int publicFriendsFetchCalls = 0;

  @override
  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async => {
    'sessionToken': 'session-token',
    'user': {
      'id': 'me',
      'displayName': 'TrailWalker',
      'firstRaceOnboardingSeen': true,
      'tutorialOnboardingSeen': true,
      'nameSetupOnboardingRequired': requiredIdentity,
      'nameSetupCompletedAt': requiredIdentity
          ? null
          : '2026-08-11T12:00:00.000Z',
      'featureFlags': {
        'racesInviteDecisionGateEnabled': true,
        'quickRaceShareAutoFriendEnabled': quickRaceShareCapability,
      },
    },
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
  Future<Map<String, dynamic>> fetchRaces({required String identityToken}) {
    fetchRaceCalls += 1;
    if (delayedRaceReads.isNotEmpty) {
      return delayedRaceReads.removeAt(0).future;
    }
    return Future.value(raceData);
  }

  @override
  Future<Map<String, dynamic>> respondToTournamentInvite({
    required String identityToken,
    required String tournamentId,
    required bool accept,
  }) async {
    if (responseError case final error?) throw error;
    raceData = _emptyRaces;
    return const {};
  }

  @override
  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) async => {
    'state': 'EMPTY',
    if (eligibleNextRace)
      'nextRace': {
        'resolved': true,
        'eligible': true,
        'discoveryEnabled': false,
        'createEnabled': true,
        'openRaces': <Map<String, dynamic>>[],
      },
  };

  @override
  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) {
    if (!malformedFriends) return Future.value(const []);
    publicFriendsFetchCalls += 1;
    return super.fetchFriendsSteps(identityToken: identityToken, date: date);
  }

  @override
  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async =>
      {
        'id': 'me',
        'displayName': 'TrailWalker',
        'incomingFriendRequests': 0,
        'firstRaceOnboardingSeen': true,
        'tutorialOnboardingSeen': true,
        'nameSetupOnboardingRequired': requiredIdentity,
        'nameSetupCompletedAt': requiredIdentity
            ? null
            : '2026-08-11T12:00:00.000Z',
        'featureFlags': {
          'racesInviteDecisionGateEnabled': true,
          'quickRaceShareAutoFriendEnabled': quickRaceShareCapability,
        },
      };

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async => const {
    'coins': 0,
    'equipped': <String, dynamic>{},
    'items': <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> fetchRankedV2({
    required String identityToken,
  }) async => const {};

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
  }) async => const {'featured': []};

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => const {'claimedToday': true};
}

const _emptyRaces = <String, dynamic>{
  'pending': <Map<String, dynamic>>[],
  'active': <Map<String, dynamic>>[],
  'completed': <Map<String, dynamic>>[],
  'tournaments': <Map<String, dynamic>>[],
};

Map<String, dynamic> _inviteData(String name) => {
  ..._emptyRaces,
  'tournaments': [
    {
      'id': 'tournament-${name.toLowerCase()}',
      'name': name,
      'myStatus': 'INVITED',
      'createdAt': '2026-08-11T19:00:00.000Z',
      'matchupDurationDays': 3,
      'creator': {'displayName': 'BracketHost'},
    },
  ],
};

Future<AuthService> _auth({bool requiredIdentity = false}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'provider-user',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'GeneratedOtter88',
    'auth_identity_state_user_id': 'me',
    'auth_identity_supported': true,
    'auth_name_setup_onboarding_required': requiredIdentity,
    if (!requiredIdentity)
      'auth_name_setup_completed_at': '2026-08-11T12:00:00.000Z',
    'auth_races_invite_decision_gate_enabled': true,
    'auth_first_race_onboarding_seen': true,
    'auth_tutorial_onboarding_seen': true,
    'notif_permission_granted': true,
  });
  final auth = AuthService();
  await auth.restoreSession();
  if (requiredIdentity) {
    await auth.syncFromBackendUser(const {
      'id': 'me',
      'displayName': 'GeneratedOtter88',
      'firstName': null,
      'lastName': null,
      'nameSetupOnboardingRequired': true,
      'nameSetupCompletedAt': null,
      'featureFlags': {'racesInviteDecisionGateEnabled': true},
    });
  }
  return auth;
}

Future<_Notifications> _pumpShell(WidgetTester tester, _ShellApi api) async {
  final notifications = _Notifications();
  await tester.pumpWidget(
    MaterialApp(
      home: MainShell(
        authService: await _auth(),
        healthService: _Health(),
        backendApiService: api,
        backgroundSyncBootstrapService: _Background(),
        notificationService: notifications,
      ),
    ),
  );
  await _settle(tester);
  return notifications;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 18; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _tab(int index) => find
    .descendant(of: find.byType(WoodenTabBar), matching: find.byType(InkWell))
    .at(index);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'America/New_York',
        );
  });

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.app',
      version: '3.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'required new account renders identity before health onboarding',
    (tester) async {
      final auth = await _auth(requiredIdentity: true);
      expect(auth.requiresDiscoverableIdentityOnboarding, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: MainShell(
            authService: auth,
            healthService: _Health(),
            backendApiService: _ShellApi(requiredIdentity: true),
            backgroundSyncBootstrapService: _Background(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DiscoverableIdentityFlow), findsOneWidget);
      expect(find.text('HELP FRIENDS FIND YOU'), findsOneWidget);
      expect(find.text('CONNECT YOUR STEPS'), findsNothing);
      expect(find.byType(WoodenTabBar), findsNothing);
    },
  );

  testWidgets(
    'malformed public friends payload keeps real Home on normal race copy',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _ShellApi(
        malformedFriends: true,
        quickRaceShareCapability: true,
        eligibleNextRace: true,
      );

      await _pumpShell(tester, api);

      expect(api.publicFriendsFetchCalls, greaterThan(0));
      expect(find.byKey(const Key('home-next-race-section')), findsOneWidget);
      expect(find.text('START YOUR OWN RACE'), findsOneWidget);
      expect(find.text('START A RACE'), findsOneWidget);
      expect(find.text('RACE WITH YOUR FRIENDS'), findsNothing);
      expect(find.text('CREATE & SHARE'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tap entry and full swipe block while partial swipe stays opaque',
    (tester) async {
      final api = _ShellApi()..raceData = _inviteData('Tap Invite');
      await _pumpShell(tester, api);

      await tester.tap(_tab(1));
      await _settle(tester);
      expect(find.text('Tap Invite'), findsOneWidget);

      api.responseError = const ApiException('offline', statusCode: 503);
      await tester.tap(find.byKey(const Key('races-gate-accept')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('races-gate-answer-home')));
      await _settle(tester);
      api.raceData = _inviteData('Swipe Invite');

      final pageView = find.byKey(const Key('main-shell-pages'));
      final size = tester.getSize(pageView);
      final shellPages = tester.widget<PageView>(pageView);
      final topLeft = tester.getTopLeft(pageView);
      final partialSwipe = await tester.startGesture(
        topLeft + Offset(size.width - 12, 50),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await partialSwipe.moveBy(
        const Offset(-24, 0),
        timeStamp: const Duration(milliseconds: 32),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await partialSwipe.moveBy(
        Offset(-(size.width * 0.42 - 24), 0),
        timeStamp: const Duration(milliseconds: 48),
      );
      await tester.pump();
      expect(shellPages.controller!.page, inInclusiveRange(0.25, 0.49));
      expect(find.text('PUBLIC RACES (0)'), findsNothing);
      expect(find.text('Swipe Invite'), findsNothing);
      await partialSwipe.cancel();
      shellPages.controller!.jumpToPage(0);
      await tester.pump();
      await tester.flingFrom(
        topLeft + Offset(size.width - 12, 50),
        Offset(-size.width * 0.9, 0),
        1200,
      );
      await _settle(tester);
      expect(find.text('Swipe Invite'), findsOneWidget);
    },
  );

  testWidgets(
    'decision blocks tabs and Android back; action error can exit Home',
    (tester) async {
      final api = _ShellApi()
        ..raceData = _inviteData('Locked Invite')
        ..responseError = const ApiException(
          'Network unavailable',
          statusCode: 503,
        );
      await _pumpShell(tester, api);
      await tester.tap(_tab(1));
      await _settle(tester);

      await tester.tap(_tab(2));
      await _settle(tester);
      expect(
        tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).currentIndex,
        1,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Locked Invite'), findsOneWidget);

      await tester.tap(find.byKey(const Key('races-gate-accept')));
      await tester.pump();
      expect(find.text('Network unavailable'), findsOneWidget);
      await tester.tap(find.byKey(const Key('races-gate-answer-home')));
      await _settle(tester);
      expect(
        tester.widget<WoodenTabBar>(find.byType(WoodenTabBar)).currentIndex,
        0,
      );
    },
  );

  testWidgets('stale gate epoch cannot replace a newer entry result', (
    tester,
  ) async {
    final api = _ShellApi();
    final notifications = await _pumpShell(tester, api);
    final oldRead = Completer<Map<String, dynamic>>();
    api.delayedRaceReads.add(oldRead);

    await tester.tap(_tab(1));
    await _settle(tester);
    expect(api.delayedRaceReads, isEmpty);
    expect(find.byKey(const Key('races-invite-gate-status')), findsOneWidget);

    notifications.pendingAction.value = const NotificationAction(
      route: NotificationRoute.home,
    );
    await _settle(tester);
    final newRead = Completer<Map<String, dynamic>>();
    api.delayedRaceReads.add(newRead);
    await tester.tap(_tab(1));
    await tester.pump(const Duration(milliseconds: 300));

    oldRead.complete(_inviteData('Old Epoch'));
    await tester.pump();
    expect(find.text('Old Epoch'), findsNothing);
    newRead.complete(_inviteData('New Epoch'));
    await _settle(tester);
    expect(find.text('New Epoch'), findsOneWidget);
  });
}
