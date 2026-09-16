import 'dart:async';
import 'package:step_tracker/widgets/app_refresh_indicator.dart';
import 'package:step_tracker/services/app_route_observer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/services/race_change_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/race_detail_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// A backend fake that counts fetchRaceProgress calls so a widget test can prove
// the periodic poll is cancelled while backgrounded and refreshes immediately
// on resume. Powerups are left disabled so the extra global-inventory fetch
// path never runs, keeping the count == the number of poll fetches.
class _CountingActiveRaceApi extends BackendApiService {
  _CountingActiveRaceApi();

  final changes = StreamController<RaceChangeSignal>.broadcast();
  int connections = 0;
  @override
  Stream<RaceChangeSignal> watchRaceChanges({
    required String identityToken,
    required String raceId,
  }) {
    connections++;
    return changes.stream;
  }

  final String status = 'ACTIVE';
  int progressCalls = 0;
  int steps = 42000;
  int? projectionGeneration;
  Completer<void>? nextProgressGate;
  Object? nextProgressError;
  Future<void> progressCompletion = Future.value();

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async {
    return {
      'id': raceId,
      'name': 'Lifecycle Race',
      'status': status,
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 0,
      'payouts': {'first': 0, 'second': 0, 'third': 0},
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': false,
      'endsAt': '2026-12-10T12:00:00.000Z',
      'participants': const [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'status': 'ACCEPTED',
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'status': 'ACCEPTED',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    progressCalls += 1;
    final capturedSteps = steps;
    final completion = Completer<void>();
    progressCompletion = completion.future;
    final gate = nextProgressGate;
    nextProgressGate = null;
    if (gate != null) await gate.future;
    final error = nextProgressError;
    nextProgressError = null;
    if (error != null) {
      completion.complete();
      throw error;
    }
    // Report ACTIVE regardless of the details status: a COMPLETED race never
    // reaches _loadProgress, so this is only exercised for the active flow.
    final result = <String, dynamic>{
      if (projectionGeneration != null) ...{
        'projectionGeneration': projectionGeneration,
        'asOf': '2026-09-14T12:00:00.000Z',
        'projectionSource': 'authoritative',
      },
      'status': 'ACTIVE',
      'participants': [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': capturedSteps,
          'finishedAt': null,
        },
        {
          'userId': 'user-2',
          'displayName': 'Hill Climber',
          'totalSteps': 38000,
          'finishedAt': null,
        },
      ],
      'powerupData': const {
        'enabled': false,
        'inventory': [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
      },
    };
    completion.complete();
    return result;
  }

  // Chat + activity feeds both poll fetchRaceMessages every 5s once an ACTIVE
  // race loads; return an empty page so those tick harmlessly and don't hit
  // the network while the test advances virtual time.
  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async {
    return const {'messages': [], 'events': []};
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
    'auth_coins': 420,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

// Drive the binding through the realistic transition chain rather than jumping
// straight to paused/resumed, so no lifecycle-transition assertion fires.
Future<void> _background(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
}

Future<void> _foreground(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'bara',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    ),
  );
  Future<(_CountingActiveRaceApi, AuthService)> open(
    WidgetTester tester, {
    Object? flag = true,
    void Function(String, Map<String, Object>)? freshnessTrace,
  }) async {
    final auth = await _createAuthService();
    auth.applyBackendUser({
      'featureFlags': {'raceEventDrivenRefreshEnabled': flag},
    }, authoritative: true);
    final api = _CountingActiveRaceApi();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: RaceDetailScreen(
          authService: auth,
          raceId: 'race-freshness',
          backendApiService: api,
          freshnessTrace: freshnessTrace,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    return (api, auth);
  }

  Future<void> close(WidgetTester tester, _CountingActiveRaceApi api) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await api.changes.close();
    await tester.pump();
  }

  testWidgets('real screen coalesces 100 hints into one rendered refresh', (
    tester,
  ) async {
    final (api, _) = await open(tester);
    expect(api.connections, 1);
    final before = api.progressCalls;
    api.steps = 46000;
    for (var i = 0; i < 100; i++) {
      api.changes.add(RaceChangeSignal.invalidated);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 99));
    expect(api.progressCalls, before);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(api.progressCalls, before + 1);
    expect(find.textContaining('46,000'), findsWidgets);
    await close(tester, api);
  });
  testWidgets('actual progress future limits inflight hints to one followup', (
    tester,
  ) async {
    final (api, _) = await open(tester);
    final before = api.progressCalls;
    final gate = Completer<void>();
    api.nextProgressGate = gate;
    api.changes.add(RaceChangeSignal.invalidated);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 100; i++) {
      api.changes.add(RaceChangeSignal.invalidated);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.progressCalls, before + 1);
    api.steps = 47000;
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(api.progressCalls, before + 2);
    expect(find.textContaining('47,000'), findsWidgets);
    await close(tester, api);
  });
  testWidgets(
    'background disconnects; foreground reconnects and refreshes current score',
    (tester) async {
      final (api, _) = await open(tester);
      await _background(tester);
      final before = api.progressCalls;
      api.steps = 44000;
      api.changes.add(RaceChangeSignal.invalidated);
      await tester.pump(const Duration(seconds: 35));
      expect(api.progressCalls, before);
      await _foreground(tester);
      await tester.pump();
      expect(api.connections, 2);
      expect(find.textContaining('44,000'), findsWidgets);
      await close(tester, api);
    },
  );
  for (final flag in [null, false, 'true', 1]) {
    testWidgets('missing or malformed flag $flag keeps polling fallback', (
      tester,
    ) async {
      final (api, _) = await open(tester, flag: flag);
      expect(api.connections, 0);
      api.steps = 45000;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(find.textContaining('45,000'), findsWidgets);
      await close(tester, api);
    });
  }
  testWidgets('disconnect reconnect fetches current state without replay', (
    tester,
  ) async {
    final (api, _) = await open(tester);
    api.steps = 48000;
    api.changes.add(RaceChangeSignal.connected);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('48,000'), findsWidgets);
    await close(tester, api);
  });
  testWidgets(
    'endpoint unavailable stops reconnect attempts but keeps 30 second fallback',
    (tester) async {
      final (api, _) = await open(tester);
      api.changes.addError(const RaceChangeStreamException(404));
      await tester.pump();
      api.steps = 49000;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(api.connections, 1);
      expect(find.textContaining('49,000'), findsWidgets);
      await close(tester, api);
    },
  );
  testWidgets(
    'transient stream failure backs off and reconnect GET recovers missed hint',
    (tester) async {
      final (api, _) = await open(tester);
      api.changes.addError(const RaceChangeStreamException(503));
      await tester.pump();
      expect(api.connections, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(api.connections, 2);
      api.steps = 50000;
      api.changes.add(RaceChangeSignal.connected);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('50,000'), findsWidgets);
      await close(tester, api);
    },
  );
  testWidgets(
    'server disable cancels hints while preserving manual and polling reads',
    (tester) async {
      final (api, auth) = await open(tester);
      await auth.syncFromBackendUser({
        'featureFlags': {'raceEventDrivenRefreshEnabled': false},
      }, authoritative: true);
      final before = api.progressCalls;
      api.steps = 51000;
      api.changes.add(RaceChangeSignal.invalidated);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.progressCalls, before);
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(find.textContaining('51,000'), findsWidgets);
      await close(tester, api);
    },
  );
  testWidgets(
    'covered route suspends stream and uncover reconciles current score',
    (tester) async {
      final (api, _) = await open(tester);
      final context = tester.element(find.byType(RaceDetailScreen));
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covered')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final before = api.progressCalls;
      api.steps = 52000;
      api.changes.add(RaceChangeSignal.invalidated);
      await tester.pump(const Duration(seconds: 31));
      expect(api.progressCalls, before);
      Navigator.of(context).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.connections, 2);
      expect(find.textContaining('52,000'), findsWidgets);
      await close(tester, api);
    },
  );
  testWidgets('logout cancels subscriptions and ignores subsequent hints', (
    tester,
  ) async {
    final (api, auth) = await open(tester);
    await auth.signOut();
    await tester.pump();
    final before = api.progressCalls;
    api.changes.add(RaceChangeSignal.invalidated);
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.progressCalls, before);
    await close(tester, api);
  });
  testWidgets('hint during an older manual GET waits then reads fresh score', (
    tester,
  ) async {
    final (api, _) = await open(tester);
    final before = api.progressCalls;
    final gate = Completer<void>();
    api.nextProgressGate = gate;
    final manual = tester
        .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator).first)
        .onRefresh;
    unawaited(manual());
    await tester.pump();
    await tester.pump();
    expect(api.progressCalls, before + 1);
    api.steps = 53000;
    api.changes.add(RaceChangeSignal.invalidated);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.progressCalls, before + 1);
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(api.progressCalls, before + 2);
    expect(find.textContaining('53,000'), findsWidgets);
    await close(tester, api);
  });

  testWidgets('freshness trace binds applied response to its visible frame', (
    tester,
  ) async {
    final events = <({String name, Map<String, Object> fields})>[];
    final (api, _) = await open(
      tester,
      freshnessTrace: (name, fields) =>
          events.add((name: name, fields: fields)),
    );
    events.clear();
    api.steps = 54000;
    api.changes.add(RaceChangeSignal.invalidated);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.textContaining('54,000'), findsWidgets);
    final names = events.map((e) => e.name).toList();
    expect(
      names,
      containsAllInOrder([
        'race_change_received',
        'race_change_refetch_start',
        'race_progress_read_start',
        'race_progress_read_complete',
        'race_progress_state_applied',
        'race_progress_frame',
      ]),
    );
    final applied = events.singleWhere(
      (e) => e.name == 'race_progress_state_applied',
    );
    final frame = events.singleWhere((e) => e.name == 'race_progress_frame');
    expect(frame.fields['fetchSequence'], applied.fields['fetchSequence']);
    expect(frame.fields['raceId'], 'race-freshness');
    expect(frame.fields['elapsedMicros'], isNonNegative);
    expect(frame.fields.containsKey('scoreVersion'), isFalse);
    await close(tester, api);
  });

  testWidgets('failed event refetch never claims a new score frame', (
    tester,
  ) async {
    final events = <String>[];
    final (api, _) = await open(
      tester,
      freshnessTrace: (name, _) => events.add(name),
    );
    events.clear();
    api.nextProgressError = const ApiException(
      'Temporary read failure',
      statusCode: 503,
    );
    api.changes.add(RaceChangeSignal.invalidated);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.textContaining('42,000'), findsWidgets);
    expect(events, contains('race_progress_read_failed'));
    expect(events, isNot(contains('race_progress_state_applied')));
    expect(events, isNot(contains('race_progress_frame')));
    await close(tester, api);
  });

  testWidgets(
    'metadata-free response never borrows an older frame generation',
    (tester) async {
      final frames = <Map<String, Object>>[];
      final (api, _) = await open(
        tester,
        freshnessTrace: (name, fields) {
          if (name == 'race_progress_frame') frames.add(fields);
        },
      );
      frames.clear();
      api.projectionGeneration = 17;
      api.changes.add(RaceChangeSignal.invalidated);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(frames.single['projectionGeneration'], 17);
      frames.clear();
      api.projectionGeneration = null;
      api.steps = 55000;
      api.changes.add(RaceChangeSignal.invalidated);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.textContaining('55,000'), findsWidgets);
      expect(frames.single.containsKey('projectionGeneration'), isFalse);
      await close(tester, api);
    },
  );
}
