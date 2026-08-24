import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/loadable.dart';
import 'package:step_tracker/models/step_data.dart';
import 'package:step_tracker/screens/race_results_summary_screen.dart';
import 'package:step_tracker/screens/settings_screen.dart';
import 'package:step_tracker/screens/tabs/home_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/tutorial/tutorial_preview_data.dart';
import 'package:step_tracker/tutorial/tutorial_real_screens.dart';
import 'package:step_tracker/tutorial/tutorial_screen.dart';
import 'package:step_tracker/widgets/invite_code_sheet.dart';

class _UiApi extends BackendApiService {
  _UiApi({
    this.redeemResult = const {'attributed': false, 'reason': 'invalid_code'},
  });

  final Map<String, dynamic> redeemResult;

  @override
  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async => const {'claimedToday': true};

  @override
  Future<Map<String, dynamic>> redeemReferralCode({
    required String identityToken,
    required String code,
  }) async => redeemResult;
}

class _FriendsHttpClient extends Fake implements HttpClient {
  _FriendsHttpClient(this.body);

  final String body;

  @override
  set connectionTimeout(Duration? value) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FriendsRequest(url, body);
}

class _FriendsRequest extends Fake implements HttpClientRequest {
  _FriendsRequest(this.uri, this.body);

  @override
  final Uri uri;
  final String body;
  final _FriendsHeaders _headers = _FriendsHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => _FriendsResponse(body);
}

class _FriendsHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _FriendsResponse extends Stream<List<int>> implements HttpClientResponse {
  _FriendsResponse(this.body);

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

Future<AuthService> _auth(BackendApiService api) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'identity',
    'auth_session_token': 'session',
    'auth_user_identifier': 'apple-user',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'auth_profile_photo_url': 'https://example.test/photo.png',
  });
  final auth = AuthService(backendApiService: api);
  await auth.restoreSession();
  return auth;
}

const _quickRaceCard = <String, dynamic>{
  'state': 'EMPTY',
  'nextRace': {
    'resolved': true,
    'eligible': true,
    'discoveryEnabled': false,
    'createEnabled': true,
    'openRaces': [],
  },
};

List<Map<String, dynamic>> _friends(int count) => List.generate(
  count,
  (index) => {'id': 'friend-$index', 'displayName': 'Friend $index'},
);

