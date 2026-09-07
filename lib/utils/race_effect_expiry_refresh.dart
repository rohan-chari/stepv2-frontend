import 'dart:async';
import 'dart:math';

/// A deadline is only a hint to refresh server state. This coordinator never
/// changes effects or awards results. One screen shares a rolling request budget
/// across every effect, including extensions and newly arriving effects.
class RaceEffectExpiryRefresh {
  RaceEffectExpiryRefresh({
    required this.refresh,
    DateTime Function()? now,
    this.trace,
  }) : _now = now ?? DateTime.now;

  final Future<void> Function() refresh;
  final DateTime Function() _now;
  final void Function(Map<String, Object> fields)? trace;
  late final bool _sampled = _random.nextInt(100) == 0;
  int _traceCount = 0;

  // Local DevTools timeline only: 1% of screen instances, at most ten events.
  // No additional HTTP, personal data, or high-cardinality metric labels.
  void _trace((String, DateTime) key, String stage) {
    if (!_sampled || _traceCount >= 10) return;
    _traceCount++;
    trace?.call({
      'effectId': key.$1,
      'expiresAt': key.$2.toIso8601String(),
      'stage': stage,
      'deadlineAgeMs': _now().difference(key.$2).inMilliseconds,
    });
  }

  final _random = Random();
  final Map<(String, DateTime), int> _attempts = {};
  final Set<Timer> _budgetTimers = {};
  Timer? _timer;
  (String, DateTime)? _scheduledKey;
  DateTime? _waitingForDeadline;
  int _usedBudget = 0;
  bool _enabled = false;
  bool _running = false;
  bool _disposed = false;

  /// Call with the effects rendered by the current progress projection. Unknown
  /// identity/timestamp shapes retain ordinary polling, including older servers.
  void update(Iterable<Object?> effects, {required bool enabled}) {
    if (_disposed) return;
    final keys = <(String, DateTime)>{};
    for (final effect in effects) {
      if (effect is! Map) continue;
      final id = effect['id'];
      final rawExpiry = effect['expiresAt'];
      if (id is! String || id.trim().isEmpty || rawExpiry is! String) continue;
      final expiry = DateTime.tryParse(rawExpiry);
      if (expiry != null) keys.add((id, expiry.toUtc()));
    }
    for (final entry in _attempts.entries) {
      if (entry.value > 0 && !keys.contains(entry.key)) {
        _trace(
          entry.key,
          keys.any((key) => key.$1 == entry.key.$1)
              ? 'deadline_changed'
              : 'absent_from_server_projection',
        );
      }
    }
    _attempts.removeWhere((key, _) => !keys.contains(key));
    for (final key in keys) {
      _attempts.putIfAbsent(key, () => 0);
    }
    _enabled = enabled;
    _schedule();
  }

  void pause() {
    _enabled = false;
    _cancel();
  }

  /// Catch a forward wall-clock adjustment without touching retry backoff or
  /// the rolling budget. A backwards adjustment is rechecked when a timer fires.
  void checkClock() {
    final deadline = _waitingForDeadline;
    if (deadline != null && !deadline.isAfter(_now())) {
      _cancel();
      _schedule();
    }
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _scheduledKey = null;
    _waitingForDeadline = null;
  }

  void _schedule() {
    if (!_enabled || _disposed) {
      _cancel();
      return;
    }
    if (_running) return;
    (String, DateTime)? candidate;
    for (final entry in _attempts.entries) {
      if (entry.value >= 4) continue;
      final current = candidate;
      if (current == null || entry.key.$2.isBefore(current.$2)) {
        candidate = entry.key;
      }
    }
    if (candidate == null || _usedBudget >= 4) {
      _cancel();
      return;
    }
    if (_timer != null && candidate == _scheduledKey) return;
    _cancel();
    final key = candidate;
    final attempt = _attempts[key] ?? 0;
    final untilDeadline = key.$2.difference(_now());
    final Duration delay;
    if (untilDeadline > Duration.zero) {
      delay = untilDeadline;
      _waitingForDeadline = key.$2;
    } else {
      delay = attempt == 0
          ? Duration.zero
          : Duration(seconds: 1 << attempt); // 2, 4, 8 seconds
    }
    _scheduledKey = key;
    _timer = Timer(delay + Duration(milliseconds: _random.nextInt(501)), () {
      _timer = null;
      _scheduledKey = null;
      _waitingForDeadline = null;
      unawaited(_fire(key));
    });
  }

  Future<void> _fire((String, DateTime) key) async {
    if (_disposed || !_enabled || _running || !_attempts.containsKey(key)) {
      return;
    }
    final now = _now();
    if (key.$2.isAfter(now)) {
      _schedule();
      return;
    }
    // One request covers every currently overdue effect, rather than one burst
    // per entry. Newly arriving deadlines still share the same rolling budget.
    for (final entry in _attempts.entries.toList()) {
      if (!entry.key.$2.isAfter(now)) _attempts[entry.key] = entry.value + 1;
    }
    _trace(key, 'refresh_requested');
    _usedBudget++;
    late final Timer budgetTimer;
    budgetTimer = Timer(const Duration(seconds: 30), () {
      _budgetTimers.remove(budgetTimer);
      _usedBudget--;
      _schedule();
    });
    _budgetTimers.add(budgetTimer);
    _running = true;
    try {
      await refresh();
    } finally {
      _running = false;
      _schedule();
    }
  }

  void dispose() {
    _disposed = true;
    _cancel();
    for (final timer in _budgetTimers) {
      timer.cancel();
    }
    _budgetTimers.clear();
    _attempts.clear();
  }
}
