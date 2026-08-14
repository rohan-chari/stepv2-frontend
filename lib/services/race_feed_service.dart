import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'backend_api_service.dart';

/// A single powerup/system event in the race Activity feed.
class RaceFeedEvent {
  final String id;
  final String eventType;
  final String? powerupType;
  final String description;
  final String? actorUserId;
  final String? targetUserId;
  final DateTime createdAt;

  const RaceFeedEvent({
    required this.id,
    required this.eventType,
    required this.description,
    required this.createdAt,
    this.powerupType,
    this.actorUserId,
    this.targetUserId,
  });

  static RaceFeedEvent? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final createdRaw = raw['createdAt'];
    return RaceFeedEvent(
      id: id,
      eventType: raw['eventType'] is String ? raw['eventType'] as String : '',
      powerupType: raw['powerupType'] is String
          ? raw['powerupType'] as String
          : null,
      description: raw['body'] is String
          ? raw['body'] as String
          : raw['description'] is String
          ? raw['description'] as String
          : '',
      actorUserId: raw['actorUserId'] is String
          ? raw['actorUserId'] as String
          : null,
      targetUserId: raw['targetUserId'] is String
          ? raw['targetUserId'] as String
          : null,
      createdAt: createdRaw != null
          ? DateTime.tryParse(
                  createdRaw is String ? createdRaw : '',
                )?.toLocal() ??
                DateTime.now()
          : DateTime.now(),
    );
  }

  factory RaceFeedEvent.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json) ??
      RaceFeedEvent(
        id: 'invalid_${DateTime.now().microsecondsSinceEpoch}',
        eventType: '',
        description: '',
        createdAt: DateTime.now(),
      );
}

/// Per-race Activity (system/powerup events) state. Read-only feed that mirrors
/// [RaceChatService] but loads `/races/:raceId/messages?kind=SYSTEM`.
class RaceFeedService extends ChangeNotifier {
  RaceFeedService({
    required this.authService,
    required this.raceId,
    required this.api,
  });

  final AuthService authService;
  final String raceId;
  final BackendApiService api;

  final List<RaceFeedEvent> _events = [];
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _disposed = false;
  Object? _lastError;
  Timer? _pollTimer;

  List<RaceFeedEvent> get events => List.unmodifiable(_events);
  bool get isLoading => _loading;
  bool get hasMore => _hasMore;
  Object? get lastError => _lastError;

  void beginCombinedLoad() {
    if (_disposed) return;
    _loading = true;
    _lastError = null;
    _safeNotify();
  }

  void endCombinedLoad() {
    if (_disposed) return;
    _loading = false;
  }

  String? get _token => authService.authToken;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadInitial() async {
    if (_disposed || _loading) return;
    _loading = true;
    _lastError = null;
    _safeNotify();
    try {
      final token = _token;
      if (token == null) throw const ApiException('Not signed in');
      final result = await api.fetchRaceMessages(
        identityToken: token,
        raceId: raceId,
        limit: 50,
        kind: 'SYSTEM',
      );
      if (_disposed) return;
      applyInitialStream(result);
    } catch (e) {
      _lastError = e;
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  Future<void> loadMore() async {
    if (_disposed || _loading || !_hasMore || _cursor == null) return;
    _loading = true;
    _safeNotify();
    try {
      final token = _token;
      if (token == null) throw const ApiException('Not signed in');
      final result = await api.fetchRaceMessages(
        identityToken: token,
        raceId: raceId,
        cursor: _cursor,
        limit: 50,
        kind: 'SYSTEM',
      );
      if (_disposed) return;
      final list = result['messages'];
      if (list is List) {
        _events.addAll(
          list.map(RaceFeedEvent.tryFromJson).whereType<RaceFeedEvent>(),
        );
      }
      _cursor = result['nextCursor'] is String
          ? result['nextCursor'] as String
          : null;
      _hasMore = _cursor != null;
    } catch (e) {
      _lastError = e;
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  /// Polls newest events, merging by id.
  Future<void> refreshTop() async {
    if (_disposed) return;
    try {
      final token = _token;
      if (token == null) return;
      final result = await api.fetchRaceMessages(
        identityToken: token,
        raceId: raceId,
        limit: 50,
        kind: 'SYSTEM',
      );
      if (_disposed) return;
      applyTopStream(result);
    } catch (_) {
      // Silent — polling.
    }
  }

  void applyInitialStream(Map<String, dynamic> stream) {
    if (_disposed) return;
    final list = stream['messages'];
    _events
      ..clear()
      ..addAll(
        list is List
            ? list.map(RaceFeedEvent.tryFromJson).whereType<RaceFeedEvent>()
            : const <RaceFeedEvent>[],
      );
    _cursor = stream['nextCursor'] is String
        ? stream['nextCursor'] as String
        : null;
    _hasMore = _cursor != null;
    _loading = false;
    _lastError = null;
    _safeNotify();
  }

  void applyTopStream(Map<String, dynamic> stream) {
    if (_disposed) return;
    final list = stream['messages'];
    final fresh = list is List
        ? list.map(RaceFeedEvent.tryFromJson).whereType<RaceFeedEvent>()
        : const Iterable<RaceFeedEvent>.empty();
    final existingIds = _events.map((event) => event.id).toSet();
    final additions = fresh
        .where((event) => !existingIds.contains(event.id))
        .toList();
    if (additions.isEmpty) return;
    _events.insertAll(0, additions);
    _events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _safeNotify();
  }

  void applyCombinedError(Object error) {
    if (_disposed) return;
    _loading = false;
    _lastError = error;
    _safeNotify();
  }

  void startPolling({Duration interval = const Duration(seconds: 5)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => refreshTop());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}
