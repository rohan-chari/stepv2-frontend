import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/backend_config.dart';
import '../models/interstitial_ad.dart';
import 'activation_analytics_service.dart';
import 'ad_service.dart';
import 'backend_api_service.dart';

enum RaceDetailRouteResult { backExit, forwardExit, stateChange, authReplace }

enum RaceDetailEntrySurface {
  home('home'),
  races('races'),
  publicRaces('public_races'),
  tournament('tournament');

  const RaceDetailEntrySurface(this.wireName);
  final String wireName;
}

enum RaceDetailEntryOrigin { existing, newlyCreated }

enum RaceDetailScopeResult { activeAccepted, ineligible }

class RaceDetailPageRoute extends MaterialPageRoute<RaceDetailRouteResult> {
  RaceDetailPageRoute({required super.builder, super.settings});

  @override
  RaceDetailRouteResult get currentResult => RaceDetailRouteResult.backExit;
}

/// One route-local eligibility stamp. It never owns navigation or a context.
class RaceDetailInterstitialVisit {
  RaceDetailInterstitialVisit({
    required this.entrySurface,
    required this.entryOrigin,
    required this.onPrime,
    this.onScopeStamped,
    this.onInvalidate,
    DateTime Function()? now,
    this.dwellRequired = const Duration(seconds: 10),
  }) : _now = now ?? DateTime.now;

  final RaceDetailEntrySurface entrySurface;
  final RaceDetailEntryOrigin entryOrigin;
  final VoidCallback onPrime;
  final VoidCallback? onScopeStamped;
  final VoidCallback? onInvalidate;
  final DateTime Function() _now;
  final Duration dwellRequired;
  bool _stamped = false;
  bool _eligible = false;
  bool _foreground = true;
  bool _covered = false;
  bool _disposed = false;
  bool _primed = false;
  bool _primeInvalidated = false;
  bool rewardedPresented = false;
  Duration _accrued = Duration.zero;
  DateTime? _visibleSince;
  Timer? _timer;

  RaceDetailScopeResult get scopeResult => _eligible
      ? RaceDetailScopeResult.activeAccepted
      : RaceDetailScopeResult.ineligible;

  void stampFirstAuthoritativeLoad({
    required Object? raceStatus,
    required Object? participantStatus,
  }) {
    if (_stamped || _disposed) return;
    _stamped = true;
    _eligible =
        entryOrigin != RaceDetailEntryOrigin.newlyCreated &&
        raceStatus == 'ACTIVE' &&
        participantStatus == 'ACCEPTED';
    onScopeStamped?.call();
    if (_eligible) _resumeClock();
  }

  void revoke() {
    _updateAccrued();
    _eligible = false;
    _timer?.cancel();
    _invalidatePrimedWork();
  }

  void setCovered(bool covered) {
    if (_covered == covered || _disposed) return;
    _updateAccrued();
    _covered = covered;
    if (covered) _invalidatePrimedWork();
    _resumeClock();
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground || _disposed) return;
    _updateAccrued();
    _foreground = foreground;
    if (!foreground) _invalidatePrimedWork();
    _resumeClock();
  }

  void recordRewardedPresented() => rewardedPresented = true;

  Duration get dwell {
    _updateAccrued(resume: true);
    return _accrued;
  }

  bool get hasQualifyingDwell => _eligible && dwell >= dwellRequired;

  String get dwellBucket {
    final seconds = dwell.inSeconds;
    if (seconds < 5) return 'under_5s';
    if (seconds < 10) return '5_9s';
    if (seconds < 60) return '10_59s';
    if (seconds < 180) return '60_179s';
    return '180s_plus';
  }

  void _updateAccrued({bool resume = false}) {
    final since = _visibleSince;
    if (since != null) {
      final delta = _now().difference(since);
      if (!delta.isNegative) _accrued += delta;
      _visibleSince = null;
    }
    if (resume) _resumeClock();
  }

  void _resumeClock() {
    _timer?.cancel();
    if (_disposed || !_eligible || !_foreground || _covered || _primed) return;
    _visibleSince ??= _now();
    final remaining = dwellRequired - _accrued;
    if (remaining <= Duration.zero) {
      _primeOnce();
      return;
    }
    _timer = Timer(remaining, _primeOnce);
  }

  void _primeOnce() {
    if (_disposed || !_eligible || !_foreground || _covered || _primed) {
      _updateAccrued();
      _resumeClock();
      return;
    }
    // This callback is scheduled for exactly the remaining visible dwell.
    // Use the monotonic Timer completion as authority; wall clock can jump and
    // Flutter's test clock intentionally does not advance DateTime.now().
    _visibleSince = null;
    _accrued = dwellRequired;
    _primed = true;
    onPrime();
  }

  void _invalidatePrimedWork() {
    if (!_primed || _primeInvalidated) return;
    _primeInvalidated = true;
    onInvalidate?.call();
  }

  void dispose() {
    if (_disposed) return;
    _updateAccrued();
    _disposed = true;
    _timer?.cancel();
  }
}

