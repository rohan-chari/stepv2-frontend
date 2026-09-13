import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/admin_metrics_dashboard.dart';
import '../models/admin_system_health.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';

enum AdminRange {
  today('Today', '7d'),
  week('7 days', '7d'),
  month('30 days', '30d');

  const AdminRange(this.label, this.apiWindow);
  final String label;
  final String apiWindow;
}

/// Permanent page identity: projected section names overlap across views.
enum AdminView {
  overview('overview', [
    'dashboard-summary',
    'dashboard-growth',
    'dashboard-dau-engagement',
  ]),
  growth('growth', ['dashboard-growth']),
  activity('activity', ['dashboard-dau-engagement']),
  retention('retention', [
    'dashboard-summary',
    'dashboard-retention',
    'dashboard-retention-mature',
  ]),
  races('races', [
    'dashboard-summary',
    'dashboard-engagement',
    'dashboard-activation',
  ]),
  invites('invites', ['dashboard-funnels']),
  onboarding('onboarding', ['dashboard-funnels']),
  ads('ads', ['dashboard-revenue', 'ads']),
  shop('shop', ['economy']);

  const AdminView(this.apiName, this.sections);
  final String apiName;
  final List<String> sections;
  String window(AdminRange range) => this == shop ? '30d' : range.apiWindow;
}

class _AdminPageData {
  _AdminPageData(AdminView view)
    : sections = {
        for (final section in view.sections) section: AdminSectionData(),
      };
  final Map<String, AdminSectionData> sections;
  Future<void>? pending;
  DateTime? attemptedAt;
}

class AdminSectionData {
  bool loading = false;
  bool calculationPending = false;
  bool followUpExhausted = false;
  String? error;
  DateTime? fetchedAt;
  DateTime? calculatedAt;
  DateTime? freshUntil;
  bool snapshotStale = false;
  bool retryableUnavailable = false;
  int? refreshIntervalSeconds;
  AdminMetricsEnvelope? envelope;
  AdminMetricMap? legacy;
}

