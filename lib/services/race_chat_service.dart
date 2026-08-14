import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'backend_api_service.dart';

class RaceChatMessage {
  final String id;
  final String kind; // 'USER' | 'SYSTEM'
  final String body;
  final String? senderId;
  final String? senderName;
  final String? senderPhotoUrl;
  final String? eventType;
  final String? powerupType;
  final String? actorUserId;
  final DateTime createdAt;
  final bool pending;
  final bool failed;

  const RaceChatMessage({
    required this.id,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.senderId,
    this.senderName,
    this.senderPhotoUrl,
    this.eventType,
    this.powerupType,
    this.actorUserId,
    this.pending = false,
    this.failed = false,
  });

  static RaceChatMessage? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final createdRaw = raw['createdAt'];
    return RaceChatMessage(
      id: id,
      kind: raw['kind'] is String ? raw['kind'] as String : 'USER',
      body: raw['body'] is String ? raw['body'] as String : '',
      senderId: raw['senderId'] is String ? raw['senderId'] as String : null,
      senderName: raw['senderName'] is String
          ? raw['senderName'] as String
          : null,
      senderPhotoUrl: raw['senderPhotoUrl'] is String
          ? raw['senderPhotoUrl'] as String
          : null,
      eventType: raw['eventType'] is String ? raw['eventType'] as String : null,
      powerupType: raw['powerupType'] is String
          ? raw['powerupType'] as String
          : null,
      actorUserId: raw['actorUserId'] is String
          ? raw['actorUserId'] as String
          : null,
      createdAt: createdRaw != null
          ? DateTime.tryParse(
                  createdRaw is String ? createdRaw : '',
                )?.toLocal() ??
                DateTime.now()
          : DateTime.now(),
    );
  }

  factory RaceChatMessage.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json) ??
      RaceChatMessage(
        id: 'invalid_${DateTime.now().microsecondsSinceEpoch}',
        kind: 'USER',
        body: '',
        createdAt: DateTime.now(),
      );

  RaceChatMessage copyWith({bool? pending, bool? failed, String? id}) {
    return RaceChatMessage(
      id: id ?? this.id,
      kind: kind,
      body: body,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      eventType: eventType,
      powerupType: powerupType,
      actorUserId: actorUserId,
      createdAt: createdAt,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
    );
  }
}

/// Per-race chat state. Caller creates one per race screen and disposes it.
class RaceChatService extends ChangeNotifier {
  RaceChatService({
    required this.authService,
    required this.raceId,
    required this.api,
  });

  final AuthService authService;
  final String raceId;
  final BackendApiService api;

  final List<RaceChatMessage> _messages = [];
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _muted = false;
  bool _disposed = false;
  Object? _lastError;
  Timer? _pollTimer;
  bool _hasUnread = false;

  List<RaceChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _loading;
  bool get hasMore => _hasMore;
  bool get isMuted => _muted;
  Object? get lastError => _lastError;