class FullScreenPresentationTracker {
  FullScreenPresentationTracker({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const storageKey = 'last_fullscreen_ad_presented_at_v1';
  static const suppression = Duration(minutes: 30);
  static final production = FullScreenPresentationTracker();
  final DateTime Function() _now;
  DateTime? _cached;

  bool get wasPresentedRecentlySync {
    final timestamp = _cached;
    return timestamp != null &&
        _now().toUtc().difference(timestamp) < suppression;
  }

  Future<bool> wasPresentedRecently() async {
    final prefs = await SharedPreferences.getInstance();
    _cached ??= DateTime.tryParse(prefs.getString(storageKey) ?? '')?.toUtc();
    final recent = wasPresentedRecentlySync;
    if (!recent && _cached != null) {
      _cached = null;
      await prefs.remove(storageKey);
    }
    return recent;
  }

  Future<void> recordPresented() async {
    final timestamp = _now().toUtc();
    _cached = timestamp;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, timestamp.toIso8601String());
  }
}

enum InterstitialShowOutcome { dismissed, failed }

abstract class InterstitialAdController {
  Future<InterstitialShowOutcome> show({
    required VoidCallback onShowed,
    required VoidCallback onImpression,
  });
  void dispose();
}

typedef InterstitialAdLoader =
    Future<InterstitialAdController?> Function(String adUnitId);

abstract class InterstitialPresentationCoordinator {
  String get ownerUserId;
  String get sessionId;
  Future<void> flushPendingImpressions();
  Future<void> warm(InterstitialPlacement placement);
  Future<void> prime(InterstitialPlacement placement);
  bool presentIfReady(
    InterstitialPlacement placement, {
    bool excludedFlow = false,
    bool rewardedPresented = false,
  });
  Future<void> cancel(InterstitialPlacement placement);
  void didEnterBackground();
  void didResume();
  void dispose();
}

class _EligibilityCacheEntry {
  const _EligibilityCacheEntry({
    required this.ownerUserId,
    required this.backendBaseUrl,
    required this.sessionId,
    required this.placement,
    required this.timeZone,
    required this.fetchedAt,
    required this.value,
  });

  final String ownerUserId;
  final String backendBaseUrl;
  final String sessionId;
  final InterstitialPlacement placement;
  final String timeZone;
  final DateTime fetchedAt;
  final InterstitialEligibility value;

  bool isValid({
    required String expectedOwnerUserId,
    required String expectedBackendBaseUrl,
    required String expectedSessionId,
    required InterstitialPlacement expectedPlacement,
    required String expectedTimeZone,
    required DateTime now,
  }) {
    final age = now.difference(fetchedAt);
    return ownerUserId == expectedOwnerUserId &&
        backendBaseUrl == expectedBackendBaseUrl &&
        sessionId == expectedSessionId &&
        placement == expectedPlacement &&
        timeZone == expectedTimeZone &&
        age >= Duration.zero &&
        age < const Duration(minutes: 5);
  }
}

enum _InterstitialLoadPhase { idle, loading, ready }

class _InterstitialLoadEntry {
  _InterstitialLoadEntry(this.placement);

  final InterstitialPlacement placement;
  String unitId = '';
  _InterstitialLoadPhase phase = _InterstitialLoadPhase.idle;
  Future<void>? inFlight;
  InterstitialAdController? ad;
  DateTime? loadedAt;
  int generation = 0;
  DateTime? lastFailureAt;
  DateTime? retryDueAt;
  int attemptCount = 0;
  bool? lastLoadSucceeded;
  Timer? retryTimer;
  bool restartAfterInFlight = false;
}

class _InterstitialPermitFlow {
  _InterstitialPermitFlow({required this.placement, required this.generation});

  final InterstitialPlacement placement;
  final int generation;
  Future<void>? primeFuture;
  InterstitialAdController? boundAd;
  InterstitialPermitGrant? grant;
  String? appVersion;
  String? lastReadinessReason;
}

class InterstitialAdCoordinator implements InterstitialPresentationCoordinator {
  InterstitialAdCoordinator({
    required this.ownerUserId,
    required String identityToken,
    required BackendApiService backendApiService,
    required ActivationAnalyticsService analytics,
    String? backendBaseUrl,
    String? adUnitId,
    String Function(InterstitialPlacement)? adUnitIdForPlacement,
    Future<String?> Function()? effectiveTimeZoneProvider,
    String? platform,
    DateTime Function()? now,
    FullScreenPresentationTracker? fullScreenTracker,
    InterstitialAdLoader? loader,
    String? sessionId,
    DateTime? sessionStartedAt,
    Future<String> Function()? appVersionProvider,
    List<Duration>? retryDelays,
  }) : _identityToken = identityToken,
       _api = backendApiService,
       _analytics = analytics,
       _backendBaseUrl = backendBaseUrl ?? BackendConfig.baseUrl,
       _adUnitIdForPlacement =
           adUnitIdForPlacement ??
           (adUnitId == null
               ? AdService.interstitialAdUnitIdFor
               : (_) => adUnitId),
       _effectiveTimeZoneProvider =
           effectiveTimeZoneProvider ?? backendApiService.getEffectiveTimeZone,
       _platform = platform ?? AdService.currentAdPlatform,
       _now = now ?? DateTime.now,
       _tracker = fullScreenTracker ?? FullScreenPresentationTracker.production,
       _loader = loader ?? _loadGoogleInterstitial,
       _appVersionProvider = appVersionProvider ?? _appVersion,
       _retryDelays =
           retryDelays ?? const [Duration(seconds: 30), Duration(minutes: 2)],
       _sessionId = sessionId ?? _uuid(),
       _sessionStartedAt = sessionStartedAt?.toUtc() ?? DateTime.now().toUtc() {
    AdService.adRequestPermissionListenable.addListener(
      _onAdRequestPermissionChanged,
    );
  }

