import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/app_route_observer.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

class _ExpiryApi extends BackendApiService {
  List<Map<String, dynamic>> effects = [];
  final List<int> offsets = [];
  Completer<RaceProgressResult>? pending;
  bool fail = false;
  bool paged = false;
  bool metadata = true;
  bool preview = false;
  bool distinctPages = false;
  int bootstrapCalls = 0;
  int generation = 10;
  String source = 'authoritative';

  Map<String, dynamic> progress({int offset = 0}) => {
    'status': 'ACTIVE',
    if (metadata) ...{
      'projectionGeneration': generation,
      'projectionSource': source,
    },
    if (paged)
      'pagination': {
        'offset': offset,
        'limit': 15,
        'total': 50,
        'hasMore': offset < 30,
      },
    'participants': distinctPages
        ? [
            for (var i = offset; i < offset + 2; i++)
              {
                'userId': 'racer-$i',
                'displayName': 'Racer $i',
                'totalSteps': 5000 - i,
              },
          ]
        : [
            if (!preview)
              {'userId': 'me', 'displayName': 'Bara', 'totalSteps': 5000},
            {'userId': 'other', 'displayName': 'Otter', 'totalSteps': 4000},
          ],
    'powerupData': {
      'enabled': true,
      'inventory': [],
      'powerupSlots': 3,
      'queuedBoxCount': 0,
      'activeEffects': List<Map<String, dynamic>>.of(effects),
      'stepsUntilNextPowerup': 1000,
    },
  };

  RaceProgressResult result({int offset = 0}) => RaceProgressResult(
    progress: progress(offset: offset),
    hasCompactInventory: true,
    globalPowerupInventory: const {'inventory': [], 'powerupSlots': 3},
  );