  /// True when new incoming messages arrived from polling while the chat was
  /// not being viewed. Cleared via [markChatViewed].
  bool get hasUnread => _hasUnread;

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
        kind: 'USER',
      );
      if (_disposed) return;
      applyInitialStream(result);
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
        kind: 'USER',
      );
      if (_disposed) return;
      final list = result['messages'];
      if (list is List) {
        _messages.addAll(list.map(RaceChatMessage.tryFromJson).whereType());
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

  /// Polls newest messages, merging by id.
  Future<void> refreshTop() async {
    if (_disposed) return;
    try {
      final token = _token;
      if (token == null) return;
      final result = await api.fetchRaceMessages(
        identityToken: token,
        raceId: raceId,
        limit: 50,
        kind: 'USER',
      );
      if (_disposed) return;
      applyTopStream(result);
    } catch (_) {
      // Silent — polling.
    }
  }

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

  void clearUnread() {
    if (_disposed || !_hasUnread) return;
    _hasUnread = false;
    _safeNotify();
  }

  void applyInitialStream(Map<String, dynamic> stream) {
    if (_disposed) return;
    final list = stream['messages'];
    final fresh = list is List
        ? list.map(RaceChatMessage.tryFromJson).whereType<RaceChatMessage>()
        : const Iterable<RaceChatMessage>.empty();
    // Preserve optimistic sends created while the initial request was in
    // flight, then merge server rows by stable id.
    final optimistic = _messages.where((message) => message.pending).toList();
    final byId = <String, RaceChatMessage>{
      for (final message in fresh) message.id: message,
      for (final message in optimistic) message.id: message,
    };
    _messages
      ..clear()
      ..addAll(byId.values)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
        ? list.map(RaceChatMessage.tryFromJson).whereType<RaceChatMessage>()
        : const Iterable<RaceChatMessage>.empty();
    final existingIds = _messages.map((message) => message.id).toSet();
    final additions = fresh
        .where((message) => !existingIds.contains(message.id))
        .toList();
    if (additions.isNotEmpty) {
      _hasUnread = true;
      _messages.insertAll(0, additions);
      _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    _loading = false;
    _lastError = null;
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

  Future<void> send(String text) async {
    if (_disposed) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = RaceChatMessage(
      id: tempId,
      kind: 'USER',
      body: trimmed,
      senderId: null,
      senderName: 'You',
      createdAt: DateTime.now(),
      pending: true,
    );
    _messages.insert(0, optimistic);
    _safeNotify();
    try {
      final token = _token;
      if (token == null) throw const ApiException('Not signed in');
      final result = await api.sendRaceMessage(
        identityToken: token,
        raceId: raceId,
        body: trimmed,
      );
      if (_disposed) return;
      final msgJson = result['message'] as Map<String, dynamic>?;
      if (msgJson != null) {
        final created = RaceChatMessage.fromJson(msgJson);
        final existingServerIdx = _messages.indexWhere(
          (m) => m.id == created.id,
        );
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (existingServerIdx != -1) {
          _messages[existingServerIdx] = created;
          if (idx != -1 && idx != existingServerIdx) {
            _messages.removeAt(idx);
          }
        } else if (idx != -1) {
          _messages[idx] = created;
        }
      } else {
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(pending: false);
        }
      }
    } catch (e) {
      if (_disposed) return;
      final idx = _messages.indexWhere((m) => m.id == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(pending: false, failed: true);
      }
      _lastError = e;
    } finally {
      _safeNotify();
    }
  }

  Future<void> deleteMessage(String messageId) async {
    if (_disposed) return;
    final token = _token;
    if (token == null) return;
    try {
      await api.deleteRaceMessage(
        identityToken: token,
        raceId: raceId,
        messageId: messageId,
      );
      if (_disposed) return;
      _messages.removeWhere((m) => m.id == messageId);
      _safeNotify();
    } catch (e) {
      if (_disposed) return;
      _lastError = e;
      _safeNotify();
    }
  }

  Future<void> setMuted(bool muted) async {
    if (_disposed) return;
    final token = _token;
    if (token == null) return;
    final previous = _muted;
    _muted = muted;
    _safeNotify();
    try {
      await api.setRaceChatMute(
        identityToken: token,
        raceId: raceId,
        muted: muted,
      );
    } catch (e) {
      if (_disposed) return;
      _muted = previous;
      _lastError = e;
      _safeNotify();
    }
  }

  void setMutedFromServer(bool muted) {
    if (_disposed || _muted == muted) return;
    _muted = muted;
    _safeNotify();
  }

  Future<void> markRead() async {
    if (_disposed) return;
    final token = _token;
    if (token == null) return;
    try {
      await api.markRaceChatRead(identityToken: token, raceId: raceId);
    } catch (_) {}
  }

  /// Clears the unread indicator and persists the read state on the server.
  /// Call when the user opens/views the Chat tab.
  void markChatViewed() {
    if (_disposed) return;
    clearUnread();
    markRead();
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}
