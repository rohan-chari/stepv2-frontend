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
  bool _timelineMode = false;
  final List<RaceChatMessage> _timelineMessages = <RaceChatMessage>[];
  String? _timelineCursor;
  bool _timelineLoading = false;
  Object? _timelineError;

  bool get chatHasUnread => _chatHasUnread || (_chat?.hasUnread ?? false);
  bool get legacyMode => _legacy;
  bool get timelineMode => _timelineMode;
  List<RaceChatMessage> get timelineMessages =>
      List.unmodifiable(_timelineMessages);
  bool get timelineLoading => _timelineLoading;
  Object? get timelineError => _timelineError;
  bool get timelineHasMore => _timelineCursor != null;

  String? get _token => authService.authToken;

  Future<void> initialize({required bool live, bool muted = false}) async {
    _live = live;
    _eligible = true;
    _initialPending = true;
    if (await _initializeTimeline(muted: muted)) {
      if (_disposed || !_eligible) return;
      if (live) _startTimer();
      return;
    }
    feed.beginCombinedLoad();
    await _refresh(includeUser: false, initial: true, muted: muted);
    if (!_legacy && !_disposed && _eligible) {
      await feed.refreshPrivateTop();
    }
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
    if (_timelineMode) {
      unawaited(chat.markRead());
      notifyListeners();
      return;
    }
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
    if (_timelineMode) {
      await _refreshTimeline();
      return;
    }
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

  /// Explicit recipient-private refresh used only at the lifecycle boundaries
  /// defined by the active-impact contract. The periodic shared timer never
  /// calls this method.
  Future<void> refreshPrivateActivity() => feed.refreshPrivateTop();

  /// Removes active synced snapshots before loading terminal authoritative
  /// impact rows from the same private endpoint.
  Future<void> replacePrivateActivity() => feed.replacePrivateImpactStream();

  Future<bool> _initializeTimeline({required bool muted}) async {
    final token = _token;
    if (token == null || token.isEmpty) return false;
    try {
      final payload = await api.fetchRaceTimeline(
        identityToken: token,
        raceId: raceId,
      );
      if (_disposed || !_eligible) return false;
      if (payload['timelineVersion'] != 1) return false;
      _timelineMode = true;
      _ensureChat(muted);
      _applyTimelinePage(payload, replace: true);
      _initialPending = false;
      _acknowledgeInitialRead(token);
      notifyListeners();
      return true;
    } catch (_) {
      // A network/404/older-server failure keeps the established two-tab path.
      return false;
    }
  }

  void _applyTimelinePage(
    Map<String, dynamic> payload, {
    required bool replace,
  }) {
    final rawMessages = payload['messages'];
    if (rawMessages is! List) {
      _timelineError = const ApiException(
        'Couldn’t load the timeline. Please try again.',
      );
      if (replace) _timelineMessages.clear();
      _timelineCursor = null;
      return;
    }
    final parsed = rawMessages
        .map(RaceChatMessage.tryFromJson)
        .whereType<RaceChatMessage>()
        .where((message) => message.kind == 'USER' || message.kind == 'SYSTEM')
        .toList();
    if (replace) {
      _timelineMessages
        ..clear()
        ..addAll(parsed);
    } else {
      final existing = _timelineMessages.map((message) => message.id).toSet();
      _timelineMessages.addAll(
        parsed.where((message) => existing.add(message.id)),
      );
    }
    _timelineMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final cursor = payload['nextCursor'];
    _timelineCursor = cursor is String && cursor.isNotEmpty ? cursor : null;
    _timelineError = null;
  }

  Future<void> _refreshTimeline() async {
    if (_timelineLoading || _disposed || !_eligible) return;
    final token = _token;
    if (token == null || token.isEmpty) return;
    _timelineLoading = true;
    notifyListeners();
    try {
      final payload = await api.fetchRaceTimeline(
        identityToken: token,
        raceId: raceId,
      );
      if (_disposed || !_eligible) return;
      if (payload['timelineVersion'] != 1) return;
      final older = List<RaceChatMessage>.from(_timelineMessages);
      _applyTimelinePage(payload, replace: true);
      final ids = _timelineMessages.map((message) => message.id).toSet();
      _timelineMessages.addAll(older.where((message) => ids.add(message.id)));
      _timelineMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (error) {
      if (_timelineMessages.isEmpty) _timelineError = error;
    } finally {
      _timelineLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadOlderTimeline() async {
    final cursor = _timelineCursor;
    final token = _token;
    if (!_timelineMode ||
        _timelineLoading ||
        cursor == null ||
        token == null ||
        token.isEmpty) {
      return;
    }
    _timelineLoading = true;
    notifyListeners();
    try {
      final payload = await api.fetchRaceTimeline(
        identityToken: token,
        raceId: raceId,
        cursor: cursor,
      );
      if (_disposed || !_eligible || payload['timelineVersion'] != 1) return;
      _applyTimelinePage(payload, replace: false);
    } catch (error) {
      _timelineError = error;
    } finally {
      _timelineLoading = false;
      if (!_disposed) notifyListeners();
    }
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
      // A 304 is a successful authorized poll whose exact rendered snapshot
      // is already installed. Preserve Activity, Chat, watermark and unread
      // state byte-for-byte.
      if (result.notModified) return;
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
    api.resetRaceMessageConditionalState(raceId: raceId);
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
    if (_timelineMode) {
      await _refreshTimeline();
      if (_live) _startTimer();
    } else if (_legacy) {
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
