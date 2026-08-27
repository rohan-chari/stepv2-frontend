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
  ActivationAnalyticsService({
    BackendApiService? backendApiService,
    bool? isIosForTesting,
  }) : _api = backendApiService ?? BackendApiService(),
       _isIos = isIosForTesting ?? Platform.isIOS;

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
    'next_race_cta_shown',
    'next_race_cta_tapped',
    'quick_create_selected',
    'quick_create_succeeded',
    'quick_create_failed',
    'open_race_discovery_shown',
    'open_race_join_succeeded',
    'race_share_prompt_shown',
    'race_share_completed',
    'quick_race_second_participant_joined',
    'quick_race_started',
    'invite_code_setup_shown',
    'invite_code_setup_dismissed',
    'invite_code_setup_applied',
    'settings_invite_code_opened',
    'home_suggested_races_shown',
    'home_suggested_race_tapped',
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
    // Extra-spin CTA funnel. Unknown names are deliberately dropped locally;
    // an older backend then soft-drops only these additive events per batch.
    'extra_spin_offer_shown',
    'extra_spin_cta_tapped',
    'extra_spin_ad_ready',
    'extra_spin_ad_not_ready',
    'extra_spin_ad_completed',
    'extra_spin_claim_succeeded',
    // Admin Metrics v2. Both names are iOS-only and additionally require the
    // exact contexts checked in record(); malformed additions are dropped
    // locally so one bad event can never poison the shared activation batch.
    'health_connected',
    'race_leaderboard_viewed',
    'interstitial_opportunity',
    'interstitial_skipped',
    'interstitial_show_attempted',
    'interstitial_load_succeeded',
    'interstitial_load_failed',
    'interstitial_dismissed',
    'interstitial_show_failed',
    'race_detail_visit_started',
    'race_detail_visit_ended',
    'race_detail_back_exit',
    'race_detail_exit_eligible',
  };

  static const allowedContext = <String, Set<String>>{
    'source': {
      'onboarding',
      'profile',
      'races',
      'empty_state',
      'share_link',
      'next_race',
      'healthkit',
    },
    'race_state': {'active', 'pending'},
    'result': {
      'granted',
      'denied',
      'dismissed',
      'unsupported',
      'failed',
      'load_failed',
      'completed',
      'empty',
      'abandoned',
      'back_exit',
      'forward_exit',
      'short_visit',
      'ineligible_race',
      'rewarded_shown',
    },
    'placement': {'race_detail_exit', 'race_results_exit'},
    'entry_surface': {'home', 'races', 'public_races', 'tournament'},
    'exit_kind': {'back', 'forward', 'state_change', 'auth_replace'},
    'scope_result': {'active_accepted', 'ineligible'},
    'dwell_bucket': {'under_5s', '5_9s', '10_59s', '60_179s', '180s_plus'},
    'reason': {
      'unauthenticated',
      'unconfigured',
      'excluded_flow',
      'recent_fullscreen',
      'invalid_timezone',
      'acquisition_grace',
      'session_grace',
      'permit_active',
      'session_cap',
      'cooldown',
      'daily_cap',
      'backend_unsupported',
      'backend_unavailable',
      'not_ready',
      'show_failed',
      'account_changed',
    },
    'mode': {'solo', 'team', 'tournament'},
    'surface': {'home', 'results'},
    'preset': {'2_day', '7_day'},
    'attributed': {'true', 'false'},
    'race_count': {'0', '1', '2', '3'},
    'featured_count': {'0', '1', '2'},
    'public_count': {'0', '1', '2', '3', '4'},
    'tournament_count': {'0', '1', '2', '3', '4'},
    'suggestion_kind': {'FEATURED_RACE', 'PUBLIC_RACE', 'TOURNAMENT'},
    'position': {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'},
    'error_code': {
      'INVALID_QUICK_CREATE_CONFIG',
      'QUICK_CREATE_DISABLED',
      'QUICK_RACE_ALREADY_LIVE',
      'QUICK_RACE_MEMBERSHIP_LIMIT',
      'UNKNOWN',
    },
    // Tutorial per-step drop-off (spec §5.11.8). Headroom to 10 so trimming or
    // extending the step list again needs no coordinated backend change — the
    // backend allowlist was widened to the same range.
    'step': {'1', '2', '3', '4', '5', '6', '7', '8', '9', '10'},
  };

  final BackendApiService _api;
  final bool _isIos;
  static Future<void>? _recordInFlight;
  Future<void>? _flushInFlight;
  String? _activeUserId;
  int _accountGeneration = 0;

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
    String? ownerUserId,
    Map<String, String> context = const {},
  }) {
    final capturedContext = Map<String, String>.unmodifiable(context);
    Future<void> run() => _record(
      name,
      sessionId: sessionId,
      ownerUserId: ownerUserId,
      context: capturedContext,
    );
    final active = _recordInFlight;
    final operation = active == null
        ? run()
        : active.catchError((_) {}).then((_) => run());
    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_recordInFlight, tracked)) _recordInFlight = null;
    });
    _recordInFlight = tracked;
    return tracked;
  }

  Future<void> _record(
    String name, {
    required String? sessionId,
    required String? ownerUserId,
    required Map<String, String> context,
  }) async {
    if (!allowedEventNames.contains(name)) return;
    if (name == 'health_connected') {
      if (!_isIos ||
          ownerUserId == null ||
          ownerUserId.isEmpty ||
          context.length != 1 ||
          context['source'] != 'healthkit') {
        return;
      }
    }
    if (name == 'race_leaderboard_viewed') {
      final raceId = context['race_id'];
      if (!_isIos ||
          ownerUserId == null ||
          ownerUserId.isEmpty ||
          context.length != 1 ||
          raceId == null ||
          !RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
          ).hasMatch(raceId)) {
        return;
      }
    }
    if (ownerUserId != null &&
        ownerUserId.isNotEmpty &&
        _activeUserId != ownerUserId) {
      _activeUserId = ownerUserId;
      _accountGeneration++;
    }
    final safeContext = <String, String>{};
    for (final entry in context.entries) {
      final isUuidKey =
          entry.key == 'race_id' ||
          entry.key == 'source_race_id' ||
          entry.key == 'suggestion_id';
      final isSafeUuid =
          isUuidKey &&
          RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
          ).hasMatch(entry.value);
      if (allowedContext[entry.key]?.contains(entry.value) == true ||
          isSafeUuid) {
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
      'platform': _isIos
          ? 'ios'
          : Platform.isAndroid
          ? 'android'
          : 'other',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (ownerUserId != null && ownerUserId.isNotEmpty)
        'ownerUserId': ownerUserId,
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

  Future<void> flush(String? authToken, {String? userId}) async {
    if (authToken == null || authToken.isEmpty) return;
    if (userId != null && userId.isNotEmpty) {
      if (_activeUserId != null && _activeUserId != userId) return;
      if (_activeUserId == null) {
        _activeUserId = userId;
        _accountGeneration++;
      }
    }
    final running = _flushInFlight;
    if (running != null) {
      await running;
      return flush(authToken, userId: userId);
    }
    final generation = _accountGeneration;
    late final Future<void> tracked;
    tracked = _flush(authToken, userId: userId, generation: generation)
        .whenComplete(() {
          if (identical(_flushInFlight, tracked)) _flushInFlight = null;
        });
    _flushInFlight = tracked;
    await tracked;
  }

  Future<void> _flush(
    String authToken, {
    required String? userId,
    required int generation,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (generation != _accountGeneration) return;
    final queue = _readQueue(prefs);
    if (queue.isEmpty) return;
    if (userId != null && userId.isNotEmpty) {
      queue.removeWhere((event) {
        final owner = event['ownerUserId'];
        return owner is String && owner.isNotEmpty && owner != userId;
      });
      if (generation != _accountGeneration) return;
      await _writeQueue(prefs, queue);
    }
    final eligible = queue.where((event) {
      final owner = event['ownerUserId'];
      return owner == null || owner == userId;
    }).toList();
    if (eligible.isEmpty) return;
    final wireEvents = eligible
        .map((event) => Map<String, dynamic>.from(event)..remove('ownerUserId'))
        .toList();
    try {
      await _api.sendActivationEvents(
        identityToken: authToken,
        events: wireEvents,
      );
      if (generation != _accountGeneration) return;
      // Only remove the exact batch sent. Events recorded during the request
      // remain queued for the next best-effort flush.
      final sentIds = eligible.map((e) => e['id']).toSet();
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
