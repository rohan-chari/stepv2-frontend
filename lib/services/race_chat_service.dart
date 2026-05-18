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

  factory RaceChatMessage.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['createdAt'] as String?;
    return RaceChatMessage(
      id: json['id'] as String,
      kind: (json['kind'] as String?) ?? 'USER',
      body: (json['body'] as String?) ?? '',
      senderId: json['senderId'] as String?,
      senderName: json['senderName'] as String?,
      senderPhotoUrl: json['senderPhotoUrl'] as String?,
      eventType: json['eventType'] as String?,
      powerupType: json['powerupType'] as String?,
      actorUserId: json['actorUserId'] as String?,
      createdAt: createdRaw != null
          ? DateTime.tryParse(createdRaw)?.toLocal() ?? DateTime.now()
          : DateTime.now(),
    );
  }

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
  Object? _lastError;
  Timer? _pollTimer;

  List<RaceChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _loading;
  bool get hasMore => _hasMore;
  bool get isMuted => _muted;
  Object? get lastError => _lastError;

  String? get _token => authService.identityToken;

  Future<void> loadInitial() async {
    if (_loading) return;
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final token = _token;
      if (token == null) throw const ApiException('Not signed in');
      final result = await api.fetchRaceMessages(
        identityToken: token,
        raceId: raceId,
        limit: 50,
      );
      final list =
          (result['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _messages
        ..clear()
        ..addAll(list.map(RaceChatMessage.fromJson));
      _cursor = result['nextCursor'] as String?;
      _hasMore = _cursor != null;
    } catch (e) {
      _lastError = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loading || !_hasMore || _cursor == null) return;
    _loading = true;
    notifyListeners();
    try {
      final token = _token;
      if (token == null) throw const ApiException('Not signed in');
      final result = await api.fetchRaceMessages(
        identityToken: token,
        raceId: raceId,
        cursor: _cursor,
        limit: 50,
      );
      final list =
          (result['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _messages.addAll(list.map(RaceChatMessage.fromJson));
      _cursor = result['nextCursor'] as String?;
      _hasMore = _cursor != null;
    } catch (e) {
      _lastError = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Polls newest messages, merging by id.
  Future<void> refreshTop() async {
    try {
      final token = _token;
      if (token == null) return;
      final result = await api.fetchRaceMessages(
        identityToken: token,
        raceId: raceId,
        limit: 50,
      );
      final list =
          (result['messages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final fresh = list.map(RaceChatMessage.fromJson).toList();
      final existingIds = _messages.map((m) => m.id).toSet();
      final newMessages = fresh.where((m) => !existingIds.contains(m.id));
      if (newMessages.isEmpty) return;
      _messages.insertAll(0, newMessages);
      _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
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

  Future<void> send(String text) async {
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
    notifyListeners();
    try {
      final token = _token;
      if (token == null) throw const ApiException('Not signed in');
      final result = await api.sendRaceMessage(
        identityToken: token,
        raceId: raceId,
        body: trimmed,
      );
      final msgJson = result['message'] as Map<String, dynamic>?;
      if (msgJson != null) {
        final created = RaceChatMessage.fromJson(msgJson);
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx != -1) _messages[idx] = created;
      } else {
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(pending: false);
        }
      }
    } catch (e) {
      final idx = _messages.indexWhere((m) => m.id == tempId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(pending: false, failed: true);
      }
      _lastError = e;
    } finally {
      notifyListeners();
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final token = _token;
    if (token == null) return;
    try {
      await api.deleteRaceMessage(
        identityToken: token,
        raceId: raceId,
        messageId: messageId,
      );
      _messages.removeWhere((m) => m.id == messageId);
      notifyListeners();
    } catch (e) {
      _lastError = e;
      notifyListeners();
    }
  }

  Future<void> setMuted(bool muted) async {
    final token = _token;
    if (token == null) return;
    final previous = _muted;
    _muted = muted;
    notifyListeners();
    try {
      await api.setRaceChatMute(
        identityToken: token,
        raceId: raceId,
        muted: muted,
      );
    } catch (e) {
      _muted = previous;
      _lastError = e;
      notifyListeners();
    }
  }

  void setMutedFromServer(bool muted) {
    if (_muted == muted) return;
    _muted = muted;
    notifyListeners();
  }

  Future<void> markRead() async {
    final token = _token;
    if (token == null) return;
    try {
      await api.markRaceChatRead(identityToken: token, raceId: raceId);
    } catch (_) {}
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