  static const _queueKey = 'interstitial_impression_facts_v1';
  static const _maxFacts = 20;
  static const _maxTotalFacts = 100;
  static const _maxAdAge = Duration(hours: 1);
  static Future<void> _queueLock = Future<void>.value();
  @override
  final String ownerUserId;
  final String _identityToken;
  final BackendApiService _api;
  final ActivationAnalyticsService _analytics;
  final String _backendBaseUrl;
  final String Function(InterstitialPlacement) _adUnitIdForPlacement;
  final Future<String?> Function() _effectiveTimeZoneProvider;
  final String _platform;
  final DateTime Function() _now;
  final FullScreenPresentationTracker _tracker;
  final InterstitialAdLoader _loader;
  final Future<String> Function() _appVersionProvider;
  final List<Duration> _retryDelays;
  String _sessionId;
  DateTime _sessionStartedAt;
  DateTime? _backgroundedAt;
  bool _disposed = false;
  bool _foreground = true;
  bool _showPending = false;
  bool _impressionConfirmedThisSession = false;
  bool _backendUnsupported = false;
  int _flowGeneration = 0;
  _InterstitialPermitFlow? _flow;
  final Set<String> _cancelledPermitIds = <String>{};
  final Map<InterstitialPlacement, _InterstitialLoadEntry> _loads =
      <InterstitialPlacement, _InterstitialLoadEntry>{};
  final Map<InterstitialPlacement, String> _lastReadinessReasons =
      <InterstitialPlacement, String>{};
  final Map<InterstitialPlacement, _EligibilityCacheEntry> _eligibilityCache =
      <InterstitialPlacement, _EligibilityCacheEntry>{};

  @override
  String get sessionId => _sessionId;

  @override
  Future<void> warm(InterstitialPlacement placement) {
    final adUnitId = _adUnitIdForPlacement(placement);
    if (_disposed ||
        !_foreground ||
        _impressionConfirmedThisSession ||
        _tracker.wasPresentedRecentlySync ||
        !AdService.adRequestsAllowed ||
        adUnitId.isEmpty ||
        _platform == 'other') {
      return Future<void>.value();
    }

    final entry = _loads.putIfAbsent(
      placement,
      () => _InterstitialLoadEntry(placement),
    );
    if (entry.unitId != adUnitId) {
      entry.generation++;
      if (entry.inFlight != null) entry.restartAfterInFlight = true;
      entry.retryTimer?.cancel();
      entry.retryTimer = null;
      entry.retryDueAt = null;
      entry.attemptCount = 0;
      _disposeEntryAd(entry);
      entry.unitId = adUnitId;
    }
    _evictExpiredEntry(entry, refresh: false);
    if (entry.ad != null) return Future<void>.value();
    final inFlight = entry.inFlight;
    if (inFlight != null) return inFlight;
    if (entry.attemptCount >= 3) return Future<void>.value();

    final now = _now().toUtc();
    final retryDueAt = entry.retryDueAt;
    if (retryDueAt != null && now.isBefore(retryDueAt)) {
      _scheduleRetryTimer(entry);
      return Future<void>.value();
    }

    entry.retryTimer?.cancel();
    entry.retryTimer = null;
    entry.retryDueAt = null;
    entry.restartAfterInFlight = false;
    entry.phase = _InterstitialLoadPhase.loading;
    entry.attemptCount++;
    final generation = ++entry.generation;
    final completer = Completer<void>();
    entry.inFlight = completer.future;
    unawaited(
      _performWarmLoad(entry, adUnitId, generation).whenComplete(() {
        if (identical(entry.inFlight, completer.future)) {
          entry.inFlight = null;
        }
        if (!completer.isCompleted) completer.complete();
        if (entry.retryDueAt != null) _scheduleRetryTimer(entry);
        if (entry.restartAfterInFlight &&
            !_disposed &&
            _foreground &&
            AdService.adRequestsAllowed) {
          entry.restartAfterInFlight = false;
          unawaited(warm(entry.placement));
        }
      }),
    );
    return completer.future;
  }

