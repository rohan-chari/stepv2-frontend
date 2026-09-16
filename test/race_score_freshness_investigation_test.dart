import 'dart:async';
import 'package:step_tracker/widgets/app_refresh_indicator.dart';
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

  final String status = 'ACTIVE';
  int progressCalls = 0;
  int steps = 42000;
  Completer<void>? nextProgressGate;
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
    final completion = Completer<void>();
    progressCompletion = completion.future;
    final gate = nextProgressGate;
    nextProgressGate = null;
    if (gate != null) await gate.future;
    // Report ACTIVE regardless of the details status: a COMPLETED race never
    // reaches _loadProgress, so this is only exercised for the active flow.
    final result = <String, dynamic>{
      'status': 'ACTIVE',
      'participants': [
        {
          'userId': 'user-1',
          'displayName': 'Trail Walker',
          'totalSteps': steps,
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
  Future<_CountingActiveRaceApi> open(WidgetTester tester) async {
    final auth = await _createAuthService();
    final api = _CountingActiveRaceApi();
    await tester.pumpWidget(
      MaterialApp(
        home: RaceDetailScreen(
          authService: auth,
          raceId: 'race-freshness',
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    return api;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  }

  testWidgets(
    'committed score remains old until the 30 second poll renders it',
    (tester) async {
      final api = await open(tester);
      expect(find.textContaining('42,000'), findsWidgets);
      api.steps = 43000;
      await tester.pump(const Duration(seconds: 29));
      expect(api.progressCalls, 1);
      expect(find.textContaining('43,000'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(api.progressCalls, 2);
      expect(find.textContaining('43,000'), findsWidgets);
      await close(tester);
    },
  );
  testWidgets(
    'foreground refresh renders committed score without waiting for poll',
    (tester) async {
      final api = await open(tester);
      await _background(tester);
      api.steps = 44000;
      await tester.pump(const Duration(seconds: 90));
      expect(api.progressCalls, 1);
      await _foreground(tester);
      await tester.pump();
      expect(find.textContaining('44,000'), findsWidgets);
      await close(tester);
    },
  );
  testWidgets(
    '100 invalidation hints coalesce into one refresh and rendered score',
    (tester) async {
      final api = await open(tester);
      api.steps = 46000;
      final action = tester
          .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator).first)
          .onRefresh;
      final controller = _HintRefresh(action);
      for (var i = 0; i < 100; i++) {
        controller.hint();
      }
      await tester.pump(const Duration(milliseconds: 99));
      expect(api.progressCalls, 1);
      expect(find.textContaining('46,000'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      await tester.pump();
      expect(api.progressCalls, 2);
      expect(find.textContaining('46,000'), findsWidgets);
      controller.dispose();
      await close(tester);
    },
  );
  testWidgets('hints during an in-flight refresh create only one follow-up', (
    tester,
  ) async {
    final api = await open(tester);
    final gate = Completer<void>();
    api.nextProgressGate = gate;
    api.steps = 47000;
    final action = tester
        .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator).first)
        .onRefresh;
    final controller = _HintRefresh(() async {
      await action();
      // Current pull refresh does not await its nested progress request.
      // The proposed narrow callback must own the actual request future.
      await api.progressCompletion;
    });
    controller.hint();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.progressCalls, 2);
    for (var i = 0; i < 100; i++) {
      controller.hint();
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.progressCalls, 2);
    gate.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(api.progressCalls, 3);
    expect(find.textContaining('47,000'), findsWidgets);
    controller.dispose();
    await close(tester);
  });
  testWidgets(
    'manual refresh renders committed score without waiting for poll',
    (tester) async {
      final api = await open(tester);
      api.steps = 45000;
      final action = tester
          .widget<AppRefreshIndicator>(find.byType(AppRefreshIndicator).first)
          .onRefresh;
      unawaited(action());
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('45,000'), findsWidgets);
      await close(tester);
    },
  );
}

// Isolated controller candidate. Uses the real screen's public refresh action;
// production would wire a narrow progress-only refresh instead of full details.
class _HintRefresh {
  _HintRefresh(this.refresh);
  final Future<void> Function() refresh;
  Timer? timer;
  bool running = false, pending = false, disposed = false;
  void hint() {
    if (disposed || timer != null) return;
    timer = Timer(const Duration(milliseconds: 100), () async {
      timer = null;
      if (running) {
        pending = true;
        return;
      }
      running = true;
      try {
        await refresh();
      } finally {
        running = false;
        if (pending) {
          pending = false;
          hint();
        }
      }
    });
  }

  void dispose() {
    disposed = true;
    timer?.cancel();
  }
}
