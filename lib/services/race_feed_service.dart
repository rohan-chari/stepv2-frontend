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
  final String? sourceFeedEventId;
  final String? impactScope;
  final int? deltaSteps;
  final String? attackerDisplayName;
  final String? redirectAttackerUserId;
  final String? redirectDecoyOwnerUserId;
  final String? redirectTargetUserId;
  final DateTime createdAt;

  const RaceFeedEvent({
    required this.id,
    required this.eventType,
    required this.description,
    required this.createdAt,
    this.powerupType,
    this.actorUserId,
    this.targetUserId,
    this.sourceFeedEventId,
    this.impactScope,
    this.deltaSteps,
    this.attackerDisplayName,
    this.redirectAttackerUserId,
    this.redirectDecoyOwnerUserId,
    this.redirectTargetUserId,
  });

  static RaceFeedEvent? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final createdRaw = raw['createdAt'];
    final sourceFeedEventId = raw['sourceFeedEventId'];
    final impactScope = raw['impactScope'];
    final rawDelta = raw['deltaSteps'];
    final rawAttacker = raw['attackerDisplayName'];
    final metadata = raw['metadata'];
    String? metadataUserId(String key) {
      if (metadata is! Map) return null;
      final value = metadata[key];
      if (value is! String || value.trim().isEmpty) return null;
      return value;
    }

    final deltaSteps =
        rawDelta is num &&
            rawDelta.isFinite &&
            rawDelta == rawDelta.roundToDouble()
        ? rawDelta.toInt()
        : null;
    final attacker = rawAttacker is String ? rawAttacker.trim() : '';
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
      sourceFeedEventId:
          sourceFeedEventId is String && sourceFeedEventId.isNotEmpty
          ? sourceFeedEventId
          : null,
      impactScope: impactScope is String && impactScope.isNotEmpty
          ? impactScope
          : null,
      deltaSteps: deltaSteps,
      attackerDisplayName: attacker.isNotEmpty && attacker.runes.length <= 30
          ? attacker
          : null,
      redirectAttackerUserId: metadataUserId('attackerUserId'),
      redirectDecoyOwnerUserId: metadataUserId('decoyOwnerUserId'),
      redirectTargetUserId: metadataUserId('redirectedUserId'),
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

