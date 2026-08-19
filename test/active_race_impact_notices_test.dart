import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/app_route_observer.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/models/race_resolution_status.dart';
import 'package:step_tracker/widgets/powerup_reveal_modal.dart';
import 'package:step_tracker/widgets/item_slot.dart';

class _WireResponse {
  const _WireResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _WireRequestRecord {
  _WireRequestRecord(this.method, this.uri);

  final String method;
  final Uri uri;
  final StringBuffer body = StringBuffer();
  final Map<String, String> headers = {};
}

class _WireHeaders implements HttpHeaders {
  _WireHeaders(this.record);

  final _WireRequestRecord record;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    record.headers[name] = value.toString();
  }

  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _WireHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _WireHttpResponse(this.script);

  final _WireResponse script;

  @override
  int get statusCode => script.statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([utf8.encode(script.body)]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WireHttpRequest implements HttpClientRequest {
  _WireHttpRequest(this.record, this.script);

  final _WireRequestRecord record;
  final _WireResponse script;

  @override
  late final HttpHeaders headers = _WireHeaders(record);

  @override
  void write(Object? object) => record.body.write(object);

  @override
  Future<HttpClientResponse> close() async => _WireHttpResponse(script);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WireHttpClient implements HttpClient {
  _WireHttpClient(this.scripts);

  final List<_WireResponse> scripts;
  final List<_WireRequestRecord> requests = [];
  int _index = 0;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final record = _WireRequestRecord(method, url);
    requests.add(record);
    final script = scripts[_index];
    _index += 1;
    return _WireHttpRequest(record, script);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ActiveImpactApi extends BackendApiService {
  _ActiveImpactApi({
    this.raceStatus = 'ACTIVE',
    this.activeNoticeError,
    this.includeHeldPowerup = false,
    this.heldPowerupType = 'SECOND_WIND',
    this.useResult = const <String, dynamic>{},
    this.starterRewardEligible = false,
    List<ActiveImpactNoticesResult>? responses,
  }) : responses = responses ?? <ActiveImpactNoticesResult>[];

  final String raceStatus;
  final Object? activeNoticeError;
  final bool includeHeldPowerup;
  final String heldPowerupType;
  final Map<String, dynamic> useResult;
  final bool starterRewardEligible;
  final List<ActiveImpactNoticesResult> responses;
  int activeNoticeFetches = 0;
  int legacyNoticeFetches = 0;
  int progressFetches = 0;
  final List<String> acknowledgedNoticeIds = [];
  final List<String> acknowledgedReceiptIds = [];
  final List<RaceResolutionState> resolutionStates = [];
  Completer<void>? nextProgressGate;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => {
    'id': raceId,
    'name': 'Impact Sprint',
    'status': raceStatus,
    'targetSteps': 100000,
    'maxDurationDays': 7,
    'buyInAmount': 0,
    'potCoins': 0,
    'heldPotCoins': 0,
    'projectedPotCoins': 0,
    'myStatus': 'ACCEPTED',
    'isCreator': false,
    'powerupsEnabled': false,
    'endsAt': '2026-12-10T12:00:00.000Z',
    'participants': const [
      {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
      {'userId': 'user-2', 'displayName': 'Hill Climber', 'status': 'ACCEPTED'},
    ],
  };

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    progressFetches += 1;
    final gate = nextProgressGate;
    nextProgressGate = null;
    if (gate != null) await gate.future;
    return {
      // Existing completed-screen harnesses keep this ACTIVE to avoid the
      // legacy `_loadProgress` -> `_loadDetails` terminal refresh loop; the
      // detail payload remains the authoritative route state under test.
      'status': raceStatus == 'COMPLETED' ? 'ACTIVE' : raceStatus,
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': 42000,
          'finishedAt': null,
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'totalSteps': 38000,
          'finishedAt': null,
        },
      ],
      'powerupData': {
        'enabled': includeHeldPowerup,
        'inventory': [
          if (includeHeldPowerup)
            {
              'id': 'held-second-wind',
              'type': heldPowerupType,
              'rarity': 'COMMON',
              'status': 'HELD',
              'upgradeLevel': 0,
            },
        ],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': const [],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async => {
    'messages': kind == 'SYSTEM'
        ? const [
            {
              'id': 'impact:final-leech',
              'eventType': 'POWERUP_IMPACT',
              'powerupType': 'LEECH',
              'body': 'Leech changed your final score by −430 steps.',
              'createdAt': '2026-08-19T17:00:00.000Z',
            },
          ]
        : const [],
  };

  @override
  Future<RaceMessageStreamsResult> fetchRaceMessageStreams({
    required String identityToken,
    required String raceId,
    required bool includeUser,
    int limit = 50,
  }) async => RaceMessageStreamsResult.unsupported;

  @override
  Future<Map<String, dynamic>> markRaceChatRead({
    required String identityToken,
    required String raceId,
  }) async => const {'marked': true};

  @override
  Future<List<Map<String, dynamic>>> fetchPrivateRaceImpactFeed({
    required String identityToken,
    required String raceId,
  }) async => const [
    {
      'id': 'impact:final-leech',
      'eventType': 'POWERUP_IMPACT',
      'powerupType': 'LEECH',
      'body': 'Leech changed your final score by −430 steps.',
      'createdAt': '2026-08-19T17:00:00.000Z',
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> fetchRaceImpactNotices({
    required String identityToken,
    required String raceId,
  }) async {
    legacyNoticeFetches += 1;
    return const [
      {'id': 'legacy', 'powerupType': 'LEECH', 'deltaSteps': -430},
    ];
  }

  @override
  Future<ActiveImpactNoticesResult> fetchActiveRaceImpactNotices({
    required String identityToken,
    required String raceId,
  }) async {
    activeNoticeFetches += 1;
    final error = activeNoticeError;
    if (error != null) throw error;
    if (responses.isEmpty) return ActiveImpactNoticesResult.empty;
    return responses.removeAt(0);
  }

  @override
  Future<bool> acknowledgeActiveRaceImpactNotice({
    required String identityToken,
    required String raceId,
    required String noticeId,
  }) async {
    acknowledgedNoticeIds.add(noticeId);
    return true;
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => const {'items': []};

  @override
  Future<Map<String, dynamic>> usePowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    String? targetUserId,
    String? targetDirection,
    String? targetEffectId,
    int upgradeLevel = 0,
  }) async => {
    'result': useResult,
    'activeImpactReceipt': {'id': 'receipt-1', 'raceId': raceId},
  };

  @override
  Future<Map<String, dynamic>> fetchStarterReward({
    required String identityToken,
  }) async => {
    'eligible': starterRewardEligible,
    'claimed': false,
    'amount': 100,
    'raceId': null,
  };

  @override
  Future<Map<String, dynamic>> claimStarterReward({
    required String identityToken,
  }) async => const {'granted': true, 'coins': 520};

  @override
  Future<bool> acknowledgeActiveImpactReceipt({
    required String identityToken,
    required String raceId,
    required String receiptId,
  }) async {
    acknowledgedReceiptIds.add(receiptId);
    return true;
  }

  @override
  Future<RaceResolutionStatus> fetchRaceResolutionStatus({
    required String identityToken,
    required String jobId,
    required int generation,
  }) async {
    final state = resolutionStates.isEmpty
        ? RaceResolutionState.succeeded
        : resolutionStates.removeAt(0);
    return RaceResolutionStatus(state);
  }
}

Future<AuthService> _auth({bool onboardingV2 = false}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 420,
    'auth_held_coins': 0,
    'auth_onboarding_v2_enabled': onboardingV2,
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

ActiveImpactNoticesResult _notices(List<Map<String, dynamic>> rows) =>
    ActiveImpactNoticesResult(notices: rows);

Future<void> _pumpRace(
  WidgetTester tester,
  _ActiveImpactApi api, {
  bool onboardingV2 = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [appRouteObserver],
      home: RaceDetailScreen(
        authService: await _auth(onboardingV2: onboardingV2),
        raceId: 'race-impact',
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _tearDownScreen(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

Future<void> _backgroundAndResume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

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
      packageName: 'com.example.bara',
      version: '2.3.9',
      buildNumber: '239',
      buildSignature: '',
    );
  });

  test('advertises active-impact capability on iOS and Android', () {
    for (final isIos in [true, false]) {
      final features = BackendApiService.clientFeaturesHeaderForPlatform(
        isIos: isIos,
        adsSupported: isIos,
        racePayoutDoubleSupported: false,
      ).split(',');
      expect(features, contains('active_impact_notices_v1'));
    }
  });

  test(
    'active-impact service reads the locked 200 and 202 wire shapes',
    () async {
      final http = _WireHttpClient([
        _WireResponse(
          200,
          jsonEncode({
            'notices': [
              {
                'id': 'notice-wire',
                'powerupType': 'LEECH',
                'deltaSteps': -15,
                'valueStatus': 'SYNCED_SNAPSHOT',
                'resolvedAt': '2026-08-19T16:30:00.000Z',
              },
            ],
          }),
        ),
        _WireResponse(
          202,
          jsonEncode({
            'notices': const [],
            'resolution': {
              'state': 'PENDING',
              'jobId': 'job-wire',
              'generation': 7,
              'retryAfterMs': 500,
            },
          }),
        ),
      ]);
      final api = BackendApiService(httpClient: http);

      final ready = await api.fetchActiveRaceImpactNotices(
        identityToken: 'token',
        raceId: 'race/with space',
      );
      final pending = await api.fetchActiveRaceImpactNotices(
        identityToken: 'token',
        raceId: 'race/with space',
      );

      expect(ready.notices.single['id'], 'notice-wire');
      expect(ready.isPending, isFalse);
      expect(pending.isPending, isTrue);
      expect(pending.jobId, 'job-wire');
      expect(pending.generation, 7);
      expect(pending.retryAfterMs, 500);
      expect(http.requests, hasLength(2));
      expect(http.requests.first.method, 'GET');
      expect(
        http.requests.first.uri.path,
        '/races/race%2Fwith%20space/active-impact-notices',
      );
    },
  );

  test(
    'active-impact service degrades malformed/404 and uses exact ack paths',
    () async {
      final http = _WireHttpClient([
        const _WireResponse(200, '{"notices":null}'),
        const _WireResponse(404, '{}'),
        const _WireResponse(200, '{"acknowledged":true}'),
        const _WireResponse(409, '{}'),
      ]);
      final api = BackendApiService(httpClient: http);

      final malformed = await api.fetchActiveRaceImpactNotices(
        identityToken: 'token',
        raceId: 'race-1',
      );
      final absent = await api.fetchActiveRaceImpactNotices(
        identityToken: 'token',
        raceId: 'race-1',
      );
      final noticeAck = await api.acknowledgeActiveRaceImpactNotice(
        identityToken: 'token',
        raceId: 'race-1',
        noticeId: 'notice/1',
      );
      final receiptAck = await api.acknowledgeActiveImpactReceipt(
        identityToken: 'token',
        raceId: 'race-1',
        receiptId: 'receipt/1',
      );

      expect(malformed.notices, isEmpty);
      expect(absent.notices, isEmpty);
      expect(noticeAck, isTrue);
      expect(receiptAck, isFalse);
      expect(http.requests[2].method, 'POST');
      expect(
        http.requests[2].uri.path,
        '/races/race-1/active-impact-notices/notice%2F1/acknowledge',
      );
      expect(
        http.requests[3].uri.path,
        '/races/race-1/active-impact-receipts/receipt%2F1/acknowledge',
      );
    },
  );

  testWidgets(
    'active race open shows a synced-step impact and acks dismissal',
    (tester) async {
      final api = _ActiveImpactApi(
        responses: [
          _notices(const [
            {
              'id': 'notice-1',
              'powerupType': 'LEECH',
              'deltaSteps': -426,
              'valueStatus': 'SYNCED_SNAPSHOT',
              'resolvedAt': '2026-08-19T16:30:00.000Z',
            },
          ]),
        ],
      );

      await _pumpRace(tester, api);

      expect(find.text('Leech drained 426 synced steps'), findsOneWidget);
      expect(api.activeNoticeFetches, 1);
      expect(api.acknowledgedNoticeIds, isEmpty);

      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(api.acknowledgedNoticeIds, ['notice-1']);
      await _tearDownScreen(tester);
    },
  );

  testWidgets('starter reward and active impact never stack', (tester) async {
    final api = _ActiveImpactApi(
      starterRewardEligible: true,
      responses: [
        _notices(const [
          {
            'id': 'notice-after-starter',
            'powerupType': 'LEECH',
            'deltaSteps': -31,
            'valueStatus': 'SYNCED_SNAPSHOT',
            'resolvedAt': '2026-08-19T16:30:00.000Z',
          },
        ]),
      ],
    );

    await _pumpRace(tester, api, onboardingV2: true);

    expect(find.text('FIRST RACE BONUS'), findsOneWidget);
    expect(find.text('Leech drained 31 synced steps'), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('claim-starter-reward')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('FIRST RACE BONUS'), findsNothing);
    expect(find.text('Leech drained 31 synced steps'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(PowerupRevealModal), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 350));
    await _tearDownScreen(tester);
  });

  testWidgets('malformed rows are filtered before the three-notice cap', (
    tester,
  ) async {
    final api = _ActiveImpactApi(
      responses: [
        _notices([
          for (var i = 0; i < 3; i++)
            {
              'id': 'future-$i',
              'powerupType': 'LEECH',
              'deltaSteps': -1,
              'valueStatus': 'FUTURE_STATUS',
              'resolvedAt': '2026-08-19T16:30:00.000Z',
            },
          const {
            'id': 'valid-after-invalid',
            'powerupType': 'RUNNERS_HIGH',
            'deltaSteps': 90,
            'valueStatus': 'SYNCED_SNAPSHOT',
            'resolvedAt': '2026-08-19T16:31:00.000Z',
          },
        ]),
      ],
    );

    await _pumpRace(tester, api);

    expect(find.text("Runner's High added 90 synced steps"), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 350));
    await _tearDownScreen(tester);
  });

  testWidgets(
    'three-notice cap leaves the oldest remainder for the next resume',
    (tester) async {
      Map<String, dynamic> notice(String id, int delta, int minute) => {
        'id': id,
        'powerupType': 'LEECH',
        'deltaSteps': delta,
        'valueStatus': 'SYNCED_SNAPSHOT',
        'resolvedAt':
            '2026-08-19T16:${minute.toString().padLeft(2, '0')}:00.000Z',
      };

      final api = _ActiveImpactApi(
        responses: [
          _notices([
            notice('notice-1', -11, 30),
            notice('notice-2', -22, 31),
            notice('notice-3', -33, 32),
            notice('notice-4', -44, 33),
          ]),
          _notices([notice('notice-4', -44, 33)]),
        ],
      );

      await _pumpRace(tester, api);
      for (final steps in [11, 22, 33]) {
        expect(find.text('Leech drained $steps synced steps'), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 350));
      }

      expect(api.acknowledgedNoticeIds, ['notice-1', 'notice-2', 'notice-3']);
      expect(find.byType(PowerupRevealModal), findsNothing);

      await _backgroundAndResume(tester);
      expect(find.text('Leech drained 44 synced steps'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
      expect(api.acknowledgedNoticeIds, [
        'notice-1',
        'notice-2',
        'notice-3',
        'notice-4',
      ]);
      await _tearDownScreen(tester);
    },
  );

  testWidgets('old-backend 404 keeps the active race usable with no overlay', (
    tester,
  ) async {
    final api = _ActiveImpactApi(
      activeNoticeError: const ApiException('Not found', statusCode: 404),
    );

    await _pumpRace(tester, api);

    expect(find.text('Impact Sprint'), findsOneWidget);
    expect(find.byType(PowerupRevealModal), findsNothing);
    expect(tester.takeException(), isNull);
    await _tearDownScreen(tester);
  });

  testWidgets(
    'inline receipt is acknowledged only after its result toast exits',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _ActiveImpactApi(includeHeldPowerup: true);

      await _pumpRace(tester, api);
      final heldSlot = find.byWidgetPredicate(
        (widget) => widget is ItemSlot && widget.state == ItemSlotState.held,
      );
      await tester.ensureVisible(heldSlot);
      await tester.tap(heldSlot);
      await tester.pump(const Duration(milliseconds: 450));
      final useButton = find.text('USE');
      await tester.ensureVisible(useButton);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(useButton);
      await tester.pump(const Duration(milliseconds: 450));

      expect(find.text('Second Wind activated!'), findsOneWidget);
      expect(api.acknowledgedReceiptIds, isEmpty);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
      expect(api.acknowledgedReceiptIds, ['receipt-1']);
      await _tearDownScreen(tester);
    },
  );

  testWidgets('immediate powerup reveal serializes a resumed impact notice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _ActiveImpactApi(
      includeHeldPowerup: true,
      heldPowerupType: 'COIN_FLIP',
      useResult: const {'flip': 'WIN'},
      responses: [
        ActiveImpactNoticesResult.empty,
        _notices(const [
          {
            'id': 'notice-after-outcome',
            'powerupType': 'LEECH',
            'deltaSteps': -73,
            'valueStatus': 'SYNCED_SNAPSHOT',
            'resolvedAt': '2026-08-19T16:30:00.000Z',
          },
        ]),
      ],
    );

    await _pumpRace(tester, api);
    final heldSlot = find.byWidgetPredicate(
      (widget) => widget is ItemSlot && widget.state == ItemSlotState.held,
    );
    await tester.ensureVisible(heldSlot);
    await tester.tap(heldSlot);
    await tester.pump(const Duration(milliseconds: 450));
    final useButton = find.text('USE');
    await tester.ensureVisible(useButton);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(useButton);
    await tester.tap(useButton);
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('HEADS!'), findsOneWidget);
    expect(find.byType(PowerupRevealModal), findsOneWidget);
    await _backgroundAndResume(tester);
    expect(api.activeNoticeFetches, 1);
    expect(find.text('Leech drained 73 synced steps'), findsNothing);
    expect(find.byType(PowerupRevealModal), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('HEADS!'), findsNothing);
    expect(api.activeNoticeFetches, 2);
    expect(find.text('Leech drained 73 synced steps'), findsOneWidget);
    expect(find.byType(PowerupRevealModal), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 350));
    await _tearDownScreen(tester);
  });

  testWidgets(
    'completed race never requests a popup and keeps final Activity',
    (tester) async {
      final api = _ActiveImpactApi(raceStatus: 'COMPLETED');

      await _pumpRace(tester, api);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(api.activeNoticeFetches, 0);
      expect(api.legacyNoticeFetches, 0);
      expect(find.byType(PowerupRevealModal), findsNothing);
      expect(
        find.text(
          'Leech changed your final score by −430 steps.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await _tearDownScreen(tester);
    },
  );

  testWidgets(
    'ordinary polling does not fetch notices; true resume does once',
    (tester) async {
      final api = _ActiveImpactApi(
        responses: [
          ActiveImpactNoticesResult.empty,
          _notices(const [
            {
              'id': 'notice-resume',
              'powerupType': 'LEECH',
              'deltaSteps': -77,
              'valueStatus': 'SYNCED_SNAPSHOT',
              'resolvedAt': '2026-08-19T16:30:00.000Z',
            },
          ]),
        ],
      );

      await _pumpRace(tester, api);
      expect(api.activeNoticeFetches, 1);

      await tester.pump(const Duration(seconds: 30));
      expect(api.progressFetches, 2);
      expect(api.activeNoticeFetches, 1);

      await _backgroundAndResume(tester);
      expect(api.activeNoticeFetches, 2);
      expect(find.text('Leech drained 77 synced steps'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 350));
      await _tearDownScreen(tester);
    },
  );

  testWidgets('pull-to-refresh never creates a notice delivery opportunity', (
    tester,
  ) async {
    final api = _ActiveImpactApi(
      responses: [
        ActiveImpactNoticesResult.empty,
        _notices(const [
          {
            'id': 'notice-refresh-leak',
            'powerupType': 'LEECH',
            'deltaSteps': -51,
            'valueStatus': 'SYNCED_SNAPSHOT',
            'resolvedAt': '2026-08-19T16:30:00.000Z',
          },
        ]),
      ],
    );

    await _pumpRace(tester, api);
    expect(api.activeNoticeFetches, 1);

    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await refresh.onRefresh();
    await tester.pump(const Duration(milliseconds: 350));

    expect(api.activeNoticeFetches, 1);
    expect(find.byType(PowerupRevealModal), findsNothing);
    await _tearDownScreen(tester);
  });

  testWidgets('returning from a child route is not a foreground delivery', (
    tester,
  ) async {
    final api = _ActiveImpactApi(responses: [ActiveImpactNoticesResult.empty]);

    await _pumpRace(tester, api);
    expect(api.activeNoticeFetches, 1);

    final navigator = Navigator.of(
      tester.element(find.byType(RaceDetailScreen)),
    );
    final childRoute = navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Child route')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Child route'), findsOneWidget);
    navigator.pop();
    await childRoute;
    await tester.pump(const Duration(milliseconds: 350));

    expect(api.activeNoticeFetches, 1);
    await _tearDownScreen(tester);
  });

  testWidgets(
    'foreground resume merges into an in-flight route-uncover refresh',
    (tester) async {
      final api = _ActiveImpactApi(
        responses: [
          ActiveImpactNoticesResult.empty,
          _notices(const [
            {
              'id': 'notice-merged-resume',
              'powerupType': 'LEECH',
              'deltaSteps': -62,
              'valueStatus': 'SYNCED_SNAPSHOT',
              'resolvedAt': '2026-08-19T16:30:00.000Z',
            },
          ]),
        ],
      );

      await _pumpRace(tester, api);
      final navigator = Navigator.of(
        tester.element(find.byType(RaceDetailScreen)),
      );
      final childRoute = navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Blocking child')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final gate = Completer<void>();
      api.nextProgressGate = gate;
      navigator.pop();
      await childRoute;
      await tester.pump();
      expect(api.progressFetches, 2);

      await _backgroundAndResume(tester);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(api.activeNoticeFetches, 2);
      expect(find.text('Leech drained 62 synced steps'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 350));
      await _tearDownScreen(tester);
    },
  );

  testWidgets('terminal unresolved generation does not refetch or show', (
    tester,
  ) async {
    final api = _ActiveImpactApi(
      responses: [
        const ActiveImpactNoticesResult.pending(
          jobId: 'job-failed',
          generation: 9,
          retryAfterMs: 500,
        ),
      ],
    );
    api.resolutionStates.add(RaceResolutionState.failed);

    await _pumpRace(tester, api);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(api.activeNoticeFetches, 1);
    expect(find.byType(PowerupRevealModal), findsNothing);
    await _tearDownScreen(tester);
  });

  testWidgets(
    'pending generation waits for status then refetches notices once',
    (tester) async {
      final api = _ActiveImpactApi(
        responses: [
          const ActiveImpactNoticesResult.pending(
            jobId: 'job-1',
            generation: 42,
            retryAfterMs: 500,
          ),
          _notices(const [
            {
              'id': 'notice-after-job',
              'powerupType': 'LEECH',
              'deltaSteps': -12,
              'valueStatus': 'SYNCED_SNAPSHOT',
              'resolvedAt': '2026-08-19T16:30:00.000Z',
            },
          ]),
        ],
      );
      api.resolutionStates.add(RaceResolutionState.succeeded);

      await _pumpRace(tester, api);
      expect(api.activeNoticeFetches, 1);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(api.activeNoticeFetches, 2);
      expect(find.text('Leech drained 12 synced steps'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 350));
      await _tearDownScreen(tester);
    },
  );
}
