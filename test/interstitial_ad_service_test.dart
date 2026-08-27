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
      packageName: 'com.example.bara',
      version: '1.2.3',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDown(() => AdService.setConsentPermission(false));

  test('version-skewed eligibility responses fail closed', () {
    expect(InterstitialEligibility.tryParse(null).eligible, isFalse);
    expect(
      InterstitialEligibility.tryParse(<String, dynamic>{}).eligible,
      isFalse,
    );
    expect(
      InterstitialEligibility.tryParse(<String, dynamic>{
        'eligible': true,
      }).eligible,
      isFalse,
    );
    expect(
      InterstitialEligibility.tryParse(<String, dynamic>{
        'eligible': true,
        'reason': null,
        'dailyCount': 0,
        'dailyLimit': 2,
        'capDate': '2026-08-26',
        'timeZone': 'America/New_York',
        'serverTime': '2026-08-26T18:00:00.000Z',
      }).eligible,
      isTrue,
    );
  });

  test('invalid timezone stays a bounded ineligible reason', () {
    final parsed = InterstitialEligibility.tryParse(<String, dynamic>{
      'eligible': false,
      'reason': 'invalid_timezone',
      'dailyCount': 0,
      'dailyLimit': 2,
      'capDate': null,
      'timeZone': null,
      'serverTime': '2026-08-26T18:00:00.000Z',
      'nextEligibleAt': null,
    });

    expect(parsed.eligible, isFalse);
    expect(parsed.reason, 'invalid_timezone');
  });

  test(
    'permit parser rejects unknown, mismatched, and nearly expired data',
    () {
      const placement = InterstitialPlacement.raceDetailExit;
      const sessionId = '4b7c1f1e-4a5f-4bc1-a9b8-6bd986112a61';
      final now = DateTime.utc(2026, 8, 26, 18);
      expect(
        InterstitialPermit.tryParse(
          <String, dynamic>{
            'id': '72eea3de-e676-40f1-8424-cae47564d311',
            'placement': placement.wireName,
            'sessionId': sessionId,
            'showBy': now.add(const Duration(seconds: 14)).toIso8601String(),
            'reservationUntil': now
                .add(const Duration(hours: 24))
                .toIso8601String(),
          },
          expectedPlacement: placement,
          expectedSessionId: sessionId,
          now: now,
        ),
        isNull,
      );
      expect(
        InterstitialPermit.tryParse(
          <String, dynamic>{
            'id': '72eea3de-e676-40f1-8424-cae47564d311',
            'placement': placement.wireName,
            'sessionId': sessionId,
            'showBy': now.add(const Duration(minutes: 1)).toIso8601String(),
            'reservationUntil': now
                .add(const Duration(hours: 24))
                .toIso8601String(),
          },
          expectedPlacement: placement,
          expectedSessionId: sessionId,
          now: now,
        ),
        isNotNull,
      );
    },
  );

  test(
    'fullscreen tracker persists the 30 minute suppression boundary',
    () async {
      final now = DateTime.utc(2026, 8, 26, 18);
      final tracker = FullScreenPresentationTracker(now: () => now);
      await tracker.recordPresented();

      final restored = FullScreenPresentationTracker(
        now: () => now.add(const Duration(minutes: 29)),
      );
      expect(await restored.wasPresentedRecently(), isTrue);

      final expired = FullScreenPresentationTracker(
        now: () => now.add(const Duration(minutes: 30)),
      );
      expect(await expired.wasPresentedRecently(), isFalse);
    },
  );

  test(
    'race visit stamps first load and counts only visible foreground dwell',
    () {
      final clock = _FakeClock(DateTime.utc(2026, 8, 26, 18));
      final visit = RaceDetailInterstitialVisit(
        entrySurface: RaceDetailEntrySurface.races,
        entryOrigin: RaceDetailEntryOrigin.existing,
        now: clock.call,
        onPrime: () {},
      );

      visit.stampFirstAuthoritativeLoad(
        raceStatus: 'ACTIVE',
        participantStatus: 'ACCEPTED',
      );
      visit.setCovered(false);
      clock.advance(const Duration(seconds: 6));
      visit.setCovered(true);
      clock.advance(const Duration(seconds: 20));
      visit.setCovered(false);
      clock.advance(const Duration(seconds: 4));

      expect(visit.hasQualifyingDwell, isTrue);
      expect(visit.scopeResult, RaceDetailScopeResult.activeAccepted);
      visit.dispose();
    },
  );

  test('newly-created and first-load-ineligible visits never upgrade', () {
    final clock = _FakeClock(DateTime.utc(2026, 8, 26, 18));
    for (final visit in <RaceDetailInterstitialVisit>[
      RaceDetailInterstitialVisit(
        entrySurface: RaceDetailEntrySurface.home,
        entryOrigin: RaceDetailEntryOrigin.newlyCreated,
        now: clock.call,
        onPrime: () {},
      ),
      RaceDetailInterstitialVisit(
        entrySurface: RaceDetailEntrySurface.publicRaces,
        entryOrigin: RaceDetailEntryOrigin.existing,
        now: clock.call,
        onPrime: () {},
      ),
    ]) {
      visit.stampFirstAuthoritativeLoad(
        raceStatus: 'PENDING',
        participantStatus: 'INVITED',
      );
      visit.stampFirstAuthoritativeLoad(
        raceStatus: 'ACTIVE',
        participantStatus: 'ACCEPTED',
      );
      clock.advance(const Duration(seconds: 20));
      expect(visit.hasQualifyingDwell, isFalse);
      expect(visit.scopeResult, RaceDetailScopeResult.ineligible);
      visit.dispose();
    }
  });

  test('coverage and eligibility revocation invalidate a primed visit', () {
    for (final invalidate in <void Function(RaceDetailInterstitialVisit)>[
      (visit) => visit.setCovered(true),
      (visit) => visit.revoke(),
    ]) {
      var primes = 0;
      var invalidations = 0;
      final visit = RaceDetailInterstitialVisit(
        entrySurface: RaceDetailEntrySurface.races,
        entryOrigin: RaceDetailEntryOrigin.existing,
        dwellRequired: Duration.zero,
        onPrime: () => primes++,
        onInvalidate: () => invalidations++,
      );
      visit.stampFirstAuthoritativeLoad(
        raceStatus: 'ACTIVE',
        participantStatus: 'ACCEPTED',
      );
      expect(primes, 1);

      invalidate(visit);

      expect(invalidations, 1);
      visit.dispose();
    }
  });

  test('typed route defaults native back to backExit', () {
    final route = RaceDetailPageRoute(builder: (_) => const SizedBox());
    expect(route.currentResult, RaceDetailRouteResult.backExit);
  });

  test(
    'placement unit resolution never borrows another placement or platform',
    () {
      expect(
        AdService.resolveInterstitialAdUnitId(
          placement: InterstitialPlacement.raceDetailExit,
          platform: 'ios',
          iosRaceDetailUnitId: 'ios-detail',
          iosRaceResultsUnitId: 'ios-results',
          androidRaceDetailUnitId: 'android-detail',
          androidRaceResultsUnitId: 'android-results',
        ),
        'ios-detail',
      );
      expect(
        AdService.resolveInterstitialAdUnitId(
          placement: InterstitialPlacement.raceResultsExit,
          platform: 'ios',
          iosRaceDetailUnitId: 'ios-detail',
          iosRaceResultsUnitId: 'ios-results',
          androidRaceDetailUnitId: 'android-detail',
          androidRaceResultsUnitId: 'android-results',
        ),
        'ios-results',
      );
      expect(
        AdService.resolveInterstitialAdUnitId(
          placement: InterstitialPlacement.raceDetailExit,
          platform: 'android',
          iosRaceDetailUnitId: 'ios-detail',
          iosRaceResultsUnitId: 'ios-results',
          androidRaceDetailUnitId: 'android-detail',
          androidRaceResultsUnitId: 'android-results',
        ),
        'android-detail',
      );
      expect(
        AdService.resolveInterstitialAdUnitId(
          placement: InterstitialPlacement.raceResultsExit,
          platform: 'android',
          iosRaceDetailUnitId: 'ios-detail',
          iosRaceResultsUnitId: 'ios-results',
          androidRaceDetailUnitId: 'android-detail',
          androidRaceResultsUnitId: 'android-results',
        ),
        'android-results',
      );
      expect(
        AdService.resolveInterstitialAdUnitId(
          placement: InterstitialPlacement.raceResultsExit,
          platform: 'ios',
          iosRaceDetailUnitId: 'ios-detail',
          iosRaceResultsUnitId: '',
          androidRaceDetailUnitId: 'android-detail',
          androidRaceResultsUnitId: 'android-results',
        ),
        isEmpty,
      );
      expect(
        AdService.resolveInterstitialAdUnitId(
          placement: InterstitialPlacement.raceDetailExit,
          platform: 'other',
          iosRaceDetailUnitId: 'ios-detail',
          iosRaceResultsUnitId: 'ios-results',
          androidRaceDetailUnitId: 'android-detail',
          androidRaceResultsUnitId: 'android-results',
        ),
        isEmpty,
      );
    },
  );

  test('coordinator loads the unit selected for each placement', () async {
    final loadedUnits = <String>[];
    final now = DateTime.utc(2026, 8, 26, 18);
    final api = _InterstitialApi(now);
    final coordinator = InterstitialAdCoordinator(
      ownerUserId: 'user-a',
      identityToken: 'token-a',
      backendApiService: api,
      analytics: ActivationAnalyticsService(
        backendApiService: api,
        isIosForTesting: true,
      ),
      backendBaseUrl: 'https://example.test',
      adUnitIdForPlacement: (placement) => switch (placement) {
        InterstitialPlacement.raceDetailExit => 'detail-unit',
        InterstitialPlacement.raceResultsExit => 'results-unit',
      },
      platform: 'ios',
      now: () => now,
      fullScreenTracker: FullScreenPresentationTracker(now: () => now),
      loader: (unit) async {
        loadedUnits.add(unit);
        return _FakeInterstitial(impresses: false);
      },
      sessionId: _sessionId,
      sessionStartedAt: now.subtract(const Duration(minutes: 2)),
    );

    await coordinator.prime(InterstitialPlacement.raceDetailExit);
    await coordinator.cancel(InterstitialPlacement.raceDetailExit);
    await coordinator.prime(InterstitialPlacement.raceResultsExit);

    expect(loadedUnits, ['detail-unit', 'results-unit']);
    coordinator.dispose();
  });

  test(
    'an absent placement unit does no backend or SDK work while its sibling works',
    () async {
      final loadedUnits = <String>[];
      final now = DateTime.utc(2026, 8, 26, 18);
      final api = _InterstitialApi(now);
      final coordinator = _coordinator(
        now: now,
        api: api,
        adUnitId: null,
        adUnitIdForPlacement: (placement) => switch (placement) {
          InterstitialPlacement.raceDetailExit => '',
          InterstitialPlacement.raceResultsExit => 'results-unit',
        },
        loader: (unit) async {
          loadedUnits.add(unit);
          return _FakeInterstitial(impresses: false);
        },
      );

      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      expect(api.eligibilityCalls, 0);
      expect(api.permitCalls, 0);
      expect(loadedUnits, isEmpty);

      await coordinator.prime(InterstitialPlacement.raceResultsExit);
      expect(api.eligibilityCalls, 1);
      expect(api.permitCalls, 1);
      expect(loadedUnits, ['results-unit']);
      coordinator.dispose();
    },
  );

  test(
    'eligibility cache is placement and session bound and expires after five minutes',
    () async {
      final clock = _FakeClock(DateTime.utc(2026, 8, 26, 18));
      final api = _InterstitialApi(clock.value);
      final coordinator = InterstitialAdCoordinator(
        ownerUserId: 'user-a',
        identityToken: 'token-a',
        backendApiService: api,
        analytics: ActivationAnalyticsService(
          backendApiService: api,
          isIosForTesting: true,
        ),
        backendBaseUrl: 'https://example.test',
        adUnitId: 'test-injected-unit',
        effectiveTimeZoneProvider: () async => api.effectiveTimeZone,
        platform: 'ios',
        now: clock.call,
        fullScreenTracker: FullScreenPresentationTracker(now: clock.call),
        loader: (_) async => _FakeInterstitial(impresses: false),
        sessionId: _sessionId,
        sessionStartedAt: clock.value.subtract(const Duration(minutes: 2)),
      );

      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      await coordinator.cancel(InterstitialPlacement.raceDetailExit);
      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      expect(api.eligibilityCalls, 1);

      await coordinator.cancel(InterstitialPlacement.raceDetailExit);
      api.effectiveTimeZone = 'America/Chicago';
      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      expect(api.eligibilityCalls, 2);

      await coordinator.cancel(InterstitialPlacement.raceDetailExit);
      await coordinator.prime(InterstitialPlacement.raceResultsExit);
      expect(api.eligibilityCalls, 3);

      await coordinator.cancel(InterstitialPlacement.raceResultsExit);
      clock.advance(const Duration(minutes: 5));
      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      expect(api.eligibilityCalls, 4);

      await coordinator.cancel(InterstitialPlacement.raceDetailExit);
      coordinator.didEnterBackground();
      clock.advance(const Duration(seconds: 30));
      coordinator.didResume();
      await coordinator.prime(InterstitialPlacement.raceResultsExit);
      expect(api.eligibilityCalls, 5);
      coordinator.dispose();
    },
  );

  test('timezone provider failures skip caching without escaping', () async {
    final now = DateTime.utc(2026, 8, 26, 18);
    final api = _InterstitialApi(now);
    final coordinator = InterstitialAdCoordinator(
      ownerUserId: 'user-a',
      identityToken: 'token-a',
      backendApiService: api,
      analytics: ActivationAnalyticsService(
        backendApiService: api,
        isIosForTesting: true,
      ),
      backendBaseUrl: 'https://example.test',
      adUnitId: 'test-injected-unit',
      effectiveTimeZoneProvider: () async => throw StateError('unavailable'),
      platform: 'ios',
      now: () => now,
      fullScreenTracker: FullScreenPresentationTracker(now: () => now),
      loader: (_) async => _FakeInterstitial(impresses: false),
      sessionId: _sessionId,
      sessionStartedAt: now.subtract(const Duration(minutes: 2)),
    );

    await coordinator.prime(InterstitialPlacement.raceDetailExit);
    await coordinator.cancel(InterstitialPlacement.raceDetailExit);
    await coordinator.prime(InterstitialPlacement.raceDetailExit);

    expect(api.eligibilityCalls, 2);
    coordinator.dispose();
  });

  test(
    'only the SDK impression callback consumes and reports a permit',
    () async {
      final now = DateTime.utc(2026, 8, 26, 18);
      final api = _InterstitialApi(now);
      final handle = _FakeInterstitial(impresses: true);
      final coordinator = InterstitialAdCoordinator(
        ownerUserId: 'user-a',
        identityToken: 'token-a',
        backendApiService: api,
        analytics: ActivationAnalyticsService(
          backendApiService: api,
          isIosForTesting: true,
        ),
        backendBaseUrl: 'https://example.test',
        adUnitId: 'test-injected-unit',
        platform: 'ios',
        now: () => now,
        fullScreenTracker: FullScreenPresentationTracker(now: () => now),
        loader: (_) async => handle,
        sessionId: _sessionId,
        sessionStartedAt: now.subtract(const Duration(minutes: 2)),
      );

      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      expect(
        coordinator.presentIfReady(InterstitialPlacement.raceDetailExit),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(api.impressionReports, 1);
      expect(handle.disposed, isTrue);
    },
  );

  test(
    'dismissal without an impression cancels and does not consume',
    () async {
      final now = DateTime.utc(2026, 8, 26, 18);
      final api = _InterstitialApi(now);
      final handle = _FakeInterstitial(impresses: false);
      final coordinator = InterstitialAdCoordinator(
        ownerUserId: 'user-a',
        identityToken: 'token-a',
        backendApiService: api,
        analytics: ActivationAnalyticsService(
          backendApiService: api,
          isIosForTesting: true,
        ),
        backendBaseUrl: 'https://example.test',
        adUnitId: 'test-injected-unit',
        platform: 'ios',
        now: () => now,
        fullScreenTracker: FullScreenPresentationTracker(now: () => now),
        loader: (_) async => handle,
        sessionId: _sessionId,
        sessionStartedAt: now.subtract(const Duration(minutes: 2)),
      );

      await coordinator.prime(InterstitialPlacement.raceResultsExit);
      expect(
        coordinator.presentIfReady(InterstitialPlacement.raceResultsExit),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(api.impressionReports, 0);
      expect(api.cancelCalls, 1);
    },
  );

  test('cancelling an in-flight prime prevents a late ad load', () async {
    final now = DateTime.utc(2026, 8, 26, 18);
    final api = _DelayedEligibilityApi(now);
    var loadCalls = 0;
    final coordinator = InterstitialAdCoordinator(
      ownerUserId: 'user-a',
      identityToken: 'token-a',
      backendApiService: api,
      analytics: ActivationAnalyticsService(
        backendApiService: api,
        isIosForTesting: true,
      ),
      backendBaseUrl: 'https://example.test',
      adUnitId: 'test-injected-unit',
      platform: 'ios',
      now: () => now,
      fullScreenTracker: FullScreenPresentationTracker(now: () => now),
      loader: (_) async {
        loadCalls++;
        return _FakeInterstitial(impresses: false);
      },
      sessionId: _sessionId,
      sessionStartedAt: now.subtract(const Duration(minutes: 2)),
    );

    final prime = coordinator.prime(InterstitialPlacement.raceDetailExit);
    await api.eligibilityStarted.future;
    await coordinator.cancel(InterstitialPlacement.raceDetailExit);
    api.releaseEligibility.complete();
    await prime;

    expect(loadCalls, 0);
    expect(
      coordinator.presentIfReady(InterstitialPlacement.raceDetailExit),
      isFalse,
    );
  });

  test('a not-ready terminal exit cancels its in-flight prime', () async {
    final now = DateTime.utc(2026, 8, 26, 18);
    final api = _DelayedEligibilityApi(now);
    var loadCalls = 0;
    final coordinator = InterstitialAdCoordinator(
      ownerUserId: 'user-a',
      identityToken: 'token-a',
      backendApiService: api,
      analytics: ActivationAnalyticsService(
        backendApiService: api,
        isIosForTesting: true,
      ),
      backendBaseUrl: 'https://example.test',
      adUnitId: 'test-injected-unit',
      platform: 'ios',
      now: () => now,
      fullScreenTracker: FullScreenPresentationTracker(now: () => now),
      loader: (_) async {
        loadCalls++;
        return _FakeInterstitial(impresses: false);
      },
      sessionId: _sessionId,
      sessionStartedAt: now.subtract(const Duration(minutes: 2)),
    );

    final prime = coordinator.prime(InterstitialPlacement.raceDetailExit);
    await api.eligibilityStarted.future;
    expect(
      coordinator.presentIfReady(InterstitialPlacement.raceDetailExit),
      isFalse,
    );
    api.releaseEligibility.complete();
    await prime;

    expect(loadCalls, 0);
    expect(api.cancelCalls, 0);
  });

  test(
    'disposing during a shown ad leaves permit ownership to show completion',
    () async {
      final now = DateTime.utc(2026, 8, 26, 18);
      final api = _InterstitialApi(now);
      final handle = _ControlledInterstitial();
      final coordinator = _coordinator(
        now: now,
        api: api,
        loader: (_) async => handle,
      );

      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      expect(
        coordinator.presentIfReady(InterstitialPlacement.raceDetailExit),
        isTrue,
      );
      await handle.started.future;
      coordinator.dispose();
      expect(api.cancelCalls, 0);

      handle.impress();
      handle.complete(InterstitialShowOutcome.dismissed);
      await _drainAsync();
      expect(api.cancelCalls, 0);
      expect(api.impressionReports, 0);

      final retryApi = _InterstitialApi(now);
      final restored = _coordinator(now: now, api: retryApi);
      await restored.flushPendingImpressions();
      expect(retryApi.impressionReports, 1);
      restored.dispose();
    },
  );

  test(
    'disposing during show cancels only after no-impression completion',
    () async {
      final now = DateTime.utc(2026, 8, 26, 18);
      final api = _InterstitialApi(now);
      final handle = _ControlledInterstitial();
      final coordinator = _coordinator(
        now: now,
        api: api,
        loader: (_) async => handle,
      );

      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      coordinator.presentIfReady(InterstitialPlacement.raceDetailExit);
      await handle.started.future;
      coordinator.dispose();
      expect(api.cancelCalls, 0);

      handle.complete(InterstitialShowOutcome.failed);
      await _drainAsync();
      expect(api.cancelCalls, 1);
      expect(api.impressionReports, 0);
    },
  );

  test(
    'queue bounds are partition-local and do not evict another account',
    () async {
      final now = DateTime.utc(2026, 8, 26, 18);
      final seeded = <Map<String, dynamic>>[
        for (var i = 0; i < 20; i++)
          _storedFact(
            ownerUserId: 'user-a',
            backendBaseUrl: 'https://example.test',
            sessionId:
                '10000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
            occurredAt: now,
            suffix: i,
          ),
      ];
      SharedPreferences.setMockInitialValues({
        'interstitial_impression_facts_v1': jsonEncode(seeded),
      });
      final api = _InterstitialApi(now, reportErrorStatus: 500);
      final handle = _FakeInterstitial(impresses: true);
      final coordinator = _coordinator(
        now: now,
        api: api,
        ownerUserId: 'user-b',
        identityToken: 'token-b',
        loader: (_) async => handle,
      );

      await coordinator.prime(InterstitialPlacement.raceDetailExit);
      coordinator.presentIfReady(InterstitialPlacement.raceDetailExit);
      await _drainAsync();

      final facts = await _storedFacts();
      expect(
        facts.where((fact) => fact['ownerUserId'] == 'user-a'),
        hasLength(20),
      );
      expect(
        facts.where((fact) => fact['ownerUserId'] == 'user-b'),
        hasLength(1),
      );
    },
  );

  test(
    '404 facts survive restart and never flush under another account',
    () async {
      final now = DateTime.utc(2026, 8, 26, 18);
      final firstApi = _InterstitialApi(now, reportErrorStatus: 404);
      final first = _coordinator(
        now: now,
        api: firstApi,
        loader: (_) async => _FakeInterstitial(impresses: true),
      );
      await first.prime(InterstitialPlacement.raceDetailExit);
      first.presentIfReady(InterstitialPlacement.raceDetailExit);
      await _drainAsync();
      expect(await _storedFacts(), hasLength(1));
      first.dispose();

      final otherApi = _InterstitialApi(now);
      final other = _coordinator(
        now: now,
        api: otherApi,
        ownerUserId: 'user-b',
        identityToken: 'token-b',
      );
      await other.flushPendingImpressions();
      expect(otherApi.impressionReports, 0);
      expect(await _storedFacts(), hasLength(1));
      other.dispose();

      final retryApi = _InterstitialApi(now);
      final restored = _coordinator(now: now, api: retryApi);
      await restored.flushPendingImpressions();
      expect(retryApi.impressionReports, 1);
      expect(await _storedFacts(), isEmpty);
      restored.dispose();
    },
  );

  test('repeated background callbacks preserve the first session boundary', () {
    final clock = _FakeClock(DateTime.utc(2026, 8, 26, 18));
    final api = _InterstitialApi(clock.value);
    final coordinator = InterstitialAdCoordinator(
      ownerUserId: 'user-a',
      identityToken: 'token-a',
      backendApiService: api,
      analytics: ActivationAnalyticsService(
        backendApiService: api,
        isIosForTesting: true,
      ),
      backendBaseUrl: 'https://example.test',
      adUnitId: 'test-injected-unit',
      platform: 'ios',
      now: clock.call,
      sessionId: _sessionId,
      sessionStartedAt: clock.value.subtract(const Duration(minutes: 2)),
    );

    coordinator.didEnterBackground();
    clock.advance(const Duration(seconds: 20));
    coordinator.didEnterBackground();
    clock.advance(const Duration(seconds: 15));
    coordinator.didResume();

    expect(coordinator.sessionId, isNot(_sessionId));
  });

  test(
    'local session cooldown and daily tombstones fail closed before HTTP',
    () async {
      final now = DateTime.utc(2026, 8, 26, 18);
      final cases = <List<Map<String, dynamic>>>[
        [
          _storedFact(
            ownerUserId: 'user-a',
            backendBaseUrl: 'https://example.test',
            sessionId: _sessionId,
            occurredAt: now.subtract(const Duration(hours: 9)),
            suffix: 51,
          ),
        ],
        [
          _storedFact(
            ownerUserId: 'user-a',
            backendBaseUrl: 'https://example.test',
            sessionId: '50000000-0000-4000-8000-000000000001',
            occurredAt: now.subtract(const Duration(hours: 1)),
            suffix: 52,
          ),
        ],
        [
          _storedFact(
            ownerUserId: 'user-a',
            backendBaseUrl: 'https://example.test',
            sessionId: '50000000-0000-4000-8000-000000000002',
            occurredAt: now.subtract(const Duration(hours: 9)),
            suffix: 53,
          ),
          _storedFact(
            ownerUserId: 'user-a',
            backendBaseUrl: 'https://example.test',
            sessionId: '50000000-0000-4000-8000-000000000003',
            occurredAt: now.subtract(const Duration(hours: 17)),
            suffix: 54,
          ),
        ],
      ];
      for (final facts in cases) {
        SharedPreferences.setMockInitialValues({
          'interstitial_impression_facts_v1': jsonEncode(facts),
        });
        final api = _InterstitialApi(now, reportErrorStatus: 500);
        final coordinator = _coordinator(now: now, api: api);

        await coordinator.prime(InterstitialPlacement.raceDetailExit);

        expect(api.eligibilityCalls, 0);
        coordinator.dispose();
      }
    },
  );

  test(
    'rewarded visit flag releases a loaded permit without showing',
    () async {
      final now = DateTime.utc(2026, 8, 26, 18);
      final api = _InterstitialApi(now);
      final handle = _FakeInterstitial(impresses: true);
      final coordinator = _coordinator(
        now: now,
        api: api,
        loader: (_) async => handle,
      );
      await coordinator.prime(InterstitialPlacement.raceDetailExit);

      expect(
        coordinator.presentIfReady(
          InterstitialPlacement.raceDetailExit,
          rewardedPresented: true,
        ),
        isFalse,
      );
      await _drainAsync();

      expect(api.cancelCalls, 1);
      expect(api.impressionReports, 0);
      expect(handle.disposed, isTrue);
    },
  );
}

const _sessionId = '4b7c1f1e-4a5f-4bc1-a9b8-6bd986112a61';

class _InterstitialApi extends BackendApiService {
  _InterstitialApi(this.now, {this.reportErrorStatus});
  final DateTime now;
  final int? reportErrorStatus;
  int impressionReports = 0;
  int cancelCalls = 0;
  int eligibilityCalls = 0;
  int permitCalls = 0;
  String effectiveTimeZone = 'America/New_York';

  @override
  Future<InterstitialEligibility> fetchInterstitialEligibility({
    required String identityToken,
    required InterstitialPlacement placement,
    required String sessionId,
    required DateTime sessionStartedAt,
  }) async {
    eligibilityCalls++;
    return InterstitialEligibility(
      eligible: true,
      dailyCount: 0,
      dailyLimit: 2,
      capDate: '2026-08-26',
      timeZone: effectiveTimeZone,
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
    return InterstitialPermitGrant(
      eligible: true,
      permit: InterstitialPermit(
        id: '72eea3de-e676-40f1-8424-cae47564d311',
        placement: placement,
        sessionId: sessionId,
        showBy: now.add(const Duration(hours: 1)),
        reservationUntil: now.add(const Duration(hours: 24)),
      ),
      capDate: '2026-08-26',
      timeZone: 'America/New_York',
      serverTime: now,
    );
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
    impressionReports++;
    final status = reportErrorStatus;
    if (status != null) {
      throw ApiException('report failed', statusCode: status);
    }
  }

  @override
  Future<void> cancelInterstitialPermit({
    required String identityToken,
    required String permitId,
  }) async {
    cancelCalls++;
  }
}

class _DelayedEligibilityApi extends _InterstitialApi {
  _DelayedEligibilityApi(super.now);

  final eligibilityStarted = Completer<void>();
  final releaseEligibility = Completer<void>();

  @override
  Future<InterstitialEligibility> fetchInterstitialEligibility({
    required String identityToken,
    required InterstitialPlacement placement,
    required String sessionId,
    required DateTime sessionStartedAt,
  }) async {
    eligibilityStarted.complete();
    await releaseEligibility.future;
    return super.fetchInterstitialEligibility(
      identityToken: identityToken,
      placement: placement,
      sessionId: sessionId,
      sessionStartedAt: sessionStartedAt,
    );
  }
}

class _FakeInterstitial implements InterstitialAdController {
  _FakeInterstitial({required this.impresses});
  final bool impresses;
  bool disposed = false;

  @override
  Future<InterstitialShowOutcome> show({
    required VoidCallback onShowed,
    required VoidCallback onImpression,
  }) async {
    onShowed();
    if (impresses) onImpression();
    return InterstitialShowOutcome.dismissed;
  }

  @override
  void dispose() => disposed = true;
}

class _ControlledInterstitial implements InterstitialAdController {
  final started = Completer<void>();
  final _outcome = Completer<InterstitialShowOutcome>();
  VoidCallback? _onImpression;

  void impress() => _onImpression?.call();
  void complete(InterstitialShowOutcome outcome) => _outcome.complete(outcome);

  @override
  Future<InterstitialShowOutcome> show({
    required VoidCallback onShowed,
    required VoidCallback onImpression,
  }) {
    _onImpression = onImpression;
    onShowed();
    started.complete();
    return _outcome.future;
  }

  @override
  void dispose() {}
}

InterstitialAdCoordinator _coordinator({
  required DateTime now,
  required _InterstitialApi api,
  String ownerUserId = 'user-a',
  String identityToken = 'token-a',
  InterstitialAdLoader? loader,
  String? adUnitId = 'test-injected-unit',
  String Function(InterstitialPlacement)? adUnitIdForPlacement,
}) => InterstitialAdCoordinator(
  ownerUserId: ownerUserId,
  identityToken: identityToken,
  backendApiService: api,
  analytics: ActivationAnalyticsService(
    backendApiService: api,
    isIosForTesting: true,
  ),
  backendBaseUrl: 'https://example.test',
  adUnitId: adUnitId,
  adUnitIdForPlacement: adUnitIdForPlacement,
  platform: 'ios',
  now: () => now,
  fullScreenTracker: FullScreenPresentationTracker(now: () => now),
  loader: loader ?? (_) async => null,
  sessionId: _sessionId,
  sessionStartedAt: now.subtract(const Duration(minutes: 2)),
);

Map<String, dynamic> _storedFact({
  required String ownerUserId,
  required String backendBaseUrl,
  required String sessionId,
  required DateTime occurredAt,
  required int suffix,
}) => <String, dynamic>{
  'eventId': '20000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}',
  'permitId': '30000000-0000-4000-8000-${suffix.toString().padLeft(12, '0')}',
  'placement': 'race_detail_exit',
  'sessionId': sessionId,
  'occurredAt': occurredAt.toIso8601String(),
  'appVersion': '1.2.3',
  'platform': 'ios',
  'ownerUserId': ownerUserId,
  'backendBaseUrl': backendBaseUrl,
  'capDate': '2026-08-26',
  'expiresAt': occurredAt.add(const Duration(hours: 24)).toIso8601String(),
};

Future<List<Map<String, dynamic>>> _storedFacts() async {
  final prefs = await SharedPreferences.getInstance();
  final decoded = jsonDecode(
    prefs.getString('interstitial_impression_facts_v1') ?? '[]',
  );
  return (decoded as List)
      .whereType<Map>()
      .map((row) => row.map((key, value) => MapEntry('$key', value)))
      .toList();
}

Future<void> _drainAsync() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeClock {
  _FakeClock(this.value);
  DateTime value;
  DateTime call() => value;
  void advance(Duration duration) => value = value.add(duration);
}
