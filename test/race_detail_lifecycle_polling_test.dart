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
  _CountingActiveRaceApi({this.status = 'ACTIVE'});

  final String status;
  int progressCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
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
        {'userId': 'user-1', 'displayName': 'Trail Walker', 'status': 'ACCEPTED'},
        {'userId': 'user-2', 'displayName': 'Hill Climber', 'status': 'ACCEPTED'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    progressCalls += 1;
    // Report ACTIVE regardless of the details status: a COMPLETED race never
    // reaches _loadProgress, so this is only exercised for the active flow.
    return {
      'status': 'ACTIVE',
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
      'powerupData': const {
        'enabled': false,
        'inventory': [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
      },
    };
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

  group('racePollLifecycleAction (pure decision)', () {
    test('paused pauses the poll', () {
      expect(
        racePollLifecycleAction(AppLifecycleState.paused, wasPolling: true),
        RacePollLifecycleAction.pause,
      );
    });

    test('hidden pauses the poll', () {
      expect(
        racePollLifecycleAction(AppLifecycleState.hidden, wasPolling: true),
        RacePollLifecycleAction.pause,
      );
    });

    test('resumed after polling resumes (immediate refresh + restart)', () {
      expect(
        racePollLifecycleAction(AppLifecycleState.resumed, wasPolling: true),
        RacePollLifecycleAction.resume,
      );
    });

    test('resumed when polling was never active does nothing', () {
      expect(
        racePollLifecycleAction(AppLifecycleState.resumed, wasPolling: false),
        RacePollLifecycleAction.none,
      );
    });

    test('inactive is a no-op (transient, do not cancel)', () {
      expect(
        racePollLifecycleAction(AppLifecycleState.inactive, wasPolling: true),
        RacePollLifecycleAction.none,
      );
    });

    test('detached is a no-op', () {
      expect(
        racePollLifecycleAction(AppLifecycleState.detached, wasPolling: true),
        RacePollLifecycleAction.none,
      );
    });
  });

  group('RaceDetailScreen lifecycle-aware polling (widget)', () {
    testWidgets('pause stops the poll; resume refreshes immediately + restarts',
        (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _CountingActiveRaceApi();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-lifecycle',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Initial load fires exactly one progress fetch (the parallel prefetch).
      expect(api.progressCalls, 1);

      // A 30s tick drives one poll.
      await tester.pump(const Duration(seconds: 30));
      expect(api.progressCalls, 2);

      // Background: the poll timer is cancelled, so time passing yields nothing.
      await _background(tester);
      await tester.pump(const Duration(seconds: 90));
      expect(api.progressCalls, 2);

      // Foreground: one immediate refresh right away...
      await _foreground(tester);
      expect(api.progressCalls, 3);

      // ...then the periodic poll is running again.
      await tester.pump(const Duration(seconds: 30));
      expect(api.progressCalls, 4);

      // Tear down cleanly (unbounded hero animations never settle).
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
    });

    testWidgets('resume does nothing for a race that never polled (COMPLETED)',
        (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _CountingActiveRaceApi(status: 'COMPLETED');

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-completed',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // A COMPLETED race never starts polling; the only fetch is the parallel
      // prefetch fired before the status is known (its result is discarded).
      final baseline = api.progressCalls;

      await _background(tester);
      await _foreground(tester);
      await tester.pump(const Duration(seconds: 60));

      // No immediate refresh, no periodic poll — resume is a no-op here.
      expect(api.progressCalls, baseline);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
    });

    testWidgets('disposing while paused does not crash',
        (WidgetTester tester) async {
      final authService = await _createAuthService();
      final api = _CountingActiveRaceApi();

      await tester.pumpWidget(
        MaterialApp(
          home: RaceDetailScreen(
            authService: authService,
            raceId: 'race-dispose-paused',
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await _background(tester);

      // Dispose the screen while backgrounded, then let any stray timers fire.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 60));

      expect(tester.takeException(), isNull);
    });
  });
}