/// Per-race Activity state. Shared and recipient-private rows have independent
/// cursors, then merge into one stable newest-first projection.
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
  final Set<String> _privateEventIds = {};
  final Set<String> _suppressedSourceFeedEventIds = {};
  final Map<String, RaceFeedEvent> _suppressedSharedEvents = {};
  String? _sharedCursor;
  String? _privateCursor;
  bool _sharedHasMore = true;
  bool _privateHasMore = false;
  bool _loading = false;
  bool _disposed = false;
  int _privateGeneration = 0;
  Object? _lastError;
  Timer? _pollTimer;
  Future<void>? _privateRefreshInFlight;

  List<RaceFeedEvent> get events =>
      List.unmodifiable(_causalActivityPresentation(_events));
  bool get isLoading => _loading;
  bool get hasMore => _sharedHasMore || _privateHasMore;
  Object? get lastError => _lastError;
  bool containsEvent(String id) => _events.any((event) => event.id == id);

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
      await refreshPrivateTop();
    } catch (e) {
      _lastError = e;
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  Future<void> loadMore() async {
    if (_disposed || _loading || !hasMore) return;
    _loading = true;
    _safeNotify();
    Object? pageError;
    try {
      final token = _token;
      if (token == null) throw const ApiException('Not signed in');
      final sharedCursor = _sharedHasMore ? _sharedCursor : null;
      final privateCursor = _privateHasMore ? _privateCursor : null;
      final privateGeneration = _privateGeneration;

      if (sharedCursor != null) {
        try {
          final result = await api.fetchRaceMessages(
            identityToken: token,
            raceId: raceId,
            cursor: sharedCursor,
            limit: 50,
            kind: 'SYSTEM',
          );
          if (!_disposed) _applySharedPage(result);
        } catch (error) {
          pageError ??= error;
        }
      } else {
        _sharedHasMore = false;
      }

      if (privateCursor != null) {
        try {
          final page = await api.fetchPrivateRaceImpactFeed(
            identityToken: token,
            raceId: raceId,
            cursor: privateCursor,
          );
          if (!_disposed && privateGeneration == _privateGeneration) {
            _applyPrivatePage(page, advanceCursor: true);
          }
        } catch (error) {
          pageError ??= error;
        }
      } else {
        _privateHasMore = false;
      }
      _lastError = pageError;
    } catch (e) {
      _lastError = e;
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  /// Polls only shared Activity. Private impacts refresh at explicit lifecycle
  /// boundaries so every mounted viewer does not query PostgreSQL every 5s.
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

  /// Fetches the newest private page. Popup and lifecycle refreshes coalesce;
  /// an old/disabled endpoint never hides shared Activity.
  Future<void> refreshPrivateTop() {
    if (_disposed) return Future.value();
    final existing = _privateRefreshInFlight;
    if (existing != null) return existing;
    final generation = _privateGeneration;
    final operation = _refreshPrivateTopImpl(generation);
    _privateRefreshInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_privateRefreshInFlight, operation)) {
        _privateRefreshInFlight = null;
      }
    });
  }

  Future<void> _refreshPrivateTopImpl(int generation) async {
    try {
      final token = _token;
      if (token == null) return;
      final page = await api.fetchPrivateRaceImpactFeed(
        identityToken: token,
        raceId: raceId,
      );
      if (_disposed || generation != _privateGeneration) return;
      _applyPrivatePage(
        page,
        advanceCursor: !_privateHasMore || _privateCursor == null,
      );
      _safeNotify();
    } catch (_) {
      // Optional private Activity quietly degrades against older backends.
    }
  }

  /// Clears active snapshot rows before installing terminal authoritative rows.
  /// The generation guard prevents a stale active response landing afterward.
  Future<void> replacePrivateImpactStream() async {
    if (_disposed) return;
    _privateGeneration += 1;
    _privateRefreshInFlight = null;
    _events.removeWhere((event) => _privateEventIds.contains(event.id));
    final restoredSharedEvents = _suppressedSharedEvents.values.toList(
      growable: false,
    );
    _privateEventIds.clear();
    _suppressedSourceFeedEventIds.clear();
    _suppressedSharedEvents.clear();
    _mergeEvents(restoredSharedEvents);
    _privateCursor = null;
    _privateHasMore = false;
    _safeNotify();
    await refreshPrivateTop();
  }

  void applyInitialStream(Map<String, dynamic> stream) {
    if (_disposed) return;
    final list = stream['messages'];
    _events.removeWhere((event) => !_privateEventIds.contains(event.id));
    _mergeEvents(
      list is List
          ? _withoutSuppressedSharedEvents(
              list.map(RaceFeedEvent.tryFromJson).whereType<RaceFeedEvent>(),
            )
          : const <RaceFeedEvent>[],
    );
    _sharedCursor = _readCursor(stream['nextCursor']);
    _sharedHasMore = _sharedCursor != null;
    _loading = false;
    _lastError = null;
    _safeNotify();
  }

  void applyTopStream(Map<String, dynamic> stream) {
    if (_disposed) return;
    final list = stream['messages'];
    final beforeIds = _events.map((event) => event.id).toSet();
    final hadMore = _sharedHasMore;
    _mergeEvents(
      list is List
          ? _withoutSuppressedSharedEvents(
              list.map(RaceFeedEvent.tryFromJson).whereType<RaceFeedEvent>(),
            )
          : const <RaceFeedEvent>[],
    );
    if (!_sharedHasMore || _sharedCursor == null) {
      _sharedCursor = _readCursor(stream['nextCursor']);
      _sharedHasMore = _sharedCursor != null;
    }
    if (_events.length != beforeIds.length ||
        _events.any((event) => !beforeIds.contains(event.id)) ||
        hadMore != _sharedHasMore) {
      _safeNotify();
    }
  }

  void applyCombinedError(Object error) {
    if (_disposed) return;
    _loading = false;
    _lastError = error;
    _safeNotify();
  }

  void _applySharedPage(Map<String, dynamic> page) {
    final raw = page['messages'];
    if (raw is List) {
      _mergeEvents(
        _withoutSuppressedSharedEvents(
          raw.map(RaceFeedEvent.tryFromJson).whereType<RaceFeedEvent>(),
        ),
      );
    }
    _sharedCursor = _readCursor(page['nextCursor']);
    _sharedHasMore = _sharedCursor != null;
  }

  void _applyPrivatePage(
    PrivateRaceImpactFeedPage page, {
    required bool advanceCursor,
  }) {
    final parsed = page.events
        .map(RaceFeedEvent.tryFromJson)
        .whereType<RaceFeedEvent>()
        .where(
          (event) =>
              event.id.startsWith('impact:') &&
              event.description.trim().isNotEmpty,
        )
        .toList(growable: false);
    for (final event in parsed) {
      _privateEventIds.add(event.id);
      final sourceId = event.sourceFeedEventId;
      if (sourceId != null && event.description.trim().isNotEmpty) {
        _suppressedSourceFeedEventIds.add(sourceId);
      }
    }
    for (final event in _events) {
      if (_suppressedSourceFeedEventIds.contains(event.id)) {
        _suppressedSharedEvents[event.id] = event;
      }
    }
    _events.removeWhere(
      (event) => _suppressedSourceFeedEventIds.contains(event.id),
    );
    _mergeEvents(parsed);
    if (advanceCursor) {
      _privateCursor = page.nextCursor;
      _privateHasMore = _privateCursor != null;
    }
  }

  Iterable<RaceFeedEvent> _withoutSuppressedSharedEvents(
    Iterable<RaceFeedEvent> events,
  ) sync* {
    for (final event in events) {
      if (_suppressedSourceFeedEventIds.contains(event.id)) {
        _suppressedSharedEvents[event.id] = event;
      } else {
        yield event;
      }
    }
  }

  void _mergeEvents(Iterable<RaceFeedEvent> incoming) {
    final ids = _events.map((event) => event.id).toSet();
    for (final event in incoming) {
      if (ids.add(event.id)) _events.add(event);
    }
    _events.sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
  }

  /// Activity is newest-first, but a Decoy redirect is the cause of its
  /// separately persisted terminal Hitchhike block. Swap only those two
  /// matched rows for causal reading; storage remains newest-first so cursors,
  /// polling, private-feed suppression, and pagination retain their contract.
  static List<RaceFeedEvent> _causalActivityPresentation(
    List<RaceFeedEvent> newestFirst,
  ) {
    final presented = List<RaceFeedEvent>.of(newestFirst);
    final claimedTerminalIds = <String>{};
    for (final redirect in newestFirst) {
      if (redirect.eventType != 'POWERUP_REDIRECTED' ||
          redirect.powerupType != 'HITCHHIKE') {
        continue;
      }
      final attackerId = redirect.redirectAttackerUserId;
      final decoyOwnerId = redirect.redirectDecoyOwnerUserId;
      final redirectedId = redirect.redirectTargetUserId;
      if (attackerId == null ||
          decoyOwnerId == null ||
          redirectedId == null ||
          redirect.actorUserId != decoyOwnerId ||
          redirect.targetUserId != redirectedId) {
        continue;
      }
      final terminalCreatedAt = redirect.createdAt.add(
        const Duration(milliseconds: 1),
      );

      RaceFeedEvent? terminal;
      for (final candidate in newestFirst) {
        if (claimedTerminalIds.contains(candidate.id) ||
            candidate.eventType != 'POWERUP_BLOCKED' ||
            candidate.powerupType != 'HITCHHIKE' ||
            candidate.actorUserId != redirectedId ||
            candidate.targetUserId != attackerId ||
            !candidate.createdAt.isAtSameMomentAs(terminalCreatedAt)) {
          continue;
        }
        if (terminal == null || candidate.id.compareTo(terminal.id) < 0) {
          terminal = candidate;
        }
      }
      if (terminal == null) continue;
      claimedTerminalIds.add(terminal.id);
      final redirectIndex = presented.indexWhere(
        (event) => event.id == redirect.id,
      );
      final terminalIndex = presented.indexWhere(
        (event) => event.id == terminal!.id,
      );
      if (terminalIndex < 0 ||
          redirectIndex < 0 ||
          terminalIndex >= redirectIndex) {
        continue;
      }
      final displaced = presented[terminalIndex];
      presented[terminalIndex] = presented[redirectIndex];
      presented[redirectIndex] = displaced;
    }
    return presented;
  }

  String? _readCursor(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;

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
