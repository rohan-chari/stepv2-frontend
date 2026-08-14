import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'backend_api_service.dart';
import 'race_chat_service.dart';
import 'race_feed_service.dart';

/// Owns the one foreground message timer for a mounted race screen. Capable
/// backends return Activity plus a body-free Chat watermark until Chat is
/// opened; a definite endpoint 404 restores the two legacy services.
class RaceStreamCoordinator extends ChangeNotifier {
  RaceStreamCoordinator({
    required this.authService,
    required this.raceId,
    required this.api,
    this.pollInterval = const Duration(seconds: 5),
  }) : feed = RaceFeedService(
         authService: authService,
         raceId: raceId,
         api: api,
       );

  final AuthService authService;
  final String raceId;
  final BackendApiService api;
  final Duration pollInterval;
  final RaceFeedService feed;

  RaceChatService? _chat;
  RaceChatService? get chat => _chat;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _refreshQueued = false;
  bool _disposed = false;
  bool _eligible = false;
  int _visibilityGeneration = 0;
  bool _live = false;
  bool _legacy = false;
  bool _legacyChatInitialized = false;
  bool _chatRequested = false;
  bool _chatVisible = false;
  bool _watermarkInitialized = false;
  bool _initialPending = false;
  bool _initialReadAcknowledged = false;
  bool _chatHasUnread = false;
  final Set<String> _seenWatermarkIds = {};

  bool get chatHasUnread => _chatHasUnread || (_chat?.hasUnread ?? false);
  bool get legacyMode => _legacy;

  String? get _token => authService.authToken;

  Future<void> initialize({required bool live, bool muted = false}) async {
    _live = live;
    _eligible = true;
    _initialPending = true;
    feed.beginCombinedLoad();
    await _refresh(includeUser: false, initial: true, muted: muted);
    if (_refreshQueued && _eligible && !_legacy && !_disposed) {
      await refreshNow();
    }
    if (_disposed || !_eligible) return;
    if (live && !_legacy) _startTimer();
  }

  Future<void> openChat({bool muted = false}) async {
    _chatRequested = true;
    _chatVisible = true;
    _chatHasUnread = false;
    final chat = _ensureChat(muted);
    chat.clearUnread();
    final token = _token;
    if (_initialPending && token != null && token.isNotEmpty) {
      _acknowledgeInitialRead(token);
    } else {
      unawaited(chat.markRead());
    }
    if (_legacy) {
      if (!_legacyChatInitialized && !chat.isLoading) {
        await chat.loadInitial();
        _legacyChatInitialized = chat.lastError == null;
      }
      notifyListeners();
      return;
    }
    chat.beginCombinedLoad();
    await refreshNow();
  }

  Future<void> refreshNow() async {
    if (!_eligible || _disposed) return;
    final existing = _inFlight;
    if (existing != null) {
      _refreshQueued = true;
      await existing;
      if (!_eligible || _legacy || _disposed) return;
      final successor = _inFlight;
      if (successor != null && !identical(successor, existing)) {
        await successor;
      } else if (_refreshQueued) {
        await refreshNow();
      }
      return;
    }
    do {
      _refreshQueued = false;
      await _refresh(includeUser: _chatRequested);
    } while (_refreshQueued && _eligible && !_legacy && !_disposed);
  }

