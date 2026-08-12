import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_api_service.dart';

class PendingRaceResultsAcknowledgement {
  const PendingRaceResultsAcknowledgement({
    required this.version,
    required this.userId,
    required this.backendBaseUrl,
    required this.raceIds,
    required this.racePayoutDoubleCapability,
    required this.queuedAt,
  });

  final int version;
  final String userId;
  final String backendBaseUrl;
  final List<String> raceIds;
  final bool racePayoutDoubleCapability;
  final DateTime queuedAt;

  String get partitionKey =>
      '$userId\u0000$backendBaseUrl\u0000$racePayoutDoubleCapability';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'userId': userId,
    'backendBaseUrl': backendBaseUrl,
    'raceIds': raceIds,
    'racePayoutDoubleCapability': racePayoutDoubleCapability,
    'queuedAt': queuedAt.toUtc().toIso8601String(),
  };

  static PendingRaceResultsAcknowledgement? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final userId = raw['userId'];
    final backend = raw['backendBaseUrl'];
    final rawIds = raw['raceIds'];
    if (userId is! String ||
        userId.isEmpty ||
        backend is! String ||
        backend.isEmpty ||
        rawIds is! List) {
      return null;
    }
    final ids = <String>{};
    for (final id in rawIds) {
      if (id is! String || id.isEmpty) return null;
      ids.add(id);
    }
    if (ids.isEmpty) return null;
    final versionRaw = raw['version'];
    final version = versionRaw is int && versionRaw > 0 ? versionRaw : 1;
    final capability = raw['racePayoutDoubleCapability'] is bool
        ? raw['racePayoutDoubleCapability'] as bool
        : false;
    final queuedAtRaw = raw['queuedAt'];
    final queuedAt = queuedAtRaw is String
        ? DateTime.tryParse(queuedAtRaw)?.toUtc()
        : null;
    return PendingRaceResultsAcknowledgement(
      version: version,
      userId: userId,
      backendBaseUrl: backend,
      raceIds: (ids.toList()..sort()),
      racePayoutDoubleCapability: capability,
      queuedAt: queuedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

/// Durable, capability-partitioned transport for results-seen acknowledgement.
///
/// Records for other users/backends are intentionally retained. A current
/// session may send and clear only its exact authenticated context.
class RaceResultsAcknowledgementQueue {
  RaceResultsAcknowledgementQueue({
    required BackendApiService backendApiService,
    Future<SharedPreferences> Function()? preferencesProvider,
    Future<bool> Function(String value)? persistenceWriter,
  }) : _backendApiService = backendApiService,
       _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance,
       _persistenceWriter = persistenceWriter;

  static const String preferencesKey =
      'pending_race_results_acknowledgements_v2';
  static const int _recordVersion = 2;
  static const int _chunkSize = 50;

  final BackendApiService _backendApiService;
  final Future<SharedPreferences> Function() _preferencesProvider;
  final Future<bool> Function(String value)? _persistenceWriter;
  final Map<String, Set<String>> _sessionSuppressed = {};
  List<PendingRaceResultsAcknowledgement> _records = const [];
  bool _hydrated = false;
  Future<void>? _hydrateInFlight;
  Future<void> _mutationTail = Future<void>.value();

  Future<void> hydrate() => _hydrateInFlight ??= _hydrate().whenComplete(() {
    _hydrateInFlight = null;
  });

  Future<void> _hydrate() async {
    if (_hydrated) return;
    try {
      final prefs = await _preferencesProvider();
      final raw = prefs.getString(preferencesKey);
      final decoded = raw == null ? const <dynamic>[] : jsonDecode(raw);
      if (decoded is List) {
        _records = _mergeRecords(
          decoded
              .map(PendingRaceResultsAcknowledgement.tryParse)
              .whereType<PendingRaceResultsAcknowledgement>(),
        );
      }
    } catch (error) {
      debugPrint('Race results acknowledgement hydration failed: $error');
      _records = const [];
    } finally {
      _hydrated = true;
    }
  }

  /// Queues before route pop. Returns false only when durable persistence was
  /// unavailable; session-memory suppression still applies in that case.
  Future<bool> enqueue({
    required String userId,
    required String backendBaseUrl,
    required List<String> raceIds,
    required bool racePayoutDoubleCapability,
    String? identityToken,
  }) => _serializeMutation(
    () => _enqueue(
      userId: userId,
      backendBaseUrl: backendBaseUrl,
      raceIds: raceIds,
      racePayoutDoubleCapability: racePayoutDoubleCapability,
      identityToken: identityToken,
    ),
  );

  Future<bool> _enqueue({
    required String userId,
    required String backendBaseUrl,
    required List<String> raceIds,
    required bool racePayoutDoubleCapability,
    required String? identityToken,
  }) async {
    await hydrate();
    final ids = raceIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return true;
    final contextKey = '$userId\u0000$backendBaseUrl';
    _sessionSuppressed.putIfAbsent(contextKey, () => <String>{}).addAll(ids);

    final partitionKey =
        '$userId\u0000$backendBaseUrl\u0000$racePayoutDoubleCapability';
    final existing = _records
        .where((record) {
          return record.partitionKey == partitionKey;
        })
        .toList(growable: false);
    final merged = <String>{...ids};
    for (final record in existing) {
      merged.addAll(record.raceIds);
    }
    final next =
        _records
            .where((record) => record.partitionKey != partitionKey)
            .toList(growable: true)
          ..add(
            PendingRaceResultsAcknowledgement(
              version: _recordVersion,
              userId: userId,
              backendBaseUrl: backendBaseUrl,
              raceIds: (merged.toList()..sort()),
              racePayoutDoubleCapability: racePayoutDoubleCapability,
              queuedAt: DateTime.now().toUtc(),
            ),
          );
    try {
      await _persist(next);
      _records = List.unmodifiable(next);
      return true;
    } catch (error) {
      debugPrint(
        'Race results acknowledgement persistence failed; results stay '
        'suppressed for this process only: $error',
      );
      final token = identityToken;
      if (token != null && token.isNotEmpty) {
        unawaited(
          _backendApiService
              .markRaceResultsSeenStrict(
                identityToken: token,
                raceIds: (ids.toList()..sort()),
                racePayoutDoubleCapability: racePayoutDoubleCapability,
              )
              .catchError((Object _) {}),
        );
      }
      return false;
    }
  }

  Set<String> suppressedRaceIds({
    required String userId,
    required String backendBaseUrl,
  }) {
    final result = <String>{
      ...?_sessionSuppressed['$userId\u0000$backendBaseUrl'],
    };
    for (final record in _records) {
      if (record.userId == userId && record.backendBaseUrl == backendBaseUrl) {
        result.addAll(record.raceIds);
      }
    }
    return result;
  }

  Future<void> replayMatching({
    required String identityToken,
    required String userId,
    required String backendBaseUrl,
    bool Function()? isAuthenticatedContextCurrent,
  }) => _serializeMutation(() async {
    if (_contextIsCurrent(isAuthenticatedContextCurrent)) {
      await hydrate();
      await _replayMatching(
        identityToken: identityToken,
        userId: userId,
        backendBaseUrl: backendBaseUrl,
        isAuthenticatedContextCurrent: isAuthenticatedContextCurrent,
      );
    }
  });

  Future<void> _replayMatching({
    required String identityToken,
    required String userId,
    required String backendBaseUrl,
    required bool Function()? isAuthenticatedContextCurrent,
  }) async {
    if (!_contextIsCurrent(isAuthenticatedContextCurrent)) return;
    final matching = _records
        .where((record) {
          return record.userId == userId &&
              record.backendBaseUrl == backendBaseUrl;
        })
        .toList(growable: false);

    for (final record in matching) {
      final sorted = [...record.raceIds]..sort();
      for (var start = 0; start < sorted.length; start += _chunkSize) {
        if (!_contextIsCurrent(isAuthenticatedContextCurrent)) return;
        final end = (start + _chunkSize).clamp(0, sorted.length);
        final chunk = sorted.sublist(start, end);
        try {
          await _backendApiService.markRaceResultsSeenStrict(
            identityToken: identityToken,
            raceIds: chunk,
            racePayoutDoubleCapability: record.racePayoutDoubleCapability,
          );
        } catch (_) {
          // A later startup/resume/refresh retries the unchanged partition.
          break;
        }

        // Auth may have changed while the strict request was in flight. The
        // old-token response must never clear a partition under a new account
        // context; leave it durable for a later matching session instead.
        if (!_contextIsCurrent(isAuthenticatedContextCurrent)) return;

        final acknowledged = chunk.toSet();
        final next = <PendingRaceResultsAcknowledgement>[];
        for (final current in _records) {
          if (current.partitionKey != record.partitionKey) {
            next.add(current);
            continue;
          }
          final remaining = current.raceIds
              .where((id) => !acknowledged.contains(id))
              .toList(growable: false);
          if (remaining.isNotEmpty) {
            next.add(
              PendingRaceResultsAcknowledgement(
                version: current.version,
                userId: current.userId,
                backendBaseUrl: current.backendBaseUrl,
                raceIds: remaining,
                racePayoutDoubleCapability: current.racePayoutDoubleCapability,
                queuedAt: current.queuedAt,
              ),
            );
          }
        }
        try {
          await _persist(next);
          _records = List.unmodifiable(next);
        } catch (error) {
          debugPrint(
            'Race results acknowledgement clear failed; the acknowledged '
            'chunk may be sent idempotently again: $error',
          );
        }
      }
    }
  }

  bool _contextIsCurrent(bool Function()? validator) {
    if (validator == null) return true;
    try {
      return validator();
    } catch (_) {
      return false;
    }
  }

  Future<T> _serializeMutation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> _persist(List<PendingRaceResultsAcknowledgement> records) async {
    final value = jsonEncode(records.map((record) => record.toJson()).toList());
    final writer = _persistenceWriter;
    final bool saved;
    if (writer != null) {
      saved = await writer(value);
    } else {
      final prefs = await _preferencesProvider();
      saved = await prefs.setString(preferencesKey, value);
    }
    if (!saved) throw StateError('SharedPreferences rejected the write');
  }

  List<PendingRaceResultsAcknowledgement> _mergeRecords(
    Iterable<PendingRaceResultsAcknowledgement> records,
  ) {
    final byPartition = <String, PendingRaceResultsAcknowledgement>{};
    for (final record in records) {
      final prior = byPartition[record.partitionKey];
      if (prior == null) {
        byPartition[record.partitionKey] = record;
        continue;
      }
      final ids = <String>{...prior.raceIds, ...record.raceIds}.toList()
        ..sort();
      byPartition[record.partitionKey] = PendingRaceResultsAcknowledgement(
        version: prior.version > record.version
            ? prior.version
            : record.version,
        userId: record.userId,
        backendBaseUrl: record.backendBaseUrl,
        raceIds: ids,
        racePayoutDoubleCapability: record.racePayoutDoubleCapability,
        queuedAt: prior.queuedAt.isBefore(record.queuedAt)
            ? prior.queuedAt
            : record.queuedAt,
      );
    }
    return List.unmodifiable(byPartition.values);
  }

  @visibleForTesting
  Future<List<PendingRaceResultsAcknowledgement>> debugRecords() async {
    await hydrate();
    return List.unmodifiable(_records);
  }
}
