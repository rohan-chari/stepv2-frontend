import 'dart:async';

import 'package:flutter/foundation.dart';

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
  AdminMetricsEnvelope? envelope;
  AdminMetricMap? legacy;
  Future<void>? pending;
}

/// One session, shared by overview and detail routes. All stats reads are
/// serialized; responses are stored under their captured API window so an old
/// completion can never overwrite the newly selected range.
class AdminDashboardController extends ChangeNotifier {
  AdminDashboardController(this.api, this.auth);
  final BackendApiService api;
  final AuthService auth;
  AdminRange range = AdminRange.week;
  final Map<String, AdminSectionData> _cache = {};
  Future<void> _queue = Future.value();
  bool _disposed = false;

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
        data.fetchedAt = DateTime.now();
        data.error = null;
      } on ApiException catch (error) {
        data.error = switch (error.statusCode) {
          401 => 'Your session has expired. Sign in again.',
          403 => 'Admin access is required.',
          404 => 'This section requires a server update.',
          _ => 'Couldn’t update this section.',
        };
      } catch (_) {
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
    super.dispose();
  }
}