  Future<void> _performWarmLoad(
    _InterstitialLoadEntry entry,
    String adUnitId,
    int generation,
  ) async {
    InterstitialAdController? ad;
    try {
      ad = await _loader(adUnitId);
    } catch (_) {
      ad = null;
    }
    if (!_acceptsLoadCallback(entry, adUnitId, generation)) {
      ad?.dispose();
      return;
    }

    if (ad == null) {
      entry.phase = _InterstitialLoadPhase.idle;
      entry.lastLoadSucceeded = false;
      entry.lastFailureAt = _now().toUtc();
      _event(
        'interstitial_load_failed',
        entry.placement,
        context: const {'result': 'failed'},
      );
      _queueRetry(entry);
      return;
    }

    _disposeEntryAd(entry);
    entry.ad = ad;
    entry.loadedAt = _now().toUtc();
    entry.phase = _InterstitialLoadPhase.ready;
    entry.lastLoadSucceeded = true;
    entry.lastFailureAt = null;
    entry.retryDueAt = null;
    entry.attemptCount = 0;
    entry.retryTimer?.cancel();
    entry.retryTimer = null;
    _event(
      'interstitial_load_succeeded',
      entry.placement,
      context: const {'result': 'completed'},
    );
  }

  bool _acceptsLoadCallback(
    _InterstitialLoadEntry entry,
    String adUnitId,
    int generation,
  ) =>
      !_disposed &&
      AdService.adRequestsAllowed &&
      entry.generation == generation &&
      entry.unitId == adUnitId &&
      _adUnitIdForPlacement(entry.placement) == adUnitId;

  void _queueRetry(_InterstitialLoadEntry entry) {
    if (_disposed ||
        _impressionConfirmedThisSession ||
        entry.attemptCount >= 3) {
      return;
    }
    final index = entry.attemptCount - 1;
    if (index < 0 || index >= _retryDelays.length) return;
    entry.retryDueAt = _now().toUtc().add(_retryDelays[index]);
    if (_foreground) _scheduleRetryTimer(entry);
  }

  void _scheduleRetryTimer(_InterstitialLoadEntry entry) {
    if (_disposed ||
        !_foreground ||
        _impressionConfirmedThisSession ||
        !AdService.adRequestsAllowed ||
        entry.ad != null ||
        entry.inFlight != null ||
        entry.attemptCount >= 3 ||
        entry.retryTimer != null) {
      return;
    }
    final dueAt = entry.retryDueAt;
    if (dueAt == null) return;
    final remaining = dueAt.difference(_now().toUtc());
    entry.retryTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () {
        entry.retryTimer = null;
        if (_now().toUtc().isBefore(dueAt)) {
          _scheduleRetryTimer(entry);
          return;
        }
        unawaited(warm(entry.placement));
      },
    );
  }

  @override
  Future<void> prime(InterstitialPlacement placement) async {
    final adUnitId = _adUnitIdForPlacement(placement);
    if (_disposed ||
        !_foreground ||
        _showPending ||
        _impressionConfirmedThisSession ||
        !AdService.adRequestsAllowed ||
        adUnitId.isEmpty ||
        _platform == 'other') {
      return;
    }

    final existingEntry = _loads[placement];
    final Future<void>? warmFuture = existingEntry?.ad != null
        ? Future<void>.value()
        : existingEntry?.inFlight;
    final existing = _flow;
    if (existing != null) {
      if (existing.placement == placement) {
        final inFlight = existing.primeFuture;
        if (inFlight != null) await inFlight;
        return;
      }
      if (_flowHasUsablePermit(existing)) {
        _lastReadinessReasons[placement] = 'permit_active';
        await (warmFuture ?? warm(placement));
        return;
      }
      await _invalidateFlow(existing);
    }

    final flow = _InterstitialPermitFlow(
      placement: placement,
      generation: ++_flowGeneration,
    );
    _flow = flow;
    final primeFuture = _preparePermitFlow(flow, warmFuture);
    flow.primeFuture = primeFuture;
    try {
      await primeFuture;
    } finally {
      if (identical(_flow, flow)) flow.primeFuture = null;
    }
  }