  @override
  Future<RaceBootstrapResult> fetchRaceBootstrap({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    bootstrapCalls++;
    return RaceBootstrapResult(
      supported: true,
      race: {
        'id': raceId,
        'name': 'Expiry Race',
        'status': 'ACTIVE',
        'maxDurationDays': 7,
        'buyInAmount': 0,
        'myStatus': preview ? null : 'ACCEPTED',
        'isPublic': preview,
        'powerupsEnabled': true,
        'endsAt': '2127-12-10T12:00:00.000Z',
        'participants': [
          if (!preview)
            {'userId': 'me', 'displayName': 'Bara', 'status': 'ACCEPTED'},
          {'userId': 'other', 'displayName': 'Otter', 'status': 'ACCEPTED'},
        ],
      },
      progress: progress(),
    );
  }

  @override
  Future<RaceProgressResult> fetchRaceProgressParticipants({
    required String identityToken,
    required String raceId,
    int offset = 0,
    int limit = 10,
  }) async {
    offsets.add(offset);
    if (fail) throw const ApiException('Offline');
    return pending?.future ?? result(offset: offset);
  }

  @override
  Future<RaceMessageStreamsResult> fetchRaceMessageStreams({
    required String identityToken,
    required String raceId,
    required bool includeUser,
    int limit = 50,
  }) async => const RaceMessageStreamsResult(
    supported: true,
    systemResolved: true,
    systemStream: {'messages': [], 'nextCursor': null},
    userResolved: true,
    userStream: {'messages': [], 'nextCursor': null},
    chatWatermark: {'recentIds': <String>[]},
  );

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async => const {'inventory': [], 'powerupSlots': 3};
}

Map<String, dynamic> _effect({String id = 'effect-1', Object? expiresAt}) => {
  'id': id,
  'type': 'RUNNERS_HIGH',
  'onSelf': true,
  'sourceUserId': 'me',
  'targetUserId': 'me',
  'expiresAt':
      expiresAt ??
      DateTime.now().subtract(const Duration(seconds: 1)).toIso8601String(),
};

Future<AuthService> _pump(
  WidgetTester tester,
  _ExpiryApi api, {
  bool demo = false,
  GlobalKey<NavigatorState>? navigatorKey,
  DateTime Function()? now,
}) async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'token',
    'auth_user_identifier': 'user',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'me',
    'auth_display_name': 'Bara',
  });
  final auth = AuthService();
  await auth.restoreSession();
  await tester.binding.setSurfaceSize(const Size(430, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [appRouteObserver],
      home: RaceDetailScreen(
        authService: auth,
        raceId: 'race-expiry',
        backendApiService: api,
        demoMode: demo,
        now: now,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return auth;
}

Future<void> _advance(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'bara',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'overdue effect refreshes within jitter and stays until server confirmation',
    (tester) async {
      final api = _ExpiryApi()..effects = [_effect()];
      await _pump(tester, api);
      expect(find.text("Runner's High"), findsOneWidget);
      await _advance(tester, 1);
      expect(api.offsets, hasLength(1));
      expect(find.text("Runner's High"), findsOneWidget);
      api.effects = [];
      await _advance(tester, 3);
      expect(api.offsets, hasLength(2));
      expect(find.text("Runner's High"), findsNothing);
      await _advance(tester, 20);
      expect(api.offsets, hasLength(2));
      await _dispose(tester);
    },
  );

  testWidgets(
    '100 simultaneous effects share four requests then ordinary polling',
    (tester) async {
      final api = _ExpiryApi()
        ..effects = [for (var i = 0; i < 100; i++) _effect(id: 'effect-$i')];
      await _pump(tester, api);
      await _advance(tester, 29);
      expect(api.offsets, hasLength(4));
      expect(find.text('Expiring...'), findsWidgets);
      await _advance(tester, 32);
      expect(api.offsets, hasLength(6)); // four accelerated, two ordinary polls
      await _dispose(tester);
    },
  );

  testWidgets('extension stops the old deadline burst', (tester) async {
    final api = _ExpiryApi()..effects = [_effect()];
    await _pump(tester, api);
    api.effects = [
      _effect(
        expiresAt: DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      ),
    ];
    await _advance(tester, 20);
    expect(api.offsets, hasLength(1));
    expect(find.text("Runner's High"), findsOneWidget);
    expect(find.text('Expiring...'), findsNothing);
    await _dispose(tester);
  });

  testWidgets(
    'missing invalid identities and deadlines use only normal polling',
    (tester) async {
      final api = _ExpiryApi()
        ..effects = [
          _effect()..remove('id'),
          _effect(id: ''),
          _effect(expiresAt: 'bad-date'),
          _effect(expiresAt: 42),
          _effect()..['expiresAt'] = null,
        ];
      await _pump(tester, api);
      await _advance(tester, 29);
      expect(api.offsets, isEmpty);
      await _advance(tester, 2);
      expect(api.offsets, hasLength(1));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  testWidgets(
    'network errors preserve effects and still exhaust bounded retries',
    (tester) async {
      final api = _ExpiryApi()
        ..effects = [_effect()]
        ..fail = true;
      await _pump(tester, api);
      await _advance(tester, 29);
      expect(api.offsets, hasLength(4));
      expect(find.text("Runner's High"), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  testWidgets(
    'slower server projection cannot resurrect a confirmed expired effect',
    (tester) async {
      final api = _ExpiryApi()..effects = [_effect()];
      await _pump(tester, api);
      api.effects = [];
      api.generation = 11;
      await _advance(tester, 1);
      expect(find.text("Runner's High"), findsNothing);
      api.effects = [_effect()];
      api.generation = 10;
      api.source = 'stale-fallback';
      await _advance(tester, 30);
      expect(find.text("Runner's High"), findsNothing);
      await _dispose(tester);
    },
  );

  testWidgets('hidden route pauses bursts and uncover refreshes once', (
    tester,
  ) async {
    final api = _ExpiryApi()..effects = [_effect()];
    final navigator = GlobalKey<NavigatorState>();
    await _pump(tester, api, navigatorKey: navigator);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Covered')),
      ),
    );
    await _advance(tester, 5);
    expect(api.offsets, isEmpty);
    api.effects = [];
    navigator.currentState!.pop();
    await _advance(tester, 1);
    expect(api.offsets, hasLength(1));
    expect(find.text("Runner's High"), findsNothing);
    await _dispose(tester);
  });

  testWidgets(
    'background cancels deadline work and resume reuses a pending request',
    (tester) async {
      final api = _ExpiryApi()..effects = [_effect()];
      await _pump(tester, api);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _advance(tester, 10);
      expect(api.offsets, isEmpty);
      api.pending = Completer<RaceProgressResult>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _advance(tester, 5);
      expect(api.offsets, hasLength(1));
      api.effects = [];
      api.pending!.complete(api.result());
      await _advance(tester, 3);
      expect(find.text("Runner's High"), findsNothing);
      expect(api.offsets, hasLength(1));
      await _dispose(tester);
    },
  );

  testWidgets('disposing a pending expiry never starts retries', (
    tester,
  ) async {
    final api = _ExpiryApi()..effects = [_effect()];
    await _pump(tester, api);
    await _dispose(tester);
    await _advance(tester, 20);
    expect(api.offsets, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'demo and tutorial real screen retain three second poll without expiry bursts',
    (tester) async {
      final api = _ExpiryApi()..effects = [_effect()];
      await _pump(tester, api, demo: true);
      await _advance(tester, 2);
      expect(api.offsets, isEmpty);
      expect(find.text("Runner's High"), findsOneWidget);
      await _advance(tester, 5);
      expect(api.bootstrapCalls, 3);
      expect(api.offsets, isEmpty);
      await _dispose(tester);
    },
  );
  testWidgets(
    'future deadline requests within 500ms and confirms inside ten seconds',
    (tester) async {
      final deadline = tester.binding.clock.now().add(
        const Duration(seconds: 5),
      );
      final api = _ExpiryApi()
        ..effects = [_effect(expiresAt: deadline.toIso8601String())];
      await _pump(tester, api, now: tester.binding.clock.now);
      await _advance(tester, 4);
      expect(api.offsets, isEmpty);
      api.effects = [];
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump();
      expect(api.offsets, hasLength(1));
      expect(find.text("Runner's High"), findsNothing);
      expect(
        tester.binding.clock.now().difference(deadline).inMilliseconds,
        lessThanOrEqualTo(500),
      );
      await _dispose(tester);
    },
  );

  testWidgets(
    'device clock forward then backward cannot expand request budget or settle an effect',
    (tester) async {
      var wall = tester.binding.clock.now();
      final api = _ExpiryApi()
        ..effects = [
          _effect(
            expiresAt: wall.add(const Duration(hours: 1)).toIso8601String(),
          ),
        ];
      await _pump(tester, api, now: () => wall);
      await _advance(tester, 1);
      expect(api.offsets, isEmpty);
      wall = wall.add(const Duration(hours: 2));
      await _advance(tester, 18);
      expect(api.offsets, hasLength(4));
      expect(find.text("Runner's High"), findsOneWidget);
      wall = wall.subtract(const Duration(hours: 4));
      await _advance(tester, 8);
      expect(api.offsets, hasLength(4));
      expect(find.text("Runner's High"), findsOneWidget);
      await _dispose(tester);
    },
  );

  testWidgets(
    'new deadline identities share rolling budget instead of starting new bursts',
    (tester) async {
      final api = _ExpiryApi()..effects = [_effect()];
      await _pump(tester, api);
      for (var i = 0; i < 10; i++) {
        api.effects = [_effect(id: 'replacement-$i')];
        await _advance(tester, 1);
      }
      expect(api.offsets, hasLength(4));
      await _advance(tester, 18);
      expect(api.offsets, hasLength(4));
      await _dispose(tester);
    },
  );

  testWidgets('logout cancels expiry and ignores an old session refusal', (
    tester,
  ) async {
    final api = _ExpiryApi()..effects = [_effect()];
    final auth = await _pump(tester, api);
    api.pending = Completer<RaceProgressResult>();
    await _advance(tester, 1);
    expect(api.offsets, hasLength(1));
    await auth.signOut();
    api.effects = [];
    api.pending!.completeError(
      const ApiException('Former session', statusCode: 403),
    );
    await _advance(tester, 20);
    expect(api.offsets, hasLength(1));
    expect(find.byKey(const Key('race-not-a-participant')), findsNothing);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets('ordinary poll reuses a slow expiry request', (tester) async {
    final api = _ExpiryApi()
      ..effects = [_effect()]
      ..pending = Completer<RaceProgressResult>();
    await _pump(tester, api);
    await _advance(tester, 35);
    expect(api.offsets, hasLength(1));
    api.effects = [];
    api.pending!.complete(api.result());
    await _advance(tester, 1);
    expect(find.text("Runner's High"), findsNothing);
    await _dispose(tester);
  });

  testWidgets(
    'next page response wins over delayed expiry and polls stay on that page',
    (tester) async {
      final api = _ExpiryApi()
        ..paged = true
        ..effects = [_effect()];
      await _pump(tester, api);
      final oldRequest = Completer<RaceProgressResult>();
      api.pending = oldRequest;
      await _advance(tester, 1);
      final oldResult = api.result();
      expect(api.offsets, [0]);
      api.pending = null;
      api.effects = [];
      api.generation = 11;
      final nextPage = find.byKey(const Key('standings-next-page'));
      await tester.ensureVisible(nextPage);
      await tester.tap(nextPage);
      await tester.pump();
      expect(api.offsets, [0, 2]);
      expect(find.text('3-4 of 50'), findsOneWidget);
      oldRequest.complete(oldResult);
      await _advance(tester, 1);
      expect(find.text("Runner's High"), findsNothing);
      await _advance(tester, 30);
      expect(api.offsets, [0, 2, 2]);
      expect(find.text('3-4 of 50'), findsOneWidget);
      await _dispose(tester);
    },
  );

  testWidgets('expiry reuses pagination already in flight', (tester) async {
    final deadline = tester.binding.clock.now().add(const Duration(seconds: 3));
    final api = _ExpiryApi()
      ..paged = true
      ..effects = [_effect(expiresAt: deadline.toIso8601String())];
    await _pump(tester, api, now: tester.binding.clock.now);
    final page = Completer<RaceProgressResult>();
    api.pending = page;
    final nextPage = find.byKey(const Key('standings-next-page'));
    await tester.ensureVisible(nextPage);
    await tester.tap(nextPage);
    await _advance(tester, 6);
    expect(api.offsets, [2]);
    api.effects = [];
    page.complete(api.result(offset: 2));
    await _advance(tester, 1);
    expect(find.text("Runner's High"), findsNothing);
    expect(find.text('3-4 of 50'), findsOneWidget);
    await _dispose(tester);
  });
  testWidgets(
    'effects outside the current participant projection do not trigger requests',
    (tester) async {
      final api = _ExpiryApi()
        ..effects = [
          _effect()
            ..['onSelf'] = false
            ..['targetUserId'] = 'outside-page',
        ];
      await _pump(tester, api);
      await _advance(tester, 29);
      expect(api.offsets, isEmpty);
      expect(find.text("Runner's High"), findsNothing);
      await _dispose(tester);
    },
  );

  testWidgets(
    'older backend without projection metadata still confirms expiry',
    (tester) async {
      final api = _ExpiryApi()
        ..metadata = false
        ..effects = [_effect()];
      await _pump(tester, api);
      api.effects = [];
      await _advance(tester, 1);
      expect(api.offsets, hasLength(1));
      expect(find.text("Runner's High"), findsNothing);
      await _dispose(tester);
    },
  );

  testWidgets(
    'same generation fallback cannot restore an effect removed by authoritative state',
    (tester) async {
      final api = _ExpiryApi()..effects = [_effect()];
      await _pump(tester, api);
      api.effects = [];
      await _advance(tester, 1);
      expect(find.text("Runner's High"), findsNothing);
      api.effects = [_effect()];
      api.source = 'stale-fallback';
      await _advance(tester, 30);
      expect(find.text("Runner's High"), findsNothing);
      await _dispose(tester);
    },
  );
  testWidgets(
    'public preview with overdue racer effect remains a single read',
    (tester) async {
      final api = _ExpiryApi()
        ..preview = true
        ..effects = [
          _effect()
            ..['onSelf'] = false
            ..['targetUserId'] = 'other',
        ];
      await _pump(tester, api);
      expect(find.text('@Otter'), findsWidgets);
      await _advance(tester, 61);
      expect(api.bootstrapCalls, 1);
      expect(api.offsets, isEmpty);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    },
  );

  testWidgets(
    'rejected older page keeps committed rows and ranks and NEXT retries the same page',
    (tester) async {
      final api = _ExpiryApi()
        ..paged = true
        ..distinctPages = true;
      await _pump(tester, api);
      expect(find.text('@Racer 0'), findsWidgets);
      expect(find.text('1-2 of 50'), findsOneWidget);
      final nextPage = find.byKey(const Key('standings-next-page'));
      await tester.ensureVisible(nextPage);
      final oldPage = Completer<RaceProgressResult>();
      api.pending = oldPage;
      await tester.tap(nextPage);
      await tester.pump();
      expect(api.offsets, [2]);
      expect(find.text('1-2 of 50'), findsOneWidget);
      api.generation = 9;
      oldPage.complete(api.result(offset: 2));
      await tester.pump();
      await tester.pump();
      expect(find.text('@Racer 0'), findsWidgets);
      expect(find.text('@Racer 2'), findsNothing);
      expect(find.text('1-2 of 50'), findsOneWidget);
      api.pending = null;
      api.generation = 11;
      await tester.tap(nextPage);
      await tester.pump();
      expect(api.offsets, [2, 2]);
      expect(find.text('@Racer 0'), findsNothing);
      expect(find.text('@Racer 2'), findsWidgets);
      expect(find.text('3-4 of 50'), findsOneWidget);
      await _dispose(tester);
    },
  );
}