/// One session, shared by overview and detail routes. Page reads are serialized
/// and stored under captured view/window keys, never under overlapping section
/// names alone. A late response cannot overwrite a different view or range.
class AdminDashboardController extends ChangeNotifier
    with WidgetsBindingObserver {
  AdminDashboardController(this.api, this.auth, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }
  final BackendApiService api;
  final AuthService auth;
  final DateTime Function() _now;
  AdminRange range = AdminRange.week;
  final Map<String, _AdminPageData> _cache = {};
  bool _oldServer = false;
  Future<void> _queue = Future.value();
  bool _disposed = false;
  Timer? _refreshTimer;
  final Map<Object, _VisibleAnalytics> _visibleAnalytics = {};
  bool _foreground = true;

  /// One timer for the shared session, including stacked detail routes. Only
  /// the top visible analytics route may request a refresh.
  void watchAnalytics(
    Object owner, {
    required bool Function() isVisible,
    required Future<void> Function() refresh,
    required AdminView Function() view,
  }) {
    _visibleAnalytics.remove(owner)?.followUp?.cancel();
    _visibleAnalytics[owner] = _VisibleAnalytics(
      isVisible,
      refresh,
      view,
      _now(),
    );
    _startRefreshTimer();
  }

  void unwatchAnalytics(Object owner) {
    _visibleAnalytics.remove(owner)?.followUp?.cancel();
    if (_visibleAnalytics.isEmpty) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  void _startRefreshTimer() {
    if (_disposed ||
        !_foreground ||
        _visibleAnalytics.isEmpty ||
        _refreshTimer != null) {
      return;
    }
    _refreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _refreshVisible(force: true);
    });
  }

  void _refreshVisible({bool force = false}) {
    if (_disposed || !_foreground) return;
    final now = _now();
    for (final view in _visibleAnalytics.values.toList()) {
      _syncWatchedPage(view);
      if (!view.isVisible() || view.pending) continue;
      final page = _page(view.view(), range);
      final needsFirstAttempt =
          page.attemptedAt == null && page.pending == null;
      if (!force &&
          !needsFirstAttempt &&
          now.difference(view.checkedAt) < const Duration(minutes: 15)) {
        continue;
      }
      view.checkedAt = now;
      view.followUpAttempts = 0;
      view.followUp?.cancel();
      view.followUp = null;
      view.pending = true;
      unawaited(
        view.refresh().whenComplete(() {
          view.pending = false;
          _scheduleFollowUps();
        }),
      );
    }
  }

  void _syncWatchedPage(_VisibleAnalytics watcher) {
    final view = watcher.view();
    final key = '${view.apiName}:${view.window(range)}';
    if (watcher.pageKey == key) return;
    watcher.pageKey = key;
    watcher.followUp?.cancel();
    watcher.followUp = null;
    watcher.followUpAttempts = 0;
    watcher.checkedAt = _now();
  }

  bool _needsFollowUp(_VisibleAnalytics watcher) {
    final view = watcher.view();
    return view.sections.any((section) {
      final data = state(section, view: view);
      return data.retryableUnavailable ||
          (data.snapshotStale && data.error == null);
    });
  }

  /// A stale response (or a cold 503) may precede a build that finishes within
  /// the backend's 45-second deadline. Read the ordinary cached endpoint after
  /// 50 seconds, at most twice per 15-minute cycle. Never force a server rebuild.
  void _scheduleFollowUps() {
    if (_disposed || !_foreground) return;
    for (final view in _visibleAnalytics.values.toList()) {
      _syncWatchedPage(view);
      if (!view.isVisible() || !_needsFollowUp(view)) {
        view.followUp?.cancel();
        view.followUp = null;
        continue;
      }
      if (view.pending || view.followUp != null) continue;
      if (view.followUpAttempts >= 2) {
        var changed = false;
        final pageView = view.view();
        for (final section in pageView.sections) {
          final data = state(section, view: pageView);
          if (data.calculationPending && !data.followUpExhausted) {
            data.followUpExhausted = true;
            changed = true;
          }
        }
        if (changed) _notify();
        continue;
      }
      view.followUp = Timer(const Duration(seconds: 50), () {
        view.followUp = null;
        if (_disposed || !_foreground || !view.isVisible() || view.pending) {
          return;
        }
        if (!_needsFollowUp(view)) return;
        view.followUpAttempts++;
        view.pending = true;
        unawaited(
          loadPage(view.view(), refresh: true).whenComplete(() {
            view.pending = false;
            _scheduleFollowUps();
          }),
        );
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      for (final view in _visibleAnalytics.values) {
        view.followUp?.cancel();
        view.followUp = null;
      }
    } else {
      _refreshVisible();
      _scheduleFollowUps();
      _startRefreshTimer();
    }
  }

  AdminSystemHealthEnvelope? health;
  AdminSystemHealthFetchStatus? healthStatus;
  bool healthLoading = false;
  bool healthFailed = false;
  Future<void>? _healthPending;

  _AdminPageData _page(AdminView view, AdminRange selected) =>
      _cache.putIfAbsent(
        '${view.apiName}:${view.window(selected)}',
        () => _AdminPageData(view),
      );

  AdminSectionData state(
    String section, {
    required AdminView view,
    AdminRange? range,
  }) {
    return _page(
      view,
      range ?? this.range,
    ).sections.putIfAbsent(section, AdminSectionData.new);
  }

  void selectRange(AdminRange value) {
    if (range == value) return;
    range = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _ensureCanDispatch(AdminView view, AdminRange selected) {
    final stillVisible =
        !_disposed &&
        _foreground &&
        view.window(range) == view.window(selected) &&
        _visibleAnalytics.values.any(
          (watcher) => watcher.view() == view && watcher.isVisible(),
        );
    if (!stillVisible) throw const _AdminPageLoadCanceled();
  }

  Future<void> loadPage(
    AdminView view, {
    bool refresh = false,
    AdminRange? range,
  }) {
    final selected = range ?? this.range;
    final page = _page(view, selected);
    final pending = page.pending;
    if (pending != null) return pending;
    final attemptedAt = page.attemptedAt;
    if (!refresh &&
        attemptedAt != null &&
        _now().difference(attemptedAt) < const Duration(minutes: 15)) {
      _scheduleFollowUps();
      return Future.value();
    }
    for (final data in page.sections.values) {
      data.loading = true;
    }
    _notify();
    final operation = _queue.then((_) async {
      var canceled = false;
      try {
        // Visibility may have changed while another page owned the queue.
        _ensureCanDispatch(view, selected);
        final token = auth.authToken;
        if (token == null || token.isEmpty) {
          throw const ApiException(
            'Sign in again to view admin statistics.',
            statusCode: 401,
          );
        }
        if (_oldServer) {
          await _loadLegacyPage(view, selected, token);
        } else {
          final result = await api.fetchAdminStatsView(
            identityToken: token,
            view: view.apiName,
            window: view.window(selected),
            section: view.sections.first,
          );
          if (_disposed) return;
          if (!result.containsKey('view') && !result.containsKey('sections')) {
            // Old servers ignore the additive query and return the compatible
            // first section. Reuse it; only fetch the remaining sections once.
            _oldServer = true;
            await _loadLegacyPage(view, selected, token, firstReply: result);
          } else {
            final projection = AdminMetricMap.from(result);
            final sections = projection?.map('sections');
            if (projection?.text('view') != view.apiName || sections == null) {
              throw const FormatException('Malformed advertised page response');
            }
            for (final section in view.sections) {
              final raw = sections.raw(section);
              final data = state(section, view: view, range: selected);
              if (raw is! Map) {
                _fail(data, const FormatException('Missing projected section'));
                continue;
              }
              final inner = <String, dynamic>{
                for (final entry in raw.entries)
                  if (entry.key is String) entry.key.toString(): entry.value,
              };
              // The outer snapshot is authoritative page metadata. Optional
              // inner metadata remains a fallback for compatible responses.
              if (result.containsKey('snapshot')) {
                inner['snapshot'] = result['snapshot'];
              }
              if (result.containsKey('generatedAt')) {
                inner['generatedAt'] = result['generatedAt'];
              }
              _acceptSection(data, section, inner);
            }
          }
        }
      } on _AdminPageLoadCanceled {
        canceled = true;
      } catch (error) {
        if (_disposed) return;
        for (final data in page.sections.values) {
          _fail(data, error);
        }
      } finally {
        page.pending = null;
        for (final data in page.sections.values) {
          data.loading = false;
        }
        if (!_disposed) {
          // A canceled queue entry is not a completed attempt. Reopening or
          // resuming this page must still be able to perform its first read.
          if (!canceled) page.attemptedAt = _now();
          _notify();
          _scheduleFollowUps();
        }
      }
    });
    page.pending = operation;
    _queue = operation;
    return operation;
  }

  Future<void> _loadLegacyPage(
    AdminView view,
    AdminRange selected,
    String token, {
    Map<String, dynamic>? firstReply,
  }) async {
    for (var index = 0; index < view.sections.length; index++) {
      _ensureCanDispatch(view, selected);
      final section = view.sections[index];
      final data = state(section, view: view, range: selected);
      try {
        final stats = index == 0 && firstReply != null
            ? firstReply
            : await api.fetchAdminStats(
                identityToken: token,
                sections: [
                  section == 'dashboard-retention-mature'
                      ? 'dashboard-retention'
                      : section,
                ],
                window: section == 'dashboard-retention-mature'
                    ? '90d'
                    : section.startsWith('dashboard-')
                    ? selected.apiWindow
                    : null,
              );
        if (_disposed) return;
        _acceptSection(data, section, stats);
      } catch (error) {
        if (_disposed) return;
        _fail(data, error);
        if (error is ApiException &&
            (error.statusCode == 401 || error.statusCode == 403)) {
          rethrow;
        }
      }
    }
  }

  void _acceptSection(
    AdminSectionData data,
    String section,
    Map<String, dynamic> stats,
  ) {
    final envelope = AdminMetricsEnvelope.fromStats(stats);
    if (envelope.status == AdminDashboardStatus.disabled) {
      // Explicit server disablement supersedes all cached enabled pages/ranges.
      for (final page in _cache.values) {
        page.attemptedAt = null;
        for (final entry in page.sections.values) {
          entry
            ..envelope = null
            ..legacy = null
            ..calculatedAt = null
            ..fetchedAt = null
            ..freshUntil = null
            ..snapshotStale = false
            ..retryableUnavailable = false
            ..calculationPending = false
            ..refreshIntervalSeconds = null;
        }
      }
      _fail(data, const ApiException('Analytics are disabled on this server.'));
      return;
    }
    if (section.startsWith('dashboard-')) {
      if (!envelope.present ||
          envelope.status != AdminDashboardStatus.available) {
        _fail(data, const FormatException('Unavailable metric envelope'));
        return;
      }
      data.envelope = envelope;
    } else {
      data.legacy = AdminMetricMap.from(stats);
    }
    final metadata = AdminMetricMap.from(stats);
    final snapshot = metadata?.map('snapshot');
    data.calculatedAt =
        DateTime.tryParse(snapshot?.text('generatedAt') ?? '')?.toLocal() ??
        DateTime.tryParse(metadata?.text('generatedAt') ?? '')?.toLocal();
    data.freshUntil = DateTime.tryParse(snapshot?.text('freshUntil') ?? '');
    data.snapshotStale = snapshot?.text('status') == 'stale';
    data.refreshIntervalSeconds = snapshot?.integer('refreshIntervalSeconds');
    data.fetchedAt = _now();
    data.error = null;
    data.retryableUnavailable = false;
    data.calculationPending = false;
    data.followUpExhausted = false;
  }

  void _fail(AdminSectionData data, Object error) {
    data.followUpExhausted = false;
    final apiError = error is ApiException ? error : null;
    data.retryableUnavailable = apiError?.statusCode == 503;
    data.calculationPending =
        apiError?.statusCode == 503 &&
        apiError?.code == 'ADMIN_ANALYTICS_PENDING';
    data.error = data.calculationPending
        ? null
        : switch (apiError?.statusCode) {
            401 => 'Your session has expired. Sign in again.',
            403 => 'Admin access is required.',
            404 => 'This section requires a server update.',
            _ => 'Couldn’t update this section.',
          };
  }

  Future<void> loadHealth() {
    final pending = _healthPending;
    if (pending != null) return pending;
    healthLoading = true;
    _notify();
    final operation = _queue.then((_) async {
      try {
        if (_disposed) return;
        final token = auth.authToken;
        if (token == null || token.isEmpty) {
          throw const ApiException('Missing authentication');
        }
        final result = await api.fetchAdminSystemHealth(identityToken: token);
        if (_disposed) return;
        healthStatus = result.status;
        if (result.status == AdminSystemHealthFetchStatus.available &&
            result.health != null) {
          health = result.health;
          healthFailed = false;
        } else {
          healthFailed = health != null;
        }
      } catch (_) {
        healthFailed = true;
      } finally {
        healthLoading = false;
        _healthPending = null;
        _notify();
      }
    });
    _healthPending = operation;
    _queue = operation;
    return operation;
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    for (final view in _visibleAnalytics.values) {
      view.followUp?.cancel();
    }
    _visibleAnalytics.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _VisibleAnalytics {
  _VisibleAnalytics(this.isVisible, this.refresh, this.view, this.checkedAt);
  final bool Function() isVisible;
  final Future<void> Function() refresh;
  final AdminView Function() view;
  Timer? followUp;
  String? pageKey;
  int followUpAttempts = 0;
  DateTime checkedAt;
  bool pending = false;
}

class _AdminPageLoadCanceled implements Exception {
  const _AdminPageLoadCanceled();
}
