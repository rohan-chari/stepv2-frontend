import 'dart:async';

import 'package:flutter/foundation.dart';

import 'backend_api_service.dart';

/// Main-shell-owned, request-coalescing friends snapshot. The one-second reuse
/// window only absorbs duplicate UI triggers; it is not a background TTL.
class FriendsSummaryRepository extends ChangeNotifier {
  FriendsSummaryRepository(this.api);

  final BackendApiService api;
  Future<Map<String, dynamic>>? _inFlight;
  Map<String, dynamic>? _last;
  DateTime? _lastAt;

  void seed(Map<String, dynamic> snapshot) {
    _last = snapshot;
    _lastAt = DateTime.now();
  }

  int _revision = 0;
  int get revision => _revision;

  void invalidate() {
    _revision++;
    _lastAt = null;
    notifyListeners();
  }

  void clear() {
    _last = null;
    _inFlight = null;
    invalidate();
  }

  Future<Map<String, dynamic>> fetch({
    required String identityToken,
    bool force = false,
  }) {
    final active = _inFlight;
    if (active != null) return active;
    final at = _lastAt;
    if (!force &&
        _last != null &&
        at != null &&
        DateTime.now().difference(at) <= const Duration(seconds: 1)) {
      return Future.value(_last);
    }
    final revision = _revision;
    late final Future<Map<String, dynamic>> request;
    request = api
        .fetchFriends(identityToken: identityToken)
        .then((snapshot) {
          if (revision == _revision) {
            _last = snapshot;
            _lastAt = DateTime.now();
          }
          return snapshot;
        })
        .whenComplete(() {
          if (identical(_inFlight, request)) _inFlight = null;
        });
    _inFlight = request;
    return request;
  }
}
