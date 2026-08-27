import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/interstitial_ad.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/ad_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/interstitial_ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AdService.setConsentPermission(true);
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.3.8',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(() => AdService.setConsentPermission(false));

  test(
    'warm coalesces by placement, keeps distinct units, and performs no backend admission work',
    () async {
      final api = _PreloadApi();
      final detailLoad = Completer<InterstitialAdController?>();
      final resultsLoad = Completer<InterstitialAdController?>();
      final loadedUnits = <String>[];
      final coordinator = _coordinator(
        api: api,
        units: _units,
        loader: (unit) {
          loadedUnits.add(unit);
          return unit == 'detail-unit' ? detailLoad.future : resultsLoad.future;
        },
      );
      final dynamic subject = coordinator;

      final Future<void> firstDetail = subject.warm(
        InterstitialPlacement.raceDetailExit,
      );
      final Future<void> secondDetail = subject.warm(
        InterstitialPlacement.raceDetailExit,
      );
      final Future<void> results = subject.warm(
        InterstitialPlacement.raceResultsExit,
      );
      await _drain();

      expect(loadedUnits, ['detail-unit', 'results-unit']);
      expect(api.eligibilityCalls, 0);
      expect(api.permitCalls, 0);
      expect(api.cancelCalls, 0);
      expect(api.impressionCalls, 0);

      detailLoad.complete(_FakeInterstitial());
      resultsLoad.complete(_FakeInterstitial());
      await Future.wait<void>([firstDetail, secondDetail, results]);
      coordinator.dispose();
    },
  );

  test('prime reuses a warmed handle and cancel preserves it', () async {
    final api = _PreloadApi();
    var loads = 0;
    final handle = _FakeInterstitial();
    final coordinator = _coordinator(
      api: api,
      loader: (_) async {
        loads++;
        return handle;
      },
    );
    final dynamic subject = coordinator;

    await subject.warm(InterstitialPlacement.raceDetailExit);
    expect(api.eligibilityCalls, 0);
    await coordinator.prime(InterstitialPlacement.raceDetailExit);
    await coordinator.cancel(InterstitialPlacement.raceDetailExit);
    await coordinator.prime(InterstitialPlacement.raceDetailExit);

    expect(loads, 1);
    expect(api.permitCalls, 2);
    expect(api.cancelCalls, 1);
    expect(handle.disposeCalls, 0);
    coordinator.dispose();
    expect(handle.disposeCalls, 1);
  });

  test(
    'an ineligible flow preserves warmed inventory for a later flow',
    () async {
      final api = _PreloadApi()..eligible = false;
      var loads = 0;
      final handle = _FakeInterstitial();
      final coordinator = _coordinator(
        api: api,
        loader: (_) async {
          loads++;
          return handle;
        },
      );
      final dynamic subject = coordinator;

      await subject.warm(InterstitialPlacement.raceDetailExit);
      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      expect(api.permitCalls, 0);
      expect(handle.disposeCalls, 0);

      api.eligible = true;
      api.timeZone = 'America/Chicago';
      await coordinator.cancel(InterstitialPlacement.raceDetailExit);
      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      expect(loads, 1);
      expect(api.permitCalls, 1);
      coordinator.dispose();
    },
  );

  test(
    'a quick exit never presents a late load, while the handle stays warm',
    () async {
      final api = _PreloadApi();
      final load = Completer<InterstitialAdController?>();
      final handle = _FakeInterstitial();
      final coordinator = _coordinator(api: api, loader: (_) => load.future);

      final prime = coordinator.prime(InterstitialPlacement.raceDetailExit);
      await _drain();
      expect(
        coordinator.presentIfReady(InterstitialPlacement.raceDetailExit),
        isFalse,
      );
      load.complete(handle);
      await prime;
      expect(handle.showCalls, 0);
      expect(handle.disposeCalls, 0);

      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      expect(
        coordinator.presentIfReady(InterstitialPlacement.raceDetailExit),
        isTrue,
      );
      await _drain();
      expect(handle.showCalls, 1);
      coordinator.dispose();
    },
  );

  test(
    'consent withdrawal disposes ready and stale callback handles once',
    () async {
      final api = _PreloadApi();
      final delayed = Completer<InterstitialAdController?>();
      final ready = _FakeInterstitial();
      final stale = _FakeInterstitial();
      final coordinator = _coordinator(
        api: api,
        units: _units,
        loader: (unit) => unit == 'detail-unit'
            ? Future<InterstitialAdController?>.value(ready)
            : delayed.future,
      );
      final dynamic subject = coordinator;

      await subject.warm(InterstitialPlacement.raceDetailExit);
      final Future<void> pending = subject.warm(
        InterstitialPlacement.raceResultsExit,
      );
      await _drain();
      AdService.setConsentPermission(false);
      delayed.complete(stale);
      await pending;
      await _drain();

      expect(ready.disposeCalls, 1);
      expect(stale.disposeCalls, 1);
      expect(api.permitCalls, 0);
      coordinator.dispose();
      expect(ready.disposeCalls, 1);
      expect(stale.disposeCalls, 1);
    },
  );

  test(
    'rapid consent regrant replaces an invalidated in-flight preload',
    () async {
      final api = _PreloadApi();
      final firstLoad = Completer<InterstitialAdController?>();
      final stale = _FakeInterstitial();
      final replacement = _FakeInterstitial();
      var loads = 0;
      final coordinator = _coordinator(
        api: api,
        loader: (_) {
          loads++;
          return loads == 1
              ? firstLoad.future
              : Future<InterstitialAdController?>.value(replacement);
        },
      );
      final dynamic subject = coordinator;

      final Future<void> pending = subject.warm(
        InterstitialPlacement.raceDetailExit,
      );
      await _drain();
      AdService.setConsentPermission(false);
      AdService.setConsentPermission(true);
      firstLoad.complete(stale);
      await pending;
      await _drain(6);

      expect(loads, 2);
      expect(stale.disposeCalls, 1);
      expect(replacement.disposeCalls, 0);
      coordinator.dispose();
      expect(replacement.disposeCalls, 1);
    },
  );

  test('consent regrant preserves both retry deadlines', () async {
    final clock = _FakeClock(DateTime.utc(2026, 8, 27, 16));
    var attempts = 0;
    final coordinator = _coordinator(
      api: _PreloadApi(now: clock.value),
      now: clock.call,
      retryDelays: const [Duration(seconds: 30), Duration(minutes: 2)],
      loader: (_) async {
        attempts++;
        return null;
      },
    );
    final dynamic subject = coordinator;

    await subject.warm(InterstitialPlacement.raceDetailExit);
    expect(attempts, 1);
    AdService.setConsentPermission(false);
    clock.advance(
      const Duration(seconds: 30) - const Duration(milliseconds: 1),
    );
    AdService.setConsentPermission(true);
    await subject.warm(InterstitialPlacement.raceDetailExit);
    await _drain();
    expect(attempts, 1, reason: 'the 30-second retry must not be bypassed');

    clock.advance(const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(attempts, 2);
    await _drain();

    AdService.setConsentPermission(false);
    clock.advance(const Duration(minutes: 2) - const Duration(milliseconds: 1));
    AdService.setConsentPermission(true);
    await subject.warm(InterstitialPlacement.raceDetailExit);
    await _drain();
    expect(attempts, 2, reason: 'the two-minute retry must not be bypassed');

    clock.advance(const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(attempts, 3);
    coordinator.dispose();
  });

  test('backgrounding retains a valid warm across a renewed session', () async {
    final clock = _FakeClock(DateTime.utc(2026, 8, 27, 16));
    final api = _PreloadApi(now: clock.value);
    final handle = _FakeInterstitial();
    var loads = 0;
    final coordinator = _coordinator(
      api: api,
      now: clock.call,
      loader: (_) async {
        loads++;
        return handle;
      },
    );
    final dynamic subject = coordinator;

    await subject.warm(InterstitialPlacement.raceDetailExit);
    final oldSession = coordinator.sessionId;
    coordinator.didEnterBackground();
    clock.advance(const Duration(seconds: 30));
    coordinator.didResume();
    await subject.warm(InterstitialPlacement.raceDetailExit);

    expect(coordinator.sessionId, isNot(oldSession));
    expect(loads, 1);
    expect(handle.disposeCalls, 0);
    coordinator.dispose();
  });

  test(
    'cross-placement prime preserves both inventory and the active permit',
    () async {
      final api = _PreloadApi();
      final handles = <String, _FakeInterstitial>{
        'detail-unit': _FakeInterstitial(),
        'results-unit': _FakeInterstitial(),
      };
      final coordinator = _coordinator(
        api: api,
        units: _units,
        loader: (unit) async => handles[unit],
      );
      final dynamic subject = coordinator;

      await Future.wait<void>([
        subject.warm(InterstitialPlacement.raceDetailExit),
        subject.warm(InterstitialPlacement.raceResultsExit),
      ]);
      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      await coordinator.prime(InterstitialPlacement.raceResultsExit);

      expect(api.permitCalls, 1);
      expect(api.cancelCalls, 0);
      expect(
        handles.values.map((handle) => handle.disposeCalls),
        everyElement(0),
      );
      expect(
        coordinator.presentIfReady(InterstitialPlacement.raceDetailExit),
        isTrue,
      );
      await _drain();
      coordinator.dispose();
    },
  );

  test(
    'expiry cancels only the bound permit and replacement cannot use it',
    () async {
      final clock = _FakeClock(DateTime.utc(2026, 8, 27, 16));
      final api = _PreloadApi(now: clock.value);
      final handles = [_FakeInterstitial(), _FakeInterstitial()];
      var loads = 0;
      final coordinator = _coordinator(
        api: api,
        now: clock.call,
        loader: (_) async => handles[loads++],
      );
      final dynamic subject = coordinator;

      await subject.warm(InterstitialPlacement.raceDetailExit);
      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      clock.advance(const Duration(hours: 1));
      await subject.warm(InterstitialPlacement.raceDetailExit);
      await _drain();

      expect(handles.first.disposeCalls, 1);
      expect(api.cancelCalls, 1);
      expect(
        coordinator.presentIfReady(InterstitialPlacement.raceDetailExit),
        isFalse,
      );
      expect(handles.last.showCalls, 0);
      coordinator.dispose();
    },
  );

  test(
    'cancellation at app-version and permit boundaries fails closed',
    () async {
      final version = Completer<String>();
      final api = _DelayedPermitApi();
      final coordinator = _coordinator(
        api: api,
        appVersionProvider: () => version.future,
        loader: (_) async => _FakeInterstitial(),
      );
      final dynamic subject = coordinator;
      await subject.warm(InterstitialPlacement.raceDetailExit);

      final firstPrime = coordinator.prime(
        InterstitialPlacement.raceDetailExit,
      );
      await _drain();
      await coordinator.cancel(InterstitialPlacement.raceDetailExit);
      version.complete('2.3.8');
      await firstPrime;
      expect(api.permitCalls, 0);

      final secondPrime = coordinator.prime(
        InterstitialPlacement.raceDetailExit,
      );
      await api.permitStarted.future;
      await coordinator.cancel(InterstitialPlacement.raceDetailExit);
      api.releasePermit.complete();
      await secondPrime;
      await _drain();
      expect(api.cancelCalls, 1);
      coordinator.dispose();
    },
  );

  test(
    'retry budget is bounded and resets on a renewed foreground session',
    () async {
      final clock = _FakeClock(DateTime.utc(2026, 8, 27, 16));
      final api = _PreloadApi(now: clock.value);
      var attempts = 0;
      final coordinator = _coordinator(
        api: api,
        now: clock.call,
        retryDelays: const [Duration.zero, Duration.zero],
        loader: (_) async {
          attempts++;
          return attempts == 4 ? _FakeInterstitial() : null;
        },
      );
      final dynamic subject = coordinator;

      await subject.warm(InterstitialPlacement.raceDetailExit);
      await _drain(8);
      expect(attempts, 3);

      coordinator.didEnterBackground();
      clock.advance(const Duration(seconds: 30));
      coordinator.didResume();
      await _drain(4);
      expect(attempts, 4);
      coordinator.dispose();
    },
  );

  test(
    'denied consent, missing unit, and other platforms never load',
    () async {
      final api = _PreloadApi();
      var loads = 0;
      Future<InterstitialAdController?> loader(String _) async {
        loads++;
        return _FakeInterstitial();
      }

      AdService.setConsentPermission(false);
      final denied = _coordinator(api: api, loader: loader);
      final dynamic deniedSubject = denied;
      await deniedSubject.warm(InterstitialPlacement.raceDetailExit);
      denied.dispose();

      AdService.setConsentPermission(true);
      final missing = _coordinator(api: api, loader: loader, units: (_) => '');
      final dynamic missingSubject = missing;
      await missingSubject.warm(InterstitialPlacement.raceDetailExit);
      missing.dispose();

      final other = _coordinator(api: api, loader: loader, platform: 'other');
      final dynamic otherSubject = other;
      await otherSubject.warm(InterstitialPlacement.raceDetailExit);
      other.dispose();

      expect(loads, 0);
      expect(api.eligibilityCalls, 0);
      expect(api.permitCalls, 0);
    },
  );

  test(
    'a stale unit callback is disposed before the replacement load starts',
    () async {
      final api = _PreloadApi();
      var unit = 'old-unit';
      final oldLoad = Completer<InterstitialAdController?>();
      final stale = _FakeInterstitial();
      final replacement = _FakeInterstitial();
      final loadedUnits = <String>[];
      final coordinator = _coordinator(
        api: api,
        units: (_) => unit,
        loader: (requestedUnit) {
          loadedUnits.add(requestedUnit);
          return requestedUnit == 'old-unit'
              ? oldLoad.future
              : Future<InterstitialAdController?>.value(replacement);
        },
      );
      final dynamic subject = coordinator;

      final Future<void> first = subject.warm(
        InterstitialPlacement.raceDetailExit,
      );
      await _drain();
      unit = 'new-unit';
      final Future<void> second = subject.warm(
        InterstitialPlacement.raceDetailExit,
      );
      oldLoad.complete(stale);
      await Future.wait<void>([first, second]);
      await _drain();

      expect(loadedUnits, ['old-unit', 'new-unit']);
      expect(stale.disposeCalls, 1);
      expect(replacement.disposeCalls, 0);
      coordinator.dispose();
    },
  );

  test(
    'background cancels retry timing but retains a completed warm handle',
    () async {
      final api = _PreloadApi();
      var attempts = 0;
      final coordinator = _coordinator(
        api: api,
        now: DateTime.now,
        retryDelays: const [Duration(milliseconds: 30), Duration(minutes: 2)],
        loader: (_) async {
          attempts++;
          return null;
        },
      );
      final dynamic subject = coordinator;

      await subject.warm(InterstitialPlacement.raceDetailExit);
      coordinator.didEnterBackground();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(attempts, 1);
      coordinator.didResume();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(attempts, 2);
      coordinator.dispose();

      final load = Completer<InterstitialAdController?>();
      final retained = _FakeInterstitial();
      final retaining = _coordinator(
        api: _PreloadApi(),
        loader: (_) => load.future,
      );
      final dynamic retainingSubject = retaining;
      final Future<void> pending = retainingSubject.warm(
        InterstitialPlacement.raceDetailExit,
      );
      retaining.didEnterBackground();
      load.complete(retained);
      await pending;
      expect(retained.disposeCalls, 0);
      retaining.didResume();
      await retainingSubject.warm(InterstitialPlacement.raceDetailExit);
      expect(retained.disposeCalls, 0);
      retaining.dispose();
    },
  );

  test(
    'confirmed impression disposes sibling inventory and suppresses loading',
    () async {
      final api = _PreloadApi();
      final detail = _FakeInterstitial(impresses: true);
      final results = _FakeInterstitial();
      var loads = 0;
      final coordinator = _coordinator(
        api: api,
        units: _units,
        loader: (unit) async {
          loads++;
          return unit == 'detail-unit' ? detail : results;
        },
      );
      final dynamic subject = coordinator;

      await Future.wait<void>([
        subject.warm(InterstitialPlacement.raceDetailExit),
        subject.warm(InterstitialPlacement.raceResultsExit),
      ]);
      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      expect(
        coordinator.presentIfReady(InterstitialPlacement.raceDetailExit),
        isTrue,
      );
      await _drain(8);
      await subject.warm(InterstitialPlacement.raceResultsExit);

      expect(api.impressionCalls, 1);
      expect(results.disposeCalls, 1);
      expect(loads, 2);
      coordinator.dispose();
    },
  );

  test(
    'an eligible exit without both components retains not_ready analytics',
    () async {
      final api = _PreloadApi();
      final analytics = _RecordingAnalytics(api);
      final coordinator = _coordinator(api: api, analytics: analytics);

      expect(
        coordinator.presentIfReady(InterstitialPlacement.raceDetailExit),
        isFalse,
      );
      await _drain();

      final skipped = analytics.events.singleWhere(
        (event) => event.name == 'interstitial_skipped',
      );
      expect(skipped.context, {
        'placement': 'race_detail_exit',
        'reason': 'not_ready',
      });
      coordinator.dispose();
    },
  );

  test(
    'consent-unavailable exit queues the allowlisted not_ready reason',
    () async {
      final api = _PreloadApi();
      final analytics = ActivationAnalyticsService(
        backendApiService: api,
        isIosForTesting: true,
      );
      final coordinator = _coordinator(api: api, analytics: analytics);
      AdService.setConsentPermission(false);

      expect(
        coordinator.presentIfReady(InterstitialPlacement.raceDetailExit),
        isFalse,
      );
      await _drain(8);

      final prefs = await SharedPreferences.getInstance();
      final events =
          jsonDecode(prefs.getString('activation_events_v1')!) as List<dynamic>;
      final queued = events.cast<Map<String, dynamic>>();
      expect(queued.map((event) => event['name']), [
        'interstitial_opportunity',
        'interstitial_skipped',
      ]);
      expect(queued.map((event) => event['onboardingSessionId']).toSet(), {
        '4b7c1f1e-4a5f-4bc1-a9b8-6bd986112a61',
      });
      final skipped = queued.last;
      expect(skipped['context'], {
        'placement': 'race_detail_exit',
        'reason': 'not_ready',
      });
      coordinator.dispose();
    },
  );
}

String _units(InterstitialPlacement placement) => switch (placement) {
  InterstitialPlacement.raceDetailExit => 'detail-unit',
  InterstitialPlacement.raceResultsExit => 'results-unit',
};

InterstitialAdCoordinator _coordinator({
  required _PreloadApi api,
  InterstitialAdLoader? loader,
  String Function(InterstitialPlacement)? units,
  DateTime Function()? now,
  Future<String> Function()? appVersionProvider,
  List<Duration>? retryDelays,
  String platform = 'ios',
  ActivationAnalyticsService? analytics,
}) {
  final clock = now ?? () => api.now;
  return InterstitialAdCoordinator(
    ownerUserId: 'user-1',
    identityToken: 'token-1',
    backendApiService: api,
    analytics:
        analytics ??
        ActivationAnalyticsService(
          backendApiService: api,
          isIosForTesting: true,
        ),
    backendBaseUrl: 'https://example.test',
    adUnitIdForPlacement: units ?? (_) => 'detail-unit',
    platform: platform,
    now: clock,
    fullScreenTracker: FullScreenPresentationTracker(now: clock),
    loader: loader ?? (_) async => _FakeInterstitial(),
    sessionId: '4b7c1f1e-4a5f-4bc1-a9b8-6bd986112a61',
    sessionStartedAt: clock().subtract(const Duration(minutes: 2)),
    appVersionProvider: appVersionProvider,
    retryDelays: retryDelays,
  );
}

Future<void> _drain([int turns = 3]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeClock {
  _FakeClock(this.value);
  DateTime value;
  DateTime call() => value;
  void advance(Duration duration) => value = value.add(duration);
}

class _FakeInterstitial implements InterstitialAdController {
  _FakeInterstitial({this.impresses = false});

  final bool impresses;
  int disposeCalls = 0;
  int showCalls = 0;

  @override
  Future<InterstitialShowOutcome> show({
    required VoidCallback onShowed,
    required VoidCallback onImpression,
  }) async {
    showCalls++;
    onShowed();
    if (impresses) onImpression();
    return InterstitialShowOutcome.dismissed;
  }

  @override
  void dispose() => disposeCalls++;
}

class _RecordingAnalytics extends ActivationAnalyticsService {
  _RecordingAnalytics(BackendApiService api)
    : super(backendApiService: api, isIosForTesting: true);

  final events = <({String name, Map<String, String> context})>[];

  @override
  Future<void> record(
    String name, {
    String? sessionId,
    String? ownerUserId,
    Map<String, String> context = const {},
  }) async {
    events.add((name: name, context: Map<String, String>.of(context)));
  }
}

class _PreloadApi extends BackendApiService {
  _PreloadApi({DateTime? now}) : now = now ?? DateTime.utc(2026, 8, 27, 16);

  DateTime now;
  bool eligible = true;
  int eligibilityCalls = 0;
  int permitCalls = 0;
  int cancelCalls = 0;
  int impressionCalls = 0;
  String timeZone = 'America/New_York';

  @override
  Future<String?> getEffectiveTimeZone() async => timeZone;

  @override
  Future<InterstitialEligibility> fetchInterstitialEligibility({
    required String identityToken,
    required InterstitialPlacement placement,
    required String sessionId,
    required DateTime sessionStartedAt,
  }) async {
    eligibilityCalls++;
    return InterstitialEligibility(
      eligible: eligible,
      reason: eligible ? null : 'acquisition_grace',
      dailyCount: 0,
      dailyLimit: 2,
      capDate: '2026-08-27',
      timeZone: timeZone,
      serverTime: now,
    );
  }

  @override
  Future<InterstitialPermitGrant> createInterstitialPermit({
    required String identityToken,
    required InterstitialPlacement placement,
    required String sessionId,
    required DateTime sessionStartedAt,
    required String appVersion,
    required String platform,
    required DateTime now,
  }) async {
    permitCalls++;
    return _grant(placement: placement, sessionId: sessionId, now: now);
  }

  @override
  Future<void> cancelInterstitialPermit({
    required String identityToken,
    required String permitId,
  }) async {
    cancelCalls++;
  }

  @override
  Future<void> reportInterstitialImpression({
    required String identityToken,
    required String eventId,
    required String permitId,
    required InterstitialPlacement placement,
    required String sessionId,
    required DateTime occurredAt,
    required String appVersion,
    required String platform,
  }) async {
    impressionCalls++;
  }
}

class _DelayedPermitApi extends _PreloadApi {
  final permitStarted = Completer<void>();
  final releasePermit = Completer<void>();

  @override
  Future<InterstitialPermitGrant> createInterstitialPermit({
    required String identityToken,
    required InterstitialPlacement placement,
    required String sessionId,
    required DateTime sessionStartedAt,
    required String appVersion,
    required String platform,
    required DateTime now,
  }) async {
    permitCalls++;
    if (!permitStarted.isCompleted) permitStarted.complete();
    await releasePermit.future;
    return _grant(placement: placement, sessionId: sessionId, now: now);
  }
}

InterstitialPermitGrant _grant({
  required InterstitialPlacement placement,
  required String sessionId,
  required DateTime now,
}) => InterstitialPermitGrant(
  eligible: true,
  permit: InterstitialPermit(
    id: '72eea3de-e676-40f1-8424-cae47564d311',
    placement: placement,
    sessionId: sessionId,
    showBy: now.add(const Duration(hours: 1)),
    reservationUntil: now.add(const Duration(hours: 24)),
  ),
  capDate: '2026-08-27',
  timeZone: 'America/New_York',
  serverTime: now,
);