  Future<void> _refresh({
    required bool includeUser,
    bool initial = false,
    bool muted = false,
  }) async {
    if (_disposed || !_eligible) return;
    final effectiveInitial = initial || _initialPending;
    final generation = _visibilityGeneration;
    final token = _token;
    if (token == null || token.isEmpty) return;
    final operation = _performRefresh(
      token,
      includeUser: includeUser,
      initial: effectiveInitial,
      muted: muted,
      generation: generation,
    );
    _inFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_inFlight, operation)) _inFlight = null;
    }
  }

  Future<void> _performRefresh(
    String token, {
    required bool includeUser,
    required bool initial,
    required bool muted,
    required int generation,
  }) async {
    try {
      final result = await api.fetchRaceMessageStreams(
        identityToken: token,
        raceId: raceId,
        includeUser: includeUser,
      );
      if (_disposed || !_eligible || generation != _visibilityGeneration) {
        return;
      }
      if (!result.supported) {
        await _enableLegacy(token: token, muted: muted, generation: generation);
        return;
      }
      if (initial) _initialPending = false;
      if (result.malformed) {
        if (initial) {
          feed.applyCombinedError(
            const ApiException('Couldn’t load activity. Please try again.'),
          );
          _initializeEmptyWatermark(token);
        }
        return;
      }
      final system = result.systemStream;
      if (result.systemResolved && system != null) {
        if (initial || feed.events.isEmpty) {
          feed.applyInitialStream(system);
        } else {
          feed.applyTopStream(system);
        }
      } else if (initial) {
        feed.applyCombinedError(
          const ApiException('Couldn’t load activity. Please try again.'),
        );
      }
      _applyWatermark(result.chatWatermark, initial: initial);
      if (initial && !_watermarkInitialized) {
        _initializeEmptyWatermark(token);
      }
      // An Activity-only response that started before the tab switch may still
      // update Activity/watermark, but can never clear or replace Chat rows.
      if (includeUser && _chatRequested) {
        final user = result.userStream;
        final chat = _ensureChat(muted);
        if (result.userResolved && user != null) {
          if (chat.messages.isEmpty) {
            chat.applyInitialStream(user);
          } else {
            chat.applyTopStream(user);
          }
          if (_chatVisible) chat.clearUnread();
        } else {
          chat.applyCombinedError(
            const ApiException('Couldn’t load chat. Please try again.'),
          );
        }
      }
      if (initial) _acknowledgeInitialRead(token);
      notifyListeners();
    } catch (error) {
      if (_disposed || !_eligible || generation != _visibilityGeneration) {
        return;
      }
      if (initial) {
        _initialPending = false;
        feed.applyCombinedError(error);
        _initializeEmptyWatermark(token);
      }
      if (includeUser && _chatRequested) {
        _ensureChat(muted).applyCombinedError(error);
      }
    }
  }

  void _applyWatermark(
    Map<String, dynamic>? watermark, {
    required bool initial,
  }) {
    final rawIds = watermark?['recentIds'];
    if (rawIds is! List) return;
    final ids = rawIds.whereType<String>().where((id) => id.isNotEmpty).toSet();
    if (!_watermarkInitialized || initial) {
      _watermarkInitialized = true;
      _seenWatermarkIds.addAll(ids);
      return;
    }
    if (ids.any((id) => !_seenWatermarkIds.contains(id)) && !_chatRequested) {
      _chatHasUnread = true;
    }
    _seenWatermarkIds.addAll(ids);
  }

  void _initializeEmptyWatermark(String token) {
    if (!_watermarkInitialized) _watermarkInitialized = true;
    _acknowledgeInitialRead(token);
  }

  void _acknowledgeInitialRead(String token) {
    if (_initialReadAcknowledged) return;
    _initialReadAcknowledged = true;
    unawaited(_acknowledgeRead(token));
  }

  Future<void> _acknowledgeRead(String token) async {
    try {
      await api.markRaceChatRead(identityToken: token, raceId: raceId);
    } catch (_) {}
  }

  RaceChatService _ensureChat(bool muted) {
    final existing = _chat;
    if (existing != null) return existing;
    final chat = RaceChatService(
      authService: authService,
      raceId: raceId,
      api: api,
    );
    chat.setMutedFromServer(muted);
    chat.addListener(_relay);
    _chat = chat;
    return chat;
  }

  Future<void> _enableLegacy({
    required String token,
    required bool muted,
    required int generation,
  }) async {
    if (_legacy) return;
    _legacy = true;
    _timer?.cancel();
    final chat = _ensureChat(muted);
    feed.endCombinedLoad();
    chat.endCombinedLoad();
    await Future.wait([feed.loadInitial(), chat.loadInitial()]);
    _legacyChatInitialized = chat.lastError == null;
    if (_disposed || !_eligible || generation != _visibilityGeneration) {
      return;
    }
    _acknowledgeInitialRead(token);
    _initialPending = false;
    if (_live) {
      feed.startPolling(interval: pollInterval);
      chat.startPolling(interval: pollInterval);
    }
    notifyListeners();
  }

  void _relay() {
    if (!_disposed) notifyListeners();
  }

  void _startTimer() {
    if (!_eligible || _disposed) return;
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => refreshNow());
  }

  void pause() {
    _eligible = false;
    _chatVisible = false;
    _visibilityGeneration += 1;
    _timer?.cancel();
    _timer = null;
    feed.stopPolling();
    _chat?.stopPolling();
  }

  Future<void> resume({bool chatVisible = false}) async {
    if (_disposed) return;
    _eligible = true;
    _chatVisible = chatVisible;
    if (chatVisible) _chatHasUnread = false;
    _visibilityGeneration += 1;
    if (_legacy) {
      final chat = _chat;
      await Future.wait([
        feed.refreshTop(),
        if (chat != null) chat.refreshTop(),
      ]);
      if (_disposed || !_eligible) return;
      final token = _token;
      if (_initialPending && token != null && token.isNotEmpty) {
        _acknowledgeInitialRead(token);
        _initialPending = false;
        if (_disposed || !_eligible) return;
      }
      if (_live) {
        feed.startPolling(interval: pollInterval);
        chat?.startPolling(interval: pollInterval);
      }
    } else {
      await refreshNow();
      if (_live) {
        _startTimer();
      }
    }
    if (chatVisible) _chat?.markChatViewed();
  }

  void setChatVisible(bool visible) {
    _chatVisible = visible;
    if (visible) {
      _chatHasUnread = false;
      _chat?.markChatViewed();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    pause();
    feed.dispose();
    _chat?.removeListener(_relay);
    _chat?.dispose();
    super.dispose();
  }
}
