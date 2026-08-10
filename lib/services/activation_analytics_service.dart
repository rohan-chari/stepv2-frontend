import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_api_service.dart';
import 'onboarding_state_service.dart';

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
    // Onboarding revamp (spec §5.9). The client drops unknown names locally, so
    // these must be listed here or the events never leave the device. The
    // backend soft-drops names it doesn't know (§6.4), so a newer client
    // against an older backend loses only the new events, not the whole batch.
    'health_result',
    'health_escaped',
    'health_probe_inconclusive',
    'health_recovered',
    'notif_prompt_shown',
    'notif_result',
    'inviter_race_shown',
    'home_reached',
    // Demo-race tutorial (spec §5.9 / §6.3). The three actions that are the
    // point of the exercise. Widening an allowlist can only increase what is
    // accepted, so no shipped client is affected; and because the backend
    // soft-drops names it doesn't know, a newer app against an older backend
    // loses only these three — the reused tutorial_* funnel still works.
    'demo_box_opened',
    'demo_powerup_used',
    'demo_won',
    // Onboarding invite-code step.
    'invite_code_step_shown',
    'invite_code_applied',
    'invite_code_skipped',
    // Install-attribution funnel (part C). The stage outcome is encoded in the
    // NAME rather than in a context key on purpose: the backend soft-drops an
    // unknown name per event, but an unknown context key 400s the ENTIRE batch
    // — and this client retains failed batches, so one bad event would poison
    // every later flush until it rolled off the 50-event queue.
    'install_attr_deep_link',
    'install_attr_detect_miss',
    'install_attr_read_denied',
    'install_attr_read_no_code',
    'install_attr_code_captured',
    'install_attr_install_referrer',
    'install_attr_error',
  };

  static const allowedContext = <String, Set<String>>{
    'source': {'onboarding', 'profile', 'races', 'empty_state', 'share_link'},
    'race_state': {'active', 'pending'},
    'result': {'granted', 'denied', 'dismissed', 'unsupported', 'failed'},
    'mode': {'solo', 'team', 'tournament'},
    // Tutorial per-step drop-off (spec §5.11.8). Headroom to 10 so trimming or
    // extending the step list again needs no coordinated backend change — the
    // backend allowlist was widened to the same range.
    'step': {'1', '2', '3', '4', '5', '6', '7', '8', '9', '10'},
  };

  final BackendApiService _api;
  Future<void>? _flushInFlight;

  /// Opens a new onboarding run. Recording this event ALWAYS mints a fresh
  /// correlation id, so the id a run uses is by construction the id its
  /// `onboarding_started` carries — which is exactly what the backend's funnel
  /// anchor requires. Adding a second name here would break that guarantee.
  static const _runStartEvent = 'onboarding_started';

  /// Closes the run. Recorded under the run's id, after which the id is
  /// dropped: everything that happens later — most importantly a
  /// settings-tutorial replay months on — starts a fresh, unanchored id and is
  /// therefore never counted inside the onboarding funnel.
  static const _runEndEvent = 'home_reached';

  /// The funnel correlation id, scoped to one onboarding **run**.
  ///
  /// It used to be minted once per install and reused forever, which made it
  /// an install id wearing a session id's name: a replay of the settings
  /// tutorial carried the original onboarding id and was counted inside the
  /// onboarding funnel. A run now starts at [_runStartEvent] and ends at
  /// [_runEndEvent]; the key is also cleared on sign-out with the rest of the
  /// device-scoped onboarding state, so a second account is a second run.
  ///
  /// Events recorded outside a run still get an id (so they correlate with
  /// each other), it simply is not an anchored one.
  Future<String> _sessionIdFor(SharedPreferences prefs, String name) async {
    if (name != _runStartEvent) {
      final existing = prefs.getString(
        OnboardingStateService.keyOnboardingSessionId,
      );
      if (existing != null && existing.isNotEmpty) return existing;
    }
    final minted = _newId();
    await prefs.setString(
      OnboardingStateService.keyOnboardingSessionId,
      minted,
    );
    return minted;
  }

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
    // Callers no longer have to thread the session id through; an explicit
    // [sessionId] still wins so a caller can correlate a different session.
    final callerSuppliedSession = sessionId != null && sessionId.isNotEmpty;
    final resolvedSessionId = callerSuppliedSession
        ? sessionId
        : await _sessionIdFor(prefs, name);
    final queue = _readQueue(prefs);
    String version = 'unknown';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    queue.add({
      'id': _newId(),
      'onboardingSessionId': resolvedSessionId,
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

    // Close the run only after the terminal event is safely queued under its
    // id. A caller correlating some other session must not end ours.
    if (!callerSuppliedSession && name == _runEndEvent) {
      await prefs.remove(OnboardingStateService.keyOnboardingSessionId);
    }
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
