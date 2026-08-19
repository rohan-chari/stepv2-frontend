import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_api_service.dart';

/// Bounded, best-effort foreground-session telemetry for Admin Metrics v2.
///
/// This owner is instantiated only by the authenticated MainShell. It never
/// runs in Android/background step-sync isolates, and a request failure never
/// delays entry into the app.
class AdminMetricsTelemetryService {
  AdminMetricsTelemetryService({
    BackendApiService? backendApiService,
    bool? isIosForTesting,
    DateTime Function()? now,
  }) : _api = backendApiService ?? BackendApiService(),
       _isIos = isIosForTesting ?? Platform.isIOS,
       _now = now ?? DateTime.now;

  static const storageKey = 'admin_metrics_foreground_v1';
  static const maxQueuedSessions = 20;
  static const _newSessionAfter = Duration(seconds: 30);

  final BackendApiService _api;
  final bool _isIos;
  final DateTime Function() _now;
  final Random _random = Random.secure();

  bool _hasForegroundSession = false;
  String? _activeUserId;
  int _accountGeneration = 0;
  DateTime? _leftForegroundAt;
  Future<void>? _flushInFlight;

  Future<void> authenticatedForeground(
    String? authToken, {
    required String? userId,
  }) async {
    if (!_isIos) return;
    if (authToken == null ||
        authToken.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      // Signing out ends the authenticated foreground session. A later
      // account/session must earn its own single foreground fact, and an
      // offline fact must never be attributed with another account's token.
      _hasForegroundSession = false;
      _activeUserId = null;
      _accountGeneration++;
      await _clearQueue(_accountGeneration);
      return;
    }
    if (_activeUserId != userId) {
      _hasForegroundSession = false;
      _accountGeneration++;
      if (_activeUserId != null) await _clearQueue(_accountGeneration);
    }
    _activeUserId = userId;
    if (!_hasForegroundSession) {
      _hasForegroundSession = true;
      await _enqueue(
        _now().toUtc(),
        userId: userId,
        generation: _accountGeneration,
      );
    }
    await flush(authToken, userId: userId);
  }

  void didEnterBackground() {
    if (!_isIos || _leftForegroundAt != null) return;
    _leftForegroundAt = _now();
  }

  Future<void> didResume(String? authToken, {required String? userId}) async {
    if (!_isIos ||
        authToken == null ||
        authToken.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      return;
    }
    final leftAt = _leftForegroundAt;
    _leftForegroundAt = null;
    if (leftAt != null && _now().difference(leftAt) >= _newSessionAfter) {
      _hasForegroundSession = false;
    }
    await authenticatedForeground(authToken, userId: userId);
  }

  Future<void> _enqueue(
    DateTime occurredAt, {
    required String userId,
    required int generation,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // A process restart loses [_activeUserId], so the persisted owner is the
    // authority. Never append account B behind account A's offline head: that
    // would strand B forever or risk sending A with B's token.
    final queue = _readQueue(prefs)
      ..removeWhere((row) => row['ownerUserId'] != userId);
    var version = 'unknown';
    try {
      final value = (await PackageInfo.fromPlatform()).version;
      if (value.isNotEmpty) version = value;
    } catch (_) {}
    if (generation != _accountGeneration) return;
    queue.add({
      'sessionId': _newSessionId(),
      'occurredAt': occurredAt.toIso8601String(),
      'appVersion': version,
      'ownerUserId': userId,
    });
    if (queue.length > maxQueuedSessions) {
      queue.removeRange(0, queue.length - maxQueuedSessions);
    }
    await prefs.setString(storageKey, jsonEncode(queue));
  }

  Future<void> flush(String? authToken, {required String? userId}) async {
    if (!_isIos ||
        authToken == null ||
        authToken.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      return;
    }
    if (_activeUserId != null && _activeUserId != userId) return;
    final running = _flushInFlight;
    if (running != null) {
      await running;
      return flush(authToken, userId: userId);
    }

    final generation = _accountGeneration;
    late final Future<void> tracked;
    tracked = _flush(authToken, userId, generation).whenComplete(() {
      if (identical(_flushInFlight, tracked)) _flushInFlight = null;
    });
    _flushInFlight = tracked;
    await tracked;
  }

  Future<void> _flush(String authToken, String userId, int generation) async {
    final prefs = await SharedPreferences.getInstance();
    while (true) {
      if (generation != _accountGeneration) return;
      final queue = _readQueue(prefs);
      if (queue.isEmpty) return;
      final beforeOwnerFilter = queue.length;
      queue.removeWhere((row) => row['ownerUserId'] != userId);
      if (queue.length != beforeOwnerFilter) {
        await prefs.setString(storageKey, jsonEncode(queue));
      }
      if (queue.isEmpty) return;
      final event = queue.first;
      final sessionId = event['sessionId'];
      final occurredAt = DateTime.tryParse(event['occurredAt'] ?? '');
      final appVersion = event['appVersion'];
      final ownerUserId = event['ownerUserId'];
      if (sessionId == null ||
          sessionId.isEmpty ||
          occurredAt == null ||
          appVersion == null ||
          appVersion.isEmpty ||
          ownerUserId == null ||
          ownerUserId.isEmpty) {
        queue.removeAt(0);
        await prefs.setString(storageKey, jsonEncode(queue));
        continue;
      }
      try {
        await _api.sendAdminMetricsForeground(
          identityToken: authToken,
          sessionId: sessionId,
          occurredAt: occurredAt,
          appVersion: appVersion,
        );
        if (generation != _accountGeneration) return;
        final current = _readQueue(prefs);
        current.removeWhere((row) => row['sessionId'] == sessionId);
        await prefs.setString(storageKey, jsonEncode(current));
      } on ApiException catch (error) {
        if (generation != _accountGeneration) return;
        if (error.statusCode == 404 || error.statusCode == 405) {
          // A frozen backend cannot ever accept this bounded queue. Drop it so
          // every later foreground does not retry an endpoint known absent.
          await prefs.setString(storageKey, '[]');
        } else if (error.statusCode == 400) {
          // The server rejected this exact persisted leaf permanently (for
          // example it aged beyond the offline window). Drop only that leaf so
          // a malformed/stale head cannot strand newer valid sessions.
          final current = _readQueue(prefs)
            ..removeWhere((row) => row['sessionId'] == sessionId);
          await prefs.setString(storageKey, jsonEncode(current));
          continue;
        }
        return;
      } catch (_) {
        return;
      }
    }
  }

  Future<void> _clearQueue(int generation) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation != _accountGeneration) return;
      await prefs.setString(storageKey, '[]');
    } catch (_) {}
  }

  List<Map<String, String>> _readQueue(SharedPreferences prefs) {
    final raw = prefs.getString(storageKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final result = <Map<String, String>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final row = <String, String>{};
        for (final entry in item.entries) {
          if (entry.key is String && entry.value is String) {
            row[entry.key as String] = entry.value as String;
          }
        }
        result.add(row);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  String _newSessionId() {
    final suffix = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${_now().toUtc().microsecondsSinceEpoch}-$suffix';
  }
}
