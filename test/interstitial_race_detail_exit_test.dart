import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/interstitial_ad.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/app_route_observer.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/interstitial_ad_service.dart';
import 'package:step_tracker/services/race_detail_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_identity_token': 'apple-token',
      'auth_user_identifier': 'apple-user',
      'auth_session_token': 'session-token',
      'auth_backend_user_id': 'user-1',
      'auth_display_name': 'Walker',
    });
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.example.bara',
      version: '1.2.3',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets(
    'real active accepted Race Detail pops before one 10-second candidate',
    (tester) async {
      final auth = AuthService();
      await auth.restoreSession();
      final api = _ActiveRaceApi();
      final coordinator = _RecordingCoordinator();
      final navigator = RaceDetailNavigator(
        authService: auth,
        backendApiService: api,
        coordinator: coordinator,
        analytics: _NoopAnalytics(api),
      );
      var refreshScheduled = false;

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: Builder(
            builder: (context) => Scaffold(
              key: const Key('underlying-route'),
              body: TextButton(
                onPressed: () => unawaited(
                  navigator.push(
                    context: context,
                    raceId: 'race-1',
                    entrySurface: RaceDetailEntrySurface.races,
                    scheduleRefresh: () => refreshScheduled = true,
                  ),
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(coordinator.primes, [InterstitialPlacement.raceDetailExit]);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('underlying-route')), findsOneWidget);
      expect(refreshScheduled, isTrue);
      expect(coordinator.presentCalls, 1);
      expect(coordinator.lastPlacement, InterstitialPlacement.raceDetailExit);
    },
  );

  testWidgets('a visit under 10 seconds never becomes an opportunity', (
    tester,
  ) async {
    final auth = AuthService();
    await auth.restoreSession();
    final api = _ActiveRaceApi();
    final coordinator = _RecordingCoordinator();
    final navigator = RaceDetailNavigator(
      authService: auth,
      backendApiService: api,
      coordinator: coordinator,
      analytics: _NoopAnalytics(api),
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              navigator.push(
                context: context,
                raceId: 'race-1',
                entrySurface: RaceDetailEntrySurface.home,
              ),
            ),
            child: const Text('OPEN'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 9));
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump(const Duration(milliseconds: 400));

    expect(coordinator.primes, isEmpty);
    expect(coordinator.presentCalls, 0);
  });

  testWidgets('native system back uses the typed back-exit result', (
    tester,
  ) async {
    final harness = await _pumpRace(tester);
    await tester.pump(const Duration(seconds: 10));

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.coordinator.presentCalls, 1);
  });

  testWidgets('nested route coverage does not count toward dwell', (
    tester,
  ) async {
    final harness = await _pumpRace(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(harness.coordinator.primes, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pump();
    // Flutter's fake timer advances while DateTime.now() does not, so use one
    // complete visible dwell window after uncovering. The assertion above is
    // the contract guard that covered time itself contributes nothing.
    await tester.pump(const Duration(seconds: 10));
    expect(harness.coordinator.primes, [InterstitialPlacement.raceDetailExit]);
  });

  testWidgets('auth replacement suppresses and records auth_replace', (
    tester,
  ) async {
    final analytics = _RecordingAnalytics(_ActiveRaceApi());
    final harness = await _pumpRace(tester, analytics: analytics);
    await tester.pump(const Duration(seconds: 10));

    await harness.auth.syncFromBackendUser(const {'id': 'user-2'});
    await harness.auth.updateSessionToken('new-user-token');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.coordinator.presentCalls, 0);
    expect(
      analytics.events
          .where((event) => event.name == 'race_detail_visit_ended')
          .single
          .context['exit_kind'],
      'auth_replace',
    );
  });

  testWidgets('missing underlying ModalRoute fails closed after pop', (
    tester,
  ) async {
    final auth = AuthService();
    await auth.restoreSession();
    final api = _ActiveRaceApi();
    final coordinator = _RecordingCoordinator();
    final navigator = RaceDetailNavigator(
      authService: auth,
      backendApiService: api,
      coordinator: coordinator,
      analytics: _NoopAnalytics(api),
    );
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [appRouteObserver],
        home: const Scaffold(body: Text('UNDERLYING')),
      ),
    );

    final routeFuture = navigator.push(
      context: navigatorKey.currentState!.overlay!.context,
      raceId: 'race-1',
      entrySurface: RaceDetailEntrySurface.home,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 10));
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump(const Duration(milliseconds: 400));
    await routeFuture;

    expect(coordinator.presentCalls, 0);
  });

  testWidgets('refresh failures never escape or block the candidate', (
    tester,
  ) async {
    final harness = await _pumpRace(
      tester,
      scheduleRefresh: () async => throw StateError('refresh failed'),
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump(const Duration(milliseconds: 400));

    expect(harness.coordinator.presentCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prime failures are swallowed and back navigation still works', (
    tester,
  ) async {
    final harness = await _pumpRace(tester, primeThrows: true);
    await tester.pump(const Duration(seconds: 10));
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('OPEN'), findsOneWidget);
    expect(harness.coordinator.presentCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

class _RaceHarness {
  const _RaceHarness({required this.auth, required this.coordinator});
  final AuthService auth;
  final _RecordingCoordinator coordinator;
}

Future<_RaceHarness> _pumpRace(
  WidgetTester tester, {
  ActivationAnalyticsService? analytics,
  FutureOr<void> Function()? scheduleRefresh,
  bool primeThrows = false,
}) async {
  final auth = AuthService();
  await auth.restoreSession();
  final api = _ActiveRaceApi();
  final coordinator = _RecordingCoordinator(primeThrows: primeThrows);
  final navigator = RaceDetailNavigator(
    authService: auth,
    backendApiService: api,
    coordinator: coordinator,
    analytics: analytics ?? _NoopAnalytics(api),
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [appRouteObserver],
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => unawaited(
            navigator.push(
              context: context,
              raceId: 'race-1',
              entrySurface: RaceDetailEntrySurface.home,
              scheduleRefresh: scheduleRefresh,
            ),
          ),
          child: const Text('OPEN'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pump(const Duration(milliseconds: 400));
  return _RaceHarness(auth: auth, coordinator: coordinator);
}

class _RecordingCoordinator implements InterstitialPresentationCoordinator {
  _RecordingCoordinator({this.primeThrows = false});
  final bool primeThrows;
  @override
  String get ownerUserId => 'user-1';
  @override
  String get sessionId => '4b7c1f1e-4a5f-4bc1-a9b8-6bd986112a61';
  final List<InterstitialPlacement> primes = [];
  int presentCalls = 0;
  InterstitialPlacement? lastPlacement;

  @override
  Future<void> prime(InterstitialPlacement placement) async {
    primes.add(placement);
    if (primeThrows) throw StateError('prime failed');
  }

  @override
  bool presentIfReady(
    InterstitialPlacement placement, {
    bool excludedFlow = false,
    bool rewardedPresented = false,
  }) {
    presentCalls++;
    lastPlacement = placement;
    return true;
  }

  @override
  Future<void> cancel(InterstitialPlacement placement) async {}
  @override
  Future<void> flushPendingImpressions() async {}
  @override
  void didEnterBackground() {}
  @override
  void didResume() {}
  @override
  void dispose() {}
}

class _NoopAnalytics extends ActivationAnalyticsService {
  _NoopAnalytics(BackendApiService api)
    : super(backendApiService: api, isIosForTesting: true);

  @override
  Future<void> record(
    String name, {
    String? sessionId,
    String? ownerUserId,
    Map<String, String> context = const {},
  }) async {}
}

class _RecordingAnalytics extends _NoopAnalytics {
  _RecordingAnalytics(super.api);
  final events = <({String name, Map<String, String> context})>[];

  @override
  Future<void> record(
    String name, {
    String? sessionId,
    String? ownerUserId,
    Map<String, String> context = const {},
  }) async => events.add((name: name, context: context));
}

class _ActiveRaceApi extends BackendApiService {
  @override
  Future<RaceBootstrapResult> fetchRaceBootstrap({
    required String identityToken,
    required String raceId,
    int? participantsLimit,
  }) async => RaceBootstrapResult(
    supported: true,
    race: {
      'id': raceId,
      'name': 'Interstitial Race',
      'status': 'ACTIVE',
      'targetSteps': 100000,
      'maxDurationDays': 7,
      'buyInAmount': 0,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'potCoins': 0,
      'heldPotCoins': 0,
      'projectedPotCoins': 0,
      'myStatus': 'ACCEPTED',
      'isCreator': false,
      'powerupsEnabled': false,
      'endsAt': '2126-12-10T12:00:00.000Z',
      'participants': const [
        {'userId': 'user-1', 'displayName': 'Walker', 'status': 'ACCEPTED'},
      ],
    },
    progress: const {
      'status': 'ACTIVE',
      'participants': [
        {
          'userId': 'user-1',
          'displayName': 'Walker',
          'totalSteps': 42000,
          'finishedAt': null,
        },
      ],
      'powerupData': {
        'enabled': false,
        'inventory': [],
        'powerupSlots': 3,
        'queuedBoxCount': 0,
        'activeEffects': [],
      },
    },
  );

  @override
  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind,
  }) async => const {'messages': [], 'events': []};
}
