import 'dart:async';

import 'package:flutter/material.dart';

import '../models/interstitial_ad.dart';
import '../screens/race_detail_screen.dart';
import 'activation_analytics_service.dart';
import 'auth_service.dart';
import 'backend_api_service.dart';
import 'interstitial_ad_service.dart';
import 'notification_service.dart';

class RaceDetailNavigator {
  const RaceDetailNavigator({
    required this.authService,
    required this.backendApiService,
    required this.coordinator,
    required this.analytics,
  });

  /// Navigation-only compatibility for independently pumped screens and
  /// embedders that have not yet supplied the shell-owned ad coordinator.
  /// The route semantics stay identical, while every ad operation is a no-op.
  factory RaceDetailNavigator.withoutInterstitials({
    required AuthService authService,
    required BackendApiService backendApiService,
  }) => RaceDetailNavigator(
    authService: authService,
    backendApiService: backendApiService,
    coordinator: _NavigationOnlyInterstitialCoordinator(authService),
    analytics: ActivationAnalyticsService(backendApiService: backendApiService),
  );

  final AuthService authService;
  final BackendApiService backendApiService;
  final InterstitialPresentationCoordinator coordinator;
  final ActivationAnalyticsService analytics;

  Future<RaceDetailRouteResult> push({
    required BuildContext context,
    required String raceId,
    required RaceDetailEntrySurface entrySurface,
    RaceDetailEntryOrigin entryOrigin = RaceDetailEntryOrigin.existing,
    List<Map<String, dynamic>> friends = const [],
    NotificationService? notificationService,
    Future<void> Function()? onBoxOpened,
    bool showPostCreateSharePrompt = false,
    FutureOr<void> Function()? scheduleRefresh,
  }) async {
    final boundUserId = authService.userId;
    final boundToken = authService.authToken;
    if (boundUserId == null ||
        boundUserId.isEmpty ||
        boundToken == null ||
        boundToken.isEmpty ||
        coordinator.ownerUserId != boundUserId) {
      return RaceDetailRouteResult.authReplace;
    }
    late final RaceDetailInterstitialVisit visit;
    var visitStartRecorded = false;
    visit = RaceDetailInterstitialVisit(
      entrySurface: entrySurface,
      entryOrigin: entryOrigin,
      onPrime: () =>
          _ignore(coordinator.prime(InterstitialPlacement.raceDetailExit)),
      onInvalidate: () =>
          _ignore(coordinator.cancel(InterstitialPlacement.raceDetailExit)),
      onScopeStamped: () {
        visitStartRecorded = true;
        _visitEvent('race_detail_visit_started', visit);
      },
    );
    RaceDetailRouteResult result = RaceDetailRouteResult.forwardExit;
    try {
      result =
          await Navigator.of(context).push<RaceDetailRouteResult>(
            RaceDetailPageRoute(
              builder: (_) => RaceDetailScreen(
                authService: authService,
                raceId: raceId,
                backendApiService: backendApiService,
                friends: friends,
                notificationService: notificationService,
                activationAnalyticsService: analytics,
                onBoxOpened: onBoxOpened,
                showPostCreateSharePrompt: showPostCreateSharePrompt,
                interstitialVisit: visit,
                raceDetailNavigator: this,
              ),
            ),
          ) ??
          RaceDetailRouteResult.backExit;
    } catch (_) {
      result = RaceDetailRouteResult.forwardExit;
    }
    try {
      final refresh = scheduleRefresh?.call();
      if (refresh is Future<void>) _ignore(refresh);
    } catch (_) {}
    final authMatches =
        authService.userId == boundUserId &&
        authService.authToken == boundToken &&
        coordinator.ownerUserId == boundUserId;
    final underlyingCurrent =
        context.mounted && ModalRoute.of(context)?.isCurrent == true;
    if (!authMatches) result = RaceDetailRouteResult.authReplace;
    final eligibleBack =
        result == RaceDetailRouteResult.backExit &&
        visit.hasQualifyingDwell &&
        visit.scopeResult == RaceDetailScopeResult.activeAccepted &&
        authMatches &&
        underlyingCurrent;
    if (!visitStartRecorded) {
      _visitEvent('race_detail_visit_started', visit);
    }
    _visitEvent(
      'race_detail_visit_ended',
      visit,
      exitKind: switch (result) {
        RaceDetailRouteResult.backExit => 'back',
        RaceDetailRouteResult.forwardExit => 'forward',
        RaceDetailRouteResult.stateChange => 'state_change',
        RaceDetailRouteResult.authReplace => 'auth_replace',
      },
    );
    if (result == RaceDetailRouteResult.backExit) {
      _visitEvent('race_detail_back_exit', visit, exitKind: 'back');
    }
    if (eligibleBack) {
      _visitEvent('race_detail_exit_eligible', visit, exitKind: 'back');
      try {
        coordinator.presentIfReady(
          InterstitialPlacement.raceDetailExit,
          rewardedPresented: visit.rewardedPresented,
        );
      } catch (_) {}
    } else {
      // Short/ineligible back visits and every forward/state/auth exit release
      // any flow-local permit; none is an ad opportunity.
      _ignore(coordinator.cancel(InterstitialPlacement.raceDetailExit));
    }
    visit.dispose();
    return result;
  }

  void _visitEvent(
    String name,
    RaceDetailInterstitialVisit visit, {
    String? exitKind,
  }) {
    unawaited(
      analytics.record(
        name,
        ownerUserId: coordinator.ownerUserId,
        sessionId: coordinator.sessionId,
        context: {
          'entry_surface': visit.entrySurface.wireName,
          'exit_kind': ?exitKind,
          'scope_result':
              visit.scopeResult == RaceDetailScopeResult.activeAccepted
              ? 'active_accepted'
              : 'ineligible',
          'dwell_bucket': visit.dwellBucket,
        },
      ),
    );
  }
}

void _ignore(Future<void> future) {
  unawaited(future.catchError((_) {}));
}

class _NavigationOnlyInterstitialCoordinator
    implements InterstitialPresentationCoordinator {
  const _NavigationOnlyInterstitialCoordinator(this._authService);

  final AuthService _authService;

  @override
  String get ownerUserId => _authService.userId ?? '';

  @override
  String get sessionId => 'navigation-only';

  @override
  Future<void> cancel(InterstitialPlacement placement) async {}

  @override
  void didEnterBackground() {}

  @override
  void didResume() {}

  @override
  void dispose() {}

  @override
  Future<void> flushPendingImpressions() async {}

  @override
  Future<void> warm(InterstitialPlacement placement) async {}

  @override
  Future<void> prime(InterstitialPlacement placement) async {}

  @override
  bool presentIfReady(
    InterstitialPlacement placement, {
    bool excludedFlow = false,
    bool rewardedPresented = false,
  }) => false;
}
