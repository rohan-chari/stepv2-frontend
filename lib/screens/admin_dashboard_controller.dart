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

class AdminSectionData {
  bool loading = false;
  String? error;
  DateTime? fetchedAt;
  DateTime? calculatedAt;
  DateTime? freshUntil;
  bool snapshotStale = false;
  bool retryableUnavailable = false;
  int? refreshIntervalSeconds;
  AdminMetricsEnvelope? envelope;
  AdminMetricMap? legacy;
  Future<void>? pending;
}

/// One session, shared by overview and detail routes. All stats reads are
/// serialized; responses are stored under their captured API window so an old
/// completion can never overwrite the newly selected range.
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
  final Map<String, AdminSectionData> _cache = {};
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
    required Iterable<String> Function() sections,
  }) {
    _visibleAnalytics.remove(owner)?.followUp?.cancel();
    _visibleAnalytics[owner] = _VisibleAnalytics(
      isVisible,
      refresh,
      sections,
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
      if (!view.isVisible() || view.pending) continue;
      if (!force &&
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

  List<String> _sectionsNeedingFollowUp(_VisibleAnalytics view) => [
    for (final section in view.sections())
      if (state(section).retryableUnavailable ||
          (state(section).snapshotStale && state(section).error == null))
        section,
  ];

  /// A stale response (or a cold 503) may precede a build that finishes within
  /// the backend's 45-second deadline. Read the ordinary cached endpoint after
  /// 50 seconds, at most twice per 15-minute cycle. Never force a server rebuild.
  void _scheduleFollowUps() {
    if (_disposed || !_foreground) return;
    for (final view in _visibleAnalytics.values.toList()) {
      if (!view.isVisible() || _sectionsNeedingFollowUp(view).isEmpty) {
        view.followUp?.cancel();
        view.followUp = null;
        continue;
      }
      if (view.pending || view.followUp != null || view.followUpAttempts >= 2) {
        continue;
      }
      view.followUp = Timer(const Duration(seconds: 50), () {
        view.followUp = null;
        if (_disposed || !_foreground || !view.isVisible() || view.pending) {
          return;
        }
        final sections = _sectionsNeedingFollowUp(view);
        if (sections.isEmpty) return;
        view.followUpAttempts++;
        view.pending = true;
        unawaited(
          loadAll(sections, refresh: true).whenComplete(() {
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

  AdminSectionData state(String section, {AdminRange? range}) {
    final window = section == 'dashboard-retention-mature'
        ? '90d'
        : section.startsWith('dashboard-')
        ? (range ?? this.range).apiWindow
        : '30d';
    return _cache.putIfAbsent('$section:$window', AdminSectionData.new);
  }

  void selectRange(AdminRange value) {
    if (range == value) return;
    range = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadAll(
    Iterable<String> sections, {
    bool refresh = false,
  }) async {
    final captured = range;
    for (final section in sections) {
      // Capture all requested ranges before waiting in the serial queue.
      unawaited(load(section, refresh: refresh, range: captured));
    }
    await _queue;
    _scheduleFollowUps();
  }

  Future<void> load(String section, {bool refresh = false, AdminRange? range}) {
    final selected = range ?? this.range;
    final data = state(section, range: selected);
    final pending = data.pending;
    if (pending != null) return pending;
    if (!refresh && (data.fetchedAt != null || data.error != null)) {
      return Future.value();
    }
    data.loading = true;
    _notify();
    final operation = _queue.then((_) async {
      if (_disposed) return;
      try {
        final token = auth.authToken;
        if (token == null || token.isEmpty) {
          throw const ApiException(
            'Sign in again to view admin statistics.',
            statusCode: 401,
          );
        }
        final stats = await api.fetchAdminStats(
          identityToken: token,
          // The internal mature-retention key uses the already-supported
          // fixed 90-day cohort request, without adding a user range toggle.
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
        if (section.startsWith('dashboard-')) {
          final envelope = AdminMetricsEnvelope.fromStats(stats);
          if (envelope.status == AdminDashboardStatus.disabled) {
            // The server's explicit disablement supersedes every cached range.
            for (final entry in _cache.entries) {
              if (!entry.key.startsWith('dashboard-')) continue;
              entry.value
                ..envelope = null
                ..calculatedAt = null
                ..fetchedAt = null
                ..freshUntil = null
                ..snapshotStale = false
                ..retryableUnavailable = false
                ..refreshIntervalSeconds = null;
            }
          }
          if (!envelope.present ||
              envelope.status != AdminDashboardStatus.available) {
            throw const ApiException(
              'This section is unavailable on this server.',
            );
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
        data.refreshIntervalSeconds = snapshot?.integer(
          'refreshIntervalSeconds',
        );
        data.fetchedAt = _now();
        data.error = null;
        data.retryableUnavailable = false;
      } on ApiException catch (error) {
        data.retryableUnavailable = error.statusCode == 503;
        data.error = switch (error.statusCode) {
          401 => 'Your session has expired. Sign in again.',
          403 => 'Admin access is required.',
          404 => 'This section requires a server update.',
          _ => 'Couldn’t update this section.',
        };
      } catch (_) {
        data.retryableUnavailable = false;
        data.error = 'Couldn’t update this section.';
      } finally {
        data.loading = false;
        data.pending = null;
        _notify();
      }
    });
    data.pending = operation;
    _queue = operation;
    return operation;
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
  _VisibleAnalytics(
    this.isVisible,
    this.refresh,
    this.sections,
    this.checkedAt,
  );
  final bool Function() isVisible;
  final Future<void> Function() refresh;
  final Iterable<String> Function() sections;
  Timer? followUp;
  int followUpAttempts = 0;
  DateTime checkedAt;
  bool pending = false;
}