  Future<void> _preparePermitFlow(
    _InterstitialPermitFlow flow,
    Future<void>? warmFuture,
  ) async {
    final placement = flow.placement;
    await flushPendingImpressions();
    if (!_acceptsFlow(flow)) return;
    if (_backendUnsupported) {
      _setFlowReason(flow, 'backend_unsupported');
      return;
    }
    if (await _tracker.wasPresentedRecently()) {
      if (!_acceptsFlow(flow)) return;
      _setFlowReason(flow, 'recent_fullscreen');
      return;
    }
    if (!_acceptsFlow(flow)) return;
    final localCapReason = await _localCapReason();
    if (!_acceptsFlow(flow)) return;
    if (localCapReason != null) {
      _setFlowReason(flow, localCapReason);
      return;
    }

    try {
      String? effectiveTimeZone;
      try {
        effectiveTimeZone = await _effectiveTimeZoneProvider();
      } catch (_) {
        effectiveTimeZone = null;
      }
      if (!_acceptsFlow(flow)) return;
      var eligibility = effectiveTimeZone == null
          ? null
          : _cachedEligibility(placement, effectiveTimeZone);
      var fetchedEligibility = false;
      if (eligibility == null) {
        eligibility = await _api.fetchInterstitialEligibility(
          identityToken: _identityToken,
          placement: placement,
          sessionId: _sessionId,
          sessionStartedAt: _sessionStartedAt,
        );
        fetchedEligibility = true;
      }
      if (!_api.interstitialSupported) {
        _backendUnsupported = true;
        _setFlowReason(flow, 'backend_unsupported');
        return;
      }
      if (!_acceptsFlow(flow)) return;
      if (fetchedEligibility && effectiveTimeZone != null) {
        _cacheEligibility(placement, eligibility, effectiveTimeZone);
      }
      if (!eligibility.eligible) {
        _setFlowReason(flow, eligibility.reason ?? 'backend_unavailable');
        return;
      }

      await (warmFuture ?? warm(placement));
      if (!_acceptsFlow(flow)) return;
      final entry = _loads[placement];
      _evictExpiredEntry(entry, refresh: true);
      if (!_acceptsFlow(flow)) return;
      final ad = entry?.ad;
      if (entry == null ||
          ad == null ||
          entry.unitId != _adUnitIdForPlacement(placement)) {
        _setFlowReason(flow, 'not_ready');
        return;
      }
      flow.boundAd = ad;

      final version = await _appVersionProvider();
      if (!_acceptsFlow(flow) || !identical(entry.ad, ad)) return;
      final grant = await _api.createInterstitialPermit(
        identityToken: _identityToken,
        placement: placement,
        sessionId: _sessionId,
        sessionStartedAt: _sessionStartedAt,
        appVersion: version,
        platform: _platform,
        now: _now().toUtc(),
      );
      if (!_acceptsFlow(flow) || !identical(entry.ad, ad)) {
        if (grant.permit != null) {
          await _cancelPermitOnce(grant.permit!.id);
        }
        return;
      }
      if (!grant.eligible || grant.permit == null) {
        _setFlowReason(flow, grant.reason ?? 'not_ready');
        return;
      }
      flow.grant = grant;
      flow.appVersion = version;
      flow.lastReadinessReason = null;
      _lastReadinessReasons.remove(placement);
    } on ApiException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 405) {
        _backendUnsupported = true;
        _setFlowReason(flow, 'backend_unsupported');
      } else {
        _setFlowReason(flow, 'backend_unavailable');
      }
    } catch (_) {
      _setFlowReason(flow, 'backend_unavailable');
    }
  }

  bool _acceptsFlow(_InterstitialPermitFlow flow) =>
      !_disposed &&
      _foreground &&
      AdService.adRequestsAllowed &&
      identical(_flow, flow) &&
      flow.generation == _flowGeneration;

  bool _flowHasUsablePermit(_InterstitialPermitFlow flow) {
    final permit = flow.grant?.permit;
    return permit != null && permit.canBeginShow(_now().toUtc());
  }

  void _setFlowReason(_InterstitialPermitFlow flow, String reason) {
    if (!_acceptsFlow(flow)) return;
    flow.lastReadinessReason = reason;
    _lastReadinessReasons[flow.placement] = reason;
  }

  InterstitialEligibility? _cachedEligibility(
    InterstitialPlacement placement,
    String effectiveTimeZone,
  ) {
    final entry = _eligibilityCache[placement];
    if (entry == null ||
        !entry.isValid(
          expectedOwnerUserId: ownerUserId,
          expectedBackendBaseUrl: _backendBaseUrl,
          expectedSessionId: _sessionId,
          expectedPlacement: placement,
          expectedTimeZone: effectiveTimeZone,
          now: _now().toUtc(),
        )) {
      _eligibilityCache.remove(placement);
      return null;
    }
    return entry.value;
  }

  void _cacheEligibility(
    InterstitialPlacement placement,
    InterstitialEligibility eligibility,
    String effectiveTimeZone,
  ) {
    final timeZone = eligibility.timeZone;
    if (timeZone == null || timeZone.isEmpty || timeZone != effectiveTimeZone) {
      _eligibilityCache.remove(placement);
      return;
    }
    _eligibilityCache[placement] = _EligibilityCacheEntry(
      ownerUserId: ownerUserId,
      backendBaseUrl: _backendBaseUrl,
      sessionId: _sessionId,
      placement: placement,
      timeZone: timeZone,
      fetchedAt: _now().toUtc(),
      value: eligibility,
    );
  }

  @override
  bool presentIfReady(
    InterstitialPlacement placement, {
    bool excludedFlow = false,
    bool rewardedPresented = false,
  }) {
    _event(
      'interstitial_opportunity',
      placement,
      context: const {'result': 'back_exit'},
    );
    final entry = _loads[placement];
    _evictExpiredEntry(entry, refresh: true);
    final flow = _flow;
    final grant = flow?.grant;
    final permit = grant?.permit;
    final ad = entry?.ad;
    String? skipReason;
    if (_disposed) {
      skipReason = 'account_changed';
    } else if (!AdService.adRequestsAllowed) {
      skipReason = 'not_ready';
    } else if (_adUnitIdForPlacement(placement).isEmpty) {
      skipReason = 'unconfigured';
    } else if (excludedFlow) {
      skipReason = 'excluded_flow';
    } else if (rewardedPresented || _tracker.wasPresentedRecentlySync) {
      skipReason = 'recent_fullscreen';
      if (rewardedPresented && entry != null) _disposeEntryAd(entry);
    } else if (_showPending ||
        ad == null ||
        permit == null ||
        flow?.placement != placement ||
        !identical(flow?.boundAd, ad) ||
        entry?.unitId != _adUnitIdForPlacement(placement) ||
        !permit.canBeginShow(_now().toUtc())) {
      skipReason = 'not_ready';
    }
    if (skipReason != null) {
      _event(
        'interstitial_skipped',
        placement,
        context: {'reason': skipReason},
      );
      // This opportunity is terminal. Invalidate eligibility/load/permit work
      // even when it has not reached readiness yet, so a late async completion
      // cannot reserve backend capacity after the approved route has gone.
      if (!_showPending) unawaited(cancel(placement));
      return false;
    }
    final appVersion = flow?.appVersion ?? 'unknown';
    entry!.ad = null;
    entry.loadedAt = null;
    entry.phase = _InterstitialLoadPhase.idle;
    flow!.boundAd = null;
    _flow = null;
    _flowGeneration++;
    _showPending = true;
    _event(
      'interstitial_show_attempted',
      placement,
      context: const {'result': 'completed'},
    );
    unawaited(_show(ad!, grant!, appVersion));
    return true;
  }

  Future<void> _show(
    InterstitialAdController ad,
    InterstitialPermitGrant grant,
    String appVersion,
  ) async {
    final permit = grant.permit!;
    var impressionRecorded = false;
    var showConfirmed = false;
    var showFailed = false;
    try {
      final outcome = await ad.show(
        onShowed: () {
          showConfirmed = true;
          unawaited(_tracker.recordPresented());
        },
        onImpression: () {
          if (impressionRecorded) return;
          impressionRecorded = true;
          _impressionConfirmedThisSession = true;
          _suppressInventoryAfterImpression();
          unawaited(_recordImpression(grant, appVersion));
        },
      );
      if (outcome == InterstitialShowOutcome.dismissed) {
        _event(
          'interstitial_dismissed',
          permit.placement,
          context: const {'result': 'dismissed'},
        );
      } else {
        showFailed = true;
        _event(
          'interstitial_show_failed',
          permit.placement,
          context: const {'reason': 'show_failed'},
        );
      }
    } catch (_) {
      showFailed = true;
      _event(
        'interstitial_show_failed',
        permit.placement,
        context: const {'reason': 'show_failed'},
      );
    } finally {
      ad.dispose();
      _showPending = false;
      if (!impressionRecorded) {
        unawaited(_cancelPermitOnce(permit.id));
      }
      if (showFailed && !showConfirmed && !impressionRecorded) {
        final entry = _loads.putIfAbsent(
          permit.placement,
          () => _InterstitialLoadEntry(permit.placement),
        );
        entry.unitId = _adUnitIdForPlacement(permit.placement);
        entry.phase = _InterstitialLoadPhase.idle;
        entry.lastLoadSucceeded = false;
        entry.lastFailureAt = _now().toUtc();
        entry.attemptCount = 1;
        _queueRetry(entry);
      }
    }
  }

  void _suppressInventoryAfterImpression() {
    for (final entry in _loads.values) {
      entry.retryTimer?.cancel();
      entry.retryTimer = null;
      entry.retryDueAt = null;
      entry.generation++;
      _disposeEntryAd(entry);
    }
  }

  Future<void> _recordImpression(
    InterstitialPermitGrant grant,
    String appVersion,
  ) async {
    final permit = grant.permit!;
    final occurredAt = _now().toUtc();
    final fact = <String, dynamic>{
      'eventId': _uuid(),
      'permitId': permit.id,
      'placement': permit.placement.wireName,
      'sessionId': permit.sessionId,
      'occurredAt': occurredAt.toIso8601String(),
      'appVersion': appVersion,
      'platform': _platform,
      'ownerUserId': ownerUserId,
      'backendBaseUrl': _backendBaseUrl,
      'capDate': grant.capDate,
      // Confirmation accepts an impression for 24 hours from occurrence, and
      // the same window safely covers local cooldown/day-cap relevance.
      'expiresAt': occurredAt.add(const Duration(hours: 24)).toIso8601String(),
    };
    await _withQueueLock(() async {
      final prefs = await SharedPreferences.getInstance();
      final facts = _readFacts(prefs)..add(fact);
      while (_partitionFacts(facts).length > _maxFacts) {
        final oldestMine = facts.indexWhere(_belongsToPartition);
        if (oldestMine < 0) break;
        facts.removeAt(oldestMine);
      }
      if (facts.length > _maxTotalFacts) {
        facts.removeRange(0, facts.length - _maxTotalFacts);
      }
      await prefs.setString(_queueKey, jsonEncode(facts));
    });
    await flushPendingImpressions();
  }

  @override
  Future<void> flushPendingImpressions() async {
    if (_disposed) return;
    await _withQueueLock(() async {
      final prefs = await SharedPreferences.getInstance();
      final now = _now().toUtc();
      final all = _readFacts(prefs)
        ..removeWhere(
          (fact) =>
              DateTime.tryParse(
                fact['expiresAt']?.toString() ?? '',
              )?.toUtc().isBefore(now) ??
              true,
        );
      final mine = _partitionFacts(all);
      for (final fact in mine) {
        final eventId = fact['eventId'];
        final permitId = fact['permitId'];
        final placement = InterstitialPlacement.tryParse(fact['placement']);
        final sessionId = fact['sessionId'];
        final occurredAt = DateTime.tryParse(
          fact['occurredAt']?.toString() ?? '',
        );
        final appVersion = fact['appVersion'];
        final platform = fact['platform'];
        if (eventId is! String ||
            permitId is! String ||
            placement == null ||
            sessionId is! String ||
            occurredAt == null ||
            appVersion is! String ||
            platform is! String) {
          all.removeWhere((row) => identical(row, fact));
          continue;
        }
        try {
          await _api.reportInterstitialImpression(
            identityToken: _identityToken,
            eventId: eventId,
            permitId: permitId,
            placement: placement,
            sessionId: sessionId,
            occurredAt: occurredAt,
            appVersion: appVersion,
            platform: platform,
          );
          all.removeWhere((row) => row['eventId'] == eventId);
        } on ApiException catch (error) {
          if (error.statusCode == 404 || error.statusCode == 405) {
            _backendUnsupported = true;
          }
        } catch (_) {}
      }
      await prefs.setString(_queueKey, jsonEncode(all));
    });
  }

  bool _belongsToPartition(Map<String, dynamic> fact) =>
      fact['ownerUserId'] == ownerUserId &&
      fact['backendBaseUrl'] == _backendBaseUrl;

  List<Map<String, dynamic>> _partitionFacts(
    List<Map<String, dynamic>> facts,
  ) => facts.where(_belongsToPartition).toList();

  static Future<T> _withQueueLock<T>(Future<T> Function() action) {
    final prior = _queueLock;
    final release = Completer<void>();
    _queueLock = release.future;
    return () async {
      try {
        await prior;
      } catch (_) {}
      try {
        return await action();
      } finally {
        release.complete();
      }
    }();
  }

  Future<String?> _localCapReason() async {
    final prefs = await SharedPreferences.getInstance();
    final now = _now().toUtc();
    final facts = _readFacts(prefs)
        .where(
          (fact) =>
              fact['ownerUserId'] == ownerUserId &&
              fact['backendBaseUrl'] == _backendBaseUrl,
        )
        .toList();
    if (facts.any((fact) => fact['sessionId'] == _sessionId)) {
      return 'session_cap';
    }
    for (final fact in facts) {
      final occurred = DateTime.tryParse(fact['occurredAt']?.toString() ?? '');
      if (occurred != null &&
          now.difference(occurred.toUtc()) < const Duration(hours: 8)) {
        return 'cooldown';
      }
    }
    final countsByServerCapDate = <String, int>{};
    for (final fact in facts) {
      final capDate = fact['capDate'];
      if (capDate is! String || capDate.isEmpty) continue;
      countsByServerCapDate[capDate] =
          (countsByServerCapDate[capDate] ?? 0) + 1;
    }
    // Never derive a cap date from the device clock/timezone. Facts retain the
    // server-stamped date and expire after the bounded 24-hour relevance
    // window; conservatively keep any still-active two-impression date closed.
    return countsByServerCapDate.values.any((count) => count >= 2)
        ? 'daily_cap'
        : null;
  }

  List<Map<String, dynamic>> _readFacts(SharedPreferences prefs) {
    try {
      final decoded = jsonDecode(prefs.getString(_queueKey) ?? '[]');
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (row) => row.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> cancel(InterstitialPlacement placement) async {
    final flow = _flow;
    if (flow == null || flow.placement != placement) return;
    await _invalidateFlow(flow);
  }

  Future<void> _invalidateFlow(_InterstitialPermitFlow flow) async {
    if (!identical(_flow, flow)) return;
    _flow = null;
    _flowGeneration++;
    final permitId = flow.grant?.permit?.id;
    flow.boundAd = null;
    flow.grant = null;
    flow.appVersion = null;
    if (permitId != null) await _cancelPermitOnce(permitId);
  }

  Future<void> _cancelPermitOnce(String permitId) async {
    if (!_cancelledPermitIds.add(permitId)) return;
    try {
      await _api.cancelInterstitialPermit(
        identityToken: _identityToken,
        permitId: permitId,
      );
    } catch (_) {}
  }

  void _evictExpiredEntry(
    _InterstitialLoadEntry? entry, {
    required bool refresh,
  }) {
    if (entry == null) return;
    final loadedAt = entry.loadedAt;
    if (loadedAt == null || _now().toUtc().difference(loadedAt) < _maxAdAge) {
      return;
    }
    _disposeEntryAd(entry);
    if (refresh) unawaited(warm(entry.placement));
  }

  void _disposeEntryAd(_InterstitialLoadEntry entry) {
    final ad = entry.ad;
    if (ad == null) {
      entry.loadedAt = null;
      if (entry.phase == _InterstitialLoadPhase.ready) {
        entry.phase = _InterstitialLoadPhase.idle;
      }
      return;
    }
    entry.ad = null;
    entry.loadedAt = null;
    entry.phase = _InterstitialLoadPhase.idle;
    final flow = _flow;
    if (flow != null && identical(flow.boundAd, ad)) {
      _flow = null;
      _flowGeneration++;
      final permitId = flow.grant?.permit?.id;
      flow.boundAd = null;
      flow.grant = null;
      flow.appVersion = null;
      if (permitId != null) unawaited(_cancelPermitOnce(permitId));
    }
    ad.dispose();
  }

  void _onAdRequestPermissionChanged() {
    if (_disposed) return;
    if (AdService.adRequestsAllowed) {
      if (!_foreground) return;
      for (final entry in _loads.values) {
        if (entry.inFlight == null && entry.ad == null) {
          unawaited(warm(entry.placement));
        }
      }
      return;
    }
    final flow = _flow;
    if (flow != null && !_showPending) unawaited(_invalidateFlow(flow));
    for (final entry in _loads.values) {
      entry.generation++;
      if (entry.inFlight != null) entry.restartAfterInFlight = true;
      entry.retryTimer?.cancel();
      entry.retryTimer = null;
      _disposeEntryAd(entry);
    }
  }

  @override
  void didEnterBackground() {
    _backgroundedAt ??= _now().toUtc();
    _foreground = false;
    for (final entry in _loads.values) {
      entry.retryTimer?.cancel();
      entry.retryTimer = null;
    }
    if (!_showPending) {
      final flow = _flow;
      if (flow != null) unawaited(_invalidateFlow(flow));
    }
  }

  @override
  void didResume() {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    _foreground = true;
    final renewed =
        backgroundedAt != null &&
        _now().toUtc().difference(backgroundedAt) >=
            const Duration(seconds: 30);
    if (renewed) {
      _flowGeneration++;
      _sessionId = _uuid();
      _sessionStartedAt = _now().toUtc();
      _eligibilityCache.clear();
      _lastReadinessReasons.clear();
      _impressionConfirmedThisSession = false;
      for (final entry in _loads.values) {
        entry.retryTimer?.cancel();
        entry.retryTimer = null;
        entry.retryDueAt = null;
        entry.attemptCount = 0;
        entry.lastFailureAt = null;
        if (entry.inFlight != null) {
          entry.generation++;
          entry.restartAfterInFlight = true;
        }
      }
    }
    if (!AdService.adRequestsAllowed || _disposed) return;
    for (final entry in _loads.values) {
      _evictExpiredEntry(entry, refresh: false);
      if (entry.ad == null) unawaited(warm(entry.placement));
    }
  }

  void _event(
    String name,
    InterstitialPlacement placement, {
    Map<String, String> context = const {},
  }) {
    unawaited(
      _analytics.record(
        name,
        ownerUserId: ownerUserId,
        sessionId: _sessionId,
        context: {'placement': placement.wireName, ...context},
      ),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    AdService.adRequestPermissionListenable.removeListener(
      _onAdRequestPermissionChanged,
    );
    _disposed = true;
    _foreground = false;
    _flowGeneration++;
    _eligibilityCache.clear();
    final flow = _flow;
    _flow = null;
    if (!_showPending && flow?.grant?.permit != null) {
      unawaited(_cancelPermitOnce(flow!.grant!.permit!.id));
    }
    for (final entry in _loads.values) {
      entry.generation++;
      entry.retryTimer?.cancel();
      entry.retryTimer = null;
      _disposeEntryAd(entry);
    }
  }
}

Future<String> _appVersion() async {
  try {
    final value = (await PackageInfo.fromPlatform()).version;
    return value.isEmpty ? 'unknown' : value;
  } catch (_) {
    return 'unknown';
  }
}

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final text = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
      '${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
}

Future<InterstitialAdController?> _loadGoogleInterstitial(String adUnitId) {
  final completer = Completer<InterstitialAdController?>();
  InterstitialAd.load(
    adUnitId: adUnitId,
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (ad) => completer.complete(_GoogleInterstitialController(ad)),
      onAdFailedToLoad: (_) => completer.complete(null),
    ),
  );
  return completer.future;
}

class _GoogleInterstitialController implements InterstitialAdController {
  _GoogleInterstitialController(this._ad);
  final InterstitialAd _ad;

  @override
  Future<InterstitialShowOutcome> show({
    required VoidCallback onShowed,
    required VoidCallback onImpression,
  }) {
    final completer = Completer<InterstitialShowOutcome>();
    _ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => onShowed(),
      onAdImpression: (_) => onImpression(),
      onAdDismissedFullScreenContent: (_) {
        if (!completer.isCompleted) {
          completer.complete(InterstitialShowOutcome.dismissed);
        }
      },
      onAdFailedToShowFullScreenContent: (_, _) {
        if (!completer.isCompleted) {
          completer.complete(InterstitialShowOutcome.failed);
        }
      },
    );
    try {
      _ad.show();
    } catch (_) {
      if (!completer.isCompleted) {
        completer.complete(InterstitialShowOutcome.failed);
      }
    }
    return completer.future;
  }

  @override
  void dispose() => _ad.dispose();
}
