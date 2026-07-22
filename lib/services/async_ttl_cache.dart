/// A tiny in-memory cache with a freshness TTL and in-flight de-duplication.
///
/// Used for the authenticated-session shop catalog (spec §9.3): a fresh value is
/// served without a network call, concurrent misses share ONE request, stale
/// data remains readable while a refresh runs, and explicit events invalidate or
/// clear it. It deliberately does not persist across app launches.
class AsyncTtlCache<T> {
  AsyncTtlCache({required this.ttl, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _clock;

  T? _value;
  DateTime? _fetchedAt;
  Future<T>? _inFlight;

  /// The last cached value (may be stale). Null before the first success.
  T? get value => _value;

  bool get hasValue => _value != null;

  /// True when a value exists and was fetched within [ttl].
  bool get isFresh =>
      _value != null &&
      _fetchedAt != null &&
      _clock().difference(_fetchedAt!) < ttl;

  /// Returns a fresh value without calling [fetch]; otherwise runs (or joins) a
  /// single in-flight [fetch]. On success the value + timestamp are recorded; on
  /// error nothing is cached and the error propagates to every joined caller.
  Future<T> get(Future<T> Function() fetch, {bool forceRefresh = false}) {
    if (!forceRefresh && isFresh) {
      return Future<T>.value(_value as T);
    }
    final existing = _inFlight;
    if (existing != null) return existing;

    late final Future<T> future;
    future = () async {
      try {
        final v = await fetch();
        _value = v;
        _fetchedAt = _clock();
        return v;
      } finally {
        // Clear the handle whether the fetch succeeded or failed.
        if (identical(_inFlight, future)) _inFlight = null;
      }
    }();
    _inFlight = future;
    return future;
  }

  /// Records an externally-supplied fresh value (e.g. a catalog returned by a
  /// purchase/equip response), resetting the TTL window.
  void set(T value) {
    _value = value;
    _fetchedAt = _clock();
  }

  /// Marks the value stale so the next [get] refetches, but keeps it readable
  /// for stale-while-revalidate rendering.
  void invalidate() {
    _fetchedAt = null;
  }

  /// Drops the value entirely (sign-out / user change).
  void clear() {
    _value = null;
    _fetchedAt = null;
    _inFlight = null;
  }
}