Widget _quickRaceHome({
  required AuthService auth,
  required BackendApiService api,
  required List<Map<String, dynamic>> friends,
  Loadable<List<Map<String, dynamic>>>? friendsState,
  Map<String, dynamic>? raceCard = _quickRaceCard,
  VoidCallback? onStart,
  bool tutorial = false,
  double textScale = 1,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: HomeTab(
      stepData: StepData(steps: 1200, date: DateTime(2026, 8, 11)),
      isLoading: false,
      error: null,
      healthAuthorized: true,
      notificationsState: true,
      displayName: 'Walker',
      authService: auth,
      backendApiService: api,
      onRefresh: () async {},
      onEnableHealth: () {},
      onEnableNotifications: () {},
      onDisplayNameChanged: () {},
      friendsSteps: friends,
      friendsStepsState: friendsState,
      raceCard: raceCard,
      onStartQuickRace: onStart,
      isTutorialPreview: tutorial,
    ),
  ),
);

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
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test(
    'friends steps decoder eagerly rejects one malformed list element',
    () async {
      final api = BackendApiService(
        httpClient: _FriendsHttpClient(
          jsonEncode({
            'friends': [
              {'id': 'friend-1'},
              7,
            ],
          }),
        ),
      );

      await expectLater(
        api.fetchFriendsSteps(identityToken: 'token', date: '2026-08-12'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  testWidgets(
    'Home derives permanent share-first copy from successful 0-4 friends',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _UiApi();
      final auth = await _auth(api);
      var starts = 0;

      for (final count in [0, 4]) {
        final friends = _friends(count);
        await tester.pumpWidget(
          _quickRaceHome(
            auth: auth,
            api: api,
            friends: friends,
            friendsState: Loadable.success(friends),
            onStart: () => starts++,
          ),
        );
        await tester.pump();
        expect(find.text('CREATE A RACE'), findsOneWidget);
        expect(find.text('RACE WITH YOUR FRIENDS'), findsOneWidget);
        expect(
          find.text(
            'Create a race, then send the link to your friends. Your race starts when someone joins.',
          ),
          findsOneWidget,
        );
        expect(find.text('CREATE & SHARE'), findsOneWidget);
        expect(find.text('START YOUR OWN RACE'), findsNothing);
      }

      await tester.tap(find.byKey(const Key('home-start-a-race')));
      expect(starts, 1);

      final five = _friends(5);
      await tester.pumpWidget(
        _quickRaceHome(
          auth: auth,
          api: api,
          friends: five,
          friendsState: Loadable.success(five),
        ),
      );
      await tester.pump();
      expect(find.text('START YOUR OWN RACE'), findsOneWidget);
      expect(
        find.text("Pick a length. We'll help find other walkers."),
        findsOneWidget,
      );
      expect(find.text('START A RACE'), findsOneWidget);
      expect(find.text('RACE WITH YOUR FRIENDS'), findsNothing);
    },
  );

  testWidgets(
    'Home uses normal copy for unknown, refreshing, and failed friends',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _UiApi();
      final auth = await _auth(api);
      final cached = _friends(2);
      final states = <Loadable<List<Map<String, dynamic>>>?>[
        null,
        const Loadable.initial(),
        const Loadable.loading(),
        Loadable.refreshing(cached),
        const Loadable.error('malformed friends payload'),
      ];

      for (final state in states) {
        await tester.pumpWidget(
          _quickRaceHome(
            auth: auth,
            api: api,
            friends: state?.data ?? const [],
            friendsState: state,
          ),
        );
        await tester.pump();
        expect(find.text('START YOUR OWN RACE'), findsOneWidget);
        expect(find.text('START A RACE'), findsOneWidget);
        expect(find.text('RACE WITH YOUR FRIENDS'), findsNothing);
      }

      final cleanedEnvelope = await _auth(api);
      cleanedEnvelope.applyBackendUser({
        'featureFlags': const {},
      }, authoritative: true);
      await tester.pumpWidget(
        _quickRaceHome(
          auth: cleanedEnvelope,
          api: api,
          friends: const [],
          friendsState: const Loadable.success([]),
        ),
      );
      await tester.pump();
      expect(find.text('RACE WITH YOUR FRIENDS'), findsOneWidget);
      expect(find.text('CREATE & SHARE'), findsOneWidget);
    },
  );

  testWidgets(
    'share-first respects Open Races, tutorial suppression, and compact layout',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _UiApi();
      final auth = await _auth(api);

      await tester.pumpWidget(
        _quickRaceHome(
          auth: auth,
          api: api,
          friends: const [],
          friendsState: const Loadable.success([]),
          textScale: 1.3,
        ),
      );
      await tester.pump();
      expect(find.text('RACE WITH YOUR FRIENDS'), findsOneWidget);
      expect(find.text('CREATE & SHARE'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _quickRaceHome(
          auth: auth,
          api: api,
          friends: const [],
          friendsState: const Loadable.success([]),
          raceCard: const {
            'state': 'EMPTY',
            'nextRace': {
              'resolved': true,
              'eligible': true,
              'discoveryEnabled': true,
              'createEnabled': false,
              'openRaces': [
                {
                  'id': 'race-1',
                  'name': 'Weekend Sprint',
                  'participantCount': 2,
                },
              ],
            },
          },
        ),
      );
      await tester.pump();
      expect(find.text('OPEN RACES'), findsOneWidget);
      expect(find.text('RACE WITH YOUR FRIENDS'), findsNothing);
      expect(find.text('CREATE & SHARE'), findsNothing);

      await tester.pumpWidget(
        _quickRaceHome(
          auth: auth,
          api: api,
          friends: const [],
          friendsState: const Loadable.success([]),
          tutorial: true,
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('home-next-race-section')), findsNothing);
      expect(find.text('RACE WITH YOUR FRIENDS'), findsNothing);
    },
  );

  testWidgets('TutorialRealHost suppresses the Home Next Race section', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = TutorialPreviewAuthService();

    await tester.pumpWidget(
      MaterialApp(
        home: TutorialRealHost(
          page: TutorialMockPage.home,
          keys: const {},
          authService: auth,
          api: TutorialPreviewBackendApiService(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('home-next-race-section')), findsNothing);
    expect(find.text('RACE WITH YOUR FRIENDS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home renders combined next-race state and tutorial suppresses it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _UiApi();
      final auth = await _auth(api);
      var inviteSkipped = false;
      const combinedCard = <String, dynamic>{
        'state': 'EMPTY',
        'nextRace': {
          'resolved': true,
          'eligible': true,
          'discoveryEnabled': true,
          'createEnabled': true,
          'openRaces': [
            {'id': 'race-1', 'name': 'Weekend Sprint', 'participantCount': 2},
          ],
        },
      };
      Widget home({
        bool tutorial = false,
        Map<String, dynamic>? raceCard = combinedCard,
      }) => MaterialApp(
        home: HomeTab(
          stepData: StepData(steps: 1200, date: DateTime(2026, 8, 11)),
          isLoading: false,
          error: null,
          healthAuthorized: true,
          notificationsState: true,
          displayName: 'Walker',
          authService: auth,
          backendApiService: api,
          onRefresh: () async {},
          onEnableHealth: () {},
          onEnableNotifications: () {},
          onDisplayNameChanged: () {},
          friendsSteps: const [],
          showInviteCodePrompt: true,
          onEnterInviteCode: () {},
          onSkipInviteCode: () => inviteSkipped = true,
          isTutorialPreview: tutorial,
          raceCard: raceCard,
        ),
      );

      await tester.pumpWidget(home());
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('home-next-race-section')), findsOneWidget);
      expect(find.byKey(const Key('home-enter-invite-code')), findsOneWidget);
      expect(find.text('START A RACE'), findsOneWidget);
      expect(find.text('Weekend Sprint'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('home-enter-invite-code'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('home-next-race-section'))).dy,
        ),
      );
      await tester.tap(find.byKey(const Key('home-skip-invite-code')));
      expect(inviteSkipped, isTrue);

      await tester.pumpWidget(home(tutorial: true));
      await tester.pump();
      expect(find.byKey(const Key('home-next-race-section')), findsNothing);
      expect(find.byKey(const Key('home-enter-invite-code')), findsNothing);

      await tester.pumpWidget(
        home(
          raceCard: const {
            'state': 'EMPTY',
            'nextRace': {
              'resolved': true,
              'eligible': true,
              'discoveryEnabled': true,
              'createEnabled': false,
              'openRaces': [
                {
                  'id': 'race-1',
                  'name': 'Weekend Sprint',
                  'participantCount': 2,
                },
              ],
            },
          },
        ),
      );
      await tester.pump();
      expect(find.text('OPEN RACES'), findsOneWidget);
      expect(find.text('CREATE A RACE'), findsNothing);
      expect(find.text('START A RACE'), findsNothing);
      expect(find.text('OR JOIN ONE'), findsNothing);

      await tester.pumpWidget(
        home(
          raceCard: const {
            'state': 'EMPTY',
            'nextRace': {
              'resolved': true,
              'eligible': true,
              'discoveryEnabled': false,
              'createEnabled': true,
              'openRaces': [],
            },
          },
        ),
      );
      await tester.pump();
      expect(find.text('START A RACE'), findsOneWidget);
      expect(find.text('OR JOIN ONE'), findsNothing);
      expect(find.text('OPEN RACES'), findsNothing);

      await tester.pumpWidget(
        home(
          raceCard: const {
            'state': 'EMPTY',
            'nextRace': {
              'resolved': true,
              'eligible': false,
              'discoveryEnabled': true,
              'createEnabled': true,
              'openRaces': [],
            },
          },
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('home-next-race-section')), findsNothing);

      await tester.pumpWidget(
        home(raceCard: const {'state': 'EMPTY', 'nextRace': null}),
      );
      await tester.pump();
      expect(find.byKey(const Key('home-next-race-section')), findsNothing);
    },
  );

  testWidgets(
    'eligible results use primary next-race action and secondary NICE',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RaceResultsSummaryScreen(
            canStartNextRace: true,
            races: const [
              {'id': 'done-1', 'name': 'Done', 'participantCount': 2},
            ],
          ),
        ),
      );
      expect(find.text('START YOUR NEXT RACE'), findsOneWidget);
      expect(find.byKey(const Key('results-nice-secondary')), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: RaceResultsSummaryScreen(
            races: const [
              {'id': 'done-1', 'name': 'Done', 'participantCount': 2},
            ],
          ),
        ),
      );
      expect(find.text('START YOUR NEXT RACE'), findsNothing);
      expect(find.text('CONTINUE'), findsOneWidget);
      expect(find.byKey(const Key('results-nice-secondary')), findsNothing);
    },
  );

  testWidgets('joining one discovery row leaves the other row enabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _UiApi();
    final auth = await _auth(api);
    final firstJoin = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeTab(
          stepData: StepData(steps: 1200, date: DateTime(2026, 8, 11)),
          isLoading: false,
          error: null,
          healthAuthorized: true,
          notificationsState: true,
          displayName: 'Walker',
          authService: auth,
          backendApiService: api,
          onRefresh: () async {},
          onEnableHealth: () {},
          onEnableNotifications: () {},
          onDisplayNameChanged: () {},
          friendsSteps: const [],
          onJoinDiscoveredRace: (id) =>
              id == 'race-1' ? firstJoin.future : Future.value(),
          raceCard: const {
            'state': 'EMPTY',
            'nextRace': {
              'resolved': true,
              'eligible': true,
              'discoveryEnabled': true,
              'createEnabled': false,
              'openRaces': [
                {'id': 'race-1', 'name': 'First', 'participantCount': 2},
                {'id': 'race-2', 'name': 'Second', 'participantCount': 3},
              ],
            },
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('home-join-race-1')));
    await tester.pump();

    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('home-join-race-1')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('home-join-race-2')))
          .onPressed,
      isNotNull,
    );
    firstJoin.complete();
    await tester.pump();
  });

  testWidgets(
    'invalid invite code keeps the shared sheet open with inline error',
    (tester) async {
      final api = _UiApi();
      final auth = await _auth(api);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InviteCodeSheet(authService: auth, backendApiService: api),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('invite-code-field')),
        'BARA-NOPE',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('invite-code-apply')));
      await tester.pump();
      expect(find.byType(InviteCodeSheet), findsOneWidget);
      expect(find.text("That code doesn't look right."), findsOneWidget);
    },
  );

  testWidgets('shared invite sheet pastes a referral-aware link', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.getData'
              ? {
                  'text':
                      'https://steptracker-api.org/r/race-token?ref=BARA-FRND',
                }
              : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final api = _UiApi();
    final auth = await _auth(api);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InviteCodeSheet(authService: auth, backendApiService: api),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('invite-code-paste')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('invite-code-field')))
          .controller!
          .text,
      'BARA-FRND',
    );
  });

  testWidgets('shared invite sheet closes with success and terminal outcomes', (
    tester,
  ) async {
    for (final result in <Map<String, dynamic>>[
      {'attributed': true},
      {'attributed': false, 'reason': 'already_raced'},
    ]) {
      final api = _UiApi(redeemResult: result);
      final auth = await _auth(api);
      InviteCodeOutcome? outcome;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                outcome = await showInviteCodeSheet(
                  context: context,
                  authService: auth,
                  backendApiService: api,
                );
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('invite-code-field')),
        'BARA-FRND',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('invite-code-apply')));
      await tester.pumpAndSettle();
      expect(outcome?.attributed, result['attributed']);
      expect(outcome?.terminal, result['reason'] == 'already_raced');
      expect(find.byType(InviteCodeSheet), findsNothing);
    }
  });

  testWidgets('Settings keeps a permanent invite-code entry', (tester) async {
    final api = _UiApi();
    final auth = await _auth(api);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          authService: auth,
          backendApiService: api,
          onSettingsChanged: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('settings-enter-invite-code')), findsOneWidget);
  });
}
