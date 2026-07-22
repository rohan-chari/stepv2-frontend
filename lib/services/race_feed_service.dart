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

  factory RaceFeedEvent.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['createdAt'] as String?;
    return RaceFeedEvent(
      id: json['id'] as String,
      eventType: (json['eventType'] as String?) ?? '',
      powerupType: json['powerupType'] as String?,
      description:
          (json['body'] as String?) ?? (json['description'] as String?) ?? '',
      actorUserId: json['actorUserId'] as String?,
      targetUserId: json['targetUserId'] as String?,
      createdAt: createdRaw != null
          ? DateTime.tryParse(createdRaw)?.toLocal() ?? DateTime.now()
          : DateTime.now(),
    );
  }
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
      final list =
          (result['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _events
        ..clear()
        ..addAll(list.map(RaceFeedEvent.fromJson));
      _cursor = result['nextCursor'] as String?;
      _hasMore = _cursor != null;
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
      final list =
          (result['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _events.addAll(list.map(RaceFeedEvent.fromJson));
      _cursor = result['nextCursor'] as String?;
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
      final list =
          (result['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final fresh = list.map(RaceFeedEvent.fromJson).toList();
      final existingIds = _events.map((e) => e.id).toSet();
      final newEvents = fresh
          .where((e) => !existingIds.contains(e.id))
          .toList();
      if (newEvents.isEmpty) return;
      _events.insertAll(0, newEvents);
      _events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _safeNotify();
    } catch (_) {
      // Silent — polling.
    }
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
