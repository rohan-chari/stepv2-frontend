import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_api_service.dart';

/// Privacy-bounded activation telemetry. No caller-provided strings are sent:
/// event names and context values must both come from the allowlists below.
class ActivationAnalyticsService {
  ActivationAnalyticsService({BackendApiService? backendApiService})
    : _api = backendApiService ?? BackendApiService();

  static const _storageKey = 'activation_events_v1';
  static const maxQueuedEvents = 50;

  static const allowedEventNames = <String>{
    'onboarding_started',
    'referral_continued',
    'health_cta_tapped',
    'daily_intro_viewed',
    'daily_opened',
    'starter_reward_claimed',
    'alert_card_enabled',
    'alert_card_dismissed',
    'tutorial_opened',
    'tutorial_completed',
    'tutorial_skipped',
    'public_browser_opened',
    'public_join_attempted',
    'public_join_succeeded',
    'public_join_failed',
    'race_creation_opened',
    'race_creation_succeeded',
    'invite_flow_opened',
    'invite_flow_sent',
    'race_started',
  };

  static const allowedContext = <String, Set<String>>{
    'source': {'onboarding', 'profile', 'races', 'empty_state', 'share_link'},
    'race_state': {'active', 'pending'},
    'result': {'granted', 'denied', 'dismissed', 'unsupported', 'failed'},
    'mode': {'solo', 'team', 'tournament'},
  };

  final BackendApiService _api;
  Future<void>? _flushInFlight;

  Future<void> record(
    String name, {
    String? sessionId,
    Map<String, String> context = const {},
  }) async {
    if (!allowedEventNames.contains(name)) return;
    final safeContext = <String, String>{};
    for (final entry in context.entries) {
      if (allowedContext[entry.key]?.contains(entry.value) == true) {
        safeContext[entry.key] = entry.value;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final queue = _readQueue(prefs);
    String version = 'unknown';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    queue.add({
      'id': _newId(),
      if (sessionId != null && sessionId.isNotEmpty)
        'onboardingSessionId': sessionId,
      'name': name,
      'context': safeContext,
      'appVersion': version.isEmpty ? 'unknown' : version,
      'platform': Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
          ? 'android'
          : 'other',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    if (queue.length > maxQueuedEvents) {
      queue.removeRange(0, queue.length - maxQueuedEvents);
    }
    await _writeQueue(prefs, queue);
  }

  Future<void> flush(String? authToken) {
    if (authToken == null || authToken.isEmpty) return Future.value();
    return _flushInFlight ??= _flush(authToken).whenComplete(() {
      _flushInFlight = null;
    });
  }

  Future<void> _flush(String authToken) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _readQueue(prefs);
    if (queue.isEmpty) return;
    try {
      await _api.sendActivationEvents(identityToken: authToken, events: queue);
      // Only remove the exact batch sent. Events recorded during the request
      // remain queued for the next best-effort flush.
      final sentIds = queue.map((e) => e['id']).toSet();
      final current = _readQueue(prefs)
        ..removeWhere((event) => sentIds.contains(event['id']));
      await _writeQueue(prefs, current);
    } catch (_) {
      // Offline, old backend (404), or server failure: retain bounded queue.
    }
  }

  List<Map<String, dynamic>> _readQueue(SharedPreferences prefs) {
    final raw = prefs.getString(_storageKey);
    if (raw == null) return [];
    try {
      final value = jsonDecode(raw);
      if (value is! List) return [];
      return value
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeQueue(
    SharedPreferences prefs,
    List<Map<String, dynamic>> queue,
  ) => prefs.setString(_storageKey, jsonEncode(queue));

  String _newId() {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }
}
