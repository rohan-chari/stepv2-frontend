import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

/// Transport hints deliberately carry no score or replay/version promise.
enum RaceChangeSignal { connected, invalidated }

class RaceChangeStreamException implements Exception {
  const RaceChangeStreamException(this.statusCode);
  final int statusCode;
}

/// Owns one visible race stream. Polling remains the screen's independent safety net.
class RaceChangeRefresh {
  RaceChangeRefresh({required this.connect, required this.refresh, this.trace});
  final Stream<RaceChangeSignal> Function(String token) connect;
  final Future<void> Function() refresh;
  final void Function(String, Map<String, Object>)? trace;
  StreamSubscription<RaceChangeSignal>? _subscription;
  Timer? _window, _retry;
  String? _token;
  bool _active = false, _disposed = false, _running = false, _pending = false;
  bool _blocked = false;
  int _epoch = 0, _failures = 0;
  final _random = Random();

  void _trace(String name, [Map<String, Object> fields = const {}]) {
    try {
      if (trace != null) {
        trace!(name, fields);
      } else {
        developer.Timeline.instantSync(name, arguments: fields);
      }
    } catch (_) {
      // Diagnostic consumers cannot interrupt state transitions or retries.
    }
  }

  void update({required bool active, required String? token}) {
    final next = active && token != null && token.isNotEmpty;
    if (_active == next && _token == token) return;
    final tokenChanged = _token != token;
    _stop();
    _token = token;
    _active = next;
    if (tokenChanged) _blocked = false;
    if (next && !_blocked && !_disposed) _open();
  }

  void _open() {
    final epoch = ++_epoch;
    final started = DateTime.now();
    var ended = false;
    void end([Object? error]) {
      if (ended || epoch != _epoch || !_active || _disposed) return;
      ended = true;
      unawaited(_subscription?.cancel());
      _subscription = null;
      if (error is RaceChangeStreamException &&
          const [401, 403, 404].contains(error.statusCode)) {
        _blocked = true; // Token change can retry; ordinary polling continues.
        return;
      }
      if (DateTime.now().difference(started).inSeconds >= 30) _failures = 0;
      final seconds = min(30, pow(2, min(_failures++, 5)).toInt());
      _retry = Timer(
        Duration(
          milliseconds: (seconds * 1000 * (1 + _random.nextDouble() * .2))
              .round(),
        ),
        _open,
      );
    }

    try {
      _subscription = connect(_token!).listen(
        (signal) {
          if (epoch != _epoch || !_active) return;
          _trace('race_change_received', {'signal': signal.name});
          if (signal == RaceChangeSignal.connected) {
            _request(); // Always reconcile after reconnect; no replay dependency.
          } else {
            hint();
          }
        },
        onError: (Object error) => end(error),
        onDone: end,
      );
    } catch (error) {
      end(error);
    }
  }

  void hint() {
    if (!_active || _disposed || _window != null) return;
    _window = Timer(const Duration(milliseconds: 100), () {
      _window = null;
      _request();
    });
  }

  Future<void> _request() async {
    if (!_active || _disposed) return;
    if (_running) {
      _pending = true;
      return;
    }
    _running = true;
    _trace('race_change_refetch_start');
    try {
      await refresh();
      _trace('race_change_refetch_complete');
    } catch (_) {
      // GET errors are rendered by the screen; polling/reconnect recover.
    } finally {
      _running = false;
      if (_pending) {
        _pending = false;
        hint();
      }
    }
  }

  void _stop() {
    ++_epoch;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _window?.cancel();
    _window = null;
    _retry?.cancel();
    _retry = null;
    _pending = false;
  }

  void dispose() {
    _disposed = true;
    _active = false;
    _stop();
  }
}
